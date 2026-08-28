# Handoff: A-1 landed (v5.4.2-03) — bi-temporal substrate on the seven reference tables; next is A-3

**Generated**: 2026-08-28 (session wrap — A-1 drafted, reviewed twice, mirrored, fresh-build verified, docs in both repos)
**Branch**: tally-utility `main` (committed + pushed) · gas-billing-memory `main` (committed + pushed — `ryan` was merged into `main` by the 2026-08-26 sessions; unrelated untracked `Clippings/` left alone)
**Status**: **A-1 DONE.** `sql/v5.4.2-03-bitemporal-substrate.sql` is mirrored into `sql/tu.sql` (14,499 → 16,245 lines, pure append; anchors 337/3600/3679 intact). Container `tally-pg` is a fresh build of the committed tu.sql. Phase 4 Wave 1 is now A-4 ✅ → A-1 ✅ → **A-3 next**.

## Goal

Bring `sql/tu.sql` (the only enforcement artifact — no application code exists) to parity with the spec corpus per `gas-billing-memory/application/schema-parity-plan.md`. This session closed A-1 per Kyle's rulings R-9…R-17 (`gas-billing-memory/application/kyle-decisions-2026-08-26-a1-bitemporal.md`). Next: **A-3** (invoice calculation snapshots, Option B — DDL sketch in `bi-temporal-decision.md` §2.3), which leans on this layer.

## Completed (this session)

