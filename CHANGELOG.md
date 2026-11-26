# Changelog

A permanent, cumulative ledger of work sessions on the TallyUtility (tally-utility) repo. Newest entries on top. Never overwrite existing entries.

This file keeps the newest 10 sessions. Older entries are in `changelog-archive/YYYY-MM.md` by the month of their date, unchanged; grep there for history. At wrap-up, add the new entry below this header. Several streams now write here (HANDOFF.md, the board): only the session that mirrors a patch moves the oldest entries into their month's archive file (newest on top there too), so 10 stay live after it.

---

## 2026-11-25 (scenarios, later) — gas cost, zones and reads (SCN-0130 – 0145), ahead of their patches; reviewed; Kyle batch 7

**What was done:**
- **`scenarios/gas-cost-zones-and-reads.md`, 16 scenarios**, written ahead of the rates stream's patches on Ryan's go-ahead (DECISION-LOG, departing from the 10-29 ordering): the gas cost figure picked by billing month (the issue month), none locked, keyed wrong and corrected, a later rebill at the original figure, the billing-side record for the utility's reconciliation, Pecan Flat's minimum bill; pressure zones confirmed before activation, a factor change mid-period, a wrong multiplier backbilled; a high read re-read, re-read fees, an estimate and its catch-up, Gulf Plains' estimates under 16 TAC §7.45 (card, cap, cut-off), rollover, a meter change, a meter moved. Cast §6 and customers BB-17, BB-18, BB-19, GP-08.
- **Review round 7** (Opus, Fable, Codex; `scenarios/review/2026-11-25-gas/`) applied.
- Board note to rates (seven points); Kyle batch 7 (`application/kyle-brief-2026-11-25-scenario-batch-7.md`, K-20, 17 questions); roadmap K-20 uploaded (dataset `decisions` v22).

**Decisions:** Ryan: write the family now, ahead of its patches. This stream's readings, Open with Kyle: billing month = issue month; a factor change states its method; a locked figure is corrected by a supervisor's record.

**Failed approaches / corrections:** reviewers caught the March pipeline safety fee left off, "by cycle" used with the old factor (SCN-0001 means the new), a re-read request dated before its read, the built estimate cap firing a step earlier than written, an estimate's base month before Gulf Plains' go-live, built confirmation records called "not built", and R-30's skip-reason buckets cited as Kyle's ruling (they are a proposal). The source inventory's §7.5519 summary (from GBM's knowledge page) was wrong: the rule sets no effective date.

- **Nine more cases (SCN-0146 – 0154)**, the reviewers' gaps, and **review round 8** (`scenarios/review/2026-11-25-gas-2/`) applied: the move-out bill follows the built part-month default (a share by days); Gulf Plains' six-month breach is surfaced and the bill still goes out (R-21; bills monthly); a stopped meter's unbilled month is an estimated bill, not a backbill, and Texas's three-month rule doesn't reach a city; the empty taxed rental replaced by a residential customer; due dates (Feb 1, not the Jan 16 issue day); BB-02 and PF-03 reuse conflicts removed. Batch 7 is 25 questions. Board note to rates (six more points).

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

## 2026-11-07 (money) — -24 built and taken through five review rounds; -25 re-tested, reviewed (r1) and its r2 built; Ryan: agency refunds to the agency, two limits, and a dispute-penalty rule (held: it conflicts with scenarios')

**What was done:**
- **-24 (unmatched cash, agency pledges):** source inventory and design; tests first; the patch. Unmatched receipts, candidates, dispositions and payments naming them, with the cap on every date. Agencies and their dated agreements. Typed pledges with a database-chosen pay-by. Refunds of agency money routed to the agency. The `agency_pledge` program type retired. Battery -23 ported.
- **-24's review rounds:**
  - r1: all three not yet.
  - r2: Opus and Fable not yet; Codex hit its usage limit, and the author ran its nine probes.
  - r3: both not yet.
  - r4: Opus ready, Fable not yet.
  - r5: Opus not yet, Fable ready.

  Every finding was settled by rule (plans r2–r5). r6 is built: battery 265, races 24, mutations 112.
