---
title: Canonical Invariants — Draft Candidates (Session 1)
type: draft-inventory
status: Session 2 complete (all 162 candidates reconciled into canonical-invariants.md CI-001–CI-135; see reconciliation map)
project: TallyUtility
tags: [tally-utility, invariants, architecture, data-model, research]
created: 2026-05-18
updated: 2026-05-18
---

# Canonical Invariants — Draft Candidates

This file is the running candidate inventory for Session 1 of the canonical invariants work unit. Candidates are appended as they are captured during reading. This is **not** the final canonical document — it is the raw harvest. Session 2 reconciles, scores, and finalizes into [[../canonical-invariants]].

**Session 2 reconciliation:** complete (all 15 batches). See the Session 2 reconciliation map below for the disposition of every candidate — merged into a canonical CI-NNN entry, or deferred-pending-question with an explicit Q-reference. No candidate remains "pending." Candidate entries themselves are preserved unchanged for traceability — the map is the single source of truth for merge status. The finalized canonical document is [[../canonical-invariants]] (135 entries CI-001–CI-135 across 17 families).

Each entry follows the strategy-defined structure:
- **Name** — short identifier
- **Statement** — the precise rule
- **Category** — `structural` | `computational`
- **Confidence** — `high` | `medium` | `low`
- **Source** — KB file(s) and rough location
- **Scope** — entities, tables, operations
- **Rationale** — regulatory citation, business justification, architectural reason
- **Known failure modes if violated** — links to gotchas / failure index
- **Related invariants** — coupling and dependency relationships
- **Review note** — *(medium/low confidence only)* what specifically is uncertain

Source files are read in the order specified by the strategy's Workflow Session 1: KB files first (to preserve original framing), then schema, then feature list as cross-reference.

---

## Source progress

- [x] 01-industry-and-regulatory.md
- [x] 02-tariffs-rates-riders.md
- [x] 03-pga-gas-cost-recovery.md
- [x] 04-zones-and-metering.md
- [x] 05-weather-normalization.md
- [x] 06-data-model.md
- [x] 07-billing-calculation.md
- [x] 08-payments-and-programs.md
- [x] 09-credit-collections-disconnects.md
- [x] 10-transportation-choice-edi.md
- [x] 11-taxes-and-gl-accounting.md
- [x] 13-gotchas-and-lessons.md
- [x] 16-bi-temporality.md
- [x] 25-rate-change-complexity.md
- [x] billing-failures/ directory (index + cross-cutting-patterns + stage-04 + stage-08 read in full; stages 01–03, 05–07, 09 summarized via 24-billing-failures-index)
- [x] schema.sql
- [x] feature-list.md (cross-reference pass — Stages 1–9 read in detail; Stages 10–19 skimmed via Notable Schema Gaps Summary and confirmed alignment with KB-derived candidates)
- [x] CONTEXT files (guiding principles — read at session start)
- [x] 31-texas-regulatory-compliance.md (Parts 1–8 read; Texas is launch scope per scenario-mapping-strategy.md)

---

## Session 2 reconciliation map

Each row: draft-candidate INV-NNN → canonical CI-NNN (or `pending` if not yet reconciled). Where a canonical entry merges multiple candidates, the same CI-NNN appears against each merged candidate. Where a candidate was excluded (e.g., re-evaluated as a config knob rather than an invariant), the row notes the exclusion reason.

