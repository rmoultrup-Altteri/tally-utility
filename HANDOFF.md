# Handoff: v5.4.2-22 r3 drafted after review round 2 — confirm mutations, freeze, launch round 3

**Generated**: 2026-10-15 (late evening)
**Branch**: `main` in both repos. tally-utility has the r3 draft committed at wrap-up. GBM `main` is at `954c472`; Kyle pushed nothing new this session. `Clippings/` is untracked on purpose: never commit it.
**Status**: In progress. The -22 r3 draft is written and tested. The full mutation run had **not finished** at wrap-up. r3 is **not frozen**, and round 3 has **not** launched.

## Goal

Reach the C# core build. Ryan's gate, in order:
1. schema parity with CI-001…CI-135 (**we are here**: 75 of 135);
2. scenarios and a test strategy;
3. a phase plan;
4. build.

Wave 2 = -22 (periods and reporting, additive) and -23 (cash, meaning-changing).

## Completed (this session)

- [x] **Resume:** no drift. CI passed with -22 pending. The r2 frozen hashes match the brief. The previous handoff paired the hashes with the wrong files; the brief is right.
- [x] **Review round 2 of -22** (`788aef4`):
  - Opus: **not yet**.
  - Fable: **ready**.
  - Codex: **not yet**. I ran its 11 probes on a clone of frozen r2 and appended the outputs to `codex-r2.md`. The b1, b2 and s2 predictions reproduced. n7 printed "COPY accepted" for a COPY that was in fact refused: the probe's `\if :ERROR` capture is wrong, not the patch.
  - Codex's "inventory absent" note was correct. The inventory and DECISION-LOG live in **tally-utility** `application/`, not GBM; the r2 brief misled it. The r3 brief uses absolute paths.
- [x] **`tests/v5.4.2-22/review/review-findings-22-r2.md`**: 13 findings with their dispositions.
- [x] **The r3 draft** of `sql/v5.4.2-22-periods-snapshot-gl-aging.sql` (1,733 lines, md5 `b0ed9454…` at wrap-up):
  - **The write-off rule** is now `enforce_write_off_recovery`, AFTER INSERT, `WHEN (NEW.reverses_ledger_entry_id IS NOT NULL)`. The cap is the net of the write-off's whole same-customer tree, kept in `[0, -amount]`, for every write-off above the new row. It takes the advisory locks in id order, at READ COMMITTED.
  - **The lineage walk fails closed:** `c_max = 1000`, and a chain that has not reached an original within it is refused.
  - **The close's edges** are read from `tenants.receivables_aging_bucket_days`. `tally_close` loses history SELECT and `receivables_aging_bucket_days_as_of`, and gains `tenants(id, receivables_aging_bucket_days)`.
  - **A withdrawal requires `app.user_id`** (23502).
  - **Closing a withdrawn period** gets its own message: "is withdrawn".
  - **The seal invariant** refuses `tally_app` UPDATE on `closed_by`, and its comment is corrected.
  - **The periods invariant** pins `tenant_configuration_history_key_known_check`, `account_ledger_reversal_not_self_check` and `account_ledger_reverses_ledger_entry_fkey`.
  - **Header:** an r3 paragraph, a lock-order note on the withdrawal-and-close deadlock, R8 reworded, and a new residual R10 (manual history rows).
- [x] **Tests on r3:**
  - Strict apply twice: the second run is skipped.
  - `battery-22.sql`: **147 PASS** (new: R9, R9b, R9c, R10–R10e, R11, P9f, C13b, C16b; C12 now uses the stored edges).
  - `races/close-22.sh`: **CR1–CR12 PASS** (new: CR11, CR12).
  - Codex's b1, b2 (the 10,001 ring), n6 and s2 probes are all refused or caught on r3.
- [x] **`mutations-22.py`:**
  - Anchors updated for M22–M25, M39 and M40.
  - New mutations M53–M61.
  - The label match is now exact. It was `[a-z]?`, which Codex flagged.
- [x] **DECISION-LOG, 2026-10-15 (-22 review round 2):** three calls settled by standing rule:
  - the net cap on the whole tree;
  - the close reads the tenant's own setting;
  - withdrawal stays an operator's act, with a named user.
- [x] **`tests/v5.4.2-22/review/review-brief-22-r3.md`:** written, with placeholders `@@PATCH@@`, `@@BATTERY@@`, `@@RACES@@`, `@@MUTATIONS@@`, `@@CI@@` and `@@MUT@@`.

