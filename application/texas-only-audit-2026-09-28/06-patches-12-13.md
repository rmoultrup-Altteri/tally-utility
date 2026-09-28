# Audit 06 — v5.4.2-12 (meter test history) and v5.4.2-13 (A-2 backbilling caps, unmerged/paused)

Scope read in full: `sql/v5.4.2-12-meter-test-history.sql` (1,790 lines), `sql/v5.4.2-13-backbilling-caps.sql` (3,757 lines). Cross-checked `tu.sql:11569` (jurisdictions) and `tu.sql:2531` (customer_type).
Paths below are abbreviated: `-12:` = v5.4.2-12, `-13:` = v5.4.2-13.

## Summary

- **-12 is mostly clean.** `meter_accuracy_thresholds` is the model to copy. The Texas law still in -12 sits in how a test is judged and what "last test" means, not in the table. Five places: the strict "more than" boundary, the max-of-loads aggregation, "non-registering = every load zero", the closed test-kind list with Texas's customer-requested field list, and `meter_governing_test()`'s reading of "last test". The R-36 gate also hardcodes `interval '6 months'` (`-12:1614`), which is Texas's cap number.
- **-13 has a data table but a Texas-shaped one.** The cap *numbers* (6, 3, enforce 6) are rows. But the table is keyed per tenant, not per state, and the "state default" is a NULL jurisdiction on a table with no state column. It has no effective dating. Every *vocabulary* in it is a closed CHECK taken from §7.45 or Kyle's rulings: the 8 causes, the protected/unprotected class, the billable formulas, and the enforceable scopes.
- **The heaviest -13 problem is decision logic keyed on cause names.** These are in triggers and functions, not data: which causes are test-anchored; that only `meter_error` reads the last test; that only a fast `meter_error` carries a mandatory refund, holds and the under-reach check; that only `rate_misapplication` may be reissued, and that it is uncapped by omission; that `tampering_bypass` is the supervisor-gated cause; that R-32's straddle forfeits whole; and that favourable periods are uncapped. Any other state's row set would be judged by Texas's decision logic.
- **Two Texas constants are buried in general mechanisms:** `interval '6 months'` in the evidence fence (`-13:2167`) and in the R-36 gate (`-12:1615`).
- **Customer class is a tenant mode (CCK-14)**, `regulatory_class_mode` (`-13:304`), with a hardcoded type→protected mapping (`-13:877`). Who is "protected" is state law, so it belongs in per-state data.
- **The mechanism is genuinely general and should survive the redesign.** That covers the case, the evaluation, the input fingerprint, the freeze, holds, approvals, the per-period evidence, the forfeiture surface, the event log, the deployment hardening and the acquisitions table. A redesign replaces the vocabularies and the cause-name branches with attribute columns read from a per-jurisdiction rule table.
- Counts: **a = 5, b = 6, c = 19** (30 findings).

---

## Theme 1 — Accuracy threshold and test judging (-12)

### Accuracy threshold table (the model)
- where: -12:584–621 — table `meter_accuracy_thresholds`; -12:623–656 — function `meter_accuracy_threshold_for`; -12:612–618 TX gas seed row
- rule: "more than nominally defective" = >2.0% — source: 16 TAC §7.45(7)(B)(iv)(II), F-3, erratum E-1
- class: a
- other states: The table can already take any state or service row. Its limits are in the next finding (a symmetric single figure).
- fix: none to the shape. Consider adding a `place`/sub-state key only if a real case appears. Stay state-level for now. — size: S

### Threshold resolved from the meter's premise state and stamped on the test
- where: -12:1233–1252 — `enforce_meter_test_record()`, `threshold_id/threshold_pct/threshold_state` columns (-12:728–730)
- rule: the threshold is resolved by `service_locations.state` of the meter's current location, on the test date, and the figure is copied onto the row
- class: a
- other states: works as-is for any state row. Residual R5 (-12:1686): it resolves the meter's *current* location's state, not the deployment's on the test date. That is harmless while only TX is seeded, and wrong the day a meter crosses a state line.
- fix: once deployments are trustworthy (the -13 section 4 hardening), bind the state to the deployment covering `test_date`. — size: S

