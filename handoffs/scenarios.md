Folder: `~/code/tally-utility-scenarios`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: scenarios and test strategy (roadmap P2, gate step 2)

**Generated**: 2026-11-24, end of the sixth scenarios session.
**Branch**: `main`. `git pull --ff-only` first, and check GBM `HEAD..origin/main` for Kyle's answers (Kyle also posts in the Slack DM, D0B0GRDQYLR).
**Status**: 116 scenarios (SCN-0001 – 0116). The tax-by-location family is written and reviewed twice. Three batches of questions for Kyle are drafted as files, none sent.

## Goal

Write the scenarios the C# core must pass, have Kyle check the dollar figures, and choose how they become tests. Runs beside schema parity (Ryan, 2026-10-29). This stream writes no schema: no `sql/` file, no patch tests.

## Where things are

- `scenarios/README.md`: shape, conventions, file index, **next free ID SCN-0117**.
- `scenarios/cast.md`: Pecan Flat (Stinnett's tariff; city sales tax 1.5% from 1987, not on homes), Bluebonnet (Brenham's; the six tax rows in stack order), Gulf Plains (investor-owned, Texas binds), Fremont / Prairie Line (a tax on a tax).
- Families: billing pipeline (0001, 0048, 0053–0055), cancel-rebill (0002–0006, 0027, 0028, 0030, 0033), deposits (0007–0012, 0029, 0032, 0042–0047, 0056, 0057), backbilling (0013–0019, 0031, 0035–0041, 0058, 0059), periods and aging (0020–0026, 0034, 0049–0052), tenant isolation (0060–0068, 0080), date-tracking (0069–0079), cash (0081–0103), **tax (0104–0116)**.
- Reviews: `scenarios/review/<date>/`; round 5 is `2026-11-24/` (codex.md, opus.md, fable.md, opus-second-pass.md, fable-second-pass.md).
- Kyle briefs: `application/kyle-brief-2026-11-22-scenario-batch-3.md` (K-14), `…-batch-4.md` (K-16), `application/kyle-brief-2026-11-24-scenario-batch-5.md` (K-18).

## Completed this session

