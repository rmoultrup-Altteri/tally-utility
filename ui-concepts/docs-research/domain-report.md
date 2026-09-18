# TallyUtility — Domain Report for First-Iteration UI

Prepared for the UI builder. Everything here is sourced from the TallyUtility knowledge base and
cited by path. Read §3 (screens) and §5 (vocabulary) first if you are building.

---

## 0. Source paths — correction and orientation

**The brief's wiki path is wrong.** `/Users/ryanscomputer/code/LLM-wiki/projects/TallyUtility/` does
not exist — `LLM-wiki/` contains only `tools/`. The TallyUtility knowledge base is the repo at:

```
/Users/ryanscomputer/code/gas-billing-memory/
├── CONTEXT.md
├── knowledge/          01-25 domain files, glossary.md, billing-failures/
├── application/        feature-list.md, kyle-decisions-*.md, invariants, schema plans
└── marketing/          26-30 persona files, sales research
```

All relative paths below are relative to that root. Absolute paths outside it are given in full.

**Files that matter most for UI work:**

| Path | Why |
|---|---|
| `application/feature-list.md` | ~350 features across the 18 stages, each with priority + schema status |
| `application/kyle-decisions-2026-09-03-topic8-cck15.md` | **Locked** rulings T8-1..T8-3: search shape, favorites, dashboard composition |
| `application/kyle-decisions-2026-09-03-topic8-dashboard-composition.md` | **Locked** rulings T8-4..T8-8; supersedes part of T8-3. The dashboard spec. |
| `knowledge/07-billing-calculation.md` | The canonical 16-step billing pipeline, proration, rounding, cancel-rebill, MIMO |
| `knowledge/18-usage-temperature-overlay-feature.md` | The portal chart, in depth. Explicitly a v1 feature and the demo lead. |
| `knowledge/glossary.md` | Every acronym with a definition. Hand this to whoever writes label strings. |
| `knowledge/02-tariffs-rates-riders.md` | Rate schedule taxonomy and bill component building blocks |
| `knowledge/05-weather-normalization.md` | The four WNA formulas and their parameters |
| `knowledge/03-pga-gas-cost-recovery.md` | PGA mechanics, deferred account, true-up, operational workflow |
| `knowledge/09-credit-collections-disconnects.md` | Collections pipeline, disconnect rules, relight, bankruptcy |
| `knowledge/13-gotchas-and-lessons.md` | The operational traps that generated most of the schema gaps |
| `/Users/ryanscomputer/code/tally-utility/CONTEXT.md` | Project orientation and the guiding invariants |

**Build target.** `/Users/ryanscomputer/code/tally-utility/ui-concepts` is a bare `create-next-app`
scaffold — `app/layout.tsx`, `app/page.tsx`, `app/globals.css`, and empty `components/`, `lib/`,
`fixtures/`, `schemas/`, `styles/`. Its `AGENTS.md` warns that the installed Next.js version has
breaking changes relative to training data and points at `node_modules/next/dist/docs/`.

**There is already a mockup queue, and none of it is built** (`kyle-decisions-2026-09-03-topic8-dashboard-composition.md`, Part 5):

1. Dashboard (composition fully specified by T8-1 … T8-8)
2. Needs Attention drilldown page
3. Single-invoice void initiation modal
4. Bulk void modal with default reason + per-row override
5. Correction diff view (Phase 8 review gate)

---

## 1. Invariants the UI must never contradict

From `/Users/ryanscomputer/code/tally-utility/CONTEXT.md`, "Guiding Principles". These are not
preferences; violating them in the UI makes the product wrong.

- **No hard deletes** on any financial or operational record. Soft delete with marker and reason
  only. There is no trash-can icon that destroys anything.
- **Bills are immutable.** Corrections happen through cancel-rebill, never an in-place edit. No
  "edit invoice" affordance may exist anywhere.
- **The ledger is append-only.** Reversals are new transactions that offset prior ones. A reversal
  row is a row, not the absence of one.
- **Every rate, rider, factor and rule is date-effective.** "Current value only" anywhere in the
  system is a bug. Any rate displayed needs an effective date beside it.
- **Audit trail must be subpoena-ready** — complete, reproducible, permanent. PUC investigations
  happen.
- **Cancel-rebill uses the original period's world** — historical rates, BTU factors, WNA inputs,
  tax rates; not today's values.
- **Gas-native first.** BTU correction, PGA, WNA, cold-weather rules and relight workflows are
  first-class features, not configuration of a generic utility model.

One more, from the dashboard rulings and worth generalizing: **a silent financial misstatement must
be prevented by the query source or the control, never by operator awareness.**

---

## 2. Personas and their daily job-to-be-done

Source: `marketing/26-persona-gm-director.md` … `marketing/30-persona-csr-manager.md`. Each file
covers four meter-count bands (sub-5K, 5K–25K, 25K–75K, 75K–150K) with the same five dimensions:
beliefs, motivations, fears, desires, problems solved. At the low end of the band the first three
personas collapse into one or two actual human beings.

### Billing Analyst / Billing Supervisor — the primary UI user
`marketing/29-persona-billing-analyst.md`

"The person who actually runs the billing cycle. They know more about how the current system works —
and how it fails — than anyone else in the organization… They are the hardest audience to impress
and the most valuable ally to win."

**JTBD:** run the cycle clean, and be able to explain any number on any bill to anyone who asks.

**Daily:** work the read-validation queue → work the pre-mail exception queue before the print-vendor
cutoff → enter effective-dated PGA factors → configure rate changes from a PUC order → run
cancel-rebills → reconcile to the GL.

**Their fears, in their own words** (design against these directly):
- "A rate change configuration error that overbills 15,000 customers before anyone notices."
- "A PGA factor applied to the wrong month in a rebill scenario because the system doesn't snapshot
  historical inputs."
- "Estimation streaks hitting the state regulatory cap before they've noticed — and then getting a
  PUC complaint."
- "A cancel/rebill that looks correct on screen but has orphan transactions in the GL that audit
  catches later."
- "A wrong bill going out to the mayor, a council member, or the GM's neighbor." (sub-5K band)
- "A regulatory subpoena for bills from 2019 that can't be reproduced because the system mutes or
  overwrites historical data." (75K+ band)

**Their desires, in their own words:**
- "A pre-mail exception report that automatically flags bills that look statistically wrong — before
  they go out."
- "A cancel/rebill that clearly shows what changed and why — not a black box that produces a new
  number."
- "A tariff sandbox where they can test a change against real data before applying it to production."
- "Visual tariff inspector — a non-engineer-readable trace of exactly what formula applied to what
  consumption for any bill."
- "Point-in-time billing query — reproduce any bill on any past date in three clicks."
- "Canary accounts billed every cycle and automatically reconciled against expected values."
- "Bulk operations — adjust 200 accounts in one action with an approval gate, not account by account."

At 25K+ meters: "They know what bi-temporality means, or would recognize it immediately if
explained." Their professional pride is tied to running a clean cycle.

### CSR / CSR Manager
`marketing/30-persona-csr-manager.md`

**JTBD:** answer "why is my bill so high" in 90 seconds without switching systems. This is *the*
call, and it spikes in January and February — "the most exhausting weeks of the year."

**Beliefs worth quoting:** "The multi-screen CSR experience is the root cause of most customer
satisfaction problems — not the policies, the tools." "Customer complaints are almost always caused
by a bill they don't understand, not a bill that's actually wrong." "A CSR who can answer 'why is my
bill high' in 90 seconds with one chart is worth more than five who can't."

