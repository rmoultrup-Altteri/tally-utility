# Fable review: SCN-0001 to SCN-0026 (2026-11-02)

Read-only. Every worked bill, ledger and aging table was recomputed by hand against the stated rates and Kyle's 10-15 rounding; the aging tables were also traced through `receivables_aging_as_of()` in v5.4.2-22 as mirrored. Rules were checked against the rulings digest, the decision log, `deposits-rules-for-the-core.md`, `a2-rules-for-the-core.md`, patches -15/-18/-19/-21/-22, the parity measurement, the canonical invariants, and Kyle's decision files in gas-billing-memory.

**Arithmetic: every figure in the 26 scenarios checks out.** SCN-0001 ($64.61; $65.18 whole-bill), the reference bill ($65.83), SCN-0002 ($52.61), SCN-0003 ($541.97), SCN-0004 (−$55.83 remainder), SCN-0005 ($54.34 → $45.85, net −$8.49), SCN-0006 ($48.20, +$2.35), SCN-0012 ($0.49 refused; $0.51), SCN-0013/14/16 window dates and sums ($26.80; $5.40; $2.10; 17 and 22 days inside), SCN-0023 ($138.55 aged 64.61/54.34/19.60 at 17/47/78 days), SCN-0024 ($130.06 aged 45.85/64.61/19.60 at 5/41/102 days), SCN-0026 cap arithmetic. The aging in SCN-0023/0024 reproduces exactly what the -22 function returns (per-root netting, newest-first allocation, bucket 0 = 0–30 days). SCN-0020(b)'s "12:00 UTC on Oct 1 = 7:00 a.m. Central" is right for CDT.

Findings, most important first.

---

## Must fix

### 1. SCN-0006 — "current" rates on a gas correction are already refused by a Kyle ruling; the scenario shows them accepted and asks whether they are lawful

