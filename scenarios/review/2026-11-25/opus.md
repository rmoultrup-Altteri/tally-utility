# Opus review: scenarios round 6 (2026-11-25)

Scope: PRIMARY `scenarios/unmatched-cash-and-pledges.md` (SCN-0117 – 0129) and `scenarios/cast.md` section 5 and the customers PF-06, PF-07, BB-16. SECONDARY: commit 177b9bf's changes to `scenarios/tax.md` and `scenarios/periods-and-aging.md`.
Checked against `sql/v5.4.2-24-unmatched-cash-and-pledges.sql` (cited as `-24:line`), the -24 design, AC-48 to AC-53, the 16 TAC 7.460 text, the -26 design and -30's levy check. No repo file was edited.

I checked every weekday, every day count, every pay-by date and every age with a script. All of them are right: Nov 16 Mon, Dec 1 Tue, Dec 2 Wed, Nov 28 Sat, Nov 27 Fri, Dec 3 Thu, Dec 8 Tue, Dec 10 Thu, May 31 2027 Mon (180 days), Jun 1 2027 Tue (181 days), Jul 6 2027 Tue, Sep 5 Sat, Sep 10 Thu, Sep 11 Fri, Sep 21 Mon, Oct 25 Sun (Sep 10 + 45), Oct 14 Wed (Sep 14 + 30), Jan 7 2027 Thu (Dec 8 + 30), Dec 14 Mon, Nov 2 Mon. The penalty figures ($6.52 + $0.07, from SCN-0033) and the Pecan Flat bills ($75.50, $45.30) are right. The reconciliations add up ($3,846.83 + $65.83 = $3,912.66; $75.50 + $45.30 = $120.80; $75.50 + $40.00 + $64.80 = $180.30).

---

## PRIMARY: findings, most severe first

### P1. SCN-0119 (d): money is reported to the state long before Texas law makes it reportable, and the Open asks a question the repo's own sources answer
- **Claim:** "R1 and R2 are reported to the state on the next annual report". The Open asks Kyle for "Texas's dormancy period for a utility's money with no known owner".
- **Evidence:** the repo's Texas-only audit already lists the rules: a 3-year general dormancy (Tex. Prop. Code §72.101), shorter periods for deposits (§72.1017), a reporting cycle, and a $250 due-diligence threshold (§74.101). See `application/texas-only-audit-2026-09-28/08-gbm-docs.md:45` and `:462`, and `01-base-part1.md:122`. A receipt from Dec 2, 2026 is not presumed abandoned until about Dec 2029. "The next annual report" after a 180-day retention is premature under the general rule. The design also leaves when a report is due to the core, which reads the state's dormancy rule (`v5.4.2-24-design.md` §2.3 item 4).
- **Fix:** date (d) to when the state's dormancy period has run, as the core computes it, or make it "(d) when the core lists them as due under Texas's dormancy rule". Rewrite the Open to cite §72.101 and §74.101 and ask only what is still unknown: which dormancy class unidentified utility receipts fall in, and whether retention should be set to match. Note that retention (180 days) and dormancy (3 years) differ, and only returning the money to whoever sent it fits inside the retention period.

### P2. SCN-0125 (b): the database does not refuse the mis-keying as described; it refuses only one version of it
- **Claim:** St. Brigid's $39.60 "keyed as Coastal Prairie's" is "Refused: a payment naming St. Brigid's pledge must be St. Brigid's."
- **Evidence:** the check at `-24:862-866` refuses only a payment whose agency differs from the agency of the pledge it names. Suppose the clerk keys the payment entirely as Coastal Prairie's: Coastal Prairie as the agency, Coastal Prairie's pledge, and restricted to the July bill as that pledge requires (`-24:870`). Then nothing refuses it. It posts as Coastal Prairie's money and pays the July bill. A later refund of it would then go to the wrong agency (`cash_money_agency`, `-24:592-596`).
- **Fix:** split (b). In (b1), St. Brigid's pledge is named with Coastal Prairie as the agency, and it is refused. In (b2), the payment is keyed wholly as Coastal Prairie's, and it is accepted: the database cannot tell who wrote the check, so matching the check to its agency is the core's and the operator's job. Optionally add an Open (Ryan) on whether intake should check the remitter's name on the instrument against the agency.

