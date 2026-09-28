# 09 — ui-concepts (Next.js prototype) — Texas-only architecture audit

## Summary
- Scope: `ui-concepts/` schemas, fixtures, lib, app, components (node_modules skipped). Paths below are relative to `ui-concepts/` unless prefixed `sql/`.
- The UI has no notion of a jurisdiction at all. No component takes a state or service type. Texas law lives in three forms: fixture rows that cite 16 TAC (acceptable as seed data, but the TYPES around them are closed Texas lists); hardcoded constants and copy in screens ("Texas cap", "Texas 12-month look-back", "Railroad Commission of Texas rules", ">= 3"); and code shapes that only fit a Texas gas tariff (`RateCard`, gas-only unit pickers, and tax branching in the fixture generator).
- Kyle's newest work: **Add payment** hardcodes oldest-first at invoice level. It ignores the SQL `tenants.payment_allocation_strategy` and `overpayment_handling`, and it has no charge-level priority (some states require partial payments to go to regulated or basic service first). **AR aging** buckets (30/60/90) are an accounting convention, not a state rule, but the customer-class axis is a fixed 3-way collapse. **The rate editor** offers only gas units and defaults usage to per-therm. **The Payments tab** is mostly generic.
- The disconnect worklist is the heaviest one. `BypassCode` is a closed union of Texas §7.460 conditions. Protection scope is a single `isResidential` boolean. The temperature hold, notice period and the "no winter moratorium" claim are Texas facts printed as the screen's logic.
- SQL divergence (verified): the UI still models `customers.disconnect_protection_type` and its CHECK list, which `sql/tu.sql:11902-11903` dropped in favour of `program_types` (`sql/tu.sql:11722-11736`). The UI models PSF as a plain rate item, while SQL has `regulatory_surcharge_rules` (`sql/tu.sql:18874-18877`). The UI's gas de-minimis void threshold contradicts the SQL comment that gas always requires a full correction (`sql/tu.sql:4803`).
- Good: rate item versions are effective-dated tenant data with a `regulatory_reference`. The unit enums are multi-service and match the SQL CHECK lists.
- Counts: a=2, b=5, c=22 (29 findings).

---

## 1. Jurisdiction binding

### Tenant carries one regulator as a display string
- where: fixtures/tenant.ts:13 — const `tenant.jurisdiction: 'Railroad Commission of Texas'`
- rule: one regulator per tenant, as free text; nothing reads it to select rules.
- class: b
- other states: a multi-state gas LDC (e.g. Atmos, CenterPoint span TX/LA/OK/MS…) answers to several commissions. A combined gas+water municipal answers to a state PUC for one service and to the city council for the other.
- fix: derive jurisdiction per service location (state + service_type, sub-state place where relevant). Every rule-bearing screen reads it from the account or premise, never from the tenant. — size: M

### Regulator name hardcoded in page chrome and editor copy
- where: app/collections/page.tsx:136 — PageHeader meta "Railroad Commission of Texas rules"; app/rates/page.tsx:85 — meta "RRC tariff GUD-10928"; components/rates/RateItemsEditor.tsx:332 — "what an auditor or the RRC reads"; :342 — placeholder "e.g. RRC GUD-10928 PGA filing"
- rule: the regulator is always RRC.
- class: c
- other states: any non-Texas tenant sees the wrong regulator (e.g. Oklahoma Corporation Commission, Louisiana PSC, NM PRC; guesses on exact agency names are safe).
- fix: render from the jurisdiction row's regulator name and the schedule's `tariff_number`. — size: S

## 2. Collections and disconnect

### "Conditions in force today" list is Texas's rule set
- where: fixtures/collections.ts:27-69 — type `Condition` + const `conditionsToday` (temperature_hold 32°F §7.460(d), winter_window `not_adopted`, dpa_offer §7.45(g), notice_maturity "Ten days" §7.460(b))
- rule: 16 TAC §7.460 / §7.45 disconnection preconditions; threshold 32°F and the 10-day notice sit in `detail` strings.
- class: b (the shape is good: a code, a state including `not_adopted`, a citation and a scope. But it is a flat global list with no jurisdiction or service key, no effective dates, and the numbers are prose.)
- other states: many states use a calendar winter moratorium (e.g. Nov 1–Mar 31 style windows; Oklahoma and Louisiana differ from TX, specifics are a guess), different temperature thresholds (some use 20°F, some add a heat threshold), and different notice periods (5, 7 or 14 days are common elsewhere). Water and electric have their own rules.
- fix: a platform table of disconnect conditions keyed by state_code + service_type + effective range. It needs typed parameters (threshold_f, window_start/end, notice_days, applies_to_classes) and a `_for(state, service, date)` lookup, as in `meter_accuracy_thresholds`. The UI renders the rows it gets. — size: L (the same substrate the SQL side needs)

