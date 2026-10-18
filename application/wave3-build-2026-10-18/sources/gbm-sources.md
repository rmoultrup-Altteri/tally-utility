# Wave 3 (disputes and collections decision records): GBM source inventory

Repo: `/Users/ryanscomputer/code/gas-billing-memory` (GBM) at `bab1da5` (2026-10-16). Read-only pass, 2026-10-18.
All paths below are relative to GBM unless prefixed `TU:` (tally-utility). `CI` = `application/canonical-invariants.md`.

**Naming caution, read first.** GBM's own wave numbering is different from the one in Kyle's 2026-10-15 file. In `application/schema-parity-plan.md:130` GBM "Wave 3" means regulatory/reporting (A-2, A-9, A-10). In GBM, collections and disputes are **"Wave 4 — collections/comms: A-14 → A-16+A-17 → A-13 → A-15 → A-18 → A-19"** (`schema-parity-plan.md:136`), shown as "NOT STARTED" (`:63`, `:138`). The "wave 3: disputes and collections decision records" in this brief follows the 1-to-7 numbering in `kyle-decisions-2026-10-15-waves-1-to-7-and-texas-first.md:5`. GBM's parity plan is also stale. It lists patches only up to v5.4.2-12 (`:46`), and A-2 as "not landed" (`:53`). TU now holds -13 through -23. Per memory, the parity record lives in tally-utility.

---

## 1. Per CI

### CI-074: Meter and billing dispute suspends collections on the disputed amount (`CI:1304-1316`)

**Statement (key sentences).**
- "When a customer formally disputes a bill on grounds the jurisdiction recognizes (meter accuracy challenge, rate-application challenge, calculation challenge, service-not-rendered claim, identity-theft claim, and analogous PUC-recognized grounds), collections activity on the *disputed portion* of the balance is suspended pending dispute resolution: no dunning notices on the disputed amount, no late-fee accrual on the disputed amount …, no disconnect-eligibility evaluation against the disputed amount." (`CI:1306`)
- "The *undisputed portion* continues to be collectable on the normal pipeline. Resolution (meter test, audit ruling, customer-accepts-bill) closes the dispute and reinstates the disputed amount to its determined status (sustained / rebilled / waived)." (`CI:1306`)
- Rationale: the split per amount guards against two opposite failures. One is "blanket-suspension on any dispute lets customers indefinitely defer collectable charges by manufacturing nominal disputes". The other is "blanket-continuation defeats the due-process protection". (`CI:1313`)

**Grade:** `unenforced-gap`. "dispute records do not yet exist as a first-class table … See Appendix A-15." (`CI:1309`) Confidence high (`CI:1308`).

**Shapes the schema must hold.**
- A `disputes` table "with per-amount granularity (so the disputed-portion / undisputed-portion split per CI-074 is queryable), with PUC-recognized-ground enumeration and resolution-event lineage" (`CI:2605`; scope `CI:1312`).
- Resolution outcome domain: sustained / rebilled / waived (`CI:1306`).
- Named failure modes give the records something to test against (`CI:1314`):
  - a dunning notice on the disputed amount;
  - a late fee on the disputed amount;
  - a disconnect work order that cites total arrears including the disputed amount;
  - "dispute resolved but disputed-amount-suspended state not reset → suspension persists indefinitely".
- Scenario axes (`application/invariant-scenarios/collections-pipeline-and-disconnect-eligibility.md`):
  - A16, scope: whole balance vs a line item or amount, plus the two opposite failures (`:117-118`);
  - A17, outcomes, including the "state isn't reset" failure (`:120-121`);
  - A18, the grounds category (`:123-124`).
- The decision tables need `disputed_amount numeric | null` and `undisputed_balance`, both marked "no substrate — A-15" (`configurable-rules/decision-tables/disconnect-eligibility.md:32-33`; `collections-bypass-evaluation.md:30`).

**Left to the core or workflow.** The split evaluation ("Core would then split disputed vs undisputed" per TU parity measurement). In GBM: the collections engine's "suspended-on-disputed-amount evaluation", the late-fee engine and dunning suppression (`CI:1312`).

**Configurable boundary values** (`CI:1316`):
- "the *set of recognized dispute grounds*";
- "the *required-payment-during-dispute cap* (Texas: not exceeding 2-year same-period average at current rates per 16 TAC §7.45 §4.4 …— INV-151 example)";
- "the *resolution-timeline rules* (60 days or-resolution per Texas …)".
- Jurisdiction line: "Texas applies a specific cap on required-payment-during-dispute per 16 TAC §7.45 §4.4 — folded as configurable boundary" (`CI:1310`). INV-151 is folded in, not a separate entry (`CI:1311`; TU `application/draft-candidates.md:145`).
- KB text, `knowledge/31-texas-regulatory-compliance.md:247-251`:
  - "If customer notifies **before the delinquency date**, the customer cannot be required to pay the disputed portion exceeding their average usage for that billing period at current rates, until the dispute is resolved or **60 days** from bill issuance" (`:249`).
  - "'Average usage' = average of customer's usage for the same period during the preceding two years (if no history, estimate from similar customers…)" (`:250`).
  - "Utility must inform the customer of their right to file a complaint" (`:251`).
- Kyle's citation: §7.45(6)(D)(ii), "Customer need not pay the disputed portion exceeding average usage until dispute resolution or 60 days from issue, whichever is earlier." (`kyle-decisions-2026-09-02-a2-backbilling-caps.md:59`). Handed to collections at `:119`. See Conflicts C1.

**Neighbouring sources.**
- Meter-test dispute: CI-091 says "a meter test is often triggered by a customer dispute; collections-suspension applies during the test workflow" (`CI:1606`). Its scope names "`meter_test_disputes` (gap)" (`CI:1603`).
- The workflows open a "dispute record" with state `opened → investigating → resolved (confirmed | corrected | unmetered-correction)`:
  - `configurable-rules/workflows/meter-accuracy-dispute-investigation.md:21,43`;
  - `read-dispute-and-re-read.md:19,44`, outcomes `confirmed | corrected` only.
