# v5.4.2-21 r1 — Opus review

**Verdict: not yet.** Three blocking items: B1 lets a bill line skip the arithmetic check, B2 lets an operator make itself a supervisor, and B3 lets an in-use label be deleted under another name. Everything else holds or is should-fix.

**Hashes checked first.** All four frozen files match the brief: patch `0900a47c…`, battery `da9e3481…`, labels `12cb39e6…`, mutations `d263033b…`.

**Clone.** `rv21opus`, cloned from `tally`. TEMP was revoked from PUBLIC, `tally_app` and `tally_core`. The frozen patch was applied strictly (`search_path=''`, `check_function_bodies=on`). The clone is dropped at the end.

**Reproduced (executed):**
- Strict apply, twice. The second run is skipped by its marker.
- `battery-21`: 103 PASS, no FAIL.
- `labels-21.sh` against `rv21opus`: LR1–LR5 PASS.

**Not reproduced:**
- `tests/ci.sh`. It uses fixed shared database names (`ci_*`), and another reviewer is working in the same cluster.
- `mutations-21.py`. The brief forbids running it.

Every repro below ran as `tally_app` under `app.user_id` unless it says otherwise. Fixtures were the battery's preamble, or my own committed rows in `rv21opus`.

---

## Blocking

### B1. A surcharge whose rate item cannot be read at the bill's coordinate needs no figures (A4 fails open) — executed

`invoice_line_arithmetic_gap` does:

```sql
v_per_unit := coalesce(v_calc IN ('per_unit_usage','tiered_usage'), false);
```

When `rate_item_as_of(item, period_end, now())` returns no row, `v_calc` is NULL and the line needs nothing. Two ways to get there, both executed with the battery's `issue()` helper, which runs only the arithmetic check:

- **P-A4x.** A per-unit item whose only version is effective from 2026-02-01. A January bill's surcharge line names it and carries no quantity, unit, rate or gas figures. Result: **PASS (issued)**.
- **P-A4y.** A surcharge line naming *tenant 2's* per-unit item on a tenant-1 bill.
  - `invoice_line_items.rate_item_id` is a single-column FK, so the line is accepted.
  - The check runs with invoker rights. Under RLS the item is invisible, so `v_calc` is NULL.
  - Result: **PASS (issued)**.
  - The same line issued by the owner would be refused, because the owner can see the item.

The sibling check fails open the same way, so nothing else catches the line (predicted, from the code). `line_item_carries_base()` also does `coalesce(v_calc IN ('percentage_of_bill','percentage_of_charges'), false)`. A surcharge whose item does not resolve is neither a percentage line (no bases needed) nor a per-unit line (no arithmetic needed). It carries an amount with no account of how it was reached.

This contradicts A4's own drafting rule: "a line that cannot be classified cannot be shown to need nothing; fail safe."

**Fix:** in the gap function, when `v_calc IS NULL`, return a gap: "rate item X has no version of this bill's tenant at (period_end, now())". Add battery rows for both repros, plus a mutation that restores the `coalesce`. Binding `invoice_line_items.rate_item_id` to the line's tenant would be a separate hardening.

### B2. Any session that can update `users` can bind a Cognito identity to an unbound supervisor, or reactivate one: self-promotion — executed

Write-once guards a binding *after* it is set. Nothing guards who sets it, or who reactivates a user, and U2 has now made `is_active` a security column. Repro, on committed fixtures in `rv21opus` inside a rolled-back transaction:

1. An **operator** session updates a new, unbound `tenant_admin` with `UPDATE users SET cognito_sub = 'operators-second-account'`. Accepted.
2. Under AC-43 the app then sets `app.user_id` from that sub, and `session_is_supervisor()` returns **true**.
3. The same operator reactivates a deactivated `tenant_admin` and binds it in one UPDATE. Accepted.
4. Binding an unbound service user to an arbitrary sub is also accepted (P-U).

Why this blocks:
- It is exactly what `enforce_tenant_admin_grant` (v5.4.2-13) refuses: "a session that could promote itself could approve its own charge." Binding an existing admin row reaches the same end without touching `role`.
- Every user is unbound until their first login, so the window is the whole onboarding of every admin.
- Write-once then locks the real person out, and only a superuser can repair it.

