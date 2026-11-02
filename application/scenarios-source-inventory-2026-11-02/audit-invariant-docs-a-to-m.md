# Audit A: the first 14 scenario docs against the rulings since 2026-10-13

Built 2026-11-02, read-only. Folder: `gas-billing-memory/application/invariant-scenarios/`. Rulings source: `scratchpad/rulings-digest.md` (cited below by date and who ruled; the digest gives the file each comes from).

## The finding that applies to all 14

**None of the 14 docs contains a scenario.** Every one is in the same state: status "DRAFT: axes of variation only, pending domain-expert axes review" (Method 1, step 1 of 6), written 2026-07-03 to 07-05, with a few edits on 07-10 folding in Kyle's July rulings. Each lists its invariants and then a set of "axes": the dimensions a future scenario would vary (for example, "deposit refunded on day 30 versus day 31"). There are **no worked examples and no real numbers anywhere**: no bill, no dollar amount, no dates a domain expert could check. The only figures are statutory parameters quoted from rule text (1/6 of annual billings, 20/30-day bankruptcy windows, 12 consecutive bills, 30-day interest grace, the 12-month backbilling cap).

So below, "affected" counts **axes**, not scenarios. And the verdicts mean something specific. A doc rated "keep" or "revise (light)" still has no scenarios to keep: its axis list is a sound starting outline for scenario writing. A doc rated "revise (heavy)" or "rewrite" has an outline that would send a writer the wrong way, so it has to be fixed before anyone writes scenarios from it.

A second thing applies to all 14: each doc cites schema columns and calls them "today's" state (for example `customers.disconnect_protection_type`, `meter_deployments` as the rate-assignment history, `customer_credits.remaining_amount`). The standing rule now is that scenarios describe rules and rulings, not tables. Every revision should take the column names out of the axis text. That isn't counted as "affected" below unless the column is itself a reversed design.