### Bypass codes are a closed union of Texas conditions
- where: fixtures/collections.ts:78-89 — type `BypassCode`; :99 — `BypassCategory`; :109-187 — const `BYPASSES` (citations 16 TAC §7.460(b)(c)(d)(f)(h)(i), §7.45(g))
- rule: the set of disconnect-blocking conditions and each one's category (protection, weather, process). `senior_grace` (§7.460(i)) and `designee_not_notified` (§7.460(c)) are Texas clauses. The category order in `evaluate()` (:492-517) is operational and fine.
- class: c
- other states: some states add conditions Texas lacks, e.g. a household with children under a given age, a heat-wave hold, or a pending energy-assistance application; others drop senior grace or give it different day counts (a guess on the specific states). A condition's category can differ by state (a medical certificate that only postpones is "process-like" in some states).
- fix: the bypass vocabulary comes from per-jurisdiction condition rows (code, category, citation, expiry semantics). The TS type becomes `string` validated against the lookup. It should map to SQL `program_types` for customer-held protections. — size: M

### Protection scope is a residential/commercial boolean
- where: fixtures/collections.ts:199 — `WorklistRow.isResidential: boolean`; app/collections/page.tsx:489 — label `Residential` : `Commercial`; :415-426 — StateBlock "The temperature hold covers residential service only. Texas has no calendar winter moratorium — 16 TAC §7.460…"
- rule: the Texas temperature hold protects residential service only; this is presented as the screen's governing explanation.
- class: c
- other states: protections are often scoped by more than residential or not. Master-metered multifamily, small commercial, and facilities such as hospitals and nursing homes can be in scope elsewhere (a guess on specifics). Water shutoff rules often scope by household occupancy.
- fix: the condition row carries `applies_to_classes` (or a predicate over customer class and premise type). The explanatory block is rendered from the in-force row's scope and citation, not written as fixed prose. — size: M

### Reconnect priority is a fixed three-value union
- where: fixtures/collections.ts:574 — `ReconnectRow.priority: 'medical' | 'temperature' | 'standard'`; :622 — "Commercial, 48-hour SLA"; :610 — after-hours differential; app/collections/page.tsx:267 — "Pressure test, then relight every pilot" on every row
- rule: reconnect priority classes and SLA; gas relight on every reconnect.
- class: c
- other states: reconnect deadlines are statutory in several states (e.g. within 24 hours of payment or the next business day; a guess on which). Water and electric have no relight step.
- fix: reconnect SLA and priority come from jurisdiction and service rows. The relight text is conditional on service_type = gas. — size: S

### UI still models the dropped single-slot disconnect protection
- where: schemas/enums.ts:306-315 — `DisconnectProtectionType`; schemas/models.ts:69-71 — `Customer.disconnect_protection_type/expiry`; app/customers/[customerId]/page.tsx:106-107
- rule: a closed protection list transcribed from the old CHECK `sql/tu.sql:2533`. That column and CHECK were dropped at `sql/tu.sql:11902-11903`. Protections are now `customer_program_enrollments` over platform table `program_types` (`sql/tu.sql:11722-11736`), which renames `military_deployment` to `military_deployment_scra` and adds `agency_pledge`, `budget_billing` and `third_party_notification`.
- class: c (also a UI/SQL divergence)
- other states: even the SQL `program_types` is platform-global and not state-keyed; its descriptions cite Texas (CI-080/081/129). Whether a program type is protective varies by state. That is for the SQL auditors, noted here because the UI will inherit it.
- fix: replace the enum with enrollments read from `program_types`, where protective-ness should be per jurisdiction. Drop the stale model fields. — size: S (UI) / M (SQL keying)

## 3. Payments (new work)

