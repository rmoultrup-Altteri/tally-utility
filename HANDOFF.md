# Handoff: v5.4.1-01 LANDED — next is v5.4.1-02 (item 2.4), then Phase 4 Wave 1

**Generated**: 2026-08-20
**Branch**: tally-utility `main` (pushed, `92433ae`) · gas-billing-memory `ryan` (pushed, `294c500` — now 14 commits ahead of `origin/main`)
**Status**: Phase 2 is complete except item 2.4. Nothing in flight; nothing uncommitted.

## Goal

Bring `sql/tu.sql` (the only enforcement artifact — no application code exists) to parity with the spec corpus per `gas-billing-memory/application/schema-parity-plan.md`. Target: vanilla PostgreSQL on AWS. Ryan owns the schema.

## Completed (this session, 2026-08-20)

- [x] **Item 2.6** drafted — both halves of the plan's either/or: `meter_deployments_no_overlap_excl` (schema's first EXCLUDE, `btree_gist`, half-open `[install_date, removal_date)`) + `meter_readings.location_id` snapshot column via `trg_populate_reading_location` (removal/final reads → deployment closed on the read date; else covering deployment; else `meters.location_id`; never re-derived on UPDATE).
- [x] **-06 review carryover** drafted — `pga_monthly_reconciliations` `low_positive` / `gas_cost_nonnegative` / `recovered_nonnegative` CHECKs.
- [x] **`application/APPLICATION-CONTRACTS.md`** created (AC-1..AC-7) — the running list of what the schema requires of future application code; linked from CONTEXT.md. Add an entry whenever a patch lands something that assumes caller behavior.
- [x] **Second independent review round** (Fable + Codex) on 2.6 + carryover; all findings fixed or documented (see CHANGELOG 2026-08-20).
- [x] **Mirrored into `tu.sql`** (pure append, 12,279 → 12,997 lines; anchors 337/3600/3679 intact), **fresh container rebuild zero errors**, full battery re-run on the fresh build, DEPLOY-VERIFICATION updated (224 CHECKs / 1 EXCLUDE / 66 triggers / 474 indexes / 273 FKs).
- [x] **GBM side done**: CI-017/018/027/032/118/122 re-check text (all tokens unchanged), family-15 intro "four → three", parity-plan Phase 2 marked landed, ingestion Section AL, CHANGELOG. Committed + pushed `ryan`.

## Not Yet Done

- [ ] **`v5.4.1-02`** — item 2.4: `tenant_configuration_history` table + date-parameterised `get_partial_period_policy()` (model on `get_correction_rate_date()`), new Appendix A entry. Not started.
- [ ] **Kyle brief candidates that accumulated this session** (write before Phase 4 if convenient): (a) *how is an active meter relocated?* — `sync_meter_deployments()` ignores `location_id` edits while active; schema can't tell relocation from typo-fix (AC-7); (b) should the sync trigger take an explicit reinstall date rather than relying on `meters.start_date` (AC-1). Plus the 8 open briefs, A-8's brief, CI-029's Fp=1.0 CHECK.
- [ ] Phase 4 Wave 1 (A-4 → A-1 → A-3), then Wave 2 (A-20 → A-21, A-7).
- [ ] Phase 0.4 (non-blocking): Kyle's Opus-session patch archive.
- [ ] GBM `origin/main` catch-up (14 commits) — Ryan's call, never unprompted.

## Failed Approaches (Don't Repeat These)

