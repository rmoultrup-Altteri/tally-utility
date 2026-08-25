# Handoff: A-1 bi-temporal design reviewed — 5 decisions sent to Kyle, blocked on his rulings; no DDL yet

**Generated**: 2026-08-25 (session wrap — design-only, no code changes; Kyle brief written and pushed, send-ready message given to Ryan)
**Branch**: tally-utility `main` (clean, unchanged this session) · gas-billing-memory `ryan` (pushed; one new untracked file this session, see below)
**Status**: **BLOCKED on Kyle.** A-1 (Phase 4 Wave 1, second of three: A-4 → **A-1** → A-3) is in the design phase. Two independent adversarial reviews (Fable, Codex) of the proposed architecture are complete and synthesized. Five open decisions remain before any DDL is drafted. On 2026-08-25 Ryan decided these are business-workflow questions for Kyle (schema author), not engineering calls — a plain-language review brief was written and committed: `gas-billing-memory/application/a1-bitemporal-kyle-brief-2026-08-25.md` (Q1–Q5, with engineering recommendations and a blank Ruling/Rationale table). Ryan sends it to Kyle; nothing proceeds until his rulings return. **Nothing in tally-utility changed this session** — no SQL was written, tu.sql is untouched at v5.2.1 + v5.4.0-00→-06 + v5.4.1-01/-02 + v5.4.2-01/-02, 14,499 lines, exactly as A-4 left it.

## Goal

Bring `sql/tu.sql` (the only enforcement artifact — no application code exists) to parity with the spec corpus per `gas-billing-memory/application/schema-parity-plan.md`. Current focus: A-1, the transaction-time (`recorded_at`/`recorded_until`) substrate for reference tables, per `gas-billing-memory/application/bi-temporal-decision.md` §6 — unlocks CI-001, CI-002, CI-005, CI-011.

## Completed (this session)

