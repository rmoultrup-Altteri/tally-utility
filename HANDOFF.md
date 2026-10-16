# Handoff: wave 2 started — v5.4.2-22 (periods, close snapshot, GL mapping, aging, write-off recovery) r2 frozen, ready for review round 2

**Generated**: 2026-10-15 23:45
**Branch**: `main` in both repos, pushed at wrap-up. GBM `main` at `954c472` (`Clippings/` untracked on purpose: never commit it).
**Status**: In progress. -22 r2 is frozen and its brief is written. The three reviewers have **not** been launched for round 2.

## Goal

Reach the C# core build. Ryan's gate, in order:
1. schema parity with CI-001…CI-135 (**we are here**: 75 of 135 done, 59 open);
2. scenarios and a test strategy;
3. a phase plan;
4. build.

Wave 2 = -22 (periods and reporting, additive) and -23 (cash, meaning-changing).

## Completed (this session)

- [x] **Drift handled at resume.** Kyle's 3 pushes were fast-forwarded (roadmap decisions JSON, ui-concepts, GBM `kyle-decisions-2026-10-15-…`).
- [x] **The parity record (Ryan):** the tally-utility measurement is the single live record. GBM grades are frozen at v5.4.2-12.
  - tally-utility `5680e6f`: update section 2026-10-15. Headline REP+PROT 51, REP 24, PARTIAL 46, GAP 13, BLOCKED 0, N/A 1 (CI-036).
  - GBM `954c472`: preamble note, frozen status line, manifest sections BP and BQ.
- [x] **Wave 2 inventory:** `application/wave2-build-2026-10-15/source-inventory-wave2.md` (`a7ce6d0`).
- [x] **Q1 answered by Ryan ("yes, go with the default"), `9b996b0`.** Under R-05's add-only money, the status column stays, moves forward only, and each move names the add-only row behind it. This is in DECISION-LOG and builds in -23.
- [x] **`sql/v5.4.2-22-periods-snapshot-gl-aging.sql`, r2:** 1,648 lines, md5 `4049de7b97362cf08760250f2824bb79` (frozen copy `tests/v5.4.2-22/review/patch-22-frozen-r2.sql`).
  - `accounting_periods`: contiguous, born open; closed only by the close; the latest open one may be withdrawn by status.
  - `accounting_close_heads` (per-tenant `closed_through`).
  - The freeze on `account_ledger`, `payments` and `customer_credits`.
  - `close_accounting_period(uuid, numeric, text)`: SECURITY DEFINER owned by the new role **`tally_close`**; a supervisor's act.
  - `accounting_period_snapshots` and `_lines`.
  - `gl_account_mappings` with `gl_mapping_as_of()`.
  - `receivables_aging_as_of(tenant, on, recorded[, edges])`.
  - `tenants.receivables_aging_bucket_days` and `write_off_threshold_days`.
  - `write_off_recovery`; the loop-free lineage trigger.
  - `assert_periods_guard_invariants()`; `assert_seal_role_invariants()` re-issued with the third role.
- [x] **Review round 1** (`afa7b67` froze r1): Opus, Fable and Codex all "not yet". Every finding is folded into r2. See `tests/v5.4.2-22/review/review-findings-22-r1.md`. All 8 Codex probes were run by me and reproduced; outputs are appended to `codex-r1.md`.
- [x] **Tests (r2):**
  - `battery-22.sql`: 135 checks.
  - `races/close-22.sh`: CR1–CR10.
  - `mutations-22.py`: 52/52 caught.
  - `tests/ci.sh`: all pass with -22 PENDING (35 steps).
- [x] **Round-2 brief:** `tests/v5.4.2-22/review/review-brief-22-r2.md` (hashes filled), plus `diff-22-r1-r2.diff`.
- [x] **Roadmap:** parity 75/135, W2-Q1 answered, wave 2 in progress. Dates unchanged (likely ready 2027-06-16). The dashboard datasets are refreshed.

## Not Yet Done

- [ ] **Launch review round 2** of -22 (Opus, Fable, Codex). Then fold the results into r3 if needed. Mirror into tu.sql **only on Ryan's approval**, after all three say ready.
- [ ] **After the mirror:**
  - remove -22 from `PENDING` in `tests/ci.sh`;
  - re-grade the parity measurement (CI-048, CI-076, CI-110 at least);
  - add a GBM manifest section (BR);
  - write DEPLOY-VERIFICATION.
