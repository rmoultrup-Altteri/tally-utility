# 08 — gas-billing-memory `application/` docs: Kyle's rulings, the CI register, configurable-rules

Scope: `~/code/gas-billing-memory/application/` at `091c990` (equal to `origin/main` per `git ls-remote`; not fetched, nothing modified). All paths below are relative to that `application/` directory unless they start with `configurable-rules/` or `test-fixtures/`.

## Summary

- **Most of Kyle's rulings are phrased as readings of 16 TAC §7.45/§7.460, with the Texas number inside the ruling.** About a third carry a general principle that transfers to other states: R-19 cause-is-evidence, R-25 per-period direction test, R-26 most-specific-wins, R-29/R-30 "the determination records what resolved it", R-33 "a bill computed wrong ≠ a meter that measured wrong", CCK-2/3/13 fail-toward-protection. The rest are Texas clauses: 3 months, 6 months, 2.0%, 1/6, 12 bills, day 31, 32°F, 5 working days, 20 days, 35 days, $15, 4 years.
- **Nothing in these docs describes a platform-held, state-keyed rule table.** Every rule table that exists or was designed is keyed by tenant: A-2 `backbilling_cap_rules` (R-26), `tenant_regulatory_class_rules` (CCK-9), `regulatory_surcharge_rules` (A-7), `franchise_fee_rules`, `deposit_interest_rates` (A-21) and `jurisdictions`. R-26's "NULL jurisdiction = state default" row is also per tenant, so every Texas tenant re-seeds Texas law. The only state-level sketch is a **test fixture** (`test-fixtures/jurisdictions.md` FIX-JUR-001). The only per-jurisdiction + service-type ruling is F-3 (2.0% meter threshold). Per the brief, that ruling became `meter_accuracy_thresholds`.
- **The CI register tags 14 entries `jurisdiction: texas`** (CI-038, 078–081, 086–092, 129–131). Each says its Texas constant is "statutory, not configurable", which invites building it as code. The ~25 "multi-jurisdiction" entries state the principle correctly but embed Texas values as the example. Some of those examples are stale: CI-008 and CI-092 still cite a "12-month Texas cap", and CI-049 says "Texas applies oldest-first".
- **configurable-rules/ is a four-layer documentation model, not a data model.** The layers are the catalog, DMN-style decision tables, workflows and scenarios. In it, jurisdiction is a "parametric overlay" with no substrate. Rule F-CC-4 limits regulatory content to "Texas-launch depth only" and defers multi-state variation to Layer-4 test expansion. Decision tables write Texas values straight into rule rows and have no state input: inputs are "Texas at launch", `service_state = TX`, and a jurisdiction enum of "Texas (in-city/environs)". The intended `jurisdiction_rules` substrate (A-14) was never designed. The layers are bi-temporal by file header but are neither per-state nor per-tenant.
- **Explicit Texas-only architecture statements** appear in `configurable-rules-scenario-strategy.md:19`, `cluster-and-workflow-inventory.md:43`, `configuration-catalog.md:36/1092`, `configurable-rules/session-1-recon.md:99`, `test-fixture-catalog-strategy.md:19/64/235/336` and `decision-tables/gas-conversion-and-energy.md:14`. Each claims the model "absorbs other states without restructuring". The decision tables contradict that claim.
- **A recurring structural shortcut uses service type as a stand-in for the Texas regulator.** "Gas ⇒ RRC ⇒ no de minimis, no void-only, historical rate mode" appears in DE-3, D-8 and R-17. "Gas is never PUC" appears in DE-8..11 and FIX-JUR. Both are true only in Texas.

---

## Part A — Inventory of statutory/tariff rulings (the list that must become per-jurisdiction data)

Phrasing: **TX** = the ruling states a Texas clause and its value as the rule. **P** = general principle, Texas only an instance. **P+TX** = general mechanism with the Texas constant written in.
Held now: **doc** = design doc only, not built. **tenant row** = tenant-keyed data. **code** = platform-fixed function, trigger or CHECK. **fixture** = test fixture.
Should be held: **J** = platform row keyed `(state[, sub-state place], service_type[, class][, cause])`, effective-dated, with a citation. **T** = tenant tariff row, bounded by J. **G** = general code reading J.

