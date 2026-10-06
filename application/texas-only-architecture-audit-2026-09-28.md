# Texas-only architecture audit — 2026-09-28

**Why this exists.** Ryan's ruling, 2026-09-28: *"A Texas only launch does not mean a Texas only architecture."* Launching in Texas decides which utilities sign first. It must not lock the design into Texas law. Kyle's rulings stay correct. What this audit questions is **where they live**.

**What was audited.**
- `sql/tu.sql` (23,452 lines) and all 23 patch files, including the paused A-2 patch (`v5.4.2-13`).
- This repo's docs.
- Gas-billing-memory's `application/` docs: Kyle's rulings, the invariant register, `configurable-rules/`, and the test-fixture strategy.
- The `ui-concepts/` prototype.

Nine readers each covered one slice and wrote a detailed report. The reports are in [`texas-only-audit-2026-09-28/`](texas-only-audit-2026-09-28/), with file and line numbers for every item. This document merges them.

I spot-checked the strongest claims against the source and the live catalog, and all of them hold:
- the literal `'TX'` branch;
- `America/Chicago`;
- the two buried six-month constants;
- `state_of_tx`;
- the one-pool-per-tenant gas cost (PGA) key;
- the backbilling seed that writes Texas rows into every tenant;
- the "last test" being read only for meter errors.

---

