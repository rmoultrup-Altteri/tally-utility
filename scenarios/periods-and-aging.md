# Accounting periods, the close, GL mapping and aging

What the platform keeps for the utility's finance side. It is a customer receivables subledger that exports to the utility's own accounting, not a general ledger (Kyle's D-2, accepted by Ryan 10-13). Invariants: CI-110 (the close snapshot is reproducible; unbilled revenue is never a ledger row), CI-048 (GL mapping), CI-076 (aging and write-off recovery), CI-019 (the balance is summed, not stored). Built in v5.4.2-22 (mirrored); its drafting calls are in the decision log, 2026-10-15/16.

**Common to every scenario here.** Bluebonnet City Gas (`cast.md` §2). Accounting periods are calendar months. Aging buckets are the default edges, 30/60/90/120: 0–30 days, 31–60, 61–90, 91–120, over 120. Age is the as-of date less the entry's date.

---

### SCN-0020 — Closing a period: only a supervisor, only after the last day has ended everywhere, only in order

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03.
*Rule:* closing a period is irreversible, so it is a supervisor's act; it is allowed only once the period's last day has ended in every time zone (UTC−12), and periods close in order. Sources: -22 drafting calls 2 and 3 (10-15); "a closed period never reopens".

**Given** September and October 2026 are open.

**When**
- (a) a billing clerk closes September on Oct 5;
- (b) a supervisor closes September at 11:00 p.m. Central on Sep 30;
- (c) a supervisor closes October on Nov 2, with September still open;
- (d) a supervisor closes September on Oct 10.

**Then**
- (a) refused: not a supervisor.
- (b) refused: Sep 30 has not yet ended everywhere. The earliest moment is 12:00 UTC on Oct 1 (7:00 a.m. Central).
- (c) refused: September must close first. (October itself has ended everywhere by then, so this is the only reason.)
- (d) closed. From then on, nothing dated on or before Sep 30 can be written.

---

### SCN-0021 — A payment received in a closed month is recorded in the open one, keeping the customer's date

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03. Payments belong to the cash family (-23 in review); this tests only the freeze and the customer's date, which -19 and -22 built.
*Rule:* money dated inside a closed period is refused; the customer's own payment date is kept separately for the customer's rights, such as whether the payment was on time, by the method the utility's tariff states. Sources: -22 (the freeze on the payment date, the ledger date and the credit date); -19 (the customer-initiation date and its method); CI-058 (the method varies by place); Bluebonnet's method is the cast's, **invented**: postmark for mail.

**Given** September is closed (SCN-0020 d). On Oct 14 a clerk finds BB-01's check for $54.34 in a misrouted mail tray, postmarked Sep 27.

**When** the clerk records it (a) dated Sep 27; (b) dated Oct 14, with the postmark Sep 27 as the customer's date.

**Then**
- (a) refused: September is closed.
- (b) accepted. The payment counts in October's activity. For on-time questions the customer's date is Sep 27. The September bill was issued Sep 18; fifteen days later is Saturday Oct 3, so it was due Monday Oct 5. It was paid on time and carries no late penalty; SCN-0034 is the case where one had already posted.

---

### SCN-0034 — A late penalty already posted is reversed when the payment proves to have been on time

*Status:* draft (2026-11-04), not yet sent to Kyle. Written against the rulings: the late-penalty rules are not yet built (R-11); payments belong to the cash family (-23 in review). Reviewer gap (Fable, 2026-11-02, item 7).
*Rule:* whether a payment was on time is judged by the customer's date, by the method the tariff states, not by the day it was recorded. A penalty posted before an on-time payment was recorded is reversed in full, naming the penalty, with the customer's date as the reason, in the open period. A reversed penalty is not counted as a late penalty afterwards. Sources: SCN-0021; -19 (the customer's date and its method; CI-058); R-02 and CI-017 (a reversal names what it undoes, capped at it); Kyle 11-03, answer 3 (a penalty on the current bill only).

**Given** SCN-0021's facts, plus: the September bill ($54.34, issued Fri Sep 18) was due Mon Oct 5; on Tue Oct 6, with no payment recorded, a penalty posted: 10% × $54.34 = 5.4340 → **$5.43** (the same **invented** reading of Bluebonnet's gross rate as SCN-0033). October is open.

**When** on Wed Oct 14 the clerk records the check dated Oct 14, with the postmark Sep 27 as the customer's date (SCN-0021 b).

**Then**

| Entry | Amount | Names |
|---|---|---|
| September bill charge (Sep 18) | +$54.34 | — |
| Late penalty (Oct 6) | +$5.43 | the September bill |
| Payment (Oct 14; customer's date Sep 27) | −$54.34 | — |
| Penalty reversal (Oct 14) | −$5.43 | the Oct 6 penalty; reason: paid on time, postmark Sep 27 |
| **Balance** | **$0.00** | |

- The reversal is dated Oct 14, in October; it is not dated Oct 6 or Sep 27.
- A further reversal of the penalty is refused: nothing is left of it.
- The penalty does not count toward Bluebonnet's limit of two late penalties for a deposit refund (SCN-0007, SCN-0008): it is reversed for being wrongly assessed.
- Recorded with no customer's date, the same check is late, and the penalty stands.

---

### SCN-0022 — The close snapshot does not change when a later correction reaches back

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03.
*Rule:* the close records the period's activity by entry type and its aging by bucket at one instant, and later writes never change it; unbilled revenue is reported with its basis, or omitted, and is never a ledger entry. Sources: -22 S1, S2, drafting call 4; D-2.

**Given**
- September is closed on Oct 10 (SCN-0020 d). Its snapshot, for the purposes of this example, covers BB-01 alone: one bill charge, $54.34 (the September bill of `cancel-rebill.md`, SCN-0005), and no payment.
- At the close the supervisor supplies an unbilled-revenue figure of $18,400.00, "basis: cycle-day estimate from the meter-reading schedule" (**invented**).
- On Nov 20 the September bill is voided and corrected to $45.85 (SCN-0005).

**When** the September snapshot is read on Nov 25.

**Then**
- It still shows charges of $54.34, and the aging **as of Sep 30, the period's last day, as recorded at the close on Oct 10**: the Sep 18 charge is 12 days old, in the 0–30 bucket.
- The unbilled figure appears on the snapshot with its basis. It is not a ledger entry, so no customer's balance includes it.
- The void (−$54.34) and the correction (+$45.85) appear in November's activity when November closes.

---

### SCN-0023 — Aging is balance-forward: the balance is aged newest first

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03.
*Rule:* each entry is netted with the reversals that name it; the balance left is aged newest first, the debt-side view of paying the oldest bill first. Sources: -22 drafting call 5; Kyle 10-15 (K-05: oldest bill first); Ryan 10-13 (the balance is summed from the ledger, not stored).

**Given** BB-01's ledger (no late penalty was assessed on the July and August bills: **invented**, to keep the ledger short):

| Date | Entry | Amount |
|---|---|---|
| Jul 15 | July bill | +$58.20 |
| Aug 15 | August bill | +$61.40 |
| Sep 18 | September bill | +$54.34 |
| Sep 20 | payment | −$100.00 |
| Oct 15 | October bill | +$64.61 |

**When** the aging is read as of Nov 1.

**Then**
- Balance: **$138.55**.

| Bucket | Amount | From |
|---|---|---|
| 0–30 days | $64.61 | the October bill, 17 days |
| 31–60 days | $54.34 | the September bill, 44 days |
| 61–90 days | $19.60 | what is left of the August bill, 78 days |
| 91–120, over 120 | — | the July bill and $41.80 of August are covered by the payment |

---

### SCN-0024 — A corrected old bill keeps its age; only an increase ages from the correction

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03; reworked to his answer 10.
*Rule:* as SCN-0023. A void nets out the entry it names; the correction is a new entry that carries an aging date apart from its posting date. What was already owed keeps its original age; a decrease reduces the old aged amount; any increase ages from the correction's date, with a new due date. Sources: Kyle 11-03, answer 10; as SCN-0023; CI-017 (the correction names the voided bill).

**Given** SCN-0023's ledger, plus SCN-0005's correction: on Nov 20 the September bill is voided (−$54.34, naming the Sep 18 entry) and corrected (+$45.85).

**When** the aging is read as of Nov 25.

**Then**
- Balance: **$130.06**. The September entry nets to zero with its void. The correction is a decrease ($54.34 to $45.85), so all of it keeps the September bill's age: posted Nov 20, aged from Sep 18.

| Bucket | Amount | From |
|---|---|---|
| 31–60 days | $64.61 | the October bill, 41 days |
| 61–90 days | $45.85 | the correction, aged from Sep 18: 68 days |
| 91–120 days | $19.60 | what is left of the August bill, 102 days |

- Had the correction been an increase, to $60.00 say, $54.34 would keep the Sep 18 age and $5.66 would age from Nov 20 (0–30 days, 5 days), with its own due date.

---

### SCN-0025 — GL mapping: a fixed order of precedence, and an export refuses an unmapped line

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03.
*Rule:* GL account mapping is the utility's dated configuration, keyed by the charge (its kind of bill line, one-off charge or ledger entry, and its code), customer class, territory and tax jurisdiction, each of which may be left open. Where several mappings fit a line, the one that names the charge wins over one that names the class, which wins over territory, which wins over tax jurisdiction. Two mappings with the same key and overlapping dates are refused when entered. An export refuses a line with no mapping, but the bill still posts. No mapping may start or end inside a closed period. Sources: -22 G1–G4 and drafting call 7 (`gl_mapping_as_of`: weights 8, 4, 2, 1); D-2 (GL mapping is tenant configuration).

**Given** Bluebonnet's mappings from Jan 1, 2026 (account numbers **invented**). The kinds of bill line are the platform's: a customer charge is a base charge; distribution is a usage charge; the commodity charge and the gas cost adjustment are per-unit surcharges (**invented** classification for this tariff; cast question 7); city sales tax is a tax line.

| Charge | Class | Territory | Tax jurisdiction | Account |
|---|---|---|---|---|
| base charge | open | open | open | 4000 customer charge revenue |
| usage charge | open | open | open | 4010 distribution revenue |
| usage charge | open | rural | open | 4011 rural distribution revenue |
| usage charge | residential | open | open | 4012 residential distribution revenue |
| surcharge | open | open | open | 4020 gas cost revenue |
| tax | open | open | the city | 2300 sales tax payable |

**When** November's export runs. It contains BB-01's bill (residential, urban), BB-02's bill (residential, rural), and a $15.00 pilot relight fee on BB-02, a one-off charge dated Nov 12, for which no mapping exists.

**Then**
- BB-01's and BB-02's distribution lines both go to 4012. For BB-02, three mappings fit: 4010 (charge), 4011 (charge and territory) and 4012 (charge and class); class outranks territory, so 4012 wins.
- The relight fee is refused by the export, naming the charge with no mapping: every mapping names a kind of bill line, and the fee is a one-off charge. BB-02's bill and ledger entry stand; only the export is held back until a mapping covering Nov 12 exists.
- A new mapping dated Sep 1 (inside closed September) is refused; one dated Nov 1 is accepted.
- A second "usage charge, rural" mapping whose dates overlap 4011's is refused when entered.

---

### SCN-0026 — A recovery after a write-off names it, and recoveries never exceed what was written off

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03.
*Rule:* a write-off recovery must name the write-off it reverses, give a reason and carry the opposite sign; the net of the write-off and everything under it stays between zero and the amount written off, at every date. Sources: -22 W3; review rounds 2 and 3 (the cap on the whole tree, at every date and instant); Kyle 10-15 (R-02: reversals against an entry total at most the entry).

**Given** BB-02 moved out owing $120.00. Bluebonnet writes it off on Dec 31, 2026: a write-off entry of −$120.00.

**When**
- (a) on Mar 3, 2027, BB-02 pays $50.00 through a collection agency, and the clerk records a recovery of +$50.00 naming the write-off;
- (b) on Apr 8, 2027, a second recovery of +$80.00 is entered;
- (c) the Mar 3 recovery is found to have been entered in error and is reversed.

**Then**
- (a) accepted. The account's balance is the $50.00 recovery less the $50.00 payment: $0.00. $70.00 remains written off.
- (b) refused: it would recover $130.00 of a $120.00 write-off.
- (c) after the reversal, the full $120.00 is written off again, and a recovery of up to $120.00 may be entered. The $50.00 payment still stands, so BB-02 now shows a **$50.00 credit** until the recovery is re-entered correctly or the payment is dealt with.
- A recovery naming no write-off, or another customer's, is refused.

---

### SCN-0049 — An account in credit ages as one row with no bucket

*Status:* draft (2026-11-04), not yet sent to Kyle. Reviewer gap (Opus, 2026-11-02, A10).
*Rule:* the aging shows each customer's balance; a debit balance is spread over the age buckets, newest first, and a credit balance is one row with no bucket. A zero balance is left out. Sources: v5.4.2-22 W1 (`receivables_aging_as_of`); Kyle 10-30 (one credit balance).

**Given** SCN-0046: after the February 2027 bill, BB-02 holds a credit of $130.40. BB-01 owes $65.83 on a bill dated Jan 15, 2027 (**invented**). A third customer, **BB-05 (invented)**, owes nothing.

**When** the aging is read as of Feb 28, 2027.

**Then**
- BB-02: one row, balance **−$130.40**, no bucket.
- BB-01: $65.83 in the 31–60 bucket (44 days).
- BB-05: no row.
- The bucket totals are BB-01's alone; the credit is not netted into them.

---

### SCN-0050 — Balances from before the first period load while it is open, and not after it closes

*Status:* draft (2026-11-04), not yet sent to Kyle. Reviewer gap (Opus, 2026-11-02, A10).
*Rule:* a date on or before the latest closed period's last day is frozen, so balances carried over from the utility's old system are loaded before its first period closes; they keep their own dates and age from them. Sources: v5.4.2-22 P2 ("inside a closed period, or before the first period once it is closed: onboarding history is loaded before the first close").

**Given** Bluebonnet's first accounting period is January 2026, open. Its old system shows BB-01 owing $54.10 on a bill dated Dec 15, 2025 (**invented**).

**When** the balance is loaded with its Dec 15, 2025 date (a) on Jan 20, 2026, while January is open; (b) on Feb 10, 2026, after January closed on Feb 5.

**Then**
- **(a)** Accepted. Read as of Jan 31, 2026, it is $54.10 in the 31–60 bucket (47 days).
- **(b)** Refused: the books are closed through Jan 31, 2026, and Dec 15, 2025 is before that.

---

### SCN-0051 — A mistyped period is withdrawn, kept on record, and created again

*Status:* draft (2026-11-04), not yet sent to Kyle. Reviewer gap (Opus, 2026-11-02, A10).
*Rule:* periods follow each other with no gap and no overlap, and are never deleted. The utility's latest period may be withdrawn while it is open; it stays on record, stamped, and its dates are free for a correct one. A closed period, or one with a later period after it, cannot be withdrawn. Sources: v5.4.2-22 P1 and r2 (withdrawal).

**Given** Bluebonnet's periods run to Oct 31, 2026, all closed. On Nov 2 a supervisor creates November, mistyped as Nov 1 – Dec 30.

**When** (a) December is created starting Dec 1; (b) the mistyped period is withdrawn; (c) November is created as Nov 1 – Nov 30; (d) someone tries to withdraw October; (e) someone tries to delete the withdrawn period.

**Then**
- **(a)** Refused: it overlaps the mistyped period, and a period must start the day after the latest.
- **(b)** Accepted: it is the latest and open. It stays on record as withdrawn, with when and by whom.
- **(c)** Accepted: the withdrawn period takes part in neither the no-gap nor the no-overlap rule.
- **(d)** Refused: October is closed, and it is not the latest.
- **(e)** Refused: periods are never deleted.

---

### SCN-0052 — An unpaid final bill reaches the write-off age, and the write-off is dated in an open period

*Status:* draft (2026-11-04), not yet sent to Kyle. Reviewer gap (Fable, 2026-11-02, item 16). Whether a write-off needs a supervisor is not stated in the rulings.
*Rule:* the core proposes writing off a receivable when its age reaches the utility's threshold; with no threshold set, none is proposed. The write-off is a ledger entry, and like any entry it may not be dated in a closed period. A former customer appears in the aging as a former occupant. Sources: v5.4.2-22 W3 (`write_off_threshold_days`; no assumed default, K-07), P2 (the freeze), D-3; CI-076.

**Given**
- **BB-06 (invented)**, residential, moved out in September 2026; the final bill, dated Sep 15, 2026, left **$120.00** unpaid (**invented**). No deposit remains.
- Bluebonnet's write-off threshold: 120 days (**invented**). December 2026 is closed on Jan 8, 2027; January is open.

**When** the aging is read on (a) Jan 12, 2027; (b) Jan 13, 2027; and (c) the write-off is entered dated Dec 31, 2026; (d) dated Jan 13, 2027. And (e) the same on Jan 13 with no threshold set.

**Then**
- **(a)** 119 days old, in the 91–120 bucket. Nothing is proposed.
- **(b)** 120 days old: the threshold is reached, and the core proposes the write-off, citing the aging and the threshold. BB-06 shows as a former occupant.
- **(c)** Refused: December is closed.
- **(d)** Accepted: a write-off of −$120.00 dated Jan 13, 2027, naming the final bill. BB-06's balance is $0.00. A later recovery names it, as in SCN-0026.
- **(e)** Nothing is proposed; an operator may still write it off.
