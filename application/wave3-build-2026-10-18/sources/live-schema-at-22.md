# Wave 3 (disputes and collections decision records): live schema inventory

Source: live catalog of `tally-pg` / db `tally` (user `tally`), which is at **v5.4.2-22** (verified: no
`customer_credit_approvals`, no `invoice_line_items.regulatory_class` — so -23 is NOT applied there), cross-checked
against `sql/tu.sql` (42,310 lines). Read-only; nothing written.

Line-number caution: tu.sql is a pg_dump base (lines ~1–11,500) followed by appended patches. A base `CREATE TABLE`
may be changed later by a patch `ALTER`; the catalog below is the live, post-patch truth. Where a function was
re-created several times, the **last** `CREATE OR REPLACE` line is the live body.

Common to every tenant table below unless noted: RLS enabled + FORCED, one policy `tenant_isolation` FOR ALL TO public
`USING (is_platform_admin() OR tenant_id = get_user_tenant_id())` with no WITH CHECK (so USING doubles as the check).
`no_hard_delete` / `no_truncate` triggers = `enforce_no_hard_delete()` (tu.sql 13250), ENABLE ALWAYS.

---

## dunning_events  (tu.sql 2952; append-only since -19 at 37354–37373)

Columns: `id uuid NN =uuid_generate_v4()`, `tenant_id uuid NN`, `invoice_id uuid NN`, `customer_id uuid NN`,
`event_type text NN`, `event_date timestamptz NN =now()` (caller-settable), `triggered_by uuid`,
`triggered_automatically bool NN =false`, `amount_related numeric(12,2)`, `scheduled_date date`,
`previous_stage text`, `new_stage text`, `notes text`, `metadata jsonb NN ='{}'`, `created_at timestamptz NN =now()`.

CHECK `event_type IN (reminder_sent, late_fee_applied, shutoff_notice_sent, shutoff_scheduled, disconnected,
reconnected, payment_plan_created, payment_plan_broken, sent_to_collections, written_off, resolved)` (2968).
No CHECK on previous_stage/new_stage vocabulary, none tying event_type to new_stage, none on amount sign.

FKs: all **single-column** — `customer_id → customers(id)`, `invoice_id → invoices(id)` (re-added without CASCADE at
37371), `tenant_id → tenants ON DELETE CASCADE`, `triggered_by → users`. Nothing binds the invoice's tenant or customer
to the row's tenant_id/customer_id (no composite FK, no trigger).

Indexes: by customer/invoice/tenant/type on event_date DESC; partial `idx_dunning_events_scheduled` on
`shutoff_scheduled`.

Triggers (all ALWAYS): `a_stamp_created_at` → `stamp_log_created_at()` (37336: created_at := now() unless superuser);
`append_only` → `enforce_append_only()` (17849); `no_hard_delete`, `no_truncate`.

tally_app: **INSERT, SELECT** (UPDATE/DELETE/TRUNCATE revoked from tally_app and tally_core at 37362).
Comment (37364): "Collections steps per invoice … append-only … a correction is a new event."

## service_orders  (tu.sql 4484)

Columns: `id`, `tenant_id NN`, `order_number text NN`, `order_type text NN`, `status text NN ='open'`,
`priority text NN ='normal'`, `customer_id`, `location_id`, `meter_id`, `description text NN`, `completion_notes`,
`external_order_id`, `external_system`, `requested_date date`, `scheduled_date date`, `dispatched_at`, `started_at`,
`completed_at` (field work finished), `billing_applied_at`, `assigned_to text`, `cancelled_at`, `cancelled_by`,
`cancellation_reason`, `parent_order_id`, `triggered_adhoc_charge_ids uuid[]`, `triggered_reading_ids uuid[]`,
`triggered_new_meter_id`, `triggered_replaced_meter_id`, `created_by_ai bool NN =false`, `ai_audit_id`,
`created_by_suggestion_id`, `billing_action_suggestion_id`, `metadata jsonb NN`, `created_at NN`, `updated_at NN`.

