# Opus review: v5.4.2-22 r1

**Date:** 2026-10-15. **Reviewer:** Opus. **Verdict: not yet.** There are two blocking items (B1, B2). Both are small to fix.

**Hashes verified (executed).** All four frozen files match the brief: patch `99acfac6…`, battery `e6070dfd…`, close `73b157d2…`, mutations `931d9091…`.

**What I ran (executed).** I cloned `rv22opus` from `tally`, revoked TEMP, and strict-applied the frozen patch twice. The second run skipped on its marker. The battery passed 115 of 115 on my clone. `close-22-frozen-r1.sh rv22opus` passed CR1–CR8. The tail invariants passed. I diffed the re-issued `assert_seal_role_invariants()` and `record_tenant_configuration_change()` against `tally`'s copies. I then probed as `tally_app` under `app.user_id`. The clone is dropped, and so is the copy of the patch I put in the container. I did not run `mutations-22.py`.

Each claim below is marked **[E]** (executed) or **[P]** (predicted).

---

## Blocking

### B1. The aging bucket edges can be written by the application, unvalidated and backdated. A closed period's aging is then neither valid nor reproducible.

The snapshot (S2) and CR7 rely on `receivables_aging_bucket_days_as_of(tenant, recorded_at)` returning the edges in force at the close. That function reads `tenant_configuration_history`. That table takes rows the application writes, and the validator on the tenant column has a hole. There are two paths:

**(a) The validator accepts an array that does not start at index 1. [E]**
`aging_bucket_days_valid('[0:1]={90,30}')` is true, and so is `'[0:1]={-5,30}'`. The reason: `p_days[1]` is the second element, and the loop compares only `i > 1`. Some arrays make the function return NULL, for example `'[-3:-1]={0,0,0}'`, because `p_days[1]` is NULL. A CHECK passes on NULL.

As a tenant admin through `tally_app`, I ran `UPDATE tenants SET receivables_aging_bucket_days = '[0:1]={90,30}'` and it was accepted. A close then wrote a permanent snapshot with `aging_bucket_days = {90,30}` and the aging line **`91-30` = 100.00** next to `0-90` = 50.00. That snapshot can never be corrected. `'[-2:0]={0,0,0}'` was also accepted.

**(b) Direct history inserts. [E]**
`tally_app` holds INSERT on `tenant_configuration_history`. `guard_tenant_configuration_history_source` only refuses `onboarding` and `trigger` as sources, so `manual` and `backfill` are open. `effective_from` is caller-chosen, and `new_value` is not validated for this key.

