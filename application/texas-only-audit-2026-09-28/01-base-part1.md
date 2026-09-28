# Texas-only architecture audit — sql/tu.sql lines 1–5700 (v5.2.1 base, part 1)

## Summary
- Scope read in full: functions (1–1399), all base tables/views/matviews (1400–4985), PK/UNIQUE constraints (4986–5700).
- The base schema has **no jurisdiction concept at all**: no state/place/service-type keyed rule table exists in this range. The only jurisdiction keys are free-text `service_locations.state`/`county`/`city` and a single address `tenants.state`. Every statutory rule is either a tenant column/JSON default, a closed CHECK list, or a constant in a matview.
- Explicit Texas literals in structure: `rate_items.calc_owner` allows `'state_of_tx'`; gas-only "RRC requires full correction" void/rebill rule keyed on `service_type`; "RRC-compliant" correction-rate default; Texas Tax Code ch. 151 platform taxability defaults; `'mud'` community type; "{12,1,2} for Texas" winter months.
- Hardest-coded statutory numbers: unclaimed-property clock in `credit_aging_statistics` (1095 / 1005 / 365 days, 60-day due-diligence, $250 due-diligence threshold, 60-day deposit-refund) — pure constants in a view.
- Statutory closed lists: disconnect-protection categories, dunning/disconnection stages, tax-exemption reasons (two different lists), customer classes, escheat notice methods, franchise `applies_to` shapes, consumption/rate units, gas usage formulas.
- Gas-first shape: `gas_*` columns on `meter_readings`, `invoice_line_items`, `meters`, `rate_schedules`; WNA tables with Texas-style HDD formula and `per_mcf` default; franchise fees keyed only by `city_name` with an `inside_city_limits` boolean.
- Class a (partial) examples: invoice tax breakdown by jurisdiction; escheat jurisdiction recorded per event/credit; tax exemptions dated and per service type; rate schedules carry regulatory authority/tariff refs. They record facts, but no rule is looked up by jurisdiction.
- Counts: a = 5, b = 18, c = 20 (43 findings; the meter test/size entry is b + c, counted as b).

---

## Theme 1 — Explicit Texas literals in structure

### rate_items.calc_owner allows 'state_of_tx'
- where: sql/tu.sql:4105 — CHECK rate_items_calc_owner_check
- rule: who computes a rate component; a named Texas state value sits in the closed list — source: none cited
- class: c
- other states: an Oklahoma, Louisiana or New Mexico tenant has no `state_of_ok`/`state_of_la`/`state_of_nm`, so it must mislabel state-set components (e.g. state pipeline-safety or gross-receipts pass-throughs) as `external`/`regulatory`
- fix: replace with generic `state_government` (plus optional `jurisdiction_code` column), or an FK to a calc-owner reference table — size: S

### Gas void-only / rebill-threshold carve-out "RRC requires full correction"
- where: sql/tu.sql:4796 and 4803 — COMMENTs on tenants.void_only_unbilled_disposition, tenants.void_rebill_threshold
- rule: gas meters ignore both tenant settings; void-only without rebill allowed only for duplicate and wrong_customer/no-occupant; gas always needs a full correction run — source: "RRC" (no clause cited)
- class: c (documented engine behavior branching on `service_type = 'gas'`, not on jurisdiction)
- other states: this is a Texas-RRC gas rule applied to all gas everywhere, and to no water/electric anywhere. Another state's gas regulator may allow threshold adjustments. A Texas water utility regulated by PUCT/TCEQ may need its own rule. None of this can be expressed.
- fix: a `correction_policy` rule table keyed (state_code, service_type, effective_from/to) with `void_only_allowed_reasons[]`, `adjustment_threshold_allowed`, source_note, plus a lookup function the engine calls instead of testing `service_type='gas'` — size: M

### Correction rate-date default "RRC-compliant"
- where: sql/tu.sql:2363 (DEFAULT 'historical'), 2364 CHECK, 2424 COMMENT — billing_runs.correction_rate_mode
- rule: corrections rebill at rates in effect for the original period — source: "RRC-compliant default"
- class: c (column DEFAULT stands in for a regulatory rule)
- other states: some commissions or tariffs may require current rates, or the lower of the two, for backbilling or corrections. The CHECK list has no `lower_of`. Guess: verify per state.
- fix: default read from a jurisdiction rule row (state, service_type → default correction rate basis); widen modes if needed — size: S