CHECKs: `order_type IN (new_connect, disconnect, reconnect, transfer, meter_install, meter_replace, meter_change_out,
meter_test, meter_reread, meter_test_failed_replace, final_read, leak_check, pressure_test, backflow_test, inspection,
tamper_response, damage_repair, customer_complaint, seasonal_turn_on, seasonal_turn_off, adjustment, other)`;
`status IN (open, scheduled, dispatched, in_progress, on_hold, awaiting_billing_action, completed, requires_followup,
cancelled, superseded)`; `priority IN (low, normal, high, emergency)`; disconnect/reconnect/new_connect/transfer need
customer_id AND location_id (`service_orders_check`); meter_* types need meter_id; final_read needs all three;
`ai_audit_required_check` (37376).

FKs: single-column to customers, service_locations, meters, users, ai_suggestions, self (parent); composite
`(ai_audit_id, tenant_id) → ai_audit_log` (37387). UNIQUE `(id, tenant_id)`, `(tenant_id, order_number)`.
Referenced (composite) by meter_correction_cases, meter_tests, read_validation_exceptions.field_order_id.

Triggers: `service_order_parent_cycle` (check_service_order_parent_cycle, 12409; not ALWAYS), `set_updated_at`;
ALWAYS: `enforce_ai_provenance_write_once` (37395: created_by_ai / ai_audit_id write-once), `no_hard_delete`,
`no_truncate`. **No status-transition guard, no stamping of completed_at, no field-verification columns.**

tally_app: INSERT, SELECT, **UPDATE** (whole row).

## invoices  (tu.sql 1633)

Collections-relevant columns: `status text NN ='draft'`, `due_date date NN`, `amount_due numeric(12,2) NN =0`,
`amount_paid numeric(12,2) NN =0`, `balance numeric(12,2) NN =0` (**both dropped by -23**),
`late_fee_assessed bool NN =false`, `late_fee_amount numeric(12,2) =0` (nullable), `dunning_stage text NN ='current'`,
`write_off_reason/date/approved_by`, `held_at timestamptz`, `held_by uuid`, `hold_reason text`, `voided_*`,
`first_issued_at`, `sent_at`, `delivery_*`. **No `dispute_*` columns.**

CHECKs: `status IN (draft, pending, held, sent, paid, partial, overdue, void, write_off)`;
`dunning_stage IN (current, reminder_sent, late_fee_assessed, shutoff_warning, shutoff_scheduled, disconnected,
payment_plan, collections, resolved, written_off)` (1690; comment 1736 describes the progression); no CHECK on
late_fee_amount sign or its pairing with late_fee_assessed.

**`held` is a pre-issue state, not a dispute hold.** `is_invoice_issued()` (13300) = status NOT IN (draft, held).
`enforce_invoice_immutable()` (live body 38574) forbids moving an issued bill back to draft/held, freezes billed
content (amount_due, due_date, totals, etc.) but **leaves status (among issued values), dunning_stage,
late_fee_assessed, late_fee_amount, amount_paid, balance, write_off_* freely app-writable** after issue.
`enforce_invoice_hold_metadata()` (177; not ALWAYS): entering held needs hold_reason, stamps held_at if null; leaving
held clears all three. `enforce_invoice_predelivery_gate()` (17624): blocks pending/sent while an open
`invoice_exceptions` row has blocks_delivery.

Other triggers: `a_enforce_invoice_first_issued` (20610), `a_enforce_invoice_snapshot_inputs`,
`b_enforce_invoice_date_rule_membership`, `enforce_invoice_has_snapshot`, `enforce_invoice_image_hash`,
`enforce_invoice_line_arithmetic`, `enforce_invoice_surcharge_lines_and_bases`, `no_truncate` (ALWAYS);
`dry_run_no_invoices`, `reversal_chain_depth`, `set_updated_at`, `trg_enforce_invoice_hold_metadata` (origin).
Void is only via `void_invoice()` as `tally_void` (live 39859).

