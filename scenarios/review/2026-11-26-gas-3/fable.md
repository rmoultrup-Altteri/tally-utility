# Round 9 review (Fable): SCN-0155 – 0162 and cast rows BB-22 – BB-26, GP-10, GP-11, PF-08

Read-only. File reviewed: `scenarios/gas-cost-zones-and-reads.md` lines 530 – 674 (working copy, uncommitted), `scenarios/cast.md`, `scenarios/README.md`.

## Verdict

Not yet. The arithmetic is clean: every dollar figure, volume, day count and weekday in the eight scenarios recomputes (list at the end). The problems are in claims, not figures: one wrong invariant number, one scenario that contradicts a Kyle-checked deposit scenario on how a corrected final bill treats the deposit, one "Built" claim with nothing behind it in the schema, and an Open for Kyle that `cancel-rebill.md` already settles by rule (with a different due-date rule).

Counts: 3 blocking, 8 should-fix, 7 nits, 7 gaps.

---

## Blocking (wrong claim)

### 1. SCN-0155 cites the wrong invariant for "a move-out requires a final reading" (lines 534, 535)

The Status line and the Sources both give CI-123. CI-123 is "Meter Change-Out Propagates to Billing Before Bill Generation": GBM `application/canonical-invariants.md:2136`, and this repo's parity record `application/invariant-parity-measurement-2026-10-13.md:432` ("Meter Change-Out Propagates to Billing"). The invariant that makes a final-read capture a required move-out event is CI-122, "MIMO Events Produce Required Billing Events" (`canonical-invariants.md:2119`: "a move-out produces a final-read capture, a prorated final bill, and a deposit disposition").

The wrong number comes from the cited GBM workflow, `application/configurable-rules/workflows/final-bill-generation.md:11` and `:41`, whose invariant numbers are shifted by one (it calls the move-in/move-out invariant CI-123 and premise persistence CI-122; canonically those are CI-122 and CI-120). GBM's own CHANGELOG (line 513) records 17 such wrong numbers across the workflow files.

Fix: CI-122 in both places. The exception-1 quote ("no next cycle to true it up in") and the failures-index quote (`knowledge/24-billing-failures-index.md:195`) are both accurate.

### 2. SCN-0162 contradicts SCN-0029 on what happens to the deposit when a deposit-paid final bill is corrected (lines 663, 664, 672)

SCN-0162's rule: "The deposit's disposition is worked again on the corrected bill"; (a): "The deposit is applied again to it, leaving $60.74"; Status: "Not built: reopening the deposit's disposition after a correction".

`deposits.md` SCN-0029 (figures checked by Kyle 2026-11-03, settled by his answer 17) says the opposite about the mechanism, on the same event: "money movements are never edited: a void reverses the bill's charge, but the deposit's application and its refund stay as they happened" (`deposits.md:131`), and "Neither the application nor the refund is edited, and the deposit does not reappear as held" (`deposits.md:149`). The result is one net credit, paid out as a deposit refund whatever its size (Kyle 11-03, answer 17: GBM `application/kyle-decisions-2026-11-03-scenario-batch-1.md:31`).

So the "Not built" item names something the Kyle-checked scenario says must never happen, and a test written from SCN-0162 would assert a re-opened deposit.

The dollars survive: (a) charge +$120.80, deposit −$100.00, payment −$20.80, void −$120.80, correction +$39.26 leaves a credit of $81.54; (b) +$39.26, −$39.26, void −$39.26, correction +$120.80 leaves $81.54 owed. Both match.

Fix: rewrite the rule and (a) in SCN-0029's terms (the void and correction leave a net credit; nothing about the deposit is reopened), cite Kyle 11-03 answer 17 and SCN-0029, and drop "reopening the deposit's disposition" from Not built. The split "$60.74 of deposit and $20.80 of payment" is then a bookkeeping choice (the released deposit money pays the correction before the released payment does, `cash.md` SCN-0089), and should be labelled as this stream's reading: Kyle's answer 17 covers a bill paid wholly from the deposit, not one paid partly in cash.