### Threshold is one symmetric figure per state/service
- where: -12:588 `threshold_pct numeric(6,3)`; -12:1042 `max_abs_error_pct <= p_threshold_pct`; -12:1248–1249
- rule: one ± tolerance, the same in both directions and at every load point (the Texas gas shape)
- class: b
- other states: water accuracy standards (AWWA C700-family, commonly adopted by state PUCs) set **different limits by flow rate and asymmetric bands**, e.g. roughly 98.5–101.5% at normal flow and 95–101.5% at low flow (from memory, verify). Electric state rules often set separate fast and slow limits or a different figure per load (guess, verify per state). One `threshold_pct` can't express a low bound ≠ high bound, or per-test-point limits.
- fix: `threshold_fast_pct`, `threshold_slow_pct`, plus an optional child `meter_accuracy_threshold_points(threshold_id, test_point_kind, fast_pct, slow_pct)`. `load_point` would then need a controlled vocabulary per service (`low_flow`/`intermediate`/`full`, `light_load`/`full_load`). — size: M

### Outcome derivation: strict ">", max-of-loads aggregation, non_registering = all zero
- where: -12:1013–1055 — function `meter_test_derive_outcome` (1039 all-zero → non_registering; 1042 `<=` = accurate; 1045–1052 sign of the largest deviation); -12:1248–1249 `found_defective`; comment -12:844
- rule: "MORE than 2.0%" (a deviation at the threshold is accurate); a test fails if ANY load exceeds; non-registering only if EVERY load reads zero — source: §7.45(7)(B)(iv)(II), (v)(II); Kyle R-39 (zero registration only)
- class: c
- other states: (1) Boundary wording varies ("exceeds", "within ±x% inclusive"), so the inclusive/exclusive choice is per rule. (2) Many electric rules judge on a **weighted average** of full-load and light-load accuracy, not the worst load (common in PUC meter-accuracy rules; verify per state). Gas and water rules sometimes average the test points too (guess). (3) "Non-registering" vs "slow" is a Texas-specific split between (v)(I) and (v)(II). Another state may not distinguish them, or may call a meter non-registering below some registration percentage (guess).
- fix: add to the threshold row: `boundary_inclusive boolean`, `aggregation text` from a vocabulary (`worst_point`, `weighted_average` with per-point weights in the child table, `each_point_own_limit`), and `non_registering_rule` (`all_points_zero`, `below_pct:n`, `not_distinguished`). The derivation reads these. The one-formula property (`meter_test_error_pct`, -12:668) is general and stays. — size: M

### Test kinds are a closed list, and one kind carries §7.45 duties structurally
- where: -12:760–761 CHECK `meter_tests_test_kind_check`; -12:711 generated `customer_requested`; -12:798–800 CHECK `meter_tests_customer_requested_check` (location and customer required); comments -12:835–838
- rule: periodic / customer_requested / complaint / post_repair / acceptance / other (D-2). `customer_requested` alone triggers the (7)(B)(ii) record and the (7)(B)(iv)(I) four-year same-customer/same-location look-back (F-5).
- class: c
- other states: many state rules have a **referee test**, one requested through or witnessed by the commission, with its own fee and record duties (common; verify per state). Here it can only go under `other`, which carries no duties. A state whose free-test look-back is per *meter* or per *account* rather than per customer at a location would find location+customer required for no reason. Water utilities often have "sample/statistical" test programs as a kind (guess).
- fix: a platform `meter_test_kinds` reference table (kind, description), plus a per-jurisdiction `meter_test_kind_duties(state, service_type, kind, requires_customer, requires_location, full_record_required, lookback_scope, lookback_years, effective_from/to)`. The CHECK becomes an FK, and the customer_requested CHECK becomes a trigger reading the duty row. — size: M

### The (7)(B)(ii) test-record field list as a CHECK
- where: -12:770–775 CHECK `meter_tests_full_record_fields_check` (performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test > 0); comment -12:766–769
- rule: the fields Texas requires on a test record — source: §7.45(7)(B)(ii), F-2
- class: c
- other states: other rules require different items, such as as-found *and* as-left readings, the test-point flow rates, a seal number, or a technician certification ID (guess, typical of PUC test-record rules). `multiplier_at_test` is a gas/electric notion, and a water meter row may have none.
- fix: keep the columns and move "which are required" into the duty row from the previous finding (`required_fields text[]`), checked by trigger. — size: S

