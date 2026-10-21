# Review brief: v5.4.2-23 r3 — cash: Kyle's K-10 applied, refunded and donated no longer statuses, round 2's findings

**Date:** 2026-10-21. **Kind:** patch review, round 3.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's round-3 files. You may read every round-1 and round-2 review in this folder (`*-r1.md`, `*-r2.md`, `codex-r*-probes/`): r3 answers round 2.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-23/review/patch-23-frozen-r3.sql` | `52044407233e3e574910cfcd2d0b976d` |
| `tests/v5.4.2-23/review/battery-23-frozen-r3.sql` | `9a616cf494c39d142a28f340765120eb` |
| `tests/v5.4.2-23/review/cash-23-frozen-r3.sh` | `844f988b8ee4117842c805b667a22c5c` |
| `tests/v5.4.2-23/review/mutations-23-frozen-r3.py` | `8add02abaee5184fd0667827ba6f68ea` |
| `tests/v5.4.2-23/review/older-tests-23-frozen-r3.diff` | `be99c2f963ab9f2177c9f059a4de7e5c` |
| `tests/v5.4.2-23/review/patch-23-r2-to-r3.diff` | `08f4867cd3c5d0fca52f580cd65dc9da` |

Today the live copies are identical to the frozen ones. Review the frozen copies. The live copies are `sql/v5.4.2-23-cash-reversals-positions-application.sql`, `tests/v5.4.2-23/battery-23.sql`, `tests/v5.4.2-23/races/cash-23.sh` and `tests/v5.4.2-23/mutations-23.py`.
- `older-tests-23-frozen-r3.diff` holds every change -23 made to earlier tests, measured against the -22 mirror commit `eef5122`. r3 adds one: -19 cancels P-4 before P-2 bounces.
- `patch-23-r2-to-r3.diff` is the patch's change since round 2, for orientation only. Review the whole patch: r3 replaced `cash_arrival_stands` and rewrote the cap.

## What changed since round 2

Two rulings arrived. Read them first.
- **Kyle's K-10** (gas-billing-memory `application/kyle-decisions-2026-10-21-refund-then-bounce.md`):
  1. a refund is its own movement of money, not an undo of the payment;
  2. a refund still waiting to go out blocks the bounce until an operator cancels it, with no automatic cancel;
  3. a hold on refunds inside the return window is tenant policy, not schema.

  Kyle also gave two caps: a bounce is limited by the payment less earlier reversals; a refund by the payment less earlier refunds and reversals.
- **Ryan, 2026-10-21:** "refunded" (payments and credits) and "donated" (credits) are no longer stored statuses. They are read from the positions. A failed refund or an undone donation frees the money again. Escheated stays.

