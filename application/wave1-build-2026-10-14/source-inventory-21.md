# v5.4.2-21 source inventory: wave 1 built (CI-014, CI-016, CI-017), the void's reversal, the identity follow-ups, the -20 notes

**Authority:** Ryan, 2026-10-14: "ok go ahead with -21", after these decisions (all in `application/DECISION-LOG.md`, 2026-10-14):
- CI-014 (17 tables, as listed; see D0), CI-016, CI-017;
- R1, Cognito identity;
- the void's reversal ("yes, go with the default");
- the rate-dependency retirement (drafting, reported).

**Sources:** the decision-log entries (DL); the live catalog of the -20 build (`tally`, tu.sql md5 `e13f0d72`); the -20 residuals and review notes (`tests/v5.4.2-20/review/opus-r3.md` S1, the HANDOFF notes).

Every requirement below is a row of `tests/v5.4.2-21/battery-21.sql`, a race case, or an invariant the CI runs.

## D: no hard delete (CI-014)

- **D0.** The decision says 17 tables but lists 16. The live catalog agrees with the list: `tally_app` holds DELETE on 28 tables = 16 + the 6 bill tables + the 6 deletable. The list is the authority.
- **D1.** These 16 tables get `no_hard_delete` (BEFORE DELETE, row) and `no_truncate` (BEFORE TRUNCATE, statement), both on `enforce_no_hard_delete()` and both ENABLE ALWAYS:
  - `ai_sessions`, `ai_suggestions`, `ai_tool_calls`;
  - `billing_cycles`, `read_routes`, `jurisdictions`, `communities`, `deposit_utility_categories`;
  - `bill_messages`, `auto_pay_settings`, `tenant_sequences`;
  - `read_cycle_meters`, `alerts`, `service_location_acquisitions`;
  - `rate_item_dependencies`, `pga_monitoring_settings`.
  Existing `no_truncate` triggers are replaced in place.
- **D2.** `tally_app` loses DELETE and TRUNCATE on the 16.
- **D3.** The 6 bill tables and the 4 import/housekeeping tables are untouched (DL CI-014).
- **D5 (r2, F10).** `assert_wave1_guard_invariants()` checks the arithmetic, born-unvoided, Cognito write-once, supervisor and dependency guards, by exact definition and ENABLE ALWAYS. The retention invariant also checks the labels' key freeze and `no_truncate`.
- **D4.** An invariant (`assert_no_hard_delete_invariants()`, patch tail and CI) fails if:
  - any of the 16 lacks either trigger, or has one not ENABLE ALWAYS;
  - `tally_app` holds DELETE on a public table outside the 12 deletable.

## L: the custom labels are refused while in use (CI-014)

- **L1.** `custom_field_definitions`: a DELETE is refused while a row of the named entity's table, same tenant, has the label's key in `metadata`.
  - `entity_type` names the table.
  - `meter_readings` and `billing_runs` have no `metadata` column, so their labels hold no values and are deletable.
