# Handoff: A-4 LANDED (v5.4.2-01 + -02 follow-up) — next is Phase 4 Wave 1, A-1

**Generated**: 2026-08-20 (end of A-4 + assessed follow-up)
**Branch**: tally-utility `main` (pushed) · gas-billing-memory `ryan` (pushed; 17 commits ahead of `origin/main`)
**Status**: A-4 fully complete. Nothing in flight; nothing uncommitted.

## Goal

Bring `sql/tu.sql` (the only enforcement artifact — no application code exists) to parity with the spec corpus per `gas-billing-memory/application/schema-parity-plan.md`. Target: vanilla PostgreSQL on AWS. Ryan owns the schema.

## Completed (this session)

- [x] **v5.4.2-01 (A-4) landed**: CI-014 generic `enforce_no_hard_delete()` on 33 tables (DELETE + TRUNCATE, loop-created, `REVOKE DELETE` from `tally_app`); CI-012 column-scoped `enforce_invoice_immutable` (issued = `NOT IN ('draft','held')` via `is_invoice_issued()`; void terminal + requires `voided_at`; no backward transitions; clean drafts deletable), line items follow parent, `invoice_events` append-only; CI-013 `account_ledger` INSERT-only, `invoice_applications` write-once reversal, identity-freeze/terminal guards on `payments`/`adhoc_charges`/`customer_credits`; 9 guards `ENABLE ALWAYS`; `void_invoice()` re-issued with `set_config('app.void_operation','false',true)` before RETURN.
- [x] Two concurrent independent reviews (Fable 2H/5M/5L, Codex 2M); every HIGH/MEDIUM fixed. Mirrored (13,241 → 14,030), fresh build zero errors, 83-check battery green on the fresh build, DEPLOY-VERIFICATION, AC-10..13, DECISION-LOG D-16..23, CHANGELOG.
- [x] **v5.4.2-02 (assessed follow-up) landed**: two post-landing assessments (Fable, Codex) → `void_invoice()` re-issued schema-qualified with `SET search_path = public, pg_temp` + fresh COMMENT; writing `status='void'` gated on the carve-out (any prior status, INSERT too); all 80 immutability guards `ENABLE ALWAYS`; **new rule: every patch must apply under `SET search_path = ''; SET check_function_bodies = on;`** (the Docker preamble masks unqualified function bodies — -01 had claimed cleanliness it didn't have). Reviewed (Fable 1M/4L, Codex 1H/1M/1L, all fixed), fresh build zero errors, 89/89, tu.sql 14,499.
- [x] GBM: CI-012 → structural, CI-013/014 → partial (boundaries stated), A-4 LANDED, new A-23, parity plan struck, Section AN, CHANGELOG.

## Not Yet Done

- [ ] **A-1** (transaction-time pair `recorded_at`/`recorded_until`, bi-temporal-decision §6) — read `gas-billing-memory/application/bi-temporal-decision.md` §6 and Appendix A-1; unlocks CI-001/002/005/011. Then **A-3** (invoice calculation snapshots, Option B, §2.3 DDL sketch).
- [ ] Flagged from A-4 (later factual-defect set): six SECURITY DEFINER functions with no pinned `search_path` (`get_correction_rate_date`, `get_effective_rate`, `get_user_tenant_id`, `is_platform_admin`, `should_charge_tax`, `validate_custom_fields` — the two tenant helpers are hijack targets); CHECK `status='void' ⇔ voided_at IS NOT NULL`; forward ordering among issued statuses; `rate_schedules` duplicate policy columns.
- [ ] **Ryan's judgment calls, listed by both assessors, untouched:** `pending` = issued; `due_date` frozen; clean drafts deletable / held never; `write_off`/`paid` non-terminal; `payments.status` default `posted`; whether to take the option-(a) SECURITY-DEFINER seal.
- [ ] Kyle brief candidates: active-meter relocation (AC-7); explicit reinstall date for `sync_meter_deployments()` (AC-1); SECURITY-DEFINER seal for the `app.void_operation` carve-out (A-23 item 1 — application architecture, may not be Kyle's); plus the 8 open briefs, A-8, CI-029.
- [ ] After Wave 1: Wave 2 (A-20 → A-21, A-7). Phase 0.4 non-blocking. GBM `origin/main` catch-up — Ryan's call.

## Failed Approaches (Don't Repeat These)

- **Fresh-loading through the Docker image as proof of `search_path = ''` safety** — `00_preamble.sql` turns `check_function_bodies` off. Test the patch FILE with `SET search_path = ''; SET check_function_bodies = on;` prepended (now recorded per patch in DEPLOY-VERIFICATION). `SET search_path = ''` on a definer function whose helpers are unqualified compiles and then fails at runtime — pin `public, pg_temp`.
- **Writing "corrected in place" about another file before editing it** — a reviewer diffed it.
- **Bare `%` in `format()`** and **`text[] || 'literal'`** in plpgsql — both compile, both fail at first RAISE. Use `%s` / `|| ARRAY['x']`.
- **Testing GUC-gated guards after `void_invoice()` in the same transaction** — `SET LOCAL` lingered (now fixed in the function, but keep negatives before the call anyway).
- **Filing a reproducible bypass as an "application contract" to avoid touching a big function** — both reviewers overruled it; re-issue the function.
- All prior traps still apply: fresh rebuild mandatory (search_path = ''); register not scenario files for grades; mirror body starts after the header's CLOSING `-- ====` (v5.4.2-01's was the third banner line, 235); fixture NOT NULLs in memory; `adhoc_charges.regulatory_class IN ('regulated','unregulated')`; hex UUIDs; never `git add -A` in GBM; `SendMessage` to resume a named reviewer.

## Key Decisions (durable copies in `application/DECISION-LOG.md` D-2026-08-20-16..23)

| Decision | Rationale |
|---|---|
| `pending` is issued | post-posting; `void_invoice()` already treats it as voidable-not-editable |
| invoice guard column-scoped | an issued bill keeps living in collections; freeze "what the customer saw" only |
| clean drafts deletable, nothing else | no soft path for drafts; `fk_adhoc_invoice` SET NULL means "clean" must be checked |
| CI-013 structural only for ledger/events/applications | the other tables are mutable by design (A-21's redesign) |
| GUC carve-out extended, named caller-settable, `void_invoice()` re-issued to clear it | consensus review; a GUC can't be a seal — SECURITY DEFINER routing is app architecture |
| CI-014 set enumerated (33), token partial | reference/config tables are A-1's retention discipline |
| `payments.status` default `posted` untouched | changing it decides intake design by inertia; AC-11 instead |

## Current State

**Working**: `tu.sql` at v5.2.1 + v5.4.0-00→-06 + v5.4.1-01/-02 + v5.4.2-01/-02, 14,499 lines; 66 tables / 229 CHECKs / 147 triggers (80 ENABLE ALWAYS) / 275 FKs; container `tally-pg` is a fresh build of the committed tu.sql.
**Broken**: nothing. **Uncommitted**: none (GBM has only untracked `Clippings/`).

## Code Context

```sql
-- Generic guard: add a table = add to the array in the v5.4.2-01 DO block (new patch), loop does trigger + REVOKE
-- Issued test everywhere: public.is_invoice_issued(status)  -- NOT IN ('draft','held')
-- Carve-out: current_setting('app.void_operation', true) = 'true'  -- set+cleared by void_invoice(); caller-settable (AC-12); also gates writing status='void'
-- Strict apply test (mandatory per patch): { echo "SET search_path = ''; SET check_function_bodies = on;"; cat sql/<patch>; } | docker exec -i tally-pg psql -U tally -d tally -v ON_ERROR_STOP=1 -f -
-- Frozen-column idiom: IF NEW.x IS DISTINCT FROM OLD.x THEN v_changed := v_changed || ARRAY['x']; END IF;  ... RAISE ... ERRCODE='restrict_violation'
-- Mirror: body after header's closing "-- ====" + 4-line MIRROR banner; anchors 337/3600/3679
-- Fresh build: docker rm -f tally-pg; docker build -q -t tally-postgres -f postgres/Dockerfile .; docker run -d --name tally-pg -e POSTGRES_PASSWORD=tally tally-postgres; docker logs tally-pg 2>&1 | grep -c ERROR  -> 0
-- psql: docker exec -i tally-pg psql -U tally -d tally
```

## Resume Instructions

1. Start **A-1**: read bi-temporal-decision §6 + Appendix A-1 + CI-001/002/005/011; decide table set and backfill shape; draft `sql/v5.4.2-02-…`. Temporal-helper rule stands: no live fallback, NULL coordinate raises, NULL result = unknowable.
2. Same loop: live-test → **strict standalone apply** → two independent reviews (fresh-load scratch DBs, strict prelude) → fresh rebuild → mirror → DEPLOY-VERIFICATION → GBM re-grades + Section AO + CHANGELOGs → commit + push both.
3. Add caller obligations to APPLICATION-CONTRACTS (AC-14+); decisions to DECISION-LOG.

## Warnings

- tu.sql APPEND-ONLY; anchors 337/3600/3679. Everything under `search_path = ''` — and PROVE it with the strict prelude on the patch file; the Docker build does not.
- Never `git add -A` in GBM. Every GBM canonical-data change needs an ingestion section (next **AO**) + both CHANGELOGs.
- A-1 will touch tables that now carry DELETE/UPDATE guards — any backfill that UPDATEs `account_ledger`/`invoice_events` must be written as inserts or done as owner with the guard consciously handled (they are `ENABLE ALWAYS`; `ALTER TABLE … DISABLE TRIGGER` is the only way and must be visible in the patch).
- Phase 3 judgment-gated items wait; A-8 needs a Kyle brief; finance gate holds A-15/A-6 remainder. Texas-only launch scope.
