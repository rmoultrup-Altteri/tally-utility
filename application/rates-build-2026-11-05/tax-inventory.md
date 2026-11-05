# Tax jurisdictions, tax stacking and franchise fees: source inventory

2026-11-05 · rates stream · inventory only (no design, no SQL)

Scope: the next rates patch, covering the invariants that a franchise fee traces to the city that levies it (CI-044), that every bill carries the full tax stack on the right bases (CI-045), and the tax half of "reference data is dated on both time axes" (CI-001) and "reference data is date-effective" (CI-004). Read against `tu.sql` as mirrored through v5.4.2-29 (47,634 lines). Line numbers below are `sql/tu.sql` unless another file is named. GBM files were read from `origin/main` (fetched 2026-11-05).

No pending patch touches this area: -25, -26 and -27 (money) mention none of `is_taxable`, `franchise_fee_rules`, `invoice_line_item_bases` or `tax_breakdown`.

---

## 1. Rulings in force

| # | Ruling | Source and date | In brief |
|---|---|---|---|
| R1 | **A tax jurisdiction is a place** | Kyle, GBM `application/kyle-decisions-2026-10-14-tax-jurisdictions-and-gas-cost.md`, answer 1 (2026-10-14; the roadmap calls this answer set K-09) | "Yes. A jurisdiction is a place (city, county, transit district, special purpose district). Its taxes hang off it as separate, effective-dated rows, and a service location links to every jurisdiction it sits in." Rates come from the Texas Comptroller's quarterly address and rate files, loaded by a scheduled job: "No rate change goes live without operator approval: the job stages proposed changes with the quarter's effective date, and an operator signs off." |
| R2 | **The tax stack comes from law and the tariff both** | same file, answer 2 | "Each tax or fee line carries its source (statute, ordinance, or tariff) and a citation, and is tenant-configured, not hard-coded." "The franchise fee is a percentage of all billed lines, except lines the rules exclude (the pipeline safety fee, 16 TAC §8.201)." "The franchise fee is **not** part of the sales-tax base." |
| R3 | **The franchise fee base is a tenant choice from a fixed list** | same file, answer 3 | "The tenant picks a base type per jurisdiction from a short fixed list, with no default." Resolve the overlap between the per-item taxable flag and the franchise rule's "applies to" "to a single mechanism". "Close the live `applies_to_customer_types` size-tier defect as part of this work." |
| R4 | **We hold the liability, not the remittance** | same file, answer 4 | "The liability only: billed and collected amounts by jurisdiction and period, plus an optional filing reference. Payments to the Comptroller and cities stay in the utility's ERP." |
| R5 | **Every charge declares its tax status; item and customer must both be taxable** | same file, answer 5 | Drop `DEFAULT false` on `rate_items.is_taxable_default` and `adhoc_charges.is_taxable`; a required field in rate setup. Tax applies only when both the item and the customer are taxable for that service type, through `should_charge_tax()`. An exempt customer still gets a $0.00 tax line. A taxable customer never makes a non-taxable item taxable. Customer taxability is recorded per service type. Water and sewer treatment waits on tax counsel. |
| R6 | **City sales tax on residential gas: inside city limits only, on flagged lines** | Kyle, GBM `kyle-decisions-2026-11-03-scenario-batch-1.md`, answer 4 (2026-11-03) | "Inside city limits only, on the lines the tenant flags taxable (per the 2026-10-14 ruling)." Same file, standing rule: "Always follow the tariff, including when a city's tariff differs from the platform default. Platform defaults apply only where the tariff is silent." |
| R7 | **A franchise rate change inside a period uses one reference date** | Kyle, GBM `wu5-wu6-kyle-decisions-2026-07-10.md`, Family 6 (D6-1, 2026-07-10) | "Single reference date, default = period end, tenant-overridable per jurisdiction. No proration machinery." |
| R8 | **Exemptions are certificate-backed; residential use is derived, not a row** | Kyle, GBM `kyle-decisions-2026-08-26-a1-bitemporal.md` (R-12, R-13; 2026-08-26) | An exemption is born pending and becomes active only when verified. The exemption table holds certificate-backed exemptions only; `industrial` left its list. Texas residential gas's state sales-tax exemption (Tax Code §151.317) is "a function of rate class and premise use … Derived, not a row." Predominant-use (partial) exemptions are deferred to a table of their own. |
| R9 | **Regulatory and tax jurisdiction are separate axes** | Kyle, GBM `kyle-decisions-2026-09-02-a2-backbilling-caps.md`, R-26 (issued 2026-09-14) | "Regulatory jurisdiction and tax jurisdiction are different axes and stay separate tables … Texas tax jurisdiction is complex in its own right and its boundaries do not track RRC / municipal GUD regulatory authority." The `jurisdictions` table is left untouched. |
| R10 | **The customer-type size-tier defect is live** | Kyle, GBM `kyle-decisions-2026-09-02-customer-class-keying.md`, section 3 (2026-09-02) | Both `applies_to_customer_types` defaults omit `small_commercial` and `large_commercial`: "A tenant that size-tiers commercial gets rate items and franchise fees that silently skip every `small_commercial` and `large_commercial` account." Fold into the next schema fixes. |
| R11 | **The pipeline safety fee is a rate-page line; it is outside every tax base** | Kyle D4-1 (2026-07-10) as applied in this repo's DECISION-LOG 2026-08-31 (v5.4.2-07); Kyle 2026-11-03 answer 2 | No remittance gate or ledger for the fee. The fee is excluded from the franchise, gas-utility-tax and sales-tax bases, and that exclusion is already structural (section 2). It is billed only in months the city passes it to customers. |
| R12 | **Rounding** | Kyle, GBM `kyle-decisions-2026-10-15-waves-1-to-7-and-texas-first.md` (K-06, 2026-10-15) | Money rounds to the cent, half-up at the midpoint; rates and intermediate math carry four decimals. |
| R13 | **A percentage rate is stored in percent, four decimals** | Ryan, DECISION-LOG 2026-11-02 (-28 r1); `APPLICATION-CONTRACTS.md` AC-45 | "Store: every percentage rate (taxes, gross receipts, franchise fees, any percent-of-bill item) with `rate_unit = 'percent'`." The app converts whatever the clerk types. |
| R14 | **A value the utility answers for stays the utility's** | Ryan, 2026-09-30 (deposits, decision R-D1; `application/deposits-parity-rescope-2026-09-30.md`; applied in -15 at `sql/v5.4.2-15-*.sql` section 8) | Where a regulator publishes a value but the utility applies it and is held responsible for it, the utility's own row is applied and cited; the platform keeps the published value as a reference and reports any disagreement. |
| R15 | **Texas city-owned gas systems are outside the state's gas utility law** | Project finding 2026-10-06 (`application/places-source-inventory-2026-10-06.md`); Utilities Code §101.003(7), §102.002 | Our first customers are city-owned systems; their policy is their own tariff, not state law rows. Any Texas law area must be checked for whether it reaches them. |