tally_app: INSERT, SELECT, UPDATE, DELETE (DELETE only for draft, by the trigger).

**-23 changes here:** drops `amount_paid`, `balance` (-23 file l.1262); adds UNIQUE `(id, tenant_id, customer_id)`
(l.937); `invoice_line_items.regulatory_class NN` (l.929); positions via `invoice_position_as_of(id, on, recorded_at)`
and `invoice_line_position_as_of` (l.1193/1215, both coordinates required); invoice_applications per bill line,
add-only (l.945–1006, `enforce_invoice_application` l.1987). Residual R3: invoice status paid/partial stays
app-written and may disagree with the position. Wave 3's "disputed amount" and "late fee base" must read positions,
not the dropped counters.

## meter_readings dispute_* (tu.sql 3481; dispute cols 3532–3537)

`dispute_reason text`, `dispute_raised_by uuid → users`, `dispute_raised_at timestamptz`, `dispute_resolved_by uuid →
users`, `dispute_resolved_at timestamptz`, `dispute_resolution_notes text` — all nullable, **no CHECK pairing, no DB
stamp, overwritable**. `status IN (active, disputed, under_review, replaced, voided)`; `reading_purpose` includes
`dispute_recheck`; index `idx_readings_disputed` (7727). On a consumed (billing_period_locked) read the whitelist in
`enforce_reading_validation_workflow()` (live 38317; whitelist 38430–38444) leaves dispute_*, status, notes,
follow-up fields editable — i.e. dispute state lives as mutable columns, not records. tally_app: INSERT, SELECT, UPDATE.
Other triggers: a_enforce_attach_to_live_invoice, a_enforce_reading_born_unconsumed, dry_run_no_read_locks,
populate_* (2), z_enforce_read_exception_gate (17205), z_raise_consecutive_estimate_exception (17334).

## customers  (tu.sql 2461)

Relevant: `status text NN ='active'` CHECK `IN (active, inactive, final_billed, collections, closed)`;
`status_reason`, `status_changed_at`, `status_changed_by`; `do_not_disconnect bool NN =false`;
`billing_hold bool NN =false`, `billing_hold_reason`, `billing_hold_set_at`, `billing_hold_set_by`;
`landlord_responsible`, `landlord_customer_id`; old `disconnect_protection_*` columns dropped (11902–11906).

Triggers (ALWAYS unless noted): `a_enforce_customer_lifecycle` (17783: a status change needs status_reason; closed
reopens only to active; no close while deposit held; writes `customer_state_events` itself and nulls the reason),
`b_enforce_customer_deposit_projection` (18651), `z_log_customer_attribute_changes` (live 19066: DB writes
`customer_attribute_history` for billing_hold, do_not_disconnect, etc.), `z_log_customer_state_event` (17834),
no_hard_delete/no_truncate; origin-only: `trg_enforce_billing_hold_metadata` (144: hold needs reason, stamps set_at;
clearing nulls all), `landlord_customer_cycle`, `set_updated_at`.

**`do_not_disconnect` is a projection with no guard**: maintained by `recompute_do_not_disconnect()` (11858, AFTER
trigger on enrollments, not ALWAYS) but tally_app holds table UPDATE and nothing refuses a direct write. Its history
is readable via `customer_attribute_as_of(customer, 'do_not_disconnect', at)` (17894).
tally_app: INSERT, SELECT, UPDATE.

customer_state_events (17743): `from_status`, `to_status NN`, `effective_at NN`, `reason_code NN` (non-blank),
`changed_by`, `source IN (operator, system, initial, backfill)`, `seq bigint NN`, `created_at`. ALWAYS triggers
`a_enforce_event_written_by_db` (19141), `append_only`, `no_truncate`. tally_app INSERT, SELECT.
`customer_status_as_of(customer, at)` (17773).

