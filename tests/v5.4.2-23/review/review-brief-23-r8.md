# Review brief: v5.4.2-23 r8 — cash: round 7's findings (escheat checks on the credit's own money, option A's narrowed promise, the escheat lock, pinned plans)

**Date:** 2026-11-02. **Kind:** patch review, round 8.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's round-8 files. You may read every earlier review in this folder (`*-r1.md` to `*-r7.md`, `codex-r*-probes/`): r8 answers round 7.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-23/review/patch-23-frozen-r8.sql` | `25e0a9212a348dfabab4f3fa22c65822` |
| `tests/v5.4.2-23/review/battery-23-frozen-r8.sql` | `c5c7fb7b3f55e6e8c192dbda94cf37a1` |
| `tests/v5.4.2-23/review/cash-23-frozen-r8.sh` | `46ed9b5d66a5fe6114f0e3fbc54942b8` |
| `tests/v5.4.2-23/review/mutations-23-frozen-r8.py` | `0478e49e40ab2e7d7fe1bc85b777d662` |
| `tests/v5.4.2-23/review/older-tests-23-frozen-r5.diff` | `be99c2f963ab9f2177c9f059a4de7e5c` |
| `tests/v5.4.2-23/review/patch-23-r7-to-r8.diff` | `12f52de9201be5b08e177bc71a59c83f` |

Today the live copies are identical to the frozen ones. Review the frozen copies. `older-tests-23-frozen-r5.diff` is still every change -23 makes to earlier tests (r8 adds none). `patch-23-r7-to-r8.diff` is for orientation; review the whole patch.

## What changed since round 7

All three reviewers said "not yet". The merged list is `application/wave2-build-2026-10-15/v5.4.2-23-r8-plan.md`, with "As built" at its end. The calls and their reasons are in `application/DECISION-LOG.md` (2026-11-01 -23 r8, and 2026-11-02 -23 r8).

