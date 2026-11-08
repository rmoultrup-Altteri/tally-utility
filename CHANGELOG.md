# Changelog

A permanent, cumulative ledger of work sessions on the TallyUtility (tally-utility) repo. Newest entries on top. Never overwrite existing entries.

This file keeps the newest 10 sessions. Older entries are in `changelog-archive/YYYY-MM.md` by the month of their date, unchanged; grep there for history. At wrap-up, add the new entry below this header. Several streams now write here (HANDOFF.md, the board): only the session that mirrors a patch moves the oldest entries into their month's archive file (newest on top there too), so 10 stay live after it.

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

---
## 2026-11-04 (scenarios) — Kyle's 17 answers folded in; the Mcf bill-line rule settled; 27 new scenarios (SCN-0033–0059), reviewed by all three

**What was done:**
- **Kyle's answers (Nov 3, GBM `kyle-decisions-2026-11-03-scenario-batch-1.md`)** folded into 15 scenarios and the cast: courtesy carries to the correction (SCN-0004 $42.61); a decrease keeps its age (0024); keying errors routed by the operator, catch-up or rebill, both $68.95 (0027); a silent city's six-month default (0019, 0028); rolling twelve months for deposit penalties (0008); deposit top-up (0010); $100 without a birth date (0011); deposit refund (0029); gas first (0031). Logged in GBM (manifest BV) and the DECISION-LOG; K-12 answered.
- **R-19 settled (Ryan):** the gas conversion figures are required only on energy-billed lines; units Ccf, Mcf, therm, dekatherm, MMBtu; a multiplier stored with its raw quantity. Board note to money.
- **27 new scenarios** for round 1's gaps and round 2's: late penalties on a voided bill and an on-time check; backbilling (stopped meter, large-volume class, two occupants, crossed meters, legacy and predecessor holds, migrated start, evidence changed after approval, payment order across bills); deposits (Texas cap and waivers, interest splits, zero refund, returned check, pooled credit, withdrawn decision, usage-doubled top-up, twelve clean bills); the 60-or-over due date (Util. Code ch. 182, read from the statute); Pecan Flat's whole-amount penalty; the pipeline safety fee; outside-city tax, gas cost credit, pressure factor; periods (credit in aging, pre-period history, withdrawn period, write-off age).
- **Review round 2** (Opus, Fable, Codex; `scenarios/review/2026-11-04/`): no arithmetic errors; must-fixes verified and applied: the unprotected class is refused without a tariff record (-18 R10); a silent city's refund needs a start (Bluebonnet live Jan 1, 2026); penalty dates re-dated to the due dates (SCN-0008 now Apr 1, 2027); a migrated test must predate go-live; corroboration is on-or-before; the per-target override; the locked gas cost mapping; the unbuilt aging date marked; stream readings marked Open.
- Board notes to money and rates; roadmap R-20 (Ryan) and K-13 (Kyle) added; dashboard's decision queue refreshed.

**Decisions:** DECISION-LOG 2026-11-04 (scenarios): Kyle's answers folded in; Ryan's gas bill-line rule.

**Failed approaches:** writing a scenario from an older patch's comments instead of the mirrored one (SCN-0036 read -13's "uncapped" where -18 delegates); a date-only migrated test dated after go-live (SCN-0041); penalty dates that didn't follow the cast's due-date rule.

**Next:** Ryan on R-20 (confirm -18's refusal for the unprotected class; recommended yes); draft Kyle's second batch (K-13); fix SCN-0026's customer; date-tracking, weather normalization and tenant isolation.

## 2026-11-01 to 11-02 (money) — -23 round 7 reviewed, round 8 built and reviewed (Fable ready; Codex and Opus not yet); AC-44 settled; -27 claimed

**What was done:**
- **11-01 (the session before, never logged):** Kyle's K-11 answer recorded (a customer's credits are one pot); round 7 frozen and reviewed by all three (not yet: two lines holding money beside a deficit can't both pay what they read; an escheated credit's own money could rise after the escheat; a deadlock between the escheat move and a give-back; slow walks under bad statistics). Ryan chose option A (no line reads more than it can pay). Round 8 built.
- **Round 8's mutation run** first caught 223 of 225: N207 (a reissue's cap forgetting its share of a take-back) passed because the narrowed agree() no longer sees a cap set too high, so Y7j2 checks it directly; N223 was relabelled to Z4a. Rerun: 225/225. Battery 390/390, races 40/40. Committed; frozen; three reviewers launched.
- **AC-44 settled (Ryan):** netting before an escheat report is a per-state rule (no rule row: report in full); netting is recorded as a new kind of application to the bounced payment's shortfall, never a billed charge (Kyle's K-10 words); that row is **-27**, claimed and moved ahead of -24.
- **Reviews:** Fable ready (two test additions). Codex not yet: a bank's return of an escheated credit's refund can't be recorded while the family is in deficit, because the family cap refuses the required reissue though it moves no money out (probe confirmed). Opus not yet: a refund's return that began before a take-back moves the take-back's share off an escheated reissue after the fact; and two per-side cap mutations pass all 390 checks (same root as N207).
- **CI on -23 r8 + -25 + -26:** all their steps pass; -15's V23 fails because its fixed due date (2026-11-01) has passed (fails on plain `tally` too).
- 7 leaked postgres-mcp containers (10-27) removed.

