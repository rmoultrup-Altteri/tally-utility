Folder: `~/code/tally-utility-scenarios`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: scenarios and test strategy (roadmap P2, gate step 2)

**Generated**: 2026-11-02, end of the first scenarios session.
**Branch**: `main`. `git pull --ff-only` first, and check GBM `HEAD..origin/main` for Kyle's answers.
**Status**: 32 scenarios drafted (SCN-0001 – 0032) in six families, reviewed once by all three reviewers (figures all correct; must-fix rule errors applied). 17 questions sent to Kyle on Slack, Nov 2. One schema decision is waiting for Ryan.

## Goal

Write the scenarios the C# core must pass, have Kyle check the dollar figures, and choose how they become tests. Runs beside schema parity (Ryan, 2026-10-29). This stream writes no schema: no `sql/` file, no patch tests.

## Where things are

- `scenarios/README.md`: the shape of one scenario, the conventions, the file index, **next free ID SCN-0033**.
- `scenarios/cast.md`: the invented utilities on real small-city tariffs (Pecan Flat on Stinnett's, Bluebonnet on Brenham's), Gulf Plains (investor-owned, Texas rule binds; tariff not drafted, rates invented per scenario), the State of Fremont with Prairie Line Gas (first law row: deposit interest), the customers, and the tariff questions. Research: `scenarios/cast-sources/`.
- Family files: `billing-pipeline-and-charge-composition.md` (0001), `cancel-rebill.md` (0002–0006, 0027, 0028, 0030), `deposits.md` (0007–0012, 0029, 0032), `backbilling.md` (0013–0019, 0031), `periods-and-aging.md` (0020–0026).
- `scenarios/review/2026-11-02/`: the three reviews and their brief.
- `application/scenarios-source-inventory-2026-11-02/`: the source inventory (GBM's older material is axes-only and largely predates the October rulings).

## Waiting on Ryan (start here next session)

1. **The Mcf bill-line question (roadmap R-19).** The bill-line rule (Ryan 10-14, CI-016; -21's `invoice_line_arithmetic_gap`) requires meter factor, Ccf, therms and commodity rate on every gas per-unit line. All four researched city tariffs bill per Mcf or Ccf with no therm conversion, so every cast bill would be refused at issue. Presented to Ryan on Nov 2 with four options; recommended: require the gas figures only on therm-billed lines, make a gas line's unit a fixed list (therm, Ccf, Mcf), and record a multiplier only with the raw quantity it multiplied. Open question asked: does therm/Ccf/Mcf cover it, or MMBtu or heat-adjusted Mcf too? It is the money stream's patch: if settled, log the decision and leave a board note for that stream.
2. **Cast question 5** (the combined city bill: gas paid, water not): raise when collections scenarios start, after -26 mirrors.

## Waiting on Kyle (sent Nov 2 by Slack, Kyle's DM; roadmap K-12)

17 questions: cast questions 1–4 and 6; and the Opens on SCN-0004, 0006, 0008, 0010, 0011, 0016, 0019 + 0028 (merged), 0024, 0027, 0029, 0030, 0031. Each scenario carries its own **Open (Kyle)** line; `grep -n "Open (Kyle)" scenarios/*.md`. When he answers: record the ruling in GBM (with `wiki-ingestion-pending.md`), in the DECISION-LOG, and on each scenario's Status line; then rework the scenarios his answers change.

## Not yet done (in order)

1. [ ] The remaining reviewer gaps, not yet written (merged list from the three reviews):
   - late penalties already posted when a bill is voided or a late check is found;
   - backbilling: a meter that stopped registering (three months; the test-date versus discovery-date anchor question), a large-volume customer outside the protected class, crossed meters, two customers inside the window, migrated meter history and deployment corroboration, a legacy hold, evidence that changes after approval;
   - deposits: the Texas cap and waivers, interest across a rate change or a partial application, a final bill that uses up the whole deposit (zero refund), a returned check that disqualifies the refund, a refund credit larger than the next bill, a due record withdrawn when its facts prove wrong;
   - the 60-or-over due-date delay (Utilities Code §182.002; pending whether it binds city systems) for PF-02;
   - periods: an account in credit in the aging, history before the first period, a withdrawn period, when an account becomes eligible for write-off.
2. [ ] Remaining families at parity: date-tracking and immutability, weather normalization, tenant isolation.
3. [ ] State machines, exception paths, the persona matrix.
4. [ ] Families after their patches mirror: cash (-23), disputes (-25), collections (-26), the rates stream's tax, gas cost, zones and reads.
5. [ ] The coverage audit against all 135 invariants; then the test strategy (roadmap R-15).

## Decisions this session (DECISION-LOG 2026-11-02)

- Scenarios live in this repo's `scenarios/`, not GBM (GBM docs carry "superseded for scenario writing" notes; GBM manifest section BU).
- A scenario's shape: Status, Rule with sources, Given (each fact sourced or marked invented), When (one event), Then (a worked bill and the refusals), Open (for whom).
- The cast is invented names on real small-city tariffs.
- Questions for Kyle were held until the first batch of worked bills, then sent (Nov 2).

## Warnings

- **Scenarios describe rules and rulings, not tables.** Where a family's schema is still being built, write against the ruling and say so on the Status line.
- **A Texas state rule appears only where it binds.** §7.45 and 16 TAC ch. 7 do not bind city-owned systems; their policy is their tariff row or nothing. SCN-0006 applies Kyle's 06-12 "historical rates only" ruling to a city system; it is asked of Kyle (question 5), not changed.
- **Invented facts are marked "invented"** in every scenario; keep it so Kyle knows what to check against reality.
- Verify a reviewer's must-fix against the source before applying it; all of this round's held up.
- Slack: Kyle's DM is a Slack Connect channel, so messages can only be **drafted** (`slack_send_message_draft`, channel `D0B0GRDQYLR`); Ryan sends them. The user search does not find him.
- Don't edit the money or rates streams' handoffs; leave notes on the board.