- [ ] **v5.4.2-23, cash:** M (counters derived, write-once; status per Q1), X (every reversal names its entry, opposite sign, capped; the void reverses what is left), A (applications per bill and charge, oldest first, operator override with reason, within-bill rule row), C (credit approvals), U (suspense receipts), L (agency pledges). The inventory sections hold the detail.
- [ ] **Reply to Kyle:** D-2 lives in Part 2 of `gas-billing-memory/application/kyle-decisions-2026-08-18-coda-items.md`. Not sent.
- [ ] **The -05 defect:** a non-estimated read inserted past `pending` fails on `meters_last_validated_actual_reading_id_fkey`.
- [ ] **-21 R9:** `line_item_carries_base` classifies at the period end. Fix: the date from the snapshot's `valid_at`, the knowledge from `now()`.
- [ ] **Possible R-03 scoping question for Ryan:** the label and import-mapping tables are still deletable.
- [ ] **Open:** whether to drop `pga_monthly_reconciliations.deferred_balance_after` (CI-036 is N/A).
- [ ] **Carried over:**
  - the backbilling tariff table;
  - the GitHub Actions bump;
  - the Florida 25-7.083 text;
  - the waiver-determination rewrite;
  - low-confidence measurement rows;
  - the -15 r8 follow-ups;
  - gate steps 2–4.

## Failed Approaches (Don't Repeat These)

- **Withdrawing a mistyped period by DELETE:** `tests/ci.sh` failed battery-21 and the retention invariant with `tally_app may delete or truncate accounting_periods, which is not in the deletable set (CI-014, v5.4.2-21)`. Use status `withdrawn` (stamped), and exclude it from the EXCLUDE with `WHERE (status <> 'withdrawn')`. See memory `correct-by-status-not-delete`.
- **Freezing by looking up the containing period:** no row to lock when no period exists, so a stale REPEATABLE READ writer slips past. A per-tenant head row that every writer takes FOR SHARE and the close takes FOR UPDATE is the handshake.
- **Recovery cap counting only `write_off_recovery` rows:** an `adjustment` naming the write-off reinstated it uncapped. Any row naming a write_off must be a recovery.
- **Aging that only roots entries with no parent:** a two-row lineage loop in one statement had no root, and its balance vanished. Refuse loops in an AFTER INSERT walk; aging also raises on uncovered entries.
- **Reproducing a snapshot from the recorded bucket setting:** a backdated `manual` history row, or a setting change in the close's own transaction, changed the recomputation. Pass the snapshot's stored edges (4-argument aging).
- **The close's sums filtered on `created_at <= instant` alone:** a superuser row with a future `created_at` was frozen uncounted. The close now refuses while such a row exists.
- **The freeze checking only NEW.tenant_id:** a pending payment moved to another tenant escaped the old tenant's closed books. Lock both heads in id order.
- **A temp table in the battery under `SET ROLE tally_app`:** `permission denied for schema pg_temp_N` (no TEMP). Stash values with `set_config('bat22.x', …, true)`.
- **`NEW.created_at` in a trigger shared by two tables:** `record "new" has no field "created_at"` on the lines table. Branch on `TG_TABLE_NAME`.
- **A wrapper comment split across lines:** battery-21 N3 greps `PostgreSQL 16's rendering` in `assert_seal_role_invariants()`'s source. Keep that phrase on one line when re-issuing it.
- **Granting a function by its bare signature in the seal list:** `seal_role_privileges` renders argument names (`p_tenant_id uuid, …`).

## Key Decisions

| Decision | Rationale |
|---|---|
| Q1: status stays a column, forward-only, each move names its row (Ryan) | Readers unchanged; DB guarantees no status change without money behind it; (b) derive-on-read would rewrite every reader |
| Freeze = per-tenant `closed_through`, which also freezes dates before the first period once it closes | Lock handshake (memory `count-guards-need-lock-handshake`); onboarding history is loaded before the first close |
| Closing is a supervisor's act; `tally_close` reads `users(id, role, tenant_id)` | Irreversible (guard the act) |
| A period closes only after its last day ends at UTC-12 | The caller's time zone must not close it early |
| Unbilled revenue is supplied to the close with its basis, or omitted | D-2: a reported figure, never a row; the schema cannot estimate |
| Aging is balance-forward, netted by lineage within a customer, newest debt left open | K-05 oldest-first seen from the debt side; per-bill aging waits for -23's applications |
| GL precedence: charge 8, class 4, territory 2, tax 1 | G1 asked for a stated precedence; different keys never tie |
| Mappings and withdrawals are stamped with `clock_timestamp()` | A lookup at an instant inside the writing transaction never changes afterwards (Codex S2) |

