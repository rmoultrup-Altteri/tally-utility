# Application Contracts — what the schema requires of the application code

No application code exists yet. This file is the running list of obligations
the schema places on whoever writes it: behaviors the database will **reject**
or get **wrong** if the application doesn't do its part. Each entry names the
patch that introduced the obligation so the DDL comment and test history can be
found. Add an entry whenever a patch lands a constraint or trigger that assumes
something about the caller.

Status legend: **REJECTS** = the database raises an error; **SILENT** = the
database accepts the write but the data is wrong.

---

## Meters and reads

### AC-1 — Set `meters.start_date` on every Pattern A reactivation — REJECTS
*Introduced by v5.4.1-01 item 2.6 (`meter_deployments_no_overlap_excl`).*

When a meter is reactivated in place (status `inactive`/`testing`/`failed` →
`active`, the "reuse_record" Pattern A path), `sync_meter_deployments()` opens a
new `meter_deployments` row with `install_date = COALESCE(NEW.start_date,
CURRENT_DATE)`. If the application leaves `start_date` at its original value,
that new row overlaps the previous (now-closed) deployment and the EXCLUDE
constraint rejects the whole UPDATE.

**Do:** in the same UPDATE that sets `status = 'active'`, set `start_date` to
the actual reinstall date (≥ the previous deployment's `removal_date`; same day
is fine — the range is half-open). Symmetrically, on deactivation either leave
`meters.removal_date` NULL (the trigger uses today) or set it ≥ the open
deployment's `install_date` — an earlier date is rejected by
`meter_deployments_removal_after_install_check` inside the same trigger.

**Why the schema doesn't do it for you:** the trigger can't know the true
reinstall date; guessing `CURRENT_DATE` or `GREATEST(...)` would fabricate a
date and silently record the wrong one. Candidate for a Kyle brief if the
product wants the trigger to take an explicit reinstall-date parameter instead.

### AC-2 — Correcting `meter_readings.reading_date` must re-check `location_id` — SILENT
*Introduced by v5.4.1-01 item 2.6 (`trg_populate_reading_location`).*

`meter_readings.location_id` is a snapshot of the premise the meter was at on
the reading date, filled once on INSERT and deliberately **never re-derived on
UPDATE** (a later meter move must not reattribute historical consumption). The
flip side: if the application corrects a read's `reading_date` across a
deployment boundary, `location_id` stays stale.

**Do:** when changing `reading_date`, either supply the correct `location_id`
in the same UPDATE or re-run the lookup (deployment covering the new date, else
`meters.location_id`). Prefer the supersede pattern (new read row, old one
`replaced`) over in-place date edits — a new row gets the snapshot for free.

Also: on the day a meter is pulled from premise A and reinstalled at B, the
trigger resolves reads with `reading_purpose` `removal`/`final_read` to A (the
deployment closed that day) and every other purpose to B. If a same-day read of
another purpose belongs to A, supply `location_id` explicitly.

### AC-3 — `location_id` is optional at the database level — SILENT
*Introduced by v5.4.1-01 item 2.6.*

The trigger fills `location_id` automatically, but the column is nullable, and
there is a real path that leaves it NULL with no error: `meter_readings.meter_id`'s
FK is not tenant-scoped and FK checks bypass RLS, so a read inserted by tenant A
against tenant B's meter passes the FK while both of the trigger's lookups
return nothing under RLS. Application validation must (a) check the meter
belongs to the caller's tenant before inserting, and (b) treat a NULL
`location_id` on a read as a data defect to surface, never a valid state.

### AC-7 — Relocating an ACTIVE meter by editing `meters.location_id` leaves history stale — SILENT
*Surfaced by v5.4.1-01 item 2.6; the cause is pre-existing (`sync_meter_deployments()`, tu.sql:841).*

`sync_meter_deployments()` opens and closes `meter_deployments` rows only on
`meters.status` transitions. A bare `UPDATE meters SET location_id = B` while
`status = 'active'` is accepted, leaves the open deployment pointing at A, and
every subsequent read snapshots A. Nothing raises. This is the leading reason
CI-027 is graded `partially-structurally-enforced`.

**Do, until ruled:** never change `location_id` on an active meter directly.
A real relocation goes through the status cycle (`inactive` → `active` with the
new `location_id` and a real `start_date`, per AC-1), which closes and reopens
the deployment. A data-entry correction (the meter was never at A) should
correct the `meter_deployments` row too, in the same transaction.

**Open product question (Kyle brief):** the schema can't distinguish relocation
from typo-fix, so it neither auto-reopens nor rejects. Whichever ruling lands
becomes a trigger and retires this entry.

---

## Imports

### AC-4 — Supply `source_filename` + `source_file_hash` on file imports — SILENT
*Introduced by v5.4.1-01 item 2.2 (`trg_populate_import_job_idempotency_key`).*

`import_jobs.idempotency_key` is NOT NULL and auto-derived as
`<filename>:<hash>:<preview|commit>` — but only when both filename and hash
are present. Otherwise it falls back to the job's own `id`, which is unique by
construction and therefore **never detects a duplicate import**.

**Do:** always populate both columns for csv/excel/file-backed imports (or
supply an explicit `idempotency_key`). CI-118's duplicate-import guarantee is
conditional on this.

---

## Lineage columns (general)

### AC-5 — Lineage FKs are representable, not required — SILENT
*`account_ledger.reverses_ledger_entry_id` / `reversal_reason` (v5.4.1-01 item
2.5), `invoices.replaces_invoice_id`, `payments.refunds_payment_id`,
`meter_readings.replaces_read_id`.*