- [x] **Scoped A-1 precisely.** Confirmed the 7-table set from CI-004's Scope note (`rate_schedules`, `rate_schedule_items`, `rate_items`, `franchise_fee_rules`, `customer_tax_exemptions`, `wna_zones`, `wna_monthly_adjustments`), verified against tu.sql directly (table DDL, every FK referencing these 7, all four consuming functions).
- [x] **Rejected a design (current-row + audit-log child, mirroring A-22's `tenant_configuration_history` pattern)** before drafting — it can't represent a correction entered in advance of its effective date without prematurely overwriting the live value, and doesn't match bi-temporal-decision.md's own worked query example. Confirmed correct by both reviewers.
- [x] **Proposed and then substantially revised** a header/version-split design: 3 tables with entity-FKs pointing at them (`rate_schedules`, `wna_zones`, `rate_items`) get a permanent identity header + a bi-temporal version table; 4 tables with no entity-FK (`rate_schedule_items`, `franchise_fee_rules`, `customer_tax_exemptions`, `wna_monthly_adjustments`) get in-place `recorded_at`/`recorded_until` columns.
- [x] **Ran two independent adversarial architecture reviews** (Fable, `subagent_type: architect`, standard effort; Codex, `subagent_type: codex:codex-rescue`) against the live schema, not against a summary. Both converged on the core shape but found real, concrete defects in the details — see `application/a1-bitemporal-design-review-2026-08-20.md` §6 for both reviews verbatim.
- [x] **Synthesized both reviews into a revised design** (same document, §4) — see Key Decisions below for the headline changes from the original proposal.
- [x] **Wrote the full design-review document**: `gas-billing-memory/application/a1-bitemporal-design-review-2026-08-20.md`. Self-contained — background, verified current schema state with line numbers, the rejected alternative and why, the synthesized design, both full reviews verbatim, 5 open decisions, and the recommended next-steps process. Written specifically so a fresh session (including Ryan's planned Fable xhigh pass) doesn't need to re-derive any of this analysis.

## Not Yet Done

- [ ] **Kyle rules on the 5 open decisions** via `a1-bitemporal-kyle-brief-2026-08-25.md` (recommendations stated there; Q2b includes a behavior change — `customer_tax_exemptions.status` DEFAULT `active` → `pending_verification` — that only Kyle should approve). Once back: fold rulings into design doc §5 + DECISION-LOG. The five, for reference: (1) does `service_type` belong on the `rate_schedules` header or should it version too; (2) group-2 lifecycle-vs-assertion timing model per table (which state is the "asserted" threshold for `wna_monthly_adjustments` — `approved` or `applied`? — and `customer_tax_exemptions` — `active`?); (3) orphaned draft-schedule headers — accept or gate header creation on activation; (4) does the `as_of()` function family ship in the A-1 patch itself or immediately behind it — Appendix A-1's re-grade depends on this; (5) session-GUC-scoped temporal views for CI-003 — defer as a noted candidate, or pull into scope now.
- [ ] **Draft the actual A-1 patch** (`sql/v5.4.2-03-...` or next available number) — blocked on the 5 decisions above. Must include (per the design doc §4): 2 header tables + `rate_item_versions` (fresh table, not a widened `rate_item_history` — see Key Decisions), 4 in-place transaction-time additions + partial/exclusion constraints replacing 3 blocking UNIQUE constraints, `archive_rate_item_history()` neutralization, CASCADE-strip + A-4 protected-array additions for the 6 currently-unprotected tables among the 7, at minimum a stub `as_of()` function family, and the `get_correction_rate_date` COMMENT rewrite (documents a uni-temporal-only query contract that becomes wrong once these tables are multi-row).
- [ ] Once A-1 lands: **A-3** (invoice calculation snapshots, Option B, bi-temporal-decision.md §2.3 DDL sketch) — sequenced after A-1 because it leans on A-1's reference layer.
- [ ] Everything already queued behind Phase 4 Wave 1 completion: Wave 2 (A-20 → A-21, A-7), the six unpinned `SECURITY DEFINER` functions (`get_correction_rate_date`, `get_effective_rate`, `get_user_tenant_id`, `is_platform_admin`, `should_charge_tax`, `validate_custom_fields` — A-23), remaining judgment calls untouched.

## Failed Approaches (Don't Repeat These)

- **My first FK-based categorization test ("does anything external FK to this table's `id`") was wrong** and both reviewers caught it independently: `wna_clamp_events.wna_monthly_adjustment_id` DOES FK to `wna_monthly_adjustments.id`, yet `wna_monthly_adjustments` still correctly belongs in the "in-place, no header needed" group. The test isn't "any FK" — it's **entity-FK** (must survive corrections, needs a permanent header — e.g. `meters.rate_schedule_id`) vs. **provenance-FK** (a citation of one specific historical fact, correctly pins a since-superseded row — e.g. a clamp event pointing at the exact HDD assertion that produced it). Use the corrected criterion for any future table added to either group (A-8, A-19).
- **Claiming `rate_item_history` was "80% of the way there"** for `rate_items`' bi-temporal treatment — wrong, and would have shipped an A-1 patch that silently left `tier_config`, `calculation_type`, `active_months`, `is_taxable_default`, `annual_billing_anchor`, `regulatory_class` uni-temporal and in-place-editable. It only ever tracked `rate_value`/`rate_unit`. Corrected estimate: closer to 30%. Fix: build a fresh `rate_item_versions` table (don't widen `rate_item_history` in place — that would require fabricating historical values it never tracked for the backfill).
- **Treating `archive_rate_item_history()` and the CASCADE deletes on these 7 tables' FKs as "flag now, fix later."** Both reviewers pushed back hard: this function hard-deletes from the table A-1 is about to declare "authoritative and permanent," and none of `rate_items`/`rate_item_history`/`rate_schedules`/`rate_schedule_items`/`franchise_fee_rules`/`wna_zones` are in A-4's no-hard-delete protected array (verified: only `wna_monthly_adjustments` and `customer_tax_exemptions`, of the 7, currently are). Deferring this leaves a landed patch whose own function contradicts its stated invariant — exactly the "claimed cleanliness a patch didn't actually have" failure mode already burned once on A-4 (see the v5.4.2-02 strict-apply rule). **Neutralize both in the same A-1 patch, don't defer.**
- **Original `change_type CHECK IN ('correction','retraction')` design was underspecified** — no value for an initial assertion or an ordinary prospective succession (a scheduled future rate change that corrects nothing), and a pure retraction (close with no successor row) had nowhere to record its reason since `change_reason` only lived on inserted rows. Fixed in the revised design: 4-value enum (`initial`/`succession`/`correction`/`retraction`) plus separate closing-side columns (`closed_reason`, `closed_by`, `closed_type`).
- All prior tu.sql traps still apply (see `application/DECISION-LOG.md` and prior HANDOFF versions): append-only file, fresh rebuild mandatory, strict-apply prelude (`SET search_path = ''; SET check_function_bodies = on;`) required per patch, register not scenario files for grades, never `git add -A` in GBM, `SendMessage` to resume a named reviewer agent rather than respawning.

## Key Decisions (full rationale in `gas-billing-memory/application/a1-bitemporal-design-review-2026-08-20.md`; durable copies belong in DECISION-LOG.md once the 5 open items resolve — not yet written there, this session didn't touch DECISION-LOG.md)

| Decision | Rationale |
|---|---|
| Header/version split (not audit-log) for `rate_schedules`, `wna_zones`, `rate_items` | Audit-log-on-current-row can't represent a correction entered ahead of its effective date; doesn't match bi-temporal-decision.md's own worked query |
| Categorization test = entity-FK vs. provenance-FK, not "any FK" | Original "no external FK" test was empirically false for `wna_monthly_adjustments`; the corrected test still sorts it correctly, for the right reason |
| Fresh `rate_item_versions` table, not a widened `rate_item_history` | Widening in place would require fabricating historical values for columns never tracked (`tier_config` etc.); a fresh table lets the backfill honestly flag itself as an approximation, same as `tenant_configuration_history`'s precedent |
| `version` counter lives on the header (group 1), no counter at all (group 2) | A single correction can touch multiple version rows at once (splitting a valid-time bracket) — no single row to check a token against; header-row-lock also incidentally serializes concurrent writers per entity, solving a problem bi-temporal-decision.md §3 calls structurally unsolved in Postgres |
| `customer_type` moved off the `rate_schedules` header (was originally proposed on it) | Reclassifying a schedule's granularity is a plausible correction; header-immutability would force a whole new schedule + re-pointing every `meters`/`meter_deployments` FK, destroying rather than preserving history |
| `current_rate` on `rate_items` is dropped, not trigger-cached | No application callers exist to break; its only consumer (`get_effective_rate`) is being rewritten regardless; a live-world cache on the header re-creates exactly the predicate-bypass bug the whole patch exists to prevent |
| 3 UNIQUE constraints become partial/exclusion constraints scoped to `WHERE recorded_until IS NULL` | Table-wide `UNIQUE(natural_key, effective_date)` on `franchise_fee_rules`, `rate_schedule_items`, `wna_monthly_adjustments` currently makes the exact same-date correction A-1 exists to support a constraint violation |

## Current State

**Working**: tu.sql unchanged from A-4's landing state (14,499 lines; 66 tables / 229 CHECKs / 147 triggers (80 `ENABLE ALWAYS`) / 275 FKs). Container `tally-pg`, if still running, is a fresh build of that same committed tu.sql — nothing to re-verify.
**Broken**: nothing (no code touched).
**Uncommitted**: both repos clean and pushed (GBM has an unrelated untracked `Clippings/` dir — not ours, leave it). Design doc committed in GBM `4d689fc`; Kyle brief + ingestion Section AP in GBM `d9f8a4f`.

## Code Context

The design doc (`a1-bitemporal-design-review-2026-08-20.md`) contains full verbatim DDL for all 7 tables, the complete verified FK inventory, and full bodies of the 4 consuming functions (`get_effective_rate`, `get_correction_rate_date`, both versions of `get_partial_period_policy`, `should_charge_tax`) plus `archive_rate_item_history()`. Do not re-derive any of this from tu.sql — it's already extracted and line-numbered in the doc. The two functions worth internalizing before drafting:

```sql
-- The established as_of() template to copy for every new domain (tu.sql:13195):
CREATE OR REPLACE FUNCTION public.get_partial_period_policy(p_rate_schedule_id uuid, p_as_of timestamp with time zone)
    RETURNS text LANGUAGE plpgsql STABLE
-- p_as_of NULL raises (never defaults to now()); no COALESCE fallback onto a live column;
-- coordinate earlier than all recorded history returns NULL, caller must treat as hard error.

-- The bug this patch's own columns would otherwise create if left unaddressed (tu.sql:476-507):
CREATE FUNCTION public.get_effective_rate(p_rate_schedule_id uuid, p_rate_item_id uuid, p_billing_month date DEFAULT CURRENT_DATE)
-- zero valid-time predicate, LIMIT 1 with no ORDER BY, reads rate_items.current_rate directly.
-- Rewrite is out of scope for A-1's own patch (open decision), but the LIMIT-1-no-ORDER-BY
-- landmine should be neutralized (comment or deprecation raise) since A-1's own columns are
-- what turns "arbitrary row" into "silently returns the wrong temporal version."
```

## Resume Instructions

1. Ask Ryan whether Kyle's rulings on `a1-bitemporal-kyle-brief-2026-08-25.md` are back. If not, A-1 is blocked — do not draft DDL under assumed answers; other queued work (e.g. A-23's six unpinned SECURITY DEFINER functions) can proceed.
2. When rulings arrive: read `a1-bitemporal-design-review-2026-08-20.md` in full (self-contained; do not re-derive the schema analysis), fill the brief's Ruling table, update design doc §5, add one DECISION-LOG entry per ruling.
3. Draft the A-1 patch per §4 of the doc and the checklist in its §7 "Recommended next steps" — same loop as A-4/A-22: live-test → strict standalone apply (`SET search_path = ''; SET check_function_bodies = on;` prelude, mandatory) → two independent reviews (fresh-load scratch DBs) → fresh rebuild → mirror into tu.sql → DEPLOY-VERIFICATION → register re-grade of exactly CI-001/CI-002/CI-005/CI-011 (+ CI-003's status note) → Appendix A-1 update (don't claim more structural coverage than actually landed — this is the exact mistake the v5.4.2-02 strict-apply rule exists to prevent) → new DECISION-LOG entries for each resolved open-decision item → both CHANGELOGs → commit + push both repos.

## Warnings

- **Do not resolve the 5 decisions by engineering judgment.** Ryan explicitly routed them to Kyle on 2026-08-25. The recommendations in the brief are inputs to his ruling, not defaults to build on.
- tu.sql APPEND-ONLY; anchors 337/3600/3679. Everything under `search_path = ''` — prove it with the strict prelude on the patch file; the Docker build does not.
- Never `git add -A` in GBM.
- A-1 will touch tables that will newly carry DELETE/UPDATE guards once added to A-4's protected array — any backfill (e.g. `rate_item_history` → `rate_item_versions` migration) must be written as inserts, done before the guards go live, or explicitly handled as owner with the guard consciously disabled and visibly re-enabled in the same patch.
- Phase 3 judgment-gated items wait; A-8 needs a Kyle brief; finance gate holds A-15/A-6 remainder. Texas-only launch scope.
