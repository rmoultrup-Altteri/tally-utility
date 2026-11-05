# Review brief: v5.4.2-27 r1 — a credit applied to a bounced payment's shortfall (AC-44's netting, recorded)

**Date:** 2026-11-05. **Kind:** patch review, round 1.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's files.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-27/review/patch-27-frozen-r1.sql` | `f1fbdf157f53fd098b989ec155d654ce` |
| `tests/v5.4.2-27/review/battery-27-frozen-r1.sql` | `5db82bc75a30e5aba615e3e2b6bcbe21` |
| `tests/v5.4.2-27/review/shortfall-27-frozen-r1.sh` | `babf6406acec78d53d9e1cfb2018d684` |
| `tests/v5.4.2-27/review/mutations-27-frozen-r1.py` | `c8be8e11cc39e1524ac9775c60d811c0` |
| `tests/v5.4.2-27/review/ci-27-frozen-r1.diff` | `bb7f2e5fe83202c41fcca2aaebd31196` |

The live copies (`sql/v5.4.2-27-shortfall-applications.sql`, `tests/v5.4.2-27/battery-27.sql`, `races/shortfall-27.sh`, `mutations-27.py`) are identical today. The diff is -27's change to `tests/ci.sh` (PENDING, battery, races). -27 changes no earlier test.

## Background

The base is the `tally` database: `sql/tu.sql` through v5.4.2-23 (mirrored 2026-11-04 after ten rounds; cash: reversals, derived positions, per-line application, overpayment credits) and -28. -27 builds on -23's cash machinery and re-issues six of its functions (`cash_source_draws`, `payment_draws_as_of`, `customer_credit_draws_as_of`, `overpayment_absorbed_as_of`, `payment_position_as_of`, `check_cash_source`) with additions only; diff each against its body in `sql/tu.sql` (or the -23 patch file) to see exactly what changed.

The rulings:
- **Kyle, 2026-10-30** (`gas-billing-memory/application/kyle-decisions-2026-10-30-credit-shortfall-after-bounce.md`): all of a customer's credits are one pot; a bounce's shortfall consumes the pot, the customer owes the rest.
- **K-10** (`kyle-decisions-2026-10-21-refund-then-bounce.md`): a refund is its own movement of money; 50 paid, 30 refunded, 50 bounced: 30 owed; never invent a billed charge for it.
- **Ryan, 2026-11-02** (DECISION-LOG, -23 r8 entry): the netting is recorded as a new kind of application pointed at the payment's shortfall, its own patch; additive.
- **Ryan, 2026-11-05** (DECISION-LOG, -27 design entry; option 1): a refund of the bounced payment that comes back after its shortfall was repaid waits until the repayment is undone (the operator undoes it first, same transaction).

The design, and the calls settled by rule, are in `application/wave2-build-2026-10-15/v5.4.2-27-design.md`; section 8 lists where the build differs. The contract the core reads is APPLICATION-CONTRACTS AC-44 (updated at mirror). -23's residuals R23 and R24 are what -27 closes.

## Drafting calls to check in particular