| Code | Ruling (short) | Phrased | Held now → should be |
|---|---|---|---|
| T-4 (wu5-wu6:36) | WNA floor/ceiling clamp, tenant-configurable | P | tenant → T (tariff) ✓ |
| D4-1 (wu5-wu6:61-63) | PSF = rate-page item; §8.201 "never bill before remitting", $0.50/service cap | TX | `regulatory_surcharge_rules` tenant row, `cap_per_service` → J (cap) + T (factor) |
| D5-1 (:66) | WNA monthly-settled, no deferred balance | P (tariff-derived) | G ✓ |
| D5-2 (:67-69) | WNA applicability is a jurisdiction property | P | tenant `jurisdictions.wna_*` → T keyed to shared place |
| D6-1 (:73) | Franchise-fee reference date = period end, tenant-overridable per jurisdiction | P | tenant → T ✓ |
| Fam-9 FV (:86) | Family violence = deposit waiver only (§7.45(5)(C)), not a disconnect bypass | TX | doc / A-21 waiver enum → J (waiver-kind × protection-kind rows) |
| Fam-9 EWE (:87) | EWE self-executing, ≤32°F prior-day high + ≤32°F forecast, county NWS station, cold-only | TX | doc / decision table → J (moratorium predicate rows) |
| D9-2 (:89) | Medical hold + broken IA share one grace window | P | G ✓ |
| Fam-10 (:92) | No Texas overlay on §366; federal 20/30 days | P (federal) | G/federal J row ✓ |
| D11-1 (:95) | Missed newspaper week ⇒ full reset of the 4-week run + 35-day clock | TX | doc → J (SOI notice rule) |
| Q-8 (:96; CI 2430) | Bilingual = statewide EN/ES, per-tenant exemption flag, **no county table** | TX | doc; "two-language enum" design → J (required languages per state/sub-state) |
| D11-2 (:97) | Estimated-read invoice ⇒ estimated-bill template | P | G ✓ |
| D14-1 (:106) | Consecutive-estimate counter per meter, validated-actual reset | P | G ✓ (cap value → J) |
| D3D-1 (:140) | PGA deferred-balance bands 10%/20% (starter defaults, "no RRC number") | P | tenant ✓ |
| D-4 (08-18:345) | Extend read whitelist to `void_released`; "RRC exposure: gas requires full correction, no de minimis" | P+TX | code → G + J (correction-completeness rule) |
| D-8 note (08-18:504) | `void_only_unbilled_disposition` ignored for **gas**; void-only on gas only for duplicate / wrong-customer | TX keyed as service type | code/COMMENT on service_type → J |
| DE-1 (de-review:21-35) | payment_terms floor 15 days; estimate ceiling = 6-month read cadence | TX | doc → J |
| DE-2 (:40) | No Texas posting-order mandate | P | tenant ✓ |
| DE-3 (:57-72) | Gas: no void-only except 2 cases, no $ threshold, `correction_rate_mode=current` forbidden for gas | TX keyed as service type | planned "gas" CHECK → J |
| DE backbill (:163-173) | per-cause cap table (per-jurisdiction × cause) | P+TX | → J |
| DE deposit (:154-162) | 1/6 cap residential-framed; FV mandatory; **65+ waiver tariff-by-tariff** | TX | A-21 → J (+T for 65+) |
| DE escheat (:252-261, action 16) | Per-property-type dormancy (deposits §72.1017; credits 3 y §72.101) | TX | matview hardcode → J |
| DE collections (:273-290) | 5 working days past delinquency; notice ≥5 working days, mail/hand; elderly day-26 | TX | doc → J |
| DE timeliness (:302-315) | Texas timeliness = postmark/sent date | TX | doc → J |
| DE retention (:302-315) | 7-year bill-image retention | TX practice | doc → J |
| DE franchise (:328-358, action 28) | §182.025 2% gross-receipts ceiling on city street-use charges | TX | doc (validate `fee_percentage`) → J |
| DE-8..11 corr. (de-review-answers-8-11:26-44) | "Gas is RRC/municipal, never PUC" (naming directive); gas medical = §7.45 seriously-ill | TX | naming → J (regulator per state×service) |
| R-3/R-6 (coda-4-7:113-172) | E-SIGN consent: portal / email_confirmed only | P (federal) | G ✓ |
| R-4/R-7 (:180-219) | HMAC-only ID number (justified by Tex. Bus. & Com. §521); per-tenant lookup | P (TX law as rationale) | G ✓ |
| §5.1 notice (:229-243) | `shutoff_notice_sent` requires `mail`/`hand_delivery` (§7.45) — CHECK | TX | designed CHECK → J |
| R-12 (a1:83-95) | Tax exemption default `pending_verification`, verified_by/at on active (Comptroller 3.287) | P | G ✓ |
| R-13 (a1:97-117) | `industrial` removed from exemption_type; residential §151.317 derived; predominant-use deferred | TX | CHECK → J (exemption bases per state) |
| R-15 (a1:130-148) | Two-axis as-of; "correction run (historical rates, RRC default)" | P+TX | G ✓ / default → J |
| R-17 (a1:164-176) | service_type correction on billed schedule ⇒ review item; "for gas under RRC no de minimis" | P+TX | G + J |
| R-18 (a1:178-193) | Sewer ↔ water at meter level; irrigation/deduct deferred to water launch | P | G ✓ |
| R-19 (a2:84-95) | `backbill_cause` findings-based; `anchor_date` | P | G ✓ |
| R-20 (a2:99-119) | two bounds; `enforceable_scope` uncapped/months/never; **Texas seed table** | P+TX | tenant cap rows → J |
| R-21 (a2:123-133) | estimation_catchup billable uncapped; "keeps per-jurisdiction slot for states that do cap" | P+TX | → J ✓ intent |
| R-22 (a2:137-143) | gate at setup + invoice creation; two failure directions | P | G ✓ |
| R-23 (a2:147-157) | trim not reject; §7.45(6)(B)(v) per-unit adjustment, (6)(B)(viii) estimated marking | P+TX | G + J (bill-content rules) |
| R-24/R-31 (a2:161-169, 326-344) | Meter test history required before first gas go-live; §7.45(7)(B)(i)/(ii) field list | TX | `meter_tests` → G (field set could be J) |
| R-25 (a2:177-195) | per-period direction test; favourable periods uncapped | P | G ✓ |
| R-26 (a2:199-229) | cap key `(tenant, jurisdiction NULL=state default, service_type, class, cause)`; 2 levels | P+TX | **tenant rows** → J (+T/municipal override) |
| R-27 (a2:233-253) | under-reach warning, meter_error only (only mandatory bound in TX) | P+TX | → G reading J's `mandatory` flag |
| R-28 (a2:259-267) | (4)(E)(vi) closing clause → counsel; never a tenant toggle | TX | doc ✓ (J if reversed) |
| R-29 (a2:271-283) | `anchor_basis` recorded, **hard-coded `test_date` in v1** | P+TX | code constant → J (anchor basis per state rule) |
| R-30 (a2:287-320) | (4)(E)(vii) three-bucket mapping of access_status/estimation_reason; **platform-fixed, never tenant** | TX | code mapping → J |
| R-32 (09-22:81-132) | straddling adverse period forfeited whole (no estimation authority in (v)(I)) | TX | code → J (`period_divisible` flag) |
| R-33 (09-22:136-187) | meter-error correction = adjustment on next bill, not void/rebill | P + TX grounds | G ✓ (delivery path per cause → J if states differ) |
| R-34 (09-22:191-233) | "last test" = most recent completed test before discovery, any outcome | TX (reading) | `meter_governing_test()` → G + J (anchor rule) |
| R-35 (09-22:237-288) | accept partial test history; never back-fill; absence falls to 6-month cap | P+TX | G ✓ |
| R-36 (09-22:292-340) | date-only migrated test anchors; supervisor gate lapses at cutover + **6 months** | P+TX | constant → read from J cap |
| F-1 (09-22:349) | meter-error backbills non-disconnectable (§7.45(4)(E)(vi)) except tampering | TX | flag → derived from J `enforceable_scope` |
| F-3 (09-22:363-372) | 2.0% threshold "keyed by service type as well as jurisdiction"; test-fee refund | TX value, **J-shaped ruling** | → J ✓ (`meter_accuracy_thresholds`) |
| F-4 (09-22:374) | non-registering (v)(II) 3 months, permissive, estimation authorised | TX | → J |
| F-5 (09-22:383) | 4-year free-test look-back "same customer same location" | TX | → J |
| R-37 (09-23:63-214) | favourable window not overridable; `MAX(anchor−6mo, test, deployment)`; 2-code hold; (d) tenant adverse limit ≤ statutory | P+TX | 6-month literal → J; (d) → T ✓ |
| R-38 (09-23:218-284) | cause/anchor freeze at evidence-freeze; tamper move gated | P | G ✓ |
| R-39 (09-23:311-403) | 8-value cause domain; 3 new causes seeded TX gas `uncapped`/`never` | P (vocabulary) + TX seeds | CHECK + tenant seeds → vocabulary G, seeds J |
| OQ-1 (09-23:286-307; brief 09-23) | delivery path per cause | open | → J if states differ |
| CCK-1..3 (cck:64-89) | customer_type = rate applicability only; protection scope derived; resolver never touches rates | P | G ✓ |
| CCK-4..8 (cck:90-148) | volumetric hysteresis 3/3, per-meter, any-wins roll-up | P (tariff) | T ✓ |
| CCK-9/10 (cck:150-181) | `tenant_regulatory_class_rules (tenant, service_type)`, **no effective dating** | P | T (needs dating) |
| CCK-13/14 (cck:212-230) | insufficient history ⇒ protected; mode default `all_non_residential_protected` | TX scope (§7.45 = residential + small commercial) | tenant mode → J (which classes a state protects) + T |
| CCK-15/15b (cck15:113-174) | early promotion only on documentary basis; forward-only | P | G ✓ |
| CI-038 / A-7 | PSF $1.00 (or $0.50) cap, state-agency exempt, not taxable | TX | tenant rule rows + `customers.is_state_agency` → J |
| CI-078 | six disconnect-ineligible arrears grounds, "not configurable" | TX | engine config → J |
| CI-079 | no disconnect on / before closed day | TX | → J |
| CI-080 | EWE predicate "not configurable" | TX | → J |
| CI-081 | medical hold 20 days / 5 working days + IA companion | TX | → J |
| CI-068 | Texas 15+5+5 notice sequence | P+TX | → J (A-14) |
| CI-077 | deposit credit evaluation; "Texas caps at 1/6" | P+TX | → J |
| CI-086 | Inc/Env enum "Texas-statutory, not configurable" | TX | `inside_city_limits` bool → J place attributes |
| CI-087 | SOI + 4 weeks newspaper + 35 days | TX | → J (+ CI-132 posture) |
| CI-088 | EN/ES bilingual | TX | → J |
| CI-089 | bill-format element set "not LDC-configurable" | TX | → J |
| CI-090 | 6-month actual read; postcard after 2 months | TX | → J |
| CI-091 | $15 fee, 4-year free, >2.0% refund | TX | `meter_tests` (2.0% → J ✓), fee → J |
| CI-092 | 6-month / last-test / 3-month bounds | TX | → J (A-2) |
| CI-129/130/131 | 1/6 cap, waivers; 30-day interest cliff; 12 bills / ≤2 delinquent refund | TX | A-21 triggers/functions → J |
| CI-008/021/033/035/036/041/044/049/054/056/058/061/062/067/069/073/074/113/114/125/126 | multi-jurisdiction principles | P (+TX example) | principle G; values → J |