### 3. SCN-0160 Status claims a built review that the schema does not raise (line 629)

"Built: ... an actual dated earlier than estimates already entered raises its own review (SCN-0142)."

What is built is only the counting half. `sql/tu.sql:17307-17309` ("back-dated actual: the later actual still bounds the streak") and `consecutive_estimate_state` (`sql/tu.sql:16890-16913`) keep the run of estimates; `APPLICATION-CONTRACTS.md:236` (AC-21) says the same. Nothing raises a review: the only place the database opens a read exception by itself is the cap exception (`sql/tu.sql:17364`, the single insert into the exceptions table), and the list of exception rules (`sql/tu.sql:17093-17096`) has no entry for an out-of-order actual. The review would be the core's, filed under "other".

The same line then says "Not built: a reason for the review", which half-admits it, but the "Built" half is wrong as written. SCN-0142's settled note ("the built rule") has the same wording and should be corrected with it.

Fix: "Built: the run of estimates counts estimates dated after the latest validated actual (AC-21). Not built: the review itself (the core raises it; there is no rule for it in the exception list) and the catch-up method (CI-114)."

The counting itself is right, checked against the trigger: after the Nov 13 actual is validated it becomes the latest-dated actual, the Nov 15 estimate is still dated after it (run of 1), and a Dec 15 estimate makes 2, as (b′) says.

---

## Should-fix

### 4. SCN-0162's Open for Kyle is already settled by rule in SCN-0033, and the two give different due dates (lines 673, 674)

The Open asks: a departed customer has no next bill, so when is the hidden undercharge due, and can a penalty post on it?

`cancel-rebill.md:344` (SCN-0033, "Settled by rule, 2026-11-25, triage of Kyle's questions") already answers: "When the corrected bill is the final one, so there is no next regular bill, the hidden extra takes a new due date counted from the correction, using the utility's ordinary gap between issue and due date: any increase ages from the correction with a new due date (Kyle 11-03, answer 10), and answer 2 of 11-05 changed that only where a next regular bill exists." Item (iii) of the same note settles the penalty: unpaid after its due date, it takes a penalty like any charge with that due date. Kyle 11-03 answer 10 is at GBM `kyle-decisions-2026-11-03-scenario-batch-1.md:24`.

Two problems follow. First, the Open should not go to batch 8 as written; it is a "Settled by rule" citing SCN-0033 and Kyle 11-03 answer 10 (which SCN-0162 does not cite at all). Second, the due dates differ: SCN-0033's rule is "the correction date plus the ordinary gap" (Pecan Flat issues on the 20th and is due the 1st, 11 or 12 days, which from Dec 9 gives Dec 20 or 21); SCN-0162 uses "the next due day", Jan 1. Jan 1 is the better reading for a tariff with a fixed due day (SCN-0131: "a late bill keeps the due date its tariff states"), but then SCN-0033's wording needs "or the tariff's fixed due day where it has one". Pick one rule and state it in both places.

If anything is left for Kyle it is narrower: whether a penalty on a closed account's debt is wanted at all. That is a where-money-ends-up question, but SCN-0033 (iii) already treats it as settled.

### 5. SCN-0162 (a): the final bill's due date is never stated, and the Dec 4 payment may be late (line 666)

The final bill is issued Mon Nov 30. Pecan Flat's tariff makes a bill due the 1st (`cast.md` §1). If that means Dec 1, PF-08's $20.80 paid on Fri Dec 4 was late, and 10% ($2.08) posted on Dec 2. The correction then shows nothing was ever owed beyond the deposit, so that penalty must come off (Kyle 11-05 answer 1: re-assessed on the lower of the wrong and corrected bills). The scenario shows neither the penalty nor its reversal, and the $81.54 refund would be short by a paid penalty.

