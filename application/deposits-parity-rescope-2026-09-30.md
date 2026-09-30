# Deposits re-scoped to parity — design (2026-09-30)

**Subject:** the deposit half of `sql/v5.4.2-06-account-lifecycle-and-deposits.sql`, which has landed (tu.sql 17,706–18,822).

**Why:**
- The audit calls it "the worst landed patch": it builds 16 TAC §7.45 almost line for line as refusals.
- See `application/texas-only-architecture-audit-2026-09-28.md` §3.4 and §6, and slice `04-patches-542-01-06.md` Theme 1.

**Ryan's rules this follows (2026-09-28):**
- **The schema represents; the C# core evaluates.**
- **A Texas-only launch is not a Texas-only architecture.**
- The pattern is the one -13 used:
  - law becomes platform rows, dated and cited, one row per (state, service, class, key);
  - records keep integrity only;
  - every dropped behaviour is written up for the core before it goes.

**The test for every object:** does it store or protect a record, or does it decide what the law requires?

**The account-lifecycle half of -06 is out of scope.** That covers the state events, the attribute history and "closed only with no open deposit". The audit calls it generic mechanism.

**One gap to know about:** -06's 141-check battery was lost before batteries were committed (tests/README.md). No test in the repo exercises the deposit guards today. So the rules-for-the-core write-up (§6) is taken from the code and `DECISION-LOG.md` D-2026-08-28-34…43, and the new patch ships a new battery.

---

## 1. Keep (stores or protects a record)

| Object | Why it stays | Change |
|---|---|---|
| `deposits`: identity frozen after insert; born `held`; `status` / `refunded_on` / `released_on` projected from events only | Integrity: the events are the only write path (D-36) | Gains the jurisdiction and rule it was decided under (§3.4) |
| `deposits` CHECKs: principal > 0; non-cash carries a reference; `released` only for non-cash; `legacy_interest_earned` only on legacy rows; status/date equivalences | What the record means | `deposits_cap_check` (principal ≤ cap) stays: it's arithmetic on the recorded cap, not the cap law |
| `legacy_unknown` not insertable; source payment same customer and `is_deposit` | Integrity | None |
| `deposit_events`: append-only; `posted` written by the database; no events after refunded/released; `effective_on ≥ posted_on`; ledger link same customer; the deposit row locked per event | Integrity | None |
| Arithmetic that holds in every state: applied ≤ remainder; refund and release amount = remainder; interest credited ≤ accrued − credited; one pending refund; nothing applied while a refund is pending; an application can't reach back into an already-accrued period; accrual periods never overlap (EXCLUDE) | The ledger adds up whatever the law says | None |
| Cash is refunded; non-cash is released | What an instrument is, not law | None |
| Accrual event carries period, rate, principal basis and amount | The record of the core's computation | Gains the cited rate row, rule row and core version (§3.4) |
| `deposit_balance()`, `deposit_principal_in_force()` | Plain reads over the events | None |
| Projections: `deposits.status`, `customers.deposit_*`, `customer_attribute_history` deposit_status | Integrity (D-36) | None |
| `customer_credits.deposit_id` lineage | Integrity | None |
| `deposit_waiver_determinations`: append-only, RLS, dates | The record that a person qualified | `waiver_class` becomes a foreign key to the platform waiver classes. "A class that requires certification carries a reference" reads the class row, not a CHECK naming family violence |
| Backdating guard on rates: a rate can't be moved under a settled accrual | Integrity of settled records | Moves to the platform rate table as -13's close floor (§3.3) |
| Customer can't close while a deposit is open | Account integrity, not state law | None |
| TEMP revoked; ENABLE ALWAYS; RLS/FORCE; composite FKs | Integrity | None |

## 2. Drop (decides what the law requires; becomes core scenarios)

