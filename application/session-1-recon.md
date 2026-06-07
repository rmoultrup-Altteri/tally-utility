---
title: Canonical Invariants — Session 1 Reconnaissance Report
type: handoff-recon
status: complete
project: TallyUtility
tags: [tally-utility, invariants, architecture, data-model, research]
load_when: starting Session 2 of the canonical invariants work unit; reviewing Session 1's output; understanding what was captured and what remains for resolution
created: 2026-05-18
updated: 2026-05-18
---

# Canonical Invariants — Session 1 Reconnaissance Report

**Work unit:** Item 1 of [[execution-kickoff]] — canonical invariants document (Sessions 1 + 2)
**Strategy:** [[scenario-mapping-strategy]] §"Prerequisite 1 — The canonical invariants document"
**Status:** Session 1 complete; ready for Session 2

This report is the redirect checkpoint between Session 1 (reading + capture) and Session 2 (categorization, scoring, drafting the canonical document). It summarizes the raw harvest in [[draft-candidates]] and surfaces the framing decisions that Session 2 will need to resolve.

---

## What I found

Session 1 captured **162 invariant candidates** across the full primary KB, the schema, the feature list (as cross-reference), and the Texas-specific regulatory compliance file (added because Texas is launch scope, though not explicitly in the strategy's primary source list).

### Candidate counts by source

| Source | Candidates surfaced (primary attribution) |
|---|---|
| `01-industry-and-regulatory.md` | 4 (INV-001 to INV-004) |
| `02-tariffs-rates-riders.md` | 8 (INV-005 to INV-012) |
| `03-pga-gas-cost-recovery.md` | 6 (INV-013 to INV-018) |
| `04-zones-and-metering.md` | 8 (INV-019 to INV-026) |
| `05-weather-normalization.md` | 6 (INV-027 to INV-032) |
| `06-data-model.md` | 11 (INV-033 to INV-043) |
| `07-billing-calculation.md` | 10 (INV-044 to INV-053) |
| `08-payments-and-programs.md` | 13 (INV-054 to INV-066) |
| `09-credit-collections-disconnects.md` | 12 (INV-067 to INV-078) |
| `10-transportation-choice-edi.md` | 3 (INV-079 to INV-081) |
| `11-taxes-and-gl-accounting.md` | 6 (INV-082 to INV-087) |
| `13-gotchas-and-lessons.md` | 9 (INV-088 to INV-096; mostly framing reinforcements) |
| `16-bi-temporality.md` | 7 (INV-097 to INV-103; sharpened bi-temporal framings) |
| `25-rate-change-complexity.md` | 1 (INV-104) |
| `24-billing-failures-index.md` + cross-cutting + stages 04/08 | 18 (INV-105 to INV-122) |
| `schema.sql` | 20 (INV-123 to INV-142; includes 2 "gap findings") |
| `31-texas-regulatory-compliance.md` | 20 (INV-143 to INV-162; launch-scope Texas) |

Many candidates reinforce or duplicate framings across sources — Session 2's reconciliation pass will merge these into the canonical set. My rough estimate after de-duplication: **80–110 distinct canonical invariants** in the final document (the strategy's expected range was ~60–120 scenarios per invariant, derived from a similar-sized invariant list).

### Distribution by category

Rough split before Session 2 reconciliation:

- **Structural invariants:** ~60% — append-only ledger, date-effectivity, bi-temporality, tenant isolation, invoice snapshotting, rebill lineage, deployment lineage, audit trail completeness, etc.
- **Computational invariants:** ~30% — PGA pass-through, WNA formula scope, rounding discipline, late-fee assessment rules, bypass condition evaluation, etc.
- **Hybrid (computational with structural enforcement):** ~10% — rate-rider DAG ordering, mid-period proration, cancel-rebill original-period world.

### Distribution by confidence

Rough split:

- **High confidence:** ~70% — explicitly named rules in KB, regulatory citations, schema-encoded constraints, or universally documented gas-billing mechanics.
- **Medium confidence:** ~20% — strongly implied by KB but framing uncertain; sometimes the invariant is real but the *boundary* is fuzzy (e.g., "is this universal or configurable per jurisdiction?").
- **Low confidence:** ~10% — KB hints but framing genuinely uncertain; included because the candidate would surface a useful expert question even if the framing is wrong.

