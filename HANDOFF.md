# Handoff: Phase 2 COMPLETE (v5.4.1-01 + v5.4.1-02 landed) — next is Phase 4 Wave 1, A-4

**Generated**: 2026-08-20 (end of session)
**Branch**: tally-utility `main` (pushed) · gas-billing-memory `ryan` (pushed, `6cd8cbb` — 15 commits ahead of `origin/main`)
**Status**: Phase 2 fully complete. Nothing in flight; nothing uncommitted.

## Goal

Bring `sql/tu.sql` (the only enforcement artifact — no application code exists) to parity with the spec corpus per `gas-billing-memory/application/schema-parity-plan.md`. Target: vanilla PostgreSQL on AWS. Ryan owns the schema.

## Completed (this session, 2026-08-20)

- [x] **v5.4.1-02 (item 2.4) landed**: `tenant_configuration_history` (append-only key/value history of the 13 tenant policy columns + top-level `settings.*`, trigger-written on `tenants` INSERT/UPDATE, RLS+FORCE, backfill, `seq` tiebreaker, source-guard) + `get_partial_period_policy(uuid, timestamptz)` with REQUIRED `p_as_of`, NULL raises, **no live fallback**; one-arg form dropped. Two-reviewer round (consensus HIGH: first draft's live-column fallback reintroduced the time-blind bug on NULL/pre-history input — fixed). Mirrored (13,241 lines), fresh build zero errors, DEPLOY-VERIFICATION, AC-8/AC-9, GBM CI-004/006/093 re-checks + Appendix A-22 + Section AM.

- [x] **Item 2.6** drafted — both halves of the plan's either/or: `meter_deployments_no_overlap_excl` (schema's first EXCLUDE, `btree_gist`, half-open `[install_date, removal_date)`) + `meter_readings.location_id` snapshot column via `trg_populate_reading_location` (removal/final reads → deployment closed on the read date; else covering deployment; else `meters.location_id`; never re-derived on UPDATE).
- [x] **-06 review carryover** drafted — `pga_monthly_reconciliations` `low_positive` / `gas_cost_nonnegative` / `recovered_nonnegative` CHECKs.
- [x] **`application/APPLICATION-CONTRACTS.md`** created (AC-1..AC-7) — the running list of what the schema requires of future application code; linked from CONTEXT.md. Add an entry whenever a patch lands something that assumes caller behavior.
- [x] **Second independent review round** (Fable + Codex) on 2.6 + carryover; all findings fixed or documented (see CHANGELOG 2026-08-20).
- [x] **Mirrored into `tu.sql`** (pure append, 12,279 → 12,997 lines; anchors 337/3600/3679 intact), **fresh container rebuild zero errors**, full battery re-run on the fresh build, DEPLOY-VERIFICATION updated (224 CHECKs / 1 EXCLUDE / 66 triggers / 474 indexes / 273 FKs).
- [x] **GBM side done**: CI-017/018/027/032/118/122 re-check text (all tokens unchanged), family-15 intro "four → three", parity-plan Phase 2 marked landed, ingestion Section AL, CHANGELOG. Committed + pushed `ryan`.

## Not Yet Done

- [ ] **Phase 4 Wave 1, A-4** (bill-immutability / append-only enforcement: issued invoices, `account_ledger`, posted operational rows — generalize the -04/-05/-06 trigger pattern; `tally_app` + GRANT layer exists). Then A-1 (transaction-time pair), then A-3 (invoice_calculation_snapshots).
- [ ] **Flagged for a later Phase 2-style set**: `rate_schedules.partial_period_policy` (unchecked, read by `get_partial_period_policy`) duplicates `partial_period_policy_override` (CHECKed, read by nothing).
- [ ] **Kyle brief candidates that accumulated this session** (write before Phase 4 if convenient): (a) *how is an active meter relocated?* — `sync_meter_deployments()` ignores `location_id` edits while active; schema can't tell relocation from typo-fix (AC-7); (b) should the sync trigger take an explicit reinstall date rather than relying on `meters.start_date` (AC-1). Plus the 8 open briefs, A-8's brief, CI-029's Fp=1.0 CHECK.
- [ ] After Wave 1: Wave 2 (A-20 → A-21, A-7).
- [ ] Phase 0.4 (non-blocking): Kyle's Opus-session patch archive.
- [ ] GBM `origin/main` catch-up (15 commits) — Ryan's call, never unprompted.

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
| -02: `get_partial_period_policy()` has **no live-column fallback**; NULL `p_as_of` raises; pre-history → NULL | Consensus review finding: the COALESCE fallback reintroduced the time-blind bug on realistic input. Rule for all future temporal helpers. |
| -02: history bracket is transaction time, not valid time | Valid-time policy changes are A-1's mechanism; inventing a second one here would pre-empt it. CI-004 stays partial. |
| -02: backfill stamps observed value at `created_at`, flagged as approximation | With no live fallback, existing tenants must still resolve pre-deploy coordinates; every such row says so in `change_reason`. |
| Two-reviewer pass before every mirror | Second round caught a wrong grade (H1) and a real attribution bug (M2) that live testing hadn't. |

