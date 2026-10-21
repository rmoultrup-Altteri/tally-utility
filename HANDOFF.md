# Handoff: -23 cash r4 reviewed "not yet" by all three; the r5 fix list is written, r5 not started

**Generated**: 2026-10-21, 14:40 CDT
**Branch**: `main` in both repos, pushed. tally-utility is at the wrap-up commit; GBM is at `8003ec9` (Kyle's K-10 answer, recorded this session).
**Status**: In progress. Ryan has been asked "shall I start round 5?" and has not answered yet. Ask him first.

## Goal

Reach the C# core build. Ryan's gate, in order:
1. schema parity with CI-001…CI-135 (**we are here**: 78 of 135, re-graded only after a mirror);
2. scenarios and a test strategy;
3. a phase plan;
4. build.

-23 (cash) is the blocker in wave 2. -25 (disputes) and -26 (collections) are drafted and wait for -23. Mirror order: -23, then -25, then -26.

## Completed (this session, 2026-10-21)

- [x] **Kyle's K-10 answer** (relayed by Ryan in chat) is recorded as a ruling file: GBM `application/kyle-decisions-2026-10-21-refund-then-bounce.md`, plus manifest Section BS (`8003ec9`).
  - 1 = A: a refund is its own movement of money.
  - The two caps: bounce ≤ payment − reversals; refund ≤ payment − refunds − reversals.
  - 2: a pending refund blocks the bounce, with no auto-cancel.
  - 3: a return-window hold is tenant policy, not schema.
- [x] **Ryan's decisions:**
  - payments and credits lose the `refunded` status, and credits lose `donated` (read from positions);
  - a refund of an escheated credit that comes back goes into a new `refund_reissue` credit.
- [x] **-23 r3:** tests first (`530ffee`), then built (`494f727`, `7728e96`), frozen and reviewed (all "not yet"); the r4 list merged (`5c3a7ab`).
- [x] **-23 r4:**
  - tests first (`d2b4ca3`);
  - built and frozen (`c91a00c`): battery 252, races CR1–CR19 (29), mutations 170/170, CI 49/49;
  - reviewed by all three ("not yet"); Codex's probes run (all reproduce); the r5 list merged (`3517d0b`): `application/wave2-build-2026-10-15/v5.4.2-23-r5-plan.md`.
- [x] **Records:**
  - DECISION-LOG has four 2026-10-21 entries;
  - the r3, r4 and r5 plans;
  - the design doc's "Corrections made in review";
  - roadmap `phases.json` summary and the dashboard `phases` dataset refreshed (dates unchanged: likely ready 2027-06-16).

## Not Yet Done

- [ ] **Ask Ryan whether to start -23 r5.** If yes, follow `v5.4.2-23-r5-plan.md`:
  - **B1:** a guard on rows under a refund's posting row (refund lock; nothing more once nsf or reversed).
  - **B2:** one split for an overpayment credit and its payment, read by both positions and both caps. A take-back recorded after the credit comes out of the credit first, up to its amount (`absorbed`); the payment's cap counts the take-back less `absorbed`.
  - **B3:** refuse a give-back under a payment whose overpayment credit is escheated.
  - **B4:** a reissue carries the escheated credit's *positive* remainder (at most the refund's amount), and the commit check requires nothing positive left. This refines Ryan's option 1 for "the payment also bounced"; it was reported to him.
  - **B5:** `status_recorded_at` is never in the future or non-finite, for any role.
  - **B6:** move the READ COMMITTED pin above the arrival-row branch in `enforce_ledger_reversal`.
  - **S1:** a reissue is dated on or after the refund's return row. S2: comment fixes. S3: tests and mutations for each.
- [ ] **Then:** freeze r5 for Opus, Fable and Codex (brief, md5s, Codex probes run by the author), and merge the findings.
- [ ] **Review -25 and -26** after -23 settles.
- [ ] **Tell Kyle (not blocking):**
  - ui-concepts still lists `refunded` as a payment status;
  - the `do_not_disconnect` checkbox must become a protective enrollment;
  - the four law findings from the wave-3 inventory.
- [ ] **Carried over:**
  - the reply to Kyle on D-2's location;
  - the -05 defect (`meters_last_validated_actual_reading_id_fkey`);
  - -21 R9;
  - the R-03 scoping;
  - `pga_monthly_reconciliations.deferred_balance_after`;
  - the backbilling tariff table;
  - the GitHub Actions bump;
  - the Florida 25-7.083 text;
  - the waiver-determination rewrite;
  - low-confidence measurement rows;
  - the -15 r8 follow-ups.

## Failed Approaches (Don't Repeat These)