Fix: state the final bill's due date (Jan 1, if a bill issued after the 20th run takes the next 1st but one, or Dec 1), and either move the payment to before it or work the penalty and its reversal. (b) has the same gap in a harmless form.

### 6. SCN-0162: the next occupant's starting reading is not corrected (lines 666 – 673)

The wrong reading is a final reading, so it is also where the next customer at the house starts. In (a) the keyed 2,046.0 is above the meter's 2,040.6: the next occupant would get 5.4 Mcf free. In (b) the keyed 2,040.6 is below the true 2,046.0: the next occupant would be billed for 5.4 Mcf PF-08 used, on top of PF-08 paying for it on the corrected bill. SCN-0155 handles exactly this for its own case; SCN-0162 is silent. Kyle 11-03 answer 7 lets the operator "keep the keyed read as the prior read and catch up on the next read", which here would put the catch-up on a different customer.

Fix: one Then line: the replacement reading (reason "typo correction") is the reading both PF-08's corrected bill and the next occupant's first bill use; catching up on the next read is not offered when the next read belongs to another customer.

### 7. SCN-0155 (b): the $3.59, where it comes from and when (line 544)

"BB-22 was overbilled $3.59, which is refunded with the deposit's remainder ... BB-22 has no account left to hold a credit on."

- (a) says the $118.89 is refunded after the Dec 11 final bill; (b) on Jan 4 says the $3.59 goes "with the deposit's remainder". The Given never says whether the $118.89 had been sent by Jan 4, so a test cannot tell whether one refund of $122.48 or two ($118.89, then $3.59) is expected.
- By Kyle 11-03 answer 17 and SCN-0029 the $3.59 is itself a deposit refund, always paid out whatever its size. Cite it; that is the ruling that makes this line true, not "a refund is never held back" alone.
- "No account left to hold a credit on" sits badly with SCN-0029 ("The account cannot close until it is paid out", `deposits.md:150`).

Fix: give the refund date in the Given (as SCN-0029 does), say the $3.59 is paid out as a deposit refund (Kyle 11-03, answer 17), total $122.48.

### 8. SCN-0156 Status lists as built what the parity record gives to the core (line 554)

"Built: ... the customer charge is billed whatever the usage (CI-102)." The parity record grades CI-102 "requires-app-discipline": "Core must emit the customer-charge line for every active agreement, including zero usage, and must not let `skipped_no_read` drop it. No schema mechanism fits." (`invariant-parity-measurement-2026-10-13.md:411`). The schema can represent a fixed monthly charge; nothing bills it. A bill with a customer charge, no usage line and no reading behind it, marked "no reading this month", is also not something the schema is shown to support alongside a meter recorded as skipped for no read.

Fix: move it to "the core's (CI-102, no schema guard)", and add the customer-charge-only bill and its marking to Not built.

### 9. SCN-0159 and SCN-0160: the catch-up reading against the high-usage check (lines 607 – 623, 633 – 639)

SCN-0156 is careful to say the two-month read passes the 150% check "per month covered". The catch-up reads here are not treated:

- SCN-0160 (b): 8.0 Mcf on the December read against a three-month average of 4.0 is 200%.
- SCN-0159: 7.1 Mcf against an average of 2.3 is over 300%.
- SCN-0160 (a): the Nov 13 reading is 6.2 Mcf in 29 days against 4.0, and "is validated" without a word on the check.

Bluebonnet's check compares with the same month last year (SCN-0139), and neither Given supplies last year's figures, so a test cannot decide whether each reading passes, is held for a re-read, or is compared per month since the last actual. Fix: add last year's months to each Given and say that a catch-up reading is checked on the gas since the last actual reading, per month covered (as SCN-0156 does), or that it is held and released by a reviewer.

### 10. SCN-0160 (a): the meter's history now runs backwards, and the scenario doesn't say what the checks do (line 637)

