# Tax, tax stacking and franchise fees — design (2026-11-05)

**Inputs:** `tax-inventory.md` (what exists, 17 gaps), `tax-triage.md` (18 open points: 16 settled, the franchise base sent to Kyle). **Invariants:** the franchise fee traces to its city (CI-044); each tax on its own base, in its order (CI-045); tax rules dated and replayable (the tax half of CI-001 and CI-004). Kyle's rulings of 2026-10-14 (answers 1–5) and 2026-11-03 (answer 4) govern; Ryan's rules on utility-owned values, percent storage and storage-not-entry apply throughout.

Each shape below says whether it is a schema change or only the core's, and whether it adds or changes meaning (cost of changing it later).

## 1. Patch split

Three patches on the rates side, plus one board note to the money stream. Numbers are names; the order is the build order.

| Patch | What | Waits on |
|---|---|---|
| **-30** | Tax rows keyed to places (the utility's levies, with the published rates as reference); required taxability; exemptions strictly per service type; tax rates in percent; reading places and memberships as known at a past instant; the size-tier defect on rate items; the old customer exempt flag retired | nothing |
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

### 2.7 The old customer exempt flag retired (schema; removes unread columns)

`customers.is_tax_exempt` and its five companion columns are read by no tax path; two reports read them. The reports switch to the exemption table, and the columns go. `customers` is claimed on the board for these columns only.

## 3. -31: franchise fees (after Kyle answers)

- **Keyed to the city as a place** (`place_id`, a municipality, replacing `city_name`), and read from the premise's city membership dated by the boundary, not the sales-tax quarter (triage 3, 4).
- **Rate in percent**, four decimals.
- **Base:** per Kyle's answer: either the base type from a fixed list ("gas sales", "all billed lines") with a rider's exclusion recorded per base, or a required franchise yes/no on each charge.
- **Customer types:** no default; values checked.
- **Reference date** for a mid-period rate change: stored on the rule, with no default (the app offers period end, Kyle D6-1).
- **The street-use ceiling** (Tax Code §182.025, 2% of gross receipts) as a reference value with a discrepancy report, not a refusal: franchise contracts may pay more (§182.026(b)(2)), and a city system does not pay it to its own city (§182.026(a)).
- No rows exist, so the rebuild is a replacement, not a migration.

## 4. Known limits carried forward

- Matching addresses to jurisdictions from the Comptroller's address file is the application's job; a proposed membership is written with its evidence (`address_lookup`), as today. Whether proposed memberships also need a draft state is settled with -32.
- The gross receipts tax is not a law-row line (triage 15).
- A tax exemption does not stop the franchise fee: the default, to confirm with Kyle (triage 10).