- **Fable's r3 fix for the overpayment credit** ("the bounce waits until the credit holds nothing"). In the common partial case the only ways to empty the credit are to refund or spend money that just bounced. Instead, the bounce waits only while the credit is applied or has a refund pending.
- **Forcing a payment's posting row to carry the payment's date** (Codex r3 B3). It broke battery M3: an ACH payment dated 03-05 settled 03-08, and the row is dated the settlement. Instead, the cap counts the arrival entry from its own date: `('-infinity', v_amount)` plus `(entry date, entry amount)`.
- **The arrival entry counted as `l.amount + v_amount` at its date.** That is zero there and leaves earlier dates unguarded (V10 was admitted). It must be missing from `-infinity` until the entry's date.
- **The commit check as "remaining = 0".** A future `status_recorded_at` hides it (Codex r4 B4). The partial-bounce case passes with no reissue, which turns out to be right; see r5 B4.
- **`IF ... CASE WHEN ... THEN ... END ... THEN` in plpgsql.** The IF parser stops at the CASE's THEN ("syntax error at end of input"). Compute into a variable first.
- **Reading `NEW.reissues_refund_id` in a trigger shared by tables that lack the column.** It fails at runtime. Nest the check under `IF TG_TABLE_NAME = 'customer_credits'`.
- **Multi-row history inserts with chosen `created_at` in one statement.** The earlier row's AFTER trigger sees the later row and refuses it (recorded order). Use one INSERT per row.
- **The mutation runner's stdout to a file.** Python buffers it, so the log stays empty until the end. Check `pg_stat_activity` on `m23` for progress.

## Key Decisions

| Decision | Rationale |
|---|---|
| A refund names no entry; refund rows > 0 (K-10 1 = A) | The bank's full return fits R-02; the customer owes what was refunded |
| Every draw capped by source − taken back, at every date, from the new row's date on | Kyle's refund cap, applied to all money leaving one source; old K-10 deficits don't veto later draws |
| No `refunded` or `donated` status (Ryan) | As final labels they left a bounced refund check unrecordable; a counter in disguise |
| `refund_reissue` credit for a refund returning after escheat (Ryan, option 1) | The money is the customer's; escheated stays final |
| One live overpayment credit per payment | The credit's standing is read from its payment's posting entry; two would need an order |
| Arrival rows only while the payment is pending or the credit active, under the source lock | A voided payment's or cancelled refund's money never arrived or went out |
| Nothing given back to an ended source | A re-presented check is a new payment; nothing comes back to an escheated credit |

## Current State

**Working:**
- tu.sql through -22.
- -23 r4, -25 and -26 pending in CI; `tests/ci.sh` all pass (49 steps).
- -23 r4: battery 252, races 29, mutations 170/170.

**Broken (known):** r4's findings (the r5 list); all reproduce on a fresh r4 clone.

**Uncommitted changes:** none after the wrap-up commit.

**Scratch DBs** (throwaway): `s23` (tally + -23 r4 + -25 + -26), `r23`, `ci_base`, `ci_pre25`, `ci_pre26`. The scratchpad holds `fresh23.sh <db> [23]` (clone tally, revoke TEMP, strict-apply -23 twice, then -25 and -26 unless the second argument is 23).

## Code Context

```sql
-- the cap (check_cash_source, r4): at every date d >= p_on,
--   draws(d) + rows under the arrival entry(d) + (v_amount until the entry's own date) > v_amount  -> refuse
-- for an overpayment credit, v_entry = its PAYMENT's arrival entry (cash_arrival_entry('payment', source_payment_id))
public.cash_arrival_entry(kind text, id uuid) -> uuid   -- unique by account_ledger_payment_arrival_key / _credit_arrival_key
public.payment_position_as_of(id, on, recorded) -> (amount, received, applied, credited, refunded, remaining)
public.customer_credit_position_as_of(id, on, recorded) -> (amount, issued, applied, refunded, given_up, carried, remaining)
customer_credits.reissues_refund_id  -- refund_reissue only; one per refund; draws on the refund's credit
enforce_escheated_credit_settled     -- DEFERRABLE constraint trigger on payments (refund leaving an escheated credit)
-- lock order: head -> tree -> source (payment before its overpayment credit; credit before its reissue) -> line
```

## Resume Instructions

1. `git pull --ff-only` here; `git -C ../gas-billing-memory fetch`.
2. Ask Ryan whether to start r5. If yes, follow the plan's order:
   - tests first (a W section in battery-23), recording failures against r4 as `red-r5-against-r4.txt`;
   - then the patch, `$S/fresh23.sh s23`, the battery, the other batteries, `races/cash-23.sh`, the mutations (~45 min), `tests/ci.sh`;
   - then freeze and launch the reviewers as in r4: Codex via `codex exec -s workspace-write ... < /dev/null`; Opus and Fable as agents.
3. Expected: every W check fails on r4 before the fix and passes after it; all earlier checks stay green.

## Warnings

- **Don't edit the patch or tests while `mutations-23.py` runs.**
- **Revoke TEMP after every TEMPLATE clone,** or the seal invariant refuses the patch ("tally_seal can define code").
- **Codex hit its usage limit in r4** after writing its review. Check that `codex-r5.md` is complete, and look for the limit line in its log.
- **Never edit** the frozen review copies or tu.sql's mirrored bodies.