As an **operator**, in a committed transaction after the race script's January close, I inserted `('receivables_aging_bucket_days', '[1,2]', effective_from = January's recorded_at minus 1 ms, 'manual')`. CR7's own comparison then returns **false**. `receivables_aging_as_of(T, 2026-01-31, recorded_at)` now says `3+` = 57.00, while the snapshot says `0-30` = 7 and `61-90` = 50. A value of `'["abc"]'` makes the aging, and every later close, raise `invalid input syntax for type integer`.

This is memory `app-written-logs-are-not-guards`. The fact that a guard and a reproducibility claim stand on is a row the application writes with its own date.

**Fix:**
- Validator: add `array_lower(p_days, 1) = 1`, and wrap the whole expression in `coalesce(…, false)`.
- `receivables_aging_bucket_days_as_of`: validate the value it reads (raise if it is not valid) and say so.
- For this key, make the history written by the database only: refuse direct inserts, or require `effective_from = now()` (stamped), as -12's recorder does.
- Optionally, reproduction should read the snapshot's stored `aging_bucket_days`.
- Tests: add a battery check for the array-bounds case, a battery check for a direct backdated insert, and a mutation for each.

### B2. The recovery cap is keyed on the label, so recovering past the write-off is one type name away. W3 is half-built against its own spec. [E]

The spec says W3's cap is X2's: the sum of reversals against an entry never exceeds the entry. X1 defines a reversal as any row that names an entry.

`enforce_write_off_recovery` returns early unless `transaction_type = 'write_off_recovery'`. As `tally_app`, `INSERT … transaction_type 'adjustment', amount 500, reverses_ledger_entry_id = <the -100 write-off>` is accepted. `receivables_aging_as_of` then nets it into the write-off's tree exactly as it nets a recovery: the customer shows **400.00 open, aged from the write-off's date**.

This is memory `guard-the-act-not-the-label`. R8 defers the general rule to -23. But the act being capped here, money netted against a write-off, does not depend on the label.

**Fix (narrow):**
- Fire the guard for any row whose `reverses_ledger_entry_id` names a `write_off`.
- Require the opposite sign.
- Cap the sum over every row naming the write-off, not only `write_off_recovery` rows.
- Add R-checks and a mutation for "an adjustment names the write-off".

If Ryan keeps it deferred under R8, the patch header and W3's comment should stop saying "recoveries never exceed the write-off" without that qualification.

---

## Should fix

**S1. The close silently leaves out money that a superuser loaded with a future `created_at`. [E]**
`stamp_log_created_at` leaves a superuser's `created_at` alone. I loaded a row dated 2026-01-10 for 500 with `created_at = now() + 1 day`, then closed January. The snapshot shows `closing_balance 0`, `entry_count 0`. The ledger through January 31 holds 500, and that row is frozen inside the closed period forever.

The fix is a cheap check in the close: refuse if any row dated on or before `period_end` has `created_at > v_at`. The same rule could also be enforced at load time. CR7b's "now" leg would only catch this after the fact.

**S2. G1 asks for "a stated precedence", but the patch has only a count of key parts with ties raising at lookup (R7).**
A class-wide row and a territory-wide row are both accepted at insert. A residential line in that territory then cannot be exported at all (G6b is that case). This is a configuration the database accepts and the export then cannot use.

Either state an order of key parts (for example charge > class > territory > tax) so that equal counts resolve, or refuse at insert a row that would tie with an overlapping row. As drafted, G1 is half-done.

**S3. `assert_periods_guard_invariants()` checks less than it claims. [E]**
In one transaction I replaced the following. The invariant still passed:
- `account_ledger_recovery_lineage_check` with `CHECK (true)`;
- the type list with `CHECK (transaction_type <> 'write_off_recovery' OR true)`;
- I also dropped `accounting_periods_no_overlap`, `gl_account_mappings_no_overlap` and `accounting_periods_closed_stamp_check`.

The fix is to compare `pg_get_constraintdef` exactly, as the seal invariants already do for `adhoc_charges_billed_names_its_bill`, and to list the EXCLUDE constraints and the stamp CHECKs. This is memory `checks-narrower-than-their-claim`.

**S4. Test gaps. Each one is a mutation that survives the whole battery.**
- **[E]** `close_accounting_period` with `'Etc/GMT+12'` changed to `'Etc/GMT-14'`: 115 of 115 pass. C5 uses a period ending at the end of the current month, so the UTC-12 boundary is never tested. Add a period ending yesterday or today at UTC-12 (memory `test-the-boundary-not-the-formula`).
- **[E]** The close with every `AND l.created_at <= v_at` removed: 115 of 115 pass, and CR7 and CR7b still pass. No test puts a row dated in the period but recorded after the instant in front of a close.
- **[P]** The aging reading the live `customers.status` instead of the event as of `p_recorded_at` would pass W4, because W4 reads at `clock_timestamp()`. My attempt failed only because `tally_close` lacks the `status` column, not because a check caught it. Add a status read at an instant before C2's move-out.
- **[E] (holds, untested)** Two recoveries in a writable CTE, or in one multi-row INSERT, against the cap: the second sees the first and is refused. Add these as checks (memory `projection-checks-lag-in-one-statement`).
- I4 says "under row security and the canonical policy" but checks only the two RLS flags. I5 may cover the policy, but the label overclaims.
- W10 does not test array bounds (B1a).

**S5. An open period can never be corrected.**
A mistyped `period_end`, say 2036 for 2026, is permanent: periods are never edited or deleted, and the next period must chain after it. The tenant cannot close again until 2036, and its freeze stops at the last close. I suggest allowing a supervisor to delete or shorten the tenant's **latest, open** period. Nothing stands on it yet: no snapshot, and the head is still behind it.

---

## Answers to the brief

**1. Inventory and rulings.** P1–P3, S1 and S2, G1–G4, and W1–W4 are built.

The gaps:
- W3's cap counts only the label (B2).
- G1's precedence is a tie that raises (S2).
- S2's "edges read at close" stand on an unvalidated, application-dated row (B1).

P2's "rows dated where no period is defined are accepted" is narrowed by drafting call 1, which freezes history before the first period once that period closes. That call is reported in the decision log, so I accept it.

**2. Paths around the new rules.**

The freeze:
- **[E]** I found no path for money dated in a closed period through the ledger, payments or customer credits for `tally_app`, the owner, or the void.
- **[E]** `void_invoice` is the only function that writes money. It dates its reversal with `CURRENT_DATE`, and the UTC-12 rule keeps that date after `closed_through`.
- **[E]** FOR SHARE needs the `updated_at` UPDATE grant: revoking it gave `permission denied`.
- **[P]** At REPEATABLE READ or SERIALIZABLE, any money write whose snapshot is older than a close fails with 40001. This includes writes dated in later open periods. That is an availability cost, not a hole.
- **[P]** Writable CTEs and multi-row statements fire the row trigger for each row.
- **[E]** A superuser can choose `created_at` (S1).

Periods: **[E]** reopening, editing, deleting, being born closed, gaps, and closing out of order or early are all refused.

Snapshot and head:
- **[E]** No role writes a snapshot outside the close.
- **[E]** No one but `tally_close` moves the head, the owner included.
- **[P]** A superuser can `SET ROLE tally_close` and move the head forward with no period closed. That is superuser-only, so it is a note.

Recovery:
- **[E]** The wrong customer, the wrong sign and an over-cap amount are refused, including in a CTE and a multi-row INSERT.
- **[E]** Another label gets past the cap (B2).
- **[E]** The cap counts gross recoveries: a recovery that was later reversed still uses up the cap, so re-recovering after a bounced recovery is refused. This is conservative; noted.

GL:
- **[E]** In-place edits are refused.
- **[E]** A row starting, or a close taking effect, on or before `closed_through` is refused.
- **[E]** A lookup for a January date returns the same row now and at the close's instant, after a close and a successor row.

**3. The seal.**
- **[E]** `tally_close` is NOLOGIN, without BYPASSRLS, with no members either way, owns exactly the pinned definer, and the invariants pass.
- **[E]** The re-issued `assert_seal_role_invariants()` diffs against `tally`'s as exactly -21's body plus: the third role in `c_owns`, `c_grants` and the role loop; `tally_void`'s two head grants; and the new block that keeps the snapshot tables and the closed-through date unwritable. Nothing else changed.
- **[E]** `tally_void` needs both its new grants: FOR SHARE needs SELECT and UPDATE on at least one column.
- **[E]** I revoked each `tally_close` grant in turn and closed. Every grant is needed except **`customers.tenant_id`**: the close succeeded without it, because RLS policy expressions are not checked against column privileges. All three `users` columns are needed (`session_is_supervisor` names `u.tenant_id`). So "least" is off by that one column, which is a note.
- `account_ledger` is granted whole-table SELECT where nine columns would do; also a note.

**4. The snapshot.**
- **[E]** Opening, activity by type, closing = opening + activity, the entry count, and the aging lines with a customer count per bucket are right in my cases and the battery's.
- Nothing is passed in that could be computed. The unbilled figure is the core's estimate by D-2.
- What cannot be trusted as computed is the edges (B1) and rows with a future `created_at` (S1).

**5. The aging.** **[E]** The netting is correct:
- Chains: a charge, its reversal and a re-reversal net to the charge's date.
- A reversal dated before its original stands alone until the original's date. It shows as a credit in between: -80 on March 7 for a March 10 charge. That is consistent balance-forward, but D-3 readers may find it odd.
- A reversal of another customer's entry is not netted (W13).
- Cycles are impossible: `account_ledger_reversal_not_self_check` plus the FK plus append-only.

Newest-first allocation never gives a negative or zero amount. `least(net, b − (cum − net))` with `cum − net < b` and `net > 0` is always positive. The buckets sum to the balance, because the sum of positive nets is at least the balance whenever every row is in a tree.

The only wrong buckets come from bad edges (B1) and from uncapped reversals of other types (B2, and R8 generally).

RLS:
- **[E]** A tenant user asking for another tenant gets "no aging bucket setting … or not visible". The function is invoker-rights and the coordinates are required, with no live fallback.
- **[P]** A platform admin works.
- **[P]** Status `effective_at` is `clock_timestamp()` at the statement, so an event from a transaction still in flight can appear later "as of" an earlier instant. The snapshot does not store status, so this is a note under R4.

**6. The invariants.** See S3.

**7. The tests.** See S4.
- The 38 mutations I read look caught for the right reasons. M02 is caught by CR1's wait, which is the right leg. M16's +400 is far coarser than the boundary (S4).
- Missing mutations: the edges path (B1), the label path (B2), the close's `created_at` filter, and the as-of status.

**8. Residuals.**
- R8 is blocking as scoped for W3 (B2).
- R7 should be fixed (S2).
- R9 is fine: a close always reads at now().
- R1, R2, R4, R5 and R6 are acceptable as written.
- A note on R2: `payments.effective_date` is not frozen and stays mutable while a payment is pending. That is consistent with "only the ledger is the books", but worth one line in R2.

---

## Notes
- N1. `customers.tenant_id` SELECT for `tally_close` is unneeded [E]. `account_ledger` could be column-granted.
- N2. `accounting_period_snapshot_lines.tenant_id` is not tied to its snapshot's tenant (only the close writes it).
- N3. `unbilled_revenue` has no sign or range rule.
- N4. GL territory and tax keys are not checked to be places of the fitting kind.
- N5. Moving a pending payment to another tenant (platform admin only, because of RLS) checks only the new tenant's head.
- N6. The recovery cap ignores the reversal of a recovery (see answer 2).
