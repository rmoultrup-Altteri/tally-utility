# Handoff: deposits (-06) to parity: decide R-D2 (the refund-due record), then build

**Generated**: 2026-09-30 (end of session)
**Branch**: tally-utility `main` (`27f2e68` plus this wrap-up) · gas-billing-memory `main` (`091c990`, no new Kyle commits at wrap-up)
**Status**: Blocked on Ryan's decision R-D2. No deposit schema has been changed yet.

## Goal

Move the Texas law built into -06's deposit guards out of the database:
- the law becomes per-state, dated, cited platform rows;
- the records keep integrity only;
- the C# core evaluates.

This is the same pattern -13 used. The ground rules are unchanged:
- **The schema represents; the core evaluates** (memory `schema-represents-core-evaluates`).
- **A Texas-only launch is not a Texas-only architecture** (memory `launch-scope-is-not-architecture-scope`).

## Completed (this session)

- [x] **-13 review round P1.**
  - Frozen on `07ced77c`; two reviewers (Fable, Opus) both said "not yet".
  - Every finding was reproduced, then folded (`a796658`).
  - Ryan's calls:
    - A: a known onset on any case, plus fallback chains;
    - B: lookup tables and term units, with interest and payment plans going to the delivery patch;
    - C: the core version is recorded on evaluations only.
  - Record: `tests/v5.4.2-13/review/review-findings-13-parity-p1.md`.
- [x] **-13 mirrored and LANDED** (`197aa9e`).
  - tu.sql went 23,452 → 25,930 lines. The rebuild is clean, and full catalog identity (6,182 lines) matches.
  - Battery 99/99, X1, mutations 45/45 (those on the clone).
- [x] **-14 drafted, mirrored and LANDED** (`fb184f4`, `47d5f2a`).
  - `meter_governing_test()` is re-created without `supervisor_gate`: R-36's Texas six months leaves the database (-13 residual R8).
  - tu.sql went 25,930 → **26,049**, md5 `9139367ab7da6ada63d4193ba189e17f`.
  - Identity including comments (9,532 lines) matches.
  - Batteries on the build: 28/58/41/116/99/6; mutations-14 4/4.
- [x] **The deposits design:** `application/deposits-parity-rescope-2026-09-30.md` (commits `b29e20e`, `19c9132`, `27f2e68`).
  - §1 keep, §2 drop, §3 platform rule tables, §4 Ryan's decisions, §5 Kyle questions, §6 prerequisites.
  - **R-D1 DECIDED** (Ryan):
    - the utility keeps the interest rate it applies (`deposit_interest_rates`, per tenant; each accrual cites its row);
    - the platform keeps each state's published legal rate as a reference only (`deposit_interest_rate_law`);
    - a discrepancy report compares them.

## Not Yet Done (in order)

1. [ ] **R-D2: Ryan decides the refund-due record.** He is thinking it over. The design doc §4 records where the discussion got to.
   - **The current recommendation:** ONE append-only row when a deposit's refund becomes due (the deposit, the date, the rule row, the reason, the counts, the core version), plus a view of due rows with no refund started.
   - The core checks on events (payment, bill past due, status change), not in a daily sweep.
   - There is no "not checked recently" column.
   - **Option B** is to store nothing: the core computes on demand, with no record.
   - Explain it in plain language, one decision at a time (memories `prefers-discussion-over-canned-options`, `explain-jargon-in-the-question`).
2. [ ] **R-D3: numbering.** The recommendation is to call the delivery patch "the delivery patch", not "-15". This deposits patch would take v5.4.2-15.
3. [ ] **Before stripping anything**, write `application/deposits-rules-for-the-core.md`.
   - It covers every behaviour in the design's §2, with its source and the -06 line range.
   - Boundary cases: the 30/31-day cliff, a rate change mid-hold, exhaustion by applications, the zero refund, and the legacy exception.
   - **-06's battery (141 checks) was lost**, so no deposit tests exist in the repo.
4. [ ] **Build the patch** to the design, with:
   - a new battery, including the fictional state ZZ;
   - mutations on a -14 base;
   - strict apply ×2;
   - regressions 28/58/41/116/99/6;
   - then Ryan's call on review or mirror.
5. [ ] Send Kyle questions K1–K5 (design §5). The answers change seed rows only.
6. [ ] **Still open from before:**
   - Kyle's A-2 questions: which date picks the rule row, R9, D1/D3/D5/D6, and the audit §3.13 doc values;
   - the register re-grade;
   - the places table;
   - OQ-1 and the delivery patch;
   - the rest of the landed-law strip, in audit §4 order: surcharges (-07/-08), tax (-03/-09), programs (-04), the PGA pool, escheat, the estimate cap, `America/Chicago`.

## Failed Approaches (Don't Repeat These)