**Searched and not found.** No later Kyle ruling on tax, franchise fees, sales tax, exemptions, the Comptroller or gross receipts in GBM's `kyle-decisions-*.md` beyond the above (the 2026-10-15 and 2026-11-03 files mention tax only as quoted). This repo's DECISION-LOG has no later tax ruling than 2026-10-14; its 2026-10-14 entry records R1–R5 and says the remaining calls ("the fixed list of base types; how `is_taxable` and `applies_to` merge") are "drafting calls for the patches that build them".

**Background, not rulings** (GBM decision tables, written 2026-08-06 before Kyle's answers; they carry the open questions R1–R5 answer):
- `franchise-fee-application` (decision table #26): a five-row match (out of city: no fee; in city with no franchise city: an exception, not $0; no effective rule: an exception; class carved out by the ordinance: a $0.00 line naming its rule; otherwise the fee). Two constraints: the §182.025 ceiling of 2% of gross receipts, checked when a rule is saved; and R7. Open questions: (1) which city wins when the premise's and the schedule's differ; (2) `applies_to` against the per-item flag; (3) `inside_city_limits` defaults to true.
- `tax-application-and-stacking` (#23): four stages (start from the settled charges; classify each; per jurisdiction, compose each tax's base and evaluate in stacking order, with no tax on tax unless the jurisdiction declares it; round each line and record the base). An exempt customer still has a base composed and a $0.00 line.
- `adhoc-charge-taxation` (#25): a three-level default chain ending in "Texas-shaped" platform defaults by charge type. **Reversed by R5** (the scenarios inventory, `application/scenarios-source-inventory-2026-11-02/audit-bitemporal-strategy-decision-tables.md` §E, marks it "rewrite").
- `tax-exemption-eligibility` (#24): four conditions for an exemption to apply (active; bracket covers the period date; service type matches). Notes the legacy customer flag is read by no tax path.

**Invariant texts** (GBM `application/canonical-invariants.md`, Family 6): CI-044 wants per-customer lineage to the city "in effect for the billing period" and an aggregate that "reconciles dollar-for-dollar against the remittance total owed". CI-045 wants each tax on its prescribed base, stacking order respected, the base recorded on the bill. CI-046 (exemption certificates) is at "represented and protected" in the parity record. CI-047 wants the premise-to-jurisdiction link from geographic ground truth, dated, with audited overrides. CI-038 (pipeline safety fee) is at partial. Appendix A-8 (GBM) describes a `tax_jurisdictions` table with code, type, parent, dates and boundary source.

**Parity record** (`application/invariant-parity-measurement-2026-10-13.md`): CI-044 PARTIAL (line 144, 2026-10-15 update: "Left: `franchise_fee_rules` keys on `city_name` (needs a place), a line-to-rule link, and the remittance record"); CI-045 PARTIAL (line 314); CI-001 and CI-004 PARTIAL, each listing tax jurisdictions in "what is left" (lines 270, 273); CI-046 and CI-047 REP+PROT (lines 315–316); CI-038 PARTIAL (line 307). No later update section changes these rows.

**Scenarios** (`scenarios/`): the Bluebonnet cast bills a 1% city sales tax on every gas line inside the city (invented, `cast.md` line 70), none outside (SCN-0055); a tax line's base is the sum of the rounded lines it names (`README.md` line 28); the pipeline safety fee stays outside the sales-tax base (SCN-0054, `billing-pipeline-and-charge-composition.md` line 98); the GL mapping keys tax lines to "the city" as tax jurisdiction (`periods-and-aging.md` line 155). No scenario bills a franchise fee yet (the tax family is written after its patch mirrors).

---

## 2. What exists today

Ownership is from the board (`HANDOFF.md`, Streams table): rates owns "rate schedules, items and versions, riders, tax and franchise rules, gas cost and PGA, places and jurisdictions, … `service_locations`"; money owns "payments, credits, the ledger, invoices and their applications, …". A table not listed belongs to whichever stream touched it first.

### 2.1 `franchise_fee_rules` — rates

- **Defined** at line 3016 (base schema). Columns: `tenant_id`, `city_name text NOT NULL`, `fee_percentage numeric(8,6) NOT NULL` (no unit declared), `applies_to text DEFAULT 'total_bill'` (CHECK: `total_bill | gross_revenue | base_and_usage | usage_only`, line 3033), `applies_to_customer_types text[] DEFAULT '{residential,commercial,industrial,government,wholesale}'` (line 3022; no CHECK on the values), `effective_date DEFAULT CURRENT_DATE`, `expiry_date`, `status`, `remittance_frequency` (CHECK monthly / quarterly / annually), `remittance_contact`, `ordinance_reference`, `notes`, `metadata`.
- **Made bi-temporal in place by v5.4.2-03** (lines 15671–15736): `recorded_at`, `recorded_until`, `change_type`, `change_reason`, `changed_by`, `supersedes_id`, `closed_*`; `status` narrowed to `active | archived`, archived needs an expiry; one open row per (tenant, city name) per day by exclusion (`franchise_fee_rules_open_no_overlap_excl`, line 15719, keyed on `city_name`); triggers `a_enforce_bitemporal_assertion` (frozen once recorded except notes / metadata; identity columns `tenant_id, city_name`) and `enforce_superseded_has_successor`. RLS by tenant (line 11097), forced (line 11423).
- **Read by** `franchise_fee_as_of(tenant, city_name, valid_at, recorded_at)` (line 16047; both coordinates required). Nothing in the database calls it; the core will. A snapshot may cite a row (`invoice_snapshot_references`, line 19625).
- **Last changed** by v5.4.2-07, a column comment only (line 19778: `applies_to` is "Open with Kyle (decision table #26, question 2)"). Structurally last changed by -03. v5.4.2-16 left it on text on purpose (residual R4, line 27231: "franchise_fee_rules still names its city by text; it moves to a place when franchise fees are rebuilt").
- **No rows** exist (brief, 2026-10-13).

### 2.2 Taxability flags on rate items — rates

- `rate_item_versions.is_taxable_default boolean DEFAULT false NOT NULL` and `is_a_tax boolean DEFAULT false NOT NULL` (lines 15379–15380, v5.4.2-03). The ruling names `rate_items.is_taxable_default`; -03 moved both columns from the header to the versions table and dropped them from `rate_items` (line 15526). Comment (line 19779) still calls the false default "decision table #23's open question 1". `is_a_tax` has no comment.
- `rate_item_versions.applies_to_customer_types` carries the same size-tier default as franchise rules (line 15376).
- `rate_schedule_items.is_taxable_override boolean` (line 4159; nullable, no default). The old reader `get_effective_rate()` resolved `COALESCE(override, default)` (line 488); -03 disabled it (line 16164). Nothing in the database resolves taxability now.
- Guarded by `b_enforce_surcharge_rider_not_taxable` (lines 19043–19046): a rider with an open pipeline-safety rule excluded from tax bases can never be marked taxable or a tax.
- `calculation_type` includes `percentage_of_bill` ("Sales Tax, Franchise Tax", line 4124) and `percentage_of_charges` (a percentage of the base items named in `rate_item_dependencies`, line 4125; dated since -28).

### 2.3 `regulatory_surcharge_rules` — rates (v5.4.2-07/-08)

Line 18842. One bi-temporal row per (rate item, assessment cycle): `surcharge_kind`, `cap_per_service`, `excluded_from_tax_bases boolean NOT NULL`, `exempts_state_agencies`, references. `excluded_from_tax_bases` is a single flag covering every tax base (sales, franchise, gas utility tax). Its lines must have `is_taxable = false`, may not be `charge_type = 'tax'`, and can never be cited as a base (lines 19418, 42469 as re-issued by -28).

### 2.4 `invoice_line_items` tax columns — money

Line 3282. `charge_type` (CHECK includes `tax`, `surcharge`, `adhoc`, …), `is_taxable boolean DEFAULT false NOT NULL`, `taxable_amount numeric(12,2)` (the taxable part of a partly taxable line), `rate numeric(12,6)`, `rate_item_id`, `adhoc_charge_id`, `meter_id`, `service_type NOT NULL`, and `regulatory_class` (added by -23, line 43760). **No column names a jurisdiction, a place, a franchise rule or a tax rule.** The issued-bill freeze is -01's `enforce_invoice_immutable` as re-issued later (money).

### 2.5 `invoice_line_item_bases` — invoice family, built by -07 before the streams split (see section 5)

Line 19206. One row per (tax or percentage line, line it was computed on, amount taken): `line_item_id`, `base_line_item_id`, `base_amount` (non-zero). Checked by `enforce_invoice_line_item_base` (line 19274) and again at issuance: same invoice, sign-consistent, no larger than the cited line, never a line of an excluded surcharge; every non-zero tax or percentage line must have at least one row. **A tax line may cite another tax line** (decision D-2026-08-31-06: "tax-on-tax is #23 stage 3 / A-8, unruled"). A zero-amount tax line may have no rows.

### 2.6 `invoices.tax_breakdown` and the snapshot — money

- `invoices.tax_breakdown jsonb DEFAULT '[]'` (line 1658): "JSONB array of {jurisdiction, authority, rate_item_id, amount}"; since -04 a display record only (comment, line 16810). Frozen at issue.
- `invoice_calculation_snapshots.tax_inputs` (comment line 16357): JSON keys `jurisdictions[]` (`jurisdiction_id, authority, rate, taxable_base`), `exemptions[]`, `franchise_fees[]` (`franchise_fee_rule_id, rate, base`). What `jurisdiction_id` points at is not stated.
- `invoice_snapshot_references.source_table` (CHECK, line 19625) accepts eight tables: the seven A-1 tables (including `franchise_fee_rules` and `customer_tax_exemptions`) and `regulatory_surcharge_rules`. Not `places`, `place_facts`, `premise_place_memberships` or any law or tariff rule table.

### 2.7 `adhoc_charges.is_taxable` — money (by first touch: its guard was last re-issued by -23)

Line 1442: `is_taxable boolean DEFAULT false NOT NULL`; `service_type text` nullable. Comment (line 1493): "subject to percentage_of_bill tax components (sales tax, franchise tax). Set at charge creation time from platform defaults by charge_type" (the chain R5 reversed). `enforce_adhoc_charge_immutable` freezes it (-01 line 13600, -20 line 38486, -23 line 45168).

### 2.8 `should_charge_tax` and the exemption tables

- `should_charge_tax(customer, item_is_taxable, service_type, valid_at, recorded_at)` (line 16122, -03). Rules: item not taxable (or NULL) → false; an exemption in force for the customer whose `service_types` is NULL, empty, **or the caller passed a NULL service type**, or which lists the service type → false; else true. Nothing in the database calls it.
- `customer_tax_exemptions` (line 2857; -03 bi-temporal freeze from line 15738; -09 certificate evidence and renewal queue): `exemption_type` (`industrial` removed), `service_types text[]` (NULL = all services), certificate fields, `effective_start/end`, `status`, verification. Read by `customer_tax_exemption_as_of` and `customer_tax_exemptions_renewal_due`. **Not on the board's ownership list.**
- Legacy `customers.is_tax_exempt`, `tax_exemption_reason` (CHECK includes `residential`), `tax_exemption_certificate`, `tax_exemption_expiry_date`, `_notes`, `_verified_by/_at` (lines 2508–2515). No tax path reads them; the `customer_summary` view (line 2595) and `compliance_statistics` (line 11922) do. **`customers` is not on the board's list.**

### 2.9 Places and memberships — rates (v5.4.2-16, -29)

- `place_kinds` (line 26065): `county`, `municipality`, `limited_purpose_area`, `extraterritorial_area`, `unincorporated_area` sit on both axes; `transit_authority` on the tax axis only; `special_purpose_district` on both (districts stack). Platform-written only (`tally_app` has SELECT).
- `place_fact_kinds` (line 26115) seeds, among others: `sales_tax_rate` (number, **"as a fraction (0.02 = 2%)"**, range 0 ≤ v < 1, for state, county, municipality, transit authority, district; source Tax Code 321.102 and the Comptroller rate file); `residential_gas_taxable` (boolean, municipality and district; Tax Code 151.317, 321.105); `census_population` (municipality; the gross receipts bands of Tax Code §182.022); `special_district_type` (text); `gas_rate_jurisdiction_retained`; `local_adoption` (keyed by citation).
- `places` (line 26267): kind, state, code, name, parent, `effective_from/to` (half-open), source note, `recorded_txid`, `closed_at/by`. `place_facts` (line 26440): place, fact kind, key, `value jsonb`, half-open dates, source note, `closed_at/by`, no overlap per (place, fact, key). Both platform-written only; a correction is a close plus a new row.
- **Loaded today:** Texas (state) and all 254 counties with a `time_zone` fact (-16, -29). **No** municipality, transit authority or district; **no** `sales_tax_rate`, `residential_gas_taxable` or `census_population` fact.
- `premise_place_memberships` (line 26584): tenant-written (RLS); premise, place, `axis` (`regulatory | tax`), `relation` (within / outside with distance), `valid_from/to`, `evidence_kind` (includes `address_lookup`, `ordinance`), `evidence_reference`, `evidence_date`, close and void stamps. One place per exclusivity group per premise and axis at a time (one county; one of a city, its limited-purpose area or its ETJ); districts stack. The table comment says the regulatory axis covers "rate jurisdiction, franchise, customer law" and the tax axis "sales and local taxes".
- Read by `premise_places_as_of(location, on_date, axis)` (line 27021): **one date, no transaction-time coordinate**. Used by `premise_time_zone_as_of` and the service-profile lookup (lines 27088–27120). Nothing reads the tax axis for a tax yet.
- `jurisdictions` (line 11569, v5.4.0-03): tenant-scoped WNA record (`wna_applicable`, `wna_zone_id`), with `place_id` added by -16 (line 26975). Its comment says it is "NOT the A-8 tax_jurisdictions table". `service_locations.jurisdiction_id` points at it (line 11606).
- `gl_account_mappings.tax_jurisdiction_place_id` (line 41756, -22, money) already keys the GL mapping's tax jurisdiction to a place.

### 2.10 Legacy address proxies — rates

`service_locations.inside_city_limits boolean DEFAULT true NOT NULL`, `franchise_city text`, `city`, `county` (lines 4448–4458); `rate_schedule_versions.franchise_city` (line 14842; moved there from `rate_schedules` by -03). -16 residual R4: "nothing reads them for law".

### 2.11 The law-row and tariff-row pattern a place-keyed rule would follow — rates and money

- Rule-terms convention (-17, `rule_tables` registry at line 28532): role `law` (platform-held, written by migration) or `tariff` (the utility's own rows), a typed key, `terms jsonb` validated against `rule_term_schemas`, typed facets, a close floor; a tariff table may name its law table and a compare function.
- Law tables registered: `backbilling_rules` (line 24037), `deposit_rules` (line 34446), `payment_allocation_rules` (line 46474). Tariff tables: `deposit_tariffs` (line 34924, compares against `deposit_rules`), `payment_allocation_tariffs` (line 46567). **Every one is keyed by `state_code`, not by a place.** No rule table is keyed to a place today; `gl_account_mappings` (money) is the only rule-like table with a place key.
- Independently published values the law names go in `rule_parameters` / `rule_parameter_values` (line 29808): dated, scoped only by state or state plus service type.

---

## 3. Gaps (17)

Per ruling, what the schema lacks. "Core" means the evaluation belongs to the C# core and the gap is only what the schema must hold or refuse.

**R1 (a jurisdiction is a place, with dated tax rows; rates staged and signed off)**
1. **Franchise rules name their city by typed text.** `franchise_fee_rules.city_name`, its no-overlap exclusion and `franchise_fee_as_of` all key on the text, so a rule cannot point at a place and a typo in a city name silently finds no rule (CI-047's named failure).
2. **There are no per-jurisdiction tax rows.** Nothing says "this place levies this tax, on this base, at this position, from this date, under this citation". A place carries one bare `sales_tax_rate` number; there is nowhere to record which taxes a place levies on gas, their base or their order.
3. **No staging or sign-off for the Comptroller files.** Place facts are written only by platform migrations; there is no table for a proposed quarterly rate change (with its effective date) awaiting an operator's approval, and none for proposed premise-to-jurisdiction matches from the address file.
4. **The jurisdiction places are not loaded.** Only Texas and its counties exist; no city, transit authority or district, and no sales-tax rate on any place, so no premise can yet be placed on the tax axis in a city.
5. **The tax-axis links and tax facts cannot be read "as we knew it then".** `premise_places_as_of` takes one date; memberships and facts have close and void stamps but no read at a recorded-at coordinate, unlike the seven A-1 tables. A rebill cannot replay the tax jurisdictions the original bill saw (CI-001, CI-004).
6. **The legacy proxies are still the only franchise match.** `inside_city_limits` defaults to true (an unconfirmed premise is presumed in the city) and `franchise_city` is free text; neither is dated.

**R2 (source and citation on each line; franchise excludes the fee; franchise not in the sales-tax base)**
7. **A bill line cannot name the rule or jurisdiction that produced it.** `invoice_line_items` has no franchise rule, tax rule or place; `tax_breakdown` is display JSON; the snapshot's references cannot cite a place, a fact, a membership or a tax rule row.
8. **Nothing refuses tax on tax.** `invoice_line_item_bases` lets a tax line cite another tax line, so a sales-tax line can be computed on the franchise fee line, which R2 forbids; and no jurisdiction can declare a permitted pair.

**R3 (base type per jurisdiction from a fixed list, no default; one mechanism; size-tier defect)**
9. **The base type defaults and cannot say what Kyle described.** `applies_to` defaults to `total_bill`; none of its four values reads "every billed line except those the rules exclude".
10. **Three mechanisms describe a base.** `applies_to` on the rule, one `is_taxable` boolean per line (which the adhoc comment says serves sales tax *and* franchise), and `rate_item_dependencies` for `percentage_of_charges`. One boolean cannot put a line in the franchise base but out of the sales-tax base.
11. **The size-tier defect is live in two places.** `franchise_fee_rules.applies_to_customer_types` and `rate_item_versions.applies_to_customer_types` default to a list without `small_commercial` and `large_commercial`, and nothing checks the array's values against the customer-type list.

**R4 (liability by jurisdiction and period, optional filing reference)**
12. **No liability record.** Billed amounts by jurisdiction cannot be totalled because lines carry no jurisdiction (gap 7). Collected amounts become derivable once they do (-23 applies payments per line, `invoice_applications.invoice_line_item_id`, line 43790), but there is no period grouping and nowhere to put a filing reference. `remittance_frequency` and `remittance_contact` on the franchise rule are read by nothing.

**R5 (no silent default; item and customer both taxable per service type; $0.00 line)**
13. **The silent "not taxable" default remains.** `rate_item_versions.is_taxable_default` and `adhoc_charges.is_taxable` both default to false (and `invoice_line_items.is_taxable`, which the ruling does not name).
14. **Customer taxability is not strictly per service type.** `should_charge_tax` treats a NULL service type as matching any exemption, an exemption with no service types covers every service, and `adhoc_charges.service_type` may be NULL, so a one-off charge has no service type to test.
15. **Nothing records why a tax line is $0.00.** An exempt customer's $0.00 line can carry no base rows and no link to the exemption that zeroed it, so it cannot be told apart from a jurisdiction that levies nothing (CI-046; the emission itself is core).

**R7 (franchise reference date, tenant-overridable per jurisdiction)**
16. **No home for the override.** Nothing records a utility's per-jurisdiction choice of franchise reference date; the period-end default exists only in the decision table.

**R13 (percent storage)**
17. **Two tax rates are stored outside the percent rule.** `franchise_fee_rules.fee_percentage` is `numeric(8,6)` with no declared unit, and `sales_tax_rate` is a fraction with an upper bound of 1. Neither follows AC-45.

---

## 4. Conflicts and open points

Each is one drafting call or question; neither side is chosen here.

1. **Is there a `tax_jurisdictions` table or not?** Kyle's answer 1 says "Yes" to "a jurisdiction is just a place" and then "This is the `tax_jurisdictions` table (gap A-8)". The DECISION-LOG entry and the parity record read it as "a place, no separate table"; -22's GL mapping already keys tax jurisdiction to a place. The likeliest reading is that his "tax_jurisdictions" means the dated tax rows hanging off a place (gap 2), but he did not say so.
2. **Who holds a tax rate: the platform or the utility?** Kyle says the stack is "tenant-configured, not hard-coded", yet rates come from a platform job reading the Comptroller's files, with "an operator" signing off. -16 put `sales_tax_rate` on platform-held place facts. Ryan's standing rule R14 says a value the utility answers for is the utility's own row, with the published value as reference and a discrepancy report. The law-plus-tariff pair (`deposit_rules` with `deposit_tariffs` and a compare function) fits "both", but which side bills, and whether "operator" means the platform or the utility, is open.
3. **Which axis decides the franchise fee?** -16's membership comment puts franchise on the regulatory axis; Kyle's answer 2 puts the franchise fee in the tax stack. R9 keeps the axes separate, and an annexation dates them differently (ordinance date against the Comptroller's quarter), so the two readings bill a different first month after an annexation.
4. **The premise's city or the schedule's city?** Decision table #26 question 1 (and the brief's "related, smaller" question) asked which wins when `service_locations` and `rate_schedule_versions.franchise_city` disagree. Kyle did not answer it.
5. **What is on the "short fixed list" of base types?** The sources offer: "every billed line except those the rules exclude" (Kyle answer 2); the four current values `total_bill`, `gross_revenue`, `base_and_usage`, `usage_only`; "gross revenue minus the pipeline safety fee" (the brief); "in-city revenue with WNA excluded for certain classes" (decision table #26, citing the knowledge base). Also open: whether "excluded by rule" means the one `excluded_from_tax_bases` flag on surcharge rules (which today excludes a rider from every base at once) or an exclusion per base.
6. **Does `is_taxable` still mean anything for the franchise base?** Kyle 2026-10-14 asks for one mechanism; Kyle 2026-11-03 answer 4 says city sales tax applies "on the lines the tenant flags taxable", so the flag survives at least as the sales-tax flag. The adhoc comment says the flag also governs "franchise tax". Whether the franchise base reads the flag, the base type, or the base type minus exclusions decides which of the three mechanisms (gap 10) stays.
7. **The ruling names columns that moved.** It says drop the default on `rate_items.is_taxable_default`; since -03 the column lives on `rate_item_versions`. And `invoice_line_items.is_taxable DEFAULT false` has the same silent default but the ruling does not name it (money's table).
8. **One franchise rate or two?** Decision table #26 says the fee "is itself computed as a `percentage_of_bill` rate item". The rate would then live both on `franchise_fee_rules.fee_percentage` and on the rate item's `rate_value` (in percent, AC-45), with nothing tying the two. Also undecided: whether a franchise line is `charge_type = 'tax'` (it is not a tax by law) or a surcharge, which matters to gap 8 and to the GL mapping.
9. **Sales-tax rate as a fraction or a percent.** -16's `sales_tax_rate` is a fraction (0.0825); AC-45 says every percentage rate is stored in percent. AC-45 speaks of rates "entered" on rate items, and place facts are platform reference data, so whether AC-45 reaches them is itself the question.
10. **Does a tax exemption stop the franchise fee?** `should_charge_tax` is for taxes, and a franchise fee is a street-rental charge, not a tax. An exempt church may still owe the city's fee. The ordinance's own carve-outs ride on `applies_to_customer_types`. The rulings are silent.
11. **Must an exempt $0.00 line show its would-be base?** Decision table #23 says an exempt customer "still has a base composed (so the snapshot shows what *would* have been taxed)"; -07 lets a zero tax line carry no base rows. Kyle's $0.00-line ruling does not say which.
12. **The remittance half of CI-044 needs re-reading.** The invariant says the aggregate "reconciles dollar-for-dollar against the remittance total owed"; Kyle answer 4 narrows the platform to the liability. As with CI-036 after answer 6, the register text and the parity row should be re-read against "liability only". Also open: is the liability's "period" the accounting period (-22, money) or the filing period on the franchise rule (`remittance_frequency`)?
13. **Retire the legacy exempt flag?** The brief proposed retiring `customers.is_tax_exempt` (its reason list still includes `residential`, the category error R8 names). Kyle did not answer. The CI-046 register queues it as a database-written display projection instead. `customers` is not on the board's list.
14. **Does the §182.025 ceiling reach our first customers?** Decision table #26 checks a franchise rate against 2% of gross receipts at save. Our first customers are city-owned systems outside the state's gas utility law (R15). Whether Tax Code ch. 182 subchapter B binds a city-owned system, and whether such a system bills a franchise fee to its own customers at all, needs checking against the statute before the ceiling becomes a law row.
15. **Is the gas gross receipts tax a bill line?** Decision table #26 says the Tax Code ch. 182 gross receipts tax is "company-level, embedded in rates, and a reporting requirement". The -28 percent decision treats its rates (0.581%, 1.070%, 1.997%) as rates to store, and -16 seeded `census_population` for its bands. Brenham's tariff passes through taxes "excluding gross receipts taxes" (`scenarios/cast.md` line 69). Whether it is ever a line on a bill decides whether it belongs in the stack.
16. **What decides "residential" for city sales tax?** R8 derives the state exemption from rate class and premise use; Kyle 2026-11-03 answer 4 limits city tax on residential gas to inside city limits. The schema has three candidates: `customers.customer_type`, the schedule's `customer_type`, and the premise's `location_type`. Related: a limited-purpose area bars city taxes (LGC 43.130) and an ETJ is outside the city; both kinds exist on the tax axis, but no rule says what each means for a tax.
17. **Water and sewer.** Kyle defers their sales-tax treatment to tax counsel. The stack's rows must not be gas-only in shape (launch scope is not architecture scope), but no values are known.
18. **Carried in by the rates handoff:** settle with the city loads whether Farwell and Texline (on the New Mexico line) are Mountain time by 49 CFR 71.7(g) (-29 residual L3). Not a tax question.

---

## 5. Tables this touches that belong to the money stream (for the board)

| Table or object | Why the tax patch would touch it | Gap / point |
|---|---|---|
| `invoice_line_items` | A link from a tax or franchise line to its rule and its place; the silent `is_taxable DEFAULT false`; what `charge_type` a franchise line carries | gaps 7, 13; points 7, 8 |
| `invoice_line_item_bases` | Refuse tax on tax unless the jurisdiction declares it; possibly require the would-be base on an exempt $0.00 line. Built by -07 before the streams split; it is invoice content, so money's by the board's "invoices" | gap 8, 15; point 11 |
| `invoice_snapshot_references` (source-table list) and `invoice_calculation_snapshots.tax_inputs` | Let a snapshot cite places, facts, memberships and any new tax rule table; say what `jurisdiction_id` in `tax_inputs` points at | gaps 5, 7 |
| `invoices.tax_breakdown` | Display only; may need its `jurisdiction` key to name a place | gap 7 |
| `adhoc_charges` | Drop `DEFAULT false` on `is_taxable` (named by the ruling); a required `service_type`; its comment describes the reversed default chain. Its guard was last re-issued by -23 | gaps 13, 14 |
| `invoice_applications` (read only) | "Collected by jurisdiction" is a sum over line-level applications | gap 12 |
| accounting periods (-22) and `gl_account_mappings` | The liability's period, if it is the accounting period; the GL mapping already keys tax jurisdiction to a place, so a franchise or tax line's place must match it | gap 12; point 12 |

**Not on the board's list at all** (to be claimed when touched): `customers` (the legacy exempt columns, point 13) and `customer_tax_exemptions` (the per-service-type rule, gap 14). The second is tax data and sits naturally with rates' "tax and franchise rules"; the first holds money's deposit columns too.