---

## Part B — Findings

### Theme 1 — Design statements that scope the architecture to Texas

### Configurable-rules strategy: "Launch scope: Texas only… v1 just doesn't exercise it"
- where: `configurable-rules-scenario-strategy.md:19`, repeated at `:122`, `:209`, `:608`; same note in `scenario-mapping-strategy.md:19`
- rule: the rule-model design limits the jurisdiction axis to "Texas sub-jurisdictional placement". It claims the four layers "support multi-state expansion without restructuring" — source: grilling decision #9 (`scenario-strategy-grilling-handoff.md:121-134`)
- class: b
- other states: the claim fails in practice. Layer-2 tables carry no state input (see Theme 9), so adding Oklahoma would mean rewriting every table's rule rows, not adding rows.
- fix: restate the scope as "Texas is the first seeded jurisdiction". Require every regulated decision table to take `(state, service_type)` as an input — size: S (doc), M (table rewrites)

### Parametric axis #1 is "Texas sub-jurisdictional placement", not jurisdiction
- where: `configurable-rules-scenario-strategy.md:606-608`; the sample table at `:299` has input `sub_jurisdiction` with domain "specific Texas city fixture ID / tx-environs / tx-special-rate-area"
- rule: the jurisdiction dimension is modelled as Texas Inc/Env/special-area only
- class: b
- other states: most states have no environs concept for gas. Rate authority is statewide PSC/PUC (guess: OK Corporation Commission, LA PSC, NM PRC), with municipal utilities exempt.
- fix: make the axis `(state, sub-state place kind)` with a per-state place-kind vocabulary — size: S

### Catalog convention F-CC-4: "Regulatory: Texas-launch depth only; multi-state deferred to Layer 4"
- where: `configurable-rules/configuration-catalog.md:36`; origin `configurable-rules/session-1-recon.md:99,123-124`
- rule: every "Regulatory constraints" field records only the Texas value. Variation is deferred to scenario (test) expansion rather than to the data model.
- class: b
- other states: the knobs that are `regulated` (deposit cap, payment terms floor, estimate ceiling, disconnect timing, etc.) have no slot for another state's value
- fix: re-scope "regulated" to mean "bounded by a per-jurisdiction row". Each regulated knob should name its J table and key — size: M

### "Jurisdiction level" is a doc-only overlay; the only schema hook is `inside_city_limits` + `franchise_city`
- where: `configurable-rules/configuration-catalog.md:1086-1104` (`jurisdiction-overlay (Texas launch)`)
- rule: "Texas regulatory ceilings … applied as the Texas-launch overlay"; "a `jurisdiction_rules` substrate (A-14) … pending"
- class: b
- other states: no home for any state's ceilings, so a second state is a code or doc fork
- fix: design the J substrate that A-14 names, platform-held and state-keyed, before the next regulated patch — size: L

### Cluster inventory scope guard: "Clusters are written to the Texas rule … multi-state is a Layer 4 axis (deferred)"
- where: `configurable-rules/cluster-and-workflow-inventory.md:43`
- rule: the failure-mode walk found MN/IL/OH/GA/NY backbilling caps and cold-weather windows, and these were deliberately excluded from cluster shape
- class: b
- other states: the named states' cold-weather rules are date-window or temperature variants (guess: MN Oct 15–Apr 15 Cold Weather Rule; IL Dec 1–Mar 31; KS/MO temperature thresholds). The Texas-only cluster shapes have no slot for them (see cold-weather finding).
- fix: re-open clusters 46–49 and 53–54 with a jurisdiction input — size: M

### Test-fixture strategy: "All tenants operate in Texas only at v1"; "States other than Texas … v2 concern"
- where: `test-fixture-catalog-strategy.md:19,64,235,336,485`; `test-fixtures/jurisdictions.md:14`
- rule: fixtures assume Texas only. There is one state-level fixture, FIX-JUR-001 TX-RRC, plus TX-ENVIRONS and TX-SPECIAL-RATE-AREA markers.
- class: b
- other states: no fixture can prove a rule is data-driven, because there is no second state to flip to
- fix: add one synthetic non-Texas state fixture (clearly marked fictional) so every J lookup has a two-state test — size: S

### Gas-conversion decision table: "Texas reference conditions (§7.4, fixed — not tenant-configurable within a Texas launch)"
- where: `configurable-rules/decision-tables/gas-conversion-and-energy.md:14`
- rule: 60°F / 14.65 psia / gross-real-dry — source: KB-31 §7.4. This contradicts CI-021 (`canonical-invariants.md:409`), which says reference conditions are "configured per jurisdiction".
- class: c (stated as fixed)
- other states: pressure base differs by state/tariff (14.73 psia is common outside Texas — guess from tariff norms)
- fix: J row `(state, service_type) → temperature_base, pressure_base, basis`, effective-dated — size: S

### Wave 2 labelled "Texas billing-correctness launch set"
- where: `schema-parity-plan.md:125` (A-20, A-21, A-7); `:41` "A-7: Texas Pipeline Safety Fee surcharge riders"
- rule: patch waves are framed as Texas deliverables, and their encodings followed that framing (see Themes 5–6)
- class: b
- other states: n/a (framing)
- fix: plan labels should read "first-jurisdiction seed". The PSF rider becomes a general statutory-surcharge rule whose Texas row is PSF — size: S

### "Gas is RRC/municipal, never PUC" as a naming directive
- where: `configurable-rules/de-review-answers-8-11.md:26-35`; echoed `test-fixtures/jurisdictions.md:19-24` and FIX-JUR-001 `regulator: … NOT PUC/PUCT (gas)`
- rule: "must be caught so 'PUC' doesn't get baked into config field names". A correct fact about Texas becomes a naming rule.
- class: b
- other states: gas **is** regulated by the state PUC/PSC almost everywhere else (guess: LA PSC, OK OCC, NM PRC)
- fix: name the regulator per `(state, service_type)` in J (`regulatory_authority` row). Never hard-name RRC or PUC in fields — size: S

### Commodity scope "gas only at launch" and sewer/water deferred
- where: `CONTEXT.md:46`; `wu5-wu6-kyle-decisions-2026-07-10.md:127` (D3B-3 sewer deferral); `kyle-decisions-2026-08-26-a1-bitemporal.md:191` (irrigation/deduct deferred)
- rule: the schema must support multiple commodities, but only gas ships
- class: a (the principle is correct: the schema stays multi-commodity)
- other states: n/a
- fix: none; keep service_type on every J key — size: —

### Theme 2 — Backbilling caps (A-2)