R1's accepted residual is a compromised app server. It does not cover an ordinary operator session, which the -13 guard already defends against.

**Fix**, a drafting call by the "guard the act" rule:
- A BEFORE UPDATE trigger, ENABLE ALWAYS, on `users`.
- It refuses a NULL→value `cognito_sub`, or `is_active` false→true, on a row whose role is `tenant_admin` or `platform_admin`, unless `session_is_supervisor()`. This mirrors `enforce_tenant_admin_grant`.
- Optionally, require a supervisor for any binding.
- Ask Ryan if the first-login binding path, which runs before `app.user_id` exists, needs a provisioning identity. That is a question for him, not a reason to leave the hole open.

### B3. An in-use label is renamed or re-pointed by UPDATE, which orphans its values exactly as a delete would — executed

The guard is BEFORE DELETE only. As `tally_app`, with label `acct_color` in use on a customer and the location type `kiosk` in use:

- `DELETE` of the field definition is refused ("is in use"), as designed.
- `UPDATE custom_field_definitions SET field_key = 'renamed'` is **accepted**. The customer still holds `acct_color`, which now has no definition.
- `UPDATE custom_location_types SET type_key = 'renamed_kiosk'` is **accepted**. The location is still `kiosk`, and 0 definitions of `kiosk` are left.
- `UPDATE … SET entity_type = 'service_orders'`, then `DELETE`, is **accepted**. The delete reads the new entity table and finds nothing.
  - `tenant_id` is re-pointable the same way. I predicted this but did not run it; RLS's WITH CHECK refuses it for a non-admin.

This is the "path around the rule" the brief asks for: the label stops existing for its key while the key is in use.

**Fix:** freeze `field_key`, `entity_type` and `tenant_id` on `custom_field_definitions`, and `type_key` and `tenant_id` on `custom_location_types`, as write-once. A label is archived, or deleted when unused, and a new one is added. The alternative is to run the same in-use check, with the same lock, on an UPDATE that changes them. Write-once is simpler and needs no lock. Add battery rows and a mutation.

---

## Should fix

### S1. The void's charge lookup is not bound to the bill's customer — executed