**What is wrong.** The Then accepts a "current" run ($48.20) and the Open asks Kyle whether current is ever lawful for a misread. Kyle answered on 2026-06-12 (DE-3): gas corrections must rate at the historical period (the voided bill's period end); `current` is selectable for non-gas only, and a compliant default is not enough, a hard guard is required. Kyle 2026-07-10 (WU-5) repeats it: a misapplied factor is corrected by cancel-rebill at historical rates. The scenario follows the schema's enum (historical | current, CI-007 "structurally enforced") rather than the ruling that narrows it for gas.

**Evidence.** `gas-billing-memory/application/configurable-rules/de-review-answers.md` line 66 and the action table line 140 ("gas correction runs must reject correction_rate_mode=current"); `wu5-wu6-kyle-decisions-2026-07-10.md` line 23.

**Fix.** Then: no basis → refused; historical → $45.85; **current → refused for a gas correction (Kyle 06-12)**; custom → allowed only if it resolves to the original period (or state that custom is open). Drop the Open, or narrow it to "which non-gas services, if any, this platform will ever bill". Note in the family header that the parity record grades CI-007 as enforced on the enum only; the gas-only narrowing is the core's (a contract to record).

### 2. SCN-0025 — the GL rule is a fixed precedence, not "most specific wins", and the "tie" case is a duplicate key refused at entry

**What is wrong.** The Rule says "the most specific mapping in force wins; two equally specific ones are an error", and the Then has a second "distribution / any / rural / any" mapping "refused as a tie". As built and reviewed (r2, Opus S2): precedence is weighted charge (8) > customer class (4) > territory (2) > tax jurisdiction (1), summed over the parts set, so two *different* keys never weigh the same: a mapping keyed on class alone beats one keyed on territory + tax jurisdiction, though the second names more parts. Two rows with the *same* key overlapping in dates are refused by the no-overlap constraint when entered, never reached at export; the export-time "tie" error exists only as a belt-and-braces check that the constraint makes unreachable.

**Evidence.** `sql/v5.4.2-22-periods-snapshot-gl-aging.sql` header "GL code mapping" ("the row of highest precedence ... charge, then customer class, then territory, then tax jurisdiction (r2)"); `gl_mapping_as_of()` specificity expression; `gl_account_mappings_no_overlap` EXCLUDE; rulings digest §10 "most specific wins" is the digest's shorthand for the same thing.

**Fix.** Rule: "a mapping may leave any key part blank; among the mappings that match a line, the charge outranks the class, the class the territory, the territory the tax jurisdiction". Then: replace the tie line with "a second mapping of the same key overlapping in dates is refused when entered"; add the branch that distinguishes the two readings: a mapping (distribution, residential, any, any) and one (distribution, any, rural, the city) both match BB-02's rural residential line, and the class-keyed one wins.

### 3. SCN-0025 — the mapping key cannot tell distribution from the commodity charge or the gas cost adjustment as the vocabulary stands

**What is wrong.** The Given maps "distribution → 4010" and "commodity, gas cost adjustment → 4020" as if they were distinct charge types. The mapping's charge key is the bill line's kind (base charge, usage charge, surcharge, tax, ...), and the CI-016 ruling (Ryan 10-14) has one gas usage line carrying both `rate` and `gas_commodity_rate`, with "one figure or two" left to drafting; the gas cost adjustment is a rider (surcharge). Nothing in -22's key separates distribution revenue from gas-cost revenue, which is the one split a city's auditor will insist on (Brenham keeps its gas cost in a separate fund). A test cannot assert 4010 vs 4020 from the facts given.

**Evidence.** `gl_account_mappings_charge_check` (bill_line codes) in -22; DECISION-LOG "2026-10-14 (CI-016)" left-to-drafting item 2; -22 residual R6.

**Fix.** Either state the mapping on the line kinds the rule knows (usage line → 4010, gas-cost rider → 4020, tax → 2300) and make the distribution/commodity split an Open for Ryan (does the GL key need the rate component?), or mark the charge types in the Given as invented and name the gap. Same point reaches SCN-0001 and the reference bill: whether distribution, commodity and the adjustment are three lines or one usage line with a rider is unsettled, so a test cannot assert line count (see note 22).

### 4. SCN-0018 — the evidence the Given supplies is not one of the three kinds the rule accepts, and the "unbilled use" claim reads as a different cause

**What is wrong.** (b) "a supervisor opens it with a photo and the field report attached". The rule needs **exactly one** evidence reference of one of three kinds: a service order on this meter, a removal of this meter for tamper, or a field report reference containing a letter or digit. A photo is not a kind; two references are refused. Separately, "an estimate of unbilled use from Jan 2025" describes `unbilled_service` (no earlier bill, so no case can open: R-32's "billing period" doesn't exist for it), whereas a tampering case corrects **billed** periods, one signed amount per period, and a period beginning before the claimed start is forfeited.

**Evidence.** `a2-rules-for-the-core.md` §3.3 (exactly one reference, three kinds), §2.1 (unbilled_service opens no case), §6.2–6.3 (amounts per billed period; `straddles_claimed_start`).

**Fix.** Given: GP-01's meter found bypassed on Jun 20, 2026; the field report reference "FR-2026-0620" (one reference); amounts per billed period Jan 2025 – May 2026 (invented), claimed start Jan 1, 2025. Then (b): every billed period from Jan 2025 is included; a Dec 2024 period, had one been claimed, would be given up because it begins before the claimed start; enforceable scope uncapped. Keep (a) as "a clerk, or a supervisor with no reference: refused".

---

## Should add (gaps a real city system hits)

### 5. Cancel-rebill — the common case is missing: a read corrected **upward**, which the void-and-reissue gate refuses

Every correction in SCN-0002–0006 charges less than the voided bill (6.0 → 4.5; 5.0 → 4.0; a held 60.0 → 6.0). R-33's gate (a2-rules §12) runs when a bill is issued and matches voided bills for the same days: a reissue that charges **more** is refused unless its correction target names a cause whose delivery path is reissue (Texas: rate misapplication only) and the usage matches the voided bill exactly. A downward reissue is not gated. So the mirror image of SCN-0002 (true read 7.5 Mcf, not 6.0) by void-and-reissue is refused as the rules stand, and the undercharge must travel another path (an adjustment on the next bill, or a cause not yet ruled). That is the case a small city hits every month and no scenario states it. Add SCN: "the November bill is voided and reissued at 7.5 Mcf: refused; the same correction as a clerical downward reissue: accepted", with the Open to Kyle: which cause an under-read correction cites, since none of the eight Texas causes is "misread". Also state in the family header that SCN-0002–0006 are clerical re-issues carrying **no** backbilling cause (the target's cause is optional for a clerical re-issue, `correction_run_targets.backbill_cause` comment), otherwise SCN-0019(a)'s refusal for a city system would seem to reach them.

### 6. Cancel-rebill × collections — a void of a bill that already carries a late penalty

SCN-0002's bill posted Nov 16; Bluebonnet's due date is 15 days after issue, so by the time many misreads surface the 10% gross-rate penalty has posted. Nothing says what the void does to a penalty computed on the voided amount (it is its own charge; the penalty on $65.83 is not the penalty on $52.61). Add the case: penalty reversed naming the penalty entry, re-assessed on the correction if still unpaid at the new due date (or Open: does a correction bill get a fresh due date?). Sources: R-02, CI-017; late-fee rules are dated rule data (R-11).

### 7. Periods × collections — SCN-0021's late payment found after the penalty posted

