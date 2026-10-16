# Handoff: v5.4.2-22 r5 drafted after review round 4 — freeze r5, launch round 5

**Generated**: 2026-10-16 (afternoon)
**Branch**: `main` in both repos.
- tally-utility is at `341590e`, clean and pushed. Kyle pushed three `ui-concepts` commits today; they don't touch the database work.
- GBM `main` is at `954c472`; Kyle pushed nothing there.
- `Clippings/` in GBM is untracked on purpose: never commit it.

**Status**: In progress.
- The r5 draft is written, tested and committed.
- It is **not frozen**, and round 5 has **not** launched: Ryan wants it started in a fresh session.

## Goal

Reach the C# core build. Ryan's gate, in order:
1. schema parity with CI-001…CI-135 (**we are here**: 75 of 135);
2. scenarios and a test strategy;
3. a phase plan;
4. build.

Wave 2 is two patches:
- -22, periods and reporting (additive);
- -23, cash (meaning-changing).

## Completed (this session)

- [x] **r3 freeze (`0b31d2b`).** A real defect turned up first.
  - The last session's mutation run never finished: one backend had sat in battery check R11 for 12 hours.
  - The cause: the write-off cap's walks scanned the customer's ledger at every step.
  - The fix: each step joins on the link only. New checks R10f and R10g; new mutations M62 and M63.
  - The runner now sets a 300 s statement timeout. M49 was rewritten to read the tenant's live setting.
- [x] **Round 3:**

  | Reviewer | Verdict | Blocker |
  |---|---|---|
  | Opus | not yet | B1: the cap held only at the end, not at every date |
  | Codex | not yet | B1: the close read the edges after its instant, without a lock |
  | Fable | ready | none |

  - Codex's 12 probes were executed and appended to `codex-r3.md`.
- [x] **r4, frozen at `94d3b99`.** The patch md5 was `5228060d…`.
  - The cap holds at every date of the tree, and the tree is in date order.
  - A row recorded before a row already in its tree is refused with 40001. Found by the author: `created_at` is the transaction's *start*.
  - A new trigger, `enforce_aging_edges_close_order`, makes an edges change take the head FOR SHARE.
  - The upward walk carries type and customer.
  - Both walk functions run with `enable_seqscan`, `enable_hashjoin` and `enable_mergejoin` off.
  - The mutation runner VACUUMs the ledger before each battery.
- [x] **Round 4:**

  | Reviewer | Verdict | Blocker |
  |---|---|---|
  | Opus | ready | none |
  | Fable | ready | none |
  | Codex | not yet | B1: a superuser history row recorded at `infinity` or in the future strands a write-off tree; every later posting gets 40001 forever |

  - Codex's B1 was reproduced: its 15 probes were executed and appended to `codex-r4.md`.