- Both workflows put the open-dispute failure state in Family 9: "an open dispute suspends collections action on the disputed amount" (`meter-accuracy…:9`; `read-dispute…:9`).
- A-11's enrollment model seeds a `pending_dispute` program type. It counts as a Texas-v1 workflow and as disconnect-protective (`CI:2564, 2572`; `CI:2487`). See Conflicts C2.
- Agency placement: "dispute opened" is a recall trigger (`workflows/agency-placement.md:28`). Exc 5: the customer disputes to the agency, and "The platform has no dispute substrate (A-15) and no channel to receive one raised elsewhere" (`:63-64`). An FCRA dispute duty applies if `credit_bureau_reporting` is ever on (`:81`).
- DPA breach: "breach trigger would fire based on a charge that is itself under active dispute" is a named failure (`invariant-scenarios/customer-programs-and-enrollment-lifecycle.md:90-91`; `CI:1079`). The collections doc says to draft A16/A17 together with programs A5 (`collections-pipeline…md:138`).
- Write-off: rank 1 blocks write-off while `disputed_amount_open`: "a disputed balance is not uncollectible, it is unresolved (CI-074)" (`decision-tables/write-off-eligibility.md:30,50`).
- DPA waiver: signing a Texas DPA gives up "your right to dispute the amount due under the agreement except for the utility's failure…" (`knowledge/31-texas-regulatory-compliance.md:425`). This interacts with dispute eligibility but no CI covers it.

### CI-054, dispute side only (`CI:963-975`)

- Statement: late fees are assessed "only on amounts that are not (a) under active dispute, (b) covered by an active program enrollment whose terms exempt …, or (c) within an active payment-arrangement breach-grace period." (`CI:965`)
- Grade: `requires-application-discipline`. "Only the exemption *evaluation* (LIHEAP / CAP / SCRA / dispute / breach-grace lookup against program-enrollment + dispute records) is app-side." The materialization substrate already exists: `invoices.late_fee_*`, ledger and adhoc `late_fee`, and `dunning_events.event_type` `late_fee_applied` (`CI:968`).
- Scope names "dispute records" (`CI:971`). Failure mode: "late fee on disputed amount (regulatory due-process violation, complaint upheld)" (`CI:973`).
- Boundary: the grace period, rate, exempt-program set, postmark policy and breach-grace window are configurable. The discipline is the invariant (`CI:975`). The **dispute exemption itself is not listed as configurable**.
- The family intro says "the dispute-suspension rule applies to both late-fee and collections" (`CI:1187`).
- Wave 7 owns the rule rows: "Estimation, late fees and program exclusions all become dated rule data with a legal citation." (R-11, `kyle-decisions-2026-10-15…:49`). What wave 3 owes CI-054 is only a dispute record the fee engine can query per amount.

### CI-067: Disconnect eligibility respects jurisdictional rules (`CI:1191-1203`)

**Statement.**
- "No disconnection may proceed unless an eligibility evaluation against the customer's jurisdiction-specific rule set returns 'eligible.'" (`CI:1193`)
- The rule set comprises: moratorium windows, temperature holds, arrears-threshold floors, notice-sequence completion, all active program enrollments, bankruptcy stay, and protected-class flags (`CI:1193`).
- "The eligibility decision is a single funnel — every disconnect-execution path consults it, no out-of-band disconnect bypasses the funnel — and the decision is recorded as a reproducible event for subpoena defense." (`CI:1193`)
- "Subpoena defense … requires reproducing the original eligibility evaluation as a function of the rule-set-version + customer-state-at-eval-time." (`CI:1200`)

**Grade:** `requires-application-discipline`. "The 'single funnel' property is enforced by code architecture, not schema." (`CI:1196`)

**Shapes.**
- A recorded eligibility decision event: rule-set version plus customer state at evaluation time (`CI:1193,1200`).
- Per-jurisdiction rule configuration and protected-status flags, "partially present but not unified (see Appendix A-14)" (`CI:1196`).
- Scope: `dunning_events`, `service_orders` (disconnect), per-jurisdiction rule config, protected-status flags, NWS feed, enrollments, bankruptcy flag (`CI:1199`).
- From the decision table (`disconnect-eligibility.md`):
  - Separate outputs `may_issue`, `may_execute`, `blocking_reason`, `all_blocking_reasons`, `recheck_required_at` (`:41-45`).
  - Rank 0 blocks when "The determination was made at issuance and is being relied on at execution without re-evaluation" (`:51`).
  - Open question 1: there is no determination record. The order "carries no reference to the eligibility determination that authorized it — no determination id, no evaluated-at timestamp, no expiry". The fix is "a determination record with an explicit validity window that the order references, and a mandatory re-evaluation at execution that the field workflow cannot skip … This is the single most consequential structural gap in Domain 11, and it is not in Appendix A." (`:77`)
  - Open question 4: `service_orders.status` has no `blocked`/`suspended` value and no structured blocking reason: "One status value and a structured reason code" (`:83`).
  - Rank 9 fails closed: "Any input above is unevaluable → block" (`:60`).
- The CI-070 evidence must carry "the disconnect-eligibility-decision identifier … that authorized the action" (`CI:1242`). So the decision record needs an id that a disconnect order can reference.
- Scenario axes: A1, every entry path routes through the funnel (`collections-pipeline…md:72-73`); A2, a scenario for each component (`:75-76`); A3, reproducibility against rule-set drift (`:78-79`).

**Left to the core.** The funnel and the evaluation itself (`CI:1196`).

**Configurable boundary.** The per-jurisdiction rule set (moratoria, temperature thresholds, arrears floors, notice sequences, protected classes) is "jurisdiction-statutory and tenant-configurable". The discipline (single funnel, reproducible, no out-of-band path) is the invariant (`CI:1203`).

**Texas inputs that feed eligibility.**
- CI-078 carve-out grounds (`CI:1371`). Kyle's A-2 records refine these into per-cause `enforceable_scope` values: `never` / `months`=6 / `uncapped` / conditional (`kyle-decisions-2026-09-02-a2-backbilling-caps.md:107-117`). See Kyle rulings K-A2.
- CI-079 closed days (`CI:1387`).
- CI-080 EWE (`CI:1403`).
- CI-081 medical hold plus IA (`CI:1420`).
- The day-26 elderly timing protection (§7.45) is a timing bar, not a bypass (`disconnect-eligibility.md:58,65`; `knowledge/31…:428` §8.4, "Delayed Payment — Elderly Customers (Age 60+)").

### CI-069: Bypass conditions evaluated at each pipeline step (`CI:1223-1236`)