By Oct 14 the September bill (due Oct 3) has been penalised. The scenario says the customer's date is Sep 27 "so it carries no late penalty" but the penalty is already on the ledger. State the mechanism: the penalty is reversed naming it, with the reason "postmark Sep 27". Without it a test can't assert the ledger. Source: R-02; -19 CI-058 (effective date and method: postmark).

### 8. Backbilling — SCN-0013 omits the transitional supervisor gate, and the Given lacks the fact that decides it

An adverse correction with **no prior test at all** carries the R-36 gate whenever the six-month reach is before the tenant's cutover date **or the tenant has no cutover date**; the freeze refuses until a supervisor who is neither the opener nor the evaluator approves. SCN-0013 has no earlier test and never mentions the gate or Gulf Plains' cutover date. Add to the common Given: "Gulf Plains went live on the platform on Jan 15, 2026 (invented)" and to SCN-0013's Then: "the charge needs a supervisor's approval before it is frozen (the window reaches Dec 15, 2025, before the cutover)". SCN-0014 (a recorded prior test) is not gated; say so, it is the contrast. Source: a2-rules §9.1–9.2 (pins G1, G8).

### 9. Backbilling — the utility's own limit applies to **every** cause, including uncapped ones; SCN-0017 and SCN-0018 must say whether it is set

Gulf Plains' two-month limit (SCN-0015/0016) is stated per scenario. A tenant's adverse limit applies "for every cause, including uncapped ones: it's where a tenant's own filed-tariff backbilling limit is expressed" (§4.4). With it set, SCN-0017's Feb and Apr charges and most of SCN-0018's periods are forfeited with reason "tenant limit". Each scenario must state "no utility limit" or show the forfeiture. Add the case explicitly (the limit cutting a tampering charge) since it is the one place a city's own rule reaches an uncapped cause.

### 10. Backbilling — no stopped-meter case

A meter that registers nothing is the small-system case (dead index, frozen regulator). Its Texas row differs on three counts a test must see: three months back, not six; no last-test term; the refund direction is *permitted*, not mandatory, so the case may be withdrawn. Add it against the common facts (test Jun 15: window Mar 15; Mar straddles and is given up; Apr–May billed). Source: §1.1 seed row; §11.4 note.

### 11. Backbilling — the unprotected class

A Gulf Plains large-volume customer is outside §7.45: every cause uncapped, "ordinary limitations law and the filed tariff govern", and the utility's own limit is the only bound. One scenario makes the class resolution (§13) and the explicit unprotected rows visible; otherwise a test cannot tell "no row" (refuse) from "uncapped row" (bill).

### 12. Backbilling — crossed meters

Two customers' meters swapped at install: one is owed, the other owes, for the same months. It exercises "each period is judged for that period's customer" (§6.1) and that a refund to one never nets against the other's charge. A city with a few hundred meters sees this at every subdivision build-out.

### 13. Deposits — Brenham's tariff has a second refund route the cast dropped

The source says the residential deposit is refunded after 12 clean months **"and also if no bill is past due"**. The cast and SCN-0007/0008 carry only the 12-month route; SCN-0008's Open says the deposit "never falls due by this route, only at move-out", which is wrong if the second clause is a route of its own. Record the clause in `cast.md` §2 and put its meaning to Kyle (a second route, or a condition on the first?). Source: `cast-sources/texas-city-gas-tariffs-2026-11-02.md` §1 Deposits.

### 14. Deposits × cancel-rebill — a deposit applied to a bill that is later voided (the brief's own example)

SCN-0009 applies the deposit to the final bill. If that bill is voided and corrected, the application must be undone by a negative application naming it (W2 A1–A4), the deposit's principal basis for interest is restored (for a Texas-bound utility, §3.3: an application reduces the basis from its own date; its reversal must restore it), and the refund already computed on the remainder is wrong. Add it on Gulf Plains (interest in play) rather than Bluebonnet.

### 15. Deposits — the rate-change and partial-application interest cases (B4, B6) have no scenario

Gulf Plains' interest rate changes each year; a deposit held across Jan 1 must split its accrual at the change, and a partial application splits it at the application date. Both are routine for every Texas-bound deposit held more than a year, both are worked in the rules doc (B4: $0.51 + $0.42; B6: $0.74 + $0.55), and neither is here. One scenario covering both reaches the "a period never spans a rate change or an application" rule.

### 16. Periods × write-off — when an account becomes eligible for write-off

CI-076's first half (an account progresses to write-off after the tenant's aging threshold) has no scenario; SCN-0026 starts after the write-off. Add: BB-02 moved out Sep 2026 owing $120; threshold 120 days; the aging as of the close shows the debt over 120 days; the core's write-off decision cites the aging and the threshold; a write-off dated inside a closed period is refused. Sources: -22 `write_off_threshold_days` (r2, W3); D-3.

### 17. Cash scope — SCN-0021 and SCN-0026(a) use payments, which the family rule says wait for -23

