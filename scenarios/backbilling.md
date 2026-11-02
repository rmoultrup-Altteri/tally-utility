# Backbilling

How far back a correction may reach, and what is given up. Invariants: CI-008 (the cap per jurisdiction), CI-091 (meter test history), the A-2 rulings R-19 to R-39 (Kyle, September). The rules the core evaluates are in `application/a2-rules-for-the-core.md`; the law rows are v5.4.2-18 (mirrored).

**Where this stands for city systems.** -18's rows bind investor-owned and cooperative utilities only: Texas law (Utilities Code 101.003(7)) excludes a municipal corporation. For a city system the lookup refuses, because "unknown law is not permission" (-18 residual R2). A city's backbilling rule is a delegated law row plus the city's own tariff record, to be written with the backbilling tariff table (the rates stream's carried-over item). Neither source tariff (Brenham, Stinnett) states a backbilling rule. So SCN-0013 to 0018 use Gulf Plains, the regulated utility, where Texas law binds; SCN-0019 is the city case.

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

*Status:* draft (2026-11-02), not yet sent to Kyle.
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

*Status:* draft (2026-11-02), not yet sent to Kyle.
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

*Status:* draft (2026-11-02), not yet sent to Kyle.
*Rule:* for a fast meter the refund is mandatory over the same window; a period straddling the window is included whole; no utility setting or operator choice shortens it. Sources: R-25, R-32 (only adverse periods are forfeited), R-37 (option C: no override in the customer's favour direction).

**Given** SCN-0013, except the test finds the meter **fast**: each amount is owed to the customer. Gulf Plains has set its own two-month limit on backbilling (as in SCN-0016).

**When** the correction is evaluated.

**Then**
- The window starts Dec 15, 2025. All seven periods are refunded, Dec included whole: **$34.20** owed to the customer. Every day from Dec 15 to Jun 14 is covered by a period; a refund with an uncovered day could not be completed (a2-rules §11.3). No approval is needed: the gate is for charges only.
- The two-month limit does not apply: it reaches only charges against the customer.
- The case cannot be withdrawn while the standing test still finds the meter fast.

---

### SCN-0016 — The utility's own limit gives up more of a charge, never of a refund

*Status:* draft (2026-11-02), not yet sent to Kyle.
*Rule:* a utility may set a backbilling limit stricter than the law, applied only to charges against the customer; each period it excludes is given up with that reason. Sources: R-37(d); "a utility may be stricter than the law, never looser" (audit rule 5).

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
- **Open (Kyle):** the Apr period is given up whole at the utility's limit as the build does it (r7). Does "forfeit whole" govern the utility's own limit too, or only the law's window? (a2-rules §6.3, open.)

---

### SCN-0017 — A charge and a refund in different months are not netted

*Status:* draft (2026-11-02), not yet sent to Kyle.
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

*Status:* draft (2026-11-02), not yet sent to Kyle.
*Rule:* a tampering or bypass finding has no backbilling window under Texas law, and entering that cause needs a supervisor's approval and recorded evidence. Sources: §7.45(4)(D)(v) and the (4)(E)(vi) carve-out; R-39; a2-rules §3.3.

**Given** GP-01's meter is found bypassed on Jun 20, 2026. The bypass is claimed to have begun Jan 1, 2025; the correction for each billed period from Jan 2025 to May 2026 is given per period (the meter registered some use throughout). Gulf Plains has set no limit of its own.

**When** the case is opened as tampering (a) by a clerk, citing field report FR-2026-0412; (b) by a supervisor, citing no evidence; (c) by a supervisor, citing field report FR-2026-0412.

**Then**
- **(a)** Refused: not a supervisor.
- **(b)** Refused: tampering needs exactly one evidence reference (a service order on this meter, a removal of this meter for tamper, or a field report reference).
- **(c)** Accepted. No window applies: every period from Jan 2025 may be billed, and the charge may ground collection without limit (enforceable scope "uncapped").
- Had Gulf Plains set its two-month limit, it would cut this charge too: the utility's limit reaches every cause, uncapped ones included.

---

### SCN-0019 — A city system's backbilling follows its own tariff, which it must state

*Status:* draft (2026-11-02), not yet sent to Kyle. Written against the ruling; the tariff table is not built.
*Rule:* Texas's backbilling rule does not bind a city-owned system; the city sets its own standard as a tariff record, and a correction is refused while no record states one. Sources: Utilities Code 101.003(7); -18 residual R2; "unknown law is not permission" (places finding 1); standing rule: a city system's policy is its own tariff row, or nothing.

**Given** Bluebonnet City Gas (`cast.md` §2); customer BB-01; the slow-meter facts of SCN-0013 on Bluebonnet's meter. Bluebonnet's published tariff says nothing about backbilling.

**When** the correction is evaluated (a) today; (b) after Bluebonnet records a tariff rule: "six months before the test, bounded by the last test, a straddling month given up whole" (**invented**: a city that chooses to copy the state's rule).

**Then**
- **(a)** Refused: no rule binds a city-owned system, and none of Bluebonnet's own is on record. The refusal names what is missing.
- **(b)** Given also the delegated law row for city-owned systems ("the city sets its own standard"; to be written with the tariff table), the same periods as SCN-0013 are billed (Bluebonnet's own amounts, at its own rates). The record cites Bluebonnet's tariff record and the delegated row, not the Texas rule.
- In (a) a fast meter's refund is held back too: the refusal protects the customer from an uncited charge, but it also delays money owed to them. Kyle's answer below should cover both directions.
- **Open (Kyle):** what do city systems actually do about backbilling when the ordinance is silent: bill back as far as the records go, follow the state's six months by habit, or something else? The answer decides what onboarding asks each city to state.