Every lineage column in the schema is nullable. `void_invoice()` populates the
ledger pair itself; any other code path that posts a reversal, replacement, or
refund must populate the corresponding lineage column or the chain is
unqueryable (CI-017/CI-018 depend on it).

---

## Concurrency

### AC-6 — Cycle guards are not race-safe — SILENT under concurrency
*v5.4.1-01 item 2.3 (`landlord_customer_cycle`, `service_order_parent_cycle`,
`import_staging_dependency_cycle`).*

The three cycle-guard triggers read the graph with plain MVCC snapshots. Two
concurrent transactions each adding one edge can together form a cycle neither
saw. Serialize writes to these parent/dependency columns per tenant (advisory
lock or `SERIALIZABLE`) in any code path that rewires hierarchies in bulk.

---

## Tenant configuration and temporal coordinates

### AC-8 — `get_partial_period_policy()` needs a real coordinate; a NULL result is an error — REJECTS / SILENT
*Introduced by v5.4.1-02. Amended by v5.4.2-03: the function now takes both axes, `(p_rate_schedule_id, p_valid_at date, p_recorded_at timestamptz)`; the 2-argument form is gone. Everything below still holds, per axis — see AC-15.*

`get_partial_period_policy(p_rate_schedule_id, p_as_of)` **raises** on NULL `p_as_of`. `get_correction_rate_date()` documents returning NULL when its target is missing — substitute (and log) before calling, never pass it through. The function returns **NULL** for an unknown rate schedule *and* for a coordinate earlier than the tenant's first recorded policy row; there is deliberately no fallback to the live `tenants` column. The billing engine must treat NULL as a hard failure, never as "use the default" — that is the time-blind bug CI-006 forbids. A DATE argument casts to midnight; pass an end-of-day `timestamptz` if "in effect on that day" is the intent.

### AC-9 — Change tenant policy through `tenants`, not by writing history; populate `settings` at onboarding if you want it recorded — SILENT
*Introduced by v5.4.1-02.*

`tenant_configuration_history` is filled by the trigger on `tenants`; application code changes policy by updating `tenants` (with `app.user_id` set so `changed_by` is captured). Direct inserts are for backdated corrections only (`change_source = 'manual'`) and cannot claim `onboarding`/`trigger`. `tenants.settings` defaults to `{}`: the seven documented sub-objects get onboarding history rows **only if the application writes them into `settings` in the tenant INSERT**. The bracket is transaction time — "this policy took effect last month" cannot be expressed through the normal path until the A-1 bi-temporal pair lands.

### AC-10 — Correct an issued invoice with `void_invoice()` + rebill; never edit, never delete — REJECTS
*Introduced by v5.4.2-01.*

Once `invoices.status` leaves `draft`/`held` (`pending` counts as issued), the billed content — identity, lineage pointers, period, dates including `due_date`, every total, `tax_breakdown`, the estimated-read/anomaly flags, `pdf_url` once set — is frozen and the line items reject INSERT/UPDATE/DELETE. Lifecycle columns (status forward, `amount_paid`, `balance`, `dunning_stage`, `late_fee_*`, `write_off_*`, `delivery_*`, `notes`, `metadata`) stay writable. `status = 'void'` is written by `void_invoice()` only — from v5.4.2-02 a direct UPDATE to `void` (from *any* status, held and draft included) or an INSERT as `void` is rejected unless the `app.void_operation` carve-out is armed, because a bare void skips the ledger reversal, read release and charge disposition and is then sealed forever; a void is terminal (notes/metadata only). Only a `draft` invoice may be hard-deleted, and only if no billed adhoc charge or locked read points at it; note that `dunning_events` and `invoice_applications` cascade from `invoices` and are in the CI-014 set, so a draft carrying either cannot be deleted (the error names the child table). Everything else retires through status.

### AC-11 — `payments.status` DEFAULTs to `posted`; insert intake rows as `pending` explicitly or they are frozen on arrival — REJECTS
*Introduced by v5.4.2-01.*

A payment's identity (customer, date, amount, method, channel, source, external references, check fields, `is_deposit`, `received_by`, lineage FKs) is frozen once `status <> 'pending'`, and a payment never returns to `pending`. Because the column default is `posted`, a webhook/lockbox intake row that may still need correction must be inserted with `status = 'pending'`; a posted payment is corrected by reversal/NSF + a new payment. `nsf`/`reversed`/`refunded`/`voided` are terminal.

### AC-12 — `app.void_operation` is a carve-out for `void_invoice()` only; never set it yourself — SILENT
*Introduced by v5.4.2-01 (the GUC itself dates from v5.2.1).*

The locked-read guard on `meter_readings` and the billed-charge guard on `adhoc_charges` both step aside when the session GUC `app.void_operation = 'true'`. It is a plain session variable: any role with UPDATE can `SET LOCAL` it and walk through both guards — the database cannot tell `void_invoice()` from an impostor. Application code must never set it; `void_invoice()` sets it and (since v5.4.2-01) clears it before returning, so nothing later in the caller's transaction inherits it. Since v5.4.2-02 the invoice guard also honours it (entering `status = 'void'`), and `void_invoice()` runs with `search_path` pinned to `public, pg_temp` — a caller's search_path can no longer redirect anything it resolves. Grep for it in code review. A true seal needs the SECURITY-DEFINER half of Appendix A-4 option (a) — routing those writes through procedures and revoking UPDATE on the columns — which is an application-architecture decision not taken by the schema.

### AC-13 — Retire operational records through their status/voided/closed marker; the 33 protected tables reject DELETE and TRUNCATE — REJECTS
*Introduced by v5.4.2-01.*

