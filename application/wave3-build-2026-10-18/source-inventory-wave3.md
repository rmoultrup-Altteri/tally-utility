# Wave 3 source inventory: disputes and collections decision records (2026-10-18)

**Authority:** Ryan, 2026-10-18: "no answer yet, start the wave-3 inventory". The wave's content is `application/step1-sequencing-2026-10-13.md` (wave 3): CI-074, 067, 069, 075, 071, and the dispute side of 054. Kyle, 2026-10-15: "wave 3 needed K-07 only" (municipal utilities enter their own rules, with no assumed defaults).

**Status:** inventory. Q1 answered by Ryan 2026-10-18 (the default: rule entries); nothing open. Everything else is settled by a ruling or a standing rule, and each settlement names the one it rests on.

**Build order:** the dispute record reads bill positions from -23 (`invoice_position_as_of`, `invoice_line_position_as_of`). -23 r3 changes refunds and credits, not those two functions, so -25 can be drafted on top of -23 r2. It can't be mirrored until -23 has mirrored.

**Research files** (in `sources/`; every claim in them cites file:line or a URL):
- `gbm-sources.md`: the register entries, Appendix A-14/A-15, the decision tables and every relevant Kyle ruling (GBM at `bab1da5`).
- `live-schema-at-22.md`: the live catalog at -22, table by table, plus the patterns to copy.
- `law-sources.md`: the law, labelled verified, mirror, secondary or unverified. Fetched texts are in `law-text/`.

## Sources

