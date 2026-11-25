# Review (Fable), scenarios round 6, 2026-11-25

Scope: `scenarios/unmatched-cash-and-pledges.md` (SCN-0117 – 0129) with `scenarios/cast.md` section 5 and PF-06, PF-07, BB-16 (PRIMARY); the tax second-pass edits in commit 177b9bf to `scenarios/tax.md` and `scenarios/periods-and-aging.md` (SECONDARY).

Read against: `sql/v5.4.2-24-unmatched-cash-and-pledges.sql` (line numbers below are this file's, cited as "patch:N"), the -24 design, AC-48 to AC-53, `tac7-460.txt`, `tac7-45.txt`, `sql/v5.4.2-26-collections-decisions.sql` (the two conditions only), cash.md SCN-0081/0082/0084/0094, cancel-rebill.md SCN-0033, periods-and-aging.md SCN-0034. Nothing in the repo was edited. No database was run: every "refused" and "taken" below is from reading the guard, not from executing it.

Totals, PRIMARY: 4 errors, 6 rules stated as settled that are open (or the reverse), 12 missing cases, 8 nits. SECONDARY: 0 errors, 3 gaps, 2 nits.

---

## What checked out (PRIMARY)

**Arithmetic.** $3,846.83 + $65.83 = $3,912.66. $65.83 + $6.52 + $0.07 = $72.42; less $65.83 = $6.59. PF-06 $45.00 + $30.50 = $75.50 (SCN-0084's bill); PF-07 $27.00 + $18.30 = $45.30; $75.50 + $45.30 = $120.80; 10% × $45.30 = $4.53. $47.80 + $39.60 = $87.40; $87.40 − $50.00 = $37.40; $100.00 − $87.40 = $12.60. $75.50 + $40.00 + $64.80 = $180.30.

**Dates and weekdays (2026 unless stated).** Nov 16 Mon, Nov 20 Fri, Nov 27 Fri, Nov 28 Sat, Nov 30 Mon, Dec 1 Tue, Dec 2 Wed, Dec 3 Thu, Dec 4 Fri, Dec 7 Mon, Dec 8 Tue, Dec 10 Thu, Dec 14 Mon; Sep 5 Sat, Sep 10 Thu, Sep 11 Fri, Sep 14 Mon, Sep 21 Mon; Oct 14 Wed, Oct 20 Tue, Oct 25 Sun, Oct 26 Mon; Nov 2 Mon; May 31, 2027 Mon, Jun 1, 2027 Tue; Jan 7, 2027 Thu. All right.

**Day counts.** Sep 10 + 45 = Oct 25. Sep 14 + 30 = Oct 14. Dec 8 + 30 = Jan 7, 2027. Nov 27 to Dec 3 is 6 days, to Dec 7 is 10, to Dec 8 is 11; aged means age above the service level (patch:1457), so aged from Dec 8. Dec 2, 2026 to May 31, 2027 is 180 days, to Jun 1 is 181; past retention means age above retention (patch:1452), so from Jun 1.

**Refusals that a guard does make** (each one checked):

| Scenario | Claim | Guard |
|---|---|---|
| 0117 | payment from the receipt dated before Dec 2 | patch:828–832 |
| 0117 | customer's date after Dec 2 | patch:833–837, and on a later write patch:795–800 |
| 0117 | no reason or no operator | `payments_suspense_resolution_check`, patch:538–542 |
| 0117 | check details differ from the receipt | patch:838–843 (channel, source, reference, check number, date, bank) |
| 0118 | third payment; payment 2 at $45.31 | the dated cap, patch:621–640, run after insert patch:906–917 |
| 0119 | second undo of one return; undo of an undo | patch:1182–1187; patch:1171 |
| 0119 | report with no state or no reference | kind check, patch:440 |
| 0121 | payment to BB-01 before the return | the cap (a reversed payment still counts: only `voided` is left out, patch:626) |
| 0121 | return of $65.84; return dated Dec 6 | exactly the misposted share, patch:1120; on or after the last row under the posting entry, patch:1153 |
| 0122 | return of the bounced $75.50 to the receipt | share is 0 for a bounce, and a zero amount is refused (patch:446, 1120) |
| 0122 | bank return above $45.30 | the cap |
| 0123 | the re-sent transaction as a payment | patch:702–710, called from patch:816 |
| 0124 | app sends its own agreement or pay-by | patch:1208–1212 |
| 0125 | payment naming St. Brigid's pledge keyed as Coastal Prairie's | patch:862–866 |
| 0125 | agency payment with no agency | `payments_agency_check`, patch:532–533 |
| 0125 | payment toward the July bill for a pledge toward August | patch:870–874 |
| 0126 | lapse dated Oct 25; lapse before Oct 25 has ended at UTC−12 | patch:1305–1314 |
| 0126 | withdraw or lapse a pledge paid in full | patch:1294–1298 |
| 0126 | record in error after a payment, even a reversed one | patch:1286–1290 (only a voided payment is ignored) |
| 0126 | second ending | unique, patch:506 |
| 0127 | refund of agency money to the customer or another agency; refund of the customer's own naming an agency | patch:882–895, through `cash_money_agency` (overpayment credit and both reissues, patch:590–598) |
| 0128 | lapse of a pledge with no pay-by | patch:1300–1304 |
| 0128 | new pledge or agreement of a retired agency | patch:1219–1224; patch:286–290 |
| 0129 | payment from the agency's receipt marked as the customer's own | patch:844–848 |

**"Taken" claims that no guard refuses.** A payment after a lapse or withdrawal (only "recorded in error" refuses, patch:875–879). An agency paying more than it pledged (no cap; reads paid, patch:1476). A pledge with no agreement (agreement and pay-by left empty, patch:1237–1241). A second pledge of the same agency (no uniqueness). An agreement entered Dec 17 with effect from Dec 1 (nothing bounds the effective date). A retired agency's payment (the payment path never reads the agency's status). The same transaction id from another processor (the source system is part of the key, patch:698–706). "Pending counts nothing toward a pledge; a bounce or reversal counts nothing" (paid is the posting entry less what was taken back, -23's reader).

**Cast.** Section 5's service levels, retention, agencies, days and holds agree with every use. PF-06, PF-07 and BB-16 agree. GP-06 and BB-09 are cash.md's, as the file says.

---

## PRIMARY — errors

### P-E1. SCN-0124: the August bill cannot ground a disconnection on Sep 21 at Gulf Plains, so "$87.40 past due" is wrong
- **Claim (lines 190, 199, 202):** GP-06 "owes" $87.40, a disconnection is scheduled for Mon Sep 21, the pledge covers $87.40, and the second Open speaks of "the past-due amount ($87.40)".
- **Evidence.** Gulf Plains is the utility the Texas service rules bind (`cast.md` §3). `tac7-45.txt`: "The due date of the bill for utility service shall not be less than 15 days after issuance"; "A bill for utility service is delinquent if unpaid by the due date"; service "may be disconnected if the bill has not been paid ... within five working days after the bill has become delinquent and proper notice has been given". The August bill was issued Sat Sep 5, so it is due no earlier than Sun Sep 20 and cannot ground a disconnection before about Mon Sep 28. On Sep 10 (the pledge) and Sep 21 (the disconnection) only the July bill, $47.80, is delinquent.
- **Why it matters.** §7.460(b)(2) protects "a delinquent residential customer" where the agency is "forwarding sufficient payment to continue service". Sufficient is then $47.80, not $87.40, which changes the worked example in the second Open ("$50.00 of $87.40" would in fact be sufficient).
- **Fix.** Either move the disconnection to a date when both bills can ground it (for example Mon Oct 5, with the notice dates stated), or say that the disconnection is for the July bill's $47.80 and the agency chose to pledge both bills. Rewrite the second Open's example with a pledge below $47.80 (say $30.00).

### P-E2. SCN-0119 (d): money held seven months is reported to the state "on the next annual report", and the amounts may not go to the state at all for a city system
- **Claim (lines 83, 89):** after the returned check comes back on Jul 6, 2027, R1 and R2 are "reported to the state on the next annual report", "jurisdiction TX".
- **Evidence, part 1 (internal).** The Status line and the scenario's own Open say when the state's dormancy period ends is not known. `cash.md` SCN-0088 (c) and SCN-0103 put a December 2026 credit's escheat on Nov 1, 2030 ("the period is the state's rule", invented). (d) reads as if the utility's 180-day retention, once passed, makes the money reportable. Retention is when the utility must act (return it, or start the unclaimed-property clock); it is not the state's dormancy.
- **Evidence, part 2 (a citation check, from memory, not in the repo's sources).** Bluebonnet is a city. Texas Property Code ch. 76 has a city, county or school district keep unclaimed property of $100 or less itself (its own treasurer, its own claims process) and not report it to the Comptroller. R1 is $38.00 and R2 is $20.00. If that reading holds, "reported to the state" is wrong for both, and the title's "never to revenue" needs care, because the city's own unclaimed-money fund is where it ends. I could not verify this from `application/` or `law/`; treat it as a question to check, not a finding of fact.
- **Fix.** (d): "once the state's dormancy period has run (**invented**: reported Nov 1, 2030, as SCN-0103), each receipt is reported ...". Add to the Open: "For a city system, does Texas Property Code ch. 76 keep amounts of $100 or less with the city (citation check), and if so what is the record: the same 'reported' disposition naming the city's own report?" The database only needs a two-letter state and a reference (patch:440), so either answer fits the record.

### P-E3. SCN-0123 (b): the sentence says the penalty is reversed and that it stands
- **Claim (line 179):** "BB-01's penalty posted on Dec 2 is the core's to reverse, as in SCN-0117: the bill was due Dec 1, so paying on Dec 2 was late, and **the penalty stands**."
- **What is wrong.** The two halves contradict. The facts give "stands": customer's date Dec 2, due Dec 1.
- **Fix.** "Unlike SCN-0117, the customer's date (Dec 2) is after the due date (Dec 1), so the penalty posted on Dec 2 stands: resolving the receipt does not reverse it."
- **Also (line 170):** "Built (CI-055, v5.4.2-23 and -24)". The one-payment-per-transaction rule on payments is -19's (SCN-0094's Status; the patch's own comments at patch:686 and 816, "-19's unique index"). -24 extends it across receipts. Write "v5.4.2-19 and -24".

### P-E4. SCN-0118 (a): "neither takes Pecan Flat's 10% penalty" skips the penalties that posted on Dec 2
- **Claim (line 67):** "Both bills were paid by the 1st, so neither takes Pecan Flat's 10% penalty."
- **Evidence.** In (a) the receipt is resolved on Thu Dec 3. On Dec 2 both bills were unpaid on the books, so both penalties posted: 10% × $75.50 = **$7.55** on PF-06 and 10% × $45.30 = **$4.53** on PF-07. (b) says exactly this for PF-07 (line 69), and SCN-0117 shows the post-then-reverse for BB-01.
- **Fix.** "Both penalties posted on Dec 2 ($7.55 and $4.53) are reversed on Dec 3, each naming its penalty, reason: paid on time, received Nov 27 (as SCN-0117 (b))." A test built from the current wording would assert that no penalty row exists.

---

## PRIMARY — rules stated as settled that are open, and Opens a source answers

### P-R1. SCN-0124 (b) and SCN-0128 (a): "the tariff is silent, so the disconnection is blocked until the city records a rule" is a decision nobody has made
- **Claim (line 200):** at Pecan Flat, "Until Pecan Flat records a rule, the collections rule cannot evaluate the pledge and so blocks the disconnection (limit L2)." SCN-0128's title says the pledge "protects".
- **Evidence.** Limit L2 (patch:92–93; design §6) is about the *statutory* row: where 16 TAC §7.460 binds and wave 7 has not yet written the row, the condition is unevaluable. It says nothing about a city system that no statute binds and whose tariff is silent. -26 says only "Which count for which act where is wave 7's rule data" (`v5.4.2-26` line 221). The README's convention is the opposite default: "a city system's policy is its own tariff row, or nothing". So for Pecan Flat two readings exist: (1) silent means no protection, the pledge is on record and the cut-off goes ahead; (2) silent means unevaluable, and every city must state a pledge policy before it can cut off a customer with an open pledge.
- **Why it matters.** This is a rule conflict about whether a customer is cut off, not bookkeeping. Reading (2) also interacts with SCN-0120 (c): together, one missing setting or one missing policy row stops every disconnection at a city.
- **Fix.** Keep (b)'s facts, and replace the settled sentence with **Open (Ryan)**: "A city system whose tariff says nothing about pledges: is an open pledge no protection (the README's 'its own tariff row, or nothing'), or unevaluable, which blocks until the city states a policy at onboarding? Recommendation: require the policy at onboarding (as SCN-0120's second Open), so the answer is never 'silent'." The existing Open (Kyle, for city systems) asks what cities do in practice; this one asks what the platform does until a city says.

### P-R2. SCN-0124 (a): the Then states the two things its own first Open asks
- **Claim (line 199):** "§7.460(b)(2) bars a disconnection for that period. The CEAP agreement also makes the pledged $87.40 not delinquent until Oct 25."
- **Evidence.** The first Open (line 201) asks whether the agreement's "not delinquent" holds to Oct 25 or the statute's billing period ends the protection on about Oct 4. The vendor agreement's term is conditional ("not delinquent *if paid within* the 45 days", design source VA-26), and it is a contract between the agency and the utility, not a rule the customer holds. Also "the billing period of the Sep 5 bill ... ends around Oct 4" is ambiguous: the bill issued Sep 5 is for the period that *ended* about Sep 5; the period Sep 11 falls in is the one billed about Oct 5.
- **Fix.** Then: "The Sep 21 disconnection is not carried out: the pledge was received in the billing period that Sep 21 also falls in (about Sep 5 to Oct 4, billed Oct 5), on either reading of §7.460(b)(2)." Move the agreement's effect wholly into the Open. Name the period by its dates, not by a bill.

### P-R3. SCN-0124, third Open (verbal pledge): the statute's text answers it for Gulf Plains
- **Evidence.** `tac7-460.txt` (b)(2): "a written pledge, letter of intent, purchase order, or other written notification". Every form listed is written. A phone pledge does not trigger (b)(2). What is open is narrower: (1) whether a pledge through an agency's web portal (the record's third form) is "other written notification"; (2) whether Gulf Plains has filed a more protective tariff under §7.460(e); (3) what a city does.
- **Fix.** Replace the Open with: "By its text §7.460(b)(2) needs a written notice, so a pledge by phone does not protect at Gulf Plains until its letter arrives (the record carries the form). **Open (Kyle):** does a pledge entered in the agency's portal count as written?" Add a Then line: a verbal pledge recorded Sep 11 followed by the letter on Sep 16 is two facts on one pledge or two pledges? The record has one form per pledge and it is never edited, so today the letter is a second pledge and the first is recorded in error. That is worth its own line, or an Open (Ryan).

### P-R4. SCN-0124: "received" is when the utility keyed the pledge, not when it arrived
- **Claim (line 197):** "received Sep 11 (the database's time)".
- **Evidence.** The pledge's only receipt stamp is the database's recording time (the table at patch:461; its comment at patch:493, "created_at the database's (when the utility recorded it)"). §7.460(b)(2) turns on the billing period "in which the provider receives" the pledge. A letter that arrives Fri Oct 2 and is keyed Mon Oct 5 is recorded as received in the next billing period. SCN-0128 (b) makes this concrete: the pledge of Dec 8 is recorded in error and recorded again on Dec 17, so its recorded receipt moves nine days.
- **Fix.** Add a When to SCN-0124: the letter arrives the last working day of a billing period and is keyed the next working day. Then: **Open (Ryan)**: the record cannot say the pledge arrived earlier than it was keyed; is the recording time good enough for the statute's "receives", or does the pledge need the utility's own stated receipt date beside the database's (an additive schema change)? Add the same note to SCN-0128 (b).

### P-R5. SCN-0118, last line: a landlord's overpayment refunded "to the customer" is stated as settled
- **Claim (line 70):** "Each payment is the customer's own, not an agency's, so a later refund of it goes to the customer."
- **Evidence.** The database's rule is only that the refund names no agency (patch:890–893); who the cheque is made out to is not a record. CI-053's "refund to whoever sent it" governs held money. Once resolved, the design treats it as the customer's (table comment patch:219: "A relative or landlord paying is the customer's own payment"). But SCN-0122's Open already asks Kyle whether a third party's bounced check should charge the tenant, which is the same question from the other side.
- **Fix.** Keep the database statement ("names no agency"), and add to SCN-0122's Open or here: "**Open (Kyle):** if the landlord's check overpaid, is the refund the tenant's or the landlord's?"

### P-R6. SCN-0126 (d): a pledge keyed for the wrong customer that took a payment can only be "withdrawn by the agency"
- **Claim (line 239):** "The operator reverses the payment under the cash rules and withdraws the pledge with the reason."
- **Evidence.** That is what the guards allow (patch:1286–1298), so the claim is right. But the record then says the agency withdrew a pledge it never made for that customer, and the wrong customer's history shows a real pledge that protected them from Sep 11 until the withdrawal. If (d) follows (a)'s lapse, even the withdrawal is refused (one ending per pledge, patch:506) and the miskeyed pledge stays "lapsed" for good.
- **Fix.** Say which branch (d) continues ("(d) apart from (a): before any lapse"). Add: "**Open (Ryan):** a miskeyed pledge that took a payment can never read as an error, only as withdrawn (or lapsed). Accept that, with the reason carrying the truth, or let 'recorded in error' be recorded once every payment naming it is reversed or voided (a change to the guard)?"

---

## PRIMARY — missing cases (ranked)

1. **An agency's payment bounces after the pledge read paid.** Coastal Prairie's $87.40 posts Oct 20 (paid), and the check is returned Oct 28, after the pay-by date. Paid is derived (patch:1249–1258, 1476), so the pledge reads paid on Oct 20–27 and overdue from Oct 28; the core may then record the lapse (dated after Oct 25, patch:1305). What protected GP-06 between Oct 26 and Oct 28, and does the customer get notice before a disconnection resumes? This is the pledge-side twin of SCN-0122 and the most likely real event not covered.
2. **Agency money moved into a credit the database cannot trace (limit L6; AC-52).** SCN-0127's Status names L6 but no Then exercises it. Case: GP-06 has a second account, and the operator transfers the agency's $12.60 to it. A transfer credit has no typed source, so a later refund of it reads as the customer's own and is *accepted* with no agency (patch:590–601). The scenario must say the core refuses the transfer (AC-52: "The core does not move agency money into such a credit"). Without it a test suite would pass a core that launders agency money to the customer.
3. **The agency's money held unidentified while its customer is cut off (limit L1 at SCN-0129).** The $64.80 for "D. Reyes" arrives Mon Dec 7 with no candidate. Pecan Flat cuts off on Thu Dec 10. The receipt is 3 days old (not aged) and names nobody, so PF-06 is cut off on Dec 10 and identified on Dec 14. Add as SCN-0129 (c), with the Open already in SCN-0120 (should money protect from the day it came?) and a second: should intake list as candidates every customer with an open pledge from that agency?
4. **A payment from a receipt keyed to the wrong customer and caught before it posts.** It is voided, not reversed: a voided payment never counted, so the receipt holds its money again with no return (patch:626; design §2.3). SCN-0121 only shows the reversal path; the two paths differ in what the operator must do next, and a core that asks for a return after a void will be refused (patch:1099–1104).
5. **A bank take-back learned after the payment was reversed as misposted (AC-51).** SCN-0122 cites AC-51 but does not use it. Case: SCN-0121 (a) on Dec 7 after the reversal, then on Dec 9 the bank returns the check. The reversed payment takes no return code afterwards (patch:762–766); the money is returned to the receipt as misposted, then recorded there as returned by the bank, and the payment to BB-01 made on Dec 7 from it must itself bounce under the cash rules. Worth one scenario: it is the order of acts the contract prescribes and nothing else shows it.
6. **Between the reversal and the return, the money is on no account and not on the receipt (AC-49).** In SCN-0121 (c) say that on Dec 7, until the return is recorded, BB-16 owes $71.40, the receipt holds $0.00, and the $65.83 appears only on the list of returns owed; a suspense reconciliation adds held money and returns owed. Then the month-end version of the same: limit L4, the close's snapshot carries no held-money line, so November's close with PF-07's $45.30 (received Nov 27) held reconciles to the bank only with the held figure added.
7. **Money that came in a month already closed.** A receipt's date is frozen by the close (patch:1665–1666). A lockbox item with the bank's date Mon Nov 30, first loaded after November closed, is refused with that date and must be dated in December. Its age then starts late and its customer's date may still be Nov 28 (effective no later than the receipt's date, so an earlier date is allowed). SCN-0117's last bullet covers resolving after the close, not recording after it. Same for a utility going live with unidentified money from its old system (design §2.1 says such a receipt "keeps its true age"; the freeze says it cannot if that month is closed). Possibly an Open (Ryan).
8. **The pay-by date does not move when the agreement changes.** The Rule in SCN-0124 says "it never changes", but no When tests it. Case: on Oct 1 Gulf Plains enters a new agreement with Coastal Prairie, 60 days; the Sep 10 pledge still reads pay by Oct 25, and a pledge dated Oct 2 gets Dec 1. And: an agreement entered in error is withdrawn; pledges already recorded under it keep it (function comment, patch:327).
9. **The agreement's eligibility hold (5 business days) is in the cast and in no scenario.** The vendor agreement keeps service on for up to five business days while the agency decides eligibility, before any pledge exists. Nothing in -24 records "the agency is checking this customer": a pledge needs an amount above zero. Either a scenario with an **Open (Ryan/Kyle)** on how the hold is recorded, or a note that it is the collections rules' and not yet written.
10. **A receipt partly returned and partly resolved.** $120.80 received; $75.50 to PF-06; the landlord asks for the other $45.30 back; later says it was PF-07's after all (undo the return if the check was not cashed, else nothing to pay with). Exercises the cap across payments and dispositions on one receipt, which only SCN-0122 touches.
11. **A clerk keys St. Brigid's money as Coastal Prairie's and names Coastal Prairie's own pledge.** SCN-0125 (b) is refused only because the payment names St. Brigid's pledge. Keyed with Coastal Prairie's agency *and* Coastal Prairie's pledge, restricted to the July bill, nothing refuses it: Coastal Prairie's pledge reads paid with another agency's money. State it as the core's (and the reconciliation's) to catch.
12. **A pay-by date on a weekend.** Oct 25 is a Sunday. The database adds days and never rolls (patch:1240). Does the agency have until Monday? One line, or an Open (Kyle).

