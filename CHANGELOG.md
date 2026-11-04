# Changelog

A permanent, cumulative ledger of work sessions on the TallyUtility (tally-utility) repo. Newest entries on top. Never overwrite existing entries.

This file keeps the newest 10 sessions. Older entries are in `changelog-archive/YYYY-MM.md` by the month of their date, unchanged; grep there for history. At wrap-up, add the new entry below this header. Several streams now write here (HANDOFF.md, the board): only the session that mirrors a patch moves the oldest entries into their month's archive file (newest on top there too), so 10 stay live after it.

---

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

## 2026-10-29 (night, money) — -23 round 6 reviewed (all three: not yet); round 7 built and tested, waiting on Kyle

**What was done:**
- **Round 6's three reviews** (Opus, Fable, Codex) all said not yet. The common finding: a payment's credits never covered each other's shortfall, so after a bounce one credit could read −50 and its reissue +20, with the +20 looking refundable when it wasn't. Opus also found an escheat admitted on money that later came back, and a voided reissue whose share of a take-back stayed in the payment's limit; Codex found the 1,000th reissue losing its payment; all three found a deadlock between a reissue's void and a give-back. Codex's probes were run on a fresh clone (outputs in `codex-r6.md`).
- **Kyle asked in Slack** (Ryan sent it): do a payment's credits net against each other, and which covers a shortfall first, the sibling credits or the payment's own money?
- **Round 7 built on our lean** (siblings first, the latest first), with every other fix: escheat only on the credit's own money, no void of a reissue carrying a take-back's share, the payment's lock first on a reissue's void, a 999-deep reissue bound that raises instead of reading NULL.
- **Tests:** battery 372/372 (Z section new; agree() now checks escheated credits); races 39/39 (CR25 new; deadlocks on r6); mutations 218/218 (N212–N219 new; N203 re-anchored to Y7i; N129's one miss was timing).

**Decisions:** which credit covers a shortfall goes to Kyle, and round 7 isn't frozen until he answers (Ryan). Refusing a reissue's void while it carries a take-back's share is a known limit, not put to Kyle (Ryan). DECISION-LOG 2026-10-29 (-23 r7).

**Failed approaches:** Codex with `-s read-only` (can't write its files); passing a voided reissue's share back to its credit (a new path through every reader and cap).

**Next:** Kyle's answer → record it in GBM → freeze round 7 → three reviewers. Then -24, and -25/-26 to review.

## 2026-10-29 — parallel streams set up (board, per-stream handoffs, clones, CI lock); scenarios run beside the schema; -23 r6 built and frozen

**What was done:**
- **The schema estimate, re-counted.** The 56 open invariants map to about 15 patches after -23: 24 / 47 / 91 working days in one stream. Ryan accepted it: 7 / 12 / 20½ weeks from 10-14, where the old estimate was 3 / 5 / 8.
- **Three decisions on concurrency** (DECISION-LOG 2026-10-29):
  - two schema streams on separate tables (money; rates, meters, places);
  - one clone per stream, each with its own handoff file, and `HANDOFF.md` becomes a board of what crosses streams;
  - scenarios run beside the schema (the gate relaxed between steps 1 and 2; Kyle has room), and the platform starts at schema parity.
- **The roadmap:** ready to onboard likely 2027-06-09 (04-24 to 09-08). `phases.json`, `decisions.json` and the dashboard are updated.
- **Setup** (`7c18a57`, `bb4b83b`):
  - clones `~/code/tally-utility-rates` and `-scenarios`, with memory linked through the shared ccs projects folder;
  - handoffs `schema-money`, `schema-rates`, `scenarios`;
  - the board;
  - `CLAUDE.md` (session start by folder, standing rules, wrap-up) and `CONTEXT.md`;
  - `tests/ci.sh` takes a lock across clones, `/tmp/tally-ci.lock`, and falls back to the main checkout's law venv.
- **-23 r6** (`00b39b1`), every item of the r6 plan:
  - take-backs ordered against the draws (`check_cash_order`);
  - the shortfall placed at the reading (`overpayment_shares`, `overpayment_absorbed_as_of`);
  - the tree's order within one instant;
  - status times change only with their status, and history moves come after their lineage (`cash_lineage_recorded`);
  - reissues stay in their payment's lineage (`overpayment_root`, `overpayment_family`);
  - S1 to S3 and S5 (R17 corrected; R18 to R21).
  - Battery 344, races 38, mutations 210/210, `ci.sh` 49/49 with -25 and -26. The new checks fail against r5 (`red-r6-against-r5.txt`). Frozen, with the brief, in `tests/v5.4.2-23/review/`.

**Decisions made:** DECISION-LOG 2026-10-29 (three entries: the estimate and the streams; the gate; -23 r6's drafting calls).

**Failed approaches:**
- **Placing a reissue's share of a take-back when a position is read.** Its own draw shrank its share, so the cap never applied (Y7j). The fix records the shares when the take-back is.
- **Caps that read the covered positions.** The cover works both ways, so one side could draw the other's money.
- **One-instant fixtures for shapes that need distinct instants.** Within one transaction the shares read that transaction's draws as already made (R17); those shapes are now history loads.
- **A payment lock on a reissue's void.** Nothing observable needed it, so it was removed.

**Next:** launch the three reviewers on the frozen r6 (`review-brief-23-r6.md`, `codex-prompt-r6.md`). Ryan's call this session: in the next one.

---

## 2026-10-28 (afternoon) — session-start context cut (repo docs, memory, global harness); roadmap concurrency what-ifs

**What was done:**
- **Measured the startup load** from transcripts: 72–84k tokens before any tool call; orientation adds 20–50k. The CHANGELOG was never read whole at the start. The real costs were global rules, connectors and skills, plus stale status written in several places.
- **Repo** (`867cd96`):
  - `CLAUDE.md`: the gate, session start, a table of the big files and how to grep them, standing rules, wrap-up.
  - `sql/PATCH-LESSONS.md`: 28 lessons moved out of session memory unchanged, plus the -22 lock-order rule and -25's build notes; 30 in all, with an index.
  - The CHANGELOG keeps the newest 10 entries; 75 older ones are in `changelog-archive/YYYY-MM.md`, checked by script to be present word for word.
  - `CONTEXT.md`'s stale status section replaced with one that has no counts or dates.
- **Memory** cut from 63 to 23 files:
  - 8 status snapshots deleted, after their durable lines moved to HANDOFF, CLAUDE.md and the lessons doc;
  - the 3 working-preference memories moved to a new personal `~/.claude/CLAUDE.md`;
  - new: `three-concurrent-sessions`.
- **Global harness**, with every original backed up in `~/.claude-backups/2026-10-28/`:
  - all of `~/.claude/rules/` (38 files) and `~/.claude/AGENTS.md` removed. They loaded into every repo because the home folder is a parent of each one, and the `common/` and `web/` sets had no `paths:` header;
  - `"disableClaudeAiConnectors": true` in `~/.ccs/shared/settings.json`. The connectors dropped out of this session immediately; Desktop keeps them;
  - 11 installer skills and the `/jira`, `/orchestrate`, `/claw` and `/devfleet` commands moved to the backup.
- **Roadmap concurrency what-ifs** on a scratch copy of `schedule.py`. Likely ready-to-onboard date: June 16 under today's plan; May 16 with P2 beside P1; May 9 with P4 started too; April 11 with P6 at P5's start and P7 at P5 +4 weeks. These dates are about 1.5 weeks too early (the `as_of` artefact). Details are in HANDOFF.

**Decisions made:**
- **Ryan: keep all 34 agents and the Laravel skills.** Agents get chosen when the core workflow is designed; never-used means nothing yet, because no code has been written.
- **Ryan: no mid-session reading rules.** The 1M context and frequent handoffs make long sessions fine.
- **Ryan: about three concurrent sessions that need his input.** The concurrency plan is built around that.
- **Global rules dropped rather than trimmed.** They restated practice a capable model follows anyway, and several contradicted this project: 80% coverage, files under 800 lines, agents spawned unasked, and "attribution disabled", which was false.
- **The connectors are off for Claude Code only.** The per-project `/mcp` disable list would have to be set in each of 17 projects.

**Failed approaches:**
- **Assuming path rules load on any file access.** The typescript rules loaded on a Read of a `.tsx` file, but the web rules did not: they were already loaded at startup and aren't loaded twice. Whether Bash `cat` triggers path rules is untested.
- **Running `schedule.py` in place for a what-if:** it overwrites the dashboard's generated files. Run it on a scratch copy.

**Accuracy / test results:** no schema changes. The CHANGELOG split was verified by script: 85 entries present verbatim, each archive holding only its own month.

**Next steps:**
- The concurrency plan: the gate decision for P2, then up to three workstreams; update `phases.json` and the dashboard.
- -23 r6 on Ryan's go; then the -25 and -26 reviews.

---

## 2026-10-28 — -23 cash round 5 built, frozen and reviewed; the r6 list written; Docker container leak fixed

**What was done:**
- **-23 r5, tests first** (`e73626c`): the W section of battery-23. The failing ones fail against r4 (`red-r5-against-r4.txt`).
- **-23 r5, built** (`4f62ae1`, `67b51e9`):
  - `cash_drawn_at` and `overpayment_split`: one split of a take-back between a payment and its overpayment credit, read by both positions, both caps and the escheat check;
  - a cap on the payment and its credit together (Kyle's K-10 refund cap), with a credit draw taking the payment's lock first;
  - nothing under a refund's posting row once it came back;
  - no give-back onto an escheated overpayment credit;
  - a reissue carries what is left (at most the refund), dated on or after the return, and the commit check requires nothing positive left;
  - no future or infinite status time for any role;
  - arrival rows and donations at READ COMMITTED;
  - the bounce's redundant credit lock removed (N145 retired).
- **Tests added with the build:** W2e/W2f, W10e, W11, W12, CR20/CR20b, CR21 and CR22. The mutations' anchors were updated for the rewritten code, and N171–N191 are new.
- **Frozen** (`83317c0`) and reviewed: Codex (`dd565e3`, with the author's probe run appended), Opus (`4dd597a`) and Fable (`0dbf502`). All three said "not yet".
- **The r6 list:** `application/wave2-build-2026-10-15/v5.4.2-23-r6-plan.md`.
- **Records:** DECISION-LOG 2026-10-28; the design doc's corrections for r4 and r5; the r5 plan's "As built"; the roadmap summary and the dashboard `phases` dataset (dates unchanged).
- **Docker:** Claude Desktop's postgres MCP had leaked 69 containers (about 6.4 GB). CI was OOM-killed twice (signal 9).
  - I killed 62 orphans, with Ryan's approval.
  - The new wrapper `~/.local/bin/postgres-mcp-docker` labels and reaps containers, and stops its own on a signal or end of input. The Desktop config points at it (backup `.bak-2026-10-28`).

**Decisions made:**
- **B2 as built (K-10 decides; reported to Ryan, not asked):** the credit absorbs a take-back from what it still held at that instant, then the payment's own part, then any shortfall (the credit up to its amount, then the payment). *Not the plan's "up to the credit's amount":* Opus's P2 would let 60 out of 50. *Not dynamic:* later draws would shift earlier take-backs.
- **The cap on the payment and its credit together, on every draw on either:** rows of one transaction share an instant, so the split alone cannot keep K-10.
- **A reissue carries `least(refund, what is left)`:** where the payment also bounced, nothing is carried and the customer owes the rest (K-10). This refines Ryan's option 1.
- **r6 settles by rule:** a deficit cancelled on an escheated credit is debt removed, not money given back.

**Failed approaches:**
- **The r5 plan's B2 and a dynamic split:** as above.
- **The shortfall placed at the take-back** (r5 as built): the positions read 40 / −10 when only 30 can be drawn (r6 B2).
- **`(created_at, id)` order within one instant:** a give-back can come before its parent (r6 B3).
- **W4 in one transaction:** no recorded order exists within one transaction; use chosen times.
- **`for i in $ids` in zsh:** the variable isn't split into words. Use `while read`.
- **`docker stop` on these containers:** "404 page not found". Use `docker kill`.

**Accuracy / test results:**

| Check | r4 | r5 |
|---|---|---|
| battery-23 | 252 | 293 |
| races/cash-23.sh | CR1–CR19, 29 | CR1–CR22, 33 |
| mutations-23.py | 170/170 | 190/190 (focused run 29/31, then the full run 189/190; owners moved to W3a and CR18, N145 retired) |
| tests/ci.sh | 49/49 | 49/49 (after the Docker fix) |

**Next steps:**
- Ask Ryan whether to start -23 r6 (the r6 plan). Then freeze and review it with the three reviewers.
- -25 and -26 review after -23 settles.
- Ryan to restart Claude Desktop, so the wrapper takes over and the last 7 untagged containers can be removed.

---

## 2026-10-21 — Kyle's K-10 answered; -23 cash rounds 3 and 4 built and reviewed; the r5 list written

**What was done:**
- **K-10:** Kyle answered (relayed by Ryan). His answer is recorded as GBM `kyle-decisions-2026-10-21-refund-then-bounce.md` plus manifest Section BS (`8003ec9`), and the brief is marked answered (`c55afe1`).
  - A refund is its own movement of money.
  - Two caps: a bounce ≤ payment − reversals; a refund ≤ payment − refunds − reversals.
  - A pending refund blocks the bounce.
  - A return-window hold is tenant policy.
- **-23 r3:** tests first (`530ffee`; every new check failed against r2), then the patch (`494f727`, `7728e96`):
  - a `refund` row names no entry and is > 0;
  - every draw is capped by the source less what was taken back under its arrival entry, at every date;
  - a pending refund blocks any row undoing the posting entry;
  - one arrival entry per source (unique indexes plus a check at the write);
  - positions read `received` / `issued`;
  - a donation undo frees the credit;
  - donations and remittances come from the credit's own account; remittances are frozen by the close (UTC day);
  - draws are not recorded before the source was posted;
  - Ryan's call: `refunded` and `donated` are no longer statuses.
  - -19's P-4 is cancelled before P-2 bounces.
  - Reviewed by Opus, Fable and Codex: "not yet". Codex's probes were run, and all reproduced (`5c3a7ab`).
- **-23 r4:** tests first (`d2b4ca3`), then the patch (`c91a00c`):
  - an overpayment credit's payment bounces per K-10 (one live credit per payment);
  - nothing comes back to an escheated credit, and a `refund_reissue` credit carries a refund that returned (Ryan, option 1), with a deferred commit check;
  - donation corrections are capped;
  - arrival rows are written only while the source is pending or active, under its lock, and count from their own date;
  - the cap runs from the new row's date on;
  - give-back rows are not held up, but never land on an ended source;
  - recorded order covers the arrival tree.
  - Reviewed: all three "not yet" (`3517d0b`); Codex hit its usage limit after writing its review; every probe reproduced.
- **The r5 fix list** is merged: `application/wave2-build-2026-10-15/v5.4.2-23-r5-plan.md`.
- **Records:** DECISION-LOG (four entries dated 2026-10-21), the design doc's "Corrections made in review", and the roadmap phases summary plus dashboard dataset (dates unchanged).

**Decisions made:**
- **Ryan:** no stored `refunded` or `donated` status. *Not "refuse the failure once labelled"* (the bank's return of a refund check would be unrecordable). *Not "refunded → posted"* (breaks forward-only).
- **Ryan:** a refund that returns after escheat goes into a new credit. *Not "remit it to the state", not "leave it flagged".*
- **The overpayment credit and the bounce:** what the credit paid out stands, and what it held goes with the payment. *Not Fable's "wait until the credit is empty"* (it needs refunding or spending bounced money).
- **A source's money counts from its arrival entry's date.** *Not "force the entry's date to the payment's"* (an ACH payment settles later).
- **r5 B4 refines Ryan's option 1:** a reissue carries only the escheated credit's positive remainder. Where the payment also bounced, nothing is carried. Reported to Ryan.

**Failed approaches:**
- **Fable's empty-the-credit bounce rule,** and **the date-equality rule:** as above.
- **The arrival counted as `amount + v_amount` at its date:** zero there, so earlier dates were unguarded.
- **plpgsql `IF` with an inner `CASE ... THEN`:** parse error. Compute into a variable first.
- **`NEW.<column>` in a trigger shared by tables without that column:** fails at runtime. Nest the check by `TG_TABLE_NAME`.
- **Two history rows with chosen times in one INSERT:** refused by recorded order. Use one INSERT per row.

**Accuracy / test results:**

| Check | r3 | r4 |
|---|---|---|
| battery-23 | 216 | 252 |
| races/cash-23.sh | CR1–CR17, 26/26 | CR1–CR19, 29/29 |
| mutations-23.py | 140/140 | 170/170 (first run 166/170; four renamed or wrapped) |
| tests/ci.sh | 49/49 | 49/49 |
| reviews | 3 × not yet | 3 × not yet |

**Open / next:**
- **Ask Ryan whether to start r5.** Six blockers: refund-tree guard, the overpayment split, give-back to an escheated overpayment credit, the reissue amount, no future status times, and the READ COMMITTED pin for arrival rows.
- **Then:** -25 and -26 go to review; the mirror order is -23, -25, -26.
- **Tell Kyle:** ui-concepts' `refunded` status, the `do_not_disconnect` checkbox, and the four law findings.

---
