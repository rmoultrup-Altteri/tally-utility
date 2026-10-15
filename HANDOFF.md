# Handoff: v5.4.2-21 mirrored (wave 1 built: retention, bill-line arithmetic, lineage, the void's reversal, Cognito binding); R1 decided

**Generated**: 2026-10-14 22:00
**Branch**: `main` at `d584e61`, pushed. gas-billing-memory `main` at `11ce5c5` (`Clippings/` uncommitted on purpose: never commit it).
**Status**: Ready for the next piece. Nothing is in review, nothing pending in CI (`PENDING=()`).

## Goal

Reach the C# core build. Ryan's gate, in order:
1. schema parity with CI-001…CI-135 (**we are here**);
2. scenarios and a test strategy;
3. a phase plan;
4. build.

## Completed (this session)

- [x] **R1, the caller identity (decided by Ryan).** The database trusts the app's Cognito-verified identity; there is no database-side session.
  - **AC-43** (`application/APPLICATION-CONTRACTS.md`): `app.user_id` is set only from the verified token's `sub`, with `SET LOCAL`, in one middleware path. It is never resolved by email.
  - Logged in `application/DECISION-LOG.md`.
- [x] **The void's reversal (decided by Ryan: "yes, go with the default").**
  - A posted bill (`first_issued_at` set) must have its charge entry, and the reversal names it; with none, the void is refused.
  - A never-posted bill (voided from `held`) writes no ledger entry.
- [x] **`sql/v5.4.2-21-wave1-lineage-arithmetic-retention.sql`**, r4, 1,468 lines, md5 `649db2b7094e585adde761f69a89a126`.
  - **Inventory:** `application/wave1-build-2026-10-14/source-inventory-21.md`.
  - **Review:** four rounds (`tests/v5.4.2-21/review/`, findings files r1–r3). r4: Opus, Fable and Codex all ready.
  - **Mirrored:** `sql/tu.sql` 39,349 → **40,652** lines, md5 `3b1433a315ecc97be284525333185932`.
  - **Build check:** a fresh build with zero init errors. Its `pg_dump --schema-only` (with privileges) is identical to a patched clone of the -20 build. `tests/ci.sh --build` passes 30/30. `DEPLOY-VERIFICATION.md` has the entry.
- [x] **Tests:**
  - `tests/v5.4.2-21/battery-21.sql`, 143 checks;
  - `races/labels-21.sh`, 9 cases (LR1–LR7, LR2b, AR1);
  - `mutations-21.py`, 68/68;
  - batteries -10, -11, -13, -15, -19 and -20, and the -20 races, adjusted (see the patch header).
- [x] **CI** has new steps: battery-21, races -21, the retention invariants and the wave-1 guard invariants. `PENDING` markers can now be `table.column`.

## Not Yet Done

- [ ] **Update GBM for -20 and -21** (two patches behind):
  - CI-011, CI-014, CI-016 and CI-017 grades;
  - A-23 item 1;
  - AC-12, AC-42 and AC-43 in the parity docs and `canonical-invariants.md`;
  - an ingestion-manifest section per patch (memory `log-changes-for-wiki-ingestion`).
- [ ] **Reply to Kyle** with where D-2 lives: Part 2 of `gas-billing-memory/application/kyle-decisions-2026-08-18-coda-items.md`. Not sent.
- [ ] **Wave 2** of `application/step1-sequencing-2026-10-13.md` (finance-released structures and cash). Kyle's answers also release A-8 tax jurisdictions and the franchise-fee rework.
- [ ] **The -05 defect** (Fable -19 r1 N6): a non-estimated read inserted past `pending` fails on `meters_last_validated_actual_reading_id_fkey`. It needs its own small patch.
- [ ] **-21 residual R9:** `line_item_carries_base` still classifies at the period end, not a correction's elected date. Fix it by the same rule: the date from the snapshot's `valid_at`, the knowledge from `now()`.
- [ ] **Carried over:**
  - the backbilling tariff table;
  - the GitHub Actions bump (`checkout@v4`, `setup-python@v5`, Node 20 warnings);
  - the Florida 25-7.083 text;
  - the waiver-determination rewrite;
  - low-confidence measurement rows;
  - the -15 r8 follow-ups;
  - step 2 onward not started.

## Failed Approaches (Don't Repeat These)

