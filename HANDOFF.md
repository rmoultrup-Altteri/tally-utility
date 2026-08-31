# Handoff: A-7 landed (v5.4.2-07) — Wave 2 complete; next is Wave 3 (A-2 → A-9 → A-10)

**Generated**: 2026-08-31 (session wrap — A-7 drafted, reviewed two rounds by Fable + Codex, mirrored, fresh-build verified, docs in both repos)
**Branch**: tally-utility `main` (committed + pushed) · gas-billing-memory `main` (committed + pushed; unrelated untracked `Clippings/` left alone)
**Status**: **A-7 DONE.** `sql/v5.4.2-07-regulatory-surcharge-riders.sql` (1,196 lines, md5 `6a322537…`; reviewed body `439d125f…` at 1,189 lines — comment-only delta) is mirrored into `sql/tu.sql` (18,822 → 19,779, pure append; anchors 337/3600/3679 intact). Container `tally-pg` is a fresh build of the committed tu.sql, run WITHOUT a host port (127.0.0.1:5432 belongs to `langfuse-postgres-1`); use `docker exec`. Phase 4: Wave 1 ✅, **Wave 2 ✅** (A-20, A-21, A-7) → **Wave 3 next**: A-2 → A-9 → A-10; A-8 HELD for a Kyle brief.

## Goal