---

## PRIMARY — nits

- **N1 (line 7).** "no guard reads one except the disconnection bar" — no database guard reads a candidate at all (table comment, patch:405); the bar is the core's, reading the aged list. Write "nothing in the database acts on one; the core reads them for the disconnection bar".
- **N2 (line 213).** SCN-0125 says "GP-06's $87.40 (SCN-0124 (a))" and then gives Coastal Prairie a $47.80 pledge, not SCN-0124's $87.40. Say "here Coastal Prairie's pledge is instead $47.80 toward the July bill".
- **N3 (line 163).** "PF-07's bill is unpaid as of Nov 27" reads oddly: it is simply unpaid, and was never paid. Also say the receipt, now holding $0.00, drops off the aged list, so SCN-0120's bar on PF-07 ends on Dec 4.
- **N4 (line 249).** "pays its final bill itself, so the agency's $12.60 is still left" assumes the leftover did not pay the October and November bills. That is SCN-0082's Open (does an unassigned remainder pay the next bill anyway?). Say "(invented: the remainder was neither applied nor approved as a credit)".
- **N5 (lines 97, 186).** The Status lines name `aged_suspense` and `agency_pledge`, which are schema vocabulary; the README asks for none. "the collections rules' condition for aged held money (-26)" does the job.
- **N6 (line 229).** "has passed everywhere" is the database's rule in its own words (the day has ended in every time zone). Say so once: "after the pay-by day has ended in every time zone".
- **N7 (line 86).** The past-retention flag comes from the same list as the aged list, which refuses to run while the *service level* is unset (patch:1443–1448). So at a utility with retention set and no service level, nothing can be listed as past retention either. One clause.
- **N8 (line 10 and `cast.md`).** The file does not say, as cash.md does, that "each scenario stands alone unless it says it continues another". PF-06 is the landlord's tenant with a $75.50 bill in SCN-0118 and "D. Reyes's household" paid by an agency in SCN-0129; PF-01's $75.50 pledge reuses SCN-0084's bill. Add the sentence.

