# Review brief: scenarios round 3 (2026-11-05)

You are one of three independent reviewers (Opus, Fable, Codex). Read-only: do not edit any repository file.

## What this is

TallyUtility is a gas-utility billing platform, multi-tenant (each utility is a tenant). The PostgreSQL schema is in `/Users/ryanscomputer/code/tally-utility-scenarios/sql/` (`tu.sql`, 42k lines, append-only: grep it, never read it whole; plus `v5.4.2-NN-*.sql` patches). A future C# core will evaluate the rules. The scenarios are the cases that core must pass; each becomes a test (Given / When / Then). Rounds 1 and 2 (`scenarios/review/2026-11-02/`, `2026-11-04/`) reviewed SCN-0001 – 0059.

**Review in this round** (in `/Users/ryanscomputer/code/tally-utility-scenarios/scenarios/`; read `README.md` and `cast.md` first):
1. `tenant-isolation.md`: SCN-0060 – 0068 (identifiers unique per utility, the isolation smoke test, switched-off users and supervisor binding, shared platform data, links between utilities, Tally staff read-only, imports once, a meter once per run, impersonation).
2. `date-tracking-and-immutability.md`: SCN-0069 – 0077 (two time axes, correction vs retraction, one time basis per bill, stale saves, bills and money never edited, no deletes, the bill snapshot, dated rate assignment).

**Rulings made today, 2026-11-05, by Ryan (the product owner)** — `application/DECISION-LOG.md`, the four entries headed "2026-11-05 (scenarios)":
- Tally employees (platform administrators) may impersonate a utility's users, on Tally's own decision; the database records each session and marks every change; plain platform-admin access is read-only (not built).
- Every single-column foreign key between tenant tables becomes a two-column key with `tenant_id` (273 counted on the live `tally` database today; the fix runs last).
- A billing run reads every bill at one recorded instant, fixed when the run starts.
- A backbill for a customer outside Texas's protected class is refused until the utility's tariff states a rule (not under review here).

**Sources the scenarios claim to follow** (check against these, not your own idea of the rules):
- `application/invariant-parity-measurement-2026-10-13.md` (the grade of each invariant CI-NNN; `grep -n "^| CI-NNN "` and the dated Update sections at the top, newest first)
- `application/APPLICATION-CONTRACTS.md` (AC-43: how the app sets the acting user)
- `application/scenarios-source-inventory-2026-11-02/rulings-digest.md`; the two inventory files `audit-invariant-docs-a-to-m.md` (sections 4 and 12) and `audit-invariant-docs-p-to-w.md` (section 9)
- GBM outlines: `/Users/ryanscomputer/code/gas-billing-memory/application/invariant-scenarios/tenant-isolation-and-structural-integrity.md`, `bi-temporal-foundation.md`, `immutability-and-snapshot.md`
- the schema: `sql/tu.sql` (mirrored through v5.4.2-23, -28 and -29). Claims of built behaviour cite patches -01 to -04, -10, -16, -19, -20, -21, -23. A live database may be reachable read-only: `docker exec tally-pg psql -U tally -d tally -Atc "<select>"` (selects only; never write).
- `HANDOFF.md` (the board): the cross-tenant link note (rates → money, 2026-11-04) and "After both schema streams finish"

**Standing rules:** scenarios describe rules and rulings, not tables; where something isn't built, the Status line must say so, and a claim that the schema does something must be true of the mirrored schema; the stream's own readings are marked as readings, with an Open; facts not from a source are marked "(invented)"; keep facts consistent with the cast and with other scenarios (customers, dates, rates). Four-decimal working figures, half-up to the cent per line (Kyle 10-15).

## What to look for

1. **Built-behaviour claims that are false.** The most valuable finding this round. For each "Built" or "refused" claim, check the schema: does the guard exist, for that role, on that table? Does something claimed "not built" actually exist?
2. **Wrong figures**: recompute SCN-0069, 0070 and 0076's bills (the reference bill is in `cancel-rebill.md`).
3. **Rules misstated**, or a ruling applied beyond what it says; a scenario contradicting another.
4. **Gaps** the invariants or outlines distinguish that no scenario exercises (the GBM outlines list axes).
5. **Test-readiness**: a Given a test would have to guess; a Then that cannot be asserted.

Don't report style or wording. Rank: **must fix**, **should add**, **note**. For each finding: scenario ID, severity, what is wrong, the evidence (file and line, or the query you ran and its result), and the fix. At most 20 findings, most important first.
