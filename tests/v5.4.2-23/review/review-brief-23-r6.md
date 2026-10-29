# Review brief: v5.4.2-23 r6 — cash: round 5's findings (recorded order for take-backs, the shortfall placed at the reading, the reissue in its payment's lineage)

**Date:** 2026-10-29. **Kind:** patch review, round 6.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's round-6 files. You may read every earlier review in this folder (`*-r1.md` to `*-r5.md`, `codex-r*-probes/`): r6 answers round 5.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-23/review/patch-23-frozen-r6.sql` | `76424e4b63d27c2bd86dfa09ab76ff11` |
| `tests/v5.4.2-23/review/battery-23-frozen-r6.sql` | `bf8d6bb8df6334bcc7aae7348e6d4fc4` |
| `tests/v5.4.2-23/review/cash-23-frozen-r6.sh` | `5025bdc372669d4096f604e2fc6aa251` |
| `tests/v5.4.2-23/review/mutations-23-frozen-r6.py` | `7d9b762f4599b8eca516bfc0ccd4146d` |
| `tests/v5.4.2-23/review/older-tests-23-frozen-r5.diff` | `be99c2f963ab9f2177c9f059a4de7e5c` |
| `tests/v5.4.2-23/review/patch-23-r5-to-r6.diff` | `34d977827ba501d7fe1ffe00bfefe57a` |

Today the live copies are identical to the frozen ones. Review the frozen copies. `older-tests-23-frozen-r5.diff` is still every change -23 makes to earlier tests (r6 adds none; since r5 only `tests/ci.sh` changed, gaining a run lock across clones on 2026-10-29, unrelated to -23). `patch-23-r5-to-r6.diff` is for orientation; review the whole patch.

## What changed since round 5

All three reviewers said "not yet". The merged list is `application/wave2-build-2026-10-15/v5.4.2-23-r6-plan.md`, with an "As built" section at its end. The calls and their reasons are in `application/DECISION-LOG.md` (2026-10-29, -23 r6). There is no new ruling.

1. **Take-backs in recorded order** (B1). A row under a payment's posting entry is not recorded before a draw already counted on the payment or its credits, the credit itself, or a draw that has since left. These are the draws' own legs, now one function, `check_cash_order`: 40001 for a row stamped at its transaction's start, 23514 for a chosen time.
2. **The shortfall placed at the reading** (B2). The split records what each side held at a take-back's instant (`overpayment_shares`). A position reads it through `overpayment_absorbed_as_of`: a side in deficit is covered by the other side's money as far as it goes. The caps do not read the cover. A draw uses only its own side's money, and the cap on the two together holds the total.
3. **One instant in the tree's order** (B3): a row before the rows under it, then by id.
4. **Status times** (B4). A status time changes only with its status, for every role. A history load's chosen move is not before a row already recorded on the source's lineage (`cash_lineage_recorded`).
5. **The reissue in its payment's lineage** (B5). A refund_reissue credit descended from an overpayment credit (`overpayment_root`, `overpayment_family`):
   - takes the payment's lock for its draws;
   - is held by the cap on the payment and its credits together, by its draws, not its amount;
   - holds up the bounce and the move to nsf while applied or with a refund pending;
   - takes a share of a take-back: the overpayment credit first, then each reissue in recorded order, and a give-back restores the latest share first (R20);
   - has its own cap count that share.

   A reissue's sizing counts its own share.
6. **Should-fix items:**
   - S1: a credit's refund that leaves takes its payment's lock first.
   - S2: a give-back under a payment whose credit is escheated is refused only as far as the credit would then hold money.
   - S3: no future `created_at` on payments, credits, applications or remittances, for any role.
   - S5: R17 corrected; R18–R21 new.

The plan's "As built" lists five points that differ from the plan or go beyond it. Look at these two in particular:
- the shares are fixed when a take-back is recorded, not placed at the reading;
- a reissue's void takes no payment lock.

## Drafting calls to check in particular

