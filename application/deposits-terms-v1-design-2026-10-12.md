# Deposit rule-terms v1: design pass against the survey gaps (2026-10-12)

Status: design draft, not built, not reviewed. Nothing here has been run against the -17 validator; every construct below must be checked against the validator's JSON Schema subset before the schema file is written (section 6).

Inputs: the -15 draft (`sql/v5.4.2-15-deposits-law-to-core.sql`), the backbilling kind (`law/backbilling/backbilling.v1.schema.json`) as the model, and the 29 gaps in `deposits-source-survey-2026-10-06.md`.

## 1. Decisions this design follows (Ryan, 2026-10-12)

1. Customer type stays on the utility's own interest rate (nullable); the published reference rate has none.
2. The utility's own deposit rules are ONE tariff record per utility, state, service and customer type (cap, thresholds, extra waivers together).
3. v1 scope: vocabulary additions + a flexible condition language + an interest-method union are IN. Periodic recalculation, bill-anchored instalments, sum-of-parts caps with add-ons, guarantor caps, municipal funds/escheat are OUT (written down below). Only Texas is seeded; other states' rules are test cases.
4. A state-set interest rate is a FLOOR the utility's own rate cannot go below; a rate below the floor that binds that utility is refused when written; a missing published rate refuses (unknown law is not permission); city-owned systems the law does not bind get no floor.

## 2. Shape of the law document, kind `deposit` v1

Same envelope as backbilling: a `oneOf` of `law` and `delegated` (the law leaves this to the utility, with a citation). The `law` branch has these sections. All are closed objects; absent is never "none" (an empty list or an explicit `none` strategy is written).

- `cap`: strategy union.
  - `none`.
  - `parts`: `combinator` (`single` | `lesser_of` | `greater_of`), `scope` (`per_deposit` | `combined`), and a list of parts, each a kind plus its figure: `fraction_of_annual_billing` (divisor), `months_of_billing`, `fixed_amount` (existing), plus new `highest_bills` (count, window months) and `seasonal_average` (months of season, multiple). Each part has a stable id (the deposit records which part governed).
- `triggers`: a list, one per additional-deposit trigger the law allows. Each has a `trigger_code` (vocabulary), a `condition` (section 3) and `guards` (section 3).
- `waivers`: a list of reach entries: `waiver_class`, optional `trigger_code`, `effect` (`excuse` | `reduce` fraction | `defer` days), optional `also_releases_held` (boolean: a held deposit is released too), optional `disqualified_by` (condition) with lookback.
- `interest`: strategy union.
  - `none`.
  - `bearing`: `instruments` (list); `rate` (below); `method` (`simple` | `compound` with `period`); `day_count`; `hold` (a union: `none`, or `minimum` with `days` and `retroactive`); `credit` (`at_refund` | `annual` | `on_bill` | `calendar_date` with month/day, plus `customer_may_elect_cash`); `stops_on` (vocabulary list: refund, service_terminated, good_faith_return_attempt); `forfeited_on` (vocabulary list: disconnect_nonpayment); optional `penalty` (rate and the event that starts it: `refused_demand`); optional `rounding` (nearest fraction).
  - `rate`: strategy union. `published` (a published-value name; optional `by_hold` list of up-to-months and name, for rules whose rate depends on how long the deposit is held), `fixed` (a stated rate), `utility_sets`. Each carries `binding`: `minimum` (a floor, decision 4) or `reference` (no floor). The floor applies only where the law row binds the utility's owner type.
- `return`: a list of return rules, each with a `reason_code` (vocabulary), a `condition` (section 3), `instruments`, optional `minimum_amount`, optional `deadline_days` after the qualifying event, optional `hold_while` (a vocabulary list, e.g. `dispute_pending`), and `vests` (stays owed once due; `unruled` allowed). Reasons: clean bill history, hold term elapsed, account closed, excess over cap (partial), on customer demand, N days after disconnection, customer enters a waiver class, excess over current bill (partial, on request).
- `instalments`: fixed schedule only (fraction, days after the determination), as -15 already has.

## 3. The condition language (the part that must be right first time)