- **L2.** `custom_location_types`: a DELETE is refused while a `service_locations` row of the same tenant has `location_type = type_key`.
- **L3.** Race (memory `count-guards-need-lock-handshake`): the guard takes `LOCK TABLE <entity> IN SHARE MODE` before it looks. A writer in flight finishes first; a new writer waits for the delete's commit.
  - The guard refuses anything but READ COMMITTED: an older snapshot would not see a writer that committed while it waited (the void's precedent).
  - No writer-side code. The cost: writes to that entity table wait while a label delete is uncommitted, so label deletes are rare admin acts.
  - **Deadlock:** a transaction that writes the entity table and then deletes the same label can deadlock with another delete of that label; PostgreSQL aborts one (40P01).
- **L4.** The guard is invoker-rights, so RLS applies. A caller sees only its tenant's rows, and RLS hides another tenant's label from its DELETE in the first place.
- **L5.** `no_truncate` on both tables; `tally_app` loses TRUNCATE if held. Both guards ENABLE ALWAYS.
- **L6 (r2, F3).** A label's key is write-once for every role: `tenant_id`, `entity_type` and `field_key` on definitions, `tenant_id` and `type_key` on location types. A rename is a new label plus an archived old one.
- **L7 (r2, F8).** The guard waits at most 5 s for its lock (55P03). It is a deletion-time check, not referential integrity: a write after the delete may still use the key.

## K: rate dependencies are retired, not deleted (CI-014 drafting, -19 R4)

- **K1.** New columns: `retired_at timestamptz`, `retired_by uuid` (FK `users`), `retired_reason text`.
  - CHECK: `retired_at` and `retired_reason` are set together.
  - CHECK: the reason holds at least one `[[:alnum:]]` (memory `blank-checks-whitelist-alnum`).
- **K2.** An insert is born live: all three are NULL.
- **K3.** An UPDATE may do one thing only: retire a live dependency.
  - The database stamps `retired_at := now()` and `retired_by` from `app.user_id` (r2, F9); the caller's values are ignored.
  - Every other column is write-once, and a retirement is permanent.
- **K4.** The UNIQUE `(rate_schedule_id, dependent_rate_item_id, base_rate_item_id)` becomes a unique index on live rows only, so a retired edge can be re-added.
- **K5.** The cycle walk counts live dependencies only. A retirement skips the cycle check but still bumps the schedule mutex (lock order unchanged).

## A: bill lines carry their arithmetic at issue (CI-016)

- **A1.** A new deferred constraint trigger, `enforce_invoice_line_arithmetic`, on `invoices`, gated exactly as its two siblings:
  - it runs only on the move into an issued status;
  - it skips an UPDATE from an issued status;
  - it skips a void (a discard).
  - It takes the lines FOR SHARE.
- **A2.** `usage_charge` requires `usage_quantity`, `usage_unit` (≥1 alnum) and `rate`.
  - When `service_type = 'gas'`, it also requires `gas_meter_factor`, `gas_ccf_used`, `gas_therms_billed` and `gas_commodity_rate`.
- **A3.** `base_charge` requires `rate`.
  - `coverage_start`, `coverage_end`, `days_covered`, `days_in_period` and `partial_period_policy_applied` are all set or all NULL. NULL means the full period.
- **A4.** `surcharge` must name its `rate_item_id`, and the item must have a version visible at the bill's coordinate (drafting: a line that cannot be classified cannot be shown to need nothing; fail safe; r2, F1).
  - If that version's `calculation_type` is `per_unit_usage` or `tiered_usage`, the line needs `usage_quantity`, `usage_unit` and `rate`. On a gas line it also needs the meter factor, Ccf and therms. The commodity rate is the usage line's, not the rider's (r2, F11).
- **A4b (r2, F2).** The coordinate is the bill's calculation snapshot's `(valid_at, recorded_at)`, which has been validated and frozen since -10. A correction's coordinate may be an elected rate date. With no snapshot, the snapshot check refuses the issuance.
- **A5.** Every other kind needs nothing new (DL).
- **A6.** Drafting: on a gas usage line, `rate` and `gas_commodity_rate` are two figures, both required, never required equal (memory `two-fields-both-the-money`). The check verifies presence, not the product (memory `schema-represents-core-evaluates`).

## G: lineage (CI-017)

- **G1.** Correction invoice: `CHECK (invoice_type <> 'correction' OR replaces_invoice_id IS NOT NULL)`, at insert.
  - "The replaced bill is void" is already refused at issue by `calculation_snapshot_coordinate_violation(…, true)`, along with "it was issued". The battery proves it; no duplicate guard.
- **G2.** Ledger: `CHECK (transaction_type <> 'void_reversal' OR (reverses_ledger_entry_id IS NOT NULL AND reversal_reason ~ '[[:alnum:]]'))`.
- **G2b (r2, F6, F7).** `reference_type = 'invoice_void'` if and only if `transaction_type = 'void_reversal'`; an entry is reversed by a void at most once (a partial UNIQUE index).
- **G3.** The ledger's self-FK becomes `(reverses_ledger_entry_id, tenant_id) → account_ledger(id, tenant_id)`. A reversal of another tenant's row is refused; the FK bypasses RLS, so the pair is the check.
- **G4.** Refund: a new column, `payments.refunds_customer_credit_id`.
  - FK `(refunds_customer_credit_id, tenant_id, customer_id) → customer_credits(id, tenant_id, customer_id)`, with a new UNIQUE on `customer_credits` for its target.
  - CHECK: `payment_method = 'refund'` ⇒ exactly one of `refunds_payment_id` and `refunds_customer_credit_id`.
  - `payments_refund_is_refund_check` is extended: either link ⇒ method `refund` and `amount < 0`.
  - The new column is frozen once posted (`enforce_payment_immutable`).
- **G5.** `nsf_original_payment_id` stays optional (DL).
- **G6.** -20 R8: an `adhoc_charges` INSERT with `voided_from_invoice_id` set is refused, except for a superuser history load (the `first_issued_at` precedent).
- **G7.** Partial indexes on every lineage column: `invoices.replaces_invoice_id`, `account_ledger.reverses_ledger_entry_id`, `payments.refunds_payment_id`, `payments.nsf_original_payment_id`, `payments.refunds_customer_credit_id`.

## V: the void's reversal (DL CI-017 / void_invoice)

- **V1.** A posted bill (`first_issued_at` set): `void_invoice()` finds the bill's charge entry: the bill's tenant and customer (r2, F5), `reference_type = 'invoice'`, `reference_id` = the bill, `transaction_type = 'charge'`, the earliest. If none exists it refuses (P0002) before writing anything, and the reversal names the entry it finds.
- **V2.** A never-posted bill (voided from `held`): no ledger entry. The payload's `ledger_entry_id`, `reverses_ledger_entry_id` and `reversal_amount` are NULL, and so is the event's `reversal_amount`.
- **V3.** Unchanged: the owner (`tally_void`), the grants, the READ COMMITTED pin, the lock order. `assert_seal_role_invariants()` still passes.
- **V4.** Residual: the reversal's amount stays `-(amount_due)`, not the named charge's amount. A bill with several charge entries reverses as one (memory `two-fields-both-the-money`; the core owns posting).

## U: identity (DL R1)

- **U1.** `users.cognito_sub text`, unique.
  - Format: `^[0-9A-Za-z_-]{1,128}$`.
  - Nullable: service users (AC-43) have none.
  - Write-once: once set, it never changes or clears (trigger, ENABLE ALWAYS).
- **U3 (r2, F4).** For `tally_app`, binding a Cognito identity (insert or update) and changing `is_active` either way require `session_is_supervisor()`. A user is bound when a supervisor provisions it. The owner (a superuser load or repair) stands aside, and may also repair a binding (F13).
- **U2.** `get_user_tenant_id()` and `is_platform_admin()` require `is_active`. A deactivated user's `app.user_id` sees no tenant row.
  - Same signatures, owners and grants; still SECURITY DEFINER, pinned to `''`.

## N: the -20 notes

- **N1.** `REVOKE TEMP ON DATABASE … FROM PUBLIC` via `EXECUTE format('… %I …', current_database())`, so -21 carries no psql variable. The -20 line already in tu.sql is mirrored and append-only; whether to replace it is Ryan's call at mirror time.
- **N2.** The PUBLIC clause's message and comment say "relation" (Opus r3 S1).
- **N3.** A header comment on `assert_seal_role_invariants()`: its trigger-definition strings are PostgreSQL 16's `pg_get_triggerdef` rendering, so re-capture them on a major upgrade.

## T: the tests

- **T1.** `battery-21.sql` runs a row per requirement above, as `tally_app` where the requirement is the app's.
  - Negative cases use SAVEPOINTs (memory `test-fixture-required-columns`).
- **T2.** `races/labels-21.sh`: L3, a label delete against a concurrent entity write, both orders and RR refused. Also the dependency retire against the cycle mutex.
- **T3.** `mutations-21.py`: each new guard and CHECK removed in turn is caught at its named check.
- **T4.** Older batteries that void a posted bill without a charge entry must plant one. Batteries -10, -11, -19 and -20, and the -20 races, are adjusted where they fail, each change named.
- **T5.** `ci.sh` gains -21 in PENDING (a column marker) and the new invariant.