Bring `sql/tu.sql` (the only enforcement artifact — no application code exists) to parity with the spec corpus per `gas-billing-memory/application/schema-parity-plan.md`. Next: **A-2** — jurisdiction-keyed backbill caps, "a cheap rider" as columns / a child table on the v5.4.0-03 `jurisdictions` table. Read Appendix A-2 and the CI entries it names, decision table cluster 27 (backbilling — the 3E/3F brief said it "has no implementable form at all" and its cause-enum answer is a prerequisite for the cap table's shape: check whether Kyle has ruled on it before drafting; if not, A-2 may be a brief, not a patch), then `jurisdictions` in tu.sql (line 11569).

## Completed (this session)

- [x] **Reading pass**: Appendix A-7, CI-038, CI-045, Kyle D4-1, the PSF axes doc, decision tables #23 / #26, KB §3.4, the PGA / A-1 / A-3 headers, `rate_item_versions`.
- [x] **Drafted v5.4.2-07** under D4-1 (NO remittance gate, NO billing window): `regulatory_surcharge_rules` (per (rate item, cycle of BILL dates); kind, configured `cap_per_service`, `excluded_from_tax_bases`, `exempts_state_agencies`; in-place bi-temporal; one open rule per rider per bill date + one open PSF rule per tenant per bill date; `regulatory_surcharge_rule_as_of()`), `customers.is_state_agency` (government only; ninth attribute in `customer_attribute_history`; `customer_is_state_agency_as_of()` at midnight America/Chicago), `invoice_line_item_bases` (CI-045's materialized base composition; guard + deferred issuance gate; an excluded surcharge line is never a base; citing line re-checked), surcharge line guard (never a tax, never taxable, 0.00 for a state agency at period end, per-(rate item, meter) cap over POSITIVE amounts on non-void invoices, drafts counted, serialised on `regulatory_surcharge_service_locks`; `rate_item_id` frozen on a ruled line), two-way taxability refusal, INSERT fence on both A-21 ledgers (`enforce_event_written_by_db`, `< 2`) + boolean CHECK, provenance (`invoice_snapshot_references` admits the rules table), `regulatory_surcharge_billing_summary` (security_invoker).
- [x] **Verified**: strict apply ×2; **battery 161 green** (scratch + build; `tally_app` end-to-end; replica mode); two-session REPEATABLE READ race (loser gets a serialization failure); pre-seeded backfill; fresh rebuild zero errors; catalog parity (82 tables / 250 triggers, 182 ENABLE ALWAYS / 357 CHECKs / 357 FKs / 10 EXCLUDE / 59 UNIQUEs / 81 policies / 80 FORCE RLS / 571 indexes / 383 functions; TEMP false).
- [x] **Two reviewers × two rounds** (Fable `general-purpose`, Codex `codex:codex-rescue`). Round 1: Fable HIGH ×4 / MEDIUM ×2, Codex CRITICAL ×2 / MEDIUM ×1, plus three author probes — all folded into one body. Round 2 on `439d125f…`: both "sound enough to mirror", nothing new.
- [x] Docs: DEPLOY-VERIFICATION; DECISION-LOG D-2026-08-31-01…-08; AC-26…AC-28; tally CHANGELOG. GBM: CI-038 → `partially-structurally-enforced` (D4-1 boundary stated); CI-045 text; Appendix A-7 LANDED; A-23 (1e); parity plan A-7 struck, Wave 2 ✅; ingestion Section AU; GBM CHANGELOG.
- [x] Memory: `trigger-depth-fence-inside-guard`, `freeze-hash-before-reviews`.

## Not Yet Done

- [ ] **Wave 3**: A-2 (see Goal) → A-9 (exemption certificate metadata) → A-10 (revenue distribution matrix; may slip behind the finance gate). A-8 (`tax_jurisdictions`) needs a Kyle brief before DDL.
- [ ] **For Kyle** (brief candidates, new this session): the PSF cap figure ($1.00 CI-038 / KB vs $0.50 D4-1 research note); whether `is_state_agency` needs a verifying document; meter change-out mid-cycle vs the per-meter cap; K1 (`is_taxable_default`'s silent false) and K4 (`applies_to` vs `is_taxable`) — still open, no longer blocking CI-038. Carried: the `customers.status` matrix; legacy-deposit refund policy; credit vs disbursement; residential non-cash instruments; instrument-expiry alerting; D14-1b; the Texas deposit-cap ceiling.
- [ ] **A-3 follow-up** (A-23 1e): bind `invoice_calculation_snapshots.valid_at` to the period (or `recorded_at` to the run) — a caller-chosen pair must never be trusted by a gate; A-7's gate already ignores it.
- [ ] **Open for Ryan — A-7 follow-up candidate (small, v5.4.2-02-style rider):** Fable's final delta pass found that a ruled, capped line can be re-parented (`UPDATE invoice_line_items SET invoice_id`) onto a draft whose bill date is OUTSIDE the cycle — no rule at that date, so the guard is silent, the meter is freed in-cycle, and both invoices issue (two 1.00 PSF lines for one meter, one on a 2027-dated bill). "Cycle = bill date" working as written; the close is to freeze `invoice_id` on a line whose OLD invoice's bill date has a rule, exactly as `rate_item_id` is frozen (`enforce_surcharge_line`, ~10 lines + 2 battery checks). Not landed: -07 was already mirrored and committed when it surfaced. Also from that pass, stated not closed: a `meter_id` swap on a capped line moves the attribution (m4 frees, m5 takes it) — the per-meter cap holds. Other LOW residuals (kind-labelled PSF EXCLUDE; mutex-row deadlock = retry) are in the -07 header; the four pre-existing views' `security_invoker` check; A-23's three unpinned definers; `anomalies.entity_type` CHECK; a `tests/` home for the batteries (this session's `battery-07.sql`, `review-brief-07.md`, `patch-07-reviewed-439d125f.sql` are in the session scratchpad only).

## Failed Approaches (Don't Repeat These)

- **`pg_trigger_depth() = 0` as an INSERT fence** — inside the trigger a direct statement is depth 1; nothing was fenced. `< 2` (memory: `trigger-depth-fence-inside-guard`).
- **An advisory lock as the cap's concurrency guard** — serialises writers, not snapshots; two REPEATABLE READ sessions billed 1.20 on a 1.00 cap. A mutex row the loser must UPDATE raises the serialization error.
- **Netting negative lines against the cap** — every variant (drafts positive-only, issued netted) leaks through discard / void of the negative line's invoice. Positives only; void + rebill is the correction path.
- **Trusting the snapshot's (valid_at, recorded_at) in a compliance gate** — A-3 accepts any past pair; a backdated one hid the rule and the rider's calc type. Judge on now().
- **`remitted_on` on a bi-temporal rule** — a later fact on a frozen assertion; D4-1 says the platform owes nothing about remittance.
- **Editing the patch file while reviewers were testing** — four hash changes in round 1; both reviewers had to freeze copies (memory: `freeze-hash-before-reviews`).
- **A SQL-function helper `_f(k text)` with `WHERE _f.k = k`** — the column shadows the parameter; every fixture resolved to the first row. Prefix parameters `p_`.
- **`INSERT INTO t SELECT … FROM (INSERT … RETURNING)`** — not SQL; `WITH s AS (INSERT … RETURNING) INSERT … SELECT FROM s`.
- **A results table with a serial column used under `SET ROLE tally_app`** — default privileges cover tables and functions, not sequences; GRANT USAGE on the sequence.
- **`docker run -p 5432:5432`** — the port belongs to another project's Postgres; run without `-p` and use `docker exec`.
- All A-21/A-20/A-3 traps still apply: `public, pg_temp` pin; battery inside one transaction with `SET CONSTRAINTS ALL IMMEDIATE` (deferred gates) and `SET CONSTRAINTS ALL DEFERRED; … ; SET CONSTRAINTS ALL IMMEDIATE` inside a single EXECUTE for close-then-insert corrections; an expected-error chunk must not contain its own setup; mirror after the LAST `-- ====` banner with the `-- MIRROR:` three-line preamble; `now()` is constant within the battery transaction (transaction-time ordering cannot be tested inside one txn).

## Key Decisions (durable copies: `application/DECISION-LOG.md` D-2026-08-31-01…-08)

| Decision | Rationale |
|---|---|
| D4-1 read strictly: no gate, no window; structural residue = cap + exemption + exclusion | Landing a gate would decide by inertia what Kyle decided the other way |
| Rider classification is its own in-place bi-temporal table keyed (rate item, cycle of bill dates); cap configured, never a literal | Cap and cycle are per assessment, classification per rider; the $ figure is Kyle's |
| Per service = per meter; positives-only cap on non-void invoices, drafts counted; mutex row, not advisory lock | Negatives leak via discard/void; RR snapshots defeat advisory locks |
| `is_state_agency` as a customer attribute with history, evaluated at period end, Central-time boundary | Government is broader than state agency; a rebill of an old period asks what the account was then |
| INSERT fence on the A-21 ledgers, boolean CHECK | A direct row cancelled the exemption; A-7 is the first patch that reads that history |
| Base composition is a table, frozen with the invoice, required at issuance; excluded lines never cited | CI-045 asks for materialization; makes K4 non-blocking |
| Issuance gate judges on now(), not the snapshot pair | The pair is caller-supplied by A-3's design |
| Ruled line's `rate_item_id` frozen; taxability refused both ways; one PSF rule per tenant per cycle | Detaching the rider link escaped every check; two riders doubled the cap |

## Current State

**Working**: tu.sql 19,779 lines, committed and pushed; `tally-pg` = fresh build (zero init errors), no host port. Catalog above.
**Broken**: nothing known.
**Uncommitted**: nothing (GBM's untracked `Clippings/` is not ours).

## Code Context

Patch header = the contract (`sql/v5.4.2-07-…` lines 1–243). Write protocols: AC-26…AC-28. The PSF path in one glance:

```sql
INSERT INTO public.regulatory_surcharge_rules (tenant_id, rate_item_id, surcharge_kind, cycle_start, cycle_end, cap_per_service, excluded_from_tax_bases, exempts_state_agencies, regulatory_reference) VALUES (:t, :psf_item, 'pipeline_safety_fee', '2026-03-01', '2027-02-28', 1.00, true, true, '16 TAC §8.201');
UPDATE public.customers SET is_state_agency = true WHERE id = :c;            -- government only; history written by the DB
INSERT INTO public.invoice_line_items (…, rate_item_id, meter_id, charge_type, amount, is_taxable) VALUES (…, :psf_item, :meter, 'surcharge', 0.25, false);   -- cap / exemption refuse here and again at issuance
INSERT INTO public.invoice_line_item_bases (tenant_id, invoice_id, line_item_id, base_line_item_id, base_amount) VALUES (:t, :inv, :franchise_line, :customer_charge_line, 10.00);   -- never :psf_line
-- lines → bases → snapshot → UPDATE invoices SET status = 'pending'   (deferred gates at commit)
SELECT * FROM public.regulatory_surcharge_billing_summary;                    -- the 90-day report's billed side
```

## Resume Instructions

1. Read Appendix A-2 and its CI entries, cluster 27 (backbilling) and the 3E/3F brief Part A item A-2, the Kyle decision files for any backbilling ruling, and `jurisdictions` (tu.sql 11569). Decide with Ryan whether A-2 is a patch or a brief.
2. Same loop as -07: fresh-load scratch (`docker exec` only) → strict apply ×2 → battery inside one transaction with an end-to-end `tally_app` path → pre-seeded check if history is touched → write the brief with `wc -l` + `md5 -q`, **launch both reviewers, then freeze the file** → fold all findings into one revision → round 2 with the new hash → mirror after the LAST banner → fresh rebuild with catalog parity → patch re-apply over the build → DEPLOY-VERIFICATION → register re-grade of exactly the CIs the header names → Appendix → DECISION-LOG / APPLICATION-CONTRACTS → ingestion section → both CHANGELOGs → commit + push both repos.
3. Before the first bill-run calculation code lands: CI-003's GUC net (R-16), A-3's snapshot value contract + replay function, and the A-3 `valid_at` binding (A-23 1e).

## Warnings

- tu.sql APPEND-ONLY; anchors 337/3600/3679. Pin `public, pg_temp`; prove qualification with the strict prelude; guards after the backfills they would refuse; a "written by the DB" fence is `pg_trigger_depth() < 2`.
- Never grant TEMP / CREATE / TRIGGER to `tally_app` without re-reading A-23 (1d).
- Wait for `PostgreSQL init process complete` before touching a freshly run container; run `tally-pg` without `-p`.
- Never `git add -A` in GBM.
- Fixtures for later patches: customers need `status_reason` on any status change and their history is DB-written only; deposits are events-only; issued invoices reject content edits; reads born `pending_review` → approve; a surcharge line needs `meter_id` when capped and must be written before its bases; issuance needs snapshot + bases.
- Phase 3 judgment-gated items wait; A-8 needs a Kyle brief; finance gate holds A-15/A-6 remainder. Texas-only launch scope.