### Ad hoc charge taxability defaults = Texas Tax Code ch. 151
- where: sql/tu.sql:1493–1504 — COMMENT on adhoc_charges.is_taxable (platform defaults per charge_type); override via tenant.settings.adhoc_taxability_overrides (also 4673)
- rule: which fee types are sales-taxable — source: Texas Tax Code Chapter 151
- class: b (platform defaults are Texas; the override is keyed by tenant, not by taxing jurisdiction)
- other states: sales-tax treatment of reconnect, tap and late fees differs by state, and by city/county within a state. A tenant serving two states can't hold two override sets.
- fix: `charge_type_taxability` table keyed (state_code[, locality], charge_type, effective_from/to) with source_note, seeded with the Texas rows; the tenant override stays as a layer on top — size: M

### communities.community_type 'mud'
- where: sql/tu.sql:2452 — CHECK communities_community_type_check
- rule: Texas Municipal Utility District as a structural category — source: none
- class: c (low impact)
- other states: other states' special districts (e.g. metro districts, CDDs, PUDs, water/sanitation districts) are missing or have to use `other`
- fix: make community types tenant/reference data (the pattern already exists in `custom_location_types`), or a generic `special_district` plus a free label — size: S

### Winter-average months "Typical: {12,1,2} for Texas"
- where: sql/tu.sql:4228 — COMMENT rate_schedules.winter_avg_months; 2938 customer_winter_averages.winter_year (Dec–Feb year rule)
- rule: the sewer winter-average window. It is data per rate schedule, which is correct; the comment treats Texas as the norm.
- class: b (tenant data, fine; `winter_year` = "year the winter ended" is fine for any US state)
- other states: other states use Nov–Mar or Jan–Mar windows. That is already expressible, so the only risk is the comment's default.
- fix: none structural; drop "for Texas" when app defaults are set — size: S

---

## Theme 2 — Disconnection, protections, collections

### Disconnect-protection categories closed list
- where: sql/tu.sql:2533 — CHECK customers_disconnect_protection_type_check
- rule: protected groups (medical_certificate, elderly_disabled, military_deployment, bankruptcy_automatic_stay, regulatory_moratorium, payment_arrangement, pending_dispute, other). These mirror the 16 TAC §7.460 categories — source: none cited
- class: c
- other states: missing categories include life-support equipment (electric), LIHEAP / energy-assistance pending, households with infants or seniors (varies by state), domestic-violence protections, and temperature-based or winter-season holds (Oklahoma and Louisiana use weather-based limits, New Mexico a seasonal winter moratorium — believed, verify). Each has its own certificate length and renewal count.
- fix: a `disconnect_protection_types` reference table keyed (state_code, service_type, code, effective_from/to) with max_duration_days, renewals_allowed, source_note; the customer row gets an FK — size: M

### One protection per customer, with a single expiry
- where: sql/tu.sql:2495–2499 — customers.do_not_disconnect, disconnect_protection_type/start/expiry/notes
- rule: a customer holds at most one protection, at customer level rather than per service or location
- class: b
- other states: concurrent protections are common (e.g. a medical certificate plus a winter moratorium). Rules differ by service type at the same customer (gas protected, water not). The shape can't express either.
- fix: a child table `customer_disconnect_protections` (customer, location/service_type, type FK, start, expiry, certificate ref) — size: M

### Protection-expiring window 30 days
- where: sql/tu.sql:2614, 2617 — matview compliance_statistics
- rule: warn 30 days before protection expiry (and 60 days for tax exemptions, 2602/2606)
- class: c (low; operational, but the certificate-renewal notice lead time can be statutory)
- other states: renewal-notice lead times differ per rule (guess)
- fix: read the lead time from the protection-type row — size: S