**Desires:** one screen with everything; the daily-usage-plus-temperature graph in both the CSR
workspace and the customer portal; a new CSR productive in days not weeks; a portal that handles
address change, autopay, e-bill and payment without a phone call.

The KB reports roughly a **5x call-time reduction** on the high-bill call when the chart exists, and
Bidgely case studies showing 30%+ reductions in high-bill complaint volume
(`knowledge/18-usage-temperature-overlay-feature.md` §5).

### Utility Director / GM
`marketing/26-persona-gm-director.md`

"The top-level decision maker… At smaller utilities they are also the owner of the billing outcome
personally — there is no layer of management between them and the front page of the local
newspaper."

**JTBD:** know the cycle is healthy; be able to answer a council member or the PUC. Weekly rather
than daily. Wants a board-reportable cycle dashboard.

### CFO / VP Finance
`marketing/27-persona-cfo.md`

"The financial gatekeeper and revenue assurance owner… usually been burned by a prior technology
project… billing accuracy is a financial controls issue for them — not just an operations issue."

**JTBD:** AR aging drillable to account level without filing an IT ticket; a GL export that balances
to zero variance; bad-debt and write-off summaries; board reporting.

### Field Tech
A required role in `application/feature-list.md` Stage 2; the mobile workflow itself is flagged as a
schema gap in Stage 18b.

**JTBD:** work the day's service orders. Meter reads with GPS and photo capture, meter change-outs,
investigations, leak calls, final reads, disconnects — and **relight**.

Relight is the constraint that shapes any field UI
(`knowledge/09-credit-collections-disconnects.md:76-86`): a technician **must be on site**; a
**pressure test / leak check** is required before gas flows; **pilot lights and appliances** need
manual relighting on older equipment; the **customer must be home** — gas can't be left on
unattended; PHMSA rules dictate the procedure. Consequence: **every reconnect is a truck roll**, and
customer scheduling is required — you cannot send a tech blindly.

### IT Director
`marketing/28-persona-it-director.md`

"The technical gatekeeper who controls the architecture decision even when they don't control the
budget… will own the CIS post-implementation for 10+ years."

**JTBD:** evaluate, then survive cutover. SSO/SAML/OIDC, a versioned REST or GraphQL API, webhooks on
every billing lifecycle state change, per-tenant API keys, and **parallel-run reconciliation** — run
the new and old billing systems side by side for a cycle and reconcile bill-level differences. Not a
daily user.

---

## 3. The 18 pipeline stages

Source: `application/feature-list.md` headings. The file has 18 numbered stages plus an "18b" and a
"19". Priority and schema-status columns in that file tell you what is `required` vs `nice-to-have`
and what has schema support today.

1. **Tenant / Utility Setup** — each LDC is an isolated tenant; billing policy config (partial-period
   policy, payment allocation strategy, overpayment handling, credit application timing), void/rebill
   policy, per-tenant number sequences with prefix and padding, subscription tier, gas-only UI gating
   at launch.
2. **User Management & Permissions** — roles (admin, billing operator, CSR, read-only, field tech),
   approval thresholds per role, audit trail of every user action that modifies financial data. RBAC
   is currently a single `role` text column — fine-grained permissions are a schema gap.
3. **Customer & Account Management** — identity and ID verification, multiple named contacts with a
   can-make-changes flag, preferred language, separate billing address, owner-vs-tenant with landlord
   linkage and landlord fallback service, security deposit, tax exemption with certificate expiry,
   do-not-disconnect, billing hold, customer interaction/call log, community/MDU grouping.
4. **Service Locations & Premises** — premise ≠ account and persists after account closure; geocode,
   parcel ID, location type, **inside/outside city limits** (drives franchise fee), franchise city,
   billing cycle assignment, and the four gas-critical zone assignments that are current schema gaps:
   **rate zone, BTU zone, pressure zone, weather station**, plus tax jurisdiction.
5. **Meter Management & Deployment** — meter master (number, manufacturer, model, serial), physical
   attributes (size, CFH capacity, dial count, seal number), **register configuration (multiplier,
   num dials, rollover point)**, temperature-compensation flag, lifecycle status, deployment history
   with install and final reads, swap lineage (`replaces_meter_id`), `meter_factor` and
   `gas_btu_factor`, accuracy test history and next-test-due, AMI endpoint and sync status,
   estimation block, meter photos with GPS and AI extraction.
6. **Read Routes & Cycle Management** — route definition (code, frequency, typical read day, expected
   meter count), meter sequence within route, assigned reader, billing cycle definition (read day,
   bill day, due-days-after-bill), read cycle instance per period with progress counters, per-meter
   assignment and skip reason, handoff to a billing run.
7. **Meter Read Ingestion & Validation** — manual entry, AMR/AMI file import with **idempotency**
   (same file resubmitted must not duplicate), read type and reading purpose classification,
   tolerance-based validation, estimation with consecutive-estimate limits, tamper detection, access
   status / skip codes / trouble codes, read disputes with collections suspension, reads **locked to
   the billing run** once billed, service-transition (simultaneous move-out/move-in) reads.
8. **Usage Calculation** — raw volume `(end_read − start_read) × multiplier`, then **pressure factor
   Fp**, **temperature factor Ft**, **supercompressibility Fpv** where applicable, then **BTU factor
   by zone and period** → therms. Every factor date-effective; a period spanning two months may need
   two factor sets. Also sewer-from-water calc and winter-average capping for the non-gas commodities.
9. **Bill Calculation & Tariff Engine** — rate schedule version determination, customer charge and
   distribution charge, block/tiered rates, demand charge on MDQ or contract demand with ratchet,
   **rider application in topological DAG order**, WNA, PGA, franchise fee, minimum bill, proration.
   The strategic core of the product.
10. **Pre-Mail Audit & Bill Validation** — statistical high/low/zero/negative-bill detection,
    absolute-baseline cross-checks against year-ago and class average, exception auto-classification,
    assignment and aging with escalation SLAs, resolution requiring reason code and notes,
    **backbilling cap enforcement before posting**, dry-run billing runs. Nothing mails until the
    queue is clear.
11. **Invoice Generation & Delivery** — invoice plus line items, invoice type (regular / correction /
    final / special), tax breakdown by jurisdiction, estimated-read flag and count, dunning stage,
    invoice event audit log, consolidated parent/child invoices for multi-location customers, PDF and
    retention, delivery method with confirmation tracking and paper fallback on bounce, print/mail
    vendor batch file, bill messages, void with reason, cancel-rebill, regulated notice language.
12. **Payment Processing & Posting** — channels (walk-in, portal, IVR, lockbox, ACH, bank bill pay,
    walk-in cash agent, in-office, agency pledge), tokenization (never store PAN), autopay with
    failure tracking, lockbox and NACHA file ingestion, **ACH return codes each with a distinct
    workflow**, NSF reversal plus returned-payment fee, payment application per configurable posting
    order, unapplied cash / suspense resolution, refunds and reversals, deposit tracking.
13. **Adjustments, Corrections & Cancel-Rebill** — ad-hoc charges with approval threshold, void and
    waive, bulk adjustment with approval gate, customer credit pool with origin type and expiry,
    **append-only account ledger with running balance**, cancel-rebill with historical-input
    correctness and an explicit balanced financial delta, backbilling cap at adjustment time, meter
    accuracy test rebill, deposit interest and refund.