- **Framing options as "until the core exists".** Ryan: nothing is live. There is no code and no data, so the only question is the PERMANENT schema. Never offer an option as a stopgap.
- **A record per check.** Proposing an append-only row every time the core checks a deposit meant a daily sweep writing mostly useless rows (Ryan). Record only when the answer changes: the trigger firing.
- **One platform interest rate that the core uses** (first R-D1 recommendation). It moves the regulatory update onus to Tally, takes control from the utility (the regulated party that the commission holds responsible), and makes one bad entry mis-rate every utility in the state. Use the utility's rate as the one applied, and the platform rate as a reference with a discrepancy report.
- **Re-applying the -12 patch over a current build.**
  - It fails with `ERROR:  cannot change return type of existing function` (-12's `CREATE OR REPLACE meter_governing_test`).
  - `races/pointer-mutex-12.sh` now applies -12 only when `meter_tests` is absent.
- **Assuming a deleted GRANT removes access.** -11's default privileges give `tally_app` EXECUTE on every new public function. To test the loss of access, REVOKE it.
- **Rewriting a mutation's anchor without re-checking its target.** -13's M16 was first pointed at the cause comparison while F6 tests the class comparison, so it was missed. Re-run every mutation after edits.
- **The -13 mutation script on the current `tally`.** `CREATE TABLE IF NOT EXISTS` keeps the real tables, so table-definition mutations don't take. It needs a -12 base (tu.sql `2aa59147…`); -14's needs a -13 base (`ab3ce7ae…`).

## Key Decisions

| Decision | Rationale |
|---|---|
| -13 fixes all folded; the core version is recorded on evaluations only (C) | Holds, approvals and freezes are a person's acts, stamped with who and when |
| Interest and payment plans go to the delivery patch (residual R10) | They attach to money that posts; nothing posts before delivery |
| -14 removes `supervisor_gate` rather than feeding it from rule rows | The gate is law; the core has every input (weak_provenance, cutover, the rule's before_anchor) |
| -14 not reviewed (Ryan) | 177 mechanical lines, with mutation-proven tests |
| R-D1: the utility's rate is the one applied; the platform legal rate is a reference plus a discrepancy report | The utility is the regulated party; avoids one mistake reaching every customer at once |
| Deposit law as `deposit_rules(state, service, class, basis)` plus vocabularies (bases, triggers, classes, waiver classes) | The -13 pattern; ZZ proves a second state is rows only |

## Current State

**Working:**
- `tally-pg` runs the fresh build of tu.sql, 26,049 lines (`9139367a…`); only the `tally` database exists.
- Every battery is green on it.

**Broken:** nothing.

**Uncommitted changes:** none after this wrap-up.

## Code Context

- **Deposit guards to strip** (tu.sql 17,706–18,822 = `sql/v5.4.2-06-account-lifecycle-and-deposits.sql`):
  - `enforce_deposit()` 840–905: the waiver and TX cap branches go; the identity freeze stays;
  - `enforce_deposit_event()` 910–1063: the interest and refund law goes; the arithmetic stays;
  - `deposit_accrual_amount()` 549;
  - `deposit_refund_trigger_state()` 790;
  - `deposits_refund_due` 821;
  - the CHECK lists at 575, 621–624.
- **The parity catalog check:** `tests/v5.4.2-14/parity/catalog-identity.sql`. Run it on the patched clone and on the fresh build, then `diff`.
- **The mirror procedure:**
  1. Append the body from the first `-- ---` divider before `-- 1.` onward.
  2. Put a 4-line banner before it, following the -13 and -14 mirrors (`tu.sql` 25,931 and 26,050).
  3. Check with `cmp` that the prefix and the appended body are unchanged.
  4. `docker build -q -t tally-postgres -f postgres/Dockerfile . && docker rm -f -v tally-pg && docker run -d --name tally-pg -e POSTGRES_PASSWORD=tally tally-postgres`.

## Resume Instructions

1. Fetch both repos: `cd ~/code/tally-utility && git pull --ff-only; cd ~/code/gas-billing-memory && git fetch && git log --oneline HEAD..origin/main`.
   - Expected: nothing new, or Kyle's rulings (read them before orienting).
2. `docker ps --filter name=tally-pg`. If it has stopped, `docker start tally-pg` and wait for "PostgreSQL init process complete" (memory `tally-pg-readiness-wait`).
3. Open `application/deposits-parity-rescope-2026-09-30.md` §4 **R-D2** and resume the discussion with Ryan there.
4. Then do R-D3, then write `deposits-rules-for-the-core.md`, then build.

## Warnings

- **`tu.sql` is APPEND-ONLY.** Mirror a patch body only, then check it with `cmp`.
- **Freeze the hash before any review round** (memory `freeze-hash-before-reviews`).
- **Reviewer subagents may be refused a report file.** Opus sent its report in 3 SendMessages; Fable wrote its report to a file.
- **Don't strip a deposit guard before its behaviour is written up for the core.** No battery covers -06 today.
- **Never `git add -A` in GBM.** Log GBM canonical changes in `application/wiki-ingestion-pending.md`.
