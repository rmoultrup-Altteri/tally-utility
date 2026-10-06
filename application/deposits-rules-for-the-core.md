# Deposit rules for the calculation core (2026-10-01)

## 0. What this is

v5.4.2-06 (`sql/v5.4.2-06-account-lifecycle-and-deposits.sql`, landed; tu.sql 17,706–18,822) put Texas's deposit law, 16 TAC §7.45, into triggers, a function and a view: who may be charged a deposit, the cap, when interest accrues, how it is computed, and when a refund falls due. Ryan ruled on 2026-09-28 that **rule evaluation belongs to the C# calculation core, not the database**. The deposits design ([deposits-parity-rescope-2026-09-30.md](deposits-parity-rescope-2026-09-30.md)) lists what stays (§1), what goes (§2), and the platform rule rows that replace it (§3).

This document holds every rule the dropped code enforced, so nothing is lost when v5.4.2-15 strips it. **-06's 141-check battery was lost** (tests/README.md), so this document is also the scenario material that battery would have been. A C# engineer should be able to build the evaluation from this document and the rule tables alone, without reading the PL/pgSQL.

**How each rule is phrased.** Against the *attributes* of the new rule rows (design §3.2, `deposit_rules` per state, service, class and basis), never against a basis name or a state code. Where -06 asked "is the tenant in TX?" or "is the basis `credit_evaluation`?", the rule below names the attribute that replaces the test and gives the Texas seed value. §1 collects them in one table.

**Rule of the house.** The core computes and records: the deposit's rule row, each accrual with its cited rate row and core version, and the return-due record (design §3.5). The database refuses only integrity violations (design §1).

### Sources

| Written as | Means | Where |
|---|---|---|
| `-06 L123` | A line of the -06 patch file | `sql/v5.4.2-06-account-lifecycle-and-deposits.sql` (1,328 lines) |
| `D-34` … `D-43` | Drafting decisions D-2026-08-28-34 … 43 | `application/DECISION-LOG.md` lines 256–284 |
| `CI-125`, `CI-129` … `CI-131` | Canonical invariants (deposit interest discipline; Texas cap and waivers; Texas interest rules; Texas automatic refund) | GBM canonical invariants |
| `#53 rank N` / `#53 rule N` | Decision table *Deposit Eligibility and Waiver* | GBM `application/configurable-rules/decision-tables/deposit-eligibility-and-waiver.md` |
| `#54 rule N` | Decision table *Deposit Refund and Interest* | `…/decision-tables/deposit-refund-and-interest.md` |
| `#55 rule N` | Decision table *Deposit Alternatives and Triggers* | `…/decision-tables/deposit-alternatives-and-triggers.md` |
| `accrual Alt N` / `refund Alt N`, `Exc N` | Workflow alternative and exception flows | `…/workflows/deposit-interest-accrual-cycle.md`, `…/deposit-refund-processing.md` |
| `K1` … `K9` | Questions for Kyle | design §5 |
| `DG1` … | Places where -06 and its sources disagree | §7 below |

Clause references such as "§7.45(5)(C)" are carried from Kyle's research and the decision tables. Nothing here is a fresh reading of the statute.

**Date arithmetic.** A deposit's age on a date is `date − posted_on` in days (-06 L967, L1041). Accrual periods are inclusive on both ends: `[period_start, period_end]`, so a period has `period_end − period_start + 1` days (-06 L553). C# `DateOnly.DayNumber` differences give the same counts.