### P3. SCN-0118 (a) and (b): the late penalty contradicts the scenario's own logic and SCN-0117's
- **Claim (a):** "Both bills were paid by the 1st, so neither takes Pecan Flat's 10% penalty." **Claim (b):** only PF-07's penalty ($4.53) posts on Dec 2.
- **Evidence:** in both branches the payments are recorded on Dec 3 or later. A payment from a receipt is posted when it is identified, with its customer's date no later than the day the money came (`-24:808-817`). On Dec 2 both bills are unpaid on the books. By (b)'s own reasoning ("On Dec 2 PF-07's bill was unpaid on the books, so its penalty posts") and by SCN-0117 (b), both penalties post on Dec 2 and are reversed when the on-time payment is recorded. Those are PF-06 10% × $75.50 = $7.55, and PF-07 $4.53. (b) also leaves out PF-06's $7.55, which posts on Dec 2 and is reversed on Dec 3.
- **Fix:** in (a), write "both penalties post on Dec 2 ($7.55, $4.53) and are reversed on Dec 3, because the customer's date Nov 27 is on time", or show the entries. In (b), add PF-06's $7.55, posted Dec 2 and reversed Dec 3. SCN-0117's Open (hold penalties on a receipt's candidates?) applies here too, but these receipts list no candidates, so even a "yes" there would not stop these penalties. That is worth one sentence.

### P4. SCN-0127: the agency's $12.60 would not still be "left" under the cash family's own rules
- **Claim:** the agency pays $100.00 on Oct 20, the pledge reads paid, "$12.60 is left on the agency's payment", and it is still left at move-out on Dec 14.
- **Evidence:** GP-06 is billed monthly around the 5th (SCN-0124's Given). So the September bill (issued around Oct 5) is open on Oct 20, and the October and November bills follow. A payment with no direction pays the oldest open bill first (SCN-0081). A remainder after every open bill is either not taken or held as a credit with approval (SCN-0082; Kyle R-06). Nothing makes the $12.60 sit unapplied for eight weeks. The pledge in SCN-0124 is not toward a bill, so no restriction stops it either (`-24:870`). "Not refused: the money is real" also skips SCN-0082 (a)'s "not taken" option, which cannot be used for a mailed agency check. That is SCN-0082's Open.
- **Fix:** either restrict the agency's payment to the July and August bills (the agency's direction, D7-1) and say the $12.60 is held as a credit with approval, which is then the Open's approval question; or say the $12.60 paid part of the September bill and set the leftover at move-out in some other way. Also cite SCN-0082's Open for an agency's overpayment that arrives with nobody at a counter to ask.

### P5. SCN-0126 (a): once the lapse is recorded, the pledge reads "lapsed", not "overdue"
- **Claim:** "From Oct 26 the pledge reads *overdue* ... The core records the lapse dated Mon Oct 26."
- **Evidence:** the pledge reader returns the event's state from the event's date before it checks the pay-by date (`-24:1476-1480`: `WHEN e.event IS NOT NULL AND e.event_on <= p_on THEN e.event` comes before `WHEN p_on > l.pay_by THEN 'overdue'`). The open-pledge list also drops a lapsed pledge (`-24:1501`: only open, overdue and no agreement are listed). A test that asserts "overdue" after the lapse fails.
- **Fix:** "From Oct 26 it reads *overdue* until the lapse is recorded. Once the lapse is recorded, dated Oct 26, it reads *lapsed* from Oct 26 and leaves the open-pledge list. (b) then reads *paid* from Nov 2, because paid in full outranks the lapse (`-24:1477`)."

### P6. SCN-0119: R2 as written cannot be recorded
- **Claim:** R2 is "$20.00 in cash in the night drop ... in an envelope marked only 'gas'". It is held, then reported.
- **Evidence:** a receipt must carry at least one research field with content: a reference, a provider id, a check number, a payer name, an account as written, an evidence reference, or an agency (`-24:378-383`). R2 as described has none of them, and the insert would be refused.
- **Fix:** say R2 is recorded with the night-drop log entry or an image of the envelope as its evidence, and add "a receipt with nothing to research it by is refused" to the Then. This is also a useful refusal to test.

### P7. SCN-0120 (a): "The $20 service charge is not added" is stated as settled
- **Claim:** the aged receipt holds PF-07 off the cut-off list, and "The $20 service charge is not added."
- **Evidence:** Pecan Flat's tariff (`cast.md` §1) says that when a bill is unpaid at 1:00 p.m. on the 10th, a $20 service charge is added and service is cut off. Whether a bar on the cut-off also stops the charge is a reading, and the -24 patch decides neither. In -26 a late fee is a separate act with its own decision (`v5.4.2-26-design.md` C7). Which acts an aged receipt bars is wave 7's rule data (design §2.4).
- **Fix:** make it an Open (Kyle): is the $20 charged for being unpaid at 1:00 p.m. on the 10th, or for the cut-off itself, and does a hold for unidentified money stop it? Alternatively, mark it as the collections rule's call (-26 and wave 7).

### P8. SCN-0124 and SCN-0128: the day a pledge was "received" is the moment it was keyed, which matters for 16 TAC 7.460(b)(2)
- **Claim (0124):** "received Sep 11 (the database's time)". **Claim (0128 (b)):** record the pledge in error and record it again. Here the new pledge's receipt becomes Dec 17.
- **Evidence:** a pledge has no receipt date the app can supply. The only record of receipt is the database's stamp of when it was recorded (`-24:446`, `created_at`; the design called it `received_at`, §4.1). The Texas rule protects "for a billing period in which the provider receives" the pledge (`tac7-460.txt`, (b)(2)). Take a pledge that arrives on the last day of a billing period and is keyed on the next workday. It is recorded in the next period. In SCN-0128 (b), recording the pledge again moves its receipt from Dec 8 to Dec 17, and the first record now reads "recorded in error" although it was correct.
- **Fix:** add an Open (Ryan; schema). Should a pledge carry the day it was received, supplied by the app and no later than the recording stamp, beside that stamp? That would be an additive column. Alternatively, should the core treat the stamp as the receipt date and require same-day keying? Add a variant to SCN-0124: a pledge received Fri Oct 2 and keyed Mon Oct 5, across the Oct 5 bill. In SCN-0128 (b), say what the re-recording costs: the receipt date moves, and the history shows an error that was not one.

### P9. SCN-0123 (b): the late-penalty sentence contradicts itself
- **Claim:** "BB-01's penalty posted on Dec 2 is the core's to reverse, as in SCN-0117: the bill was due Dec 1, so paying on Dec 2 was late, and **the penalty stands**."
- **Fix:** "Unlike SCN-0117, the penalty stands. The customer's date is Dec 2 (the sent date), after the Dec 1 due date, so there is nothing to reverse." The rest of (b) is right: a payment from a receipt carries no provider transaction id (`-24:540`), and (a)'s refusal holds (`-24:695-700`, matched on source system and transaction id).

### P10. SCN-0122: wrong contract cited, and the bounce's effect on the penalty is left out
- **Evidence:** AC-51 (`APPLICATION-CONTRACTS.md:487`) covers a bank's take-back learned after a receipt's payment already ended reversed. SCN-0122 is the ordinary bounce. The claims themselves hold. The bank's return is capped at what the receipt holds (`-24:600-627`). A return of the $75.50 to the receipt is refused, because what was posted wrongly comes to $0 once the bounce rows are left out (`-24:972-979`) and an amount must be exact (`-24:1116`). PF-06's Dec 2 penalty, reversed on Dec 3 (see P3), is back in question once the check bounces. That is SCN-0084's second Open.
- **Fix:** cite AC-51 only in a new variant that covers its own case (see M3), and cite design §2.3 item 3 here. Add one line: "Whether PF-06's Dec 2 penalty, reversed on Dec 3, is charged again is SCN-0084's Open."

### P11. SCN-0126 (d): a keying error is recorded as the agency withdrawing the pledge, and the $50.00 never reaches the right customer
- **Evidence:** "recorded in error" is refused while any payment that is not voided names the pledge. A reversed payment still counts (`-24:1286-1291`), so the claim is right. But "withdrawn" means the agency cancelled the pledge (design §4.2), and here the agency did not. The scenario also stops before the agency's $50.00 is posted to the right customer under a new pledge.
- **Fix:** say the withdrawal's reason records the keying error and that this is the only way out the record offers (`-24:1304-1308` names it). Add the next step: a new pledge for the right customer, and the $50.00 posted to it as a new agency payment. Optionally, Open (Ryan): should an operator's correction be its own ending, separate from the agency's withdrawal?

### P12. Cast consistency
- GP-06 and BB-09 are now used by two families, but they are not in `cast.md`'s customers table, and `cash.md:10` still says "used only here". The cast rule says "If a scenario needs a fact the cast doesn't have, add it here first" (`cast.md:5`). Add GP-06 and BB-09 to the table, and update `cash.md:10`.
- Gulf Plains's billing day ("monthly around the 5th", **invented**, SCN-0124) and its due dates belong in `cast.md` §3. SCN-0124 needs GP-06 to be "delinquent" on Sep 21, but no due date is stated anywhere.
- Pecan Flat has no "when a payment counts as made" row. SCN-0118 uses the day received at the counter, and SCN-0120 relies on it. Bluebonnet has this row in §2; add one to §1, **invented**.
- Section 5: the agreements run "from Jan 1, 2026, the CEAP vendor agreement", but design source VA-26 is the August 2026 revision. Name it as an earlier revision, or start the agreement from Aug 2026 (it is invented either way). The five business days' eligibility hold is in the cast, but no scenario uses it (see M7).

### P13. Sources that don't say what they are cited for
- SCN-0117 cites "Ryan 10-16 (suspense is never applied to a guessed account)". The 2026-10-16 decision-log entry (`DECISION-LOG.md:328`) is the -23/-24 split. The rule is CI-053's and the wave-2 inventory's U2 (`source-inventory-wave2.md:98`). Cite those instead.
- SCN-0118's "A landlord's or relative's check is the customer's own payment" has a ruling: Ryan 2026-11-07 (`DECISION-LOG.md:95`, "A relative or landlord paying is the customer's own payment"). Cite it. It also settles where a refund of that money goes (to the customer), which SCN-0118's last bullet relies on.

### P14. Smaller consistency points
- SCN-0124 (b): "the same pledge reaches Pecan Flat for PF-01", for $87.40. PF-01's bill is $75.50 (SCN-0084). Give PF-01's own amount.
- SCN-0129: the PF-01 and PF-02 pledges have no pledge dates, so their pay-by dates and their state on Dec 7 cannot be checked. Add dates, for example pledged Nov 20 with pay-by Jan 4, 2027.
- SCN-0125's Given says "GP-06's $87.40 (SCN-0124 (a))" and then gives Coastal Prairie a $47.80 pledge. Say it replaces SCN-0124's $87.40 pledge.
- Common section: "no guard reads one except the disconnection bar". The bar is not a database guard. The aged list returns the candidates (`-24:1449`), and the core applies the bar (-26). Write: "no guard reads one; the aged-receipt list returns them for the collections rule's bar."

### P15. Plain language (README: rules, not tables)
- SCN-0122's Rule line says "design §2.3 (kind 3)". Write "the bank takes it back (design §2.3)".
- Status lines name the condition codes in backticks (`-26 aged_suspense`, `-26 agency_pledge`). Say "the collections rule's bar for aged held money" and "its protection for a pledge", with the code after as a pointer at most.
- SCN-0128's "state *no agreement*" and SCN-0119's "jurisdiction TX" are reader and column vocabulary. They are acceptable as quoted outputs, but "it shows as having no agreement" reads better.

---

## PRIMARY: claims verified as built (no change needed)

- Payment dated on or after the receipt, customer's date no later than the receipt: `-24:808-817` (insert) and `-24:762-767` (later). Posting in the open month with a customer's date in a closed month is allowed, because the close freezes the payment date, not the customer's date (`tu.sql:40948`).
- Payment carries the receipt's instrument: `-24:818-824`. A reason and an operator are required: `-24:536-540`.
- The cap on every date, with a reversed payment still counted (only a voided payment is excluded): `-24:600-627`. That supports SCN-0118's $45.31 and its third payment, SCN-0121 (c), and SCN-0122's bank return above $45.30.
- SCN-0121's return: it must be exactly what was posted wrongly ($65.84 refused, `-24:1116`) and dated on or after every row under the posting entry (Dec 6 refused, `-24:1153`).
- SCN-0119 (c): undos are capped at what they undo, and an undo of an undo is refused (`-24:1170-1186`). (d): a report needs a two-letter jurisdiction and a reference (`-24:402`).
- SCN-0120: age = date minus the day the money came, and a receipt is aged when its age is above the service level (`-24:1412`, `:1455`). Dec 7 = 10 days, not aged; Dec 8 = 11, aged. While the service level is unset the aged list raises an error (`-24:1442-1447`). An unset retention shows as unknown (`-24:1450`). When a condition cannot be evaluated, -26 blocks the act (`v5.4.2-26-design.md` C6).
- SCN-0124: an agreement or pay-by date sent by the app is refused, and the database computes both (`-24:1207-1240`). Reads open, then overdue (`-24:1479`).
- SCN-0125 (c): a pledge toward a bill limits its payment to that bill (`-24:870`). An agency payment with no agency named is refused (`-24:531-533`). A pending payment counts nothing, because what it has brought is read from the ledger (`tu.sql:48206` ff.).
- SCN-0126: a lapse must be dated after the pay-by date and recorded only once that date has passed everywhere (`-24:1299-1310`). A pledge paid in full can be neither withdrawn nor lapsed (`-24:1294`). A pledge ends only once (`-24:465`).
- SCN-0127 (a) and (b): a refund names the agency whose money it carries, and names none for the customer's own money (`-24:883-896`, lineage `-24:580-596`).
- SCN-0128: a pledge with no agreement is recorded with no pay-by date and cannot lapse (`-24:1300`). It is first on the open-pledge list (`-24:1502`). A retired agency takes no new pledge (`-24:1218-1223`) and no new agreement (`-24:264`), and nothing checks whether an agency is retired when its payment comes in.
- SCN-0129 (b): a payment from a receipt that names an agency is that agency's (`-24:825-830`).

---

## PRIMARY: missing cases the guards or the known limits make important

- **M1. A receipt for a closed month.** The close freezes the day the money came (`-24:1665-1667`). Take a lockbox item found during a bank reconciliation after November closed. It cannot be recorded at its true date. Does the core date it in the open month (which shortens its age and the protection it gives), or does an operator reopen a path? SCN-0117's last bullet works only because the receipt was recorded before the close.
- **M2. Money reversed off the wrong customer and not yet returned to its receipt (AC-49).** It sits on no customer's account and in no receipt's figure. It is listed only by the reader of returns still owed (`-24:1552-1583`), which flags it once it is past the service level. That reader's comment says the money protects no candidate by itself. SCN-0121 does the reversal and the return on the same day, so it never shows this. Add a variant where the return waits until Dec 21: the suspense total shown alone is short by $65.83, and the reconciliation adds the two figures.
- **M3. AC-51's own case.** A receipt's payment ends reversed with no bank code, and the bank's take-back is learned later. The code is refused on the payment (`-24:735-739`). The money is returned to the receipt as misposted, and then the bank's return is recorded there with the code.
- **M4. AC-53, second bullet.** A receipt's payment is left pending. It holds the receipt's money but is on no aging or returns list.
- **M5. Limit L6.** Agency money moved into a transfer or adjustment credit is read as the customer's own, so its refund would go to the customer. One line in SCN-0127, "the core never does this (AC-52)", would cover it.
- **M6. The provider id in the other order.** SCN-0123 covers a receipt first, then a payment. The reverse is also refused: a payment first, then the same transaction arriving as an unmatched item, for example from a settlement file (`-24:698-699`).
- **M7. The eligibility hold** (CEAP's five business days, in the cast and the agreement) is never exercised.
- **M8. A service-level or retention setting that changes.** The readers take the setting as recorded at the instant read (`-24:1441`), not as of the date asked about.
- **M9. Test clock.** Every money date, pledge date and disposition date is refused if it is later than today at UTC+14 (`-24:929`, `:1078`, `:1212`, `:1281`), and a lapse waits for the real date at UTC-12. Scenarios dated December 2026 to 2027 can only run under a controlled clock. One line in the test strategy is enough.

---

## SECONDARY: commit 177b9bf (tax.md, periods-and-aging.md)

I re-ran all the arithmetic and it is right: SCN-0115 ($202.85 / $202.39 / $65.99, BB-10 billed $0.46 too much under a city-keyed core), SCN-0109 (b) ($66.15, $202.86) and (c) (short by $0.16 and $0.47), SCN-0108's table and (e)'s $0.65 + $0.16 = $0.81, SCN-0110 ($70.53, $1.40), and SCN-0116's $100.00 split ($12.80 + $59.20 + $28.00). Fri Oct 1, 2027, Wed Mar 3, 2027 and Thu Apr 1, 2027 are the right weekdays. BB-03 and BB-10 are west of Main in both `cast.md` and `tax.md`. `periods-and-aging.md:194` points to SCN-0108's Open on a bill that straddles a tax start, and that Open exists.

### S1. SCN-0109's Given overstates the 2% limit for the hospital district
- **Claim:** "had either still overlapped, the city could not have raised its rate (Tax Code §321.101(f))".
- **Evidence:** the same commit's "Not yet written" entry says a district's rate "is reduced there automatically unless it has debt paid from the tax; a transit authority's never is, so the city may not raise" (§321.102(e)-(h)). SCN-0115's Rule line says the same. So an overlapping hospital district alone would not have stopped the raise. Its rate would have been cut back automatically.
- **Fix:** "had the transit authority still overlapped (or a district with debt paid from the tax), the city could not have raised its rate; a district without such debt would have been reduced automatically (§321.102(e)-(h); 'Not yet written')."

### S2. SCN-0108 (e) gives a result that the Open still asks about
- **Claim:** "the March bill is corrected: **$0.81 credited** to the account". The Open then asks whether the utility should credit it or leave it for the customer to claim.
- **Fix:** present the credit as the stream's recommendation, pending the Open: "if the utility credits it (the recommendation), $0.81 is credited". Otherwise the test asserts an outcome nobody has ruled on.

### S3. SCN-0108 (e): "(to check)" has no owner, and the doubt is real
- **Evidence:** the cast's crime-control district taxes under Tax Code chapter 321 (§321.1055, `cast.md` §2 tax rows). §321.3025's "taxes imposed by the municipality" may therefore reach the district's $0.16 as well. Narrowing to "the city's part only" is not yet supported.
- **Fix:** turn "(to check)" into "**Open (a citation check):** whether §321.3025 reaches a municipal crime-control district's tax under §321.1055".

### S4. SCN-0113 (e): the remark about (b) is right but confusing
- **Evidence:** -30's levy check tests the place (`v5.4.2-30-tax-levies-and-taxability.sql:322-352`) before the decimals (`:359`), so the order claim holds. But (b) is a City of Bluebonnet row, and that place is already loaded.
- **Fix:** "(a row naming a place not yet loaded is refused for the place before its decimals are checked, so a test of (b) uses a loaded place)."

No other issues found in the secondary diff.
