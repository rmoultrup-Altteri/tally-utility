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
is fine — the range is half-open).

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

### AC-3 — `location_id` is optional at the database level — SILENT
*Introduced by v5.4.1-01 item 2.6.*

The trigger fills `location_id` automatically, but the column is nullable. Reads
inserted for a meter whose `meters` row is missing a location can't happen
(`meters.location_id` is NOT NULL), so in practice it's always populated — but
application validation should treat a NULL `location_id` on a read as a data
defect to surface, not a valid state. CI-027 stays `partially-structurally-
enforced` for exactly this reason.

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
