Folder: `~/code/tally-utility-scenarios`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: scenarios and test strategy (roadmap P2, gate step 2)

**Generated**: 2026-11-07, end of the fourth scenarios session.
**Branch**: `main`. `git pull --ff-only` first, and check GBM `HEAD..origin/main` for Kyle's answers (he also posts in his Slack DM, D0B0GRDQYLR).
**Status**: 80 scenarios (SCN-0001 – 0080) in eight families. Codex's round-3 review done and applied. Ryan settled Tally's access (the hidden Tally User; reads logged by the application) and four dispute questions. **A conflict between two of Ryan's dispute rulings, made the same day in two sessions, must be put to him first** (below).

## Goal

Write the scenarios the C# core must pass, have Kyle check the dollar figures, and choose how they become tests. Runs beside schema parity (Ryan, 2026-10-29). This stream writes no schema: no `sql/` file, no patch tests.

## Where things are

- `scenarios/README.md`: shape, conventions, file index, **next free ID SCN-0081**.
- `scenarios/cast.md`: Pecan Flat (Stinnett's tariff), Bluebonnet (Brenham's; live Jan 1, 2026; now with a "Bill disputes" row from Brenham's rules of service), Gulf Plains (investor-owned, Texas binds), Fremont / Prairie Line.
- Families: billing pipeline (0001, 0048, 0053–0055), cancel-rebill (0002–0006, 0027, 0028, 0030, 0033), deposits (0007–0012, 0029, 0032, 0042–0047, 0056, 0057), backbilling (0013–0019, 0031, 0035–0041, 0058, 0059), periods and aging (0020–0026, 0034, 0049–0052), tenant isolation (0060–0068, **0080 the Tally User**), date-tracking and immutability (0069–0079).
- Reviews: `scenarios/review/2026-11-02/`, `2026-11-04/`, `2026-11-05/` (round 3 now has codex.md).

## Waiting on Ryan (start here next session)

1. **Two dispute rulings disagree; ask Ryan which stands, before anything else on disputes.** Both 2026-11-07, both in the DECISION-LOG:
   - *This stream's session* (four entries, "(scenarios)"): a city's own dispute rule wins (Bluebonnet's rule: the disputed bill should still be paid, so a penalty posts); only a city with no rule gets a platform default; the default counts a dispute raised before the due date and protects **the disputed amount only** until the earlier of resolution and **60 days after issue**.
   - *The money session, about an hour later* ("(money, -25 r1 review)", AC-46, -25 r2 plan item 9, board note money → scenarios): no late penalty while a dispute is open is a **platform rule for every customer**, covering **the whole bill**, from receipt **until resolution or withdrawal** (no 60-day end).
   - They differ on three points: whether a city's own rule overrides it, whole bill or disputed amount, and whether protection ends at 60 days. The money session's ruling was answered without the scenarios rulings in front of it (it was asked before they were recorded). Lay out both side by side in plain words and ask which he means; record a dated correction under whichever entry yields, update AC-46 or SCN-0033 to match, and leave a board note for money (-25 r2 depends on it). Don't edit money's files beyond what the board's rules allow; ask money via the board if AC-46 needs changing.
2. **Then the pending question (asked at session end, unanswered; Ryan will answer next session):** when the default's protection ends with the dispute unresolved (day 60), is the disputed amount penalized at once, or moved to the next bill with that bill's due date (recommended; it mirrors Kyle's answer for the extra a billing error hid), or never penalized for that bill? Example: BB-01's November bill issued Nov 16, due Dec 1, $13.23 disputed on Nov 25 and unpaid; protection ends Jan 15. Moot if Ryan picks the money ruling (no 60-day end).
3. Still open on the default: which customer classes it reaches (Texas protects residential and small commercial only; Kyle named none).
4. Kyle's flags for Ryan from batch 2: (b) confirm Pecan Flat's penalty base is the full amount owed excluding earlier penalties (SCN-0053, cast); (c) SCN-0033's Open: whether the corrected bill shows the lower figure ($65.83), or the full figure ($79.06) with the $13.23 marked as moved.
5. Offered, not asked for: check whether Stinnett (Pecan Flat's model) has a written dispute rule. Check its rules of service and billing page, not only the rate PDFs (memory: check own sources before claiming absence).

## Waiting on Kyle

- **K-14, the third batch: not yet sent.** `grep -n "Open (Kyle" scenarios/*.md`: whether a utility-error rebill's hidden extra goes on the next bill for every upward correction (SCN-0027 a, 0028, 0033, 0069); whether answer 12's month-by-month pre-go-live refund applies where §7.45 binds (SCN-0039); his own flag 6 (recheck batch 2's figures); the new dollar figures of SCN-0069, 0070, 0078 and the penalty re-basing ($6.59 on the reference bill); and, **once item 1 above is settled**, how his answer 1 (no penalty while disputed) was applied. Not to build until ruled: bank-error returned checks (SCN-0045) and the senior's proof details (SCN-0011), his flag 2. Draft for Ryan to send (Slack drafts only), one line per question.

## Not yet done (in order)

1. [ ] The dispute conflict, then the pending dispute questions and Kyle's flags (b), (c), one per message.
2. [ ] Draft K-14 for Kyle.
3. [ ] Weather normalization (likely needs Kyle on how city systems adjust).
4. [ ] State machines, exception paths, the persona matrix.
5. [ ] Families after their patches mirror: cash (-23 mirrored), disputes (-25, after item 1), collections (-26; cast question 5), the rates stream's tax, gas cost, zones and reads.
6. [ ] Deferred gap: one meter across premises with different rules.
7. [ ] The coverage audit against all 135 invariants; then the test strategy (roadmap R-15).

## Decisions this session (DECISION-LOG 2026-11-07, scenarios)

- R-27 (renumbered from R-23; money had used R-23/R-24): every utility gets a hidden Tally User, created at setup, with no login, reachable only through an impersonation session with a required reason; hidden from the user list but never from the change history; the utility can't change it; it isn't counted as utility staff. Correction bullet under 11-05: "Tally staff read-only" was the stream's proposal, not Ryan's rule.
- R-28 (from R-24): Tally's reads are logged by the application (who, utility, record, when) and shown to the utility; refused attempts go to operational logs.
- Disputes: the silent-city default (before the due date; until resolved or 60 days after issue); its correction (Brenham does have a written rule); a city's rule wins over Kyle's answer 1; the default protects the disputed amount only (whole bill when none recorded). **See item 1: the money session's later ruling conflicts.**
- Codex round 3 (6 findings) settled by rule: SCN-0061, 0065, 0066, 0071, 0077, 0078, 0079.

## Board notes left this session

- Unassigned: Tally's access now describes the Tally User design.
- scenarios → money (four notes, for -25): the silent-city default, its correction, city rule wins, disputed amount only.

## Warnings

- **Check own sources before telling Ryan a source is silent.** This session told Ryan Brenham had no dispute rule; it was already in `law/dispute/examples/dispute_tariff.brenham.yaml` and the wave-3 inventory. Grep `law/` and the inventories first; read the page, not a search summary.
- **Another stream may rule on the same question in parallel.** Before recording a dispute or penalty ruling, grep the DECISION-LOG and the board's notes for the same topic from today.
- **Check the mirrored schema before saying something is built**: read-only on the live database (`docker exec tally-pg psql -U tally -d tally -Atc "select …"`).
- **Isolation is not "sees nothing"**: a session with no user or a switched-off user still reads the shared platform tables; a write it cannot reach changes nothing rather than raising.
- **A city system never reads the Texas rule's terms** for backbilling; its own tariff record or Kyle's six-month default.
- Scenarios describe rules and rulings, not tables; mark the stream's own readings as readings, with an Open; keep facts consistent with the cast.
- Reviewers: Codex via `PATH=~/.nvm/versions/node/v24.15.0/bin:$PATH codex exec -s workspace-write -C <repo> "<prompt>" < /dev/null > log 2>&1` (no `timeout` on macOS; don't pass `-o` when the prompt tells Codex to write the report file, or `-o` overwrites it). Opus and Fable as background agents told to SendMessage the report in parts under 3 KB.
- eCode360 blocks curl and WebFetch (Cloudflare); use the Chrome extension, reject non-essential cookies, close the tab.
- Slack: Kyle's DM is Slack Connect: draft only (`slack_send_message_draft`, D0B0GRDQYLR); Ryan sends.
- Don't edit the money or rates streams' handoffs; leave notes on the board.
