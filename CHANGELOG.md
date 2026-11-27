# Changelog

A permanent, cumulative ledger of work sessions on the TallyUtility (tally-utility) repo. Newest entries on top. Never overwrite existing entries.

This file keeps the newest 10 sessions. Older entries are in `changelog-archive/YYYY-MM.md` by the month of their date, unchanged; grep there for history. At wrap-up, add the new entry below this header. Several streams now write here (HANDOFF.md, the board): only the session that mirrors a patch moves the oldest entries into their month's archive file (newest on top there too), so 10 stay live after it.

---

## 2026-11-27 (money) — v5.4.2-25 (disputes) rounds 8 and 9 reviewed; mirrored

**What was done:**
- **Round 8** frozen and reviewed (Opus, Fable, Codex): Opus and Fable ready; Codex not yet, on one sentence of residual R10 (the seeded 16 TAC §7.45 employee stage is not final). Codex's three probes run by the author on fresh clones of frozen r8, all as predicted.
- **Round 9** built (wording only: R10's direction (a) keeps every appeal the law gives before its last stage; the seed sentence names the last stage), frozen and reviewed: all three ready, nothing to fix. Battery 351, mutations 199/199, ci.sh 59/59. Plans `application/wave3-build-2026-10-18/v5.4.2-25-r8-plan.md`, `-r9-plan.md`.
- **Mirrored on Ryan's approval** (commit 894eecf): patch body appended to `tu.sql` (56,306 lines, md5 ac1901a7…); -25 out of PENDING. Verified: schema dumps with and without privileges and catalog identity equal to `tally` + frozen r9 (13,524 lines, md5 fe30daf0…); init md5 matches; ci.sh --build 56/56; TEMP off for every app role; counts 163 tables / 125 policies / 612 triggers / 680 functions.
- Records: DEPLOY-VERIFICATION (new Current line, v5.4.2-25 section); AC-54 to AC-60 and AC-46 updated; parity update (CI-074 GAP to REP; 88 of 135); DECISION-LOG; board (queue now -26, note to rates and scenarios); GBM Section CC; roadmap (parity data refreshed, stale since -28; wave 2 done; dashboard datasets `phases` v20, `parity` v5, `parts` v9). Changelog: 8 oldest entries to `changelog-archive/2026-11.md`.

**Tried and dropped:** a global r7→r8 sed over the Codex prompt (it also rewrote the round-7 file references; fixed by a targeted edit); running the probe script under zsh (`$P` as a command fails; bash script instead).

**Next:** -26 (collections decisions), first review; at its mirror, update AC-10. The container was replaced, so -25's mutation base and other scratch databases are gone.

---

## 2026-11-26 (scenarios, later) — round 9's six gas gaps (SCN-0163 – 0168), reviewed in round 10; two of Ryan's rulings

**What was done:**
- **Six gas cases** (`scenarios/gas-cost-zones-and-reads.md`): a café under Pecan Flat's $20 minimum, with tax; a ten-day final bill against the minimum, shared by days (Pecan Flat's own setting); a Gulf Plains self-read card that fails the checks; a late same-day actual showing an over-estimate; an estimated final reading with no one following; a Gulf Plains estimated final bill, the deposit and interest refunded at once (16 TAC §7.45(5)(F)(i), (5)(C)(iv)(II), read on Cornell LII). Cast PF-09, PF-10, BB-27, BB-28, GP-12, GP-13.
- **Review round 10** (`scenarios/review/2026-11-26-gas-4/`, Opus, Fable, Codex): figures, dates and law quotes held; claims fixed (the minimum comparison is not built, SCN-0135 too; the over-estimate proven only by a same-day reading; the empty-house payer provisional, for Kyle; a failed card rejected, never overridden, since an override ends the run of estimates; Gulf Plains' July bills after the observed holiday; corrected final bills stay marked "Estimated", SCN-0155 too).
- **Ryan's rulings** (DECISION-LOG; roadmap R-29, R-30, dataset `decisions` v28): a late actual showing an over-estimate is the operator's choice, default a rebill while unpaid and catch-up once paid (SCN-0166, variant (c) added); a minimum bill floors the charges before tax, no setting for now (SCN-0163; the board note to rates says CI-103's wording is to correct).

**Tried and dropped:** inferring an overbill from a reading two days before the estimate (the house could have used gas in between).

**Next:** two Kyle questions held for a batch 9 (SCN-0165, SCN-0167; Ryan: "hold them"); then weather normalization and state machines, or the tax items.

---

## 2026-11-26 (scenarios) — batches 3 – 7 sent; the remaining gas read cases (SCN-0155 – 0162); Kyle batch 8

**What was done:**
- Ryan sent Kyle batches 3 to 7 (Slack, two messages); the five briefs and the roadmap marked sent.
- **Eight gas read cases**, round 8's gaps: an estimated final reading, shared by days at the next actual and the final bill corrected (both directions); a missed month at Bluebonnet still billing its customer charge (CI-102); a rebill keeping a carried-forward figure; the self-read card in time and after the bill; estimated months not feeding the three-month average; an actual dated before a billed estimate; a new Gulf Plains customer estimated from the address's history; a final bill corrected after the deposit was applied, both ways.
- **Review round 9** (`scenarios/review/2026-11-26-gas-3/`, Opus, Fable, Codex): all figures and weekdays recomputed clean; claims fixed (CI-122; built vs the core's; deposit entries never reopened, SCN-0029; estimate defaults as utility settings, not rulings; SCN-0162's due date by SCN-0033's settled rule, whose wording now covers a fixed due day; SCN-0142's Open narrowed; SCN-0146's boundary reading is built). Cast: BB-22 – 26, GP-10, GP-11, PF-08; estimate wording; Gulf Plains' part-month default.
- Batch 8 drafted (1 question and a figures check); roadmap K-21, dataset `decisions` v26.

**Next:** batch 8 was sent by Ryan the same day (all six batches now with Kyle); fold in Kyle's answers when they come; round 9's small gaps are optional; then weather normalization and state machines, or the tax items.

---

## 2026-11-25 (scenarios, later) — gas cost, zones and reads (SCN-0130 – 0145), ahead of their patches; reviewed; Kyle batch 7

**What was done:**
- **`scenarios/gas-cost-zones-and-reads.md`, 16 scenarios**, written ahead of the rates stream's patches on Ryan's go-ahead (DECISION-LOG, departing from the 10-29 ordering): the gas cost figure picked by billing month (the issue month), none locked, keyed wrong and corrected, a later rebill at the original figure, the billing-side record for the utility's reconciliation, Pecan Flat's minimum bill; pressure zones confirmed before activation, a factor change mid-period, a wrong multiplier backbilled; a high read re-read, re-read fees, an estimate and its catch-up, Gulf Plains' estimates under 16 TAC §7.45 (card, cap, cut-off), rollover, a meter change, a meter moved. Cast §6 and customers BB-17, BB-18, BB-19, GP-08.
- **Review round 7** (Opus, Fable, Codex; `scenarios/review/2026-11-25-gas/`) applied.
- Board note to rates (seven points); Kyle batch 7 (`application/kyle-brief-2026-11-25-scenario-batch-7.md`, K-20, 17 questions); roadmap K-20 uploaded (dataset `decisions` v22).

**Decisions:** Ryan: write the family now, ahead of its patches. This stream's readings, Open with Kyle: billing month = issue month; a factor change states its method; a locked figure is corrected by a supervisor's record.

**Failed approaches / corrections:** reviewers caught the March pipeline safety fee left off, "by cycle" used with the old factor (SCN-0001 means the new), a re-read request dated before its read, the built estimate cap firing a step earlier than written, an estimate's base month before Gulf Plains' go-live, built confirmation records called "not built", and R-30's skip-reason buckets cited as Kyle's ruling (they are a proposal). The source inventory's §7.5519 summary (from GBM's knowledge page) was wrong: the rule sets no effective date.

- **Nine more cases (SCN-0146 – 0154)**, the reviewers' gaps, and **review round 8** (`scenarios/review/2026-11-25-gas-2/`) applied: the move-out bill follows the built part-month default (a share by days); Gulf Plains' six-month breach is surfaced and the bill still goes out (R-21; bills monthly); a stopped meter's unbilled month is an estimated bill, not a backbill, and Texas's three-month rule doesn't reach a city; the empty taxed rental replaced by a residential customer; due dates (Feb 1, not the Jan 16 issue day); BB-02 and PF-03 reuse conflicts removed. Batch 7 is 25 questions. Board note to rates (six more points).

- **Ryan: netting a credit against a bounce is a utility setting, default at the bounce** (DECISION-LOG); SCN-0087 and SCN-0103 reworked with both settings; board note to money.
- **Kyle's questions triaged** (Ryan): 83 to 28 and five figure checks; 43 points settled by standing rules and recorded in the scenarios as "Settled by rule"; two to Ryan (netting against a bounce), one to counsel (unclaimed-money dating). DECISION-LOG.

**Next:** Ryan sends batches 3 – 7; round 8's small remaining gaps (handoff item 1) or another family, Ryan's choice.

## 2026-11-25 (scenarios) — unmatched cash and pledges (SCN-0117 – 0129), reviewed; two of Ryan's rulings; the transit rate fixed; Kyle batch 6

**What was done:**
- **`scenarios/unmatched-cash-and-pledges.md`, 13 scenarios** after -24 mirrored: money held with no customer (never guessed; split; returned to sender; to unclaimed property after Texas's three years, a city's small amounts to its own treasurer), aged receipts barring their candidates' cut-off, misposted money returned, a held check bouncing, one provider transaction; agency pledges at Gulf Plains under 16 TAC §7.460(b)(2) and at cities, two agencies, lapse, refunds to the agency, no agreement on file, remittance batches. Cast §5 (settings, agencies); Gulf Plains billing days; Pecan Flat's payment date.
- **Review round 6** (Opus, Fable, Codex) applied, including the tax second-pass edits.
- **Tax:** transit authority 0.25% (Transportation Code allows no lower rate), hospital district removed; SCN-0115 BB-13 $202.86; reviewed by Opus.
- **Kyle batch 6** (K-19, 16 questions) drafted as a file. None sent. Roadmap and dashboard updated.
- **Board notes** to money: four gaps (a found-late receipt's date, a miskeyed pledge's ending, the eligibility hold, a check keyed as another agency's) and the two rulings.

**Decisions (Ryan, DECISION-LOG 2026-11-25):** a utility cannot go live until it states its held-money service level, retention and pledge rule; a pledge carries the day the utility received it.

**Failed approaches:** a silent city tariff stated as blocking (an unmade decision); a contract term stated as settled beside its own Open; skipping penalties that posted before money was identified; a Codex wait loop matching "error" in its own output.

**Open:** Kyle's batches 3–6; three citation checks (transit boundary on annexation; §321.3025 and a crime-control district; Property Code §76.601–.602).

**Next:** the rates stream's gas cost, zones and reads, if Ryan agrees.

---

## 2026-11-24 (scenarios) — tax by location (SCN-0104 – 0116), reviewed twice; Kyle batches 3 and 5 as files

**What was done:**
- **`scenarios/tax.md`, 13 scenarios** after -30 mirrored: the tax stack per place, residential gas, exempt customers' $0.00 lines, annexation's two dates, published rate changes and the gaps report, a wrong jurisdiction, Pecan Flat's business-only tax, a tax on a tax, refused tax rows, the liability, overlapping places, a line outside the base. Cast: six Bluebonnet tax rows, new customers.
- **Review round 5** (Opus, Fable, Codex) applied; SCN-0115, 0116 came from it. **Second pass** (Opus 2 / 3 / 6; Fable 3 / 7 / 7) applied: every local tax counts toward the 2% limit, transit included (§321.101(f)), so the east-of-Main district and transit authority are 0.125% each and end Sep 30, 2027 (BB-13 $202.85); the fee's exclusion cited to 34 TAC §3.295(j); §321.3025 reaches only the city's part. Its own edits are not re-reviewed.
- **Corrected elsewhere:** SCN-0055 (c) $447.32; SCN-0054 (a) $66.99.
- **Kyle:** batch 3 (K-14) rebuilt as a file from the Slack draft, item 6 edited; batch 5 (K-18, 11 questions) drafted. None sent. Roadmap and dashboard updated.
- **Board notes** to rates (six tax gaps) and money (tax lines, the liability).

**Decisions:** none by Ryan; statutory readings recorded in `tax.md` (see the handoff's table).

**Failed approaches:** §321.102(h) misread as transit outside the 2% limit; an undated cast place reaching old bills; a statute cited without its scope (§121.211(g)).

**Open:** Kyle's batches 3–5; the rates and money board notes; two leaked postgres-mcp containers.

**Next:** the rates stream's gas cost, zones and reads, if Ryan agrees.

---

## 2026-11-22 (money) — the dispute conflict settled; -24 rounds 9 and 10 reviewed, r11 built; a bill's credit line goes to Kyle

**What was done:**
- **Ryan's dispute rulings** (DECISION-LOG, four entries with scenarios): the scenarios version of the late-penalty rule stands; the silent-city default reaches every customer, and also stops both disconnection steps. AC-46 rewritten, -25 r2 plan item 9 settled, board notes.
- **-25:** the default row designed. First design (inside the delegation document) drafted in a worktree and refused by -17's template; corrected to its own table. Nothing built.
- **-24:**
  - r9 frozen after ci.sh 63/63 and mutations 119/119. Reviews: all three not yet (the returns-due reader was wrong at past dates: found by each alone; a partly misposted payment could strand its share: Opus). Author ran Codex's ten probes and Opus's sequence: all confirmed.
  - r10 (reader at its coordinates; bounced payments return their misposted part; conservation both ways): battery 309, mutations 142, ci.sh 63/63. Reviews: Fable ready, Opus and Codex not yet (what the bank took was ambiguous at the ending: three shapes; author ran Codex's 14 probes, as predicted).
  - r11 built (ending rules; a code only with the move; pending postings not undone; payments not born ended; conservation over every receipt; races SU13 to SU15b): battery 335, races 29. The first ci.sh run failed 8 steps: the new ledger trigger refused every bill void (`tally_void` may not read `payments`); fixed. Then ci.sh 61/61 (while rates was mirroring -30, so to be run again) and mutations 161/161 (M98's check named, run alone).
- **A bill's credit line** (scenarios' finding): confirmed by reading -23; options laid out twice; Ryan asks Kyle (K-17, Slack draft, roadmap).

**Decisions:** three of Ryan's here on disputes (DECISION-LOG 2026-11-22, money -25), day 60 in the scenarios session; the -24 findings by rule (plans r10, r11).

**Lessons:** PATCH-LESSONS `as-of-readers-take-no-final-figure`, `triggers-run-as-every-writer`.

**Failed approaches:** see `handoffs/schema-money.md`.

**Next:** -24 r11 on the base with -30 mirrored, freeze, review; -25 r2's default table; K-17.

---

## 2026-11-22 (scenarios) — the cash family (SCN-0081 – 0103), five of Ryan's rulings, two batches for Kyle

**What was done:**
- **Rulings written in** (SCN-0033, 0024, 0053, 0089, cast): the dispute conflict, day 60, Pecan Flat's penalty, the corrected bill, the hidden $13.23 as one charge with part due later.
- **`scenarios/cash.md`, 23 scenarios:** allocation, overpayment, refunds, bounces, the pot, unclaimed money, paid-bill corrections, undo, designation, regulated first, duplicates, bank returns, closed months, the customer's date.
- **Review round 4** (Codex 2 must / 8 should; Opus 9 / 9 / 2 notes; Fable 2 must / 4 fix / 8 add / 6 notes) applied; SCN-0099 – 0103 came from it. **Second pass** on the changed and new scenarios (Opus 5 / 7 / 2; Fable 3 / 5 / 6) applied; its own edits are not re-reviewed.
- **Second pass's main fixes:** the later-due record per line ($4.44, $8.03, $0.63, $0.13), since one figure per bill left $12.45 of priced lines open ($1.25 penalty, not $1.31); the next bill prints the $13.23 and holds no line; SCN-0087 and 0103 agree on when netting is recorded.
- **Kyle:** K-14 drafted in Slack (item 6 to be edited by Ryan); K-16 drafted, `application/kyle-brief-2026-11-22-scenario-batch-4.md` (22 questions). Neither sent. Roadmap decisions uploaded.

**Decisions:** DECISION-LOG 2026-11-22 (scenarios): four entries, with corrections and what was settled by rule after the re-review.

**Failed approaches:** see `handoffs/scenarios.md` (the matched pair; a shown amount as a line; cast facts reused unchecked; an on-time test that could not fail).

**Open:** the money stream's board notes (the per-line due-later record is the main one); Kyle's answers.

**Next:** tax by location (-30 is mirrored), if Ryan agrees.

---

## 2026-11-22 (rates) — v5.4.2-30 (tax levies and taxability): rounds 3 to 6, mirrored

**What was done:**
- **r3:** Codex's review (its 11-06 job never ran): not yet. A past read of a premise's places answered one place twice, or both within and outside (its probe confirmed).
- **r4:** one live set; alike repeats answer once, disagreeing ones refuse. Known limit L7 restated. All three ready.
- **r5:** Opus r4 found a regression from -16: the plain read, at `now()`, answered a voided district beside its replacement in a transaction begun between two corrections. It now reads what is committed. The counted memberships are picked once; race verdicts name their proof. All three ready: Fable 13,920 and Opus 132,912 reads against -16's reader, no difference.
- **r6:** words only (schema dumps of r5 and r6 differ in one comment; Opus confirmed).
- **Numbers (r5/r6):** battery 127, preconditions 9/9, races 8/8, mutations 78/78, ci.sh 63/63.
- **Mirrored** on Ryan's approval, ahead of -25, -26 and -24, once money's reviewers and suite run had ended: tu.sql 49,958 lines, md5 `373668c9…`, schema parity 0 lines, `ci.sh --build` 61/61.
- **Records:** DEPLOY-VERIFICATION, parity update (no class change; 85 of 135), AC-47, board, GBM Section CA, roadmap.

**Decisions:** DECISION-LOG 2026-11-22 (rates): the two read rules, AC-47, the mirror order (Ryan).

**Lessons:** PATCH-LESSONS `as-of-now-is-not-committed`, `race-catch-names-its-damage`.

**Failed approaches:** see `handoffs/schema-rates.md` (a read at `now()` for a plain read; waiting for an instant's writers; filters written twice; a shared premise; a bare FAIL label).

**Open:** battery -22's R11d failed once in `ci.sh` (1.34 s against 1 s), cause not established; 0.3 s with and without -30, passed since.

**Next:** -31 (franchise fees).

---

## 2026-11-07, evening (money) — -24 rounds 5 to 8 (r9 built); -25's mutation suite repaired (126/126)

**What was done:**
- **The background jobs from the afternoon** had ended with that session; re-run: ci.sh 63/63, -24 mutations 112/112.
- **-25:** the first full mutation run caught 121 of 125. Four tests were weak, not the schema: two checks matched a tag shared by two guards, one mutation emptied an already-empty list, one broke the wrong half of the policy check. Repaired, plus H16f2 and M126: battery 222, mutations 126/126. PATCH-LESSONS `check-names-its-own-guard`.
- **-24, round by round** (each settled by rule; plans r6–r9):
  - r5: Opus not yet (an undo typed nsf left out), Fable ready, Codex not yet: a return dated before a later undo counted one receipt of 100 as 200 received on the dates between (its probe confirmed). Fixed in r6: the return is dated on or after every row under the posting entry.
  - r6: Opus and Fable ready; Codex not yet: in an owner's history load the return could be recorded before the reversal it rests on (confirmed). Fixed in r7: recorded no earlier than every tree row (40001/23514). Also: a redundant date check removed, the invariant lists a missing helper, and Fable's conservation sweep S4b over every date and recorded instant (shown to flag both Codex shapes).
  - r7: Fable ready; Opus not yet: a short return stranded the rest (now exactly the share) and an untested half of the r7 rule; Codex did not start (usage limit).
  - r8: Fable ready (the refusal checks now pin the share); Opus not yet: money awaiting a return showed up nowhere. r9 adds `suspense_misposted_share` and `suspense_misposting_returns_due_as_of`. r9 is built: battery 282, mutations 119, not frozen.
- Every Codex probe (r5: six; r6: nine) was run by the author on fresh clones (`*.author-run.txt`); every prediction held.

**Decisions:** none of Ryan's this session; all review findings settled by rule.

**Lessons:** PATCH-LESSONS `check-names-its-own-guard` (shared tags, an empty list, the wrong leg; a rule made exact).

**Failed approaches:** see `handoffs/schema-money.md` (business date alone; "at most" for a once-only release; editing tests during a run).

**Next:** confirm r9's CI and mutations; Ryan: wait for Codex (resets 00:15 on 11-08) or waive; freeze and review -24 r9; the dispute ruling, then -25 r2.

---