A condition is a small tree, depth capped by -17's nesting limit:
- `count`: `event` (vocabulary: nsf, late_payment, final_notice, disconnection, broken_arrangement, missed_shutoff, ...), `at_least`, `window` (months or bills), optional `consecutive` (boolean), optional `exclude_disputed`.
- `ratio`: `measure` (`usage_to_estimate`, `final_bill_to_class_average`), `at_least`.
- `all_of` / `any_of`: lists of conditions.
- Delinquency is a named definition the `count` may use: `unpaid_after_next_bill` or `partial_payment_fraction` (e.g. under one half of arrears).

Guards on a trigger (all optional, all closed): `not_after_service_months`, `not_if_moved_within_days`, `assess_within_days`, `notice_days`, `payment_due_days`, `cured_by` (a vocabulary entry such as a kept payment arrangement entered before assessment), `not_after_cumulative_service_years_since` (the Arkansas tampering rule).

Why a tree and not columns: consecutive runs, either/or, both/and and expiry are four of the ways the survey's states combine events; a count-in-window column pair covers only Texas.

## 4. Every survey gap

IN means v1 holds it; OUT means a recorded residual with what it would take.

| Gap | Rule in plain words | Disposition |
|---|---|---|
| G1 | Extra trigger events (late payment, final notice, missed shut-off, tampering, bankruptcy, service change) | IN: vocabulary rows |
| G2 | Rate depends on hold period; change band | IN: `rate.by_hold`. The change band is not in the document: the published value is entered only when it moves past the band (a data practice, noted in the published-values loader) |
| G3 | Return depends on deposit size and years of tenure | IN: return condition `ratio`/`count` extended with `deposit_below_amount` and `service_years_at_least` |
| G4 | A statute fixes the rate | IN: decision 4; `rate.binding = minimum`, `fixed` rate |
| G5 | Penalty after a refused demand; return on demand | IN: `penalty`, reason `customer_demand` |
| G6 | Minimum refund amounts; excess over current bill | IN: `minimum_amount`; partial reason `excess_over_current_bill` |
| G7 | Consecutive, either/or, both/and thresholds | IN: condition tree |
| G8 | Triggers expire with account age | IN: guard `not_after_service_months`, `not_after_cumulative_service_years_since` |
| G9 | Cap bases: highest bills, seasonal, peak | IN: cap parts `highest_bills`, `seasonal_average` |
| G10 | Cap plus an add-on (equipment damage, diversion) | OUT: needs a `sum` combinator and a non-billing add-on part |
| G11 | Instalments anchored to bills, or by minimum/maximum term | OUT: needs a bill-anchored schedule and a schedule that depends on the size basis |
| G12 | No re-assessment on a move within N days | IN: guard `not_if_moved_within_days` |
| G13 | Disputed bills excluded; refund held during a dispute | IN: `exclude_disputed`, `hold_while` |
| G14 | Events that stop interest | IN: `stops_on` |
| G15 | Guarantor liability caps differ from cash cap | OUT: guarantor cap is a separate figure on the instrument |
| G16 | Credit on a calendar date; customer may take cash | IN: `credit.calendar_date`, `customer_may_elect_cash` |
| G17 | Separate municipal deposit funds; escheat | OUT: accounting for how a municipality holds money, not rule terms |
| G18 | Recalculation after a bankruptcy discharge | OUT: recalculation event |
| G19 | Periodic two-way recalculation with a tolerance band | OUT: recalculation event; a deposit would change both ways over time |
| G20 | Assessment deadline; notice period | IN: guards `assess_within_days`, `notice_days` |
| G21 | A cure by customer action cancels a trigger | IN: guard `cured_by` |
| G22 | Mandatory return N days after disconnection | IN: reason `days_after_disconnection` |
| G23 | Return when the customer later enters a waiver class | IN: reason `entered_waiver_class` |
| G24 | Threshold relative to a utility-wide average | IN: `ratio.final_bill_to_class_average` (the core supplies the average) |
| G25 | Delinquency by partial-payment fraction | IN: named delinquency definitions |
| G26 | A waiver with its own disqualifier and lookback, and release of a held deposit | IN: `disqualified_by`, `also_releases_held` |
| G27 | Monthly compounding; monthly-varying rate | IN: `method.compound` with `period`; `rate.by_hold` is not used, the published value is monthly |
| G28 | Interest forfeited on disconnection | IN: `forfeited_on` |
| G29 | Refund deadline in days | IN: `deadline_days` |
| Ohio | Cap is a sum of parts | OUT with G10 |
| Arkansas | Cap depends on prepaid/postpaid and landlord status | IN as customer classes (vocabulary), not document fields |
| Illinois | Rate rounded to nearest 0.5% | IN: `rounding` |