### Add-payment allocation is hardcoded oldest-first, invoice-level only
- where: components/payments/PaymentForm.tsx:147-148 — sort by dueDate, then invoiceDate; :166-175 — `allocate()`; :459, :470 — copy "pays the oldest bill first" / "Reset to oldest first"
- rule: payments apply to the oldest open invoice first, whole-invoice, with no charge-type priority.
- class: c
- other states: SQL already makes this a tenant choice, `tenants.payment_allocation_strategy` with values oldest_first, newest_first, largest_first and manual_only (`sql/tu.sql:4606`, CHECK `:4627`), and the UI ignores it. Beyond that, some commissions prescribe the order inside a bill: partial payments go first to regulated or basic utility service (so they count against disconnection) before non-regulated charges such as merchandise, appliance repair or other-service fees. Pennsylvania's Chapter 56 is the usual example; the exact section is a guess. Multi-service municipal bills (water/sewer/trash) often have an ordinance-set order.
- fix: allocation reads a strategy. The tenant's strategy covers invoice order, plus a per-jurisdiction and per-service "priority class" order over charge types or display groups that the allocator applies within and across bills. The UI shows the resolved rule's citation. — size: M

### Unapplied money can only become a credit on account
- where: components/payments/PaymentForm.tsx:190, :229 — `creditOk`; :707-712 — the only option is "Hold … as a credit on the account"
- rule: an overpayment is always held as a credit.
- class: c
- other states: SQL has `tenants.overpayment_handling` (hold_as_credit / refund_automatically / apply_to_specific_invoices, `sql/tu.sql:4607`, CHECK `:4626`) and `minimum_refund_amount` (`:4609`). Some states require refunding credit balances on request or above a threshold (a guess on specifics).
- fix: offer the options that the tenant setting and any jurisdiction refund rule allow. — size: S

### Returned-check restriction is permanent and string-matched
- where: app/payments/new/page.tsx:42-47 — any NSF payment ever adds the note "accept cash, money order or card only"; components/payments/PaymentForm.tsx:231, :240 — `noChecks = text.startsWith('Returned check')` blocks check payments
- rule: after one returned check, checks are refused forever.
- class: c
- other states: rules that allow a utility to demand certified funds often limit it, e.g. after 2+ NSFs within 12 months and only for 12 months. That is a guess at the typical form, and some states specify it. It is also tenant policy.
- fix: a tenant policy (count, lookback, duration) with an optional jurisdiction cap. Key it off a flag, not a note's prefix. — size: S

### "Payment in full stops the disconnect process" as fixed copy
- where: app/payments/new/page.tsx:48
- rule: what cures a pending disconnect.
- class: c
- other states: many states treat the past-due amount, not the full balance, or an agreed arrangement, as the cure (a guess on specifics). Texas nuances exist too.
- fix: the note is generated from the jurisdiction's cure rule. — size: S

## 4. AR aging and customer classes (new work)

### Aging buckets and the "arrears" threshold are fixed constants
- where: components/collections/AgingReport.tsx:32-38 — `BUCKETS` Current/1–30/31–60/61–90/90+; :233, :237 — red at `daysPastDue > 60`; app/collections/page.tsx:499 — `arrears={row.pastDueDays >= 60}`; fixtures/billing.ts:1058-1061 — dashboard buckets
- rule: none statutory. 30/60/90 is the accounting convention, which is fine to ship as a default.
- class: c (low priority; not state law)
- other states: some commissions ask for arrearage reporting in their own bands (e.g. 30/60/90/120+ or 0–60/61–90; a guess). The 60-day red is a policy choice.
- fix: tenant-configurable bucket edges, with a report-template override per regulator. — size: S

### Aging collapses customer type to a fixed 3-class axis
- where: components/collections/AgingReport.tsx:12 — `CustomerClass = 'Residential' | 'Commercial' | 'Government'`; :39 — `CLASSES`; app/collections/page.tsx:87-95 — `CLASS_OF` maps industrial and wholesale to Commercial
- rule: the reporting class set is fixed.
- class: c
- other states: arrears reports to commissions are usually by tariff class. Water utilities report irrigation, multifamily and fire-line; electric reports lighting and agricultural.
- fix: the report axis is the tenant's class list (or rate-schedule class) with a configurable roll-up. — size: S