**Statement.**
- "The collections engine evaluates every account at each pipeline-step transition (and on a daily-sweep basis for accounts in the pipeline) against the full configured bypass-condition set. Any single active bypass halts pipeline progression for that account." (`CI:1225`)
- The set (at minimum): "active deferred-payment-arrangement in good standing, active LIHEAP / agency-pledge hold, active medical certification, active SCRA flag, cold-weather moratorium window per jurisdiction, temperature-forecast hold …, active bankruptcy stay, pending billing dispute on disputed-amount portion, payment-pending-clearance state, third-party-notification not-yet-delivered (where required), senior/disabled protected-status flags." (`CI:1225`)
- "The set is tenant- and jurisdiction-configurable but the evaluation discipline — *all active bypasses halt, evaluated uniformly at every step* — is the invariant." (`CI:1225`)
- Composition, not precedence (`CI:1232`).

**Grade:** `requires-application-discipline`. "bypass conditions live in heterogeneous tables (program enrollments per Appendix A-11, dispute records per A-15, weather feed integration, bankruptcy flag, SCRA flag); the *evaluator* is the collections engine. Per Appendix A-14." (`CI:1228`)

**Shapes.**
- A per-jurisdiction bypass-set configuration: "which conditions count, evaluation cadence — per Q-6 for Texas" (`CI:2601`).
- The inputs listed above.
- Named failure mode: "configuration change to the bypass set applied retroactively → historical decisions become non-reproducible" (`CI:1234`). So the bypass-set config must be effective-dated or versioned.
- From the bypass table (`collections-bypass-evaluation.md`):
  - Outputs `bypass_active`, `governing_basis`, `all_active_conditions` ("the CI-064 output, not just the governing one"), `evaluated_at` ("proof the daily evaluation ran for this account"), and `unevaluable` (`:38-42`).
  - Ranked rules (`:48-57`): bankruptcy (absolute, including recall of in-flight field work), moratorium, the §7.45 seriously-ill hold with its IA, agency pledge in its commitment window, DPA `active_current`/`grace`, disputed amount where "the undisputed balance alone would not support disconnection", unapplied payment sufficient to cure, aged suspense past SLA, and "unevaluable → bar — fail closed".
  - Open question 3: "an unevaluable bypass condition blocks the action, and the inability to evaluate is itself recorded" (`:79`).
  - Open question 4: "`dunning_events` … there is no value for an evaluation that found a bypass and *declined* to act … Two enum values (`bypass_applied`, and arguably `bypass_evaluated`)" (`:81`).
  - `elderly_disabled` is "deliberately absent … pending his confirmation" (`:63`).
- `agency-placement.md:77` makes the same point: "the log records what the collections engine did to the customer and not what it stopped doing on the customer's behalf."

**Left to the core.** The evaluator.

**Configurable boundary.** Set membership per jurisdiction or tenant (per Q-6) and evaluation cadence (per-step plus daily sweep at minimum; real-time optional) are configurable. "all-active-bypasses-halt, uniform evaluation at every step, no precedence-shortcut" is the invariant (`CI:1236`).

**Texas set (Q-6 resolved).** See §2 below and Kyle rulings K-Q6. The final Texas-launch list matches CI-069's statement. Family violence is excluded (`collections-pipeline…md:42,90-91`).

### CI-071: Disconnect work order field verification (`CI:1257-1269`)

**Statement.**
- "Before executing a disconnect, the field technician validates the on-site captured meter serial and service-point identifier against the dispatched work order's expected values. Mismatch halts the disconnect at the field stage and routes back to dispatch for resolution." (`CI:1259`)
- "The verification is captured on the work order (with the captured-vs-expected pair recorded) and is reviewable post-incident." (`CI:1259`)
- "The discipline is binding even when the address matches." (`CI:1259`)

**Grade:** `partially-structurally-enforced`. The dispatched identifiers exist as FKs (`meter_id`, `location_id`, `customer_id`), and `service_orders_check` binds a disconnect to a customer and location. "The on-site-capture vs. expected check lives in the field-app workflow … The 'halt-on-mismatch' property is workflow-enforced" (`CI:1262`). Confidence medium: the rule spans the system side and procedure (`CI:1267`).

**Shapes.**
- On the work order: the captured-vs-expected pair (captured meter serial and service point vs expected), the outcome, and a mismatch event routed back to dispatch (`CI:1259,1262`).
- Failure modes include "technician overrides the halt-on-mismatch without supervisor approval" and "captured-vs-expected pair not recorded" (`CI:1268`). So the schema should be able to record an override event too (axis A15, `collections-pipeline…md:114-115`).
- Meter-deployment lineage makes verification reproducible across swaps (`CI:1269`).
- Axis A14: match / mismatch / address matches but meter drifted (`collections-pipeline…md:111-112`).

**Left to the field app.** The halt itself and the technician's compliance with it (`CI:1262,1267`).

**Kyle context.** D3A-1: the field-service and ticketing layer is kept "platform-agnostic". When the hold lifts, "the eventual field app submits reads through the same external-read API surface any third-party field tool would use — no privileged internal channel" (`wu5-wu6-kyle-decisions-2026-07-10.md:119`). So whatever records verification must accept it from an external field tool. There is no boundary value.

### CI-075: Collections engine deterministic and idempotent (`CI:1320-1331`)

**Statement.**
- "The collections engine is a pure function of `(account state, rule version, evaluation date, dependent reference data at coordinate)` for its decisions" (`CI:1322`).
- "Re-running the engine for the same evaluation date does *not* duplicate dunning notices, escalate to the next pipeline step, alter prior decisions, or post duplicate events — the engine recognizes already-emitted events and is idempotent on re-run." (`CI:1322`)
- "Every evaluation, decision, and emitted action records its inputs (rule version, account-state coordinates, dependent-reference-data coordinates) so the decision is reproducible at audit time." (`CI:1322`)

**Grade:** `requires-application-discipline`. "the schema records `dunning_events` with timestamps but cannot prevent code from introducing non-determinism or duplicate-on-replay behavior." (`CI:1325`)