## program_types  (tu.sql 11723; seed 11731–11741)

Platform-global, **no tenant_id, no RLS**; tally_app SELECT only. Columns: `code text PK`, `display_name NN`,
`is_disconnect_protective bool NN`, `description`, `requires_attestation bool NN =false` (-19, CI-062). No triggers.
Rows (code | protective | attestation):
agency_pledge f f; **bankruptcy_automatic_stay t f** (event-terminated, D8-2); budget_billing f f;
elderly_disabled t f; medical_certificate t **t** (Texas: composes with active payment_arrangement, CI-081);
military_deployment_scra t f; other t f; payment_arrangement t f (one active per account, D8-3);
**pending_dispute t f** ("disconnect suspended while pending. Texas-v1 workflow ships."); **regulatory_moratorium t f**
("Weather or commission-ordered … Texas EWE per CI-080 is self-executing at/below 32F, county-level"); third_party_notification f f.

Note: protection is a single boolean per type; no per-step scope (notice vs late fee vs disconnect), no amount scope
(pending_dispute protects the whole account, not the disputed amount), no jurisdiction scope, no link to the
dispute or invoice.

## customer_program_enrollments  (tu.sql 11753)

Columns: `id`, `tenant_id NN`, `customer_id NN`, `program_type NN → program_types`, `effective_start_date date NN`,
`effective_end_date date` (NULL for event-terminated), `expiry_type NN ='calendar'` (calendar|event),
`status NN ='pending_application'` (pending_application|active|expired|breached|canceled|superseded),
`attestation_artifact_url`, `attestation_received_at`, `attestation_verified_at`, `attestation_verified_by`,
`enrollment_data jsonb NN ='{}'` (object), `notes`, `enrolled_by`, `supersedes_enrollment_id → self`, `created_at`,
`updated_at`. UNIQUE partial `(tenant_id, customer_id, program_type) WHERE status='active'`. FKs single-column.

Triggers: `enrollment_customer_immutable` (11809), `enrollment_recompute_dnd` (11858), `enrollment_supersedes_chain`
(11827), `set_updated_at` (all origin-only, not ALWAYS); ALWAYS `a_enforce_enrollment_attestation` (37632),
no_hard_delete, no_truncate. **Mutable rows (dates, status) with no history and no as-of helper**; tally_app INSERT,
SELECT, UPDATE.

## adhoc_charges late_fee  (tu.sql 1432)

`charge_type` CHECK includes `late_fee` (also penalty, reconnection_fee, disconnection_fee, returned_payment_fee);
`regulatory_class text NN IN (regulated, unregulated)`; `status IN (pending, billed, void, waived,
void_pending_rebill)`; `triggered_by_invoice_id`, `triggered_by_payment_id`, `triggered_by_reading_id` (link a late
fee to its bill, single-column FK); `source IN (manual, service_order, ai_suggestion, import, system_generated,
payment_reversal)`; `billed_names_its_bill` CHECK. Triggers (ALWAYS): a_enforce_adhoc_charge_born_unvoided (39824),
a_enforce_attach_to_live_invoice (38703), enforce_adhoc_charge_approval_capture, enforce_adhoc_charge_immutable (live
38486), enforce_ai_provenance_write_once, no_hard_delete/no_truncate. tally_app INSERT, SELECT, UPDATE.
Nothing records the base a late fee was computed on, nor excludes a disputed amount.
**-23:** identity incl. amount/type/class fixed from insert; void/waive need a reason (-23 l.1619–1716).

## account_ledger late_fee  (tu.sql 1409)