**Rounding.** -06 rounds **each accrual event** to cents, half away from zero (PostgreSQL `round(numeric, 2)`; C# `Math.Round(x, 2, MidpointRounding.AwayFromZero)` on `decimal`). Interest over a hold is the sum of the rounded events, not the rounded sum. Keep that: splitting at a rate change or an application can change the total by a cent, and the record must reproduce.

---

## 1. The attribute map: every place -06 keyed on a name or a literal

| # | -06 asked… | -06 lines | The core asks instead… | Texas seed |
|---|---|---|---|---|
| 1 | `basis IN ('credit_evaluation','additional_trigger','tariff')`: a waiver blocks it | 865 | the customer's in-force waiver class is on the rule's reach list (`deposit_rule_waiver_reach`), for the deposit's trigger, with its effect (excuse / reduce / defer) | all four TX classes excuse the six §7.45 rules; none reaches §366 (K2) |
| 2 | `upper(tenants.state) = 'TX'` | 876–877 | the jurisdiction from the **premise** (design §3.4), never the utility's home state | — |
| 3 | `customer_type = 'residential'` | 877 | the account's deposit class (`deposit_customer_classes`), decided by the core from the tariff (K1) | residential, non_residential |
| 4 | `instrument = 'cash'` for the cap | 877 | the rule's `cap_kind ≠ none`; whether non-cash counts toward the cap is K5 | cap on residential cash |
| 5 | `cap_amount IS NULL` refused | 877–881 | `cap_kind ≠ none` ⇒ the deposit records the cap that applied — the statute's, or a tighter one from the utility's tariff (`cap_source`) — with its basis; under `cap_scope = combined`, what else was held (`cap_other_held`) | `fraction_of_annual_billing`, 1/6 |
| 6 | `instrument <> 'cash'` refuses interest | 964–966 | `instrument ∈ interest_bearing_instruments` | {cash} |
| 7 | `effective_on − posted_on < 31` refuses an accrual | 967–969 | `interest_min_hold_days` (NULL = from day 1) | 30 |
| 8 | first period must start ON `posted_on` | 978–981 | `interest_retroactive = true` ⇒ first period starts on `posted_on`; false ⇒ on `posted_on + interest_min_hold_days` | true |
| 9 | amount = principal × rate × days/365, rounded per event | 549–555, 1005–1008 | `interest_method`, `interest_day_count` | simple, actual_365 |
| 10 | rate = `deposit_interest_rate_as_of(tenant, period_start)` | 527–547, 988–991 | the utility's rate row in force (R-D1), cited by `rate_id` | the utility's PUCT-rate row |
| 11 | interest credited in full before `refunded` | 1049–1051 | `interest_credit_cadence` (`at_refund` / `annual` / `on_bill`); at refund, all accrued is credited whatever the cadence | at_refund (§7.45 permits annual too, accrual Alt 4) |
| 12 | twelve clean bills, ≤ 2 delinquent, none overdue | 790–819 | `refund_after_count`, `refund_measure`, `refund_max_delinquencies`, `refund_disqualify_on_disconnect` | 12, bills, 2, true |
| 13 | customer `closed / final_billed / inactive` ⇒ refund due | 826, 834 | `refund_on_account_close` (see DG1 for disconnect and DG7 for `inactive`) | true |
| 14 | `basis IN (…)` and `instrument = 'cash'` in the refund-due view | 831–832 | `refund_mandatory` and `return_mandatory_instruments` | §7.45 bases: true; §366: false; instruments: K5 |
| 15 | `waiver_class` CHECK list; family violence needs a certification reference | 575–576 | `deposit_waiver_classes` rows, with `requires_certification` | family_violence_certified (cert), age_65_no_balance, good_payment_history, tariff |
| 16 | `basis` / `trigger_basis` CHECK lists | 621–623 | `deposit_bases`, `deposit_triggers` vocabulary rows | as -06 |

---

## 2. Posting a deposit

**2.1 A waiver in force relieves a deposit it reaches** (-06 L865–874; CI-129; D-40; #53 ranks 0–3; #55 rule 8; v5.4.2-15 review B3).
- A waiver determination is *in force on the posting date* when `determined_on ≤ posted_on` and (`certification_expires_on` is NULL or `≥ posted_on`). Both ends are inclusive.
- Find the rule's reach rows (`deposit_rule_waiver_reach`) for the customer's in-force waiver classes, matching the deposit's trigger (a row with no trigger matches any). Apply the effect: excuse (no deposit), reduce (by `reduce_fraction`), or defer (by `defer_days`). There is no ranking among classes; where several reach, apply the strongest (excuse, then the larger reduction, then deferral) and record which one.
- -06 did not ask which class: every class blocked every §7.45 basis. The Texas seed reproduces that (24 reach rows) and gives §366 none (K2: Kyle's answer is a close of the two §366 rules and successors with reach rows).
- A **tariff** waiver (a class marked `tariff_defined`) rests on the utility's own ground (`deposit_tariff_waiver_grounds`), which carries its own scope (bases, customer classes, triggers) and effect. It relieves a deposit only where the law's tariff class reaches the rule **and** within the ground's scope.
- This includes an additional-trigger deposit: a waiver attaches to the person, a trigger to behaviour, so the waiver is re-checked when a trigger fires (#55 rule 8).
- A determination is a recorded point-in-time act, not a re-derivation (#53 OQ2). A certification lapsing later does not reopen a deposit that was lawfully waived.
- **Not in -06, in the sources:** #53 rank 4: if any waiver input is unevaluable (for example `date_of_birth` NULL for the 65+ waiver), **no deposit**. Fail open. The core must implement it (DG3).

**2.2 The cap** — the deposit records the cap that applied and its source: the statute (the rule's cap) or the utility's tariff (Ryan, 2026-10-02, B2). A tariff cap may be tighter than the statute's, or exist where the statute sets none. (-06 L875–881, CHECKs L626–628; CI-129; D-41; #53 rank 8; #55 rule 9).
- Where the rule row's `cap_combinator ≠ none`, the deposit records its cap amount, the kind of the part that governed (`cap_basis_kind`) and that part's basis figure. The parts are `deposit_rule_cap_parts`; `single` takes the one part, `lesser_of` / `greater_of` the smaller / larger of the parts' amounts (v5.4.2-15 review r2 D2). Texas gas: single, 1/6 of estimated annual billing, residential. Texas retail electric (16 TAC §25.478(e)(1)(A)), for reference: the **greater** of 1/5 of annual billing and the next two months' billings.
- `principal ≤ cap_amount` and "`cap_binding` ⇒ `principal = cap_amount`" stay as CHECKs (design §1): arithmetic on the recorded cap.
- `cap_binding` must be set when the cap reduced the computed amount: the customer is entitled to know (#53 outputs).
- **Estimated annual billing for a new applicant is undefined** (#53 OQ5). The core must specify the method (for example a rate-class average) so two tenants don't compute different caps.
- **Per deposit or combined?** -06 checks per deposit. #55 rule 9 says the cap governs the **total** held: three $200 trigger deposits against a $450 cap break the rule, though each one alone is lawful. K4. The rule row carries `cap_scope`.
- Refund Alt 4: a held deposit found above the cap has its excess refundable independently of any trigger. Where the rule's `refund_excess_over_cap` is true, the core records a return-due row **with the amount** (reason `excess_over_cap`, resting on the deposit) and settles it with `principal_returned` of exactly that amount (review r2 D4). Texas: false, as -06.

**2.2a Instalments** (52 Pa. Code §56.42, gas; review r2 D3). Where the rule has a schedule (`deposit_rule_instalments`: Pennsylvania 0.5 at 0 days, 0.25 at 30, 0.25 at 60), the customer may elect to pay in instalments. The deposit's `principal` is the deposit required; `received_at_posting` is the first instalment; `deposit_instalments` lists the rest with amounts and due dates; each receipt is an `instalment_received` event. What is held, and what interest and refunds run on, is what was received. The start of the schedule depends on the trigger (§56.42(c): from reconnection), so the core computes the dates. A missed instalment is a ground for termination (§56.81). Texas has no schedule.

**2.3 Basis, trigger and instrument** (-06 L621–624, L629–631; #53 OQ4; #55).
- Every deposit names its basis, because the bases refund on different rules: a §366 deposit is never auto-refunded while its case is live (#54 rule 3; refund Exc 2).
- `additional_trigger` ⇔ a trigger basis (`nsf`, `disconnect_history`, `broken_dpa`, `usage_doubled`). This stays as record integrity (the trigger is what the additional basis means).
- **Thresholds** (review r2 D1). A trigger fires against a threshold: a count of events in a window of months (#55 rules 5–7: "nsf_count_12m ≥ threshold", disconnection in 24 months) or a ratio of actual use to the estimated billing. The statute's thresholds are rule parts (`deposit_rule_trigger_thresholds`); the utility's, set in its tariff, are its own rows (`deposit_tariff_trigger_thresholds`, R-D1). The deposit cites the one it was decided under and the measure observed. Where the rule sets a threshold for the trigger, a citation is required.
- **Texas's own usage trigger** (16 TAC §7.45(5)(C)(ii)): "If actual use is at least twice the amount of the estimated billings, a new deposit requirement may be calculated and an additional deposit may be required within two days." Seeded as `usage_doubled`, ratio 2, payable in 2 days. -06 and #55 both omit it (DG10, **K9**).
- Instruments: cash, or one of the §366(c)(1)(A) forms plus guarantor. Non-cash carries a reference. Residential non-cash is undecided (#55 rule 2, K5); -06 accepts any instrument for any class.
- **Not in -06:** #55 rule 4: a non-cash instrument past its expiry no longer satisfies the deposit. -06 records the expiry and does nothing with it. The core (or an alert) owns it.

**2.4 Legacy deposits** (-06 L854–856; D-42). `legacy_unknown` exists only for rows carried at patch time. The core must refuse to decide anything that needs a rule row for one (there is no Texas rule row for `legacy_unknown`, design §3.2).

---

## 3. Interest accrual

All of §3 applies only when the deposit's instrument is in the rule's `interest_bearing_instruments` (-06 L964–966; CI-125; #55 OQ1: no interest on money never received).

**3.1 The minimum hold** (-06 L967–976; CI-130; #54 rules 5–6; D-38). Texas: 30 days.
- **An accrual may be recorded only once the deposit is more than `interest_min_hold_days` old:** `effective_on − posted_on ≥ 31` (L967). A monthly job writes nothing for a deposit in its first 30 days.
- **A deposit whose principal was exhausted by applications within the minimum hold owes no interest at all:** `exhausted_on − posted_on ≤ 30` refuses any accrual (L974). Otherwise an accrual recorded for its short life would block the zero refund forever (Codex round 2).
- Rules 5 and 6 of #54 are **one rule with a cliff**: ≤ 30 days held ⇒ nothing; ≥ 31 ⇒ interest **from day 1**. "Interest accrues after 30 days" reads as right and is the wrong implementation (accrual Exc 2).

**3.2 The first period and contiguity** (-06 L977–987; accrual Alt 1).
- With `interest_retroactive = true`, the first period starts **on** `posted_on`, not on day 31 and not at a cycle boundary.
- Each later period starts the day after the previous one ends: no gap. No overlap stays as the EXCLUDE constraint (design §1).
- An accrual is recorded after the period it covers: `period_end < effective_on` (L985).

**3.3 Splits** (-06 L992–997; accrual steps 3–5, Alt 2, Alt 3).
- A period never spans a rate change: if a rate row takes effect on a day after `period_start` and on or before `period_end`, split at that day.
- A period never spans a principal application: if an `applied_to_balance` is effective on a day after `period_start` and on or before `period_end`, split there. A period may **start** on an application's date.
- An application can't be dated on or before the accrued-through date (L960; it stays as integrity, design §1). An application reduces the basis from its own date forward.

**3.4 Rate and principal** (-06 L988–991, L998–1004; R-D1).
- The rate is the utility's rate row in force on `period_start`: the latest row with `effective_date ≤ period_start`. **No row ⇒ refuse, never fall back** (L539–543; accrual Exc 1).
- The principal basis is the principal in force on `period_start`: `principal − Σ applications effective ≤ period_start` (L781–786). A basis ≤ 0 means nothing is held and nothing accrues (L999–1001).

**3.5 The amount** (-06 L549–555, L1005–1008).
- `simple` / `actual_365`: `round(principal_basis × annual_rate × days / 365, 2)` per period, days inclusive. A leap year still divides by 365, so a 366-day period earns 366/365 of a year (§6 case B9).
- Each event records period, rate, rate row, principal basis and amount. Interest is events, never an accumulator (D-38; accrual Exc 3). A re-run never overwrites what was accrued or credited (accrual Alt 5).

---

## 4. Crediting, refund and release

**4.1 Credit** (-06 L1009–1012). `0 < interest_credited ≤ accrued − credited` stays as integrity. *When* it is credited is `interest_credit_cadence`. An annual credit pays the customer and reduces nothing about the principal held (accrual Alt 4).

**4.2 The horizon** (-06 L1027–1031; D-39). Interest is owed on money held, through the day before the **earlier** of:
- the return date (`refunded.effective_on`);
- the day the principal was exhausted by applications (`exhausted_on`, the first day cumulative applications reached the principal).

**4.3 What a refund requires** (-06 L1020–1052; CI-130, CI-131; #54 rules 5–7).
- Cash only: non-cash is **released**, not refunded (L1021, L1054; stays as integrity).
- Amount = the remainder (stays as integrity). Interest is a separate movement and is **disclosed separately** (#54 rule 7; refund step 10).
- If `horizon − posted_on ≤ 30`: no accrual may exist.
- Otherwise: accrual must reach `horizon − 1`, and everything accrued must be credited, before the refund.
- A fully applied deposit is settled by a **zero refund**: the obligation is still recorded and disclosed (D-39; refund Alt 2). Until then its status is `applied`, and the customer can't close.
- **Legacy exception** (L1032–1040; D-42, flagged): a `legacy_unknown` deposit with no accrual events may be refunded with a recorded reason stating how its interest was settled (its interest is the carried `legacy_interest_earned`). The alternative, entering the rate history back to posting and accruing first, is still open with Ryan and Kyle.
- **Not in -06:** #54 rule 8: a mandatory deposit refund **bypasses** `tenants.minimum_refund_amount` and `below_threshold_action`. It is never held for escheat or donated (refund Exc 4).
- **Not in -06:** refund OQ4: credit only where service continues, disbursement on close. Recommended, not ruled.

**4.4 Ordering on close or disconnect** (#54 rule 1; refund step 6). Apply the deposit to the unpaid balance **first**, then refund the remainder. Interest is computed on the full principal for the full hold up to the application date (§6 case B6).

---

## 5. The return-due decision (design §3.5)

The core writes a `deposit_return_due` row when a mandatory return falls due, with its reasons and evidence. -06 computed this as a view (L790–834; D-43). What it computed:

**5.1 Which deposits can fall due** (L831–833; #54 rule 3).
- The rule row is `refund_mandatory` (Texas: the three §7.45 bases; never §366, never `legacy_unknown`).
- The instrument is in `return_mandatory_instruments` (-06: cash only. The design generalises to release for non-cash, pending K5).
- The deposit is open (held, partially applied, or applied). A pending refund is not "due": it has started.

**5.2 Clean-bill history** (L790–819; CI-131; #54 rule 2). -06's definitions, which its own COMMENT calls **an approximation**:
- **The bills counted:** the customer's invoices dated on or after `posted_on`, excluding draft, held and void, of type regular, final or correction. Newest first by invoice date, then creation time.
- **Paid clean:** status paid, balance 0, and dunning stage current or resolved.
- **Delinquent occasion:** status overdue, or dunning stage beyond current/resolved.
- **Consecutive clean bills:** the paid-clean bills newer than the newest bill that isn't paid clean (a trailing run).
- **Delinquent occasions:** counted over **every** bill since posting, not over the twelve (DG4).
- **Currently delinquent:** any counted bill is overdue.
- **Due when** consecutive ≥ `refund_after_count` (12), occasions ≤ `refund_max_delinquencies` (2), and not currently delinquent.
- **Missing from -06:** "not disconnected for nonpayment" (#54 rule 2; `refund_disqualify_on_disconnect`). There was no `disconnect_reason` to read (DG2).
- **Missing from -06:** #54 rule 4: **if any input is unevaluable, the refund is due**. Fail open (DG3).

**5.3 Account closed** (L826, L834; #54 rule 1). -06: customer status `closed`, `final_billed` or `inactive`. #54 also names **service disconnected for any reason** (DG1). `inactive` is -06's reading, not a source's (DG7).

**5.4 What the core does with it** (design §3.5): write one due row when the answer becomes "due", citing the bills (or the closure) it rests on; withdraw it if the facts behind it turn out wrong; never write a row per check. Whether the obligation survives a later delinquency is K6.

---

## 6. Boundary cases

The rate is 3% (0.030000) unless stated, the deposit $200 cash, posted 2026-01-01. The amounts were computed with -06's formula.

| # | Case | Expected |
|---|---|---|
| B1 | **30/31 cliff, day 30.** Refund 2026-01-31 (30 days) | No accrual may exist. Interest 0.00 |
| B2 | **30/31 cliff, day 31.** Refund 2026-02-01 (31 days) | One accrual 2026-01-01..01-31 (31 days), **0.51**, credited before the refund. From day 1, not day 31 |
| B3 | **Accrual before day 31.** An accrual event effective 2026-01-31 | Refused (age 30) |
| B4 | **Rate change mid-hold.** Posted 2026-12-01, rate 3% to 2026-12-31 and 2.5% from 2027-01-01, refund 2027-02-01 | Two periods: 12-01..12-31 at 3% = **0.51**; 01-01..01-31 at 2.5% = **0.42**; total 0.93. One period across 01-01 is refused |
| B5 | **No rate in force.** The first rate row is dated after `posted_on` | Refuse. No fallback to the nearest row |
| B6 | **Partial application.** $50 applied effective 2026-02-15, refund 2026-04-01 | 01-01..02-14 on $200 = **0.74**; 02-15..03-31 on $150 = **0.55**; refund principal $150, interest 1.29. One period across 02-15 is refused |
| B7 | **Exhaustion after the hold.** $200 applied effective 2026-03-02 (60 days) | Interest through 03-01 (60 days) = **0.99**, credited; then a **zero refund** |
| B8 | **Exhaustion within the hold.** $200 applied effective 2026-01-20 | No accrual may exist; zero refund with no interest |
| B9 | **Leap year.** Posted 2028-01-01, accrual 2028-01-01..12-31 (366 days) | **6.02** (366/365 of a year) |
| B10 | **Legacy.** `legacy_unknown`, no accruals, refund without a reason | Refused; with a reason, allowed |
| B11 | **Waiver on the posting date.** Determination `determined_on` = `posted_on`; and one expiring on `posted_on` | Both in force: the deposit is refused |
| B12 | **Waiver vs §366.** Certified family violence, §366 deposit | -06 allows it; #53 rank 0 refuses it. **K2** |
| B13 | **Combined cap.** Cap $450, three $200 trigger deposits | -06 accepts all three; #55 rule 9 refuses the third. **K4** |
| B14 | **Eleven, then twelve.** Eleven clean bills, then a twelfth paid clean | Due on the twelfth, not before (one row) |
| B15 | **Three delinquencies.** Twelve trailing clean bills, three delinquent occasions earlier in the hold | -06: not due (counts every bill since posting). DG4 |
| B16 | **Currently overdue.** Twelve clean, but an older bill still overdue | Not due |
| B17 | **§366 meets the trigger.** Twelve clean bills on an `adequate_assurance_366` deposit while the case is live | Never due (#54 rule 3) |
| B18 | **Final bill consumes the deposit.** Customer goes `final_billed`; deposit fully applied to the final bill 60 days in | Due (account closed); stays owed until the zero refund with 0.99 interest. The customer can't move to `closed` until then (-06 L313, kept) |
| B19 | **Small refund.** $3.50 due; tenant sends sub-$5 residuals to donation; customer opted in | Paid, not donated (#54 rule 8) |
| B20 | **Disconnect ordering.** Disconnect; $200 deposit, $120 balance | $120 applied, $80 refunded; interest on $200 to the application date (#54 test note) |

---

**5.5 Which rule a later record cites** (Ryan, 2026-10-02, B1). An accrual, a return or a due row cites either the rule the deposit was decided under (the old law governs it) or the rule of the same state, service, class and basis in force over the dates the record covers (a later law reaches deposits already held). The amendment decides which; the core records it.

## 7. Where -06 and its sources disagree (for Kyle and Ryan)

| # | -06 | The source | Effect |
|---|---|---|---|
| DG1 | Refund due on customer status closed / final_billed / inactive | #54 rule 1: **service disconnected (any reason)** or account closed | Add a disconnect reason to the return-due vocabulary; needs `disconnect_reason` on service orders (3K-collections) |
| DG2 | Ignores disconnection for nonpayment in the clean-bill rule | #54 rule 2 disqualifies it | `refund_disqualify_on_disconnect` on the rule row; same data gap as DG1 |
| DG3 | No fail-open anywhere | #53 rank 4 (waiver inputs) and #54 rule 4 (refund inputs): unevaluable ⇒ the customer-favourable answer | The core implements it; scenario tests on NULL inputs |
| DG4 | Delinquent occasions counted over the whole hold | #54 says "≤ 2" without stating over what window | **K7**: over the twelve bills, twelve months, or the whole hold? |
| DG5 | Any waiver blocks a §7.45 deposit, but not a §366 one (D-40) | #53 rank 0: family violence outranks §366 | K2 |
| DG6 | Cap per deposit | #55 rule 9: combined | K4 |
| DG7 | `inactive` counts as closed | No source names `inactive` | **K8**: is an inactive account a return trigger? |
| DG8 | Expiry recorded, never acted on | #55 rule 4: not satisfied past expiry | Core or alert, not schema |
| DG9 | No minimum-refund exclusion | #54 rule 8 | Core rule; scenario B19 |
| DG10 | No usage trigger | 16 TAC §7.45(5)(C)(ii): actual use ≥ 2× the estimate ⇒ an additional deposit, payable in 2 days | Seeded in v5.4.2-15 (review r2); **K9**: why #55 omits it, and does the utility apply it? |

---

## 8. What stays in the database

Design §1, unchanged: identity frozen after insert; status projected from events; the sub-ledger's arithmetic (applied ≤ remainder, refund and release = remainder, credited ≤ accrued − credited, one pending refund, no application while a refund is pending, no application into an accrued period, no overlapping periods); cash refunded and non-cash released; the rate backdating guard; the close-with-open-deposit guard; the return-due record's integrity checks (design §3.5).

The test for anything not listed here: does it store or protect a record, or does it decide what the law requires? If it decides, it is in §§2–5 above and belongs to the core.
