# Backbilling

How far back a correction may reach, and what is given up. Invariants: CI-008 (the cap per jurisdiction), CI-091 (meter test history), the A-2 rulings R-19 to R-39 (Kyle, September). The rules the core evaluates are in `application/a2-rules-for-the-core.md`; the law rows are v5.4.2-18 (mirrored).

**Where this stands for city systems.** -18's rows bind investor-owned and cooperative utilities only: Texas law (Utilities Code 101.003(7)) excludes a municipal corporation. For a city system the lookup refuses today, because "unknown law is not permission" (-18 residual R2). Kyle's answer of 2026-11-03 (answer 8) replaces that for a city whose ordinance is silent: refunds go back as far as the records show, and undercharges take a six-month platform default until the city records its own rule, citing its ordinance; a missing rule never holds back a refund. A city's own rule is a delegated law row plus its tariff record, to be written with the backbilling tariff table (the rates stream's carried-over item; board note). Neither source tariff (Brenham, Stinnett) states a backbilling rule. So SCN-0013 to 0018 use Gulf Plains, the regulated utility, where Texas law binds; SCN-0019 is the city case.

**How the amounts are given.** How a test's error becomes dollars per bill is not ruled (A-2 residual R2): the amount for each billing period is an input to the correction. These scenarios test which periods the rules admit, not the conversion. The amounts are **invented**.

**Common to SCN-0013 to 0018.** Gulf Plains Gas Company (`cast.md` §3); customer GP-01, residential, in the unincorporated area (the protected class). Monthly bills on calendar months. The meter was installed in 2019 and has no deployment change since. A bench test with readings on **Jun 15, 2026** finds the meter's error; the meter is removed that day, and its last bill covers Jun 1–14. Gulf Plains went live on the platform on Jan 15, 2026 (`cast.md` §3). Gulf Plains has set no backbilling limit of its own unless a scenario says so. The correction is evaluated on Jul 6, after the June bill. The seven bills on that meter, with the error in each as given:

| Period | Error in the bill |
|---|---|
| Dec 2025 | $6.20 |
| Jan 2026 | $8.40 |
| Feb 2026 | $7.90 |
| Mar 2026 | $5.10 |
| Apr 2026 | $3.30 |
| May 2026 | $2.10 |
| Jun 1–14, 2026 | $1.20 |
| **All seven** | **$34.20** |

---

### SCN-0013 — A slow meter: six months back from the test, a straddling month given up whole

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03.
*Rule:* where 16 TAC §7.45 binds, a slow meter's undercharge may be billed back the shorter of six months before the test or to the last test; a period straddling the window's start is given up whole; each period is judged on its own. While the window still reaches before the utility went live and there is no reliable earlier test, the charge needs a supervisor's approval. Sources: §7.45(7)(B)(v)(I); R-25 (per period, never netted), R-32 (forfeit whole), R-34/R-35 (the last test, any outcome; none means six months alone), R-36 (the approval gate; a2-rules §9).

**Given** the common facts; the test finds the meter **slow**; there is no earlier test on record.

**When** the correction is evaluated.

**Then**
- The window starts **Dec 15, 2025** (Jun 15, 2026 less six months).

| Period | Amount | Result | Why |
|---|---|---|---|
| Dec 2025 | $6.20 | given up | straddles the window's start (17 days inside it are given up too) |
| Jan 2026 – Jun 14, 2026 | $28.00 | billed | inside the window |

- The window reaches before Jan 15, 2026, when Gulf Plains went live, and there is no earlier test: **the charge needs a supervisor's approval**, from someone who neither opened the case nor ran the evaluation. Without it the correction cannot be completed.
- Once approved, the customer is charged **$28.00**, as an adjustment on the next bill (the delivery path for a meter error, R-33). This charge can never ground a disconnection (its enforceable scope is "never", F-1).
- The record cites the Texas law row, the window, and the reason for each given-up period.

---

### SCN-0014 — An earlier test shortens the window, whatever it found

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03.
*Rule:* as SCN-0013; the last test before the finding bounds the window, whatever its outcome. Sources: R-34 (no accuracy filter: "the last test of the meter"), R-35.

**Given** SCN-0013, plus a test on **Mar 10, 2026** that found the meter accurate, recorded on the platform with its readings.

**When** the correction is evaluated.