- **Trusting the iteratively-patched container as a deploy test.** `CREATE EXTENSION IF NOT EXISTS btree_gist` worked all session in psql but failed the fresh build: tu.sql runs under `search_path = ''` (tu.sql:65) and needs `WITH SCHEMA public`. Any future statement that depends on search_path (CREATE EXTENSION, unqualified CREATE of anything) must be schema-qualified. **The fresh rebuild is mandatory before commit, not a formality.**
- **Reading a CI grade from the scenario file** (`invariant-scenarios/*.md`) — those are stale copies; the register is `canonical-invariants.md`. CI-032 was misgraded in the header that way until review caught it.
- **Mirror boundary**: the patch file has *two* `-- ====` banner lines in its header; the body starts after the second (the line before `-- Item 2.1`). Splitting at the first mirrors the whole header into tu.sql (wrong form; the -06 precedent omits the header).
- **Fixture NOT NULLs** (now in memory too): `service_locations` needs address_line1/city/state/zip; `service_orders` needs order_number+description; `import_jobs` needs initiated_by+error_handling_policy (enum — check `pg_get_constraintdef` first). Wrap negatives in `SAVEPOINT sp … ROLLBACK TO sp`.
- All prior traps still apply (hex-only UUIDs, never guess enum values, `invoices_check`'s location requirement, an active `meters` insert auto-creates deployment #1, no `-p` on `docker run`, zsh `echo ===` glob trap, `SendMessage` not `Agent` to resume a named reviewer, check a late-arriving review report against what's already fixed).

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| 2.6 lands **both** EXCLUDE and recorded column | Each alone leaves half the CI-027 defect; flagged as a widening in the header rather than landed silently. |
| EXCLUDE range is **half-open** `[)` | `sync_meter_deployments()` closes with `CURRENT_DATE` and reopens with `CURRENT_DATE`; `[]` would break same-day Pattern A reactivation. |
| In-place active-meter relocation gap: **documented (AC-7), not fixed** | Auto close+reopen fabricates a date; rejecting blocks typo corrections. Relocation vs correction is a product ruling → Kyle brief. |
| Removal/final reads prefer the deployment **closed on** the read date | The outgoing-premise read is the one that most needs correct attribution (CI-124); no-move final reads fall through unchanged. |
| CI-027 stays `partially-structurally-enforced`, led by AC-7 not nullability | Single-valued ≠ correct. Same discipline that reverted 2.2's over-grade last session. |
| CI-032 corrected to `partially-structurally-enforced` | Register re-graded it 2026-08-13; 2.6a closes only the temporal-guard half; nullable `replaces_meter_id` remains. |
| Carryover leaves `monthly_variance`/`deferred_balance_after` signed | Those carry the sign by design (-06 header); a supplier credit is a lower cost, never a negative one. |
| Two-reviewer pass before every mirror | Second round caught a wrong grade (H1) and a real attribution bug (M2) that live testing hadn't. |

## Current State

**Working**: `tu.sql` at v5.2.1 + v5.4.0-00→-06 + v5.4.1-01, 12,997 lines, deploys clean from `postgres/Dockerfile`. Container `tally-pg` is a **fresh build of the committed tu.sql** (for once, container == disk).
**Broken**: Nothing.
**Uncommitted**: None in either repo (GBM has only the untracked `Clippings/`, as always — never `git add -A` there).

## Setup Required

`docker build -t tally-postgres -f postgres/Dockerfile . && docker run -d --name tally-pg -e POSTGRES_PASSWORD=tally tally-postgres` (no `-p`).

## Resume Instructions

1. Read `schema-parity-plan.md` Phase 2 item 2.4 and the 3M item 3 source; read `get_correction_rate_date()` in tu.sql as the model. Draft `sql/v5.4.1-02-tenant-configuration-history.sql` with the same header form as -01.
2. Live-test, two independent reviews, **fresh rebuild**, mirror (banner + body after the second `-- ====` line), DEPLOY-VERIFICATION, GBM re-grades (CI-004/006/093 named by the plan) + Section AM + CHANGELOGs, commit both, push both.
3. Add any new caller obligations to `application/APPLICATION-CONTRACTS.md`.
4. Then Phase 4 Wave 1 starting with A-4.

## Warnings

- **tu.sql is APPEND-ONLY**; verify anchors 337/3600/3679 after every append.
- **Everything under `search_path = ''`**: schema-qualify any CREATE that isn't a table-bound object.
- **Never `git add -A` in GBM** (`Clippings/`).
- Every GBM canonical-data change needs a `wiki-ingestion-pending.md` section (next is **AM**) + both CHANGELOGs.
- Phase 3 judgment-gated items wait on their named questions; A-8 needs a Kyle brief; CI-029's CHECK stays parked; finance gate holds A-15 ledger parts and A-6 remainder.
- `regulatory_class` NOT NULL and `import_jobs.idempotency_key` NOT NULL both mean any future *populated* database needs a backfill (the -01 patch's own backfill handles idempotency_key).
- Texas-only launch remains the scope discipline.
