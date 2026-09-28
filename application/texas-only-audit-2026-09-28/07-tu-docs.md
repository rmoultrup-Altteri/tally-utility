# 07 — tally-utility docs: where the docs state Texas law as architecture

Scope: CONTEXT.md, INVESTIGATION-BRIEF.md, TECH-STACK-DISCUSSION.md, application/ (APPLICATION-CONTRACTS.md = "AC", DECISION-LOG.md = "DL", draft-candidates.md = "DC", session-1-recon.md = "S1R", database/schema.sql, FEATURE-LIST.md). CHANGELOG/HANDOFF skipped. FEATURE-LIST.md is a 3-line pointer with nothing to find.

## Summary

- **Where it started.** S1R:99 says the Texas rules "are invariants, not configurable policies". F1 (S1R:101-106, 145) then kept them in the canonical register as Texas-only entries. Session 2 did this unevenly (DC map rows 205-224). Four Texas candidates were folded in as the per-jurisdiction value of a universal rule, which is correct (15+5+5 disconnect sequence, dispute cap, PGA cadence, BTU conditions). Fifteen became standalone **"Texas —" invariants** (CI-038, CI-078…081, CI-086…092, CI-129…131). The schema patches then built those fifteen as structure.
- **The docs tell builders to hardcode statutes.** The AC file is the build contract. It names "§7.45-basis" deposits, the TCFV reference, the 30/31-day interest cliff, the twelve-clean-bill refund trigger, the `pipeline_safety_fee` kind and "state agency". DL records a statute as structure as a win: "every rule of the Texas accrual/refund discipline is a refusal" (DL:290). DL also pins a day boundary to America/Chicago (DL:218).
- **Statewide values are held per tenant.** Deposit interest rate ("a new PUCT rate", AC:246), PSF cap (AC:253), estimate cap (AC:224) and certificate-required flags (AC:273) are all tenant-keyed. None is keyed by state and service type.
- **Next patch at risk.** CONTEXT.md:33 frames the in-flight A-2 as "the 16 TAC §7.45 limits on backbilling". The register's own CI-008 says "Backbilling Cap Per Jurisdiction".
- **Good examples.** `meter_accuracy_thresholds` (DL:19, AC:312). CI-008 / CI-067 / CI-132 framing. The F2 folds that treat a Texas number as a boundary value. The "no uncitable seeded number" principle (DL:169).
- **Stale schema.sql.** It shows the base shapes that fed all this: an `inside_city_limits` boolean, franchise rules keyed by tenant and city name, one `tenants.state`, and WNA defaults of Nov–Apr and per_mcf.

---

## Theme 1 — Scope statements that lead a builder to hardcode (the root)

### Texas rules declared "invariants, not configurable policies"
- where: application/session-1-recon.md:99 — recon finding #2
- rule: "Several Texas rules (e.g., the no-disconnect-for-stale-underbilling list, the meter-test rebill bounds, the deposit auto-refund trigger) are concrete operational rules that the system *must* implement at launch — they are invariants, not configurable policies." — source: file 31 / 16 TAC §7.45
- class: c
- other states: every rule named has a different or absent counterpart elsewhere. Examples: the meter-error window (6 months in TX); refund-after-N-good-bills (the N varies by state; a guess for OK/LA/NM); disconnect carve-out lists. A builder reading this makes them structure.
- fix: add a dated correction that follows the owner ruling. The *discipline* is the invariant. The Texas values are the first rows of per-jurisdiction data. Contradicts S1R:118-123 (F2 in the same file) — size: S

### F1: Texas candidates kept as Texas-tagged canonical entries
- where: application/session-1-recon.md:101-106, 143-145 — flag F1 and its recommendation
- rule: "(a) Canonical doc holds Texas as launch-scope content … each Texas candidate tagged `jurisdiction: texas`". Recommended and adopted.
- class: b
- other states: tagging is data-like. But the result is one invariant per Texas rule ("Texas — EWE…"), not one universal invariant with per-jurisdiction values. Adding Oklahoma would mean a parallel "Oklahoma — …" family, and schema patches written per entry.
- fix: re-cut the "Texas —" CIs as universal disciplines, with Texas values as boundary rows (the F2 pattern already used for INV-151/152/145/161) — size: M