- **The target's cap** (`check_shortfall_repaid`). From a date on, the payment and its overpayment family never hold money: the same sum as `check_cash_source`'s cap on a payment and its credits together, read the other way. A repayment is checked from its own date; a move giving money back from the target's latest shortfall row's date (section 8: a refund that leaves stops counting at every date, so between a repayment and its undo the money reads back). Is that the right boundary? Can a sequence of back-dated repayments, undos and leaving moves leave the family holding money at a date from which nothing re-checks?
- **Every way money comes back to a repaid family.** The check runs after a repayment, after any `undo` purpose in `check_cash_source` (application, donation, shortfall undos on the family), and after a refund of the payment or of a family credit leaves (`enforce_shortfall_source_moves`). Is any path missing: a family credit's void, a reissue, an escheat event, a row under the posting entry, a give-back, a status move with a chosen time?
- **Within one family** (purpose `shortfall_within_family`): a credit holding the target's own money is exempt from the family cap, as -23 r9 exempted a reissue. Can that exemption be reached by a credit that is not of the target's family, or used to move money out of a family?
- **The source's own bounce** (R15): two new triggers rather than editing -23's `enforce_ledger_reversal` and `enforce_payment_immutable`. Do they cover every take-back and every move to nsf, reversed or voided, under the right lock?
- **Readers.** The source counts the netting in `applied`; the target's `repaid` is a new last column of `payment_position_as_of` (dropped and re-created) and on the payment's own part in the cover. Do the positions still add up to the ledger, with no line reading money beside another's deficit (-23 r7/r8's properties), with repayments present? Is `cash_drawn_at` really safe unchanged (header)?
- **Recorded order and locks.** The target's lock first, then the source's (through `check_cash_source`). A repayment is not recorded before the target's move, a draw on it or its family, a draw that left them, or a row under its posting entry. Any deadlock no retry resolves? Any instant at which a position reads the repayment and a state it should follow but does not?
- **Tenancy.** Every key carries the tenant; RLS and FORCE RLS; `tally_app` SELECT, INSERT only.

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`; the second run is skipped by its marker, the table `shortfall_applications`.
- **`battery-27.sql`:** 80 checks, one transaction, rolled back.
- **`races/shortfall-27.sh`:** SR1–SR8, 14 results.
- **`mutations-27.py`:** 35 of 35 caught, each at its named check as the first failure.
- **-23's own tests with -27 applied:** battery-23 409/409, races cash-23.sh 51/51.
- **`tests/ci.sh`:** 58 steps, all pass, with -27 pending (behind -25 and -26).

## What to answer

1. **Does the patch implement the design and the rulings?** Name any requirement missed or half-done.
2. **Is there a path around any new rule?** Consider: a repayment past what is owed at any date; a payment that has not ended taking one; a source of another customer or tenant; a deposit or pending payment as a source; an undo past what it undoes, of another source, or before its row; money coming back to a repaid family by any path; a source applied to a shortfall that still bounces; the within-family exemption abused. Try each role, isolation level and statement shape (multi-row, writable CTE, COPY), and a superuser history load.
3. **-23's properties.** Do -23's caps, cover, shares and recorded-order rules still hold with repayments in the family? Does any re-issued function differ from -23's beyond the additions?
4. **Concurrency.** Is the lock order followed everywhere? Is any cap a read without the lock that orders it?
5. **The invariants.** Does `assert_shortfall_guard_invariants()` catch what it claims? Is any claim narrower than its check?
6. **The tests.** Is any check weaker than its label? Does any mutation pass for the wrong reason? What is missing?
7. **Residuals R1–R4.** Is any of them actually blocking?

## How to probe

**Opus and Fable** may query the running `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv27opus`, Fable `rv27fable`):
1. `CREATE DATABASE <name> TEMPLATE tally`.
2. Revoke TEMP on the clone from PUBLIC, `tally_app` and `tally_core` right after creating it.
3. `docker cp` the frozen patch into the container, then apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim must be a probe file in `tests/v5.4.2-27/review/codex-r1-probes/`. Each probe runs as the owner, on a fresh clone with frozen r1 applied, ends in ROLLBACK, and prints SQLSTATE and message for each caught error with RAISE NOTICE (a COPY probe must print its own error: psql leaves LAST_ERROR_SQLSTATE at 00000 after a failed COPY). The author will run the probes.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role.
- Do not run `mutations-27.py`; it uses the fixed name `m27`. Do not run `tests/ci.sh`.
- Run `shortfall-27.sh` only against your own clone; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.

**Output:** `tests/v5.4.2-27/review/<you>-r1.md` (opus, fable, codex): verdict "ready" or "not yet"; items B (blocking), S (should fix), N (note), each marked executed or predicted, with the evidence.