Tally: 23 IN, 6 OUT (G10, G11, G15, G17, G18, G19, plus Ohio's sum with G10), 3 borderline handled as above.

## 5. The utility's tariff record, kind `deposit_tariff` v1

One record per tenant, state, service, system kind and customer type (decision 2). It holds: `cap` (same union as the law's, so the comparator can compare like with like), `triggers` (same condition tree), `waivers` (extra grounds the utility grants, each with scope and effect), and `instalments`. A tariff cap stricter than or equal to the law's passes; a looser one is refused when written. Under a `delegated_to_utility` law row there is nothing to compare, and the core refuses a decision with no tariff record. A deposit cites the law row always and the tariff row when one applied.

The utility's applied interest rate stays its own table (decision 1 and R-D1) with the floor check of decision 4.

Open for the build, not for Ryan: confirm the template's tariff check handles a combined record (decision 2's follow-up).

## 6. Validator check (done 2026-10-12)

Run against the live `rule_terms_schema_errors` / `rule_terms_errors` in `tally` (pure functions, read-only; the script is a scratch file, not in the repo). Results:

- A recursive condition tree (`all_of` / `any_of` holding conditions through `$ref`) is ACCEPTED, and documents nested 12 levels deep validate. The validator caps document depth at 64 levels (about 30 condition levels), far above need. Condition nodes use `kind` as the discriminator, as backbilling's window terms do (a `strategy` property would force a `version` on each node).
- "Both or neither" pairs and "an effect with exactly the figure it needs" must be unions, not paired optional fields: a missing partner, or an extra figure, is refused (tested). So `min_hold_days`/`retroactive` become a `hold` union (`none` | `minimum` with days and retroactive), and a waiver effect is a union (`excuse` | `reduce` with fraction | `defer` with days).
- Refused at registration, so the design must not use them: `enum` or `const` on a number, `anyOf`, `format`, any `pattern` other than the two whitelisted, and null anywhere. Every list of allowed values is therefore a list of strings.
- Rules the schema cannot say go to the area's insert check (as backbilling's "a kind once per direction, in order" does): that each cap part kind appears once, that a cited vocabulary entry exists for the row's state and service (the facet check), and cross-field relations.
- The Python cross-check uses a standard 2020-12 validator, which handles recursive `$ref`; it has not yet been run on this schema because the schema file does not exist.

Not yet tested: facet checks against vocabularies, component ids, and the 64-level cap itself.

## 7. To do before the schema file is written

