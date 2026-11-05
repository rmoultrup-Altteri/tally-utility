# Date-tracking and immutability

What the platform knew, and when. Every dated fact carries two dates: when it was true, and when the platform recorded it. A wrong fact is corrected by a new record, never by an edit, so "what did we believe on date X about date Y" always has one answer. Issued bills, money and the snapshot behind each bill never change. Invariants: CI-001 (two time axes), CI-002 (correction versus retraction), CI-003 (one time basis per computation), CI-004 (dated reference data), CI-009 (a bill can be recomputed exactly), CI-011 (a stale save is refused), CI-012 (bills are not edited), CI-013 (money is add-only), CI-014 (no hard deletes), CI-015 (a full input snapshot per bill). Built across v5.4.2-01 to -04, -10, -20, -21 and -23 (mirrored). Source outlines: GBM `application/invariant-scenarios/bi-temporal-foundation.md` and `immutability-and-snapshot.md`, as revised by the 2026-11-02 inventory.

Already elsewhere, not repeated here: a void and its rebill (SCN-0002, 0003), a correction in a closed period (SCN-0005), the close snapshot not changing (SCN-0022), a decision withdrawn rather than edited (SCN-0047), a mistyped period withdrawn (SCN-0051), the period close in time zones (SCN-0020), the fee's state-agency check in the bill's zone (SCN-0054).

**Common to every scenario here.** Bluebonnet City Gas (`cast.md` §2) and the reference November bill (`cancel-rebill.md`): BB-01, schedule R-U, period Oct 15 – Nov 13, 6.0 Mcf, issued and posted Mon Nov 16, 2026, **$65.83**. "As known on" a date means what the platform had recorded by then.

---

### SCN-0069 — A rate keyed wrong is corrected by a new record: the bill already issued keeps the old rate until it is rebilled