### Gap findings (schema cannot enforce stated invariants)

I added two explicit "gap finding" entries (INV-141, INV-142) that are not themselves invariants but flag where the schema does not yet support the canonical invariants. These align with the existing Notable Schema Gaps Summary in `application/feature-list.md`:

- Meter attributes: `rollover_point`, `pressure_class`, `temperature_compensated` columns missing
- Service location zones: BTU zone FK, pressure zone FK, weather station FK, tax jurisdiction FK missing
- Communication log: no general outbound communication log table (only `bill_messages` for targeting config and `customer_interactions` for CSR side)
- Bi-temporal columns (`recorded_at`, `recorded_until`) missing on reference data — confirmed per HANDOFF.md Session A scope

---

## What surprised me

### 1. The schema already encodes more invariants than I expected.

I was prepared to find a thin schema where invariants live primarily in KB prose. In fact, the schema encodes important structural invariants explicitly:

- **`billing_runs.correction_rate_mode`** (with values `historical` | `run_default`) and **`correction_run_targets.rate_date_mode` + `rate_date_override`** directly support the three-flavor cancel-rebill model from [[16-bi-temporality]] §5.1. This is unusually mature.
- **`meter_readings.billing_period_locked` + `triggers_correction_workflow`** explicitly model the supersede pattern for post-bill read corrections.
- **`invoice_line_items.rate`, `gas_meter_factor`, `gas_btu_factor`, `gas_commodity_rate`** are *value snapshots* on the line item, not just FK references to mutable rate items. The most dangerous bi-temporal failure mode (mutable references) is partially neutralized by the line item already capturing values.
- **`payment_methods` schema has no PAN column** — PCI safety by construction.
- **`adhoc_charges.approval_threshold_at_creation`** snapshots RBAC policy at the time of action — already audit-aware.
- **`import_jobs.idempotency_key` + `source_file_hash`** make file re-ingestion idempotent.
- **`anomalies` table uses dedup_key + recurrence_count** rather than producing duplicate rows.

This shifts the framing for several invariants from "must be enforced" to "is partially enforced and the rest must be added." Session 2 should reflect this distinction (perhaps a column "enforcement status: structurally-enforced / requires-application-discipline / unenforced-gap").

### 2. The Texas regulatory file (31) surfaces 20 launch-scope-critical invariants that are not in the strategy's primary source list.

The strategy's primary source list (written 2026-05-15) predates file 31 (added 2026-05-15 from Perplexity research). I included it because:

- Texas is the explicit launch scope per [[scenario-mapping-strategy]].
- Texas regulatory rules surface boundary cases (Inc vs. Env jurisdiction, EWE definition, deposit cap, PSF surcharge cap, mandatory bill format, bilingual rules) that the multi-state KB summaries don't make precise.
- Several Texas rules (e.g., the no-disconnect-for-stale-underbilling list, the meter-test rebill bounds, the deposit auto-refund trigger) are concrete operational rules that the system *must* implement at launch — they are invariants, not configurable policies.

**Flag for review:** Should Texas-specific candidates (INV-143 through INV-162) live in the canonical invariants document, or in a separate "Texas regulatory invariants" sub-document? Two framings:

- **(a) Canonical doc holds Texas as launch-scope content** — clear single source of truth; each Texas candidate tagged `jurisdiction: texas`.
- **(b) Canonical doc holds platform-universal invariants; Texas (and future states) live in jurisdiction-specific addenda** — keeps the canonical doc smaller, but creates two-tier scenario-derivation later.

My recommendation: (a) for now (single source), with explicit `jurisdiction` tagging so future jurisdiction additions follow the same pattern. Flag for confirmation.

### 3. The "policy vs. invariant" boundary is the dominant framing question, not the rule-correctness question.

Most of my low- and medium-confidence candidates are not uncertain about *what the rule says*. They're uncertain about whether the rule is:

- **A platform invariant** — the system must always behave this way regardless of tenant configuration; or
- **A configurable policy with a regulatory ceiling** — the tenant chooses within a regulator-set range; or
- **A pure configuration knob** — the tenant chooses freely.

The strategy anticipates this (the [[configurable-rules-scenario-strategy]] runs after this work for exactly this reason), but the *invariant framing question* must be resolved before Session 2's drafting can complete. A few examples:

