Folder: `~/code/tally-utility-scenarios`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: scenarios and test strategy (roadmap P2, gate step 2)

**Generated**: 2026-11-05, end of the third scenarios session.
**Branch**: `main`. `git pull --ff-only` first, and check GBM `HEAD..origin/main` for Kyle's answers (he also posts in his Slack DM, D0B0GRDQYLR). Kyle answered batch 2 the same day it was sent; check early.
**Status**: 79 scenarios (SCN-0001 – 0079) in eight families. Kyle's batch 2 (20 answers, Nov 5) folded in. Two new families written today (tenant isolation, date-tracking and immutability), reviewed by Opus and Fable, findings applied; **Codex has not reviewed them** (usage limit, reset 5:18 PM Nov 5). Two decisions wait on Ryan.

## Goal

Write the scenarios the C# core must pass, have Kyle check the dollar figures, and choose how they become tests. Runs beside schema parity (Ryan, 2026-10-29). This stream writes no schema: no `sql/` file, no patch tests.

## Where things are

- `scenarios/README.md`: shape, conventions, file index, **next free ID SCN-0080**.
- `scenarios/cast.md`: Pecan Flat (Stinnett's tariff), Bluebonnet (Brenham's; live Jan 1, 2026), Gulf Plains (investor-owned, Texas binds; live Jan 15, 2026), Fremont / Prairie Line. Penalty rows updated to Kyle's batch 2.
- Families: billing pipeline (0001, 0048, 0053–0055), cancel-rebill (0002–0006, 0027, 0028, 0030, 0033), deposits (0007–0012, 0029, 0032, 0042–0047, 0056, 0057), backbilling (0013–0019, 0031, 0035–0041, 0058, 0059), periods and aging (0020–0026, 0034, 0049–0052), **tenant isolation (0060–0068)**, **date-tracking and immutability (0069–0079)**.
- Reviews: `scenarios/review/2026-11-02/`, `2026-11-04/`, `2026-11-05/` (round 3: brief, opus.md, fable.md; no codex.md).

## Waiting on Ryan (start here next session)

1. **Roadmap R-23: who sets up and restores a utility's supervisors, now that Tally staff are read-only** (SCN-0062, Opus r3 finding 1). Today a platform administrator binds logins and switches users at any utility; the 11-05 ruling makes a Tally employee acting as themselves read-only, and impersonation can't restore a supervisor who is the one switched off. Recommended: **option 1**, user administration (binding, switching on or off, a utility's users only) is the one exception, recorded with the Tally employee and a required reason, visible to the utility. Option 2: the last active supervisor can't switch itself off and provisioning runs as a service user. Raised at session end, not answered.
2. **Codex for round 3:** retry after the reset (same brief, `scenarios/review/2026-11-05/brief.md`; it now covers SCN-0060 – 0079) or waive. Raised, not answered.
3. Then, one at a time: R-24 (is a refused attempt, or a Tally employee's plain reading, recorded for the utility to see; SCN-0061); Kyle's flags for Ryan from batch 2: (a) the dispute rule's start and end (no penalty while a bill's dispute is open; Kyle proposes raised before the due date, lasting until resolved); (b) confirm Pecan Flat's penalty base is the full amount owed excluding earlier penalties (SCN-0053, cast); (c) SCN-0033's Open: whether the corrected bill shows the lower figure, or the full figure with the extra marked as moved.

## Waiting on Kyle

- **K-13 (20 questions): answered Nov 5**, recorded in GBM (wiki-ingestion-pending Section BY, logged by this stream), the DECISION-LOG and each scenario's Status line.
- **K-14, the third batch: not yet sent.** `grep -n "Open (Kyle" scenarios/*.md`: whether a utility-error rebill's hidden extra goes on the next bill for every upward correction (SCN-0027 a, 0028, 0033, 0069); whether answer 12's month-by-month pre-go-live refund applies where §7.45 binds (SCN-0039); plus his own flag 6 (recheck batch 2's figures) and the new dollar figures of SCN-0069, 0070, 0078 and the penalty re-basing ($6.59 on the reference bill). Not to build until ruled: bank-error returned checks (SCN-0045) and the senior's proof details (SCN-0011), his flag 2. Draft for Ryan to send (Slack drafts only), one line per question.

## Not yet done (in order)

1. [ ] Ryan's R-23; Codex round 3 or waiver; then R-24 and Kyle's flags, one per message.
2. [ ] Draft K-14 for Kyle.
3. [ ] Weather normalization (likely needs Kyle on how city systems adjust).
4. [ ] State machines, exception paths, the persona matrix.
5. [ ] Families after their patches mirror: cash (-23 mirrored; includes answer 7's credit-and-rebill on a paid bill), disputes (-25), collections (-26; cast question 5), the rates stream's tax, gas cost, zones and reads.
6. [ ] Deferred gap: one meter across premises with different rules.
7. [ ] The coverage audit against all 135 invariants; then the test strategy (roadmap R-15).

## Decisions this session (DECISION-LOG 2026-11-05, scenarios)

- R-20: a backbill for a customer outside Texas's protected class is refused until the utility's tariff states a rule.
- R-21: Tally employees may impersonate a utility's users on Tally's own decision; the database records each session (required reason) and marks every change; impersonation has the user's permissions only; a Tally employee's own access is read-only (not built; unassigned on the board).
- R-12: every one of the 273 single-column foreign keys between tenant tables becomes a two-column key with `tenant_id` (counted on `tally` today; the fix runs last).
- R-22: a billing run reads every bill at one recorded instant, fixed at its start; a correction run likewise, unless the operator elects a replay at the original's instant (dated correction appended after review round 3).
- Kyle's batch 2 folded in (one entry).

## Board notes left this session

- Unassigned: Tally's access to a utility's records (impersonation record, read-only platform admin).
- The end-of-schema link fix note now carries R-12 and the 273 count.
- scenarios → money and scenarios → rates: Kyle's batch 2 answers that touch their tables.

## Warnings

- **Check the mirrored schema before saying something is built** (round 3's most common finding, again): SCN-0067's run outcomes, SCN-0066's failed-import retry, SCN-0076's priced-at date (period end, not issue date), SCN-0071's rebill (always on a correction run). Use the live database read-only (`docker exec tally-pg psql -U tally -d tally -Atc "select …"`).
- **Isolation is not "sees nothing"**: a session with no user or a switched-off user still reads the shared platform tables; a write it cannot reach changes nothing rather than raising.
- **A city system never reads the Texas rule's terms** for backbilling; its own tariff record or Kyle's six-month default.
- Scenarios describe rules and rulings, not tables; mark the stream's own readings as readings, with an Open; keep facts consistent with the cast.
- Reviewers: Codex via `PATH=~/.nvm/versions/node/v24.15.0/bin:$PATH codex exec -s workspace-write -C <repo> -o <file> "<prompt>" < /dev/null` (about 4 minutes; check its log for the usage limit); Opus and Fable as background agents told to SendMessage the report in parts under 3 KB.
- Slack: Kyle's DM is Slack Connect: draft only (`slack_send_message_draft`, D0B0GRDQYLR); Ryan sends.
- Two postgres-mcp containers were running at session end (not this stream's; not touched).
- Don't edit the money or rates streams' handoffs; leave notes on the board.
