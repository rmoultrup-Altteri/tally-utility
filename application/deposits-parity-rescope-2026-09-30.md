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
| `deposits_refund_due` view | which bases are refund-mandatory (an IN list); closed/final/inactive fires it. Replaced by the recorded answer (§3.5) | CI-131; #54 rules 1–3 |
| `deposits.refund_eligibility_on` | an informational "earliest the trigger could fire" date; it would compete with the recorded due rows (§3.5). Found by the R-D2 council | -06 line 608 |
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
| ~~`waivable`~~ | Replaced after review round 1 by `deposit_rule_waiver_reach` (§3.7): which waiver classes reach the rule, per trigger, with what effect |
| `cap_kind` | `none` / `fraction_of_annual_billing` / `months_of_billing` / `fixed_amount` |
| `cap_divisor`, `cap_months`, `cap_amount_fixed` | The figure the kind needs: a divisor of annual billing (Texas residential: 6, i.e. 1/6, stored exactly), a number of months, or an amount. Built this way in v5.4.2-15 instead of one `cap_factor`, because 1/6 has no exact decimal |
| `cap_scope` | `per_deposit` / `combined` (#55 rule 9: the cap governs the total held) |
| `interest_bearing_instruments` | Which instruments earn interest (Texas: cash) |
| `interest_min_hold_days` | No interest unless held longer (Texas: 30; NULL = from day 1) |
| `interest_retroactive` | Past the threshold, from posting (Texas: true) or from the threshold |
| `interest_method`, `interest_day_count`, `interest_credit_cadence` | `simple`/`compound_annual`; `actual_365`/`actual_actual`; `at_refund`/`annual`/`on_bill` |
| `refund_mandatory` | Must be refunded without being asked when the trigger fires (Texas §7.45 bases: yes; §366: no) |
| `refund_after_count`, `refund_measure`, `refund_max_delinquencies`, `refund_disqualify_on_disconnect`, `refund_on_account_close` | Texas: 12 bills, ≤ 2, disqualifying disconnect, refund on close |
| `refund_obligation_vests` | Once the trigger fires, the return stays owed even if the customer falls behind before it is made (Kyle question K6) |
| `return_mandatory_instruments` | Which instruments the mandatory return covers: cash is refunded, non-cash is released |
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

### 3.5 The return-due record (R-D2, Ryan, 2026-10-01)

The core decides when a deposit's mandatory return falls due. The schema records that answer when it happens and never computes it. It is called *return* due because a non-cash deposit is released, not refunded.

- **`deposit_return_due`** (append-only, RLS, one row per answer):
  - `deposit_id`, `tenant_id`, `rule_id`, `due_on`;
  - the reason or reasons (`account_closed`, `clean_bill_history`, …) from a vocabulary (`deposit_return_reasons`), so a state with another trigger is rows only; both reasons firing at once make one due row with two reasons, not two due rows. As built in v5.4.2-15, each reason is carried on its evidence rows (one row per reason and record) rather than in a separate reasons table;
  - `inputs_fingerprint` and `calculated_by` (the core version);
  - created_at and created_by stamped by the database.
- **`deposit_return_due_evidence`**: what the answer rests on, written in the same transaction as its due row (-13's evidence pattern):
  - one row per bill, with the core's classification (clean / delinquent);
  - or the account-closure event the row relies on.
  The counts are derived from these rows, not stored beside them.
- **`deposit_return_due_withdrawals`**: says a due row was wrong (a reversed payment, a corrected bill, a core bug):
  - `due_id` (unique: a row is withdrawn once), `reason`, `calculated_by`, stamped time and role;
  - a corrected answer is a new due row naming the withdrawn one (`deposit_return_due.supersedes_due_id`, once each). As built in v5.4.2-15 the link is on the new row, not the withdrawal: the withdrawal must come first (one live row per deposit), so it cannot name a row that doesn't exist yet;
  - a withdrawal never moves money. If a return was already made, it is corrected through the deposit's own events.
  - A customer falling behind after qualifying is **not** a withdrawal. Whether the return is still owed is law (`refund_obligation_vests`, K6), decided by the core.
- **`deposit_events.refund_initiated` / `released`** may cite the due row they settle. It is optional, because voluntary and §366 returns have none.
- **The view `deposits_return_owed`**: due rows not withdrawn, on deposits with no refund or release recorded yet. It reads recorded answers and computes no law.
  - A deposit fully applied to its final bill stays on the list until its (zero) refund is recorded, because interest may still be owed at refund.
- **What the database checks (integrity only, never whether the answer is right):**
  - the due row's `rule_id` is the deposit's `rule_id`, and that rule row's `refund_mandatory` is true (this keeps §366 deposits out by reading a stored attribute, like -13's rule-for-cause check);
  - at most one live (not withdrawn) due row per deposit;
  - no due row on a deposit that is already refunded or released;
  - evidence bills belong to the deposit's customer and are dated on or after `posted_on`; a closure reason cites a closure event of that customer;
  - evidence is added only in its due row's transaction;
  - reason codes are known vocabulary rows.
- **Not in the schema:**
  - no "last checked" column;
  - no row per check.
  The core checks on events (payment received, bill past due, status change, import, reversal, bill correction). Whether it also runs a read-only reconcile that writes only when it disagrees with the live row is the core's design (Opus raised it; noted for the core).

---

### 3.6 As built (v5.4.2-15, 2026-10-02)

The patch follows this design with the three changes noted above (the cap figures, where reasons live, where the supersession link lives) and one divergence for Ryan:
- **Interest accrued must be credited by the last event.** §2 drops "credited in full before the refund" as law. The patch keeps the arithmetic half: a refund or release is the deposit's last event, so interest already **accrued on the record** must be **credited** by then, or the ledger closes owing money it can never pay. Whether interest is owed, and to which date, stays the core's.

### 3.7 After review round 1 (2026-10-02)

Opus, Fable and Codex all said "not yet" on the first draft (`tests/v5.4.2-15/review/review-findings-15-r1.md`). Ryan's decisions:
- **B1, which rule a later record cites:** the deposit's own rule, or the rule of its key in force over the record's dates. An amendment may spare or reach deposits already held.
- **B2, the cap's source:** the deposit records whether its cap came from the statute or the utility's tariff (with the tariff provision). A tariff cap may be tighter, or exist where the law sets none.
- **B3, waiver reach** (the proposal was reviewed by the same three before building): the `waivable` column on §3.2 is replaced by `deposit_rule_waiver_reach`: one row per (rule, waiver class, trigger), with an effect (excuse, reduce, defer).
  - The utility's own tariff waivers are its rows (`deposit_tariff_waiver_grounds`), each with its own scope and effect. The law keeps only the permission (`deposit_waiver_classes.tariff_defined`).

The other 15 findings were fixed as recorded. They added these shapes:
- class-specific interest rates;
- a combined cap's `cap_other_held`;
- partial returns (`principal_returned`);
- a refund lookback and disqualifiers as rows;
- a time-held return reason resting on the deposit itself;
- each return reason tied to the rule attribute that enables it.

## 4. Decisions for Ryan

**R-D1. Interest rates. DECIDED (Ryan, 2026-09-30):** the utility keeps the rate it applies, and the platform keeps the published legal rate as a reference, with a discrepancy report (§3.3).

Why:
- **The utility is the regulated company.** The commission holds it, not Tally, responsible for paying the right interest, so it owns, checks and can correct the number it applies.
- **A single platform rate would concentrate the risk.** A missed or wrong entry would stop or mis-rate every utility in the state at once.
- **The rate matters for audits and refunds.** Every accrual cites its rate row, and a wrong rate is fixed by correcting entries, never by editing. So a platform-wide error would mean corrections across every utility.
- **Duplicate data entry is solved in the app.** It pre-fills a new published rate for each utility to confirm.

This supersedes the first recommendation (a platform rate the core uses, with a per-utility override for a higher rate).

**R-D2. The refund-due surface. DECIDED (Ryan, 2026-10-01): record the core's answer when the return falls due, with a separate withdrawal table (§3.5).**

How it was decided:
- Ryan put the recommendation below to a council: Claude Opus 5.5, an Opus subagent and Codex (`gpt-5.5`, high reasoning effort).
- **All three chose A over B.** Only a record written at the time answers "she qualified in March, so why was she refunded in August?". Recomputing later replays the rule over bills that may since have been corrected.
- **All three found the same hole:** one append-only "became due" row can't be taken back, so a wrong row would stay on the list for good. They also agreed on:
  - citing the bills, not just counts;
  - the integrity checks in §3.5;
  - covering non-cash release;
  - no "last checked" column;
  - Kyle question K6.
- **Where they split, and how it was settled:**
  - **Withdrawal shape.** Opus proposed a running series of "due" / "not due" rows, the latest one counting. Codex proposed a separate withdrawal record. Ryan chose the separate table, because "not due any more" would blur "the answer was wrong" with "the obligation lapsed", and the second is law (K6).
  - **A deposit used up by its final bill.** Codex would drop it from the list. Opus keeps it until the zero refund is recorded. The doc follows Opus, because interest may still be owed at refund.
  - **Missed triggers.** Opus suggested a read-only reconcile in the core. Codex called a missed trigger a core bug. Neither puts it in the schema, so it is noted for the core.

The discussion that led here (kept for the record):

- **The obligation.** A §7.45 deposit must be refunded without the customer asking once its trigger fires (12 clean bills, ≤ 2 late, none overdue; or the account closes). Kyle's #54 wants an owed-but-unstarted refund visible.
- **Today.** -06's `deposit_refund_trigger_state()` and the `deposits_refund_due` view decide that in the database, which is Texas law in DDL.
- **Where the discussion got to:**
  1. **Nothing is temporary.** No code or data exists, so the question is only the permanent schema. My first framing ("until the core exists") was wrong.
  2. **Option A:** the schema stores the core's decision.
  3. **Option B:** it stores nothing; the core computes on demand, with no record.
  4. **A row per check was rejected (Ryan).** A daily sweep of every deposit would write mostly useless rows.
- **The current recommendation (A, revised):**
  - **One row, written when a deposit's refund becomes due:** the deposit, the date, the rule row, the reason (clean bills or account closed), the counts behind it, and the core version. Append-only. Most deposits get one row in their life, or none.
  - **A view of due rows with no refund started:** the operators' "refunds owed" list, reading recorded answers, not computing law.
  - **No "not checked recently" column.** A missed trigger is a core bug, for the core's tests.
  - **The core checks on events** (payment received, bill past due, account status change), not a daily sweep. That's the core's design.
  - **Why store it at all:** it's the evidence of meeting a standing obligation ("she qualified in March, so why was she refunded in August?"), permanent and next to the money; it's the same split as -13's evaluations; and it's the list Kyle asked for.

**R-D3. Numbering. DECIDED (Ryan, 2026-10-01): as recommended.** The deposits patch is v5.4.2-15. The delivery patch is called "the delivery patch" and takes a number only when drafted. Landed text that says "-14" (in -13) or "-15" (in -14) means the delivery patch; it is not edited (tu.sql is append-only), and -15's header says so.

- This would be v5.4.2-15. The delivery patch has been renumbered once already, to -15 by -14's header.
- **Recommend:** from now on, call it "the delivery patch" rather than by number. Each patch takes the next number when it's drafted.

## 5. Questions for Kyle (answers change seed rows, not the schema)

- **K1.** Which classes do §7.45's deposit rules reach? -06 caps residential only and applies the refund trigger and interest to every class.
- **K2.** Family violence against §366. Decision table #53 ranks the family-violence waiver above a §366 assurance demand. -06 (D-40) lets a §366 deposit through a waiver. Which is right?
- **K3.** The 65+ waiver: is it mandatory, or tariff-by-tariff (the contradiction the audit notes)?
- **K4.** Is the cap per deposit or combined (#55 rule 9 says combined)? -06 checks it per deposit.
- **K5.** Residential non-cash instruments (#55 rule 2, "decide, do not default").
- **K6.** A customer meets the refund trigger, then falls behind before the refund is made. Is the refund still owed (`refund_obligation_vests`)? Codex leaned yes. Either answer is a rule-row value.
- **K7.** "No more than two delinquencies": counted over the twelve bills, over twelve months, or over the whole hold? -06 counts the whole hold (rules-for-the-core DG4).
- **K8.** Is an `inactive` account a return trigger? -06 treats it as closed; no source names it (DG7). Related: #54 rule 1 makes **any disconnection** a trigger, which -06 can't see (DG1).
- **K9.** (2026-10-06, review r2.) 16 TAC §7.45(5)(C)(ii) lets the utility require an additional deposit, payable within two days, when actual use is at least twice the estimated billing. Decision table #55 lists NSF, disconnection history and broken payment plans as triggers but not this one. Was it left out deliberately, and does a Texas municipal gas utility apply it? v5.4.2-15 seeds it as a trigger the core may act on.
- **K10.** (2026-10-06, rule-terms v2.) Does 16 TAC §7.45 bind Texas *municipally owned* gas systems, or only utilities under Railroad Commission rate jurisdiction? The survey found the answer differs by state: Kansas K.S.A. 12-822 binds municipal utilities directly, and Illinois exempts them. Our first customers are municipal systems, so this decides whether the Texas seed rows apply to them at all, and whether law rows need a utility-type key. **Answered from the statute, 2026-10-06:** no. Utilities Code §101.003(7) excludes "a municipal corporation" from "gas utility", and §102.002 bars the Commission from regulating a municipally owned utility's rates or service. Municipal deposits are under LGC §552.0025(c). To confirm against practice: do cities adopt §7.45 by ordinance, and does ch. 183 (deposit interest) bind a city? See `places-source-inventory-2026-10-06.md` §5.
- **K11.** (2026-10-06.) For our first customers, which customer-service policies are in the city's ordinance and which in a utility policy or tariff? That decides where a municipal utility's rows are cited.

## 6. Before anything is stripped

1. **`application/deposits-rules-for-the-core.md`** (written 2026-10-01; its §7 adds K7, K8 and the -06/source disagreements DG1–DG9): every dropped behaviour in §2, with its source, the -06 line range, and the boundary cases:
   - the 30/31 day cliff;
   - a rate change mid-hold;
   - exhaustion by applications;
   - the zero refund of a fully applied deposit;
   - the legacy exception;
   - for the return-due answer (§3.5): qualifying then falling behind (K6), both reasons at once, a reversed payment that un-cleans a counted bill, and each event that must prompt a check.

   This is the scenario material the lost battery would have been.
2. **A new battery**, testing:
   - that Texas is stored as rows;
   - a fictional state ZZ with other classes, a month cap, interest from day 1 credited annually, a 24-month refund measure and a waiver class Texas lacks, all with no DDL;
   - every kept integrity guard, as `tally_app`;
   - the return-due record (§3.5):
     - due, then withdrawn, then due again;
     - a second live due row refused;
     - a due row refused on a refunded or released deposit;
     - a due row refused for §366 (rule not refund-mandatory) and for a rule that isn't the deposit's;
     - evidence citing another customer's bill, or added in a later transaction, refused;
     - a fully applied deposit stays on `deposits_return_owed` until its zero refund;
     - a non-cash release clears the row;
   - the patch's legacy and backfill paths on a pre-seeded clone.
3. **Mutations** for every guard, on a -14 base.