- **`coalesce(v_calc IN (...), false)` for "is this rider per unit":** when no version is visible (none effective at the date, or another tenant's item hidden by RLS) it reads "unknown" as "fixed", and the line issues with no figures. Refuse when `v_calc IS NULL`.
- **Classifying at `(period_end, now())`:** a correction priced at an elected rate date was misread (Codex r1 B2).
- **Classifying at the snapshot's `(valid_at, recorded_at)`:** `recorded_at` is the caller's to pick inside `[created_at, now()]`, so a backdated instant hid a retracted classification (Fable r2 B1). Use `(valid_at, now())` (memory `date-from-snapshot-knowledge-from-now`).
- **Guarding only the label DELETE:** an in-use label was renamed or re-pointed (`field_key`, `entity_type`, `tenant_id`, `type_key`) and then deleted, or simply left renamed. The keys are now write-once.
- **A write-once Cognito binding with no rule on who sets it:** an operator bound its second account to an unbound tenant_admin and became a supervisor.
- **Supervisor-only on the platform admin:** a tenant_admin revived a platform admin of its tenant.
- **Guarding `is_active` but not `role`:** a role-only demotion switched any administrator off, even by an operator. Removing power through any column is the act to guard.
- **A combined OR across both label tables' columns in one plpgsql expression:** the error was `record "new" has no field "type_key"`. Branch per table.
- **A mutation runner that counts the first FAIL:** a weak earlier check caught M12/M16 for the wrong reason. Put the stronger check first (K3a2, K3d2).
- **A wait loop that grep'd the Codex log for `error:`:** it matched Codex's own tool output and ended early. Wait on the `-o` file only.
- **Battery fixtures that reset `updated_at`:** the BEFORE `set_updated_at` trigger overwrites it. Use `SET LOCAL session_replication_role = replica` for that one statement.
- **`refuses_at` on another tenant's row as `tally_app`:** RLS hides it, so the result is "accepted" (zero rows). Target the caller's own tenant.

## Key Decisions

| Decision | Rationale |
|---|---|
| R1: trust the app's Cognito-verified identity (Ryan) | A compromised app server has the DB credentials anyway; a session table only narrows which users it can claim. Bugs are covered by one middleware path and `SET LOCAL` |
| A supervisor binds identities, switches users and demotes admins; a platform admin does so for platform admins | Guard the act. A user is bound when a supervisor provisions it (Cognito admin create returns the sub). Reported to Ryan |
| A gas rider needs no commodity rate | It is the usage line's figure; a rider's rate is `rate`. Reported to Ryan |
| Rate dependencies are retired, not deleted | The table had no status; no-hard-delete would have frozen a wrong dependency forever |
| One void reversal per entry; `invoice_void` if and only if `void_reversal` | Guard the act, not the label; it narrows -21 R2 cheaply |
| The label guard: SHARE lock, READ COMMITTED only, 5 s lock wait | A no-writer-side handshake. It is a deletion-time check, not referential integrity (LR2b) |
| The -20 `:"DBNAME"` line is left in tu.sql | Mirrored bodies are never edited; -21 carries the `current_database()` form |

## Current State

**Working:**
- `tally-pg` runs the **-21 build**: `tally` = tu.sql md5 `3b1433a3`.
- `tests/ci.sh` passes 30 steps.
- TEMP is revoked for `tally_app`, `tally_seal` and `tally_void`.

**Broken:** nothing.
**Uncommitted changes:** this HANDOFF and the CHANGELOG entry (committed at wrap-up). GBM: `Clippings/`, untracked, never commit.

## Code Context

```sql
public.invoice_line_arithmetic_gap(p_line invoice_line_items, p_valid_at date, p_recorded_at timestamptz) RETURNS text  -- NULL = complete
  -- called by enforce_invoice_line_arithmetic() (deferred, issuance only) as gap(line, snapshot.valid_at, now())
public.enforce_custom_label_unused()        -- BEFORE DELETE on both label tables; SHARE lock, 5 s lock_timeout saved and restored
public.enforce_custom_label_key_frozen()    -- BEFORE UPDATE; keys write-once for every role
public.enforce_user_binding_by_supervisor() -- BEFORE INSERT OR UPDATE OF cognito_sub, is_active, role; tally_app only
public.enforce_user_cognito_sub_write_once()
public.assert_no_hard_delete_invariants()   -- CI
public.assert_wave1_guard_invariants()      -- CI; exact trigger strings (PostgreSQL 16 rendering)
void_invoice(...)                           -- Step 2.5: charge lookup by tenant + customer + reference; first_issued_at decides posted
```

## Resume Instructions

1. Fetch both repos:
   ```
   cd ~/code/tally-utility && git pull --ff-only
   cd ~/code/gas-billing-memory && git fetch && git log --oneline HEAD..origin/main
   ```
   - Expected: tally-utility at `d584e61` plus the wrap-up commit. Kyle may have pushed to GBM (memory `fetch-gbm-before-orienting`).
2. `tests/ci.sh`.
   - Expected: `ci: all pass`, 30 steps.
   - If tally-pg is gone: `tests/ci.sh --build`, about 5 minutes.
3. Do the GBM update for -20 and -21 (bookkeeping, no decision needed).
4. Then ask Ryan which comes next: wave 2, the -05 defect, or R9.
   - One decision, in plain language, with a default (memory `one-decision-at-a-time-plain-language`).

## Warnings

- **Never edit the frozen review copies or tu.sql's mirrored body.** tu.sql is append-only and is mirrored only on Ryan's approval.
- **Revoke TEMP from PUBLIC, `tally_app` and `tally_core` after every `CREATE DATABASE … TEMPLATE`.**
- **Roles are cluster-wide.** Reviewers must not create, alter or drop roles.
- **`tests/ci.sh --build` deletes the container,** and every scratch database with it. Dump anything you need first.
- **Codex runs source-only** (no Docker): `PATH=~/.nvm/versions/node/v24.15.0/bin:$PATH codex exec -s workspace-write -C <repo> -o <out> - < prompt`. You run its probes on a clone and append the outputs.
- **Never `git add -A` in gas-billing-memory** (`Clippings/`).
- **Ask Ryan one decision per message, in plain language.**