`transaction_type` CHECK includes `late_fee` (and nsf, write_off, write_off_recovery, adjustment, void_reversal …);
`reference_type IN (invoice, payment, customer_credit, adhoc_charge, invoice_application, billing_run,
escheatment_event, manual, invoice_void, refund, deposit)`; `reverses_ledger_entry_id`, `reversal_reason`.
Triggers (ALWAYS): a_enforce_accounting_freeze (40890), a_stamp_created_at, enforce_account_ledger_immutable (13490),
enforce_ledger_lineage_acyclic (41135), enforce_write_off_recovery (40972), no_hard_delete/no_truncate; origin
dry_run_no_ledger. tally_app INSERT, SELECT. `account_balance_as_of(customer, on, recorded_at)` (37659; NULL
coordinate raises). **-23:** late_fee is not a reversal type; reversal rules X1/X2 generalised (`enforce_ledger_reversal`
-23 l.358–570); a late-fee waiver would be an `adjustment` naming the late_fee entry.

## Exception queues

- **anomalies** (2116; -19 changes 37428+): `anomaly_type` (37 values; none for dispute/collections/disconnect except
  `disconnect_protection_expiring`), `entity_type` (no service_order, no dunning_event), `status`, `dedup_key text NN`
  with UNIQUE `(tenant_id, dedup_key)` (CI-128 idempotent detection), recurrence_count, first/last_detected_at.
  Triggers: ALWAYS `a_enforce_anomaly_record` (37437), no_hard_delete/no_truncate. tally_app INSERT, SELECT, UPDATE.
- **invoice_exceptions** (17426): per invoice; `criterion` (14 values, none dispute/collections), `queue IN
  (batch_hold, billing_analyst, senior_analyst, csr, field_ops, informational)`, `blocks_delivery`,
  resolution-consistency CHECK, routing_reason required. Triggers ALWAYS a_enforce_invoice_exception (17499),
  no_hard_delete (own fn), no_truncate, z_log_invoice_exception_event (17596). Pre-delivery only (rejects already
  delivered invoices, 17525). tally_app INSERT, SELECT, UPDATE.
- **read_validation_exceptions** (17063): `field_order_id → service_orders (composite)`, dispositions incl.
  `field_order_dispatched`; enforce_read_validation_exception (17135). tally_app INSERT, SELECT, UPDATE.
- **alerts** (2070): types include `account_past_due`, `disconnect_warning`, `dunning_action_due`,
  `disconnect_protection_expiring`. No enforcement trigger beyond no_hard_delete. tally_app INSERT, SELECT, UPDATE.
- **customer_interactions**: `reason` includes high_bill_complaint, complaint, disconnect_reconnect,
  payment_arrangement; has `invoice_id`, `service_order_id`; status open..closed; mutable. tally_app INSERT/SELECT/UPDATE.

## Place facts / weather