After (a) the history reads 500.0 (Oct 15, actual), 506.2 (Nov 13, actual), 504.0 (Nov 15, estimate). The exception list has rules for a reverse read and for negative consumption (`sql/tu.sql:17094-17096`). The scenario should say which of these the review is, or that it is a separate one, and what usage the Nov 13 reading records (6.2 since Oct 15, billed to nobody directly). It should also say that the December usage is taken from the last billed reading (the estimate), not the latest-dated lower one; otherwise "512.0 − 504.0" is ambiguous for a test.

Also for the parity record: the CI-113 row still lists "D14-1b back-dated actual" as a question for Kyle (`invariant-parity-measurement-2026-10-13.md:422`). SCN-0142 and SCN-0160 now settle it by rule; note that for the next re-grade, or it will be asked again.

### 11. SCN-0161: GP-11's March bill is in the When but not in the Then; Gulf Plains' part-month setting is not in the cast (lines 649 – 655)

"When the March and April bills are issued" covers both customers, but only GP-10's March bill is worked. GP-11 has no Mar 1 reading in the Given, so its first bill cannot be built. Either give the reading and the bill ($10.18 plus gas) or restrict the When to GP-10's March bill and both April bills.

GP-10's $10.18 uses a share by days. `cast.md` §6 states that setting for Bluebonnet only ("Bluebonnet keeps the platform default"). The cast's own rule is "if a scenario needs a fact the cast doesn't have, add it here first": add Gulf Plains to that line (invented, until its tariff is drafted).

---

## Nits

12. **SCN-0157 (line 579):** "issuing it so is refused (SCN-0133)" does not say by whom. SCN-0133 says the core. Add "by the core". The rule's "A downward correction keeps the original due date" has no source on the line: it is Kyle 11-05 answer 2 (the amount already known keeps its due date) and SCN-0033.

13. **SCN-0161 (lines 647, 657):** the rulings cited (Kyle 08-18 D-3, requirement 2; Kyle 10-15 R-10) say read history is kept with the meter and the address. They do not say a new customer is estimated from the previous occupant's use; that step is this stream's reading, and the Rule line should say so, as SCN-0155 and SCN-0150 do. As a utility setting with a default it is rightly not asked of Kyle. A closer analogy is in the law itself: §7.45(7)(B)(v)(II) bases unmetered use on "consumption during other like periods by the same customer at the same location, when available, and on consumption under similar conditions at the same location or of other similarly situated customers, when not available" (`application/wave3-build-2026-10-18/sources/law-text/tac7-45.txt:568-573`). Worth citing as the analogy: it supports the address default, and it would also support "similar customers" as the supervisor's basis for GP-10.

14. **SCN-0158 (line 588):** (6)(C)'s last sentence supports the scenario directly and is not quoted: "If such a postcard is not received by the utility in time for billing, the utility may estimate" (`tac7-45.txt:482-484`), so a card received in time is billed on. That narrows batch 7's question 6 to its second half (does it count as the six-month actual).

15. **SCN-0155 (line 535):** the cited workflow says the final bill carries "a full customer charge" (`final-bill-generation.md:7`, `:22`), the opposite of the share by days used here and in SCN-0146. SCN-0146 settles that by rule (the schema's default, and canonical CI-102's "prorated only by the schedule's proration rule"), so nothing changes, but say the workflow is cited for its exception 1 only.

16. **SCN-0156, 0159, 0160:** Nov 15, 2026 is a Sunday. The cast says Bluebonnet reads on the 15th; only Gulf Plains is said to read weekends (SCN-0142). Harmless (SCN-0141 has the same), but one phrase in `cast.md` §6 ("weekends included") would close it.

17. **SCN-0156 (line 557):** "the same months last year" is late 2025, before Bluebonnet went live on the platform (Jan 1, 2026; "bills before that stay in its old system", `cast.md` §2). Say the usage history was loaded at go-live, or the check has nothing to compare with. The bills' periods are also unstated (which dates the customer-charge-only bill and the December bill each cover), which a test of the customer charge needs.