### Gas-specific unit columns inside general mechanisms
- where: -12:722 `meter_tests.gas_btu_factor_at_test`; -13:1005/1010 and 1039/1044 (`backbilling_units_match`, `backbilling_units_not_above` compare `gas_ccf_used`, `gas_therms_billed`)
- rule: the units that define "correct units" (R-39) include gas volume and therms
- class: b
- other states: harmless for water/electric lines (the columns are NULL on both sides and compare equal), but "correct units" for electric would need kWh and demand kW. A demand-billed electric line whose kW changed would pass as "same units" if only `usage_quantity` matched (guess about how electric lines will be modelled).
- fix: compare a service-neutral set, `usage_quantity` plus a per-service list of billing-determinant columns read from a small table, not a hardcoded gas list. — size: S

### Test-interval rules are per meter, not per jurisdiction
- where: -12:136–137 and -12:1393 (`next_test_due_date`, `test_interval_months` stay tenant-writable scheduling fields on `meters`; R-31 excludes scheduling)
- rule: none enforced. The periodic test interval is a free per-meter number.
- class: b
- other states: periodic test intervals are commonly set by state rule, per service and meter size/type (e.g. years between tests for small diaphragm gas meters, or a sample-testing program instead). That is common; the figures vary, so verify per state. A per-meter number can't show whether a meter is out of compliance with its state's interval. `meter_governing_test()` correctly never reads it (-12:1524–1529), so this is not a backbilling risk.
- fix: when scheduling is built, a `meter_test_interval_rules(state, service_type, meter_class/size_band, interval_months | sample_program, effective_from/to)` table. `meters.test_interval_months` becomes a derived default or an override with a reason. — size: M (future work, not blocking)

### "Last test" = most recent test strictly before the anchor, any outcome
- where: -12:1544–1618 — function `meter_governing_test` (1580–1591 selection; comment 1517–1522); used by -13:2230
- rule: "the last test of the meter" in §7.45(7)(B)(v)(I) = most recent non-superseded test before the discovering test, whatever its outcome or kind — source: R-34 (Kyle took the text over "last accurate test")
- class: c
- other states: other rules phrase the bound as "the last test at which the meter was found accurate", or "the date the error began, if it can be determined". A common fallback is "one-half the time since the last test, not exceeding N months" (from memory, several Midwestern PUC rules; verify). Each needs a different selector, not "any outcome".
- fix: keep one function with a selector parameter held on the cap/window rule: `last_test_any_outcome`, `last_test_accurate`, `last_test_half_interval`. Tie-breaking and supersession handling (-12:1585–1590) are general and stay. — size: S/M

### Absence declarations and gap report (general, noted)
- where: -12:1424–1511 `meter_test_absence_declarations`; -12:1631–1658 view `meter_test_history_gaps`
- rule: attested_none / unknown; with no test, the months cap governs alone (R-35 refinement 5)
- class: a
- other states: the vocabulary is about evidence provenance, not law, so it carries. Only the *consequence* ("the months cap alone") is rule-dependent, and it lives in -13's window formula.
- fix: none. — size: —

---

## Theme 2 — The cap table and its resolution (-13 section 5)

### Cap month numbers are rows (the good part)
- where: -13:780–803 — seed rows (meter_error 6 months shorter-of-test; non_registering 3; rate_misapplication enforce 6); -13:723–728 month counts present exactly under counted scopes
- rule: §7.45(7)(B)(v)(I)/(II), (3)(C)(iii), each row with a `source_note` (R-21)
- class: a
- other states: another state's 12 or 24 months is a row value, as intended. The limits are the key and the vocabularies (the next findings).
- fix: keep `source_note`, the equivalence CHECKs and fail-closed resolution. — size: —

### Cap table is tenant-keyed, NULL jurisdiction stands in for "state", no effective dating
- where: -13:685–760 — table `backbilling_cap_rules` (`tenant_id NOT NULL` 687; `jurisdiction_id` nullable 688, "NULL is the state / filed-tariff default" 750–751; UNIQUE 703–704 with no date range); -13:887–922 `backbilling_resolve_cap` (two levels only, no date argument); -13:2313 `jurisdiction_level` labels `'state_default'` / `'municipal'`; tu.sql:11569 `jurisdictions` has **no state column**
- rule: R-26 two-level most-specific-wins (Texas: RRC state rule, plus municipal original jurisdiction over gas rates inside city limits)
- class: b
- other states: (1) The NULL row is really a *tenant* default, so a tenant serving premises in two states (a TX/OK or TX/NM border system) cannot hold two state defaults for the same service/class/cause, because the UNIQUE forbids it. (2) With no `effective_from/to`, a rule amendment overwrites history. A correction is then judged by today's row, not the row in force for the period, and the `updated_at` in the fingerprint only detects the change. (3) The statute is copied into every tenant, when the brief's model is platform rows. (4) Only two levels. A water rule may sit at county, special district or commission-region level (guess), and "municipal" is a Texas gas-utility notion.
- fix: split it. **Platform** `backbilling_rules(state_code, place_id NULL, service_type, customer_class, cause, …, effective_from, effective_to, source_note)` with EXCLUDE no-overlap on `(state, place, service, class, cause, daterange)`, no tenant_id, read-only to tally_app. Tenant filed-tariff limits stay in tenant data (they already partly do: `backbilling_adverse_limit_months`). Resolve by `(premise state, premise place chain, service_type, class, cause, as-of date)`, where the as-of date is each period's start or the anchor, a ruling to take to Kyle. `jurisdictions` needs a `state_code` or a link into a shared place hierarchy (the pending shared-place restructure, -13:505–507). — size: L

