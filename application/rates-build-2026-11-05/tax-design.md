# Tax, tax stacking and franchise fees — design (2026-11-05)

**Inputs:** `tax-inventory.md` (what exists, 17 gaps), `tax-triage.md` (18 open points: 16 settled, the franchise base sent to Kyle). **Invariants:** the franchise fee traces to its city (CI-044); each tax on its own base, in its order (CI-045); tax rules dated and replayable (the tax half of CI-001 and CI-004). Kyle's rulings of 2026-10-14 (answers 1–5), 2026-11-03 (answer 4) and 2026-11-05 (batch 2, answers 3a, 3b and 20; GBM `application/kyle-decisions-2026-11-05-scenario-batch-2.md`) govern; Ryan's rules on utility-owned values, percent storage and storage-not-entry apply throughout.

Each shape below says whether it is a schema change or only the core's, and whether it adds or changes meaning (cost of changing it later).

## 1. Patch split

Three patches on the rates side, plus one board note to the money stream. Numbers are names; the order is the build order.

| Patch | What | Waits on |
|---|---|---|
| **-30** | Tax rows keyed to places (the utility's levies, with the published rates as reference); required taxability; each charge's base memberships (sales tax and the late-penalty base); exemptions strictly per service type; tax rates in percent; reading places and memberships as known at a past instant; the size-tier defect on rate items; a state-agency setting carries its documented basis | nothing |
| **-31** | Franchise fees rebuilt: keyed to the city as a place, rate in percent, base type, customer types checked, reference date, the street-use ceiling as a reference value | Kyle's answer on the franchise base |
| **-32** | Data: Texas cities, transit authorities and special districts as places, with the Comptroller's published rates as reference facts (like -29) | the Comptroller's files pulled and checked; -30 |
| board note | The money side: each tax or franchise line names its rule row and its place; no tax on tax unless the levy declares it; an exempt $0.00 line keeps its would-be base and names the exemption; the silent defaults on one-off charges and bill lines; a one-off charge's service type required; snapshots may cite places, memberships and levies; the liability by jurisdiction and accounting period | money's own patch |

Why this split: -30 carries everything that does not wait on Kyle and that -31 and -32 build on (the levy table, percent rates, the as-of reads). -31 is small once Kyle answers. -32 is data and needs its own source check, as -29 had.

## 2. -30: what it builds

### 2.1 The utility's tax levies, keyed to a place (schema; additive: a new table)

A new tariff table on the rule-terms template, `tax_levies`: the utility's own rows (tenant-scoped, row-level security), one per (place, tax kind, service type), dated and bi-temporal like the other rule tables.
- **Key:** the place (any kind on the tax axis: state, county, city, transit authority, district), the tax kind (a short checked list: `sales_tax` today; others added by rows of a kind table, not by editing a CHECK), the service type (gas now; water and sewer when tax counsel answers, same shape).
- **Terms:** the rate in percent with at most four decimals; the base (for sales tax: the lines flagged taxable, Kyle 2026-11-03 answer 4); the stacking position; any levy it may be computed on (tax on tax), named explicitly and empty by default (Texas: none unless the jurisdiction declares it); the source kind (statute, ordinance or tariff) and its citation, both required (Kyle answer 2).
- **Facet:** whether residential gas is reached, read from the place's `residential_gas_taxable` reference fact or the utility's tariff (Kyle 2026-11-03 answer 4: city sales tax inside city limits only).
- **Read by** `tax_levies_as_of(tenant, place, tax kind, service type, valid_at, recorded_at)`, both coordinates required, like every A-1 lookup.

**Why a utility row and not the place fact:** the utility collects the tax and answers for it (Ryan 2026-09-30). The Comptroller's published rate stays the platform's reference fact (`place_facts.sales_tax_rate`), and a compare function reports where a utility's levy disagrees with it. Neither ever silently overrides the other.

**Staging and sign-off (Kyle answer 1):** a proposed rate change is a draft levy row, dated from its quarter's first day, created by the scheduled job from the Comptroller's file. A draft bills nothing; it becomes an assertion when an operator of the utility approves it (stamped by the database, with the approver), as an exemption certificate does when it is verified (-03). No separate staging table. The job itself is the application's.

### 2.2 Required taxability (schema; changes meaning of an unset value, cheap now: no rows)

- `rate_item_versions.is_taxable_default` loses its default: every new version states it (Kyle answer 5). `is_a_tax` likewise.
- The comment on the column stops calling the default an open question.
- The one-off charge and bill-line defaults are the money stream's (board note).

### 2.2a Each charge states which bases it is in (schema; one mechanism for every base)

Kyle 2026-11-05 (batch 2, answer 3a) rules a late penalty is computed on "every line priced by the tariff" (customer charge, volume charge, gas cost adjustment), "never on taxes or state fees such as the pipeline safety fee", delivered as a **tenant-controlled per-charge "penalty base" setting**. That is a second base whose membership each charge states. With the sales-tax flag (2.2) it makes two; the franchise base may be a third (Kyle's answer pending, section 3).

So the mechanism is one, shared by every base: each rate item version states, for each base kind that applies, whether its lines are in that base, required, with no default. The base kinds are rows of a kind table (`sales_tax`, `late_penalty` now; `franchise` if Kyle answers per-charge), not a CHECK edited per base. The sales-tax flag of 2.2 becomes the `sales_tax` membership, so there are not two ways to say it. A rider whose surcharge rule excludes it from tax bases (the pipeline safety fee) can state "in" for none of them, as today's guard does for the taxable flag.
- **Why now:** a second per-charge base setting arrives with -30's work on the first; building them as one mechanism costs little now, and two parallel flags would be the overlap Kyle asked to remove (2026-10-14 answer 3). If Kyle answers the franchise base with a fixed list instead, the franchise base is computed from the list and the kind table simply has no `franchise` row: nothing built here changes meaning.
- **Who reads it:** the penalty engine is the money stream's (the late-charge type, Kyle answer 3b, decides the penalty line's own taxability: a forfeited prompt-payment discount on a gross/net tariff is taxed like the gas, a true penalty is not; a tax advisor confirms before a gross/net city goes live). The setting lives on rate item versions, this stream's table; a board note tells money it exists.

### 2.3 Exemptions strictly per service type (schema; tightens a function)

- `should_charge_tax` refuses a NULL service type instead of letting it match any exemption.
- A new exemption names at least one service type; "every service" is the list written out. Existing rows: none in production; the battery checks the old reading is gone.
- `customer_tax_exemptions` joins this stream's tables on the board (it is tax data).

### 2.4 Tax rates in percent (schema; changes the meaning of a fact kind, free now: no rows)

`place_fact_kinds.sales_tax_rate` becomes percent with at most four decimals (8.25, not 0.0825), and its bounds move with it. The levy rate is percent. (AC-45.)

### 2.5 Places and memberships as known at a past instant (schema; additive)

A rebill must see the tax jurisdictions the original bill saw (CI-001, CI-004). `premise_places_as_of` gains a recorded-at coordinate: a membership closed or voided after that instant still counts, and one recorded after it does not. Places and place facts likewise (they carry close stamps). The one-date form stays for today's readers.

### 2.6 The size-tier defect on rate items (schema; changes a default)

`rate_item_versions.applies_to_customer_types` loses the default that leaves out small and large commercial accounts, and its values are checked against the customer-type list (Kyle 2026-09-02). The franchise rule's copy is fixed in -31.

### 2.6a A state-agency setting carries its documented basis (schema; tightens a write)

Kyle 2026-11-05 (batch 2, answer 20): counties, school districts and private colleges pay the pipeline safety fee by default; a public college or university may be an exempt state agency (Utilities Code §101.003(15), Government Code §572.002, limited by Natural Resources Code §31.401(a) on the Attorney General's reading). Any customer may carry an operator-set exemption flag "with documented basis"; setting up a public college prompts the operator to verify; when unsure, lean toward exempting.
- Today the fee check (-07, re-issued by -28: `customer_is_state_agency_as_of`) reads the dated customer setting `is_state_agency` from `customer_attribute_history`, with no basis recorded.
- -30 requires a basis (a citation or document reference, and who set it) on every change of that setting to true. The prompt for a public college is the application's. The definition of "state agency" is on the tariff-counsel list.

### 2.7 The old customer exempt flag retired (schema; removes unread columns)

`customers.is_tax_exempt` and its five companion columns are read by no tax path; two reports read them. The reports switch to the exemption table, and the columns go. `customers` is claimed on the board for these columns only.

## 2.8 -30's interface (fixed before the tests; 2026-11-05)

Two drafting calls changed while fixing it, both toward less machinery:
- **No draft levy rows (replaces the staging paragraph of 2.1).** The rule-terms template's tariff rows have no draft state, and a proposed rate bills nothing, so it need not be a schema row. The Comptroller job's proposal lives in the application; the operator's approval is the insert of the utility's row, which records who approved it (`created_by`). The reference compare (below) is what catches a published change nobody approved.
- **One column per base, not a kind table (replaces the kind table of 2.2a).** `is_taxable_default` already is the sales-tax membership; the late-penalty base is a second required column beside it; a franchise column follows only if Kyle answers per-charge. A column with NOT NULL and no default is required by itself; a kind table would need a deferred check that every version answers every kind.

**Objects.**
- `tax_kinds` (platform-held: `tally_app` reads only): `tax_kind` (key), `place_kinds` (the kinds of place that levy it), `description`, `source_note`. Seeded: `sales_tax`.
- `tax_levies` (tariff, on the rule-terms template; area key `place_kind`, `place_code`, `tax_kind`; terms kind `tax_levy` v1): template columns plus `place_kind`, `place_code` and `tax_kind` (text, NOT NULL; FKs to `place_kinds` and `tax_kinds`). **The place is named by its kind and code within the row's state, not by its row id** (drafting, 2026-11-05): the template's key columns must be text, and a code-keyed row survives the place's succession (a closed place row and its successor share the code), which a row id would not (the lesson of -29's Texas succession). Terms: `rate_percent` (number, 0 to 100), `stacking_position` (integer, 1 or more), `computed_on` (array of tax kinds this levy is charged on top of; required, empty means none), `source_kind` (`statute`, `ordinance` or `tariff`), `citation` (text), `reaches_residential` (boolean). Insert check (refuses): another utility's row; a place kind that does not levy the tax (`tax_kinds.place_kinds`: for sales tax the state, a county, a city, a transit authority, a district); no place of that kind and code in the row's state in force over the whole of the row's dates (its successive rows may cover them together); a rate with more than four decimals; `computed_on` naming an unknown kind or the levy's own; a blank citation (at least one letter or digit).
- `tax_levy_as_of(p_tenant_id, p_state_code, p_place_kind, p_place_code, p_tax_kind, p_service_type, p_system_kind, p_on date, p_recorded_at timestamptz)` (the place as `premise_places_as_of` returns it): the row in force on the date as recorded at the instant (created by then, not closed by then), or NULL; any NULL argument raises.
- `tax_levy_reference_gaps(p_tenant_id, p_on date)`: one row per `sales_tax` levy in force whose place carries a `sales_tax_rate` reference fact in force that differs, with both values and the fact's source.
- `rate_item_versions`: `is_taxable_default` and `is_a_tax` lose their defaults; new `in_late_penalty_base boolean NOT NULL` (no default); `applies_to_customer_types` loses its default and must be a non-empty subset of the customer types the `customers` check allows. Refused: a version in the late-penalty base that is a tax (`is_a_tax`), or whose rate item has an open surcharge rule excluded from tax bases (both directions, as -07's guard).
- `customer_tax_exemptions`: `service_types` must be a non-empty list. `should_charge_tax` raises on a NULL service type.
- `place_fact_kinds.sales_tax_rate`: percent, 0 to 100.
- `premise_places_as_of(p_service_location_id, p_on, p_axis, p_recorded_at)`: a membership created after the instant is not seen; one voided or closed after it is seen as it stood. The three-argument form stays.
- `customers.state_agency_basis text`: required (a letter or digit) while `is_state_agency` is true; changes logged in the attribute history (attribute `state_agency_basis`).

**Moved out of -30:** retiring the old customer exempt columns (2.7). It needs the `compliance_statistics` materialized view rebuilt under -11's isolation checks, which is more risk than an unread column is worth inside this patch; it becomes its own small item.

**Older tests ported in the same change** (they insert rate item versions without the columns that lose their defaults, or exemptions with no service types): batteries -09, -20, -21, -23 (the money stream's: board note), -28, -29 and race `labels-21.sh`.

## 3. -31: franchise fees (after Kyle answers)

- **Keyed to the city as a place** (`place_id`, a municipality, replacing `city_name`), and read from the premise's city membership dated by the boundary, not the sales-tax quarter (triage 3, 4).
- **Rate in percent**, four decimals.
- **Base:** per Kyle's answer: either the base type from a fixed list ("gas sales", "all billed lines") with a rider's exclusion recorded per base, or a required franchise yes/no on each charge. If per-charge, it is the `franchise` row of -30's base kinds (2.2a), not a new column.
- **Customer types:** no default; values checked.
- **Reference date** for a mid-period rate change: stored on the rule, with no default (the app offers period end, Kyle D6-1).
- **The street-use ceiling** (Tax Code §182.025, 2% of gross receipts) as a reference value with a discrepancy report, not a refusal: franchise contracts may pay more (§182.026(b)(2)), and a city system does not pay it to its own city (§182.026(a)).
- No rows exist, so the rebuild is a replacement, not a migration.

## 4. Known limits carried forward

- Kyle's batch 2 answers outside the tax work but in this stream's tables go to their own items, not to -30: the silent city's backbilling default and pre-go-live approvals (answers 10–14) to the backbilling tariff table; the keying-error cause and its borrowed six-month limits (answer 15) to the backbilling law rows; gas corrections at historical rates with no per-customer override (answer 17), once its table's owner is checked.

- Matching addresses to jurisdictions from the Comptroller's address file is the application's job; a proposed membership is written with its evidence (`address_lookup`), as today. Whether proposed memberships also need a draft state is settled with -32.
- The gross receipts tax is not a law-row line (triage 15).
- A tax exemption does not stop the franchise fee: the default, to confirm with Kyle (triage 10).
