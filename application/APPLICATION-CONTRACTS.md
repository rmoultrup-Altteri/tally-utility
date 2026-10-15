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

### AC-4 — A file import names and hashes its file; one live commit per file; a job finishes in one write — REJECTS
*Introduced by v5.4.1-01 item 2.2 (`trg_populate_import_job_idempotency_key`); made a refusal by v5.4.2-19 (CI-118, CI-098).*

**Do:**
- **Name and hash the file.** A csv, excel, pdf or legacy_export import must carry both `source_filename` and `source_file_hash`, or it is refused. The hash's algorithm and format are the intake's (R13).
- **Expect a second copy of a file to be refused.** One live commit per tenant and file hash, whatever its `import_type` and filename. Previews and failed or cancelled jobs do not count. A renamed copy is refused; so is a fresh caller `idempotency_key`.
- **Treat the identity as write-once.** Tenant, initiator, import and source type, filename, hash, `is_dry_run`, `idempotency_key` and `created_at` never change.
- **Finish a job in ONE write.** Set the terminal status (`complete`, `partial`, `failed`, `cancelled`) together with the final row counts, `source_file_url`, `source_file_size_bytes`, `import_summary`, `validation_errors` and `completed_at`. After that, any write to them, or to the status, is refused. The counts are a snapshot at finish; staging rows stay the live record of held rows.
- **Mark a job that already committed rows as `partial`, never `cancelled`.** A cancelled job frees its file for re-import (R13).
- **Use the new types.** ACH return, lockbox and AMR files are `ach_return`, `lockbox` and `amr`.

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

### AC-12 — Void a bill only through `void_invoice()`; it names its caller — REJECTS
*Introduced by v5.4.2-01 as a SILENT contract on the `app.void_operation` setting; rewritten by v5.4.2-20, which removed the setting.*

`void_invoice()` is the only way to void a bill, release the reads it locked, or un-bill its ad-hoc charges. Since v5.4.2-20 it runs as `tally_void`, a role no login can become. The read, charge and invoice guards admit those writes because they run as that role, and only while the function runs. Setting `app.void_operation` (the v5.2.1 to v5.4.2-19 carve-out) now admits nothing. Every function body that read it is rewritten, and `assert_seal_role_invariants()` refuses any that does.

**Name the caller.** Set `app.user_id` to a user of the bill's tenant, or to a platform administrator, before calling. Row-level security is the tenant check: a caller with no user, a user that does not exist, or a user of another tenant gets `Invoice not found` (P0002). Before -20, a caller with no user could void any tenant's bill.

**Concurrency.** The function locks the bill (`FOR UPDATE`) before reading its status. A second void waits, then is refused (`is not voidable`).
- A write that attaches a read (`locked_by_invoice_id`) or a charge (`billed_on_invoice_id`) to a bill takes `FOR SHARE` on it. It waits for a void in flight, then is refused if the bill is now void.
- A void that waits behind an attach releases what was attached.
- A voided bill takes no new reads or charges: bill them on its correction.
- **Isolation (r2):** call `void_invoice()` at READ COMMITTED. Any other level is refused (`invalid_transaction_state`), because an older snapshot would miss a charge attached while the void waited. An attach at REPEATABLE READ behind a void fails to serialise (40001); retry it.
- **Deadlock:** a transaction that already holds a row attached to a bill (an edit of a billed charge, say) and then attaches another can deadlock with a void of that bill. PostgreSQL aborts one (40P01) and nothing is left half-done. Retry the aborted transaction.
- **Which bill:** a read or charge names only a bill of its own tenant that the caller can see. Anything else is refused, a platform administrator included.
- **Billed means billed on a bill:** a charge is `billed` if and only if it names its bill (`adhoc_charges_billed_names_its_bill`). Set the pointer and the status in one write.

**History loads.** Only a superuser may INSERT a bill already `void`.

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