18. **SCN-0162 (b):** Fri Jan 1, 2027 is New Year's Day. Pecan Flat's tariff has no holiday rule, so the date stands, as in SCN-0131; "the next day" for the penalty is Sat Jan 2.

---

## Checks that found nothing

**Arithmetic (check 1).** All recomputed, four decimals, half-up per line:
- SCN-0155: 9.3 × 10 ÷ 31 = 3.0; $4.13, $8.88, $16.05, $1.74, tax on $30.80 = $0.31, $31.11; $118.89. Shares 2.5806 → 2.6 and 5.4. Corrected: $7.70 (7.696), $13.91, $1.51 (1.508), tax on $27.25 = $0.27 (0.2725), $27.52; $3.59. BB-23: $8.67 (8.6710), $15.98 (15.984), $28.89, $3.83 (3.834), tax on $57.37 = $0.57, $57.94. The "had it instead" bill at 5.0 Mcf: $54.31.
- SCN-0156: $49.10 (49.104), $77.04, $8.35 (8.352), $149.24; $163.99 with two charges.
- SCN-0157: $36.75; $9.84 + $8.16 + $15.00 = $33.00; $34.20 at $3.90.
- SCN-0158: $82.50; $29.11 + $24.14 + $15.00 = $68.25; 16.1 Mcf in all.
- SCN-0159: average 2.3; $35.59 ($7.84, $12.31 from 12.305, $0.69); $35.87 ($0.97); catch-up 7.1: $24.21, $37.99 (37.985), $4.12, $81.07. Other column: 2.4667 → 2.5, $37.71; 2.6, $38.62; 607.4, 6.6 Mcf, $76.40. Both add to 14.0 Mcf.
- SCN-0160: $51.47; $27.28 + $42.80 + $4.64 + $14.75 = $89.47.
- SCN-0161: 19 of 28 days, $10.18 (10.1786), $15.58, $12.92, $38.68; 0.2 a day × 31 = 6.2, $61.50; $78.00.
- SCN-0162: $120.80, $39.26, $41.21 at $6.85, $81.54 both ways, penalty $8.15 (8.154).
- Weekdays all correct (Dec 10 Thu, Dec 11 Fri, Dec 28 Mon, Dec 31 Thu, Jan 4, 2027 Mon; Nov 16 Mon, Dec 1 Tue, Dec 16 Wed; Oct 5, 2027 Tue, Oct 8 Fri, Oct 21 Thu, Oct 25 Mon; Mar 1, 2027 Mon, May 1 Sat, May 3 Mon, May 5 Wed; Nov 13 Fri, Nov 20 Fri; Feb 10, 2027 Wed, Mar 5 Fri, Apr 5 Mon; Nov 30 Mon, Dec 2 Wed, Dec 4 Fri, Dec 9 Wed, Jan 1, 2027 Fri). Dec 11 plus 15 days is Sat Dec 26, moved to Mon Dec 28, correct.

**Rulings (check 2), other than findings 1, 2, 4, 13.** Kyle 10-14 answer 6, "Keep every historical factor so rebills use the factor in effect at the time": exact (`kyle-decisions-2026-10-14-tax-jurisdictions-and-gas-cost.md:37`). Kyle 10-15 R-11, "Estimation, late fees and program exclusions all become dated rule data": matches (`...waves-1-to-7-and-texas-first.md:49`). Kyle 11-05 answer 2 as described. Kyle 07-10 D14-1 (per meter, reset only on a validated actual): matches. Batch 7 question 6 is the card question SCN-0158 says it is (`kyle-brief-2026-11-25-scenario-batch-7.md:26`). AC-21 says what SCN-0158, 0159 and 0160 take from it.