**Shapes.**
- Each decision row carries its rule version, account-state coordinates, reference-data coordinates and evaluation date (`CI:1322`).
- Something that lets the engine "recognize already-emitted events", in practice a uniqueness or idempotency key per evaluation date (`CI:1322`).
- Failure modes (`CI:1330`): "engine reads `now()` instead of the run's evaluation timestamp"; a non-idempotent side effect "flips a flag the first run had set"; "rule version not recorded with the decision".
- Axes A19/A20 (`collections-pipeline…md:126-130`).
- The broader rule: CI-093 requires every regulated decision ("disconnect attempted or executed, dispute opened or resolved, … bypass-condition evaluation") to be reproducible "yielding the original inputs, the decision-logic version, the acting persona or system identity, and the temporal-coordinate basis" (`CI:1635`).

**Left to the core.** Determinism and replay safety (`CI:1325`). No boundary value is stated.

**Related idempotency CIs, for pattern only.**
- CI-055: a payment-intake idempotency token "deduplicates at the *intake* layer"; deliberately no schema column (`CI:981,984`).
- CI-098 ingestion replay (TU draft-candidates `:163`).

### Cross-referenced CIs (wave 3 only where they bear)

- **CI-068**, pipeline step completeness (`CI:1207-1219`).
  - "recorded as `dunning_events` with timestamps and content references" (`CI:1209`). Grade `partially-structurally-enforced` (`CI:1212`).
  - Texas 15+5+5 per TUC §104.258 / §7.45 is a boundary example, INV-152 (`CI:1213,1219`).
  - Failure modes include a rebill landing mid-sequence (`CI:1217`; axis A6 `collections-pipeline…md:87-88`).
  - TU's parity measurement says the sequence is "not yet law rows (wave 3)" (TU `application/invariant-parity-measurement-2026-10-13.md:77`). So TU treats CI-068's law rows as wave 3.
- **CI-070**, disconnect execution evidence (`CI:1240-1253`).
  - The evidence includes "the disconnect-eligibility-decision identifier" (`CI:1242`). This ties CI-067's decision record to CI-070.
  - Boundary: "*evidence-completeness-override workflow* (supervisor-attested missing-evidence in narrow operational circumstances)" is tenant-configurable (`CI:1253`). Kyle settled this as D9-1 (K-D9-1).
- **CI-072**, gas reconnection on-site (`CI:1273-1284`). "This is a PHMSA gas-safety claim and is NOT an impossibility proof. Route to a safety owner." (`CI:1278`)
- **CI-078–081**, Texas overlay (`CI:1369-1430`; `invariant-scenarios/texas-collections-overlay.md`).
  - The CI-078 carve-out "excludes these grounds … when the underlying arrears trace exclusively to them" (`CI:1371`).
  - Axis A2, mixed arrears, mirrors "CI-074's disputed/undisputed split" (`texas-collections-overlay.md:61-62`). Carve-out balances and disputed balances need the same per-amount tagging.
- **CI-082–085**, bankruptcy and estate (`CI:1442-1501`).
  - CI-082 requires withdrawing pending disconnect orders and reversing field activity in flight (`CI:1444`).
  - CI-085's deceased hold is a bypass condition (`CI:1490`). Kyle's R-08 now rules on it (K-R-08).

---

## 2. Appendix A-14 and A-15, in full

### A-14. Collections engine configuration: per-jurisdiction pipeline-step rules, bypass-condition set, eligibility-rule-set versioning (`CI:2599-2601`)

> CI-067, CI-068, CI-069, and CI-075 all depend on a unified collections-engine configuration substrate that today is partially present and partially scattered across tenant configuration, hard-coded engine logic, and ad-hoc tables. The substrate needs: a per-jurisdiction pipeline-step configuration (step sequence, required content per step, minimum-elapsed-time per step, delivery method, content versioning), a per-jurisdiction bypass-condition-set configuration (which conditions count, evaluation cadence — per Q-6 for Texas), an eligibility-rule-set with explicit versioning so historical decisions remain reproducible per [[CI-collections-engine-deterministic-and-idempotent]], and an integration surface to dispatch / field-app systems for the absolute-halt discipline of [[CI-bankruptcy-absolute-stay]] (reversal of in-flight field activity). The `dunning_events` table provides the event-recording substrate; the configuration substrate above is the gap. Queued for the schema-hardening sessions; affected entries remain `requires-application-discipline` or `partially-structurally-enforced` until landed. (`CI:2601`)

Shapes sketched by A-14:
1. A per-jurisdiction pipeline-step config: sequence, content per step, minimum elapsed time, delivery method, content versioning.
2. A per-jurisdiction bypass-set config: membership and cadence.
3. A versioned eligibility rule set.
4. A dispatch and field-app integration surface for halting and recalling work.

A-14 does **not** mention a per-decision eligibility record. `disconnect-eligibility.md:77` says this outright ("it is *not* in Appendix A").

Related evidence:
- `tenants.settings.dunning` is "a reserved, empty key" (`collections-bypass-evaluation.md:9`; `cold-weather-moratorium.md:9`).
- The weather substrate needed for EWE: "a county-to-NWS-station reference, a daily observations-and-forecast table fed by an integration, and an EWE-period event log" (`cold-weather-moratorium.md:67`).
- `service_locations.county` is nullable (`:69`), and A-5's weather-station FK is "the same build" (`:69`).

### A-15. Disputes table, bankruptcy / estate workflow tables, pre-/post-petition ledger partition (`CI:2603-2605`)

> CI-074 (Meter and Billing Dispute Suspends Collections on Disputed Amount), CI-082 (Bankruptcy Absolute Stay), CI-083 (Pre- and Post-Petition Ledger Split), CI-084 (Bankruptcy Adequate Assurance Window), and CI-085 (Estate and Deceased Customer Collections Hold) all depend on dispute and bankruptcy/estate workflow substrate that does not yet exist as first-class tables. The needed substrate: a `disputes` table with per-amount granularity (so the disputed-portion / undisputed-portion split per CI-074 is queryable), with PUC-recognized-ground enumeration and resolution-event lineage; bankruptcy / estate workflow tables (`bankruptcy_filings` or analogous with petition-date, chapter, court-id, filing-evidence references, and §366 adequate-assurance disposition tracking; `deceased_customers` or analogous with date-of-death, source-of-notice, survivor / estate-representative records and resolution-event lineage); and a pre-/post-petition ledger-partition mechanism on `account_ledger` (either an explicit partition column populated on bankruptcy-flag-set or a join-based partition derived from petition-date — the engineering choice has trade-offs for historical-query performance vs. schema-evolution complexity). Queued for the schema-hardening sessions; affected entries remain `unenforced-gap` until landed. (`CI:2605`)

