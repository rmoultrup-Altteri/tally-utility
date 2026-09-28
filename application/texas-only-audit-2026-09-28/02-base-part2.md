# 02 — tu.sql base schema, part 2 (lines 5700–11353)

## Summary
- **Scope note:** this range holds no function, view or COMMENT bodies. It is the tail of the constraints section (5700–5763), every INDEX (5764–8227), the trigger *bindings* (8228–8570), FK constraints (8571–10586) and RLS/policies (10587–11353), and it ends at "PostgreSQL database dump complete". All function, view and table bodies sit before line 5700, in part 1. I read the whole range. Findings here point at in-scope objects. Where the rule itself lives in part 1, I give that line as `(def: tu.sql:NNNN)` so the two reports can be deduplicated.
- **Hardcoded constants that reach into this range:** partial-index predicates and indexed flags depend on part-1 view constants: days-since-read > 45, NSF "2 in 90 days", a 3-year escheat dormancy (1095/1005 days), deposit refunds overdue after 60 days, and alert windows of 30 and 60 days. Each is one jurisdiction's number built into structure.
- **Jurisdiction shape:** nothing in this range references a jurisdiction, regulator or state table. No FK from `tenants`, `service_locations`, `franchise_fee_rules`, `customer_tax_exemptions` or `escheatment_events` leads to any jurisdiction entity. Franchise-fee applicability runs on a free-text `city_name` / `franchise_city` plus an `inside_city_limits` boolean, which is the Texas municipal-franchise model.
- **RLS:** every table in the base schema that has a policy is tenant-isolated (tenant_id or id = tenant). The base schema has **no platform-held rule table** (no tenant_id) of the `meter_accuracy_thresholds` kind. Class (a) examples exist only in later patches.
- **Good signs:** `service_type` is already an indexed dimension on meters, rate items and rate schedules. `state` sits on `service_locations` (county index) and `id_issuing_state` on customers. Franchise fees and WNA zones carry effective dates.
- Counts: a 1, b 9, c 6 (16 findings).

---

## Theme 1 — Constants in index predicates and in indexed statistic flags

### Stale-read threshold of 45 days in a partial index
- where: tu.sql:8147 — INDEX idx_usage_stats_stale ON usage_statistics (tenant_id, days_since_last_read) WHERE days_since_last_read > 45 (column def: tu.sql:4857)
- rule: an account is "stale" when it has gone 45 days without a read. This is a meter-reading-frequency threshold (Texas gas practice is monthly reads, with estimate limits under 16 TAC §7.45). Nothing is cited.
- class: c
- other states: other gas commissions and water rules set read-frequency and estimation limits differently (bi-monthly water reads are common, so 45 days would flag every account). This is a guess for specific states. A per-state or per-service-type threshold cannot be expressed, because the number is compiled into the index predicate.
- fix: move the stale threshold into a jurisdiction and service-type table, or at least a tenant setting; drop the literal from the index predicate (index on days_since_last_read only, filter at query time) — size: S