- [x] **r5 draft (`341590e`).** `sql/v5.4.2-22-periods-snapshot-gl-aging.sql` is 1,913 lines, md5 `7e914bda…`.
  - A row in a write-off's tree is recorded at a finite time already reached. The write-off itself is covered: the trigger now fires `WHEN (reverses IS NOT NULL OR transaction_type = 'write_off')`.
  - The invariant pins both walk functions' `proconfig`.
  - The header states the tenant-row deadlock (the close's snapshot FK against an edges change) and adds residual R12: history loads post one statement per recorded instant.
- [x] **Tests on r5:**
  - strict apply twice (the second run is skipped);
  - battery **157/157** on a vacuumed ledger;
  - races **CR1–CR15**;
  - mutations **72/72**;
  - `tests/ci.sh` **all pass, 35 steps**.
- [x] **Review files:**
  - `review-findings-22-r3.md` and `review-findings-22-r4.md`;
  - `review-brief-22-r5.md` (only the four md5 placeholders remain);
  - DECISION-LOG entry for 2026-10-16 (-22 review round 3).
- [x] **Memory:** `recursive-walks-join-on-link-alone.md` (pin the plan; test after VACUUM).

## Not Yet Done

- [ ] **Freeze r5:**
  - copy the four live files to `tests/v5.4.2-22/review/*-frozen-r5.*`;
  - `diff -u patch-22-frozen-r4.sql patch-22-frozen-r5.sql > diff-22-r4-r5.diff`;
  - fill `@@PATCH@@`, `@@BATTERY@@`, `@@CLOSE@@` and `@@MUTATIONS@@` in `review-brief-22-r5.md`;
  - write `review-brief-22-r5.md5`;
  - commit and push.
- [ ] **Launch round 5** (Opus, Fable, Codex), the same way as round 4 (below). Run Codex's probes yourself.
- [ ] **If all three say ready,** ask Ryan to approve the mirror into tu.sql: one plain-language question, with a default.
- [ ] **After the mirror:**
  - remove -22 from PENDING in `tests/ci.sh`;
  - re-grade the parity measurement (CI-048, CI-076, CI-110);
  - add GBM manifest section BR;
  - write DEPLOY-VERIFICATION.
- [ ] **v5.4.2-23, cash:** M, X, A, C, U, L (see the inventory).
- [ ] **Carried over:**
  - the reply to Kyle on D-2's location;
  - the -05 defect (`meters_last_validated_actual_reading_id_fkey`);
  - -21 R9;
  - the R-03 scoping;
  - `pga_monthly_reconciliations.deferred_balance_after`;
  - the backbilling tariff table;
  - the GitHub Actions bump;
  - the Florida 25-7.083 text;
  - the waiver-determination rewrite;
  - low-confidence measurement rows;
  - the -15 r8 follow-ups;
  - gate steps 2–4.

## Failed Approaches (Don't Repeat These)

- **Tenant or customer predicates in a recursive step's join.** The planner picked `idx_ledger_type(tenant_id)` or a bitmap AND over the PK or reversal index, so each step scanned about 1,000 rows. Under M57 that hung for 12 hours. Join on the link alone, and test tenant and customer through a CASE or a carried `mine` flag.
- **Link-only joins without pinned plans.**
  - On a ledger the planner believes empty (fresh, or after VACUUM, reltuples 0), the step hash-joined a sequential scan of the whole ledger.
  - With only `enable_seqscan` off, it merge-joined a full index scan instead.
  - R10g alternated between passing (1.5 s) and failing (30 s) from run to run.
  - Turn off all three: seqscan, hashjoin and mergejoin.
- **Testing plan-sensitive claims on a fresh clone.** The slow plan appears only after VACUUM. M68 was MISSED until the runner VACUUMed first.
- **`refuses_at`/`WHEN OTHERS` to catch a statement timeout.** `query_canceled` is not caught by OTHERS. R10g uses its own DO block with `WHEN query_canceled`.
- **A same-date check (R12h) as the catcher for the ROWS-frame mutation.** R10f's same-date rows cross first, so M71 is labeled R10f. Rename to the earlier check; never loosen the runner.
- **R10f with only the foreign-customer row.** A C1 row never triggers C5's cap, so M62 was MISSED. R10f now adds a C5 row after it.
- **psql `LAST_ERROR_SQLSTATE` after a failed COPY.** It stays `00000`, which broke r2 n7 and r3 n7. Print the error text.
- **"The close never locks the tenant row".** False: the snapshot rows' tenant FK takes FOR KEY SHARE. The deadlock is now stated.
- **Earlier sessions' failures still hold:**
  - an AFTER (not BEFORE) cap;
  - the net of the whole tree;
  - a fail-closed lineage bound;
  - no close read of the config history;
  - P9f run as owner;
  - `repr()` anchors;
  - withdraw by status;
  - the head handshake;
  - no TEMP under `tally_app`;
  - and the rest.

## Key Decisions

| Decision | Rationale |
|---|---|
| The cap holds at every date; tree rows are dated on or after the entry they name | Guard the act: aging and the close net the tree at a date (Opus B1 froze 200 recovered against 100) |
| A row recorded before a tree row is refused with 40001 (retry) | `created_at` is the transaction start; otherwise a recorded-instant view sees an over-cap state |
| Tree rows, write-off included, are recorded at a finite time already reached | Otherwise a superuser history row at `infinity` makes 40001 permanent (Codex r4 B1) |
| The edges change waits for the close (head FOR SHARE); the promise is not reworded | Design permanent; the same handshake as money writes, and no new grants |
| The tenant-row deadlock is stated, the FK is not rerouted | Both reviewers accepted either; rerouting changes the snapshot keys, and the `closed_by` FK still locks a users row |
| Walk functions run with seqscan, hashjoin and mergejoin off, pinned in the invariant | Plans are otherwise statistics-dependent (measured 30 s against 1.5 s) |
| History loads under a write-off post one statement per recorded instant (R12) | Siblings in one statement see each other; a valid mixed batch is refused (Codex r4 S1) |

## Current State

**Working:** r5 passes everything: battery 157, CR1–CR15, mutations 72/72, CI 35/35.
**Broken:** nothing known. Codex's r4 B1 is fixed in r5 but not yet reviewed.
**Uncommitted changes:** none. **Scratch DBs:** none left.

## Code Context

```sql
-- AFTER INSERT on account_ledger, fired by name: enforce_ledger_lineage_acyclic, then enforce_write_off_recovery
-- enforce_write_off_recovery: SET search_path=public, pg_temp; enable_seqscan/hashjoin/mergejoin=off
--   WHEN (NEW.reverses_ledger_entry_id IS NOT NULL OR NEW.transaction_type = 'write_off')
--   raises: 23514 "recorded in the future" | "dated on or after the entry it names" | "on <date> the rows netted" (R-02 cap)
--           40001 "... retry it" (recorded before a tree row) | 23503 "names a write_off entry" | 25000 at non-READ COMMITTED
-- enforce_aging_edges_close_order: BEFORE UPDATE OF receivables_aging_bucket_days ON tenants; head FOR SHARE
-- assert_periods_guard_invariants(): exact triggerdefs, constraintdefs, and the walks' proconfig
--   {"search_path=public, pg_temp",enable_seqscan=off,enable_hashjoin=off,enable_mergejoin=off}
```

- The per-date cap is `sum(amount) OVER (ORDER BY transaction_date)` over `v_tree`. The default RANGE frame nets same-date rows together.
- The mutation runner VACUUMs `public.account_ledger` before every battery, and passes `PGOPTIONS=-c statement_timeout=300s`.

## Resume Instructions

1. `git pull --ff-only` in both repos. Check GBM for Kyle's pushes.
2. Freeze r5:
   ```
   cd tests/v5.4.2-22/review
   cp ../../../sql/v5.4.2-22-periods-snapshot-gl-aging.sql patch-22-frozen-r5.sql
   cp ../battery-22.sql battery-22-frozen-r5.sql
   cp ../races/close-22.sh close-22-frozen-r5.sh
   cp ../mutations-22.py mutations-22-frozen-r5.py
   diff -u patch-22-frozen-r4.sql patch-22-frozen-r5.sql > diff-22-r4-r5.diff
   ```
   - Fill the four md5 placeholders in `review-brief-22-r5.md` (`md5 -q`).
   - Write `review-brief-22-r5.md5`.
   - Commit and push.
   - Expected: `grep -c @@ review-brief-22-r5.md` returns 0.
3. Launch round 5 in parallel:
   - **Opus and Fable:** Agent `general-purpose`, model opus / fable, background, named `opus-r5` / `fable-r5`, pointed at `review-brief-22-r5.md` and its md5. Each reads its own r4 report. Scratch clones: `rv22opus5` and `rv22fable5`.
   - **Codex:** `mkdir -p tests/v5.4.2-22/review/codex-r5-probes && PATH=~/.nvm/versions/node/v24.15.0/bin:$PATH codex exec -s workspace-write -C ~/code/tally-utility -o tests/v5.4.2-22/review/codex-r5-final.txt - < tests/v5.4.2-22/review/codex-prompt-r5.md`. The prompt is ready in the repo.
4. Run Codex's probes yourself:
   - one fresh clone per probe, from a template with frozen r5 applied, TEMP revoked, `statement_timeout=300s`;
   - append the outputs to `codex-r5.md`.
5. If all three say ready, ask Ryan to approve the mirror (one question, plain language, with a default). Otherwise fold the findings into r6.

## Warnings

- **Never edit the frozen review copies or tu.sql's mirrored body.** tu.sql is mirrored only on Ryan's approval.
- **Revoke TEMP from PUBLIC, `tally_app` and `tally_core` after every `CREATE DATABASE … TEMPLATE`.**
- **Roles are cluster-wide;** reviewers must not touch roles.
- **`tests/ci.sh --build` deletes the container.**
- **Plan-sensitive tests:** VACUUM first, or a slow plan will not show.
- **Codex runs source-only.** You run its probes, and check each probe's own error capture.
- **Never `git add -A` in gas-billing-memory.**
- **Commits go straight to main.** `git pull --rebase` before pushing: Kyle pushes `ui-concepts` work to tally-utility.
- **Background reviewers' final messages repeat as idle notifications.** Don't act on a second copy.
- **Ask Ryan one decision per message, in plain language, with a default.**