*Status:* draft (2026-11-05), not yet sent to Kyle. Built (CI-001 and CI-002 for rate versions, REP+PROT; v5.4.2-03).
*Rule:* a rate version records when it is in force and when it was recorded. A wrong value is corrected by recording a successor, which names the version it supersedes, and closing the wrong version as superseded, with a reason; both stay readable. A lookup names both dates, and its answer depends on both. An issued bill is not changed by a correction; rebilling it is a separate act. Sources: CI-001, CI-002; Kyle 10-15 (R-12: closings of the record, not in-place edits); CI-005 (a rebill uses the original period's rates, as now known).

**Given** Bluebonnet's Oct 1, 2026 rate change was entered on Sep 20 with the distribution rate keyed **$2.69** per Mcf instead of the tariff's $2.96 (**invented**). The November bill was issued at the keyed rate:

| Line | Arithmetic | Amount |
|---|---|---|
| Customer charge | $12.80 | $12.80 |
| Distribution | 6.0 Mcf × $2.69 = 16.1400 | $16.14 |
| Commodity charge | 6.0 Mcf × $5.35 | $32.10 |
| Gas cost adjustment | 6.0 Mcf × $0.42 | $2.52 |
| City sales tax | 1% × $63.56 = 0.6356 | $0.64 |
| **Total** | | **$64.20** |

**When** on Fri Nov 20 a clerk records the correction, $2.96 in force from Oct 1, reason "keyed wrong; tariff section 500 states $2.96".

**Then**
- The $2.96 version is in force from Oct 1, recorded Nov 20, and names the $2.69 version as the one it supersedes. The $2.69 version is closed as superseded on Nov 20, with the reason. The clerk who closed it is written by the application from the acting user (AC-43); the database requires the reason, not the closer (Fable r3).
- The distribution rate in force on Nov 1: **as known on Nov 16, $2.69; as known on Nov 21, $2.96.** A lookup that leaves out either date is refused.
- The November bill stays **$64.20**: its lines and snapshot record $2.69 as read when it was computed.
- A rebill of the November bill (void and correction, SCN-0002) sits on a correction run, basis historical, priced at the original period's date. Which knowledge it reads is the correction run's choice, and it matters:
  - at the correction run's own instant, after Nov 20 (as R-22 applies to a correction run): the rates as now known, **$65.83**, $1.63 more. It passes as an upward correction under Bluebonnet's six-month default (SCN-0028), cause rate misapplication;
  - as a replay at the original bill's own instant (which v5.4.2-10 also allows): $2.69 again, **$64.20**, correcting nothing. A test proves the two differ.
- **Open (Kyle):** as in SCN-0033, does the $1.63 the error hid go on the correction, or on the next regular bill (his answer 2 of 11-05 covers a utility's own error, as this is)?
- Correcting the $2.69 version without recording a successor is refused, and so is closing it with no reason.

---

### SCN-0070 — A rate row that should never have existed is retracted: no successor, and its history stays

*Status:* draft (2026-11-05), not yet sent to Kyle. Built (CI-002, REP+PROT; v5.4.2-03).
*Rule:* a record that was never true is closed as retracted, with a reason, and needs no successor; a record that was true but wrong is superseded (SCN-0069). Lookups as known after the retraction find nothing; lookups as known before still find the retracted record, and a bill computed in between stays as computed. Sources: CI-002; Kyle 10-15 (R-12).

**Given** on Oct 5 a clerk added a "pressure surcharge" of $0.15 per Mcf to schedule R-U, in force from Oct 1 (**invented**); Bluebonnet never adopted one. The November bill carried it: 6.0 × $0.15 = $0.90, taxed, so the tax is 1% × $66.08 = 0.6608 → $0.66 and the total **$66.74**.

**When** on Nov 20 a clerk retracts the surcharge, reason "never adopted; entered in error".

**Then**
- The surcharge is closed as retracted on Nov 20; no successor is needed.
- R-U's items in force on Nov 1: as known on Nov 16, the surcharge is among them; as known on Nov 21, it is not.
- The November bill stays $66.74 until it is rebilled; a rebill reads R-U as now known and comes to **$65.83**, a decrease, so it keeps the original bill's age (Kyle 11-03, answer 10).
- A retraction with no reason is refused. Closing it as superseded with no successor is refused (that would be a correction with nothing to correct to).

---

### SCN-0071 — Every figure on one bill is read at the same pair of dates

*Status:* draft (2026-11-05), not yet sent to Kyle. **The core's discipline (CI-003, REP):** the schema makes every dated lookup name both dates and binds a bill's snapshot to its run's dates, but cannot see whether one computation used one pair. The preventive net (R-16) is deferred to before the first bill-run code. Ryan ruled 2026-11-05 that a run reads every bill at one recorded instant, fixed when it starts (DECISION-LOG; roadmap R-22); a check that the run's snapshots carry that instant is not built.
*Rule:* a bill is computed at one pair: the date it is priced at (an ordinary bill's period's last day; a correction's elected rate date, both built, v5.4.2-10), and one recorded instant for what was known. Every bill in a billing run uses the run's instant, fixed when the run starts. A rebill is never outside a run: it sits on a correction run, which takes its own start as its instant, unless the operator elects a replay at the replaced bill's own instant (SCN-0069). Every lookup of that bill (rates, gas cost, tax, the customer's attributes, the zone) uses that same pair, and the snapshot records it. Sources: CI-003; CI-015; v5.4.2-10 (the snapshot's dates bound to its run); Ryan 11-05 (R-22).

**Given** BB-02 is on R-R and BB-01 on R-U; both December bill periods run Nov 14 – Dec 13, 2026 (**invented**, the cast's mid-month periods). Bluebonnet's Oct 1, 2026 rate entry, recorded Sep 20, keyed R-R's customer charge as **$14.57** instead of the tariff's $14.75 (**invented**, as SCN-0069 does for R-U's distribution rate); the whole December period is after Oct 1, so no split method arises. The December billing run starts Wed Dec 16, 2026 at 8:00. At 9:30, while the run is going, a clerk records the correction, $14.75 in force from Oct 1.

**When** the run computes BB-01's bill at 9:00 and BB-02's at 10:00.

**Then**
- Each bill's lookups all use one pair; none mixes figures known before 9:30 with figures known after.
- BB-01's bill is unaffected (R-U didn't change).
- BB-02's bill is computed at the run's instant, 8:00, so at **$14.57**, though it is computed at 10:00; the correction reaches it by the next run or a rebill. Every R-R bill in the run carries the same customer charge.
- Each snapshot records the pair the bill used (priced at Dec 13, known as at 8:00), so a recomputation gets the same bill (SCN-0076).
- A bill never mixes bases, so a rebill that takes the original period's rates with today's tax rules (the GBM bi-temporal outline's axis A4) is ruled out: a bill has one priced-at date (v5.4.2-10), and a gas correction always uses the original period's rates (Kyle 11-05, answer 17).

---

### SCN-0072 — Two clerks edit the same record: the later save is refused, and the clerk starts again from what is there now

*Status:* draft (2026-11-05), not yet sent to Kyle. Built for rate schedules, rate items and weather zones (CI-011, REP+PROT; v5.4.2-20, the sealed version check). **Not built** for every other edited record, which Kyle's ruling covers too; that is the second of the two patches that run last (the board).
*Rule:* a save names the version of the record it was loaded at; if the record has changed since, the save is refused, and the person refreshes and re-enters. Cached edits are never replayed onto the newer record; only a memo or note the person typed is kept for them to paste. Sources: Kyle 10-15 (K-01); Ryan 10-14 and Kyle 10-15 (R-04: the version moves only through one sealed function).

**Given** Bluebonnet's R-U rate item, version 4. At 10:00 BB-clerk and BB-clerk2 both open it.

**When** at 10:05 BB-clerk saves a new customer charge from Jan 1, 2027 of $13.10 (**invented**), with the memo "council ordinance 2026-41"; at 10:07 BB-clerk2 saves a different customer charge, $13.25, from the same date.

**Then**
- BB-clerk's save is accepted; the item is version 5.
- BB-clerk2's save is refused: it was loaded at version 4. Nothing of it is written.
- BB-clerk2 refreshes, sees $13.10 and BB-clerk's memo, and decides: leave it, or record a correction (SCN-0069) with a reason. Their typed memo is offered back to paste; the $13.25 is not re-applied by itself.
- The same pair of saves on a customer's mailing address is, under the ruling, refused the same way; today it is not checked (the gap above).

---

### SCN-0073 — An issued bill is never edited; a draft may be thrown away

*Status:* draft (2026-11-05), not yet sent to Kyle. Built (CI-012, REP+PROT; v5.4.2-01, -02, -20).
*Rule:* once a bill is issued, nothing on it changes: not its lines, amounts, dates, premise, customer or the summary bill it belongs to. A wrong bill is voided and rebilled. A draft, never issued, may be discarded. The line is posting, not mailing: once posted, the customer owes it, whether or not it was delivered. Sources: CI-012; Ryan 10-14 (bills: a draft can be discarded, an issued bill never).

**Given** the November bill, issued and posted Nov 16. Two December drafts for BB-01, not issued: one computed by the December run, holding BB-01's December read (locked to it); one started by hand, with nothing attached (**invented**).

**When** a clerk (a) changes the November bill's due date to Dec 8; (b) changes its distribution line to $16.14; (c) moves it to BB-01's new address; (d) deletes it; (e) discards the December draft; (f) reprints the November bill for BB-01, who lost it.

**Then**
- (a)–(d) Refused. The way to change any of them is SCN-0002's void and rebill.
- (e) The hand-started draft is discarded: it was never issued, and nothing is attached. The run's draft can't simply be deleted while it holds the read: it is discarded through the void, which posts nothing (SCN-0003), or once its read is released.
- (f) The copy is the same bill, $65.83, due Dec 1; sending it again changes nothing on the bill and owes nothing more. (How a resend is logged is the communication log's, CI-095, not built.)

---

### SCN-0074 — Money is never edited: a payment keyed wrong is reversed and entered again

*Status:* draft (2026-11-05), not yet sent to Kyle. Built (CI-013, REP+PROT; v5.4.2-23).
*Rule:* payments, credits, one-off charges and ledger entries are add-only. Their amounts and identity are fixed when entered; a mistake is undone by a reversal naming the row it undoes, and the right row is entered new. A status only moves forward, and each move names the row behind it. Balances are read from the rows, never stored. Sources: Kyle 10-15 (R-05); Ryan 10-15 (W2-Q1: status moves forward and names its money row); Ryan 10-21 (payments are pending, posted, nsf, reversed or voided).

**Given** on Tue Nov 24 BB-01 pays the November bill, $65.83, by check. The clerk keys **$65.38** and posts it; it is applied to the November bill.

**When** the clerk finds the mistake the same afternoon.

**Then**
- Changing the amount to $65.83 is refused; so is deleting the payment.
- The clerk undoes the $65.38's application to the bill, then reverses the payment with a ledger reversal naming it, reason "keyed wrong". The payment's status moves from posted to reversed, naming that reversal.
- The clerk enters a new payment of $65.83, the same check, and applies it.
- BB-01's history shows eight records: the $65.38 payment, its posting entry, its application to the bill, the undo of that application, the ledger reversal, the $65.83 payment, its posting entry and its application. The amount owed on the November bill, read from them, is **$0.00**; no balance is stored. The bill's own paid/partial status is still written by the application and could disagree with that figure (CI-013's residual; -23 R3), so a test asserts the derived amount.
- Had the payment been entered but not yet posted, it would be voided instead, with nothing to reverse.

---

### SCN-0075 — Nothing is deleted: a customer, a meter or a billing cycle is ended with a date

*Status:* draft (2026-11-05), not yet sent to Kyle. Deletes are refused today for operational records and the setup tables of v5.4.2-21 (CI-014, REP+PROT). **Retiring with an end date is not built for billing cycles:** a cycle carries only a status (active or not), so today it is switched off, undated; the dated end is R-03's ruling. Whether four more setup tables (two label tables, two import-mapping tables) also lose delete is the open scoping item R-03 (the board, Unassigned).
*Rule:* operational records (customers, premises, meters, readings, bills, money) and setup records (billing cycles, read routes, rate schedules, jurisdictions and the like) are never deleted; a setup record is retired with an end date. Sources: CI-014; Kyle 10-15 (R-03); Ryan 10-14.

**Given** Bluebonnet's billing cycle 7, last used in June 2026 (**invented**); BB-06, the former customer of SCN-0052; a meter removed from service in 2025 (**invented**).

**When** a supervisor tries to delete cycle 7, BB-06 and the meter; then retires cycle 7 from Jul 1, 2026.

**Then**
- Each delete is refused, for every user and for the platform's own application login.
- Cycle 7 is retired from Jul 1 (under the ruling; today, switched off with no date): it is not offered for new runs, and the June runs that used it still name it.
- BB-06 stays a former customer, with the write-off and recovery history of SCN-0026; the meter stays with its readings and deployment history.

---

### SCN-0076 — A bill from years ago is recomputed exactly, from its own snapshot

*Status:* draft (2026-11-05), not yet sent to Kyle. The snapshot is built (CI-015, REP+PROT; v5.4.2-04, -10); recomputing from it is the core's (CI-009, REP: the formulas are code, identified by the version the snapshot records).
*Rule:* each issued bill keeps one snapshot of every input it was computed from and the version of the calculation; the snapshot is never edited, and its fingerprint shows it hasn't been. Recomputing the bill from the snapshot with that calculation version gives the same lines and amounts, whatever has changed since. Sources: CI-015; CI-009; CI-093 (a regulated decision can be reconstructed years later).

**Given** the November 2026 bill and its snapshot. By March 2030 (**invented**): R-U's distribution rate is $3.40; Bluebonnet has adopted a 2% city sales tax; BB-01 has moved to another premise; the platform's calculation has moved on two versions.

**When** in March 2030 the city's auditor, answering a ratepayer's complaint, asks how the November 2026 bill was computed.

**Then**
- The snapshot gives every input, and a test asserts each kind: the readings (6.0 Mcf for Oct 15 – Nov 13); the meter's multiplier and factors; the rate schedule and its rates ($12.80, $2.96, $5.35); the gas cost factor ($0.42); the tax rows and what is taxable (1%, every gas line); the premise's places and zones; the customer's class and attributes; the period dates and the partial-period method; the pair, priced at **Nov 13, 2026** (the period's last day) and known as at the November run's start (Mon Nov 16, 8:00, **invented**); and the calculation version then in use. Recomputed with that version: the same five lines and **$65.83**.
- For the meter's schedule and factors, which have no history today (SCN-0077, SCN-0078), the snapshot is the only record of what they were.
- Recomputing it with 2030's rates or 2030's calculation is a different question (what the bill would be today) and is never presented as the bill.
- Changing any input in the snapshot is refused; its fingerprint is unchanged since Nov 16, 2026.
- Had the bill been rebilled (SCN-0069), the voided bill and the correction each have their own snapshot, both kept.

---

### SCN-0077 — A customer's rate schedule is dated: a correction to a month before the change uses the old schedule

*Status:* draft (2026-11-05), not yet sent to Kyle. **Not built** (CI-004, PARTIAL): the meter's rate schedule is a single current value with no history, as are meter factors and the zone assignments. Kyle's ruling (R-09) makes the assignment a dated, add-only history with no overlaps; the rates stream's (meters, assignments). Today (c) would read the new schedule; the bill's own snapshot still holds the old one, which is why an issued bill is safe, but a correction or a back-dated query is not.
*Rule:* which schedule a customer is billed on is a dated fact, kept as a history that is only added to, never overlapping; a computation reads the schedule in force on its date. Sources: Kyle 10-15 (R-09); CI-004.

**Given** BB-02, outside the city, on schedule R-R ($14.75 a month, $3.41 per Mcf). Bluebonnet annexes BB-02's street from Mar 1, 2027 (**invented**), and the clerk moves BB-02 to R-U ($12.80, $2.96) from that date, recorded Mar 3.

**When** (a) the March bill is computed; (b) the February bill is computed; (c) in April the February bill is found misread and rebilled, basis historical; (d) someone asks which schedule BB-02 was on in February, as known on Mar 2.

**Then**
- (a) R-U. (b) R-R. (c) **R-R**: February is priced on the schedule in force in February. (d) R-R.
- Moving BB-02 to R-U from Mar 1 adds a record; it does not change February's.
- A second assignment overlapping Mar 1 onwards (say, to SC-U from Mar 15 without ending R-U) is refused.
- City sales tax follows the premise's place on each date in the same way (Kyle 11-03, answer 4; SCN-0055); that part is built (premise memberships are dated, v5.4.2-16).

---

### SCN-0078 — A meter's pressure factor is dated: a correction to a month before it changed uses the old factor

*Status:* draft (2026-11-05), not yet sent to Kyle. Review round 3 gap (Fable F12). **Not built** (CI-004, PARTIAL): a meter's multiplier and factors are current values with no history, like its rate schedule (SCN-0077); the rates stream's (meters, factor tables). Today (c) would read the new factor; the issued February bill's snapshot still holds the old one.
*Rule:* a meter's multiplier and factors (pressure, heating value, temperature) are dated facts, kept as a history that is only added to; a computation reads the factor in force on its date, and every bill line shows the raw reading beside the factor that multiplied it. Sources: CI-004; Kyle 10-15 (K-02: dated zone and factor sets, assigned to the location or the meter); Ryan 11-04 (R-19: a multiplier is stored with its raw quantity).

**Given** BB-03, the county courthouse (schedule G, $72.10 a month, $1.67 per Mcf; `cast.md` §2), on an elevated-pressure meter with a pressure factor of **1.0500** (**invented**). The regulator is reset on Mar 1, 2027 and the factor becomes **1.0800** (**invented**), recorded Mar 2. The February bill: raw reading 40.0 Mcf × 1.0500 = 42.0000 Mcf billed (**invented**).

**When** (a) the February bill is computed; (b) the March bill is computed; (c) in April the February bill is found misread and rebilled on the true raw reading, 38.0 Mcf (**invented**), basis historical.

**Then**
- (a) 1.0500: 42.0 Mcf × $1.67 = $70.14 of distribution, beside the $72.10 customer charge.
- (b) 1.0800.
- (c) **1.0500**, the factor in force in February: 38.0 × 1.0500 = 39.9000 Mcf; 39.9 × $1.67 = 66.6330 → **$66.63** of distribution. At the new factor it would have been 41.04 Mcf, $68.54: the gap the rule protects against.
- The line shows the raw 38.0 Mcf and the factor 1.0500 beside the 39.9 billed.
- Changing the factor from Mar 1 adds a record; it does not change February's.

---

### SCN-0079 — A dry run computes bills and changes nothing

*Status:* draft (2026-11-05), not yet sent to Kyle. Review round 3 gap (Fable F10; the GBM bi-temporal outline's axis A5). Built (v5.4.0-05, D3C-6): a dry run's flag is fixed for life; no bill or ledger entry may name it; it may not lock a reading; it may not be approved or posted.
*Rule:* a dry run computes what a cycle's bills would be, at its own instant, and issues nothing, posts nothing and locks no reading; it never becomes the real run (that is a new run), and its figures are never presented as a bill. Sources: v5.4.0-05 (D3C-6); CI-119; Ryan 11-05 (R-22: a run's one instant).

**Given** Bluebonnet's December cycle (SCN-0071's facts). On Mon Dec 14 at 15:00 BB-clerk starts a dry run, **DR-12 (invented)**.

**When**
- (a) DR-12 computes every meter in the cycle;
- (b) BB-clerk tries to approve DR-12, or to post it, or to turn it into the real run;
- (c) a bill is created naming DR-12, or a reading is locked to it;
- (d) the real run starts Wed Dec 16 at 8:00, after the 9:30 correction of SCN-0071 had instead been recorded on Dec 15.

**Then**
- (a) DR-12 holds an outcome per meter and the figures each bill would carry, read at Dec 14, 15:00. No bill is issued, nothing posts, no reading is locked; BB-01's December read stays free for the real run.
- (b) Refused, each one. The real run is a new run.
- (c) Refused.
- (d) The real run reads at its own instant, Dec 16, 8:00, so BB-02's customer charge is $14.75 there, though DR-12 showed $14.57. The two differ, and only the real run's figures are bills.
