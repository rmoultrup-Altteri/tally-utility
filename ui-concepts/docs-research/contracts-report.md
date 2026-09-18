# Application obligations that shape a UI — TallyUtility

**Sources**
- `/Users/ryanscomputer/code/tally-utility/application/APPLICATION-CONTRACTS.md` (AC-1 … AC-32)
- `/Users/ryanscomputer/code/tally-utility/TECH-STACK-DISCUSSION.md`
- `/Users/ryanscomputer/code/tally-utility/HANDOFF.md`
- `/Users/ryanscomputer/code/tally-utility/application/DECISION-LOG.md`

**Framing caveat up front.** There is no application code, no API, and no UI. APPLICATION-CONTRACTS.md opens: *"No application code exists yet. This file is the running list of obligations the schema places on whoever writes it."* Everything below is a database-enforced rule the UI must surface, not an existing endpoint.

Second caveat worth flagging: the locked stack decision is **C#/.NET for the engine and API, TypeScript/React only for the portal**. A React/Next.js prototype is a UI-layer mock, not the real API tier (see §3).

**Status legend used by the contracts file:** **REJECTS** = the database raises an error; **SILENT** = the database accepts the write but the data is wrong. The SILENT ones matter most for a UI, because nothing will tell the user they were wrong.

---

# 1. User-visible obligations — what the UI must show, ask for, or forbid

## 1.1 Bills are immutable once issued — "edit" does not exist

**AC-10.** Once `invoices.status` leaves `draft`/`held` — and **`pending` counts as issued** (D-2026-08-20-16: *"'Issued' = `status NOT IN ('draft','held')`"*) — the billed content is frozen:

- identity, lineage pointers, period
- **every date including `due_date`**
- every total, `tax_breakdown`
- the estimated-read and anomaly flags
- `pdf_url` once set

Line items reject INSERT, UPDATE and DELETE entirely.

What **stays writable** on an issued bill, and may legitimately appear in the UI: status forward, `amount_paid`, `balance`, `dunning_stage`, `late_fee_*`, `write_off_*`, `delivery_*`, `notes`, `metadata`. (D-2026-08-20-17: immutability is column-scoped, not row-scoped — *"an issued bill keeps living in collections."*)

**Consequence: the only correction affordance on an issued bill is void → rebill.**

`status = 'void'` is written by `void_invoice()` only. Since v5.4.2-02 a direct UPDATE to `void` from **any** status — held and draft included — or an INSERT as `void` is rejected, *"because a bare void skips the ledger reversal, read release and charge disposition and is then sealed forever."* A void is terminal: notes and metadata only.

**Hard delete** is offered only for a **clean draft**: no billed adhoc charge, no locked read, and no `dunning_events` or `invoice_applications` children (both cascade from `invoices` and are in the CI-014 protected set — the error names the child table). Held invoices are never deletable: they carry an operator's reason and are voidable. Everything else retires through status.

## 1.2 Correction / rebill is a guided multi-step flow, not a button

**AC-31** is the heaviest single UI constraint in the corpus. A correction invoice must:

1. sit on a billing run with `run_type = 'correction'`;
2. carry `replaces_invoice_id`;
3. have a `correction_run_targets` row for (run, replaced bill) — **"record the operator's election first"**;
4. point at a replaced bill that is RLS-visible, same-tenant, `status = 'void'` (through `void_invoice()`), and **once actually issued** (`first_issued_at` set — *"a held-then-voided discard cannot be corrected"*).

D-2026-09-08-03 records that Ryan ruled strict on (1) and (3): an off-run manual rebill is refused, because *"the target row is where the operator's rate-date election is recorded (CI-005); a rebill with nowhere to record its election is exactly the bill an auditor asks about."* This was a new rule, chosen knowingly.

**The operator's election is the rate-date mode**, and the UI must collect it:

- `historical` — the voided bill's `period_end`
- `current` — the session's `CURRENT_DATE` (run the election and the snapshot insert in one session TimeZone)
- `custom` — an explicit override

`valid_at` must equal `get_correction_rate_date(run, replaced)` at insert.

**One live rebill per bill LINEAGE** (D-2026-09-08-08). The check walks `replaces_invoice_id` to the root and looks at every descendant at any hop. *"Only one live (non-void) rebill anywhere in a bill's lineage … may carry a snapshot; void the earlier correction to correct again."* The UI must show the lineage and explain this refusal, because per-hop intuition gets it wrong.

**Type restrictions.** Only `correction`, `credit_memo` and `duplicate` may carry `replaces_invoice_id` through the binding. A `regular` / `final` / `prebill` that replaces a bill is refused as *"a correction in all but name."* Credit memos and duplicates must point at a visible same-tenant bill and do not count toward the lineage.

**Ordinary (non-correction) invoices**: `valid_at` must equal the invoice's `period_end` **exactly** — not "a date inside the period" (D-2026-09-08-01, Ryan strict). `recorded_at` must lie in `[billing_runs.started_at, now()]` on a run, or `[invoices.created_at, now()]` off-run. Pass the writing transaction's `now()`; **never `data_cutoff_at`**, which is the candidate-set freeze line, not a lookup coordinate.

Refusals in this family are `check_violation`; freeze refusals are `restrict_violation`.

## 1.3 Every rate lookup is date-effective and needs an explicit two-axis coordinate

**AC-15** is the most pervasive rule in the system. Nine functions —

`rate_schedule_as_of`, `wna_zone_as_of`, `rate_item_as_of`, `rate_schedule_item_as_of`, `franchise_fee_as_of`, `customer_tax_exemption_as_of`, `wna_monthly_adjustment_as_of` (its valid coordinate is `p_billing_month`), `should_charge_tax(...)`, `get_partial_period_policy(...)`

— **all require both `p_valid_at` and `p_recorded_at`, raise on NULL, and none defaults to `now()` or falls back to any live column.**

**Zero rows is a hard error.** *"A result of zero rows (or NULL from `get_partial_period_policy`) means 'unknowable at that coordinate' — a hard error, never 'use the current value.'"* This descends from the standing rule in D-2026-08-20-09: *"no live-value fallback; NULL coordinate raises; NULL result means 'unknowable,' never 'use the default.'"* The UI must render this as an error state, never a silent fallback to today's rate.