The 10-29 ruling says families still changing (cash first) are written after their patches mirror. SCN-0021 says so and limits itself to the freeze; SCN-0026(a) silently uses a payment through a collection agency (agency payments are -24's). Either mark (a) as waiting on -23/-24 or restate it as the recovery alone (the recovery entry names the write-off; the cash that funds it is the cash family's).

---

## Should fix (rules and test-readiness)

### 18. SCN-0001 — the gas cost adjustment is not split though the rule family it cites splits every line

CI-106 (cited as "the mid-period rate selection family") bills **each** segment with its own complete stack, taxes and PGA included, and CI-034 prorates usage across a gas-cost factor change by days. The scenario splits the ordinance rates by days but bills commodity, the adjustment and tax on the whole period, and the cancel-rebill header gives the adjustment different values for the September and October **cycles** ($0.30, $0.42). Two readings are possible (the adjustment is a per-cycle figure the city sets, so a cycle is never straddled; or it is a dated factor that splits like a rate), and the scenarios silently take the first while citing the second's invariant. The totals happen to agree here (3.2 × $5.35 + 2.8 × $5.35 rounds to the same $32.10) so Kyle's check will not catch it. Make it cast question 1's second half: is the city's monthly gas cost a per-cycle figure or a dated factor? and state which the scenario assumes.

### 19. SCN-0007 — the twelve bills are not dated

"Twelve clean months" needs twelve counted bills dated on or after Jan 5, 2026. If Bluebonnet's January bill is dated Jan 3 it is not counted and the twelfth clean bill is the January 2027 one, due date Feb 2027 (B14: due on the twelfth, not before). Give the bill dates (e.g. the 15th of each month) and say the twelfth is Dec 15, 2026, so the due record is written then, not on the anniversary. As written, "reaches twelve months on Jan 5, 2027" is an anniversary rule the tariff does not state.

### 20. SCN-0008 — the window question is partly answered for the Texas rule, which should be stated as the contrast

-06's Texas reading counts delinquent occasions over **every** bill since posting (DG4, B15), with the consecutive-clean run trailing. The city's own rule is Kyle's to state, but the Open should say the Texas-bound reading exists, so Kyle answers "same as the state's, or different" rather than from nothing.

### 21. SCN-0023 — the Given needs "no late penalties were assessed"

Bluebonnet's gross rate is 10% higher after the due date, and the July and August bills were unpaid for two months before the Sep 20 payment. Either add the penalties as entries (then the aging changes) or state that none were assessed (invented). A test cannot build the ledger otherwise.

### 22. Line shapes across SCN-0001–0006 and SCN-0025 — a test cannot assert line count

The bills show customer charge, distribution, commodity, adjustment, tax as five lines. The CI-016 ruling has the gas usage line carrying `rate` and `gas_commodity_rate` together ("one figure or two" left to drafting) and the adjustment as a rider (Ryan 10-14: a rider line carries no commodity rate). Say in `README.md` conventions that the worked bills show *components*, not line rows, and that the tax base is the sum of the components named, so a test asserts amounts and arithmetic per component and not the number of rows.

### 23. SCN-0012 — "Gulf Plains' interest rate ... at or above the state floor" is backwards for Texas

Where §7.45 binds, the state's rate is what the utility must pay (CI-130: "at the PUCT-set rate"), and the rules doc treats the utility's rate row as the one in force with the law as a floor only where decision 4 says so. The scenario invents both a utility rate and a floor and says nothing about which the accrual cites. Cite the rule the accrual rests on (§5.5: the rule the deposit was decided under, or the one in force over the period) and give one rate, marked invented.

---

## Notes

### 24. SCN-0016 — the Open is genuinely open (D4), correctly stated; SCN-0019's Open is the right one to ask

Both match the rules doc's own open list. SCN-0014's "whatever it found" is R-34 as ruled. SCN-0015's "cannot be withdrawn while the standing test finds the meter fast" is §11.4 exactly.

### 25. Cast — Brenham's deposit refund rule is stated for a *residential* deposit; the gross-receipts exclusion and "all other city services become delinquent" are recorded but no scenario depends on them. Pecan Flat's "$20 service charge at 1:00 p.m. on the 10th" is a fixed-clock rule that will need the premise's time zone (the -28 ruling on day boundaries) when collections scenarios start; worth a line in cast question 5.

---

**Summary for the author.** Figures are clean. Four must-fix items: SCN-0006 contradicts Kyle's 06-12 gas-historical ruling; SCN-0025 misstates the GL precedence and the tie, and maps charge types the key cannot distinguish; SCN-0018's evidence and cause don't fit the rule. The biggest gap is the upward correction the reissue gate refuses (finding 5), then the supervisor gate and the utility-limit reach in backbilling (8, 9), then Brenham's second deposit-refund route (13).