### Session 2 map: 15 candidates became standalone Texas invariants
- where: application/draft-candidates.md:205-222 — reconciliation-map rows INV-143, 144, 146-150, 153-160, 162
- rule: kept "jurisdiction: texas per F1" as CI-086, 087, 038, 088, 089, 090, 078, 079, 080, 081, 129, 130, 131, 091, 092. The contrast is rows 207, 213, 214 and 223, which fold Texas values into universal CIs. — source: 16 TAC §7.45, §7.460, §8.201, TUC §104.258
- class: c
- other states: see the per-domain findings below.
- fix: one pass over GBM canonical-invariants moving each into its universal parent (CI-038→a generic regulatory-surcharge CI; CI-078/079/080/081→CI-067/068/069/062; CI-129/130/131→CI-077/125; CI-090→CI-113; CI-091/092→CI-008; CI-088/089→CI-097/CI-111; CI-086/087→CI-044/CI-035-style) — size: M

### "Launch scope is Texas only"
- where: INVESTIGATION-BRIEF.md:28 — project description (doc marked historical/superseded at CONTEXT.md:44)
- rule: states Texas-only as the project scope, with no launch-vs-architecture distinction.
- class: c
- other states: n/a (a scope statement).
- fix: add a one-line pointer to the owner ruling, or leave it since the doc is historical. Low risk — size: S

### Tax engine: "build in-house for the Texas-only gas launch"
- where: TECH-STACK-DISCUSSION.md:5 and :106 — Decisions log row D
- rule: "Single-state Texas tax is a bounded, documented spec"; "Gas Utility Tax is a small population-bracket variant"; situsing "nearly free for a defined-territory utility". Multi-state is a later hybrid seam. — source: knowledge/31-texas-regulatory-compliance.md
- class: b
- other states: the seam is sound. The risk is that in-house tax and assessment tables get shaped around Texas instruments (population-bracket GUT, city franchise %, PSF). Other states' regulatory assessments and municipal utility taxes use other bases (per-therm, flat per-customer, tiered). A guess for OK/LA/NM specifics.
- fix: amend the row to say the in-house tables are keyed by jurisdiction and service type from day one, and that "Texas-only" describes the launch, not the table shape — size: S

### A-2 framed as "the 16 TAC §7.45 limits on backbilling"
- where: CONTEXT.md:33 — "In flight" paragraph
- rule: the next patch (`v5.4.2-13-backbilling-caps.sql`) is described as implementing a Texas section, to R-32…R-39.
- class: c
- other states: the backbilling cap and meter-error window vary: NY 24 months, CA 3 months (DC:1311 cites them); TX has 6 months for meter error and a separate 12-month general cap (DC:1915). Gas vs electric/water differ.
- fix: re-describe A-2 as a per-jurisdiction backbilling-cap mechanism (CI-008). The window lengths, the "last test" prong and the 3-month non-registering rule become rows keyed by state and service type, dated, following `meter_accuracy_thresholds`. Texas is the first row — size: S (doc) / L (patch)

### Guiding principles omit "rules are per-jurisdiction data"
- where: CONTEXT.md:74-84 — Guiding Principles
- rule: "Every rate, rider, factor, and rule is date-effective" (:81). Nothing says statutory rules are held per jurisdiction and service type. ":84 Gas-native first — … cold-weather rules … first-class features" invites cold-weather (EWE) rules as built-in features.
- class: b
- other states: n/a (a missing principle).
- fix: add the owner ruling as a guiding principle: a statute or tariff rule is dated data keyed by state (and sub-state place) and service type, and code is a mechanism that reads it. Re-word :84 so "cold-weather rules" are data-driven — size: S

### "the Texas Pipeline Safety Fee" as a delivered capability
- where: CONTEXT.md:29 — "What the patches delivered"
- rule: the capability is named after the Texas statute, not "regulatory cost-recovery surcharges". This mirrors the schema's `surcharge_kind = 'pipeline_safety_fee'` (see Theme 3).
- class: c
- other states: other states' pipeline-safety or regulatory-assessment recovery riders have different caps and exemptions, or none (a guess). Electric and water have their own assessment riders.
- fix: rename in doc to the generic mechanism, with Texas PSF as a seeded rule row — size: S

---

## Theme 2 — Deposits (AC-24, AC-25, DL 2026-08-28 A-21)

