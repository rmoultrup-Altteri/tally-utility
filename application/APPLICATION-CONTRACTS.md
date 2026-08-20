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
*Introduced by v5.4.1-02.*

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