### AC-24 — A deposit is a `deposits` row plus `deposit_events`, decided by the core and citing the law row (and the tariff row) it was decided under; never write `deposits.status` / `refunded_on` / `released_on` or any `customers.deposit_*` column; post the events in the order the ledger requires — REJECTS
*Introduced by v5.4.2-06 (CI-077 / CI-129 / CI-130 / CI-131, D-2026-08-28-36…-42); rewritten at v5.4.2-15 (the deposit law leaves the database; Ryan 2026-09-28 and 2026-10-12).*

**The database no longer decides deposit law.** Whether a deposit may be required, how large, what it earns and when it is returned are the calculation core's, read from the law (`deposit_rules`) and the utility's own policy (`deposit_tariffs`). The database keeps the record coherent and refuses the arithmetic and citation errors below; it does not refuse a deposit a waiver forbids or an interest figure the law does not support. Every record shows what it was decided under, so a wrong decision is findable.

**Law and policy.** `deposit_rules` is platform-held and never edited: one row per (state, service, owner types, customer class, basis, dates), its content a validated document (`terms`: the cap, the triggers for an additional deposit, the waivers, the interest, the return rules, the instalments). Texas gas is seeded: eight rows for investor-owned and cooperative utilities (16 TAC 7.45, 11 U.S.C. 366) and eight **delegations** for a city-owned system (7.45 does not bind it: its policy is its tariff). Another state or service has no row — the core refuses; unknown law is not permission. The utility defines its own deposit categories (`deposit_utility_categories`: owner, renter, small commercial …, each mapped to exactly one law class) and one tariff per category (`deposit_tariffs`, a document measured against the law of the category's class when written, never looser).

INSERT `deposits` with `basis` (credit_evaluation | adequate_assurance_366 | additional_trigger + `trigger_basis` | tariff — never legacy_unknown), `instrument` (cash accrues interest; anything else needs `instrument_reference`, may carry issuer/expiry, is released not refunded), `principal`, `posted_on`, `source_payment_id` (a payment of the customer flagged `is_deposit`), and what it was decided under: `state_code`, `service_type`, `system_kind`, `customer_class` (the law class) and the utility's `tariff_category` (which must be one it defined for that state and service, mapped to that class), `rule_id` (**always**: a city's delegation row for a city), `tariff_id` (required where the law row delegates, and wherever the deposit has a category and a tariff row is in force for it on `posted_on`; a deposit with no category may skip every tariff, the statutory cap still holds), and `decided_by` (the core version). Record the cap that applied: `cap_amount` (principal ≤ cap_amount − `cap_other_held`), `cap_source` (`statute`, with `cap_component` the id of the document's cap part that governed and `cap_basis_amount` the figure it was computed from; or `tariff`, citing the row), `cap_binding` when it bit — a tariff's cap may be tighter than the statute's, never looser, and never above the tariff's own amount. An additional deposit records the trigger it was decided on (`trigger_source`, `trigger_component`) and the measure observed (`trigger_observed`), which must meet that trigger's threshold. A deposit taken in instalments records `received_at_posting` and, in the same transaction, its `deposit_instalments` rows (numbers from 2, as the cited document schedules; received + instalments = principal; the set is complete at commit and closed afterwards). Identity is frozen after insert — a wrong deposit is refunded or released and posted again. The database writes the `posted` event.

Then only events, each dated on or after posting: `instalment_received` (no more than is still to come), `applied_to_balance` and `principal_returned` (a partial return: part of what is held goes back, by agreement or as a due row's amount; it may be recorded without a due row, and when it cites one its amount is exactly that row's), `interest_accrued` (cash only; a law row of the deposit's key and a rate row of the utility's own for the state, service and category in effect by the period's start, `rate_applied` exactly that row's, `rate_id`, `rule_id`, `calculated_by`; `principal_basis` no more than the least principal held over the period; the period has ended, ends before `effective_on`, never overlaps another, never spans a partial return or ends on/after a full one; whether interest is owed and how much is the core's), `interest_credited` (≤ accrued for periods ended before its date − credited), `refund_initiated` (amount = remainder), `refunded` (cash) / `released` (non-cash) (amount = remainder, 0 when fully applied; nothing accrued may be left uncredited, since nothing can follow). **Money cannot leave before it arrived:** an application or partial return must leave the principal held non-negative on its own day and on every later day an event is recorded for (a later instalment does not fund an earlier return), and a refund, release or refund notice is dated on or after every receipt, application and return already recorded — and not before its own refund notice. A refund notice ends receipts and returns; a refunded/released deposit accepts no more events. These guards read the events, so several events written in one statement are judged row by row. A refund or release may cite the return-due row it settles (`return_due_id`). Link the ledger row that moved the money via `ledger_entry_id` (same customer; `deposit` / `adjustment` / `deposit_interest` / `refund` / `credit_issued`). A deposit_refund `customer_credits` row names its `deposit_id`. Events are append-only. Read balances from `deposit_balance(deposit)` and the principal held on a day from `deposit_principal_in_force(deposit, day)`. A legacy (`legacy_unknown`) deposit carried from -06 cites no law row, accrues nothing, and may be refunded with a `reason` stating how its interest was settled. **Waiver determinations** (`deposit_waiver_determinations`) are untouched by -15 and not tied to the new law or tariff documents; the rewrite waits for a core that records them (residual R6).

### AC-25 — Enter the utility's own deposit interest rate as effective-dated rows before accruing, never below the floor the law sets; record a return that fell due once, when the answer changes; read `deposits_return_owed`, never estimate a trigger yourself — REJECTS / SILENT
*Introduced by v5.4.2-06 (CI-125 / CI-131, D-2026-08-28-38/43); rewritten at v5.4.2-15 (R-D1, R-D2; Ryan 2026-10-12 decisions 1 and 4).*

`deposit_interest_rates` is **the utility's own rate**, per tenant, state and service, optionally for one of its own deposit categories (NULL = every category), effective-dated (`effective_date`, `annual_rate` as a fraction) and append-only: a new rate is a new row. The state's rate is a **floor**: a rate below the floor the law sets (a fixed rate, or the published value named by the law row, in force on the row's date) is refused where it is written; a mapped class with no law row in force, or a published value not recorded (`tx_deposit_interest_rate` has no values until a reviewed migration enters them from its publication), is refused rather than guessed. A rate dated on or before a settled accrual period is refused — a correction is a new rate going forward. Every accrual cites the row it used (AC-24); `deposit_interest_rate_as_of()`, `deposit_accrual_amount()`, `deposit_refund_trigger_state()` and the `deposits_refund_due` view are **gone** — the core finds the rate row and computes the amount and the trigger, and the database checks the citation and the arithmetic.

A mandatory return that has fallen due is the core's record, not a view: INSERT `deposit_return_due` (deposit, `due_on`, `amount` for a partial return — an excess over the cap — or NULL for the whole remainder, the law row, the inputs and their fingerprint, `calculated_by`) with its `deposit_return_due_evidence` rows **in the same transaction** (each reason names the return rule it rests on, and a bill with the core's classification, a customer state change, or the deposit itself; evidence is required, not proved complete — whether the core cited every bill it counted is the core's). Write it when the answer **changes**, never per check. At most one live row per deposit. A row found wrong is withdrawn once (`deposit_return_due_withdrawals`, with a reason, by a person or the core) and the corrected answer is a new row naming it (`supersedes_due_id`); a customer falling behind after qualifying is not a withdrawal. No due row may stand once the deposit's return has started (a refund notice, refund or release that does not cite it — judged when the statement ends). `deposits_return_owed` lists the live rows on deposits with no refund begun (`amount_due` NULL = the whole remainder); a deposit fully applied stays listed until its zero refund is recorded — interest may still be owed at refund. It reads recorded answers and computes no law; a row that persists is an unmade return. A deposit refund is never routed into `minimum_refund_amount` / `below_threshold_action` (table #54 rule 8 — workflow).

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

---

## Hardening batch 1 (v5.4.2-19)

*All introduced by v5.4.2-19 (step 1, wave 1). The patch header's "What changes" list and residuals R1–R18 are the authority; this section is what a writer must do.*

### AC-34 — The core writes a read's usage; a read is born unconsumed; only a billing run locks it, with its bill, in one write; a consumed read is frozen but for follow-up — REJECTS / SILENT
- **Usage:** the database no longer computes `meter_readings.consumption`, so the core writes it, including rollover and the multiplier (CI-022). A read the core never gives usage to drops out of `usage_statistics`, which filters NULL consumption: **SILENT**.
- **Born unconsumed:** an application INSERT may not carry a lock record. That means no locked or void_released status, no `billing_period_locked`, no `locked_*`, no `voided_from_invoice_id`. On a read no run has consumed, those fields are written only by the move to `locked`; `voided_from_invoice_id` is written only by `void_invoice()`.
- **Locking:** a billing run sets `validation_status = 'locked'`, `billing_period_locked`, `locked_by_billing_run_id` **and `locked_by_invoice_id`** in the SAME UPDATE. A read locked without its bill pointer can never get one, and `void_invoice()` can never release it (R15). `locked_at` is the database's.
- **After consumption** (locked or void_released), every column is frozen except the follow-up fields: notes, tamper investigation, dispute fields, `status`, follow-up, assignee, `replaced_by_reading_id`, `triggers_correction_workflow`. A correction run re-locks a `released_to_billing` read under its own run. A read in locked or void_released always carries `billing_period_locked`, history loads included.
- **Previous-read selection:** marking a consumed read `disputed` or `voided` (its `status`) changes which read the next read takes as its "previous" (R18). Field-reader confirmation and `quality_flag` are frozen after consumption.

### AC-35 — Payments: effective date and method when the payment takes effect; an ACH return's code; one receipt and one money-out per processor id; lineage within the customer — REJECTS
- **Effective date:** a payment in any status but `pending` or `voided` carries `effective_date` and `effective_date_method` (`postmark`, `lockbox_receipt`, `bank_settlement`, `other`). Both are write-once once it has left pending (CI-058). Which method applies is the core's.
- **Return code:** an ACH payment going to `nsf` carries `return_code` (`R` + two digits). It is write-once, and allowed only on `nsf` or `reversed` (CI-052).
- **One per processor id:** one positive row (`amount > 0`, a replacement for a bounced payment included) and one negative row (a refund, a chargeback, any money out) per (tenant, `source_system`, `provider_transaction_id`).
  - A further refund of the same payment, or a chargeback after a refund, carries the processor's **own** id for that event.
  - An ACH re-presentment is a new transaction with its own id.
  - On a `unique_violation` from either index, compare the rows before treating it as a harmless redelivery.
  - The index keys on the capture channel, so the core matches one transaction arriving by webhook and again in a settlement file (R17).
  - A zero-amount row is not counted.
- **Lineage:** a row citing `refunds_payment_id` is a negative `refund`. `refunds_payment_id` and `nsf_original_payment_id` cite a payment of the same tenant and customer, never the row itself. A cited payment cannot be moved to another customer.
  - To move a cited pending payment with its pending refund, use three writes: clear the refund's pointer; move the payment; move the refund and re-point it in one UPDATE.

### AC-36 — A changed bank account or card is a new `payment_methods` row that supersedes the old; never edit the identity — REJECTS
The account identity is frozen once written: customer, provider, token, method type, last four, bank, account type, holder. Card-updater expiry and the nickname stay editable.
- **A change is a new row** with `supersedes_payment_method_id` and `supersede_reason`, either `customer_update` or `ach_notice_of_change`. The latter carries `noc_change_code` (`C` + two digits) and `noc_received_at`, from which the core runs the NACHA window.
- **The database deactivates the predecessor.** It cannot be reactivated or made the default, and each row has at most one successor. Retry on `serialization_failure`.
- **A payment may still cite an inactive method,** for a late confirmation of a charge on the old account. Choosing the account to draw on is the core's, and it must not draw on an inactive method (R16).

### AC-37 — Dunning, escheatment and AI audit rows are written once, complete; an AI-created order or charge cites its audit row — REJECTS
- **Append-only logs:** `dunning_events`, `escheatment_events` and `ai_audit_log` refuse UPDATE, DELETE and TRUNCATE, and UPDATE is revoked. Write each row complete. Their `created_at` is the database's; a superuser's history load keeps its value.
- **AI citations:** a `service_orders` row with `created_by_ai`, or an `adhoc_charges` row with `source = 'ai_suggestion'`, cites its `ai_audit_log` row through `ai_audit_id`. The citation must be of the same tenant, and the flag, source and citation are write-once. The check proves a citation exists, not that it is the right action (R11).
- **Ledger:** `account_ledger.created_at` is the database's too. It is the recorded coordinate of `account_balance_as_of()`.

### AC-38 — An anomaly carries its `dedup_key`; a recurrence updates the canonical row — REJECTS
`anomalies.dedup_key` is NOT NULL and immediately unique.
- **Recurrence:** update the canonical row. Raise `recurrence_count` and move `last_detected_at` forward, never back and never before `first_detected_at`.
- **Write-once:** `dedup_key`, `first_detected_at`, `created_at`, and the subject and detection fields (`entity_type` / `entity_id`, customer, meter, location, `detected_at`, detection method and detector).

### AC-39 — A bill image is recorded with its SHA-256; an issued bill's image and hash are frozen — REJECTS
Set `invoices.pdf_url` and `pdf_sha256` together; on a draft or held bill, change them together. Once the bill is issued, both are frozen (CI-096).

### AC-40 — Ad-hoc approval captures its threshold; medical holds carry attestation; rider dependencies take headers first — REJECTS
- **Ad-hoc approval:** a charge that requires approval records the threshold in force at creation. `requires_approval` and the threshold are write-once (CI-127).
- **Medical holds:** an enrollment in a program type that `requires_attestation` (`medical_certificate`) is active only with its attestation received. A verifier needs a verification time, and verification falls on or after receipt (CI-062).
- **Rider dependencies:** they form a DAG within one tenant, and the database refuses a cycle. Lock order:
  1. Take the schedule headers first, in schedule-id order (`assert_reference_version` or the dependency write's own bump).
  2. Write dependency rows only after that.
  3. Retry the whole transaction on `deadlock_detected` or `serialization_failure`.
  - A dependency on an archived schedule is accepted (R12).

### AC-41 — A balance is a sum of the ledger; there is no stored running balance — REJECTS
`account_ledger.running_balance` is dropped (CI-019, Ryan 2026-10-13). Read a balance with `account_balance_as_of(customer, on_date, recorded_at)`: all three arguments are required, and an invisible customer raises. `void_invoice()` returns `credit_balance` as the same sum.


### AC-42 — Call `assert_reference_version()` first, in the same transaction, before any rate, item or zone edit — REJECTS
*Introduced by v5.4.2-20 (CI-011, D1-1).*

Before writing a version of a `rate_schedules`, `rate_items` or `wna_zones` entity, call `assert_reference_version('<header table>', id, <the version you read>)` **in the same transaction as the write**. This covers:
- inserting its first version;
- closing a version (supersede or retract);
- inserting a successor;
- a lifecycle move of the header (`status`, and on schedules `archive_reason`, `activated_at`, `archived_at`).

The database refuses each of those writes unless the transaction holds the check's receipt for that entity at its current version.

**What it returns.** The new version. Keep it if you check again in the same transaction.
- **Stale token:** `40001` ("modified since it was read"). Re-read the entity, show the editor the change, and retry.
- **Entity not visible:** `P0002`. It is not retryable.

**What the database cannot prove.** That the token came from the read the edit is based on. Pass the version the editor saw, never one re-read just before the call: a fresh read always passes and turns the check into last-writer-wins (v5.4.2-20 residual R2).

**Shape of the transaction.** In autocommit, the check and the write as two statements fail. So does a check whose savepoint was rolled back. The app holds no UPDATE on `version`.
- An `updated_at`-only write needs no check (the `rate_item_dependencies` mutex).
- A header is created at version 1.
- Schedule composition (`rate_schedule_items`, `rate_item_dependencies`) is outside the token (R7).

### AC-43 — Set `app.user_id` only from the verified Cognito token, with `SET LOCAL`, in one place — TRUSTED
*Decided 2026-10-14 (-20 residual R1). The database cannot check this; it acts on whatever `app.user_id` says.*

- **Source:** the user whose identity matches the `sub` of the Cognito token the middleware has just verified. Never take it from a request body, a header the client controls, a cache or a previous request.
- **Scope:** `SET LOCAL app.user_id` (or `set_config('app.user_id', …, true)`) inside each transaction. With a connection pool, a session-level `SET` leaks to the next request that borrows the connection, which then acts as the previous user.
- **One path:** a single middleware sets it. No other code sets or changes it.
- **No user:** for work with no human caller (jobs, imports), name a dedicated service user. Never borrow a real user or a platform admin.
- **Never the empty string:** an empty `app.user_id` raises on the `::uuid` cast in the RLS helpers.
- **Binding (v5.4.2-21 r2):** a user's `cognito_sub` is written by a supervisor's session (tenant_admin or platform admin) when the user is provisioned. Cognito's admin create returns the sub. A new user's own first login cannot bind it, and a supervisor also switches users on or off (`is_active`). Once set, a binding never changes.
---

## Meter test history

### AC-33 — Record meter tests as raw readings in `meter_tests`; never write the meter's test columns; the cutover date is the platform's — REJECTS
*Introduced by v5.4.2-12 (CI-091; Kyle R-31, R-34…R-36).*

**Recording a test.** INSERT one `meter_tests` row per test with `record_basis`:
- `recorded` — a test performed on or after `tenants.cutover_date`. Needs `performed_by_name`, `test_equipment`, `meter_serial_at_test`, `multiplier_at_test` > 0, and EITHER `load_results` (a JSON array of `{load_point, standard_volume, meter_volume[, notes]}`, volumes with at most four decimals, standard > 0, meter ≥ 0) OR an `inconclusive_reason` when the test produced no valid measurement.
- `migrated_full` — a pre-go-live test with the full field list AND readings, dated on or before cutover.
- `migrated_date_only` — a pre-go-live test known only by its date (optionally the result the legacy records show), dated on or before cutover.

**Never supply** `outcome` (except on a date-only row), `max_abs_error_pct`, `found_defective` or any `threshold_*` column: they are derived, and supplying one is refused. A `customer_requested` test needs `customer_id` and `location_id`. `location_id`, if given, must be the meter's location or one it was deployed at, in the same state. A `service_order_id` must be a `meter_test` / `meter_test_failed_replace` order for the same meter. `test_date` may not be in the future.

**Never write** `meters.last_test_date`, `last_test_result` or `test_history_absence` (refused, even for the owner), and never insert into `meter_test_load_results` directly. `next_test_due_date` and `test_interval_months` stay writable.

**Correcting a test.** Insert a new row with `supersedes_test_id` and a non-blank `supersede_reason`, on the SAME `test_date`, with a `record_basis` at least as strong, and with readings if the original had readings or found the meter defective. A row can be superseded once. A test entered against the wrong date cannot be corrected (R13 — a question for Kyle).

**No history.** Declare what is known in `meter_test_absence_declarations` (`attested_none` or `unknown`, with a `basis_note`). `meter_test_history_gaps` is the standing operator report of meters with no history.

**Cutover.** `tenants.cutover_date` is set by the platform (a platform administrator via `tally_app`, or the owner at onboarding) **before** any test is recorded or migrated history loaded. A change must run under READ COMMITTED (a tenant INSERT carrying its cutover is exempt) and should be the first row lock in its transaction; on a deadlock, retry. It may not fall before a migrated test or after a recorded one.

**Reading "the last test".** Call `meter_governing_test(meter_id, anchor_date)` — never `meters.last_test_date`. It returns exactly one row: the most recent non-superseded test strictly before the anchor, whatever its outcome, with `prior_test_failed` and `weak_provenance`; or, where none qualifies, NULL test columns and the declared `absence`. It never infers a date. **Since v5.4.2-14 it returns no `supervisor_gate`:** whether a correction needs a supervisor's approval (R-36) is the calculation core's. The core computes it from `weak_provenance`, the direction, the resolved rule's `before_anchor` term and `tenants.cutover_date` (`a2-rules-for-the-core.md` §9.1), and records it on `meter_correction_evaluations.approval_required`.

**Platform administrators.** A `tally_app` session may grant `platform_admin` only if it already is one, and may not change `users.id`.