- **The cover at the reading.** Does each position equal what its cap admits, with the two adding up to the ledger? agree() checks this for every W pair and r6 shape. Can a draw ever use the other side's money? Is a deficit ever left beside money on the other side?
- **The shares.** Is credit-first, then reissues, with a give-back restoring the latest share first, a sound attribution (R20)? Is there any reading in which the shares and the pool cap disagree about the money?
- **The recorded-order legs on a take-back.** Is anything legitimate refused, for example a bounce posted while an unrelated draw on the credit is in flight? Is a writer missing that should take the payment's lock?
- **`cash_lineage_recorded`.** Is the lineage complete? Does it refuse a legitimate history load?
- **One instant (R17).** Is the pool cap still enough for every reading of one transaction?
- **The lock order.** Is there any cycle with S1's new lock: the return, the move and the reissue, against give-backs, voids and draws on the family?

## Results so far (reproduce them)

- **Strict apply, twice:** clean.
- **`tests/ci.sh`:** passes in full with -23, -25 and -26 pending (49 steps).
- **`battery-23.sql`:** 343 checks. The Y section is new; W10d's fixture is now a history load. The Y checks fail against r5: `tests/v5.4.2-23/red-r6-against-r5.txt`.
- **`races/cash-23.sh`:** CR1–CR24, 38 results. New:
  - CR23 and CR23a–c: a take-back begun before a draw on the credit, or before the credit itself (40001, then a clean retry).
  - CR24: Fable's RR-D, now with no deadlock.
- **`mutations-23.py`:** 210 of 210 caught, each at its named check as the first failure. N192–N211 are new. 16 anchors moved with the code. N175, N177, N180, N203 and N204 are renamed to the check that now meets them first (the cover hides N175 and N177 at W3). N174 now mutates the per-credit "not yet recorded" test: the split's outer condition duplicated it and was removed.

## What to answer

1. **Does r6 close each round-5 finding it claims to close?** Item by item, for all three reviews.
2. **Does r6 apply the rulings faithfully** (K-10; Ryan's status, reissue and escheat decisions)?
3. **Did r6 open anything new?** A guard refusing a legitimate act; a lock-order cycle; a moved check; a role or superuser path.
4. **Is there still a path around any rule?** Every role, isolation level and statement shape.
5. **Concurrency.** Every cap behind its lock; every money-freeing move taking the lock the next draw waits on.
6. **The invariants and the tests.** Any claim narrower than its check; any mutation passing for the wrong reason; anything missing.
7. **Residuals R1–R21.** Is any of them blocking?

## How to probe

**Opus and Fable** may query the running `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv23opus`, Fable `rv23fable`):
1. `CREATE DATABASE <name> TEMPLATE tally`.
2. Revoke TEMP on the clone from PUBLIC, `tally_app` and `tally_core` right after creating it.
3. `docker cp` the frozen patch into the container and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

-25 and -26 are not needed for this review.

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim must be a probe file in `tests/v5.4.2-23/review/codex-r6-probes/`. Each probe runs as the owner on a fresh clone with frozen r6 applied, ends in ROLLBACK, and prints SQLSTATE and message for each caught error with RAISE NOTICE. The author will run the probes.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role.
- Do not run `mutations-23.py`; it uses the fixed name `m23`.
- Run `cash-23.sh` only against your own clone; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.
- Other sessions now share this container: do not run `tests/ci.sh`, and keep to your own clone.

## Output

Write your full review to `tests/v5.4.2-23/review/<reviewer>-r6.md` (`opus`, `fable` or `codex`). It should contain:
- a verdict: "ready" or "not yet";
- the round-5 findings, each marked closed, partly closed or not closed;
- blocking items (B1…), each with the concrete path or repro;
- should-fix items (S1…);
- notes (N1…).

Mark each claim as **executed** or **predicted**. Your final message, under 2 KB, gives the verdict, the blocking items in one line each, and the file path. If you cannot write the file, send the review to main as several messages, each under 3 KB.
