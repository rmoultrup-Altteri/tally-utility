# Handoff: v5.4.2-18 (backbilling on the rule-terms convention) is MIRRORED; next is the -15 rewrite

**Generated**: 2026-10-11
**Branch**: `main`, pushed, working tree clean (last commit `9761827`, the mirror; `5f26697` is the r6 work). gas-billing-memory was not fetched this session; fetch both before orienting.
**Status**: Ready for next patch. v5.4.2-18 is landed. Patch `sql/v5.4.2-18-backbilling-rule-terms.sql` is the r6 freeze (md5 `baa6e72a0555c344473eb3b099c44fca`, 895 lines; battery `7adbcf318e773009fbcfb15c2fbb269f`, 108 PASS; 107/107 mutations). `sql/tu.sql` is 31,380 lines, md5 `b35302dcc0979c29b2c693dc569838c7`. `tally-pg` runs the new build (fresh volume, zero init errors). Catalog: 117 tables / 497 CHECKs / 349 triggers / 487 functions / 665 indexes. Verification: `sql/DEPLOY-VERIFICATION.md` (the -18 entry). `tests/ci.sh` passes in full; `PENDING` is empty.

## Goal
Move the platform's law tables onto the rule-terms convention (-17), one area at a time. Done: backbilling (-18). Next: deposits (-15).