1. **B1, two holders of money beside a deficit: option A (Ryan, 2026-11-01).** The promise is narrowed, not the caps changed. A line's position never exceeds what it can pay; the payment's and its credits' positions add up to what the ledger leaves; no line reads money beside another's deficit. A line need not pay exactly what it reads: with two holders, the one the cover falls on reads less than its caps admit. The comments (at `overpayment_absorbed_as_of`, R17, R20) and agree() in the battery say exactly this. Fable P2, P3 and Opus G are added (Q1–Q3).
2. **B2, an escheated credit's own money rising after the escheat.** One helper, `customer_credit_own_remaining_as_of` (shares as recorded, no cover), is read by the move to escheated, the give-back guard in `enforce_ledger_reversal`, `enforce_escheated_credit_settled`, and the reissue's size. Opus H (Q4) is refused; Codex 02 (Q5) must be carried to a reissue.
3. **Beyond the plan: a reissue is sized on its credit's own side.** Sized on the covered position, the reissue Codex 02 requires could be 0 while the credit held 20 of its own, and the bank's returned refund could never be settled.
4. **S1, the escheat move's lock.** A move to escheated of a credit holding a payment's money takes the payment's lock first. Race CR26 (Opus D2); on r7 it deadlocks.
5. **S2, plan-sensitive walks.** `reissue_generation`, `overpayment_root`, `overpayment_family` and `cash_source_draws` are pinned as `overpayment_shares` is, and listed in the invariant's plan-settings check. The mutation runner vacuums `payments` and `customer_credits` too. Under vacuumed statistics the whole battery, including the 999th reissue's make and a refund of it, runs in about 45 s; before, one step ran past 5 minutes.
6. **S3–S5.** Z6 now requires the 999th make and a refund of it to succeed (Codex S3). R24 is new (below). The new shapes are tested through agree(), with a mutation per new leg.
7. **Found by the first full mutation run.** N207 (a reissue's own cap forgetting its share of a take-back) passed the battery: the narrowed agree() no longer catches a cap set too high. Y7j2 checks that cap directly. N223 is relabelled Z4a, the first check that sees it.

**Decided since the round-7 reviews (AC-44, what the core must do; no schema change in -23):**
- Netting a credit across payments before an **escheat report** is a setoff. The core does it only where the escheat state's rule allows; with no rule row, it reports the credit's own money in full (Ryan, 2026-11-02; Opus r7 N3). Before a refund it nets always (Kyle's pot).
- The netting is recorded as **a new kind of application, pointed at the bounced payment's shortfall**, never as a billed charge (Kyle, K-10, rejected inventing a charge). That row is v5.4.2-27, claimed and not drafted; it goes next after -23 (Ryan, 2026-11-02).

## Known limits (accepted; listed so you can judge them, not as findings to rediscover)

- **R22.** A reissue carrying a take-back's share cannot be voided until the share is given back (Ryan, 2026-10-29).
- **R23.** The cover nets within one payment only. Across payments, the core nets as AC-44 now says; -27 adds the row that records it. A database cap across the customer's payments can be added later.
- **R24.** A credit whose own money covers a deficit that nothing will give back reads 0 and never closes: its escheat is refused, and its void is a correction. The money is right. The core reads it as netted, not dormant; -27's application is its closing act.
- **Option A.** A screen showing per-line credits can show a line paying out more than it read, and a sibling's figure then moving untouched. The customer-facing number is the net (Kyle, 10-30).

## Drafting calls to check in particular

- **The narrowed promise.** Does every position stay at or under what its caps admit, in every shape (one holder, two, a payment and credits, after a give-back, after a refund's return)? Do the positions still add up to the ledger? Is there now any test that only checks "no more than", where it should also check the figure?
- **The own-side helper.** Is it read the same way as each per-side cap, at the same instant? Is anything legitimate now refused: a give-back that only cancels a deficit, a credit that truly holds nothing, a bank return of a refund?
- **The reissue's size on the own side.** Can the reissue carry more than the credit's own money, or strand any?
- **The lock order with the escheat move's new lock.** Any cycle among the escheat move, the void, the give-back, the return, the move to nsf and the draws?
- **The pinned plans.** Does any pinned function still pick a bad plan under bad statistics? Is the plan-settings check complete?
- **The mutation suite.** With agree() narrowed, is any other cap-too-high mutation passing for the wrong reason, as N207 was?

## Results so far (reproduce them)

- **Strict apply, twice:** clean (the second skips: "already applied").
- **`battery-23.sql`:** 390 checks, all pass, about 22–45 s after `VACUUM payments, customer_credits, account_ledger`. Q1–Q5d and Y7j2 are new.
- **`races/cash-23.sh`:** CR1–CR26, 40 results. CR26 is new.
- **Against r7** (`tests/v5.4.2-23/red-r8-against-r7.txt`): Q4 fails first (the give-back of 40 onto the escheated credit is admitted); CR26 deadlocks (40P01).
- **`mutations-23.py`:** 225 of 225 caught, each at its named check (43 min). N220–N226 are new; N205 and N215 re-anchored; N207 retargeted to Y7j2, N223 to Z4a.
- **`tests/ci.sh`:** not yet run on r8.
- Since the mutation run, the only change is to the header comments (R23 and R24 updated for the 11-02 AC-44 decisions). The strict apply and battery were rerun after it: 390 of 390.

## What to answer

1. **Does r8 close each round-7 finding it claims to close?** Go item by item, for all three reviews.
2. **Does r8 apply the rulings faithfully** (K-10; Kyle's 10-30 answer; Ryan's 10-21 escheat rule and option A)?
3. **Did r8 open anything new?** For example: a guard that refuses a legitimate act, a lock-order cycle, a moved check, or a role or superuser path.
4. **Is there still a path around any rule?** Consider every role, isolation level and statement shape.
5. **Concurrency.** Is every cap behind its lock? Does every move that frees money take the lock the next draw waits on?
6. **The invariants and the tests.** Is any claim narrower than its check, or any mutation passing for the wrong reason? Is anything missing?
7. **Residuals R1–R24 and AC-44 as now worded.** Is any of them blocking?

## How to probe

**Opus and Fable** may query the running `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv23opus`, Fable `rv23fable`):
1. `CREATE DATABASE <name> TEMPLATE tally`.
2. Revoke TEMP on the clone from PUBLIC, `tally_app` and `tally_core` right after creating it.
3. `docker cp` the frozen patch into the container and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

-25 and -26 are not needed for this review.

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim must be a probe file in `tests/v5.4.2-23/review/codex-r8-probes/`. Each probe runs as the owner on a fresh clone with frozen r8 applied, ends in ROLLBACK, and prints SQLSTATE and message for each caught error with RAISE NOTICE. A COPY probe must print its own error. Keep any long-chain probe to what runs in minutes: the author cancels a probe past 30 minutes.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role.
- Do not run `mutations-23.py`; it uses the fixed name `m23`.
- Run `cash-23.sh` only against your own clone; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.
- Other sessions share this container: do not run `tests/ci.sh`, and keep to your own clone.

## Output

Write your full review to `tests/v5.4.2-23/review/<reviewer>-r8.md` (`opus`, `fable` or `codex`). It should contain:
- a verdict: "ready" or "not yet";
- the round-7 findings, each marked closed, partly closed or not closed;
- blocking items (B1…), each with the concrete path or repro;
- should-fix items (S1…);
- notes (N1…).

Mark each claim as **executed** or **predicted**. Your final message gives the verdict, the blocking items in one line each, and the file path, in several messages, each under 3 KB.