---

## SECONDARY — the tax second-pass edits (177b9bf)

**What checked out.** Hospital district and transit authority at 0.125%: 0.125% × $187.40 = 0.23425 → 0.2343 → $0.23 each; BB-13 $202.39 + $0.23 + $0.23 = **$202.85**; the difference to BB-10 is **$0.46**. Local totals: east of Main 1 + 0.5 + 0.25 + 0.125 + 0.125 = 2.0% in 2027 to Sep 30; from Oct 1, 2027, 1.25 + 0.5 + 0.25 = 2.0% everywhere. SCN-0109's figures are unchanged and still right ($0.81, $2.34, $66.15, $202.86; short by $0.16 and $0.47); Oct 1, 2027 Fri, Oct 5 Tue, Nov 15 Mon, Nov 20 Sat. SCN-0108 (e) now splits $0.65 (city, §321.3025) from $0.16 (district, no rule read) and the Open still asks about the $0.81. SCN-0108 (f) now records both memberships from Jul 1, matching its table row. SCN-0114's "no December bill" makes the December "billed" column the penalty's tax alone, as tabled; $201.92 + $20.19 − $100.00 = $122.11. `cast.md` line 73 and tax.md's header agree with SCN-0115 and SCN-0109. No stale "$203.80", "$1.41", "0.5% transit" or "outside the limit" remains in `scenarios/`, the batch-5 brief or `places-sources/texas.md`. The SCN-0109 (e) rewrite matches what the second-pass review found the database does (one approval: a silent difference between two reads; two writers: refused for good).