A charge planted by `tally_app` for customer **C2** (0.01, `reference_type='invoice'`, `reference_id` = C1's posted bill) was the only charge. `void_invoice()` named it. The result was a −30.00 reversal on **C1** whose `reverses_ledger_entry_id` points at C2's entry.

**Fix:** add `AND l.customer_id = v_invoice.customer_id` to Step 2.5. That keeps "names its charge" true to the bill. The amount mismatch is R1's and accepted.

**Test gaps:**
- Nothing tests two charge entries (the `ORDER BY created_at, id` tie-break).
- Nothing tests the tenant filter when a platform admin voids while another tenant has planted a charge with the same `reference_id`. Removing `l.tenant_id = v_invoice.tenant_id` would pass every test (predicted).

### S2. The void-reversal act can be written under another transaction type — executed

`INSERT account_ledger (transaction_type 'adjustment', reference_type 'invoice_void', amount −30)` with no `reverses_ledger_entry_id` is accepted. G2 is keyed on the caller-chosen label `void_reversal` (memory: guard the act, not the label).

**Fix:** `CHECK ((reference_type = 'invoice_void') = (transaction_type = 'void_reversal'))`, or one-directional if historic rows need it. This narrows R2 for free.

### S3. The lock note understates what SHARE costs — executed

- **Deadlock with different labels.** A and B each UPDATE a different customer, then each DELETE a *different* customers label. Result: `ERROR: deadlock detected … waits for ShareLock on relation … LOCK TABLE customers IN SHARE MODE`.
  - The header and L3 say a deadlock needs "the same label".
  - The true condition: any two transactions that have written the entity table and then delete a label of that entity. Two label deletes that then write the entity table deadlock the same way (predicted).
- **Writers queue behind a waiting delete, not only an uncommitted one.**
  - A held an uncommitted customers UPDATE for 4 s.
  - B's label delete queued for SHARE.
  - C, an unrelated customers UPDATE started 1 s after B, waited 2.0 s and finished 7 ms after B ended.
  - So every write to `customers`, `invoices` or `payments` stalls for as long as the longest open writer, plus the delete's own transaction.
- The in-use check is a scan of the entity table for the tenant while SHARE is held (predicted; no index on `metadata ?`). The outage grows with table size.

**Fix:**
- `PERFORM set_config('lock_timeout', '<n>s', true)` before the LOCK in the guard, so a busy table fails the delete fast (55P03) instead of stalling every writer.
- Correct the header and L3 text.
- L4's RLS reasoning is right for a platform admin, who sees every row and is filtered by `OLD.tenant_id`, and for a caller with no user, whose RLS hides the label so it deletes nothing (predicted from the policies; confirmed in part by L4 and L1f).

### S4. `retired_by` names any user, of any tenant — executed

The retirement accepted `retired_by` = tenant 2's user on a tenant-1 dependency. The FK is single-column and nothing ties it to the caller.

**Fix:** stamp `retired_by := current_setting('app.user_id', true)::uuid` when present, as `retired_at` is stamped. Or check that the user is visible and of the row's tenant.

### S5. Narrower than claimed, and missing tests

- **Invariants.** `assert_no_hard_delete_invariants()` does not check the label tables' `no_truncate` (L5). Neither invariant checks that `enforce_no_hard_delete()` or `enforce_custom_label_unused()` still refuse: a replaced body passes. The same pattern exists in the seal invariant.
- **The brief's known gaps.** issued→issued and the lines' FOR SHARE have no mutation.
- **Not in the brief's list:** B1–B3, S1, S2.
- **LR2** proves the writer waited. It does not assert the final state: a customer holding `k_two` with its definition gone, which is by design.
- **battery-15 C8** now proves the missing grant, not the -15 "never deleted" guard. Run it once as the owner too, so the guard keeps a check.

---

## Notes

- **N1. Posted means exactly `first_issued_at`, for non-superusers.**
  - Executed: a born-`pending` INSERT as `tally_app` is accepted at statement time with the stamp forced to NULL. It is then refused at commit by `enforce_invoice_has_snapshot`, and a snapshot cannot be written for an issued bill.
  - The stamp is database-written and write-once (`enforce_invoice_first_issued`, from the code).
  - issued→held/draft is refused by `enforce_invoice_immutable`.
  - So a bill cannot be posted without the stamp, or carry it without being posted. A superuser's history load is the only exception, by precedent.
- **N2. The gate is right.** Issuance only; it skips a discard (UPDATE to void) and issued→issued. Lines are frozen the moment the status is issued (`enforce_invoice_line_items_immutable` reads the in-transaction status), so no line can be added or changed after an immediate check.
  - An INSERT born `void` (a superuser load) is checked. This is consistent with the siblings.
- **N3. The coordinate.** `(period_end, now())` matches the sibling's documented choice: current knowledge, not the snapshot's caller-supplied pair. A correction priced at an elected rate date can classify an item differently from its pricing; that is acceptable.
- **N4.** `enforce_payment_immutable` differs from the live version by exactly the one added line (executed diff), and its config is unchanged.
- **N5. Retention.**
  - No definer function deletes from the 16 (catalog query, executed).
  - All the cascades into them come from tables `tally_app` cannot delete: `tenants`, `customers`, `read_cycle_instances`, `ai_audit_log`, `ai_sessions`. The ALWAYS trigger refuses them for the owner too (predicted; battery D1 covers TRUNCATE … CASCADE).
  - Five of the 16 have no lifecycle column: `jurisdictions`, `deposit_utility_categories`, `pga_monitoring_settings`, `tenant_sequences`, `service_location_acquisitions`. A wrong row there can only be edited. That is per the decision.
- **N6. Residuals R1–R5:** none blocks alone. R2 is wider than stated until S2 lands, and R1 compounds with S1.
- **N7. U2.** The other helper that reads `app.user_id`, `session_is_supervisor()`, goes through both RLS helpers, so an inactive user fails it too. No policy reads `app.*` directly (catalog, executed).
