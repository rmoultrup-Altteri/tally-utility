# Step 1 sequencing — pricing and ordering the 80 open invariants — 2026-10-13

**Input.** `application/invariant-parity-measurement-2026-10-13.md` (61 PARTIAL, 12 GAP, 7 BLOCKED). The finance gate is resolved since that document was written (D-2 accepted for receivables and reporting), so CI-048, 076 and 110 move from BLOCKED to buildable. The gas-cost side (CI-033, 036) remains fenced for Kyle.

**Pricing terms.** Size: S = a column, CHECK, default or trigger on an existing table; M = a new table with its guards, or several S fixes touching one area; L = a new subsystem or a change in the grain of an existing table. Migration cost: *tightening* (a new refusal on an existing table; free while the tables are empty, needs a backfill and a cleanup once data exists), *additive* (new table or nullable column; cheap at any time), *meaning-changing* (the same row now means something else; expensive later; settle before data exists).

**Spot check (2026-10-13, live `tally`).** Re-verified before relying on them: `prorate_tier_breakpoints` default false; `payments` has `source_system` and `provider_transaction_id` with no unique key on them; `anomalies.dedup_key` nullable; `escheatment_events`, `ai_audit_log` and `dunning_events` carry only no-delete/no-truncate triggers while `tally_app` holds UPDATE; `rate_item_dependencies` has no triggers; `customer_is_state_agency_as_of` hardcodes `America/Chicago`; `account_balance_as_of` absent; `populate_reading_calculations` fills `consumption = (reading - previous) * multiplier` with no rollover branch; `enforce_reading_validation_workflow` Block 2 keys the freeze on `OLD.validation_status = 'locked'`, so a `void_released` read (lock flag still true) is writable.

## The order

| Wave | What | Invariants | Size | Migration cost | Needs a ruling? |
|---|---|---|---|---|---|
| 1 | Close holes in what is already built | 010, 019, 022, 025, 031, 041, 052, 055, 057, 058, 062, 068, 096 (hash), 098, 099, 101, 106*, 108, 118, 126, 127, 128 | M (about 20 S fixes, one patch) | Tightening: cheapest now | No |
| 2 | Finance-released structures and cash handling | 110, 048, 076, AR aging (A7), 053, 056, 049 (strategy record + source FK) | L | Additive | No (earmarking in 049 waits on Kyle's Q-5) |
| 3 | Disputes and collections decision records | 074, 067, 069, 075, 071, 054 (dispute side) | M–L | Additive + tightening on `dunning_events`/`service_orders` | No (070's override policy and 072's safety checklist wait on people) |
| 4 | Program enrollment lifecycle | 065, 082, 083, 084, 060, 081 (link) | M | Tightening on a live-shaped table | Yes: Ryan (transition record; lapse by date) |
| 5 | Communications | 094, 095, 135, 088, 093, 097 (language), 111, 096 (retention) | L | Additive | 135's breach consequence: counsel |
| 6 | Rate-assignment and occupancy history | 133, 104, 120, 087, 001/004 (meter-parameter history) | L | Meaning-changing (scalar → dated history) | 120's shape: Ryan; 027 relocation: Ryan/Kyle |
| 7 | Rule-terms extensions | 114, 054 (late-fee rows), 043, 105, 079, 080, 081 (law row) | M | Additive (new registered rule tables) | Yes: Ryan (extend the convention) |

\* 106 is REP in the measurement but carries a cheap hardening (coverage CHECKs); included because it costs one line.

**Why this order.**
1. Wave 1 is all tightening on tables that are empty today. Each item is cheap now, and each becomes a backfill plus a cleanup after the first tenant loads data. No ruling is needed, and every item is a guard that should already act (several are holes in guards that exist).
2. Wave 2 is unblocked as of today's finance decision and sits on the money path that every later wave reads.
3. Disputes come before enrollments because the eligibility record (067), the bypass inputs (069) and late fees (054) all need a per-amount dispute to exist.
4. Communications come after collections because the notice log is what 088, 093, 097 and the reclassification notice in 104 complete against; building it after the events it logs keeps it from being designed blind.
5. Waves 6 and 7 change meaning or need a decision first, so they wait for those calls; the calls can be asked one at a time while waves 1–3 are built and reviewed.

## Waiting on Kyle (not sequenced)

011 (concurrent-assertion surfacing, Q-1), 020 and 026 (zone model), 030 (canonical supersede column), 033 and 036 (gas-cost side, in the brief), 037 (transport/sales vocabulary), 038 (surcharge cap figure), 044 and 045 (tax jurisdictions, in the brief), 089 (early-pay discount), 091 (meter-test fee binding), 097 (accessibility format set), 109 (tariff rounding).

## Ryan's calls (to be asked one at a time, in plain language, when the wave that needs them comes up)

- Before wave 1 closes: which charge types must carry rate and coverage when issued (016); force every reversal to name what it reverses (017); which configuration tables lose DELETE (014); seal reference-version bumps behind a definer function (011's buildable half).
- Before wave 2: payments, credits and ad-hoc charges append-only (013, meaning-changing, L); payment application per charge instead of per invoice (050, meaning-changing, M).
- Wave 4 and later: as in the table. Also 116 (tenant-bound foreign keys on 267 edges, L, tightening) and 085 (deceased customer: status or protective enrollment).
- Counsel: PAN-shaped strings refused or redacted (051).

## Accounting check

Each of the 80 open CI numbers was checked by script to appear at least once above. Some appear in two places on purpose (054, 096, 097: part buildable, part waiting); 106 is not open and is included only for its hardening.