### Seed function writes Texas gas rows into every tenant
- where: -13:766–834 — function `seed_backbilling_cap_defaults` plus the DO block at 825–834 that runs it for every existing tenant
- rule: R-20 table amended by R-39, as literal VALUES inside a function body
- class: c
- other states: a tenant whose premises are in Oklahoma still receives Texas gas rows as its "state default" and resolves them happily. The fail-closed property ("no row → refuse", -13:911–915) is defeated, because a row always exists. Law text sits in code, so an amendment needs a new function version.
- fix: seed once as platform data keyed `state_code='TX', service_type='gas'` with `effective_from`. Tenants need no per-tenant seeding, since resolution goes by premise state. — size: S (given the table from the previous finding)

### Customer class is a binary protected/unprotected CHECK
- where: -13:712–713 CHECK `backbilling_cap_rules_customer_class_check`; -13:2571 evidence `customer_class`; seed -13:779–813
- rule: §7.45 protects "residential and small commercial"; everyone else is outside it — CCK-1…CCK-14
- class: c
- other states: other regimes split differently and often into more than two tiers: residential vs non-residential with different reaches (California utility tariff Rules 17/17.1 give residential and non-residential different backbill periods, from memory, verify); residential-only protection (New York HEFPA's backbilling limit is for residential customers, from memory, verify). "protected/unprotected" also bakes in that a class is either wholly inside or wholly outside one statute.
- fix: replace the CHECK with a per-jurisdiction class vocabulary: `backbilling_rule_classes(state_code, service_type, class_code, effective…)`, and FK the rule's `customer_class` to it. Then the mapping in the next two findings maps a customer onto that state's class codes. — size: M

### regulatory_class_mode tenant setting and its CHECK/DEFAULT
- where: -13:304–349 — `tenants.regulatory_class_mode` DEFAULT `'all_non_residential_protected'` (306), CHECK 309–314, platform-only guard 326–349, config-history keys 357/371; comment 320–321
- rule: CCK-14's default sweeps every non-residential account into §7.45 protection. `explicit_class` / `volumetric_threshold` are Texas's "small commercial" size-tier question.
- class: c
- other states: the mode is per *tenant* but the question is per *state* (plus the utility's tariff tiers). A tenant in two states can't answer it twice. `all_non_residential_protected` is a *Texas* fail-safe. In a residential-only state the same default would wrongly protect every commercial account (over-protection, a revenue risk, not a compliance risk). `volumetric_threshold` exists only because Texas's rule turns on a size tier.
- fix: split into (1) per-jurisdiction data: which customer categories a state's rule protects, and whether it has a size tier (`class_basis: customer_type | size_tier | volumetric`), and (2) tenant data: how *this utility* sizes customers (its tariff tiers or thresholds). Keep the fail-toward-protection default as a *per-jurisdiction* row, not a tenant DEFAULT. — size: M

### backbilling_customer_class() hardcodes Texas's class mapping
- where: -13:842–885 — function `backbilling_customer_class` (871–873 default mode → 'protected'; 877–880 `residential/small_commercial/commercial` → protected, else unprotected)
- rule: CCK-14; "a bare commercial reads as protected"
- class: c
- other states: the mapping from `customers.customer_type` (tu.sql:2531: residential, commercial, small_commercial, large_commercial, industrial, government, wholesale) to class is state law. For example, government accounts are protected in some regimes and not others (guess). The function also takes no date, so the class is "as of now" (R19, -13:3688–3691).
- fix: `backbilling_class_map(state_code, service_type, customer_type, class_code, effective…)` read by the resolver with the period's date. — size: S/M

### Case-level rule resolved as 'protected' regardless of the customer
- where: -13:2225 `backbilling_resolve_cap(…, 'protected', c.cause)` in `meter_correction_inputs`; residual R5 -13:3571–3576
- rule: assumes the protected-class row is always the widest reach, so it bounds which periods are evaluated
- class: c
- other states: true for Texas, where "unprotected" = uncapped (the period set comes from the protected window and unprotected periods then pass). Where the only defined class is `residential`, or the non-residential reach is *longer* than the residential one, the case-level resolve either raises (no 'protected' row) or picks too short a set and silently under-reaches for refunds.
- fix: derive the period-set start as the MIN over window starts for every class/jurisdiction that could apply to the meter's periods, or evaluate every billed period back to a platform ceiling and let each period's own rule decide. — size: S

### Cause vocabulary: R-39's eight causes as a closed CHECK
- where: -13:714–715 CHECK `backbilling_cap_rules_cause_check`; comment -13:680–683, 748
- rule: meter_error, non_registering_meter, rate_misapplication, estimation_catchup, tampering_bypass, billing_constant_error, crossed_meters, unbilled_service — source: §7.45(4)(D)(v), (4)(E)(v)–(vii), (7)(B)(v); R-39
- class: c
- other states: other rules cut causes differently. Many have a single "utility billing error" bucket for rate, constant and crossed meters. New York-style rules turn on **customer culpable conduct** (not the same as tampering; from memory, verify). Some distinguish "customer denied access" as its own backbilling exception (guess, common in PUC rules). Water has leak-adjustment programs that behave like causes (guess). None fits the eight without a CHECK change and a patch.
- fix: platform `backbilling_causes(cause_code, description)` plus per-jurisdiction availability. The cause's *behaviour* goes into attributes (see the next finding) so a new cause needs no code. — size: M

### Case causes and which are test-anchored, hardcoded in CHECK and trigger
- where: -13:1515–1516 CHECK `meter_correction_cases_cause_check` (five causes); -13:1523–1529 CHECK `meter_correction_cases_shape_check` (meter_error/non_registering_meter = test-anchored); trigger `enforce_meter_correction_case()` -13:1689 (`v_test_cause`), 1801–1807 (a test finding may change only to tampering_bypass), 1867–1919 (meter_error needs fast/slow; non_registering_meter needs non_registering; direction from outcome)
- rule: R-39 "the outcome decides the cause"; R-19 cause progression; R-33 delivery split
- class: c
- other states: a state whose fast/slow corrections share one cause with non-registering, or which anchors a non-test cause (e.g. a "customer notified" date) on a record rather than discovery, can't be modelled. The allowed transitions are one reading of Texas's R-19.
- fix: attributes on the cause (platform, possibly per jurisdiction): `anchor_kind` (`test` | `discovery`), `required_test_outcomes text[]`, `direction_source` (`test_outcome` | `per_period_sign`), `allowed_transitions text[]`, `delivery_path` (`adjustment` | `reissue` | `next_bill`), `requires_supervisor_evidence boolean`, `favourable_duty` (see Theme 4). The CHECKs become an FK plus trigger reads. — size: M/L

### The governing test is read only for meter_error
- where: -13:2230–2231 `SELECT * INTO g FROM meter_governing_test(...) WHERE c.cause = 'meter_error'`; used at -13:2286 and 2307 (`CASE WHEN billable_scope = 'shorter_of_months_or_last_test' THEN g.test_date END`)
- rule: only (7)(B)(v)(I) has a last-test prong
- class: c
- other states: a latent defect in the redesign's favour-of-data direction. If any other state's row gives `shorter_of_months_or_last_test` to a cause other than `meter_error` (e.g. a non-registering rule bounded by the last test), `g` is NULL and the last-test prong **silently drops**. The window gets longer, against the customer, with no error.
- fix: read the governing test whenever the resolved rule's formula uses a last-test term, never by cause name. — size: S

---

## Theme 3 — Window formula and enforceability

### Billable-window formulas are Texas's clause shapes
- where: -13:716–717 CHECK `backbilling_cap_rules_billable_scope_check` (`uncapped`, `months_from_anchor`, `shorter_of_months_or_last_test`); -13:723–725; computation in `meter_correction_inputs` -13:2233–2234, 2284–2288, 2305–2308; comment -13:754–755, 2034–2060
- rule: (7)(B)(v)(II) "not to exceed three months" and (7)(B)(v)(I) "the shorter of six months or the last test", with R-37(a) service start added as a MAX term
- class: b
- other states: common shapes this can't express: "from the date the error began, if determinable, else N months"; "one-half the time since the last test, capped at N months" (from memory, verify); a reach counted from the date the *customer was notified*, not the test; **different reach for refunds and for charges** (e.g. refund up to 3 years, backbill 3 months: California tariff shape from memory, verify); a calendar-based limit tied to a statute of limitations. The formula is also direction-blind: one `billable_*` pair governs both directions, and code then waves favourable periods through (Theme 4).
- fix: store the window as data terms, not enum names. For example `backbilling_rule_window_terms(rule_id, direction ('adverse'|'favourable'|'both'), term_kind, months, combine)`, where `term_kind` is from a small general vocabulary (`months_before_anchor`, `last_test_any`, `last_test_accurate`, `half_since_last_test`, `error_start_if_known`, `deployment_start`, `notice_date`, `uncapped`) and `combine` = MAX (latest start wins) or MIN. The evaluator loops over terms. Adding a state is then rows. The R-37(a) deployment-start term (-13:2239–2288, with its corroboration rule) becomes one term kind rather than always-on code. — size: L

### Enforceable scope vocabulary is Texas's disconnection rules
- where: -13:718–719 CHECK `backbilling_cap_rules_enforceable_scope_check` (`uncapped`, `months`, `never`, `conditional_on_read_classification`); -13:727–728; comment -13:756–757; evidence columns -13:2577–2578
- rule: (4)(E)(vi) bars disconnection for a faulty-metering underbill (`never`); (3)(C)(iii) six months for a rate error; (4)(E)(vii) estimated bills, depending on whether the missed read was beyond the utility's control (`conditional_on_read_classification`, R-30)
- class: b
- other states: "enforceable" here means "may be pursued by disconnection". Other states govern that separately, through installment-plan duties (a backbill over some amount must be offered a payment plan of at least N months, common; figures vary), or amount thresholds rather than months (guess). `conditional_on_read_classification` names one Texas sub-clause as a vocabulary value.
- fix: separate enforcement into its own per-jurisdiction rule: `backbill_enforcement_rules(state, service, class, cause, disconnect_allowed, max_months, min_installment_months, condition_code, …)`, where `condition_code` comes from a general vocabulary (`read_beyond_utility_control`, `customer_culpable`…) evaluated by named functions. — size: M

### R-32 straddle rule: a straddling adverse period is forfeited whole
- where: -13:2686–2696 in `meter_correction_evaluation_after()`; CHECK -13:2605–2609 (forfeit = whole amount); comment -13:2075–2084
- rule: R-32 (Kyle): an adverse billing period that begins before the window is forfeited in full, never prorated
- class: c
- other states: prorating a straddling period by days in the window is a common reading elsewhere (guess). Some rules count the window in *billing cycles* rather than days or months, which makes the straddle question moot (guess).
- fix: `straddle_treatment` (`forfeit_whole` | `prorate_days` | `include_whole`) on the rule row. The evidence table already records `days_in_window`, so proration is a computation, not a new shape. — size: S

### The tenant adverse limit (filed tariff) is data, correctly
- where: -13:307, 316–318, 323–324 `tenants.backbilling_adverse_limit_months`; applied -13:2296–2298, 2690–2692
- rule: R-37(d): a tenant may bill for less than the statute; it only shortens the adverse side
- class: a
- other states: this is the utility's own choice, so tenant-level is right. Limits: it is one number per tenant, not per service type (a gas-and-water utility's tariffs may differ) and not effective-dated (the config history logs changes, but the evaluator reads today's value). The adverse-only direction is also a Texas reading (R-37); a tariff might limit refunds too (guess).
- fix: optionally key by service_type, and read the value in force at the anchor from `tenant_configuration_history`. — size: S

---

## Theme 4 — Direction duties: the fast-meter refund (R-37)

### Mandatory refund to the window on a fast meter
- where: `enforce_meter_correction_case()` -13:1772–1792 (withdrawal refused while the test is `fast`); `enforce_meter_correction_evaluation()` -13:2494–2502 (zero amount refused); holds limited to `cause='meter_error' AND direction='customer_owed'` -13:3069–3073; `meter_correction_uncovered_days()` -13:3215 (only fast meter_error is checked); freeze -13:3304–3310; view `meter_fast_findings_without_case` -13:3506–3523 (keyed on `outcome='fast'`; comment says "more than 2% FAST")
- rule: §7.45(7)(B)(v)(I) makes the refund back to the window a duty; R-37 allows no favourable-direction decline; R-27 detection surface
- class: c
- other states: whether a refund is *mandatory*, how far back it reaches, and whether it has a floor (de minimis) is state law. Other rules may require the refund for the full period since the last test regardless of the months cap, or allow the utility to net small amounts (guess). A state where a *slow* meter correction is also mandatory in some sense (e.g. water leak rules) can't flip it.
- fix: rule attributes `favourable_duty` (`mandatory` | `permitted`), `favourable_window_terms` (Theme 3), `de_minimis_amount`. Holds, the uncovered-days check, the zero-amount refusal and the fast-findings view read `favourable_duty = 'mandatory'` for the resolved rule, never `cause = 'meter_error' AND outcome = 'fast'`. The *mechanisms* (holds, uncovered-days, surface) are general and stay. — size: M

### Favourable periods pass uncapped; tenant limit never applies to them
- where: -13:2697–2701 (`v_eff := greatest(v_pwindow, NEW.claimed_from)` for favourable; no forfeiture branch); comment -13:2072–2074, 298–300
- rule: R-25 (favourable periods pass uncapped), R-32 (a favourable straddler is included whole), R-37(d) (the tenant limit is adverse-only)
- class: c
- other states: refunds are commonly capped too (by a refund reach or a statute of limitations), so an "include every favourable period in the period set" rule would over-refund there (guess; common).
- fix: covered by `direction` on the window terms from Theme 3 plus a favourable straddle treatment. The evaluator then treats both directions symmetrically, with data deciding the asymmetry. — size: S (once Theme 3 lands)

---

## Theme 5 — Gates

### R-36 supervisor gate: six months hardcoded, scope keyed on cause name
- where: -12:1614–1615 `supervisor_gate := v_weak AND (v_cutover IS NULL OR (p_anchor_date - interval '6 months')::date < v_cutover)`; -13:2329 `supervisor_gate_required := c.cause = 'meter_error' AND c.direction = 'customer_owes' AND g.supervisor_gate`; comments -12:427, 1539–1542, -13:2741–2751, 2876; residual R18 -13:3680–3686
- rule: R-36: an adverse correction resting on weak provenance needs a supervisor while the six-month reach still crosses cutover
- class: c
- other states: the lapse point is "while the cap reaches before cutover". With a 12-month rule the gate lapses six months too early, while a migrated date can still set the window, which is the exact failure round 1 fixed at month ends. The meter_error-only scope is an engineering reading of the Texas rule (R18).
- fix: compute the gate in -13 from the resolved rule (`anchor − <the rule's longest last-test-bearing months>` < cutover). `meter_governing_test()` should return `weak_provenance` only and not decide the lapse. Scope the gate by "the rule's window has a last-test term and direction is adverse", not by cause name. **The approval mechanism is general and stays as-is** (`meter_correction_approvals` -13:2753–2876: one approval per evaluation, the approver is not the opener or evaluator, stamped). — size: S

### Evidence fence hardcodes the six-month reach
- where: -13:2147–2169 function `meter_correction_evidence_fence` (2167 `t.test_date > (c.anchor_date - interval '6 months')::date`)
- rule: "any defective test on the meter within the reach of the window": Texas's six months written in
- class: c
- other states: with a longer window, an earlier defective test inside that window would not move the fence earlier, so deployments recorded between the earlier finding and the discovering test would count as pre-finding evidence. That is the forgery the fence exists to stop.
- fix: use the case's computed period-set start (or the rule's maximum reach) instead of the literal. — size: S

### Tamper gate keyed on the cause literal
- where: -13:1921–1973 in `enforce_meter_correction_case()` (`v_into_tamper := NEW.cause = 'tampering_bypass'…`); CHECK -13:1542–1550 `meter_correction_cases_tamper_check`; error text cites "(4)(E)(vi) disconnection bar" -13:1927
- rule: R-38 attachment 2: the move into tampering_bypass lifts the (4)(E)(vi) bar and uncaps the bill, so it needs a supervisor and evidence
- class: c
- other states: the *reason* for the gate is "this cause removes customer protections". Another state's equivalent (e.g. "culpable conduct" or "theft of service", from memory) is a different code, and a state where some *other* cause lifts protections needs the same gate on it.
- fix: cause attribute `requires_supervisor_evidence` (or derive it: the cause's rule is uncapped *and* enforcement allows disconnection). The evidence kinds (service order, deployment removed for tamper, field report) are general. The tamper_* columns could generalise to `gated_evidence_*`. — size: S

### Void-and-reissue path: cause list, and "rate misapplication is uncapped" by omission
- where: -13:964–972 CHECK `correction_run_targets_backbill_cause_check` (`rate_misapplication` only); -13:1059–1289 function `enforce_backbilling_gate_issue()` (1242–1247 requires a cause; 1253–1258 the same period; 1269–1282 units must match / not rise); it **never calls `backbilling_resolve_cap`**
- rule: R-33 (meter errors go by adjustment, not reissue); R-39 (rate_misapplication = correct units, wrong price); §7.45(4)(E)(v) no billing cap on a misapplied rate
- class: c
- other states: the gate's detection ("charges more for days already billed on a since-voided bill") is general and good. The Texas-specific part is what it allows after that: any increase, any distance back, once labelled `rate_misapplication`, because Texas puts no billing cap on that cause. In a state that caps *billing-error* backbills too (common in PUC rules, often 6–12 months for residential; figures from memory, verify), a reissue of a bill from years ago at a higher price would pass unchecked. Which causes may use the reissue path is itself a Texas reading (R-33).
- fix: (1) the CHECK becomes an FK to causes with `delivery_path = 'reissue'`. (2) The gate resolves the rule for the reissue's premise, class, cause and date, and applies its billable window (refusing a period entirely before the window, and handling a straddle per `straddle_treatment`) as the case evaluator does. (3) The "same units" invariant becomes a cause attribute (`units_invariant boolean`). — size: M

---

## Genuinely general mechanism (keep through the redesign; not findings)

These encode no jurisdiction's law and read (or should read) rule data:
- **Case object** `meter_correction_cases` (-13:1476–1592): one finding per meter, following the meter across deployments and occupants (R-37(b)). Its status machine (open/frozen/withdrawn), whole-row fence on status changes (-13:1741–1750) and derived-column fences are general. Only the cause vocabulary and the cause-name branches in it are Texas (above).
- **Evaluation + per-period evidence** (-13:2345–2735): caller supplies only the amounts; the database derives everything else; one evidence row per period, never netted; forfeitures recorded as rows (`backbilling_forfeitures` view -13:3451–3479). The per-period re-resolution of class and jurisdiction (-13:2300–2316) is exactly the shape a multi-state design needs.
- **Input fingerprint** `meter_correction_inputs()` + md5 (-13:2178–2339, 2538) and **freeze** `meter_correction_freeze_check()` (-13:3263–3317): general. Once rules are platform-held and effective-dated, the fingerprint should carry the rule row id plus its effective range rather than `updated_at`.
- **Holds** (-13:2907–3174): no Tally invoice for an in-window stretch, legacy (before cutover) / predecessor (before acquisition), self-lapsing. General as a mechanism. Only its eligibility test (cause = meter_error, direction = owed) is Texas, covered in Theme 4.
- **Approvals** (-13:2753–2876) and **supervisor** definition (-13:440–493): general.
- **Event log** (-13:1603–1673), **deployment hardening** (-13:596–660), **predecessor acquisitions** per location (-13:1357–1419), **billed-periods definition** (-13:2103–2135), **reissue detection** half of the issue gate: general.
- **-12 history mechanics**: append-only tests, database-derived outcome from raw readings, the one error formula, supersession rules, cutover boundary and its guard, the pointer, absence declarations, gap view. All general. `record_basis` (recorded / migrated_full / migrated_date_only) is migration provenance, not law.

## Watch list (pending work that must land as data, not structure)
- Customer-requested test **fee rule**: free if none in four years, fee cap, refund when more than 2.0% off (§7.45(7)(B)(iv); -12:169–171, residual R1 -12:1664–1668). Not built yet. When the adhoc-charge work builds it, the look-back years, fee cap and refund trigger must be per-jurisdiction rows (reuse the threshold table for the refund trigger), not constants.
- `volumetric_threshold` resolver (CCK-4…13; -13:864–869): due in its own patch. Build it against per-state class data, not as a tenant mode.
- Error messages and comments citing "16 TAC §7.45" / "2%" in RAISE text (e.g. -13:335, 1787, 3071, 3307; -13:3523) should quote the resolved rule's `source_note` rather than a literal cite.
