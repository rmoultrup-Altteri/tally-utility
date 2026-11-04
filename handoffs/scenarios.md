Folder: `~/code/tally-utility-scenarios`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: scenarios and test strategy (roadmap P2, gate step 2)

**Generated**: 2026-11-04, end of the second scenarios session.
**Branch**: `main`. `git pull --ff-only` first, and check GBM `HEAD..origin/main` for Kyle's answers (he also posts in his Slack DM, D0B0GRDQYLR).
**Status**: 59 scenarios (SCN-0001 – 0059) in six families. Kyle's 17 answers (Nov 3) folded in; the 27 written this session (0033 – 0059) reviewed once by Opus, Fable and Codex, findings applied. One decision waits on Ryan; a second batch of Kyle questions is collecting, not yet sent.

## Goal

Write the scenarios the C# core must pass, have Kyle check the dollar figures, and choose how they become tests. Runs beside schema parity (Ryan, 2026-10-29). This stream writes no schema: no `sql/` file, no patch tests.

## Where things are

- `scenarios/README.md`: shape, conventions, file index, **next free ID SCN-0060**.
- `scenarios/cast.md`: Pecan Flat (Stinnett's tariff), Bluebonnet (Brenham's; **live on the platform Jan 1, 2026**, invented), Gulf Plains (investor-owned, Texas binds; live Jan 15, 2026; tariff not drafted), Fremont / Prairie Line. Tariff questions 1–4, 6, 7 answered; question 5 (combined city bill) waits for collections.
- Families: `billing-pipeline-and-charge-composition.md` (0001, 0048, 0053–0055), `cancel-rebill.md` (0002–0006, 0027, 0028, 0030, 0033), `deposits.md` (0007–0012, 0029, 0032, 0042–0047, 0056, 0057), `backbilling.md` (0013–0019, 0031, 0035–0041, 0058, 0059), `periods-and-aging.md` (0020–0026, 0034, 0049–0052).
- Reviews: `scenarios/review/2026-11-02/` (round 1), `scenarios/review/2026-11-04/` (round 2: brief, codex.md, opus.md, fable.md; Opus and Fable condensed from their messages).

## Waiting on Ryan (start here next session)

1. **Roadmap R-20: confirm -18's delegation reading.** v5.4.2-18 (mirrored) made the eight unprotected-class Texas backbilling rows delegations: for a large customer outside §7.45's protected class, the law row claims no window, and with no utility tariff record the case is refused (residual R10, "Ryan to confirm"; no DECISION-LOG entry confirms it). The alternative, the older -13 reading, is "uncapped": a utility could bill a large customer back without limit on the platform's say-so. Recommended at session end: confirm (fails toward protection; costs only that a utility with large customers states its rule at onboarding). SCN-0036 is written to the refusal, with an Open (Ryan). If confirmed: DECISION-LOG entry, remove SCN-0036's Open (Ryan), mark R-20 answered; it's the rates stream's table (board note only if something changes for them).

## Waiting on Kyle

- **K-12 (17 questions): answered Nov 3**, recorded in GBM (manifest Section BV), the DECISION-LOG and each scenario's Status line.
- **K-13, the second batch: not yet sent.** `grep -n "Open (Kyle" scenarios/*.md` (14 lines, several with sub-questions). Main ones: whether a penalty is re-assessed or waived when the utility sent a wrong bill, and what Bluebonnet's 10% is charged on (SCN-0033); the returned-check window (0045) and whether a reversed penalty counts (0034); a stopped meter's anchor (0035); a silent city's refund reach and default anchor (0019); limitations law for the unprotected class (0036); keying-error increases where §7.45 binds (0027); per-target override (0006); chapter 182 at city systems (0048); payment order across bills (0058); Pecan Flat penalty on a penalty (0053); county vs state agency (0054); late DOB refund (0011); later check from a pooled deposit credit (0046). Draft it for Ryan to send (Slack drafts only), one line per question, like the Nov 2 message.

## Not yet done (in order)

1. [ ] Ryan's R-20; then draft K-13 for Kyle.
2. [ ] Fix SCN-0026's customer: it writes off BB-02 in Dec 2026 while SCN-0007/0046/0049 keep BB-02 paying into 2027 (each scenario stands alone, but it will confuse Kyle). Give it its own customer.
3. [ ] Remaining families at parity: date-tracking and immutability, weather normalization, tenant isolation.
4. [ ] State machines, exception paths, the persona matrix.
5. [ ] Families after their patches mirror: cash (-23; includes answer 7's credit-and-rebill on a paid bill), disputes (-25), collections (-26; cast question 5), the rates stream's tax, gas cost, zones and reads.
6. [ ] Deferred gap: one meter across premises with different rules (needs city-level rules and an unprotected-class tariff record).
7. [ ] The coverage audit against all 135 invariants; then the test strategy (roadmap R-15).

## Decisions this session (DECISION-LOG 2026-11-04, scenarios)

- Kyle's 17 answers folded into the scenarios (his standing rule: follow the tariff; defaults only where silent).
- Ryan: a gas bill line carries the conversion figures only when billed in an energy unit; units Ccf, Mcf, therm, dekatherm, MMBtu; a multiplier is stored with its raw quantity (R-19; board note to money).

## Board notes left this session

- scenarios → money: Kyle's answers that touch money's tables (payment order, a correction's aging date, courtesy carry-over, one deposit balance topped up, rolling late-payment count for §7.45 (flag 1), left-over credit is a deposit refund, keying-error rebill); and the gas bill-line rule (R-19).
- scenarios → rates: rate-change method stated at entry and the locked monthly gas cost figure; a silent city's backbilling default; the keying-error law row; forfeit-whole at a utility's own limit.

## Warnings

- **Scenarios describe rules and rulings, not tables.** Where something isn't built (a correction's aging date, the backbilling tariff table, late-penalty rules), say so on the Status line; check the mirrored patch before saying a schema behaviour exists (round 2 caught SCN-0024 and 0036 on this).
- **A Texas state rule appears only where it binds.** §7.45 doesn't bind city systems; their policy is their tariff, or Kyle's platform default where it is silent.
- **Mark the stream's own readings** as readings, with an Open; don't present them as rulings (round 2's most common note).
- **Keep facts consistent with the cast** (due dates, go-live dates, which customer is where): round 2 found penalties dated before their bills fell due.
- Invented facts are marked "invented". Verify a reviewer's must-fix against the source before applying it (all of round 2's held up).
- Reviewers: Codex via `PATH=~/.nvm/versions/node/v24.15.0/bin:$PATH codex exec -s workspace-write -C <repo> -o <file> "<prompt>" < /dev/null` (about 4 minutes); Opus and Fable as background agents told to SendMessage the report in parts under 3 KB.
- Slack: Kyle's DM is Slack Connect: draft only (`slack_send_message_draft`, D0B0GRDQYLR); Ryan sends.
- Don't edit the money or rates streams' handoffs; leave notes on the board.