- INV-054 payment posting order: the rule is "the posting order is rule-driven and applied consistently." But *which* order (oldest-first / current-first / specific priority) is configured per tenant or per jurisdiction? Invariant on the *discipline*; policy on the *order*.
- INV-058 late fee discipline: 1.5% per month is a typical value, state-capped. The invariant is "late fee is assessed per the configured rate, on overdue principal, after grace, with LIHEAP/dispute exemptions"; the *rate value* is policy.
- INV-073 pre-/post-petition split: structurally required (the ledger must support the split). Whether the *split is automatic on bankruptcy flag set* is operational.

Session 2 should resolve framing by separating the structural-discipline statement (the invariant) from the value-or-mechanism (the policy). The strategy's entry structure supports this — but the writer must be disciplined about it.

### 4. The billing-failures catalog surfaces invariants that no KB file states as rules.

Several invariants emerged primarily from the failure catalog (24-billing-failures-index, cross-cutting-patterns, stages 04 and 08 read in detail): mass-error detection via absolute-baseline checks (INV-108), bill-to-envelope binding integrity (INV-117), web/IVR payment idempotency (INV-111), wrong-meter disconnect prevention (INV-112), seasonal-rate keyed to meter-read-date (INV-106). The KB describes these as failures to avoid, not as rules to uphold — but the *invariant* is "the system upholds the rule that prevents the failure." Method 3 (exception path excavation) will later map failures back to invariants; Session 2's draft should pre-emptively include these.

### 5. Confidence on bi-temporality is high but the scope is still being established.

Bi-temporality (INV-035) is locked architecturally per HANDOFF.md Session A. But the *scope* — which entities get bi-temporal treatment — is partially defined and partially deferred. HANDOFF.md lists:

- **Needs bi-temporal:** rate_schedules, rate_schedule_items, rate_items, rate_item_history, wna_zones, wna_monthly_adjustments, BTU factor tables (gap), pressure factor tables (gap), zone assignments (gap), customer classification, tax rate tables (gap), franchise_fee_rules.
- **Does NOT need:** invoices, invoice_line_items, payments, account_ledger, meter_readings, billing_runs, dunning_events, escheatment_events, ai_audit_log, import_jobs.

For each entity that "needs bi-temporal," the invariant statement implicitly requires that entity to have `recorded_at` / `recorded_until` columns added. This is consistent with the architectural decision but means several invariants reference a column set that doesn't yet exist. Session 2 should make this explicit: "this invariant assumes the bi-temporal columns are added per Session A; the structural implementation is downstream."

---

## What I'm flagging (framing decisions for the user)

These framing decisions should be confirmed before Session 2 drafts the canonical document, because they affect how the canonical entries are structured.

### F1. Should Texas-specific invariants live in the canonical document or a sub-document?

See "What surprised me #2" above. Recommendation: keep in the canonical document with `jurisdiction: texas` tagging.

### F2. How are structural-discipline invariants distinguished from configurable-policy values?

See "What surprised me #3" above. Recommendation: each invariant entry has a clear "the invariant is the *discipline*; the *value* is configurable" framing when applicable. The entry structure already has the right shape (Statement, Category, Scope) — the discipline goes in Statement; the value-or-mechanism is captured in the review note for low/medium confidence candidates.

### F3. Should "gap findings" (INV-141, INV-142) be in the canonical invariants document?

Two options:

- **(a)** Keep them as gap-finding entries (clearly labeled) to make the structural-enforcement-gap explicit alongside each invariant.
- **(b)** Pull them out into a separate "Schema enforcement status" appendix to the canonical document.

My recommendation: (b) — the canonical document should hold *invariants*, not gap findings. Schema-enforcement-gap belongs in a separate "schema readiness" appendix that the data-model-hardening sessions (B, C, D per HANDOFF.md) consume.

### F4. Confidence scoring discipline — high-confidence threshold.

I assigned "high confidence" generously when the KB explicitly states a rule. This produces ~70% high-confidence. The strategy says "high confidence" requires "the strongest candidates and require only sanity-check review" — so the threshold should arguably be tighter. Should Session 2:

- **(a)** Re-evaluate confidence with a stricter threshold (likely producing ~50% high, ~35% medium, ~15% low)?
- **(b)** Keep current scores and assume domain-expert review will recalibrate?