Shapes sketched by A-15:
1. `disputes`: per-amount, with a recognized-ground enumeration and resolution-event lineage.
2. `bankruptcy_filings`: petition date, chapter, court id, filing evidence, §366 disposition.
3. `deceased_customers`: date of death, notice source, survivor or estate-rep records, resolution lineage.
4. A pre-/post-petition partition on `account_ledger`.

GBM gates:
- The parity plan fences A-15's "finance-adjacent parts (pre-/post-petition ledger partition, GL neighbors)" behind the finance reader. "The non-finance parts of A-15 (disputes table, bankruptcy/estate workflow records) can land in this wave" (`schema-parity-plan.md:137`).
- Per memory, the finance gate was resolved 2026-10-13 (D-2 accepted). GBM's plan still lists it as open (`:67`).

### Q-6 (flagged; resolved) (`CI:2402-2419`)

- "Status: RESOLVED (research, 2026-07-10 …). KB correction: family-violence status is a deposit-waiver-only protection (16 TAC §7.45(5)(C)), NOT a disconnect-bypass-set member." (`CI:2404`)
- "the only standing medical-type hold is the seriously-ill hold (§7.45(4)(H), physician statement, 20 days), which CI-081 already covers" (`CI:2404`).
- "EWE (CI-080) is separately confirmed self-executing with no declaration required. A tenant's specific tariff could extend more protection than this default — an onboarding-time check, not a platform default." (`CI:2404`)
- Preliminary inventory (`CI:2408-2413`): LIHEAP / agency pledge (§7.460(c)) yes; medical cert yes; EWE yes; "DPA in good standing: implied by 16 TAC §7.45 §5.1 carve-outs; explicit confirmation requested"; family violence no; bankruptcy stay yes.
- The second half of Q-6 ("Is per-tenant extension permitted for tenant-specific protected-status flags?" `CI:2415`) is answered only by "an onboarding-time check" (`CI:2404`). K-07 (2026-10-15) and the standing rule now cover it: rules are per jurisdiction or utility, no defaults.

### Related appendix: A-11 / Q-13, the enrollment substrate (landed in v5.4.0-04)

- `program_types` is seeded with `pending_dispute`, `regulatory_moratorium`, `bankruptcy_automatic_stay`, `payment_arrangement`, `agency_pledge`, and others. `is_disconnect_protective` drives the trigger-maintained `customers.do_not_disconnect` (`CI:2562-2568`).
- Texas-v1 ships workflows for six types, including `pending_dispute` (`CI:2572`).
- `customers.billing_hold` is "preserved unchanged as an independent admin-action axis … (fraud investigation, court order, customer dispute outside formal dispute records)" (`CI:2570`).
- Enrollment state-change audit was deferred to A-21 (`CI:2589`). Kyle's R-07 now requires an add-only status history (K-R-07).

---

## 3. Kyle rulings relevant to wave 3

Each entry gives file:line, date, and the quote.

**K-1015 (2026-10-15)**, `application/kyle-decisions-2026-10-15-waves-1-to-7-and-texas-first.md`
- Header: "**Closes:** R-01 to R-11, K-01 to K-07 / **Unblocks:** waves 2, 4, 6 and 7 (wave 3 needed K-07 only)" (`:4-5`).
- Standing rule: "A jurisdiction (state, regulator, and a city overlay where it applies) owns its own effective-dated rule sets, each with a legal citation. Texas is the first jurisdiction loaded as data. Adding a state means adding data, not changing code. Where the governing rules differ inside a state (for example, inside versus outside city limits), the rule set attaches per service location." (`:9`)
- **K-07:** "Support municipal utilities with rules entered per utility and no assumed defaults. Not required at launch." (`:57`)
- **K-05** (context for municipal scope): "16 TAC §7.45 … applies as minimum standards in unincorporated areas while municipalities can set their own inside city limits. The tenant confirms the within-bill order from their own tariff at setup." (`:29`)
- **R-07** (wave 4 here, but it bears on the bypass inputs): "Program enrollments keep an add-only history of status changes with effective dates, plus an optional end date per program type. A lapse triggers a notice before protection ends and never silently drops the customer." (`:33`)
- **R-08** (wave 4; a deceased hold is a bypass): "Death is a customer status with a date. … The account carries a hold that blocks shutoff and collections until the account is changed over to a family member. … the hold gets a one-month review reminder. If no update … within a month, the system raises a medium-priority exception to review it" (`:35`).
- **R-11** (wave 7): late fees and program exclusions become "dated rule data with a legal citation" (`:49`).

**K-Q6 / EWE / D9 / D8 (2026-07-10)**, `application/wu5-wu6-kyle-decisions-2026-07-10.md`
- Q-6: "family-violence flag = deposit waiver ONLY. 16 TAC §7.45(5)(C) … **Design: FV flag waives/suppresses deposit; it does NOT join the disconnect bypass list.** CI-069's bypass list finalizes without FV. Per-tenant tariff could extend more protection — check at onboarding, not platform default." (`:86`)
- EWE: "self-executing, at-or-below 32°F, county-level, cold-only … previous day's high 'did not exceed 32°F' (32.0 qualifies) AND forecast ≤32°F next 24h, per nearest NWS station for the customer's county. **No declaration required** … **No heat trigger for gas** … EWE-period bills defer into payment plans." (`:87`)
- **D9-1:** "No-photo-evidence disconnect sites → supervisor-role approval, recorded as event with reason code. Process control + audit trail, no new mechanism." (`:88`). This settles CI-070's override policy; also in `collections-pipeline…md:108-109`.
- **D9-2:** "Medical hold + broken IA → uniform grace window. IA breach isn't final until the D8-1 grace window lapses; medical hold survives exactly as long as the IA does." (`:89`)
- **D8-1:** "Breach is terminal; new enrollment required — with tenant-configurable grace window (payment within N days of breach flag = breach never happened). No cure state machine." (`:81`)
- **D8-2:** "Bankruptcy holds are event-terminated, not date-terminated. Expiry-type enum (`calendar` | `event`); end date nullable; termination = explicit operator action recording the court event" (`:82`).
- **D8-3:** "max one active installment/deferred-payment agreement per account … Holds compose freely with each other and with an IA." (`:83`)
- **D7-2:** "`regulatory_class` enum on charge definitions (regulated vs. unregulated) → v5.4. Load-bearing for Family 9 rules ('unregulated debt can't drive disconnect')." (`:78`)
- §366: "no Texas overlay on federal §366 for gas … 20-day adequate-assurance (individual Ch. 7/13), 30-day (Ch. 11 …); deposit-as-adequate-assurance; disconnect permitted after window if assurance not furnished. Ordinary Texas holds … run independently and can overlap." (`:92`)
- **D3A-1:** field-service layer platform-agnostic; "the eventual field app submits reads through the same external-read API surface any third-party field tool would use" (`:119`).
- **D12-1:** subpoena-readiness coverage map, "one-page table. Decision type / reconstructable-today (Y/N) / blocking gap." (`:100`)
- Not relevant despite the name: **D13-1**, "Pipeline is a fixed platform-level sequence" (`:103`). That is the *billing* pipeline (Family 13), not dunning.