### Cap table held per tenant; the "state default" is a tenant row
- where: `kyle-decisions-2026-09-02-a2-backbilling-caps.md:203-210` (R-26); `a2-implementation-brief-2026-09-21.md:40,56,68`
- rule: key `(tenant_id, jurisdiction_id NULLABLE, service_type, class, cause)`, with "`jurisdiction_id` NULL = the state / filed-tariff default row. Texas gas §7.45 rows seeded as NULL-jurisdiction rows" — source: R-20, R-26
- class: b
- other states: the key has no `state_code`, so a tenant serving two states cannot hold two defaults. Every Texas tenant re-seeds and can edit §7.45 values. No effective dating is ruled.
- fix: split into (1) a platform J table `backbilling_cap_rules(state, service_type, class, cause, billable_*, enforceable_*, effective_from/to, source_note)`, (2) tenant T rows only for R-37(d) shorter tariff limits, and (3) tenant/municipal override rows per R-26 evidenced by ordinance. The lookup should raise when no row is in force — size: M

### Texas seed values in the ruling itself (R-20, R-39 seeds)
- where: `kyle-decisions-2026-09-02-a2-backbilling-caps.md:111-117`; `kyle-decisions-2026-09-23-a2-override-and-cause-freeze.md:363-367`
- rule: non_registering 3 mo from discovery / never; meter_error ≤6 mo or last test / never; rate_misapplication uncapped / 6 mo; estimation_catchup uncapped / conditional; tampering uncapped / uncapped; three new causes uncapped / never — source: §7.45(7)(B)(v), (4)(E)(v)-(vii), (4)(D)(v)
- class: b (data, but tenant-keyed; see above)
- other states: electric Texas §25.126 inverts tampering (6 mo) vs non-tamper (3 mo) (a2:64). The docs cite NY 24 mo and CA 3 mo (CI-008:199, feature-list:336). Unverified here.
- fix: seed as J rows with `source_note`, `state='TX'`, `service_type='gas'`, `class IN (residential, small_commercial)` — size: S

### `enforceable_scope` bars disconnection and refusal only (both §7.45 legs)
- where: `kyle-decisions-2026-09-02-a2-backbilling-caps.md:101-107` (R-20)
- rule: the enforceable-side protection is "disconnection AND refusal / re-establishment of service", per (4)(E)(v) and (3)(C)(iii)
- class: b
- other states: some states bar late fees or collection-agency referral on backbilled amounts (guess). The two-leg set is Texas's.
- fix: in J, make the protected actions a set column (`disconnect`, `refuse_service`, `late_fee`, …) rather than a fixed pair — size: S

### `anchor_basis` hard-coded to `test_date`
- where: `kyle-decisions-2026-09-02-a2-backbilling-caps.md:278-279` (R-29); `a2-implementation-brief-2026-09-21.md:76`
- rule: "Hard-coded to `test_date` in v1 — no operator choice, no tenant setting". Tenant configurability is deferred to "first tenant whose filed tariff specifies" otherwise.
- class: c
- other states: another state's rule may run from discovery or the last read (guess)
- fix: J row carries `anchor_basis` per cause. The tariff override stays T per R-29's trigger — size: S