- **place_fact_kinds** (26115; rows 26163): platform vocabulary, no RLS, tally_app SELECT. Cols `fact_code PK`
  (`^[a-z][a-z0-9_]*$`), `value_type IN (text, number, boolean, time_zone)`, `keyed bool`, `value_min/max`,
  `place_kinds text[]`, `description`, `source_note`. ALWAYS `a_enforce_place_vocabulary_immutable`, no_truncate.
  Rows: local_adoption, **weather_station (text, unkeyed, county; "The National Weather Service station the law uses
  for the county", 16 TAC 7.460)**, residential_gas_taxable, time_zone, gas_rate_jurisdiction_retained,
  census_population, time_zone_uniform, sales_tax_rate, special_district_type.
- **place_facts** (26440): `place_id`, `fact_code`, `fact_key`, `value jsonb`, `effective_from date NN`,
  `effective_to`, `source_note`, `created_at`, `closed_at`, `closed_by`. ALWAYS `a_enforce_place_fact` (26475),
  no_truncate. No RLS (platform data); tally_app SELECT. Live: 4 places, 4 facts.
- **places** (26267), `premise_places_as_of(location, on, axis)` (27021), `premise_time_zone_as_of` (27064 — the model
  for a "premise → county → weather_station" lookup). `place_lock_key` (26308).
- **No temperature / weather observation table exists.** "temperature" appears only as a gas factor key (16355).
  WNA tables (`wna_zones` 4963, `wna_zone_versions` 15232, `wna_monthly_adjustments`) carry HDD per month for rating;
  their weather_station_* columns were dropped (15328).

## Rule-terms tables (where moratorium / bypass rows would go)

- **rule_tables** (28532): registry; rows today: `backbilling_rules` (law, backbilling, area customer_class,cause),
  `deposit_rules` (law, deposit, area customer_class,basis, facets cap_part_ids/return_reasons/trigger_codes/
  waiver_classes), `deposit_tariffs` (tariff, deposit_tariff, area tariff_category, law_table deposit_rules). Guard
  `enforce_rule_table_registry` (28559).
- **rule_term_schemas** (28053): `(terms_kind, terms_version)`, rule_role, json_schema, schema_hash,
  accepts_new_rows, introduced_on, frozen_at. Rows: backbilling v1 law, deposit v1 law, deposit_tariff v1 tariff.
  Guard `enforce_rule_term_schema`. **rule_term_facets** (28216), guard `enforce_rule_term_facet`.
- **rule_parameters** (29808) / **rule_parameter_values** (29847): scalar statewide parameters
  (`scoped_by` {} / {state_code} …). One row: `tx_deposit_interest_rate`; 0 values. A freeze threshold (32F) could
  live here or in terms. `rule_parameter_value_as_of` (29942).
- **deposit_tariffs** (34924): `tenant_id`, state_code, service_type, system_kind, tariff_category,
  effective_from/to, tariff_reference, terms_kind, terms_version, terms_source, terms jsonb, recorded_txid,
  closed_at/by. RLS tenant_isolation. Triggers ALWAYS `rule_row_insert` (enforce_rule_row_insert 29230),
  `rule_row_history` (29375), `rule_row_no_truncate`. tally_app INSERT, SELECT, UPDATE (guarded); tally_core SELECT.
  Law tables (deposit_rules 34446, backbilling_rules 24037) are SELECT-only for tally_app and tally_core.
- Readers: `rule_law_row_as_of` (29504), `rule_tariff_row_as_of` (29589), `rule_row_cite` (29465, shared advisory lock
  on the cited row), `rule_law_row_cite` (29565).
- Existing dispute/collection vocabulary inside terms: deposit trigger terms carry `exclude_disputed` ("disputed bills
  do not count", 31974–31998, compare at 34891); deposit return terms carry `hold_while: ["dispute_pending"]`
  (33358–33369); backbilling terms carry `enforcement` = uncapped | months | never | conditional ("what collection —
  disconnection, refusal of service — may pursue on what was billed", 24133; schema 30973–31040). These are the only
  places "disputed" and "collection limits" are already typed.

## tu.sql keyword sweep

- dispute (58): meter_readings dispute_* (3532), reading status `disputed`, `pending_dispute` program type (11738),
  customer_credits origin `dispute_resolution` (2659), billing_hold_reason example "Disputed bill" (2562), deposit
  terms `exclude_disputed` / `dispute_pending`, meter test "figure a dispute contests" (22528, 22600). Nothing else.
- collection (28): dunning_stage `collections`, customers.status `collections`, backbilling enforce_scope, comments.
- dunning (56): dunning_events, invoices.dunning_stage, deposit "delinquent" classification reads dunning_stage
  (18290–18299).
- disconnect (99): program types, do_not_disconnect, service_orders.order_type disconnect, adhoc
  disconnection_fee, deposit trigger `disconnect_history` / `disconnect_nonpayment`, backbilling "(4)(E)(vi) bars
  disconnection" (24363).
- moratorium (2): the program_types seed row and a dropped CHECK only.
- bypass (72): all RLS/BYPASSRLS/role hygiene and backbilling cause `tampering_bypass` — **nothing about
  collection-step bypass conditions**.
- eligib (6): adhoc billing eligibility, dropped deposits.refund_eligibility_on (35791). No disconnect eligibility.
- idempot (26): import_jobs.idempotency_key + UNIQUE (12312–12359, 37566); rule seeds. No collections idempotency.
- field_verif (0). captured (21): read_cycle_meters.captured_at/captured_reading_id (4364), invoice_calculation_
  snapshots.captured_at DB-forced (16433). serial (59): meters.serial_number (3674, not unique by design 3731),
  meter_tests.meter_serial_at_test (22381, required on full records 22436, caller-supplied "as observed" 22518).
- weather (23) / temperature (4): as above; no observation store.

---

## Absent (what wave 3 needs that does not exist)

1. **Dispute record.** No dispute table on invoices or lines; no disputed amount; no dispute open/close events; the
   only dispute state is the mutable meter_readings.dispute_* columns and the account-wide `pending_dispute`
   enrollment (protective boolean, whole account). CI-074 (suspend collections on the disputed amount only) and
   CI-054 (late fee exempts disputed amount) have nothing to bind to.
2. **Disconnect eligibility decision record (CI-067).** Nothing records "this account/bill was judged eligible on
   date D under rule R with inputs I by core version V". dunning_events `shutoff_scheduled`/`disconnected` are
   app-written steps with no cited rule, no inputs, no amount basis and no link to protections checked.
3. **Per-step bypass/protection model (CI-069).** program_types has one `is_disconnect_protective` flag; no
   per-collections-step scope (notice, late fee, disconnect, reconnect fee), no jurisdiction rows. No rule-terms kind
   for moratorium / bypass sets; rule_tables has no collections family.
4. **Weather observations.** weather_station fact exists per county but no temperature/forecast table to evaluate a
   32F-style moratorium deterministically.
5. **Field verification on disconnect work orders (CI-071).** service_orders has no captured meter serial / service
   point / read / photo, no expected-vs-captured fields, no mismatch outcome; status freely app-updatable; no FK from a
   disconnect order to the dunning event / eligibility decision that authorised it (and dunning_events has no
   service_order_id).
6. **Collections idempotency (CI-075).** No run/decision key on dunning_events (no unique per invoice+step+cause, no
   inputs fingerprint, no engine version); event_date caller-settable; dunning_events' customer_id/invoice_id not
   bound to each other or to the tenant (single-column FKs).
7. **Late-fee basis.** invoices.late_fee_assessed/late_fee_amount are mutable after issue and carry no base, rule
   or exclusion; no late-fee rule/tariff table; no tenant grace-period/late-fee settings columns anywhere.
8. **Guarded projections.** invoices.dunning_stage and customers.do_not_disconnect are app-writable with no
   cause-naming or event-derivation guard; enrollments have no history/as-of (only do_not_disconnect's attribute
   history).
9. Exception queues have no criterion/type for dispute, collections or field-verification mismatch (anomalies
   entity_type lacks service_order/dunning_event; invoice_exceptions is pre-delivery only).

## Patterns to copy

| Pattern | Where (tu.sql unless noted) |
|---|---|
| Append-only log: `append_only` → `enforce_append_only()` + `a_stamp_created_at` → `stamp_log_created_at()` + REVOKE UPDATE/DELETE/TRUNCATE, ENABLE ALWAYS loop | 17849; 37336; loop 37350–37362 (dunning/escheatment/ai_audit) |
| DB-written event table (app cannot forge the event) | `enforce_event_written_by_db()` 19141 on customer_state_events; status move writes its own event in `enforce_customer_lifecycle()` 17783 |
| Status moves name their cause (-23 Q1(a)) | -23 file: `status_cause_id`/`status_recorded_at` l.1014–1040, 1074–1080; `enforce_payment_immutable` l.1328; `enforce_customer_credit_immutable` l.1481; born-state `enforce_cash_birth` l.1590 |
| Decision record + evidence + withdrawal + supersession, one live per subject via row-version mutex, written by core (`calculated_by`, `inputs`, `inputs_fingerprint`, `recorded_txid`, sequence) | `deposit_return_due` 35836, `_withdrawals` 35874, `_evidence` 35897 (one-subject CHECK), `deposit_return_due_is_live` 35934, `enforce_deposit_return_due_record` 35946, `_has_evidence` 36060, `_evidence` 36081, `_withdrawal` 36161; design note 35808–35830 |
| Deposit decision citing law + tariff row + core version | deposits.rule_id / tariff_id / decided_by comments 35800–35804; `deposit_cite_rule` 35247 |
| Hold that opens once, closes once, never changes; non-overlap | `meter_correction_holds` 25516, `enforce_meter_correction_hold_record` 25568, comment 25655 |
| Case + append-only case events | `meter_correction_cases` 24618, `meter_correction_case_events` 24937 |
| Temporal as-of helpers, coordinates required, NULL raises, no live fallback | `account_balance_as_of` 37659; `customer_status_as_of` 17773; `customer_attribute_as_of` 17894; `receivables_aging_as_of` 41376/41488; `premise_places_as_of` 27021; `premise_time_zone_as_of` 27064; -23 `cash_coordinates_required` l.1114, `invoice_position_as_of` l.1215 |
| Rule-terms law/tariff rows + registry + cite lock | rule_tables 28532, rule_term_schemas 28053, rule_term_facets 28216, `enforce_rule_row_insert` 29230, `enforce_rule_row_history` 29375, `rule_row_cite` 29465, `rule_law_row_as_of` 29504, `rule_tariff_row_as_of` 29589, `rule_row_lock_key` 27412; scalar `rule_parameters` 29808 / `rule_parameter_value_as_of` 29942 |
| Row-mutex count guards / FOR KEY SHARE handshake | surcharge (rider, service) mutex 19354/19440; correction-run handshake 20888–20916; meter_tests tenant FOR KEY SHARE 22606/22760 and row-version mutex 23017; deposit row as mutex 35955; -23 `cash_source_lock_key` l.1319 + lock order rule l.118–146 |
| Advisory xact locks keyed by entity | `place_lock_key` 26308 (26396, 26726), `deposit_rate_lock_key` 35119, `rule_term_schema_lock_key` 27423 |
| DB-stamped write-once columns | `invoice_calculation_snapshots.captured_at := now()` 16433/20925; `enforce_invoice_first_issued` 20610; `stamp_log_created_at` 37336; `enforce_ai_provenance_write_once` 37395; places/rule rows `recorded_txid DEFAULT txid_current()`; -23 `status_recorded_at` |
| "As observed" caller-supplied field record (for CI-071 captured serial) | meter_tests.meter_serial_at_test 22381, full-record CHECK 22432–22437, comment 22518; `enforce_meter_test_record` 22723 |
| Idempotent detection key | anomalies `dedup_key NN` + UNIQUE (tenant_id, dedup_key) 37428–37432; import_jobs idempotency_key 12312–12359 |
| Seal / owner-role guard (act only through a function) | `void_invoice()` as `tally_void` (check in `enforce_invoice_immutable` 38574+, roles invariants `assert_seal_role_invariants` 41953); `tally_core` NOLOGIN role invariants 30336 |
| Accounting freeze on money rows | `enforce_accounting_freeze` 40890; accounting_close_heads 40677 |
| Blank-check whitelist `~ '[[:alnum:]]'` with coalesce | e.g. 22432–22437, place_facts/anomalies CHECKs |
| Invariant assert functions run in CI | `assert_rule_table_invariants` 28687, `assert_core_role_invariants` 30336, `assert_no_hard_delete_invariants` 40534, `assert_periods_guard_invariants` 42199 |
