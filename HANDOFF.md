# Handoff: Phase 2 in progress — v5.4.1-01 drafted (2.1/2.2/2.3/2.5), reviewed, fixed; 2.6 + carryover remain

**Generated**: 2026-08-19 (late evening)
**Branch**: tally-utility `main` (pushed, `acb41cd`) · gas-billing-memory working branch **`ryan`** (pushed, `14f1728` — **untouched this session**, still 13 commits ahead of `origin/main`)
**Status**: In Progress — patch file drafted, live-tested, and independently reviewed for 4 of 6 planned items; NOT yet mirrored into `sql/tu.sql`; NO GBM-side documentation done yet

## Goal

Bring `sql/tu.sql` (the only enforcement artifact — no application code exists) to parity with the spec corpus per `gas-billing-memory/application/schema-parity-plan.md`. Target: vanilla PostgreSQL on AWS. Ryan owns the schema. Phase 1 (Kyle-ruled work) is complete as of last session; this session is Phase 2 — six low-controversy "factual-defect hardening" items, patch-split into `v5.4.1-01` (five items + a carryover) and `v5.4.1-02` (item 2.4 alone, not started).

## Completed (this session, 2026-08-19 evening)

- [x] **Decided the Phase 2 patch split** (confirmed the plan's own candidate): `v5.4.1-01` = items 2.1, 2.2, 2.3, 2.5, 2.6 + the two-reviewer v5.4.0-06 carryover (PGA threshold positivity/non-negativity CHECKs); `v5.4.1-02` = item 2.4 alone (`tenant_configuration_history` + date-parameterised `get_partial_period_policy()` — adds a table, changes a function signature, kept separate).
- [x] **Drafted `sql/v5.4.1-01-factual-defects-1.sql`** (848 lines, NOT yet mirrored into `tu.sql`) — items 2.1, 2.2, 2.3, 2.5 of 2.6. Each item's full source citations, drafting decisions, and CI-entry grading calls are in the file's own header — read that before touching it further. Summary:
  - **2.1** — two new CHECK constraints on `service_orders` (`service_orders_final_read_referents_check`, `service_orders_incident_location_check`): `final_read` now requires customer+location+meter; `tamper_response`/`damage_repair` require location. `customer_complaint`/`adjustment`/`other` deliberately left unconstrained, stated via `COMMENT ON CONSTRAINT`. Source: 3M item 7.
  - **2.2** — `import_jobs.idempotency_key` NOT NULL, backed by trigger `trg_populate_import_job_idempotency_key` / function `populate_import_job_idempotency_key()`: derives `<filename>:<hash>:<preview|commit>` when the caller doesn't supply a key, falls back to the job's own `id` when no file is present. Fixes the preview/commit key collision as a side effect. Source: 3M items 2 and 8, CI-118.
  - **2.3** — cycle guards (REJECT, not log) on three self-referencing lineage columns: `check_landlord_customer_cycle()` / trigger `landlord_customer_cycle`; `check_service_order_parent_cycle()` / trigger `service_order_parent_cycle`; `check_import_staging_dependency_cycle()` / trigger `import_staging_dependency_cycle` (BFS over a visited-set — the only one of the three not FK-backed). Also added `import_staging_job_row_number_key` UNIQUE(import_job_id, row_number), load-bearing for the third guard's lookup. Source: bulk-data-import-with-validation.md's "cycle-guard theme" finding.
  - **2.5** — `account_ledger` gets `reverses_ledger_entry_id` (self-referencing FK) + `reversal_reason` (text), nullable, not paired by a CHECK. `void_invoice()` (tu.sql:1126) rewritten in place to populate both when posting a `void_reversal` row — reproduced faithfully with exactly two additions (a lookup step + two INSERT columns + one return-payload key). Source: 2026-08-13 re-grade finding, CI-017/CI-018.
- [x] **Live-tested every item against the running `tally-pg` container** as each was drafted — positive and negative fixtures for every constraint/trigger, all wrapped in `BEGIN...ROLLBACK` except the iterative "apply the whole file" runs (which left the DDL live on the container, harmless/ephemeral). Full idempotency re-run confirmed clean after every item.
- [x] **Ran two independent adversarial reviews** (one Fable-model agent, one Codex-rescue agent — same methodology precedent as the -06 patch) against the drafted portion. Both confirmed all four items' DDL does what its header claims, all GBM citations check out verbatim, no SQL injection surface, no RLS/privilege regression, `void_invoice()`'s SECURITY DEFINER cross-tenant check intact.
- [x] **Fixed the findings both reviews converged on or that were independently confirmed real** (commit `acb41cd`):
  - **HIGH (Fable-only, real bug)** — the 2.3c `import_staging` cycle guard fired only on `UPDATE OF depends_on_row_numbers`; since the graph's edges key on `row_number` (not FK-protected, freely updatable), an `UPDATE` relabeling a row's own `row_number` (or moving it to another `import_job_id`) could complete a cycle the guard never re-checked. Fixed: trigger now also fires on `UPDATE OF row_number, import_job_id`.
  - **MEDIUM (Fable-only)** — the BFS's 10,000-node visited-cap silently `RETURN NEW`'d instead of raising, contradicting the patch's own stated philosophy for the other two guards. Fixed: now raises.
  - **Consensus (Fable MEDIUM, Codex HIGH)** — item 2.2's header originally re-graded CI-118 forward to unqualified `structurally-enforced`. Both reviewers independently found and live-reproduced the same hole: the `id`-fallback only engages when filename+hash are both NULL, but nothing requires a csv/excel import to populate them, so two file-less/hash-less imports of the same logical file both insert cleanly with no duplicate-detection. Reverted: CI-118 stays at `partially-structurally-enforced`; header rewritten to explain why, citing CI-117's own "when set" hedge as the precedent.
  - **Documented, not fixed** — all three cycle guards race under concurrent transactions (plain MVCC reads, no locking); flagged in the header as a known limitation and candidate for a future item, not silently left undocumented. Also noted (consistency, not a new fix): `account_ledger_reverses_ledger_entry_id_fkey` has the same not-tenant-scoped shape already flagged out-of-scope for the landlord FK.
  - Re-verified post-fix: the row_number bypass repro now correctly rejects, no regressions on any previously-passing scenario, full patch file still re-applies idempotently with zero errors.

**Verified current container state**: `tally-pg` has the full `v5.4.1-01` draft (items 2.1/2.2/2.3/2.5, post-fix) applied live from iterative testing — but this is NOT reflected in `sql/tu.sql`, which is still at the v5.4.0-06 state (12,279 lines) on disk. The container is ephemeral and schema-fresh on rebuild; don't rely on its current state persisting.

## Not Yet Done

- [ ] **Item 2.6** — `meter_readings` service-point premise (CI-027 re-grade finding): either a recorded service-point column or an EXCLUDE constraint on `meter_deployments` preventing temporal overlap. Not started. If the EXCLUDE route is taken, it's the schema's **first** exclusion constraint anywhere — needs `btree_gist`; check the Dockerfile preamble supports it before committing to that approach.
- [ ] **The v5.4.0-06 review carryover** — mirror `pga_monitoring_settings_low_positive_check` onto `pga_monthly_reconciliations` (positivity CHECK on `low/medium_threshold_pct_applied`, the consensus defect from the prior session's two-reviewer -06 review) + non-negativity CHECKs on `actual_gas_cost`/`pga_recovered_revenue`. Not started — was queued to ride along with `v5.4.1-01` but not yet drafted.
- [ ] **Once 2.6 + carryover land, run the full per-patch loop that hasn't happened yet for ANY of this session's work**: mirror into `tu.sql` (pure append; verify anchors 337/3600/3679), rebuild the container fresh from `postgres/Dockerfile` (zero errors), re-run all positive/negative tests against the fresh build (not just the iteratively-patched live container), re-grade the exact CI entries named in the header (CI-122 re-check, CI-118 re-check confirming `partially-structurally-enforced`, CI-017/CI-018 re-check, none for 2.3), DEPLOY-VERIFICATION § + counts, GBM ingestion Section **AL** (queue is through AK), CHANGELOGs both repos, commit both, GBM push to `origin ryan`.
- [ ] **GBM-side documentation is entirely undone**: no ingestion log entry, no CI re-grade/re-check text written into `canonical-invariants.md`, no family-15 intro correction. GBM repo is untouched this session (still `14f1728`).
- [ ] `v5.4.1-02` (item 2.4 — `tenant_configuration_history` + date-parameterised `get_partial_period_policy()`) — not started, separate patch.
- [ ] Then Phase 4 Wave 1 (A-4 → A-1 → A-3) per the already-sequenced plan.
- [ ] Kyle briefs outstanding: the 8 open briefs; candidate brief needed for A-8 before its DDL; CI-029's Fp=1.0 CHECK still parked with Kyle.
- [ ] Phase 0.4 (non-blocking): Kyle's Opus-session patch archive.
- [ ] GBM `origin/main` catch-up — Ryan's call, never unprompted.

## Failed Approaches (Don't Repeat These)

- **Sending a message to a named subagent by that literal name when a duplicate might exist**: mid-session, a stray `Agent({subagent_type: "fork", name: "fable-review"})` call (meant to be a `SendMessage`) spawned a *second*, unrelated agent that happened to reuse the name `fable-review`. `SendMessage({to: "fable-review", ...})` still routed correctly to the original reviewer (bare name resolution favors the live original in this harness), but it was a close call — the fix is to use `SendMessage` to resume a named agent, never `Agent` with a matching `name` field, which creates a new agent rather than resuming one.
- **Trusting the first delivery of a subagent's report as complete**: `fable-review` sent only an `idle_notification` (no report body) after finishing; a follow-up prompt was needed to get the actual findings. A second, near-identical copy of the same report arrived later (a duplicate delivery, not new findings) — don't re-act on a report that matches one already actioned; check line numbers/wording against what's already fixed before treating it as new.
- All prior-session traps still apply (non-hex UUIDs, guessing enum values without checking `pg_get_constraintdef` first, `invoices_check`'s location requirement, `meter_deployments.deployment_number` auto-creating deployment #1, no `-p` on the Docker run, zsh's `echo ===` glob trap).

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| **Patch split**: `v5.4.1-01` = 2.1/2.2/2.3/2.5/2.6 + -06 carryover; `v5.4.1-02` = 2.4 alone | 2.4 adds a table and changes a function signature; the other five are narrow, independently-testable CHECK/trigger/column additions. |
| **2.1**: `final_read` requires customer+location+meter (all three); `tamper_response`/`damage_repair` require only location; `customer_complaint`/`adjustment`/`other` left unconstrained | Exact match to the 3M brief's own recommendation — final_read closes an occupancy and produces the final bill off a specific meter (CI-124); the incident types carry money but not always a known customer/meter at intake; the other three are legitimately unconstrained per the brief. |
| **2.2**: "generated default" implemented as a BEFORE INSERT trigger, not a `GENERATED ALWAYS` column or plain `DEFAULT` | Neither alternative can both accept an operator-supplied override AND reference sibling columns (filename/hash/is_dry_run) — only a trigger does both. |
| **2.2**: CI-118 stays at `partially-structurally-enforced`, NOT re-graded upward (reverted mid-session after review) | The id-fallback makes duplicate-detection conditional on the caller supplying filename+hash, which nothing enforces — same "representable, not enforced" character already conceded for 2.5's lineage columns. Original draft's upward re-grade was wrong; both independent reviewers caught it. |
| **2.3**: all three land as REJECT triggers, not depth-monitoring events (unlike -05's reversal-chain-depth) | Depth is legitimate on these three structures per the source finding ("unbounded... a cycle is reachable") — only a cycle is a defect, so log-only monitoring (right for depth) is wrong here (a cycle should never be allowed to commit). |
| **2.3**: added `UNIQUE (import_job_id, row_number)` on `import_staging`, not named in the plan's item list | Load-bearing for the BFS guard's row_number lookup to be unambiguous; flagged explicitly in the header per Phase 2's "flag rather than land silently" rule rather than added quietly. |
| **2.3 concurrency race**: documented, not fixed | Closing it needs advisory locking or SERIALIZABLE — more machinery than a "low-controversy factual-defect" Phase 2 item should carry. Flagged as a candidate for a future item. |
| **2.5**: two new columns NOT paired by a CHECK (both-or-neither) | The invoice/payment lineage columns this mirrors are independent, not a paired unit, and the underlying finding already concedes every lineage column in the schema is representable-not-enforced. Pairing would invent a stricter rule than the pattern being copied. |
| **2.5**: CI-017/CI-018 status token unchanged, NOT re-graded upward | Both new columns land nullable — the guarantee stays representable, not enforced. This is the one item where landing the fix correctly does NOT restore a stronger grade (contrast with 2.2's original, wrong, attempt to do exactly that). |
| Two independent reviews (Fable + Codex) before continuing, same as -06 | Caught one real bug (the 2.3c row_number bypass) that neither citation-checking nor my own live testing surfaced — worth repeating before every future patch's mirror step. |

## Current State

**Working**: `sql/tu.sql` itself is unchanged this session (still v5.2.1+v5.4.0-00→-06, 12,279 lines, deploys clean). The draft patch `sql/v5.4.1-01-factual-defects-1.sql` (848 lines) is fully written, live-tested, reviewed, and fixed for items 2.1/2.2/2.3/2.5.
**Broken**: Nothing. Container `tally-pg` running with the draft DDL applied live (from iterative testing) — this is ahead of what's on disk in `tu.sql`; don't confuse the two.
**Uncommitted changes**: None — everything through the review-fix round is committed (`acb41cd`) and pushed to `tally-utility` `main`. GBM repo has zero changes this session.

## Code Context

```sql
-- The whole session's work lives in one file, not yet mirrored:
--   sql/v5.4.1-01-factual-defects-1.sql (848 lines)
-- Its own header (top ~280 lines) documents every citation, drafting
-- decision, and CI-entry call — read it before extending or mirroring.

-- New objects added so far (2.1/2.2/2.3/2.5), by name:
--   service_orders_final_read_referents_check   (CHECK)
--   service_orders_incident_location_check       (CHECK)
--   populate_import_job_idempotency_key()         + trg_populate_import_job_idempotency_key (BEFORE INSERT)
--   check_landlord_customer_cycle()                + landlord_customer_cycle (BEFORE INSERT OR UPDATE OF landlord_customer_id)
--   check_service_order_parent_cycle()             + service_order_parent_cycle (BEFORE INSERT OR UPDATE OF parent_order_id)
--   check_import_staging_dependency_cycle()        + import_staging_dependency_cycle
--       (BEFORE INSERT OR UPDATE OF depends_on_row_numbers, row_number, import_job_id  <- widened post-review)
--   import_staging_job_row_number_key              (UNIQUE)
--   account_ledger.reverses_ledger_entry_id + .reversal_reason (columns)
--   account_ledger_reverses_ledger_entry_id_fkey    (FK, self-referencing)
--   account_ledger_reversal_not_self_check          (CHECK)
--   void_invoice()  -- rewritten in place, tu.sql:1126 baseline + Step 3.7 lookup
--       + 2 INSERT columns + 1 return-payload key, nothing else changed

-- Test/verification idiom used throughout (repeat for 2.6 + carryover):
--   docker exec -i tally-pg psql -U tally -d tally -v ON_ERROR_STOP=1 < sql/v5.4.1-01-factual-defects-1.sql
--   then hand-built fixtures inside BEGIN...ROLLBACK, testing both the
--   rejection path and the allow path for every new constraint/trigger.
```

Non-obvious: the container currently has MORE applied than `tu.sql` has on disk (the whole draft patch, iteratively re-applied many times during this session) — do not mistake `tally-pg`'s live state for what's committed. `check_function_bodies = off` preamble still required on rebuild. `users` fixture NOT NULLs: id, tenant_id, display_name, email (+role); `tenants` needs only name+slug; `customers` needs `customer_number`; `service_locations` needs `customer_id`, `location_number`, `zip` (not `postal_code`); `meters` needs `location_id`, `service_type`.

## Resume Instructions

1. Draft item **2.6** (`meter_readings` service-point premise, CI-027) into the same `sql/v5.4.1-01-factual-defects-1.sql` file, following the established pattern: read the CI-027 re-grade finding in GBM, decide the column-vs-EXCLUDE approach (check Dockerfile for `btree_gist` support if EXCLUDE), draft, live-test positive+negative against `tally-pg`, update the file's own header (Authority/CI entries/drafting decisions/line-count-status sections — all currently say item 2.6 is `[PENDING]`).
2. Draft the **v5.4.0-06 review carryover** (positivity + non-negativity CHECKs on the two PGA tables) into the same file — small, mechanical, same pattern as the rest.
3. Once both are drafted and live-tested, run the **full per-patch loop that has NOT happened yet for anything this session**: mirror into `tu.sql` as a pure append (verify anchors 337/3600/3679), rebuild the container fresh (`docker rm -f tally-pg; docker build...; docker run...`, zero errors expected), re-run the full test battery against the FRESH build (the current `tally-pg` has been patched iteratively, not freshly rebuilt — a fresh-build test run hasn't happened yet), re-grade CI-122/CI-118/CI-017/CI-018 exactly as scoped in the patch header, DEPLOY-VERIFICATION § + counts, GBM ingestion Section AL, CHANGELOGs both repos, commit both, GBM push.
4. Consider a third review pass (or re-running Fable+Codex) on the finished, fully-mirrored patch before moving to Phase 4 — the two-review pattern caught a real bug this session that would otherwise have shipped.
5. After `v5.4.1-01` fully lands: start `v5.4.1-02` (item 2.4), then Phase 4 Wave 1 (A-4 → A-1 → A-3).

## Setup Required

Docker only: `docker build -t tally-postgres -f postgres/Dockerfile . && docker run -d --name tally-pg -e POSTGRES_PASSWORD=tally tally-postgres` (no `-p`, host 5432 taken).

## Warnings

- **`sql/tu.sql` itself has NOT been touched this session** — all work is in the standalone draft file. Don't assume `tu.sql`'s 12,279-line count or its constraint/trigger/function counts reflect this session's work.
- **The `tally-pg` container is AHEAD of `tu.sql`** (has the draft patch applied live) — rebuilding it from `postgres/Dockerfile` right now will NOT include this session's work, since the Dockerfile builds from `tu.sql`, not from the draft file. Mirror first.
- **GBM `origin/main` is still 13 commits behind `ryan`** — Kyle reads `main`. Catch-up is Ryan's explicit call only. GBM repo has zero new commits this session — everything about CI re-grades/re-checks named in the patch header is still only true in the SQL comments, not in `canonical-invariants.md`.
- **tu.sql edits, when they happen, are APPEND-ONLY** (currently 12,279 lines). Never edit the body; appends win at execution. Verify anchors 337/3600/3679 after every append.
- **Never `git add -A` in GBM** (`Clippings/` trap).
- Every GBM canonical-data change needs a `wiki-ingestion-pending.md` section (through AK; next is AL) + both CHANGELOGs.
- Phase 3 judgment-gated items still wait on their named questions — do not draft DDL for them. A-8 needs a Kyle brief. CI-029's structural CHECK stays parked with Kyle.
- The finance gate: A-15's ledger-partition/GL parts and A-6's remainder wait on the coda brief's finance reader.
- `regulatory_class` NOT NULL (from a prior patch) means any future *populated* database needs a backfill before -03 applies. Fresh deploys unaffected.
- Texas-only launch remains the scope discipline.
