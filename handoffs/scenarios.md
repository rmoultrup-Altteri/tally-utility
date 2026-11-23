Folder: `~/code/tally-utility-scenarios`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: scenarios and test strategy (roadmap P2, gate step 2)

**Generated**: 2026-11-22 evening, end of the fifth scenarios session.
**Branch**: `main`. `git pull --ff-only` first, and check GBM `HEAD..origin/main` for Kyle's answers (Kyle also posts in the Slack DM, D0B0GRDQYLR).
**Status**: 103 scenarios (SCN-0001 – 0103). The cash family is written and reviewed twice. Two batches of questions for Kyle are drafted, neither sent.

## Goal

Write the scenarios the C# core must pass, have Kyle check the dollar figures, and choose how they become tests. Runs beside schema parity (Ryan, 2026-10-29). This stream writes no schema: no `sql/` file, no patch tests.

## Where things are

- `scenarios/README.md`: shape, conventions, file index, **next free ID SCN-0104**.
- `scenarios/cast.md`: Pecan Flat (Stinnett's tariff), Bluebonnet (Brenham's), Gulf Plains (investor-owned, Texas binds), Fremont / Prairie Line. Customers GP-06, BB-09 and PL-02 are cash.md's own.
- Families: billing pipeline (0001, 0048, 0053–0055), cancel-rebill (0002–0006, 0027, 0028, 0030, 0033), deposits (0007–0012, 0029, 0032, 0042–0047, 0056, 0057), backbilling (0013–0019, 0031, 0035–0041, 0058, 0059), periods and aging (0020–0026, 0034, 0049–0052), tenant isolation (0060–0068, 0080), date-tracking (0069–0079), **cash (0081–0103)**.
- Reviews: `scenarios/review/<date>/`; round 4 is `2026-11-22/` (codex.md, opus-fable-summary.md, opus-fable-r2-summary.md).

## Completed this session

- [x] Ryan's five rulings recorded and written in (Key decisions).
- [x] `scenarios/cash.md`, 23 scenarios; review round 4 (Opus, Fable, Codex) applied (426b9f2); second pass (Opus, Fable, changed and new scenarios only) applied (eb75e70). **The second pass's own edits have not been reviewed.**
- [x] K-14 (batch 3) drafted in Slack; K-16 (batch 4) drafted in `application/kyle-brief-2026-11-22-scenario-batch-4.md`. Roadmap decisions uploaded to the dashboard.

## Waiting on Ryan