14. **Collections & Disconnection** — aging and dunning event log, configurable pipeline step
    sequence, jurisdiction-parameterized notice timing and content, **bypass conditions engine
    evaluated daily**, cold weather moratorium, NWS temperature hold, medical certification hold,
    third-party notification, senior/disabled extended grace, bankruptcy automatic stay with
    pre/post-petition split, disconnect work orders with photo documentation, reconnection SLA,
    **gas relight workflow**, write-off, agency placement, escheatment of unclaimed credits.
15. **Customer Portal / Self-Service** — authenticated per-account portal (mobile-responsive, not a
    native app initially), bill view and download, online payment, autopay and e-bill enrollment,
    usage history, **the daily usage + temperature overlay graph**, move-in/move-out request, contact
    and communication-preference management, SMS/email opt-in.
16. **Reporting & Regulatory Compliance** — revenue by class, AR aging drillable without an IT ticket,
    bad debt and write-off summary, collections funnel, **PGA deferred balance and amortization
    schedule**, WNA annual true-up, DSIC/ISRS quarterly cap, franchise fee remittance by city, tax
    liability by jurisdiction, GL posting journal export, self-service ad-hoc reporting with Excel
    export, PHMSA / EIA Form 176 / FERC Form 2 extracts, backbilling-cap compliance, disconnect-notice
    compliance, cold-weather moratorium log, estimated-read streak report, subpoena-ready per-account
    history export.
17. **Integrations** — email/SMS notification, proactive alerts (bill-ready, high-usage,
    payment-due, disconnect-warning, bill-shock-before-mail), per-account communication log, tax
    engine (Avalara/Vertex), GL/ERP, AMI/MDM ingestion with format versioning and replay, AMI vendor
    adapters (Itron, Sensus/Arcadian, Honeywell/Elster, Landis+Gyr), print/mail vendor (DATAMATX,
    Output Solutions, Kubra), IVR and payment gateway, credit bureau, **NWS/NOAA weather**, GIS,
    public REST/GraphQL API with webhooks and per-tenant API keys, EDI X12 (phase 2).
18. **AI / Operational Intelligence** — AI session and cost tracking, full AI audit log (prompt,
    interpretation, result), **AI suggestions on a propose → pending → reviewed → executed workflow**
    with expiry and supersession, tool-call logging, `created_by_ai` attribution on records,
    anomaly detection with dedup key, recurrence counting, severity, confidence, estimated impact,
    assignment and resolution, AI meter-photo register extraction.

**18b — Admin, Configuration & Import.** Bulk legacy-CIS import (customers, meters, reads, billing
history) with reusable mapping templates, dry-run, per-row validation, error-handling policy,
idempotency by file hash, row-level status and dependency ordering. Service order management with
types (connect, disconnect, reconnect, meter change-out, investigation, leak, re-read, final-read),
parent/child hierarchy, and triggered charges/readings. Field tech mobile workflow (gap).

**19 — Implementation, Migration & Support.** Migration toolkit for NISC, Cayenta/Harris, Tyler,
Oracle CC&B, CUSI. **Parallel billing run** — run the new system alongside legacy for a full cycle
and reconcile bill-level differences. Training sandbox with anonymized data. All configuration
without custom code.

---

## 4. The screens

Ten screens. Three of them are **already specified by locked domain-expert decisions** (Kyle
Shaffer, implementer Ryan) — build to spec rather than inventing:

- `application/kyle-decisions-2026-09-03-topic8-cck15.md` — T8-1 (search shape), T8-2 (favorites),
  T8-3 (dashboard composition, partly superseded)
- `application/kyle-decisions-2026-09-03-topic8-dashboard-composition.md` — T8-4 … T8-8, and the
  authoritative dashboard element list in its Part 2

### Global chrome (locked — T8-1, T8-2)

- **Jump-to-record quick-find in the page header, present on every page.** Single input, typeahead,
  no mode switch, no criteria builder. **Match fields, v1, exactly five:** customer name, account
  number, meter number / serial, service address, invoice number. When a term matches more than one
  record, the operator lands on the relevant record list page with the term pre-applied — that is
  the only connection between search and filtering.
- **Filtering lives on record list pages as column filters.** There is no standalone advanced-search
  screen in v1. Rationale: "find this customer, they're on the phone" is the dominant operator
  search and is fully served by jump-to-record; multi-criteria retrieval is a reporting need.
- **Favorites cover reports, record lists and saved searches only.** Nothing record-level —
  individual customer, meter, location and invoice records are **not** favoritable, and there is no
  recents list. A saved search and a saved filtered view are **one concept**; implement a single
  named-view object, not two.
- **Nav sections** (assumed for the mockup, explicitly not a ruling): Dashboard, Customers,
  Locations, Meters, Reads, Billing Runs, Invoices, Payments, Reports, Admin.

---

### Screen 1 — Billing Operations Dashboard

**Primary persona:** Billing Analyst. The Utility Director reads it over their shoulder.

**Contents — this is the locked element list** (`kyle-decisions-2026-09-03-topic8-dashboard-composition.md`, Part 2):

**1a. Three severity portlets — Critical / Medium / Low.** Capped at six type-rows each, with a
"+N more" row. **Placement is determined by ITEM TYPE, not by row-level severity (T8-4).**

Why this matters and must not be "improved": several portlet item types carry no severity column at
all — held invoices are `invoices.status = 'held'`, failed calculations are
`billing_run_meters.outcome = 'failed_calculation'`, delivery failures are
`invoices.delivery_failed_reason`. A severity-driven placement would require inventing a synthetic
severity for these with no source of truth. Also the two existing severity scales do not align —
`anomalies.severity` is low/medium/high/critical while `alerts.priority` is low/normal/high/urgent —
so collapsing them into three portlets would bury a mapping decision in query code. And counts must
be explainable: under row-level placement, the same anomaly type lands in different portlets
depending on what the detector scored, and an operator cannot answer "why is this Critical today and
Medium yesterday."

Row-level severity is used for **one thing only: the default sort order inside the drilldown list.**
Severity does not escalate with age in v1. The item-type → portlet map is tenant-overridable
configuration with hardcoded defaults.

**1b. Revenue pair (T8-5).** Two figures side by side, **calendar month-to-date**, each with a small
prior-month same-day comparator beneath it.

| Figure | Basis |
|---|---|
| **Billed, net of voids** | Invoices with `invoice_date` inside the window. **Voids subtract at their void date, not at the original invoice date.** |
| **Collected** | Payments by posting date. |

**No ratio, percentage or delta is rendered between Billed and Collected.** The gap itself is the
operator signal. Rationale: payments arriving this month are largely against last month's invoices,
so any percentage between them would be read as a collection rate by every operator who saw it —
"leaving it out is cheaper than explaining it forever."

Void-date netting rationale: subtracting a void at the original invoice date silently restates a
closed month every time a correction runs. An operator who reported August revenue on September 1
would find a different August figure on September 15.

Accrued revenue is **not** a dashboard figure — accrual is a report, never a row.

**1c. AR aging strip (T8-6, T8-7).** Buckets **current / 30 / 60 / 90+**. **Dollars are the primary
figure; account count is a secondary figure on each bucket.** The 90+ bucket carries a visual flag
treatment. Account count is in because it is the number that sizes disconnect workload and the
number that will expose a bad AR source fastest.

**Aging is by INVOICE, not by customer.** A customer with unpaid invoices of different ages appears
in **more than one bucket** — that is intended, and the row carries a multi-bucket marker (e.g.
"3 buckets") so the operator understands why the same name recurs. The rejected alternative (bucket
each customer by their oldest unpaid invoice) reads more cleanly but breaks reconciliation: the sum
of the drilldowns would no longer equal the tile, which surfaces the first time anyone reconciles AR
against the GL, and at that point the dashboard is the thing that gets distrusted.