**Three call shapes:**
- a new bill passes (service period, `now()`)
- a correction run — the default — passes (original period, `now()`), so a correction discovered since is applied
- reproducing or defending the original bill passes (original period, the original run's instant)

Resolve the pair **once per billing run** and pass the same pair to every lookup in that run. (Noted as still application discipline — see §4 residuals.)

`get_correction_rate_date()` returns only the valid-time coordinate and NULL when its target is missing — substitute and log before calling any lookup, never pass the NULL through. `get_effective_rate()` and `archive_rate_item_history()` are **disabled stubs that raise**; compose `rate_schedule_item_as_of` over `rate_item_as_of` instead. `rate_item_history` / `rate_item_history_archive` are retired read-only.

A DATE argument casts to midnight — *"pass an end-of-day `timestamptz` if 'in effect on that day' is the intent"* (AC-8).

## 1.4 Reference data corrections are close-then-insert, never edit

**AC-14.** Seven bi-temporal tables: `rate_schedule_versions`, `wna_zone_versions`, `rate_item_versions`, `rate_schedule_items`, `franchise_fee_rules`, `customer_tax_exemptions`, `wna_monthly_adjustments`. Once a row is asserted (`recorded_at` set), **every content column is frozen.**

The UI's "edit a rate" button must actually mean one of three shapes:

- **Correction** — close the row (`closed_type = 'superseded'`, required `closed_reason`), then INSERT the corrected row with `supersedes_id` = the closed row's id (same entity, same tenant — the guard checks), `change_type = 'correction'`, and a `change_reason`.
- **Succession** — a scheduled change that corrects nothing: same shape, `change_type = 'succession'`, closing and re-asserting the prior bracket with an `expiry_date` when a new bracket follows.
- **Retraction** — a close as `closed_type = 'retracted'` with no successor.

**At commit, a row closed as `superseded` must have an asserted successor of the same entity, or the transaction fails.** (A DEFERRABLE INITIALLY DEFERRED constraint trigger; D-2026-08-28-02 records that reviewers reproduced both cross-entity and draft satisfaction of an earlier design.)

The only writes an asserted open row accepts are the close itself — one UPDATE setting `recorded_until` (**the value you pass is ignored; the database stamps `now()`**), `closed_type`, `closed_reason`, optionally `closed_by`, with **every other column byte-identical** — plus the per-table lifecycle set (`wna_monthly_adjustments.status` forward; `notes` / `metadata` / `updated_at`).

**Optimistic concurrency the UI must render.** For the three header tables, call `assert_reference_version('<table>', id, version_you_read)` **first in the transaction**. It rejects a stale token with `serialization_failure` and the message *"review and retry"*, and row-locks the header so concurrent writers serialise. So: read a version token with the form, send it back on save, and render a real "someone else changed this — review and retry" state. A raw `UPDATE … SET version = version + 1` is accepted by the trigger and bypasses the check — do not write it.

For the four in-place tables there is no counter: predicate the closing UPDATE on `recorded_until IS NULL` and treat 0 rows as "stale, re-read."

Nothing in these tables is ever deleted, **including drafts**.

## 1.5 Rate schedules: draft → activate, with gates

**AC-17.** `INSERT INTO rate_schedules` must be (and defaults to) `status = 'draft'`. Insert the `rate_schedule_versions` row(s), then set `status = 'active'` — the trigger requires an open version and stamps `activated_at`.

- A `draft` or `archived` schedule **cannot** be assigned to `meters.rate_schedule_id` or `meter_deployments.rate_schedule_id`.
- Archiving requires `archive_reason` **and** every open version to carry an `expiry_date` first (assert the valid-time end, or retract). An archived schedule accepts no new versions and is terminal.
- **`expired` is not a schedule status** — read the version's `expiry_date` (D-2026-08-28-06: transaction-time death is `recorded_until` only; valid-time death is `expiry_date` / `effective_end` only).
- `UNIQUE (tenant_id, code)` is **permanent** — the UI should warn that a code is forever. Multi-service tenants namespace internal codes (`GAS-R1`, `WTR-R1`); the filed designation goes in `tariff_number`.
- One schedule = one service. `service_type` may change only as a transcription correction: a `correction` row over the predecessor's exact valid bracket with `service_type_change_basis = 'transcription_error'`. If any invoice line references the schedule, the database queues an `anomalies` row (`reference_correction_review`, severity high) that an operator must resolve. A re-tag that moves customers between regulatory regimes is a **new schedule**, not a correction.

## 1.6 Meters: relocation is not an edit

**AC-7 (SILENT — the dangerous kind).** `sync_meter_deployments()` opens and closes `meter_deployments` rows only on `meters.status` transitions. *"A bare `UPDATE meters SET location_id = B` while `status = 'active'` is accepted, leaves the open deployment pointing at A, and every subsequent read snapshots A. Nothing raises."*

**Do, until ruled:** never change `location_id` on an active meter directly. A real relocation goes through the status cycle (`inactive` → `active` with the new `location_id` and a real `start_date`), which closes and reopens the deployment. A data-entry correction should also correct the `meter_deployments` row in the same transaction.

**AC-1 (REJECTS).** On reactivation the UI **must collect the actual reinstall date** and set `meters.start_date` in the same UPDATE that sets `status = 'active'` (≥ the previous deployment's `removal_date`; same day is fine, the range is half-open). Leaving the original `start_date` makes the new deployment row overlap the closed one and the EXCLUDE constraint rejects the whole UPDATE. Symmetrically on deactivation: either leave `removal_date` NULL (the trigger uses today) or set it ≥ the open deployment's `install_date`.

*Why the schema doesn't do it for you:* the trigger can't know the true reinstall date, and *"guessing `CURRENT_DATE` or `GREATEST(...)` would fabricate a date and silently record the wrong one."* D-2026-08-20-03: the schema cannot tell relocation from typo-fix, so **the UI has to**.

**AC-2 (SILENT).** `meter_readings.location_id` is a snapshot filled once on INSERT and deliberately never re-derived on UPDATE. If the UI corrects a read's `reading_date` across a deployment boundary, `location_id` goes stale. **Prefer the supersede pattern** (new read row, old one `replaced`) over in-place date edits — a new row gets the snapshot for free.

**AC-3 (SILENT, and a real tenant hole).** `meter_readings.meter_id`'s FK is **not tenant-scoped** and FK checks bypass RLS. A read inserted by tenant A against tenant B's meter passes the FK while both of the trigger's lookups return nothing under RLS, leaving `location_id` NULL with no error. *"Application validation must (a) check the meter belongs to the caller's tenant before inserting, and (b) treat a NULL `location_id` on a read as a data defect to surface, never a valid state."*

## 1.7 Meter reads: a workflow with an exception queue, not a data grid

**AC-20.** When VEE or an operator finds a read failing a rule, INSERT a `read_validation_exceptions` row. **Every step of the read into `approved` / `released_to_billing` / `locked` is refused while any row is open** — an exception raised after approval stops the read at its next step. `billing_run_meters` refuses `billed` / `billed_estimated` against such a read.

Set `validation_status = reviewed_with_exception` only when such a row exists; `reviewed_clean` only when none is open.

An exception may **not** be raised on a `locked` / `void_released` read — correct a billed read with a replacement reading. Rows are never deleted; a resolved row is frozen.

**AC-21.** The consecutive-estimate streak is the database's. The UI must never write `meters.consecutive_estimate_count`, the streak columns, or `meter_readings.validated_at`.

Inserting an estimated main-register read that would bring the meter to `tenants.settings.estimation.max_consecutive_estimates` (default 3, must be ≥ 1) **auto-opens** a `consecutive_estimate_over_cap` exception. Approving that read requires the exception resolved by `override` (reason-coded) or `field_order_dispatched`. If no exception was raised (cap lowered after insert, or a pre-patch pending estimate), approval is still refused — the operator raises the exception by hand (`detected_by = 'operator'`) and resolves it.

Streak definition (D-2026-08-28-27, after three failed designs): **validation decides membership, reading date decides order.** Validated estimates dated after the latest-dated validated actual. A validated actual dated at/after the streak clears it; a back-dated actual does not; a same-day estimate beside an actual is not counted; a read excluded after validation stays counted; re-approving after `pending_review` does not recount. `consecutive_estimate_state(meter_id)` is the reconciliation function and always equals the stored columns.

Once a read is validated, `is_estimated`, `register_type`, `meter_id`, `reading_date` and `tenant_id` are frozen — correct with a replacement reading.

## 1.8 Bill exceptions: the UI holds the invoice, the database doesn't

**AC-22.** When a criterion fires, INSERT an `invoice_exceptions` row with `queue`, `blocks_delivery`, `routing_reason` (plus `sla_days`, `escalation_target`, `severity`, `estimated_impact`, `anomaly_id`, and `read_validation_exception_id` — required for `unresolved_read_exception` — as the routing decides). Stamps are the database's; `billing_run_id` defaults to the invoice's.

**Set the invoice to `held` (with `hold_reason`) yourself.** The database deliberately does not auto-hold (D-2026-08-28-31: a trigger rewriting status would fight A-4 and *"hide the operator action CI-115 records"*). And because A-4 forbids `pending → held`, **hold before release.**

While an open row has `blocks_delivery = true`, the invoice cannot enter `pending` (from draft or held) or `sent`, nor be stamped `sent_at` / `delivery_confirmed_at`.

`blocks_delivery` and `routing_reason` **cannot be edited** after insert — clearing `blocks_delivery` would be an override without a reason.

A blocking row cannot be raised on an already-delivered invoice — use the dispute workflow.

Every insert and resolution appends an `invoice_events` row (the database does it). Rows are never deleted; a draft-invoice delete cascades.

**CI-023:** `billing_run_meters` refuses `billed` / `billed_estimated` for a meter with `meter_master_incomplete_reasons(meter_id) <> '{}'` — route the meter to the read queue (rule `meter_master_incomplete`) instead.

## 1.9 Customer status changes always carry a reason

**AC-23.** Every status change must carry a non-blank `status_reason` and the acting user in `status_changed_by`, **in the same UPDATE**. The database writes the `customer_state_events` row and **clears both columns** — *"so never read them back and never expect a reason to carry over."*

D-2026-08-28-34 records why: an earlier draft left the reason on the row and a reviewer reused it for the next transition with a bare `SET status`. The BEFORE trigger now consumes and NULLs it; a reason on a non-status update is dropped.

History is read from `customer_status_as_of(customer, at)` and `customer_attribute_as_of(customer, attribute, at)`. Attributes: `billing_delivery_method`, `billing_hold`, `consolidate_invoices`, `do_not_disconnect`, `landlord_responsible`, `customer_type`, `autopay_enabled`, `deposit_status`. **Both return NULL before recorded history — never substitute the current value.** The log tables are append-only.

## 1.10 Deposits: an event ledger, never editable fields

**AC-24.** The UI must never write `deposits.status`, `refunded_on`, `released_on`, or any `customers.deposit_*` column — all are database projections of the event stream (D-2026-08-28-36: six representations were found disagreeing because each was written independently).

Creation requires: `basis`, `instrument` (cash accrues interest; anything else needs `instrument_reference`, may carry issuer/expiry, and is **released** not refunded), `principal`, `posted_on`, `source_payment_id` (a payment of the customer flagged `is_deposit`). For a Texas residential cash §7.45 deposit, the cap block is required: `cap_amount` (1/6 estimated annual billing), `cap_basis_annual_billing`, `cap_binding` when it bit, with `principal ≤ cap_amount` as a CHECK. **The cap's derivation is the application's** — D-2026-08-28-41: *"the database records and enforces what was decided; it cannot compute it."*

A §7.45-basis deposit is refused while the customer has a `deposit_waiver_determinations` row in force on `posted_on`. Waivers are recorded there (family-violence certification needs the TCFV reference) — deliberately in its own RLS table, *"among the most sensitive data the platform holds,"* and explicitly not on `customers`. Note: **no column-level access control exists** — flagged.

After creation, only events. Balances are read from `deposit_balance(deposit)`.

**AC-25.** `deposit_interest_rates` is per tenant and append-only; `deposit_interest_rate_as_of()` **raises** when no row covers a date, so the history must be entered back to the oldest posting date before the first accrual cycle. A rate dated on/before any settled accrual period is refused — a correction is a new period at the new rate going forward.

`deposits_refund_due` is a work queue view: *"a row that persists is an unmade statutory refund."* That is a dashboard item with regulatory teeth. §366 and legacy deposits never appear. The view's "paid clean" definition is stated as an approximation — the refund job records its own evaluation.

## 1.11 Tax exemptions: certificate evidence and a renewal queue

**AC-30.** Verifying an exemption into `active` — or writing an `expired` / `revoked` successor — requires certificate evidence: `certificate_number` **or** `certificate_url` containing **at least one alphanumeric character**. Whitespace-only and punctuation-only values are not evidence (D-2026-09-04-01: the drafted `btrim()` blank check let a single tab, newline or NBSP through; the whitelist closes the family in one move). Refusal is `check_violation` (23514).

The gate can be waived per category via `tenants.settings.tax_exemptions.certificate_required.<exemption_type>`, **default TRUE**. Drafts (`pending_verification`) are exempt from the gate. Asserted rows are frozen and **never re-judged by later config flips** — flips are consulted at entry to assertion only, and are audited in `tenant_configuration_history`. *"The knob is an omission barrier, not a fraud barrier."* Accepted residual: letter-bearing placeholders like "N/A" pass.

**Config shape is enforced loudly at read.** `tax_exemptions` must be an object; `certificate_required` an object of per-category JSON `true`/`false` (string `"true"`/`"false"` accepted); `renewal_notice_days_before` a positive integer of at most nine digits (default 60). A wrong-shape node at either level, or an unknown/retired category, raises `check_violation` — *"the read that consulted it is refused rather than a direction guessed."*

**`customer_tax_exemptions_renewal_due`** is the renewal work queue (security_invoker; RLS applies). Two row kinds needing different UI actions:
- **`renewal_due`** — enters on the day exactly `renewal_notice_days_before` days remain (`notice_window_opened_on = effective_end − N`). Wants a renewal entered as a **NEW row** — *"never an `effective_end` edit (the bracket froze with the assertion)."* Quieted by a renewal on file (a later-bracketed open active assertion, same customer and category).
- **`lapsed`** — past `effective_end` (the end date itself is still covered; the bracket is inclusive). **Stays listed even with a renewal on file** — it owes its valid-time expiry succession and leaves the queue only when that lands.

The queue reads the exemptions table only. *"The legacy `customers.is_tax_exempt` display columns are not consulted by any tax path and must not be treated as authoritative."* (D-2026-09-04-06: the divergence is display-only, recorded as a residual.)

## 1.12 Surcharge riders (Texas Pipeline Safety Fee)

**AC-26.** Before the first bill of an assessment cycle, INSERT one `regulatory_surcharge_rules` row per (rate item, cycle): `surcharge_kind` (`pipeline_safety_fee` needs `cap_per_service`, `excluded_from_tax_bases = true`, `exempts_state_agencies = true`, and a gas / all-service rider), `cycle_start` / `cycle_end` **as BILL dates**, plus references. One open rule per rate item per bill date; one open `pipeline_safety_fee` rule per tenant per bill date. Read through `regulatory_surcharge_rule_as_of(rate_item, bill_date, recorded_at)` — both coordinates required. A rider with an excluded rule can never assert `is_taxable_default` / `is_a_tax` / `is_taxable_override = true`.

**There is NO remittance gate** (D4-1): bill after remitting, never before — operator discipline, not enforcement.

**AC-27.** A line of a ruled rider must name its service (`meter_id`) when capped. The cycle's **positive** amounts per (rate item, meter) over non-void invoices, **drafts included**, may not exceed the cap. A negative line is accepted but lends no headroom — the way to bill again is `void_invoice()` + rebill. (D-2026-08-31-03: every netting variant leaked through the discard or void of the negative line's invoice.)

Set `customers.is_state_agency` (government customers only) and let the logger record it — **never INSERT into `customer_attribute_history` / `customer_state_events`** (refused; D-2026-08-31-05 closed that hole). A state agency at the end of the billed period may carry only a **0.00 line** — and the UI should still render it, because showing the exemption is CI-046's intended shape; a charge is refused.

**Every one of these checks runs again at issuance on current knowledge** — a draft edited after its lines were written (bill date moved into a cycle, customer changed) is refused at commit. *"Do not treat a clean INSERT as final until the invoice issues."*

Known gaps: a meter change-out mid-cycle resets the cap; two sessions writing capped lines for two meters in opposite order may deadlock (retry).

**AC-28.** For each `charge_type = 'tax'` line and each `percentage_of_bill` / `percentage_of_charges` line with a non-zero amount, INSERT one `invoice_line_item_bases` row per line it was computed on, with `base_amount` (non-zero, the cited line's sign, no larger than its amount — a partially taxable line contributes its taxable part).

**Write order: lines → bases → snapshot → status flip.** Issuance is refused while a non-zero tax/percentage line has no base row, a base row cites a line that left the invoice, a cited line shrank under its base, or a citing line is no longer a tax/percentage charge. A fixed charge cannot carry a composition; a line of a rider excluded from tax bases can never be cited as a base.

**AC-29.** A ruled surcharge line's `invoice_id` is frozen like its `rate_item_id` — relocate by delete + new line. A draft invoice carrying a ruled line keeps its bill date under the **same rule row** (within-cycle moves are free; delete the ruled lines before re-dating out). Run every rule correction/retraction under **READ COMMITTED** (refused otherwise) and expect it to wait behind in-flight line writes.

## 1.13 Invoice calculation snapshots

**AC-18.** Every invoice that leaves `draft`/`held` for any other status (`pending` included) **must have exactly one `invoice_calculation_snapshots` row at commit**; the transaction is rejected otherwise.

Write order: invoice (draft) → line items → snapshot → status flip. The validator refuses a snapshot for a parent already issued, and A-4 refuses lines on one, so an invoice cannot be INSERTed directly in an issued status.

Supply: `valid_at` / `recorded_at` = the ONE pair the run passed to every lookup; `snapshot_schema_version = 'v1'`; `formula_version`; `billing_run_id` equal to the invoice's; the eight sections with v1's required keys (every key present, `null` for a group that does not apply, `wna_inputs.applied = false` when WNA was not applied); `period_inputs.period_start/period_end` and `customer_inputs.customer_id` equal to the invoice's; `line_items[]` citing exactly the invoice's line rows.

**Never UPDATE a snapshot.** If a draft is recalculated or a line changes, DELETE the snapshot and insert a new one, or the issuance is rejected with "line items changed." Once issued, the snapshot is frozen (no DELETE); `void_invoice()` keeps it. Voiding a draft/held invoice needs no snapshot. Invoices issued before v5.4.2-04 have no snapshot and **cannot be given one**.

**AC-19.** For each `*_as_of` result the calculation used, insert an `invoice_snapshot_references` row `(snapshot_id, source_table, source_row_id, role)` before the status flip. Only rows open at the snapshot's `recorded_at` are citable — a draft (pending exemption, unapproved WNA row) or a row closed before the coordinate is rejected, *"which is correct: the run could not have read it at that coordinate."* Citations are optional per snapshot (a credit memo may cite nothing); `role` is free text. Concurrency is handled: a snapshot delete, citation insert or line edit racing an issuance waits on the invoice row and the loser is rejected — retry from the read.

## 1.14 Other cross-cutting items

**AC-4 (SILENT).** `import_jobs.idempotency_key` is NOT NULL and auto-derived as `<filename>:<hash>:<preview|commit>` — **but only when both filename and hash are present.** Otherwise it falls back to the job's own id, which is unique by construction and therefore **never detects a duplicate import**. Always populate both `source_filename` and `source_file_hash` for file-backed imports.

**AC-5 (SILENT).** Every lineage FK is nullable — `account_ledger.reverses_ledger_entry_id` / `reversal_reason`, `invoices.replaces_invoice_id`, `payments.refunds_payment_id`, `meter_readings.replaces_read_id`. `void_invoice()` populates the ledger pair itself; **any other code path that posts a reversal, replacement or refund must populate the lineage column** or the chain is unqueryable.

**AC-6 (SILENT under concurrency).** The three cycle-guard triggers (`landlord_customer_cycle`, `service_order_parent_cycle`, `import_staging_dependency_cycle`) read the graph with plain MVCC snapshots. Two concurrent transactions each adding one edge can together form a cycle neither saw. Serialize writes to these parent/dependency columns per tenant in any bulk-rewiring path.

**AC-9.** Change tenant policy by updating `tenants` (with `app.user_id` set so `changed_by` is captured), **never by writing `tenant_configuration_history` directly** — that is trigger-filled. Direct inserts are for backdated corrections only (`change_source = 'manual'`) and cannot claim `onboarding` / `trigger`. `tenants.settings` defaults to `{}`: the seven documented sub-objects get onboarding history rows **only if the application writes them into `settings` in the tenant INSERT**. The history bracket is transaction time — "this policy took effect last month" cannot be expressed through the normal path.

**AC-12.** `app.void_operation` is a carve-out for `void_invoice()` only. *"Application code must never set it… Grep for it in code review."* It is a plain session variable any role with UPDATE can arm to walk through the locked-read and billed-charge guards. Worth a lint rule in whatever the prototype becomes.

---

# 2. Form-shaping obligations

## 2.1 Fields the DATABASE stamps — the UI must NOT let a user set them

| Field(s) | Contract | Note |
|---|---|---|
| `recorded_at` / `recorded_until` on all 7 bi-temporal tables | AC-14 | *"stamped by the database — a value you supply is replaced"*; forced to `now()` on insert, on draft→asserted, and on close |
| `invoice_calculation_snapshots.captured_at`, `content_hash` | AC-18 | *"are the database's — do not supply them"* |
| `invoices.created_at` | AC-31 | stamped at INSERT, write-once (a plain UPDATE of it was round 1's CRITICAL) |
| `invoices.first_issued_at` | AC-31 | stamped on first draft/held → non-void issued transition; INSERT values discarded |
| `billing_runs.started_at` | AC-31 | stamped by the database when set, **never moves** |
| `meter_readings.validated_at` | AC-21 | server-stamped `clock_timestamp()` on first entry into a billable state; caller values replaced |
| `meters.consecutive_estimate_count` + streak columns | AC-21 | written only from inside the read gate; direct writes rejected |
| `deposits.status`, `refunded_on`, `released_on` | AC-24 | projections of the event stream |
| all `customers.deposit_*` columns | AC-24 | projections of `deposits` |
| `customer_attribute_history` / `customer_state_events` rows | AC-23, AC-27 | direct INSERT is **refused**; write `customers` and let the logger record |
| `customers.status_reason`, `status_changed_by` | AC-23 | consumed into the event and **cleared** — never read back |
| `rate_schedules.activated_at`, `archived_at` | D-2026-08-28-06 | stamped by the trigger, not supplied |
| `read_validation_exceptions` / `invoice_exceptions` stamps | AC-20, AC-22 | "stamps are the database's" |
| `invoice_events` rows | AC-22 | appended by the database on exception insert and resolution |
| `tenant_configuration_history` | AC-9 | trigger-written from `tenants`; the UI edits `tenants` |
| `deposit_events.posted` | AC-24 | *"The database writes the `posted` event"* |
| `import_jobs.idempotency_key` | AC-4 | derived — but only if you supply filename + hash |
| `account_ledger` / `invoice_events` generally | D-2026-08-20-19 | INSERT-only, no exceptions |

## 2.2 Write-once / frozen-after-assertion fields

- **Every content column on an asserted bi-temporal row** (AC-14) — only the close columns and the lifecycle set are writable.
- **All billed content on an issued invoice** (AC-10): identity, lineage pointers, period, every date **including `due_date`**, every total, `tax_breakdown`, estimated-read and anomaly flags, `pdf_url` once set, `id`.
- **Payment identity once `status <> 'pending'`** (AC-11): customer, date, amount, method, channel, source, external references, check fields, `is_deposit`, `received_by`, lineage FKs. A payment never returns to `pending`.
- **A validated read's** `is_estimated`, `register_type`, `meter_id`, `reading_date`, `tenant_id` (AC-21).
- **A ruled surcharge line's `rate_item_id` AND `invoice_id`** (AC-27, AC-29) — relocate or reclassify by delete + new line.
- **`invoice_exceptions.blocks_delivery` and `routing_reason`** (AC-22).
- **A resolved read exception** — entirely frozen (AC-20).
- **A resolved/overridden invoice exception** — frozen (AC-22).
- **While a snapshot exists** (AC-31): the invoice's `invoice_type`, `replaces_invoice_id`, `billing_run_id`, `period_start`, `period_end`; the run's `correction_rate_mode` and `run_type`; the target's run, voided invoice, `rate_date_mode`, `rate_date_override` (nor may the target row be deleted). Refusals are `restrict_violation`.
- **`invoices.created_at` and `first_issued_at` never change** — regardless of snapshot state.
- **A frozen WNA factor** after approval (AC-16); an `active` exemption row (AC-16).

## 2.3 Required reason codes and their allowed values

| Field | Allowed values / rule |
|---|---|
| `read_validation_exceptions.resolution_disposition` | `estimate_accepted` \| `manual_read_entered` \| `read_corrected` \| `field_order_dispatched` \| `excluded` \| `override`. **A `consecutive_estimate_over_cap` row resolves ONLY by `override` or `field_order_dispatched`.** |
| `read_validation_exceptions.resolution_reason_code` | non-blank, **free text** — no catalogue exists yet; a later patch adds a CHECK (D-2026-08-28-25) |
| `read_validation_exceptions.resolved_by` | required; must be a user of the tenant |
| conditional on disposition | `field_order_id` (same meter) required for `field_order_dispatched`; `replacement_reading_id` (a *different* reading of the same meter) required for `manual_read_entered` / `read_corrected` |
| `invoice_exceptions.status` (clearing) | `resolved` (the bill was corrected or the flag was wrong) \| `overridden` (the bill goes out as flagged) — each with `resolution_reason_code` + `resolved_by` (same tenant) |
| `invoice_exceptions.criterion` | CI-115's list plus `unresolved_read_exception`, `batch_baseline_breach`, `meter_master_incomplete`, `tamper_detected`, `canary_mismatch`, `manual`, `other` |
| `invoice_exceptions` conditional | `read_validation_exception_id` **required** for `unresolved_read_exception` |
| bi-temporal `closed_type` | `superseded` \| `retracted` — **`closed_reason` required** in both cases; `closed_by` optional |
| bi-temporal `change_type` | `initial` \| `succession` \| `correction` \| `backfill`. `backfill` **cannot be inserted** after the patch. **`retraction` is NOT a value** — it lives on the closing side (D-2026-08-28-01) |
| `change_reason` | required on a correction (and carried on succession rows) |
| `rate_schedules.archive_reason` | `abandoned_draft` (for a draft) \| `superseded_by_filing` \| `service_discontinued` (for an activated schedule). Required exactly when archived |
| `rate_schedule_versions.service_type_change_basis` | `transcription_error` — the only legal basis for a service-type correction |
| `deposits.basis` | `credit_evaluation` \| `adequate_assurance_366` \| `additional_trigger` (+ `trigger_basis`) \| `tariff` — **never `legacy_unknown`** (that value exists only for carried legacy rows) |
| `deposits.instrument` | cash accrues interest; anything else requires `instrument_reference`, may carry issuer/expiry, and is **released** not refunded |
| `correction_run_targets.rate_date_mode` | `historical` \| `current` \| `custom` (+ `rate_date_override` when custom). Resolution precedence: custom > per-target > run default |
| `customers.status_reason` | free text, **non-blank**, required on every status change, together with `status_changed_by` |
| `invoices.hold_reason` | required when the application sets `held` |
| `void_invoice()` void reason | includes `service_date_error`, `wrong_customer` among others (named in D-2026-09-08-04 as legitimate reasons the rebill moves period and customer) |
| legacy deposit refund | a `reason` stating how its interest was settled |
| certificate evidence | `certificate_number` or `certificate_url` with **≥1 `[[:alnum:]]` character** |

## 2.4 Other required-field rules

- **Payment intake must set `status = 'pending'` explicitly** (AC-11). The column **defaults to `posted`**, which freezes the row on arrival. A webhook/lockbox row that may still need correction must be inserted as `pending`.
- **File imports must supply both `source_filename` and `source_file_hash`** (AC-4) — or the duplicate-import guarantee silently never fires.
- **Meter reactivation must supply the real `start_date`** (AC-1).
- **Exemption activation needs `verified_by` AND `verified_at` in the same UPDATE** (AC-16).
- **WNA approval needs `approved_by` AND `approved_at` in the same UPDATE** (AC-16).
- **Capped surcharge lines need `meter_id`** (AC-27).
- **Surcharge rule cycles are BILL dates**, not service dates (AC-26).
- **Effective dates are never implicit.** No form may default a temporal coordinate to "now." `deposit_interest_rate_as_of()` raises when no row covers a date, so rate history must be entered back to the oldest posting date before the first accrual cycle (AC-25).

## 2.5 Error shapes the UI should handle distinctly

| Error | Meaning | UI response |
|---|---|---|
| `check_violation` (23514) | a rule refusal | show the message — it names the rule |
| `restrict_violation` | a freeze refusal (AC-31) | explain the delete-and-recreate path |
| `serialization_failure` | **retryable** — stale version token (AC-14, "review and retry"), capped-line mutex (AC-27), rule row FOR SHARE (AC-29), snapshot race (AC-31) | a real re-read-and-retry affordance, not a generic toast |
| `invalid_transaction_state` | wrong isolation level — a run's `correction_rate_mode` / `run_type` may be changed only under READ COMMITTED (AC-31); rule corrections/retractions likewise (AC-29) | fix the transaction, not the data |
| FK error naming a child table | a protected-set delete hit a child (AC-13) | name the blocking child in the message |

---

# 3. Soft-delete semantics — short answer: there is no soft delete

**AC-13.** `enforce_no_hard_delete()` is attached to every table in the v5.4.2-01 protected set — **33 operational tables** spanning money, bills, parties, premises, metering, operations and audit. They reject **DELETE and TRUNCATE**. The guard **fires on FK cascades too**: *"deleting a customer/tenant/meter fails at its first protected child"* — and the error names the child table.

There is **no delete-with-reason dialog anywhere**. Retirement is through **status**, with a reason attached where that status carries one (see §2.3). A UI that offers a delete button on anything in the protected set will produce an error the user cannot act on.

**The narrow exceptions:**

1. **A clean draft invoice** may be hard-deleted (AC-10, D-2026-08-20-18) — only if no billed adhoc charge and no locked read point at it, and it carries no `dunning_events` and no `invoice_applications`. Held invoices are **never** deletable: they carry an operator's reason and are voidable. The rationale: a draft is not posted, not voidable, and has no soft-delete path, so forbidding DELETE would leave an abandoned draft with no disposition.
2. **Snapshots and their citations** may be deleted only while the invoice is draft/held (AC-18, AC-19) — recalculating a draft means delete + re-snapshot. Frozen after issuance.
3. **Surcharge lines and base compositions on a draft** — relocation and reclassification are delete + new row (AC-27, AC-28, AC-29). Discarding a draft discards its composition.

**Reference / configuration tables are NOT delete-guarded** — the `rate_*` family, `billing_cycles`, `read_routes`, `jurisdictions`, `import_staging`. D-2026-08-20-22 is explicit that this is deliberate: *"their retention is CI-004/A-1's date-effective discipline."* But bi-temporal rows in them are **never deleted by contract** (AC-14), drafts included. So the UI should not expose delete there either.

Adding a table to the protected set means adding it to the DO-block array in a new patch (the loop also performs the `REVOKE DELETE`).

---

# 4. Tenant scoping expectations

- **Enforced by Postgres RLS, not application filters.** TECH-STACK-DISCUSSION.md:60: *"RLS already chosen for tenant isolation."* Shared schema, `tenant_id` on every tenant table.
- **The canonical policy form (AC-32):** every table with a `tenant_id` column must `ENABLE` **and** `FORCE ROW LEVEL SECURITY`, with a policy `USING (is_platform_admin() OR tenant_id = get_user_tenant_id())` — *"written in exactly that form and order."* A permissive `WITH CHECK (true)` beside a canonical `USING` is read-isolated but **write-open** and is refused.
- **Identity reaches the database through two wrapper functions**, `get_user_tenant_id()` and `is_platform_admin()` (tu.sql ~535 and ~570). They currently call `auth.uid()` (residual Supabase plumbing). De-Supabasing swaps those two bodies for a standalone mechanism, *"e.g. `current_setting('app.current_user_id')::uuid`."* So the transport is a **session GUC set per request** — every request opens a connection/transaction that sets the user GUC and the database does the scoping.
- **`app.user_id` is separately required** for audit attribution on tenant policy changes (AC-9: *"with `app.user_id` set so `changed_by` is captured"*).
- **Known hole the application must close (AC-3):** FK checks bypass RLS and `meter_readings.meter_id`'s FK is not tenant-scoped. Validate tenant ownership before insert; treat a NULL `location_id` on a read as a defect to surface.
- **Cross-tenant attribution** is guarded by composite `(id, tenant_id)` FKs where such a key exists (`meters`, `meter_readings`, `service_orders`, `invoices`), and by `assert_same_tenant_user()` for `resolved_by` / `verified_by` / `approved_by` style columns — *"platform admins excepted"* (D-2026-08-28-32). `users` deliberately has no `(id, tenant_id)` key: it is the RLS root and platform admins legitimately act across tenants.
- **`replaces_invoice_id` is tenant-bound at the FK** as of v5.4.2-10 — it was previously a plain FK that let any tenant point at any tenant's bill.
- **Platform admin is a first-class mode**, not an escape hatch — the UI needs it as a real surface (global queues, cross-tenant reads).
- **Views must be `security_invoker`; materialized views cannot be** (AC-32). Four statistics matviews are simply `REVOKE`d from `tally_app` — a matview *"takes neither `security_invoker` nor RLS; an owner-rights wrapper is the same shape as the hole."* Consequence: **matview-backed data has no app read path today** (see §6).
- **Residual affecting a global UI surface (AC-30):** one tenant's malformed `tenants.settings` loud-blocks that tenant's queue rows **and a platform admin's global queue**. Render a per-tenant error row, not a blank page.
- **The key is the column name `tenant_id`** — a tenant table whose discriminator is named something else is outside the isolation check by construction.

---

# 5. Status / state machines with legal transitions

## Invoice

```
draft ──► pending ──► sent ──► (paid | write_off | …)
  │  ╲                          
  │   ╲──► held ──► pending      (held is a PRE-POSTING detour)
  │
  └──► [hard delete, clean drafts only]

any status ──► void   ONLY via void_invoice()   ──► terminal
```

- **"Issued" = `status NOT IN ('draft','held')`. `pending` is on the immutable side** (D-2026-08-20-16).
- **`pending → held` is FORBIDDEN** (backward). **Hold before release** (AC-22).
- **`void` is written by `void_invoice()` only.** A direct UPDATE to `void` from *any* status — held and draft included — or an INSERT as `void`, is rejected unless the `app.void_operation` carve-out is armed (which application code must never do). Void is terminal: notes and metadata only.
- **Forward ordering among issued statuses is NOT enforced** — `sent → write_off → sent` is accepted; `write_off` and `paid` are **not terminal**. Flagged, deliberately unfixed (D-2026-08-20-16 flagged list). Do not assume the DB will stop a backwards move here.
- **Blocked transitions:** cannot enter `pending` (from draft or held) or `sent`, nor be stamped `sent_at` / `delivery_confirmed_at`, while an open `invoice_exceptions` row has `blocks_delivery = true`.
- **Snapshot gate:** leaving `draft`/`held` for any other status requires exactly one calculation snapshot at commit, plus base compositions for every non-zero tax/percentage line.
- **Delete:** only a clean draft (see §3).

## Meter read

```
pending_review ──► approved ──► released_to_billing ──► locked
                                        ▲                  
                    void_released ───────┘  (re-lock path, v5.2.1 matrix)
```

- `locked` requires **`billing_period_locked` AND `locked_by_billing_run_id`** (HANDOFF.md:88).
- **Every step into a billable state** (`approved`, `released_to_billing`, `locked`) is refused while **any** `read_validation_exceptions` row is open (AC-20, D-2026-08-28-26 — an earlier draft gated only the first entry, and reviewers walked reads through both the post-approval route and the `void_released → released_to_billing` re-lock).
- Approving a read at the estimate cap requires the auto-raised `consecutive_estimate_over_cap` exception resolved by `override` or `field_order_dispatched` (AC-21).
- An exception may **not** be raised on a `locked` / `void_released` read — correct a billed read with a replacement reading.
- `validation_status`: `reviewed_with_exception` only when such a row exists; `reviewed_clean` only when none is open.
- Once validated, the read's facts freeze (see §2.2).

## Payment

```
pending ──► posted ──► nsf | reversed | refunded | voided   (all terminal)
   ▲                                                         
   └── NEVER returns to pending
```

- **The column DEFAULTS to `posted`** (AC-11) — an intake row that may still need correction must be inserted as `pending` **explicitly**. D-2026-08-20-27 left the default alone deliberately: changing it *"decides the intake design by inertia."*
- Identity freezes once `status <> 'pending'`.
- A posted payment is corrected by reversal/NSF **plus a new payment**, never an edit.

## Customer

```
active ⇄ … (matrix largely UNENFORCED) … 
closed ──► active   (the ONLY reopen target)
```

- **Only two rules are enforced today** (AC-23, D-2026-08-28-34):
  1. `closed` reopens **only** to `active`;
  2. `closed` is **refused** while any deposit of the customer is `held` / `partial_applied` / `applied` / `refund_pending` — settle it first.
- **The rest of the matrix — including `final_billed → closed` and the customer-move-out case — is unruled and pending Kyle.** *"Do not hard-code a status matrix."*
- Every transition requires `status_reason` + `status_changed_by` in the same UPDATE; both are consumed and cleared.
- Events are ordered by `clock_timestamp()` + an identity `seq` (same-transaction transitions otherwise read the wrong state).

## Rate schedule

```
draft ──► active ──► archived   (terminal)
  └────────────────► archived   (archive_reason = 'abandoned_draft')
```

- Born `draft` (DEFAULT flipped from `active` in v5.4.2-03).
- `draft → active` requires an **open version to exist first**; the trigger stamps `activated_at`.
- `→ archived` requires `archive_reason` **and** every open version to carry an `expiry_date`. Archived accepts no new versions and is terminal.
- **`draft` and `archived` are NOT assignable** to `meters.rate_schedule_id` / `meter_deployments.rate_schedule_id`.
- **`expired` is not a status** — read the version's `expiry_date`.

## Tax exemption (`customer_tax_exemptions.status`)

```
pending_verification ──► active      (needs verified_by + verified_at + certificate evidence)
        └──────────────► rejected    (terminal)

active  ──[frozen]──►  revocation / expiry = a NEW superseding row
                        (close the active row as 'superseded', then insert
                         status = 'revoked' | 'expired' with supersedes_id)
```

- Born `pending_verification` — a draft: `recorded_at` NULL, freely editable, **invisible to every lookup and to `should_charge_tax`**.
- A pending row may go **only** to `active` or `rejected`; `rejected` is terminal.
- Once `active`, the row is frozen. **Revocation and expiry are new rows, never an `effective_end` edit** — the bracket froze with the assertion (D-2026-08-28-04).
- One asserted exemption per `(customer, exemption_type)` per valid period (exclusion constraint).
- **`industrial` is no longer a legal `exemption_type`** — predominant-use exemptions are manual tax adjustments until their own table lands.
- A revocation discovered late means issued bills were under-taxed — route it to void/rebill as a correction run.

## WNA monthly adjustment

```
pending ──► approved ──► applied ──► archived      (forward only)
```

- `pending` is a draft. Approving requires `approved_by` **and** `approved_at` in the same UPDATE, and **freezes the factor**.
- Afterwards only `approved → applied → archived` is writable in place.
- An HDD restatement is a **correction**: close the approved row as `superseded`, insert the restated row (already `approved`, with its approver) pointing back. A pending restatement may be entered beside the live month, but **approving it while the live row is still open fails on the unique index — close first.**

## Deposit (status is a PROJECTION; events are the only write path)

```
events:  posted (DB-written)
           ├─ applied_to_balance
           ├─ interest_accrued      (cash only; ≥31 days held; strict period rules)
           ├─ interest_credited
           ├─ refund_initiated
           ├─ refunded              (terminal)
           └─ released              (non-cash; terminal)

projected status: held | partial_applied | applied | refund_pending | refunded | released
```

- **Never write `deposits.status`, `refunded_on`, `released_on`, or any `customers.deposit_*`** — all are trigger-maintained projections; direct writes are refused.
- Events are **append-only**; a refunded/released deposit accepts no more events.
- Accrual rules (AC-24, D-2026-08-28-38/39): cash only; only once `effective_on − posted_on ≥ 31`; never on a deposit exhausted within 30 days; `period_start` = `posted_on` for the first period, else previous `period_end + 1`; no rate change or application inside the period; periods contiguous, no overlap. A fully applied deposit is status `applied` and is settled by a **zero-amount `refunded` event** — and `applied` blocks customer closure until it is.
- Non-cash instruments are **released**, not refunded.
- Every event links the ledger row that moved the money via `ledger_entry_id`.

## Read validation exception

```
open ──► resolved   (disposition + reason code + resolver, once)  ──► FROZEN
```
Never deleted.

## Invoice exception

```
open ──► resolved | overridden   (resolution_reason_code + resolved_by)  ──► FROZEN
```
`blocks_delivery` and `routing_reason` are frozen at insert. Never deleted (a draft-invoice delete cascades). Every insert and resolution appends an `invoice_events` row.

## Bi-temporal reference row (all seven tables)

```
[draft: recorded_at NULL, editable]        (only exemptions + WNA have a draft phase)
        │
        ▼  assert
    asserted / open  ──[FROZEN: content columns]──►  close
        │                                             ├─ superseded  ──► MUST have an asserted
        │                                             │                  successor at commit
        │                                             └─ retracted   ──► no successor
        ▼
   successor row: supersedes_id + change_type + change_reason
```
Group-1 version rows (rate schedule / WNA zone / rate item versions, rate schedule items, franchise fee rules) have **no draft phase** — the draft lives on the `rate_schedules` header (D-2026-08-28-05). Editing a draft schedule's content therefore still leaves history: *"That is the cost of one write path, and it is honest."*

## Billing run (relevant constraints, not a full matrix)

- `started_at` must be set (database-stamped, never moves) **before any snapshot** can be written against the run (AC-31, HANDOFF.md:88).
- `run_type` must be `correction` for a correction invoice.
- `correction_rate_mode` and `run_type` **cannot change while any snapshot cites the run**; change them **only under READ COMMITTED** (`invalid_transaction_state` otherwise).
- Heartbeats, status and totals on the run row do not conflict with snapshot writers (the writers hold FOR KEY SHARE, not FOR SHARE — D-2026-09-08-06).

## Canonical lock order (for any transaction touching more than one)

**invoice → lineage root → replaced bill → correction target → billing run.** A transaction touching a void bill and its targets edits the bill first. Do not write the run row's election inside a snapshot transaction (AC-31).

---

# 6. Tech-stack decisions — locked, and what's open

All locked 2026-06-07 (TECH-STACK-DISCUSSION.md decisions log).

**B. Language / runtime — LOCKED.**
> *"C# / .NET for the billing engine + API; TypeScript / React for the portal/frontend."*

Strict-mode .NET (nullable reference types on, analyzers and warnings-as-errors from day one). The billing calculation core is *"a pure, I/O-free library."* Rationale includes: native base-10 `decimal` makes exact money math *"a language default, not a discipline"*; most code will be LLM-written, so the compiler is the load-bearing safety net and *"the worst LLM error in this domain — silent float money math — uncompilable."* The vertical slice doubles as Ryan's C# ramp; he has no prior C# experience and *"the portal stays in TS where his fluency is highest."*

**API shape — LOCKED in principle, open in detail.**
> *"Frontend talks to the API over a typed client generated from .NET's first-class OpenAPI output (contract kept in sync by codegen, not discipline)."*

No REST-vs-GraphQL debate — it is OpenAPI-described HTTP with a generated TypeScript client. **Left open:** endpoint design, resource naming, error envelope, pagination. Nothing in these documents specifies them.

**C. Data access — LOCKED.**
> *"Raw SQL + thin mapper (Dapper) over Npgsql. No heavy ORM (EF Core not used for the engine)."*

*"Constraint #3 demands a data layer that works with raw SQL, range types, RLS, four-column bi-temporal predicates, and linked snapshot tables — not an ORM that hides or fights them."* Set-based and bulk-`COPY` writes stay in our control.

**High-level architecture — LOCKED.**
> *"Modular monolith with a pure, I/O-free billing calc core. One deployable, one transactional Postgres."*

Modules named: Metering, Tariff/Rating, Billing, Ledger/AR, Collections, Tax, Customer/CIS, **Portal-API** — each owns its tables, reached through interfaces. Seams *"pre-drawn but not cut"* for later extraction of batch-billing, integrations/EDI gateway, and document/PDF generation workers sharing the same DB. *"True per-entity microservices off the table."*

**A. Tariff / rate engine — LOCKED, and it is substantially a UI decision.**
> *"Data-driven config + a typed, decimal-only calc core."*

Engineers build a composable charge-type library once (`FIXED`, `TIERED_VOLUME`, `PASSTHROUGH_RATE`, `PCT_OF_BASE`, `WNA_ADJUSTMENT`, demand/ratchet, min/max riders); **"billing staff operate it through forms as date-effective data writes; all arithmetic runs in one linted calc core, never in tenant input."** That separation *"**is** the 'no consultant required' positioning."* Decision tables (DMN) handle rule *selection*; the charge-type library handles rate *math*. A tiny pure decimal-only DSL is held in reserve for the rate-math half only, if the vertical slice proves the vocabulary too rigid.

**Implication: rate-configuration forms are a headline product surface, not an admin afterthought.**

**D. Tax — LOCKED.** Build in-house for the Texas-only gas launch; design a clean Tax-module seam so a commercial engine can slot in later as a hybrid at multi-state expansion. Consequence for the UI: *"tax/franchise rates become config rows billing staff maintain through the same UI as tariff rates."*

**E. Testing — DEFERRED** by explicit decision, until the scenarios exist (Layer 4). Partially resolved since B landed: *"property-based via CsCheck/FsCheck, example/golden-master via xUnit."* Still open: scenario→test mechanics and fixture shape; golden-master tests for cancel-rebill reproducibility; and the **clock-injection mechanism** (constructor-injected clock vs global).

**Auth — NOT DECIDED.** No auth decision exists in any of these documents. What is known: identity reaches the database through `get_user_tenant_id()` / `is_platform_admin()`, currently backed by `auth.uid()`, to be swapped for a session GUC. The IdP, session handling, and role model are all open — and D-2026-08-28-31 is explicit: **"a role model does not exist (rbac-model pending)"**, which is why `invoice_exceptions.queue` is a bare enum string. A UI prototype should treat the current user as a stub: a tenant id plus a platform-admin flag.

**Money hazard specific to a TypeScript prototype.** Domain constraint #1: *"Exact decimal money math. No binary floats anywhere near currency."* JavaScript numbers are binary floats. Money must arrive from the API as **strings** and be handled as strings or via a decimal library. **Never `parseFloat` a currency value.**

**Where the real state lives.** The knowledge base is **not in this repo**: `/Users/ryanscomputer/code/gas-billing-memory/` holds `CONTEXT.md`, `application/execution-kickoff.md` (the 12-work-unit sequence; Work Unit 2, the config catalog, is next), `application/canonical-invariants.md` (135 invariants CI-001…CI-135), the Kyle Shaffer gap analysis, `application/bi-temporal-decision.md`, and `application/configurable-rules-scenario-strategy.md`.

---

# 7. Project phase and HANDOFF notes

**Phase: schema parity, Phase 4 Wave 3.** As of 2026-09-09 (HANDOFF.md), `sql/tu.sql` is at **v5.4.2-11** — 21,916 lines; catalog: 82 tables / 5 views / 4 matviews / 81 policies / 80 FORCE RLS / 255 triggers / 393 functions / 357 FKs. Wave 1 ✅, Wave 2 ✅; Wave 3: A-9 ✅, **A-2 paused** on domain expert Kyle Shaffer's Part 4, A-10 open, A-8 held for its brief.

The goal statement is explicit about what exists:
> *"Bring `sql/tu.sql` (the only enforcement artifact — no application code exists) to parity with the spec corpus."*

A React/Next prototype therefore genuinely precedes the .NET API it will eventually talk to.

**Items that bear directly on UI work:**

- **The four statistics matviews have no read path, and `refresh_statistics_views()` has never worked** — it raises `column reference "view_name" is ambiguous` for everyone (HANDOFF.md:36, :71; D-2026-09-09-09 recorded it rather than fixing it). HANDOFF.md names the owner: **"the dashboard work fixes both."** If the prototype includes a dashboard, this is the one place UI work is already scheduled as the fix, and the one known-broken surface it will meet.
- **AC-32** (every patch calls `assert_tenant_isolation_invariants()`) is a DDL-patch obligation, not a UI one — relevant only as context for why nothing gets casually added to the database.
- **AC-15's "one pair per run" is deliberately unenforced** (a -10 residual). Any UI that triggers a billing run must make the coordinate pair explicit and singular; the database will not catch a run that drifts.
- **`anomalies` is the operator work queue** (`status`, `assigned_to`, `resolved_*`, `dedup_key`, RLS, in the protected set). `entity_type` gained a 15-value singular domain in -11; **`entity_id` has no polymorphic FK** (a recorded residual) — the UI cannot rely on referential integrity to resolve the target.
- **Scope: Texas-only launch, gas-only.** The schema supports water/electric/sewer. Tenants are natural gas LDCs, 500–150,000 meters.
- **Open pending Kyle — do not hard-code these:** the full `customers.status` matrix; the PSF cap figure ($1.00 per CI-038 vs $0.50 per D4-1); whether `is_state_agency` needs a verifying document; the meter change-out mid-cycle cap question; legacy-deposit refund policy; credit vs disbursement for refunds; residential non-cash instruments; instrument-expiry alerting; the Texas deposit-cap ceiling.
- **Carried "Open for Ryan" residuals** (HANDOFF.md:38): a `meter_id` swap on a capped line moves the attribution; letter-bearing placeholders like "N/A" pass the certificate-evidence test; one tenant's bad notice-days value loud-blocks the platform admin's global queue; legacy `customers.is_tax_exempt` is unguarded and display-only.
- **HANDOFF.md:88 fixture notes double as a valid-object-graph checklist for any seed/demo data:** customers need `status_reason` on any status change; deposits are events-only; issued invoices reject content edits; reads are born `pending_review` → approve → `released_to_billing` → `locked` (needs `billing_period_locked` AND `locked_by_billing_run_id`); a surcharge line needs `meter_id` when capped and must be written before its bases; issuance needs snapshot + bases; a billing run needs `started_at` before any snapshot; rule corrections/retractions run only under READ COMMITTED; an asserted exemption needs alphanumeric certificate evidence; a snapshot's `valid_at` = `period_end` and `recorded_at` ≥ the run's `started_at`.

---

# 8. The five things I'd tell the UI builder first

1. **There is no edit button on anything issued or asserted.** Bills: void + rebill. Rates, exemptions, WNA factors: close + insert successor. Reads: replacement reading. Meters: status cycle, not a location edit. **Design the correction flows first — they are the product**, not an exception path.

2. **Every form touching money or rates needs an explicit effective date, and every reference lookup needs a two-axis coordinate.** NULL raises; zero rows is a hard error, never a fallback to today's value. The UI must never quietly show "current" where "as of" was asked for.

3. **Reason codes and actor attribution are required fields with fixed vocabularies and conditional dependents** — not optional notes. Six read-exception dispositions, two exception clearances, two close types, three archive reasons, four deposit bases, three rate-date modes. Build them as constrained pickers with dependent fields, and surface the reason in every history view — that is the whole point of collecting it.

4. **A large set of fields are database-stamped and must be read-only in the UI** — every `recorded_at` / `recorded_until`, snapshot `captured_at` and `content_hash`, `first_issued_at`, `created_at`, `started_at`, `validated_at`, streak counters, and every deposit projection. Several more are write-once after a state change. Rendering them as inputs invites a write the database will discard or refuse.

5. **Concurrency is visible to the user here.** Optimistic version tokens on reference edits (`assert_reference_version` → "review and retry"), `serialization_failure` retries on capped surcharge lines and snapshot races, and isolation-level requirements on run-election changes. Build a genuine re-read-and-retry affordance, not a generic error toast.