**Built / not built (check 3), other than findings 3 and 8.** Confirmed in `sql/tu.sql`: the reading method "customer reported" (3581); the three-month average and same-month-last-year methods in a fixed list of five (4211); the part-month setting with a share by days as default (4605, 4624); the choice not to estimate, per schedule and per meter (4204, 3766); the cap, its exception and its two resolutions (17293-17300; AC-20). A customer-reported reading is not an estimate, so it ends the run as built: SCN-0158's "estimates in a row 0" is right. One softening for SCN-0155: nothing in the schema stops a reading from being both an estimate and a final reading (no check ties the two), so "an estimated reading as a final reading" is representable today; what is not built is the core allowing it and the sharing between two customers.

**Consistency (check 4), other than findings 2, 4, 7.** SCN-0155 matches SCN-0146 on the day counts (10 and 21), $4.13 and $8.67, the due date and the 2026 taxes. SCN-0157 matches SCN-0149 (2.9 Mcf, $36.75, filed Fri Oct 8) and SCN-0133. SCN-0158 matches SCN-0142 (Mar 1 actual, 9.0 Mcf, $82.50, weekend reads). SCN-0156 matches SCN-0147's bracketed sentence. The cast rows match their scenarios; README's range and next free ID (SCN-0163) are right; the preamble's customer list is updated. No cast customer is reused on conflicting facts (GP-08 appears in SCN-0142, 0149, 0157 and 0158 with different 2027 histories, covered by "each scenario stands alone").

**Law (check 5).** No misstatement in the new section. (6)(C)'s card "for the second consecutive month" is applied correctly in SCN-0158 (April and May) and correctly not applied in SCN-0161 (first failed month). Nothing new is claimed about (6)(B)(viii), (4)(E)(vii), the scope, or §7.5519.

**Plain language (check 7).** No table or column names in SCN-0155 – 0162.

**Opens and "Settled by rule".** SCN-0155's Open (who pays for the gas across an estimated final reading) is a real where-money-ends-up question and belongs in batch 8. SCN-0156, 0159, 0160 and 0161's "Settled by rule" notes are bookkeeping or a utility setting with a default; none hides a money question, with the one caution in finding 13. SCN-0162's Open is finding 4.

---

## Gaps (within the cast)

1. **The minimum bill with tax** (round 8, my gap 6) is still open: SCN-0135 says the difference "would show" for a taxed customer and no scenario works it. PF-03, the café, would do.
2. **A self-read card that arrives after the bill.** SCN-0158 has it in time. A card dated May 1 arriving May 7, after the May 5 estimate was billed, is a customer reading dated the same day as a billed estimate: by AC-21 a same-day estimate beside an actual is not counted, so the run would clear, unlike SCN-0160's two-days-earlier case. Worth one scenario, since the two built rules give opposite answers a few days apart.
3. **A customer reading that fails the checks** (a card showing less than the last actual, or far more): held, re-read, or estimated for that month?
4. **An estimated final bill that was too low.** SCN-0155 shows only the over-estimate. With an actual of, say, 4,112.0, BB-22 owes more after the deposit's remainder has gone back: SCN-0162 (b)'s problem, reached through an estimate instead of a typo, and with no utility error in the ordinary sense.
5. **An estimated final reading with no next occupant.** The house stays empty and the next actual is months later, or is the utility's own lock-off reading. When is the final bill put right, and is all the gas the departed customer's?
6. **A back-dated actual that shows the estimate was too high.** SCN-0160 covers only "too low". SCN-0140's settled rule says an overcharge from a wrong reading is always rebilled, never left to catch up; SCN-0141 leaves an over-estimate to a credit on the next bill (an Open). A reading on file that proves the over-estimate sits between the two.
7. **An estimated move-out at Pecan Flat**, where the part month meets the $20.00 minimum (does a ten-day final bill carry the whole minimum?). SCN-0147 counts the minimum per month covered, and nothing says what a part month does.