**Then**
- The window starts **Mar 10, 2026** (the later of Dec 15 and Mar 10).

| Period | Amount | Result | Why |
|---|---|---|---|
| Dec 2025 – Feb 2026 | $22.50 | given up | before the window |
| Mar 2026 | $5.10 | given up | straddles the window's start (22 days inside) |
| Apr 2026 – Jun 14, 2026 | $6.60 | billed | inside the window |

- The customer is charged **$6.60**. No approval is needed: the earlier test is a recorded one, so the approval gate does not apply.

---

### SCN-0015 — A fast meter: the refund includes the straddling month, and no setting shortens it

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03.
*Rule:* for a fast meter the refund is mandatory over the same window; a period straddling the window is included whole; no utility setting or operator choice shortens it. Sources: R-25, R-32 (only adverse periods are forfeited), R-37 (option C: no override in the customer's favour direction).

**Given** SCN-0013, except the test finds the meter **fast**: each amount is owed to the customer. Gulf Plains has set its own two-month limit on backbilling (as in SCN-0016).

**When** the correction is evaluated.

**Then**
- The window starts Dec 15, 2025. All seven periods are refunded, Dec included whole: **$34.20** owed to the customer. Every day from Dec 15 to Jun 14 is covered by a period; a refund with an uncovered day could not be completed (a2-rules §11.3). No approval is needed: the gate is for charges only.
- The two-month limit does not apply: it reaches only charges against the customer.
- The case cannot be withdrawn while the standing test still finds the meter fast.

---

### SCN-0016 — The utility's own limit gives up more of a charge, never of a refund

*Status:* draft (2026-11-02); checked by Kyle 2026-11-03 and confirmed as written: April given up whole, $3.30 (answer 11).
*Rule:* a utility may set a backbilling limit stricter than the law, applied only to charges against the customer; each period it excludes is given up with that reason, and a period straddling the utility's limit is given up whole, as at the law's window: one rule. Sources: Kyle 11-03, answer 11; R-37(d); "a utility may be stricter than the law, never looser" (audit rule 5).

**Given** SCN-0013 (slow, no earlier test), and Gulf Plains' own limit of **two months**.

**When** the correction is evaluated.

**Then**
- The law's window starts Dec 15, 2025; the utility's limit starts **Apr 15, 2026**.

| Period | Amount | Result | Why |
|---|---|---|---|
| Dec 2025 | $6.20 | given up | straddles the law's window |
| Jan – Mar 2026 | $21.40 | given up | the utility's limit |
| Apr 2026 | $3.30 | given up | the utility's limit (it begins before Apr 15) |
| May 2026 – Jun 14, 2026 | $3.30 | billed | |

- The customer is charged **$3.30**, after the same supervisor approval as SCN-0013.
- April is given up whole because it straddles the utility's limit (a2-rules §6.3, now settled).

---

### SCN-0017 — A charge and a refund in different months are not netted

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03.
*Rule:* direction is decided for each billing period by the sign of its correction, never netted across the case, so a time-barred charge cannot hide behind a refund; the utility's own limit cuts charges, never refunds. Sources: R-25; R-37(d) (the utility's limit applies to every cause, charges only).

**Given**
- GP-01's meter is found to have been read through the wrong billing constant (a cause anchored on discovery, with no window under Texas law: R-39 "never" enforceable, pending counsel). Discovered Jun 20, 2026; claimed to reach back to Feb 1, 2026.
- The corrections for Feb – May: +$10.00, −$5.00, +$10.00, $0.00.
- Gulf Plains has set its own two-month limit: charges may reach back to Apr 20, 2026.

**When** the correction is evaluated.

| Period | Correction | Result | Why |
|---|---|---|---|
| Feb 2026 | +$10.00 | given up | the utility's limit |
| Mar 2026 | −$5.00 | refunded | the limit never reaches a refund |
| Apr 2026 | +$10.00 | given up | the utility's limit (it begins before Apr 20) |
| May 2026 | $0.00 | no change | |

**Then**
- The customer is refunded **$5.00** and charged nothing. A calculation that netted the case first would have seen one $15.00 charge and lost the refund.

---

### SCN-0018 — Tampering reaches back without a window, but only with a supervisor and evidence

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03.
*Rule:* a tampering or bypass finding has no backbilling window under Texas law, and entering that cause needs a supervisor's approval and recorded evidence. Sources: §7.45(4)(D)(v) and the (4)(E)(vi) carve-out; R-39; a2-rules §3.3.