| Object | What it decided | Source |
|---|---|---|
| `enforce_deposit` waiver branch | an in-force waiver of any class blocks every "§7.45 basis" (`credit_evaluation`, `additional_trigger`, `tariff`) | CI-129; #53 ranks 0–3; #55 rule 8 |
| `enforce_deposit` cap branch | `upper(tenants.state) = 'TX'` and residential and cash ⇒ `cap_amount` required | CI-129; #53 rank 8 |
| `enforce_deposit_event`, interest_accrued branch (except the record integrity kept above) | cash only; no accrual before day 31; first period starts ON posting; periods contiguous; a period never spans a rate change or an application; rate = rate in force; principal = principal in force; amount = simple × days/365 | CI-125, CI-130; D-38 |
| `enforce_deposit_event`, refunded branch | held ≤ 30 days ⇒ no accrual; > 30 ⇒ accrued to the horizon and credited in full; the horizon = earlier of return and exhaustion; legacy exception with a reason | CI-130, CI-131; D-39 |
| `deposit_accrual_amount()` | the Texas interest formula (simple, actual/365, rounded to cents) | CI-130 |
| `deposit_refund_trigger_state()` | 12 clean bills, ≤ 2 delinquencies, not delinquent; the definitions of "clean" and "delinquent" | CI-131 |
| `deposits_refund_due` view | which bases are refund-mandatory (an IN list); closed/final/inactive fires it | CI-131; #54 rules 1–3 |
| `deposit_interest_rate_as_of(tenant, date)` | which rate applies, keyed per utility | CI-125 |
| CHECK lists: `deposits.basis`, `trigger_basis`, `waiver_class`, the family-violence certification CHECK | Texas's categories as DDL | #53, #55 |

Each is written up in §6 before the patch strips it.

## 3. Change: the law becomes platform rows

These follow the -13 conventions:
- no `tenant_id`; `tally_app` reads and can't write;
- dated, with no overlap per key;
- `source_note` required;
- closed and never edited;
- the close is stamped and refused on or before a date a citation used;
- vocabulary rows are immutable;
- a missing row means refuse, never fall back.

### 3.1 Vocabularies (platform-wide, rows not CHECKs)

- **`deposit_bases`** (`basis_code`, `description`, `is_federal`):
  - seeded with `credit_evaluation`, `additional_trigger`, `tariff`, `adequate_assurance_366` (federal) and `legacy_unknown` (internal, never insertable);
  - what a basis *does* in a state is on the rule row.
- **`deposit_triggers`** (`trigger_code`, `description`): `nsf`, `disconnect_history`, `broken_dpa`.
- **`deposit_customer_classes`** (`state_code`, `service_type`, `class_code`, …):
  - the classes a state's deposit rules distinguish;
  - Texas gas: `residential`, `non_residential` (Kyle question K1);
  - which class an account is in is the core's call, from the tariff, as with CCK-14.

### 3.2 `deposit_rules` (state, service, class, basis, dated)

