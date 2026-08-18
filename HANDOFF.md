# Handoff: Schema parity execution — Phase 0 complete, v5.4.0-00 shipped

**Generated**: 2026-08-18 (afternoon)
**Branch**: tally-utility `main` (remote `RyanMoultrup/tally-utility`, pushed) · gas-billing-memory working branch **`ryan`** (pushed; **`origin/main` is 6 commits behind `ryan`** — see Warnings)
**Status**: In Progress — Phase 0 of the schema parity plan complete; next is the app-role/GRANTs patch, then Phase 1

## Goal

Bring `sql/tu.sql` (the only enforcement artifact — no application code exists) to parity with the spec corpus in `gas-billing-memory`, per `gas-billing-memory/application/schema-parity-plan.md`. Ryan owns the schema now. Target: **vanilla PostgreSQL on AWS — no Supabase.**

## The project pivoted this week — read this first

The WU6 documentation corpus is **finished** (140 files, validated, 8 briefs open with Kyle — delivery done, answers pending; Ryan handles pinging Kyle out-of-band, do not chase this). The 2026-08-17 independent review (see `INVESTIGATION-BRIEF.md` and CHANGELOG) verified the corpus's factual layer and redirected effort to schema execution. **The old corpus-era handoff, with its full ~30-entry Failed Approaches list, is in git history at commit `785884b`** — consult it before doing any corpus-editing work.

## Completed (this session, 2026-08-17→18)

- [x] **Provenance established (from Ryan, load-bearing):** schema authored by Kyle + Claude Opus, never deployed with data anywhere; the one test run's machine died; `application/database/schema.sql` is a tables-only export for LLM parsing (**column-reference only, never an enforcement source**). No v5.3+ exists anywhere; CI-019's "v5.3" citations are now classifiable.
- [x] **tu.sql v5.2.1 verified deployable** — zero errors on fresh postgres:16 via `postgres/Dockerfile`; all objects confirmed from the catalog (59 tables / 49 triggers / 59 policies / 23 functions / 188 CHECKs / 352 indexes / 252 FKs / 58 RLS tables / 0 FORCE-RLS / 2 views + 4 matviews). Record: `sql/DEPLOY-VERIFICATION.md`. Two corpus findings independently confirmed: all FKs single-column; CI-116's missing FORCE-RLS.
- [x] **Grading freeze lifted** (register warning-block rule 4 rewritten): standing rule is version-stamped grades + each patch re-grades exactly the CI entries its header names.
- [x] **Patch v5.4.0-00 shipped**: Supabase substrate removed (`sql/v5.4.0-00-remove-supabase-substrate.sql`). Only `get_user_tenant_id()` and `is_platform_admin()` called `auth.uid()`; all 59 policies route through them. Now read `app.user_id` session GUC, fail-closed. Mirrored into tu.sql **with line counts preserved** (11,351 lines; register anchors 337/3600/3679 verified unmoved). Redeployed clean; runtime-tested (no ctx → NULL/false; operator → own tenant; platform_admin → true).
- [x] Parity plan written and maintained: `gas-billing-memory/application/schema-parity-plan.md` (Phases 0–4; 0 complete except 0.4).
- [x] D3-2 retraction brief delivered via `origin/main` push (2026-08-17); cover note for Kyle at `gas-billing-memory/application/configurable-rules/kyle-cover-note-d3-2.md`.
- [x] tally-utility gained its first remote and is fully pushed.

## Not Yet Done

- [ ] **NEXT: the app-role/GRANTs patch (v5.4.0-01).** RLS never applies to the table owner and 0 tables set FORCE, so **the 59 policies currently bind no one**. Define app role(s), GRANTs, and decide FORCE ROW LEVEL SECURITY (closes CI-116's gap). Open design question for Ryan: one app role, or separate app/admin/migration roles.
- [ ] **Phase 1: the ruled v5.4 backlog** — 13 items in five migration sets (meters & reads first: `rollover_point`, `meter_pressure_class`, `meter_skip_reason`, tamper columns) + A-11 substrate. Authority: `wu5-wu6-kyle-decisions-2026-07-10.md` Part 5.
- [ ] Phase 0.4 (non-blocking): ask Kyle for the Opus-session patch archive; the seven-bug list survives in tu.sql's header regardless.
- [ ] Kyle's answers to the 8 open briefs; the two queued correction commits (17 miscites, 4 column refs) stay parked behind that round-trip.

## Failed Approaches (Don't Repeat These)

- **Assuming `schema.sql`'s emptiness of constraints meant anything**: reasoned twice about what its zero CHECKs/triggers implied (first "condensed listing", then "the real DB may have no enforcement") → both wrong; it was a deliberately tables-only export → **ask Ryan about artifact provenance before reasoning from file contents**; three different stories about this one file were all plausible from inspection alone.
- **Host-port Docker run**: `docker run -p 5432:5432` → `Bind for 0.0.0.0:5432 failed: port is already allocated` (something local owns 5432) → run with no `-p` and use `docker exec tally-pg psql -U tally -d tally`.
- **Header edit that changed tu.sql's line count**: a rewrite grew the header by 2 lines, which would have shifted every register citation below it → caught by `wc -l`; recomposed to identical line count → **any tu.sql edit must preserve total line count; verify `wc -l` = 11,351 and spot-check anchors 337/3600/3679 after every edit**.
- **Org repo creation**: `gh repo create rmoultrup-Altteri/tally-utility` → GraphQL "RyanMoultrup cannot create a repository for rmoultrup-Altteri" → fell back to personal `RyanMoultrup/tally-utility`; transfer to the org is an org-admin action.
- *(Corpus-era list — grep hygiene, count verification, absence-claim discipline, cwd-chaining, validator scoping — lives in the `785884b` HANDOFF. Still binding for corpus edits.)*

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| **AWS-hosted vanilla PostgreSQL; Supabase removed** (Ryan, 2026-08-18) | Ryan's infrastructure call. Swap confined to two wrapper functions; zero policy churn. |
| RLS context = `app.user_id` session GUC, fail-closed | Matches the schema's existing `app.void_operation` GUC pattern; `current_setting(..., true)` → unset context denies everything. |
| tu.sql maintained **in place**, patches mirrored, line counts preserved | The register cites tu.sql line numbers everywhere; a pg_dump regen would invalidate them all for zero gain. Discipline documented in tu.sql's header. |
| tu.sql (not schema.sql, not a fresh dump) is canonical | It's what Kyle's audit and all 58 checked grades were graded against, and it deploys clean. schema.sql demoted to column-reference. |
| Freeze lifted, replaced by version-stamped grades | The freeze's premise (moving target, unknown owner) died with the provenance story. |
| Patch series named **v5.4.0-NN** (not v5.3) | The corpus consistently calls the ruled backlog "v5.4"; a real v5.3 would collide with CI-019's phantom v5.3 citations. |
| Cover note + plan committed to GBM branch `ryan` only | Ryan's explicit instruction; he controls when `main` (Kyle's branch) catches up. |