### Dunning / disconnection stage ladder
- where: sql/tu.sql:1690 — CHECK invoices_dunning_stage_check; 1736 COMMENT; 2968 CHECK dunning_events_event_type_check
- rule: fixed sequence current → reminder → late_fee → shutoff_warning → shutoff_scheduled → disconnected → collections/written_off
- class: c
- other states: some states require a second notice, a 48-hour or 24-hour pre-disconnect contact, a field visit or door hanger, notice to a third party, or a hearing offer. None of these can be a stage or event. The `dunning` settings key is only "reserved" (4717).
- fix: a jurisdiction-keyed collection-process table (ordered steps with min days and notice method, per state/service_type/customer class, effective-dated); keep a generic event log with `step_code` FK — size: L

---

## Theme 3 — Deposits

### Deposit held as scalar columns on customers
- where: sql/tu.sql:2500–2506 — customers.deposit_amount, deposit_status, deposit_received/refund dates, deposit_interest_earned; 2532 CHECK
- rule: one deposit per customer, and interest "earned" stored as a number with no rate source
- class: b
- other states: deposit caps (e.g. Texas-style "1/6 of annual" or "2× average bill" versus other states' multiples), mandatory interest rates set annually per state, refund-after-N-months-of-good-payment, and per-service deposits all need data. There is also nowhere to record which rate or rule computed the interest.
- fix: a `deposits` table (per customer/location/service_type) plus a `deposit_rules` table keyed (state_code, service_type, customer_class, effective_from/to) with max_multiple, interest_rate, refund_after_months, source_note — size: L

### Deposit also modeled on payments
- where: sql/tu.sql:3860–3861, 3877 — payments.is_deposit, deposit_status CHECK
- rule: a second, parallel deposit status machine (without `none`/`refund_pending`)
- class: b
- other states: duplication only; it blocks a clean per-jurisdiction deposit model
- fix: fold into the `deposits` table above — size: S

### Deposit refund overdue = 60 days
- where: sql/tu.sql:2712 — matview credit_aging_statistics.deposit_refund_overdue
- rule: a deposit-refund credit is overdue after 60 days — source: none cited
- class: c
- other states: refund deadlines after service ends differ by state and commission (guess)
- fix: read from deposit_rules.refund_deadline_days — size: S

---

## Theme 4 — Unclaimed property (escheat)

### Dormancy clock hardcoded in a matview
- where: sql/tu.sql:2705–2715 — matview credit_aging_statistics (aging_bucket, above_due_diligence_threshold)
- rule: escheat due at 1095 days of inactivity (3 years); dormancy_approaching at 1005 (90 days before); stale at 365; due diligence overdue 60 days after notice; due-diligence threshold $250 — source: none cited (matches Texas Property Code ch. 74 as understood; verify)
- class: c
- other states: dormancy periods for utility deposits and refunds are often 1 year under RUUPA-derived statutes (guess, verify per state). Due-diligence thresholds are often $50. Notice windows differ, e.g. 60–120 days before the report. The holder's state follows the owner's last-known address, not the tenant's state.
- fix: an `unclaimed_property_rules` table keyed (state_code, property_type, effective_from/to) with dormancy_days, due_diligence_min_amount, due_diligence_window_days, report_due_date rule, source_note; the view joins on the owner's address state — size: M

### escheat_status "within 90 days"
- where: sql/tu.sql:2684 — COMMENT customer_credits.escheat_status (and 2707 constant 1005 = 1095−90)
- rule: 90-day approaching window
- class: c
- other states: as above
- fix: derive from the rule row — size: S

### Escheat notice methods closed list
- where: sql/tu.sql:3001 — CHECK escheatment_events_notice_method_check
- rule: email / first_class / certified / registered mail
- class: c (low)
- other states: some states require or allow publication notice, or electronic notice only with consent. Methods are statutory per state.
- fix: move to the reference table, or add values tied to the rule row — size: S

### Minimum refund amount and below-threshold disposition
- where: sql/tu.sql:4609–4611, 4621 — tenants.minimum_refund_amount DEFAULT 5.00, below_threshold_action CHECK ('hold_for_escheat','apply_to_donation_if_opted_in'); 2548 customers.donation_opt_in COMMENT "residuals follow state escheatment law"
- rule: small-credit handling tied to escheat law, stored per tenant
- class: b
- other states: whether a holder may keep, donate or de-minimis-write-off small balances is state law. Some states forbid netting small amounts. A two-state tenant needs two rules.
- fix: keep the tenant preference, but validate it against the state rule row (allowed dispositions, de minimis floor) — size: S

---

## Theme 5 — Tax

### Two different closed tax-exemption lists
- where: sql/tu.sql:2539 — CHECK customers_tax_exemption_reason_check (includes 'residential', 'diplomatic', 'reseller'); 2882 — CHECK customer_tax_exemptions_exemption_type_check (non_profit, government, agricultural, industrial, sales_for_resale, religious, educational, medical, other)
- rule: exemption categories. 'residential' as an exemption reason reflects Texas Tax Code §151.317 (residential gas/electric exempt) — source: none cited
- class: c
- other states: exemption categories and certificate types are per state and per taxing authority (state vs city vs county vs special district). Examples: manufacturing, ag or irrigation exemptions, and winter-only residential exemptions (guess). The two lists already disagree with each other.
- fix: a `tax_exemption_types` reference table keyed (state_code[, taxing authority], code, effective dates, source_note); retire the customers.* scalar exemption columns (2508–2514) — size: M

### should_charge_tax() ignores the taxing jurisdiction
- where: sql/tu.sql:755–792 — FUNCTION should_charge_tax
- rule: an exemption applies if active and covering the service type; it is not linked to which tax (state sales, city, franchise) it exempts
- class: b
- other states: a certificate exempting from state sales tax often does not exempt from municipal taxes or franchise fees. Texas has this too, so the shape is wrong even for Texas.
- fix: the exemption row carries `taxing_authority`/`tax_type` FK; the function takes the tax component and matches on it — size: M

### Tax exemptions dated, per service type, with issuing authority
- where: sql/tu.sql:2857–2884 — TABLE customer_tax_exemptions (service_types[], issuing_authority, effective_start/end, verification)
- rule: correct per-record shape: effective-dated, per service type, with the authority recorded
- class: a (partial: authority is free text, not a key)
- other states: works, once the type list and authority are made reference data
- fix: FK issuing_authority to a jurisdiction/authority table — size: S

### Invoice tax breakdown by jurisdiction
- where: sql/tu.sql:1658, 1722 — invoices.tax_breakdown JSONB {jurisdiction, authority, rate_item_id, amount}
- rule: itemized taxes per jurisdiction on the bill
- class: a
- other states: works for any state; the jurisdiction is still free text
- fix: none now; later key to a jurisdiction table — size: S

---

## Theme 6 — Franchise fees and city limits

### franchise_fee_rules keyed by tenant + city name only
- where: sql/tu.sql:3016–3036 — TABLE franchise_fee_rules; 5312 UNIQUE (tenant_id, city_name, effective_date)
- rule: Texas-style municipal franchise model: one percentage per city, `applies_to` IN (total_bill, gross_revenue, base_and_usage, usage_only), customer-type default list, effective_date/expiry_date with no no-overlap EXCLUDE
- class: b
- other states: there is no state_code (two "Springfield"s collide) and no service_type (gas and water franchises in the same city collide on the UNIQUE key). Franchise charges that are per-unit (per Mcf/kWh), fixed per customer, tiered, or capped can't be expressed; nor can county or unincorporated-area fees, or state-level gross-receipts taxes (e.g. Texas Tax Code ch. 182 for gas — believed). Overlapping rows are not prevented.
- fix: rekey as (jurisdiction/place_id, service_type, effective range) with an EXCLUDE constraint; the fee formula becomes calc_type + rate + unit (reuse the rate_items calculation vocabulary); the place references a places table with state — size: M

### inside_city_limits boolean + franchise_city text on locations
- where: sql/tu.sql:4457–4458 — service_locations.inside_city_limits DEFAULT true, franchise_city
- rule: a location is either inside one franchise city or not
- class: c
- other states: overlapping jurisdictions (city + county + special district, or a city in a different state) and locations in ETJs or unincorporated areas with county fees can't be expressed. The DEFAULT true silently applies city fees.
- fix: `service_location_jurisdictions` (location, place_id, place_type, effective range), or place_id FKs resolved from address; drop the boolean — size: M

### rate_schedules.franchise_city text
- where: sql/tu.sql:4186 — rate_schedules.franchise_city
- rule: a tariff tied to one franchise city by name
- class: b
- other states: same name-collision and single-city problems as above
- fix: FK to a place/jurisdiction table — size: S

---

## Theme 7 — Service type and gas-first shape

### Service-type vocabulary repeated as CHECK lists
- where: sql/tu.sql:1476 (adhoc_charges), 3315 (invoice_line_items, +general), 3720 (meters), 4109 (rate_items, +all), 4216 (rate_schedules); unconstrained at 2223 (bill_messages.target_service_types), 2863 (customer_tax_exemptions.service_types)
- rule: service types = water, sewer, electric, gas, stormwater, trash, reclaimed_water
- class: c (not Texas-specific, but every jurisdiction rule table will need to key on this and there is no reference table)
- other states: propane/LPG distribution, district steam or chilled water, and fiber/broadband are missing (guess at demand). Five drifting copies already differ.
- fix: a `service_types` reference table and FKs; the jurisdiction rule tables key on it — size: M

### Gas-specific columns on generic reading/bill/meter/schedule rows
- where: sql/tu.sql:3538–3541 (meter_readings.gas_meter_factor, gas_pressure_corrected_volume, gas_btu_factor, gas_therms); 339–342 (lock whitelist in enforce_reading_validation_workflow); 3304–3307 (invoice_line_items.gas_meter_factor, gas_ccf_used, gas_therms_billed, gas_commodity_rate); 3688–3689 (meters.meter_factor, gas_btu_factor); 4197–4198 (rate_schedules.gas_meter_factor_required, gas_usage_formula); 4195 (sewer_cap_gallons)
- rule: gas volume-correction and therm conversion hardwired as columns
- class: b
- other states: electric (power factor, demand ratchets, TOU) and water need their own conversion data. Gas states that bill in dekatherms or correct for altitude/pressure base (e.g. New Mexico high-altitude pressure bases — believed) need different factors. Each would add more columns.
- fix: a generic `reading_conversions` / `line_item_measure` child (factor_code, value) driven by per-schedule conversion steps — size: L

### Gas usage formula closed list
- where: sql/tu.sql:4212 — CHECK rate_schedules_gas_usage_formula_check (standard, with_meter_factor, with_temp_factor); 4235–4242 COMMENT; 4126–4128 usage_modifier "Gas Temp Factor"
- rule: the three Texas gas volume-calculation shapes
- class: c
- other states: pressure-base or altitude correction, BTU/therm-zone conversion, supercompressibility (large volume) — guess at variants
- fix: express as an ordered chain of usage_modifier rate items (the mechanism exists) and drop the enum — size: M

### Consumption and rate unit closed lists
- where: sql/tu.sql:3577 — CHECK meter_readings_consumption_unit_check; 4108 — CHECK rate_items_rate_unit_check; 4954 — CHECK wna_monthly_adjustments_adjustment_unit_check; 3492 DEFAULT 'gallons'
- rule: allowed units
- class: c
- other states: dekatherm/MMBtu (common gas billing unit outside Texas), kVAR/kVARh, and a per_kw demand rate unit are missing. rate_unit lacks `per_kw` even though consumption_unit has `kw`.
- fix: a units reference table with conversions — size: S

### Rate component catalogue = Texas gas riders
- where: sql/tu.sql:4106 — CHECK rate_items_calculation_type_check; 4120–4130 COMMENT (Customer Charge, GRIP, Pipeline Safety, GCA, CRRC, Sales/Franchise Tax, WNA-style `formula` escape hatch); 3323 COMMENT (GCA, CRRC)
- rule: mechanisms are generic. The examples are Texas statutory riders: GRIP interim adjustments, the RRC pipeline-safety fee, and CRRC (Uri securitization).
- class: b (mechanism fine; WNA pushed to a `formula` escape hatch)
- other states: decoupling or revenue true-ups, purchased-gas adjustments with over/under-recovery, and percent-of-bill riders with caps — mostly expressible, but `formula` is opaque to the engine
- fix: none urgent; document state riders as rate_item data, and make `formula` a real rider mechanism if a second state needs it — size: S

### WNA model tenant-keyed with Texas-style HDD formula and defaults
- where: sql/tu.sql:4963–4984 — TABLE wna_zones (active_months DEFAULT {11,12,1,2,3,4}, normal_hdd, base_load_consumption, heating_factor); 4939–4956 wna_monthly_adjustments (adjustment_unit DEFAULT 'per_mcf'); 4185 rate_schedules.wna_zone_id; 469 referenced by correction rate date
- rule: weather normalization as a Texas-tariff HDD formula shape
- class: b (a tariff mechanism, so tenant-level is fine; the defaults and formula columns are Texas-shaped)
- other states: WNA formulas differ (per-class R-factors, billing-cycle-HDD weighting, deadbands, caps). Some states use decoupling instead of WNA. Electric has no WNA. The Nov–Apr default is a Texas season.
- fix: drop the month DEFAULT; generalize the formula params into JSON or param rows versioned per tariff — size: M

### Estimation defaults by service type
- where: sql/tu.sql:4263 — COMMENT rate_schedules.estimation_method (gas → same_period_prior_year; others → historical_average_3mo); 4211 CHECK estimation_method list; 4650–4656 tenants.settings.estimation (max_consecutive_estimates 3, default_method_*)
- rule: estimation methods and the consecutive-estimate cap
- class: b (tenant JSON + platform defaults; the cap is statutory in many states)
- other states: several states cap consecutive estimated bills (e.g. at 2 or 3, sometimes requiring a customer-read card) and prescribe methods. Texas 16 TAC has its own. None of this is jurisdiction data.
- fix: an `estimation_rules` row keyed (state, service_type) with max_consecutive, allowed_methods, source_note; the tenant setting may only tighten it — size: M

### Meter test interval per meter; meter sizes water-only
- where: sql/tu.sql:3691–3694 — meters.test_interval_months, next_test_due_date; 3721 — CHECK meters_size_check (5/8"–12")
- rule: test cadence is a free per-meter number; sizes are water pipe sizes
- class: b (test interval); c (size list)
- other states: meter-testing intervals are regulated per state, service and meter class (sample-testing plans vs periodic). Gas meters are sized by capacity (e.g. 250/400 cfh or rotary/turbine class) and electric by form/class. They can't be recorded.
- fix: a `meter_test_rules` table (state, service_type, meter_class → interval/sample plan); a meter-size reference per service_type — size: M

---

## Theme 8 — Customer classes

### Customer class closed list (twice) and default applicability lists
- where: sql/tu.sql:2531 — CHECK customers_customer_type_check; 4210 — CHECK rate_schedules_customer_type_check; 3022 franchise_fee_rules.applies_to_customer_types DEFAULT; 4088 rate_items.applies_to_customer_types DEFAULT
- rule: classes = residential, commercial, small/large_commercial, industrial, government, wholesale
- class: c
- other states: tariff classes differ: irrigation/agricultural, public authority, schools, churches, transport vs sales service, interruptible, and low-income/CARE-style discounted residential (e.g. California CARE is a class-like program). Statutory protections often key on class.
- fix: tenant tariff classes as data (a per-tenant class table) mapped to a small platform "regulatory class" set used by jurisdiction rules — size: M

---

## Theme 9 — Bill timing and payment

### Due date default 21 days; warning below 15
- where: sql/tu.sql:2253 — billing_cycles.due_days_after_bill DEFAULT 21; 4676–4679 tenants.settings.billing.payment_terms_days 21, issue_warning_below_payment_terms_days 15
- rule: the minimum days between bill and due date. 15 looks like a statutory floor, given as a tenant JSON default — source: none cited
- class: b
- other states: minimum due periods differ by state and service (commonly 15–25 days; some count from mailing, some from rendering; guess). A warning is also weaker than enforcement.
- fix: a `billing_timing_rules` row (state, service_type, min_days_to_due, basis mailing/rendering); validate billing_cycles against it and raise, as the meter-accuracy lookup does — size: M

### Payment allocation "most regulator-friendly"
- where: sql/tu.sql:4606, 4627, 4733 — tenants.payment_allocation_strategy
- rule: oldest_first default; the allowed list has no class-based ordering
- class: b
- other states: some commissions require partial payments to go to regulated utility charges before non-regulated or third-party charges, or to arrears vs current in a set order (guess, verify). Not expressible.
- fix: allow a jurisdiction-mandated allocation order (priority by charge category) that overrides the tenant preference — size: M

### Service-transition vacancy days and fees in tenant JSON
- where: sql/tu.sql:4642–4647 — tenants.settings.service_transition (turn_on_minimum_vacancy_days 3, fee defaults)
- rule: reconnect/turn-on fee defaults per tenant
- class: b (low; these are tariff numbers, so tenant-level is fine; maximum fee caps can be statutory)
- other states: some states cap reconnect fees or bar them in certain cases (e.g. after an erroneous disconnect; guess)
- fix: optional cap check against a jurisdiction rule row — size: S

---

## Theme 10 — Jurisdiction keys (where rules would attach)

### Tenant has a single address state; no operating jurisdictions
- where: sql/tu.sql:4590–4633 — TABLE tenants (address `state` only)
- rule: implicit one-state tenant; nothing records which states or regulators a tenant operates under
- class: b
- other states: a utility serving Texas and New Mexico (or a gas + water utility with two regulators) can't be modeled
- fix: `tenant_jurisdictions` (tenant, state_code, service_type, regulator, certificate/docket) — size: M

### service_locations.state / county / city free text
- where: sql/tu.sql:4448–4451 — service_locations city, county, state (NOT NULL, no validation); 2489–2490 customers.billing_county/billing_state
- rule: the only per-location jurisdiction key, unvalidated
- class: a (partial — the right place for a lookup key, but free text; rule lookups like meter_accuracy_threshold_for(state,…) will depend on its quality)
- other states: needs to be a validated 2-letter code for any per-state rule lookup
- fix: CHECK/FK to a states table; optional place_id — size: S

### Tariff and regulatory references on rate schedules and history
- where: sql/tu.sql:4187–4190 — rate_schedules.regulatory_authority, tariff_number, tariff_document_url, regulatory_code; 4045/4066 rate_item_history(_archive).regulatory_reference with effective_date/end_date
- rule: each tariff records its regulator and citation; rate values are effective-dated with a regulatory reference
- class: a
- other states: works for any regulator (free text)
- fix: FK regulatory_authority to a regulator table when one exists — size: S

### Escheat jurisdiction recorded per credit and event
- where: sql/tu.sql:2650 — customer_credits.escheated_to_jurisdiction; 2993–2994 — escheatment_events.jurisdiction, regulatory_reference
- rule: the destination state is recorded, not assumed
- class: a (records the fact; the rules that decide it are hardcoded, see Theme 4)
- other states: fine
- fix: key to states table — size: S

---

## Theme 11 — Minor closed lists with regulatory flavor

### Preferred languages closed list
- where: sql/tu.sql:2537 — CHECK customers_preferred_language_check (en, es, vi, zh, ko, other)
- rule: Texas-region language set
- class: c (low)
- other states: some states require bills or notices in the languages of large customer populations (e.g. California lists more languages — guess at exact rule), which may include tl, ru, ar, ht and others
- fix: ISO 639 code with a CHECK on format; required-notice languages per jurisdiction as data — size: S

### Disconnect/NSF-related thresholds in matview
- where: sql/tu.sql:3959–3960, 3966 — matview payment_health_statistics (≥2 NSF in 90 days, ≥3 in 12 months, ≥2 auto-pay failures)
- rule: returned-payment patterns. These can drive deposit or cash-only requirements, which some states regulate (guess).
- class: c (low; currently informational)
- other states: if these later gate deposit demands, the counts must come from jurisdiction data
- fix: read thresholds from the deposit/credit rule row if used for action — size: S

### RRC audit trail comment on void notes
- where: sql/tu.sql:1827 — COMMENT invoices.void_reason_notes
- rule: notes "recommended for RRC audit trail" (void_reason_code CHECK at 1693 is generic)
- class: c (comment-level; the note is optional everywhere)
- other states: other regulators may require a documented reason on every rebill
- fix: make "notes required" a jurisdiction rule flag — size: S