My recommendation: (a) — Session 2 should re-evaluate confidence with stricter discipline, since the canonical document is what the domain expert reviews, and noisy high-confidence flooding their review queue defeats the moderately-aggressive purpose.

### F5. Low-confidence candidates worth keeping for expert framing.

A subset of low-confidence candidates exist primarily because they surface a question:

- INV-004 — Regulatory-posture-configurable-per-tenant: is this an invariant or a config knob?
- INV-040 — Read-references-meter-and-service-point: confirm schema-enforced.
- INV-051 — MIMO-events-produce-billing-events: invariant or workflow?
- INV-080 — Transport-imbalance-charges-tracked: launch-scope or deferred?
- INV-087 — CIAC rate-base treatment: CIS or ERP boundary?
- INV-092 — Multi-dwelling submetering: in scope?
- INV-103 — Concurrent-assertion conflict surfacing: required or acceptable to use last-writer-wins?
- INV-122 — Combined-bill allocation: launch-scope or deferred?
- INV-140 — Account-ledger running_balance computation discipline: forward-recompute on backdate or stamped-at-insert?

Each of these is worth keeping per the strategy's "include if it surfaces a productive question" rule. Domain expert (or product-decision) review will resolve them.

### F6. Some invariants have overlapping framings that need de-duplication.

Examples I noticed during writing that Session 2 should merge:

- INV-015 (Transportation-customers-not-billed-PGA) and INV-079 (Transport-customer-not-billed-commodity) — same rule, two framings.
- INV-003 (Franchise-fee-traceable-to-jurisdiction) and INV-086 (Franchise-fee-remitted-to-franchising-municipality) — same rule, two angles (per-customer assessment vs. aggregate remittance).
- INV-005 (Rate-and-rider-date-effective-and-versioned) and INV-034 (Date-effectivity-everywhere) — same broad principle, different scopes; merge or layer.
- INV-035 (Bi-temporality) overlaps with INV-026 (Cancel-rebill-uses-original-period-world) and INV-098 (Cross-entity-temporal-coordinate-consistency); these are layered (bi-temporality is the substrate; original-period world and cross-entity consistency are properties of correct queries on the substrate).
- INV-022 (Meter-attributes-complete-for-billing) and INV-141 (gap statement) — merge into one entry with structural-enforcement status.

Session 2 needs a deliberate de-duplication pass before producing the final canonical entries.

---

## Open questions for the domain expert

These items need domain-expert resolution before the canonical document is finalized. They are framed as questions to ask in the batched expert review per [[execution-kickoff]] §"Domain expert review cadence."

### Q1. Is oldest-first payment posting a hard rule or a configurable policy in Texas?

The tariff/state may dictate posting order, and Texas customers may also have UCC §3-310 earmarking rights. INV-054 says "rule-driven and consistent"; INV-109 says "honor earmarking before fallback." Are these in tension, complementary, or jurisdiction-dependent?

### Q2. Does the WNA deadband apply uniformly across all customers in a zone, or vary by rate schedule?

INV-029 states "tariff-defined deadband." The 05-weather-normalization.md examples show different deadband values per utility/state (Mountaineer ±2%, Peoples PA ±3%, KEDNY ±2.21%, Columbia PA ±5%). Is deadband per WNA zone (current schema) sufficient, or does it need to be per rate schedule × zone?

### Q3. Is the consecutive-estimation cap a per-account rolling counter or calendar-bounded?

INV-045 says "tracks consecutive estimated reads per meter/account." Texas (INV-149) requires actual read every 6 months; PA §56.14 says 4 consecutive; MO says 3; NY HEFPA says 4 months. Is the counter:

- **(a)** A per-meter consecutive-read streak (resets on any actual read)?
- **(b)** A calendar window (X estimates within a 6-month window)?
- **(c)** Both, with the binding constraint being whichever fires first?

### Q4. Bi-temporal scope: are customer-attribute changes (rate class, contact info, billing address) bi-temporal?

HANDOFF.md lists "customer classification" and "Customer attributes (rate class, service address, contact info)" under "Needs bi-temporal treatment." Some customer attributes are clearly invariant-relevant (rate class, mailing address for notice service). Some seem operational (preferred contact method, donation opt-in). Does the bi-temporal scope cover all of `customers.*` or only the billing-relevant subset?