### Customer type enum is a closed list
- where: schemas/enums.ts:295-303 — `CustomerType` (same as the CHECK `sql/tu.sql:2531`, `:4210`, `:14876`)
- rule: 7 fixed classes for customers and rate schedules.
- class: c
- other states: water needs irrigation, multifamily/master-metered, fire service. Electric needs lighting and agricultural. Some gas tariffs split transport, interruptible and public authority (a guess on naming).
- fix: a per-tenant class catalog (tariff classes are the utility's own), optionally mapped to a platform-standard reporting class. The UI enum goes away. — size: M (mostly SQL)

## 5. Rates and the rate editor (new work)

### Tariff sandbox RateCard is the Texas gas tariff, hardcoded
- where: fixtures/tariff.ts:14-34 — `type RateCard` (customerCharge, exactly two blocks, pga, wna, grip, psf, franchisePct, gutPct, minimumBill); :78-94 — `billFor()` arithmetic; :52-59 — `LEVERS` ("first 50 therms"); components/rates/TariffSandbox.tsx:46-51 — therm bands; :224-226; :384 — copy "Franchise fee and gas utility tax ride on top of it at 4.5%"
- rule: the rate structure is Texas gas. GRIP is Texas Gas Reliability Infrastructure Program interim-rate rider; PSF is the Texas pipeline safety fee; the municipal gas utility tax and franchise fee are percentage-of-charges. There are always 2 inclining blocks, and the tax sits on the charges subtotal.
- class: c
- other states: other states have other riders (e.g. infrastructure trackers under other names, energy-efficiency riders, decoupling instead of WNA), more or fewer blocks, seasonal rates, demand charges, and tax computed on different bases. Water has 3–5 tier inclining blocks per kgal plus fixed meter-size charges. Electric has kWh tiers, TOU and demand.
- fix: the sandbox evaluates the schedule's actual rate items (calculation_type + tiers), the same engine as billing, rather than a bespoke card. Levers are the chosen item codes. Tax and franchise ride-along comes from the tax rows. — size: L

### Rate editor offers only gas units and defaults usage to per-therm
- where: components/rates/RateItemsEditor.tsx:30 — `UNITS = ['per_month','per_therm','per_ccf','per_mcf','percent','flat']`; :33-40 — `UNIT_FOR` maps per_unit_usage, usage_modifier and tiered_usage to `per_therm`; :29 — `CALCULATIONS` omits `fixed_annual` and `formula`
- rule: gas-only units in the editor, although `RateUnit` (schemas/enums.ts:340-354) and SQL CHECK `sql/tu.sql:4108` include per_gallon, per_kgal, per_kwh and per_cubic_meter.
- class: c
- other states: any water or electric tenant, or a gas tenant billing in Mcf or Dth by default.
- fix: filter units by the schedule's service_type; take the default from service_type or tenant setting. — size: S

### Rate schedule model has no service type; regulator is free text
- where: schemas/models.ts:317-329 — `RateSchedule` (`regulatory_authority: string | null`, no `service_type`); fixtures/rates.ts:20, :33, :46 — 'Railroad Commission of Texas' on every schedule
- rule: implied one service and one regulator.
- class: b
- other states: SQL rate schedules carry `service_type` (`sql/tu.sql:14939`, `:14945` select `rs.service_type`). The UI drops it, so a gas+water tenant's schedules are indistinguishable.
- fix: add service_type (and jurisdiction) to the model, and filter units, derivation and bill copy by it. — size: S

### Class-independent items listed by hardcoded code
- where: app/rates/page.tsx:27-31 — `CLASS_INDEPENDENT = ['PGA-GAS','PSF-TX','GRIP-2025','FRAN-BRYAN','FRAN-CSTAT']`; :45-47 — schedule membership assigned by code
- rule: which items apply to all classes, by Texas item code.
- class: c
- other states: every other tenant's riders and fees have other codes.
- fix: item-to-schedule applicability is data (rate item linked to schedules, or an "all schedules" flag). — size: S

### PGA de-minimis void threshold ($2.00) on gas bills
- where: fixtures/pga.ts:169-176 — `thresholdAmount: '2.00'`, `thresholdTherms`; app/rates/pga/page.tsx:139-144 — copy
- rule: below $2 a gas correction becomes an adjustment on the next bill instead of void-and-rebill.
- class: b (fixture constant; a tenant policy in spirit)
- other states: this contradicts the SQL, where `tenants.void_rebill_threshold` is "Non-gas meters only … Gas meters always require full correction regardless of this setting" (`sql/tu.sql:4620`, `:4803`). Whether a de-minimis exists, and how large, can be a commission rule on refunds and credits (a guess).
- fix: read `void_rebill_threshold` plus any jurisdiction refund de-minimis. Reconcile the gas exception with the owner. — size: S

## 6. Taxes, fees, franchise

### Franchise fee hangs on an inside-city-limits boolean and one city
- where: schemas/models.ts:98-100 — `ServiceLocation.inside_city_limits` / `franchise_city`; app/customers/[customerId]/page.tsx:158-165 — "Inside city limits — franchise fee applies" / "Outside … no franchise fee"; fixtures/bill-history.ts:326-328 — `franchise_city === 'Bryan' ? 'FRAN-BRYAN' : 'FRAN-CSTAT'`, 4%
- rule: the Texas municipal franchise model, where one city fee applies inside limits and none in the environs (mirrors SQL `sql/tu.sql:4457-4458`).
- class: c
- other states: stacked taxing jurisdictions such as city + county + special district/parish (Louisiana parishes, a guess). Some franchise fees are per-therm or per-meter, not percent. In some states a fee applies in unincorporated areas too.
- fix: a premise-to-tax-jurisdiction many-to-many (the SQL comment at `sql/tu.sql:11615` already lists "tax jurisdiction" as an open zone FK), with fee rows per jurisdiction. The UI lists every jurisdiction that applies. — size: M

### Tax applicability decided in code by customer class
- where: fixtures/bill-history.ts:220 — `taxable = display_group !== 'taxes_fees' && rate_item_code !== 'PSF-TX'`; :330-331 — residential gets "Gas utility tax" GUT-TX 0.5%, else "TX state sales tax" 6.25% unless `is_tax_exempt`; fixtures/rates.ts:355-358 comment "residential gas is exempt in Texas"
- rule: Texas Tax Code §151.317 residential gas exemption. PSF is excluded from the tax base.
- class: c (a fixture generator, but it is the only rating logic in the prototype and will be copied)
- other states: residential utility exemptions differ by state and service (some tax residential gas at a reduced rate, some exempt water, and electric differs). Base exclusions differ.
- fix: the generator calls a tax-applicability lookup (jurisdiction × service × class × item). It mirrors SQL `should_charge_tax` (`sql/tu.sql:755`), extended with state keying. — size: M

### State sales tax and the statutory pipeline fee stored as tenant rate items
- where: fixtures/rates.ts:276-290 — `PSF-TX` rate item citing "TX Nat. Res. Code §121.211"; :435-448 — `TX-SALES` 6.25% citing "TX Tax Code §151.317"; fixtures/billing.ts:146, :187, :767-770; fixtures/bill-history.ts:302
- rule: state-law charges held as ordinary per-tenant rate items with no state key. Every Texas tenant re-keys the same statute.
- class: b
- other states: SQL already models PSF as `regulatory_surcharge_rules` with kind `pipeline_safety_fee` and shape CHECKs (`sql/tu.sql:18874-18877`); the UI does not. Other states' pipeline or regulatory assessments have different caps and bases.
- fix: the statutory rate lives in a platform per-jurisdiction row; the tenant row only links or adopts it. The UI shows the rule's source. — size: M

### Percent lines recognised by a closed charge_type pair
- where: app/invoices/[invoiceId]/page.tsx:330-335 and app/invoices/[invoiceId]/diff/page.tsx:261-263 — `lineRateUnit()` returns percent only for `franchise_fee` | `tax`
- rule: only franchise fees and taxes are percentage charges.
- class: c (minor)
- other states: percentage riders such as regulatory assessment fees and gross-receipts pass-throughs would render as $/unit.
- fix: use the line's rate item `rate_unit`/`calculation_type`. — size: S

## 7. Estimation, backbilling, corrections

### Estimate streak cap hardcoded at 3 and labelled Texas
- where: app/customers/[customerId]/page.tsx:185-192 — `consecutive_estimate_count >= 3` gives "At the Texas cap"; fixtures/exceptions.ts:26-30 — "Third consecutive estimate — at Texas cap", `cap: 3`
- rule: maximum consecutive estimates.
- class: c
- other states: SQL keeps this as tenant setting `settings.estimation.max_consecutive_estimates` (default 3, `sql/tu.sql:4651`), which is tenant-keyed, not jurisdiction-keyed. Other states allow 2 or 6, or require an actual read every N months (a guess on specifics). Water AMR tenants differ again.
- fix: read the resolved cap and its source (jurisdiction row or tenant override) and print the citation instead of "Texas". — size: S

### Backbilling check is copy saying "Texas 12-month look-back"
- where: app/invoices/[invoiceId]/diff/page.tsx:247 — `Check done label="Backbilling cap" detail="Texas 12-month look-back…"`; :251 — "Supervisor approval required for corrections over $50.00"; :252 — "Regulated language: this bill replaces…"
- rule: Texas §7.45 backbilling limit; a $50 approval threshold; mandated replacement-bill wording.
- class: c
- other states: SQL now has `backbilling_cap_rules` (sql/v5.4.2-13-backbilling-caps.sql:685, scopes at :717/:719) and `tenants.backbilling_adverse_limit_months` (:307). Look-back periods differ (e.g. 6, 12 or 24 months, or none; a guess on which states). The approval threshold is tenant policy.
- fix: render the check from the resolved cap rule, its citation and the computed window. Put the approval threshold in tenant config and the replacement-notice text in per-jurisdiction bill templates. — size: S (UI), once the SQL rule is jurisdiction-keyed

## 8. Bill document

### Regulated bill notices hardcoded in the statement
- where: app/invoices/[invoiceId]/page.tsx:320-324 — "Call … within 30 days", "payment arrangements and energy assistance referrals", "Service will not be disconnected for non-payment without written notice"; :208 — tenant address "Bryan, TX 77805" inline
- rule: mandated bill-content language (Texas bill-content rules), fixed.
- class: c
- other states: required bill disclosures differ by state and service: dispute-rights wording, commission contact, Spanish-language requirement, LIHEAP text, water-quality notices.
- fix: bill notice blocks come from per-jurisdiction and per-service template rows, effective-dated. SQL `bill_messages` (display_group header/footer/notice_box, `sql/tu.sql:2235`) is a candidate home. Tenant contact details come from tenant data. — size: M

## 9. Gas-only shapes

### Gas derivation and gas pipeline stages are unconditional
- where: schemas/models.ts:159-163, :272-277 — `gas_*` columns on MeterReading and InvoiceLine (mirroring DDL); app/reads/page.tsx:38-44, :130-133 — "Gas correction" column group (Mult., BTU factor, Therms) always shown; app/invoices/[invoiceId]/page.tsx:414-450 — Inspector derivation Ccf, multiplier, BTU, therms; picks `charge_type === 'pga'`; app/runs/[runId]/page.tsx:29-38 — `STAGES` fixed with "BTU + pressure correction" and "WNA applied"; lib/vocabulary.ts:5-7 comment
- rule: every meter is gas; every run applies BTU correction and WNA.
- class: c
- other states: WNA is a Texas/South-Central gas mechanism, and many states use decoupling or nothing. Water and electric runs have no BTU step. Pressure correction applies only to some gas meters.
- fix: the derivation rail and the run stages are driven by the service type and the rate items actually present (stage list from the run's pipeline definition). Gas columns show only for gas reads. — size: M

## 10. Held correctly (good examples)

### Consumption and rate unit enums are multi-service and match SQL
- where: schemas/enums.ts:169-180 — `ConsumptionUnit`; :340-354 — `RateUnit` (match `sql/tu.sql:3577` and `sql/tu.sql:4108`); lib/vocabulary.ts:10-20, :59-73 label maps cover all
- rule: none state-specific. Water, electric and gas units are all present. (It is still a closed list, but of physical units, not law.)
- class: a
- other states: fine. Dth (dekatherm) is mentioned in vocabulary copy but absent from both enums, a small gap for interstate-supply gas tenants.
- fix: none needed; optionally add `dth`/`per_dth`. — size: S

### Rate items are effective-dated tenant data with a citation
- where: schemas/models.ts:338-358 — `RateItemVersion` (effective_from/to, recorded_from/until, change_type, change_reason, regulatory_reference); lib/rate-changes.ts:159-193 — close-then-insert `applyDraft`
- rule: the utility's own tariff numbers as dated, cited data, which is the right place for them.
- class: a
- other states: works for any jurisdiction. The only gap is that statutory items (PSF, state sales tax) are ALSO put here instead of in platform per-jurisdiction rows (see section 6).
- fix: none. — size: S