Each bucket is clickable into a filtered account list. **The drilldown lists must sum back to the
tile dollars — that is the acceptance test, not a nice-to-have.**

**Drilldown columns (v1):** customer name · account number · balance in *this* bucket · oldest unpaid
invoice date · days past due · disconnect-protection flag · collections status.

Source hazard carried forward and still binding: the AR tile must be sourced **independently** of
`compliance_statistics` or any view carrying `WHERE status IN ('active','final_billed')`, because a
customer moved to `status='collections'` drops out of it entirely — the aging buckets would
systematically understate exactly the population aging exists to surface.

**1d. Tariff rate card strip (T8-8).** Shows the rates a selected schedule **actually billed at**,
with a **drift marker** against the current effective rate.

The basis is load-bearing: the strip reads **as-billed** values from `invoice_line_items.rate` for
the **last posted run**. It does **not** read live configuration
(`rate_schedule_items.rate_override` / `rate_items.current_rate`) as the primary figure. The current
effective rate appears **only where it differs**, as a drift marker on that row.

Why: "current tariff rate" and "the amount used to bill the last run" are different datasets that
agree only if nothing changed since the run posted — and for a gas tenant they routinely will not,
because GCA and WNA carry `update_frequency = 'monthly'`. An operator loading October's gas cost
adjustment immediately makes a live-config tile misdescribe September's bills. **The drift marker is
a feature, not a caveat: a rate that moved after a run posted is a correction-run trigger.**

Three consequences, all ruled:
1. **A schedule selector is required** — there is no single "rate by item"; the same Customer Charge
   is $18 on one schedule and $21.95 on another via `rate_schedule_items.rate_override`. One schedule
   at a time, defaulting to the tenant's highest-volume schedule, with a dropdown and a link to the
   full rate card page.
2. **Tiered items show a bracket count, not a rate** — `calculation_type = 'tiered_usage'` items hold
   brackets in `tier_config` and have no single rate. The row reads as a bracket count linking to the
   full card.
3. **The strip is strictly read-only.** Rate editing stays on the rate schedule page with its
   effective-dating. It does not become an editing surface one click from the dashboard.

**1e. Header quick-find** and **1f. Favorites** per the global chrome above.

**Key interaction:** triage. Click a portlet row or an AR bucket to drill in.