1. (Done, section 6.)
2. Decide which fields are facets (checked against vocabularies and the row's own key): `trigger_code`, `waiver_class`, `reason_code`, cap part ids, `stops_on`, `forfeited_on`, `hold_while`.
3. Write the tests first, including the other states' rules as fixtures that never enter real data (Oklahoma, Louisiana, New Mexico, Illinois, New York, Arkansas, Kansas, Ohio), and a case for each OUT item showing the refusal is explicit.
4. Re-verify with the official Florida text before any Florida fixture claims to be law.

## 8. The document format as the test fixtures fix it (2026-10-12)

The fixtures under `law/deposit/examples/` and `law/fixtures/deposit-states/` are the contract the schema file is written to; `tests/v5.4.2-15/terms-15.py` fails until `law/deposit/deposit.v1.schema.json` matches them. Differences from the sketch in sections 2 and 3:

- A ratio condition is `{kind: ratio, measure, op: at_least | greater_than, value}` (Arkansas's usage trigger is "more than the estimate", not "at least 1.01 times").
- A count condition is `{kind: count, event, at_least, window: {unit: months | bills, size}, consecutive, exclude_disputed}`. A delinquency definition is an event in the vocabulary (for example `past_due_over_30_days`), not a separate construct.
- Guards are an explicit list of `{kind: ...}` objects (`[]` when there are none).
- A waiver's reach is `applies_to: {kind: any_trigger} | {kind: trigger, trigger_code}`; `disqualified_by` is `{kind: none}` or `{kind: condition, condition}`.
- A return rule is `{id, when: {reason: ...}, instruments, conditions, minimum_amount, deadline, hold_while, vests}`; the reason-specific fields sit inside `when`. `clean_bill_history` carries `exclude_disputed`.
- "The law does not say" is spelled `unruled` where the schema allows it: a cap (`strategy: unruled`), a day count, an interest credit. It is never `none` and never absent. Louisiana's fixture uses it because the Commission's rule was not located.
- A rate is `{kind: published, name, binding, by_hold}`, `{kind: fixed, rate, binding}` or `{kind: utility_sets}`; `binding` is `minimum` or `reference` and is always written (decision 4).

## 9. The database tests (started 2026-10-12)

`tests/v5.4.2-15/battery-15r.sql` is the rewrite's battery, replacing `battery-15.sql` (the first draft's). It is written before the patch and fails first; its blocks are marked `-- rN:begin NAME` so a fail-first runner can run each alone. The first slice is the law side:

| Group | What it proves |
|---|---|
| S | The `deposit` v1 kind is registered with its four facets (trigger codes, waiver classes, return reasons, cap part ids); the vocabularies exist and hold every code the schema and the Texas rows name; the first draft's child tables are not in the database. |
| M | `deposit_rules` is a registered law table keyed by class and basis; the draft's typed content columns and the -06 Texas law (functions and view) are gone; the template's invariants hold. |
| K | The eight investor-owned Texas rows hold exactly the documents -06's truth table gives; a city-owned system gets eight delegations, so its deposit policy is its own tariff. |
| D | The schema's refusals reach the table (including each out-of-scope shape and a rate that does not say whether it binds). |
| X | The area's insert check: each cap part kind once, in order; a single cap has one part, a lesser-of two or more; instalments add up to 1, in day order; a trigger code, waiver class or return reason the vocabulary lacks is refused; a waiver cannot reach a trigger the document lacks; one trigger and one return rule per code. |

Second slice (also in `battery-15r.sql`): C (the utility's own deposit categories, each mapped to exactly one law class; tenant-owned under row security; never edited or deleted), U (the tariff table `deposit_tariffs`, keyed by the utility's own category, measured against `deposit_rules`; successors after a close; the as-of lookup; never edited) and N ("never looser than the law": a flat amount is not compared when written and each deposit's own recorded cap check holds it; months of billing are compared with the law's cap converted to months; a usage trigger may not fire sooner, or give less time to pay, than the law; a trigger or waiver ground the law has no word on is the utility's own).

Third slice (also in `battery-15r.sql`): P (published values: a law row may name only a registered published rate; platform-held; the value in force on a date, with no fallback) and F (the interest floor, decision 4): the utility's own rate row now carries state, service and an optional category (decision 1); a rate below the floor that binds it is refused when written; a floor is the published value in force on the row's own date, or a stated fixed rate; where the law's rate depends on how long a deposit is held, the floor is the highest of its names; a category is held to its own mapped class only, and a rate for every category must clear every class's floor; a rate named only as a reference, or a city the law does not bind, has no floor; no published value in force on the date refuses the rate; a later rise in a published value is not a refusal of the law and is left to the core's audit.

Fourth slice (also in `battery-15r.sql`): R (a deposit cites what it was decided under). A deposit records the state and service, the law class and the utility's own category, the law row (always: a city's delegation row), the utility's tariff row when one applied, the cap that applied with the document it came from and the part that governed, and the core version. Refused: no law row; a law row for another class, basis or owner type, or not in force on the posting date; a statutory cap that names no part of the cited document; a principal above the cap; a carried-history basis; a category that maps to another class or does not exist; under a city's delegation, no tariff row, another category's, one not in force, or another utility's; an additional deposit on a trigger the document lacks or a measure below its threshold; an edit of a deposit's identity; a close of a law or tariff row on or before a date a deposit cites it. Who writes these records (the app now; the core later, per the grant pattern) is left to the patch; the tests write them as the app.

Fifth slice (also in `battery-15r.sql`): A (an interest accrual cites the utility's rate row and the law row it used). The record is held coherent, not recomputed: the rate row is this utility's own for the deposit's state, service and category (or for every category), in effect by the period's start, at the rate cited; the law row is the deposit's own or one of its key in force over the period (a successor after a law change; not another class's); the period has ended and the record is made after it; the principal it was earned on is no more than was held; periods do not overlap; no rate row, law row or core version is a refusal. How much interest is owed, and by what day count, is the core's, from the document.

Sixth slice (also in `battery-15r.sql`): V (the return-due record) and Q (partial returns; the chronology of money and interest). A due row cites the deposit's law row (its own, or one of its key in force on the due date) and carries at least one evidence row at commit. Each evidence row names a return rule of that document (`return_component`, as a deposit names its `cap_component`) and the reason that rule is for, and rests on a record of the reason's own kind (a bill the core judged, the customer's change of state, or the deposit itself). Refused: a document with no return rule that reaches the deposit's instrument (11 U.S.C. 366 has none; Texas returns cash only); a reason that is not the cited rule's; a rule the document lacks; a bill of another customer, from before posting or after the due date; a change of state that is not to a status the reason names, not the customer's own, or not on or before the due date by the UTC day; a second live row for a deposit; a due row once a return has started. A withdrawal states its reason and is made once; a corrected answer names the withdrawn row it supersedes, once; a refund cannot cite a withdrawn row, another deposit's row, or settle a row before it fell due. A partial return (a due row with an amount) needs a document that returns an excess over the cap, leaves something held, rests on a partial reason, and is settled only by a `principal_returned` of exactly that amount. The money chronology (the first draft's groups E and N): no return dated inside a period already accrued; no accrual that spans a partial return or earns on more than was held; interest is credited only once earned; nothing accrues after the principal is used up or from the day a refund started.

The patch keeps the first draft's vocabulary columns on `deposit_return_reasons` that say what a reason rests on (`evidence_kind`, `qualifying_statuses`, `partial`); "which reasons a due row may carry, and for which instruments" now comes from the cited document's return rules. Not decided by the tests: evidence for a clean bill history that counts months rather than bills (the old draft refused it by `requires_measure`; the document now says `measure` only in the clean-history rule).

Seventh slice (also in `battery-15r.sql`): H (history, grants, tenancy, the template's invariants over both tables): a law row is never edited or deleted, closes once and is stamped; the close floor is the latest date any record cites the row for (a deposit's posting, an accrual's period end, a due row's day, a return's day); a utility's tariff row follows the same history rules; the application reads the law and writes none of it; each utility sees its own records only; both tables are registered and the template's invariants hold.

The migration (`migration-15r.py`, on clones of the -18 build): the patch applies to an empty base and to one holding carried `legacy_unknown` deposits, which come through unchanged, cite no law row, return only with a stated reason, and accrue nothing; a second application changes nothing and says so; a real (non-legacy) deposit, a waiver determination or a utility's own rate row stops the patch, naming it (the standing precondition, Ryan 2026-09-28: nothing is live); the -06 Texas law is gone. Not tested: evidence written outside its due row's transaction (needs two transactions; a later script, as the first draft's `evidence-txn-15.sh`).

Contract for the patch's names that the new slices fix: columns `deposit_return_due_evidence.return_component`; function `deposit_rule_close_floor(uuid)`; the view `deposits_return_owed` (columns `due_id`, `deposit_id`, `reasons`, `amount_due`, `remainder`, `deposit_status`); a run-once notice `nothing to do` on a second application.

Still to write: nothing in the tests except the two-transaction evidence script and the mutation runner (`mutations-15r.py`, copied from -18's once the patch exists).

Decided (Ryan, 2026-10-12, decision 5): the tariff is keyed on the utility's own category, `tariff_category`, which shares no column name with the law table's key (the template compares only shared key columns). Each category names the one law class it falls under, and the comparator reads that mapping to choose the law rows.