## Current State

**Working**: tu.sql v5.2.1+v5.4.0-00 deploys clean; container `tally-pg` running (up ~2h, ephemeral, schema-fresh on each start); both repos fully committed and pushed.
**Broken**: Nothing. Known gap by design: RLS policies bind no one until the app role exists (next patch).
**Uncommitted changes**: None (GBM's untracked `Clippings/` is deliberate — never commit it).

## Code Context

```sql
-- sql/tu.sql:535 and :570 (post v5.4.0-00) — every RLS policy routes through these
CREATE FUNCTION public.get_user_tenant_id() RETURNS uuid  -- NULL when app.user_id unset (fail-closed)
    AS $$ SELECT tenant_id FROM users WHERE id = current_setting('app.user_id', true)::uuid $$;
CREATE FUNCTION public.is_platform_admin() RETURNS boolean -- false when unset
-- Application contract: SET [LOCAL] app.user_id = '<users.id uuid>'; per connection/transaction.
-- users NOT NULL columns for fixtures: id, tenant_id, role, display_name, email (+defaults).
```

Non-obvious: `check_function_bodies = off` (preamble) is still required — pg_dump ordering puts these functions before `CREATE TABLE users`. Policies shaped `is_platform_admin() OR tenant_id = get_user_tenant_id()`.

## Resume Instructions

1. Read `gas-billing-memory/application/schema-parity-plan.md` — the live plan; Phase 0 status is current.
2. Draft `sql/v5.4.0-01-app-roles-and-grants.sql`: app role(s), GRANTs, FORCE ROW LEVEL SECURITY decision. **Ask Ryan the one-role-vs-several question first** (flagged in plan 0.5). Mirror into tu.sql preserving line count — FORCE-RLS lines are *additions*, so line numbers below WILL shift; if so, record the shift in the patch header and re-anchor the three canonical citations (337/3600/3679) in DEPLOY-VERIFICATION.md.
   - Expected: rebuild + rerun harness, zero error lines, then an RLS smoke test **as the app role** — cross-tenant SELECT returns 0 rows.
   - If policies don't bind: check the role isn't owner/superuser and FORCE-RLS/GRANTs applied.
3. Then Phase 1, meters-and-reads set (backlog items 1, 2, 8, 9). Per-patch loop: numbered file → mirror → rebuild → `docker logs tally-pg | grep -ci error` = 0 → update DEPLOY-VERIFICATION.md → re-grade the named CI entries in the register `(as of v5.4.0-NN)` → CHANGELOG entries in **both** repos → commit both, push (`git -C`, never cd-chains) → GBM pushes to `origin ryan`.

## Setup Required

Docker only. Harness: `docker build -t tally-postgres -f postgres/Dockerfile . && docker run -d --name tally-pg -e POSTGRES_PASSWORD=tally tally-postgres` (no `-p` — host 5432 is taken). Query via `docker exec tally-pg psql -U tally -d tally`.

## Warnings

- **GBM `origin/main` is 6 commits behind `ryan`** — Kyle reads `main`. Catch-up is Ryan's call: `git -C ~/code/gas-billing-memory fetch . ryan:main && git -C ~/code/gas-billing-memory push origin main`. Don't do it unprompted.
- **Never edit tu.sql without preserving its 11,351-line count** (or documenting the shift). Verify anchors 337/3600/3679 after every edit.
- **`Clippings/` in GBM is untracked on purpose** — it has been accidentally committed three times historically. Never `git add -A` in GBM.
- Every canonical-data change in GBM gets a `wiki-ingestion-pending.md` section (currently through **AD**) and entries in **both** CHANGELOGs.
- The 77 untested register entries (`requires-application-discipline` + `unenforced-gap`) are deliberately untested — their grades claim non-enforcement; don't audit them without cause.
- Judgment-gated schema items (plan Phase 3) wait on their named question — **do not draft DDL for them**; a drafted migration becomes the ruling by inertia.
- Texas-only launch remains the scope discipline.