`enforce_no_hard_delete()` is attached to every table in the v5.4.2-01 DO-block array (money, bills, parties, premises, metering, operations, audit). It fires on FK cascades too, so deleting a customer/tenant/meter fails at its first protected child. Reference and configuration tables (rate_* family, `billing_cycles`, `read_routes`, `jurisdictions`, `import_staging`, …) are not guarded — their retention discipline is A-1's date-effective shape, not a delete guard. Adding a table to the protected set means adding it to that array in a new patch (the loop also performs the `REVOKE DELETE`).

---

## Bi-temporal reference data (A-1, v5.4.2-03)

### AC-14 — Correct by close-then-insert; retract by close; never edit an asserted row; bump the header version first — REJECTS
*Introduced by v5.4.2-03.*

`rate_schedule_versions`, `wna_zone_versions`, `rate_item_versions`, `rate_schedule_items`, `franchise_fee_rules`, `customer_tax_exemptions`, `wna_monthly_adjustments` are bi-temporal: once a row is asserted (`recorded_at` set — always, for the first five; on approval/verification for the last two) every content column is frozen. The only writes an asserted open row accepts are the **close** — one UPDATE setting `recorded_until` (the value you pass is ignored; the database stamps `now()`), `closed_type` (`superseded` | `retracted`), `closed_reason` (required) and optionally `closed_by`, with every other column byte-identical — and the per-table lifecycle set (`wna_monthly_adjustments.status` forward only; `notes`/`metadata`/`updated_at`). A **correction** is: close the row as `superseded`, then INSERT the corrected row with `supersedes_id` = the closed row's id (same entity, same tenant — the guard checks), `change_type = 'correction'` and a `change_reason`; a **succession** (a scheduled change that corrects nothing) is the same shape with `change_type = 'succession'`, closing and re-asserting the prior bracket with an `expiry_date` when a new bracket follows; a **retraction** is a close as `retracted` with no successor. At commit, a row closed as `superseded` must have an asserted successor of the same entity, or the transaction fails. `recorded_at` is stamped by the database — a value you supply is replaced; `change_type = 'backfill'` cannot be inserted. For the three header tables, call `assert_reference_version('<table>', id, version_you_read)` **first** in the transaction: it rejects a stale token (`serialization_failure`, "review and retry") and row-locks the header so concurrent writers on the entity are serialised. A raw `version = version + 1` is accepted by the trigger and bypasses the check — do not write it. For the four in-place tables there is no counter: predicate the closing UPDATE on `recorded_until IS NULL` and treat 0 rows as "stale, re-read". Nothing in these tables is ever deleted (`no_hard_delete`), including drafts.

### AC-15 — Every reference lookup takes an explicit `(p_valid_at, p_recorded_at)` pair; pass ONE pair per run; NULL raises; zero rows is a hard error — REJECTS / SILENT
*Introduced by v5.4.2-03 (R-15).*

`rate_schedule_as_of`, `wna_zone_as_of`, `rate_item_as_of`, `rate_schedule_item_as_of`, `franchise_fee_as_of`, `customer_tax_exemption_as_of`, `wna_monthly_adjustment_as_of` (its valid coordinate is `p_billing_month`), `should_charge_tax(customer, taxable, service_type, p_valid_at, p_recorded_at)` and `get_partial_period_policy(schedule, p_valid_at, p_recorded_at)` all require both coordinates and raise on NULL; none defaults to `now()` and none falls back to any live column. A result of zero rows (or NULL from `get_partial_period_policy`) means "unknowable at that coordinate" — a hard error, never "use the current value". Three call shapes, one contract: a new bill passes (service period, `now()`); a correction run — the RRC default — passes (original period, `now()`) so a correction discovered since is applied; reproducing or defending the original bill passes (original period, the original run's instant). Resolve the pair **once per billing run** and pass the same pair to every lookup in that run (CI-003 is still application discipline; R-16 defers the GUC net until calculation code exists). `get_correction_rate_date()` returns only the valid-time coordinate (a date) and NULL when its target is missing — substitute and log before calling any lookup. `get_effective_rate()` and `archive_rate_item_history()` are disabled stubs that raise; compose `rate_schedule_item_as_of` over `rate_item_as_of` instead (the recipe is in the stub's message). `rate_item_history` / `rate_item_history_archive` are retired read-only.

### AC-16 — Lifecycle tables: exemptions are born `pending_verification` and activate only with a verifier; WNA factors lock at approval; restatements close first — REJECTS
*Introduced by v5.4.2-03 (R-11, R-12, R-13).*

`customer_tax_exemptions.status` DEFAULTs to `pending_verification` (a draft: `recorded_at` NULL, freely editable, invisible to every lookup and to `should_charge_tax`). Activation requires `verified_by` and `verified_at` in the same UPDATE; a pending row may only go to `active` or `rejected` (terminal). Once active the row is frozen: revocation is a **new row** (`status = 'revoked'`, `effective_end`, `revoked_at`, `revoked_by`, `supersedes_id` = the active row, after closing it as `superseded`); expiry likewise. One asserted exemption per `(customer, exemption_type)` per valid period (exclusion constraint). `industrial` is no longer a legal `exemption_type` — predominant-use exemptions are handled as manual tax adjustments until their own table lands. A revocation discovered late means issued bills were under-taxed: route it to the void/rebill infrastructure as a correction run. `wna_monthly_adjustments`: `pending` is a draft; approving requires `approved_by` and `approved_at` in the same UPDATE and freezes the factor; afterwards only `approved → applied → archived` is writable in place. An HDD restatement for a month is a correction: close the approved row as `superseded`, insert the restated row (already `approved`, with its approver) pointing back. A pending restatement may be entered beside the live month, but approving it while the live row is still open fails on the unique index — close first.