### Deposit basis enum carries a Texas statutory basis
- where: application/APPLICATION-CONTRACTS.md:241 — AC-24; DL:274-275 — D-2026-08-28-40
- rule: `basis` ∈ credit_evaluation | adequate_assurance_366 | additional_trigger | tariff (| legacy_unknown). A "§7.45-basis deposit" is refused while a waiver is in force. "Rank 0 vs rank 5 (federal permission vs state mandate)". — source: 16 TAC §7.45; 11 USC §366
- class: c
- other states: the §366 federal basis is universal. The "§7.45 basis" is Texas's deposit rule. Another state's deposit statute has different triggers and waivers, and the enum and waiver-refusal logic cannot name it.
- fix: the basis should reference a per-jurisdiction deposit-rule row (state, service_type, effective dates, citation), not a Texas section. The waiver refusal reads "waivers recognised by the governing rule" — size: M

### 1/6-annual-billing cap applies to "a Texas residential cash §7.45 deposit"
- where: APPLICATION-CONTRACTS.md:241 — AC-24; DL:277-278 — D-2026-08-28-41
- rule: `cap_amount` = 1/6 of estimated annual billing, required on Texas residential cash deposits; `principal ≤ cap_amount` is a CHECK. The derivation is left to the app. — source: 16 TAC §7.45 (CI-129)
- class: c
- other states: DC:1067 notes the common alternatives, "2× average monthly bill or 1/6 of annual billing". Some states cap at the highest two months' bills (a guess, e.g. OK/LA). Non-residential rules differ. The predicate "required for Texas residential cash" is state law in structure.
- fix: a platform table `deposit_cap_rules(state_code, service_type, customer_class, instrument, formula_kind, fraction/multiplier, effective_from/to, source_note)` with a lookup that raises. The cap requirement is driven by the row, not the basis — size: M

### Waiver classes: family violence with TCFV reference; 65+; good-payment history
- where: APPLICATION-CONTRACTS.md:241 — AC-24 ("family_violence_certified needs the TCFV reference"); draft-candidates.md:1870 — INV-156
- rule: the waiver determination types and their evidence requirement are Texas's (Texas Council on Family Violence). — source: 16 TAC §7.45
- class: c
- other states: other states recognise other waiver classes, such as low-income program enrollees, medical, or guarantor; the certifying bodies differ; some have no 65+ waiver (a guess per state).
- fix: waiver types and evidence requirements become per-jurisdiction rows (type, evidence kind, certifying body, effective dates) — size: M

### Interest 30/31-day cliff hardcoded
- where: APPLICATION-CONTRACTS.md:241 — AC-24 (`interest_accrued` "only once `effective_on − posted_on ≥ 31` and never on a deposit exhausted within 30 days"); DL:268-272 — D-2026-08-28-38/-39; draft-candidates.md:1880 — INV-157
- rule: no interest if held ≤ 30 days; retroactive to posting once > 30 days. — source: 16 TAC §7.45 (CI-130)
- class: c
- other states: many states accrue from the day of deposit with no grace, credit annually at a set date, or require no interest on some classes (guesses). Water and electric in Texas fall under PUCT rules, not RRC rules.
- fix: the grace days, retroactivity flag and credit cadence become columns of a per-jurisdiction deposit-interest rule row; the accrual guards read them — size: M

### Deposit interest rate held per tenant
- where: APPLICATION-CONTRACTS.md:246 — AC-25 ("`deposit_interest_rates` is per tenant … a new PUCT rate is a new row")
- rule: a statewide, regulator-set annual rate is re-entered by every tenant. — source: PUCT annual rate (Tex. Util. Code)
- class: b
- other states: every state sets its own rate, or a formula such as a Treasury-yield reference. It is statewide, not per utility. Tenant-keying invites divergence and typos.
- fix: a platform `deposit_interest_rates(state_code, service_type, effective_from/to, annual_rate, source_note)` with EXCLUDE and a raising lookup (the `meter_accuracy_thresholds` model). Keep a tenant override only where a tariff sets a higher rate — size: M

### Refund trigger: twelve clean bills / ≤ 2 delinquencies
- where: APPLICATION-CONTRACTS.md:246 — AC-25 (`deposits_refund_due`, `deposit_refund_trigger_state()`); DL:284 — D-2026-08-28-43; draft-candidates.md:1890 — INV-158
- rule: mandatory refund after 12 consecutive bills, ≤ 2 delinquencies and not currently delinquent, or on inactive/final/closed. — source: 16 TAC §7.45 (CI-131)
- class: c
- other states: refund timing differs by state (for example, 12 vs 24 months of good payment, or at utility discretion — guesses). The counts are constants in a function.
- fix: N bills, M delinquencies and the "currently not delinquent" flag become per-jurisdiction rule columns read by the function — size: M