- **-25 (disputes):** re-tested on today's base (mutations 110/110, every CI step passing), frozen r1, and reviewed by Opus and Fable (both not yet, the same blocker). r2 is built: records written in the same statement as the resolution are refused; duties and stages compared; the shelter's end tied to its document; the utility's tariff cited; the amount capped; the reading released at commit; R-12 keys; a new exact invariant (`fill-manifest.py`). Battery 221, mutations 125.

**Decisions:** DECISION-LOG 2026-11-07 (money):
- a refund of an agency's money goes to the agency, for every agency (10 TAC 6.312(f));
- agency money in a deposit or an untyped credit stays known limits L5 and L6;
- no late penalty while a bill's dispute is open is a platform rule (AC-46). **Held:** it conflicts with Ryan's rulings to the scenarios stream the same day, and the scenarios stream asks him.

**Lessons:** PATCH-LESSONS `constraint-trigger-name-order`.

**Failed approaches:** see `handoffs/schema-money.md`: the status label, the four ledger-tree rules, self-exclusion by id across tables, an AFTER-trigger projection, and a CTE that doesn't read its CTE.

**Next:** Codex's -24 r5 review (it started at 19:15) and its probes; -24 r6 freeze; the dispute ruling; -25 r2 freeze and full review; then -26.

---

## 2026-11-07 (scenarios) — Tally staff access settled (the hidden Tally User, reads logged); Codex round 3 applied; four dispute rulings, one in conflict with money's