### NSF "2 in 90 days" pattern flag, indexed
- where: tu.sql:7321 — INDEX idx_payment_health_nsf ON payment_health_statistics (… multiple_nsf_pattern_90d) WHERE multiple_nsf_pattern_90d = true (def: tu.sql:3959 `nsf_count_90d >= 2`)
- rule: two returned payments within 90 days count as a pattern. Rules like this drive deposit and cash-only requirements. The count and window are frozen into the column name and the view.
- class: c
- other states: many states tie a new deposit or a cash-only requirement to returned checks, often "2 in 12 months" (guess; varies by state). The 90-day window and the count of 2 cannot vary.
- fix: parameterise the count and window from per-jurisdiction data (or tenant policy where it is the utility's choice), and rename the column to something neutral such as `nsf_pattern_flag` — size: S

### Escheat dormancy of 3 years, with a "dormancy approaching" status
- where: tu.sql:6369 — INDEX idx_credits_escheat_active ON customer_credits … WHERE escheat_status = ANY('active','dormancy_approaching'); tu.sql:6698–6719 escheatment_events indexes; FKs tu.sql:9398, 9406 (defs: tu.sql:2658 CHECK; tu.sql:2705–2707 1095/1005/60-day buckets; tu.sql:2715 $250 due-diligence threshold)
- rule: 1095 days (3 years) of dormancy, 90-day warning, 60-day due-diligence response, $250 due-diligence threshold. These look like Texas Property Code ch. 72–74 numbers. None is cited.
- class: c
- other states: unclaimed-property dormancy for utility deposits and credits differs by state (1 year is common for utility deposits; guess on specific states). The priority rules send property to the owner's last-known-address state, not the utility's state. A customer who moved out of state needs a different state's clock, and nothing on the credit or event records **which** state's clock applies or where the property was remitted.
- fix: add an `unclaimed_property_rules` table keyed by state (dormancy days, notice window, due-diligence threshold, effective dates) and a `holder_state` / `remitted_to_state` on credits and escheat events; the view should read the rule — size: M

### Deposit refund overdue after 60 days
- where: tu.sql:6341 — INDEX idx_credit_aging_deposit_overdue … WHERE deposit_refund_overdue = true (def: tu.sql:2712 `CURRENT_DATE - issued_date > 60`)
- rule: a deposit refund credit becomes "overdue" 60 days after issue. This is a deposit-refund deadline; the Texas rule area is 16 TAC §7.315 deposits. Nothing is cited.
- class: c
- other states: deposit refund timing (and deposit interest, which has no home in this range at all) is statute per state and per service type (guess on exact numbers).
- fix: read the refund deadline from a per-jurisdiction deposit rule row — size: S

### Disconnect-protection and tax-exemption "expiring" windows
- where: tu.sql:6292 — INDEX idx_compliance_stats_disconnect_expiring; tu.sql:6299, 6306 — idx_compliance_stats_tax_expired / _tax_expiring (defs: tu.sql:2617 30 days; tu.sql:2606 60 days)
- rule: a 30-day warning before disconnect protection lapses and a 60-day warning before a tax exemption lapses.
- class: c (low severity: these look operational, but medical-certificate renewal windows are statutory in some states)
- other states: medical/critical-care certificate renewal and notice windows differ by state (guess). A per-state lead time cannot be set.
- fix: take the lead time from tenant policy, or from the jurisdiction rule where one is statutory — size: S

### Estimation-rate data-quality bands (20% / 50%)
- where: tu.sql:8140 — INDEX idx_usage_stats_quality ON usage_statistics (tenant_id, data_quality_flag) (def: tu.sql:4853–4855)
- rule: estimated-read share above 20% counts as marginal and above 50% as poor. This is operational, not statute, but it sits next to estimation limits that are statutory.
- class: c (probably not law; listed so it is not mistaken for one)
- other states: n/a unless a state sets a maximum share of estimated reads (guess).
- fix: tenant setting — size: S

---

## Theme 2 — Texas municipal-franchise-fee shape

### Franchise fee keyed by free-text city name
- where: tu.sql:6726, 6733, 6740 — INDEXes idx_franchise_fees_active / _city (tenant_id, city_name, status) / _tenant; tu.sql:11097 POLICY tenant_isolation ON franchise_fee_rules; no FK anywhere in 8571–10586 from franchise_fee_rules to a jurisdiction (defs: tu.sql:3016–3035, unique key tu.sql:5312)
- rule: one franchise fee per (tenant, city_name, effective_date), a percentage applied to a fixed list of bases (`applies_to` CHECK: total_bill / gross_revenue / base_and_usage / usage_only) and remitted monthly, quarterly or annually. This is the Texas city-franchise model: a percentage of gross receipts, with the city identified only by name.
- class: b
- other states: counties, special districts and townships that levy franchise or right-of-way fees can't be expressed ("city" only). A city name can't be told apart across states (two Springfields). Per-unit fees (cents per Ccf, per meter per month) and tiered or capped fees don't fit a single `fee_percentage` (e.g. some Oklahoma/Louisiana municipal fees are per-customer; guess).
- fix: key the rule by a jurisdiction entity (state + place type + place code) with a fee-basis model that allows percentage, per-unit or flat amounts, and FK service_locations to that place — size: M

### `inside_city_limits` boolean and `franchise_city` text on locations and rate schedules
- where: tu.sql:7874 — INDEX idx_service_locations_city_limits (tenant_id, inside_city_limits); tu.sql:7909 — idx_service_locations_franchise (tenant_id, franchise_city); tu.sql:7580 — idx_rate_schedules_franchise (tenant_id, franchise_city) (defs: tu.sql:4457–4458, 4186)
- rule: a location is either inside one city or not, and a rate schedule is tied to one franchise city. This matches Texas inside-city vs environs gas rates (the RRC "environs" rate class).
- class: b (boolean defaulting to true is structure: c-leaning)
- other states: a location can sit in several overlapping taxing or franchise places (city + county + special district). "Environs" rates are a Texas RRC construct, and other states split rates by service territory or zone instead (guess). A boolean holds only one place layer.
- fix: replace with a location-to-jurisdiction membership (many rows), and derive "inside city" from it — size: M

---

## Theme 3 — Tenant-keyed rule data with no jurisdiction or service dimension

### Customer tax exemptions have no taxing jurisdiction
- where: tu.sql:8049–8077 — INDEXes idx_tax_exemptions_*; tu.sql:6565, 6572 — idx_customers_tax_exempt / _tax_expiry; FK tu.sql:9278 (customer only); POLICY tu.sql:11062
- rule: one `is_tax_exempt` flag and expiry per customer, plus exemption rows linked to a customer with no taxing authority.
- class: b
- other states: exemptions are per taxing authority (state sales tax vs city vs county vs special district), per service type (residential gas exempt from state tax in Texas, but not every state), and per certificate. A customer exempt from state tax but not city tax can't be represented.
- fix: exemption rows keyed to a jurisdiction and tax type, with a service_type column — size: M

### Single `do_not_disconnect` protection flag
- where: tu.sql:6544 — INDEX idx_customers_protection (tenant_id, do_not_disconnect) WHERE do_not_disconnect = true (def: tu.sql:2495)
- rule: disconnect protection is one boolean with one expiry. It carries no protected category (medical, elderly/disabled, weather moratorium, military, energy assistance pending).
- class: b
- other states: states list different protected groups and give each its own duration and renewal (e.g. winter moratoria in northern states, and the 16 TAC §7.460 Texas categories). The reason and its statutory source can't be stored, so per-category rules can't be applied.
- fix: a protections table (customer, category from per-jurisdiction data, source rule, start, end) — size: M

### Winter averaging assumes a Dec–Feb northern-hemisphere winter
- where: tu.sql:6586–6600 — INDEXes idx_cwa_* on customer_winter_averages (meter_id, winter_year); FKs tu.sql:9318, 9326 (def: tu.sql:2905–2938, comment "Winter 2025-2026 (Dec 2025, Jan 2026, Feb 2026)"; unique tu.sql:5248)
- rule: one winter average per meter per "winter_year", with the months fixed to Dec–Feb in the documented semantics. Used for averaging (a sewer/water or gas billing practice).
- class: b
- other states: averaging periods are set by tariff or ordinance and vary (e.g. Nov–Mar, Jan–Mar; guess). The key also has no way to record which averaging rule produced the row.
- fix: record the averaging-window definition (months, effective dating) as tenant tariff data and reference it from each row — size: S

### WNA zones: tenant tariff data, with Texas season defaults
- where: tu.sql:5744, 5760 — UNIQUE (tenant_id, wna_zone_id, billing_month) / (tenant_id, zone_code); tu.sql:8175–8203 — idx_wna_*; FKs tu.sql:10318 (rate_schedules.wna_zone_id, singular), 10574; POLICIES tu.sql:11307, 11314 (def: tu.sql:4963, DEFAULT active_months '{11,12,1,2,3,4}')
- rule: weather-normalisation adjustment is an RRC-approved tariff mechanism (Texas gas LDCs). Holding it per tenant is correct, since it is the utility's tariff. The Nov–Apr DEFAULT is a Texas-style heating season, and a rate schedule can carry only one zone.
- class: b (tenant scoping is right; the season DEFAULT and the single-FK shape are not jurisdiction-neutral)
- other states: WNA is not permitted or used in every state, and formulas differ (HDD-based vs decoupling/revenue-per-customer; guess). Water and electric have no WNA equivalent.
- fix: drop the month DEFAULT (require explicit months) and allow the adjustment formula type to vary — size: S

### Meter test due date with no rule source
- where: tu.sql:7272 — INDEX idx_meters_test_due (tenant_id, next_test_due_date) WHERE next_test_due_date IS NOT NULL AND status = 'active' (def: tu.sql:3693)
- rule: periodic meter testing. Test intervals and sampling plans are regulatory (the RRC sets gas meter testing; water follows AWWA/state rules). The date is a bare column, so whatever interval produced it isn't recorded.
- class: b
- other states: intervals differ by state, service type and meter size (guess on specifics).
- fix: a per-jurisdiction and service-type meter-test-interval table, used the same way as meter_accuracy_thresholds, with next_test_due_date derived from it — size: S

---

## Theme 4 — Structural absences visible in FKs and RLS

### No jurisdiction or regulator entity in the base FK graph
- where: tu.sql:8571–10586 — FK CONSTRAINT section (e.g. service_locations FKs tu.sql:10430, 10438, 9486 go only to billing_cycles, customers and communities; no FK from tenants)
- rule: implicit. A tenant has no regulator or state, and a location's state and county are free text.
- class: b
- other states: a utility serving two states (common for gas LDCs across OK/TX/NM or AR/LA; guess on specific operators), or a tenant regulated by a city council rather than a state commission (municipal water), has nowhere to say so. Every rule lookup would have to guess the jurisdiction from text.
- fix: add a platform-held jurisdictions table and FK service_locations (and optionally tenants/rate_schedules) to it; this becomes the key that every class-(a) rule table reads — size: L

### Every rule-bearing table is tenant-scoped under RLS
- where: tu.sql:10587–11353 — ROW SECURITY + POLICY tenant_isolation on all 50-odd tables (e.g. franchise_fee_rules 11097, customer_tax_exemptions 11062, wna_zones 11314)
- rule: none directly. But every table here is either tenant-owned or `tenants` itself, so the base schema can hold no platform-wide statutory data.
- class: b
- other states: whenever a second tenant lands in the same state, each would have to re-enter the same statute numbers, and they can drift apart.
- fix: add platform-held rule tables (no tenant_id, read-only to tally_app, as in v5.4.2-12) for statute data; keep tenant tables for tariff choices — size: M (bundled with the jurisdictions table)

---

## Theme 5 — Correctly neutral (inverse)

### Service type is a first-class dimension
- where: tu.sql:7251 — idx_meters_service_type (tenant_id, service_type); tu.sql:7524 — idx_rate_items_service; tu.sql:7566 — idx_rate_schedules_active (tenant_id, service_type, status); tu.sql:6523 — idx_customers_id_number (tenant_id, id_issuing_state, id_number)
- rule: meters, rate items and rate schedules are indexed by service type, and customer ID documents carry their issuing state. Neither is tied to gas or to Texas.
- class: a (structure is jurisdiction-neutral; whether service_type's CHECK list is gas-only is a part-1 question)
- other states: fine as is.
- fix: none; reuse `service_type` as the second key of each future rule table — size: S

---

## Also checked, nothing jurisdictional found
- Trigger bindings tu.sql:8228–8570 attach part-1 functions (`populate_reading_calculations`, `enforce_reading_validation_workflow`, `enforce_meter_estimation_block_metadata`, `enforce_billing_hold_metadata`, …). Their bodies are part-1 scope and none is defined here.
- The AI, import, alert, anomaly, payment-method and ledger indexes and FKs (confidence cutoffs 0.70/0.85 at tu.sql:6236 and 7146 are AI heuristics, not law). The dunning, deposit and service-order status lists in index predicates (tu.sql:6495, 6656, 6950, 7972) only repeat part-1 CHECK values.