**Given** GP-01's meter is found bypassed on Jun 20, 2026. The bypass is claimed to have begun Jan 1, 2025; the correction for each billed period from Jan 2025 to May 2026 is given per period (the meter registered some use throughout). Gulf Plains has set no limit of its own.

**When** the case is opened as tampering (a) by a clerk, citing field report FR-2026-0412; (b) by a supervisor, citing no evidence; (c) by a supervisor, citing field report FR-2026-0412.

**Then**
- **(a)** Refused: not a supervisor.
- **(b)** Refused: tampering needs exactly one evidence reference (a service order on this meter, a removal of this meter for tamper, or a field report reference).
- **(c)** Accepted. No window applies: every period from Jan 2025 may be billed, and the charge may ground collection without limit (enforceable scope "uncapped").
- Had Gulf Plains set its two-month limit, it would cut this charge too: the utility's limit reaches every cause, uncapped ones included.

---

### SCN-0019 — A city system's backbilling follows its own tariff, or a six-month default for charges while it is silent

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03; case (a) reworked to his answer 8. Written against the ruling; the tariff table and the default row are not built.
*Rule:* Texas's backbilling rule does not bind a city-owned system; the city sets its own standard as a tariff record, citing its ordinance. While it has none, a refund reaches back as far as the records show, and a charge reaches back six months by platform default; a period straddling the default's start is given up whole (one rule, answer 11). Sources: Kyle 11-03, answers 8 and 11; Utilities Code 101.003(7); the standing rule: a city system's policy is its own tariff row, and the platform default only where it is silent.

**Given** Bluebonnet City Gas (`cast.md` §2), live on the platform from Jan 1, 2026 (**invented**), its earlier bills not loaded; customer BB-01; the slow-meter facts of SCN-0013 on Bluebonnet's meter, so the platform holds the bills from January 2026 to June 14. Bluebonnet's published tariff says nothing about backbilling.

**When** the correction is evaluated (a) with Bluebonnet's ordinance silent; (a′) the same, but the test finds the meter fast; (b) after Bluebonnet records a tariff rule: "six months before the test, bounded by the last test, a straddling month given up whole" (**invented**: a city that chooses to copy the state's rule).