**What was done:**
- **Tally's access to a utility (R-27, R-28; renumbered from R-23/R-24, which money had used):** Ryan corrected the premise that Tally staff are read-only, and proposed a hidden Tally User in each utility, impersonated through a recorded session. Recorded with four conditions (no login, never hidden from the change history, the utility can't change it, not counted as staff); new SCN-0080; SCN-0062, 0065, 0068 updated. Tally's reads are logged by the application and shown to the utility (SCN-0061, 0065).
- **Codex round 3** (6 findings; report restored from its log into `scenarios/review/2026-11-05/codex.md`): every finding checked on live `tally` and settled by rule (SCN-0066 job key vs content fingerprint; SCN-0071 which lookups take both dates; SCN-0077/0078 month-end cycles and computation instants; SCN-0079 a dry run created already approved).
- **Disputes (Kyle's flag 1):** a silent city's default (before the due date; until resolved or 60 days after issue); a city's own rule wins; the default protects the disputed amount only. Bluebonnet's "Bill disputes" cast row from Brenham's rules of service; SCN-0033; four board notes to money.
- **Conflict found at wrap-up:** the money session's later ruling (AC-46: a platform rule, whole bill, no 60-day end) disagrees on three points. Board note to money; first item for next session.

**Decisions:** DECISION-LOG 2026-11-07 (scenarios), five entries plus two correction bullets.

**Failed approaches:** told Ryan Brenham had no written dispute rule after searching only rate PDFs and the code of ordinances; the rule was already in `law/dispute/examples/` (corrected the same session; memory saved). `timeout` doesn't exist on macOS; Codex's `-o` overwrote the report it had written.

**Next:** put the dispute conflict to Ryan; then the pending day-60 question, customer classes, Kyle's flags (b) and (c); draft K-14.

---

## 2026-11-06 (rates) — v5.4.2-30 into CI, then three review rounds: r3 ready from Opus and Fable, Codex pending; Kyle's franchise answers in

**What was done:**
- **-30 joins `ci.sh`:** seven older tests ported to its required answers (batteries -09, -16, -20, -21, -23 (money's), -28, -29; race labels-21); PENDING after money's -27; board note to money. New tools: `mutations-30.sh` (battery, `PRE:` and `RACE:` catches), `preconditions-30.sh` (guards that fire only over existing data, re-apply, backfill), `races/levy-30.sh`.
- **Round 1** (all three; Opus and Codex not yet, Fable ready; Codex's probes run, all predictions held): the main gaps were that correcting a premise's state rewrote past reads, and that a place could be closed under an open levy.
- **Round 2** (plan `v5.4.2-30-r2-plan.md`): `service_location_state_history`, written by the database, read as known at an instant; a deferred commit-time check that a place's levies stay covered (a succession passes); late-penalty guards ALWAYS; the repair re-applies after percent facts; exemption services checked; the gaps report lists a published rate with no levy. Opus and Fable: not yet, both on overlapping corrections recorded out of order; Codex rate-limited.
- **Round 3** (plan `v5.4.2-30-r3-plan.md`): the earlier-begun overlapping correction is refused (40001, retry); the coverage check needs an all-tenants role; a past read within two places of one exclusive group refuses; a levy insert that waited re-reads the place's rows. Opus and Fable: **ready** (should-fix: count places not rows; L7's wording overclaims for writers in flight; two untested filters). Codex queued for 16:08 after its reset.
- Results at r3: strict apply twice clean; battery 112/112; preconditions 8/8; races 5/5; mutations 57/57; `ci.sh` 59/59.
- **Kyle answered the franchise base (K-15):** two base values with no default; class-split franchise rules per city; the taxable flag is sales tax only; no 2% cap assumed for city-owned systems. Recorded in the DECISION-LOG; roadmap K-15 answered; dashboard updated.

**Decisions:** DECISION-LOG 2026-11-06 (rates, -30 r1) and (rates, -30 r2): every review finding settled by standing rule; the premise state recorded on change rather than its change refused; the overlapping writer retries rather than clock stamps.

**Failed approaches:** a place-close check at the close (refuses every succession: moved to commit); `clock_timestamp()` for the state history (splits a correction from its own voids); `ALTER TABLE places` after a close in one battery transaction (pending deferred events); a tie-break test ending where it began. Two new PATCH-LESSONS: history-stamped-at-xact-start, succession-checks-at-commit.

**Next:** Codex's r3 review and its probes; a short r4 folding all three reviewers' should-fix items; re-test on the current `tally`; ask Ryan about the mirror; then -31 franchise fees.

---

## 2026-11-06 (money) — v5.4.2-27 rounds 3, 4 and 5 built and reviewed; mirrored

**What was done:**
- **Round 3** (Ryan: "build round 3"): the return check also read from today; a carry is born active for every role; a carry names an undo recorded after the escheat. Battery 135, races 16, mutations 67/67, `ci.sh` 55/55. Reviews: Codex ready; Opus and Fable not yet, the same hole found independently (an undo dated 2099, recorded alone, made the refund's return unrecordable until 2099).
- **Ryan's question on round 3, and the lesson.** Fable's "undo and escheat in one transaction" was put to Ryan as three options. He asked why money-flow questions kept reaching him: this one decides only which record a carry names, so it is settled by rule. Saved to memory (policy vs bookkeeping questions).
- **Round 4** (Ryan: "build round 4"):
  - an undo is dated no later than today (UTC+14), or the row it undoes where later. This is -23's R-02 rule, which r3's plan had wrongly said -23 lacked;
  - r3's second reading is removed (redundant under the rule);
  - the database records whether an undo gave money to an escheated credit (`gave_to_escheated`, re-read under the credit's lock). Built as option 2, not the option 1 Ryan approved: option 1 needed owner-chosen times through most of the battery (DECISION-LOG);
  - new tests: J1 (Codex S2), a carry paying a bill, SR10 and SR11;
  - results: battery 142, races 21, mutations 72/72, `ci.sh` 58/58. All three reviewers ready.
- **Round 5** (Ryan: "do the short round 5", so the mirrored comment is accurate):
  - `cash_drawn_at`'s comment corrected for both terms (Codex r4 S1; J2, M64);
  - an undo and its credit's escheat in one statement gives 23514, not an unclearable 40001 (Opus r4 S1);
  - SR11 checks its SQLSTATE.
  - Results: battery 146, races 21, mutations 74/74, `ci.sh` 58/58. Opus and Fable ready; Codex rate-limited until 16:06, waived by Ryan.
- **Mirror** (Ryan: "waive Codex and mirror -27"):
  - tu.sql 47,634 → 49,090 lines, a pure append, body byte-identical;
  - the build is identical to tally + the frozen r5 (schema dumps and catalog identity); init md5 matches; `ci.sh --build` 56/56;
  - -27 out of PENDING, ahead of -25 and -26 (none of -25, -26 or -30 redefines its functions);
  - AC-44 updated; parity update (no class change, 85 of 135); DEPLOY-VERIFICATION; GBM Section BZ.
- **Every Codex probe of rounds 3 and 4 was run by the author** (25 probes). Every prediction held, including two that showed my "always 0" comment wrong.
- **The rates stream ported -23's battery to -30's columns.** It now passes only with -30 applied after -27.
- **Roadmap:** P1 at 85 of 135 and its summary; R-25, R-26 answered. The dashboard's decision list was merged with the rates stream's newer upload (K-15 answered), not overwritten. Dates unchanged (ready to onboard 2027-06-09 likely).

**Decisions:** DECISION-LOG 2026-11-06 (-27 r3) and (-27); the r3, r4 and r5 plans hold the by-rule calls.

**Failed approaches:**
- r3's second reading (from today), which checked only dates a row falls on and missed an undo recorded alone;
- claiming a reader term "always reads 0", twice disproved by same-transaction rows;
- option 1's strictly-later stamp comparison, which needs chosen times through the whole battery;
- running -23's battery without -30 after the rates port.

**Next:** -24 (unmatched cash, agency pledges); review -25 and -26 (re-test on the new tally first); -23's `refund_reissue` gap and its missing carry check for a returned refund of an escheated credit, in a later patch.

---

## 2026-11-05 (rates) — v5.4.2-29 reviewed by Codex, fixed, reviewed ready by all three and mirrored; tax work inventoried, triaged and designed; v5.4.2-30 claimed, tested first and drafted

**What was done:**
- **-29 (every Texas county and its time zone):** Codex ran on round 2 (Ryan: "run Codex on round 2") and said not yet: re-applying refused after Texas itself was closed and succeeded (the state was still looked up as open today). All five of its probes executed; every prediction held. Round 3 looks Texas up as in force on 1900-01-01; tests: re-apply P10/P10b (fail on r2), failures say how they failed and mutations require that outcome, P7/P8/P10 compare every row before and after, `ci.sh` checks the second marker read. Opus, Fable and Codex all ready on r3 (two test-only items folded: P7's fingerprints checked, the marker counts counties in force on 1900-01-01). Mirrored on Ryan's approval: schema dumps, catalog identity and place data identical to `tally` + frozen r3; init md5 matches; `ci.sh --build` 55/55; re-applied twice over the build, 0 loaded. DEPLOY-VERIFICATION, parity update (no class change; CI-010's data clause closed; 85 of 135), GBM Section BX.
- **Tax work:** `application/rates-build-2026-11-05/`: inventory (17 gaps, 18 open points; agent-built), triage (16 settled by rule or statute; the franchise base to Kyle by Ryan's choice, Slack draft, K-15), design (split into -30, -31, -32; -30's interface). Kyle's batch 2 folded in (a per-charge late-penalty base; a state agency's documented basis).
- **-30 claimed** and built tests-first: `tests/v5.4.2-30/battery-30.sql` (80 checks; failed at its first -30 check on `tally`), then `sql/v5.4.2-30-tax-levies-and-taxability.sql` r0: `tax_kinds`, `tax_levies` (rule-terms tariff keyed by place kind and code), `tax_levy_as_of` (date and recorded instant), `tax_levy_reference_gaps`, no defaults on rate item versions' tax columns and customer types, `in_late_penalty_base`, exemptions per service, `sales_tax_rate` in percent (a platform repair), `premise_places_as_of` with a recorded instant, `customers.state_agency_basis`. Strict apply twice clean; battery 80/80. A CI run with -30 pending: 51 pass, 7 older tests to port (listed in the handoff); -30 taken back out of `PENDING` until then.

**Decisions:** DECISION-LOG 2026-11-05 (rates, -29) and (rates, tax).

**Failed approaches:** a uuid place id as a rule-template key (keys must be text: use the place's kind and code); editing a fact-kind row directly (immutable vocabulary: a reviewed repair); non-canonical JSON numbers in terms (`1.0`); expecting "as known before the build" to read empty (it refuses: the state was not yet recorded).

**Next:** port the seven older tests, put -30 in `ci.sh`, the board note to money, the mutation runner, freeze r1 and review with all three; -31 after Kyle's K-15.

## 2026-11-05 (scenarios) — four rulings from Ryan; Kyle's batch 2 folded in; tenant isolation and date-tracking families (SCN-0060 – 0079), reviewed by Opus and Fable

**What was done:**
- **Ryan's rulings:** R-20 (a backbill outside Texas's protected class is refused until the tariff states a rule); R-21 (Tally may impersonate a utility's users on its own decision, recorded by the database with a required reason; plain Tally access read-only); R-12 (all 273 single-column foreign keys between tenant tables become two-column keys with `tenant_id`, counted on `tally` today); R-22 (one recorded instant per billing run, fixed at its start). Each in the DECISION-LOG and the roadmap.
- **K-13 drafted and sent** (20 questions); **Kyle answered the same day** (GBM `kyle-decisions-2026-11-05-scenario-batch-2.md`), folded into 14 scenarios and the cast: penalties re-assessed on the lower amount after our error, the hidden extra to the next bill, base = tariff-priced lines with tax as a forfeited discount ($6.59 on the reference bill), never compounding, reversed penalties never count; deposit correction for late proof of age, credited deposit is ordinary credit; silent-city backbilling anchors, pre-go-live approval with the legacy record, refunds in two parts, "found" = confirmed, four-year backstop, keying-error rebill limits, two-tier payment order; no per-target override for gas; ch. 182 at city systems, PSF exemption by flag. Logged in GBM (Section BY; Kyle's push added none). Board notes to money and rates.
- SCN-0026's write-off moved to BB-06 (SCN-0052's former customer).
- **Two new families:** tenant isolation (SCN-0060 – 0068) and date-tracking and immutability (0069 – 0079, with 0078 dated meter factors and 0079 dry runs added from review).
- **Review round 3** (`scenarios/review/2026-11-05/`): Opus 18 findings (7 must fix), Fable 12 (2 must fix), all verified and applied: priced-at date is the period end; a rebill always sits on a correction run (dated correction under R-22); shared data stays readable to a switched-off session; -29 is mirrored; run outcomes, run reopening, a second bill from an estimate and a failed-import retry are not built (tests expected to fail); a city never reads the Texas row; test-ready wording where the database changes nothing instead of refusing. Codex did not run (usage limit).
- Dashboard's decision queue refreshed (R-12, R-20 – R-24, K-13, K-14).

**Decisions:** DECISION-LOG 2026-11-05 (scenarios): R-20, R-21, R-12, R-22 (with its correction), Kyle's batch 2.

**Failed approaches:** claiming built behaviour from a patch's intent rather than its guards (SCN-0067's run outcomes, SCN-0066's retry); taking the issue date as a bill's priced-at date; writing that a rebill can sit outside a run (it reached the R-22 decision-log entry before review caught it).

**Next:** Ryan on R-23 (who provisions and restores a utility's supervisors under read-only Tally staff; recommended: a user-administration exception, recorded with a reason) and Codex for round 3 (retry or waive); then R-24 and Kyle's flags; draft K-14; weather normalization.

## 2026-11-05 (money) — v5.4.2-27 designed, built and reviewed twice; Ryan's two calls; round 3 planned

**What was done:**
- **The -27 design**: a credit applied to a bounced payment's shortfall, AC-44's netting. Ryan settled the one open call: a refund that comes back after its shortfall was repaid waits until the repayment is undone (option 1; DECISION-LOG).
- **Round 1** built, then reviewed:
  - the build: `shortfall_applications`, add-only and tenant-keyed; six of -23's readers re-issued; the target's cap; the source's own bounce guard. Battery 80, races 14, mutations 35/35.
  - the reviews: Codex not yet (a later repayment hid an earlier one when a refund came back; invariant privileges), Opus not yet (the same, plus an escheat deadlock), Fable ready.
- **Ryan's second call.** An undo of a repayment whose credit was since escheated carries the money into a new credit (option 1; DECISION-LOG). It is the 10-21 refund rule, applied here.
- **Round 2** built, then reviewed:
  - the return check reads from the first repayment, with an undo counted from the row it undoes;
  - the carry: origin `shortfall_reissue`, in the old credit's overpayment line, checked at commit. Five more -23 functions are re-issued for it, additions only;
  - deposit and refund targets refused; invariant privileges asked alone; the race harness bounded; SR9;
  - results: battery 116, races 16, mutations 58/58; -23's 409 and 51 pass; `ci.sh` 55/55;
  - the reviews: Fable ready; Opus not yet (an undo dated in the future); Codex not yet (a history load's carry born escheated). Every Codex probe was run by the author, and every prediction held.
- **Round 3 plan** written: both blockers and one more fix, all by rule, plus the test gaps. The roadmap got R-23, R-24 and the P1 summary.

**Decisions:** see DECISION-LOG 2026-11-05 (-27 design) and (-27 r1); the r2 and r3 plans hold the by-rule calls.

**Failed approaches:**
- the latest-row boundary (r1);
- counting an undo retroactively with no strict check from today (r2);
- a `SET CONSTRAINTS IMMEDIATE` left on in the battery;
- a void test placed after a draw, so -23's own refusal masked the guard.

**Next:** build -27 round 3 (on Ryan's go), review it with all three, then the mirror; then -24.

## 2026-11-04 (rates) — v5.4.2-28 round 2 reviewed ready by all three and mirrored (ahead of the money patches); v5.4.2-29 (every Texas county and its time zone) built, reviewed once, round 2 frozen

**What was done:**
- **The zone read settled** (Ryan, DECISION-LOG 2026-11-04). The fee check keeps reading the bill's time zone, and every Texas county is loaded once as shared data in a separate patch (-29). Counties and zones rarely change.
- **-28 round 2 built and reviewed.** The fixes:
  - a tier-rate check that survives a dump and restore;
  - a close needs a reason;
  - a summary bill's zone comes from its member bills, whether or not it has an address of its own;
  - the cycle walk counts links another session closed after the writer began (new race `past-cycle-28.sh`);
  - NaN refused;
  - a fraction-unit rate refused with a "store percent" message.
  - Opus, Fable and Codex all said ready, and their test additions were folded in (battery 101, mutations 28/28). The outcome is in `application/rates-build-2026-11-02/v5.4.2-28-r2-review-outcome.md`.
- **-28 mirrored into `tu.sql`** (Ryan, 2026-11-04), ahead of -23, -25 and -26.
  - The build's schema equals the reviewed one, and `ci.sh` is as before.
  - Parity re-graded: CI-089, CI-101 and CI-109 done. CI-010 stays partial (money's UTC day boundaries). 81 of 135.
  - DEPLOY-VERIFICATION, decision log, board, GBM section BW.
  - New PATCH-LESSONS: `jsonpath-check-must-reparse`, `check-passes-null`.
- **-29 built:** `sql/v5.4.2-29-texas-counties.sql`, data only. It loads the 252 counties -16 had not seeded, from the Census 2020 list (copied into `application/places-sources/`). Zones follow 49 CFR 71.6–71.8: Mountain only at El Paso and Hudspeth, and Culberson is Central by law.
  - Older tests that planted real county codes (batteries -16 and -28, race place-close-16) now use even codes, which are never real.
  - Round 1: Opus and Fable said ready. Codex didn't run (usage limit). Both reviewers found that "re-applying is a no-op" broke after a later correction, and Fable found the citation one section off.
  - Round 2 judges every county as of 1900-01-01, cites 71.6(a) and 71.8, and tightens the tests. Results: battery 22, load rules 10/10, source check 5/5, mutations 19/19. `ci.sh`, on `tally` with money's newly mirrored -23: 53 pass, only -15 V23. Plan: `application/rates-build-2026-11-04/v5.4.2-29-r2-plan.md`.
  - `tests/ci.sh` gained a pending marker for a data patch (an SQL condition), which stops the run if it errors.

**Decisions (Ryan, DECISION-LOG 2026-11-04):** the zone read stays (option 1) and the counties are loaded once; -28 is mirrored out of order.

**Failed approaches:** none new. Codex hit "model at capacity" twice on -28 and its usage limit on -29 (reset 18:56 CST).

**Next:** Ryan's call on -29: wait for Codex on round 2, or mirror on Opus's and Fable's reviews. Then the mirror, and tax jurisdictions and franchise fees.