- [x] Folded Kyle's rulings into `a1-bitemporal-design-review-2026-08-20.md` §5 (each fork: original question, ruling, where the patch implements it; §5.6 records R-18 as v5.5, not A-1).
- [x] **Drafted v5.4.2-03** (1,909 lines). Group 1: `rate_schedules` / `wna_zones` / `rate_items` → identity headers (immutable id/tenant/code/created_at; lifecycle `status`; CI-011 `version`) + `rate_schedule_versions` / `wna_zone_versions` / `rate_item_versions` (content moved, backfilled as flagged `backfill` rows at `created_at`; `current_rate` dropped; `rate_item_history` brackets migrated then retired read-only; `archive_rate_item_history()` a RAISE stub). Group 2: in-place `recorded_at`/`recorded_until` + `change_type`/`change_reason`/`changed_by`/`supersedes_id`/`closed_type`/`closed_reason`/`closed_by` on `rate_schedule_items`, `franchise_fee_rules`, `customer_tax_exemptions`, `wna_monthly_adjustments`; the three UNIQUEs that blocked same-date corrections → open-rows exclusion / partial-unique constraints. Shared machinery: `enforce_bitemporal_assertion()` (closed rows immutable; asserted rows accept only the close or the per-table lifecycle set; drafts free; **both stamps are `now()`, caller values replaced**; `backfill` not insertable), `assert_bitemporal_predecessor()` (same entity, same tenant, predecessor closed *as superseded*), `enforce_superseded_has_successor()` (DEFERRABLE, entity-scoped, asserted non-retracted successor required at commit), `enforce_reference_header()` (identity frozen; version +1 only; archive requires every open version to carry an expiry; archived terminal), `assert_reference_version()` (D1-1 optimistic check + row lock). Rulings: R-9 `service_type` versioned, full-span-only correction, reference falls back to the latest closed version; R-11 lock at `approved`; R-12 lock at `active`, DEFAULT → `pending_verification`, verifier CHECK; R-13 `industrial` removed, self-verifying; R-14 tolerate drafts + all three riders (archive-reason enum; draft **and archived** not assignable to meters/deployments; `expired`/`superseded` removed from status enums, `archived` needs an expiry); R-15 seven `*_as_of(…, p_valid_at, p_recorded_at)` lookups + `should_charge_tax(…, p_valid_at, p_recorded_at)` (no longer SECURITY DEFINER) + `get_partial_period_policy(uuid, date, timestamptz)`; `get_effective_rate` disabled; `get_correction_rate_date` COMMENT rewritten and search_path pinned; R-17 `service_type_change_basis` + `anomalies` row `reference_correction_review` when invoices exist. Six CASCADEs stripped; ten tables added to the CI-014 set; every new guard `ENABLE ALWAYS`; version tables bound to their header's tenant by composite FK.
- [x] **Verified**: strict standalone apply (`SET search_path = ''; SET check_function_bodies = on;`) clean on a seeded v5.4.2-02 container after the R-13 refusal fired on a seeded `industrial` row; re-applied ×3 (once after committed post-patch rows) — idempotent; **166-check battery green**; fresh rebuild zero init errors with exact catalog parity (69 tables / 194 triggers, 127 ENABLE ALWAYS / 283 CHECKs / 302 FKs / 7 EXCLUDE / 68 policies / 67 FORCE RLS / 333 functions / 507 indexes); patch re-applied over the mirrored build clean; 18-check smoke set green on the fresh build.
- [x] **Two independent adversarial reviews, two rounds each** (Fable `general-purpose`, Codex `codex:codex-rescue`, fresh-load scratch DBs). Round 1 found real defects (see Failed Approaches); round 2: both "sound enough to mirror".
- [x] Docs: `sql/DEPLOY-VERIFICATION.md` entry; `application/DECISION-LOG.md` D-2026-08-28-01…-15 (+ flagged, failed approaches, outcomes); `application/APPLICATION-CONTRACTS.md` AC-14…AC-17 (+ AC-8 amended); tally `CHANGELOG.md`. GBM: CI-001/002/035 → `structurally-enforced`, CI-011 → `partially-structurally-enforced`, CI-003/004/005 text updated (tokens unchanged; CI-003's revisit trigger corrected to "before the first calculation code", per R-16); Appendix A-1 LANDED (with the entity-FK vs provenance-FK sorting rule), A-3 and A-23 amended; parity plan A-1 struck; brief's DECISION-LOG note corrected; ingestion Section AQ; GBM `CHANGELOG.md`.
- [x] Memory: `tally-pg-readiness-wait` (Docker's two-phase init fools a `SELECT 1` probe).

## Not Yet Done

- [ ] **A-3** — invoice calculation snapshots (Option B, `bi-temporal-decision.md` §2.3 sketch; Appendix A-3). Design note already recorded in A-3's appendix text: the snapshot can cite `*_versions` row ids and the run's `(valid, recorded)` pair as provenance. Same loop as A-1 (below).
- [ ] Wave 2 (A-20 → A-21, A-7); the three still-unpinned SECURITY DEFINER helpers (`get_user_tenant_id`, `is_platform_admin`, `validate_custom_fields` — A-23); R-18's v5.5 sewer-linkage item; A-19 / A-5 / A-8 / `jurisdictions.wna_zone_id` copy A-1's pattern when they land.
- [ ] **Open for Ryan** (flagged, not changed): a raw `UPDATE … SET version = version + 1` bypasses `assert_reference_version()` — closing it is the option-(a) SECURITY-DEFINER seal; CI-003's GUC coordinate net must be revisited **before any bill-run calculation code** exists (R-16); one `service_type` correction over N brackets posts N `anomalies` rows; versions of a draft schedule are asserted immediately.
- [ ] Reviewer test artifacts (`seed-prepatch.sql`, `battery.sql`, `smoke-fresh.sql`) live only in this session's scratchpad — the battery needs pre-patch seed rows, so it runs on the upgrade path only. If a durable copy is wanted, it belongs in `tests/` (does not exist yet) — Ryan's call.

## Failed Approaches (Don't Repeat These)

- **Round-1 review defects in the first draft** — every one reproduced live, fixed by mechanism, re-verified: lineage/successor check entity-scoped on one table only (a "superseded" close satisfied by another entity's row silently left the entity with no current assertion); transaction time caller-supplied on both axes (2010-dated "corrections", erasure by `recorded_until = recorded_at`); `change_type = 'backfill'` as a post-patch born-closed door; a revoked exemption inserted beside the open active one kept the customer exempt; R-9 accepted a shifted valid bracket; R-17 bypassed by retract-then-`initial`; drafts satisfied "superseded"; re-apply broke after a post-patch `initial` row; headers unreconciled with archive; version rows not tenant-bound; `should_charge_tax` leaked across tenants as SECURITY DEFINER. **Rule confirmed again: the author's battery proves the design, not the absence of holes — two adversarial reviewers with fresh-load DBs before every mirror.**
- **Rejecting a same-transaction close as "zero-width erasure"** — blocks legitimate multi-step work and protects nothing once both stamps are server-set. Tolerated and documented instead.
- **Test-harness traps** (all cost a run each): psql `:var` is not substituted inside `$$…$$`; `SET CONSTRAINTS ALL IMMEDIATE` is sticky — pair with `… DEFERRED`; `UPDATE … RETURNING` cannot sit in a subquery; `SET ROLE tally_app` cannot write a superuser-owned temp table without a GRANT; `set_config('app.user_id', NULL)` stores `''`, which `get_user_tenant_id()` cannot cast — "no context" means unset.
- **Docker readiness**: wait for `PostgreSQL init process complete` in `docker logs`, then poll — a `SELECT 1` probe connects to the temporary init server and the seed runs against a half-built schema.
- **Patch-authoring traps**: `format('%:')` is not a specifier; a text-matched Python wrapper nested DO blocks when two INSERTs shared a header; comparing a uuid column to `jsonb ->> key` needs a cast; drop the dependent FK before the UNIQUE it uses.
- All prior tu.sql traps still apply (`application/DECISION-LOG.md` and prior HANDOFF versions): append-only file, fresh rebuild mandatory, strict-apply prelude per patch, register grades from `canonical-invariants.md` only, never `git add -A` in GBM, `SendMessage` to resume a named reviewer agent rather than respawning.

## Key Decisions (durable copies: `application/DECISION-LOG.md` D-2026-08-28-01…-15)

| Decision | Rationale |
|---|---|
| Retraction is a closing event (`closed_type = 'retracted'`), not an insert enum value | No inserted row can carry it; the reason lives on the closing side |
| Lineage points backwards (`supersedes_id` on the successor), close first, verified at commit per entity | Two open assertions over one valid point are forbidden, so the predecessor must close before the successor exists; a closed row is frozen |
| Transaction time is the database's (`recorded_at`/`recorded_until` forced to `now()`; `backfill` not insertable after the patch) | CI-001's subpoena-defence rationale needs a tamper-evident axis; both reviewers forged it in round 1 |
| Every valid-time change to an asserted row (revocation, expiry) is insert-and-close | An in-place `effective_end` makes "what did we believe on date X" wrong |
| The draft is the `rate_schedules` header (born `draft`, DEFAULT flipped); version rows have no draft phase | R-14 put drafts on the header; activation requires an open version, so a header cannot be born active |
| `expired`/`superseded` leave the status enums; archived reconciles with versions on all three headers | R-14 rider 3 — one column per kind of death (tx-time = `recorded_until`, valid-time = `expiry_date`) |
| R-17's review queue is an `anomalies` row | No generic queue table exists; `anomalies` is the operator work queue with RLS and the CI-014 guard |
| No `app.*` carve-out anywhere | The close is a recognisable row shape; nothing to arm, nothing to leak (the A-4 lesson) |

## Current State

**Working**: tu.sql 16,245 lines, committed and pushed; `tally-pg` = fresh build of it (zero init errors). Catalog: 69 tables / 194 triggers (127 ENABLE ALWAYS) / 283 CHECKs / 302 FKs / 7 EXCLUDE / 68 policies / 67 FORCE RLS.
**Broken**: nothing known. Reviewer residuals recorded, not open.
**Uncommitted**: nothing (GBM's untracked `Clippings/` is not ours).

## Code Context

The patch header (`sql/v5.4.2-03-bitemporal-substrate.sql` lines 1–180) is the contract: what landed, the drafting decisions, what review changed. For A-3, the shapes to build on:

```sql
-- every reference read is a two-axis lookup; a run resolves ONE pair and passes it everywhere (AC-15)
SELECT * FROM public.rate_item_as_of(p_rate_item_id, p_valid_at, p_recorded_at);        -- 0 rows = unknowable = hard error
SELECT * FROM public.rate_schedule_item_as_of(p_schedule_id, p_item_id, p_valid_at, p_recorded_at);
-- correction protocol (AC-14): version token first (group 1), close, then insert the successor
SELECT public.assert_reference_version('rate_items', :id, :version_read);
UPDATE public.rate_item_versions SET recorded_until = now(), closed_type = 'superseded', closed_reason = '…' WHERE id = :old AND recorded_until IS NULL;
INSERT INTO public.rate_item_versions (…, change_type, change_reason, supersedes_id) VALUES (…, 'correction', '…', :old);
-- A-3's snapshot should cite the *_versions ids it read plus (p_valid_at, p_recorded_at) — that is the provenance CI-015 wants
```

## Resume Instructions

1. Read `gas-billing-memory/application/bi-temporal-decision.md` §2.3 (Option B DDL sketch) and Appendix A-3 / CI-015 in `canonical-invariants.md`; check `schema-parity-plan.md` Wave 1 for anything A-3 must cite.
2. Draft `sql/v5.4.2-04-…` (or next number) for A-3. Same loop: live-test on a seeded container → strict standalone apply (prelude mandatory, apply twice) → two independent reviews (fresh-load scratch DBs; use `general-purpose` for the Fable reviewer — `architect` has no Bash — and `codex:codex-rescue`; expect a round 2) → fresh rebuild with catalog parity → mirror (body starts after the header's last `-- ====` line) → DEPLOY-VERIFICATION → register re-grade of exactly the CIs the header names (CI-015 at minimum) → Appendix A-3 → DECISION-LOG / APPLICATION-CONTRACTS → ingestion section → both CHANGELOGs → commit + push both repos.
3. Before the first bill-run calculation code lands (whenever that is): revisit CI-003's GUC coordinate net (R-16).

## Warnings

- tu.sql APPEND-ONLY; anchors 337/3600/3679. Everything under `search_path = ''` — prove it with the strict prelude on the patch file; the Docker build does not.
- Wait for `PostgreSQL init process complete` before touching a freshly run container.
- Never `git add -A` in GBM.
- The seven bi-temporal tables reject every in-place content edit and every DELETE — fixtures for later patches must follow AC-14/16/17 (schedules born draft → version → activate; exemptions verified into `active`; WNA approved with an approver).
- Phase 3 judgment-gated items wait; A-8 needs a Kyle brief; finance gate holds A-15/A-6 remainder. Texas-only launch scope.