### AC-17 — Rate schedules are born `draft`, activate only with content, and drafts/archived schedules are not assignable; tariff codes are namespaced by convention — REJECTS
*Introduced by v5.4.2-03 (R-9, R-10, R-14, R-17).*

`INSERT INTO rate_schedules` must be (and defaults to) `status = 'draft'`; insert its `rate_schedule_versions` row(s), then set `status = 'active'` (the trigger requires an open version and stamps `activated_at`). A `draft` or `archived` schedule cannot be assigned to `meters.rate_schedule_id` / `meter_deployments.rate_schedule_id`. Archiving requires `archive_reason` (`abandoned_draft` for a draft; `superseded_by_filing` | `service_discontinued` for an activated one) and every open version to carry an `expiry_date` first (assert the valid-time end, or retract); an archived schedule accepts no new versions and is terminal. `expired` is not a schedule status — read the version's `expiry_date`. `UNIQUE (tenant_id, code)` is permanent: a multi-service tenant namespaces internal codes (`GAS-R1`, `WTR-R1`); the filed designation is `tariff_number`. One schedule = one service: `service_type` may change only as a transcription correction — a `correction` row over the predecessor's exact valid bracket with `service_type_change_basis = 'transcription_error'`; if any invoice line references the schedule, the database queues an `anomalies` row (`reference_correction_review`, severity high) that an operator must resolve by ruling on correction scope. A re-tag that moves customers between regulatory regimes is a new schedule.

## Invoice calculation snapshots (A-3, v5.4.2-04)

### AC-18 — Write order is invoice (draft) → lines → snapshot → status flip; the snapshot is the run's coordinate pair plus a `v1`-keyed input set; recalculating a draft means delete + re-snapshot — REJECTS
*Introduced by v5.4.2-04 (CI-015, D-2026-08-28-16…-20).*