**K-A2: the enforceable-side bounds handed to collections (2026-09-02, closed 2026-09-14)**, `application/kyle-decisions-2026-09-02-a2-backbilling-caps.md`
- Provenance: R-19…R-24 "have not each been separately re-confirmed by Kyle sentence by sentence" (`:26`).
- Disputed-portion shelter: "§7.45(6)(D)(ii) | Customer need not pay the disputed portion exceeding average usage until dispute resolution or 60 days from issue, whichever is earlier." (`:59`)
- Scope limit: "Applies to gas utility service to **residential and small commercial** customers in **unincorporated areas**; … incorporated areas **only to the extent they do not conflict with standards lawfully established by the municipality**." (`:63`)
- **R-20:** "Scope of the enforceable-side protection: disconnection AND refusal / re-establishment of service. … Nothing in §7.45 bars *billing* the amount, nor ordinary late-payment treatment or collections referral on it." (`:103`)
  - "`enforceable_scope` is a discriminator, not an integer. Explicit non-null enum `uncapped` / `months` / `never`" (`:107`).
  - Seed table (`:111-117`).
- Handoff: "**The enforceable half is recorded in A-2 and consumed by collections, not wired silently.** … §7.45(2)(D)(iv) disallows the prompt-payment discount on the one-time 5.0% deferred-payment penalty where the balance is unusually high because of utility error … Also in scope for them: the (6)(D)(ii) 60-day disputed-portion shelter." (`:119`)
- **R-26:** "`jurisdiction_id` NULL = the state / filed-tariff default row. … Municipal rows are admitted only where the tenant actually operates under a lawfully established differing municipal standard, evidenced by the ordinance … Resolution is most-specific-wins, two levels only" (`:207-209`).
  - "NULL premise FK falls to the statutory row … fail-toward-protection" (`:219`).
  - Unique constraint must be NULL-aware (`:227`).
- **R-28:** the (4)(E)(vi) closing clause goes to counsel: "**Nothing is built on it.** R-20's conservative reading — protection applies — remains the operative rule … **It must never become a tenant config toggle**" (`:261-263`).
- **R-30:** the (4)(E)(vii) estimated-bill determination is derived from the read record, with an operator override. "Where no basis is recorded, `enforceable_scope` for `estimation_catchup` is `never`" (`:291`). "The mapping is platform-fixed, never tenant-configurable." (`:300`) Bucket values are "an engineering proposal, not Kyle's ruling" (`:312`). The approved-meter-reading-plan leg is deferred under a named trigger (`:318`).

**K-F1 (2026-09-22)**, `application/kyle-decisions-2026-09-22-a2-straddle-and-meter-test-anchor.md`
- R-33 ground 1: folding a meter-error correction into a reissued invoice "merges a non-disconnectable charge with disconnectable ordinary charges into a single invoice balance, and collections can no longer tell them apart. An adjustment line keeps them separable and taggable." (`:153-158`)
- **F-1:** "Meter-error backbills are not disconnectable. … The correction therefore needs a **non-disconnectable flag that flows into collections**. This is a silent-and-financial failure if left to operator discipline, so it is a schema control. … a correction whose cause is tampering is *not* covered by this bar." (`:349-356`)
- Patch note: "Non-disconnectable flag on meter-error corrections (F-1), excluding the tampering cause." (`:398-399`)

**K-R38/39 (2026-09-23)**, `application/kyle-decisions-2026-09-23-a2-override-and-cause-freeze.md`
- Attachment 2: any change of cause "**into** `tampering_bypass` … requires **supervisor approval and an evidence artifact reference** … Changes **toward** protection need only a recorded reason." (`:238-243`) This is "the one edit in A-2 that at once lifts the (4)(E)(vi) disconnection protection" (`:245-247`).
- Attachment 3: "disconnection protection on the already-posted charge is lifted by an **append-only protection re-determination row**, under the attachment 2 gate, never by editing the posted row." (`:258-261`)
- R-39 seed: `billing_constant_error`, `crossed_meters`, `unbilled_service` are enforceable `never`, "pending, per fail-toward-protection" (`:363-367`). "F-1's non-disconnectable flag excludes `tampering_bypass` … and … also attaches to the three new causes." (`:398-400`)
- Counsel bundle: "Who tampered … A new occupant who inherits an existing bypass would, on the text, lose protection"; "Enforceable classification of the three R-39 additions … `never` stands until answered." (`:422-427`)

**K-CCK (2026-09-02)**, `application/kyle-decisions-2026-09-02-customer-class-keying.md`
- "Risk asymmetry (governs the whole design): under-protection is an RRC exposure (disconnect notice, deposit limits, deferred payment plans, the 'seriously ill' hold). Over-protection is a receivables cost. … Every ruling below resolves toward protection." (`:55-58`)
- **CCK-7** grain table: "Disconnect notice | Meter / service"; "'Seriously ill' hold | Premises / service location"; "Deferred payment plan | Bill". "**Rule: any protected meter → the coarser-grained action is treated as protected.**" (`:130-139`)
- "Protection decisions read the latest approved row, never the live function. … an RRC inquiry into a specific disconnect produces the exact threshold, months, and consumption figures the determination rested on." (`:199-202`). Same pattern as a recorded eligibility decision.
- **CCK-14:** "v1 default mode is `all_non_residential_protected`" (`:222-227`).