### Q5. Is the bill snapshot a JSONB blob on the invoice (current implementation), a separate `invoice_snapshots` table (HANDOFF.md option), or a content-addressable artifact in object storage (INV-099 from 16-bi-temporality §6.4)?

INV-039 (snapshot completeness) says "every input persisted." Current schema has `invoices.tax_breakdown JSONB` partially serving this. INV-099 suggests content-addressable artifacts. The bi-temporal-decision.md says "Postgres with linked snapshot tables." Three options on the table:

- **(a)** JSONB blob on invoices (current; minimal).
- **(b)** Separate snapshot table per invoice (HANDOFF.md option).
- **(c)** Content-addressable artifact in object storage (16-bi-temporality recommendation).

The invariant should be silent on mechanism but precise about completeness; the *implementation* is downstream.

### Q6. What is the exact set of programs whose enrollments are honored for disconnect bypass in Texas, and is the set extensible per tenant?

INV-068 (bypass conditions evaluated daily) lists a generic set; INV-154 (Texas EWE) and INV-155 (Texas medical hold) are Texas-specific. For launch:

- LIHEAP / agency pledge (16 TAC §7.460(c)): yes
- Medical certification (16 TAC §7.45 §5.4): yes
- EWE temperature hold (16 TAC §7.460): yes
- DPA in good standing: implied
- Family violence victim flag (16 TAC §7.45 §6.2 — affects deposits; does it also affect disconnect?): unclear
- Bankruptcy: federal, always yes

Is this list the full launch set, or are there RRC-recognized program holds I haven't captured? (E.g., does Texas recognize PIPP equivalents?)

### Q7. Does Texas have an arrearage forgiveness or AMP-equivalent program structurally?

08-payments-and-programs.md describes AMP (Arrearage Management Program) as a structured forgiveness program in Massachusetts and Pennsylvania. Texas does not appear in the AMP-recognized list. Is AMP-style enrollment in launch scope, or is it deferred? The schema's `payment_arrangement` family handles DPA but not arrearage forgiveness.

### Q8. Bilingual scope in Texas — is it English/Spanish only, or are there additional language obligations?

INV-147 captures English+Spanish per 16 TAC §7.45. Are there county-level requirements (Cameron, El Paso, Hidalgo, etc.) that extend the language set? Or does the state rule preempt?

---

## Open questions for Session 2 to resolve

These are framing/scoping decisions Session 2 should make in the categorize-and-score and review-low-confidence steps. The information needed is available in Session 1 artifacts; no external resolution required.

### S1. Final invariant count after deduplication.

Session 2 begins by walking the merge list in F6 (and finding others I missed). Target: 80–110 canonical invariants.

### S2. Re-confidence pass with stricter threshold.

Per F4, re-evaluate using stricter discipline.

### S3. Apply the "discipline vs. value" framing pass.

Per F2, separate invariant statement (discipline) from value/mechanism (configurable). Update Statement and review-note text accordingly.

### S4. Decide which Method-1 invariant docs the canonical list seeds.

Per the strategy, each canonical invariant becomes a Method-1 narrative doc. With 80–110 invariants and the strategy's expected scenario count (~60–120 across Method 1), some canonical invariants will share Method-1 docs (an "invariant family"), and some Method-1 docs will be slim. Session 2 should produce a tentative grouping that the strategy can validate. Suggested groupings:

- **Bi-temporal foundation family:** INV-035, INV-026, INV-097, INV-098, INV-100 → one Method-1 doc.
- **Date-effective reference data family:** INV-034, INV-005, INV-013, INV-017, INV-025, INV-125 → one doc.
- **Bill immutability and snapshot family:** INV-033, INV-039, INV-099, INV-126, INV-128 → one doc.
- **Append-only ledger family:** INV-036, INV-037, INV-114, INV-139, INV-140 → one doc.
- **Cancel-rebill correctness family:** INV-026, INV-100, INV-127 + reads/factor invariants → one doc.
- **Volume-to-energy and meter-correctness family:** INV-020, INV-021, INV-022, INV-023, INV-024, INV-025, INV-105 + Texas BTU reference → one doc.
- **PGA family:** INV-006, INV-013, INV-014, INV-015 / INV-079, INV-016, INV-017, INV-018, INV-145, INV-146 → one doc.
- **WNA family:** INV-027, INV-028, INV-029, INV-030, INV-031, INV-032 → one doc.
- **Tax and franchise family:** INV-003, INV-082, INV-083, INV-084, INV-085, INV-086 → one doc.
- **Collections eligibility and bankruptcy family:** INV-001, INV-067, INV-068, INV-069, INV-070, INV-071, INV-072, INV-073, INV-074, INV-075, INV-076, INV-077, INV-152, INV-153, INV-154, INV-155, INV-162 → one doc (possibly split bankruptcy out).
- **Payments and programs family:** INV-054, INV-055, INV-056, INV-057, INV-058, INV-059, INV-060, INV-061, INV-062, INV-063, INV-064, INV-065, INV-066, INV-109, INV-110, INV-111, INV-115, INV-116, INV-119, INV-121 → likely two docs (posting/processing vs. programs).
- **Audit trail and communication family:** INV-002, INV-089, INV-090, INV-091, INV-118, INV-134, INV-147 → one doc.
- **Texas regulatory family:** the remaining Texas-specific invariants (INV-143, INV-144, INV-148, INV-149, INV-150, INV-151, INV-156, INV-157, INV-158, INV-159, INV-160, INV-161) — possibly one or two docs.
- **Tenant isolation and structural integrity:** INV-123, INV-124, INV-136, INV-137, INV-138 → one doc.
- **Read pipeline and exception-handling family:** INV-024, INV-040, INV-041, INV-044, INV-045, INV-046, INV-048, INV-052, INV-130 → one doc.
- **Rate-and-rider-DAG family:** INV-008, INV-009, INV-010, INV-011, INV-047, INV-049, INV-104, INV-106, INV-107, INV-113 → one doc.
- **Operational pipeline integrity family:** INV-051, INV-053, INV-094, INV-112, INV-117, INV-120, INV-131, INV-133, INV-135 → one doc.
- **Mass-error-detection family:** INV-095, INV-096, INV-108 → one doc (small; might fold into operational).
- **MIMO, work orders, deposits, AI-agent family:** INV-042, INV-043, INV-093, INV-132, INV-134 — split per topic.

This is a starting structure for Session 2 to refine.

### S5. Resolve overlap with `bi-temporal-scenarios.md`.

The existing `application/bi-temporal-scenarios.md` is Level 2 narrative (style reference per the strategy). Session 2 should check whether its scenarios are captured by Method-1 invariant docs once produced — likely yes — and flag any unique scenarios there for inclusion or archival.

### S6. Schema enforcement status as an entry attribute.

Per F3 recommendation, add a "schema enforcement status" field to each canonical entry: `structurally-enforced` / `requires-application-discipline` / `unenforced-gap`. This is the single most useful structural metadata for downstream consumers (Method-1 architectural mapping, impossibility-proof scenarios, schema-hardening sessions).

---

## Handoff state

**Artifacts produced by Session 1:**

- `application/invariants/draft-candidates.md` — 162 candidate entries grouped by source, with the strategy-defined entry structure.
- `application/invariants/session-1-recon.md` — this report.

**Session 2 starting protocol (per strategy):**

Session 2 begins by reading (in order):
1. `application/invariants/session-1-recon.md` (this file)
2. User and domain-expert annotations on this recon report (when returned)
3. `application/invariants/draft-candidates.md`
4. Any architectural decisions that landed between sessions

Session 2's first message states: "I've read X, Y, Z. Here's where I'm picking up and what I'm doing first."

**Session 2 outputs:**

- `application/canonical-invariants.md` — the canonical document, ready for final domain-expert review.
- Updated `application/invariants/draft-candidates.md` reflecting Session 2's reconciliation and scoring (kept for traceability).

---

## See also

- [[draft-candidates]] — the raw candidate inventory this report summarizes
- [[scenario-mapping-strategy]] — the strategy governing this work unit
- [[execution-kickoff]] — the cross-strategy execution sequencing
- [[bi-temporal-decision]] — the locked architectural decision that grounds bi-temporal invariants
- [[bi-temporal-scenarios]] — style reference for Level 2 scenario specificity (downstream of this work)