> **Correction, 2026-09-28 (Ryan, after reading this audit).** The drift is wider than Texas. The work has been writing the *application* in the database.
>
> **The locked stack decision** (`TECH-STACK-DISCUSSION.md`, 2026-06-07):
> - Data-driven configuration plus a typed calculation core.
> - C#/.NET backend; the billing core is a pure library.
> - TypeScript/React frontend.
>
> **The current phase is schema parity:** the schema can *represent* every invariant and every configurable aspect of the app, then the scenarios are written. Rule *evaluation* belongs to the C# core, which isn't being written yet.
>
> **How this changes the rest of the document:**
> - The **Mechanism** layer in §2 is future C# code, not triggers.
> - The rule "code decides by what a rule says, never by its name" is a requirement for that C# core.
> - The fictional-state ("ZZ") check becomes a scenario and test requirement for the core, plus a schema check that ZZ's rules *can be stored*.
> - The schema keeps the **places**, **law rules** and **utility choices** layers.
> - The schema also keeps record integrity, which must hold whoever writes:
>   - tenant isolation;
>   - issued bills can't change;
>   - the ledger is append-only;
>   - timestamps the database stamps itself;
>   - foreign keys and uniqueness;
>   - recording which rule row a decision used.
> - Trigger logic that *applies* law (the deposit accrual refusals, A-2's evaluator, the surcharge shape checks, and so on) is a finding in its own right: application logic in the wrong layer.
>
> See §6.

## 1. The short version

1. **The system has no idea which state a customer is in.**
   - No table records a state that a law rule could key on.
   - The `jurisdictions` table is a per-utility list of weather-adjustment places, with no state column.
   - The only state anywhere is free text: the utility's own mailing address (`tenants.state`) and the premise address (`service_locations.state`).
   - Because rules have nothing to hang on, Texas law got built in wherever a rule was needed.

2. **Only one rule is held the right way:** the meter accuracy threshold from v5.4.2-12 (`meter_accuracy_thresholds`).
   - It is keyed by state and service type and dated by when it takes effect.
   - It is held by the platform, not by each utility, and it cites its source.
   - Texas's 2.0% is one seeded row.
   - Every other statutory rule is either typed into structure or held per utility.

3. **Texas law sits in structure in four ways.** Each needs a different fix.

   | How it's built in | Example | Raw entries |
   |---|---|---|
   | **Hardcoded:** a fixed list of allowed values, a constant in code, or code that branches on a Texas category | the deposit guard contains `IF state = 'TX'`; the eight Texas backbilling causes are a closed list; "day 31" for deposit interest | 144 |
   | **Data, but Texas-shaped:** a value that can change, but only in a shape Texas uses | the deposit interest rate is a dated table, but keyed per *utility* rather than per *state*; franchise fees are keyed by a city *name* with no state | 107 |
   | **Right already** | the meter accuracy threshold; the backbilling month *numbers*; the tax breakdown per jurisdiction; tariff references on rate schedules | 36 |

   The 287 raw entries overlap: the same object is often reported once from the schema, once from the docs and once from the UI. Section 3 merges them into about 70 table rows, some of which group several related items, plus the UI and document lists. The document entries (the invariant register saying "statutory, not configurable", the rules model deferring other states) are counted in the first two rows.

4. **Where it started.**
   - The session-1 notes (`application/session-1-recon.md:99`) said the Texas rules "are invariants, not configurable policies".
   - The invariant register then turned 15 Texas rules into standalone entries titled "Texas — …".
   - The rules model (`configurable-rules/`) declared other states a *test* concern, not a data concern.
   - Every schema patch since has built what those documents said.
   - My A-2 work took the same path. I defended it with "Texas-only scope", and Ryan was right to call that out.

5. **The fix is a keying change, not a rewrite.** The mechanisms are sound almost everywhere:
   - the backbilling case, evaluation, input fingerprint, freeze, holds and approvals;
   - the deposit event ledger;
   - the surcharge cap machinery;
   - the tax-exemption evidence gate;
   - the bitemporal history.

   What changes is what they read. Each needs a platform-held rule row, looked up from the premise's state, service type and date, in place of a literal or a per-utility setting.

6. **What it costs.**
   - **A-2 is cheap to fix now,** because it is not merged.
   - **The landed patches need follow-up patches,** because `tu.sql` is append-only. No real utility's data sits in them yet, so the cost is schema work and tests, not migrating customers.
   - **Most of collections and disconnection is not built yet.** It exists only in the rules documents, so the fix there is to write those documents the right way before building.

---

## 2. The recommended shape

### Four layers

| Layer | Holds | Keyed by | Who writes it | Example |
|---|---|---|---|---|
| **Places** (new, platform) | States, counties, cities, special districts, unincorporated areas | the place itself; each place belongs to a state and may have a parent | Tally staff | Texas → Brazos County → Bryan |
| **Law rules** (new, platform) | What a statute or commission rule says | state (sometimes a smaller place), service type, sometimes customer class or cause, and the dates it's in force | Tally staff, with a citation on every row | TX gas deposit cap = 1/6 of annual billing, from 16 TAC §7.45, in force from X |
| **Utility choices** (exists) | What this utility's filed tariff or policy says | utility, plus service type and dates | the utility, with ruled exceptions | Atmos's customer charge; its franchise agreement with Bryan; a backbill limit shorter than the law's |
| **Mechanism** (exists) | The code that applies rules: gates, ledgers, evaluations, holds | — | engineering | the backbilling evaluator; the deposit accrual guard |

### Six rules that make it work

1. **The state comes from the premise, never from the utility.**
   - A utility may serve customers in two states.
   - Each rule is looked up from the service location's place, as of the relevant date.
   - `tenants.state` is a mailing address and nothing reads it for law.

2. **One table per rule family, with typed columns.** *(Reversed 2026-10-06 — see the note below and `application/rule-terms-convention-v2-2026-10-06.md`.)* Examples are `deposit_rules`, `backbilling_rules` and `moratorium_rules`, not one generic "key/value rules" table.
   - Typed columns can carry checks.
   - A generic table would move the Texas assumptions into untyped JSON, where nothing checks them.

   > **Correction, 2026-10-06 (Ryan).** Typed columns per setting could not keep up: two review rounds on deposits found five shapes, and a 10-state survey found 29 more. Rule 2 is replaced by the rule-terms convention (v2). A law table keeps a typed applicability key, dates and citation. Its content is a `terms` document of strategy choices and parameters, checked against a registered schema on every write. Typed facets derived from it carry the database's reference checks. The logic is named, versioned strategies in the core. The concern this rule answered ("untyped JSON, where nothing checks them") is met by write-time validation, not by typed columns.

3. **Every law table follows the meter-threshold template.**
   - No `tenant_id`.
   - `state_code` (plus an optional place), `service_type`, then the family's own keys.
   - `effective_from` and `effective_to`, with a no-overlap constraint.
   - A `source_note` citation.
   - The app role can only read it.
   - A `…_for(state, service, …, date)` lookup that **refuses when no row is in force**, never falling back to a default. A utility in a state we haven't seeded cannot bill that rule until someone enters the law.

4. **Code decides by what a rule says, never by what it's called.**
   - Today's code asks "is the cause `meter_error`?", "is the service `gas`?", "is the state `TX`?".
   - It should ask "does this rule make the refund mandatory?", "does this window have a last-test term?", "does this rule allow void-only?".
   - The names (causes, protection types, surcharge kinds) become reference rows. Their behaviour becomes columns on the law rule.

5. **A utility may be stricter than the law, never looser.**
   - Where a utility setting overlaps a law rule, the utility value is checked against the law row in force. Examples: its estimate cap, its backbill limit, its deposit cap.
   - This is Kyle's R-37(d) pattern: a utility's own backbill limit may be shorter than the statute, but not longer.
   - Utility settings that are pure policy stay as they are, such as the weather-adjustment clamps, the gas cost (PGA) alert bands and the aging buckets.

6. **Every decision records which rule row it used.**
   - Bill snapshots and correction evaluations already fingerprint their inputs.
   - They cite the law row's id and its date range, so a rule change is visible as a new row, not as an edited one.

### How we'll know it worked

Every test battery gets a **second, fictional state**, called "ZZ", seeded with deliberately different values. Examples: a 12-month backbilling window, a two-month deposit cap, interest from day one, no weather moratorium.
- Each test runs once as Texas and once as ZZ.
- The Texas answers must match today's exactly, which is the proof nothing changed for launch.
- The ZZ answers must follow ZZ's rows, which is the proof nothing is hardcoded.
- A rule that gives Texas's answer under ZZ is a finding.

This is the check the audit could not run: today nothing *can* flip.

### What is fine to leave per utility

Not everything regulatory is law. These are the utility's own choices and stay per utility:
- weather-adjustment floor and ceiling (T-4);
- gas cost (PGA) alert bands (D3D-1, "no RRC number exists");
- franchise fee percentages (a contract with each city, but keyed to a real place, not a city name);
- rate item values;
- the order of payment application within whatever the law allows;
- the utility's backbill limit (R-37(d));
- its volumetric class threshold (CCK-4…13);
- aging buckets and alert lead times.

Over-building these as law would be its own mistake.

---

## 3. What the audit found, by area

Each table gives:
- **Status:** **Hardcoded**, **Texas-shaped data** or **Right**.
- **Size** of the fix: **S** is a small patch; **M** is a table plus a lookup plus rewiring; **L** is a structural change.

The detailed reports have the exact lines.

### 3.1 Foundation: where a premise's state comes from

| What | Status | What another state needs | Fix | Size |
|---|---|---|---|---|
| `jurisdictions` (v5.4.0-03): per-utility, no state, no level or parent, no dates; holds only the weather-adjustment flag | Texas-shaped | Say "this place is in Oklahoma"; handle county-level rules; handle a city that adopts a rider on a date | Shared `places` table with state, kind and parent (Ryan's 2026-09-22 proposal); `jurisdictions` points at it | L |
| `service_locations.state`: free text, not validated. It is the key every rule lookup will use | Right place, weak key | A validated two-letter code | Check against a states table; add a dated premise-to-place link | S |
| `tenants.state` read as law: the deposit guard `enforce_deposit()` (v5.4.2-06:877) | Hardcoded | A utility serving two states | Read the premise's state | S |
| `inside_city_limits` true/false plus `franchise_city` text (tu.sql:4457). Register CI-086 calls "Incorporated vs Environs" "Texas-statutory, not configurable" | Hardcoded | Stacked places (city + county + district); states with no environs concept | Premise belongs to places, and "inside the city" is derived. Incorporated/environs become Texas's place kinds | M |
| Regulator as free text, "Railroad Commission of Texas" in the UI, "gas is RRC, never PUC" as a naming rule | Hardcoded (UI) / Texas-shaped | Gas is regulated by the state PUC or PSC in most states | Regulator per (state, service) in law data; UI reads it | S |
| **Service type used as a stand-in for the Texas regulator:** gas ⇒ no void-only, no small-amount threshold, historical rates on correction (tu.sql:4796/4803; D-8, DE-3, R-17; v5.4.2-03:808) | Hardcoded | Another state's gas regulator may allow small write-offs; a Texas water utility is not RRC-regulated | `correction_rules(state, service, …)`: allowed void-only reasons, small-amount threshold, required rate mode | M |
| Day boundary pinned to `America/Chicago` (v5.4.2-07:601) | Hardcoded | Every other time zone. **Wrong for El Paso already** | Time zone from the premise's place | S |
| Base schema: every rule-bearing table is per utility; no platform law table exists apart from -12's threshold and `program_types` | Texas-shaped | Each utility in a state re-enters the same statute, and the copies drift | The law layer above | (the model) |

### 3.2 Backbilling and meter corrections (A-2, v5.4.2-13, paused)

A-2's *mechanism* is general and keeps its tests:
- the case follows the meter across occupants;
- the database derives the evaluation from the caller's amounts;
- one evidence row per billed period, never netted;
- the input fingerprint and freeze;
- holds, supervisor approvals, the event log, deployment hardening and predecessor acquisitions.

A-2's *law* is built into its vocabulary and its branches:

| What | Status | What another state needs | Fix | Size |
|---|---|---|---|---|
| `backbilling_cap_rules` keyed per utility. The "state default" is a NULL-jurisdiction row per utility. The table has no dates | Texas-shaped | Two states' defaults for one utility; a rule amendment that doesn't rewrite history | Platform `backbilling_rules(state, place?, service, class, cause, dates, source)`; the utility's shorter limit stays utility data | L |
| `seed_backbilling_cap_defaults` writes Texas gas rows into **every** utility (-13:766–834) | Hardcoded | An Oklahoma utility would silently get Texas rules, and "no rule means refuse" never fires | Seed once, as `TX / gas` platform rows | S |
| Eight causes (Kyle's R-39) as a closed list; the case's five causes, "test-anchored" causes and allowed cause changes in checks and triggers | Hardcoded | Other cause splits, such as one "billing error" bucket, "culpable conduct", "access denied" | `backbilling_causes` reference rows. Behaviour moves to columns: anchor kind, required test outcomes, direction source, allowed changes, delivery path, gated or not | M/L |
| **The governing meter test is read only when the cause is `meter_error`** (-13:2231). If another state's rule gives a "last test" limit to a different cause, the limit **silently drops** and the window gets longer, against the customer | Hardcoded (latent defect) | — | Read the test whenever the resolved rule's window uses a last-test term | S |
| Window formulas are Texas clause shapes: `months_from_anchor`, `shorter_of_months_or_last_test`. One window for both directions | Texas-shaped | "Half the time since the last test, capped at N"; "from when the error began, if known"; different reaches for refunds and charges | Window as data terms (months before the anchor, last test, deployment start, error start …) combined with MAX or MIN, per direction | L |
| "Enforceable" scope: `never`, `months`, and `conditional_on_read_classification`, which names one Texas sub-clause | Texas-shaped | Instalment-plan duties; amount thresholds; protections beyond disconnection | Separate `backbill_enforcement_rules`, with a set of protected actions | M |
| Kyle's R-32: a billing period that straddles the window edge is forfeited whole | Hardcoded | Proration by days in the window | `straddle_treatment` on the rule; the evidence already records days in window | S |
| Fast-meter refund made mandatory by testing `cause='meter_error' AND outcome='fast'`, in five places: case withdrawal, zero-amount refusal, holds, uncovered days, the detection view | Hardcoded | A mandatory refund on another cause; a small-amount floor; a different reach | `favourable_duty` (mandatory or permitted) on the rule. The five places read it | M |
| Favourable periods always pass uncapped (R-25), and the utility limit never applies to them | Hardcoded | States that cap refunds too | Covered by per-direction window terms | S |
| Protected vs unprotected class (a fixed pair); `regulatory_class_mode` as a utility setting defaulting to "all non-residential protected" (CCK-14); a hardcoded map from customer type to class (-13:877) | Hardcoded | Residential-only protection; three tiers; government in or out | Per-state protected-class data, plus the utility's own size tiers (utility data) | M |
| The case-level lookup always asks for the "protected" row (-13:2225), assuming it has the widest reach | Hardcoded | A state where non-residential reaches further | Start from the widest window across the classes that could apply | S |
| Void-and-reissue allowed only for `rate_misapplication` (R-33). The reissue gate **never looks up a cap**, so it is uncapped by omission | Hardcoded | States that cap billing-error backbills too; "same units" as a per-cause rule | The gate resolves the rule and applies its window; `delivery_path` and `units_invariant` become cause attributes | M |
| **"6 months" buried in general code:** the R-36 supervisor gate (-12:1615) and the evidence fence (-13:2167) | Hardcoded | A 12-month rule would lapse the gate six months early and let a forged deployment through the fence | Read the resolved rule's reach | S |
| The tamper gate is keyed on the name `tampering_bypass` | Hardcoded | A different cause that lifts protections, such as "theft of service" | `requires_supervisor_evidence` on the cause | S |
| The anchor is always the test date (R-29); the estimated-bill three-bucket mapping is "platform-fixed" (R-30) | Hardcoded | Other anchors; states without a "beyond the utility's control" exception | Per-state rows (still not utility-editable, as ruled) | S |
| "Same units" compares gas columns (Ccf, therms) | Texas-shaped | kWh and kW for electric | A per-service list of billing quantities | S |
| **Right:** cap month numbers are rows with citations; the utility's shorter backbill limit; lookups refuse when no row matches | Right | — | Keep | — |

### 3.3 Meter testing (v5.4.2-12)

| What | Status | What another state needs | Fix | Size |
|---|---|---|---|---|
| `meter_accuracy_thresholds`: the model | Right | — | Keep; copy it | — |
| One symmetric ± figure | Texas-shaped | Water and electric use different fast/slow limits and per-flow-rate limits | Fast and slow percentages, plus optional per-test-point limits | M |
| How a test is judged: strictly "more than", the worst load decides, "non-registering" only if every load reads zero | Hardcoded | Weighted averages (common for electric); inclusive limits; no non-registering category | `boundary_inclusive`, `aggregation` and `non_registering_rule` on the threshold row | M |
| Test kinds as a closed list; "customer requested" carries Texas's record duties by check | Hardcoded | Commission referee tests; look-backs per meter rather than per customer and location | `meter_test_kinds` plus per-state duties | M |
| The Texas test-record field list as a check | Hardcoded | Other required fields | A required-field list on the duty row | S |
| "Last test" means the most recent test of any outcome (R-34) | Hardcoded | "Last *accurate* test", "half the interval since the last test" | A selector on the rule | S/M |
| Threshold resolved from the meter's *current* location, not its location on the test date | Right, residual | Wrong once a meter crosses a state line | Bind to the deployment on the test date | S |
| Watch: the test-fee rule (free after 4 years, $15, refund over 2%) is not built yet | — | — | Build it as law rows from the start | — |

### 3.4 Deposits (v5.4.2-06, plus base columns)

This is the worst landed patch. It builds 16 TAC §7.45 almost line for line as refusals.

| What | Status | What another state needs | Fix | Size |
|---|---|---|---|---|
| Residential cap applied only `IF upper(tenants.state) = 'TX'` (-06:877); a cap formula of 1/6 of annual billing | Hardcoded | "Two months' billing", "2× average bill", non-residential caps, no cap | `deposit_rules(state, service, class, cap kind, factor, dates, source)` | M |
| Cap columns can only hold an annual-billing basis | Texas-shaped | Average-month or highest-months bases | `cap_basis_kind`, plus the rule row used | S |
| Interest: none unless held ≥ 31 days, then back to day one; simple, 365-day, paid at refund (CI-130) | Hardcoded | Interest from day one, a six-month threshold, annual crediting, compounding | Rule columns: minimum hold, retroactive or not, method, day count, credit cadence | M |
| Interest rate is dated data, keyed **per utility** (the brief says "a new PUCT rate is a new row") | Texas-shaped | The rate is statewide law; every Texas utility re-enters it | Platform rate per (state, service), with an optional utility override | M |
| Refund trigger: 12 clean bills, ≤ 2 late, not currently late (CI-131) | Hardcoded | 24 months non-residential; months not bills; disconnection disqualifies | Rule columns | S |
| Basis list, with three values treated as "§7.45 basis" by an in-code list; additional-deposit triggers (bounced check, disconnect history, broken payment plan) | Hardcoded | Other bases and triggers | `deposit_bases` and triggers per state, flagged waivable or refund-mandatory | M |
| Waiver classes: family violence (with the **Texas Council on Family Violence** reference), 65 and over, good payment history | Hardcoded | Energy-assistance enrolees, medical, other certifying bodies. The 65+ waiver is also contradictory in the docs (mandatory vs tariff-by-tariff) | `deposit_waiver_classes(state, …)` | M |
| Only cash earns interest | Hardcoded | Some states require interest on other instruments | Instrument list on the rule | S |
| Refund "overdue after 60 days" (tu.sql:2712); old per-customer deposit columns duplicated on `customers` and `payments` | Hardcoded / legacy | — | Read from the rule; retire the duplicates | S |
| **Right:** the event ledger, the "no fallback, refuse when missing" rate lookup, the refund-due view as a mechanism | Right | — | Keep | — |

### 3.5 Disconnection, protections, collections

Mostly **not built yet**; it lives in the rules documents. The risk is building it from those documents as they stand.

| What | Status | What another state needs | Fix | Size |
|---|---|---|---|---|
| `program_types`: one "protects from disconnection" true/false per program for every state and service. Descriptions state Texas law (the medical certificate requires a payment plan; the 32°F weather emergency; Texas deposit waiver) | Texas-shaped | A program's effect differs by state: protects, waives the deposit, extends notice, for how long, how many renewals | Keep the list; add `program_type_effects(program, state, service, effect, parameters, dates)` | M |
| Weather emergency (32°F, county NWS station, cold only) modelled as a per-customer enrolment; the register says "not configurable" (CI-080) | Hardcoded | Calendar moratoria (e.g. Minnesota, Illinois), other temperatures, heat moratoria | `moratorium_rules(state, service, kind, threshold, geography, dates)` plus area events | M |
| `do_not_disconnect`: one flag per customer | Texas-shaped | Protected for gas but not water; protected at one premise, not another | Derive per customer, premise and service | M |
| One active enrolment per program type (a unique index) | Hardcoded | Concurrent plans; limits per year | Limits on the effects row | S |
| Disconnection stages as a fixed ladder (tu.sql:1690, 2968); notice sequence 15 + 5 + 5 working days; notice by mail or hand only (a designed check) | Hardcoded | Personal contact, 48-hour notices, electronic notice with consent, calendar days | `notice_sequence_rules(state, service, class, step, …)` plus a holiday calendar | L |
| Six arrears grounds that can't cause disconnection (CI-078); no disconnection before a closed day (CI-079); elderly day-26 protection; medical hold of 20 days plus a payment plan (CI-081); family violence is a deposit waiver only | Hardcoded / Texas-shaped | Each differs or is absent elsewhere | Per-state rows in the families above | M |
| `regulatory_class` regulated/unregulated drives both "can this debt cause disconnection" and "which charges payment goes to first" | Hardcoded | More categories (deposit, late fee, third party, merchandise); a state-mandated order | Utility tags each charge with a category; `charge_category_rules(state, service, category, may_drive_disconnect, allocation_priority)` | M |
| Payment allocation is a utility preference with no law layer; the UI hard-codes oldest-first and ignores the utility's setting | Texas-shaped / Hardcoded (UI) | A state-required order within a bill | As above | M |
| Warning windows (30 and 60 days), the 2-bounced-checks-in-90-days flag, the permanent "no checks" rule in the UI | Hardcoded (low) | — | Utility settings, or rule values where statutory | S |

### 3.6 Regulatory surcharges (v5.4.2-07 / -08)

Built around one Texas statute, the Pipeline Safety Fee (16 TAC §8.201).

| What | Status | What another state needs | Fix | Size |
|---|---|---|---|---|
| `surcharge_kind` is `pipeline_safety_fee` or "other"; the fee's shape is forced by a check (cap required, never taxed, state agencies exempt); gas only by a literal | Hardcoded | Other assessments: taxable, uncapped, applied to water or electric | `regulatory_surcharge_kinds(state, service, kind, …shape…, dates, source)`; the utility's rule points at a kind | M |
| One Pipeline Safety Fee rule per utility per date | Hardcoded | A two-state utility has two | Key by state as well | S |
| `customers.is_state_agency`, commented "agency of the State of Texas" | Hardcoded | *Which* state; other exempt classes | Exempt categories on the kind row; dated customer categories | M |
| Tax exclusion is all or nothing; the cap is per meter per bill-date cycle; the surcharge is never billed as a tax line | Texas-shaped | Excluded from sales tax but not a city fee; per-bill or per-account caps; assessments billed as taxes | Attributes on the kind row | M |
| **Right:** the cap is a configured amount, not a literal; the remittance timing was kept out of structure; the per-bill tax base table | Right | — | Keep | — |

### 3.7 Tax, exemptions, franchise fees

| What | Status | What another state needs | Fix | Size |
|---|---|---|---|---|
| Exemption categories as closed lists (two different ones in the base; `industrial` removed on Texas reasoning, R-13), repeated as a literal in a function (-09:252) | Hardcoded | Other categories: manufacturing, tribal, direct-pay | `tax_exemption_categories(state, …)` | M |
| "Certificate required" per category held in utility settings, defaulting to TRUE because of the Texas Comptroller's Rule 3.287; the error text names Form 01-339 | Texas-shaped / Hardcoded text | "Exempt by status" states; other forms | `tax_exemption_certificate_rules(state, category, required, forms, dates)` | M |
| Residential gas is assumed exempt from the rate class (Texas Tax Code §151.317); `should_charge_tax()` is yes/no and ignores which tax | Texas-shaped | Residential taxed, partly taxed, or exempt from state tax but not city tax. **This is wrong even for Texas city taxes** | Taxability per (state, tax, service, class); exemptions tied to a taxing authority | M |
| Taxability defaults for one-off fees follow Texas Tax Code ch. 151; the override is per utility | Texas-shaped | Other states' rules | Defaults by state | M |
| Franchise fees keyed by utility + **city name** (no state), a percentage, and four Texas base shapes; the §182.025 2% ceiling is planned as a literal | Texas-shaped / Hardcoded | Two Springfields; county or district fees; fees per unit or per meter; stacked fees | Key by place; fee kind and basis as data; ceiling as a law row | M |
| **Right:** the invoice tax breakdown per jurisdiction; per-bill tax bases; the exemption evidence gate and renewal queue | Right | — | Keep; A-8 (tax jurisdictions) builds on places | — |

### 3.8 Rates, gas measurement, weather adjustment, gas cost, corrections

| What | Status | What another state needs | Fix | Size |
|---|---|---|---|---|
| `calc_owner` allows `'state_of_tx'` (tu.sql:4105, -03:1079) | Hardcoded | `state_of_ok`… | `state_regulator` | S |
| Gas cost (PGA) is **one pool per utility**, justified in the patch by "§7.5519 is a single Texas-wide mechanism" (v5.4.0-06:39, unique keys :75, :124) | Hardcoded | Multi-state utilities run one pool per state or division; water and electric have their own pass-throughs | `cost_recovery_pools(utility, service, state, area, mechanism)`; re-key on the pool | M |
| Pressure class with "Fp = 1.0 always for residential" (CI-029); reference conditions "60°F / 14.65 psia, fixed"; the usage formula has no therm step | Hardcoded | Pressure base 14.73 in many states; therm and dekatherm billing | `gas_measurement_bases(state, …)`; tariff pressure tiers as utility data | M |
| Gas columns on generic reading, line and meter rows; the bill snapshot (v1) *requires* gas and weather-adjustment sections on every bill | Texas-shaped / Hardcoded | Electric demand and time-of-use; water tiers | Sections required by service type; law rows cited in a v2 snapshot | M |
| Weather adjustment: season Nov–Apr and `per_mcf` as defaults, "applies" defaults to true ("the common Texas case"), monthly settlement assumed | Texas-shaped | No weather adjustment, decoupling, annual true-up | No defaults; settlement mode as utility tariff data | S/M |
| An ordinary bill is priced entirely at the period's end date (v5.4.2-10:640) | Hardcoded | Commissions that require proration across a rate change | A pricing convention per tariff or state | L |
| The correction rate mode defaults to "historical", labelled "RRC-compliant", and the function falls back to it silently | Hardcoded | Other regulators' rebill rules | Default from `correction_rules`; the fallback raises instead | S |
| Customer classes as a closed list of 7 (tu.sql:2531, 4210, -03:553; the UI mirrors it) | Hardcoded | Irrigation, public authority, transport, interruptible, lighting | Each utility's own class list, mapped to the state's statutory classes | M |
| Units without dekatherm; `mud` (a Texas water district) as a community type; a language list of 6; water-only meter sizes | Hardcoded (low) | — | Reference data | S |
| **Right:** rate items are dated utility data with a citation; regulator and tariff references on every schedule version | Right | — | Keep | — |

### 3.9 Reads and estimation

| What | Status | What another state needs | Fix | Size |
|---|---|---|---|---|
| The consecutive-estimate cap is a utility setting (default 3, counted in reads). **The Texas six-month limit is held nowhere**, so a utility could set a cap above the law | Texas-shaped | Limits by count (e.g. Pennsylvania 4) or by months (New York) | `estimation_limits(state, service, kind, value, dates)`; the utility value must be ≤ the law | M |
| "Stale" after 45 days is built into an index | Hardcoded (low) | Water reads every two months | Setting | S |
| The UI prints "At the Texas cap" at 3 | Hardcoded | — | Show the resolved rule and its citation | S |

### 3.10 Unclaimed property (escheat)

| What | Status | What another state needs | Fix | Size |
|---|---|---|---|---|
| Dormancy clock in a materialized view: 1095 days, a 90-day warning, 60-day due diligence, a $250 threshold (tu.sql:2705–2715) | Hardcoded | Each state sets its own, by property type, and the owner's last-known state decides which state applies | `unclaimed_property_rules(state, property type, …)`; the view joins the owner's state | M |
| Minimum refund and the small-balance action held per utility; `escheated_to_jurisdiction` as free text | Texas-shaped | — | Checked against the state rule; linked to a state | S |

### 3.11 Bills, notices, languages, rate changes, payment terms

All mostly in the documents, not yet in SQL.

| What | Status | What another state needs | Fix | Size |
|---|---|---|---|---|
| English and Spanish as a fixed two-language set, "no county table" (Q-8, CI-088) | Hardcoded | Other languages, some set by locality | `required_notice_languages(state, place?, notice)` | S |
| Mandatory bill elements "not configurable" (CI-089); the UI hard-codes the Texas notice text | Hardcoded | Other required disclosures | `bill_content_requirements(state, service, element)`; notice templates per state | M |
| Rate-change process: Statement of Intent, 4 weeks of newspaper notice, 35 days (CI-087) | Texas-shaped | Entirely different rate-case processes | `rate_change_procedure(state, service, posture, steps)` | M |
| Payment terms floor of 15 days (a warning only); postmark as the on-time rule; 7-year retention | Texas-shaped | Other floors and on-time rules | `payment_terms_rules(state, …)` | S |

### 3.12 The UI prototype (`ui-concepts/`)

The UI has no concept of a jurisdiction. It follows whatever the schema gives it, so most of its fixes fall out of the SQL ones. UI-only items:

**Kyle's newest work**
- Add payment applies payments oldest-first and ignores the utility's allocation and overpayment settings.
- The rate editor offers only gas units and defaults to per-therm.
- The tariff sandbox is a fixed Texas gas rate card: two blocks, PGA, weather adjustment, GRIP, Pipeline Safety Fee, franchise fee and gas utility tax.
- `CLASS_INDEPENDENT` lists rate items by Texas item codes.

**Collections**
- The bypass codes are a closed set of Texas §7.460 conditions.
- "Texas has no calendar winter moratorium" appears as screen logic.
- Protection scope is a residential-or-not flag.

**Hardcoded copy**
- "Railroad Commission of Texas"
- "Texas 12-month look-back" (also wrong: the §7.45 numbers are 6 and 3 months)
- "At the Texas cap"

**Tax in the fixture generator**
- Tax is decided by customer class, with residential gas exempt, which is Texas law.

**Where the UI and SQL disagree**
- The UI still models the dropped single disconnect-protection field.
- It treats the Pipeline Safety Fee as a plain rate item.
- Its $2 threshold for correcting a gas bill contradicts the schema's "gas always needs a full correction".

### 3.13 The documents that drove it

These need a dated correction note, not rewriting history:

- **`application/session-1-recon.md:99`**: "invariants, not configurable policies". This is the root.
- **GBM `canonical-invariants.md`:**
  - 14 entries tagged `jurisdiction: texas` (CI-038, 078–081, 086–092, 129–131), each "statutory, not configurable".
  - Four other Texas candidates were correctly folded into general rules as Texas values (the 15+5+5 notice sequence, the dispute cap, PGA cadence, gas reference conditions). **That fold is the pattern to copy for the other 14.**
- **GBM `configurable-rules/`:**
  - Convention F-CC-4: "Regulatory: Texas-launch depth only; multi-state deferred to Layer 4".
  - The scenario strategy claims the model absorbs other states "without restructuring". Its decision tables contradict that: 13 of 60 carry Texas values in their rule rows and none takes a state as input.
  - The `jurisdiction_rules` store it names (A-14) was never designed.
- **GBM test-fixture strategy:** "All tenants operate in Texas only at v1". No second-state fixture exists. The one state-level fixture, FIX-JUR-001, is the right shape and a ready list of Texas gas columns.
- **This repo:**
  - `CONTEXT.md:33` frames A-2 as "the 16 TAC §7.45 limits" rather than CI-008 "backbilling cap per jurisdiction".
  - The guiding principles lack "law is per-jurisdiction data".
  - `DECISION-LOG.md:290` records "every rule of the Texas accrual/refund discipline is a refusal" as the goal.
  - `APPLICATION-CONTRACTS.md` specifies the Texas deposit and Pipeline Safety Fee shapes.
  - `TECH-STACK-DISCUSSION.md` scopes the in-house tax engine as "single-state Texas".
- **Stale or contradictory values found along the way:**
  - CI-008 and CI-092 still cite a "12-month Texas cap".
  - CI-049 says "Texas applies oldest-first" (DE-2 found no such rule).
  - The 65+ deposit waiver: mandatory, or tariff by tariff?
  - The deposit interest rate: "PUCT rate" vs statutory rate.
  - CI-091 says "platform-fixed 2.0%".
  - The Pipeline Safety Fee cap: $1.00 vs $0.50.

  These need Kyle.

---

## 4. Recommended order of work

1. **Write the principle down (S).**
   - Add to `CONTEXT.md`'s guiding principles: "A statute or commission rule is dated data keyed by state (and a smaller place where the law needs one) and service type; code is a mechanism that reads it; utility settings may be stricter than the law, never looser."
   - Add dated correction notes to `session-1-recon.md:99`, `DECISION-LOG.md:290` and `CONTEXT.md:33`.
   - GBM-side notes are logged in `wiki-ingestion-pending.md`.

2. **Build the foundation (M–L).** This is the new A-2 prerequisite.
   - A platform `places` table with state and kind.
   - A dated premise-to-place link.
   - Validated `service_locations.state`.
   - `jurisdictions` pointing at places.
   - The law-table template and the refuse-when-missing lookup convention, written once.
   - The ZZ fictional-state fixture in the test harness.

   This is Ryan's shared-places proposal from 2026-09-22, which was waiting for the tax jurisdictions work (A-8). A-2 now needs it too, so it goes first.

3. **Rebuild A-2 on it (L).**
   - `backbilling_rules` as platform law.
   - Causes as reference rows with attributes.
   - The window as data terms per direction.
   - Enforcement as its own rule.
   - The reissue gate resolves the rule.
   - No "6 months" literals.
   - The governing test is read by what the window says.

   The mechanism and battery carry over. Pass condition: the r7 battery gives identical Texas answers, *and* the ZZ answers follow ZZ's rows.

4. **Re-key the landed Texas law, highest risk first:**
   - deposits (-06);
   - correction rules keyed on `gas`;
   - surcharges (-07/-08);
   - tax exemptions and taxability (-03/-09);
   - program effects and moratoria (-04);
   - the PGA pool (-06);
   - unclaimed property;
   - the estimate cap;
   - the `America/Chicago` boundary.

   Each is its own patch, with a Texas-unchanged test and a ZZ test.

5. **Fix the documents before building from them.** Before any collections, notices, bill-content or rate-change work:
   - Fold the 14 "Texas —" invariants into their general parents, with Texas as data.
   - Give every regulated decision table in `configurable-rules/` a (state, service) input.

6. **Low-value items as they're touched:** `state_of_tx`, `mud`, the language list, units, comments and error texts citing §7.45, and UI copy.

**Stopping rule for this work:** no new patch lands with a statute in a fixed list, a constant or a branch on a state, cause or service name. A review checks exactly that, and the ZZ battery proves it.

---

## 5. Decisions needed

**From Ryan**

1. **The four-layer shape:** places, law rules, utility choices, mechanism. In particular:
   - law rows are **held by Tally, not the utility**;
   - one typed table per rule family;
   - the lookup refuses when no row is in force.

   Holding law centrally has a running cost. Someone at Tally has to track amendments to 16 TAC and enter the rows. The upside is that every Texas utility gets the same, cited rule.
2. **Sequencing.** Build places first and rebuild A-2 on them. The alternative is to rebuild A-2 on a state column alone and add places later, which would redo A-2's keys a second time.
3. **Scope of step 4.** Re-key all landed Texas law now, or only before a second state is signed?

   I recommend now, at least for deposits, surcharges and the `gas`-keyed correction rules. Application code will start reading those shapes, and each shape it reads makes the change dearer.

**From Kyle** (his rulings stand; these are questions about how they become data)

1. **The resolution date:** when a correction reaches back across a rule change, which rule applies? The one in force for each billed period, at the discovery date, or at the correction date?
2. **Which of his rulings are a reading of Texas text, and which are a general principle?**
   - Examples of readings: R-32 (forfeit whole), R-34 ("last test" of any outcome), R-30 (estimated-bill buckets).
   - Examples of principles: R-33 (a bill computed wrong is not a meter that measured wrong), R-25 (the direction test per period).

   The Texas readings become Texas rows. The principles stay in code.
3. **The six stale or contradictory values** listed in §3.13.
4. **Who is "protected" is law, but where the line falls for "small commercial" is the utility's tariff.** Is that the right split for CCK-14?

---

*Detailed per-slice reports, with line numbers:*
- [texas-only-audit-2026-09-28/01-base-part1.md](texas-only-audit-2026-09-28/01-base-part1.md) — `tu.sql` 1–5700
- [02-base-part2.md](texas-only-audit-2026-09-28/02-base-part2.md) — `tu.sql` 5700–11353
- [03](texas-only-audit-2026-09-28/03-patches-540-541.md) — v5.4.0 and v5.4.1
- [04](texas-only-audit-2026-09-28/04-patches-542-01-06.md) — v5.4.2-01…06
- [05](texas-only-audit-2026-09-28/05-patches-542-07-11.md) — v5.4.2-07…11
- [06](texas-only-audit-2026-09-28/06-patches-12-13.md) — v5.4.2-12 and -13
- [07](texas-only-audit-2026-09-28/07-tu-docs.md) — this repo's docs
- [08](texas-only-audit-2026-09-28/08-gbm-docs.md) — GBM rulings and rules model, including a table of ~95 ruling codes and where each should live
- [09](texas-only-audit-2026-09-28/09-ui-concepts.md) — UI prototype

---

## 6. The second drift: application logic in the schema (added 2026-09-28)

**What happened.**
- The invariant register grades each rule on one scale: `structurally-enforced` (the schema makes a violation impossible) sits at the top, and `requires-application-discipline` sits below it, as if it were a partial failure.
- With no application code being written, every patch aimed to raise grades, so rules became triggers.
- Review rounds then treated the app role as an attacker, which pushed more logic into the database. A-2 is the clearest case: 3,757 lines of PL/pgSQL, and six review rounds on one function.
- Trigger bodies are also the easiest place to type a Texas literal. So this drift and the Texas drift reinforced each other.

**What the schema is for in this phase.** An invariant is at parity when the schema can:
1. **store** everything the rule needs and everything it produces: the inputs, the configurable parameters (per state for law, per utility for tariff and policy), the decision, and which rule row produced it;
2. **protect** record integrity that must hold whoever writes: tenant isolation, issued bills that can't change, the append-only ledger, timestamps the database stamps itself, keys and uniqueness;
3. **leave evaluation to the C# core.** "Evaluation" means computing windows, caps, interest, eligibility and which rule applies. The scenarios describe it, and the C# tests prove it.

**What follows (proposals, for Ryan to confirm).**
- **A-2 is re-scoped to parity:**
  - per-state rule tables;
  - the case, evidence and event tables;
  - the freeze and approval *records*;
  - integrity constraints.

  The evaluation triggers and gates drop out, and their logic becomes scenario material for the C# core. What the r7 battery taught us carries over as scenarios.
- **Landed patches:** trigger logic that applies law is replaced over time by follow-up patches, since `tu.sql` is append-only. The worst cases:
  - `enforce_deposit_event`'s accrual and refund refusals, and `deposit_refund_trigger_state`;
  - `enforce_deposit`'s cap branch;
  - the surcharge shape and cap checks;
  - `tax_exemption_certificate_required`;
  - the `service_type = 'gas'` correction rules.

  What those triggers encode is recorded as scenarios before they go.
- **The register's grading needs a re-cut** (GBM, with Kyle). For rules that are evaluations, "the schema represents it, the core evaluates it" should be the *target* grade, not a gap.