### (4)(E)(vii) three-bucket mapping is platform-fixed
- where: `kyle-decisions-2026-09-02-a2-backbilling-caps.md:300,304-310` (R-30)
- rule: `access_status` / `estimation_reason` values map to beyond-control / within-control / determination-required. "Platform-fixed, never tenant-configurable. It is a reading of the rule." — source: §7.45(4)(E)(vii)
- class: c
- other states: "beyond the utility's control" and the approved-meter-reading-plan exception are Texas text. Another state's estimated-bill protection may have no such exception.
- fix: store the mapping as J rows `(state, service_type, reason_code) → bucket`. It stays non-tenant-editable (the ruling's intent) but is per state — size: S

### Straddling period forfeited whole
- where: `kyle-decisions-2026-09-22-a2-straddle-and-meter-test-anchor.md:81-132` (R-32)
- rule: an adverse period that starts before the window is forfeited in full. Grounded on (v)(I) having no estimation authority.
- class: c (mechanism chosen for Texas text; to be coded in A-2)
- other states: a rule that authorises proration would permit a split. R-32 names its own revisit trigger (interval data).
- fix: J flag `straddle_policy (forfeit_whole | prorate_days | measured)` per cause — size: S

### Six-month literal inside general mechanisms (R-36, R-37(a), §1 arithmetic)
- where: `kyle-decisions-2026-09-22-a2-straddle-and-meter-test-anchor.md:49,62-68,300-305`; `kyle-decisions-2026-09-23-a2-override-and-cause-freeze.md:72-74,123-127`
- rule: `window_start = MAX(anchor − 6 months, …)`. The transitional gate lapses at cutover + 6 months. The hold "self-lapses" once six months are billed.
- class: c
- other states: any cap other than 6 months breaks the gate-lapse arithmetic
- fix: every "6 months" in the gate, the hold self-lapse and the R-36 transitional gate must read the governing J row's bound — size: S

### Under-reach warning scoped to `meter_error` because it is the only mandatory bound in Texas
- where: `kyle-decisions-2026-09-02-a2-backbilling-caps.md:241` (R-27); `kyle-decisions-2026-09-23…:196-198`
- rule: "Under-reach is possible only for `meter_error` … the only mandatory bound in the seed table"
- class: c (if coded as `cause = 'meter_error'`)
- other states: a state whose non-registering rule is mandatory would need the warning on that cause too
- fix: J column `bound_is_mandatory bool`. The warning keys on it, not on the cause name — size: S

### Non-disconnectable flag (F-1) keyed to cause names
- where: `kyle-decisions-2026-09-22…:349-356` (F-1); `kyle-decisions-2026-09-23…:398-400`
- rule: meter-error (and the 3 new causes) backbills are non-disconnectable except `tampering_bypass` — source: §7.45(4)(E)(vi)
- class: c (as specified: "excludes `tampering_bypass`")
- other states: the tamper carve-out and "faulty metering" class are Texas text
- fix: derive the flag solely from the resolved J row's `enforceable_scope = never`. No cause-name branch — size: S

### Correction delivery path per cause (R-33, OQ-1)
- where: `kyle-decisions-2026-09-22…:136-187`; `kyle-brief-2026-09-23-oq1-correction-delivery.md:20-31,45-47`
- rule: meter_error ⇒ adjustment on the next bill (grounded in (v)(I) "corrected in subsequent bills"). The interim build lets void-and-reissue accept only `rate_misapplication`.
- class: c (interim cause-name gate)
- other states: the "computed wrong vs measured wrong" principle is general, but the mandated mechanism is Texas text
- fix: J column `delivery_path (adjustment | reissue | new_charge)` per state/cause. The general code reads it — size: S

### Stale "12-month Texas cap" left in the register
- where: `canonical-invariants.md:199` (CI-008 Jurisdiction), `:1612` (CI-092 Statement: "distinct from the general 12-month Texas backbilling cap")
- rule: the corrected miscitation (PUC water §24.165) still sits in two CI entries — source: corrected in `de-review-answers.md:163-173`, `backbilling-cap-enforcement.md:40`
- class: b (doc value, wrong)
- other states: n/a
- fix: strike it. Any value that survives into J needs a `source_note` citation — size: S

### Theme 3 — Meter testing (CI-091/092)

### 2.0% threshold: ruled per jurisdiction + service type (good)
- where: `kyle-decisions-2026-09-22…:363-372` (F-3); `ci091-meter-test-history-implementation-brief-2026-09-22.md:87` ("a second jurisdiction is a new data row rather than a code change")
- rule: "2.0% is the RRC gas figure, and the water and electric bodies do not share it"
- class: a
- other states: handled
- fix: none. But the register still says "platform-fixed 2.0% threshold" (`canonical-invariants.md:1599`), so update CI-091's grade text to name `meter_accuracy_thresholds` — size: S

### Meter-test fee rules ($15 cap, 4-year free test, refund on defect)
- where: `canonical-invariants.md:1594-1608` (CI-091); `kyle-decisions-2026-09-22…:383-386` (F-5)
- rule: free if none in 4 years for the same customer and location; fee ≤ $15 or tariff; refund if >2.0% — source: §7.45(7)(B)(iv)(I)/(II) (per E-1 erratum, `kyle-decisions-2026-09-23…:52-59`)
- class: b (designed as residual adhoc-charge work, no key named)
- other states: fee caps and look-back years differ (guess)
- fix: J row `meter_test_fee_rules(state, service_type, free_lookback_years, fee_cap, refund_on_defect)` + T fee — size: S

### "The last test" reading and the (7)(B)(ii) field list
- where: `kyle-decisions-2026-09-22…:191-233` (R-34), `:292-340` (R-36), `kyle-decisions-2026-09-02…:326-344` (R-31)
- rule: the anchor is the most recent completed test before discovery, any outcome. The customer-requested test record needs the (7)(B)(ii) field list.
- class: b
- other states: the anchor definition is a reading of Texas text. Field lists vary (guess).
- fix: keep the history table general, which is already the case. Put the anchor definition in J (`anchor_rule`) alongside `anchor_basis` — size: S

### Theme 4 — Protected-class scope (CCK)

### Protection scope = "§7.45 residential + small commercial" built into the resolver's modes
- where: `kyle-decisions-2026-09-02-customer-class-keying.md:27-58,222-230` (CCK-14 modes `all_non_residential_protected` / `explicit_class` / `volumetric_threshold`); `a2-implementation-brief-2026-09-21.md:126,161` ("Texas protections cover residential and small commercial customers only")
- rule: which customers a consumer-protection rule reaches is resolved per tenant by mode — source: §7.45 preamble
- class: b
- other states: many states' disconnection/deposit rules reach residential only, with commercial on tariff (guess). Some reach "small business" by statute. The set of protected classes is state law, not a tenant mode.
- fix: J row `protected_classes(state, service_type, rule_family)`. The tenant mode/threshold (CCK-4..13) stays T and says how that tenant's tariff draws the class line — size: M

### `tenant_regulatory_class_rules` has no effective dating
- where: `kyle-decisions-2026-09-02-customer-class-keying.md:150-181` (CCK-9, CCK-10)
- rule: `UNIQUE (tenant_id, service_type)`, "No effective-dating", on the grounds that determinations snapshot their inputs
- class: b
- other states: a tariff threshold change mid-year cannot be represented forward-dated. It is also a tariff (T) value, which is correct to key by tenant.
- fix: add `effective_from/to`; keep tenant keying — size: S

### `applies_to_customer_types` defaults omit size tiers (open, unruled)
- where: `kyle-decisions-2026-09-02-customer-class-keying.md:234-252`; `kyle-outstanding-2026-09-05.md:40-44`
- rule: a Texas-style size-tier vocabulary (small/large commercial) is missing from array defaults
- class: b
- other states: class vocabularies differ by tariff everywhere
- fix: class vocabulary as tenant T reference data, not array defaults — size: S

### Theme 5 — Collections, disconnection, notices

### EWE predicate (32°F, county NWS station, cold-only) as "the" moratorium
- where: `wu5-wu6-kyle-decisions-2026-07-10.md:87`; `canonical-invariants.md:1400-1415` (CI-080, "predicate itself … not configurable" :1413); `configurable-rules/decision-tables/cold-weather-moratorium.md:29` (`service_state` = TX), `:47` (rule 1), `:55` (no heat trigger)
- rule: moratorium basis enum has one value, `ewe_temperature` — source: Tex. Util. Code §104.258, 16 TAC §7.460
- class: c (stated non-configurable; table has one Texas predicate)
- other states: calendar-window moratoria (guess: MN, IL, MI), different thresholds (guess: KS/MO ~32–35°F forecast), and heat triggers for gas in some states (guess)
- fix: J `moratorium_rules(state, service_type, class, kind {calendar_window | temp_observed | temp_forecast | heat}, params, effective_from/to)`. The daily evaluator reads it — size: M

### Notice sequence and timing (15 / 5 / 5 working days, mail/hand, "Termination Notice")
- where: `canonical-invariants.md:1210,1218` (CI-068); `configurable-rules/configuration-catalog.md:1147-1151`; `configurable-rules/de-review-answers.md:273-290`; `configurable-rules/decision-tables/dunning-step-routing.md` rules 3/6/7; `disconnect-eligibility.md` rank 5/6
- rule: Texas values written into rule rows ("≥5 working days") — source: §7.45, TUC §104.258
- class: b (doc tables; intended `tenants.settings.dunning` = tenant-keyed)
- other states: personal-contact steps, 10-day or 48-hour notices, and calendar vs working days all vary (guess). The docs themselves say "CA, NY, PA each have distinct sequences" (CI-068 :1210).
- fix: J `notice_sequence_rules(state, service_type, class, step, min_elapsed, day_kind, delivery_methods, required_text_key)` + a per-state holiday calendar — size: M

### `notice_delivery_method` CHECK tied to `event_type`
- where: `kyle-decisions-2026-08-26-coda-items-4-7.md:237` (§5.1)
- rule: CHECK "`shutoff_notice_sent` requires `mail` or `hand_delivery`" — source: 16 TAC §7.45
- class: c
- other states: some states allow electronic termination notice with consent, or require a phone or personal-contact attempt (guess)
- fix: move the permitted-methods set to the J notice rule. Enforce it with a trigger lookup, not a literal CHECK — size: S

### Disconnect-ineligible arrears grounds (six carve-outs), "not configurable"
- where: `canonical-invariants.md:1368-1382` (CI-078, :1380)
- rule: previous occupant, merchandise, other service type, rate-misapplication >6 mo, faulty metering, estimated bill outside plan — source: §7.45
- class: c (stated as a fixed statutory set)
- other states: sets differ (guess)
- fix: J `disconnect_ineligible_grounds(state, service_type, class, ground_code)` over a general charge-categorization vocabulary — size: M

### No disconnect on / before a closed day (the "Friday" rule)
- where: `canonical-invariants.md:1384-1398` (CI-079); `configurable-rules/decision-tables/disconnect-eligibility.md` rank 6
- rule: no disconnect on a day, or the day before a day, when personnel are unavailable — source: TUC §104.258
- class: b
- other states: many states forbid disconnection on Friday or before holidays, or restrict it to certain hours (guess), with different day definitions
- fix: J row `disconnect_calendar_rules(state, …)` + a tenant business calendar (T) — size: S

### Elderly day-26 timing protection
- where: `configurable-rules/decision-tables/disconnect-eligibility.md:30-31` and rank 7; `configurable-rules/configuration-catalog.md:1136-1140`
- rule: an elderly customer may not be disconnected on or after day 26 — source: §7.45 (text unverified per de-review action 19)
- class: b
- other states: senior protections vary or are absent (guess)
- fix: J row in `disconnect_timing_rules` — size: S

### Medical (seriously-ill) hold: 20 days, 5 working days, installment-agreement companion
- where: `canonical-invariants.md:1417-1431` (CI-081, :1429); `configurable-rules/decision-tables/program-enrollment-eligibility.md` rows 1-2; `configurable-rules/de-review-answers-8-11.md:36-44`
- rule: Texas-specific composition (hold requires IA) — source: §7.45(4)(H)
- class: b
- other states: durations of 21, 30 or 63 days and renewals are common (catalog cites 63 days for PUCT electric, `configuration-catalog.md:1159-1163`). The IA companion requirement is Texas-only (guess).
- fix: J `program_protection_rules(state, service_type, program_type, duration, submission_window, requires_companion)` — size: M

### Agency pledge is time-boxed to the billing period
- where: `kyle-decisions-2026-08-26-coda-items-4-7.md:303`; `configurable-rules/decision-tables/collections-bypass-evaluation.md` rank 4
- rule: §7.460(b)(2): no disconnect for the billing period in which a pledge is received. The planned "mandatory-expiry CHECK mirroring the rule's own scope".
- class: c (if the expiry CHECK encodes the Texas scope)
- other states: pledge-hold windows vary (CI-056 cites PA 30 days)
- fix: pledge window from J `program_protection_rules` — size: S

### Family-violence status is a deposit waiver only, not a disconnect bypass
- where: `wu5-wu6-kyle-decisions-2026-07-10.md:86`; `canonical-invariants.md:2401-2403` (Q-6)
- rule: "FV flag waives deposit; it does NOT join the disconnect bypass list" — source: §7.45(5)(C)
- class: b (a Texas ruling fixed into the platform's bypass-set membership)
- other states: some states give domestic-violence victims disconnect or deposit protections differently (guess)
- fix: membership of each protection in each rule family is J data `(state, protection_kind, rule_family)` — size: S

### Bilingual: "two-language enum + per-tenant exemption flag; no county table"
- where: `wu5-wu6-kyle-decisions-2026-07-10.md:96`; `canonical-invariants.md:1544-1560` (CI-088), `:2430` (Q-8); `configurable-rules/decision-tables/communication-language-format.md:25,49-50`
- rule: EN+ES mandatory for regulated notices unless there is an RRC exemption. The decision table's `jurisdiction` enum is "Texas (in-city / environs)" — source: §7.45(2)(A)(vi), (4)(C)
- class: c (a closed two-language shape and a Texas-only jurisdiction enum)
- other states: other states require other or additional languages, some by locality (guess: CA). The docs themselves cite "CA AB 3254" (CI-097).
- fix: J `required_notice_languages(state[, place], notice_type, languages[])` + tenant exemption rows (T) — size: S

### Theme 6 — Deposits (A-21)

### Deposit cap 1/6 annual billing, recorded as a Texas residential cash §7.45 property
- where: `canonical-invariants.md:2229,2231` (CI-129); `:2629-2632` (A-21 landed); `configurable-rules/decision-tables/deposit-eligibility-and-waiver.md` rank 8; `execution-kickoff.md:57`
- rule: `principal ≤ cap_amount` CHECK; the cap basis is 1/6 estimated annual billing — source: §7.45 §6
- class: b/c (the cap is recorded per deposit; the formula "1/6" is application-side per the doc; the §7.45 basis is baked into the `basis` enum)
- other states: deposit caps are commonly "2× average monthly bill" or "2 months' billing" (the KB itself cites 2×, CI-077 :1353)
- fix: J `deposit_rules(state, service_type, class, cap_formula, cap_multiplier, effective_from/to)`. The basis enum becomes general (`regulatory` / `adequate_assurance_366` / `tariff`) — size: M

### Waiver kinds are a closed Texas list; the 65+ waiver's status is contradictory
- where: `canonical-invariants.md:2231` (A-21 `deposit_waiver_determinations`: family_violence_certified, age_65_no_balance, good_payment_history, tariff), `:2229` (CI-129 lists 65+ as mandatory); vs `configurable-rules/de-review-answers.md:160-162` ("65+ waiver is tariff-by-tariff for gas … must not be hard-coded as statutory")
- rule: waiver classes fixed as statutory
- class: c
- other states: medical, LIHEAP-enrolled and senior waivers vary (guess)
- fix: J `deposit_waiver_rules(state, service_type, waiver_kind, mandatory, criteria)` + T tariff waivers. Resolve the 65+ contradiction to T — size: M

### Interest 30-day cliff, retroactive to day 1, built as `deposit_events` refusals
- where: `canonical-invariants.md:2243-2257` (CI-130, :2248 "Every rule of this Statement is a refusal in `deposit_events`"); `configurable-rules/decision-tables/deposit-refund-and-interest.md` rules 5-6
- rule: no interest if refunded ≤30 days, else accrue from the posting date — source: §7.45 / TUC §183
- class: c
- other states: interest from day 1, from month 6, or no interest at all (guess)
- fix: J `deposit_interest_rules(state, service_type, grace_days, retroactive bool)`. The triggers read it — size: M

### Deposit interest rate table keying
- where: `canonical-invariants.md:2629` (A-21 "`deposit_interest_rates` (effective-dated, no fallback)"); `configurable-rules/configuration-catalog.md:1289-1292`; `canonical-invariants.md:2255` ("PUCT rate") vs `test-fixtures/jurisdictions.md` FIX-JUR-001 ("statutory rate … NOT a 'PUCT rate'")
- rule: the rate in force per accrual period is a single statewide annual figure in Texas
- class: b (effective-dated; the docs do not say state-keyed, and the catalog frames it as tenant/jurisdiction — verify in tu.sql)
- other states: each state sets its own rate or ties it to Treasury bills (guess)
- fix: platform J `(state, service_type, effective_from/to, rate, source_note)`. Also settle PUCT vs statute in the docs — size: S

### Automatic refund trigger: 12 bills, ≤2 delinquent, not currently delinquent
- where: `canonical-invariants.md:2259-2273` (CI-131, :2271); A-21 `deposit_refund_trigger_state()` (`:2629`)
- rule: thresholds live in a function — source: §7.45 §6.5
- class: c
- other states: 12 months, 18 months or 24 months of good payment (guess)
- fix: J `deposit_refund_rules(state, class, consecutive_bills, max_delinquent)` — size: S

### Good-payment-history no-deposit exception
- where: `configurable-rules/decision-tables/customer-credit-scoring.md` rule 1 (inputs at :26 "the §7.45 test is ≤1")
- rule: prior customer within 2 years, ≤1 late payment, never disconnected ⇒ no deposit
- class: b
- other states: different look-backs and late-count thresholds (guess)
- fix: fold into J `deposit_waiver_rules` — size: S

### Theme 7 — Surcharges, taxes, franchise, escheatment

### PSF: tenant-held rule rows, per-tenant $ cap, Texas-only `surcharge_kind`
- where: `canonical-invariants.md:683-697` (CI-038), `:2535-2537` (A-7 landed: `regulatory_surcharge_rules`, `cap_per_service` "configured amount", one open `pipeline_safety_fee` rule per tenant, `customers.is_state_agency`, `excluded_from_tax_bases`); `wu5-wu6-kyle-decisions-2026-07-10.md:61-63`
- rule: the statutory cap ($1.00 vs $0.50 unresolved), the state-agency exemption and tax exclusion are all from 16 TAC §8.201
- class: b
- other states: other states' pipeline-safety or regulatory-assessment surcharges have different caps, exemptions and taxability (guess). The general `other_regulatory_cost_recovery` kind is a good seam.
- fix: J `statutory_surcharge_rules(state, service_type, kind, cap, exempt_customer_kinds[], excluded_tax_bases, effective_from/to)`. Tenant rows carry only the factor. `is_state_agency` generalises to an exemption-kind attribute — size: M

### Franchise fees: per-tenant per-city rows; 2% ceiling to be validated in code
- where: `configurable-rules/configuration-catalog.md:1106-1117`; `configurable-rules/decision-tables/franchise-fee-application.md:52`; FIX-JUR-001 "CONTESTED — §182.025" (`test-fixtures/jurisdictions.md:139`)
- rule: `franchise_fee_rules` is tenant-scoped with free-text `franchise_city`. The Tax Code §182.025 2% ceiling is to be checked at save.
- class: b (rules) / c (ceiling planned as a validation literal)
- other states: the franchise model itself differs (guess: some states fold it into rates, and many have no statutory ceiling)
- fix: the ceiling goes in a J row `(state, service_type, max_street_use_pct)`. Rows point at a shared place (see Theme 8) — size: S

### Tax exemption bases: `industrial` removed on Texas reasoning
- where: `kyle-decisions-2026-08-26-a1-bitemporal.md:97-117` (R-13)
- rule: three Texas bases (exempt org, residential §151.317 derived, predominant use). Removing `industrial` from the CHECK ships in A-1.
- class: c (CHECK domain decided by Texas bases)
- other states: states exempt residential gas differently, and some exempt industrial or manufacturing by category (guess)
- fix: exemption kinds as J `(state, tax_kind, exemption_kind, requires_certificate, partial_allowed)` — size: M

### Adhoc-charge taxability: "platform's Texas-shaped defaults", tenant override
- where: `configurable-rules/decision-tables/adhoc-charge-taxation.md:40,43`
- rule: platform defaults follow Texas Tax Code Ch. 151; the divergence path is a tenant override
- class: b
- other states: a non-Texas tenant must override state law per tenant
- fix: defaults become J rows by state; the tenant override stays for tariff specifics — size: S

### Tax stacking: "Texas default: no tax-on-tax"
- where: `configurable-rules/decision-tables/tax-application-and-stacking.md:44`
- rule: a tax line never enters a later tax's base
- class: b
- other states: some jurisdictions tax gross receipts taxes or stack city on state (guess)
- fix: stacking order and base inclusion as J rows in the A-8 `tax_jurisdictions` design — size: M

### Escheatment dormancy hardcoded in a matview (1095 / 1005 / 365 / 60 / 250)
- where: `configurable-rules/workflows/escheatment-processing.md:11,74`; `configurable-rules/decision-tables/overpayment-and-credit-disposition.md:32,72`; `configurable-rules/de-review-answers.md:252-261` (action 16)
- rule: 3-year general dormancy; Texas also needs 18-month or 1-year for deposits, a June 30 / Nov 1 cycle and a $250 due-diligence threshold — source: Tex. Prop. Code §72.101, §72.1017, §74.101
- class: c
- other states: every state sets its own dormancy by property type and its own report date (guess)
- fix: J `unclaimed_property_rules(state, property_type, dormancy, report_as_of, report_due, due_diligence_threshold)`. `escheated_to_jurisdiction` is free text and should FK a state — size: M

### Theme 8 — The jurisdiction model itself

### `jurisdictions` is tenant-scoped, has no state, and mixes place with utility config
- where: `jurisdictions-shared-place-modelling-2026-09-22.md:20-29,39,60`; `kyle-decisions-2026-09-02-a2-backbilling-caps.md:210` (R-26: "No change to the `jurisdictions` table")
- rule: `UNIQUE (tenant_id, jurisdiction_code)`; no level, no parent, no state, no Inc/Env
- class: b
- other states: there is no place to say "this row is in Oklahoma", so a state-keyed J lookup has nothing to join through
- fix: adopt the doc's shared-places proposal, and add `state_code` (+ place kind) to the shared place. Tenant `jurisdictions` then points at it. Sequence this before A-2's cap FK hardens — size: M

### Incorporated vs Environs as a Texas-statutory enum; `inside_city_limits` boolean
- where: `canonical-invariants.md:1512-1526` (CI-086, :1524 "Inc/Env enumeration itself is Texas-statutory and not configurable"); `configurable-rules/configuration-catalog.md:1021-1030`
- rule: every Texas location carries Inc/Env, which keys tariff, franchise and rate-change path
- class: c (enum) / b (boolean in place today)
- other states: municipal original jurisdiction is Texas-specific. Elsewhere the place attributes that matter are tax districts or municipal-utility status (guess).
- fix: a place-kind vocabulary per state in J. The date-effective place assignment on the service location points at a shared place — size: M

### Service type used as a stand-in for "RRC gas" (no de minimis, void-only barred, historical rate mode)
- where: `configurable-rules/de-review-answers.md:57-72` (DE-3: "`current` is selectable for non-gas only"); `kyle-decisions-2026-08-18-coda-items.md:504` (D-8: "`void_only_unbilled_disposition` is ignored for gas meters (COMMENT 4796) — RRC requires full correction"); `kyle-decisions-2026-08-26-a1-bitemporal.md:172` (R-17)
- rule: the Texas regulator's correction doctrine is keyed on `service_type = 'gas'`
- class: c
- other states: another state's gas regulator may allow de minimis write-offs or void-only; a Texas water utility would not be RRC
- fix: J `correction_rules(state, service_type, allow_void_only_reasons[], de_minimis, rate_mode_required)`. Code tests the resolved row, never the literal 'gas' — size: S

### `program_types` is shared (no tenant_id) but not state-keyed
- where: `jurisdictions-shared-place-modelling-2026-09-22.md:37`; `configurable-rules/decision-tables/program-enrollment-eligibility.md:22` (11 seeded values, incl. `regulatory_moratorium`, `elderly_disabled`, `agency_pledge`); `configurable-rules/de-review-answers.md:175-186` (statutory seed types regulated, tenant-added configurable)
- rule: the protection-type list is platform reference data with a "statutory seed", but whose statute is unstated
- class: b
- other states: the set of statutory protections differs by state (e.g. PIPP-style programs in OH/PA, guess)
- fix: keep the vocabulary general and platform-held. Add J membership rows `(state, service_type, program_type, is_statutory, is_disconnect_protective)` — size: S

### Regulatory posture as a first-class tenant attribute (good principle)
- where: `canonical-invariants.md:2281-2296` (CI-132)
- rule: posture-dependent gates read the tenant's posture (IOU / municipal / co-op), never assume it
- class: a
- other states: correct shape; the effect of posture is itself state law (e.g. munis exempt from the PSC)
- fix: pair it with J `(state, posture) → which rule families apply` — size: S

### Theme 9 — Rates, bill content, read cadence, rule-model shape

### SOI workflow: 4 consecutive weeks of notice + 35 days; missed week ⇒ full reset
- where: `canonical-invariants.md:1528-1542` (CI-087, :1540); `wu5-wu6-kyle-decisions-2026-07-10.md:95` (D11-1)
- rule: rate increases gated on TUC SOI steps — source: TUC (GURA §104.103)
- class: b (unenforced gap; the design is Texas steps)
- other states: rate cases, suspension periods and notice rules differ entirely (guess)
- fix: J `rate_change_procedure(state, service_type, posture, steps[], waiting_days)`. The gate reads it — size: M

### Bill-format element set "not LDC-configurable"
- where: `canonical-invariants.md:1562-1576` (CI-089, :1574); `kyle-decisions-2026-09-02…:56-57,155-157` (R-23: (6)(B)(v), (6)(B)(viii))
- rule: a fixed list of mandatory bill elements
- class: c (as stated)
- other states: required elements differ (guess)
- fix: J `bill_content_requirements(state, service_type, element_code)`. The completeness gate reads it — size: M

### Actual-read cadence 6 months; postcard after 2 inaccessible months
- where: `canonical-invariants.md:1578-1592` (CI-090, :1590); `configurable-rules/de-review-answers.md:21-35` (DE-1 estimate ceiling = the Texas 6-month cadence)
- rule: TX-RRC-prescribed values
- class: b
- other states: the docs themselves cite "2-in-a-row residential" (CI-113). Values vary.
- fix: J `read_cadence_rules(state, service_type, class, max_months_without_actual, self_read_trigger_months)` — size: S

### Payment terms floor 15 days; postmark timeliness
- where: `configurable-rules/de-review-answers.md:27-30,302-315`; `configurable-rules/configuration-catalog.md:1212-1216`
- rule: `payment_terms_days ≥ 15` "system should enforce the floor". Texas timeliness uses the postmark/sent date.
- class: b (planned enforcement, key unspecified)
- other states: floors of 14, 20 or 21 days and receipt-date rules (guess)
- fix: J `payment_terms_rules(state, service_type, class, min_days, timeliness_basis)` — size: S

### Decision tables: Texas values in rule rows, no state input
- where: e.g. `configurable-rules/decision-tables/backbilling-cap-enforcement.md:23` (`jurisdiction | Texas at launch`), `:27` (`service_type | gas at launch`); `deposit-eligibility-and-waiver.md:5` ("regulated — … 16 TAC §7.45-prescribed"); `deposit-refund-and-interest.md` rules 2, 5, 6; `dunning-step-routing.md` rules 3, 6, 7
- rule: 13 of 60 tables carry ≥5 Texas citations and none has a state column. The model's bi-temporal header (`configurable-rules-scenario-strategy.md:620-640`) versions the whole table, not a state's slice.
- class: b
- other states: a second state would fork each table
- fix: regulated tables take a `jurisdiction_rule_id` resolved from J as an input. Rule rows reference J fields (`cap_formula`) rather than literals — size: M

### Tenant-level knobs that are Texas-statutory values under a tenant key
- where: `configurable-rules/configuration-catalog.md:1147-1151` (`collections-pipeline-config` → `tenants.settings.dunning`), `:1256-1260` (DPP config → `tenants.settings.dunning`), `:1136-1140` (late-fee elderly provision)
- rule: statutory timings and the obligation to offer a DPP are to be held in tenant settings JSON
- class: b
- other states: every tenant would re-enter its state's law, and a multi-state tenant cannot
- fix: split into a statutory floor (J) and the tariff value (T, CHECKed ≥ floor via lookup) — size: M

### Good examples (class a) worth reusing
- where: `kyle-decisions-2026-09-02…:133` (R-21 keeps "the per-jurisdiction slot for states that *do* cap it"); `:281` (R-29 "the determination records what resolved it"); `kyle-decisions-2026-09-23…:129-142` (R-37(d): the tenant adverse limit is constrained ≤ the statutory bound, defaults to it, never applies favourably); `wu5-wu6-kyle-decisions-2026-07-10.md:92` (bankruptcy implemented federally, with no Texas overlay); `kyle-decisions-2026-08-26-coda-items-4-7.md:217-219` (R-7 per-tenant by design); `canonical-invariants.md:409` (CI-021 reference conditions "configured per jurisdiction"); `configurable-rules-scenario-strategy.md:620-640` (rule tables bi-temporal on both axes); `test-fixtures/jurisdictions.md:27+` (FIX-JUR-001, a state-level parameter set with sub-jurisdiction children — the right shape, as a fixture)
- rule: the statute sets the bound as data, and the tenant chooses within it; determinations record the rule row used
- class: a
- other states: these carry over unchanged
- fix: FIX-JUR-001's attribute list is a ready inventory of J columns for Texas gas. Promote it to seed data — size: S

---

## configurable-rules/ — shape of the rule model

- **Layers:** (1) `configuration-catalog.md` holds 125 knobs at levels tenant / customer / account / service-location / meter / rate-schedule / customer-class / jurisdiction, each marked `configurable` / `regulated` / `none`. (2) 60 DMN-style decision tables in `decision-tables/`, each with a hit policy, Inputs, Outputs and ranked Rules, plus a bi-temporal file header (`Valid from/to`, `Recorded at`, `Supersedes`). (3) Workflows in `workflows/`. (4) Scenarios with parametric expansion over five axes, the first being "Texas sub-jurisdictional placement".
- **Keying:** every substrate that exists or is designed is per **tenant**: `tenants.*` columns, `tenants.settings` JSON sub-objects (`dunning`, `billing`, `estimation`…), tenant `franchise_fee_rules`, and tenant `jurisdictions`. "Jurisdiction" is a catalog *level* whose only content is a doc overlay (`configuration-catalog.md:1086-1104`) sourced from KB-31. The intended per-jurisdiction substrates (`jurisdiction_rules` A-14, `tax_jurisdictions` A-8) were named but never designed. A-8 is fenced pending a Kyle brief (`schema-parity-plan.md:60,134`).
- **Per state?** No. There is no state key anywhere in the model. Texas values are written into catalog "Regulatory constraints" fields (F-CC-4) and into decision-table rule rows. "Multi-state" is declared a Layer-4 parametric *test* axis, deferred.
- **Per tenant?** The runtime model is per tenant, with a tenant overriding downstream (override chains). Regulated knobs are "tariff-bound" (tenant value must match the filed tariff) or "regulated" (a Texas ceiling documented beside the knob).
- **Closest thing to a per-jurisdiction rule model:** the test fixture FIX-JUR-001 (`test-fixtures/jurisdictions.md:27-148`) and R-26's cap-table fallback. The first is state-level but only a fixture. The second is data but tenant-keyed.
- **Net:** the model's *discipline* is sound: regulated vs configurable, bi-temporal rule versions, and "tenant may extend but never narrow" (`deposit-eligibility-and-waiver.md` rank 3). It is missing the platform-held J layer that the `meter_accuracy_thresholds` pattern supplies. Adding that layer is a keying change plus seed data. It is not a redesign of the four layers.

## Doc inconsistencies found in passing (unclassed)

- CI-049 says "Texas applies oldest-first per 16 TAC" (`canonical-invariants.md:887`); DE-2 found no such mandate (`configurable-rules/de-review-answers.md:40-55`).
- CI-129 treats the 65+ waiver as a mandatory §7.45 waiver (`canonical-invariants.md:2229`); DE says tariff-by-tariff (`de-review-answers.md:160-162`).
- CI-130 cites the "PUCT rate" (`canonical-invariants.md:2245,2255`); FIX-JUR-001 insists it is a "statutory rate … NOT a PUCT rate".
- CI-091 says the outcome is derived "against the platform-fixed 2.0% threshold" (`canonical-invariants.md:1599`); F-3 ruled it per jurisdiction × service type.
- CI-038 states a "$1.00" PSF cap (`:685`); D4-1 research says "$0.50/service" (`wu5-wu6-kyle-decisions-2026-07-10.md:62`). Still unresolved.
- CI-008 and CI-092 still cite a 12-month Texas cap (`:199`, `:1612`).

## Finding counts

- class a: **4** (F-3 2.0% threshold; CI-132 posture; commodity-scope principle; grouped good-examples entry)
- class b: **35**
- class c: **22**
- Total 61 findings, plus 6 unclassed doc inconsistencies. Mixed entries are counted once: the deposit cap as c, franchise fees as b, Inc/Env as c.
- Part A inventory: ~95 ruling codes tabulated (R-3…R-39, F-1…F-5, CCK-1…15b, T-/D-series, DE-1…11, 14 Texas-tagged CIs plus the multi-jurisdiction CI group).