Families still changing (per the board, `HANDOFF.md`): cash, -23 (in review) and -27 (a credit applied to a bounced payment's shortfall); unmatched cash and agency pledges, -24 (not drafted); disputes, -25 (drafted, not reviewed); collections decisions, -26 (drafted, not reviewed); rates small fixes, -28 (not drafted): state-agency time zone (CI-010), dropping the prompt-pay discount (CI-089), meter test fee by outcome (CI-091), dated rider order (CI-101), rounding (CI-109). Ryan's 10-29 ruling (R-18) says scenarios for families still changing are written **after their patch mirrors**.

---

## 1. account-lifecycle-mimo-and-final-bill

**Covers:** CI-120 (a premise outlives its occupants), CI-121 (the account state machine and its dated attributes), CI-122 (move-in and move-out must produce their billing events), CI-123 (a meter swap reaches billing before the next run), CI-124 (no final bill until pending adjustments settle). 14 axes, 0 scenarios, no numbers.

**What changed under it:**
- **A1–A3 (the premise keeps its zone, tax and history across occupants): confirmed and made structural.** Kyle 10-15 (R-10): service locations never change, and occupancy is a separate dated record with no overlaps at one location. "Last account closed means the premise is closed" can no longer happen by design. The axes stay, but they become "this is enforced" scenarios, not "watch for this failure" scenarios.
- **A2 (zone assignments checked one type at a time): narrowed.** Kyle 10-15 (K-02): zones are tenant-defined, with **separate dated zone sets per factor** (heating value, pressure, rate), assigned to the location *or the meter*. Kyle 10-14 (Q1): a location links to **every** tax jurisdiction it sits in (city, county, transit, special district). The axis's slot list (one BTU zone, one tax jurisdiction, and so on) is too flat.
- **A4 (state sequence pending → active → inactive → closed): narrowed.** Kyle 10-15 (R-10): during a transfer the account stays open and each premise is vacant, held by the owner, or held by a customer. The doc's account state machine has no "held by owner / vacant" occupancy state. It needs that state machine split from the occupancy record.
- **A5 (was a deposit on file in March; autopay; paperless): narrowed.** Autopay settings joined the setup tables that block deletes and retire with an end date (Kyle 10-15, R-03; Ryan 10-14). Account attributes are therefore dated rows, which is what A5 asks for. Keep the axis, but "today's scalar value" is no longer a live failure for autopay.
- **A6 (proving the account was active when it was dunned): reframed.** Ryan's 10-18 collections design (-26): every collections act cites an **eligible collections decision** covering its date, stored once per change of answer. The proof is that decision record, not reconstructed account state.
- **A8 and A14 (move-out deposit disposition; deposit refund against an incomplete final balance): narrowed.** Kyle 10-30 (K-11): all of a customer's credits are one pot, and a credit never shows as refundable while the customer's net position is owed. Ryan 11-01: netting across payments is the core's job, and app code must net before refunding (contract AC-44). A14's "refund computed against an incomplete final balance" scenario now has to show the net-position check. The Texas automatic deposit refund on disconnect (16 TAC §7.45) does not bind city systems (see Texas section).
- **A12–A13 (an adjustment that posts after the final bill): narrowed.** Ryan 10-14: a correction invoice must name the invoice it replaces, and that invoice must be void. Voiding a bill that was never posted posts nothing. A void reverses only what is left of the charge (10-15 drafting). The 10-15 period-close drafting (-22): **a closed period never reopens; corrections post into an open period**. So the "corrected final" response in A12 has to land in an open period, and a post-closure cancel-rebill (A13) cannot reach back into the closed one.
- **R-08 (Kyle 10-15): death is a customer status with a date**, not a program. This touches move-out (who closes a deceased customer's account), and the doc doesn't mention it.

**Texas-only assumptions:** none stated directly. The move-out deposit disposition implicitly assumes the Texas mandatory refund; for city systems it comes from the city's deposit tariff row.

**Verdict: revise (heavy).** About 9 of 14 axes are touched, though most change only in shape, and none is reversed outright. **Family still changing:** cash (-23/-27) for the final-bill refund netting.

**Open items answered by later rulings:**
- Next step 2 (A2 waits on the premise-zone gap): answered in design by K-02 (dated zone sets per factor) and Q1 (multi-jurisdiction links). Close it as answered; whether it's built is a schema-parity question.
- Kyle's 07-10 "no decisions needed in Family 16" note is now stale, since R-10 and R-08 are decisions in this family.

---

## 2. audit-trail-and-subpoena-readiness

**Covers:** CI-093 (every regulated decision can be reconstructed years later), CI-099 (every AI action is audited and linked). 10 axes, 0 scenarios, no numbers.

**What changed under it:**
- **A5 (a value that would drift is captured at decision time): its example is reversed.** It names "a running-ledger-balance recomputation" as a drifting value to snapshot. Ryan 10-13: the stored running balance is dropped, and the balance is the sum of the customer's ledger rows **as of a date and a recorded instant**. That recomputation doesn't drift: it is reproducible from add-only rows. Replace the example. The weather baseline (NHDD) example still stands.
- **A1 (each decision type can be reconstructed): the substrate changed for four of the eleven types.**
  - Disconnect decisions and bypass checks: Ryan 10-18 (-26). The core writes a collections decision (`eligible`, `blocked`, or `unevaluable`, and unevaluable blocks) **once per change of answer**, never per check. Executing a disconnect cites its own decision.
  - Dispute opened or resolved: Ryan 10-18 (-25). Every dispute determination cites the law or tariff row it applied.
  - Refund or credit issued, payment allocated: Kyle and Ryan 10-15 to 11-01 (-23). Money is add-only and every status move names its cause row. Application is stored per bill line, marked oldest-first or operator override.
  - Tax and gas-cost factors: Kyle 10-14. Tax rates go live only after an operator signs off. Every historical gas-cost factor is kept.

  The axis is still right; its per-type sources need rewriting.
- **A3 (the subpoena drill: a 4-year-old disconnect): reframed.** The reconstruction now reads the chain: the disconnect order's eligible decision → the execution's own separate decision → the field-visit match or supervisor override (10-18) → the notices, each citing its own decision. Write it against that chain.
- **A2 (the communication log is the weak link):** partly narrowed. Kyle 10-15 (K-06): the notice format actually sent (large print, braille, language) is recorded. The general outbound log is still not ruled.
- **A4, A6–A10 (AI audit):** no rulings. Unchanged.

**Texas-only assumptions:** none.

**Verdict: revise (light-to-heavy, call it heavy for A1/A3).** Only 3 of 10 axes are touched, but they include the doc's central scenario (A3). **Families still changing:** collections (-26), disputes (-25), cash (-23). Per R-18, write A3 after -26 mirrors.

**Open items answered by later rulings:** none of its open items. The D12-1 coverage map (07-10) is still to be built; its "blocking gap" column will shrink after -23, -25 and -26 mirror.

---

## 3. bankruptcy-and-estate-statutory-holds

**Covers:** CI-082 (the bankruptcy automatic stay), CI-083 (the ledger split before and after the petition date), CI-084 (the 20- or 30-day window to demand adequate assurance), CI-085 (holding collections on a deceased customer). 17 axes, 0 scenarios. It quotes statutory windows (20 days for Chapter 7 and 13, 30 days for Chapter 11) but has no worked example.

**What changed under it:**
- **CI-085 and A14–A16 (estate hold): largely settled by Kyle 10-15 (R-08).**
  - Death is a **customer status with a date**, not a program.
  - Changing ownership needs proof: a death certificate or obituary, *plus* a will, conservatorship, or spouse documentation.
  - The account carries a hold that **blocks shutoff and collections** until it is changed over to a family member.
  - With no update within a month, the system raises a **medium-priority exception**.

  A16's "held indefinitely with no path" now has a ruled answer (the one-month exception). A14's open "evidentiary weight per trigger source" is narrowed: the trigger can be anything, but the ownership change needs the named proof. A15's "new account record versus rename" should be re-read against R-10: occupancy is a dated record, so a survivor takeover is a new occupancy.
- **CI-082, A4 and A5 (the stay as a flag; one protection field holding only one protection): reversed in shape.** The 10-18 collections design (-26) turns every act (notice, late fee, disconnect order, execution, referral) into a decision that reads all inputs, the bankruptcy stay among them. A5's premise, that a single-valued protection field hides a second protection, is about a superseded column, so drop it. A4 (late fees still accruing after the petition) becomes "the late-fee act has no eligible decision," and late-fee terms are dated rule rows (Kyle 10-15, R-11).
- **CI-083 and A7 (payments go to pre-petition debt only as the plan permits): conflicts with the payment-order rulings.** Kyle 10-15 (K-05/R-06): a payment goes to the **oldest bill first**, and a customer can designate a payment only as a bill payment or a deposit, never to a particular bill. Within a bill, regulated lines are paid first (10-16). Applied blindly, oldest-first would put a post-petition payment against pre-petition bills, which is what the stay forbids. **No ruling covers this.** It is a new question for Kyle (see "New questions" below).
- **A8 (a backdated rebill lands in the pre-petition partition):** this composes with the 10-15 rule that a closed period never reopens and corrections post into an open period. The rebill is *dated* in the open period, but its charge belongs to the pre-petition service period. The scenario must keep "posting date" and "service period" apart.
- **A13 (assurance linked to the bankruptcy case):** Kyle 10-15 (K-05) makes "deposit" one of only two designations a customer can put on a payment. An adequate-assurance deposit is therefore a deposit-designated payment, and the link to the case is still unmodelled.

**Texas-only assumptions:** CI-084's research note says "no Texas overlay, implement federal". That is fine, and it is federal law, so it applies to city systems too. The note that "ordinary Texas holds (extreme weather, seriously ill, payment plans) compose freely" assumes §7.45 holds. For city systems those holds come from tariff rows.

**Verdict: revise (heavy).** About 10 of 17 axes are touched. **Families still changing:** collections (-26), cash/payment application (-23).

**Open items answered by later rulings:**
- A16 (no resolution path): answered by R-08, the one-month medium-priority exception.
- A14 (death-notice evidentiary weight): narrowed by R-08's proof list for an ownership change.
- Next step 2 (wait for the programs doc's multi-program framing): moot for death, since R-08 makes death a status, not a program. Still open for bankruptcy.

---

## 4. bi-temporal-foundation

**Covers:** CI-001 (two time axes: when a fact was true, when we recorded it), CI-002 (correction versus retraction), CI-003 (one time basis per computation), CI-004 (dated reference data), CI-009 (deterministic calculation), CI-010 (UTC storage, explicit time zone), CI-011 (conflicting concurrent edits). 10 axes, 0 scenarios, no numbers.

**What changed under it:**
- **CI-011, A9 and A10 (concurrent edits): confirmed.** Kyle 10-15 (K-01): a save is refused if the record changed since it was loaded. The user refreshes and re-enters, and cached edits are never replayed (only memo and note text is kept). Kyle 10-15 (R-04) and Ryan 10-14: the version number changes only through one sealed function. The doc's 07-10 resolution matches. Add the "no replay of cached edits; memo text survives" detail to A9.
- **A1 (which reference data is dated): the list needs updating.**
  - Rate assignment: a customer's rate assignment is a dated, add-only history with no overlaps (Kyle 10-15, R-09).
  - Zones: separate dated zone sets per factor, on the location or the meter (K-02).
  - Tax: each tax jurisdiction is a place, with its own dated tax rows (Kyle 10-14, Q1). Every charge declares its tax status, with no default (Q5).
  - Gas cost: every historical gas-cost factor is kept (Q6).
  - Deletions: setup tables block deletes and retire with an end date (R-03; 17 more tables).

  A1 is still right in kind; it just needs these entries.
- **A7 (calendar-day boundaries: weekend and holiday disconnect bans): narrowed.** The 10-18 collections design: "closed days" are the **utility's staffed days**, a calendar the utility supplies. A missing calendar makes the collections decision **unevaluable, which blocks**. The time-zone rule of the 10-15 period-close drafting (-22): closing is allowed after the last day has ended at UTC-12.
- **CI-010 itself:** -28 (not drafted) carries a "state-agency time zone" fix. Hold A7 and A8 until -28 mirrors.
- **A5 (computation mode: billing, rebill, dry run, replay):** no change.

**Texas-only assumptions:** none.

**Verdict: revise (light).** 3 of 10 axes are touched, and none is reversed. **Family still changing:** -28 (CI-010).

**Open items answered by later rulings:** none open in the doc. Q-1/D1-1 was already closed, and K-01/R-04 confirm it.

---

## 5. billing-pipeline-and-charge-composition

**Covers:** CI-100 (the fixed stage order), CI-101 (rider dependency order), CI-102 (the customer charge at zero usage), CI-103 (the minimum bill), CI-105 (program enrollment honored in billing), CI-109 (rounding). 21 axes (A3 dropped on 07-10, so 20 live), 0 scenarios, no numbers.

**What changed under it:**
- **CI-109, A19–A21 (rounding as a tariff prescription: half-even versus half-up, per line versus total): narrowed.** Kyle 10-15 (K-06): money rounds **to the cent, half-up at the midpoint**, and rates and intermediate math carry **four decimals**. This is a platform rule, not a per-tariff choice. A19's "scenario per tariff rounding dimension" collapses to one rule. A21 (a refactor silently switching half-up to half-even) still matters as a regression scenario. CI-109 is in -28 (not drafted).
- **CI-101, A5–A8 (rider dependency order):** -28 carries "dated rider order". Rider dependencies are now **retired, not deleted** (Ryan 10-14), and the order becomes dated. A5 and A7 need a dated-order case (the order in effect for the bill's period). Hold until -28 mirrors.
- **CI-100, A1 (stage order: … WNA → PGA → tax → adjustments → assembly → GL → …): narrowed.**
  - **GL stage:** Ryan 10-13 accepted Kyle's D-2. The platform is a **customer receivables subledger that exports to the utility's accounting, not a general ledger**. The "GL" stage is an export through a dated GL mapping, and an export refuses an unmapped line (10-15 drafting).
  - **PGA stage:** Kyle 10-14 (Q6/Q7). Gas cost is billing side only: apply the approved factor, with no deferred balance, no true-up, and no unaccounted-for gas cap.
  - **Adjustments stage:** Kyle 10-15 (K-06). There are no early-pay discounts.
- **A8 (the rider stack settles before the tax base is computed): narrowed.** Kyle 10-14 (Q2/Q5):
  - The franchise fee is a percentage of all billed lines except excluded ones (the pipeline safety fee, §8.201).
  - The franchise fee is **not in the sales-tax base**.
  - Tax applies only when both the item and the customer are taxable for that service type.
  - An exempt customer still gets a **$0.00 tax line**.
- **CI-105, A15–A18 (program exclusions in billing): narrowed.** Kyle 10-15 (R-11): program exclusions and late-fee exempt programs become **dated rule data with a citation**, per law or tariff row. A16's "LIHEAP excluded from WNA and certain franchise fees" must be stated as a rule row, not a built-in list. A17: Kyle 10-15 (R-07) says an enrollment lapse **triggers a notice before protection ends**. Ryan 10-18 (-25): `pending_dispute` is no longer a disconnect-protective program.
- **Line arithmetic (touches A9–A11 and A14):** Ryan 10-14 / Kyle 10-15 (R-01). A base-charge line for a partial period carries its coverage dates, days covered, days in the period, and the policy applied. A gas rider line carries **no commodity rate** (Ryan 10-14, -21). These make CI-102's proration checkable per line.

**Texas-only assumptions:** none stated. A16's LIHEAP list is a program assumption, not a jurisdiction one, but it should become rule rows.

**Verdict: revise (heavy).** About 13 of 20 live axes are touched. Most are narrowings; the rounding axes collapse. **Family still changing:** rates/tax (-28: CI-101, CI-109).

**Open items answered by later rulings:**
- A19's open "which rounding dimensions does the tariff prescribe": answered by K-06 (half-up to the cent, four-decimal intermediates).
- Next step 2 (CI-105 blocked on program enrollments): the enrollment substrate has since been ruled (R-07: add-only dated status history). Check whether it is built before closing.

---

## 6. cancel-rebill-correctness

**Covers:** CI-005 (a rebill uses the original period's rules), CI-006 (a rebill is a pure function), CI-007 (the rebill's time basis is recorded explicitly), CI-008 (backbilling cap per jurisdiction). 8 axes, 0 scenarios. The only numbers are statutory caps (Texas 12 months or 6 for meter error, NY 24, CA 3).

**What changed under it:**
- **A7 (a rebill of a rebill): the depth ruling changed.** The doc records D1-3 (07-10): "no schema cap, depth > 3 emits a medium event, no blocking ceiling." Ryan 10-17 (-23 draft): a correction chain is at most **1,000 deep**, and past that the correction posts as a **new unlinked entry**. Update A7.
- **CI-006 (side effects: new bill, ledger entries, lineage): narrowed.**
  - Ryan 10-14: every reversal names exactly what it undoes. A correction invoice must name the invoice it replaces, and that invoice must be void.
  - 10-15 drafting: a void reverses **only what is left** of the charge after earlier reversals.
  - Kyle 10-15 (R-02): reversals against an entry total at most the entry.
  - 10-15 drafting (-22): the rebill's ledger entries post into an **open period**, since a closed period never reopens.

  A5's batch-replay idempotency scenario should show these.
- **A1 (rebill driver):**
  - Read supersede: Kyle 10-15 (K-03). A replacement reading points at the one it replaced, with a required reason code (estimate trued up, meter swap, misread).
  - Dispute resolution: Ryan 10-18 (-25). A reopened dispute is a new dispute.
  - Meter test: K-06. The meter test fee depends on the test outcome (-28, CI-091).
- **A2 (the original-period world):** Kyle 10-14 (Q6). Every historical gas-cost factor is kept so a rebill uses the one in effect then. This confirms the default flavor.

**Texas-only assumptions:**
- **CI-008 and A4 cite "Texas ~12 months per 16 TAC §7.45" as the Texas cap.** §7.45 does not bind city-owned systems, our first customers (standing rule; Kyle K-07, 10-15). For a city system, the cap is whatever its tariff row says, and **a city with no tariff row has no cap rule**, and the record says so. A4's "Texas 12-month vs 6-month meter-error on the same account" applies only to GURA-regulated utilities. The structure "cap per jurisdiction, possibly per driver" is right. Restate the values as law rows (Texas §7.45 row) and city tariff rows.

**Verdict: revise (light).** 3–4 of 8 axes are touched. A7 and A4 need real edits; the rest are additions. **Family still changing:** cash (-23) for the void and reversal caps.

**Open items answered by later rulings:**
- A7's D1-3 "no schema cap": superseded by Ryan 10-17 (1,000 deep, then unlinked).

---

## 7. collections-pipeline-and-disconnect-eligibility

**Covers:**
- CI-067: the eligibility funnel.
- CI-068: the notice sequence.
- CI-069: bypasses checked at each step.
- CI-070: disconnect evidence.
- CI-071: field verification.
- CI-074: a dispute suspends collections on the disputed amount.
- CI-075: the engine is deterministic.

20 axes, 0 scenarios. The numbers are statutory parameters only (Texas 15-day delinquency, 5 working-day notice).

**What changed under it:** almost every axis.
- **CI-067 and A1–A3 (the funnel): reshaped by Ryan's 10-18 design (-26).**
  - The core writes a **collections decision** for every act: notice, late fee, disconnect order, disconnect execution, collections referral.
  - The outcome is `eligible`, `blocked`, or **`unevaluable`, which blocks**.
  - Every act cites an eligible decision covering its date.
  - **Execution cites its own decision**, separate from the order's.
  - Decisions are stored **once per change of answer**, never per check (standing rule).

  A1 needs execution as its own entry path. A3's reproducibility is the cited decision row.
- **CI-069 and A7–A11 (the bypass set):**
  - A7 calls its list "the finalized Texas-launch set," sourced from §7.45, and that fails for city systems (see the Texas section).
  - **Pending dispute is no longer a whole-account bypass.** Ryan 10-18 (-25): a dispute protects the disputed **amount**, not the account. `pending_dispute` stops being disconnect-protective.
  - **Pledges** come with -24 (Ryan 10-16).
  - **Death** is a status hold that blocks shutoff and collections (Kyle 10-15, R-08). The doc lacks it.
  - A9 (a bypass that starts between sweeps) and A10 (the evaluator stops at the first bypass) are reframed by "unevaluable blocks" and by decisions recorded per change of answer.
  - A11 (configuration changes apply prospectively) matches R-11 (dated rule rows with citation).
- **A20 (a side-effecting flag flipped twice on replay): reversed premise.** Protection is no longer a customer flag the engine toggles. It is enrollments (an add-only dated history, R-07) read by a decision. Restate the axis as "a replay writes no second decision row when the answer didn't change."
- **CI-068, A4–A6 (notice sequence and elapsed time):**
  - The step sequence and minimum times are §7.45 / Utilities Code §104.258 values, which do not bind city systems.
  - A5 (business days versus calendar days): Ryan 10-18 (for Kyle), "closed days" are the **utility's staffed days**. A missing calendar makes the decision unevaluable.
  - Ryan 10-18 (for Kyle): the 60+ due-date delay (§182.002: 25 days after issue, no late fee) **does bind city gas systems**.
  - The extreme-weather hold uses the **forecast high** (§7.460).

  These three are pending Kyle, but they reverse GBM's table.
- **CI-070, A12 and A13 (evidence; the photography-prohibited site):** Ryan 10-18 (-26). An order completes only after a field visit whose meter and service point match, **or** a **supervisor's override with a reason and evidence**. Abort reasons use Pennsylvania's vocabulary only (Texas requires none). This matches D9-1. Keep A13.
- **CI-071, A14 and A15:** same 10-18 rule, so A15's "technician overrides without supervisor" has a ruled answer: only a supervisor override, with reason and evidence, completes it.
- **CI-074, A16–A18 (dispute suspension): reshaped by Ryan 10-18 (W3-Q1, -25).**
  - Dispute policies are **rule rows**: one Texas law row (§7.45(6)(D)), plus each city's tariff row. **A city with no tariff row has no dispute terms.**
  - City policies differ. Brenham requires paying 100%, with no cutoff during the investigation. CPS requires paying the undisputed charges and has a two-stage appeal.
  - The disputed amount is a **dated series**. The shelter is a core-written determination (amount, must-pay and basis, what it blocks), which late fees and notices read as of a date.
  - **A reopened dispute is a new dispute.**

  So:
  - A18's "Texas 2-year same-period average cap" is one law row, not the rule.
  - A17's "suspended state never reset" becomes "the shelter determination ends by its terms."
  - A16's "entire balance disputed" case is the Brenham shape, which Brenham's row may allow.
- **CI-075, A19 (re-run uses now()):** unchanged in intent. The decision record makes it checkable.
- **Late fees:** Ryan 10-18 design. Stored late-fee flags are dropped and derived from late-fee charges, and `dunning_stage` moves only with an event behind it. Kyle 10-15 (R-11): late-fee rate, base, cap, grace, and exempt programs are rule rows.
- **Due process (10-18, for Kyle):** city systems still owe *Craft* due process. Before a cutoff, the customer gets a protest heard by someone with authority to cancel it. The doc lacks this.

**Texas-only assumptions:** heavy.
- CI-068's sequence ("15-day delinquency + 5-working-day notice + 5-working-day pre-disconnect per 16 TAC §7.45/TUC §104.258").
- CI-069/A7's "finalized Texas-launch set" (which the Q-6 research also tied to §7.45 via the family-violence exclusion).
- CI-074/A18's "Texas caps required-payment-during-dispute per §7.45."

None of these binds a city-owned system (Kyle K-07, 10-15, standing). For a city, the sequence, the protections and the dispute terms are the city's tariff rows, with **no assumed defaults**. Two exceptions bind cities regardless: §182.002 (the 60+ delay, pending Kyle) and *Craft* due process.

**Verdict: rewrite.** About 18 of 20 axes are touched, and the core shapes (whole-account dispute shelter, bypass flags, Texas sequence as the rule) are reversed. **Families still changing:** collections (-26), disputes (-25), pledges (-24). Per R-18, write after -25 and -26 mirror.

**Open items answered by later rulings:**
- A13 (photography-prohibited site): confirmed by 10-18 (supervisor override with reason and evidence).
- A15 (technician overrides the halt): answered, since only a supervisor override completes the order.
- A16/A17 (whole versus partial dispute; reset on resolution): answered by -25's amount shelter, which ends by its terms; a reopen is a new dispute.
- A18 (dispute grounds and the Texas cap): answered as "rule rows per jurisdiction or city; terms cover grounds and excluded subjects."
- Next step 3 (A16/A17 jointly with the programs doc's DPA-against-disputed-charge axis): the dispute record now exists in design (-25), so this is unblocked once it mirrors.

---

## 8. customer-communication-and-notice-discipline

**Covers:** CI-094 (versioned notice templates), CI-095 (the communication log), CI-096 (keeping the bill image), CI-097 (language and accessibility honored), CI-098 (vendor file intake), CI-135 (print-mail integrity and PII breach). 26 axes, 0 scenarios, no numbers.

**What changed under it:**
- **CI-097, A13 and A16 (preference types; the paper override): narrowed and partly ruled.** Kyle 10-15 (K-06): customers can prefer an accessible notice format (large print, braille, language), and **the format actually sent is recorded**. That gives A14 its evidence: compare the preferred format with the recorded format sent.
- **A9 (a bounced notice blocks the next collections step): reframed by -26.** A notice is a collections act that needs an eligible decision, and a step whose inputs are missing makes the decision unevaluable, which blocks. The race in A9 becomes "the next act's decision reads the bounce as of its date."
- **A5/A6 (notice types):** add two kinds of notice.
  - The **notice before program protection lapses** (Kyle 10-15, R-07).
  - Dispute responses, whose review stages and deadlines now come from each city's tariff row (Ryan 10-18, W3-Q1).
- **CI-135 (A21–A26):** the "bill mailed to the wrong person" question is **still open with counsel** (open list, CI-135). No change, but don't write these until counsel answers.

**Texas-only assumptions:** A15 and next step 3 treat Texas English/Spanish (CI-088, "statewide standard, good-cause exemption") as the Texas instance. If its source is 16 TAC chapter 7, it does not bind city systems; their language obligation would be a tariff row or another statute. **Check CI-088's citation** before writing A15.

**Verdict: revise (light).** About 5 of 26 axes are touched. **Families still changing:** collections (-26) for A9. CI-135 waits on counsel.

**Open items answered by later rulings:**
- A13/A16's "which preference types": answered in part by K-06 (accessible format preference plus the format sent recorded).

---

## 9. customer-programs-and-enrollment-lifecycle

**Covers:** CI-059 (budget billing), CI-060 (payment-arrangement breach), CI-061 (pledge holds), CI-062 (medical certificate), CI-063 (SCRA, the military-service protections), CI-064 (programs stack, they don't override each other), CI-065 (enrollment lifecycle), CI-066 (third-party notification). 18 axes, 0 scenarios. The figures are generic only ("45–60 days", "30–90 days").

**What changed under it:**
- **CI-065, A14 and A15 (lifecycle; expiry reverts automatically): reversed.** Kyle 10-15 (R-07): enrollments keep an **add-only, dated status history**, with an optional end date per program type, and **a lapse triggers a notice before protection ends and never silently drops the customer**. A15 says expiry "reverts to standard treatment automatically, as designed: not a failure." That is now wrong unless the lapse notice went out first. A14's five-state chain should become a dated status history.
- **CI-059, A1–A3 (budget billing's "running budget balance"): narrowed.** Ryan 10-13: stored running balances are dropped, and balances are sums as of a date. The budget balance should be stated as derived (cumulative actual cost minus cumulative levelized payments, read as of a date), not a carried balance.
- **CI-064 ("every … posting-order resolution evaluates all active enrollments"): narrowed.**
  - Kyle 10-15 (K-05): the order within a bill is the jurisdiction's or tariff's rule, confirmed by the tenant at setup.
  - A customer may designate a payment only as a bill payment or a deposit.
  - Regulated lines are paid before unregulated ones (10-16), and no tariff row can turn that off.

  Programs no longer influence posting order, except possibly through agency-pledge restrictions. Who wins when a pledge restriction conflicts with the regulated-first floor is **not ruled** (10-16, for Kyle). Scenarios must not assume an answer.
- **CI-061, A7 and A8 (pledges): defer.** Agency pledges come in -24 (Ryan 10-16, not drafted).
- **A5 (payment-arrangement breach judged against a disputed charge): reshaped.** Ryan 10-18 (-25): the dispute shelters an **amount**, recorded as a determination that late fees and notices read as of a date. The breach check reads that shelter.
- **A11 (SCRA interest cap versus late fees):** late-fee terms are dated rule rows with citation (Kyle 10-15, R-11). The SCRA cap would be a federal law row.
- **A18 (the six Texas-v1 programs):**
  - `pending_dispute` is **no longer disconnect-protective** (10-18).
  - `bankruptcy_automatic_stay` becomes an input to the collections decision.
  - Death is a customer status, not a program (Kyle 10-15, R-08).
  - `regulatory_moratorium` and `elderly_disabled` are §7.45 notions that don't bind cities, except that the 60+ due-date delay (§182.002) does bind cities, per Ryan 10-18 (for Kyle).
- **A12 and A13 (stacking; the evaluator that stops at the first program):** the -26 collections decision reads all inputs, and unevaluable blocks. The D8-3 rule (one active payment arrangement per account) stands.
- **CI-060 / D8-3 note:** "§7.45 composition purposes" is a Texas-law framing. See below.

**Texas-only assumptions:**
- CI-060's note ties the single-arrangement rule to "§7.45 composition".
- A18's launch set is the §7.45 protection list ("regulatory_moratorium", "elderly_disabled").

For city systems these are tariff rows with no assumed defaults. The single-arrangement rule is a platform rule (D8-3), so it survives on its own; just drop the §7.45 justification.

**Verdict: revise (heavy).** About 10 of 18 axes are touched, one reversed (A15). **Families still changing:** collections (-26), disputes (-25), pledges (-24), cash (-23) for the posting order.

**Open items answered by later rulings:**
- Next step 2 / A18 (launch scope: which programs are launch-critical): partly answered. Pending dispute is out of the protective set; death is a status; pledges ship in -24. Ryan should re-confirm the rest against city tariffs.
- A15 (what happens at expiry): answered by R-07, which requires a lapse notice before protection ends.
- A5 (DPA breach against a disputed charge): answered in shape by -25's amount shelter.

---

## 10. deposits-credits-and-operational-integrity

**Covers:** CI-125 (deposit interest), CI-126 (customer credits and escheatment, i.e. unclaimed money turned over to the state), CI-127 (approval threshold captured when the charge is created), CI-128 (anomaly de-duplication), CI-129 (Texas deposit cap and waivers), CI-130 (Texas deposit interest), CI-131 (Texas automatic refund). 20 axes, 0 scenarios. The figures are statutory parameters only (1/6, 30 days, 12 bills, ≤2 delinquencies, 65+, 2 years).

**What changed under it:**
- **CI-126's statement ("tracks … applied and remaining amounts … escheatment state"): reversed.**
  - 10-15 (W2 drafting): the stored applied and remaining counters are dropped, and each is a sum of application rows read as of a date.
  - Ryan 10-21: credit statuses are **active, escheated, voided** only. "Refunded" and "donated" are read from the positions, not stored. A refund that fails, or a donation undone, frees the money again. Escheated is final.
- **A4 (credit origin: overpayment, ad-hoc reversal, invoice credit): narrowed.**
  - Kyle 10-15 (R-06): an overpayment becomes a credit **only if the customer approves** applying it to future bills at payment time. That approval is an add-only record of amount, approver, and time.
  - Ryan 10-21: a refund that comes back after its credit was escheated becomes a **new credit** (`refund_reissue`) with its own dormancy clock.
  - Ryan 10-21 (r4): a payment has at most one live overpayment credit.
  - Whether "ad-hoc reversal" and "invoice credit" remain credit origins needs re-checking against -23.
- **A5 (disposition: applied, refunded, escheated, written off): narrowed.**
  - Kyle 10-30 (K-11): all of a customer's credits are **one pot shown as one net credit balance**. A positive credit never shows as refundable while the net position is owed. Partial refunds up to the available credit are utility policy.
  - Ryan 11-01: netting across payments is the core's job. In the database, one payment's credit can still read as refundable and run its own escheat clock while another payment's bounce leaves the customer owing. App code must net before refunding or escheating (AC-44).

  A5 and A6 need a "net position owed, so no refund and no escheat" case.
- **A6 (escheat due-diligence timing):** add the reissue's fresh dormancy clock (Ryan 10-21).
- **CI-129, A13–A15 (Texas cap, waivers, good-payment exception), CI-130/A16–A17 (Texas interest), CI-131/A18–A20 (Texas automatic refund): Texas-only.** See below. These eight axes are a third of the doc.
- **A9 (an AI-created charge):** Kyle 10-15 (R-01): a one-off charge carries a **reason code**, not a rate or service period. Add that to what is captured atomically.
- **CI-125, A1–A3:** no new ruling. The -15 deposits rewrite (Florida-style interest by customer type, pre-10-13) is the model, and it already made interest per-jurisdiction and per-tariff.
- **CI-127, CI-128, A8, A10–A12:** unchanged.

**Texas-only assumptions:** this is the doc most exposed.
- CI-129, CI-130 and CI-131 are typed "Jurisdiction: texas (16 TAC §7.45)" and read as universal mechanics: "a required residential deposit **cannot** exceed 1/6", "**must** be automatically refunded", "**mandatory, not discretionary**".
- Under the standing rules, §7.45 does not bind city-owned systems, our first customers. For a city, the cap, the waivers, the interest and the refund triggers are the **city's deposit tariff rows** (or another statute, if one binds municipally owned utilities; the doc cites none). With no row, there is no rule, and the record says so.
- The platform keeps the §7.45 figures as the GURA law row, used as a reference. Per "the utility owns regulated values," it keeps the legal value and reports discrepancies; it does not override.
- Next step 2 says A16 (the day-30/day-31 boundary) is "the first scenario written in this family," as a Texas statutory scenario. It should be written as "a tariff with a 30-day no-interest grace."

**Verdict: revise (heavy).** About 13 of 20 axes are touched: A13–A20 by the Texas framing, A4–A6 and A9 by the cash rulings. **Family still changing:** cash (-23, -27) for credits.

**Open items answered by later rulings:**
- A5 (which dispositions exist): answered. "Refunded" and "donated" are derived, not statuses (Ryan 10-21), and escheated is final.
- A7 (escheat jurisdiction for a customer who moved states): not answered, but the standing "Texas-first, not Texas-only" rule confirms keeping it as a real axis, not a placeholder.

---

## 11. disconnect-execution-reconnect-and-deposit

**Covers:** CI-070/CI-071 (restated from the collections doc), CI-072 (gas reconnect needs a technician on site), CI-073 (reconnection deadline), CI-076 (write-off and bad-debt recovery), CI-077 (deposit amount tied to credit evaluation). 14 axes, 0 scenarios. Figures are generic ("24 business hours", "90–180 days", "2×", "1/6").

**What changed under it:**
- **A1/A2 (evidence consumers; verification against meter-swap history): narrowed.**
  - Ryan 10-18 (-26): execution cites its **own** collections decision.
  - Completion needs a field match or a supervisor override with reason and evidence.
  - Kyle 10-15 (R-10): meters have a dated install history per location.
- **A3 (reconnect conditions include "DPA reinstated"): contradicts a July ruling.** D8-1 (Kyle 07-10) made payment-arrangement breach **terminal with no cure**, so a broken arrangement is never "reinstated." Restate it as "a new arrangement enrolled." Not a post-10-13 change, but the doc was never reconciled.
- **CI-076, A8–A10 (write-off): reshaped by Ryan's 10-13 finance ruling and the 10-15/16 drafting.**
  - The platform is a receivables subledger, not a GL. "Moving balance from A/R to bad-debt expense" is an export mapping, not a platform posting (Ryan 10-13, D-2).
  - **Aging is balance-forward from the ledger**: each entry is netted with its reversals, and what is left is aged newest first. Bucket edges are a tenant setting (default 30/60/90/120) (10-15).
  - **A write-off recovery must name its write-off.** The net of a write-off and everything under it stays between 0 and the amount written off at every date (10-15/16).
  - A10 (does write-off get fail-fast GL treatment?) is **answered**: an export refuses an unmapped line, for every line (10-15).
  - A9's "recovery posted to miscellaneous income" is now structurally blocked by the must-name rule.
  - The **Bad Debt Rider true-up** has no ruling. By analogy with gas cost (Kyle 10-14, Q6: billing side only, the true-up is the utility's), it is probably out of platform scope. Raise it.
- **A8 (when the write-off fires):** the collections referral is a collections act needing an eligible decision (-26).
- **CI-077, A11–A14 (deposit formula, waivers, override):**
  - A deposit is one of only two designations a customer can put on a payment (Kyle 10-15, K-05).
  - A reconnect or deposit charge carries a reason code (Kyle 10-15, R-01).
  - The formula variants are tariff rows (the -15 deposits rewrite model).
- **CI-072, A4–A5; CI-073, A6–A7:** no rulings. Unchanged.

**Texas-only assumptions:**
- CI-077's "Texas caps at 1/6 estimated annual billing per 16 TAC §7.45."
- A11's "1/6 … the Texas-capped form."
- A12's "Texas elderly/disabled waiver" and the family-violence waiver (§7.45(5)(C)).

None binds a city system. They are law-row references, with the city's tariff row governing.

**Verdict: revise (heavy).** About 9 of 14 axes are touched. **Families still changing:** collections (-26) for execution; the cash/aging rows already mirrored with -22, so check them.

**Open items answered by later rulings:**
- A10 (write-off GL fail-fast): answered. An export refuses any unmapped line.
- Next step 2 (fold CI-070/071 into one doc?): not answered.
- Next step 4 (A12 waits on the programs doc's launch scope): partly answered (see doc 9).

---

## 12. immutability-and-snapshot

**Covers:** CI-012 (bills are not edited), CI-013 (the ledger is add-only), CI-014 (no hard deletes), CI-015 (a full input snapshot per invoice), CI-016 (values stored on each line). 8 axes, 0 scenarios, no numbers.

**What changed under it:**
- **CI-013 scope and A1/A2: widened and sharpened.**
  - Kyle 10-15 (R-05): payments, credits and one-off charges are **add-only**. A correction is a reversal plus a new row.
  - Ryan 10-15 (W2-Q1): status stays a column but **only moves forward**, and every move names its money row (a bounce names its reversing ledger entry).
  - 10-15 drafting: the stored counters (applied, unapplied, remaining) are dropped.
  - Ryan 10-21: "refunded" and "donated" are not statuses.

  A2's "correct path = reversal transaction" stands. A3's soft-delete shapes for payments and credits must use the ruled status sets (payments: pending, posted, nsf, reversed, voided; credits: active, escheated, voided).
- **CI-012 (bills): narrowed.** Ryan 10-14: the six bill tables keep their own guard, so **a draft can be discarded, an issued bill never**. Voiding a posted bill reverses its charge entry. Voiding a never-posted (held) bill **posts nothing**, which reverses the old behaviour. The line is posting, not mailing: once posted, the customer owes, delivered or not.
- **CI-014 and A3: widened.** Kyle 10-15 (R-03) and Ryan 10-14: **setup tables block deletes too** (17 more tables, including billing cycles, read routes, jurisdictions, bill messages, auto-pay settings and rate dependencies), retiring with an end date. A1's class list is operational records only; add setup records.
- **CI-016 and A4 (line values: "rate, meter factor, BTU factor, commodity rate…"): narrowed.** Ryan 10-14 / Kyle 10-15 (R-01): each line type carries **its own** arithmetic.
  - Usage lines: quantity, unit and rate; plus, for gas, the meter factor, CCF, therms and commodity rate.
  - Base charges: the rate, plus the coverage dates, days covered, days in the period and the policy, for a partial period.
  - Per-unit surcharges: as for usage.
  - Tax lines: their base rows.
  - All other line types: amount only. One-off charges carry a reason code.
  - A gas rider line carries **no** commodity rate (Ryan 10-14).

  The flat list in CI-016 is now a per-line-type list.
- **A4 (snapshot input classes):** tax now needs the per-service-type taxability of both item and customer, and the $0.00 exempt line (Kyle 10-14, Q5). The gas-cost factor stays historical (Q6).
- **CI-015, A5/A8:** no ruling on the bill-level snapshot store.
- **The correction chain (ties to A2):** at most 1,000 deep (Ryan 10-17).

**Texas-only assumptions:** none.

**Verdict: revise (light-to-heavy, call it heavy).** About 5 of 8 axes are touched, though mostly by additions and more precise lists rather than reversals. **Family still changing:** cash (-23) for payment and credit statuses.

**Open items answered by later rulings:**
- Next step 3 (impossibility proofs first): still valid. The R-03 and R-05 add-only and no-delete rules make more of A1 × A2 into structural proofs.

---

## 13. meter-and-premise-master-data

**Covers:** CI-020 (every premise has all its zones), CI-023 (meter attributes complete), CI-026 (dated factor tables by zone), CI-027 (a reading is tied to its meter and service point), CI-032 (meter install history). 11 axes, 0 scenarios, no numbers.

**What changed under it:**
- **CI-020, A1/A2 (one slot per zone type): narrowed.**
  - Kyle 10-15 (K-02): zones are tenant-defined, with **separate dated zone sets per factor** (heating value, pressure, rate), assigned to the **location or the meter**.
  - Kyle 10-14 (Q1): a location links to **every** tax jurisdiction it sits in, each jurisdiction being a place with its own dated tax rows.
  - The franchise-fee base type is chosen per jurisdiction from a short list, with **no default** (Q3).

  A1's "franchising-municipality designation" becomes a jurisdiction link plus that jurisdiction's franchise rule.
- **A3 (annexation and redistricting): confirmed.** Standing rule (Kyle 10-15): where rules differ inside and outside city limits, the rule set attaches **per service location**, as dated rows.
- **CI-027, CI-032 and A9–A11: confirmed and extended.** Kyle 10-15 (R-10): meters have a **dated install history per location**, and replacing a meter does not touch the location. Kyle 10-15 (K-03): a replacement reading points at the reading it replaced and carries a reason code; the old one is marked superseded, not edited. A11 (missing removal read) should include the supersede path.
- **CI-026, A6–A8:** K-02's per-factor zone sets are the "zone-indexed factor table" shape this doc asked for. A7 (lab recalibration) composes with "every historical factor kept."

**Texas-only assumptions:** none. A1's tax list ("MUD, school district") is Texas-flavoured, but it is presented as examples.

**Verdict: revise (light).** About 4 of 11 axes are touched, all by confirmation or refinement. **Family still changing:** rates, tax and meters (-28 touches CI-091 meter test fee, not these invariants directly). Kyle 10-15 (R-11) makes estimation rules dated rule data, which matters for the sibling read docs, not this one.

**Open items answered by later rulings:**
- Next step 2 (draft the gap-state scenarios now or defer?): D1-2 (07-10) already said draft now. Treat it as answered.
- CI-023/D3-1 (rollover point and pressure class become columns): a schema-parity question, not a ruling. Check its grade in the parity measurement.

---

## 14. mid-period-and-temporal-rate-selection

**Covers:**
- CI-104: changing a customer's rate schedule is a dated event.
- CI-106: a billing period split by a rate change bills each part separately.
- CI-107: seasonal rate keyed to the read date.
- CI-108: tier thresholds prorate.
- CI-110: unbilled revenue accrual.
- CI-111: the bill template and the rate engine change together.
- CI-132: regulatory posture is a tenant attribute.

28 axes, 0 scenarios. The one figure is the CI-108 example (30 therms over 30 days becomes 10 therms over 10 days).

**What changed under it:**
- **CI-110, A18–A20 (unbilled-revenue accrual and its reversal): reversed.** Ryan 10-13 (accepting Kyle's D-2): the platform is a receivables subledger, and **unbilled revenue is never a ledger row**. The accrual-and-reversal pair this invariant describes is not a platform posting. At most, the platform reports billed revenue and volumes per period for the utility's accounting (compare Kyle 10-14, Q6, for gas cost). Drop the three axes, or recast CI-110 as an export/report invariant. Either way, the invariant itself needs re-grading.
- **CI-104, A2 (the schedule history "is" the meter-install history): reversed in mechanism.** Kyle 10-15 (R-09): a customer's rate assignment is its **own dated, add-only history with no overlaps**, and the rate-version view shows the rate in effect on the 1st and flags bills that went out at a different rate. The doc's statement that "`meter_deployments` structurally IS the date-effective bracket history" for schedule changes is superseded.
- **A9 (per-segment rate periods shown on the bill): narrowed.** Ryan 10-14 / Kyle 10-15 (R-01): a partial-period base-charge line carries its coverage dates, days covered, days in the period and the policy. So each segment is visible on its lines.
- **A5–A7 (full charge stack per segment):** gas cost is billing side only, using the historical factor in effect (Kyle 10-14, Q6/Q7). Tax uses item-and-customer taxability per service type (Q5). Both confirm per-segment binding without changing the axes.
- **A21–A23 (template and engine change together):** the dropped early-pay discount (Kyle 10-15, K-06) and the meter test fee by outcome are -28 items that will exercise this. No ruling changes the axes.
- **CI-132, A24–A28 (posture): confirmed and strengthened.** The city-systems-outside-GURA rule (Kyle K-07, 10-15) is the concrete case. A municipal tenant's workflows read **its tariff rows**, not §7.45. A24's "municipal-board tenant forced through the PUC filing" is the main real risk. A27 names CI-087 (Texas statement of intent and rate-change waiting period), which may not bind a city system; check its citation.

**Texas-only assumptions:** A27's CI-087 gate (Texas statement-of-intent waiting period) is a GURA process. For city systems, a rate change runs through council or board action per the city's own rules. CI-132 is exactly the invariant that prevents this mistake, so the fix is to make A27's example posture-aware.

**Verdict: revise (light).** About 6 of 28 axes are touched (A2, A9, A18–A20, A27). But the CI-110 reversal removes one whole invariant, so treat that part as a re-grade, not an edit. **Family still changing:** rates (-28) for A21–A23.

**Open items answered by later rulings:**
- Next step 2 (one shared split-and-recompute component?): not ruled.
- CI-110's open accounting-engine question: answered. Unbilled revenue is never a ledger row (10-13).

---

## Texas-only design across the 14 (summary)

The docs that treat 16 TAC §7.45 (or another GURA-only rule) as *the* rule, when for city-owned systems it is only a reference law row:

| Doc | Where | What it should become |
|---|---|---|
| cancel-rebill | CI-008, A4: 12-month cap (6 for meter error) | per-jurisdiction law rows plus city tariff rows; no row = no cap rule |
| collections | CI-068 sequence; CI-069/A7 "finalized Texas-launch bypass set"; CI-074/A18 dispute payment cap | city tariff rows (Brenham, CPS differ); keep §182.002 (60+ delay, pending Kyle) and *Craft* due process as binding on cities |
| programs | CI-060 "§7.45 composition"; A18 protection list | platform rule (one arrangement) stands on its own; protections = tariff rows |
| deposits-credits | CI-129, CI-130, CI-131 (A13–A20), typed "texas (16 TAC §7.45)" and written as mandatory | city deposit tariff rows; §7.45 as reference with a discrepancy report |
| disconnect-execution | CI-077 1/6 cap; A11, A12 waivers | same |
| bankruptcy | "ordinary Texas holds compose freely" | holds come from tariff rows for cities; federal §362/§366 still bind |
| communication | CI-088 English/Spanish as the Texas instance | check its citation; if 16 TAC ch.7, it's not binding on cities |
| mid-period | A27 CI-087 Texas statement-of-intent gate | posture-dependent (CI-132) |

## New questions surfaced (not answered by any ruling)

1. **Bankruptcy versus oldest-bill-first payment order** (doc 3, A7). K-05/R-06 send a payment to the oldest bill first, and a customer can't designate a bill. The automatic stay forbids applying a post-petition payment to pre-petition debt. Which wins, and does the schema need a "post-petition only" application rule? For Kyle; it touches -23 (payment application).
2. **The Bad Debt Rider true-up** (doc 11, CI-076). Is it, like the gas-cost true-up, the utility's record and outside the platform? For Kyle.
3. **CI-088's citation** (doc 8) and **CI-087's citation** (doc 14): do they bind city-owned systems? A citation check, which can be verified before asking anyone.

## Verdict table

| Doc | Axes | Verdict | Still-changing family |
|---|---|---|---|
| account-lifecycle-mimo-and-final-bill | 14 | revise (heavy) | cash -23/-27 |
| audit-trail-and-subpoena-readiness | 10 | revise (heavy: A1, A3) | -26, -25, -23 |
| bankruptcy-and-estate-statutory-holds | 17 | revise (heavy) | -26, -23 |
| bi-temporal-foundation | 10 | revise (light) | -28 (CI-010) |
| billing-pipeline-and-charge-composition | 20 live | revise (heavy) | -28 (CI-101, CI-109) |
| cancel-rebill-correctness | 8 | revise (light) | -23 |
| collections-pipeline-and-disconnect-eligibility | 20 | **rewrite** | -26, -25, -24 |
| customer-communication-and-notice-discipline | 26 | revise (light) | -26; CI-135 awaits counsel |
| customer-programs-and-enrollment-lifecycle | 18 | revise (heavy) | -26, -25, -24, -23 |
| deposits-credits-and-operational-integrity | 20 | revise (heavy) | -23, -27 |
| disconnect-execution-reconnect-and-deposit | 14 | revise (heavy) | -26 |
| immutability-and-snapshot | 8 | revise (heavy, mostly additions) | -23 |
| meter-and-premise-master-data | 11 | revise (light) | — |
| mid-period-and-temporal-rate-selection | 28 | revise (light) + re-grade CI-110 | -28 |
