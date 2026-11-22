# Review brief: scenarios round 4 (2026-11-22): cash, and today's changes

You are one of three independent reviewers (Opus, Fable, Codex). Read-only: do not edit any repository file (Codex writes only its own report). Do not read the other reviewers' reports for this round.

## What this is

TallyUtility is a gas-utility billing platform, multi-tenant (each utility is a tenant). The PostgreSQL schema is in `/Users/ryanscomputer/code/tally-utility-scenarios/sql/` (`tu.sql`, 42k+ lines, append-only, later definitions win: grep it, never read it whole; plus `v5.4.2-NN-*.sql` patches). A future C# core will evaluate the rules. The scenarios are the cases that core must pass; each becomes a test (Given / When / Then).

**Review in this round** (in `scenarios/`; read `README.md` and `cast.md` first):
1. `cash.md`: SCN-0081 – 0098, new, never reviewed. The main work.
2. Changed today to rulings by Ryan (the product owner): `cancel-rebill.md` SCN-0033; `periods-and-aging.md` SCN-0024 (last bullet); `billing-pipeline-and-charge-composition.md` SCN-0053; `cast.md` (late penalty rows).

**Rulings today**: `application/DECISION-LOG.md`, the entries headed 2026-11-22.

**Sources the scenarios claim to follow** (check against these, not your own idea of the rules):
- Kyle (the domain expert), in `/Users/ryanscomputer/code/gas-billing-memory/application/`: `kyle-decisions-2026-10-15-waves-1-to-7-and-texas-first.md` (R-01 to R-06, K-05, K-07), `kyle-decisions-2026-10-21-refund-then-bounce.md`, `kyle-decisions-2026-10-30-credit-shortfall-after-bounce.md`, `kyle-decisions-2026-11-03-scenario-batch-1.md`, `kyle-decisions-2026-11-05-scenario-batch-2.md`; `wu5-wu6-kyle-decisions-2026-07-10.md` (D7-1, D7-2)
- `application/DECISION-LOG.md`: the -23 and -27 entries (2026-10-14 to 2026-11-06); grep the headings
- `application/APPLICATION-CONTRACTS.md`: AC-35, AC-36, AC-41, AC-44, AC-46
- `/Users/ryanscomputer/code/gas-billing-memory/application/canonical-invariants.md` CI-013, 017, 048–058; outlines `invariant-scenarios/payment-allocation-and-posting.md`, `payment-intake-channels-and-reversal-handling.md`, `reversal-lineage-and-chain-discipline.md`; what superseded them: `application/scenarios-source-inventory-2026-11-02/audit-invariant-docs-p-to-w.md`
- `application/invariant-parity-measurement-2026-10-13.md`: grades and the dated Update sections
- the schema, mirrored through -23, -27, -28, -29; not mirrored: -24 (unmatched cash, pledges), -25 (disputes), -26 (collections), -30 (tax). Header comments and residual limits (R1–R24) in `sql/v5.4.2-23-*.sql` and `sql/v5.4.2-27-*.sql`; their executed batteries in `tests/v5.4.2-23/` and `tests/v5.4.2-27/`
- The live database, READ-ONLY: `docker exec tally-pg psql -U tally -d tally -Atc "<select>"`. Selects only: never write, never create a database, never run the batteries or `tests/ci.sh` (other sessions share it).

**Standing rules:** scenarios describe rules and rulings, not tables; where something isn't built the Status line says so; a claim that the schema does something must be true of the mirrored schema; the stream's own readings are marked, with an Open; facts not from a source are marked "(invented)"; facts stay consistent with the cast and other scenarios. Four-decimal working figures, half-up to the cent per line. A rule evaluated by the core is tested in the core, and the scenario must not say the database refuses it.

## What to look for

1. **Built-behaviour claims that are false**: for each "built", "refused" or "accepted", which guard does it, for which role, on which table? Is it the database or the core?
2. **Rules misstated**: a ruling applied beyond what it says; an Open that is already ruled somewhere; a reading presented as a ruling; one scenario contradicting another.
3. **Wrong figures, dates or ledger arithmetic**: recompute every table.
4. **Gaps**: cases the invariants, outlines, rulings or the -23/-27 batteries distinguish that no scenario exercises.
5. **Test-readiness**: a Given a test would have to guess; a Then that cannot be asserted.

Don't report style. Rank: **must fix**, **should add**, **note**. For each finding: scenario ID, severity, what is wrong, the evidence (file and line, or the query and its result), and the fix. At most 20, most important first.
