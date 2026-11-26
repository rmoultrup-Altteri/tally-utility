Folder: `~/code/tally-utility-scenarios`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: scenarios and test strategy (roadmap P2, gate step 2)

**Generated**: 2026-11-25, end of the seventh scenarios session (continued after the gas family).
**Branch**: `main`. `git pull --ff-only` first, and check GBM `HEAD..origin/main` for Kyle's answers (Kyle also posts in the Slack DM, D0B0GRDQYLR; this session had no Slack tool, so the DM was not read).
**Status**: 145 scenarios (SCN-0001 – 0145). The gas cost, zones and reads family (0130 – 0145) is written ahead of its patches (Ryan's go-ahead) and reviewed (round 7, all three reviewers, applied). Five batches of questions for Kyle are drafted as files, none sent.

## Goal

Write the scenarios the C# core must pass, have Kyle check the dollar figures, and choose how they become tests. Runs beside schema parity (Ryan, 2026-10-29). This stream writes no schema: no `sql/` file, no patch tests.

## Where things are

- `scenarios/README.md`: shape, conventions, file index, **next free ID SCN-0146**.
- `scenarios/cast.md`: Pecan Flat, Bluebonnet (five tax rows now: the hospital district is gone, transit 0.25%), Gulf Plains (billing days now stated: read the 1st, billed the 5th, due 20 days later), Fremont / Prairie Line, §5 held money and agencies, **§6 gas cost, zones and reads** (billing days, gas cost figures by billing month, Gulf Plains' rates, Bluebonnet's pressure zones, estimate methods and the cap, meter dials); customers BB-17, BB-18, BB-19, GP-08.
- Families: billing pipeline, cancel-rebill, deposits, backbilling, periods and aging, tenant isolation, date-tracking, cash (0081–0103), tax (0104–0116), unmatched cash and pledges (0117–0129), **gas cost, zones and reads (0130–0145)**.
- Reviews: `scenarios/review/<date>/`; round 6 is `2026-11-25/`; **round 7 is `2026-11-25-gas/`** (brief.md, codex.md, opus.md, fable.md).
- Kyle briefs: batch 3 `application/kyle-brief-2026-11-22-scenario-batch-3.md` (K-14), batch 4 (K-16), batch 5 `…-2026-11-24-…-batch-5.md` (K-18), batch 6 `…-2026-11-25-…-batch-6.md` (K-19), **batch 7 `…-2026-11-25-…-batch-7.md` (K-20, 17 questions)**.

## Completed this session

- [x] `scenarios/unmatched-cash-and-pledges.md`, 13 scenarios after -24 mirrored: held receipts never guessed, split, returned, reported as unclaimed property; aged receipts bar their candidates' cut-off; misposted money back to the receipt; a held check bouncing; one provider transaction; pledges at Gulf Plains (16 TAC §7.460(b)(2)) and at cities; two agencies; lapse; refunds to the agency; no agreement on file; remittance batches.
- [x] Review round 6 (Opus, Fable, Codex) applied, plus the tax second-pass edits reviewed (Codex, Fable, Opus) and fixed.
- [x] Law read 2026-11-25: Property Code §72.101, §72.1017, §76.001, §76.301 (texas.public.law, verified May 26, 2025); Transportation Code §451.404(a), §452.401(a), §460.551(a), §460.552; 16 TAC §7.460(a), (b)(2).
- [x] Tax: transit authority 0.25% (no Texas transit rate is lower), hospital district removed; SCN-0115 BB-13 $202.86; batch 5 item 11 updated; reviewed by Opus.
- [x] Two rulings by Ryan (below), DECISION-LOG; board notes to money (four gaps; the two rulings).
- [x] Batch 6 drafted; roadmap K-19; dashboard's decisions dataset uploaded.
- [x] **`scenarios/gas-cost-zones-and-reads.md`, 16 scenarios, ahead of the rates stream's patches** (Ryan: "start the gas cost, zones and reads scenarios"; DECISION-LOG): the gas cost figure by billing month (issue month), none locked, keyed wrong, a later rebill, the billing-side record, Pecan Flat's minimum; pressure zones confirmed before activation, a factor changing mid-period, a wrong multiplier; a high read re-read, re-read fees, an estimate and its catch-up, Gulf Plains' estimates (card, cap, cut-off), rollover, a meter change, a meter moved.
- [x] Review round 7 (Opus, Fable, Codex) applied: the March pipeline fee; "by cycle" as SCN-0001; the built cap fires at the third estimate; the estimate's base month; dates; what is built (zone and pressure confirmations, the billing guard); R-30's list is a proposal; §7.45's approved-plan and customer-readable conditions.
- [x] Law read: 16 TAC §7.45 (6)(B), (6)(C), (4)(E)(vii), (7)(B)(iv); §7.5519 sets no effective date (GBM's knowledge page says otherwise).
- [x] Board note to rates (seven points); batch 7 drafted; roadmap K-20; dashboard dataset `decisions` v22.

## Waiting on Ryan

- **Send batches 3, 4, 5, 6, then 7**, each pasted from below its "Paste from here". If an older batch 3 draft is in Kyle's DM, delete it first.

## Waiting on Kyle

- K-14, K-16, K-18, K-19, K-20. Not to build until ruled: bank-error returned checks (SCN-0045), the senior's proof details (SCN-0011).

## Not yet done (in order)

1. [ ] Gas family gaps the reviewers named, not yet written: a final bill or two bills for one meter in a billing month; two months billed on one read; Gulf Plains' six-month actual read missed (the Jul/Sep deadline); Gulf Plains' factor not filed; an estimated removal read; an estimate with no history; a city at its estimate cap; a zero or stuck read; a standard-pressure meter wrongly given a factor; a multiplier and a pressure factor on one meter; a zone confirmed wrong. Energy-unit (therm) billing waits for Gulf Plains' tariff to be drafted from a real Railroad Commission tariff. Ryan's question in SCN-0145 (a meter recorded at the wrong address: correction or move) to ask when the rates stream reaches it.
2. [ ] Tax, not yet written: a rise that would pass 2% where a district overlaps (needs a district of its own: east of Main is full at 2%); disannexation; a premise with no city status on the tax axis; a use change partway through a period; franchise fees (after -31). Citation checks open: how annexation moves a transit authority's boundary; whether §321.3025 reaches a crime-control district; Property Code §76.601–.602 (what a city treasurer does with unclaimed property).
3. [ ] Weather normalization; state machines, exception paths, the persona matrix.
4. [ ] Families after their patches mirror: disputes (-25), collections (-26).
5. [ ] One meter across premises with different rules.
6. [ ] The coverage audit against all 135 invariants; then the test strategy (roadmap R-15). Note for it: -24's dates refuse anything after the real today, so these tests need a controlled clock.
7. [ ] Fold in K-14, K-16, K-18, K-19, K-20 when answered.

## Key decisions

| Decision | Who | Why |
|---|---|---|
| A utility cannot go live until it states its held-money service level, retention and a pledge rule ("no protection" allowed); the database's block-when-unknown stays as a safety net | Ryan 2026-11-25 (option 3) | blocking surprises a live utility; silence-as-no-protection cuts off a customer whose money sits unidentified |
| A pledge carries the day the utility received it, entered by the operator, beside the keying stamp | Ryan 2026-11-25 | §7.460(b)(2) turns on the billing period the pledge is received in; a late keying moved it |
| Unidentified money a city holds, $100 or less: presumed abandoned after 3 years, then to the city's own treasurer by Nov 1 | statute (Prop. Code §72.101, §76.001, §76.301) | settled by source, recorded in SCN-0119 |
| Transit authority 0.25%, no hospital district | statute (Transp. Code) | 0.125% is no Texas transit rate |
| Gas cost, zones and reads written ahead of their patches | Ryan 2026-11-25 | the patches are unclaimed; the scenarios become their specification |
| A bill's billing month is its issue month (all three cast utilities); a factor change states its method like a rate change | this stream's reading, Open with Kyle (K-20) | Kyle's "per billing month" doesn't define the month; "never split" covers the gas cost only |

## Failed approaches (don't repeat)

- **Writing "a city's silent tariff blocks the cut-off" as settled**: limit L2 covers only the missing statutory row; the city case was a decision nobody had made (now settled by Ryan's go-live rule).
- **Stating a contract term and its own Open as both settled** (SCN-0124's 45 days): put the reading in the Open, mark the expected behaviour provisional.
- **Skipping penalties that posted before money was identified**: a receipt resolved after the penalty run means post-then-reverse.
- **Calling a design proposal Kyle's ruling** (R-30's skip-reason buckets) and **calling built records "not built"** (zone and pressure confirmations): read the ruling's own caveats and grep tu.sql before every Status line.
- **A wait loop grepping "error"** in Codex's log: it matched Codex's own work output. Wait on the report file and the process.
- From earlier sessions: §321.102(h) misread; an undated cast place; a statute cited without its scope; the matched pair of lines; reusing a cast customer unchecked.

## Warnings

- Other streams rule on the same topics in parallel. Before recording a ruling, pull and grep the DECISION-LOG and the board.
- Check own sources before telling Ryan a source is silent (`law/`, `application/places-sources/`, `application/texas-only-audit-2026-09-28/`, the inventories).
- Core or database: before writing "refused", find the guard. This round every refusal was checked against `sql/v5.4.2-24-*.sql` by three reviewers.
- Reviewers: Opus and Fable as background agents told to write the report to a scratchpad file. Codex: `PATH=~/.nvm/versions/node/v24.15.0/bin:$PATH codex exec -s workspace-write -C <repo> "<prompt>" < /dev/null > log 2>&1`, with the prompt pointing at a brief file.
- texas.public.law works (its copies are verified May 2025; flag that). capitol.texas.gov returns only navigation. eCode360 needs the Chrome extension.
- Slack: Kyle's DM is Slack Connect: draft only, Ryan sends; briefs live as files. Don't edit other streams' handoffs.

## Resume

1. `git pull --ff-only`; GBM fetch; read the board's notes for this stream.
2. Read the DM (D0B0GRDQYLR) if a Slack tool is available: if Kyle answered a batch, fold it in first.
3. Ask Ryan which next: the gas family's gaps (item 1), weather normalization and state machines (item 3), or the tax items (item 2).