### Doc grades the Texas statute-in-structure as the achievement
- where: application/DECISION-LOG.md:290 — "CI-130 → `structurally-enforced` (every rule of the Texas accrual/refund discipline is a refusal)"
- rule: records Texas deposit law implemented as refusals as the target state.
- class: c
- other states: n/a (a framing statement).
- fix: add a dated correction: "structurally enforced *against the jurisdiction's rule rows*" is the target, and the current grade is Texas-only — size: S

---

## Theme 3 — Regulatory surcharges (PSF, AC-26…29, DL A-7)

### `surcharge_kind = 'pipeline_safety_fee'` with forced attributes
- where: APPLICATION-CONTRACTS.md:253 — AC-26; DL:212-213 — D-2026-08-31-02
- rule: the kind `pipeline_safety_fee` requires `cap_per_service`, `excluded_from_tax_bases = true`, `exempts_state_agencies = true`, and a gas/all-service rider. The cap is a configured amount, not a literal ("never a literal in a CHECK"). — source: 16 TAC §8.201 (CI-038)
- class: c (the kind and its forced attributes); the cap amount is b (per tenant)
- other states: another state's pipeline-safety or regulatory-assessment rider may be taxable, may not exempt state agencies, may be per-therm rather than per service, may be annual or monthly (a guess), and electric/water assessment riders exist. The kind couples Texas's attribute bundle to a name.
- fix: a generic surcharge rule whose exemption, tax-exclusion and cap attributes come from a per-jurisdiction assessment-rule row (state, service type, dates, citation). `pipeline_safety_fee` becomes a seeded TX row, not an enum member with hardwired implications — size: M

### One open PSF rule per tenant per bill date
- where: DL:231 — D-2026-08-31-08; APPLICATION-CONTRACTS.md:253 — AC-26
- rule: "the fee is one assessment per tenant."
- class: c
- other states: a tenant serving two states, or gas plus water, would have two assessments on the same date. This assumes one regulator per tenant.
- fix: uniqueness per (tenant, jurisdiction, service_type, assessment kind) — size: S

### "Per service = per meter"
- where: DL:216 — D-2026-08-31-03
- rule: the §8.201 "per service" is interpreted as per meter and baked into the cap sum and mutex.
- class: b
- other states: other assessments are per customer, per premise, or volumetric (a guess).
- fix: a `cap_unit` (per meter / per premise / per account / per volume) on the jurisdiction rule — size: S

### State-agency exemption attribute, day boundary pinned to America/Chicago
- where: DL:218-219 — D-2026-08-31-04; APPLICATION-CONTRACTS.md:258 — AC-27
- rule: `customers.is_state_agency` (CHECK: government only), evaluated at period end "day boundary pinned to America/Chicago". — source: §8.201 exemption
- class: c
- other states: "state agency" means the agency of *which* state; other states exempt different classes or none. **America/Chicago is wrong even inside Texas** (El Paso and Hudspeth counties are Mountain time), and wrong for any other-time-zone state.
- fix: the exempt customer class comes from the assessment rule row. The time zone is per tenant or territory (CI-010, DC:1319-1327 already requires "explicit per tenant/territory") — size: S (tz) / M (exemption)

### §8.201 compliance report view
- where: APPLICATION-CONTRACTS.md:263 — AC-28 (`regulatory_surcharge_billing_summary` is "the billed side of the §8.201 compliance report … amounts paid to RRC"); DL:183
- rule: the reporting view is described as Texas's report to RRC.
- class: b
- other states: other regulators have different report periods and fields.
- fix: describe it as a generic assessment billing summary grouped by jurisdiction rule; the report format is per-jurisdiction — size: S

---

## Theme 4 — Reads and estimation