| Draft | Status | Canonical | Notes |
|---|---|---|---|
| INV-005 | merged | CI-004 (Date-Effective Reference Data) | Rate/rider-specific framing absorbed into the broad date-effectivity entry. |
| INV-026 | merged | CI-005 (Cancel-Rebill Uses Original-Period World) | |
| INV-034 | merged | CI-004 (Date-Effective Reference Data) | Broad principle is the primary framing; INV-005 and INV-125 layered in. |
| INV-035 | merged | CI-001 (Bi-Temporality) | |
| INV-088 | merged | CI-009 (Audit-Proof Deterministic Calculation) | |
| INV-097 | merged | CI-002 (Correction vs. Retraction Distinguished) | |
| INV-098 | merged | CI-003 (Cross-Entity Temporal Coordinate Consistency) | |
| INV-100 | merged | CI-006 (Cancel-Rebill is a Pure Function) | |
| INV-101 | merged | CI-008 (Backbilling Cap Per Jurisdiction) | |
| INV-102 | merged | CI-010 (UTC Storage and Explicit Time-Zone Semantics) | Confidence stayed medium per F4 (tenant TZ mechanism not yet decided). |
| INV-103 | merged | CI-011 (Conflicting Concurrent Assertions Surface for Resolution) | Kept at low confidence per F5; flagged as pending-expert-review under Q-1 in canonical doc. |
| INV-127 | merged | CI-007 (Cancel-Rebill Correction Rate Mode is Explicit) | |
| INV-001 | merged | CI-067 (Disconnect Eligibility Respects Jurisdictional Rules) | Batch 8. The root invariant of Family 9 — single-funnel discipline composes every other Family-9 and Family-8 entry. |
| INV-002 | merged | CI-093 (Audit-Trail Subpoena Readiness) | Batch 10 / Family 12. The family root and the document's regulatory-facing capstone; ~14 prior entries forward-reference `[[CI-audit-trail-subpoena-readiness]]` and this entry supplies its canonical definition. `partially-structurally-enforced` (composition of Families 1+2 + communication-log gap A-16 + structurally-enforced AI-audit CI-099). |
| INV-003 | merged | CI-044 (Franchise Fee Traceable to Franchising Jurisdiction) | Batch 6. Merged with INV-086 per F6 — bill-side traceability and remittance-side reconciliation are two halves of one closed-loop financial mechanic. |
| INV-004 | merged | CI-132 (Regulatory Posture is a First-Class Tenant Attribute) | Batch 15 / Family 17. Survived the F5 inclusion gate — the "posture is a first-class attribute consulted by gates, never hard-coded" discipline is the canonical parent of the posture-conditional gates CI-035/CI-087/CI-104. F2 — posture taxonomy + gate mapping are config. |
| INV-006 | merged | CI-033 (PGA Pass-Through Discipline) | Batch 4. Merged with INV-007 — UAF cap is a composition of the pass-through discipline. |
| INV-007 | merged | CI-033 (PGA Pass-Through Discipline) | Batch 4. Merged with INV-006 — see note. UAF cap value is jurisdiction-configurable (Texas, WV, NY, CA differ); recorded as configurable boundary on CI-033. |
| INV-008 | merged | CI-101 (Rider Composition Follows a Deterministic Dependency DAG) | Batch 11 / Family 13. The rider stage's internal ordering within CI-100's pipeline; tax base computes after the DAG settles. |
| INV-009 | merged | CI-102 (Customer Charge Billed Independent of Usage) | Batch 11 / Family 13. Customer-charge amount and partial-period proration rule are configurable boundaries per F2. |
| INV-010 | merged | CI-103 (Minimum Bill Floor Applied When Specified) | Batch 11 / Family 13. F2 — floor binds whenever a schedule specifies one; which schedules specify one and the floor value are configurable. Confidence kept medium per review-note framing (resolved by F2). |
| INV-011 | merged | CI-104 (Rate-Schedule Reclassification Date-Effective and Notification-Bound) | Batch 11 / Family 13. F2 — date-effective + notification-bound + no-prior-mutation is the invariant; approval gate is configurable. `unenforced-gap` → new Appendix A-19 (account-schedule history + workflow substrate). |
| INV-012 | merged | CI-105 (Program Enrollment Honored in Rate and Rider Eligibility) | Batch 11 / Family 13. The billing-side counterpart of the Family-8 collections-side bypasses; composes with CI-064 / CI-043 / CI-054. Exclusion set per program is configurable boundary; depends on program-enrollment substrate A-11. |
| INV-013 | merged | CI-004 (Date-Effective Reference Data) | Batch 4. PGA-specific framing of broad date-effectivity per F6; the PGA-historical-retrievability claim is fully covered by CI-004 (date-effective) + CI-015 (snapshot completeness) + the Family 4 entries. No separate canonical entry. |
| INV-014 | merged | CI-034 (PGA Mid-Period Proration) | Batch 4. Proration method (calendar-day vs. degree-day vs. estimated) is configurable boundary. |
| INV-015 | merged | CI-037 (Commodity Charge Not Assessed to Transportation Customers) | Batch 4. Merged with INV-079 per F6 — duplicate framings from two KB-file vantages on the same rule. |
| INV-016 | merged | CI-036 (PGA Deferred-Account Accrual and Reconciliation) | Batch 4. Merged with INV-018 — accrual and reconciliation are two halves of one closed-loop financial mechanic. |
| INV-017 | merged | CI-035 (PGA Factor Future-Dated Activation) | Batch 4. Texas RRC monthly-filing cadence from INV-145 folded as configurable boundary. |
| INV-018 | merged | CI-036 (PGA Deferred-Account Accrual and Reconciliation) | Batch 4. Merged with INV-016 — see note. Per-rate-class vs. per-tenant-aggregate reconciliation scope is configurable boundary. |
| INV-019 | merged | CI-020 (Premise Zone Assignment Complete) | Batch 3. |
| INV-020 | merged | CI-021 (Volume-to-Energy Formula Composition) | Batch 3. |
| INV-021 | merged | CI-022 (Meter Rollover Arithmetic) | Batch 3. |
| INV-022 | merged | CI-023 (Meter Master Attributes Complete) | Batch 3. Merged with the meter-attribute half of INV-141 per F6. |
| INV-023 | merged | CI-024 (Meter-Swap Split Calculation Within Period) | Batch 3. |
| INV-024 | merged | CI-025 (Read Type Discipline) | Batch 3. |
| INV-025 | merged | CI-026 (Zone-Indexed Date-Effective Factor Tables) | Batch 3. |
| INV-027 | merged | CI-039 (WNA Scope Restricted to Distribution Charges) | Batch 5. |
| INV-028 | merged | CI-040 (WNA Seasonal Window Honored) | Batch 5. Period-straddling proration method (calendar-day vs. degree-day vs. estimated) is configurable boundary; season dates configurable. |
| INV-029 | merged | CI-041 (WNA Deadband Applied) | Batch 5. Confidence kept medium per Q-3 (deadband scoping per-zone vs. per-rate-schedule × zone — recon Q2 surfaced as canonical Flagged Q-3). |
| INV-030 | merged | CI-042 (WNA Inputs Captured in Bill Snapshot) | Batch 5. Kept as a separate canonical entry beyond CI-015 because NHDDs are recomputed periodically and not preserved by the bi-temporal reference layer — the snapshot is the *load-bearing* mechanism for WNA replay, distinct from CI-015's broad statement. |
| INV-031 | merged | CI-043 (WNA Customer Program Exclusions Honored) | Batch 5. Set of excluded programs is configurable boundary. |
| INV-032 | merged | CI-020 + CI-004 (decommission-supersede footnote in Appendix A-5) | Batch 5. Per F6: weather-station-to-premise mapping is already enumerated in CI-020's zone-assignment list; the decommission-supersede pattern is CI-004's date-effective discipline applied to that assignment. No separate canonical entry — the decommission-supersede dynamic is footnoted into Appendix A-5 to surface its composition with CI-042. |
| INV-033 | merged | CI-012 (Bill Immutability) | Batch 2. |
| INV-036 | merged | CI-013 (Append-Only Financial Ledger) | Batch 2. |
| INV-037 | merged | CI-014 (No Hard Deletes of Operational Records) | Batch 2. Kept separate from CI-013 — append-only is financial; no-hard-deletes is operational scope. |
| INV-038 | merged | CI-120 (Premise Persists Independent of Occupancy) | Batch 14 / Family 16. Data-model counterpart of CI-012 bill immutability. `partially-structurally-enforced` — service_locations distinct from accounts; the zone-assignment persistence is the A-5 premise-zone-FK gap. |
| INV-039 | merged | CI-015 (Invoice Snapshot Completeness) | Batch 2. |
| INV-040 | merged | CI-027 (Read–Meter–Service-Point Attribution) | Batch 3. Re-evaluated as `structurally-enforced` (FK + deployment history) — promoted from medium to high confidence per F4. |
| INV-041 | merged | CI-028 (Consumption Computed Once Per Read Pair) | Batch 3. Kept at medium confidence — framing well-named, table-shape question remains engineering-decision. |
| INV-042 | merged | CI-121 (Account Lifecycle State Discipline) | Batch 14 / Family 16. F2 — explicit-vs-derived state-machine is the engineering boundary; lifecycle + transition-events + date-effective-attributes is the invariant. `unenforced-gap` → new Appendix A-21 (account-state-events + date-effective account attributes). |
| INV-043 | merged | CI-125 (Deposit Interest Accrual Discipline) | Batch 14 / Family 16. The universal deposit-interest rule; Texas CI-130 (INV-157) is its jurisdiction-specific instance. `unenforced-gap` → A-21 (deposit/interest ledger). Rate/basis/schedule jurisdiction-prescribed configurable. |
| INV-044 | merged | CI-100 (Billing Pipeline Staged Acyclic Dataflow) | Batch 11 / Family 13. The family root. F2 — exact stage list is the configurable/architectural boundary; the staged-acyclic-no-backflow discipline is the invariant. Confidence kept medium per review-note framing (resolved by F2). |
| INV-045 | merged | CI-113 (Consecutive Estimation Cap Enforced) | Batch 12 / Family 14. `unenforced-gap` — counter not modeled (Q-10 = recon Q3 counter-shape, distinct from canonical Q-3 WNA). Cap value is jurisdiction-prescribed configurable boundary; Texas CI-090 is a jurisdiction-specific instance. |
| INV-046 | merged | CI-114 (Estimation True-Up Method Consistently Applied) | Batch 12 / Family 14. F2 — method (catch-up vs. cancel-rebill) is jurisdiction-prescribed configurable; consistent-application-per-jurisdiction is the invariant. Composes CI-005 cancel-rebill original-period world. |
| INV-048 | merged | CI-115 (Pre-Mail Exception Routing and Pre-Delivery Control Gate) | Batch 12 / Family 14. Merged with INV-095 per F6 — INV-095's system kernel is the per-cycle pre-delivery gate INV-048 states precisely; canary-accounts is one configurable implementation per F2. Exception-queue substrate is gap A-20. |
| INV-047 | merged | CI-106 (Mid-Period Tariff Change — Segment-Independent Full Charge Stack) | Batch 11 / Family 13. Merged with INV-104 per F6 — INV-104 is INV-047's rigorous full-charge-stack form (INV-047 states the split; INV-104 states the *entire* stack splits per segment). Proration method is configurable boundary. |
| INV-049 | merged | CI-109 (Tariff-Dictated Rounding Applied Consistently) | Batch 11 / Family 13. F2 — rounding precision/mode/scope is tariff-prescribed configurable; one-tariff-version-one-rounding-population-wide is the invariant. |
| INV-050 | merged | CI-110 (Unbilled Revenue Accrual Reverses With Lineage) | Batch 11 / Family 13. Period-close-accrual instance of CI-017 reversal-lineage strengthened with a must-reverse obligation; composes CI-013. F2 — JE mechanism is engineering boundary. |
| INV-051 | merged | CI-122 (MIMO Events Produce Required Billing Events) | Batch 14 / Family 16. F2 — workflow orchestration is the boundary; required-event-completeness is the invariant. Composes CI-024 / CI-102 / CI-077 / CI-124. |
| INV-053 | merged | CI-123 (Meter Change-Out Propagates to Billing Before Bill Generation) | Batch 14 / Family 16. Kept distinct from CI-024 per F6 — CI-024 is the calculation given a known swap; CI-123 is the data-pipeline-freshness guarantee that billing knows before it bills ("swap Monday, billing Thursday"). |
| INV-052 | merged | CI-112 (Read Validation Exception Resolved Before Billing) | Batch 12 / Family 14. The read→bill gate (upstream of CI-115's bill→delivery gate). Exception-queue / validation-state substrate is gap A-20. |
| INV-054 | merged | CI-049 (Payment Allocation Discipline) | Batch 7. Merged with INV-109 per F6 — base posting order and customer earmarking are two facets of one allocation algorithm. Q-5 flagged (UCC §3-310 earmarking vs. tariff posting order). Confidence kept medium pending Q-5 resolution. |
| INV-055 | merged | CI-051 (PCI-DSS No-PAN-Storage Discipline) | Batch 7. Merged with INV-138 per F6 — broad principle + schema-encoded impossibility-proof form (same pattern as INV-005/INV-034/INV-125 → CI-004). |
| INV-056 | merged | CI-052 (ACH Return Code-Specific Handling) | Batch 7. Per-code handling rules are NACHA/state-defined; returned-payment fee amount is state-tariff-capped (configurable boundaries). |
| INV-057 | merged | CI-053 (Unapplied Cash and Suspense Holding Discipline) | Batch 7. Suspense ledger is a schema gap (Appendix A-12). |
| INV-058 | merged | CI-054 (Late-Fee Assessment with Program and Dispute Exemptions) | Batch 7. Grace period, rate, state cap, exempt-program set, and postmark-policy all configurable boundaries. |
| INV-059 | merged | CI-059 (Budget Billing Balance Tracking and Settle-Up) | Batch 7 / Family 8. Budget-billing enrollment is a schema gap (Appendix A-11). |
| INV-060 | merged | CI-060 (Deferred Payment Arrangement Breach Discipline) | Batch 7 / Family 8. Breach-trigger configuration and post-breach-grace window are configurable boundaries. |
| INV-061 | merged | CI-061 (Pledge-Held Disconnect Eligibility Suspension) | Batch 7 / Family 8. Commitment-period length and accepted-pledge-source set are configurable boundaries. |
| INV-062 | merged | CI-062 (Medical Certification Disconnect Hold) | Batch 7 / Family 8. Effective duration, renewal-window, and attestation requirements are state-statutory configurable boundaries. |
| INV-063 | merged | CI-063 (SCRA Active-Duty Protections Honored) | Batch 7 / Family 8. Federal SCRA jurisdiction. Confidence kept medium per source on specific gas-utility application variation. |
| INV-064 | merged | CI-064 (Multi-Program Enrollment Composition) | Batch 7 / Family 8. The central architectural property of Family 8 — additive composition, not "one program wins". |
| INV-065 | merged | CI-065 (Program Enrollment Lifecycle and Recertification) | Batch 7 / Family 8. Merged with INV-115 program-side per F6 — INV-115 is the meta-rule generalizing recertification across artifact types; tax-cert side folded as confirming citation on CI-046. |
| INV-066 | merged | CI-066 (Third-Party Notification Non-Binding) | Batch 7 / Family 8. |
| INV-067 | merged | CI-068 (Collections Pipeline Step Completeness) | Batch 8. INV-152 Texas 15+5+5 sequence folds as configurable boundary example per F2, not a separate entry. |
| INV-068 | merged | CI-069 (Bypass Conditions Evaluated at Each Pipeline Step) | Batch 8. Q-6 flagged (Texas bypass-set membership scope per recon Q6). Bypass-set membership per jurisdiction is configurable boundary; evaluation discipline is the invariant. |
| INV-069 | merged | CI-070 (Disconnect Execution Evidence Required) | Batch 8. Confidence kept medium per source on completeness-check granularity policy variation. |
| INV-070 | merged | CI-072 (Gas Reconnection Requires On-Site Technician) | Batch 8. Impossibility-proof per INV-070 source review note — confirmed at canonical-entry time. Schema literally cannot effect a remote gas reconnect. Architectural twin of CI-051 PCI no-PAN. |
| INV-071 | merged | CI-073 (Reconnection SLA Honored) | Batch 8. SLA duration jurisdiction-varied; clock-start definition (conditions-met vs. customer-availability) is configurable boundary. |
| INV-072 | merged | CI-082 (Bankruptcy Absolute Stay 11 USC §362) | Batch 8 / Family 10. Federal jurisdiction; immediate-and-absolute property includes in-flight field activity reversal. |
| INV-073 | merged | CI-083 (Pre- and Post-Petition Ledger Split) | Batch 8 / Family 10. Federal bankruptcy code; petition-date partition mechanism is the schema gap (A-15). |
| INV-074 | merged | CI-084 (Bankruptcy Adequate Assurance Window 11 USC §366) | Batch 8 / Family 10. Confidence kept medium per source on state-PUC layered restrictions. |
| INV-075 | merged | CI-074 (Meter and Billing Dispute Suspends Collections on Disputed Amount) | Batch 8. INV-151 Texas disputed-amount-cap-on-required-payment folded as configurable boundary value per F2. Disputes table is schema gap (A-15). |
| INV-076 | merged | CI-076 (Write-Off Aging Discipline and Bad-Debt Recovery) | Batch 8. Aging-threshold value and Bad Debt Rider mechanics are configurable boundaries. Confidence kept medium per source on rider-mechanics variation. |
| INV-077 | merged | CI-075 (Collections Engine Deterministic and Idempotent) | Batch 8. Engine-side twin of CI-006 (cancel-rebill purity) and CI-009 (audit-proof determinism); idempotency-on-replay addition distinct from pure determinism. |
| INV-078 | merged | CI-077 (Deposit Amount Tied to Credit Evaluation) | Batch 8. Texas deposit-cap (1/6 annual per INV-156), mandatory waivers (INV-156), interest accrual (INV-157), and automatic refund triggers (INV-158) compose in Batch 14 deposit sub-family. |
| INV-079 | merged | CI-037 (Commodity Charge Not Assessed to Transportation Customers) | Batch 4. Merged with INV-015 per F6 — see note above. |
| INV-080 | deferred | Q-12(a) (transport balancing launch scope) | Batch 15. Real discipline (imbalance charges / monthly cashout / OFO penalties) but balancing-subsystem launch scope is uncertain — deferred pending Q-12, same pattern as INV-087/Q-4 and INV-096/Q-9. Canonical entry to be added post-review if in-scope. |
| INV-081 | merged | CI-133 (Transport Eligibility Volume-Gated and Workflow-Controlled) | Batch 15 / Family 17. Clean tariff-applicability rule; the eligibility gate is the trigger, CI-104 is the migration workflow, CI-037 is why it matters to the bill. Threshold values are tariff-configurable. |
| INV-082 | merged | CI-045 (Tax Stacking and Base Composition Discipline) | Batch 6. |
| INV-083 | merged | CI-046 (Tax Exemption Certificate Lifecycle and Period Validity) | Batch 6. Exempt-category set, certificate validity period, and renewal-cadence are configurable boundaries. |
| INV-084 | merged | CI-047 (Tax Jurisdiction Assignment by Geographic Ground Truth) | Batch 6. Geocoding mechanism (internal vs. third-party tax engine) and override workflow are configurable boundaries per F2. Confidence kept medium pending engineering decision on geocoding mechanism. |
| INV-085 | merged | CI-048 (Revenue Distribution Matrix Deterministic and Complete) | Batch 6. |
| INV-086 | merged | CI-044 (Franchise Fee Traceable to Franchising Jurisdiction) | Batch 6. Merged with INV-003 per F6 — see note. Per-municipality remittance reconciliation half of the closed-loop mechanic. |
| INV-087 | deferred | Q-4 (CIAC: CIS scope or ERP scope?) | Batch 6. F5 productive-question test: CIAC tracking may live in ERP rather than CIS. **Confirmed still deferred at Batch 15** — domain-expert review (the gating step that resolves Q-4) is out of Session 2 scope and no expert annotation has landed; no resolution is fabricated. Canonical entry to be added in a post-review pass if Q-4 resolves as in-CIS-scope. |
| INV-089 | merged | CI-094 (Regulated Notice Language Versioned) | Batch 10 / Family 12. Notice-side analogue of CI-004 date-effective; notice-template versioning is schema gap A-17. Slug matches the `[[CI-regulated-notice-language-versioned]]` forward-references CI-070/CI-088/CI-089 made. |
| INV-090 | merged | CI-095 (Communication Log Completeness) | Batch 10 / Family 12. Merged with the INV-142 gap finding per F3 — the communication-log gap is Appendix A-16; CI-095 carries `unenforced-gap`. Slug matches the `[[CI-communication-log-completeness]]` forward-reference CI-088 made. |
| INV-091 | merged | CI-096 (Bill Image Retention and Retrievability) | Batch 10 / Family 12. Kept distinct from CI-015 — the as-delivered image is retained *in addition to* the calculation snapshot because re-render is not byte-guaranteed across template drift. Archive-store substrate is schema gap A-18. Retention period jurisdiction-configurable (7-year U.S. default). |
| INV-092 | deferred | Q-12(b) (tenant submetering launch scope) | Batch 15. Real regulatory concern (jurisdictional submetering prohibition) but depends on whether a first-class submeter/master-meter model is in launch scope — deferred pending Q-12 rather than hard-excluded, given the legal-exposure stakes. Canonical entry post-review if in-scope. |
| INV-093 | merged | CI-085 (Estate and Deceased Customer Collections Hold) | Batch 8 / Family 10. Structurally analogous to CI-082 bankruptcy stay — different statute, same statutory-hold shape. Confidence kept medium per source on trigger-source variation. |
| INV-094 | merged | CI-098 (Inbound Vendor File Format-Drift Tolerance and Replay) | Batch 10 / Family 12. Ingestion-side instance of the idempotent-replay discipline shared with CI-055 (payment intake) and CI-075 (collections engine). Confidence kept medium per review note (ingestion-adapter substrate is an engineering decision). |
| INV-095 | merged | CI-115 (Pre-Mail Exception Routing and Pre-Delivery Control Gate) | Batch 12 / Family 14. Merged with INV-048 per F6 — the candidate's own review note (INV-048 covers the system invariant; canary-accounts-vs-pre-mail-review is the implementation) is the F6/F2 resolution. Routed from Batch 10 as planned. |
| INV-096 | deferred | Q-9 (External-vendor rate-lag reconciliation: CIS-owned invariant or out-of-system report?) | Batch 10. F5 productive-question test, parallel to INV-087 → Q-4. The invariant kernel may be fully covered by CI-047 + CI-004 + cancel-rebill detection path with the residual being an operational report. **Confirmed still deferred at Batch 15** — same reason as INV-087: domain-expert review is out of Session 2 scope; no resolution fabricated. Canonical entry in a post-review pass if Q-9 resolves as in-CIS-scope. |
| INV-099 | merged | CI-015 (Invoice Snapshot Completeness) | Batch 2. Content-addressable framing folded as implementation-strategy note inside CI-015's Configurable boundary; not a separate canonical entry per recon §F5 review (content-addressability is one of three storage options considered in [[bi-temporal-decision]] §2.3, with Option B linked-table chosen). |
| INV-104 | merged | CI-106 (Mid-Period Tariff Change — Segment-Independent Full Charge Stack) | Batch 11 / Family 13. Merged with INV-047 per F6 — see note above. The rigorous full-charge-stack form: base/block/demand/riders/WNA/PGA/tax all split per segment, not just the commodity charge. |
| INV-105 | merged | CI-029 (Pressure Factor Restricted to Elevated-Pressure Meters) | Batch 3. |
| INV-106 | merged | CI-107 (Seasonal Rate Keyed to Meter-Read Date) | Batch 11 / Family 13. Concrete instance of CI-003 / CI-004 temporal-coordinate discipline — the valid-time anchor for seasonal-rate selection is the consumption/read date, not bill-issue date. |
| INV-107 | merged | CI-108 (Tier Thresholds Prorate With Period Length) | Batch 11 / Family 13. F2 — prorate-unless-tariff-forbids is the invariant default; the no-proration schedules are the configured exception. Composes with CI-106 (each split segment's thresholds prorate). |
| INV-108 | merged | CI-134 (Batch Absolute-Baseline Mass-Error Gate) | Batch 15 / Family 17. Survived F5 strongly — the batch-level complement to CI-115's per-bill gate; the documented Hydro One 84,394-customer pattern that per-bill checks structurally cannot catch. Kept distinct from CI-115 (different granularity, not a dedup). Baselines/tolerances configurable per F2. |
| INV-109 | merged | CI-049 (Payment Allocation Discipline) | Batch 7. Merged with INV-054 per F6 — see note above. UCC §3-310 earmarking is one facet of the allocation algorithm; Q-5 flagged. |
| INV-110 | merged | CI-050 (Regulated-Before-Unregulated Allocation Constraint) | Batch 7. Minnesota PUC CenterPoint Minnesota case (March 2024); composes as a hierarchical floor on top of CI-049. |
| INV-111 | merged | CI-055 (Payment Intake Idempotency) | Batch 7. Web / IVR / mobile / agent-phone intake-channel adapters. |
| INV-112 | merged | CI-071 (Disconnect Work Order Field Verification) | Batch 8. Confidence kept medium per source on the system-side vs. procedural-discipline bridge. |
| INV-113 | merged | CI-111 (Bill Template and Rate Engine Changes Coordinated) | Batch 11 / Family 13. Composes with Batch-10 CI-094 (versioned regulated notice) — the coordination discipline keeps template version and rate-item version in lockstep. Depends on notice-template substrate A-17. F2 — which line items are display-mandated is jurisdiction-configurable. |
| INV-114 | merged | CI-018 (Reversal Chains Unbounded) | Batch 2. |
| INV-115 | merged | CI-046 (tax-exemption-side) + CI-065 (program-enrollment-side) | Batch 7. F6 split — INV-115 is the meta-rule generalizing the recertification pattern across both artifact types; tax-cert side folded as confirming citation on CI-046 (Batch 6), program-enrollment side merged with INV-065 → CI-065 (Batch 7). |
| INV-116 | merged | CI-056 (Pledge and Suspense Processing SLA Discipline) | Batch 7. SLA duration per program/jurisdiction is configurable boundary; PA PROMISe 30-day Crisis-pledge SLA is the canonical citation. |
| INV-117 | merged | CI-135 (Print-Mail Integrity and PII-Breach Classification) | Batch 15 / Family 17. System-side kernel survived F5 — match-assertion recorded per bill; mismatch = tracked PII-breach event. Kept distinct from CI-095 (not folded) because the statutory breach-notification consequence is a distinct Method-1 scenario surface. Vendor-side physical controls are the configurable boundary. |
| INV-118 | merged | CI-097 (Bilingual and Accessibility Delivery Honored) | Batch 10 / Family 12. The universal discipline that CI-088 (Texas English/Spanish) is a jurisdiction-specific instance of; slug matches the `[[CI-bilingual-and-accessibility-delivery-honored]]` forward-references CI-066/CI-088 made. Confidence kept medium per review note (in-scope accessibility-format / per-jurisdiction language-set is unenumerated config, not framing doubt). |
| INV-119 | merged | CI-057 (ACH Notice-of-Change Action Window) | Batch 7. NACHA 6-banking-day window is firm; action workflow within window is LDC-configurable. |
| INV-120 | merged | CI-124 (Final Bill Issued Only After Pending Adjustments Settle) | Batch 14 / Family 16. Routed from Batch 7's deferral. Composes CI-122 (move-out trigger) + CI-005 (post-closure correction is a cancel-rebill) + CI-013 (late adjustment appended). |
| INV-121 | merged | CI-058 (Payment Effective Date Discipline) | Batch 7. Per-jurisdiction effective-date method (postmark / lockbox-receipt / bank-settlement) is the configurable boundary. |
| INV-122 | deferred | Q-12(c) (combined multi-commodity billing launch scope) | Batch 15. Real cross-commodity allocation discipline but explicitly out of the gas-only launch scope; its own review note asks "framing now or deferred?" — deferred pending Q-12. Canonical entry post-review if/when multi-commodity launches. |
| INV-123 | merged | CI-116 (Tenant Isolation by Foreign Key) | Batch 13 / Family 15. The most platform-existential invariant. `partially-structurally-enforced` — write-side fully structural; read-side enforcement is Q-11 (RLS vs. application query-predicate). Structural-guarantee inverse of the CI-014/051/072/099 impossibility-proofs. |
| INV-124 | merged | CI-117 (Business Identifiers Unique Per Tenant) | Batch 13 / Family 15. `structurally-enforced` — UNIQUE (tenant_id, identifier) + tenant_sequences. Namespaced (not global) uniqueness is deliberate and coexists with CI-116. |
| INV-126 | merged | CI-016 (Line-Item Value Snapshot) | Batch 2. |
| INV-128 | merged | CI-017 (Reversal Lineage Explicit) | Batch 2. Merged with INV-139: invoice rebill lineage and payment reversal lineage are the same structural pattern on two entities. |
| INV-129 | merged | CI-030 (Read Supersede Pattern) | Batch 3. |
| INV-130 | merged | CI-031 (Billing-Period Lock on Meter Readings) | Batch 3. |
| INV-131 | merged | CI-032 (Meter Deployment Lineage) | Batch 3. |
| INV-134 | merged | CI-099 (AI Action Audit Completeness) | Batch 10 / Family 12. Pulled out of the Batch-14 INV-132–137 range into the audit family — it is the AI-specific specialization of CI-093. `structurally-enforced` (ai_audit_log + ai_audit_id FKs exist); the document's fourth impossibility-proof alongside CI-014, CI-051, CI-072. |
| INV-132 | merged | CI-126 (Customer Credit and Escheatment Tracking) | Batch 14 / Family 16. `partially-structurally-enforced` — customer_credits + escheatment_events tables exist; due-diligence/escheatment workflow is app discipline. Multi-jurisdiction (state unclaimed-property law). |
| INV-133 | merged | CI-127 (Approval Threshold Captured at Charge Creation) | Batch 14 / Family 16. `structurally-enforced` — adhoc_charges.approval_threshold_at_creation. RBAC instance of the "what was the rule then" pattern (CI-004/CI-035/CI-087). Confidence kept medium per RBAC-scope-breadth uncertainty (framing is sound). |
| INV-135 | merged | CI-128 (Anomaly Detection Deduplication) | Batch 14 / Family 16. `structurally-enforced` — UNIQUE (tenant_id, dedup_key). Structural kin of CI-118/CI-119 (UNIQUE-makes-duplicate-impossible) applied to operational monitoring. |
| INV-134 moved to Batch 10 / CI-099; INV-136/INV-137 to Batch 13 (CI-118/CI-119). | — | — | (Pointer row retained for traceability — see those batch rows above.) |
| INV-136 | merged | CI-118 (Import Job Idempotency) | Batch 13 / Family 15. `structurally-enforced` — UNIQUE (tenant_id, idempotency_key). The schema-enforced anchor of the idempotency thread; CI-055 / CI-075 / CI-098 are its application-discipline cousins. |
| INV-137 | merged | CI-119 (Billing-Run Meter Uniqueness Per Run) | Batch 13 / Family 15. `structurally-enforced` — UNIQUE (billing_run_id, meter_id). Composes CI-100 (pipeline batch unit) + CI-012 (re-runs append, not mutate). |
| INV-138 | merged | CI-051 (PCI-DSS No-PAN-Storage Discipline) | Batch 7. Merged with INV-055 per F6 — see note above. Schema-encoded impossibility-proof form of the no-PAN principle. |
| INV-139 | merged | CI-017 (Reversal Lineage Explicit) | Batch 2. Merged with INV-128 — see note above. |
| INV-140 | merged | CI-019 (Account Ledger Running Balance Discipline) | Batch 2. Kept at low confidence per F5; flagged as pending-expert-review under Q-2 in canonical doc. |
| INV-141 | merged | Appendix A-5 + CI-020 + CI-023 | Batch 3. Gap finding — per recon §F3, the substance is captured in Appendix A-5 (premise-zone FKs + meter-attribute columns) and the affected invariants (CI-020 Premise Zone Assignment Complete, CI-023 Meter Master Attributes Complete) carry `unenforced-gap` schema-enforcement status. |
| INV-142 | merged | Appendix A-16 (+ CI-095 carries `unenforced-gap`) | Batch 10 / Family 12. Gap finding per F3 — the communication-log gap is captured in Appendix A-16 and CI-095 (Communication Log Completeness) carries `unenforced-gap` status citing it. No separate canonical entry. |
| INV-143 | merged | CI-086 (Texas — Sub-Jurisdiction Flag Per Account) | Batch 9 / Family 11. Inc/Env flag is Texas-statutory; FK chain (direct column vs. reference table) is engineering-configurable. |
| INV-144 | merged | CI-087 (Texas — Rate Change SOI Workflow and Waiting Period) | Batch 9 / Family 11. Analogous future-dated-activation pattern to CI-035 PGA. SOI workflow is gap. |
| INV-145 | merged | CI-035 (configurable boundary) + CI-036 (confirming Texas citation) | Batch 4. Texas RRC monthly-filing cadence (last business day, first-of-month effective) folded as configurable boundary on CI-035 per F2 discipline-vs-value; prospective-only-adjustment rule confirms the deferred-account discipline on CI-036 (TX 16 TAC §7.5519 cited). |
| INV-146 | merged | CI-038 (Pipeline Safety Fee Surcharge Discipline) | Batch 4. Texas-specific entry; jurisdiction: texas per F1. |
| INV-147 | merged | CI-088 (Texas — Bilingual Notice Discipline) | Batch 9 / Family 11. Q-8 flagged (Texas bilingual scope — county-level extensions vs. state preemption per recon Q8). Confidence kept medium pending Q-8. |
| INV-148 | merged | CI-089 (Texas — Bill Format Mandatory Elements) | Batch 9 / Family 11. Customer-disclosure-side discipline distinct from CI-015 replay-side snapshot completeness. |
| INV-149 | merged | CI-090 (Texas — Actual Read Cadence and Estimated-Bill Marking) | Batch 9 / Family 11. Composes with CI-025 Read Type Discipline + CI-078 Texas disconnect-eligible-bases carve-outs (estimated-bill marker is what enables the carve-out evaluation). |
| INV-150 | merged | CI-078 (Texas — Disconnect-Eligible-Bases Carve-Outs) | Batch 8. Merged with INV-162 per F6 — INV-150 estimated-bills-outside-plan ground is one of INV-162's six carve-out grounds. |
| INV-151 | merged | CI-074 (configurable boundary value example) | Batch 8. Texas-specific disputed-amount-cap-on-required-payment (16 TAC §7.45 §4.4: not exceeding 2-year same-period average at current rates, until resolution or 60 days from issuance) folded as configurable boundary value on CI-074 per F2 — not a separate canonical entry. |
| INV-152 | merged | CI-068 (configurable boundary value example) | Batch 8. Texas 15+5+5-day disconnect-prerequisite sequence (TUC §104.258) folded as configurable boundary value on CI-068 per F2 — not a separate canonical entry. The sequence values are Texas-specific; the step-completeness discipline is universal. |
| INV-153 | merged | CI-079 (Texas — No Disconnect Before Utility-Closed Days) | Batch 8. Texas-specific calendar discipline; jurisdiction: texas per F1. |
| INV-154 | merged | CI-080 (Texas — Extreme Weather Emergency Disconnect Prohibition) | Batch 8. NWS-station-based predicate (≤32°F prior-day-high + ≤32°F next-24-hour forecast); 16 TAC §7.460. AG civil-penalty exposure. Q-6 named on CI-080. |
| INV-155 | merged | CI-081 (Texas — Medical Hold Installment-Agreement Requirement) | Batch 8. Composes with CI-062 (medical cert disconnect hold) + CI-060 (DPA breach discipline). Texas adds the installment-agreement-as-condition-of-hold structural requirement. |
| INV-156 | merged | CI-129 (Texas — Deposit Cap and Mandatory Waivers) | Batch 14 / Family 16. jurisdiction: texas per F1. Texas overlay on CI-077 (credit eval drives amount; Texas caps/waives). 1/6 cap, waiver classes, good-payment exception are 16 TAC §7.45 configurable. |
| INV-157 | merged | CI-130 (Texas — Deposit Interest Accrual Rules) | Batch 14 / Family 16. jurisdiction: texas. Texas instance of CI-125 — retroactive-to-deposit-date accrual once 30-day grace lapses (the subtle correctness point). |
| INV-158 | merged | CI-131 (Texas — Deposit Automatic Refund Trigger) | Batch 14 / Family 16. jurisdiction: texas. Automatic+mandatory on disconnect (balance-first ordering) or 12-consecutive-bills condition; composes CI-075 (engine-monitored standing condition) + Texas collections. |
| INV-159 | merged | CI-091 (Texas — Meter Test Fee Discipline) | Batch 9 / Family 11. 4-year-free / $15-cap / refund-on-defect discipline; meter-test-history table is a schema gap. |
| INV-160 | merged | CI-092 (Texas — Meter Error Rebill Bounds) | Batch 9 / Family 11. Texas-specific specialization of CI-008 backbilling cap (6-month meter-error variant distinct from 12-month general cap). Composes with CI-091 meter-test result. |
| INV-161 | merged | CI-021 (Volume-to-Energy Formula Composition) | Batch 3. Texas reference conditions (60°F / 14.65 psia / gross-real-dry) folded as configurable-boundary value on CI-021 per F2 (discipline-vs-value framing) — not a separate canonical entry. |
| INV-162 | merged | CI-078 (Texas — Disconnect-Eligible-Bases Carve-Outs) | Batch 8. Merged with INV-150 per F6 — Texas-specific enumeration of six grounds (previous-occupant, merchandise, different-utility, stale-underbilling, faulty-metering, estimated-outside-plan) that cannot trigger disconnect; jurisdiction: texas per F1. |

**Batch 1 complete:** 13 candidates merged into 11 canonical entries (CI-001 through CI-011).
**Batch 2 complete:** 10 candidates merged into 8 canonical entries (CI-012 through CI-019).
**Batch 3 complete:** 14 candidates merged into 13 canonical entries (CI-020 through CI-032).
**Batch 4 complete:** 11 candidates merged into 6 canonical entries (CI-033 through CI-038) plus 1 dedup back into Family 1 (INV-013 → CI-004). Remaining: ~114 candidates pending in subsequent batches.
**Batch 5 complete:** 6 candidates merged into 5 canonical entries (CI-039 through CI-043) plus 1 dedup back into Family 3 (INV-032 → CI-020 + CI-004 via Appendix A-5 decommission-supersede footnote). Q-3 added to canonical Flagged section (WNA deadband scoping per-zone vs. per-rate-schedule × zone). Family 5 added to Appendix B (proposed Method-1 doc: weather-normalization.md). Remaining: ~108 candidates pending in subsequent batches.
**Batch 6 complete:** 7 candidates → 5 canonical entries (CI-044 through CI-048) plus 1 F6 merge (INV-086 → CI-044 with INV-003) plus 1 deferred-pending-Q-4 (INV-087 CIAC scope). Three new Appendix A entries (A-8 tax_jurisdictions, A-9 tax-exemption-certificate metadata, A-10 revenue distribution matrix). Q-4 added to canonical Flagged section (CIAC: CIS scope or ERP scope?). Family 6 added to Appendix B (proposed Method-1 doc: taxes-franchise-fees-and-gl-posting.md). Remaining: ~101 candidates pending in subsequent batches.
**Batch 7 complete:** 22 candidates → 18 canonical entries (CI-049 through CI-066) plus 3 F6 merges (INV-054 + INV-109 → CI-049 allocation discipline; INV-055 + INV-138 → CI-051 PCI no-PAN; INV-115 split across CI-046 + CI-065). Two families added (Family 7 payment posting and processing, Family 8 customer programs and enrollment lifecycle) per kickoff's two-docs-likely framing. Three new Appendix A entries (A-11 program enrollment schema, A-12 suspense ledger, A-13 payment posting order configuration). Q-5 added to canonical Flagged section (UCC §3-310 earmarking vs. tariff posting order). Two Method-1 docs proposed in Appendix B: payment-allocation-and-posting.md + payment-intake-channels-and-reversal-handling.md (Family 7), and customer-programs-and-enrollment-lifecycle.md (Family 8). Remaining: ~79 candidates pending in subsequent batches.
**Batch 8 complete:** 21 candidates → 19 canonical entries (CI-067 through CI-085) plus 2 F6 merges (INV-150 + INV-162 → CI-078 Texas disconnect-eligible-bases carve-outs; INV-151 and INV-152 folded as F2 configurable-boundary value examples on CI-074 and CI-068 respectively, not separate entries). Two families added (Family 9 collections-and-disconnect with 4 Texas overlay entries CI-078–CI-081; Family 10 bankruptcy-and-estate with 4 entries CI-082–CI-085). Two new Appendix A entries (A-14 collections-engine configuration substrate, A-15 disputes table + bankruptcy/estate workflow tables + pre-/post-petition ledger partition). Q-6 added to canonical Flagged section (Texas program-bypass set scope per recon Q6). Method-1 docs proposed in Appendix B: collections-pipeline-and-disconnect-eligibility.md + disconnect-execution-reconnect-and-deposit.md + texas-collections-overlay.md (Family 9), and bankruptcy-and-estate-statutory-holds.md (Family 10). Remaining: ~60 candidates pending in subsequent batches (mostly Batch 9 Texas non-collections residual, Batch 10 audit/communication, Batch 11 rate-DAG, Batch 12 read-exception, Batch 13 tenant-isolation, Batch 14 MIMO/deposits, Batch 15 cleanup).
**Batch 9 complete:** 7 candidates → 7 canonical entries (CI-086 through CI-092) all `jurisdiction: texas` per F1. One new family (Family 11 Texas regulatory residual — topic-heterogeneous grouping for Texas-launch review coherence; the Method-1 docs split by topic into texas-sub-jurisdiction-and-rate-change-workflow.md + texas-bill-format-read-cadence-and-meter-rules.md). No new Appendix A entries (existing gaps cover the substrate needs). Q-7 added to canonical Flagged section (Texas AMP-equivalent arrearage forgiveness scope per recon Q7). Q-8 added to canonical Flagged section (Texas bilingual scope — county-level extensions vs. state preemption per recon Q8). Remaining: ~53 candidates pending in subsequent batches.
**Batch 10 complete:** 10 candidates → 7 canonical entries (CI-093 through CI-099 — Family 12 audit trail and communication, the regulatory-facing capstone) plus 1 F3 gap-merge (INV-142 → Appendix A-16, CI-095 carries `unenforced-gap`) plus 1 forward-route (INV-095 → Batch 12, composes with INV-048) plus 1 deferred-pending-Q-9 (INV-096 external-vendor rate-lag reconciliation scope). INV-134 pulled out of the Batch-14 INV-132–137 range into this family (CI-099, the document's fourth impossibility-proof). INV-092 stays pending → Batch 15. The four forward-referenced slugs (`CI-audit-trail-subpoena-readiness`, `CI-communication-log-completeness`, `CI-regulated-notice-language-versioned`, `CI-bilingual-and-accessibility-delivery-honored`) are now resolved with canonical definitions. Three new Appendix A entries (A-16 outbound communication log, A-17 notice-template versioning, A-18 bill-image archive store). Q-9 added to canonical Flagged section (external-vendor rate-lag reconciliation: CIS-owned invariant or out-of-system report? — F5 productive-question, parallel to INV-087 → Q-4). Family 12 added to Appendix B (two proposed Method-1 docs: audit-trail-and-subpoena-readiness.md + customer-communication-and-notice-discipline.md). Remaining: ~43 candidates pending in subsequent batches.
**Batch 11 complete:** 13 candidates → 12 canonical entries (CI-100 through CI-111 — Family 13 rate-and-rider-DAG / mid-period / billing-pipeline correctness, the per-bill calculation backbone) plus 1 F6 merge (INV-047 + INV-104 → CI-106 mid-period segment-independent full charge stack). INV-045/046/048/052 routed to Batch 12 (read-exception/estimation; INV-095 from Batch 10 composes with INV-048 there); INV-051/053 routed to Batch 14 (MIMO/work-order); INV-108 routed to Batch 15 cleanup. One new Appendix A entry (A-19 rate-schedule reclassification history + workflow substrate). No new Flagged Q — every framing note (INV-010/011/044/049/050/107) is F2-resolvable (discipline vs. value), not a domain-expert blocker, consistent with Batches 3–4. Family 13 added to Appendix B (two proposed Method-1 docs: billing-pipeline-and-charge-composition.md + mid-period-and-temporal-rate-selection.md). Remaining: ~30 candidates pending in subsequent batches.
**Batch 12 complete:** 5 candidates → 4 canonical entries (CI-112 through CI-115 — Family 14 read exception handling and estimation discipline) plus 1 F6 merge (INV-048 + INV-095 → CI-115; INV-095 routed from Batch 10 as planned, its review-note framing is the F6/F2 resolution). One new Appendix A entry (A-20 read/bill exception-queue + validation-state substrate, covering CI-112/CI-113/CI-115). One new Flagged Q-10 (recon Q3 — consecutive-estimate counter shape; explicitly disambiguated from canonical Q-3 WNA deadband per the Session 1 label collision). Family 14 added to Appendix B (one proposed Method-1 doc: read-exception-handling-and-estimation.md). Remaining: ~25 candidates pending in subsequent batches.
**Batch 13 complete:** 4 candidates → 4 canonical entries (CI-116 through CI-119 — Family 15 tenant isolation and structural integrity) with no F6 merges. Highest `structurally-enforced` density of any family: CI-117/CI-118/CI-119 fully structural, CI-116 partial (write-side structural; read-side pending Q-11). No new Appendix A entries (substrate exists — these entries document existing structural enforcement, the inverse of gaps). One new Flagged Q-11 (tenant read-isolation enforcement — Postgres RLS vs. application query-predicate; determines CI-116's enforcement classification). Family 15 added to Appendix B (one proposed Method-1 doc: tenant-isolation-and-structural-integrity.md). Remaining: ~21 candidates pending in subsequent batches.
**Batch 14 complete:** 12 candidates → 12 canonical entries (CI-120 through CI-131 — Family 16 account lifecycle, MIMO, deposits, and operational integrity) with no F6 merges (the three Texas deposit rules INV-156/157/158 kept separate per F1 / Batch-9 precedent; INV-053 kept distinct from CI-024 — calculation vs. data-pipeline-freshness). INV-120 routed in from Batch 7's deferral. One new Appendix A entry (A-21 account-lifecycle state-events + date-effective account attributes + deposit/interest ledger; covers CI-121/CI-125/CI-129–131). No new Flagged Q (INV-042/051 framing notes F2-resolvable, consistent with Batches 3/4/11). Family 16 added to Appendix B (two proposed Method-1 docs: account-lifecycle-mimo-and-final-bill.md + deposits-credits-and-operational-integrity.md). Remaining: ~9 candidates pending in Batch 15 cleanup.
**Batch 15 complete (cleanup batch):** 7 cleanup candidates → 4 canonical entries (CI-132–CI-135 — Family 17 cross-cutting residuals, topic-heterogeneous like Family 11) that survived the F5 inclusion gate (INV-004 regulatory posture, INV-081 transport eligibility, INV-108 batch mass-error gate, INV-117 print-mail integrity) + 3 deferred under new Flagged Q-12 (INV-080 transport balancing, INV-092 tenant submetering, INV-122 combined multi-commodity — all launch-scope-uncertain, deferred not excluded since each is a real discipline). The two long-standing deferrals INV-087 (Q-4 CIAC) and INV-096 (Q-9 vendor-rate-lag) confirmed still deferred — domain-expert review is out of Session 2 scope and no expert annotation landed, so no resolution was fabricated. No new Appendix A entries (all four entries compose existing substrate). One new Flagged Q-12 (3-part launch-scope question). Family 17 added to Appendix B (no dedicated Method-1 doc — entries fold into their topic-family docs).

**Session 2 complete.** All 15 reconciliation batches done: 162 Session-1 candidates → **135 canonical entries (CI-001–CI-135) across 17 families**. Disposition of every candidate is recorded in this map: merged-to-CI-NNN (the large majority, including F6 dedup merges and F2 configurable-boundary folds), or deferred-pending-question with an explicit Q-reference (INV-087/Q-4, INV-096/Q-9, INV-080/INV-092/INV-122 under Q-12(a/b/c)). **No row remains "pending."** Appendix A holds 21 schema-enforcement gaps (A-1–A-21); the canonical doc's Flagged section holds 12 framing questions (Q-1–Q-12). Next gating step per [[../execution-kickoff]]: domain-expert review of the Flagged questions and confidence scores, then Method 1 narrative-doc derivation per the canonical doc's Appendix B family grouping. Wiki registration (CHANGELOG.md / INDEX.md / global INDEX.md) is the immediate follow-up per the prior session decision to register after Session 2 completes.

---

## Candidates

---

### From 01-industry-and-regulatory.md

#### INV-001 — Disconnect-eligibility-respects-jurisdictional-rules

- **Statement:** No disconnection may proceed unless the eligibility evaluation against the customer's jurisdiction-specific rule set (moratorium windows, temperature holds, arrears thresholds, notice cadence, medical certification, third-party notification, protected-class flags) returns "eligible."
- **Category:** computational (with structural enforcement boundary — the engine is one place all paths funnel through)
- **Confidence:** high
- **Source:** 01-industry-and-regulatory.md "Platform Requirements"; 09-credit-collections-disconnects.md
- **Scope:** dunning_events, work_orders (disconnect type), per-jurisdiction rule config tables, customer protected-status flags, weather feeds
- **Rationale:** State PUC consumer protection orders bind utility behavior. Unauthorized disconnects produce consumer complaints, statutory fines, and reconnection at LDC expense. Subpoena evidence depends on full reproducible eligibility decision.
- **Known failure modes if violated:** wrongful disconnect during moratorium; disconnect of medical-certified customer; disconnect on temperature-forecast day; collections complaint upheld by state PUC
- **Related invariants:** [[INV-audit-trail-completeness]], [[INV-protected-status-honored]]

#### INV-002 — Audit-trail-subpoena-readiness

- **Statement:** Every regulated decision (rate applied, disconnect attempted, dispute resolved, refund issued, deposit assessed, payment program enrollment, communication sent) is reproducible from persisted records at any future point in time, with original inputs, decision logic version, and acting persona/system identity.
- **Category:** structural
- **Confidence:** high
- **Source:** 01-industry-and-regulatory.md "audit trail (regulators subpoena the full history)"; project guiding principles in CONTEXT.md ("audit trail must be subpoena-ready")
- **Scope:** all financial, operational, and customer-touching tables; ai_audit_log, communication log (gap), invoice snapshots
- **Rationale:** Regulatory subpoenas can demand reconstruction of any historical billing, disconnect, or complaint decision. Inability to reproduce = adverse inference in proceedings.
- **Known failure modes if violated:** PUC complaint upheld because LDC can't show notice was sent; rate-case challenge succeeds because tariff version applied can't be proven; bankruptcy court rejects pre-petition arrears claim
- **Related invariants:** [[INV-bi-temporality]], [[INV-bill-immutability]], [[INV-append-only-ledger]], [[INV-communication-log-completeness]]

#### INV-003 — Franchise-fee-traceable-to-jurisdiction

- **Statement:** Every franchise-fee assessment on a bill traces to the customer's tax-jurisdiction assignment in effect for the billing period, and aggregates to a remittance total per franchising municipality matching the sum of customer-level assessments.
- **Category:** computational
- **Confidence:** high
- **Source:** 01-industry-and-regulatory.md "Franchise agreements"; 11-taxes-and-gl-accounting.md (to be read)
- **Scope:** tax_jurisdictions table (gap), service_locations, invoice_line_items, franchise-fee rider config, remittance ledger
- **Rationale:** Cities audit franchise-fee remittances. Mis-assignment or rate-version drift produces under-remittance liability and over-billing exposure to customers.
- **Known failure modes if violated:** city audit finds franchise underpayment; customer outside city limits charged city franchise fee; rate-version drift causes silent under-charge
- **Related invariants:** [[INV-premise-zone-assignment-complete]], [[INV-tax-jurisdiction-date-effective]]

#### INV-004 — Regulatory-posture-configurable-per-tenant

- **Statement:** Each tenant's regulatory posture (PUC-jurisdictional / municipal-board / cooperative / IOU subset) governs which workflows require formal filings versus board resolution; the platform must not assume one posture.
- **Category:** structural
- **Confidence:** medium
- **Source:** 01-industry-and-regulatory.md "configurable regulatory posture"
- **Scope:** tenant config, rate-change workflows, PGA filing workflows
- **Rationale:** Target market spans IOUs, municipal gas systems, and cooperatives with different governance and reporting requirements.
- **Related invariants:** [[INV-tenant-isolation]]
- **Review note:** Likely a configuration knob, not an invariant. Included because the *invariant* may be "tenant regulatory posture is a first-class attribute referenced by workflow gates," which is structural. Worth flagging for expert framing review.

---

### From 02-tariffs-rates-riders.md

#### INV-005 — Rate-and-rider-date-effective-and-versioned

- **Statement:** Every rate schedule, rate item, rider, tariff rule, and exclusion is stored with an effective date range; mutations create new versions, never edit in place. "Current value only" representation is not permitted.
- **Category:** structural
- **Confidence:** high
- **Source:** 02-tariffs-rates-riders.md "Rider Engine Requirements: Effective date range (date-effective, versioned, immutable)"; CONTEXT.md guiding principles
- **Scope:** rate_schedules, rate_items, rate_schedule_items, riders (existing or gap), all factor tables
- **Rationale:** Cancel-rebill correctness requires reading the world as it was at the bill date. PUC challenges examine which tariff version applied. Audit reproducibility.
- **Known failure modes if violated:** retroactive rate change silently corrupts prior bills; cancel-rebill produces wrong total because today's rate used instead of original-period rate
- **Related invariants:** [[INV-bi-temporality]], [[INV-cancel-rebill-uses-original-period-world]]

#### INV-006 — PGA-pass-through-no-markup

- **Statement:** The PGA / GCR / commodity component of a bill is computed from the approved PGA factor for the billing period without addition of LDC margin; aggregate PGA revenue collected reconciles dollar-for-dollar (within deferred-account mechanics) against gas acquisition cost.
- **Category:** computational
- **Confidence:** high
- **Source:** 02-tariffs-rates-riders.md "PGA / GCR / GCA / CGA / WACOG — gas commodity cost"; 03-pga-gas-cost-recovery.md "dollar-for-dollar pass-through. No markup."
- **Scope:** rate_items for PGA, invoice_line_items, deferred_gas_cost ledger (gap), gas_purchases (gap)
- **Rationale:** PUC orders forbid markup on PGA. Excess collection is refunded via deferred account amortization. Violation is regulatory finding plus customer refund liability.
- **Known failure modes if violated:** PGA rate set wrong, over-recovery not refunded, regulatory finding
- **Related invariants:** [[INV-pga-deferred-account-accrual]], [[INV-uaf-cap-shareholder-expense]]

#### INV-007 — UAF-cap-shareholder-expense

- **Statement:** Lost & Unaccounted-For gas exceeding the regulated cap (e.g., 8% large / 10% small per WV; varies by state) is excluded from PGA recovery and absorbed as a shareholder expense.
- **Category:** computational
- **Confidence:** medium
- **Source:** 02-tariffs-rates-riders.md "Lost & Unaccounted For (UAF) — capped by regulation … over-cap is shareholder expense"; 03-pga-gas-cost-recovery.md three-part prudency test
- **Scope:** PGA reconciliation calc, deferred_gas_cost ledger
- **Rationale:** Statutory; protects ratepayers from imprudent gas loss.
- **Related invariants:** [[INV-pga-pass-through-no-markup]]
- **Review note:** Threshold value is jurisdiction-specific; framing as invariant is "the cap exists and is enforced," with the cap value being a config knob. Confidence is medium because the *system* invariant is the enforcement, not the specific cap value.

#### INV-008 — Rider-ordering-dependency-respected

- **Statement:** Riders compose with a deterministic ordering: each rider's calculation base (pre-tax total, distribution subtotal, specific other rider output) is explicit, and riders that depend on other riders' output evaluate after their dependencies. Bill calculation must traverse the dependency DAG, not iterate in arbitrary order.
- **Category:** computational (with structural mechanism — order is encoded in rule metadata)
- **Confidence:** high
- **Source:** 02-tariffs-rates-riders.md "Ordering dependencies — some riders operate on pre-tax totals, some are themselves taxable. Need a DAG."
- **Scope:** rate_items, rate_schedule_items, rider metadata, billing calculation engine
- **Rationale:** Wrong order produces wrong totals (taxing a tax, or omitting a base from a percentage). Bills are immutable, so wrong-order errors propagate until detected and cancel-rebilled.
- **Known failure modes if violated:** see billing-failures stage 04 (rate-application)
- **Related invariants:** [[INV-bill-calculation-determinism]]

#### INV-009 — Customer-charge-billed-at-zero-usage

- **Statement:** The customer/basic/facilities charge for an active service agreement is billed for the period regardless of consumption (including zero usage), prorated only per the schedule's proration rule for partial periods.
- **Category:** computational
- **Confidence:** high
- **Source:** 02-tariffs-rates-riders.md "Customer Charge … Billed at zero usage"
- **Scope:** billing calculation, invoice_line_items
- **Rationale:** Tariff language; covers fixed costs (meter, service line, billing) independent of usage.
- **Related invariants:** [[INV-minimum-bill-floor]], [[INV-proration-rules-honored]]

#### INV-010 — Minimum-bill-floor-applied

- **Statement:** When a rate schedule specifies a minimum-bill provision, the bill total cannot fall below that floor regardless of usage (after all other charges are computed).
- **Category:** computational
- **Confidence:** medium
- **Source:** 02-tariffs-rates-riders.md "Minimum Bill Provision — floor on total bill regardless of usage"
- **Scope:** billing calculation
- **Rationale:** Tariff-required for some schedules.
- **Review note:** Some schedules have minimum bills, others have customer charges that act similarly. Need to confirm whether minimum bill is universal-when-specified or only triggers on specific schedules. Framing is the question.

#### INV-011 — Rate-class-reclassification-workflow-controlled

- **Statement:** Migration of a customer/account between rate schedules (auto-driven by applicability criteria or operator-proposed) requires a workflow event with effective date, approval if configured, and customer notification per tariff rule; the migration cannot silently mutate prior bills.
- **Category:** structural (workflow) + computational (eligibility rule)
- **Confidence:** medium
- **Source:** 02-tariffs-rates-riders.md "platform must support automatic and proposed-by-operator reclassification with an approval/notification workflow"
- **Scope:** account.rate_schedule_id, reclassification events, account history
- **Rationale:** Customer can dispute reclassification; tariff requires notice; PUC reviews.
- **Review note:** Whether the *workflow* is the invariant or whether the invariant is "rate-schedule assignment is date-effective and notification-bound" — framing question.

#### INV-012 — LIHEAP-and-protected-class-exclusions-applied

- **Statement:** Customers in protected programs (LIHEAP, PIPP, medical certification, third-party notification enrollees) have program-defined exclusions (e.g., LIHEAP excluded from WNA, late-fee waivers, certain collection actions) applied consistently across billing and collections.
- **Category:** computational
- **Confidence:** medium
- **Source:** 02-tariffs-rates-riders.md "Exclusions — e.g., LIHEAP customers excluded from WNA and from some franchise fees"; 08-payments-and-programs.md
- **Scope:** payment program enrollment (gap), billing rider eligibility, collections engine
- **Rationale:** Statutory protection; misapplied exclusions cause regulatory complaints and customer harm.
- **Related invariants:** [[INV-disconnect-eligibility-respects-jurisdictional-rules]]
- **Review note:** The exclusion set per program is jurisdiction- and program-specific; invariant is "enrollment is honored across all subsystems," value of specific exclusions is configuration.

---

### From 03-pga-gas-cost-recovery.md

#### INV-013 — PGA-historical-rate-retrievable-by-effective-period

- **Statement:** For any historical billing period, the PGA factor in effect (and the underlying components — base commodity, pipeline demand, FL&U, storage, hedging policy) is retrievable for cancel-rebill or regulatory reconstruction.
- **Category:** structural
- **Confidence:** high
- **Source:** 03-pga-gas-cost-recovery.md "Every historical PGA rate must be retrievable for cancel-rebill scenarios — a bill rendered in January 2024 must rebill with the January 2024 PGA rate"
- **Scope:** PGA rate history (likely on rate_items with effective dates), invoice snapshot (PGA factor used)
- **Rationale:** Cancel-rebill correctness; PUC reconstruction.
- **Related invariants:** [[INV-rate-and-rider-date-effective-and-versioned]], [[INV-invoice-snapshot-completeness]], [[INV-cancel-rebill-uses-original-period-world]]

#### INV-014 — PGA-mid-period-proration

- **Statement:** When a billing period spans a PGA rate-change date, the energy/volume billed within the period is prorated across PGA factors: pre-change usage × days × old factor + post-change usage × days × new factor.
- **Category:** computational
- **Confidence:** high
- **Source:** 03-pga-gas-cost-recovery.md "Mid-period proration"
- **Scope:** billing calculation, invoice_line_items
- **Rationale:** Tariff language; under-/over-collection if not prorated.
- **Known failure modes if violated:** billing-failures stage 04 may have specific entries
- **Related invariants:** [[INV-rate-and-rider-date-effective-and-versioned]]
- **Review note:** Proration method (calendar days vs. degree-day weighted vs. estimated split) may vary by tariff. Confidence high on "must prorate"; framing of method may be configurable.

#### INV-015 — Transportation-customers-not-billed-PGA

- **Statement:** Customers on transportation rate schedules procure their own gas and are not assessed the PGA / commodity charge; they pay only distribution + transportation-specific riders.
- **Category:** computational
- **Confidence:** high
- **Source:** 03-pga-gas-cost-recovery.md "Transportation Customer Treatment"; 10-transportation-choice-edi.md (to be read)
- **Scope:** rate schedule applicability, billing engine, invoice_line_items
- **Rationale:** Tariff-required; double-charge to transport customer is regulatory violation.
- **Related invariants:** [[INV-customer-class-determines-applicable-tariff]]

#### INV-016 — PGA-deferred-account-accrual-with-carrying-cost

- **Statement:** The deferred gas cost account accrues the running over/under-collection between actual gas cost × throughput and recovered revenue × throughput; carrying costs accrue on the deferred balance at the commission-prescribed rate; reconciliation amortizes the balance over the next period per state rule.
- **Category:** computational
- **Confidence:** high
- **Source:** 03-pga-gas-cost-recovery.md "True-Up Mechanics"; 31-texas-regulatory-compliance.md (to read)
- **Scope:** deferred_gas_cost ledger (likely gap), gl_postings, PGA reconciliation workflow
- **Rationale:** Statutory PGA mechanic; mishandling = under/over recovery and ratepayer harm.
- **Related invariants:** [[INV-pga-pass-through-no-markup]]

#### INV-017 — PGA-pre-load-with-future-effective-date

- **Statement:** Newly approved PGA factors are loaded with a future effective date; bills generated for periods before that date must continue to use the prior factor. The system cannot allow a "current PGA" mutation that retroactively changes prior bill periods.
- **Category:** structural
- **Confidence:** high
- **Source:** 03-pga-gas-cost-recovery.md "System pre-loads new PGA factor with future effective date"
- **Scope:** rate_items pre-load, billing engine date-resolution
- **Rationale:** Cancel-rebill correctness; current-value mutation = silent corruption of prior bills.
- **Related invariants:** [[INV-rate-and-rider-date-effective-and-versioned]], [[INV-pga-historical-rate-retrievable-by-effective-period]]

#### INV-018 — Annual-GCR-reconciliation-applied-to-affected-class

- **Statement:** The annual Gas Cost Reconciliation factor (calculated per rate class against actual gas cost vs. recovered) is applied as a credit or surcharge for the prescribed period to customers in that class.
- **Category:** computational
- **Confidence:** medium
- **Source:** 03-pga-gas-cost-recovery.md "Calculate GCR factor per rate class … Apply GCR credit or surcharge"
- **Scope:** rate_items (GCR rider), billing engine, customer-class scoping
- **Rationale:** Reconciliation is class-scoped because each class contributed to over/under-collection differently.
- **Review note:** Whether reconciliation is per-class or per-tenant-aggregate may vary by jurisdiction.

---

### From 04-zones-and-metering.md

#### INV-019 — Premise-zone-assignment-complete

- **Statement:** Every premise/service location has assignments for: BTU zone, rate zone, pressure zone (if commercial/industrial), tax jurisdictions (city/county/school district/MUD). Billing cannot proceed without complete zone assignment.
- **Category:** structural
- **Confidence:** high
- **Source:** 04-zones-and-metering.md "Data Model Implications: Premise / service point links to: BTU zone, rate zone, pressure zone, tax jurisdictions"
- **Scope:** service_locations (gap: zone foreign keys missing per CONTEXT.md), BTU zones, rate zones, pressure zones, tax_jurisdictions (gap)
- **Rationale:** Without zone assignment the volume-to-energy and tax/franchise computations cannot be correct.
- **Known failure modes if violated:** wrong BTU factor applied; franchise fee assessed wrong city; gas billed as electric volume
- **Related invariants:** [[INV-volume-to-energy-formula-correct]], [[INV-franchise-fee-traceable-to-jurisdiction]]

#### INV-020 — Volume-to-energy-formula-correctly-composed

- **Statement:** Billed energy is computed as: raw_volume × meter_multiplier × pressure_factor (Fp) × temperature_factor (Ft) × supercompressibility (Fpv, for high-pressure industrial) × btu_factor, with each factor sourced from the date-effective value for the meter's zones and period.
- **Category:** computational
- **Confidence:** high
- **Source:** 04-zones-and-metering.md "Volume-to-Energy Conversion"
- **Scope:** consumption calculation, billing engine, factor tables
- **Rationale:** Core gas-billing correctness; wrong formula → wrong therms → wrong bill.
- **Known failure modes if violated:** billing-failures stage 03 (consumption calculation)
- **Related invariants:** [[INV-meter-attributes-complete]], [[INV-zone-factor-date-effective]]

#### INV-021 — Meter-rollover-arithmetic-correct

- **Statement:** When current read < previous read on the same meter (no meter swap), the consumption calculation treats this as a rollover at the meter's rollover point — not as negative consumption. New-meter "roll-under" (replacement starting at lower index than previous meter's final) does not apply rollover math.
- **Category:** computational
- **Confidence:** high
- **Source:** 04-zones-and-metering.md "Handle skipped reads, rollovers, and roll-under"; 13-gotchas-and-lessons.md (to be read)
- **Scope:** consumption calculation, meter_readings, meters
- **Rationale:** Negative consumption = customer credit erroneously; rollover-mis-handling = massively overbilled.
- **Known failure modes if violated:** billing-failures stage 03
- **Related invariants:** [[INV-meter-attributes-complete]] (rollover point on meter)

#### INV-022 — Meter-attributes-complete-for-billing

- **Statement:** Every active billing meter has populated values for: type, capacity, register multiplier (billing constant), pressure class, temperature-compensation flag, rollover point, dial configuration. Billing cannot proceed against an incomplete meter master record.
- **Category:** structural
- **Confidence:** high
- **Source:** 04-zones-and-metering.md "Meter master needs"
- **Scope:** meters table (gap: rollover point and temp-comp flag missing per CONTEXT.md)
- **Rationale:** Each attribute is an input to the consumption formula; missing = silent wrong bill.
- **Related invariants:** [[INV-volume-to-energy-formula-correctly-composed]]

#### INV-023 — Meter-swap-split-calculation-within-period

- **Statement:** When a meter is replaced mid-billing-period, consumption is computed as two segments: pre-swap (using old meter's attributes and final read) and post-swap (using new meter's attributes and starting read). Each segment uses its own multiplier/factors; the period total is the sum.
- **Category:** computational
- **Confidence:** high
- **Source:** 04-zones-and-metering.md (implied) + 13-gotchas-and-lessons.md "meter swap-out rollover math gotchas" (to be read)
- **Scope:** consumption calculation, meter swap events
- **Rationale:** Single-meter math against two physical devices = wrong consumption.
- **Known failure modes if violated:** billing-failures stage 03
- **Related invariants:** [[INV-meter-rollover-arithmetic-correct]]

#### INV-024 — Read-type-discipline

- **Statement:** Each meter read is recorded with its read type (actual, estimated, customer-read, test-read, final-read, check-read); downstream logic (estimation cap, dispute handling, true-up) keys on type. The type cannot be mutated post-acceptance; corrections create new reads.
- **Category:** structural
- **Confidence:** medium
- **Source:** 04-zones-and-metering.md "Handle read types"; 13-gotchas-and-lessons.md
- **Scope:** meter_readings
- **Rationale:** Estimation policy and consumer-protection rules (consecutive estimation caps) depend on type accuracy.
- **Review note:** Whether type is immutable post-acceptance or correctable via supersede-with-audit is a framing question.

#### INV-025 — BTU-and-zone-factors-date-effective

- **Statement:** BTU factor, pressure factor (where zone-scoped), and any combined "billing factor" are stored as date-effective values per zone and period (typically monthly); reading any historical bill requires retrieving the factor in effect for that period.
- **Category:** structural
- **Confidence:** high
- **Source:** 04-zones-and-metering.md "Factor tables are date-effective and versioned per zone."
- **Scope:** btu_zone_factors (likely gap), pressure_zone_factors (likely gap)
- **Rationale:** Cancel-rebill correctness; PUC reconstruction.
- **Related invariants:** [[INV-rate-and-rider-date-effective-and-versioned]], [[INV-cancel-rebill-uses-original-period-world]]

#### INV-026 — Cancel-rebill-uses-original-period-world

- **Statement:** A cancel-rebill operation re-computes the corrected bill using the rates, riders, factors, tax rates, BTU zones, premise assignments, and customer-class assignments that were in effect during the *original* billing period (valid time), not their current values. This applies even when the original-period values were since corrected — the rebill replays the world the bill came from.
- **Category:** structural + computational
- **Confidence:** high
- **Source:** 04-zones-and-metering.md "Cancel-rebill must use the factors in effect during the original bill period, not today's"; CONTEXT.md guiding principles; 16-bi-temporality.md
- **Scope:** cancel-rebill workflow, all date-effective reference data, invoice snapshots
- **Rationale:** Regulatory reconstruction; otherwise the rebill is a "today's prices applied to yesterday's usage" artifact, which fails subpoena and customer-protection challenges.
- **Known failure modes if violated:** rebilled customer charged today's PGA on a 2-year-old correction
- **Related invariants:** [[INV-bi-temporality]], [[INV-pga-historical-rate-retrievable-by-effective-period]], [[INV-bill-immutability]]

---

### From 05-weather-normalization.md

#### INV-027 — WNA-scope-distribution-only

- **Statement:** WNA adjustments apply only to the distribution-charge component of the bill, never to the commodity/PGA portion. Therms used for the WNA computation are the customer's billed therms; the adjustment's monetary base is the distribution rate.
- **Category:** computational
- **Confidence:** high
- **Source:** 05-weather-normalization.md "Applicability: Applies only to the distribution charge, not the commodity (PGA) portion."
- **Scope:** WNA rider calculation, rate_items WNA
- **Rationale:** WNA's purpose is LDC distribution-revenue stabilization; PGA is a pass-through with no margin to normalize.
- **Related invariants:** [[INV-pga-pass-through-no-markup]], [[INV-rider-ordering-dependency-respected]]

#### INV-028 — WNA-seasonal-window-honored

- **Statement:** WNA is computed only for bills with consumption periods inside the configured heating season (typically Oct/Nov 1 – Apr/May 31), unless the tariff uses annual-true-up form. Period split required when a bill straddles the season boundary.
- **Category:** computational
- **Confidence:** high
- **Source:** 05-weather-normalization.md "Season: typically Oct/Nov 1 – Apr/May 31"
- **Scope:** WNA calculation, billing engine date-resolution
- **Rationale:** WNA outside heating season is not authorized in tariff.
- **Review note:** Whether the season is tariff-configurable per tenant (yes) — invariant is "WNA respects its tariff-defined season window," with the specific dates configurable.

#### INV-029 — WNA-deadband-applied

- **Statement:** WNA does not adjust the bill when the difference between actual and normal HDDs falls within the tariff-defined deadband (typically 2.2–3%). Inside the deadband, weather is treated as "normal" and no adjustment posts.
- **Category:** computational
- **Confidence:** high
- **Source:** 05-weather-normalization.md "Deadband: 2.2%–3%. WNA applies only when actual HDDs deviate from normal by more than the deadband."
- **Scope:** WNA calculation
- **Rationale:** Tariff-required; avoids small-perturbation adjustments.

#### INV-030 — WNA-inputs-snapshotted-on-bill

- **Statement:** Every bill that applies a WNA adjustment stores a snapshot of the WNA inputs used: normal HDDs, actual HDDs, deadband, base load, distribution rate, weather station, formula version. Cancel-rebill must reproduce the WNA using the snapshotted inputs.
- **Category:** structural
- **Confidence:** high
- **Source:** 05-weather-normalization.md "Snapshot the inputs … on the bill record for cancel-rebill reproducibility"; "Store the NHDDs used for each bill snapshot"
- **Scope:** invoices / invoice_snapshots, WNA calculation
- **Rationale:** Cancel-rebill correctness; NHDDs are recomputed periodically and may differ from the original-period value at rebill time.
- **Known failure modes if violated:** rebill produces different WNA than original bill because today's NHDDs used
- **Related invariants:** [[INV-cancel-rebill-uses-original-period-world]], [[INV-invoice-snapshot-completeness]]

#### INV-031 — WNA-customer-program-exclusions

- **Statement:** Customers enrolled in LIHEAP / CAP / other program exclusions defined by tariff or program rule are not assessed (and not credited) the WNA adjustment.
- **Category:** computational
- **Confidence:** medium
- **Source:** 05-weather-normalization.md "Typically excludes LIHEAP / Customer Assistance Program (CAP) participants"
- **Scope:** WNA calculation, program enrollment
- **Rationale:** Program design; LIHEAP customers are insulated from rate-recovery volatility separately.
- **Review note:** "Typically" — set of excluded programs is tariff/jurisdiction-specific. Invariant is "exclusions honored as configured," specifics configurable.

#### INV-032 — Weather-station-per-premise

- **Statement:** Every premise that participates in WNA has an assigned NOAA weather station (or equivalent observed source). The assignment is date-effective; if a station decommissions, a new assignment with effective date supersedes (the old does not silently disappear).
- **Category:** structural
- **Confidence:** medium
- **Source:** 05-weather-normalization.md "Weather station: per-customer mapping … may need to update when stations decommission"
- **Scope:** service_locations, weather-station assignment table (gap)
- **Rationale:** Without station mapping, WNA cannot compute; silent station change breaks historical reproducibility.
- **Review note:** "Date-effective" is implied by the more general date-effectivity invariant. Worth keeping as its own framing because the station-decommission case is concrete.

---

### From 06-data-model.md

#### INV-033 — Bill-immutability

- **Statement:** Once issued, a bill record (header, line items, applied rates, snapshot fields) is not edited in place. Corrections are produced as cancel + rebill (with parent reference) or as new adjustment transactions; the original record remains unchanged in storage.
- **Category:** structural
- **Confidence:** high
- **Source:** 06-data-model.md "Bills are immutable"; CONTEXT.md guiding principles
- **Scope:** invoices, invoice_line_items, invoice_events
- **Rationale:** Subpoena reproducibility; cancel-rebill audit chain.
- **Known failure modes if violated:** silent retro-amendment, audit fail, customer dispute hard to investigate
- **Related invariants:** [[INV-append-only-ledger]], [[INV-cancel-rebill-uses-original-period-world]], [[INV-audit-trail-subpoena-readiness]]

#### INV-034 — Date-effectivity-everywhere

- **Statement:** Every rate, rider, tax, factor, zone assignment, customer attribute, meter parameter, and tariff-referenced configuration value is stored with effective-from / effective-to dates. No "current value only" attribute exists for any value that has historical billing relevance.
- **Category:** structural
- **Confidence:** high
- **Source:** 06-data-model.md "Date Effectivity Everywhere — Do not build 'current value only' anywhere"; CONTEXT.md
- **Scope:** all reference tables; customer attribute tables; meter master; zone assignment tables
- **Rationale:** Cancel-rebill correctness; PUC reconstruction. "Current value only" silently corrupts historical bills.
- **Related invariants:** [[INV-bi-temporality]], [[INV-rate-and-rider-date-effective-and-versioned]]

#### INV-035 — Bi-temporality

- **Statement:** Reference data subject to historical reconstruction is stored on two time axes: **valid time** (when the fact is true in the world) and **transaction time** (when the system recorded the fact). Queries support point-in-time retrieval on either axis independently.
- **Category:** structural
- **Confidence:** high
- **Source:** 06-data-model.md "Bi-Temporality"; 16-bi-temporality.md (to be read); bi-temporal-decision.md (architecture locked)
- **Scope:** rates, riders, factors, zone assignments, customer-class assignments, tax rates, franchise-fee rules
- **Rationale:** Architecture-foundational; cancel-rebill correctness and forensic reproducibility depend on it.
- **Known failure modes if violated:** rebill produces wrong values; PUC challenge to a historical bill cannot be defended
- **Related invariants:** [[INV-date-effectivity-everywhere]], [[INV-cancel-rebill-uses-original-period-world]], [[INV-invoice-snapshot-completeness]]

#### INV-036 — Append-only-ledger

- **Statement:** The financial transaction ledger admits inserts only; no in-place updates and no deletes. A reversal is a new transaction (signed opposite) that references the prior transaction; original posting remains.
- **Category:** structural
- **Confidence:** high
- **Source:** 06-data-model.md "Transactions Are Append-Only"; CONTEXT.md
- **Scope:** account_ledger, invoice_applications, payments
- **Rationale:** Audit and regulatory; allows reconstruction of any historical account state.
- **Known failure modes if violated:** missing payment reversal, account balance unauditable
- **Related invariants:** [[INV-no-hard-deletes-of-financial-records]], [[INV-bill-immutability]], [[INV-audit-trail-subpoena-readiness]]

#### INV-037 — No-hard-deletes-of-operational-records

- **Statement:** No financial or operational record is hard-deleted from the database. Removal happens via soft-delete with marker and reason; the original row remains queryable.
- **Category:** structural
- **Confidence:** high
- **Source:** CONTEXT.md guiding principles "No hard deletes on any financial or operational record — soft delete with marker and reason only"
- **Scope:** customers, accounts, service_locations, service_agreements, meters, meter_readings, invoices, payments, account_ledger, work_orders, all operational entities
- **Rationale:** Audit and regulatory; deletion = unrecoverable history loss.
- **Related invariants:** [[INV-append-only-ledger]], [[INV-audit-trail-subpoena-readiness]]

#### INV-038 — Premise-immutable-occupancy-changes

- **Statement:** A premise/service-location entity exists independently of any active customer and persists across occupancy transitions. Closing an account (final read, final bill) does not close the premise; the premise awaits next occupancy with its zone/jurisdiction assignments intact.
- **Category:** structural
- **Confidence:** high
- **Source:** 06-data-model.md "Premise is immutable — it exists whether or not anyone is currently receiving service there"; "Closing a premise vs. closing an account"
- **Scope:** service_locations, accounts, service_agreements
- **Rationale:** Premise-bound rate zone, tax jurisdiction, weather station, and consumption history transfer across occupancies.

#### INV-039 — Invoice-snapshot-completeness

- **Statement:** Every issued invoice persists a snapshot of every input used in its computation: rates and rider values, PGA factor, BTU factor, pressure factor, temperature factor, multiplier, WNA inputs (NHDDs/AHDDs/deadband/baseload/rate), tax rates by jurisdiction, applicable charges array, premise zone assignments, customer class, calculation formula version. The bill is fully reproducible from its snapshot without point-in-time queries on reference data.
- **Category:** structural
- **Confidence:** high
- **Source:** 06-data-model.md "Audit Trail — Every calculated value on a bill should be reproducible years later from stored inputs"; HANDOFF.md "Bill Record Snapshot Question"
- **Scope:** invoices, invoice_snapshots / tax_breakdown JSONB (current partial implementation)
- **Rationale:** Bi-temporal reference store + snapshot strategy = forensic reproducibility belt-and-suspenders. Cancel-rebill correctness without bi-temporal-query dependency.
- **Known failure modes if violated:** rebill diverges from original because point-in-time query semantics drift or a reference row got soft-deleted
- **Related invariants:** [[INV-bi-temporality]], [[INV-cancel-rebill-uses-original-period-world]], [[INV-bill-immutability]]

#### INV-040 — Read-references-meter-and-service-point

- **Statement:** Every meter read records both the meter (FK) and the service point (FK) at the time of the read. The two associations together establish where the read applied; later meter moves cannot mask the original premise.
- **Category:** structural
- **Confidence:** medium
- **Source:** 06-data-model.md "Read: Meter (FK), service point (FK at time of read)"
- **Scope:** meter_readings
- **Rationale:** Audit; meters move between premises and reads must be unambiguously attributable.
- **Review note:** Schema may already enforce this via FKs — verify in schema pass.

#### INV-041 — Consumption-separable-from-reads

- **Statement:** Consumption is computed once and stored as its own entity (with FKs to start-read and end-read, factor snapshot, and billed/canceled/rebilled status). Rebills do not have to re-source reads; cancel-rebill creates a new consumption row with the same read references but recomputed factors-of-original-period.
- **Category:** structural
- **Confidence:** medium
- **Source:** 06-data-model.md "Consumption: Derived usage bracketed by two reads. Stored separately so rebills don't have to re-source reads."
- **Scope:** consumption (entity may be implicit in current schema — verify)
- **Rationale:** Decouples re-billing from re-fetching reads; preserves the chain.
- **Review note:** Whether "consumption" is its own row vs. an attribute of invoice_line_items is a schema question; framing matters.

#### INV-042 — Account-lifecycle-state-discipline

- **Statement:** Accounts traverse a defined lifecycle (pending → active → inactive → closed) with state-transition rules. State transitions are events with timestamps; mid-state values (deposit on file, autopay status, paperless preference) are date-effective.
- **Category:** structural
- **Confidence:** medium
- **Source:** 06-data-model.md "Account … Lifecycle: pending → active → inactive → closed"
- **Scope:** accounts, account state events
- **Rationale:** Operational correctness; billing/collections key on state.
- **Review note:** Whether the state machine is explicit (state column + transitions) or derived (computed from events) is a design choice.

#### INV-043 — Deposit-interest-accrual

- **Statement:** Customer deposits accrue interest from posting date at the regulator-prescribed rate; interest is credited at refund or on a periodic schedule per tariff/PUC rule. The accrual basis and rate are date-effective per jurisdiction.
- **Category:** computational
- **Confidence:** medium
- **Source:** 06-data-model.md "Deposit on file: amount, posted date, interest-accrual start, refund eligibility date"; 02-tariffs-rates-riders.md
- **Scope:** deposits, account_ledger (deposit-interest transactions)
- **Rationale:** Statutory; under-accrual = customer harm and PUC complaint.

---

### From 07-billing-calculation.md

#### INV-044 — Billing-pipeline-ordering

- **Statement:** The billing pipeline executes in a defined order: reads → estimation → consumption → rate determination → base/block/demand → riders (DAG order) → WNA → PGA → tax → adjustments → assembly → GL → exception queue → delivery. Earlier stages do not consume outputs of later stages; later stages cannot mutate earlier outputs.
- **Category:** structural
- **Confidence:** medium
- **Source:** 07-billing-calculation.md "Top-Level Pipeline"
- **Scope:** billing engine
- **Rationale:** Deterministic, reproducible billing; out-of-order execution = silent corruption.
- **Review note:** This is more of an architectural-pattern requirement than an enforceable invariant. Framing question: is the invariant "deterministic-billing-pipeline" (mechanism unspecified) or "exact ordering as listed"?

#### INV-045 — Consecutive-estimation-cap

- **Statement:** The system tracks consecutive estimated reads per meter/account and enforces the jurisdiction-configured cap (e.g., "no more than 2 in a row for residential" per Section 2.). On cap-exceeded, the next billing cycle requires actual-read attempt or field-order trigger; bill cannot be generated against an over-cap streak without explicit override.
- **Category:** computational
- **Confidence:** high
- **Source:** 07-billing-calculation.md "Some jurisdictions limit consecutive estimates"; 13-gotchas-and-lessons.md
- **Scope:** meter_readings, estimation engine, exception queue
- **Rationale:** Consumer protection (state-PUC); over-estimation harms customer.
- **Known failure modes if violated:** customer billed estimates indefinitely, large true-up surprise
- **Related invariants:** [[INV-read-type-discipline]]

#### INV-046 — Estimation-trueup-method-respected

- **Statement:** When an actual read arrives after one or more estimates, the true-up follows the jurisdiction's prescribed method: catch-up adjustment in current period, OR cancel-rebill of all intervening estimated bills. The choice is configured per jurisdiction; mixed application across customers is a violation.
- **Category:** computational
- **Confidence:** high
- **Source:** 07-billing-calculation.md "When an actual arrives after estimates: true-up is typically a single catch-up adjustment in the current period … Some states require true cancel-rebill. This varies by state — parameterize it."
- **Scope:** billing engine, cancel-rebill workflow
- **Rationale:** State PUC consumer-protection rules.
- **Review note:** The *method choice* is configurable; the *invariant* is "the chosen method is consistently applied." Framing matters.

#### INV-047 — Mid-period-tariff-change-split

- **Statement:** When a billing period spans a tariff version change (new rate effective mid-period), consumption is split pro-rata by days at the change date and each segment is billed under its applicable tariff version. Billing period remains the full range; the per-segment rate periods are recorded on the bill.
- **Category:** computational
- **Confidence:** high
- **Source:** 07-billing-calculation.md "Period Span Across Tariff Change"
- **Scope:** billing engine, invoice_line_items
- **Rationale:** Wrong tariff application = customer overcharge/undercharge.
- **Related invariants:** [[INV-pga-mid-period-proration]], [[INV-rate-and-rider-date-effective-and-versioned]]

#### INV-048 — Pre-mail-exception-routing

- **Statement:** Bills meeting any exception criterion (high-bill threshold, zero-bill on active account, negative-bill, consecutive-estimate streak, out-of-tolerance usage, rider true-up exceeding threshold, missing rebill approval) are routed to a pre-mail review queue and held until resolved or explicitly overridden with documented reason.
- **Category:** structural (workflow)
- **Confidence:** high
- **Source:** 07-billing-calculation.md "Exception Queue Routing (pre-mail review)"
- **Scope:** billing engine, exception queue, invoice status
- **Rationale:** Operational control; avoids high-impact customer-visible errors.
- **Known failure modes if violated:** billing-failures stage 06 (pre-mail review)

#### INV-049 — Tariff-dictated-rounding-applied-consistently

- **Statement:** Rounding (digit precision per line item, half-even vs half-up, per-line vs total-only) follows the tariff's prescription and is applied identically across every bill for that tariff version. Mixed-rounding across the customer population for the same tariff is a violation.
- **Category:** computational
- **Confidence:** medium
- **Source:** 07-billing-calculation.md "Inconsistent rounding across millions of bills creates material revenue differences. Standardize per tariff and document."
- **Scope:** billing engine
- **Rationale:** Material revenue differences across millions of bills; PUC reviews.

#### INV-050 — Unbilled-revenue-accrual-reverses

- **Statement:** Unbilled-revenue accruals posted at period close (for GAAP/regulatory reporting) reverse in the next period as actual bills are rendered; the reversal entry is tied to the originating accrual entry. Both the accrual and the reversal are append-only.
- **Category:** computational + structural
- **Confidence:** medium
- **Source:** 07-billing-calculation.md "Unbilled Revenue Accrual … Posted as a reversing journal entry at month-end; reverses when actual bills are rendered"
- **Scope:** account_ledger, GL postings
- **Rationale:** Period-end financial reporting integrity.
- **Review note:** Reversal mechanism (manual JE vs auto-reversing JE) is an accounting-engine design choice; framing question.

#### INV-051 — MIMO-events-produce-billing-events

- **Statement:** Every move-in and move-out completion generates a billing-relevant event: move-in produces a new active service agreement and initial-read capture; move-out produces a final-read capture, prorated final bill, and deposit disposition. Service activation cannot occur without a corresponding billable service agreement record.
- **Category:** structural (workflow)
- **Confidence:** medium
- **Source:** 07-billing-calculation.md "Move-In / Move-Out (MIMO) Workflow"
- **Scope:** service_agreements, meter_readings, work_orders, invoices
- **Rationale:** Avoids unbilled service or unrefunded deposit gaps.
- **Review note:** Whether this is an invariant or a workflow design is a framing question.

#### INV-052 — Read-exception-resolution-precedes-billing

- **Statement:** Reads failing validation rules (high/low threshold vs history, reverse read, max-dial rollover, consecutive-estimate over cap, zero-read on active account, reading-date gap out of bounds) cannot produce a bill until the exception is resolved (estimate accepted, manual read entered, field order dispatched) with reason code recorded.
- **Category:** structural (workflow) + computational (validation rules)
- **Confidence:** high
- **Source:** 07-billing-calculation.md "Read Exception Queue Workflow"
- **Scope:** meter_readings, exception queue, billing engine
- **Rationale:** Prevents propagation of bad reads into invoices.
- **Related invariants:** [[INV-consecutive-estimation-cap]], [[INV-pre-mail-exception-routing]]

#### INV-053 — Meter-change-out-event-real-time-to-billing

- **Statement:** A meter change-out (old meter retired, new meter activated at service point with old-final-read and new-initial-read captured) propagates to the billing engine such that the next bill for the affected service point splits consumption correctly across the swap date. A swap unknown to billing at bill-generation time is a violation.
- **Category:** structural (data pipeline)
- **Confidence:** high
- **Source:** 07-billing-calculation.md "Meter Change-Out Billing Workflow"; 13-gotchas-and-lessons.md "classic problem of 'tech swaps a meter on Monday, billing finds out Thursday'"
- **Scope:** meter_install (history), meter_readings, billing engine
- **Rationale:** Wrong meter / wrong factors = wrong bill; dispute volume.
- **Related invariants:** [[INV-meter-swap-split-calculation-within-period]]

---

### From 08-payments-and-programs.md

#### INV-054 — Payment-posting-order-rule-driven

- **Statement:** Payments apply to outstanding charges in the tariff/state-defined posting order (oldest-first, current-first, specific priority, etc.). The order is configured per tenant/jurisdiction and applied consistently. Manual one-off ordering is not allowed without documented exception reason.
- **Category:** computational
- **Confidence:** high
- **Source:** 08-payments-and-programs.md "Payment Posting Order (Regulated) … Tariff-configurable — this is a real difference across customers. Must be rule-driven."
- **Scope:** invoice_applications, payment posting engine
- **Rationale:** State-regulated rule; mis-application = customer harm and complaint.
- **Review note:** Whether posting order is per-tenant, per-rate-class, or per-customer-program-membership varies. Framing is "posting order is rule-driven and reproducible."

#### INV-055 — PCI-no-PAN-in-CIS

- **Statement:** The CIS application does not store, log, or pass through primary account numbers (PAN) for cards. All card interactions use tokenization at the processor; the CIS holds only the token and last-four. Database, logs, and message traces are PAN-free.
- **Category:** structural
- **Confidence:** high
- **Source:** 08-payments-and-programs.md "PCI DSS … Tokenize always. Don't store PAN, don't log PAN, don't pass PAN through the application layer"
- **Scope:** payments, payment methods, logging
- **Rationale:** PCI DSS compliance; scope reduction.
- **Related invariants:** [[INV-impossibility-proof-no-PAN-storage]] (likely impossibility-proof scenario)

#### INV-056 — NSF-and-ACH-return-handling-per-code

- **Statement:** Inbound payment reversals (NSF on check, ACH return codes R01–R29+) are processed per code-specific handling rules: re-debit when eligible, suspend retry on unauthorized codes (R10, R29), assess returned-payment fee where applicable, route to dunning if uncollectible. Codes are not collapsed into a single "failed" category.
- **Category:** computational
- **Confidence:** high
- **Source:** 08-payments-and-programs.md "ACH returns (R01 insufficient funds, R02 account closed, R10 unauthorized, R29 corporate unauthorized, etc.) — each return code has handling rules"
- **Scope:** payments, payment reversal handling
- **Rationale:** NACHA rules; unauthorized re-debit = compliance violation.
- **Known failure modes if violated:** billing-failures stage 08 (payment posting)

#### INV-057 — Unapplied-cash-holding-discipline

- **Statement:** Payments that cannot be matched to an account (wrong account number, unparseable remittance, amount mismatch) post to an unapplied-cash / suspense account with retain-and-research workflow, not silently dropped or auto-applied to a guessed account.
- **Category:** structural (workflow) + computational
- **Confidence:** high
- **Source:** 08-payments-and-programs.md "Unapplied cash / suspense — payment received but can't be applied; holds until resolved"
- **Scope:** payments, suspense ledger, reconciliation workflow
- **Rationale:** Customer received credit at bank; LDC must apply or refund.
- **Known failure modes if violated:** billing-failures stage 08 patterns

#### INV-058 — Late-fee-applicable-and-LIHEAP-and-dispute-exempt

- **Statement:** Late-payment charges are assessed only on overdue principal after the tariff-defined grace period (typically 5 business days), at the tariff rate (typically 1.5% monthly simple, state-capped), and only on amounts that are not (a) under active dispute, (b) covered by an active payment program exempting the customer (LIHEAP, etc.), or (c) under a payment-arrangement breach grace.
- **Category:** computational
- **Confidence:** high
- **Source:** 08-payments-and-programs.md "Late Payment Charges … 5-business-day grace … exempt for LIHEAP customers … Does not apply to disputed amounts"
- **Scope:** late-fee assessment engine, customer flags, dispute records
- **Rationale:** Tariff/PUC rules; mis-assessment = consumer complaint.
- **Related invariants:** [[INV-liheap-and-protected-class-exclusions-applied]]

#### INV-059 — Budget-billing-balance-tracking

- **Statement:** Budget-billing enrollees have a running budget balance (actual usage cost minus levelized payments) maintained alongside the actual account balance; review and adjustment events occur on the tariff-defined cadence (quarterly, semi-annually) and at the annual anniversary; settle-up at anniversary credits over-collection or amortizes under-collection per tariff.
- **Category:** computational
- **Confidence:** high
- **Source:** 08-payments-and-programs.md "Budget Billing … running 'budget balance' separate from actual bill balance; auto-adjust logic on anniversary or on significant variance"
- **Scope:** budget billing enrollment (gap per CONTEXT.md), invoice line items, account ledger
- **Rationale:** Misalignment of budget balance and actual = customer surprise and complaint.

#### INV-060 — DPA-breach-cancellation-and-balance-due

- **Statement:** Deferred payment arrangements cancel automatically when breach conditions trip (missed installment, further arrears, configured count of late current-period payments). Cancellation triggers: full remaining DPA balance becomes immediately due, collections resumes per jurisdiction rules, customer notification per tariff.
- **Category:** computational + structural (workflow)
- **Confidence:** high
- **Source:** 08-payments-and-programs.md "Breach conditions — miss a payment, or go further into arrears; DPA cancels, full balance immediately due, collections resumes"
- **Scope:** payment arrangement enrollment, collections engine
- **Rationale:** Tariff-defined; mis-handling = either improper collection or stranded arrears.

#### INV-061 — LIHEAP-pledge-blocks-disconnect-during-hold

- **Statement:** An active LIHEAP / agency pledge (committed amount within commitment period, typically 45–60 days) places a disconnect-eligibility hold on the account for that period; the actual remittance posts as a payment when received.
- **Category:** computational + structural (workflow)
- **Confidence:** high
- **Source:** 08-payments-and-programs.md "Agency submits a pledge; commits to pay within N days … System places a hold, blocks disconnect during the hold period"
- **Scope:** payment arrangement / pledge enrollment, collections engine
- **Rationale:** Statutory in many states; wrongful disconnect during pledge = harm + complaint + reconnect at LDC expense.
- **Related invariants:** [[INV-disconnect-eligibility-respects-jurisdictional-rules]]

#### INV-062 — Medical-certification-disconnect-hold

- **Statement:** A current, valid medical certification on file (physician-attested, within renewal window) suspends disconnect-eligibility for the customer/account for the certification's effective duration (state-specific, typically 30 days with renewal).
- **Category:** computational + structural (workflow)
- **Confidence:** high
- **Source:** 08-payments-and-programs.md "Medical Certification Hold"; 01-industry-and-regulatory.md
- **Scope:** customer/account program enrollment, collections engine
- **Rationale:** Statutory consumer protection.
- **Related invariants:** [[INV-disconnect-eligibility-respects-jurisdictional-rules]]

#### INV-063 — SCRA-active-duty-protections

- **Statement:** Customers (or related parties) on active military duty as recognized under SCRA receive the federal protections (interest cap, deferral, no foreclosure without court order — applied as applicable to a utility account) for the active-duty period and post-duty grace.
- **Category:** computational
- **Confidence:** medium
- **Source:** 08-payments-and-programs.md "Servicemembers Civil Relief Act (SCRA)"
- **Scope:** customer status flags, late-fee assessment, disconnect engine
- **Rationale:** Federal statute.
- **Review note:** Specific application to gas utility accounts varies; framing should be "SCRA flag is honored across collections/late-fee paths."

#### INV-064 — Multi-program-enrollment-honored

- **Statement:** A customer/account may hold simultaneous active enrollments in multiple programs (e.g., budget billing + LIHEAP + medical certification + third-party notification). Each program's effects (rate exclusions, disconnect holds, notice CCs, posting modifiers) apply additively; collections decisions evaluate all active programs before action.
- **Category:** structural + computational
- **Confidence:** high
- **Source:** 08-payments-and-programs.md "A customer may be in multiple programs simultaneously … Collections treatment engine evaluates all programs when deciding action"
- **Scope:** program enrollment records (gap), collections engine, billing engine
- **Rationale:** Single-program assumption = wrongful action under one of the unconsidered programs.
- **Related invariants:** [[INV-disconnect-eligibility-respects-jurisdictional-rules]], [[INV-liheap-and-protected-class-exclusions-applied]]

#### INV-065 — Program-enrollment-lifecycle

- **Statement:** Every program enrollment record traverses a defined lifecycle: pending-application → active → expired (or completed) → breached → canceled. State transitions are events with timestamps and reasons; "active" is bounded by effective and renewal dates.
- **Category:** structural
- **Confidence:** medium
- **Source:** 08-payments-and-programs.md "Enrollment lifecycle: pending-application → active → expired → breached → completed"
- **Scope:** payment program / assistance program enrollment records (gap per CONTEXT.md)
- **Rationale:** Predictable program treatment; supports audit and renewal cadence.

#### INV-066 — Third-party-notification-CCs-not-financially-binding

- **Statement:** Third-party notification adds the designated party as a CC on notices (bills, disconnect warnings, dunning); it does not create a financial obligation or change account ownership. Removal of the third party does not affect account financial state.
- **Category:** structural
- **Confidence:** high
- **Source:** 08-payments-and-programs.md "Third-Party Notification … Not a financial commitment by the third party — notification only"
- **Scope:** communication log (gap), third-party enrollment, party/account relationships
- **Rationale:** Liability and contract clarity.

---

### From 09-credit-collections-disconnects.md

#### INV-067 — Collections-pipeline-step-completeness

- **Statement:** Disconnect for non-payment can occur only after the jurisdiction's required notice sequence has been completed in order with prescribed minimum elapsed time per step (past-due notice → formal disconnect notice → pre-disconnect contact → personal contact attempt). A skipped or out-of-order step is grounds for PUC reversal of the disconnect.
- **Category:** structural (workflow) + computational (elapsed-time rule)
- **Confidence:** high
- **Source:** 09-credit-collections-disconnects.md "Each step has regulated content and timing. Miss a step and a disconnect can be reversed by the PUC."
- **Scope:** dunning_events, collections engine, work_orders
- **Rationale:** State PUC consumer protection rules; non-compliance produces reversed disconnects + fines.
- **Related invariants:** [[INV-disconnect-eligibility-respects-jurisdictional-rules]], [[INV-audit-trail-subpoena-readiness]]

#### INV-068 — Bypass-conditions-evaluated-daily

- **Statement:** The collections engine evaluates every account in the pipeline against the configured bypass-condition set daily (or on each pipeline step), including: active DPA, budget billing current, LIHEAP pledge in-flight, medical certification, cold weather moratorium, temperature-forecast hold, bankruptcy stay, pending billing dispute, payment-pending-clearance, third-party notification not yet fulfilled, senior/disabled status. Any active bypass halts pipeline progression for that account.
- **Category:** structural (workflow) + computational (rule evaluation)
- **Confidence:** high
- **Source:** 09-credit-collections-disconnects.md "Bypass Conditions (Collections Engine Stops) — engine evaluates these daily for every account"
- **Scope:** collections engine, dunning_events, program enrollments, NWS forecast feed
- **Rationale:** Single-bypass-missed = wrongful disconnect.
- **Related invariants:** [[INV-disconnect-eligibility-respects-jurisdictional-rules]], [[INV-multi-program-enrollment-honored]]

#### INV-069 — Disconnect-execution-evidence-required

- **Statement:** Every executed disconnect produces an evidence record containing: final-read captured, on-site outcome timestamp, customer-notice-left flag, photo documentation reference (or affidavit), tech identity. A disconnect lacking complete evidence cannot be billed for disconnect/reconnect fees and is not defensible in PUC review.
- **Category:** structural
- **Confidence:** medium
- **Source:** 09-credit-collections-disconnects.md "On-site protocol … Photo documentation for audit trail"
- **Scope:** work_orders, meter_readings (final read), media references
- **Rationale:** Audit defense; dispute resolution.

#### INV-070 — Gas-reconnect-requires-on-site-tech

- **Statement:** Gas reconnection cannot be remotely actuated; a qualified technician must be on site to perform pressure test, leak check, pilot relight (where applicable), and re-energize the service. Reconnect work orders schedule a customer-present appointment within the regulatory SLA window.
- **Category:** structural + computational (SLA)
- **Confidence:** high
- **Source:** 09-credit-collections-disconnects.md "A technician must be on site … Customer must be home … PHMSA rules dictate safety procedures"
- **Scope:** work_orders, reconnection workflow, SLA tracking
- **Rationale:** PHMSA safety rules; physical reality of gas service.
- **Review note:** Captures a *system* invariant (no remote-reconnect operation may be exposed in UI/API) — candidate for impossibility-proof classification in Method 1.

#### INV-071 — Reconnection-SLA-honored

- **Statement:** Once a customer has met the reconnection conditions (payment received, deposit posted, DPA reinstated, etc.), reconnection must be scheduled within the jurisdiction's SLA (typically 24–48 hours during business days, longer for weekends; configurable per tariff). SLA miss is a complaint trigger.
- **Category:** computational
- **Confidence:** high
- **Source:** 09-credit-collections-disconnects.md "Regulated reconnection SLAs — typically 24–48 hours after payment receipt during business days"
- **Scope:** work_orders, reconnect scheduling
- **Rationale:** Tariff/PUC rule.

#### INV-072 — Bankruptcy-absolute-stay

- **Statement:** On notice of a customer's bankruptcy filing, the system immediately and absolutely halts collections activity: stops dunning notices, withdraws pending disconnect work orders, reverses pending field activity, splits the ledger at petition date (pre-petition / post-petition). Any collections action attempted after filing-date awareness is a federal-law violation (11 U.S.C. § 362).
- **Category:** structural (workflow + ledger split) + computational
- **Confidence:** high
- **Source:** 09-credit-collections-disconnects.md "Bankruptcy Handling … Automatic stay in effect from filing — no collections activity"; 13-gotchas-and-lessons.md "Absolute halt on collections activity"
- **Scope:** customer bankruptcy flag, collections engine, account_ledger split, dunning_events, work_orders
- **Rationale:** Federal statute; violation produces sanctions and damages.
- **Known failure modes if violated:** dunning notice sent post-petition, court-imposed sanctions
- **Related invariants:** [[INV-pre-and-post-petition-ledger-split]]

#### INV-073 — Pre-and-post-petition-ledger-split

- **Statement:** A bankruptcy filing splits the account ledger at petition date: pre-petition balance becomes an unsecured claim (subject to discharge or plan treatment); post-petition charges accumulate as new debt outside the bankruptcy. The system tracks both balances separately and posts to them by date of charge/payment.
- **Category:** structural
- **Confidence:** high
- **Source:** 09-credit-collections-disconnects.md "Pre-petition vs. post-petition balance tracking — split the ledger at the petition date"
- **Scope:** account_ledger, bankruptcy flag, invoice posting logic
- **Rationale:** Bankruptcy code; payments to pre-petition must be controlled by plan.
- **Related invariants:** [[INV-bankruptcy-absolute-stay]], [[INV-append-only-ledger]]

#### INV-074 — Bankruptcy-adequate-assurance-window

- **Statement:** Per 11 U.S.C. § 366, a utility may require adequate assurance of payment (deposit or equivalent) from a bankrupt customer within 20 days post-filing; if not provided, service may be discontinued. The system tracks the 20-day window and the assurance disposition.
- **Category:** computational + structural (workflow)
- **Confidence:** medium
- **Source:** 09-credit-collections-disconnects.md "Utility may require adequate assurance (deposit) within 20 days (11 U.S.C. § 366)"
- **Scope:** bankruptcy workflow, deposits, customer flags
- **Rationale:** Federal statute; failure to act in window forfeits right.

#### INV-075 — Meter-dispute-suspends-collections-on-disputed-amount

- **Statement:** When a customer formally disputes a bill on grounds of meter accuracy (or other PUC-recognized grounds), collections activity on the disputed amount is suspended pending dispute resolution. Late fees do not accrue on disputed amount during the dispute. Resolution (meter test, audit, ruling) results in rebill per state rules (typically 2% accuracy tolerance, back-adjustment up to 6–12 months).
- **Category:** computational + structural
- **Confidence:** high
- **Source:** 09-credit-collections-disconnects.md "Pending billing dispute"; 13-gotchas-and-lessons.md "Meter Accuracy Disputes"
- **Scope:** disputes (likely gap), collections engine, late fee engine
- **Rationale:** State PUC consumer protection.
- **Related invariants:** [[INV-late-fee-applicable-and-LIHEAP-and-dispute-exempt]]

#### INV-076 — Write-off-aging-policy

- **Statement:** Accounts in disconnected-no-payment status proceed to write-off after the configured aging threshold (typically 90–180 days). Write-off moves balance from A/R to bad debt expense; subsequent recoveries reverse a portion. The aging threshold is configurable per tenant policy and consistent with the Bad Debt Rider true-up.
- **Category:** computational
- **Confidence:** medium
- **Source:** 09-credit-collections-disconnects.md "Write-Off — Typically 90–180 days after disconnect with no payment activity"
- **Scope:** account_ledger, A/R aging, GL distribution
- **Rationale:** Financial reporting; tariff Bad Debt Rider mechanics.

#### INV-077 — Collections-engine-deterministic-and-idempotent

- **Statement:** The collections engine produces the same decisions given the same inputs (same account state, same rule version, same evaluation date); re-running the engine for the same day does not duplicate actions, escalate, or alter prior decisions. Full audit trail of every evaluation, decision, and action is retained.
- **Category:** structural
- **Confidence:** high
- **Source:** 09-credit-collections-disconnects.md "Deterministic, idempotent — same inputs always produce same decisions. Full audit trail … Time-travel"
- **Scope:** collections engine, dunning_events
- **Rationale:** Replay for audit; safe re-run after operational incident.
- **Related invariants:** [[INV-audit-trail-subpoena-readiness]]

#### INV-078 — Deposit-amount-tied-to-credit-evaluation

- **Statement:** Deposit amount on new service is determined by the configured credit evaluation rule (typically 2× average monthly bill or 1/6 annual billing, with adjustments for credit score and waivers for established history / guarantor / letter of credit). Deposits accrue interest from posting date per state-mandated rate.
- **Category:** computational
- **Confidence:** medium
- **Source:** 09-credit-collections-disconnects.md "Deposits … Amount: usually 2× average monthly bill or 1/6 of annual billing"
- **Scope:** deposits, credit evaluation workflow
- **Rationale:** PUC rule.
- **Review note:** Texas RRC caps deposits at 1/6 annual estimated billing (per execution-kickoff.md). Texas-specific cap is configurable; framing is "deposit amount honors jurisdiction cap."

---

### From 10-transportation-choice-edi.md

#### INV-079 — Transport-customer-not-billed-commodity

- **Statement:** Customers on transport rate schedules (FT, IT, NGVFT, etc.) are billed for delivery and any transport-specific riders (balancing/imbalance, storage reservation, transport rider) but not for the commodity (PGA). Commodity is invoiced separately by the supplier (or by the LDC via UCB on the supplier's behalf for choice markets).
- **Category:** computational
- **Confidence:** high
- **Source:** 10-transportation-choice-edi.md "Transport Customer Billing — Skip the PGA"; 03-pga-gas-cost-recovery.md
- **Scope:** rate_schedule_items, billing engine
- **Rationale:** Tariff-required; double-billing the customer for commodity = regulatory violation.
- **Related invariants:** [[INV-transportation-customers-not-billed-PGA]] (duplicate framing — to merge in Session 2)

#### INV-080 — Transport-imbalance-charges-tracked

- **Statement:** Transport customers and their supplier pools may incur imbalance charges (when delivered vs. consumed deviation exceeds the tariff tolerance band — typically ±5%–10% daily). Monthly cashout applies imbalance × market index price ± penalty adder; OFO violations carry separate penalties.
- **Category:** computational
- **Confidence:** medium
- **Source:** 10-transportation-choice-edi.md "Imbalance Handling"
- **Scope:** transport balancing tables (gap), invoice_line_items
- **Rationale:** Tariff mechanic; non-tracking = lost revenue and supplier disputes.
- **Review note:** Whether this falls in launch scope depends on transport-customer launch plan. Flag for expert.

#### INV-081 — Transport-eligibility-volume-gated

- **Statement:** Eligibility for transport rate schedules is gated on customer-class and annual-volume threshold per tariff (e.g., "must consume 3,500 Mcf/yr to be a direct transport customer"); migration onto/off transport rate is a workflow-controlled event with effective date.
- **Category:** computational
- **Confidence:** medium
- **Source:** 10-transportation-choice-edi.md "Customer eligibility typically gated on annual volume"
- **Scope:** account.rate_schedule, transport eligibility rules
- **Rationale:** Tariff applicability rule.

---

### From 11-taxes-and-gl-accounting.md

#### INV-082 — Tax-jurisdiction-stacking-correct

- **Statement:** Each customer's bill assesses the full applicable tax stack for the premise's tax jurisdictions: state, county, city, special districts, UUT, franchise fee, regulatory assessment, USF. Each tax is computed on its prescribed base, with stacking order respected per jurisdiction rules.
- **Category:** computational
- **Confidence:** high
- **Source:** 11-taxes-and-gl-accounting.md "Taxes are jurisdictional and layered. Expect 3–8 tax lines on a typical bill."
- **Scope:** tax_jurisdictions (gap), tax engine, invoice_line_items
- **Rationale:** Tax law; under-assessment = LDC liability; over-assessment = customer harm.
- **Related invariants:** [[INV-premise-zone-assignment-complete]], [[INV-tax-jurisdiction-date-effective]]

#### INV-083 — Tax-exemption-certificate-lifecycle

- **Statement:** Tax exemptions (resale, manufacturing, agricultural, nonprofit, government, religious) are tracked per certificate with issue date, expiry date, scanned image, and certificate number. Expired certificates revert the customer to taxable; system prompts renewal in advance of expiry. Application of an exemption to a billing period requires the certificate to be valid for that period.
- **Category:** structural + computational
- **Confidence:** high
- **Source:** 11-taxes-and-gl-accounting.md "Certificates expire — typically 1–5 years. System must track and prompt renewal before expiry."
- **Scope:** tax exemption certificates (gap), customer flags, tax engine
- **Rationale:** Tax law; applying tax after expiry = customer-contact moment; applying exemption without valid cert = audit finding.

#### INV-084 — Tax-jurisdiction-assignment-by-geocode

- **Statement:** Tax jurisdiction assignment for a premise is determined by geocoding the physical address; manual overrides require documented reason and audit. The assignment is date-effective: jurisdiction boundary changes generate new effective-dated assignments rather than silent overwrites.
- **Category:** structural
- **Confidence:** medium
- **Source:** 11-taxes-and-gl-accounting.md "Geocode premise → tax engine returns jurisdictions"
- **Scope:** service_locations, tax_jurisdictions (gap)
- **Rationale:** Wrong jurisdiction = under/over remittance, customer complaint.
- **Review note:** Geocoding mechanism (tax engine vs. internal) is a design choice; invariant is "geographic ground-truth drives assignment, with date-effective history of changes."

#### INV-085 — Revenue-distribution-matrix-deterministic

- **Statement:** Every charge on a bill posts to a specific GL account by the deterministic matrix `(charge_type, customer_class, service_territory, tax_jurisdiction) → GL_account + subaccount + FERC/NARUC_USOA_code + cost_center`. The matrix is configured per tenant; posting cannot proceed for a charge with an unresolved matrix entry.
- **Category:** structural + computational
- **Confidence:** high
- **Source:** 11-taxes-and-gl-accounting.md "Revenue Distribution Matrix … The platform needs a configurable matrix"
- **Scope:** GL posting matrix (gap per CONTEXT.md), invoice_line_items, account_ledger
- **Rationale:** FERC USOA / NARUC USOA reporting; financial reconcilability.
- **Related invariants:** [[INV-append-only-ledger]]

#### INV-086 — Franchise-fee-remitted-to-franchising-municipality

- **Statement:** Aggregate franchise-fee revenue collected from customers within a franchising municipality matches the remittance owed to that municipality (per franchise agreement, often ~3–6% of in-city gross revenue, per period). Each customer's franchise-fee line item is tagged to the specific franchising entity for remittance reporting.
- **Category:** computational
- **Confidence:** high
- **Source:** 11-taxes-and-gl-accounting.md "Franchise fee — % of in-city revenue; remitted to franchising city"
- **Scope:** invoice_line_items franchise fees, GL remittance ledger
- **Rationale:** Franchise agreement contracts; under-remittance is breach.
- **Related invariants:** [[INV-franchise-fee-traceable-to-jurisdiction]] (likely duplicate framing — to merge in Session 2)

#### INV-087 — CIAC-rate-base-treatment

- **Statement:** Contributions in Aid of Construction (customer-funded plant extension) are accounted as a reduction of rate base; refundable advances accrue eligibility for refund based on additional-customer-connection conditions and are written off at end of refund period. The system tracks original contribution, refund eligibility, refund payments, and writeoff.
- **Category:** structural + computational
- **Confidence:** low
- **Source:** 11-taxes-and-gl-accounting.md "CIAC (Contributions in Aid of Construction)"
- **Scope:** CIAC ledger (gap), plant accounting (typically in ERP not CIS)
- **Rationale:** Rate-base correctness; tax treatment.
- **Review note:** May live in ERP, not CIS. Confidence low because TallyUtility scope vs. ERP boundary is uncertain. Flag for expert.

---

### From 13-gotchas-and-lessons.md
*(Most candidates above already capture 13's content. The entries below are framing reinforcements or new angles.)*

#### INV-088 — Audit-proof-deterministic-calculation

- **Statement:** All billing calculation logic is deterministic (no randomness, no non-injected time dependence), side-effect-free per evaluation, and references version-locked formula tables. Re-running the calculation with the same inputs (including snapshot inputs) reproduces the same outputs byte-for-byte.
- **Category:** structural
- **Confidence:** high
- **Source:** 13-gotchas-and-lessons.md "Audit-Proof Math — Deterministic calculation (no randomness, no time-dependent unless explicitly modeled). … Side-effect-free rate evaluation."
- **Scope:** billing engine, rate engine
- **Rationale:** Cancel-rebill correctness; PUC reproduction.
- **Related invariants:** [[INV-invoice-snapshot-completeness]], [[INV-bi-temporality]]

#### INV-089 — Regulated-notice-language-versioned

- **Statement:** Customer-facing notices that have regulator-prescribed language (disconnect notices, rate change notices, cold-weather-rule notifications, formal dispute responses) use template-versioned content with effective dates, jurisdiction binding, and approval workflow. Notice records persist the template version used and the rendered content.
- **Category:** structural
- **Confidence:** high
- **Source:** 13-gotchas-and-lessons.md "Bill Messaging Is Often Regulated Verbatim … Build a template system with: Version control. Approval workflow. Jurisdiction assignment. Language variants."
- **Scope:** notice templates (gap), communication log (gap)
- **Rationale:** PUC compliance; non-prescribed language voids the notice.
- **Related invariants:** [[INV-communication-log-completeness]]

#### INV-090 — Communication-log-completeness

- **Statement:** Every customer-directed communication (bill, statement, dunning notice, disconnect notice, rate change notice, dispute response, program notification, third-party CC, system message) is logged per-account with channel, timestamp, template version, rendered content (or content reference), and delivery outcome (sent/bounced/delivered).
- **Category:** structural
- **Confidence:** high
- **Source:** 13-gotchas-and-lessons.md "Regulatory Subpoena Readiness — Every notice sent to a customer, with timestamps and content snapshots"; CONTEXT.md (gap: no outbound communication log)
- **Scope:** communication log (gap per CONTEXT.md)
- **Rationale:** Subpoena defense; complaint defense ("notice was sent on date X").
- **Related invariants:** [[INV-audit-trail-subpoena-readiness]], [[INV-regulated-notice-language-versioned]]

#### INV-091 — Bill-image-retention-period

- **Statement:** A rendered bill image (PDF or equivalent) is retained for the regulator-prescribed period (typically 7 years for U.S. gas LDCs) and remains retrievable for cancel-rebill, audit, and dispute resolution.
- **Category:** structural
- **Confidence:** high
- **Source:** 13-gotchas-and-lessons.md "Bill Image Retention — Typically 7 years per regulatory requirements"
- **Scope:** invoices (bill image reference), archive store
- **Rationale:** Regulatory retention.

#### INV-092 — Multi-dwelling-submetering-jurisdiction-aware

- **Statement:** Submetering of tenants by a landlord is permitted or prohibited per jurisdiction rule; the system honors the configured posture (some jurisdictions require master-metering only). Submeter accounts cannot be billed where prohibited.
- **Category:** computational + structural
- **Confidence:** low
- **Source:** 13-gotchas-and-lessons.md "Multi-Dwelling Submetering — Some jurisdictions prohibit tenant submetering"
- **Scope:** premise configuration, tenant/landlord account relationships
- **Rationale:** Statute; non-compliant submetering = legal exposure.
- **Review note:** Whether the system has a "submeter" concept in scope is uncertain. Flag for expert.

#### INV-093 — Estate-and-deceased-customer-handling

- **Statement:** On notice of a customer's death, collections are paused pending estate disposition (or survivor's takeover of the account); deceased flag and date are recorded; subsequent collections actions require survivor/estate identity resolution.
- **Category:** structural (workflow)
- **Confidence:** medium
- **Source:** 13-gotchas-and-lessons.md "Deceased customer — estate processing, hold collections, often survivor takes over"
- **Scope:** customer status flags, collections engine
- **Rationale:** Consumer protection norm; legal exposure for collecting against estate without protocol.

#### INV-094 — Format-drift-tolerance-on-inbound-files

- **Statement:** Inbound vendor files (AMR/AMI reads, NACHA ACH returns, lockbox remittance, print-vendor acks) are processed with format-version awareness and graceful degradation on unknown fields; processing emits alerts but does not silently drop records. Replay capability exists for re-processing a corrected file.
- **Category:** structural
- **Confidence:** medium
- **Source:** 13-gotchas-and-lessons.md "AMR/AMI File Format Drift — Format versioning. Graceful degradation / alerting on unknown fields. Replay capability"
- **Scope:** import_jobs, import_staging, ingestion adapters
- **Rationale:** Operational continuity; vendor format changes cannot silently corrupt the read pipeline.

#### INV-095 — Canary-account-or-pre-mail-control

- **Statement:** Each billing cycle includes a control mechanism (canary internal accounts billed and verified against expected values, and/or pre-mail exception review on production accounts) that catches material billing errors before customer-visible delivery.
- **Category:** structural (operational)
- **Confidence:** low
- **Source:** 13-gotchas-and-lessons.md "Bad Bill Visibility Is Existential … Canary accounts (internal test accounts billed every cycle, verified against expected values)"
- **Scope:** billing operations dashboard, exception queue
- **Rationale:** Operational quality gate.
- **Review note:** Whether canary accounts rise to "invariant" or are an operational practice is a framing question. Pre-mail exception review (already in INV-048) probably covers the system invariant.

#### INV-096 — Tax-engine-and-rate-change-reconciliation

- **Statement:** Tax-rate and PGA-rate changes that may lag at external vendors (tax engine, print vendor) are reconciled within a defined window post-change; bills issued under a stale rate are detected and corrected before customer impact compounds.
- **Category:** structural (operational)
- **Confidence:** low
- **Source:** 13-gotchas-and-lessons.md "Tax Engine Lag — Even Avalara/Vertex sometimes lag a jurisdiction rate change by a few days. Build reconciliation reports"
- **Scope:** rate change workflow, tax engine integration
- **Rationale:** Operational hygiene; catches integration drift.
- **Review note:** Operational practice rather than system invariant. May not meet inclusion threshold.

---

### From 16-bi-temporality.md
*(Most bi-temporal candidates already captured under INV-035, INV-039, INV-026, INV-088. The entries below sharpen specific framings only this file makes explicit.)*

#### INV-097 — Correction-vs-retraction-distinguished

- **Statement:** The system distinguishes corrections (we had the facts wrong; revise the historical valid-time) from retractions (the fact never happened; we no longer believe it). A correction closes the old record's transaction-time and inserts a corrected record; a retraction closes the old record's transaction-time without insertion. Each is recorded as a distinct event with explicit reason.
- **Category:** structural
- **Confidence:** high
- **Source:** 16-bi-temporality.md §7.2 "Retractions vs. Corrections"
- **Scope:** bi-temporal data model, correction and retraction events
- **Rationale:** Regulators care about the difference. Conflating produces audit ambiguity and incorrect downstream rebill logic.
- **Related invariants:** [[INV-bi-temporality]], [[INV-audit-trail-subpoena-readiness]]

#### INV-098 — Cross-entity-temporal-coordinate-consistency

- **Statement:** A bill (or any multi-entity computation) applies a single, explicitly-specified temporal-coordinate basis (tt, vt) consistently across every reference-data join. Mixing coordinates across entities within one computation is forbidden unless the mixed mode is explicit and documented (e.g., the "mixed" cancel-rebill flavor in §5.1).
- **Category:** structural
- **Confidence:** high
- **Source:** 16-bi-temporality.md §7.4 "Cross-Entity Temporal Consistency"
- **Scope:** billing engine, all bi-temporal queries
- **Rationale:** "Phantom inconsistency" — rate from one moment, factor from another — is a silent corruption mode.
- **Related invariants:** [[INV-bi-temporality]], [[INV-audit-proof-deterministic-calculation]]

#### INV-099 — Bill-snapshot-content-addressable-and-self-contained

- **Statement:** Each finalized bill is serialized into a content-addressable artifact (hash-as-id) containing the complete input set needed to reproduce its numbers without further reference-data lookups. The artifact is the canonical bill record; relational bill rows reference the artifact. Reproducing the bill from the artifact requires no database join.
- **Category:** structural
- **Confidence:** medium
- **Source:** 16-bi-temporality.md §6.4 "The bill itself as an immutable, content-addressable snapshot"
- **Scope:** invoices, invoice_snapshots (gap), object storage for artifacts
- **Rationale:** Decouples bill reproducibility from bi-temporal-query availability; defense-in-depth for cancel-rebill and audit.
- **Related invariants:** [[INV-invoice-snapshot-completeness]], [[INV-bill-immutability]], [[INV-audit-proof-deterministic-calculation]]
- **Review note:** Content-addressability is one implementation of the broader snapshot invariant (INV-039). Whether content-addressability rises to its own invariant or is a strategy for the snapshot invariant is a framing question.

#### INV-100 — Cancel-rebill-pure-function

- **Statement:** Cancel-rebill is a pure function of (input-set-at-chosen-temporal-coordinates, bill formula). It has no side effects beyond producing the new bill artifact and the ledger entries that reflect the bill difference; running it twice with the same inputs produces the same output. The temporal-coordinate basis is an explicit input, not implicit.
- **Category:** structural
- **Confidence:** high
- **Source:** 16-bi-temporality.md §6.4 "Cancel-rebill as a pure function"
- **Scope:** cancel-rebill engine, billing engine
- **Rationale:** Deterministic reproducibility; safe replay; what-if scenarios fall out for free.
- **Related invariants:** [[INV-audit-proof-deterministic-calculation]], [[INV-cancel-rebill-uses-original-period-world]]

#### INV-101 — Backbilling-cap-per-jurisdiction

- **Statement:** Cancel-rebill of a historical bill whose `vt_start` is older than the jurisdiction's backbilling cap (e.g., NY 24 months, CA 3 months, varies by state) is rejected by the system as a declarative rule. The cap is configured per jurisdiction and applied uniformly across rebill workflows.
- **Category:** computational + structural
- **Confidence:** high
- **Source:** 16-bi-temporality.md §5.5 "Backbilling Caps"; CPUC PG&E backbilling decision D0709041
- **Scope:** cancel-rebill engine, jurisdiction config
- **Rationale:** State PUC statutes/orders; cap enforcement is a centralized rule, not per-workflow ad-hoc.
- **Related invariants:** [[INV-cancel-rebill-uses-original-period-world]]

#### INV-102 — UTC-storage-and-explicit-time-zone-semantics

- **Statement:** All timestamps in the system are stored as UTC; local-time rendering occurs only at the UI/notice layer. For valid-time semantics that depend on calendar-day boundaries (rate effective dates, moratorium start dates), the time zone defining "midnight" is explicit per tenant/territory and documented.
- **Category:** structural
- **Confidence:** medium
- **Source:** 16-bi-temporality.md §7.7 "Time Zone Discipline"
- **Scope:** schema timestamp columns, billing engine date resolution
- **Rationale:** DST and TZ ambiguity are recurring bug sources in date-effective systems.

#### INV-103 — Conflicting-concurrent-assertions-surface-for-resolution

- **Statement:** When two writers attempt overlapping valid-time assertions for the same entity within a concurrency window, the system surfaces a conflict (rather than silently linearizing into last-writer-wins). Resolution flows through an approval/supervisor workflow.
- **Category:** structural (concurrency)
- **Confidence:** low
- **Source:** 16-bi-temporality.md §7.1 "Concurrent Assertions and Ordering"
- **Scope:** bi-temporal write path, approval workflow
- **Rationale:** Avoids silent data loss when two CSRs make conflicting overlapping assertions.
- **Review note:** Whether conflict-surfacing is required or last-writer-wins is acceptable depends on the use case. Low confidence on framing; flag for expert.

---

### From 25-rate-change-complexity.md
*(Most rate-change content reinforces existing invariants — INV-005, INV-008, INV-035, INV-039, INV-047. Single new framing below.)*

#### INV-104 — Mid-period-segment-independent-charge-stack

- **Statement:** When a billing period straddles a tariff/rate version change, *each* sub-segment's full charge stack (base charges, block thresholds, demand charges, riders, WNA, PGA, taxes) is computed independently under its own tariff version using its own days/usage allocation; segment results are then summed. Applying any single sub-segment's tariff version to the entire period is a violation.
- **Category:** computational
- **Confidence:** high
- **Source:** 25-rate-change-complexity.md "Mid-Period Rate Changes: The Arithmetic Problem"; billing-failures/stage-04 "Mid-period tariff change fails to prorate"
- **Scope:** billing engine, invoice_line_items
- **Rationale:** Tariff law; SAP IS-U is documented to commonly fail this — taking the simple route of "use one version for the whole period."
- **Related invariants:** [[INV-mid-period-tariff-change-split]], [[INV-pga-mid-period-proration]]

---

### From 24-billing-failures-index.md, cross-cutting-patterns.md, stage-04 and stage-08 (detailed)

#### INV-105 — Pressure-factor-applied-only-to-elevated-pressure-meters

- **Statement:** Pressure correction (Fp) is applied to a meter's consumption only when the meter is on elevated-pressure service (per its pressure class on the meter master). Residential meters at 7" WC base do not have a pressure-factor multiplier other than 1.0 applied. Applying a pressure factor to a residential meter is a per se billing error.
- **Category:** computational
- **Confidence:** high
- **Source:** billing-failures/stage-03 (via 24-billing-failures-index) "Pressure factor applied to residential meters — drives residential bills 13–34% high"; 04-zones-and-metering.md
- **Scope:** consumption calculation, meters (pressure class)
- **Rationale:** Documented systemic billing error category; PG&E Rule 17 lists this explicitly.
- **Related invariants:** [[INV-volume-to-energy-formula-correctly-composed]], [[INV-meter-attributes-complete-for-billing]]

#### INV-106 — Seasonal-rate-keyed-to-meter-read-date

- **Statement:** When a rate schedule has seasonal effective dates (e.g., winter vs. summer rate), the applicable rate for a consumption period is determined by the meter-read date, not the bill-issue date. A bill issued in December for usage that was read in November applies the November-applicable seasonal rate.
- **Category:** computational
- **Confidence:** high
- **Source:** billing-failures/stage-04 "Seasonal rate switchover uses bill-issue-date instead of meter-read-date"
- **Scope:** rate determination, billing engine
- **Rationale:** Tariff intent; documented systemic failure of legacy CIS to use bill-issue-date.

#### INV-107 — Tier-threshold-prorated-with-period

- **Statement:** When a billing period is shorter than the standard cycle (new service, final bill, mid-cycle event), block/tier thresholds for the rate schedule prorate proportionally with the period length (e.g., 30-therm tier on 30 days = 10-therm tier on 10 days), unless the tariff explicitly forbids proration.
- **Category:** computational
- **Confidence:** medium
- **Source:** billing-failures/stage-04 "Tiered threshold proration for partial months — SQ rules in CC&B don't prorate by default"; 07-billing-calculation.md
- **Scope:** block-rate calculation
- **Rationale:** Tariff intent; Oracle CC&B documented to not prorate by default.
- **Review note:** Whether all tariffs prorate or some explicitly don't may vary; framing as "default to prorate unless tariff forbids" matters.

#### INV-108 — Mass-error-detection-via-absolute-baseline

- **Statement:** Each billing batch is evaluated against absolute baselines (cycle total revenue vs. commission-approved revenue requirement, cycle distribution vs. prior-year same-month, canary-account expected values) in addition to per-bill relative-tolerance checks. A systematic over-/under-billing that produces internally-consistent batch totals but deviates from absolute baselines is flagged and held.
- **Category:** structural (operational)
- **Confidence:** medium
- **Source:** billing-failures/cross-cutting-patterns.md "Pattern 2: The Mass-Error-Passes-Validation Blind Spot"
- **Scope:** billing operations dashboard, batch validation
- **Rationale:** Hydro One pattern: 84,394 customers affected because relative-tolerance checks couldn't catch a systematic error. Post-2020 enforcement environment treats mass billing errors as shareholder-funded liability.
- **Review note:** This is a billing-ops practice as much as a system invariant. The system *invariant* is "the batch cannot release without an absolute-baseline gate" — framing matters.
- **Related invariants:** [[INV-pre-mail-exception-routing]]

#### INV-109 — Payment-customer-earmarking-honored

- **Statement:** When a payment carries a customer-explicit earmarking (memo line, portal selection, "for X invoice"), application honors the earmarking before falling back to the tariff posting order. Earmarked payments are not allocated to other invoices.
- **Category:** computational
- **Confidence:** medium
- **Source:** billing-failures/stage-08 "Wrong-invoice allocation against customer earmarking … UCC §3-310"
- **Scope:** payment posting engine, invoice_applications
- **Rationale:** UCC §3-310; ignoring earmarking causes wrongful delinquency on the customer's intended invoice.
- **Related invariants:** [[INV-payment-posting-order-rule-driven]]
- **Review note:** Whether the system *must* support earmarking or earmarking is opt-in is a framing question. Many tariffs require oldest-first regardless — framing must reconcile.

#### INV-110 — Regulated-vs-unregulated-allocation-discipline

- **Statement:** Payments applied to an account must reach the regulated utility service (gas) before being applied to unregulated add-on services (appliance plan subscriptions, surge protection, etc.). Cross-subsidy by allocating customer payment to unregulated services first that results in regulated-service disconnection is forbidden.
- **Category:** computational + structural
- **Confidence:** high
- **Source:** billing-failures/stage-08 "Allocation across regulated and unregulated service lines — CenterPoint Minnesota case (March 27, 2024)"
- **Scope:** payment posting engine
- **Rationale:** Minnesota PUC ruling; cross-subsidy disconnections from unregulated charges are unacceptable.
- **Related invariants:** [[INV-payment-posting-order-rule-driven]]

#### INV-111 — Web-and-IVR-payment-idempotency

- **Statement:** Payment submissions from web and IVR channels carry a unique idempotency token; duplicate submissions of the same token (rage-click, retry) do not produce duplicate postings. Confirmation to the customer is only returned after the processor acknowledges processing (not merely the request).
- **Category:** structural
- **Confidence:** high
- **Source:** billing-failures/stage-08 "Duplicate web payments from rage-click or double-submit … server-side idempotency"; "Web or IVR confirmation given but payment not posted"
- **Scope:** payments, payment intake channels
- **Rationale:** Customer double-charge avoidance; defensible posting state.

#### INV-112 — Disconnect-work-order-premise-verification

- **Statement:** A disconnect work order in the field is validated against the meter serial and service point before action; the technician's on-site capture (meter serial, service point) must match the dispatched work order. Mismatches halt the disconnect and route to dispatch resolution.
- **Category:** structural (workflow) + computational
- **Confidence:** medium
- **Source:** billing-failures/stage-09 via 24-billing-failures-index "Wrong-meter disconnect — field tech at unit B instead of unit A"
- **Scope:** work_orders, field app, meters
- **Rationale:** Wrong-meter disconnects produce no-heat and frozen-pipes events; vendor/insurance liability.
- **Review note:** This bridges system invariant ("the system enforces match") and procedural discipline. Framing question.

#### INV-113 — Bill-template-and-rate-engine-coordinated-changes

- **Statement:** Changes to required-by-regulation bill line items require simultaneous updates to the rate engine (charge calculation) and the bill template (line-item display). A rate change that is charged but not displayed (or vice versa) is a per se disclosure violation.
- **Category:** structural (process) + computational
- **Confidence:** medium
- **Source:** billing-failures/stage-04 "Energy-efficiency rider not coordinated with bill template — MA EES 2025/2026 heating season required simultaneous rate-engine and template change"
- **Scope:** rate engine, notice/bill template system
- **Rationale:** State PUC disclosure rules.
- **Related invariants:** [[INV-regulated-notice-language-versioned]]

#### INV-114 — Adjustment-reversal-chain-depth

- **Statement:** Reversal of an adjustment is itself a new transaction that can be further reversed; the chain depth is unbounded by the schema (no "cannot reverse a reversal" limitation that creates orphaned states). Each reversal records the prior transaction it offsets and the reason.
- **Category:** structural
- **Confidence:** medium
- **Source:** billing-failures/stage-05 (via 24-billing-failures-index) "SAP IS-U adjustment-reversal cascade — cannot reverse a document that itself was an adjustment reversal"
- **Scope:** account_ledger, invoice_events
- **Rationale:** Documented SAP IS-U defect pattern; ledger correctness on operational corrections.
- **Related invariants:** [[INV-append-only-ledger]]

#### INV-115 — Tax-exemption-and-program-re-certification-deadlines

- **Statement:** Tax exemptions and program enrollments (PIPP, CAP, RAAF, etc.) with re-certification requirements are automatically flagged for renewal in advance of expiry; an expired certificate or enrollment reverts the customer to standard treatment without manual intervention. Application of an expired benefit to a billing period is a violation.
- **Category:** structural (workflow)
- **Confidence:** high
- **Source:** 11-taxes-and-gl-accounting.md; billing-failures/stage-04 "Universal-service / low-income rider enrollment not enforced … re-certification deadlines"
- **Scope:** customer flags, certificate tracking, program enrollment lifecycle
- **Rationale:** Tax-audit findings; cross-subsidy concerns.
- **Related invariants:** [[INV-tax-exemption-certificate-lifecycle]], [[INV-program-enrollment-lifecycle]]

#### INV-116 — Daily-LIHEAP-pledge-and-suspense-processing-SLA

- **Statement:** LIHEAP and agency pledges, plus unapplied-cash/suspense items, are processed against the customer's account within the jurisdiction's SLA (e.g., PA PROMISe Crisis pledges within 30 days). Aged-suspense and unprocessed pledges that result in wrongful disconnect are regulatory violations.
- **Category:** structural (workflow) + computational
- **Confidence:** medium
- **Source:** billing-failures/stage-08 "Payment in suspense not researched within SLA"; "Energy assistance and LIHEAP pledge processing failures"
- **Scope:** suspense ledger, agency pledge intake, collections engine
- **Rationale:** PA PROMISe rule; documented disconnect violations.
- **Related invariants:** [[INV-liheap-pledge-blocks-disconnect-during-hold]], [[INV-unapplied-cash-holding-discipline]]

#### INV-117 — Bill-to-envelope-binding-integrity

- **Statement:** Print/mail processes ensure that the bill content in an envelope matches the address printed on the envelope (OMR/IMb/barcode match); double-stuff, inserter misfeed, and content/envelope swap conditions are detected and quarantined. Any such mismatch is a PII breach event.
- **Category:** structural (operational)
- **Confidence:** medium
- **Source:** billing-failures/stage-07 (via 24-billing-failures-index) "Bill stuffed in wrong envelope … CCPA/NY SHIELD breach notification required"
- **Scope:** print/mail vendor integration
- **Rationale:** Privacy law; per-incident breach notification.
- **Review note:** Largely a vendor-side control. System-side invariant is "OMR/IMb match assertion is recorded on each bill" — framing question.

#### INV-118 — Bilingual-and-accessibility-delivery-honored

- **Statement:** Customer-elected language preferences and accessibility requirements (paper-required even with paperless, large print, Braille, bilingual notice obligations per state — e.g., CA AB 3254) are honored on every customer-directed communication. Notice rendered in the wrong language or inaccessible format is treated as not-served for regulatory purposes.
- **Category:** structural + computational
- **Confidence:** medium
- **Source:** billing-failures/stage-07 (via 24-billing-failures-index) "Bilingual obligation failure — CA AB 3254"; "Section 508/ADA/WCAG 2.1 AA violations"
- **Scope:** customer preferences, notice rendering
- **Rationale:** State law; disability law.
- **Related invariants:** [[INV-communication-log-completeness]], [[INV-regulated-notice-language-versioned]]

#### INV-119 — ACH-NOC-bank-info-update-window

- **Statement:** ACH Notice of Change (NOC) transactions received from the customer's bank trigger update of the stored bank account info within the NACHA-prescribed window (6 banking days); subsequent autopay drafts use the corrected info.
- **Category:** structural + computational
- **Confidence:** medium
- **Source:** billing-failures/stage-08 "ACH NACHA Notice of Change (C01/C02/C03) not actioned"
- **Scope:** payment methods, NACHA file ingestion
- **Rationale:** NACHA Operating Rules; non-update produces failed autopay → wrongful late fee.

#### INV-120 — Final-bill-after-pending-adjustments

- **Statement:** A final bill on account closure is issued only after all pending adjustments for the period have posted; a pending adjustment that posts after final-bill issuance must be added to the final bill as a corrected final or a separate post-closure invoice, never silently dropped.
- **Category:** structural (workflow) + computational
- **Confidence:** medium
- **Source:** billing-failures/stage-05 (via 24-billing-failures-index) "Final bill issued before pending adjustment posts — adjustment lands as separate post-closure invoice"
- **Scope:** account closure workflow, final-bill generation
- **Rationale:** Customer correctness on close; deposit refund disposition.

#### INV-121 — Postmark-date-discipline

- **Statement:** Where state rules treat postmark date as the timely date for payment (PA, OH, NY among others), late-fee assessment uses postmark date when available, not lockbox-receipt or bank-settlement date.
- **Category:** computational
- **Confidence:** medium
- **Source:** billing-failures/stage-08 "Postmark date vs. effective date mismatch"
- **Scope:** late-fee engine, payment effective-date handling
- **Rationale:** State PUC rules.

#### INV-122 — Combined-bill-allocation-correctness

- **Statement:** On combined gas/electric or gas/water bills (where multi-commodity tenant scope applies), payment allocation across services prevents one commodity from showing credit while another shows arrears that triggers disconnect notice on the paid service. Allocation rules are tariff-driven and consistent.
- **Category:** computational
- **Confidence:** low
- **Source:** billing-failures/stage-05 (via 24-billing-failures-index) "Commodity-allocation error on combined gas/electric"
- **Scope:** payment posting, multi-commodity tenant config
- **Rationale:** Wrongful disconnect risk; demarcated by tariff and PUC scope.
- **Review note:** Launch scope is gas-only; this is a "schema-supports-but-not-launch" invariant. Flag for expert as to whether it needs framing now or deferred.

---

### From application/database/schema.sql

#### INV-123 — Tenant-isolation-by-foreign-key

- **Statement:** Every customer/operational/financial row carries a `tenant_id` (NOT NULL, foreign-keyed to `tenants.id`). Cross-tenant access is structurally impossible if queries filter on `tenant_id` and FK constraints are honored. Tenant-namespaced UNIQUE constraints (e.g., `UNIQUE (tenant_id, customer_number)`) prevent identifier collision but allow same identifier across tenants.
- **Category:** structural
- **Confidence:** high
- **Source:** schema.sql — `tenant_id UUID NOT NULL REFERENCES tenants(id)` on customers (line 82), service_locations (line 297), meters (line 346), rate_schedules (line 700), invoices (line 1002), payments (line 1220), account_ledger (line 1312), and every other operational table
- **Scope:** all multi-tenant tables (~60 tables)
- **Rationale:** SaaS multi-tenant architecture; cross-tenant data leak is platform-existential.
- **Known failure modes if violated:** customer of tenant A sees data of tenant B
- **Related invariants:** [[INV-rls-row-level-security-policy]] *(if RLS is the enforcement mechanism)*

#### INV-124 — Customer-number-and-key-business-identifiers-unique-per-tenant

- **Statement:** Within a tenant, customer numbers, location numbers, meter numbers, invoice numbers, payment numbers, charge numbers, billing-run numbers, service-order numbers are unique. External-id (when set) is also unique per tenant. Sequence allocation is handled by `tenant_sequences` to avoid collisions.
- **Category:** structural
- **Confidence:** high
- **Source:** schema.sql — `UNIQUE (tenant_id, customer_number)` on customers (line 160); analogous on service_locations, meters, invoices, payments, adhoc_charges, service_orders, billing_runs, etc.; `tenant_sequences` table
- **Scope:** identifier-bearing tables
- **Rationale:** Predictable lookup, idempotent imports, regulator/customer-facing identifier stability.

#### INV-125 — Effective-date-bracketing-on-rate-and-rider-entities

- **Statement:** Rate items, rate schedule items, rate schedules, franchise fee rules, customer tax exemptions, and WNA zones all carry `effective_date` (NOT NULL) and optional `expiry_date` columns. The current value is determined by the row whose bracket contains "now" (or the bill period for historical lookups). The schema does not yet encode bi-temporal (transaction-time) columns — this is a known gap.
- **Category:** structural
- **Confidence:** high
- **Source:** schema.sql — rate_items.effective_date (line 759), rate_schedule_items.effective_date (line 778), rate_schedules.effective_date (line 712), franchise_fee_rules.effective_date (line 839), customer_tax_exemptions.effective_start (line 193), wna_zones.effective_date (line 871), wna_monthly_adjustments per-month uniqueness (line 894)
- **Scope:** rate engine reference data
- **Rationale:** Implements valid-time half of bi-temporality; cancel-rebill correctness for the valid-time-only flavor. Transaction-time (recorded_at + recorded_until) is required per Session A decision and is currently missing from these tables.
- **Related invariants:** [[INV-bi-temporality]], [[INV-rate-and-rider-date-effective-and-versioned]]
- **Review note:** Schema currently encodes uni-temporal; bi-temporal columns to be added per Session A decision. Invariant statement reflects target architecture.

#### INV-126 — Invoice-line-item-rate-snapshotted-by-value

- **Statement:** Each `invoice_line_items` row stores the applied rate as a numeric value (`rate NUMERIC(12,6)`) and the period coverage (`coverage_start`, `coverage_end`, `days_covered`, `days_in_period`, `partial_period_policy_applied`), not solely a foreign-key reference to a mutable rate item. The line item is self-contained for the dollar calculation it represents.
- **Category:** structural
- **Confidence:** high
- **Source:** schema.sql — invoice_line_items.rate, .usage_quantity, .gas_meter_factor, .gas_ccf_used, .gas_therms_billed, .gas_commodity_rate, .coverage_start/.coverage_end (lines 1086–1101)
- **Scope:** invoice_line_items
- **Rationale:** Avoids the "mutable reference" failure mode from 16-bi-temporality.md §4.1. Even if `rate_item_id` is followed, the value is right here on the line.
- **Related invariants:** [[INV-invoice-snapshot-completeness]], [[INV-bill-immutability]], [[INV-bi-temporality]]

#### INV-127 — Cancel-rebill-correction-rate-mode-explicit

- **Statement:** Every cancel-rebill billing run records its `correction_rate_mode` (`historical` | `run_default` | tenant-defined values) explicitly. Per-target overrides on `correction_run_targets.rate_date_mode` and `rate_date_override` let individual rebills opt into a different temporal lens than the run default. The rebill's temporal basis is never implicit.
- **Category:** structural
- **Confidence:** high
- **Source:** schema.sql — billing_runs.correction_rate_mode (line 937), correction_run_targets.rate_date_mode + rate_date_override (lines 988–989)
- **Scope:** billing_runs, correction_run_targets
- **Rationale:** Implements the "three flavors of cancel-rebill" from 16-bi-temporality.md §5.1; ensures bi-temporal-coordinate explicitness.
- **Related invariants:** [[INV-cancel-rebill-pure-function]], [[INV-cross-entity-temporal-coordinate-consistency]]

#### INV-128 — Invoice-rebill-lineage-explicit

- **Statement:** A rebill invoice references its predecessor via `replaces_invoice_id`; the voided/canceled invoice carries `voided_at`, `voided_by`, `void_reason_code`, `void_rebill_expected`. The chain from voided original → rebill is queryable forward and backward; voiding does not delete the original row.
- **Category:** structural
- **Confidence:** high
- **Source:** schema.sql — invoices.replaces_invoice_id, .voided_at, .voided_by, .void_reason_code, .void_rebill_expected (lines 1013, 1056–1060); invoice_type
- **Scope:** invoices
- **Rationale:** Bill immutability + cancel-rebill audit trail.
- **Related invariants:** [[INV-bill-immutability]], [[INV-cancel-rebill-uses-original-period-world]]

#### INV-129 — Read-supersede-pattern

- **Statement:** When a meter read is corrected, the new read references the old via `replaces_reading_id` and the old is marked superseded (`replaced_by_reading_id`). Reads are append-only at the row level; status changes are recorded but the original read row persists.
- **Category:** structural
- **Confidence:** medium
- **Source:** schema.sql — meter_readings.replaced_by_reading_id, .replaces_reading_id (lines 641–642); .status column
- **Scope:** meter_readings
- **Rationale:** Reads can be corrected post-acceptance; original must persist for audit. Implements valid-time supersede.
- **Review note:** Whether the schema treats reads as fully append-only or allows status mutation (`status TEXT` is mutable) is a framing question. Currently uni-temporal correction.

#### INV-130 — Billing-period-lock-on-meter-readings

- **Statement:** Once a meter reading is used to lock a billing period (`billing_period_locked = TRUE`, `locked_at`, `locked_by_billing_run_id`, `locked_by_invoice_id`), the read cannot be silently mutated; any subsequent correction triggers a correction workflow (`triggers_correction_workflow`).
- **Category:** structural
- **Confidence:** high
- **Source:** schema.sql — meter_readings.billing_period_locked, .locked_at, .locked_by_billing_run_id, .locked_by_invoice_id, .triggers_correction_workflow (lines 672–676)
- **Scope:** meter_readings, cancel-rebill workflow
- **Rationale:** Prevents silent post-bill mutation; enforces explicit correction-rebill path.
- **Related invariants:** [[INV-bill-immutability]], [[INV-read-supersede-pattern]]

#### INV-131 — Meter-deployment-lineage-tracked

- **Statement:** Meter deployments at service locations are tracked in `meter_deployments` with install/removal dates and reads; meter swaps record `replaces_meter_id` on the new meter; service-location moves recorded as new deployment rows. A meter's history at a location is reconstructable.
- **Category:** structural
- **Confidence:** high
- **Source:** schema.sql — meters.replaces_meter_id (line 398), meter_deployments table with install_date/removal_date/install_read_value/removal_read_value (lines 411–433)
- **Scope:** meters, meter_deployments
- **Rationale:** Meter-swap split calculation depends on deployment history; audit reproducibility.
- **Related invariants:** [[INV-meter-swap-split-calculation-within-period]]

#### INV-132 — Customer-credit-and-escheatment-tracking

- **Statement:** Customer credits track origin (payment, ad-hoc charge reversal, invoice credit), applied/remaining amounts, expiry, last activity date, and escheatment state (escheat_status, due_diligence_sent_at, escheated_at, jurisdiction). Unclaimed credits move through due-diligence and escheatment per state rules without silent forfeiture.
- **Category:** structural
- **Confidence:** medium
- **Source:** schema.sql — customer_credits with origin_type, status, escheat_status, due_diligence_sent_at, escheated_at, escheated_to_jurisdiction (lines 237–263); escheatment_events table (lines 1348–1365)
- **Scope:** customer_credits, escheatment_events
- **Rationale:** State escheatment law; unclaimed-property reporting.

#### INV-133 — Adhoc-charge-approval-threshold-captured-at-creation

- **Statement:** Ad-hoc charges that require approval capture the approval threshold *at creation time* (`approval_threshold_at_creation`), not at the current setting. Subsequent changes to the threshold policy do not retroactively change which historical charges were/were not within the originator's authority.
- **Category:** structural
- **Confidence:** medium
- **Source:** schema.sql — adhoc_charges.requires_approval, .approval_threshold_at_creation (lines 1165–1166)
- **Scope:** adhoc_charges
- **Rationale:** RBAC + audit; "what was the rule when this was done?" reproducibility.
- **Related invariants:** [[INV-audit-trail-subpoena-readiness]]

#### INV-134 — AI-action-audit-completeness

- **Statement:** Every AI-originated suggestion, tool call, and resulting state change is logged in `ai_audit_log` with user prompt, AI interpretation, result summary, entity changes (JSON diff), provider/model, token counts, cost, latency. AI-authored rows on operational tables (adhoc_charges.created_by_ai, service_orders.created_by_ai) link to the audit row via `ai_audit_id`.
- **Category:** structural
- **Confidence:** high
- **Source:** schema.sql — ai_audit_log (lines 1661–1685), ai_sessions, ai_suggestions, ai_tool_calls; adhoc_charges.ai_audit_id, service_orders.ai_audit_id
- **Scope:** AI layer
- **Rationale:** AI agency in regulated workflow must be fully accountable; supervisor/auditor reconstruction.
- **Related invariants:** [[INV-audit-trail-subpoena-readiness]]

#### INV-135 — Anomaly-detection-deduplication

- **Statement:** Anomaly detection produces deduplicated records keyed by `(tenant_id, dedup_key)`; recurring detections increment `recurrence_count` and update `last_detected_at` rather than producing duplicate rows. Resolution and assigned-user state attaches to the canonical anomaly row.
- **Category:** structural
- **Confidence:** medium
- **Source:** schema.sql — anomalies with `UNIQUE (tenant_id, dedup_key)` (line 1501), recurrence_count, first_detected_at, last_detected_at (lines 1487–1489)
- **Scope:** anomalies
- **Rationale:** Operator noise control while preserving recurrence signal.

#### INV-136 — Import-job-idempotency

- **Statement:** Import jobs (file ingestion) are idempotent: `(tenant_id, idempotency_key)` UNIQUE; same source file hash + key cannot create duplicate posting; replay-eligible via job re-submission.
- **Category:** structural
- **Confidence:** high
- **Source:** schema.sql — import_jobs with source_file_hash, idempotency_key, UNIQUE (tenant_id, idempotency_key) (lines 1565, 1566, 1589)
- **Scope:** import_jobs
- **Rationale:** Safe replay; vendor file delivery retry without duplication.
- **Related invariants:** [[INV-format-drift-tolerance-on-inbound-files]]

#### INV-137 — Billing-run-meter-once-per-run

- **Statement:** Within a single billing run, each meter appears at most once (`UNIQUE (billing_run_id, meter_id)`); the run's outcome for that meter (billed, skipped with reason, errored) is recorded on the single row. Re-runs are new billing-run rows, never duplicate within a run.
- **Category:** structural
- **Confidence:** high
- **Source:** schema.sql — billing_run_meters with UNIQUE (billing_run_id, meter_id) (line 976)
- **Scope:** billing_runs, billing_run_meters
- **Rationale:** Prevents double-billing within a cycle; clear audit trail.

#### INV-138 — Payment-method-token-uniqueness-and-PAN-absence

- **Statement:** Payment methods are stored by `(provider, provider_token)` UNIQUE — the token is the only identifier kept; no PAN is stored in the `payment_methods` schema (columns: last_four, card_brand, expiry_month/year, bank_name, account_type — no full PAN column exists).
- **Category:** structural (impossibility-proof candidate)
- **Confidence:** high
- **Source:** schema.sql — payment_methods (lines 1193–1216) with UNIQUE (provider, provider_token); no PAN column in schema
- **Scope:** payment_methods
- **Rationale:** PCI DSS by construction; the schema cannot hold a PAN.
- **Related invariants:** [[INV-pci-no-pan-in-cis]]

#### INV-139 — NSF-and-reversal-lineage-on-payments

- **Statement:** Payment reversals (NSF return, refund, void) reference the prior payment they offset (`nsf_original_payment_id`, `refunds_payment_id`); the NSF fee is materialized as an `adhoc_charge` referenced from `nsf_fee_charge_id`. Reversal chains are queryable; the original payment row is preserved.
- **Category:** structural
- **Confidence:** high
- **Source:** schema.sql — payments.nsf_date, .nsf_reason, .nsf_fee_charge_id, .nsf_original_payment_id, .refunds_payment_id, .reversed_at, .reversed_by (lines 1242–1252)
- **Scope:** payments
- **Rationale:** Append-only-style ledger semantics on the payment side.
- **Related invariants:** [[INV-append-only-ledger]], [[INV-nsf-and-ach-return-handling-per-code]]

#### INV-140 — Account-ledger-running-balance-derived

- **Statement:** `account_ledger.running_balance` is a derived value (current as of the most recent transaction); it does not retroactively update prior rows when a backdated transaction is inserted. Historical balance reconstruction reads transactions up to a target date, not the running_balance column.
- **Category:** structural
- **Confidence:** low
- **Source:** schema.sql — account_ledger.running_balance NUMERIC(12,2) (line 1319)
- **Scope:** account_ledger
- **Rationale:** Prevents silent mutation of historical balances; backdated transactions must trigger forward-recompute of subsequent running_balance values.
- **Review note:** Schema has running_balance as a column. Whether it's recomputed on every insert (correct) or stamped at insert time and never updated (also correct, as long as queries don't use it for historical answer) is a framing question. Flag for engineer review.

#### INV-141 — Meter-attribute-gaps-identified-as-invariants-pending-schema

- **Statement (gap):** Meters lack explicit `rollover_point`, `pressure_class`, `temperature_compensated` columns required by INV-022. Schema fields `dial_count`, `num_dials` partially substitute for rollover_point (rollover at 10^num_dials) but the explicit canonical column is missing. Premise/service_locations lack BTU zone, pressure zone, rate zone, weather station, tax_jurisdiction FKs required by INV-019 (only `inside_city_limits`, `franchise_city` text, and `wna_zone_id` on rate_schedules — not on the location itself).
- **Category:** structural (gap statement)
- **Confidence:** high
- **Source:** schema.sql — meters (lines 344–409) missing rollover_point and pressure-class; service_locations (lines 295–325) missing BTU zone FK, pressure zone FK, weather-station FK, tax-jurisdiction FK; rate_schedules.wna_zone_id is on the schedule not the location; HANDOFF.md "BTU zone, rate zone, pressure zone, weather station — don't exist yet"
- **Scope:** meters, service_locations
- **Rationale:** These invariants exist as domain rules; the schema does not yet enforce them. Pre-application-build hardening (per HANDOFF.md Session B/D) addresses this gap.
- **Review note:** This is a "schema doesn't yet encode invariant" finding, not a separate invariant. Listed here to make the structural enforcement gap explicit for the canonical document's gap section.

#### INV-142 — Communication-log-gap

- **Statement (gap):** Schema has `bill_messages` (per-bill informational messages) and a `customer_interactions` table (CSR-driven), but no general outbound communication log capturing every notice sent (disconnect notices, dunning notices, rate-change notices, regulatory-required communications) with timestamp, template version, rendered content, channel, delivery outcome. This gap blocks INV-090.
- **Category:** structural (gap statement)
- **Confidence:** high
- **Source:** schema.sql — bill_messages (lines 1416–1436) is targeting-config, not delivery log; customer_interactions (lines 209–234) is CSR-side; no notice/communication log table exists; CONTEXT.md noted gap
- **Scope:** communication log (gap)
- **Rationale:** Per INV-090, the schema must support the invariant; currently it does not.
- **Review note:** Gap finding, listed to make schema-enforcement gap explicit.

---

### From 31-texas-regulatory-compliance.md (launch-scope-specific)

#### INV-143 — Texas-sub-jurisdiction-flag-per-account

- **Statement (launch-scope: Texas):** Every Texas service account/location carries an explicit jurisdictional flag: `Incorporated` (inside city limits — municipality has original rate jurisdiction) or `Environs` (outside city limits — RRC has original jurisdiction). Tariff schedule lookup, rate change workflow, and franchise-fee applicability all key on this flag.
- **Category:** structural
- **Confidence:** high
- **Source:** 31-texas-regulatory-compliance.md §1.2 "Dual Jurisdiction: Municipal vs. Environs"; service_locations schema lacks an explicit Inc/Env enum (only `inside_city_limits` boolean and `franchise_city` text)
- **Scope:** service_locations, rate determination, tariff workflows
- **Rationale:** Texas Utilities Code; different rate schedules and approval paths.
- **Known failure modes if violated:** wrong tariff applied to Inc vs. Env customer; wrong appeal path on a rate change
- **Related invariants:** [[INV-premise-zone-assignment-complete]], [[INV-franchise-fee-traceable-to-jurisdiction]]

#### INV-144 — Texas-tariff-SOI-workflow-and-35-day-waiting-period

- **Statement (launch-scope: Texas):** Rate-increase tariff changes require Statement of Intent filing with the city, 4 consecutive weeks of newspaper notice, and a minimum 35-day waiting period before rates take effect. The system tracks SOI date, notice dates, hearing/suspension state, and effective date; rates cannot activate before completion of the prerequisite steps. Rate decreases follow the simpler tariff-filing-alone path.
- **Category:** structural (workflow) + computational
- **Confidence:** high
- **Source:** 31-texas-regulatory-compliance.md §2.4 "Rate Change Procedures"
- **Scope:** tariff change workflow, rate_schedules, rate_items effective dates
- **Rationale:** Statutory; rate activated before completing SOI is unauthorized.
- **Related invariants:** [[INV-rate-and-rider-date-effective-and-versioned]]

#### INV-145 — Texas-PGA-monthly-filing-prospective-only

- **Statement (launch-scope: Texas):** PGA factors are filed with RRC by the last business day of the month preceding effectiveness; new factor takes effect for bills rendered on and after the first day of the calendar month. Adjustments for a prior period are made **prospectively** (rolled into a future-period PGA), never as a retroactive recalculation of past bills under PGA mechanics.
- **Category:** computational + structural
- **Confidence:** high
- **Source:** 31-texas-regulatory-compliance.md §3.1 "Filing mechanics … Any adjustment for a prior period must be made prospectively"
- **Scope:** PGA workflow, deferred_gas_cost ledger (gap), billing engine
- **Rationale:** TX 16 TAC §7.5519.
- **Related invariants:** [[INV-pga-pre-load-with-future-effective-date]], [[INV-pga-deferred-account-accrual-with-carrying-cost]]

#### INV-146 — Texas-PSF-surcharge-cap-and-state-agency-exemption

- **Statement (launch-scope: Texas):** The Pipeline Safety Fee surcharge billed to customers cannot exceed $1.00 per service in aggregate; cannot be billed before LDC remittance to RRC; must be billed in the cycle(s) immediately following remittance; state-agency accounts are exempt; the surcharge itself is exempt from franchise fees, gas utility tax, and sales tax.
- **Category:** computational + structural
- **Confidence:** high
- **Source:** 31-texas-regulatory-compliance.md §3.4 "Pipeline Safety Fee (PSF) Surcharge"
- **Scope:** PSF surcharge rider, exemption flags
- **Rationale:** TX 16 TAC §8.201.

#### INV-147 — Texas-bilingual-notice-discipline

- **Statement (launch-scope: Texas):** Disconnect notices, new-customer information packets, and annual rights notices to Texas customers are produced in both English and Spanish. Default delivery is dual-language unless the RRC has granted an exemption for the specific tenant.
- **Category:** structural + computational
- **Confidence:** high
- **Source:** 31-texas-regulatory-compliance.md §4.2 "Bilingual Requirements … firm regulatory requirement, not optional"
- **Scope:** notice templates, communication log
- **Rationale:** RRC consumer-protection rule.
- **Related invariants:** [[INV-bilingual-and-accessibility-delivery-honored]]

#### INV-148 — Texas-bill-format-mandatory-elements

- **Statement (launch-scope: Texas):** Every Texas customer bill displays: meter read dates (begin/end), units billed (number + kind), rate schedule code, base bill before adjustments, adjustments total + per-unit amount for each adjustment (PGA, WNA, PSF, etc.), prompt-payment discount date, total amount due before/after discount, estimated-bill indicator (distinct marking when estimated). Bills missing any required element are not compliant.
- **Category:** structural + computational
- **Confidence:** high
- **Source:** 31-texas-regulatory-compliance.md §4.1 "Mandatory Bill Format Requirements"
- **Scope:** bill template, invoice rendering
- **Rationale:** 16 TAC §7.45 disclosure requirements.

#### INV-149 — Texas-actual-read-every-6-months

- **Statement (launch-scope: Texas):** An actual meter reading must be taken at least every 6 months per service location; estimated bills cannot substitute beyond this interval. After two consecutive months of inaccessibility, the utility sends a self-read postcard (if meter type permits). Estimated bills must be distinctly marked.
- **Category:** computational + structural
- **Confidence:** high
- **Source:** 31-texas-regulatory-compliance.md §4.3 "Estimated Billing Rules"
- **Scope:** estimation engine, read scheduling, meter_readings
- **Rationale:** 16 TAC §7.45.
- **Related invariants:** [[INV-consecutive-estimation-cap]]

#### INV-150 — Texas-estimated-bill-no-disconnect

- **Statement (launch-scope: Texas):** A Texas customer may not be disconnected for failure to pay an estimated bill that was not rendered pursuant to an approved meter reading plan (unless the utility was unable to read the meter due to circumstances beyond its control).
- **Category:** computational
- **Confidence:** high
- **Source:** 31-texas-regulatory-compliance.md §4.3, §5.1 "Bills that may NOT serve as the basis for disconnection: … Estimated bills (outside approved plans) when meter could not be read"
- **Scope:** collections engine, dunning_events
- **Rationale:** 16 TAC §7.45 consumer protection.
- **Related invariants:** [[INV-disconnect-eligibility-respects-jurisdictional-rules]]

#### INV-151 — Texas-disputed-amount-cap-on-required-payment

- **Statement (launch-scope: Texas):** When a customer disputes a Texas bill before delinquency, the customer cannot be required to pay the disputed portion exceeding their average usage (two-year same-period average) at current rates, until the dispute is resolved or 60 days from issuance. Collections on the disputed portion are suspended.
- **Category:** computational
- **Confidence:** high
- **Source:** 31-texas-regulatory-compliance.md §4.4 "Billing Disputes"
- **Scope:** disputes, collections engine, late fee engine
- **Rationale:** 16 TAC §7.45.
- **Related invariants:** [[INV-meter-dispute-suspends-collections-on-disputed-amount]]

#### INV-152 — Texas-disconnect-prerequisite-sequence

- **Statement (launch-scope: Texas):** Disconnect cannot proceed unless: (a) bill is delinquent (due date ≥15 days from issuance), (b) bill remains unpaid 5 working days after delinquency, (c) a Termination Notice (with required content) has been delivered ≥5 working days before disconnection. Missing any element invalidates the disconnect.
- **Category:** computational + structural
- **Confidence:** high
- **Source:** 31-texas-regulatory-compliance.md §5.1 "Standard Disconnection Prerequisites"
- **Scope:** collections engine, dunning_events
- **Rationale:** TUC §104.258 + 16 TAC §7.45.
- **Related invariants:** [[INV-collections-pipeline-step-completeness]]

#### INV-153 — Texas-no-disconnect-on-day-before-utility-closed

- **Statement (launch-scope: Texas):** Service may not be disconnected on a day, or on the day immediately preceding a day, when utility personnel are not available to receive payment and reconnect service (no disconnect Fridays if utility is closed Saturday).
- **Category:** computational
- **Confidence:** high
- **Source:** 31-texas-regulatory-compliance.md §5.2 "Weekend and Holiday Prohibition"; TUC §104.258
- **Scope:** disconnect scheduling, business calendar
- **Rationale:** Statutory; customer must be able to pay to restore service.

#### INV-154 — Texas-EWE-disconnect-prohibition

- **Statement (launch-scope: Texas):** During an Extreme Weather Emergency (previous day high ≤32°F + forecast ≤32°F for next 24 hours, per nearest NWS station for the customer's county), Texas residential customers cannot be disconnected; payment collection on the delinquent balance is deferred until after the EWE ends; the utility works with customer to establish a payment schedule.
- **Category:** computational + structural
- **Confidence:** high
- **Source:** 31-texas-regulatory-compliance.md §5.3 "Extreme Weather Emergency (EWE) Rules"; 16 TAC §7.460
- **Scope:** collections engine, weather feed, customer protection flags
- **Rationale:** RRC rule; AG civil penalty for violations.
- **Related invariants:** [[INV-bypass-conditions-evaluated-daily]], [[INV-disconnect-eligibility-respects-jurisdictional-rules]]

#### INV-155 — Texas-medical-hold-20-day-protection

- **Statement (launch-scope: Texas):** When a Texas residential customer submits a written request + licensed-physician written statement within 5 working days of delinquency, disconnect is prohibited for 20 days from receipt (or shorter agreed period); customer must sign an installment agreement for outstanding balance plus future bills.
- **Category:** computational + structural
- **Confidence:** high
- **Source:** 31-texas-regulatory-compliance.md §5.4 "Medical / Health Emergency Protection"
- **Scope:** medical certification record, collections engine
- **Rationale:** 16 TAC §7.45.
- **Related invariants:** [[INV-medical-certification-disconnect-hold]]

#### INV-156 — Texas-deposit-cap-and-waivers

- **Statement (launch-scope: Texas):** A required residential deposit cannot exceed 1/6 of estimated annual billings. Mandatory waivers apply to family-violence victims (with Texas Council on Family Violence certification) and residential applicants age 65+ (with no outstanding balance accrued in the last 2 years from same-service utility). A deposit cannot be required at all if the applicant meets the "good payment history" exception (was a customer within last 2 years, ≤1 late payment, no disconnect).
- **Category:** computational + structural
- **Confidence:** high
- **Source:** 31-texas-regulatory-compliance.md §§6.1–6.3
- **Scope:** deposit calculation, customer flags
- **Rationale:** 16 TAC §7.45 consumer protection.
- **Related invariants:** [[INV-deposit-amount-tied-to-credit-evaluation]]

#### INV-157 — Texas-deposit-interest-accrual-rules

- **Statement (launch-scope: Texas):** If a deposit is refunded within 30 days, no interest required. If retained more than 30 days, interest accrues retroactively to the date of deposit at the PUCT-set rate, paid annually or at refund. Interest stops accruing on the date of return/credit.
- **Category:** computational
- **Confidence:** high
- **Source:** 31-texas-regulatory-compliance.md §6.4 "Deposit Interest"
- **Scope:** deposits, interest accrual ledger
- **Rationale:** 16 TAC §7.45.
- **Related invariants:** [[INV-deposit-interest-accrual]]

#### INV-158 — Texas-deposit-automatic-refund-trigger

- **Statement (launch-scope: Texas):** A Texas residential deposit must be automatically and promptly refunded (with accrued interest) when (a) service is disconnected (applied first to unpaid balance, remainder refunded) OR (b) the customer has paid 12 consecutive residential bills without disconnection-for-nonpayment, with no more than 2 delinquent occasions, and is currently not delinquent. This is mandatory, not discretionary.
- **Category:** computational + structural (workflow)
- **Confidence:** high
- **Source:** 31-texas-regulatory-compliance.md §6.5 "Deposit Refund — Mandatory Automatic Trigger"
- **Scope:** deposit refund workflow, collections engine
- **Rationale:** 16 TAC §7.45.
- **Related invariants:** [[INV-deposit-interest-accrual]]

#### INV-159 — Texas-meter-test-rules

- **Statement (launch-scope: Texas):** A customer-requested meter test is free of charge if no test has been performed for the same customer at the same location in the previous 4 years; otherwise the fee cannot exceed $15 (or tariffed fee). If the meter is more than nominally defective (>2.0% deviation), any fee charged must be refunded.
- **Category:** computational + structural
- **Confidence:** high
- **Source:** 31-texas-regulatory-compliance.md §7.2 "Meter Testing"
- **Scope:** meter test workflow, meter_test_disputes (gap)
- **Rationale:** 16 TAC §7.45.

#### INV-160 — Texas-meter-error-rebill-bounds

- **Statement (launch-scope: Texas):** If a meter test reveals >2.0% deviation, the utility corrects previous readings for the shorter of (a) the last 6 months or (b) the time since the last test. If the meter failed to register entirely, the utility may charge for unmetered usage for up to 3 months prior to discovery, based on comparable prior periods.
- **Category:** computational
- **Confidence:** high
- **Source:** 31-texas-regulatory-compliance.md §7.3 "Bill Adjustments for Meter Error"
- **Scope:** rebill engine, cancel-rebill
- **Rationale:** 16 TAC §7.45.
- **Related invariants:** [[INV-backbilling-cap-per-jurisdiction]] (12-month general TX backbill cap is a separate, broader rule)

#### INV-161 — Texas-BTU-reference-conditions

- **Statement (launch-scope: Texas):** For Texas gas billing, the standard reference conditions are: temperature base 60°F, pressure base 14.65 psia, on gross-real-dry basis. Billing in CCF, Mcf, therms, MMBtu/Dth all supported; conversion uses these reference conditions.
- **Category:** computational
- **Confidence:** high
- **Source:** 31-texas-regulatory-compliance.md §7.4 "BTU Reference Conditions (Texas)"
- **Scope:** consumption calculation, unit conversion
- **Rationale:** 16 TAC §7.45 industry-standard reference.
- **Related invariants:** [[INV-volume-to-energy-formula-correctly-composed]]

#### INV-162 — Texas-no-disconnect-for-stale-underbilling-or-meter-fault

- **Statement (launch-scope: Texas):** A Texas customer cannot be disconnected for: a previous occupant's delinquency, merchandise/non-utility charges, a different utility service type (unless on the same bill), underbilling from rate misapplication more than 6 months prior, underbilling from faulty metering (except tamper), or estimated bills outside an approved plan.
- **Category:** computational
- **Confidence:** high
- **Source:** 31-texas-regulatory-compliance.md §5.1 "Bills that may NOT serve as the basis for disconnection"
- **Scope:** collections engine, disconnect eligibility
- **Rationale:** 16 TAC §7.45.
- **Related invariants:** [[INV-disconnect-eligibility-respects-jurisdictional-rules]], [[INV-collections-pipeline-step-completeness]]