## Not Yet Done

- [ ] **The mutation result on r3.** The full run did not finish this session. Re-run `python3 tests/v5.4.2-22/mutations-22.py` (61 mutations, about 10–15 minutes).
- [ ] **`tests/ci.sh`** on r3. It has not been run since the r3 edits; -22 is still PENDING in it.
- [ ] **Freeze r3:**
  - copy the four live files to `tests/v5.4.2-22/review/*-frozen-r3.*`;
  - write `diff-22-r2-r3.diff` (`diff -u patch-22-frozen-r2.sql patch-22-frozen-r3.sql`);
  - fill the brief's placeholders;
  - write `review-brief-22-r3.md5`;
  - commit.
- [ ] **Launch round 3** in parallel (Opus, Fable, Codex), the same way as round 2 (below). Run Codex's probes yourself. Mirror into tu.sql **only on Ryan's approval**, after all three say ready.
- [ ] **After the mirror:**
  - remove -22 from PENDING;
  - re-grade the parity measurement (CI-048, CI-076, CI-110);
  - add GBM manifest section BR;
  - write DEPLOY-VERIFICATION.
- [ ] **v5.4.2-23, cash:** M, X, A, C, U, L (see the inventory).
- [ ] **Carried over:**
  - the reply to Kyle on D-2's location;
  - the -05 defect (`meters_last_validated_actual_reading_id_fkey`);
  - -21 R9 (`line_item_carries_base`: the date from the snapshot's `valid_at`, the knowledge from `now()`);
  - the R-03 scoping question (label and import-mapping tables are deletable);
  - `pga_monthly_reconciliations.deferred_balance_after`;
  - the backbilling tariff table;
  - the GitHub Actions bump;
  - the Florida 25-7.083 text;
  - the waiver-determination rewrite;
  - low-confidence measurement rows;
  - the -15 r8 follow-ups;
  - gate steps 2–4.

## Failed Approaches (Don't Repeat These)

- **Capping write-off reversals in a BEFORE INSERT trigger:** a row naming a write-off listed *later* in the same VALUES, CTE or COPY is invisible to BEFORE, so it is accepted. Codex reproduced 150 reinstated against a 50 write-off. Use AFTER INSERT ROW, which fires at statement end and sees all the rows.
- **Capping only the rows that name the write-off directly** (gross recoveries): `+700` naming the *recovery* was uncapped (Opus), and a reversed recovery still consumed the cap (Fable). Cap the net of the whole same-customer tree.
- **A depth-bounded loop walk that stops silently:** at `u.depth < 10000` a ring of 10,001 was admitted, after which aging and the close raise `22000 … reach no original`. Refuse when the bound is reached without a root.
- **Mutating the close to read the config history:** `tally_close` holds no grant on it any more, so the battery dies with permission denied at C7, not at the named check. M60 instead pins fixed edges `'{30,60,90,120}'`, caught at C16b.
- **Testing a NULL `withdrawn_by` as `tally_app`:** without `app.user_id`, RLS hides the row, so the UPDATE touches 0 rows and nothing is refused. P9f runs as the owner with `app.user_id = ''`.
- **Python `str.replace` anchors written from memory:** the header line reads `--     write_off it recovers …`, not `--     the write_off …`. When an anchor misses, print `repr()` of the real lines.
- **Earlier sessions' failures still hold:**
  - withdraw by status, never DELETE;
  - the per-tenant head handshake;
  - pass the snapshot's stored edges;
  - lock both heads on a tenant move;
  - no temp tables under `tally_app`;
  - branch on `TG_TABLE_NAME`;
  - keep `PostgreSQL 16's rendering` on one line;
  - seal grants render argument names.

## Key Decisions

| Decision | Rationale |
|---|---|
| The cap is on the net of the write-off's whole same-customer tree, in [0, written off] | Guard the act, not the label: it is whatever aging nets into the write-off. It also lets a bounced recovery be re-recovered (Fable S1). |
| Only same-customer descendants count | Aging nets lineage only within a customer; a cross-customer row stands alone. |
| The loop bound is 1,000 and fails closed | Real chains are a few entries. A test can cross it cheaply (a 1,001 ring). |
| The close reads `tenants.receivables_aging_bucket_days`, not the history | App-written logs are not guards. At the close's instant, the live value *is* the value at that instant, and the snapshot stores it. |
| Withdrawal stays an operator's act and must name its user | It is undone by re-creating the same period, so it is not irreversible. Only irreversible acts earn the supervisor gate. Opus wanted the gate; Fable did not. |
| Two new race legs; the other race gaps Codex listed are accepted | Fable executed those orderings in r2 with no deadlock; the header states the one deadlock that exists. |

## Current State

**Working:** r3 applies strictly and the second run is skipped. Battery 147/147. Races CR1–CR12. Codex's r2 blockers are refused.
**Unknown:** the mutation result, and `tests/ci.sh` on r3.
**Uncommitted changes:** none after the wrap-up commit (the r3 draft, tests, findings, the brief with placeholders, the DECISION-LOG entry).
**Scratch DBs left:** `rv22r3` (r3 applied) and `rv22r3c` (races ran; it has commits). Drop both. The mutation runner drops `m22` itself.

## Code Context

```sql
-- AFTER INSERT triggers on account_ledger fire by name: enforce_ledger_lineage_acyclic, then enforce_write_off_recovery
public.enforce_write_off_recovery()      -- RETURN NULL; raises 23503 "names a write_off entry", 23514 "opposite sign" | "only a write_off_recovery names a write-off" | "R-02 cap"
public.enforce_ledger_lineage_acyclic()  -- c_max 1000; 23514 "returns to itself" | "does not reach an original within 1000 entries"
public.close_accounting_period(uuid, numeric, text) -- edges: SELECT t.receivables_aging_bucket_days FROM tenants t WHERE t.id = v_tenant
```

- `assert_periods_guard_invariants()` pins exact `pg_get_triggerdef` and `pg_get_constraintdef` strings. Capture them from a patched clone with `search_path` including `public`; the FK renders `REFERENCES account_ledger(id, tenant_id)` without a schema.
- The seal's grant list for `tally_close` is a sorted jsonb array. A dropped quote broke the apply once (`JSON data, line 1`).

## Resume Instructions

1. `git pull --ff-only` in both repos; check GBM for Kyle's pushes.
2. Drop the scratch DBs: `docker exec tally-pg psql -U tally -d postgres -c "DROP DATABASE IF EXISTS rv22r3" -c "DROP DATABASE IF EXISTS rv22r3c"`.
3. Run the mutations in the background: `python3 tests/v5.4.2-22/mutations-22.py > <scratch>/mut.out 2>&1`.
   - Expected: `61/61 caught`.
   - If a mutation is reported MISSED with an earlier check first: rename it to that check, or fix the guard. Never loosen the runner.
   - The exact label match may shift some old mutations (an `F2`-named one caught at `F2b`): rename those to the exact label.
4. `tests/ci.sh`. Expected: `ci: all pass`, 35 steps.
5. Freeze r3. Copy the four files to `*-frozen-r3.*`, write the diff, fill the brief's placeholders (md5s, the CI line, the mutation count), and write `review-brief-22-r3.md5`. Commit and push.
6. Launch round 3:
   - **Opus and Fable:** Agent `general-purpose`, model opus / fable, background, pointed at `review-brief-22-r3.md`. Each reads its own r2 report.
   - **Codex:** `PATH=~/.nvm/versions/node/v24.15.0/bin:$PATH codex exec -s workspace-write -C ~/code/tally-utility -o tests/v5.4.2-22/review/codex-r3-final.txt - < prompt`. The prompt is source-only, with probes in `codex-r3-probes/`.
7. Run Codex's probes on a clone of frozen r3, append the outputs to `codex-r3.md`, and fold the findings into r4, or ask Ryan to approve the mirror: one question, plain language, with a default.

## Warnings

- **Never edit the frozen review copies or tu.sql's mirrored body.** tu.sql is append-only and is mirrored only on Ryan's approval.
- **Revoke TEMP from PUBLIC, `tally_app` and `tally_core` after every `CREATE DATABASE … TEMPLATE`.**
- **Roles are cluster-wide.** `tally_close` exists; reviewers must not touch roles.
- **`tests/ci.sh --build` deletes the container** and every scratch database.
- **Codex runs source-only.** You run its probes, and check each probe's own error capture (r2 n7 misreported).
- **Never `git add -A` in gas-billing-memory** (`Clippings/`).
- **Ask Ryan one decision per message, in plain language, with a default.**
- **Commits go straight to main** in both repos.
- **Background reviewer reports truncate at about 4 KB.** Ask for the file.
- **Python output redirected to a file is block-buffered,** so a long `mutations-22.py` run shows nothing until it ends. Use `python3 -u` to watch progress.