**K-Notice (2026-08-26)**, `application/kyle-decisions-2026-08-26-coda-items-4-7.md`
- **5.1, "Dunning notice delivery method — ruled into scope":** "16 TAC §7.45 specifies the method … deposit in the United States mail, postage prepaid, or hand delivery … at least five working days before the stated disconnection date" (`:229-231`).
  - "Design: `notice_delivery_method` with a two-column CHECK against `event_type` — `shutoff_notice_sent` requires `mail` or `hand_delivery` …; every other event type requires NULL … Domain deliberately *includes* `email`/`portal`/`text_message` so an unlawful send is recordable" (`:237`).
  - Companion `notice_delivery_confirmed_at`, "Separable" (`:239`).
  - "**Not built:** five-working-day enforcement … there is no calendar" (`:241`).
  - "Likely home: Wave 4's A-16/A-17" (`:243`).
- NULL-poisoning: the draft CHECK passed on NULL; "The fix is an explicit `IS NOT NULL` conjunct" (`:281`).
- Coda item 6 (agency pledge): "still blocked on cluster 46's member list and on whether 'bypass' means deferred-for-launch or bypasses-the-check-at-runtime. … 16 TAC §7.460(b)(2) prohibits disconnecting … *for a billing period in which the provider receives a written pledge* … time-boxed **by rule** to the billing period" (`:303`).

**K-D5 (2026-08-18)**, `application/kyle-decisions-2026-08-18-coda-items.md`
- D-5: "A re-read **inserts a new read that supersedes the original** … carries a **reason code** — re-read, meter issue, dispute … **Enforced in schema**" (`:363`).
- Confirmed list includes `dispute_recheck` (`:379`). A15: "Add `reread` to `reading_purpose` CHECK … Do not overload `dispute_recheck`" (`:249`). Bears on the read-dispute workflow's outputs.

---

## 4. Open questions (awaiting Kyle, Ryan or counsel) and whether they block wave 3

