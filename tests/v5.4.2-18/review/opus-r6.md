# v5.4.2-18 review round 6 (delta) — Opus

Both hashes match: patch r6 is `baa6e72a…` (895 lines, the same as `sql/v5.4.2-18-…` in the repo) and battery r6 is `7adbcf31…` (the same as the repo battery). `diff r5 r6` is exactly what the brief lists: the LOCK, the cap, the HINT and the comment. The battery diff adds D40c only.

## Runs
- **Strict apply** (`search_path=''`, `check_function_bodies=on`) on a fresh clone of `tally`: OK, 16 rows. Re-applying it to the migrated clone is a no-op ("already on the rule-terms convention") and exits 0.
- **Frozen battery, run by hand:** exit 0, 108 PASS. D40 and D40c pass, and D40b succeeds.
- **`PATCH18=<frozen r6> migration-18.py`:** all pass, including P11a/b. I ran it once on the version that was in the repo at freeze time (sleep-based P11), and again on the version that replaced it at 22:46:35, after the freeze. In the new version P11 waits on `pg_stat_activity` and adds a P11-setup check.
- **M107 by hand** (the frozen r6 patch with the LOCK line removed), run on the current migration-18: P11-setup passes and P11a fails. Without the lock, the patch aborts late at the fingerprint ("adoption moved a row's identity…"), so the mutation is caught. The mutant still aborts, which confirms that the lock improves the diagnosis; it does not close a hole that let a wrong document in.

## What the lock could break: checked, nothing blocking
- **Idempotent re-run:** still a no-op (the lock is taken, then the registration check returns).
- **Two patches applied at once** on a pre-18 clone: one succeeds. The other fails in section 1 with a duplicate `pg_proc` entry from the concurrent `CREATE OR REPLACE FUNCTION`, which is harmless and has nothing to do with the lock. If they were staggered past section 1, the lock-first order would make the second a clean no-op rather than an ALTER error.
- **Deadlock:** I listed every lock the patch transaction holds (via `pg_locks`, before ROLLBACK):
  - AccessExclusive on `backbilling_rules`, the child table, the two vocabularies and the no-overlap index.
  - ShareRowExclusive on `rule_term_schemas`.
  - ShareUpdateExclusive (from the COMMENTs) on `meter_correction_cases`, `correction_run_targets`, `meter_correction_period_evidence` and `backbilling_anchor_bases`.
  - Exclusive advisory locks on the 16 row keys, plus one shared schema-version key.

  A citing or tenant writer takes RowExclusive on the correction tables, then RowShare or AccessShare on `backbilling_rules` (through the FK). RowExclusive does not conflict with ShareUpdateExclusive, and before -18 nobody takes the backbilling row-key advisory locks (`rule_row_cite` needs the table to be registered). So there is no wait cycle. Taking AccessExclusive first also removes r5's AccessShare→AccessExclusive upgrade (pre-flight, then ALTER), which was the classic two-upgrader deadlock. That makes the lock strictly better.
- **Isolation:** the lock's claim ("waited for and seen by the pre-flight") holds only under READ COMMITTED. Under `default_transaction_isolation=repeatable read`, the snapshot is taken by section 1's DDL, before the LOCK. That is still safe: the patch aborts at the fill, where -17's `assert_rule_read_committed` raises ("adopting a row … runs only under READ COMMITTED"), and nothing is adopted (I reproduced this).
- **Privileges:** the owner can LOCK, and the ALTERs need ownership anyway.

## The cap: checked, nothing broken
`rule_terms_errors` on the registered schema gives these results:

| value | result |
|---|---|
| 2147483647 | accepted |
| 2147483648 | refused, "must be at most 2147483647" |
| 1e30 | refused, same message |
| 99999999999999999999999 | refused, same message |
| 2147483647.0 | refused by -17's canonical-number rule |
| -1 | refused by the minimum |
| 1e9 | accepted (jsonb stores it as 1000000000, so the duplicate-priority text grouping is unaffected) |

A legacy priority can't exceed it, because -13 stored priority as an int4 column with only `> 0` checked (sql/v5.4.2-13 lines 780 and 797). B1 stays fixed (D40b). The law file `law/backbilling/backbilling.v1.schema.json` equals the registered schema as JSON. M66 (re-pointed to P8a) and M108 (D40c) are each caught.

## Verdict: READY (R10 is still Ryan's)

## Should-fix (non-blocking)
1. **migration-18.py was edited after the freeze, and an intermediate version crashed.** The freeze was at 22:42. The file changed at 22:45:57 and again at 22:46:35. The 22:45:57 version closed the writer's stdin and then called `writer.communicate()`, which raises `ValueError: I/O operation on closed file` on Python 3.9. That skipped the cleanup loop and leaked `m18_*_<pid>` databases, one set per run, including the mutation runner's runs (mut-r6.log shows "M107 MISSED … ValueError"). The 22:46:35 version (md5 `b53517d9…`) fixes it, and I verified it: r6 passes and M107 is caught. Freeze or hash migration-18.py with the patch and battery, so reviewers know which P11 they ran. About 240 `m18_*` databases are on the server, many left by the crashed runs. I dropped the one set my crashed run leaked (`_71856`); the rest are the author's.
2. **The cleanup should not depend on reaching the end of the script.** Wrap the body in try/finally, or use `atexit`, so that any exception still drops `m18_a`–`m18_j`.

## Notes
3. **A re-run now waits for every open reader.** On an already-migrated database, the re-run takes AccessExclusive before it finds out it has nothing to do. In r5 it never locked the table. I reproduced this: with a session holding a read on `backbilling_rules`, the no-op re-run waited about 5 s, and every new reader queues behind it while it waits. This is harmless in CI. On a live database it is an unexpected outage window. Two options, both cheap:
   - Check registration before the lock, and again after it.
   - Add `SET LOCAL lock_timeout = '5s'` to the patch, so a stuck reader fails the patch instead of stalling every rule lookup.
4. **Say "READ COMMITTED" next to the lock.** One `PERFORM public.assert_rule_read_committed('adopting backbilling_rules')` beside the LOCK would make the lock's guarantee self-contained, and would refuse other isolation levels at the top instead of at the fill.
5. **The new HINT wording is right.** It now covers the case of a delegation overlapping twins with different anchors (my r5 note 3). The comment at line 246 now points to the pre-flight (my r5 note 4).

## Clean-up
I dropped `opus18r6` and `opus18pre`, and the leaked `m18_*_71856` set. My two complete migration-18 runs cleaned up after themselves. I touched no repo file except this report.