**Deferred to v1.1, not dropped:** the upcoming-billing-runs strip (displaced by the rate card, not
rejected on merit), a recent-activity feed, and KPI metrics beyond revenue/AR (excluded because the
definitions aren't agreed, not because rendering is hard — the reports module defines metrics first).

**Domain concepts surfaced:** as-billed vs live configuration; monthly-cadence gas riders; AR aging
basis; void timing and month immutability.

---

### Screen 2 — Needs Attention / Pre-Mail Exception Queue

**Primary persona:** Billing Analyst. This is the screen they live in on bill day.

**Contents.** Every flagged bill in the current run, held before anything mails. Exception types
from `knowledge/07-billing-calculation.md:153-163`:

- High-bill flag (e.g. > 2.5× rolling average)
- Zero bill (possible meter issue)
- Negative bill (possible prior-period overcharge now reversing)
- Consecutive estimates exceeding policy
- Usage out of tolerance (high or low)
- Significant rider true-up producing customer impact
- Missing CSR-required approval on a rebill

Plus, from the billing-failures catalog: **absolute-baseline cross-checks** against the year-ago
period and the rate-class average — *not* just relative tolerance, which the KB names the
"mass-error blind spot" (a systematic error that shifts the whole distribution passes a relative
check). Plus **backbilling cap violations** and missing required regulatory disclosures.

**Row fields:** account number · customer name · service address · rate schedule · bill amount ·
prior period amount · same period last year · % variance · therms this period · therms prior ·
estimated-read badge · consecutive-estimate count (n of cap) · exception type · severity · assigned
reviewer · age / SLA remaining.

**Key decision:** resolve, hold, or release. **Resolution requires a reason code and free-text
notes** — audit trail. **All billing exceptions must be resolved before bills can be posted or
mailed**, so the screen needs a visible "N unresolved / cannot post" state and a print-vendor
deadline countdown (print vendors have hard cutoffs; missing one delays the whole cycle).

**Domain concepts surfaced:** pre-mail review as a formal internal control; exception aging and
escalation SLAs; estimation streaks against state caps; backbilling caps (NY 4 months per PSL §41 as
amended 2024, CA 3 months, TX 12 months); canary accounts reconciled expected-vs-actual each cycle.

---

### Screen 3 — Bill Detail with Tariff Inspector

**Primary persona:** Billing Analyst. CSR read-only.

This is the analyst's most-requested capability, named in their persona file: "Visual tariff
inspector — a non-engineer-readable trace of exactly what formula applied to what consumption for
any bill" (`marketing/29-persona-billing-analyst.md:108`, restated at :114).

**Contents.** The invoice rendered as the customer sees it, and beside it an expandable **formula
trace per line**, following the canonical pipeline order from
`knowledge/07-billing-calculation.md`:

```
start read, end read, read dates, read method
  → rollover adjustment, if end_read < start_read:
        raw_volume = (rollover_point − start_read) + end_read
  → meter-swap split, if a swap fell inside the period:
        two segments, each with its own factors
  → × meter multiplier            (the one effective on the read date)
  → × pressure factor    Fp[period]
  → × temperature factor Ft[period]      (non-temperature-compensated meters)
  → × supercompressibility Fpv[period]   (high-pressure industrial only)
  → × BTU factor [zone, period]
  = therms billed

  → Customer Charge               (prorated per the tariff's own rule)
  → Distribution Charge           therms × $/therm
  → Block / tier allocation       therms split across breakpoints in order
  → Demand Charge                 $/Dth × MDQ or contract demand, ratchet applied
  → Infrastructure riders         DSIC / ISRS / PRP, applied to distribution
  → WNA                           per-customer, in season
  → PGA                           therms × pga_rate[period] + true-up adder
  → Program riders                EE/DSM, LIHEAP rider, USF
  → Franchise fee                 % of in-city revenue subtotal
  → Environmental / MGP rider
  → Taxes                         by jurisdiction, by service type, by exemption
  = Total
```

Riders traverse in **topological DAG order**; show the order, since it is the thing that is
impossible to fake. Some riders add, some reduce.

**Key interaction.** Expand any line to see the factor values **as snapshotted at billing time**,
each with its effective date and its source. If the bill period spanned a tariff version change or a
PGA change date, show the two sub-segments and the day-split that produced them.

**Domain concepts surfaced:** the rider DAG; per-line vs per-total rounding (tariff-dictated, and
`knowledge/13-gotchas-and-lessons.md` treats this as a real source of disputes); proration triggers
(new service, final bill, mid-period rate migration, mid-period tariff change, meter swap); the
snapshotted-inputs invariant; therms-vs-CCF and the BTU conversion (residential customers don't
care; commercial customers want raw volume *and* applied factor *and* derived therms exposed so they
can audit it).

---

### Screen 4 — Rate Schedule Editor + Tariff Sandbox / Dry Run

**Primary persona:** Billing Analyst. **This screen is the product's core differentiator** —
"rate changes that billing staff can do themselves, no vendor consultant required"
(`/Users/ryanscomputer/code/tally-utility/CONTEXT.md:15`). The competitive claim is that a rate
change is an afternoon, not a three-week vendor professional-services engagement.

**Contents.**

*Schedule header:* code · name · service type · customer type/class · effective date · expiry date ·
version · PUC docket reference · applicability criteria (annual volume threshold, end-use
restriction, firmness election) · minimum bill amount · partial-period proration policy · prorate
tier breakpoints (yes/no).

*Rate item rows:* item name · calculation type (`fixed` / `volumetric` / `tiered_usage` / `demand` /
`rider` / `tax`) · rate or bracket editor · unit ($/month, $/therm, $/Dth) · active months (seasonal
applicability) · applies-to customer types · schedule-level rate override · taxability · display
name override · dependency position in the rider DAG · update frequency (monthly for GCA and WNA).

*Tier editor:* breakpoints and per-block rates, marked declining or inclining, with a note on whether
breakpoints prorate by days for partial periods.

*Version history:* every prior version with effective dates, the PUC docket that authorized it, a
**diff view**, and rollback.

**Key interaction — the demo moment.** **Dry-run the proposed change against last cycle's actual
data** before committing anything: a per-account impact list plus a distribution-level summary (how
many bills move up, down, by how much, which classes). Then an approval gate. Then staged rollout.
This is the "tariff sandbox" the analyst asks for by name.

**Domain concepts surfaced:** effective dating; immutable past versions with a version chain;
mid-period tariff change producing two sub-segments on one bill; automatic rate-schedule migration
when a customer crosses an annual-volume threshold (e.g. "> 3,000 therms for two consecutive years →
SGS becomes MGS") and operator-proposed reclassification with approval/notification.

---

### Screen 5 — CSR 360° Account Workspace

**Primary persona:** CSR.

**Contents — one screen, no system switching.** That is the whole point; the persona names
multi-screen bouncing as the root cause of most satisfaction problems.

*Header strip:* customer name · account number · service address · status · balance due · due date ·
rate schedule · billing cycle · last bill amount and date · last payment amount and date · flags row
(do-not-disconnect with type and expiry, billing hold, tax exempt, budget billing, autopay enrolled,
paperless, medical certification, bankruptcy stay, dispute open, collections stage).

*Panels:*
- **Usage + temperature chart** (the same component as Screen 6) — the de-escalation tool.
- **Bills** — last 12, each with period, therms, amount, status, estimated-read badge; click through
  to Screen 3.
- **Payments & credits** — payment history with channel and reference, applied vs unapplied,
  credit pool with origin type and remaining amount.
- **Premise & meter** — premise type, inside/outside city limits, franchise city, community/MDU,
  meter number, install date, last read, next scheduled read, AMI status, estimation block.
- **Programs** — LIHEAP / CAP / PIPP enrollment and renewal date, budget billing with running
  balance and anniversary, DPA schedule and breach status, medical certification expiry,
  third-party notification designee, SCRA status.
- **Interactions** — call/contact log with type, channel, reason, resolution, follow-up, linked
  invoice or service order.
- **Service orders** — open and recent, with type and status.

**Key interaction:** answer the call, log the interaction, and act — take a payment, set up a DPA,
order a re-read, request a bill explanation, update contact preferences.

**Domain concepts surfaced:** premise ≠ account; program enrollments as collections bypasses;
next-best-action prompts sourced from `anomalies`; persona-based UI so a new CSR sees only what
their role needs (the persona asks for onboarding in days, not weeks).

---

### Screen 6 — Usage + Temperature Overlay (customer portal; same component embedded in Screen 5)

**Primary persona:** the Customer. The CSR uses the identical chart as a prop on the phone.

Full treatment: `knowledge/18-usage-temperature-overlay-feature.md`. Its thesis: *"the
usage-plus-temperature graph is the single most leveraged piece of UI in the customer portal — it is
the central de-escalation tool for high-bill calls, it is achievable at monthly grain (no AMI
required), and it is conspicuously missing from most CIS vendor offerings in our target band."*
It is explicitly a **v1** feature, not v2 — "anything we ship without this graph loses a side-by-side
eval against NISC SmartHub."

**Contents.**
- **Series A — usage**, bar columns, in **therms** (or CCF). ~13 bars covering a rolling year.
- **Series B — temperature**, a line: daily mean, or a high/low pair, or an HDD line.
- **X-axis labeled with READ DATES, not month names.** Gas bill periods are 28–33 days and wobble
  ±3 days with the meter route schedule — a "December bill" might be Nov 18 – Dec 19 for one
  customer and Dec 2 – Jan 4 for their neighbor. HDD must be computed **per actual read window**,
  never per calendar month.
- **Estimated bars visually marked** — different color, hatched pattern, or an "E" badge, plus a
  footnote. The customer must be able to tell at a glance which bars are estimated, because when the
  actual read arrives the bar retroactively changes.
- **Hover tooltip:** usage in the bar's units · day count in the period · high/low/avg temperature ·
  year-over-year delta · $ cost equivalent.
- **Headline insight strip above the chart** — the weather-normalized comparison, which is the most
  analytically defensible framing and the one that actually de-escalates:

  > This bill: 580 therms over 642 HDDs = **0.90 therms per HDD**
  > Same month last year: 410 therms over 401 HDDs = **1.02 therms per HDD**
  > **Your home used 12% less gas per degree of heating need.**

- **Personalization line** from per-meter balance-point regression: "Your home starts heating around
  58°F. December averaged 32°F outdoors, which is why your bill rose."

**Key interaction:** click a bar; read the plain-language explainer for that period.

**Domain concepts surfaced.** HDD = max(0, 65°F − ((daily high + daily low) / 2)). The four data
patterns and where each belongs (Pattern 1 honest monthly bars = default chart; Pattern 3
weather-normalized comparison = headline strip; Pattern 4 balance-point regression = the
personalization driving copy; Pattern 2 modeled daily allocation = AMI drill-in, and only ever
labeled as estimated). **Gas load slopes up to the LEFT** — consumption rises as temperature drops,
the opposite of electric AC — so copy templates need a gas flag; generic electric-first portal copy
reads wrong. Designed **monthly-first with AMI as progressive enhancement**: most target-band LDCs
have 15–25% AMI penetration and even gas AMI delivers one read per day, not 15-minute intervals,
because the radio is the dominant draw on a 15–20 year lithium battery. Retroactive correction: when
an actual read replaces an estimate the historical bar changes, which is the bi-temporal cancel-rebill
scenario surfacing in customer-facing UI — a customer who screenshots in January and calls in March
needs a CSR who can reproduce the as-of state.

Open questions the KB deliberately leaves to the design doc: variable-width vs uniform-width bars
(probably uniform with day-count in the tooltip); HDD base temperature configurable per utility with
65°F default; NOAA ISD as the free v1 weather feed behind an abstraction layer; regression run
nightly into a per-meter cache, not on portal load; customers with <12 months history fall back to
climate-zone defaults rather than refusing to show the chart.

---

### Screen 7 — Meter Read Review / Validation Queue

**Primary persona:** Billing Analyst; field supervisor secondary.

**Contents.** Reads flagged by validation, with clean reads auto-approved and out of the way.

**Row fields:** meter number · serial · route / sequence · cycle · read date · previous read ·
current read · consumption · consumption unit (CCF/MCF/therms/Dth) · read method (manual / AMR /
AMI / customer) · reading purpose (regular cycle / move-in / move-out / final / check / re-read /
disputed / test / investigation) · quality flag · validation status · access status · skip code ·
trouble codes · tamper count and tamper-changed flag · estimated (Y/N) · **consecutive estimates
(n of cap)** · vs prior period · vs same period last year · % vs typical · rollover suspected ·
roll-under suspected · GPS / location anomaly · meter photo thumbnail with AI-extracted register
value and confidence score · assigned reviewer.

**Key decision:** approve · re-read (creates a service order) · estimate · dispute.

**Domain concepts surfaced.**
- **Rollover:** `end_read < start_read` means the register wrapped (5-dial 99999 → 00000);
  `raw_volume = (rollover_point − start_read) + end_read`.
- **Roll-under:** a swapped-in meter starts lower than the removed meter's final read, producing
  spurious negative consumption. Different problem, different fix.
- **Mid-period multiplier change:** honor the multiplier effective on each read date, never today's.
- **Meter swap inside the period:** split at the swap date, each segment with its own factors.
- **Estimation streak against the jurisdiction cap** — NY HEFPA caps consecutive estimates at 4;
  the analyst's fear is hitting the cap unnoticed and drawing a PUC complaint.
- **True-up when an actual arrives after estimates:** single catch-up adjustment in the current
  period, *or* full cancel-rebill of the estimated periods — **this varies by state and must be
  parameterized**, not hardcoded.
- Reads lock to the billing run and invoice once billed and cannot be modified afterward.

---

### Screen 8 — Cancel-Rebill / Correction Diff View

**Primary persona:** Billing Analyst, with supervisor approval. Already #5 in the existing mockup
queue ("correction diff view, Phase 8 review gate").

**Contents.** Original invoice and rebill side by side, line by line, with the **financial delta
explicit and balanced**. The analyst's fear is precise: "a cancel/rebill that looks correct on screen
but has orphan transactions in the GL that audit catches later."

Beneath each side, the **input set that produced it**, each value with its effective date:
rate schedule version · every rider rate · PGA factor · BTU factor · pressure/temperature factors ·
WNA normal HDD, actual HDD, deadband, base load and margin rate · tax rates by jurisdiction ·
franchise fee rate. This is what proves the rebill used the original period's world rather than
today's.

**Key decision — and it must be an explicit election, never a silent default:** the **rate date
mode**, *historical* (default) vs *current rate*. Then the approval gate. Then the customer
notification with regulated language ("this bill replaces the bill dated X").

Also on this screen: the backbilling cap check for the period being corrected, and the void reason
code with notes.

**Domain concepts surfaced.** Bills are immutable — no in-place edit exists. The ledger is
append-only — the reversal is a new offsetting transaction. Void + rebill lineage
(`replaces_invoice_id`, one live rebill per lineage). Point-in-time bill reproduction. The
bi-temporal requirement (valid time + transaction time), which the KB calls "the single most
consequential architectural gap."

Two neighbors from the mockup queue belong here as modals: **single-invoice void initiation** and
**bulk void with a default reason plus per-row override**.

---

### Screen 9 — Collections / Disconnect Worklist

**Primary persona:** Billing Analyst or collections clerk. Feeds the field tech's day.

**Contents.** Accounts by dunning stage across the configurable pipeline: past-due notice → formal
disconnect notice → pre-disconnect call → disconnect. Notice timing and content are
jurisdiction-parameterized.

Each row shows **every bypass condition evaluated today** — this is the engine that has to run daily:
- Cold weather moratorium (seasonal date window per jurisdiction)
- Temperature hold (NWS forecast below the state's threshold)
- Medical certification on file, with expiry and re-certification status
- DPA in good standing vs breached
- LIHEAP / agency pledge pending remittance
- Bankruptcy automatic stay (11 USC §362)
- Formal dispute open — collections blocked on the disputed amount
- Pending payment posted but not cleared
- Senior / disabled extended grace
- SCRA protection
- Third-party notification designee not yet notified

**Row fields:** account · customer · service address · balance · days past due · dunning stage · last
notice sent (type, date, channel) · bypass conditions active · disconnect eligible (Y/N + reason) ·
deposit on hand · prior disconnects · commercial vs residential · medical/temperature priority.

**Key decision:** who is genuinely eligible for disconnect today. **The screen's real job is making
the blocked accounts obvious and stating why** — a wrongful disconnect is the highest-consequence
error in this module.

Downstream: the disconnect work order carries address, reason, amount, customer notes, safety
requirements; outcomes are disconnected / customer paid on site / not home (reschedule) / safety
concern; photo documentation required.

**Reconnect side:** reconnection SLA (24–48h after payment, per state), reconnection fee with
after-hours differential (waived on wrongful disconnect), and the **relight workflow** — tech on
site, pressure/leak test before gas flows, pilot lights relit, customer must be home. Every reconnect
is a scheduled truck roll. A reconnect prioritization queue (medical, temperature severity, time
disconnected, commercial vs residential) is a nice-to-have.

**Domain concepts surfaced:** cold weather rules; the automatic stay as an absolute prohibition (no
notices, no field activity, ledger splits at petition date, adequate-assurance deposit request
within 20 days under §366); FDCPA on agency placement; the subpoena-ready collections audit trail
(every action with timestamp, decision rationale, and operator-or-system source).

---

### Screen 10 — PGA / Gas Cost Recovery Console

**Primary persona:** Billing Analyst. The CFO reads it.

**Contents.**

*Factor schedule:* every PGA/GCA/GCR factor with its $/therm rate, effective date, filing cadence,
commission docket, and status (filed / approved / effective / superseded). New factors are
**pre-loaded with future effective dates** — that is the workflow.

*WACOG breakdown for the current factor:* base commodity cost (NYMEX + basis + storage injection) ·
pipeline demand / reservation charges · **FL&U** (fuel and lost-and-unaccounted, within the regulated
UAF cap — above-cap UAF is shareholder expense, not recoverable) · storage costs · hedging
gains/losses.

*Deferred gas cost account:* month-by-month over/under-collection — actual gas cost × actual
throughput versus revenue collected at the current PGA rate × actual throughput — with running
balance and carrying-cost/interest accrual at the commission-prescribed rate.

*True-up amortization schedule:* remaining balance · months remaining · current month's adder or
credit · per-rate-class GCR factor.

**Key interaction:** enter next period's factor with its effective date, and see (a) which billing
periods it will apply to and (b) how a bill period spanning the change date prorates:
`usage × days before change × old rate` + `usage × days after change × new rate`.

**Domain concepts surfaced:** PGA is a dollar-for-dollar pass-through with **no markup permitted**;
prospective forecast and retrospective reconciliation **coexist** (forecast the coming period while
reconciling the last); **transportation customers skip PGA entirely** and are billed distribution
plus transport riders only; filing cadence varies by state (monthly in Illinois, quarterly commonly,
annual in Oregon / Kentucky / West Virginia / Georgia); the audit trail of all PGA and GCR history
must survive regulatory review.

---

### Alternates, if ten is too many

**Billing Run Monitor.** Run status with the dry-run toggle prominent, per-meter outcomes, failed
calculations, meters skipped, estimate count, exception count, average bill vs prior period, and the
**print/mail vendor deadline countdown**. Cycle-level completion %, skipped count, estimate count and
anomaly count are named as a required feature with no schema support yet.

**Payments / Unapplied Cash.** Lockbox OCR mismatch resolution (fuzzy match on name/address when the
account number is wrong), ACH return codes each with a distinct workflow (R01 insufficient, R02
account closed, R03 no account, R10 unauthorized, R29 unauthorized corporate), NACHA Notice of Change
(C01/C02/C03) processing, NSF reversal plus returned-payment fee, payment posting order
(oldest-first / current-before-arrears / tariff-specified priority), and unapplied cash / suspense
resolution.

---

## 5. The three highest-signal demos

### (a) Bill Detail with Tariff Inspector — Screen 3

Nothing else proves the domain is actually modeled. Showing therms derived from CCF through
multiplier → Fp → Ft → BTU factor, then the rider DAG traversed in topological order with WNA and
PGA sitting in their correct positions, is a claim a generic billing UI cannot fake — you either
built the pipeline or you didn't. The billing analyst persona asks for exactly this capability by
name, and the incumbent answer ("the tariff engine is a black box only the vendor consultant can
open") is the thing they resent most. A prospect who sees a per-line formula trace understands
within thirty seconds that this was built by someone who has looked at a gas tariff.

### (b) The dashboard's rate card strip with drift marker — Screen 1d

A small strip that encodes a subtle truth: *what you billed at* and *what the tariff says today* are
different datasets, and they diverge the moment someone loads next month's GCA. Anyone who has run a
gas cycle sees instantly that the builder knew the difference — and anyone who hasn't will not even
notice the strip, which is fine. It also demonstrates the whole product philosophy in one control:
the failure mode (a tile labeled "what we billed" silently reading live config) is prevented by the
query source rather than by operator vigilance, and the resulting drift marker is turned into a
*useful signal* — a correction-run trigger — instead of a caveat.

### (c) Cancel-Rebill Diff — Screen 8

Every billing analyst in the target market carries this scar, and the persona file states it nearly
verbatim: *"every billing analyst has a horror story about a cancel/rebill that produced a wrong
number because the system used current rates for a historical period."* Showing the original and the
rebill side by side with **both** snapshotted input sets visible, and the historical-vs-current rate
mode as a deliberate, recorded operator election rather than a hidden default, lands directly on the
scar. The balanced financial delta closes the second half of the same fear — the orphan GL
transaction that audit finds later.

### Note on the portal chart

The usage + temperature overlay (Screen 6) is the highest-signal demo for the **buyer** — the KB
calls it the Tier-1 demo lead and says a product without it loses side-by-side against NISC
SmartHub. Build it. But it signals *customer empathy*, not gas-billing depth; it answers a different
question than "do these people actually understand gas billing," which is what the three above
answer.

---

## 6. Vocabulary — the exact labels to put on screen

Two standing rules. **Never write "usage" where the domain says therms.** **Never write "account"
where the domain says premise** — a premise is not an account, it persists after the account closes,
and closing a premise is not closing an account.

The full acronym table with plain-language definitions is `knowledge/glossary.md`. Give it to
whoever writes the label strings.

### Bill / invoice fields

Invoice Number · Invoice Type (Regular / Correction / Final / Special) · Account Number · Customer
Name · Service Address · Billing Address · Billing Period (From / To, stated as read dates) · Days
in Period · Bill Date · Due Date · Rate Schedule · Meter Number · Read Date · Previous Read ·
Current Read · Read Type (Actual / Estimated / Customer Read) · Consumption (CCF) · Meter Multiplier
· BTU Factor · **Therms Billed** · Previous Balance · Payments Received · Balance Forward ·

**Charge lines:**
- **Customer Charge** — also seen as Basic Charge, Monthly Charge, Service Charge, Facilities Charge.
  Fixed $/month, billed even at zero usage. Covers meter, service line, billing.
- **Distribution Charge** — also Delivery Charge, Base Rate. $/therm (or $/CCF, $/Dth). The "margin"
  side: distribution system, O&M, A&G, return on equity.
- **Gas Cost Adjustment / PGA / GCR / CGA** — commodity pass-through, no markup permitted.
- **Weather Normalization Adjustment (WNA)**
- Riders by their real names: **DSIC**, **ISRS**, **PRP**, **GSEP**, DSM / Energy Efficiency, USF,
  LIHEAP rider, **RNG**, **MGP**, **TCJA Surcredit**, **RNM / Decoupling**
- **Franchise Fee** — % of in-city revenue, applies only inside city limits
- **Sales Tax**, **Utility Users Tax (UUT)**, by jurisdiction
- **Minimum Bill**
- **Late Payment Charge** — typically 1.5%/month simple on past-due balance, state-capped, often
  waived for LIHEAP customers
- **Returned Payment Fee**, **Reconnection Fee**

Current Charges · **Total Amount Due** · Past-Due Amount · Payment Coupon / Scan Line · Bill Messages
· Estimated Read notice · Rate Change Notice.

### Meter read / read-exception fields

Meter Number · Serial Number · Route · Route Sequence · Read Cycle · Read Date · Reader · Previous
Read · Current Read · Consumption · Consumption Unit (CCF / MCF / Therms / Dth / kGal / kWh) ·
**Read Method** (Manual / AMR / AMI / Customer Read) · **Reading Purpose** (Regular Cycle / Move-In /
Move-Out / Final / Check / Re-Read / Disputed / Test / Investigation) · Quality Flag · **Validation
Status** · Auto-Approved · Validated By · **Access Status** · **Skip Code** · **Trouble Codes** ·
**Tamper Count** · Tamper Changed · Estimated (Y/N) · **Consecutive Estimates (n of cap)** · Estimation
Blocked · Consumption vs Prior Period · vs Same Period Last Year · % vs Typical · **Rollover
Suspected** · **Roll-Under Suspected** · Multiplier Applied · GPS Coordinates · Location Anomaly ·
Meter Photo · AI Extracted Value · AI Confidence · Assigned To · Billing Period Locked · Locked By
Billing Run.

### Rate schedule fields

**Schedule Code** — the real ones:

| Code | Meaning |
|---|---|
| **RS / RGS / GSR** | Residential Service |
| **SGS / GSS / CGS** | Small General Service (small commercial) |
| **MGS / LGS** | Medium / Large General Service |
| **LVS / XLGS** | Large Volume / Extra Large General Service |
| **IS** | Interruptible Service |
| **FT / TS** | Firm Transportation |
| **IT** | Interruptible Transportation |
| **NGVS** | Natural Gas Vehicle Service |
| **SHS** | Seasonal Heating Service |

Schedule Name · Service Type (Gas / Water / Electric / Sewer — gas only at launch) · **Customer
Class** (Residential / Commercial / Industrial) · Effective Date · Expiry Date · Version · **PUC
Docket Reference** · Applicability Criteria · Annual Volume Threshold · End-Use Restriction ·
Firmness Election · **Rate Items** with **Calculation Type** (Fixed Charge / Volumetric / Tiered
Usage / Demand / Rider / Tax) · Rate · Unit · **Active Months** · **Applies To Customer Types** ·
**Rate Override** · Taxability · Display Name · **Tier Breakpoints** (Declining Block / Inclining
Block) · **Minimum Bill Amount** · **Partial-Period Proration Policy** · **Prorate Tier Breakpoints**
· **MDQ (Maximum Daily Quantity)** · **Contract Demand** · **Ratchet Clause** · **DCQ (Daily Contract
Quantity)** · Update Frequency.

### WNA panel

**Weather Station** · **Normal HDD (NHDD)** — rolling 15-year or 30-year, a live PUC policy question
· **Actual HDD (AHDD)** · **Deadband** (typically 2.2%–3%; WNA applies only outside it) · **Base Load
(BLMM — Base Load Monthly Mcfs)** · Base Load Method (Summer Average / Minimum Monthly / Regression)
· **Heat Use** · **Degree-Day Factor (DDF)** · **Margin Rate (MR)** · **WNA Therms (WNAM)** · **WNA
Amount** · WNA Season (active months) · Formula Form (1 / 2 / 3 / 4).

`HDD = max(0, 65°F − ((daily high + daily low) / 2))`

Sign convention matters on screen: colder than normal → actual usage exceeds weather-adjusted usage →
**WNA is negative → a credit to the customer**. Warmer than normal → **surcharge**. Label it so
nobody has to work that out.

The four canonical formulas (`knowledge/05-weather-normalization.md`):
- **Form 1 — Usage Adjustment** (UGI, Virginia Natural Gas):
  `Weather-Adjusted Usage = Base Use + (Heat Use × NHDD / AHDD)`; `WNA = (Adjusted − Actual) × Distribution Rate`
- **Form 2 — Direct Volume** (Peoples Gas PA):
  `WNBM = BLMM + ((NHDD ± (NHDD × 3%)) / AHDD) × (AMUM − BLMM)`; `WNAM = AMUM − WNBM`; `WNA$ = WNAM × Distribution Rate`
- **Form 3 — Margin-Based** (National Grid KEDNY):
  `WNA = MR × DDF × ((NDD × (1 ± deadband)) − ADD)`, deadband typically 2.21%
- **Form 4 — Annual True-Up** (Washington Gas): billed once a year in August, capped at 3% of actual
  Oct–May distribution revenue per month, remainder amortized forward

### PGA panel

**PGA Factor** ($/therm) — also **GCA**, **GCR**, **CGA**, **Gas Cost Adjustment** · Effective Date ·
Filing Cadence (Monthly / Quarterly / Annual / Interim) · Docket · **WACOG (Weighted Average Cost of
Gas)** · Base Commodity Cost · Pipeline Demand / Reservation Charges · **FL&U (Fuel & Lost and
Unaccounted-For)** · **UAF** vs Regulated Cap · Storage Costs · Hedging Gains/Losses · **Deferred Gas
Cost Account Balance** · Over/Under-Collection · Carrying Cost · **True-Up Amortization** (Remaining
Balance / Months Remaining / Monthly Adder) · GCR Factor by Rate Class · **CGC (Commodity Gas
Charge)** · **NCGC (Non-Commodity Gas Charge)**.

### Collections panel

Dunning Stage · Days Past Due · Aging Bucket · **Do Not Disconnect** (Type / Start / Expiry / Notes) ·
**Cold Weather Moratorium** · **Temperature Hold** · **Medical Certification** (Physician / Expiry /
Re-certification Due) · **DPA — Deferred Payment Arrangement** (Schedule / Installment / Breach
Status) · **LIHEAP** / **CAP** / **PIPP** / **USF** Pledge (Amount / Status / Remittance Received) ·
**Automatic Stay (11 USC §362)** · Bankruptcy Chapter / Filing Date / Case Number · **Pre-Petition
Balance** / **Post-Petition Balance** · Adequate Assurance Deposit (§366) · **Third-Party
Notification** designee · **SCRA** · Senior / Disabled Status · Dispute Open · Disputed Amount ·
Disconnect Notice Sent (Date / Channel) · Day-Of Personal Contact Attempt · **Disconnect Eligible** ·
Disconnect Work Order · **Relight Required** · **Pressure Test / Leak Check** · Customer Must Be Home
· **Reconnection Fee** (with After-Hours Differential) · Reconnection SLA · Write-Off (Reason /
Approved By) · Agency Placement · **Escheatment** (Due Diligence Sent / Escheated / Jurisdiction).

### Corrections / adjustments

**Void** (Reason Code / Notes / Rebill Expected) · **Cancel-Rebill** · **Rate Date Mode (Historical /
Current)** · **Replaces Invoice** · Correction Run · Correction Run Target · **Financial Delta** ·
**Backbilling Cap** · **Adjustment** vs **Ad-Hoc Charge** vs **Credit** · Ad-Hoc Charge (Charge
Number / Type / Taxability / Requires Approval / Approval Threshold / Target Billing Period / Voided
/ Waived) · Customer Credit (Origin Type: Overpayment / Goodwill / Refund / Complaint Settlement /
LIHEAP · Issued / Applied / Remaining / Expires) · **Account Ledger** (append-only, Running Balance)
· Unapplied Cash / Suspense · **MEA (Measurement Equipment Adjustment)** — the billing adjustment when
a meter test comes back outside tolerance.

### Payments

Payment Number · Amount · Payment Date · Posting Date · **Channel** (Walk-In / Web Portal / IVR /
Lockbox / ACH / Bank Bill Pay / Walk-In Cash Agent / In-Office / Agency Pledge) · Source System ·
Reference Number · Check Number / Check Date / Bank Name · Provider Transaction ID · Authorization
Code · Card Brand / Last Four / Expiry · Bank Name / Account Type / Holder Name · **Applied Amount** /
**Unapplied Amount** · **Posting Order** (Oldest-First / Current-Before-Arrears / Tariff Priority) ·
**NSF** (Reversal / Fee / Return Code) · **ACH Return Codes** (R01 Insufficient Funds, R02 Account
Closed, R03 No Account, R10 Unauthorized, R29 Unauthorized Corporate) · **Notice of Change**
(C01 / C02 / C03) · Autopay (Billing Day / Max Amount / Consecutive Failures / Disabled Reason) ·
Refund · Reversal Reason · Deposit Status · Postmark Date vs Effective Date.

### Customer / premise

Customer Number · Customer Type (Residential / Commercial / Industrial) · Status (Active / Inactive /
Closed) · Preferred Language · Preferred Contact Method · **Billing Delivery Method** (Email / Paper /
Both) · Property Owner vs Tenant · Landlord · **Landlord Responsible** · Security Deposit (Amount /
Status / Received / Refund Date / Interest Earned) · Tax Exempt (Reason / Certificate / Expiry /
Verified By) · **Billing Hold** (Reason / Set By / Set At) · Consolidate Invoices · External ID /
Source (legacy CIS continuity) · **Service Location / Premise** · Parcel ID · Location Type ·
**Inside City Limits** · **Franchise City** · **Rate Zone** · **BTU Zone** · **Pressure Zone** ·
**Weather Station** · **Tax Jurisdiction** · Community / MDU · Billing Cycle.

---

## 7. Things the KB flags that will bite a naive UI

From `knowledge/13-gotchas-and-lessons.md` and the billing-failures catalog. Worth a glance before
laying out any screen.

- **"Billing is never just math."** Every number on a bill has a tariff rule and a regulator behind
  it. A UI that lets someone type a rate with no effective date is wrong by construction.
- **Date effectivity is everywhere.** Any single-value rate display is a bug waiting to happen.
- **Rounding is tariff-dictated** — decimal places on therms, per-line vs per-total, rounding method.
  Two systems that disagree by a penny per line disagree by real money at 50,000 accounts.
- **Proration gets you.** Customer charge, minimum bill, block boundaries, riders and taxes each have
  their own proration rule, and the tariff specifies them separately.
- **Closing a premise ≠ closing an account.** The premise outlives the customer.
- **Bill messaging is often regulated verbatim** — versioned templates, not free text.
- **Print-and-mail vendors have hard deadlines and specific formats.** A missed cutoff delays a
  cycle; the dashboard should know the deadline.
- **Posting order is regulated**, not a preference.
- **The bankruptcy automatic stay is absolute** — no notices, no field activity, and the ledger
  splits at the petition date.
- **Bad bill visibility is existential.** The product's premise is that the operator sees the error
  before the customer does.