| # | Open item | Source | Blocks wave 3? |
|---|---|---|---|
| O1 | **No eligibility determination record and no re-evaluation at execution**: the "single most consequential structural gap in Domain 11 … not in Appendix A". Raised as a finding with no ruling. | `disconnect-eligibility.md:77` | It is the main thing wave 3 builds. It needs a design call, not a Kyle ruling. |
| O2 | Bypass evaluations that find a bar leave no trace (`bypass_applied` / `bypass_evaluated`); there is no recall counterpart to `sent_to_collections`. | `collections-bypass-evaluation.md:81`; `agency-placement.md:77` | Design call, buildable now. |
| O3 | A fail-closed convention ("unevaluable blocks and is recorded") is proposed but never ruled. | `collections-bypass-evaluation.md:79`; `cold-weather-moratorium.md:71` | No. It matches the standing fail-toward-protection pattern in Kyle's rulings (K-CCK `:55-58`; R-26 `:219`; R-30 `:291`). |
| O4 | `elderly_disabled` as a bypass: "absent pending his confirmation". | `collections-bypass-evaluation.md:63` | Minor. In TU it is still `is_disconnect_protective = true` (TU `sql/tu.sql:11733`). The data-driven bypass set can carry either answer. |
| O5 | Coda item 6, agency pledge: launch scope and the meaning of "bypass". | `kyle-decisions-2026-08-26-coda-items-4-7.md:303` | Partly. The pledge is a CI-069 bypass by statute (§7.460(b)(2)), but TU seeds `agency_pledge` as `is_disconnect_protective = false`, "workflow deferred" (TU `sql/tu.sql:11739`). Needs a decision if wave 3's bypass-set rows include it. |
| O6 | "DPA in good standing … explicit confirmation requested". | `CI:2411` | Nearly settled by the final list (`collections-pipeline…md:91`) and D8-1/D8-3. Not blocking. |
| O7 | **CI-072 safety owner**: what a completed reconnect must record from the PHMSA sequence. | `CI:1278` ("Route to a safety owner"); TU parity `:194` | Not wave 3 (reconnect). Only blocks a reconnect completion gate. |
| O8 | **CI-070 override policy**: GBM treats it as **resolved** by D9-1 (supervisor-role approval plus an event with a reason code). | `wu5-wu6…:88`; `collections-pipeline…md:109` | Not blocking. Still open: the *required-evidence component* list and retention period are tenant-configurable (`CI:1253`), and the approver vocabulary waits on `rbac-model` (`write-off-eligibility.md:11,82`). |
| O9 | §7.45(4)(E)(vi) closing clause (R-28); the three R-39 causes' enforceable class; "who tampered". All with counsel. | `kyle-decisions-2026-09-02…:261-265`; `-09-23…:422-427`; `kyle-outstanding-2026-09-05.md:20` | No. The protective reading is operative and reversal is additive. |
| O10 | R-30 bucket assignments for `meter_buried`, `meter_obstructed`, `key_required`, `seasonal_closure` (an engineering proposal, possibly for counsel); the approved-meter-reading-plan leg is deferred. | `kyle-decisions-2026-09-02…:312,318` | No. They default to `never`. |
| O11 | Moratorium: no weather feed, station map, or EWE event log ("procurement/build decision with a deadline attached to launch"); `service_locations.county` nullable. | `cold-weather-moratorium.md:67,69` | Partly. A-14's moratorium input is unevaluable without it. Wave 3 can record the decision with `unevaluable`. |
| O12 | Customers already disconnected when an EWE begins: "should be settled with Kyle". | `cold-weather-moratorium.md:73` | No (reconnection policy). |
| O13 | No holiday or business calendar, so CI-079 and the 5-working-day notice rule cannot be computed. | `disconnect-eligibility.md:27-29,79`; `kyle-…coda-items-4-7.md:241` | Partly. The rank 5 and 6 bars are unevaluable without it. |
| O14 | Meter-accuracy workflow: the path for a `conditional` test result. Read dispute: the fallback when a re-read is never obtainable, and the crossed-meter lookback. "needs Kyle's input". | `meter-accuracy-dispute-investigation.md:49`; `read-dispute-and-re-read.md:50-51` | No for the dispute *record*. They affect resolution outcomes, so the resolution enum should not be closed too tightly. |
| O15 | `rbac-model`: the approver and authorization vocabulary (D9-1 supervisor; CI-071 override; write-off bands). | `write-off-eligibility.md:11,82`; `agency-placement.md:13` | Partly, for any approval column. TU may have its own role decisions since. |
| O16 | Agency placement substrate and FCRA `credit_bureau_reporting` ("treat the toggle as out of scope for launch"). | `agency-placement.md:75,81` | No, unless wave 3 takes on placement. |
| O17 | GBM still lists the finance gate as open (A-15's pre-/post-petition partition). | `schema-parity-plan.md:67,137` | No. Memory says it was resolved 2026-10-13, and the dispute table is the non-finance part. |
| O18 | K-07: municipal per-utility rules, "Not required at launch". | `kyle-decisions-2026-10-15…:57` | Already ruled. This is the only ruling wave 3 needed (`:5`). Design consequence: no assumed defaults for municipal tenants, and §7.45 does not bind city-owned systems (memory `texas-muni-outside-gura`). |

---

## 5. Conflicts between sources

**C1. The Texas dispute shelter: what is sheltered, and for how long.**
- CI-074's general framing suspends collections on the *whole disputed portion* "pending dispute resolution" (`CI:1306`).
- The Texas source shelters only **the disputed portion exceeding average usage** (same period, prior two years, at current rates). The shelter ends at **resolution or 60 days from issue, whichever is earlier** (`kyle-decisions-2026-09-02…:59`; `knowledge/31…:249-250`).
- It also applies only **if the customer notifies before the delinquency date** (`knowledge/31…:249`). CI-074 omits this precondition entirely.
- CI-074's boundary phrase, "required-payment-during-dispute cap … not exceeding 2-year same-period average" (`CI:1316`), describes the same rule from the payment side. But it frames it as a *cap on what may be demanded*, while the body text suspends the whole disputed amount.
- **Newer and more specific:** Kyle 2026-09-02, cited to §7.45(6)(D)(ii). For Texas, a dispute record therefore needs a disputed amount, an average-usage figure (or the sheltered amount derived from it), the notice date relative to delinquency, and a shelter expiry. It should not carry a single "suspended until resolved" flag.

**C2. Dispute protection per amount vs per customer.**
- CI-074 and A-15 require per-amount granularity, with the undisputed portion still collectable (`CI:1306,2605`).
- A-11 seeds `pending_dispute` as a customer-level, disconnect-protective enrollment (`CI:2564,2572`). TU's seed reads "Formal dispute in progress; disconnect suspended while pending." That suspends the whole account, the "blanket-suspension" failure CI-074 names (TU `sql/tu.sql:11738`; CI rationale `CI:1313`).
- A-11 (2026-05-26) is older and was locked before CI-074's shape was built. CI-074/A-15 is the more specific source. The decision tables also condition the bar on "the undisputed balance alone would not support disconnection" (`collections-bypass-evaluation.md:53`; `disconnect-eligibility.md:59`), not on the existence of a dispute.

**C3. Agency pledge as a bypass.**
- CI-069 lists the pledge hold as a bypass (`CI:1225`), and Q-6 says "LIHEAP / agency pledge (16 TAC §7.460(c)): yes, in scope" (`CI:2408`). Kyle's 08-26 finding cites §7.460(b)(2) (`kyle-…coda-items-4-7.md:303`).
- A-11 makes `agency_pledge` a deferred workflow (`CI:2572`), and TU seeds it `is_disconnect_protective = false` (TU `sql/tu.sql:11739`).
- Coda item 6 is still unruled. The statutory sources are more specific.

**C4. `elderly_disabled`.**
- CI-069 lists "senior/disabled protected-status flags" (`CI:1225`), and the scenarios keep "protected-status flags (senior/disabled)" in the final Texas set (`collections-pipeline…md:91`).
- The bypass table removes `elderly_disabled` pending Kyle's confirmation, arguing it is a deposit waiver (`collections-bypass-evaluation.md:63`).
- A-11 ties it to the "Texas deposit waiver per CI-129" (`CI:2572`) yet seeds it protective.
- No Kyle ruling either way. The bypass table (2026-08-07) is newer than the scenarios doc (2026-07-04).

**C5. Disconnect precedence vs composition.**
- CI-069 says "composition rather than precedence … no precedence-shortcut" (`CI:1232,1236`). The decision tables are ranked.
- They reconcile this themselves: rank is for attribution only and "evaluation does not stop" (`collections-bypass-evaluation.md:4,16`). Not a real conflict, but the decision record must store `all_active_conditions` as well as `governing_basis` (`:39-40`).

**C6. GBM decision tables vs the current schema (staleness).**
- The tables (2026-08-07, corrected 2026-08-10) state that `customers.do_not_disconnect` is "maintained by no trigger" (`collections-bypass-evaluation.md:23,75`), and that enrollments are "not in SQL — v5.4" (`:22`).
- v5.4.0-04 landed the A-11 enrollment table and trigger (`CI:1447` re-check 2026-08-19; `CI:2568`). These "no substrate" statements predate that. TU's parity measurement (2026-10-13) is the current grade.
- TU still notes `recompute_do_not_disconnect` "tests status only, never `effective_end_date`" (TU parity `:202`).

**C7. CI-072's grade text vs its statement.** The statement still calls it "an impossibility-proof invariant" (`CI:1275`). The 2026-08-13 re-grade says "NOT an impossibility proof" (`CI:1278`). The re-grade is newer. It is outside wave 3 but sits on the same `service_orders` surface.

**C8. "Wave 3" naming.** GBM's parity plan puts collections in Wave 4 (`schema-parity-plan.md:136`). Kyle's 10-15 numbering puts disputes and collections decision records in wave 3 (`kyle-decisions-2026-10-15…:5`). TU's parity measurement follows the Kyle/TU numbering ("not yet law rows (wave 3)", TU `:77`). Different numbering schemes; not a substantive conflict. Anything cited from GBM's parity plan as "Wave 4" means this work.

**C9. Elapsed-time anchor for notices.** CI-068 keys the minimum elapsed time to step timestamps in `dunning_events` (`CI:1209`). Kyle's 5.1 says §7.45 is satisfied by *deposit in the mail*, so the defensible clock start is a vendor-confirmed postal-entry date (`notice_delivery_confirmed_at`), not the event's creation time (`kyle-…coda-items-4-7.md:239`). Kyle's text is more specific.