## Current State

**Working:**
- `tally-pg` runs the -21 build (`tally` = tu.sql md5 `3b1433a3…`, 40,652 lines).
- `tests/ci.sh` passes all 35 steps with -22 PENDING.
- The role `tally_close` now exists in the cluster, from the scratch runs.

**Broken:** nothing.
**Uncommitted changes:** none after the wrap-up commit.

## Code Context

```sql
public.close_accounting_period(p_period_id uuid, p_unbilled_revenue numeric DEFAULT NULL, p_unbilled_revenue_basis text DEFAULT NULL)
  RETURNS timestamptz   -- the recorded instant; definer owned by tally_close; RC only; supervisor
public.receivables_aging_as_of(p_tenant_id uuid, p_on date, p_recorded_at timestamptz[, p_bucket_days integer[]])
  RETURNS TABLE (customer_id, customer_number, customer_status, last_location_id, balance, bucket_index, bucket_from_days, bucket_to_days, amount)
public.gl_mapping_as_of(tenant, charge_source, charge_code, customer_class, territory_place_id, tax_jurisdiction_place_id, on, recorded) RETURNS uuid
public.enforce_accounting_freeze()          -- trigger arg = the date column; FOR SHARE on accounting_close_heads
public.assert_periods_guard_invariants()    -- 19 exact trigger strings + 18 exact constraint defs; refill with the capture script below
```

Non-obvious:
- `assert_periods_guard_invariants()` pins exact `pg_get_triggerdef` and `pg_get_constraintdef` strings. After changing a -22 trigger or constraint, re-capture them. The procedure was:
  1. replace both arrays' contents with `@@TRIGGERS@@` / `@@CONSTRAINTS@@`;
  2. trial-apply with `NULL` in their place;
  3. query the catalog;
  4. fill the arrays.

  The scratch script `capture22.sh` did this; it is gone with the session, so redo it inline.
- The mutation runner treats any earlier FAIL as a miss. Name each mutation for the first check that can catch it.

## Resume Instructions

1. Fetch both repos (`git pull --ff-only` in each; check GBM for Kyle's pushes).
   - Expected: tally-utility at the wrap-up commit.
2. `tests/ci.sh`.
   - Expected: `ci: all pass`, 35 steps.
   - If tally-pg is gone: `tests/ci.sh --build` (about 5 minutes).
3. Verify the frozen r2 hashes against `tests/v5.4.2-22/review/review-brief-22-r2.md`: patch `4049de7b…`, battery `2b7149d7…`, races `7af6f68a…`, mutations `0d91882c…` (`md5 -q tests/v5.4.2-22/review/*frozen-r2*`).
4. Launch round 2 in parallel:
   - **Opus and Fable:** Agent, `general-purpose`, model opus / fable, run in background. Point them at the r2 brief and tell them to write `<reviewer>-r2.md`; they read their own r1 report.
   - **Codex:** `PATH=~/.nvm/versions/node/v24.15.0/bin:$PATH codex exec -s workspace-write -C ~/code/tally-utility -o tests/v5.4.2-22/review/codex-r2-final.txt - < prompt`. The prompt is source-only, with probes in `codex-r2-probes/`.
   - Run Codex's probes on a clone of `patch-22-frozen-r2.sql` and append the outputs to `codex-r2.md`.
5. Fold findings into r3 (one revision per round), or if all three say ready, ask Ryan to approve the mirror (one question, plain language).

## Warnings

- **Never edit the frozen review copies or tu.sql's mirrored body.** tu.sql is append-only and is mirrored only on Ryan's approval.
- **Revoke TEMP from PUBLIC, `tally_app` and `tally_core` after every `CREATE DATABASE … TEMPLATE`.**
- **Roles are cluster-wide.** Reviewers must not create, alter or drop roles. `tally_close` already exists.
- **`tests/ci.sh --build` deletes the container** and every scratch database.
- **Codex runs source-only.** You run its probes.
- **Never `git add -A` in gas-billing-memory** (`Clippings/`).
- **Ask Ryan one decision per message, in plain language, with a default.** Walk tradeoffs in prose, not menus.
- **Commits go straight to main in both repos** (push without asking).
- **Background reviewer reports truncate at about 4 KB.** Ask for the file or for several short messages.