### S-G1. SCN-0105 still says "the local rates add up to 1.75%" without saying where (tax.md line 73)
- Not touched by the commit, and now location-dependent: 1.75% is west of Main; east of Main it is 2.0% from Jan 1, 2027. BB-01's and BB-15's side of Main Street is not in the cast (BB-10 is west). The figures do not change, because the two eastern taxes never reach a home.
- **Fix.** "West of Main Street the local rates add up to 1.75% (east of it 2.0%, SCN-0115) ...", and give BB-01 and BB-15 a side in `cast.md` so a test fixture has one.

### S-G2. The transit authority's 0.125% may not be a rate Texas allows (citation check, from memory)
- The second pass chose 0.125% each to fit under 2%. City, county and special-district rates move in eighths of a percent, but a transit authority's rate is, as I recall the Transportation Code (ch. 451, 452, 460), one of one-quarter, one-half, three-quarters or one percent. The repo's sources do not say; I did not fetch the statute.
- **Why it matters.** The README bars a scenario from implying something untrue about Texas. A reader who knows transit rates will stop at 0.125%.
- **Fix if confirmed.** Keep the transit authority at 0.25% and drop the hospital district east of Main to none-in-2027, or make the eastern pair "a hospital district 0.25%" alone plus a transit authority that covers a *different* strip. The smallest change that keeps both places: transit 0.25%, hospital district 0.125%, crime-control district east of Main unchanged, county 0.5%, city 1% = 2.125%, which does not fit; so one of the two eastern places has to go, or the county rate has to be lower for everyone (which moves SCN-0104 to 0116). Worth asking the tax advisor before choosing.

### S-G3. periods-and-aging.md line 194: the left-out district tax is a figure that waits on Kyle, and nothing tracks it
- "BB-01 owes $65.83 on a bill dated Jan 15, 2027 (... the crime-control district's tax from Jan 1 is left out ...)". The bill's period (Dec 15 – Jan 14) straddles the tax's start, so the note is right that SCN-0108's Open governs. But two of that Open's three answers make this bill $65.99 or a split figure, and the aging table built on $65.83 changes with it.
- **Fix.** Add "(figure to revisit when Kyle answers batch 5's question on a straddling bill)" here, or avoid the dependency: date the bill Dec 15, 2026, before the district exists, if the scenario's aging dates allow.

### Nits
- **S-N1 (tax.md line 284, SCN-0113 (e)).** The added parenthesis, "(b) likewise needs a loaded place, since the place is checked before the decimals", is a note about (b) placed inside (e). Move it to (b).
- **S-N2 (`cast.md` line 73; SCN-0115).** The hospital district and transit authority have an end (Sep 30, 2027) and no start. A fixture needs one; SCN-0114's "the only taxed bills" in November 2026 is safe only because BB-13 is not in it. Say "from Jan 1, 2027 (invented)" or "throughout 2026".