Every invoice that leaves `draft`/`held` for any other status (`pending` included) must have exactly one `invoice_calculation_snapshots` row at commit; the transaction is rejected otherwise. Write the row after the line items and before the status flip — the validator refuses a snapshot for a parent already issued, and A-4 refuses lines on one, so an invoice cannot be INSERTed directly in an issued status. Supply: `valid_at` and `recorded_at` = the ONE `(p_valid_at, p_recorded_at)` pair the run passed to every `*_as_of` lookup (AC-15; `recorded_at` not in the future); `snapshot_schema_version = 'v1'` and `formula_version` (the engine build); `billing_run_id` equal to the invoice's; the eight sections with `v1`'s required keys (the column COMMENTs list them — every key present, `null` for a group that does not apply, `wna_inputs.applied = false` when WNA was not applied); `period_inputs.period_start/period_end` and `customer_inputs.customer_id` equal to the invoice's; `line_items[]` citing exactly the invoice's `invoice_line_items` rows (`invoice_line_item_id`, `charge_type`, `amount` as a JSON number equal to the line's). `captured_at` and `content_hash` are the database's — do not supply them. Never UPDATE a snapshot; if a draft is recalculated or a line changes, DELETE the snapshot and insert a new one, or the issuance is rejected with "line items changed". Once issued the snapshot is frozen (no DELETE); `void_invoice()` keeps it. Voiding a draft/held invoice needs no snapshot. Invoices issued before v5.4.2-04 have no snapshot and cannot be given one. A new snapshot shape is a patch that teaches `validate_calculation_snapshot()` a `v2` — not a string the caller invents.

### AC-19 — Cite the reference rows the run read in `invoice_snapshot_references`, before the status flip; only rows open at the snapshot's `recorded_at` are citable — REJECTS
*Introduced by v5.4.2-04 (D-2026-08-28-21).*

For each `*_as_of` result the calculation used, insert `(snapshot_id, source_table, source_row_id, role)` with `source_table` one of `rate_schedule_versions`, `wna_zone_versions`, `rate_item_versions`, `rate_schedule_items`, `franchise_fee_rules`, `customer_tax_exemptions`, `wna_monthly_adjustments` and `source_row_id` the row id the lookup returned (a version id for the three header/version domains). The guard requires the row to exist in that table, in the snapshot's tenant, with `recorded_at <= snapshot.recorded_at < coalesce(recorded_until, 'infinity')` — a draft (pending exemption, unapproved WNA row) or a row closed before the coordinate is rejected, which is correct: the run could not have read it at that coordinate. Citations follow the snapshot's immutability (no UPDATE; DELETE only while draft/held; frozen after issuance). Optional per snapshot (a credit memo may cite nothing); `role` is free text. Concurrency is handled for you: a snapshot delete, citation insert or line edit racing an issuance waits on the invoice row and the loser is rejected — retry from the read.

### AC-31 — The snapshot's coordinate pair is bound: ordinary bills price at `period_end` in the run's window; corrections price at the recorded election against a void, once-issued original; the inputs freeze under the snapshot — REJECTS
*Introduced by v5.4.2-10 (A-23 1e; D-2026-09-08-01…-09).*

**Ordinary invoice** (every `invoice_type` but `correction`): `valid_at` must equal the invoice's `period_end` exactly. `recorded_at` must lie in `[billing_runs.started_at, now()]` when the invoice is on a run — the run must have started; `started_at` is stamped by the database when set and never moves — or in `[invoices.created_at, now()]` off-run; `created_at` is stamped at INSERT and write-once. Pass the writing transaction's `now()` (or the run's instant) as `recorded_at`; never `data_cutoff_at`, which is the candidate-set freeze line, not a lookup coordinate.

**Correction invoice**: must sit on a run with `run_type = 'correction'`, carry `replaces_invoice_id`, and have a `correction_run_targets` row for (run, replaced bill) — record the operator's election first. The replaced bill must be visible to the writer, same-tenant, `status = 'void'` (through `void_invoice()`) and once issued (`first_issued_at` set — a held-then-voided discard cannot be corrected). `valid_at` must equal `get_correction_rate_date(run, replaced)` at insert (historical = the voided bill's `period_end`; current = the session's `CURRENT_DATE` — run the election and the snapshot insert in one session TimeZone; custom = the override). `recorded_at` lies in the run's window or equals the replaced bill's snapshot `recorded_at` exactly (original-world replay; a pre-A-3 original has none, so only the window applies). Only one live (non-void) rebill anywhere in a bill's lineage (its `replaces_invoice_id` chain from the root, any hop) may carry a snapshot; void the earlier correction to correct again. Only `correction`, `credit_memo` and `duplicate` may carry `replaces_invoice_id` through the binding — a `regular` / `final` / `prebill` that replaces a bill is refused ("a correction in all but name"); credit memos and duplicates must point at a visible same-tenant bill and do not count toward the lineage. `replaces_invoice_id` is tenant-bound at the FK. Refusals are `check_violation`.

**Freezes**: while a snapshot exists, the invoice's `invoice_type`, `replaces_invoice_id`, `billing_run_id`, `period_start`, `period_end` cannot change (delete the snapshot, edit, re-snapshot — the -04 model); `created_at` and `first_issued_at` never change; the run's `correction_rate_mode` and `run_type` cannot change while any snapshot cites the run; a target row's run, voided invoice, `rate_date_mode`, `rate_date_override` cannot change (nor the row be deleted) while the correction it governs is snapshotted. Refusals are `restrict_violation`.

**Concurrency**: the validator writes a row version onto the invoice, the replaced bill and the target (their `updated_at` moves on every snapshot insert — do not rely on it as "last operator edit") and holds the run row FOR KEY SHARE. An election change waits behind in-flight snapshots and then sees them. Under REPEATABLE READ, an edit racing a snapshot writer fails with `serialization_failure` — retry from the read. **Change a run's `correction_rate_mode` / `run_type` only under READ COMMITTED** (`invalid_transaction_state` otherwise: under RR the absence of a concurrent snapshot cannot be verified). Canonical lock order for any transaction touching more than one of these rows: **invoice → lineage root → replaced bill → correction target → billing run** (a transaction touching a void bill and its targets edits the bill first); do not write the run row's election inside a snapshot transaction. Heartbeats, status and totals on the run row do not conflict with snapshot writers.

**Deploy note**: v5.4.2-10 never refuses; it reports pre-patch snapshots that would fail the binding (immutable, left as recorded), runs carrying snapshots without `started_at`, and the `first_issued_at` backfill counts (issued rows from row timestamps; void rows from their `voided` event — an approximation; void bills with no such event cannot be corrected through the binding until a superuser stamps them).

## Read and bill exception queues (A-20, v5.4.2-05)

### AC-20 — A failed read rule is a `read_validation_exceptions` row; resolve it (disposition + reason + resolver) before the read can be approved, released or billed; never edit a resolved row — REJECTS
*Introduced by v5.4.2-05 (CI-112, D-2026-08-28-25/26).*

When VEE or an operator finds a read failing a rule, INSERT a row (`meter_reading_id`, `meter_id`, `rule_code`, optional `severity`/`detail`/`raised_by_user_id`; `status` open, stamps are the database's). Set `validation_status = reviewed_with_exception` only when such a row exists; `reviewed_clean` only when none is open. To resolve: UPDATE `status = 'resolved'` with `resolution_disposition` ∈ estimate_accepted | manual_read_entered | read_corrected | field_order_dispatched | excluded | override, a non-blank `resolution_reason_code`, `resolved_by` (a user of the tenant); name `field_order_id` (same meter) for field_order_dispatched and `replacement_reading_id` (a different reading of the same meter) for manual_read_entered / read_corrected. A `consecutive_estimate_over_cap` row resolves only by override or field_order_dispatched. Every step of the read into approved / released_to_billing / locked is refused while any row is open — an exception raised after approval stops the read at its next step; `billing_run_meters` refuses billed / billed_estimated against such a read. Do not raise an exception on a locked / void_released read — correct a billed read with a replacement reading. Rows are never deleted; a resolved row is frozen.

### AC-21 — The consecutive-estimate streak is the database's: never write `meters.consecutive_estimate_count` / streak columns or `meter_readings.validated_at`; approve reads through `validation_status`; at the cap, resolve the auto-raised exception — REJECTS
*Introduced by v5.4.2-05 (CI-113, D14-1, D-2026-08-28-27…-30).*

Inserting an estimated main-register read that would bring the meter to `tenants.settings.estimation.max_consecutive_estimates` (default 3, must be ≥ 1) opens a `consecutive_estimate_over_cap` exception on it; approving that read requires the exception resolved by override (reason-coded) or field_order_dispatched. If no exception was raised (cap lowered after insert; estimate pending from before the patch), the approval is still refused — raise the exception by hand (`detected_by = 'operator'`) and resolve it. The streak = validated estimates dated after the latest-dated validated actual: a validated actual dated at/after the streak clears it; a back-dated actual does not; a same-day estimate beside an actual is not counted; a read excluded after it was validated stays counted; re-approving a read after pending_review does not recount. Once a read is validated (`validated_at` set by the database), its `is_estimated`, `register_type`, `meter_id`, `reading_date` and `tenant_id` are frozen — correct with a replacement reading. `consecutive_estimate_state(meter_id)` is the reconciliation function; it always equals the stored columns.

### AC-22 — Route a bill exception into `invoice_exceptions` with table #35's outputs before releasing the invoice; hold it yourself; clear a block only by resolving or overriding with a reason — REJECTS
*Introduced by v5.4.2-05 (CI-115, D-2026-08-28-31/32).*

When a criterion fires (`criterion` ∈ CI-115's list + unresolved_read_exception / batch_baseline_breach / meter_master_incomplete / tamper_detected / canary_mismatch / manual / other), INSERT a row with `queue`, `blocks_delivery`, `routing_reason` (and `sla_days`, `escalation_target`, `severity`, `estimated_impact`, `anomaly_id`, `read_validation_exception_id` — required for unresolved_read_exception — as the routing decides); stamps are the database's; `billing_run_id` defaults to the invoice's. Set the invoice to `held` (with `hold_reason`) yourself — A-4 forbids pending → held, so hold before release. While an open row has `blocks_delivery = true` the invoice cannot enter pending (from draft or held) or sent, nor be stamped `sent_at` / `delivery_confirmed_at`. Clear it by UPDATE `status = 'resolved'` (the bill was corrected or the flag was wrong) or `'overridden'` (the bill goes out as flagged) with `resolution_reason_code` and `resolved_by` (same tenant); `blocks_delivery` and `routing_reason` cannot be edited. A blocking row cannot be raised on an already-delivered invoice (use the dispute workflow). Every insert and resolution appends an `invoice_events` row. Rows are never deleted (a draft-invoice delete cascades). CI-023: `billing_run_meters` refuses billed / billed_estimated for a meter with `meter_master_incomplete_reasons(meter_id) <> '{}'` — route the meter to the read queue (rule meter_master_incomplete) instead.

## Account lifecycle and deposits (A-21, v5.4.2-06)

### AC-23 — Change `customers.status` with `status_reason` (and `status_changed_by`) in the same UPDATE; read history from `customer_state_events` / `customer_attribute_history`, never from the row — REJECTS
*Introduced by v5.4.2-06 (CI-121, D-2026-08-28-34/35).*

Every status change must carry a non-blank `status_reason` (and the acting user in `status_changed_by`, same tenant); the database writes the event and clears both columns, so never read them back and never expect a reason to carry over. `closed` reopens only to `active`; `closed` is refused while any deposit of the customer is held / partial_applied / applied / refund_pending — settle it first (AC-24). `customer_status_as_of(customer, at)` and `customer_attribute_as_of(customer, attribute, at)` (attributes: billing_delivery_method, billing_hold, consolidate_invoices, do_not_disconnect, landlord_responsible, customer_type, autopay_enabled, deposit_status) return the value in force at `at` and NULL before recorded history — never substitute the current value. The log tables are append-only.

### AC-24 — A deposit is a `deposits` row plus `deposit_events`; never write `deposits.status` / `refunded_on` / `released_on` or any `customers.deposit_*` column; post the events in the order the ledger requires — REJECTS
*Introduced by v5.4.2-06 (CI-077 / CI-129 / CI-130 / CI-131, D-2026-08-28-36…-42).*

INSERT `deposits` with `basis` (credit_evaluation | adequate_assurance_366 | additional_trigger + `trigger_basis` | tariff — never legacy_unknown), `instrument` (cash accrues interest; anything else needs `instrument_reference`, may carry issuer/expiry, is released not refunded), `principal`, `posted_on`, `source_payment_id` (a payment of the customer flagged `is_deposit`), and for a Texas residential cash §7.45 deposit the cap (`cap_amount` = 1/6 estimated annual billing, `cap_basis_annual_billing`, `cap_binding` when it bit; `principal ≤ cap_amount`). A §7.45-basis deposit is refused while the customer has a `deposit_waiver_determinations` row in force on `posted_on` — record waivers there (family_violence_certified needs the TCFV reference). The database writes the `posted` event. Then only events: `applied_to_balance` (≤ remainder; not inside a settled accrual period; not while refund_pending), `interest_accrued` (cash only; only once `effective_on − posted_on ≥ 31` and never on a deposit exhausted within 30 days; `period_start` = `posted_on` for the first period, else previous `period_end + 1`; no rate change or application inside the period; `rate_applied` = `deposit_interest_rate_as_of(tenant, period_start)`; `principal_basis` = `deposit_principal_in_force(deposit, period_start)`; `amount` = `deposit_accrual_amount(basis, rate, start, end)`; `period_end < effective_on`), `interest_credited` (≤ accrued − credited), `refund_initiated` (amount = remainder), `refunded` (amount = remainder, 0 when fully applied; if the accrual horizon — the earlier of return and exhaustion — is > 30 days after posting, interest must be accrued through the day before it and credited in full; if ≤ 30 days, no accrual may exist), `released` (non-cash; amount = remaining face value). Link the ledger row that moved the money via `ledger_entry_id` (same customer; `deposit` / `adjustment` / `deposit_interest` / `refund` / `credit_issued`). A deposit_refund `customer_credits` row names its `deposit_id`. Events are append-only; a refunded/released deposit accepts no more. Read balances from `deposit_balance(deposit)`. A legacy (`legacy_unknown`) deposit with no accrual events may be refunded with a `reason` stating how its interest was settled.

### AC-25 — Enter deposit interest rates as effective-dated rows before accruing; watch `deposits_refund_due` on a schedule; never estimate the twelve-bill trigger yourself — REJECTS / SILENT
*Introduced by v5.4.2-06 (CI-125 / CI-131, D-2026-08-28-38/43).*

`deposit_interest_rates` is per tenant and append-only: a new PUCT rate is a new row (`effective_date`, `annual_rate` as a fraction); `deposit_interest_rate_as_of()` raises when no row covers a date, so enter the history back to the oldest posting date before the first accrual cycle; a rate dated on/before any settled accrual period is refused — a correction is a new period at the new rate going forward. The accrual job splits every window at rate changes and applications and posts one event per segment; a re-run is refused by the contiguity/overlap rules, never doubled. `deposits_refund_due` lists the §7.45 cash deposits whose mandatory refund has become due (twelve clean bills / ≤ 2 delinquencies / not delinquent per `deposit_refund_trigger_state()`, or an inactive / final_billed / closed customer) — the refund job reads it on its own cadence; a row that persists is an unmade statutory refund. §366 and legacy deposits never appear; evaluate them by their own rules. The definition of "paid clean" in the function is an approximation — the job records its own evaluation. A deposit refund is never routed into `minimum_refund_amount` / `below_threshold_action` (table #54 rule 8 — workflow).

## Regulatory surcharge riders (A-7, v5.4.2-07)

### AC-26 — Classify a surcharge rider in `regulatory_surcharge_rules` before its cycle; correct it by close + insert; never make it taxable — REJECTS
*Introduced by v5.4.2-07 (CI-038 / CI-045, D-2026-08-31-01/02/08).*

Before the first bill of an assessment cycle, INSERT one row per (rate item, cycle): `surcharge_kind` (`pipeline_safety_fee` needs `cap_per_service`, `excluded_from_tax_bases = true`, `exempts_state_agencies = true`, and a gas / all-service rider), `cycle_start` / `cycle_end` as BILL dates, the references. The cap is the tenant's figure against its filed tariff (the $1.00 / $0.50 question is open with Kyle). One open rule per rate item per bill date and one open `pipeline_safety_fee` rule per tenant per bill date. Content is frozen: a correction closes the row (`recorded_until`, `closed_type = 'superseded'`, `closed_reason`) and inserts the successor (`supersedes_id`) in the same transaction; a retraction closes as `'retracted'`. A rider with an excluded rule can never assert `is_taxable_default` / `is_a_tax` / `is_taxable_override = true`, and the rule is refused while any open version or override says taxable. Read through `regulatory_surcharge_rule_as_of(rate_item, bill_date, recorded_at)` — both required. There is NO remittance gate: bill after remitting, never before (D4-1, operator discipline). Cite the rule row in `invoice_snapshot_references` (`source_table = 'regulatory_surcharge_rules'`).

### AC-27 — Write surcharge lines with `meter_id`, `charge_type <> 'tax'`, `is_taxable = false`; expect the cap and the exemption to refuse; retry on a serialization failure; never re-label a surcharge line — REJECTS
*Introduced by v5.4.2-07 (CI-038, D-2026-08-31-03/04/08).*

A line of a ruled rider must name its service (`meter_id`) when capped; the cycle's positive amounts per (rate item, meter) over non-void invoices, drafts included, may not exceed the cap — a negative line is accepted but lends no headroom; the way to bill again is `void_invoice()` + rebill. Under REPEATABLE READ / SERIALIZABLE a concurrent writer for the same (rider, meter) fails with `could not serialize access due to concurrent update` — retry the transaction; under READ COMMITTED it queues. Set `customers.is_state_agency` (government customers only) and let the logger record it — never INSERT into `customer_attribute_history` / `customer_state_events` (refused); a state agency at the end of the billed period may carry only a 0.00 line. A ruled surcharge line's `rate_item_id` cannot be changed or removed — delete the line and write a new one. Every one of these checks runs again at issuance on current knowledge, so a draft edited after its lines were written (bill date moved into a cycle, customer changed) is refused at commit. Known gaps: a meter change-out mid-cycle resets the cap; two sessions writing capped lines for two meters in opposite order may deadlock (retry).

### AC-28 — Write the base composition (`invoice_line_item_bases`) for every non-zero tax / percentage line, after the lines and before issuance; never cite an excluded surcharge line — REJECTS
*Introduced by v5.4.2-07 (CI-045, D-2026-08-31-06/07).*

For each tax line (`charge_type = 'tax'`) and each `percentage_of_bill` / `percentage_of_charges` line with a non-zero amount, INSERT one row per line it was computed on with `base_amount` (non-zero, the cited line's sign, no larger than its amount — a partially taxable line contributes its taxable part). Both lines on the same invoice; a fixed charge cannot carry a composition; a line of a rider excluded from tax bases is refused as a base; whether a tax line may cite another tax line is a jurisdiction rule not decided here (#23 stage 3 / A-8). Write order: lines → bases → snapshot → status flip; issuance is refused while a non-zero tax / percentage line has no base row on this invoice, a base row cites a line that left the invoice, a cited line shrank under its base, or a citing line is no longer a tax / percentage charge. After issuance the composition is frozen; a draft line with a composition cannot be moved to another invoice and a cited line cannot change amount under what a base took from it — delete the rows first. Discarding a draft discards its composition. `regulatory_surcharge_billing_summary` is the billed side of the §8.201 compliance report only — amounts paid to RRC and collected from customers are the application's.

### AC-29 — Amendments to AC-26/AC-27 (v5.4.2-08): the freeze family and the concurrency contract — REJECTS
*Introduced by v5.4.2-08 (CI-038, D-2026-08-31-09…-12).*

A ruled surcharge line's `invoice_id` is frozen like its `rate_item_id` — relocate by delete + new line. A draft invoice carrying a ruled line keeps its bill date under the SAME rule row (within-cycle moves free; delete the ruled lines before re-dating out). A rule correction whose successor cycle would leave any non-void line of the rider outside it is refused — void or delete those bills first; a rule with non-void lines in its cycle cannot be retracted. Run every rule correction / retraction under READ COMMITTED (refused otherwise) and expect it to WAIT behind in-flight line writes for the same rider. Line writers: a capped line insert may fail with `serialization_failure` either from the per-meter mutex (AC-27) or from the rule row's FOR SHARE when the rule was concurrently corrected — retry the transaction in both cases. A line written for a rider before its rule exists passes at INSERT but is re-validated at issuance against current knowledge — do not treat a clean INSERT as final until the invoice issues.

### AC-30 — Tax exemption certificate evidence, config shape, and the renewal queue — REJECTS
*Introduced by v5.4.2-09 (CI-046, D-2026-09-04-01…-07).*

Verifying an exemption into `active` — or writing an `expired` / `revoked` successor row — requires certificate evidence: `certificate_number` or `certificate_url` containing **at least one alphanumeric character** (whitespace-only and punctuation-only values are not evidence), unless the tenant flipped that category to flag-only in `tenants.settings.tax_exemptions.certificate_required.<exemption_type>`. The refusal is `check_violation` (23514). Drafts (`pending_verification`) are exempt from the gate; asserted rows are frozen by A-1 and are never re-judged by later config flips — flips are consulted at entry to assertion only and are audited by `tenant_configuration_history` (v5.4.1-02). The knob is an omission barrier, not a fraud barrier.

Config shape is enforced loudly at read: `tax_exemptions` must be an object when present, `certificate_required` an object of per-category JSON `true`/`false` (`"true"`/`"false"` strings accepted), `renewal_notice_days_before` a positive integer of at most nine digits (default 60). A wrong-shape node at either level, an unknown/retired category (`industrial` left the domain at R-13), or any other value raises `check_violation` — the read that consulted it is refused rather than a direction guessed. One tenant's bad config loud-blocks that tenant's queue rows (and a platform-admin's global queue) until corrected — the A-20 `max_consecutive_estimates` precedent.

`customer_tax_exemptions_renewal_due` is the renewal work queue (security_invoker; RLS applies): a row enters ON the day exactly `renewal_notice_days_before` days remain (`notice_window_opened_on = effective_end − N`). `'renewal_due'` rows want a renewal entered as a NEW row — never an `effective_end` edit (the bracket froze with the assertion); they are quieted by a renewal on file (a later-bracketed open active assertion, same customer and category). `'lapsed'` rows (past `effective_end` — the end date itself is still covered, the bracket is inclusive) stay listed even with a renewal on file: they owe their valid-time expiry succession (close + `expired` successor carrying the same bracket and the evidence) and leave the queue when it lands. The queue reads the exemptions table only — the legacy `customers.is_tax_exempt` display columns are not consulted by any tax path and must not be treated as authoritative.

Deploy note: the v5.4.2-09 precondition refuses to apply while any CURRENT assertion head (active, or an unsuperseded expired/revoked head — those still suppress tax for their bracket on rebills) lacks required evidence. Remediation: a correction row carrying the evidence, a retraction (certificate never existed), or the flag-only flip. Preconditions bind only under the repo-standard `psql -v ON_ERROR_STOP=1` apply.

### AC-32 — Every patch calls `assert_tenant_isolation_invariants()` in its tail; a new table, view or matview is born leaky until it does — REJECTS

`public.assert_tenant_isolation_invariants()` (v5.4.2-11, owner-only, invoker rights) raises unless every tenant-isolation invariant still holds. **Call it in the tail of every future patch, and last in the container build.** It is not decoration: these invariants are true when a patch applies and drift at the next `CREATE`, because `tu.sql`'s `ALTER DEFAULT PRIVILEGES ... ON TABLES TO tally_app` covers views and matviews.

What the database will refuse to certify:

| Drift | What you must do |
|---|---|
| A new table with a `tenant_id` column | `ENABLE` **and** `FORCE ROW LEVEL SECURITY`, plus a policy `USING (is_platform_admin() OR tenant_id = get_user_tenant_id())` — written in exactly that form and order |
| A partition child | Give it its own row security; it does **not** inherit the parent's, and a direct read of the child bypasses the parent's policy |
| A second permissive policy | Permissive policies are OR-ed — one `USING (true)` opens the table. Every permissive policy must be canonical, in **both** its `USING` and its `WITH CHECK` |
| A permissive `WITH CHECK (true)` beside a canonical `USING` | Read-isolated but **write-open**: any session can write rows tagged with any tenant. Refused |
| A new view | `ALTER VIEW ... SET (security_invoker = true)` — `CREATE VIEW` has no such default, and the owner is a BYPASSRLS superuser |
| A new materialized view | `REVOKE ALL ... FROM tally_app, PUBLIC`. A matview can carry neither `security_invoker` nor RLS; the grant is the only lever, and column-level grants count |
| A new `SECURITY DEFINER` function | Pin its `search_path` and keep it un-executable by PUBLIC |
| A default privilege granting PUBLIC EXECUTE | Global **or** per-schema — either reopens it for every new function |

`RESTRICTIVE` policies are exempt from the canonical-predicate test (they are AND-ed and can only narrow), but a table must still carry at least one permissive policy. A table whose predicate must legitimately differ is an explicit edit of the assertion, not a reason to weaken it. The key is the column name `tenant_id`: a tenant table whose discriminator is called something else is outside the check by construction.