`application/wave2-build-2026-10-15/v5.4.2-23-r3-plan.md` maps every round-2 finding to its fix, and `application/DECISION-LOG.md` (2026-10-21) gives the reasons. In short:
1. **X1.** A `refund` row names no entry and is more than 0. The bounce-row exemption is gone.
2. **The cap** (`check_cash_source`). At every date, a source's draws plus what was taken back under its arrival entry total at most the source. An undo is not capped. `cash_arrival_entry` replaces `cash_arrival_stands`.
3. **K2.** Any row undoing a payment's posting entry is refused while a refund of it is pending.
4. **One arrival entry per source.** Unique indexes; the row is checked at its write (label, kind, amount, account); an overpayment credit posts no `credit_issued` row.
5. **Positions** read `received` (a payment) and `issued` (a credit): what stands on the ledger. A donation counts net of its undo.
6. **Recorded order.** A draw is not recorded before its source reached the ledger, nor before a draw that has since left it. A refund that leaves takes its source's lock; so does an overpayment credit's void (its payment's).
7. **Escheat remittances.** Frozen by the close (their own trigger, by UTC day); on the credit's own account (a composite FK). Donations likewise.
8. **Status vocabularies.** Payments: pending, posted, nsf, reversed, voided. Credits: active, escheated, voided. An escheated credit has nothing left of what stands on the ledger.
9. **Invariants** pin the new guards plus the three facts Fable found unpinned (refund sign on payments, a credit's positive amount, the remittance's stamp), tally_app's EXECUTE on `check_cash_source`, and "one policy only" on approvals.

## Drafting calls to check in particular

- **The cap.** Draws ∪ the arrival entry's tree, summed by date. Is every way money leaves a source in `cash_source_draws`, and every way it comes back under the arrival entry? Can any row count twice: a donation's undo, a refund's own posting row, a re-reversal? Is skipping the cap for an undo safe in every state a legitimate history can reach?
- **Kyle's example and its neighbours.** A refund posted, then a full bounce: the payment reads remaining −30. What else reads a payment's remaining and could mistake that for an error? What happens to a draw, an undo or a status move on that payment afterwards?
- **The arrival-row check** in `enforce_ledger_reversal`. It applies to `payment`/`deposit`/`refund` rows whose `reference_type` is `payment` or `refund`, and to `credit_issued` rows referencing a credit. Is there a posting row it misses (another label, a NULL reference) that the readers still treat as an arrival?
- **The leaving moves.** A refund's void, nsf or reversed, and an overpayment credit's void, give money back. Does every one take its source's lock? Does `check_cash_source`'s new recorded-order leg see every one, and only those?
- **Status vocabularies.** Is any reader, guard, index, view or earlier patch still keyed on `refunded` or `donated` for payments or credits? (Deposits have their own `refunded`; escheat events have `donated` as an event type. Neither is in scope.)
- **The remittance freeze.** UTC day against `closed_through`; the head before the credit's lock. Does any escheat path move money without it?
- **Residuals R12–R15** (new in the header). Is any of them blocking?

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`; the second run skips on its marker.
- **`tests/ci.sh`:** passes in full with -23, -25 and -26 pending (49 steps): batteries 09–26, the -15/-17/-18 runners, every race script, the migrations and all invariant steps.
- **`battery-23.sql`:** 216 checks. The S section is new: Kyle's example, both caps at their boundaries, K2, one arrival entry, credit refunds posted, partial withdrawal, donation undo, cross-customer draws, the remittance freeze, posting by an undone entry. R8, R10–R12 are rewritten for the status decision; R8e–R8h are the bounced refund check; R12h–R12j escheat with money left and an undo after it. Every S check failed against r2 before the fix: `tests/v5.4.2-23/red-r3-against-r2.txt`.
- **`races/cash-23.sh`:** CR1–CR17, 26 results. New: CR13 and CR13b (a refund cancelled under an application, in both orders), CR14 (an application begun before its payment was posted), CR15 and CR15b (a pending refund against a bounce, in both orders), CR16 (posting under an application), CR17 (an overpayment credit voided under an application).
- **`mutations-23.py`:** 140 of 140 caught, each at its named check as the first failure of any kind. N111–N140 are new; N33, N83–N85 and N88 are replaced (their r2 code is gone).

## What to answer

1. **Does r3 close each round-2 finding it claims to close?** Item by item: closed, partly closed (what is left), or not closed.
2. **Does r3 apply K-10 and Ryan's status decision faithfully?** Any place the patch says one thing and does another.
3. **Did r3 open anything new?** A guard refusing a legitimate act; a lock-order cycle; a check that moved and no longer runs on some path; a role or superuser path around the new rules.
4. **Is there still a path around any rule?** Try each role, isolation level and statement shape (multi-row, writable CTE), and a superuser history load.
5. **Concurrency.** Is every cap behind a lock taken before its read? Does every money-freeing move take the lock the next draw waits on?
6. **The invariants and the tests.** Is any claim narrower than its check? Does any mutation pass for the wrong reason? What is missing?
7. **Residuals R1–R15.** Is any of them blocking?

## How to probe

**Opus and Fable** may query the running `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv23opus`, Fable `rv23fable`):
1. `CREATE DATABASE <name> TEMPLATE tally`.
2. Revoke TEMP on the clone from PUBLIC, `tally_app` and `tally_core` right after creating it.
3. `docker cp` the frozen patch into the container and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

-25 and -26 are not needed for this review.

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim must be a probe file in `tests/v5.4.2-23/review/codex-r3-probes/`. Each probe runs as the owner on a fresh clone with frozen r3 applied, ends in ROLLBACK, and prints SQLSTATE and message for each caught error with RAISE NOTICE. The author will run the probes.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role.
- Do not run `mutations-23.py`; it uses the fixed name `m23`.
- Run `cash-23.sh` only against your own clone; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.

## Output

Write your full review to `tests/v5.4.2-23/review/<reviewer>-r3.md` (`opus`, `fable` or `codex`). It should contain:
- a verdict: "ready" or "not yet";
- the round-2 findings, each marked closed, partly closed or not closed;
- blocking items (B1…), each with the concrete path or repro;
- should-fix items (S1…);
- notes (N1…).

Mark each claim as **executed** or **predicted**. Your final message, under 2 KB, gives the verdict, the blocking items in one line each, and the file path. If you cannot write the file, send the review to main as several messages, each under 3 KB.