**Then**
- **(a)** Billed under the six-month default, which the record cites: the window starts Dec 15, 2025; January – June 14 are billed, **$28.00** (SCN-0013's amounts, standing in for Bluebonnet's own). December 2025 has no bill on the platform; had it one, it would straddle the window and be given up whole.
- **(a′)** Refunded for every bill on the platform on this meter, January – June 14: **$28.00**. No window cuts it, and nothing waits on Bluebonnet stating a rule. The rules refuse an evaluation with no start (a2-rules §5.1), so the start is taken as the first bill on the platform: this stream's reading of "as far back as the records show".
- **(b)** Given also the delegated law row for city-owned systems ("the city sets its own standard"; to be written with the tariff table), the same periods as SCN-0013 are billed (Bluebonnet's own amounts, at its own rates). The record cites Bluebonnet's tariff record and the delegated row, not the Texas rule.
- Onboarding asks each city whether its ordinance states a backbilling rule; the default stands until it records one.
- **Open (Kyle, next batch):** in (a), is the six-month default counted back from the test, as Texas's is, and is it also cut short by an earlier test? Does a charge under it need the supervisor's approval when the window reaches before the city went live (SCN-0013)? Written here as counted from the test, with no earlier test on record. And in (a′), does "as far back as the records show" reach the city's records from before it went live (December 2025 and earlier), held until they are loaded as SCN-0039 does, or only the bills on the platform?

---

### SCN-0031 — A backbilled charge sits in the aging like any debt, but can never ground a disconnection

*Status:* draft (2026-11-02); figures checked by Kyle 2026-11-03; variant (b) added to his answer 12 (gas first). Written against the rulings: carrying the limit into collections is the collections family's (v5.4.2-26, not yet built).
*Rule:* a meter-error charge under Texas law can never be the reason for a disconnection, however old it gets (enforceable scope "never"); that limit travels with the charge. Aging is balance-forward and shows the debt by age whatever its kind; a collection step reads the charge's limit, not its age bucket. A partial payment goes first to what can ground a disconnection, and last to the backbilled charge ("protect the customer"). Sources: Kyle 11-03, answer 12; §7.45(4)(E)(vi); F-1; a2-rules §6.4; aging as SCN-0023 (Kyle 10-15, K-05: oldest bill first).

**Given**
- SCN-0013: GP-01's $28.00 slow-meter charge, approved and evaluated on Jul 6, 2026.
- Gulf Plains issues bills on the 5th of the following month, due 16 days later (**invented**).
- The July bill, issued Aug 5: July's gas $40.00 (**invented**) and the backbilling adjustment $28.00, as its own line carrying its limit: **$68.00**.
- GP-01 pays (a) $40.00 or (b) $28.00 on Aug 18.
- The August bill, issued Sep 5, due Sep 21: **$42.00**, unpaid.

**When** GP-01's account is read on Oct 1: its aging, and what may ground a disconnection notice.

**Then**
- **(a)** The $40.00 pays July's gas. Balance **$70.00**, aged:

| Bucket | Amount | From |
|---|---|---|
| 0–30 days | $42.00 | the August bill, 26 days |
| 31–60 days | $28.00 | what is left of the July bill, 57 days |

- What may ground a disconnection: the August bill's $42.00, now past due. The $28.00 never can, though it is older; it can still be billed, reminded and collected by other means.
- **(b)** The $28.00 goes to July's gas first, leaving $12.00 of it and the whole $28.00 backbilling line. Balance **$82.00**, aged: 0–30 days $42.00 (the August bill); 31–60 days $40.00 (what is left of the July bill). What may ground a disconnection: $42.00 and July's **$12.00**; the $28.00 never can. Applied to the backbilling line first instead, $40.00 of July would be disconnectable: that order is refused.

---

### SCN-0035 — A meter that stopped registering: three months back, and the anchor question

*Status:* draft (2026-11-04), not yet sent to Kyle. Reviewer gap (Opus, 2026-11-02, A7). The anchor follows the built Texas row (the test's date); that it should be the discovery date instead is an open disagreement (a2-rules §16, D1).
*Rule:* where §7.45 binds, gas used but not metered may be charged for at most three months; the window is also cut short by the meter's deployment start, but not by an earlier test; a period straddling the window's start is given up whole; the charge can never ground a disconnection. The record says which basis estimated the unmetered use. Sources: §7.45(7)(B)(v)(II); (4)(E)(vi); the Texas rows of v5.4.2-18 (three months, test-date anchor, forfeit whole, never enforceable); R-23 and R-25 (the estimation basis is recorded); a2-rules §4.1 (F9), §9.1 (D3).

**Given** the common facts, except: the meter stopped registering at all around Feb 25, 2026 (**invented**); the bills from March on show zero usage; and the Jun 15 test finds it **not registering**. The unmetered use for each period, estimated from GP-01's own use in the same months of 2025 (**invented**): Feb $3.00 (its last four days), Mar $22.00, Apr $18.00, May $12.00, Jun 1–14 $5.00. No earlier test.

**When** the correction is evaluated.

**Then**
- The window starts **Mar 15, 2026** (Jun 15 less three months). The 2019 deployment start is earlier, so it doesn't count.

| Period | Amount | Result | Why |
|---|---|---|---|
| Mar 2026 | $22.00 | given up | straddles the window's start (17 days inside) |
| Apr 2026 – Jun 14, 2026 | $35.00 | billed | inside the window |

- GP-01 is charged **$35.00**. It can never ground a disconnection.
- No supervisor approval: the three-month window has no last-test term, so a weak test history cannot move it (the build's reading; Kyle's ruling R-36 names no cause, a2-rules D3).
- The record names the estimation basis: the same customer's like-period use at the same premise.
- How the charge reaches a bill is not ruled for this cause (OQ-1); the scenario tests the periods admitted, not the delivery.
- **Open (Kyle, next batch):** §7.45(7)(B)(v)(II) counts three months back from when the meter "is found not to be registering". Is that the test (Jun 15, as built) or the day it was first noticed, say a reader's May 5 report of no movement (**invented**)? From May 5 the window would start Feb 5: February ($3.00) would be given up whole and March billed whole. And does R-36's approval apply to this cause on a meter with no test history?

---

### SCN-0036 — A large-volume customer outside the protected class: the law delegates to the utility's tariff, and without one the case is refused

*Status:* draft (2026-11-04), not yet sent to Kyle. Reworked in review round 2 (all three reviewers): the unprotected Texas rows are delegations, not permissions (v5.4.2-18, residual R10; confirmed by Ryan 2026-11-05, DECISION-LOG). Gulf Plains' backbilling tariff record is **invented**; the tariff table is not built (the rates stream's).
*Rule:* Texas's backbilling limits protect residential and small commercial customers only. Whether a customer is protected follows the utility's class mode: by default every customer is protected; under the explicit-class mode, a class outside the protected list is not. For an unprotected customer, Texas law delegates to the utility's filed tariff and ordinary limitations law: the law row claims no window and no collection scope of its own, and with no tariff record the case is refused (fail toward protection). The period set starts at the widest window of the rules that could apply. Sources: v5.4.2-18 (the unprotected rows as delegations, "16 TAC 7.45 does not reach this class; ordinary limitations law and the filed tariff govern, outside this table"; residual R10); a2-rules §13.1 (class modes), §13.3 and §5.1 (the set start), §4.1 (`claimed_start`), §9.1 (the gate needs a last-test term).

**Given** the common facts, except the customer is **GP-02 (invented)**, a large industrial plant on its own meter, customer class industrial. The Jun 15 test finds the meter **slow**; no earlier test. A field report shows the meter's register gear damaged at the Oct 1, 2025 read (**invented**). The error in each bill (**invented**):

| Period | Error |
|---|---|
| Oct 2025 | $410.00 |
| Nov 2025 | $520.00 |
| Dec 2025 | $620.00 |
| Jan 2026 | $840.00 |
| Feb 2026 | $790.00 |
| Mar 2026 | $510.00 |
| Apr 2026 | $330.00 |
| May 2026 | $210.00 |
| Jun 1–14, 2026 | $120.00 |
| **All** | **$4,350.00** |

**When** the correction is evaluated with Gulf Plains' class mode (a) the default; (b) explicit class, and no backbilling tariff record for the unprotected class; (c) explicit class, with Gulf Plains' tariff record (**invented**): "for a customer outside the protected class, a meter error is charged back to the date it is shown to have begun, with the evidence cited; a month straddling that date is billed whole", the case claiming Oct 1, 2025 with the field report.

**Then**
- **(a)** GP-02 is protected, as SCN-0013: the window starts Dec 15, 2025; October and November lie before it and are not evaluated; December straddles it and is given up; January – June 14 are billed, **$2,800.00**, after a supervisor's approval, never disconnectable.
- **(b)** Refused: the law sends the unprotected class to Gulf Plains' tariff, and no tariff record states a rule. The refusal names what is missing.
- **(c)** The window is the claimed start, Oct 1, 2025, earlier than the protected class's Dec 15, so the period set starts there. Every period from October is billed, December whole: **$4,350.00**. No approval: the rule has no last-test term for a weak history to move. The record cites Gulf Plains' tariff record, the delegating row and the field report.
- As (c) with no claimed start: refused, since the tariff's only bound is the claimed start.
- **Open (Kyle, next batch):** in (c), does ordinary limitations law cap how far back the charge reaches, and how far may collection (disconnection) pursue it? The delegating row claims nothing on either.

---

### SCN-0037 — Two customers inside the window: the correction follows the meter, and each period stays with whoever was billed for it

*Status:* draft (2026-11-04), not yet sent to Kyle. Reviewer gap (Codex, 2026-11-02). How a charge reaches a former customer is the delivery patch's (v5.4.2-14).
*Rule:* a meter correction is one finding about one meter, across every occupant it served; each period is judged on its own rule, for the customer and premise its bill names, and its amount belongs to that customer. Sources: R-37(b) ("the meter's readings across every deployment and occupant"); R-25; a2-rules §5.1 and §6.1.

**Given** the common facts (slow meter, no earlier test, SCN-0013's approval), except the premise changed hands: **GP-03 (invented)**, residential, was billed Dec 2025 – Feb 2026 and moved out Feb 28; GP-01 moved in Mar 1 and was billed from March.

**When** the correction is evaluated, (a) slow; (b) the same test finds the meter fast instead.

**Then**
- **(a)** December straddles the window and is given up, as SCN-0013. GP-03 is charged **$16.30** (Jan $8.40, Feb $7.90); GP-01 is charged **$11.70** (Mar – Jun 14). Together $28.00, as SCN-0013. GP-01 is never charged for GP-03's use. Neither charge can ground a disconnection.
- **(b)** Every period is refunded, December whole: GP-03 is owed **$22.50** (Dec – Feb), GP-01 **$11.70**. GP-03's refund is owed though GP-03 has moved out.
- The record names the customer and premise of each period.

---

### SCN-0038 — Crossed meters: one customer refunded, the other charged, and only the charge is limited

*Status:* draft (2026-11-04), not yet sent to Kyle. Reviewer gap (Opus, 2026-11-02). Texas sets no window for crossed meters, and whether such a charge can ground a disconnection is referred to counsel (R-39: "never" until then).
*Rule:* crossed meters are a discovery cause: the operator gives the discovery date and the date the fault is claimed to begin, with evidence. Each meter is its own case. Each period's direction is the sign of its correction. Texas law sets no window; the utility's own limit cuts charges only. Sources: R-39 (the Texas row: no window, enforceable never pending counsel); R-25; R-37(d); a2-rules §2.6.

**Given**
- Gulf Plains (`cast.md` §3). GP-01 and **GP-04 (invented)**, residential, live in the two halves of a duplex. On Feb 1, 2026 both meters were replaced, and the installer connected each to the other's line (the service order of that day is the evidence; **invented**). From February each was billed for the other's gas.
- Found and put right on **Jun 1, 2026**; the claimed start is Feb 1. Evaluated on Jun 10.
- The corrections (**invented**): GP-01 was billed for more gas than GP-01 used: Feb −$6.00, Mar −$5.50, Apr −$3.00, May −$2.00. GP-04 the mirror: +$6.00, +$5.50, +$3.00, +$2.00.

**When** both cases are evaluated, (a) Gulf Plains with no limit of its own; (b) with its two-month limit (charges reach back to Apr 1).

**Then**
- **(a)** GP-01 is refunded **$16.50**. GP-04 is charged **$16.50**, which can never ground a disconnection. Nothing before Feb 1 is evaluated.
- **(b)** GP-01's refund is still **$16.50**. GP-04's February and March are given up (the utility's limit); April begins on Apr 1, inside it; GP-04 is charged **$5.00** (Apr $3.00, May $2.00).
- The two cases are separate findings, one per meter: withdrawing GP-04's charge doesn't touch GP-01's refund.

---

### SCN-0039 — A refund reaching before the utility went live, for bills it never loaded, is held, not declined

*Status:* draft (2026-11-04), not yet sent to Kyle. Reviewer gap (Codex, Opus, 2026-11-02). How the held stretch's refund posts after the rest was delivered is the delivery patch's (v5.4.2-14).
*Rule:* a fast meter's refund over the whole window is mandatory. A stretch of the window for which the platform holds no bill cannot be computed, so it is held with a validated reason; the rest of the correction goes ahead. A "legacy records not loaded" hold covers only days before the utility went live, and it closes only when those bills are loaded, never as unrecoverable. The case cannot freeze while any day of the window is neither billed nor held. Sources: R-37(c); a2-rules §10.1, §10.2, §11.3 (H2, H7, H10).

**Given** the common facts, except the meter is **fast** and Gulf Plains' bills from before going live on Jan 15, 2026 were not loaded: the platform's first bill on this meter covers Jan 15–31 (**invented**: the cycle restarted at go-live), with an error of $4.50 (**invented**); the bills from February are the common table's. No earlier test.

**When** the correction is evaluated and frozen (a) with no hold; (b) after a "legacy records not loaded" hold for Dec 15, 2025 – Jan 14, 2026; then (c) a supervisor tries to close that hold as unrecoverable.

**Then**
- The window starts Dec 15, 2025. The bills on the platform give a refund of **$24.10** (Jan 15–31 $4.50, Feb $7.90, Mar $5.10, Apr $3.30, May $2.10, Jun 1–14 $1.20).
- **(a)** The freeze is refused: 31 days of the window (Dec 15 – Jan 14) are neither billed nor held.
- **(b)** The hold is accepted (it ends before go-live). The case freezes, and the $24.10 is refunded now. The hold stays on the open-holds list.
- **(c)** Refused: this kind of hold closes only when the bills for Dec 15 – Jan 14 are loaded; it then completes, and the case is re-evaluated to include them.
- A hold on any day from Jan 15 is refused: the platform billed those days.

---

### SCN-0040 — A migrated meter's start date doesn't shorten a refund unless an earlier meter corroborates it

*Status:* draft (2026-11-04), not yet sent to Kyle. Reviewer gap (Codex, 2026-11-02). The corroboration test is the build's reading, put to Kyle in the OQ-1 brief and unanswered (a2-rules §16, D9).
*Rule:* a meter's deployment start bounds its window, since another meter's readings were never this meter's. For a charge, any start on record before the fault was recorded shortens the window. For a refund it shortens it only when corroborated: another meter at the same premise, on record before the fault, served into the window and came out on or before the day this one went in. A start that is only the day the meter was loaded onto the platform corroborates nothing. Sources: R-37(a); a2-rules §4.3 (F4, F7c, F9), §7 (the evidence fence).

**Given** the common facts, except this meter's only deployment record starts **Jan 15, 2026**, the day Gulf Plains loaded its meters (the real install was 2019). The seven bills all name this meter. No earlier test.

**When** the correction is evaluated (a) with the test finding the meter fast; (b) fast, and the premise's previous meter is also on record, with this meter's corrected deployment, both loaded before the Jun 15 test was recorded: installed 2015 and removed Mar 1, 2026, when this meter's deployment record is corrected to begin Mar 1 (**invented**), and the bills to Feb 28 name the previous meter; (c) slow, with only the Jan 15 start.

**Then**
- **(a)** The Jan 15 start has no predecessor to corroborate it, so it doesn't bound the refund: window Dec 15, 2025, all seven periods, **$34.20**.
- **(b)** Corroborated: the window starts **Mar 1, 2026**. This meter's periods are March – June 14: **$11.70**. The earlier bills are the previous meter's.
- **(c)** For a charge any recorded start bounds the window: it starts **Jan 15, 2026**. December lies before it; January straddles it and is given up; February – June 14 are billed, **$19.60**, after a supervisor's approval (the six months reach before go-live, with no earlier test).
- A deployment or a removal written after the test was recorded is ignored in all three, whichever way it would move the window: history written after a finding is not evidence about it.
- Had the previous meter come out on Feb 20 and this one gone in on Mar 1 (**invented**), (b) is still corroborated: the previous meter came out before this one went in, and served into the window.

---

### SCN-0041 — Evidence that changes after approval: the approval lapses, and the correction is evaluated again

*Status:* draft (2026-11-04), not yet sent to Kyle. Reviewer gap (Codex, 2026-11-02).
*Rule:* an evaluation is fixed to the facts it was computed from. If any of them changes before the freeze (the cause, the tests, the deployments, a rule row, the utility's limit, the billed periods), the freeze is refused until the case is evaluated again; an approval is of one evaluation and never carries over to the next. A test entered after a later-dated one still governs, flagged as entered out of order. A frozen case found stale at delivery is refused. Sources: R-38; R-36; R-34, R-35; a2-rules §8, §9.2 (G6), §11.2 (I4–I6), §4.2 (I6).

**Given** SCN-0013: evaluated Jul 6, 2026; approved Jul 7 by a supervisor who neither opened the case nor ran the evaluation. Not yet frozen. On Jul 8 a test of this meter is entered that found it accurate (**invented**): (a) a test made on **Mar 10, 2026**, after go-live, recorded with its readings, its paperwork entered late; (b) a test dated **Jan 10, 2026**, before go-live, migrated from the old system as a date only. (A migrated test must be dated on or before go-live, Jan 15, 2026: v5.4.2-12.)

**When** the operator tries to freeze the case on Jul 8, and then evaluates it again.

**Then**
- The freeze is refused: the governing test has changed since the evaluation.
- **(a)** The window starts **Mar 10, 2026**: the result is SCN-0014's, **$6.60** (December – February before the window, March straddling it). The test is flagged as entered out of order. No approval is needed: the governing test is a recorded one with readings.
- **(b)** The window starts **Jan 10, 2026**: December lies before it; January straddles it and is given up; February – June 14 are billed, **$19.60**. The date-only test sets the window, marked as date-only, so the approval gate stands: Jul 7's approval doesn't count, and a new one is needed before the freeze.
- Had the case been frozen on Jul 7, delivery would refuse it as stale; it is unfrozen, evaluated again and frozen again. The Jul 6 evaluation stays on record beside the new one.

---

### SCN-0058 — Which bill a partial payment pays when an older bill holds only a backbilled charge

*Status:* draft (2026-11-04), not yet sent to Kyle. Review round 2 gap (Codex 9). Kyle's answer 12 covers the order within one bill; across bills it meets the oldest-bill-first rule (Kyle 10-15, K-05). Both outcomes are written; the scenario is open until he says which wins. Carrying the limit into collections is v5.4.2-26's (not built).
*Rule:* a payment pays the oldest bill first (K-05), and within a bill the amounts that can ground a disconnection first (answer 12). Aging is balance-forward, newest first (v5.4.2-22). Sources: Kyle 10-15, K-05; Kyle 11-03, answer 12; SCN-0031.

**Given** SCN-0031 (a): the July bill's $40.00 of gas is paid, leaving only its $28.00 backbilling line (never disconnectable). The August bill, issued Sep 5, due Sep 21: **$42.00** of gas, unpaid. On Sep 25 GP-01 pays **$28.00**.

**When** GP-01's account is read on Oct 1.

**Then**
- Balance **$42.00** either way. The aging, balance-forward and newest first, shows it all in 0–30 days (the August bill, 26 days), whichever bill the payment went to.
- **Reading A (what can ground a disconnection first, across bills):** the $28.00 pays August's gas. Left: $14.00 of August (disconnectable) and July's $28.00 backbilling line (never). What may ground a disconnection: **$14.00**.
- **Reading B (oldest bill first):** the $28.00 pays July's backbilling line. Left: August's $42.00, all disconnectable.
- Under reading A, the aging (all $42.00 at 26 days) and what is actually unpaid ($28.00 at 57 days, $14.00 at 26) disagree; a test must assert each against its own rule.
- **Open (Kyle, next batch):** across two bills, does a partial payment go first to what can ground a disconnection (A, "protect the customer"), or to the oldest bill (B)?

---

### SCN-0059 — A refund for months a predecessor utility billed is held until its records come, or closed by a supervisor with counsel

*Status:* draft (2026-11-04), not yet sent to Kyle. Review round 2 gap (Codex 12). The acquisition is **invented**.
*Rule:* a stretch of a fast meter's window that a predecessor billed, before the utility acquired the premise, may be held as "predecessor records unavailable". It needs a deployment of this meter covering the whole stretch and a recorded acquisition after it, both on record before the fault. Unlike the legacy hold, it may close as unrecoverable, but only by a supervisor, citing a document and referring the matter to counsel. Sources: R-37(c); a2-rules §10.1, §10.3, §10.4 (H3, H9, H11, H12).

**Given** the common facts, except: the meter is **fast**; its premise was in the Cedar Creek system (**invented**), which Gulf Plains acquired on **Mar 1, 2026**, the acquisition recorded before the Jun 15 test; the meter's deployment there since 2019 is on record from the same load. Gulf Plains' bills on this meter start Mar 1 (Cedar Creek billed it before). No earlier test.

**When** the correction is evaluated; then (a) a hold "predecessor records unavailable" is opened for Dec 15, 2025 – Feb 28, 2026; (b) one is opened for Dec 15, 2025 – Mar 10, 2026; (c) a clerk closes (a)'s hold as unrecoverable; (d) a supervisor closes it as unrecoverable citing the purchase agreement, without a counsel referral; (e) the same with a counsel referral.

**Then**
- Window Dec 15, 2025. Refunded now from Gulf Plains' own bills, March – June 14: **$11.70**.
- **(a)** Accepted. The case can freeze with the hold open.
- **(b)** Refused: Gulf Plains billed the days from Mar 1.
- **(c)** Refused: not a supervisor.
- **(d)** Refused: closing as unrecoverable needs a counsel referral.
- **(e)** Accepted: closed as unrecoverable, citing the agreement and the referral. The Dec 15 – Feb 28 refund (December $6.20, January $8.40, February $7.90: $22.50 on Cedar Creek's bills) is left with counsel, not declined.
- Without the acquisition on record, (a) is refused.