- **Send K-14**, the unsent draft in Kyle's DM (not sent when checked, 2026-11-22 evening). One draft per channel and no tool edits it, so **Ryan edits item 6 and its figures by hand first**:
  > 6. (SCN-0033) The corrected bill is charged at the full true figure ($79.06), shown with "of which $13.23 is due with your next bill", so $65.83 is due now. The next bill shows the $13.23 without charging it again. This needs a record that part of a bill is due later, so your "no schema change" no longer holds. Any objection? The next bill prints the $13.23 but holds no line for it; money for it pays the November charges, so it can't be paid twice. Your answer said a line.

  In its figure check: "carry-over ($13.23 moved" becomes "later-due amount ($13.23"; add $85.65 on December 4 (of which $13.23 isn't due yet) and $13.23 for SCN-0089 (b).
- **Then send K-16** (paste below its "Paste from here"). Questions 18–22 assume Kyle accepts item 6; if not, rewrite them.
- Offered, not asked for: check whether Stinnett has a written dispute rule (its article 12.02 did not load).

## Waiting on Kyle

- K-14 and K-16, above. Not to build until ruled: bank-error returned checks (SCN-0045), the senior's proof details (SCN-0011).

## Not yet done (in order)

1. [ ] **Tax by location** (recommended next, not yet chosen by Ryan): -30 mirrored 2026-11-22 (tax rows by place, taxability, exemptions per service, places as known; AC-47), so its scenarios can be written. Then the rates stream's gas cost, zones and reads.
2. [ ] Weather normalization (likely needs Kyle on how city systems adjust).
3. [ ] State machines, exception paths, the persona matrix.
4. [ ] Families after their patches mirror: unmatched cash and pledges (-24), disputes (-25), collections (-26; cast question 5).
5. [ ] One meter across premises with different rules.
6. [ ] The coverage audit against all 135 invariants; then the test strategy (roadmap R-15).
7. [ ] Fold in K-14 and K-16 when answered.

## Key decisions (DECISION-LOG 2026-11-22)

| Decision | Why |
|---|---|
| Dispute conflict: the scenarios version stands (a city's own rule wins; disputed amount only; earlier of resolution and 60 days) | recorded by money too |
| Day 60 unresolved: the disputed amount takes the next bill's due date | no penalty on a date never told |
| Full-amount penalty base: once or every month is the city's setting, no default; Pecan Flat monthly | the tariff is silent |
| Corrected bill: one charge at the full true figure, part due later (replaces a matched pair of lines) | the pair read open after payment and would be paid twice |
| By rule, after the re-review: the record is **per line**; the next bill prints the amount and holds no line; "not yet due" is its own aging row; netting a credit against a bounce is recorded before a refund, not at the bounce (Kyle asked) | one figure per bill gives $1.25 where Ryan's base gives $1.31; netting at the bounce would leave the per-state escheat rule nothing to act on |

## With the money stream (board notes)

The per-line "due later" record; a penalty paid before any bill line exists (0092); one receipt split between deposit and bill (0091 c); no unclaimed-property clock on an unapproved overpayment (0082); how a negative line nets; no ledger row for money sent to the state (0088 c); no basis for a customer's direction (0091 d); a take-back short of ended (0101 b).

## Failed approaches (don't repeat)

- **Matched pair of lines for the hidden extra** → the schema's open amount counts positive lines only and a ledger row naming a charge is its reversal → one charge, part due later.
- **A shown amount written as a bill "line"** → any positive line of an issued bill takes money, so the same $13.23 could be paid on two bills → say printed, not a line.
- **Reusing a cast customer without checking its other scenarios** → contradictions (BB-02, GP-01; a final bill left out) → grep the ID first, or invent a customer.
- **"Service ended" to explain a quiet account** → it brings a final bill and a deposit into the figures.
- **An on-time test with both dates before the due date** → it passes under either rule → put the customer's date and the settlement on either side.
- **Inserting a DECISION-LOG entry without pulling** → money had put one on top → `git pull`, read it, then insert.

## Warnings

- **Other streams rule on the same topics in parallel.** Before recording a ruling, pull and grep the DECISION-LOG and the board for it.
- **Check own sources before telling Ryan a source is silent**: grep `law/` and the inventories, read the page.
- **Core or database:** before writing "refused", find the guard (`docker exec tally-pg psql -U tally -d tally -Atc "select …"`, read-only). Choosing bills and lines is the core's.
- A city system never reads the Texas rule's terms for backbilling; its own tariff record or Kyle's six-month default.
- Isolation is not "sees nothing": a session with no user still reads the shared platform tables.
- Scenarios describe rules, not tables; mark readings, with an Open; keep facts consistent with the cast.
- Reviewers: Opus and Fable as background agents told to **write the report to a scratchpad file** and return titles only (reports truncate). Codex: `PATH=~/.nvm/versions/node/v24.15.0/bin:$PATH codex exec -s workspace-write -C <repo> "<prompt>" < /dev/null > log 2>&1` (no `-o` when the prompt tells it to write a file).
- eCode360 blocks curl and WebFetch; use the Chrome extension, reject non-essential cookies, close the tab.
- Slack: Kyle's DM is Slack Connect: draft only; Ryan sends. Don't edit other streams' handoffs; leave notes on the board.

## Resume

1. `git pull --ff-only`; GBM fetch; read the board's notes for this stream. Expected: at `HEAD`, only other streams' commits.
2. Read the DM (D0B0GRDQYLR): if K-14 is sent, remind Ryan of K-16; if Kyle answered, fold it in first.
3. Ask Ryan: tax by location next?
