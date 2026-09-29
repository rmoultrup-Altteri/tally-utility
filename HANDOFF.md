# Handoff: A-2 rebuilt to parity; next, decide review/mirror and strip the landed Texas-law triggers

**Generated**: 2026-09-28 (end of session)
**Branch**: tally-utility `main` (`d96a8d6` plus this wrap-up) · gas-billing-memory `main` (`091c990`, unchanged this session; no new Kyle commits at wrap-up)
**Status**: -13 is rebuilt and verified. It is **not** mirrored into `tu.sql` and **not** sent for review. Both wait on Ryan.

## THE TWO THINGS TO CARRY FORWARD

1. **"A Texas only launch does not mean a Texas only architecture"** (Ryan). Statutory and tariff rules are platform-held rows, keyed by state and service type and dated by when they take effect. Texas is only the first set of rows. Memory: `launch-scope-is-not-architecture-scope`.
2. **The schema represents; the C# core evaluates** (Ryan). The stack is locked: React/TypeScript frontend, C# backend. No application code is written yet. **The current phase:** bring the schema to parity with the invariants and the configurable parts of the app, then keep writing scenarios. Triggers protect record integrity: stamps, immutability, same-tenant, frozen means frozen. Triggers never compute law, such as windows, forfeitures, who must approve, or which causes may be reissued. Memory: `schema-represents-core-evaluates`.

## Completed (this session)