### Consecutive-estimate cap: tenant setting default 3; the Texas ceiling is not a bound
- where: APPLICATION-CONTRACTS.md:224 — AC-21 (`tenants.settings.estimation.max_consecutive_estimates` default 3); DL:349 — "Tenant cap above the Texas 6-month ceiling is not bounded"
- rule: the statutory ceiling is not held anywhere; the tenant value is unbounded, and the default 3 is not Texas's rule (Texas is "actual read at least every 6 months"). — source: 16 TAC §7.45 (CI-090, CI-113)
- class: b
- other states: S1R:213 has them: PA §56.14 is 4 consecutive, MO is 3, NY HEFPA is 4 months. Some rules count reads and some count time.
- fix: a per-jurisdiction estimation ceiling (count and/or months, by service type, dated). Tenant value ≤ jurisdiction ceiling, checked — size: M

### CI-090 "Texas — Actual Read Cadence" as its own invariant
- where: application/draft-candidates.md:1799-1807 — INV-149; map row :211
- rule: an actual read every 6 months, a self-read postcard after 2 inaccessible months, estimated bills marked.
- class: c
- other states: as above. The recon's Q3 (S1R:213) already framed this correctly as per-jurisdiction.
- fix: fold into CI-113 as boundary values — size: S

---

## Theme 5 — Meter tests and backbilling

### Meter accuracy threshold per state and service type (the model)
- where: DL:19 — D-2026-09-23-02; APPLICATION-CONTRACTS.md:312 — AC-33 (location "in the same state")
- rule: `meter_accuracy_thresholds` is platform-fixed, date-effective, keyed by state and service type; Texas's 2.0% is a row. — source: F-3
- class: a
- other states: expressible.
- fix: none — size: S

### R-36 supervisor gate: "(anchor − 6 months) < cutover"
- where: DL:22-25 — D-2026-09-23-03/-04
- rule: the gate lapses six months after cutover because A-2's window is six months. The constant is the Texas meter-error look-back. — source: R-36, 16 TAC §7.45
- class: c
- other states: with a 24-month (NY) or 3-month (CA) window (DC:1311), the gate length must follow that jurisdiction's window.
- fix: the gate reads the same per-jurisdiction backbilling-window row A-2 will use — size: S (once A-2 has the table)

### CI-091 / CI-092: Texas meter-test fee and meter-error rebill bounds
- where: application/draft-candidates.md:1898-1915 — INV-159, INV-160; map rows :221-222
- rule: a free test if none in 4 years, otherwise ≤ $15; a refund if > 2.0%; rebill for the shorter of 6 months or since the last test; 3 months for non-registering meters. — source: 16 TAC §7.45
- class: c
- other states: fee caps, free-test intervals and rebill windows vary by state and by commodity (water meters are often a different %).
- fix: fold into CI-008 (per jurisdiction) plus a test-fee rule table (state, service type, free interval, fee cap, dated) — size: M

### CI-008 "Backbilling Cap Per Jurisdiction" (good framing)
- where: application/draft-candidates.md:1309-1317 — INV-101; map row :71
- rule: "The cap is configured per jurisdiction" (NY 24 months, CA 3 months).
- class: a
- other states: expressible.
- fix: none. A-2 should implement *this* (see CONTEXT.md:33) — size: S

---

## Theme 6 — Collections and disconnection

### CI-067 disconnect eligibility against the jurisdiction's rule set (good framing)
- where: application/draft-candidates.md:252-261 — INV-001; map row :75
- rule: eligibility is evaluated "against the customer's jurisdiction-specific rule set".
- class: a
- fix: none — size: S

