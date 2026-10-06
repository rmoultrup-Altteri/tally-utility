## Part 6: our own sources (tu.sql at the -14 build; docs)

| Where | What it holds | Whose fact | Problem |
|---|---|---|---|
| `service_locations` (tu.sql 4440–4470) | `city`, `county`, `state` (free text, NOT NULL except county), `zip`, `latitude`/`longitude`, `parcel_id`, `inside_city_limits boolean DEFAULT true`, `franchise_city text`, `jurisdiction_id` (11606) | Place facts (city, county, state, inside limits) stored as text per premise | No validation; no dates (annexation silently rewrites history); `inside_city_limits` defaults true; franchise city is free text and duplicates `city` semantics |
| `jurisdictions` (11569–11604, v5.4.0-03) | tenant-scoped code/name/description + `wna_applicable`, `wna_zone_id`, metadata | Mixed: name = the place's; WNA = the utility's | The 2026-09-22 note (GBM `jurisdictions-shared-place-modelling-2026-09-22.md`): two utilities in one city hold two unrelated rows; no Inc/Env flag (CI-093 open); not a municipality in every case (unincorporated county, franchise area) |
| `franchise_fee_rules` | tenant-scoped `city_name text`, `fee_percentage`, applies_to, dates, `ordinance_reference` | The city's ordinance, applied by the utility | City named by text, not a place; no link to `jurisdictions` |
| `wna_zones` / `wna_zone_versions`; `rate_schedule_items.wna_zone_id`, `franchise_city`, `regulatory_authority` (4185–4190) | The utility's tariff variants by zone; regulator as free text on a rate item | Utility's (zones); regulator is law's | Regulator free text, per rate item |
| `communities` | tenant-scoped developments (`city`, `state`, `zip` text) | Utility's | Duplicates place text |
| `tenants` (4595–4603) | `city`, `state`, `zip` — mailing address | Utility's | Audit: never read for law (it was, in -06's deposit guard) |
| `customer_tax_exemptions` | per customer, `issuing_authority` text | Customer's certificate | Authority not a place; no tax-jurisdiction table exists (A-8 gap, tu.sql 11598) |
| `America/Chicago` (tu.sql 19184, -07 state-agency as-of) | day boundary hard-coded | Place's time zone | Wrong for El Paso / Hudspeth (Mountain time) |
| Law tables: `deposit_rules`, `backbilling_rules`, `meter test thresholds` (`state_code`), `regulatory_surcharge_service_locks.state_code` | key on `state_code` only | Law's | No sub-state place, no utility type (a2-rules-for-the-core §789 / R-26: "state-level now, a place key when the places table lands") |

Design sources:
- Ryan, 2026-09-22 (GBM note above): shared places, `jurisdictions` keeps per-utility config with an optional pointer; owner of the shared list, annexation and incorporation named as open costs; routed to A-8.
- The note's observation: 16 TAC §7.45's preamble scopes it to unincorporated areas and has utilities fold the same standards into service rules for incorporated areas — relevant to K10.
- Audit §3.1 rows (state from the premise; validated state; Inc/Env as Texas place kinds; regulator per state and service; time zone from the place; service type as a stand-in for the regulator).
- R-26 (A-2): regulatory and tax jurisdiction are separate axes and separate tables.