- [x] **Texas-only architecture audit.** `application/texas-only-architecture-audit-2026-09-28.md`, drawn from 9 slice reports in `application/texas-only-audit-2026-09-28/`.
  - §2 recommends four layers: places (platform), law rules (platform), utility choices (per utility, stricter than the law but never looser), and mechanism (the future C# core).
  - §6 covers the second drift: application logic built into the schema.
- [x] **A-2 re-scoped to parity** (Ryan approved). `application/a2-parity-rescope-2026-09-28.md` holds the keep/drop/change map, the rule-table design, and §6 "As built".
- [x] **Ryan's three calls:**
  1. Approval checks (supervisor, and not the opener) move to the core; the database only stamps who and when.
  2. City-level rules (R-26) wait for the places table; rules are state-level only for now.
  3. The `regulatory_class_mode` names stay Texas-shaped until the class resolver patch (CCK-4…13). This is residual R4.
- [x] **`sql/v5.4.2-13-backbilling-caps.sql` rebuilt**: 2,167 lines, down from r7's 3,757 (r7 = `570d437`).
  - **New platform law tables:**
    - `backbilling_causes`;
    - `backbilling_customer_classes` (per state);
    - `backbilling_rules`: dated, no overlap per key, citation required;
    - `backbilling_rule_window_terms`.
    - The app cannot write to any of them. A law row is never edited, only closed and replaced.
  - **Texas gas seeded once** (16 rows, effective 2004-07-12).
  - **Correction records keep integrity only:** cases, evaluations (written by the core, citing the rule row and the core version), per-period evidence (only in its evaluation's transaction), approvals, holds and the event log.
- [x] **Every dropped behaviour written up for the core**: `application/a2-rules-for-the-core.md`. Each behaviour has its ruling, the r7 line range, and the battery, mutation and race cases that pinned it.
- [x] **Tests** (the r7 set moved to `tests/v5.4.2-13/r7/`):
  - `battery-13.sql`: 79 checks. Group Z stores a fictional state "ZZ" with no schema change: other classes, a new cause, a 12-month window, a 36-month refund reach, proration and conditional enforcement.
  - `evidence-txn-13.sh`: X1, run across two committed transactions.
  - `mutations-13.py`: 25 mutations.
- [x] **Verified on a clone of the -12 build:**
  - strict apply ×2 is clean and idempotent;
  - **79/79 PASS**;
  - **X1 PASS**;
  - **25/25 mutations caught**;
  - regressions unchanged at **28 / 58 / 41 / 116**.
- [x] **Two real defects found and fixed while building:**
  - a NULL-leg hole in the evidence and hold-artifact CHECKs (fixed with `coalesce`);
  - the law-history trigger read `effective_to` on the terms table, which has no such column.
- [x] Memory: `schema-represents-core-evaluates` (new).

## Not Yet Done (in order)

1. [ ] **Ryan decides on -13.** Either run one focused review round (does it store everything, and are the records protected?), or mirror it into `tu.sql` as it stands. My recommendation: one focused round, frozen by hash, with no open-ended adversarial hunting.
2. [ ] **Strip the law-applying triggers already in `tu.sql`** (audit §3/§6). Ryan decides now or later. Examples:
   - deposit rules (-06);
   - surcharge and rider logic (-07/-08);
   - gas-keyed correction rules;
   - -12's `meter_governing_test().supervisor_gate`, which has Texas's six months written in (-12:1615; residual R8).
   - Each moves its law to rows and its evaluation to the core, the same way -13 did.
3. [ ] **Questions for Kyle.** The answers change seed rows, not the schema.
   - Which date picks the rule row: each period's start, the anchor, or the correction date?
   - **R9:** does the unprotected class carry the fast-meter refund duty and the tamper sign-off? r7 applied both to every class; the new rows follow R-20.
   - Disagreements in the rules-for-the-core doc:
     - D1: for a non-registering meter, does the window count from the test date or from discovery?
     - D3: the scope of R-36's sign-off;
     - D5: may a zero amount be entered on a period where the customer owes?
     - D6: recording how an unmetered amount was estimated.
   - The six stale or contradictory doc values in audit §3.13.
4. [ ] Re-cut the invariant register's grading scale with Kyle, since "enforced by a DB trigger" is no longer the goal for law.
5. [ ] Sequence the shared places table. It unblocks city-level rules (R2) and `place_id` on law rows.
6. [ ] **Still open from before:**
   - OQ-1 (delivery path), and Kyle's OQ-1 brief is still unsent;
   - -14 waits on it;
   - U4 and U5 are now core concerns;
   - Workstreams A and B: the UI direction, the 229 tenant-blind FKs, A-8, A-10, Wave 4, re-grades, scenarios, wiki ingestion A–BM.

## Failed Approaches (Don't Repeat These)

- **Hardcoding Texas law in CHECK lists and triggers because the launch is Texas-only.** Use per-state, dated, platform rows instead.
- **Building the app in the database.** The r7 -13 evaluated law in about 3,700 lines of triggers and took six review rounds against a contrived attacker. Law evaluation belongs to the C# core.
- **Open-ended adversarial review.** Each round finds a narrower path; set a stopping rule first.
- **Assuming the right mutation target.** M07 surfaced at H7, not H5, because overlapping guards also refuse the edit it targets. Retarget to where the mutation actually surfaces, and say why in the script.
- **DROP and CREATE DATABASE in one `psql -c`.** It fails with "cannot run inside a transaction block"; run them as two commands.

## Key Decisions

| Decision | Rationale |
|---|---|
| The schema represents rules; the C# core evaluates them (Ryan) | Stack locked; the phase is schema parity, then scenarios |
| Law lives in platform rows keyed by (state, service, class, cause) and dated | A second state is new rows, not a redesign; ZZ proves it |
| Law rows are closed and replaced, never edited, even by the owner | Evaluations and evidence cite them |
| Approval rules move to the core; the database stamps who and when (Ryan) | Who must approve is law |
| State-level rules only until the places table lands (Ryan) | A platform table can't point at the per-utility `jurisdictions` |
| Class-mode names stay Texas-shaped for now (Ryan) | They are fixed in the CCK resolver patch; residual R4 |
| `partly_forfeited` disposition, `qualifying_test_outcomes` on rules | Proration states fit; a test-anchored rule says which outcomes make the cause |

## Current State

- `sql/v5.4.2-13-backbilling-caps.sql`: 2,167 lines, md5 `07ced77c92311ae73ffd3f19623ca4f9`.
- `tests/v5.4.2-13/battery-13.sql`: 853 lines, md5 `80a98fcbd3ac09ad37d20cb9812b512a`.
- `tests/v5.4.2-13/mutations-13.py`: md5 `fe19110a0b56aacddde32a70b4168649`.
- `tests/v5.4.2-13/evidence-txn-13.sh`: md5 `587a2b4ae524295820a36986fa63f3f5`.
- **Deployed:** `tally-pg` is running, and only the databases `tally` (the -12 build) and `postgres` exist.
- **Uncommitted changes:** none after this wrap-up commit.

## Resume Instructions

1. Fetch both repos, and check GBM for Kyle's commits (memory `fetch-gbm-before-orienting`).
   ```sh
   cd ~/code/tally-utility && git pull --ff-only
   cd ~/code/gas-billing-memory && git fetch && git log --oneline HEAD..origin/main
   ```
2. Start `tally-pg` if it has stopped: `docker start tally-pg`, then wait for "PostgreSQL init process complete" (memory `tally-pg-readiness-wait`).
3. Re-verify -13 on a clone:
   ```sh
   docker exec tally-pg psql -U tally -d postgres -c "CREATE DATABASE a2p TEMPLATE tally"
   (echo "SET search_path = ''; SET check_function_bodies = on;"; cat sql/v5.4.2-13-backbilling-caps.sql) | docker exec -i tally-pg psql -U tally -d a2p -v ON_ERROR_STOP=1 -q -f -
   docker exec -i tally-pg psql -U tally -d a2p -v ON_ERROR_STOP=1 -q -f - < tests/v5.4.2-13/battery-13.sql | grep -c PASS   # 79
   tests/v5.4.2-13/evidence-txn-13.sh a2p
   python3 tests/v5.4.2-13/mutations-13.py      # 25/25, uses its own DB a2pm
   ```
4. Ask Ryan item 1 (review or mirror) and item 2 (strip the landed triggers now or later), then proceed.

## Warnings

- **`tu.sql` is APPEND-ONLY.** Mirror a patch BODY only, then `diff` it.
- **Freeze the hash before any review round** (memory `freeze-hash-before-reviews`).
- `evidence-txn-13.sh` commits rows that the append-only tables won't let you remove. Run it only on a throwaway clone.
- `mutations-13.py` uses a fixed DB name (`a2pm`), so only one run at a time.
- Never `git add -A` in GBM. Log GBM canonical changes in GBM `application/wiki-ingestion-pending.md`.
- Explain jargon in plain language for Ryan (memory `explain-jargon-in-the-question`).