## Current State

**Working**: `tu.sql` at v5.2.1 + v5.4.0-00→-06 + v5.4.1-01 + v5.4.1-02, 13,241 lines, deploys clean from `postgres/Dockerfile` (66 tables / 229 CHECKs / 70 triggers). Container `tally-pg` is a **fresh build of the committed tu.sql** (for once, container == disk).
**Broken**: Nothing.
**Uncommitted**: None in either repo (GBM has only the untracked `Clippings/`, as always — never `git add -A` there).

## Code Context

```sql
-- Temporal helper contract (v5.4.1-02) — the model for anything A-1/A-3 adds:
get_partial_period_policy(p_rate_schedule_id uuid, p_as_of timestamptz) RETURNS text
--   p_as_of NULL -> RAISES; unknown schedule or pre-history coordinate -> NULL (engine must fail on NULL)
--   resolution: rate_schedules.partial_period_policy > history row (effective_from <= p_as_of, ORDER BY effective_from DESC, seq DESC) > nothing

-- History table shape:
tenant_configuration_history(id, seq identity, tenant_id, config_key, old_value jsonb, new_value jsonb,
    effective_from timestamptz, changed_by uuid, change_source onboarding|trigger|backfill|manual, change_reason, created_at)
--   scalars read back with  new_value #>> '{}';  SQL-NULL column values are stored as JSON null, not SQL NULL

-- Immutability trigger pattern (now proven 5x; A-4 generalises it):
CREATE TRIGGER <name> BEFORE UPDATE OR DELETE ON <table> FOR EACH ROW EXECUTE FUNCTION <raise_fn>();
--   add a BEFORE TRUNCATE ... FOR EACH STATEMENT twin (tally_app has no TRUNCATE grant, but the owner does)

-- Mirror step:
--   body starts after the header's CLOSING "-- ====" line; prepend the 4-line MIRROR banner; append to tu.sql; verify anchors 337/3600/3679
-- Fresh-build step (mandatory):
--   docker rm -f tally-pg; docker build -q -t tally-postgres -f postgres/Dockerfile .; docker run -d --name tally-pg -e POSTGRES_PASSWORD=tally tally-postgres
--   docker logs tally-pg 2>&1 | grep -c ERROR   -> expect 0
```

Durable records: decisions → `application/DECISION-LOG.md`; caller obligations → `application/APPLICATION-CONTRACTS.md`; per-patch verification → `sql/DEPLOY-VERIFICATION.md`. This file is rewritten every session — copy anything worth keeping into those before overwriting.

## Setup Required

`docker build -t tally-postgres -f postgres/Dockerfile . && docker run -d --name tally-pg -e POSTGRES_PASSWORD=tally tally-postgres` (no `-p`).

## Resume Instructions

1. Start Phase 4 Wave 1 with **A-4**: read Appendix A-4 in `canonical-invariants.md` (options (a) privilege revocation + SECURITY DEFINER procs vs (b) row triggers; the plan says (b)'s pattern is proven 3× and (a)'s infrastructure exists), CI-012/013/014, and the existing immutability triggers (`enforce_enrollment_customer_immutable`, the -05 dry-run guards, `enforce_pga_reconciliation_immutable`, `enforce_tenant_configuration_history_immutable`). Decide scope per table (which rows count as "issued/posted"), draft `sql/v5.4.2-01-…` with the -01/-02 header form.
2. Same loop: live-test, two independent reviews (ask them to fresh-load tu.sql + patch into a scratch DB), **fresh rebuild**, mirror (banner + body after the header's closing `-- ====`), DEPLOY-VERIFICATION, GBM re-grades + Section AN + CHANGELOGs, commit + push both.
3. Add caller obligations to `application/APPLICATION-CONTRACTS.md` (AC-10+).
4. Temporal-helper rule from -02, apply to anything A-1/A-3 adds: no live-value fallback, NULL coordinate raises, NULL result = unknowable.

## Warnings

- **tu.sql is APPEND-ONLY**; verify anchors 337/3600/3679 after every append.
- **Everything under `search_path = ''`**: schema-qualify any CREATE that isn't a table-bound object.
- **Never `git add -A` in GBM** (`Clippings/`).
- Every GBM canonical-data change needs a `wiki-ingestion-pending.md` section (next is **AN**) + both CHANGELOGs.
- Phase 3 judgment-gated items wait on their named questions; A-8 needs a Kyle brief; CI-029's CHECK stays parked; finance gate holds A-15 ledger parts and A-6 remainder.
- `regulatory_class` NOT NULL and `import_jobs.idempotency_key` NOT NULL both mean any future *populated* database needs a backfill (the -01 patch's own backfill handles idempotency_key).
- Texas-only launch remains the scope discipline.
