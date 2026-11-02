# Review brief: v5.4.2-23 r7 — cash: round 6's findings (credits cover each other's shortfall, escheat on the credit's own money, reissue depth bounded)

**Date:** 2026-11-01. **Kind:** patch review, round 7.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's round-7 files. You may read every earlier review in this folder (`*-r1.md` to `*-r6.md`, `codex-r*-probes/`): r7 answers round 6.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-23/review/patch-23-frozen-r7.sql` | `9bbaab8a2f23634ad617c5bb12cb196a` |
| `tests/v5.4.2-23/review/battery-23-frozen-r7.sql` | `e43f0c34c7930d62ee4d3c8959ec0f10` |
| `tests/v5.4.2-23/review/cash-23-frozen-r7.sh` | `90d6d81e656a1c47971f8837c1edfb0e` |
| `tests/v5.4.2-23/review/mutations-23-frozen-r7.py` | `8f699ac28b9f3c4d024067ff372e585d` |
| `tests/v5.4.2-23/review/older-tests-23-frozen-r5.diff` | `be99c2f963ab9f2177c9f059a4de7e5c` |
| `tests/v5.4.2-23/review/patch-23-r6-to-r7.diff` | `3b96c94570aa33ddc0062e1cfd8468e0` |

Today the live copies are identical to the frozen ones. Review the frozen copies. `older-tests-23-frozen-r5.diff` is still every change -23 makes to earlier tests (r7 adds none; nothing outside -23's own files has changed since r6). `patch-23-r6-to-r7.diff` is for orientation; review the whole patch.

## What changed since round 6

All three reviewers said "not yet". The merged list is `application/wave2-build-2026-10-15/v5.4.2-23-r7-plan.md`, with "Answered" and "As built" sections at its end. The calls and their reasons are in `application/DECISION-LOG.md` (2026-10-29 -23 r7, and 2026-11-01 -23 r7).

**New ruling:** Kyle, 2026-10-30, `gas-billing-memory/application/kyle-decisions-2026-10-30-credit-shortfall-after-bounce.md`. A customer's credits are one pot, shown as one net balance; a bounce's shortfall uses up the total credit and the customer owes the rest; the order among the pieces underneath is ours.

1. **Credits cover each other's shortfall** (B1). In `overpayment_absorbed_as_of`, a credit in deficit (the overpayment credit first, then each reissue in recorded order) is covered first by the family's other credits holding money, the latest first, then by the payment. The caps are unchanged.
2. **Escheat on the credit's own money** (B2). A credit is escheated only when its own side, without the cover, holds nothing positive either. agree() now checks escheated credits too.
3. **A reissue carrying a share of a take-back is not voided** (B3). This differs from the plan, which passed the share back to the credit it came from. Once the share is given back, the void is admitted.
4. **Reissue lines are at most 999 deep** (B4). One bound, `reissue_line_bound()`, read by `reissue_generation`, `overpayment_root`, `overpayment_family` and the reissue's make. A deeper make is refused, and every walk raises 22000 rather than returning NULL.
5. **A reissue's void takes its payment's lock first** (S1): payment, then K, then R, the order every other family writer keeps. Race CR25.
6. **Should-fix items:** S2 the stale comments; S3 the new test shapes; S4 the mutation runner's APPLY branch matches the first diagnostic, `overpayment_shares` is in the walk-plan list, and the counts are corrected.
7. **The shares are read once per reading** in `overpayment_absorbed_as_of`, not once per family credit. Codex's 1,000-reissue probe ran for over 50 minutes on r6.

## Known limits (accepted; listed so you can judge them, not as findings to rediscover)

- **R22. A reissue carrying a take-back's share cannot be voided** until the share is given back (Ryan, 2026-10-29). A reissue made by mistake after a take-back stays on that line, still the customer's money, until it is refunded or applied. *Why:* passing the share on at the void's instant would mean re-splitting the shares, row by row of the take-back, through every reader and cap.
- **R23. The cover nets within one payment only** (Kyle, 2026-10-30; Ryan, 2026-11-01). Kyle's pot spans all of the customer's payments. Across payments, a credit still reads as refundable, and runs its own escheat clock, while another payment's bounce leaves the customer owing. The core nets the pot before a refund or an escheat report (`application/APPLICATION-CONTRACTS.md` AC-44). A database cap across the customer's payments can be added later as a tightening. Say if you think this is wrong for the escheat report in particular.

## Drafting calls to check in particular

- **The cover within the family.** After the sibling pass, do the family's credits read all money or all deficit, as the comment claims? Does every position still equal what its cap admits, with the payment and its credits adding up to the ledger? Can a give-back or a refund's return ever leave a deficit beside money?
- **The escheat check on the credit's own side.** Is "its own side, without the cover" read the same way as the cap? Is anything legitimate refused, for example a credit that truly holds nothing?
- **The void refusal.** Is "carries a share" read at the right instant? After the share is given back, does the void return exactly what the reissue still holds?
- **The depth bound.** Do all four walks agree on 999? Can any path make or reach a reissue past it without a raise (a history load, a superuser, a chosen time)?
- **The lock order with S1's new lock.** Is there any cycle among the void, the give-back, the return, the move to nsf and the draws on the family?
- **Performance.** The shares are read once per reading. Is the 1,000-deep line now usable one act at a time?

## Results so far (reproduce them)

- **Strict apply, twice:** clean (the second skips: "already applied").
- **`battery-23.sql`:** 372 checks, all pass. Z1–Z6e are new. Against r6, Z1–Z5d fail as the reviewers found, and Z6a–d fail because r6 reads a 1,000-deep line as NULL.
- **`races/cash-23.sh`:** CR1–CR25, 39 results. CR25 is new (Fable's RR-E, three sessions); on r6 it deadlocks (40P01).
- **`mutations-23.py`:** 218 of 218 caught, each at its named check. N212–N219 are new; N194 is re-anchored. N129 once missed CR10 on a timing miss under the run's load; run alone, it is caught at CR17. N203 is re-anchored from Y7b to Y7i, because the new cover makes Y7b read correctly even under the mutation.
- **`tests/ci.sh`:** not yet run on r7 (it passed 49/49 on r6 with -25 and -26).
- Since the build, the only change is to the header comments (R20 updated for Kyle's answer; R22 and R23 added). The battery was rerun after it: 372 of 372.

## What to answer

1. **Does r7 close each round-6 finding it claims to close?** Go item by item, for all three reviews.
2. **Does r7 apply the rulings faithfully** (K-10; Kyle's 10-30 answer; Ryan's status, reissue and escheat decisions)?
3. **Did r7 open anything new?** For example: a guard that refuses a legitimate act, a lock-order cycle, a moved check, or a role or superuser path.
4. **Is there still a path around any rule?** Consider every role, isolation level and statement shape.
5. **Concurrency.** Is every cap behind its lock? Does every move that frees money take the lock the next draw waits on?
6. **The invariants and the tests.** Is any claim narrower than its check, or any mutation passing for the wrong reason? Is anything missing?
7. **Residuals R1–R23.** Is any of them blocking?

## How to probe

**Opus and Fable** may query the running `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv23opus`, Fable `rv23fable`):
1. `CREATE DATABASE <name> TEMPLATE tally`.
2. Revoke TEMP on the clone from PUBLIC, `tally_app` and `tally_core` right after creating it.
3. `docker cp` the frozen patch into the container and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

-25 and -26 are not needed for this review.

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim must be a probe file in `tests/v5.4.2-23/review/codex-r7-probes/`. Each probe runs as the owner on a fresh clone with frozen r7 applied, ends in ROLLBACK, and prints SQLSTATE and message for each caught error with RAISE NOTICE. A COPY probe must print its own error. Keep any long-chain probe to what runs in minutes: the author cancels a probe past 30 minutes.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role.
- Do not run `mutations-23.py`; it uses the fixed name `m23`.
- Run `cash-23.sh` only against your own clone; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.
- Other sessions share this container: do not run `tests/ci.sh`, and keep to your own clone.

## Output

Write your full review to `tests/v5.4.2-23/review/<reviewer>-r7.md` (`opus`, `fable` or `codex`). It should contain:
- a verdict: "ready" or "not yet";
- the round-6 findings, each marked closed, partly closed or not closed;
- blocking items (B1…), each with the concrete path or repro;
- should-fix items (S1…);
- notes (N1…).

Mark each claim as **executed** or **predicted**. Your final message gives the verdict, the blocking items in one line each, and the file path, in several messages, each under 3 KB.