| Tag | Source | What it settles |
|---|---|---|
| CI | GBM register: CI-074, 054, 067, 069, 071, 075 (and 068, 070, 078–085 where they bear) | The invariants' statements. CI-074: suspend collection on the *disputed portion* only; the undisputed part stays collectable. CI-067: one funnel, a recorded and reproducible eligibility decision. CI-069: every bypass that is active halts the step; the set is jurisdiction data. CI-075: decisions are pure in (account state, rule version, evaluation date), carry their inputs, and are idempotent on re-run. CI-071: the field captures meter serial and service point against the order's expected values; a mismatch halts. |
| A | GBM Appendix A-14, A-15 | A-14: per-jurisdiction step and bypass configuration, and a versioned eligibility rule set. A-15: a per-amount `disputes` table with recognized grounds and resolution lineage. Neither appendix has a per-decision record. GBM's own decision table calls that "the single most consequential structural gap in Domain 11 … not in Appendix A" (`disconnect-eligibility.md:77`). |
| K-1015 | GBM `kyle-decisions-2026-10-15-…` | Standing rule: each jurisdiction owns dated rule sets with citations, Texas is data, and rules attach per service location. K-07: municipal rules are entered per utility, with no assumed defaults. R-11: late fees and program exclusions become dated rule data (wave 7). |
| K-0710 | GBM `wu5-wu6-kyle-decisions-2026-07-10.md` | Q-6: the Texas bypass list is final without family violence. EWE (the Texas extreme-weather shutoff ban) is self-executing, at or below 32 °F, county-level, with no heat leg for gas. D9-1: a disconnect with no photo needs supervisor approval, recorded as an event with a reason code. D8-1/2/3: plan breach is terminal (with a grace window); bankruptcy holds end on a court event, not a date; at most one active plan per account. D3A-1: the field tool is external and uses the same API as any third-party tool. |
| K-A2 | GBM `kyle-decisions-2026-09-02-a2-…`, `-09-22-…`, `-09-23-…` | §7.45(6)(D)(ii), the shelter: the customer need not pay the disputed portion above their average usage until resolution or 60 days from issue, whichever comes first. The enforceable bounds (`never`/`months`/`uncapped`) are handed to collections. F-1: meter-error backbills can't drive a disconnect. R-26: municipal rows only where an ordinance differs; most-specific wins; fail toward protection. |
| K-CCK | GBM `kyle-decisions-2026-09-02-customer-class-keying.md` | Risk asymmetry: under-protection is a regulator exposure and over-protection a receivables cost, so every ruling resolves toward protection. Grain: a disconnect notice is per meter or service, a seriously-ill hold per premises, a payment plan per bill. Protection decisions read the latest approved row, so an inquiry gets the exact figures the decision rested on. |
| K-0826 | GBM `kyle-decisions-2026-08-26-coda-items-4-7.md` | 5.1: shutoff notices record the delivery method (mail or hand delivery), checked against the event type. Coda item 6 (agency pledge as a bypass) is unruled. |
| CRAFT | *Memphis Light, Gas & Water v. Craft*, 436 U.S. 1 (1978); TML Legal Q&A | **Binds our first customers.** Federal due process: before a city utility cuts service, the customer can protest to an employee with authority to cancel the cutoff, and the notice says how. |
| TX-GAS | 16 TAC §7.45(6)(D), (2)(B)–(D), (4); §7.460; Util. Code §104.258 | The gas rules for investor-owned utilities and unincorporated areas. They don't bind city-owned systems (memory `texas-muni-outside-gura`). The §7.45(6)(D) shelter needs four things on the record: a dispute raised before the bill went delinquent, a must-pay cap of two years' same-period average usage at current rates, a 60-day end, and a report of the result. |
| TX-MUNI | Brenham gas tariff Sheet 511 (eff. 2026-10-01); CPS Energy T&C (rev. 2019-03-01); Util. Code ch. 182; Local Gov't Code §552.0025; Gov't Code §2251.042 | Two real city policies with opposite shapes. **Brenham:** the customer pays 100% of the disputed bill; there is no cutoff and no credit damage during the investigation. **CPS:** two stages (a manager's review, then a formal appeal within 30 days, decided within 90); ten subjects that can't be disputed; undisputed charges must be paid. Ch. 182 (customers aged 60+ can delay the due date to day 25 with no penalty) binds city gas systems. Governmental payers may withhold up to 110% of a disputed amount. |
| OTHER | PA 52 Pa. Code ch. 56; FL 25-22.032, 25-7.089; CA Pub. Util. Code §10010; TX electric §25.28–.30 | **PA:** a dispute blocks *issuing* notices, not just executing them; the field tech must abort the disconnect when shown proof of payment, illness or a pending dispute; no late fee on a disputed estimated bill. **FL:** the disputed amount can be set by a regulator's interim estimate. **CA:** cities are bound, with an appeal to the governing body. **TX electric:** the hold lasts through the regulator stage. |
| LIVE | `tally` at -22; -23 r2 | Tables and patterns: see "What exists". |

## What exists (LIVE)

- **No dispute record.** Invoices have no dispute columns. `invoices.status = 'held'` only exists before a bill is issued. The program type `pending_dispute` (`is_disconnect_protective = true`) protects the *whole account*, which is the blanket suspension CI-074 names as a failure. The only per-item dispute fields are six free-text columns on `meter_readings` (`dispute_*`), which can be overwritten after billing.
- **`dunning_events`.** Add-only since -19, written by the app. Rows cite no rule, no inputs and no decision. `event_date` is whatever the caller sends. Customer, invoice and tenant are bound by single-column FKs, so nothing makes them agree. Nothing refuses a duplicate step.
- **Projections with no guard.** `invoices.dunning_stage`, `late_fee_assessed`, `late_fee_amount` and `customers.do_not_disconnect` can all be written by the app after issue. `do_not_disconnect` is kept in step with enrollments by `recompute_do_not_disconnect`, but nothing refuses a direct write.
- **`service_orders`.** No captured meter serial or service point, no outcome, no status-transition guard, and no link to the dunning step or decision behind a disconnect. The app holds whole-row UPDATE.
- **Rule terms.** The registry has backbilling, deposit and deposit_tariff only. The typed "disputed" and collection-limit vocabulary already exists in three places: deposit `exclude_disputed`, deposit return `hold_while: dispute_pending`, and backbilling `enforcement`.
- **Weather.** The `weather_station` place fact exists per county. There is no observation or forecast table.
- **Patterns to copy.**
  - `deposit_return_due`, the closest template for a decision record: written by the core, cites its rule, inputs and fingerprint, uses a sequence, and supersession and withdrawal are add-only rows (tu.sql 35836–36161).
  - `meter_correction_holds`: opens once and closes once (25516).
  - -23's `status_cause_id`/`status_recorded_at`: every status move names its cause.
  - `meter_tests.meter_serial_at_test`: a field value recorded as observed (22381).
  - `rule_row_cite`: a cite lock on the rule row a decision rests on (29465).

## Proposed split: two patches

The wave is M–L. Split by dependency and migration cost (memory `frame-shapes-by-migration-cost`):

- **v5.4.2-25, disputes (additive, plus two small meaning changes on empty tables).** D below. It goes first because every collections decision reads it.
- **v5.4.2-26, collections decisions and field verification (additive, plus tightening on `dunning_events`, `service_orders` and the projections).** E and F below.

(-24 stays the cash follow-up, U and L. It waits for -23 r3.)

## v5.4.2-25: disputes

### D: the dispute record (CI-074, CI-054 dispute side; CRAFT, TX-GAS, TX-MUNI, OTHER)

- **D1. `disputes`.**
  - **Fields:** tenant, customer, the bill disputed, and the subject category (meter accuracy, rate application, calculation, service not rendered, identity theft, responsible party, other: CI-074's grounds plus PA's). Also when it was received (as the customer dated it) and the channel. The database stamps `recorded_at`.
  - **Writes:** add-only. Status is `open → resolved | withdrawn`, and each move names its event (-23 pattern).
  - **Sources:** every one in the table. CRAFT alone makes it binding for city systems.
- **D2. `dispute_amounts`.** An add-only, dated series. Each row holds:
  - the disputed amount;
  - who set it: customer claim, agreed, utility determination, or regulator interim estimate (FL);
  - optionally the bill lines it falls on (per amount, A-15).

  The latest row as of a recorded instant is the dispute's amount. A revision is a new row.
- **D3. `dispute_determinations`.** The core's reading of the shelter, written when it changes (memory `design-permanent-record-on-change`):
  - **The figures:**
    - the sheltered amount;
    - the amount that must still be paid, and its basis (undisputed charges, an average-usage cap, the full bill, or a withholding percentage);
    - the figures behind it (e.g. the two-year average and the rates used).
  - **The eligibility facts:** whether the dispute was raised before the bill went delinquent, and the shelter's end rule and date.
  - **What the shelter blocks:** notices, disconnects, late fees, credit reporting.
  - **Its citations:** the rule row it applied (`rule_row_cite`), the core version, and the inputs with their fingerprint.

  Copied from `deposit_return_due`. The schema stores the result; the core evaluates (memory `schema-represents-core-evaluates`).
- **D4. `dispute_events`.** Add-only:
  - opened;
  - stage advanced (with stage number, the decider's role, and the filing and decision deadlines);
  - escalated (to the regulator or the city's governing body);
  - decided;
  - resolved (`sustained | adjusted | waived | withdrawn`);
  - reopened only as a new dispute.

  CPS, TX electric, PA and FL all need stages. The outcome list stays open-ended enough for the meter-test paths Kyle hasn't settled (GBM O14). An `adjusted` resolution names the correction it produced (the -21 rebill or -22/-23 adjustment).
- **D5. A reader**, `dispute_shelter_as_of(bill, on, recorded)`: the sheltered amount per bill and line as of a date, with both coordinates required and no fallback to live columns (memory `temporal-helper-no-live-fallback`). The late-fee base, the notice amount and the eligibility inputs all read it.
- **D6. Dispute terms as rule data.** A `dispute` terms kind: a law table plus a tariff table, registered under the rule-terms convention. Each row's terms hold:
  - the recognized grounds and the excluded subjects (CPS);
  - the must-pay strategy and its parameters;
  - the shelter's start test and end rule;
  - the stages and their deadlines;
  - what the shelter blocks.

  Texas gas is one law row (§7.45(6)(D)). Brenham and CPS are tariff rows. A city with no tariff row has no dispute terms, and the core's decision says so (K-07: no assumed defaults). **Q1, answered: build it in -25.**
- **D7. `pending_dispute` stops being a protection.** Its `is_disconnect_protective` becomes false and the description points at `disputes`. A dispute protects the disputed amount, not the account. **Settled by rule:** CI-074 and A-15 are newer and more specific than A-11's seed. This is a meaning change on a seed row with no enrollments behind it today.
- **D8. `meter_readings.dispute_*` retire.** A read dispute becomes a `disputes` row naming the reading. The six columns go, along with their place on the editable list for a consumed read. **Settled by rule:** dispute state is a record, not a field the app can overwrite (R-05's add-only principle; memory `guard-the-act-not-the-label`). The table is empty.

## v5.4.2-26: collections decisions and field verification

### E: the decision record (CI-067, CI-069, CI-075; CI-070's link)

- **E1. `collections_decisions`.** The core writes one row each time it decides whether a collections act may happen. Each row holds:
  - **the act:** a notice, a late fee, issuing a disconnect order, executing a disconnect, or a collections referral;
  - **the subject**, at Kyle's grain (CCK-7): the bill for a notice or late fee; the customer, location and meter for a disconnect;
  - **the evaluation date;**
  - **the outcome:** `eligible | blocked | unevaluable`;
  - **every condition that was active**, plus the one credited as the cause (CI-069 composes conditions, and the rank is only for attribution);
  - **how long it holds:** `valid_until`;
  - **its citations:** the rule rows cited, the core version, and the inputs with their fingerprint.

  The database stamps `recorded_at`. Add-only; a later decision supersedes an earlier one, as with `deposit_return_due`.
- **E2. Idempotent by key.** Unique on (tenant, act, subject, evaluation date, inputs fingerprint):
  - **Same inputs, same date:** a re-run is refused, which is CI-075's "recognizes already-emitted events".
  - **Changed inputs** (a payment arrived, say): a new row.

  That also gives "a row only when the answer changes" without a sweep log. Volume is one row per proposed act, plus one when a due act is declined.
- **E3. A blocked decision is the bypass trace.** GBM's ask for `bypass_applied` events (O2) is met by the `blocked` row itself. `dunning_events` gets no new types for it.
- **E4. `unevaluable` blocks.** A missing input (no weather data yet, no county, no staffed-days calendar) is an outcome, never `eligible`. **Settled by rule:** fail toward protection (K-CCK, R-26, R-30). No law says it; it is a design rule and is written down as one.
- **E5. Acts cite their decision.** An act cites an `eligible` decision for the same act and subject, whose `valid_until` covers the act's date:
  - `dunning_events` of type `shutoff_notice_sent`, `late_fee_applied`, `shutoff_scheduled`, `disconnected` and `sent_to_collections`;
  - a `late_fee` one-off charge;
  - a disconnect `service_order`, both when it is created and when it completes.

  The completion cites a separate **execute** decision, which is CI-067's "every disconnect path consults it" and GBM rank 0 (no relying on the decision made at issue). This is record integrity (which decision authorized the act), not evaluation: the database checks that the citation exists and matches, never the rule.
- **E6. `dunning_events` hardening** (CI-075):
  - customer, invoice and tenant are bound by composite keys;
  - unique on (decision, event type), so one decision cannot emit the same step twice;
  - `event_date` must fall inside the decision's window.
- **E7. Projections name their cause** (-23 pattern):
  - `invoices.dunning_stage` moves only with a `dunning_events` row behind it.
  - `invoices.late_fee_assessed`/`late_fee_amount` go. They are derived from the late-fee charges (wave 2 rule M1: derive, do not store).
  - A direct write to `customers.do_not_disconnect` is refused. Only `recompute_do_not_disconnect` writes it (memory `guards-must-act-not-record`).

### F: field verification (CI-071; D9-1; PA §56.94)

- **F1. `service_order_field_visits`.** Add-only. Each visit records:
  - **arrival:** when the tech arrived;
  - **as observed:** the captured meter serial and service-point identifier, copied from `meter_tests.meter_serial_at_test`;
  - **expected:** the expected values, filled by the database from the order and the meter deployed at the location on that date;
  - **match:** match or mismatch, computed by the database;
  - **outcome:** `executed`, `aborted` (reason: mismatch, payment shown or tendered, medical evidence, dispute pending, no access, safety, other), or `overridden`;
  - **evidence:** references, which may be empty.

  PA supplies the abort reasons. Texas law requires none of them, so for a Texas city they are tariff options, recorded when they happen.
- **F2. An override is a supervisor's act.** A mismatch override or a no-photo execution names the approving user, a reason code and an evidence reference. The database checks the approver's role (D9-1; CI-071's "override without supervisor approval" failure; memory `guard-the-act-not-the-label`).
- **F3. A disconnect order's status is guarded.**
  - It can't reach `completed` without an `executed` visit that matched, or one with an approved override, plus the execute decision (E5).
  - Every other status move names its cause.
  - Applies to the `disconnect` type only. Other order types stay as they are; widening it has no source.

## Settled by rule (reported, not asked)

1. **A dispute protects an amount, not an account** (D7): CI-074 and A-15 are newer and more specific than A-11's seed.
2. **Dispute state is a record, not editable columns** (D8): R-05's add-only principle.
3. **The schema stores decisions; the core makes them** (D3, E1, E5): memory `schema-represents-core-evaluates`. The database checks that an act cites a matching decision, never the rule.
4. **One decision row per change, not per check** (E2): memory `design-permanent-record-on-change`. The unique key enforces it.
5. **Unevaluable blocks** (E4): fail toward protection, recorded as a design rule.
6. **No Texas default for a city** (D6): K-07. A city without a tariff row has no dispute terms, and the decision records that.
7. **Late-fee counters on the bill are derived** (E7): wave 2's M1.
8. **Field abort reasons come from PA, not Texas** (F1): a real source in another state counts (memory `launch-scope-is-not-architecture-scope`). They are vocabulary, not obligations.

## Not in wave 3 (where each goes)

- **Weather observations and forecasts, the EWE rule rows, the staffed-days calendar and the medical-hold rows:** wave 7 (CI-079, 080, 081 law rows). Until they exist, a decision that needs them is `unevaluable` (E4).
- **The late-fee rule rows** (rate, base, cap, grace, exempt programs): wave 7 (R-11). Wave 3 supplies only the dispute shelter they read.
- **Bypass-set membership per jurisdiction** (which conditions count): rule data, wave 7. This includes whether an agency pledge or `elderly_disabled` is a bypass (GBM O4, O5; Kyle's coda item 6).
- **Notice content, delivery confirmation, posted notices, contact attempts** (PA §56.93–.96): wave 5, communications.
- **Bankruptcy and estate records** (A-15's other half): wave 4 (CI-082–085; R-08).
- **Enrollment history and `recompute_do_not_disconnect` ignoring end dates:** wave 4 (R-07).
- **Governmental payers** (Gov't Code §2251: 21-day window, 110% withholding, interest instead of a late fee): a payer-type shape for wave 7's late-fee rows. Recorded here because the dispute terms (D6) need a strategy for it.

## Residuals (no source; recorded, not built)

- Photo evidence as a requirement. D9-1 rules only on what happens without one, and F2 records that.
- Reconnecting customers already cut off when an EWE starts (GBM O12).
- An installment-agreement breach ending a medical hold early.
- A Texas arrears floor, a Texas door-step contact or a pre-disconnect call attempt.

## For Kyle (not blocking)

Found by the law research. Each one corrects a GBM decision table, and none changes what wave 3 builds.

1. **The "day-26" elderly bar is misread.** GBM's disconnect-eligibility table blocks a disconnect when the calendar day of the month is 26 or later. Util. Code §182.002 says something else: a customer aged 60+ can push the bill's due date to the 25th day after issue, with no late fee. The statute's "26th day" counts days after the bill date and only decides which utilities the law exempts. The exemption needs a utility regulated under Title 2, which covers electric and telecom, so **a city gas system can never qualify, and the delay binds our first customers.** It belongs in wave 7's due-date and late-fee rows.
2. **The EWE forecast leg likely uses the wrong temperature.** §7.460 says "predicted to remain at or below" 32 °F for the next 24 hours, which reads as the forecast *high*. GBM's table uses the forecast low, which is Georgia's rule. Plain-text reading; no RRC interpretation was found.
3. **The closed-day bar is the utility's own staffed days**, not a fixed weekend and holiday list (§7.45(4)(F), §104.258(b)).
4. **City systems still owe due process.** *Craft* applies to city utilities: before a cutoff, a protest heard by an employee with authority to cancel it. The dispute record (D1, D4) represents it either way. Kyle or counsel may want to confirm that a Texas city's customers have the property interest *Craft* rests on.

## Q1 (answered 2026-10-18: the default): dispute terms as a new rule family

A city's dispute policy, like Texas gas law, has parts that vary: what may be disputed, how much the customer must still pay, when protection starts and ends, the review stages, and what the protection blocks. Brenham and CPS already show opposite answers. The dispute record (D3) has to say which policy it applied.

- **Default:** in -25, add a "dispute" family of rule rows, one law table and one tariff table, under the rule-terms convention we already use for deposits and backbilling. Texas gas is one law row; each city enters its own tariff row. The dispute record cites the row it used.
- **The alternative:** the dispute record stores the policy's figures and a free-text citation, and wave 7 adds the rule rows later. That means a later backfill that rewrites every dispute record's citation, and a "for now" design (memory `design-permanent-record-on-change`).

It comes to you because the sequencing note reserved "extend the convention" to new areas for your call (wave 7). Disputes weren't on that list when it was written.

**Answer.** Ryan, 2026-10-18: "go with the rule entries". -25 registers the dispute family (law table + tariff table), and every dispute determination cites the row it applied.
