# Review brief: v5.4.2-23 r5 — cash: round 4's findings, the take-back split, the reissue's remainder

**Date:** 2026-10-28. **Kind:** patch review, round 5.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's round-5 files. You may read every earlier review in this folder (`*-r1.md` to `*-r4.md`, `codex-r*-probes/`): r5 answers round 4.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-23/review/patch-23-frozen-r5.sql` | `3e29cdb7900ee02fdf4109e29f098849` |
| `tests/v5.4.2-23/review/battery-23-frozen-r5.sql` | `8d6f85a3a4c1f4faaf1e6ec8a30fa7ee` |
| `tests/v5.4.2-23/review/cash-23-frozen-r5.sh` | `09a1a2f432f8f12fddd188ccd2c864e4` |
| `tests/v5.4.2-23/review/mutations-23-frozen-r5.py` | `97ed11196a45bc8e3bf7f0c87dc1d741` |
| `tests/v5.4.2-23/review/older-tests-23-frozen-r5.diff` | `be99c2f963ab9f2177c9f059a4de7e5c` |
| `tests/v5.4.2-23/review/patch-23-r4-to-r5.diff` | `1b6bdb48dd8b381b7c32d0e7af0633e7` |

Today the live copies are identical to the frozen ones. Review the frozen copies. `older-tests-23-frozen-r5.diff` is every change -23 made to earlier tests, against the -22 mirror commit `eef5122` (unchanged since r3: r4 and r5 add none). `patch-23-r4-to-r5.diff` is for orientation; review the whole patch.

## What changed since round 4

All three reviewers said "not yet". `application/wave2-build-2026-10-15/v5.4.2-23-r5-plan.md` is the merged list, with an "As built" section at its end. `application/DECISION-LOG.md` (2026-10-28, r5) gives the calls and the reasons. No new ruling; one fix differs from the plan:
- **B2 as built is not the plan's "up to the credit's amount".** That rule fails Opus's executed P2: a credit that had refunded its 20 would carry a later 10 take-back as a deficit, and the payment could still pay out 40 (60 out of 50). Kyle's K-10 refund cap allows 30, so K-10 decides.

In short:
1. **One split of a take-back** between a payment and its overpayment credit (`overpayment_split`), read by both positions, both caps and the escheat check. The split works row by row in recorded order:
   - A take-back comes first out of what the credit still held at its instant (`cash_drawn_at`), then out of the payment's own part.
   - What neither held falls on the credit up to its amount, then on the payment.
   - A take-back recorded before the credit is the payment's.
   - A give-back goes to the credit first.
   - Rows of one transaction share an instant, and the split reads them as if the take-back came last (R17).
   - A draw on either the payment or its credit is also capped by the two together (the payment less what was taken back, from the row's date on).
   - A draw on the credit takes the payment's lock first. That made the bounce's credit lock redundant: it is removed, and N145 is retired.
2. **Nothing more goes under a refund's posting row** once the refund is nsf or reversed, under the refund's lock.
3. **No give-back under a payment whose overpayment credit is escheated.**
4. **A reissue carries what is left on the credit, at most the refund**, dated on or after the refund's return. The commit check requires nothing *positive* left; where the payment also bounced, nothing may be carried (K-10).
5. **No status time in the future or infinite**, for any role: at a move, on a later correction, and at birth.
6. **Arrival rows and donations at READ COMMITTED**: one pin at the top of `enforce_ledger_reversal`, which replaces the reversal path's.

## Drafting calls to check in particular

- **The split.**
  - Do both positions, both caps and the escheat check read it the same way?
  - Does each position's remainder equal what its cap admits, and do the two add up to the ledger?
  - Kyle's example through the credit, in full and in part (V1, V2): unchanged?
  - A deficit: does it ever sit on one side while the other still has money to give?
- **The cap on the two together.** Is it ever stricter than K-10 allows (a legitimate draw refused because of an older deficit), or ever missing?
- **Rows of one instant (R17).** Is the cap on the two together enough to keep K-10 for every reading of one transaction?
- **`cash_drawn_at`'s as-of reading** (statuses at an instant, by `status_recorded_at`). Can a history load or a later move rewrite an earlier split?
- **The refund-tree guard.** Every row under a refund's posting row, either sign, after nsf or reversed. Anything legitimate refused?
- **The reissue's remainder rule** against Ryan's option 1 and K-10.
- **The lock order.** Payment, then its credit, for a credit draw; tree, then refund, under a refund's row. Any cycle?

## Results so far (reproduce them)

- **Strict apply, twice:** as before.
- **`tests/ci.sh`:** passes in full with -23, -25 and -26 pending (49 steps).
- **`battery-23.sql`:** 293 checks. The W section is new. The W checks written first failed against r4: `tests/v5.4.2-23/red-r5-against-r4.txt`. W2e/W2f, W10e, W11 and W12 were added with the build (the r5 plan's "As built"). V7i now meets the reissue's remainder rule before the cap.
- **`races/cash-23.sh`:** CR1–CR22, 33 results. New:
  - CR20 and CR20b: an arrival row at REPEATABLE READ after a void.
  - CR21: a row under a refund's return while it moves to nsf.
  - CR22: a credit draw waits on its payment's lock.
- **`mutations-23.py`:** 190 of 190 caught, each at its named check as the first failure. N171–N191 are new; N145 is retired. N06, N87, N105, N147, N148, N150, N152 and N154 have new anchors or owners.

## What to answer

1. **Does r5 close each round-4 finding it claims to close?** Item by item, for all three reviews.
2. **Does r5 apply the rulings faithfully** (K-10, Ryan's status and reissue decisions), and is the B2 refinement right under K-10?
3. **Did r5 open anything new?** A guard refusing a legitimate act; a lock-order cycle; a moved check; a role or superuser path.
4. **Is there still a path around any rule?** Every role, isolation level and statement shape.
5. **Concurrency.** Every cap behind its lock; every money-freeing move taking the lock the next draw waits on.
6. **The invariants and the tests.** Any claim narrower than its check; any mutation passing for the wrong reason; anything missing.
7. **Residuals R1–R17.** Is any of them blocking?

## How to probe

**Opus and Fable** may query the running `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv23opus`, Fable `rv23fable`):
1. `CREATE DATABASE <name> TEMPLATE tally`.
2. Revoke TEMP on the clone from PUBLIC, `tally_app` and `tally_core` right after creating it.
3. `docker cp` the frozen patch into the container and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

-25 and -26 are not needed for this review.

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim must be a probe file in `tests/v5.4.2-23/review/codex-r5-probes/`. Each probe runs as the owner on a fresh clone with frozen r5 applied, ends in ROLLBACK, and prints SQLSTATE and message for each caught error with RAISE NOTICE. The author will run the probes.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role.
- Do not run `mutations-23.py`; it uses the fixed name `m23`.
- Run `cash-23.sh` only against your own clone; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.

## Output

Write your full review to `tests/v5.4.2-23/review/<reviewer>-r5.md` (`opus`, `fable` or `codex`). It should contain:
- a verdict: "ready" or "not yet";
- the round-4 findings, each marked closed, partly closed or not closed;
- blocking items (B1…), each with the concrete path or repro;
- should-fix items (S1…);
- notes (N1…).

Mark each claim as **executed** or **predicted**. Your final message, under 2 KB, gives the verdict, the blocking items in one line each, and the file path. If you cannot write the file, send the review to main as several messages, each under 3 KB.