- [x] `scenarios/tax.md`, 13 scenarios, after -30 mirrored: the stack, residential gas (city and crime-control district only), exemptions with $0.00 lines, annexation's two dates, published rate changes and the gaps report, a wrong jurisdiction, Pecan Flat's business-only tax, a tax on a tax, refused tax rows, the liability, overlapping places, a line outside the base.
- [x] Review round 5 (Opus, Fable, Codex) applied; second pass (Opus, Fable) applied (177b9bf). **The second pass's own edits are not reviewed.**
- [x] Law read 2026-11-24: Tax Code §151.051(b), §321.101(f), §321.102(e)–(h), §321.3025; 34 TAC §3.287, §3.295 (incl. (j), the pipeline safety fee), §3.334.
- [x] Earlier scenarios corrected: SCN-0055 (c) $447.32 (state and county tax outside the city); SCN-0054 (a) $66.99 (the district from Jan 2027); `periods-and-aging.md` BB-01's Jan 15, 2027 figure marked.
- [x] Batch 3 rebuilt as a file from the 2026-11-22 Slack draft (the DM may hold it, or money's K-17 may have displaced it), with item 6 and the figure check edited as asked. Batch 5 drafted. Roadmap: K-14 points to the file, K-18 added, dashboard uploaded.
- [x] Board notes: scenarios → rates (six gaps: missed district not reported, residential reach and stack order unchecked, a tax row with no user, axes that disagree, use with no dated history); scenarios → money (what tax lines record; the liability's periods).

## Waiting on Ryan

- **Send batch 3, then 4, then 5**, each pasted from below its "Paste from here". If an older batch 3 draft is in Kyle's DM, delete it first. Batch 4's questions 18–22 assume Kyle accepts batch 3's item 6.
- Two leaked postgres-mcp containers were running on 2026-11-24 (`docker ps --filter ancestor=crystaldba/postgres-mcp`); left alone.
- Offered, not asked for: whether Stinnett has a written dispute rule (its article 12.02 did not load).

## Waiting on Kyle

- K-14, K-16, K-18. Not to build until ruled: bank-error returned checks (SCN-0045), the senior's proof details (SCN-0011).

## Not yet done (in order)

1. [ ] The rates stream's gas cost, zones and reads (recommended next; not yet chosen by Ryan).
2. [ ] Tax, not yet written: a rise that would pass 2% where a district overlaps; disannexation; a premise with no city status on the tax axis (refuse, or state only? Ryan or rates); a use change partway through a period; franchise fees (after -31).
3. [ ] Weather normalization (likely needs Kyle on how city systems adjust).
4. [ ] State machines, exception paths, the persona matrix.
5. [ ] Families after their patches mirror: unmatched cash and pledges (-24), disputes (-25), collections (-26).
6. [ ] One meter across premises with different rules.
7. [ ] The coverage audit against all 135 invariants; then the test strategy (roadmap R-15).
8. [ ] Fold in K-14, K-16, K-18 when answered.

## Key decisions

No rulings from Ryan this session. Settled by rule or statute (recorded in `tax.md`, not the DECISION-LOG):

| Decision | Why |
|---|---|
| Every local tax counts toward the 2% limit, transit included; the east-of-Main district and transit authority are 0.125% each and end Sep 30, 2027 | §321.101(f); §321.102(h) only exempts transit from the automatic reduction. Leaves room for SCN-0109's city rise |
| Residential gas: only the city's tax and a fire- or crime-control district's | §151.317, §321.105, §321.201(a), §321.1055 |
| The pipeline safety fee is outside every tax base | 34 TAC §3.295(j), names municipally owned systems |
| Tax charged early after annexation: only the city's part is the city's revenue (§321.3025); crediting it is Kyle's call | the statute names the municipality only |
| A business's late penalty carries every tax its gas carries | Kyle 11-05 answer 3 ("taxed like the gas"); confirmed in K-18 |

## Failed approaches (don't repeat)

- **Reading §321.102(h) as "transit is outside the 2% limit"** → it only keeps transit from being the rate cut back → check every stack's local total ≤ 2% at each location, on every date a scenario uses.
- **Adding a cast place with no dates** → it reached every bill, including ones written before it (BB-03's exempt lines) → give new places dates and say which side of a boundary each premise is.
- **Citing a statute from the inventory without its scope** (§121.211(g) is investor-owned and cooperative only) → read the scope before citing for a city system.
- From earlier sessions: the matched pair of lines for the hidden extra; a shown amount as a "line"; reusing a cast customer unchecked; "service ended" for a quiet account; an on-time test that can't fail; a DECISION-LOG insert without pulling.

## Warnings

- **Other streams rule on the same topics in parallel.** Before recording a ruling, pull and grep the DECISION-LOG and the board for it.
- **Check own sources before telling Ryan a source is silent**: grep `law/`, `application/places-sources/`, the inventories, and read the page.
- **Core or database:** before writing "refused", find the guard (read-only psql on tally-pg, or grep the patch). Choosing bills and lines is the core's.
- Scenarios describe rules, not tables; mark readings, with an Open; keep facts consistent with the cast.
- Reviewers: Opus and Fable as background agents told to **write the report to a scratchpad file** (reports truncate). Codex: `PATH=~/.nvm/versions/node/v24.15.0/bin:$PATH codex exec -s workspace-write -C <repo> "<prompt>" < /dev/null > log 2>&1`; it can't reach the docker socket, so it reviews from SQL. Retry once on "model at capacity".
- capitol.texas.gov returns only navigation to fetchers; texas.public.law works (verified-as-of date on each page). eCode360 blocks fetchers; use the Chrome extension.
- Slack: Kyle's DM is Slack Connect: draft only; Ryan sends. One draft per channel, and another stream's draft can displace ours, so briefs now live as files. Don't edit other streams' handoffs; leave notes on the board.

## Resume

1. `git pull --ff-only`; GBM fetch; read the board's notes for this stream. Expected: at `HEAD`, only other streams' commits.
2. Read the DM (D0B0GRDQYLR): if Kyle answered a batch, fold it in first.
3. Ask Ryan: the rates stream's gas cost, zones and reads next? (Optionally first a third review of the tax second-pass edits.)