### Texas-only CIs: carve-outs, closed-day, EWE, medical hold
- where: application/draft-candidates.md:1809-1817, 1927-1935 (INV-150/162 → CI-078); :1839-1846 (INV-153 → CI-079); :1848-1856 (INV-154 → CI-080); :1858-1866 (INV-155 → CI-081); map rows :212, 215-217, 224
- rule: a closed list of six non-disconnect grounds; no disconnect on or before a day the utility is closed; EWE = prior-day high ≤ 32°F and forecast ≤ 32°F from the nearest NWS station; medical hold of 20 days plus a mandatory installment agreement. — source: 16 TAC §7.45, §7.460; TUC §104.258
- class: c
- other states: winter protection is often a date-range moratorium (e.g., Nov–Mar) rather than a temperature predicate, or uses different thresholds (Kansas's Cold Weather Rule is a 35°F forecast — from memory, verify). Medical holds are commonly 30 days, renewable (DC:908). The carve-out grounds differ by state.
- fix: fold into CI-067/068/069/062 as rule rows: protection type (temperature / date-window / closed-day), thresholds, durations, and a carve-out ground list per jurisdiction, dated — size: L

### Folded correctly: 15+5+5 disconnect sequence, dispute cap
- where: application/draft-candidates.md:213-214 — map rows INV-151 → CI-074, INV-152 → CI-068
- rule: "folded as configurable boundary value … The sequence values are Texas-specific; the step-completeness discipline is universal."
- class: a
- fix: none. This is the pattern to copy — size: S

### Texas disconnect-bypass program set as the launch list
- where: application/session-1-recon.md:233-244 — Q6
- rule: asks whether LIHEAP pledge, medical, EWE, DPA and family violence are "the full launch set" of Texas bypass programs.
- class: b
- other states: PIPP-type programs (OH/PA) and AMP (MA/PA, S1R:248) are real elsewhere.
- fix: frame the question as which rows Texas seeds in a per-jurisdiction bypass table — size: S

---

## Theme 7 — Rates, franchise, jurisdiction shape

### Incorporated vs Environs flag (CI-086)
- where: application/draft-candidates.md:1740-1749 — INV-143; map row :205 ("Inc/Env flag is Texas-statutory")
- rule: every account is flagged Incorporated (the city has original rate jurisdiction) or Environs (RRC has it); tariff lookup, rate-change workflow and franchise fees key on it. — source: Texas Utilities Code
- class: c
- other states: most states have one PUC with statewide original jurisdiction; some have municipal-utility exemptions; some have county-level franchises. A two-value flag cannot express "which rate authority governs this premise" elsewhere.
- fix: premise → a dated `rate_jurisdiction` / regulator assignment (FK to a jurisdictions table with state, place and authority). Inc/Env are Texas rows — size: M

### schema.sql shapes: inside_city_limits boolean, franchise_city text, single tenant state
- where: application/database/schema.sql:312-313 (`service_locations.inside_city_limits BOOLEAN DEFAULT TRUE`, `franchise_city TEXT`); :707-708 (`rate_schedules.franchise_city`, `regulatory_authority TEXT`); :29 (`tenants.state`, a single address field; no operating jurisdictions)
- rule: a Texas-style city/environs split and a city-negotiated franchise are baked into columns; the regulator is free text.
- class: b
- other states: franchise fees on county or special-district bases; utilities spanning two states (a tenant needs more than one jurisdiction).
- fix: this file is stale (CONTEXT.md:41). Mark it as not a design reference for jurisdiction; tu.sql's `jurisdictions` table (DL:485, 566) should carry state, place and authority — size: S

### Franchise fee rules keyed by tenant + city_name
- where: application/database/schema.sql:832-849 — `franchise_fee_rules` UNIQUE (tenant_id, city_name, effective_date); applies_to DEFAULT 'total_bill'
- rule: a franchise is per city, as a free-text name.
- class: b
- other states: county franchises, special districts, gross-receipts taxes levied by the state and passed through.
- fix: FK to a jurisdiction, not a city name — size: S

### CI-044 franchise fee traceable to jurisdiction (good framing)
- where: application/draft-candidates.md:274-283 — INV-003; map row :77
- class: a
- fix: none — size: S

### CI-087 Texas SOI + 35-day waiting period
- where: application/draft-candidates.md:1751-1759 — INV-144; map row :206
- rule: a rate increase needs a Statement of Intent, 4 weeks of newspaper notice and 35 days before activation.
- class: c
- other states: other PUCs use different filing and notice regimes, and municipal or co-op boards use a resolution (CI-132 posture).
- fix: a per-jurisdiction and per-posture rate-change workflow rule (notice weeks, waiting days) — size: M

### PGA cadence and BTU reference conditions folded as values (good)
- where: application/draft-candidates.md:207 (INV-145 → CI-035), :223 (INV-161 → CI-021)
- class: a
- fix: none — size: S

### WNA defaults: active months Nov–Apr, per_mcf
- where: application/database/schema.sql:862 (`wna_zones.active_months DEFAULT '{11,12,1,2,3,4}'`), :887 (`adjustment_unit DEFAULT 'per_mcf'`)
- rule: a seasonal window and unit DEFAULT in structure (tenant data, but with a Texas-style default).
- class: b
- other states: WNA windows and units are tariff-specific (the recon cites PA and WV deadbands, S1R:209). Some tariffs use Ccf or therms.
- fix: no default; required from the tariff row — size: S

### "a correction run — the RRC default"
- where: APPLICATION-CONTRACTS.md:177 — AC-15
- rule: the default correction rate mode is attributed to the Texas regulator.
- class: b
- other states: other regulators may require current rates on a rebill, or mandate one mode.
- fix: the correction-rate-mode default comes from a per-jurisdiction rule; the doc should say "the jurisdiction's default (TX: historical-period world)" — size: S

### Tax-exemption categories and certificate-required per tenant
- where: APPLICATION-CONTRACTS.md:273-275 — AC-30; DL:157 — D-2026-09-04-03 (citing Rule 3.287, the Texas Comptroller rule)
- rule: exemption_type is a closed domain (with `industrial` removed at R-13); certificate-required defaults TRUE per tenant because Texas puts the liability on the seller.
- class: b
- other states: exempt categories and certificate rules are state tax law, not the utility's choice. Other states' resale and manufacturing exemptions differ.
- fix: categories and certificate requirements per (state, tax type) as platform data; the tenant flag is only an override where the law allows — size: M

### Principle: no uncitable seeded number (good)
- where: DL:168-169 — D-2026-09-04-07
- rule: "a number nobody can cite, in a compliance table" is refused.
- class: a
- fix: none. Extend it to "and no citable number outside a jurisdiction-keyed row" — size: S

---

## Theme 8 — Notices and bill format

### CI-088 / CI-089: Texas bilingual notices and bill format
- where: application/draft-candidates.md:1780-1797 — INV-147, INV-148; map rows :209-210
- rule: English and Spanish on disconnect, new-customer and annual notices; a fixed list of mandatory bill elements. — source: 16 TAC §7.45
- class: c
- other states: language sets and bill elements vary (S1R:250-252 even asks about county-level language). The universal parents already exist: CI-097 (DC:181, "per-jurisdiction language-set is … config") and CI-111 (DC:176, "which line items are display-mandated is jurisdiction-configurable"). Those are class a.
- fix: fold into CI-097/CI-111 as per-jurisdiction rows — size: S

---

## Theme 9 — Other correctly-framed items (class a)

### F2 configurable-boundary folds in the reconciliation map
- where: application/draft-candidates.md:80 (UAF cap: "jurisdiction-configurable (Texas, WV, NY, CA differ)"), :113 (deposit interest "Rate/basis/schedule jurisdiction-prescribed configurable"), :115 (estimate cap "jurisdiction-prescribed"), :116, :132 (medical hold "state-statutory configurable"), :148, :160 (retention "7-year U.S. default"), :184 (payment effective-date method per jurisdiction)
- class: a
- fix: none on the doc. Note that the schema did not follow these for deposits (Theme 2) — size: S

### CI-132: regulatory posture is a first-class tenant attribute, "never hard-coded"
- where: application/draft-candidates.md:78, :285-296 — INV-004
- class: a
- fix: none — size: S

---

## Texas-specific terms presented as universal

| term | where | why it is Texas |
|---|---|---|
| Incorporated / Environs | DC:1742; schema.sql:312 `inside_city_limits` | the RRC vs. municipal original-jurisdiction split |
| Pipeline Safety Fee / `pipeline_safety_fee` | CONTEXT.md:29; AC:253 | 16 TAC §8.201 |
| state agency / `is_state_agency` | AC:258; DL:218 | the §8.201 exemption class |
| EWE (Extreme Weather Emergency) | DC:1850 | 16 TAC §7.460 term and predicate |
| §7.45-basis deposit | AC:241; DL:274 | a Texas section as an enum-like basis |
| TCFV reference | AC:241 | Texas Council on Family Violence |
| "twelve clean bills" | AC:246; DL:284 | the §7.45 refund trigger |
| PUCT rate | AC:246 | the Texas deposit-interest rate setter |
| "RRC default" | AC:177 | the Texas regulator named as the system default |
| SOI (Statement of Intent) | DC:1753 | Texas rate-change filing |
| Gas Utility Tax (population bracket) | TECH-STACK:106 | a Texas tax |
| Rule 3.287 | DL:157 | the Texas Comptroller exemption rule |
| America/Chicago | DL:218 | Texas Central time as the day boundary (and wrong for El Paso) |
| "per service" = per meter | DL:216 | a reading of §8.201 |

---

Findings by class: **a = 9, b = 13, c = 21** (43 findings; the PSF-kind entry counts as c, and its per-tenant cap part is b).