| Column | Meaning |
|---|---|
| `waivable` | An in-force waiver of a class that reaches this basis means no deposit may be required |
| `cap_kind` | `none` / `fraction_of_annual_billing` / `months_of_billing` / `fixed_amount` |
| `cap_factor`, `cap_amount_fixed` | The number the kind needs (Texas residential: 1/6 of annual) |
| `cap_scope` | `per_deposit` / `combined` (#55 rule 9: the cap governs the total held) |
| `interest_bearing_instruments` | Which instruments earn interest (Texas: cash) |
| `interest_min_hold_days` | No interest unless held longer (Texas: 30; NULL = from day 1) |
| `interest_retroactive` | Past the threshold, from posting (Texas: true) or from the threshold |
| `interest_method`, `interest_day_count`, `interest_credit_cadence` | `simple`/`compound_annual`; `actual_365`/`actual_actual`; `at_refund`/`annual`/`on_bill` |
| `refund_mandatory` | Must be refunded without being asked when the trigger fires (Texas §7.45 bases: yes; §366: no) |
| `refund_after_count`, `refund_measure`, `refund_max_delinquencies`, `refund_disqualify_on_disconnect`, `refund_on_account_close` | Texas: 12 bills, ≤ 2, disqualifying disconnect, refund on close |
| `source_note` | The citation |

**Texas gas is seeded once, from what -06 enforces.**
- For credit_evaluation, additional_trigger and tariff: waivable; residential capped at 1/6 of annual billing, per deposit; cash-only interest; 30-day minimum hold, retroactive, simple, actual/365, at refund; refund mandatory after 12 bills with ≤ 2 delinquencies, and on account close.
- For adequate_assurance_366: not waivable, no cap, not refund-mandatory.
- Rows for `legacy_unknown` are deliberately absent: the core refuses to decide one.

### 3.3 Interest rates (Ryan, R-D1, 2026-09-30)

- **The rate applied stays the utility's.**
  - `deposit_interest_rates` (per tenant, effective-dated, append-only, no fallback) remains the rate each utility applies.
  - Each accrual cites the row it used (`rate_id`).
  - Its backdating guard stays: a rate can't be moved under a settled accrual.
- **The platform keeps a reference.**
  - `deposit_interest_rate_law` (`state_code`, `service_type`, `effective_from/to`, `annual_rate`, `source_note`) holds each state's published legal rate.
  - It's platform-held, with no overlap, closed and never edited.
  - It is a **reference**, not the source: nothing reads it to decide an accrual.
- **The check.**
  - A report, `deposit_interest_rate_discrepancies`, lists each utility rate row whose rate differs from the published legal rate for the same state, service and dates. It also lists the dates on which a legal rate is published and the utility has no row.
  - It's a read over two records, not a refusal. Whether a difference is lawful (a tariff paying more) is the core's and the utility's call.
- **Texas.** The PUCT sets one statewide rate a year (Utilities Code §183.003).

### 3.4 What the records gain

- **`deposits`:**
  - `state_code`, `service_type` and `customer_class`: the jurisdiction and class the core decided under, taken from the premise, not the utility;
  - `rule_id` (FK, NULL only for `legacy_unknown`);
  - `cap_basis_kind` and `cap_basis_amount`, so the cap's basis is recorded whatever the state's kind;
  - `decided_by` (core version).
  - A consistency check: the rule is for that state, service, class and basis. It is the -13 evidence pattern.
- **`deposit_events` accruals:**
  - `rate_id` (the law row, or the utility row under R-D1) and `rule_id`;
  - `calculated_by`;
  - a consistency check that `rate_applied` equals the cited rate row's rate. It is record integrity, like -13's rule-for-cause check.
- **`trigger_basis`** becomes a foreign key to `deposit_triggers`, and `basis` a foreign key to `deposit_bases`.

---

## 4. Decisions for Ryan

**R-D1. Interest rates. DECIDED (Ryan, 2026-09-30):** the utility keeps the rate it applies, and the platform keeps the published legal rate as a reference, with a discrepancy report (§3.3).

Why:
- **The utility is the regulated company.** The commission holds it, not Tally, responsible for paying the right interest, so it owns, checks and can correct the number it applies.
- **A single platform rate would concentrate the risk.** A missed or wrong entry would stop or mis-rate every utility in the state at once.
- **The rate matters for audits and refunds.** Every accrual cites its rate row, and a wrong rate is fixed by correcting entries, never by editing. So a platform-wide error would mean corrections across every utility.
- **Duplicate data entry is solved in the app.** It pre-fills a new published rate for each utility to confirm.

This supersedes the first recommendation (a platform rate the core uses, with a per-utility override for a higher rate).

**R-D2. The refund-due surface.**
- `deposits_refund_due` shows deposits whose refund is owed and not started. That is the standing obligation Kyle's #54 wants visible. But deciding "owed" is law (12 bills and the rest).
- **Recommend:** store the core's decision.
  - A `deposit_refund_evaluations` table, append-only: deposit, evaluated on, rule row, trigger met yes/no, which trigger, counts, core version.
  - A view listing deposits whose latest evaluation says due, with no refund started.
  - This is -13's evaluation pattern: the database keeps the record, the core decides.
- The alternative is to drop the surface until the core exists; nothing then shows an unfired refund.

**R-D3. Numbering.**
- This would be v5.4.2-15. The delivery patch has been renumbered once already, to -15 by -14's header.
- **Recommend:** from now on, call it "the delivery patch" rather than by number. Each patch takes the next number when it's drafted.

## 5. Questions for Kyle (answers change seed rows, not the schema)

- **K1.** Which classes do §7.45's deposit rules reach? -06 caps residential only and applies the refund trigger and interest to every class.
- **K2.** Family violence against §366. Decision table #53 ranks the family-violence waiver above a §366 assurance demand. -06 (D-40) lets a §366 deposit through a waiver. Which is right?
- **K3.** The 65+ waiver: is it mandatory, or tariff-by-tariff (the contradiction the audit notes)?
- **K4.** Is the cap per deposit or combined (#55 rule 9 says combined)? -06 checks it per deposit.
- **K5.** Residential non-cash instruments (#55 rule 2, "decide, do not default").

## 6. Before anything is stripped

1. **`application/deposits-rules-for-the-core.md`:** every dropped behaviour in §2, with its source, the -06 line range, and the boundary cases:
   - the 30/31 day cliff;
   - a rate change mid-hold;
   - exhaustion by applications;
   - the zero refund of a fully applied deposit;
   - the legacy exception.

   This is the scenario material the lost battery would have been.
2. **A new battery**, testing:
   - that Texas is stored as rows;
   - a fictional state ZZ with other classes, a month cap, interest from day 1 credited annually, a 24-month refund measure and a waiver class Texas lacks, all with no DDL;
   - every kept integrity guard, as `tally_app`;
   - the patch's legacy and backfill paths on a pre-seeded clone.
3. **Mutations** for every guard, on a -14 base.