## Completed (this session)
- [x] Resumed from a stale HANDOFF; "A" (the user's reply) = **delegation** for the eight unprotected Texas backbilling rows (R10); already built in r4.
- [x] Codex's r4 review ("not yet") reproduced on a clone, then fixed in r5: priority above 8 aborted adoption (schema cap removed, later capped at 2147483647); a repeated legacy outcome aborted adoption (outcomes are a set in the builder, the adoption check and the twin comparison); a delegation's distinct anchor was cleared unseen (a pre-flight in the migration compares it with its protected twin, same cause, overlapping dates).
- [x] Codex's r5 should-fix reproduced (probe 06, then test P11) and fixed in r6: `LOCK TABLE backbilling_rules IN ACCESS EXCLUSIVE MODE` first in the migration.
- [x] All three reviewers (Opus, Fable, Codex) **ready** on r6. Mirrored on Ryan's approval ("Mirror r6, mirror as is on the lock").
- [x] Tests: `migration-18.py` P8-P11 (P11 = a real second session, synchronised by polling `pg_stat_activity`, not sleeps), cleanup via `atexit`; battery D40/D40b/D40c; mutations M66, M97, M102-M108.
- [x] `tests/v5.4.2-14/parity/catalog-identity.sql`: removed the row count of the dropped window-terms table.

## Not Yet Done
- [ ] **The -15 rewrite** (deposits) on the template: drop or justify its class-scoped rate (R10 of -17 -- not to be confused with -18's R10); city classes (R16). Its triggers are `a_...` too.
- [ ] **The backbilling tariff table**: until it exists, a billing case for the unprotected class is refused (unknown law is not permission).
- [ ] Bump the GitHub Actions versions (`checkout@v4`, `setup-python@v5` warn about Node 20).
- [ ] Optional, noted by reviewers: a re-run of -18 takes the exclusive lock before finding nothing to do (accepted by Ryan 2026-10-10; fix = check registration before locking, or `SET LOCAL lock_timeout`); `assert_rule_read_committed` beside the lock; `migration-18.py` drops go through `sh()` and ignore failures.

## Failed Approaches (Don't Repeat These)
- **P11 synchronised by `time.sleep(2)` / `pg_sleep(6)`** -> if the writer is slow to start the migration locks first and P11a fails on a correct patch; if the pre-flight is slow M107 is "caught" for the wrong reason -> poll `pg_stat_activity` for the writer's active `pg_sleep` and for the migration's `wait_event_type = 'Lock'`.
- **`writer.communicate()` after closing `writer.stdin`** -> `ValueError: I/O operation on closed file`, which skipped the cleanup and left ~240 `m18_*` databases -> `writer.wait()` and read `writer.stderr`; cleanup is now `atexit`.
- **D40b inserting a protected `crossed_meters` row from 2020-01-01** -> `pg_temp.does` keeps what it inserts, so X13 later hit `backbilling_rules_rule_no_overlap` -> give it its own dates (1800-1801).
- **Fixtures inserting window terms in a separate statement** -> `-13`'s "window terms were written with it" guard -> insert the rule and its terms in one `BEGIN; ... COMMIT;`.
- **Mirror body from line 91** -> two blank lines after the banner, unlike -17's one -> `git checkout sql/tu.sql` and redo from line 92 (the `-- ----` rule).
- **Running the identity script with the window-terms row count after the rebuild** -> `relation "public.backbilling_rule_window_terms" does not exist` -> line removed (the saved stdout never included it, so parity held).

## Key Decisions
| Decision | Rationale |
|----------|-----------|
| Unprotected rows are delegations, not "law, uncapped" (R10, Ryan "A") | 7.45 not reaching a class means the tariff decides, not that the law permits unlimited backbilling; unknown law is never permission. |
| Priority: any integer 1..2147483647 | -13 allowed any positive integer; the rank is only an order; the bound matches the old integer column and a C# `int`. |
| Outcomes are a set | -13's CHECK allowed `['fast','fast']`; the schema requires unique items; the set is lossless. |
| A delegation's anchor is checked against its twin in the migration, not the adoption check | The fill clears it before the adoption check runs. |
| Lock first, as is (Ryan) | Closes the pre-flight/fill race; re-run cost accepted, nothing is live. |

## Current State
**Working**: everything above; the build passes `tests/ci.sh`.
**Broken**: nothing known. `migration-18.py` and `mutations-18.py` cannot run on `tally` now (post-18).
**Uncommitted changes**: None.

## Resume Instructions
1. Fetch both repos:
   ```
   cd ~/code/tally-utility && git pull --ff-only
   cd ~/code/gas-billing-memory && git fetch && git log --oneline HEAD..origin/main
   ```
   (Kyle pushes rulings to gas-billing-memory main directly.) Remote had two `ui-concepts/` commits this session; they never touch `sql/` or `tests/`.
2. Ask Ryan which comes first (-15 rewrite or the backbilling tariff table), then follow the per-patch loop below.
3. Per patch: test first; fail-first runner (`tests/v5.4.2-17/fail-first.py <db> [block]`); a mutation per clause; three reviewers (Opus and Fable as background `general-purpose` agents with their own database prefixes; Codex via `codex exec -s workspace-write -o <out>.md - < prompt` under nvm v24.15.0, then I run its probes); freeze the patch and battery (copy to `tests/v5.4.2-NN/review/*-frozen-rN.sql`, write the hash in every brief) before reviews; mirror only on Ryan's approval. Mirror recipe: the -18 entry in `sql/DEPLOY-VERIFICATION.md` (banner + body from the first `-- ----` rule, `cmp` the body, `git diff` shows 0 deletions, `docker rm -fv tally-pg`, build, wait for "PostgreSQL init process complete", identity md5 against a patched clone, re-apply twice, `tests/ci.sh`).
4. To rerun -18's migration tests or mutations, build a pre-18 base first (a database from the -17 `tu.sql`); `tally` is post-18.

## Warnings
- **`tu.sql` is append-only.** Mirror only after Ryan approves.
- **Revoke TEMP after every `CREATE DATABASE ... TEMPLATE`** (the helper scripts do; `assert_core_role_invariants()` checks it).
- **Freeze the hash before any review; one revision per round.** Do not edit the repo patch while reviewers run (they use the frozen copy, but they diff against the repo).
- **Waiting on a background run:** never `pgrep -f` the script's own name inside a Monitor; poll its log file.
- **A reviewer's finding is usually right, the proposed fix often is not:** reproduce on a clone before folding. Codex cannot reach Docker; it writes probe `.sql` files and I run them.
- **Rebuilding `tally-pg` destroys every scratch clone**, including a reviewer's; rebuild only when no reviewer is running.
- **Never `git add -A` in gas-billing-memory.** Explain choices to Ryan in prose; ask only on rule conflicts. Commits go to main in tally-utility.