**Decisions:** option A (11-01); AC-44's per-state escheat netting and -27; -27 before -24. DECISION-LOG 2026-11-01 and 2026-11-02 (-23 r8). Roadmap: counsel question C-03.

**Failed approaches:** narrowing agree() without a direct check on each per-side cap; rewriting roadmap JSON with a different indent; editing the roadmap before pulling the other stream's wrap-up.

**Next:** Ryan's call on Codex B1's fix (recommended: the family cap skips the two internal moves) → r9 plan from all three reviews → build, test, freeze, review. Fix -15's expired test. Then -27.

## 2026-11-02 (scenarios) — first scenarios session: source inventory, shape and cast decided, SCN-0001–0032 drafted and reviewed, 17 questions to Kyle

**What was done:**
- **Source inventory** (`application/scenarios-source-inventory-2026-11-02/`): GBM's 29 per-family docs hold no scenarios (axes-only outlines from July); most material predates the October rulings and treats §7.45 as binding on city systems; the fixtures can't price a bill.
- **Three decisions** (Ryan): scenarios live in `scenarios/` here; the shape (Status, Rule, Given, When, a worked bill, Open); a cast of invented names on real small-city tariffs (Brenham, Stinnett; research in `scenarios/cast-sources/`).
- **32 scenarios** across billing, cancel-rebill, deposits, backbilling, and periods and aging, plus the reviewers' top gaps (an upward correction, a deposit-paid final bill voided, a straddling bill rebilled after close, a never-disconnectable backbill in the aging, Fremont deposit interest).
- **Three-reviewer pass** (Opus, Fable, Codex; `scenarios/review/2026-11-02/`): every figure correct; must-fix rule errors verified and applied (a correction can't name a never-issued bill; a meter error is an adjustment, not a reissue; gas corrections refuse current rates; the close snapshot ages as of the period's last day; GL precedence is charge > class > territory > tax; and others).
- **Board note to rates:** city systems can't backbill until the backbilling tariff table exists.
- **17 questions to Kyle** drafted into his Slack DM; Ryan sent them.

**Decisions:** DECISION-LOG 2026-11-02 (where scenarios live; their shape; the cast).

**Failed approaches:** sending Slack directly to Kyle (his DM is Slack Connect: drafts only; the user search doesn't find him). Fifteen candidate towns were investor-owned-served and dropped from the cast.

**Next:** Ryan on the Mcf bill-line question (roadmap R-19); Kyle's answers (K-12); the remaining reviewer gaps; date-tracking, weather normalization and tenant isolation.

---


## 2026-11-02 (rates) — the rates stream's first session: v5.4.2-28 (small fixes) built, tested and reviewed once; round-2 fix list; two of three calls settled

**What was done:**
- **Claimed -28** and built `sql/v5.4.2-28-rates-small-fixes.sql`. It judges the pipeline safety fee's state-agency exemption at midnight in the bill's own time zone, not Chicago's (CI-010). It gives rider dependencies their own in-force dates and a recorded history, like schedule items (CI-101). It refuses a rate with more than four decimals where rates are entered (CI-109).
- **The prompt-pay discount (CI-089) needs no SQL.** The meter test fee (CI-091) moves to its own patch after dated history.
- **Tests:** battery 77 PASS, mutations 11/11, the -19/-21 batteries and races ported to the dated shape. The full `ci.sh` passes except battery -15 V23, the money stream's (a fixed date that has now passed; board note).
- **Round 1 frozen and reviewed** by Opus (not yet), Fable (ready) and Codex (not yet; I ran its probes).
  - The worst finding: the tier-rate check can't be restored from a database dump.
  - A dependency can be closed without a reason.
  - A summary bill that has its own address skips its member bills' time zones.
  - A long transaction can record a cycle in the past.
  - The fix list is `application/rates-build-2026-11-02/v5.4.2-28-r2-plan.md`.
- **Board notes to money:** V23; -28 in PENDING; UTC day boundaries in deposits and period close; bill-line rates outside the four-decimal check; freezing a summary bill's members at issue.

**Decisions (Ryan, DECISION-LOG 2026-11-02):**
- The scope of -28: four entries.
- A summary bill is fixed once it goes out. Every member bill is final at issue and nothing attaches after; that's the money stream's rule.
- Percentage rates are stored as percent to four decimals. The app accepts fractions and converts them (AC-45).

**Failed approaches:** a jsonpath `(@ * 10000).floor()` in a CHECK. PostgreSQL prints it back as text that doesn't parse, so dumps break.

**Next:** Ryan's call on reading the zone only when it can change the answer. Then build round 2, freeze it, and send it to all three reviewers.

---
