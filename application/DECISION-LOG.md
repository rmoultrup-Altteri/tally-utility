# Decision Log — schema decisions, with the why

A permanent, cumulative ledger of decisions made while bringing `sql/tu.sql` to parity with the spec. Newest session on top; never rewrite an old entry (append a dated correction instead). `HANDOFF.md` is rewritten every session and is **not** a durable record — anything worth keeping from its Key Decisions / Failed Approaches tables is copied here at wrap-up. Kyle's rulings live in `gas-billing-memory/application/`; this file records the drafting-time calls made inside those rulings and the Phase 2/4 calls Ryan owns directly.

Format per decision: **what** → *why this, and why not the alternative* → where it lives.

---

## 2026-08-20 — Phase 2 completed (v5.4.1-01 item 2.6 + -06 carryover, v5.4.1-02)

### Decisions

**D-2026-08-20-01 · Item 2.6 lands BOTH the EXCLUDE and the recorded column, where the plan said "either/or."**
*Why:* the CI-027 re-grade named two defects — premise not *recorded* on the read, and overlapping deployments making reconstruction ambiguous. Fixing only the EXCLUDE still leaves the premise unrecorded (the CI's own statement is "every meter read *records* … the service point"); fixing only the column records a value derived from an ambiguous history. Flagged as a scope widening in the patch header rather than landed silently. → `meter_deployments_no_overlap_excl`, `meter_readings.location_id`, `trg_populate_reading_location` (v5.4.1-01).

**D-2026-08-20-02 · The EXCLUDE range is half-open `[install_date, removal_date)`.**
*Why:* `sync_meter_deployments()` closes a deployment with `CURRENT_DATE` and reopens with `CURRENT_DATE`; a closed `[]` range would make every same-day Pattern A remove+reinstall collide with itself. Cost accepted: a zero-day row (`install = removal`) is an empty range that overlaps nothing and covers no read date — tolerated and stated in the COMMENT.

**D-2026-08-20-03 · The in-place active-meter relocation gap is DOCUMENTED (AC-7), not fixed.**
*Why:* both reviewers found that `sync_meter_deployments()` reacts only to `status` transitions, so `UPDATE meters SET location_id = B` on an active meter leaves deployment history — and every later read's snapshot — stale with no error. Auto close+reopen would fabricate a relocation date; rejecting the UPDATE would block legitimate typo corrections. The schema cannot tell relocation from correction, and deciding that by inertia is exactly what Phase 3's rule forbids. → Kyle brief candidate: *"how is an active meter relocated?"* Until ruled, CI-027 stays `partially-structurally-enforced` with this as the leading reason (not nullability).

**D-2026-08-20-04 · Removal/final reads resolve to the deployment CLOSED ON the read date, other purposes to the covering one.**
*Why:* with half-open ranges, a same-day pull-from-A/reinstall-at-B makes a read dated that day resolve to B — wrong for the removal/final read taken at A, the one read that most needs correct attribution (CI-124). A final read with no meter move finds no closed-on-that-day row and falls through unchanged, so the heuristic cannot misfire on the common case.

**D-2026-08-20-05 · `location_id` is never re-derived on UPDATE.**
*Why:* it is a snapshot of where the meter *was*; a later meter move must not reattribute historical consumption (the whole point of CI-027). Cost: a `reading_date` correction does not re-sync it (AC-2). Prefer the supersede pattern (new read row) over in-place date edits.

**D-2026-08-20-06 · CI-032 corrected to `partially-structurally-enforced` (the patch header's first draft said `structurally-enforced`).**
*Why:* the grade had been read off `invariant-scenarios/meter-and-premise-master-data.md`, a stale copy; the register re-graded it 2026-08-13 for two reasons — no temporal guard, and nullable `meters.replaces_meter_id`. 2.6a closes only the first. **Rule:** grades come from `canonical-invariants.md` only, never from scenario files.

**D-2026-08-20-07 · -06 carryover leaves `monthly_variance` / `deferred_balance_after` signed; only the gross inputs get non-negativity CHECKs.**
*Why:* the -06 header defines the sign as living in the variance/balance columns; `actual_gas_cost` is the gross supplier invoice and `pga_recovered_revenue` the gross billed revenue. A supplier credit month is a *lower* cost, never a negative one — stated so nobody later tries to post a negative "credit month."

**D-2026-08-20-08 · `tenant_configuration_history` is ONE key/value table with JSONB values, populated by trigger.**
*Why:* thirteen typed columns plus an open-ended `settings` blob do not fit a typed-column history; the 3M brief's own shape was key/value. Trigger-written rather than convention because with no application layer a convention-only history would grade `requires-application-discipline` and the hazard would remain. On tenant INSERT every key is recorded so an onboarding default becomes a recorded decision (W-tenant-onboarding item 5). Settings granularity is top-level key (whole sub-object before/after); finer is a later call. *Not chosen:* the brief's interim "snapshot resolved policy onto `billing_runs`" — that is A-3's territory.

**D-2026-08-20-09 · `get_partial_period_policy(uuid, timestamptz)` — `p_as_of` REQUIRED, NO live-column fallback, NULL RAISES, pre-history returns NULL. Old one-arg signature dropped.**
*Why:* CI-006 says the temporal coordinate is an explicit input, never implicit "now." A `DEFAULT now()` would have kept the time-blind form as the path of least resistance. The first draft's `COALESCE(... , t.default_partial_period_policy)` was caught by both reviewers: NULL `p_as_of` (realistic — `get_correction_rate_date()` documents returning NULL) and any pre-history coordinate silently resolved to *today's* value, i.e. the bug the patch exists to fix, back through the side door. Dropping the old signature is safe: zero callers in tu.sql. **Standing rule for every future temporal helper (A-1/A-3): no live-value fallback; NULL coordinate raises; NULL result means "unknowable," never "use the default."**

**D-2026-08-20-10 · The history bracket is transaction time, not valid time.**
*Why:* `effective_from` is `now()` at the change; an operator cannot say "this took effect last month" through the trigger path. Valid-time policy changes are the A-1 bi-temporal pair's job (bi-temporal-decision §6); inventing a second valid-time mechanism here would pre-empt it. Backdated rows remain *representable* as `change_source='manual'`. Hence CI-004 stays partial.

**D-2026-08-20-11 · Backfill stamps the deploy-time value at `tenants.created_at`, explicitly flagged as an approximation.**
*Why:* with no live fallback in the function (D-09), existing tenants must still resolve for pre-deploy coordinates, and `now()` would make all of them NULL. A value changed after onboarding is therefore recorded as if in effect since creation — unknowable either way; every backfill row carries a `change_reason` saying so.

**D-2026-08-20-12 · Direct inserts into the history are allowed for `tally_app` but guarded.**
*Why:* backdated corrections should not require a migration; RLS scopes them to the caller's tenant. But a direct insert may not impersonate the recorder (`pg_trigger_depth()` guard on `change_source`), must use a known `config_key`, and must carry a legal `default_partial_period_policy` value. TRUNCATE is rejected like UPDATE/DELETE; the tenant FK has no CASCADE — an audit trail must outlive its tenant (CI-093).

**D-2026-08-20-13 · Identity `seq` column as the deterministic tiebreaker.**
*Why:* `now()` is fixed per transaction, so two changes to one key inside one transaction tie on both `effective_from` and `created_at`; "latest row" was a coin flip in testing. Resolution orders by `effective_from DESC, seq DESC`.

**D-2026-08-20-14 · Two independent adversarial reviews (Fable + Codex) before every mirror; reviewers must fresh-load tu.sql + patch into a scratch database.**
*Why:* round two caught a wrong CI grade and a real attribution bug live testing had not; round three caught the time-blind fallback. The scratch-DB load was added after the btree_gist failure (below) to catch environment-dependent statements before the mirror.

**D-2026-08-20-15 · `application/APPLICATION-CONTRACTS.md` exists and is mandatory to update.**
*Why:* several patches now assume caller behavior the DB can't enforce (set `start_date` on reactivation; never pass NULL `p_as_of`; write `settings` at onboarding if you want it recorded). With no application code yet, these obligations had no home. Every patch that lands a constraint or trigger with a caller assumption adds an AC entry.

### Flagged, deliberately not changed (candidates for a later set)

- `rate_schedules.partial_period_policy` (no CHECK, **read** by `get_partial_period_policy`) duplicates `partial_period_policy_override` (CHECK-constrained, read by nothing). Two columns for one override; the unchecked one is live.
- `sync_meter_deployments()`: stale `meters.start_date` on Pattern A reactivation and stale `meters.removal_date` on deactivation now fail at the EXCLUDE/CHECK inside the trigger (AC-1). Substituting a date would be guessing; candidate Kyle brief whether the trigger should take an explicit reinstall date.
- Cross-tenant `meter_id` on a read passes the (not tenant-scoped) FK and leaves `location_id` NULL under RLS (AC-3). Same FK shape already flagged for the landlord and ledger lineage FKs.
- All three v5.4.1-01 cycle guards race under concurrent transactions (AC-6). Closing it needs advisory locks or SERIALIZABLE.

### Failed approaches (permanent record)

- **Trusting the iteratively-patched container as a deploy test.** `CREATE EXTENSION IF NOT EXISTS btree_gist;` worked in every psql session all day and failed the fresh build with `ERROR: no schema has been selected to create in`, because tu.sql runs under `search_path = ''` (tu.sql:65) and a psql session does not. Fix: `WITH SCHEMA public`. Rule: the fresh rebuild from `postgres/Dockerfile` is mandatory before commit, and reviewers fresh-load into a scratch DB before the mirror. Any statement that depends on search path must be schema-qualified; `pg_catalog` functions are safe, extension-provided operators/types are not.
- **Reading a CI grade from a scenario file** (see D-06).
- **Mirroring from the wrong banner line.** The patch header has two `-- ====` lines; the body starts after the *second* (the line before the first `-- Item` / body comment). Splitting at the first mirrored the whole header into tu.sql — harmless, but not the -06 form; redone.
- **Incomplete test fixtures cost four runs** — `service_locations` needs `address_line1/city/state/zip`, `service_orders` needs `order_number/description`, `import_jobs` needs `initiated_by/error_handling_policy` (enum), `rate_schedules` needs `customer_type` (enum). Query `information_schema.columns … is_nullable='NO' and column_default is null` and `pg_get_constraintdef` first; wrap negatives in `SAVEPOINT sp … ROLLBACK TO sp`.
- **`COALESCE` onto a live column in a temporal helper** (see D-09) — it reads as a harmless default and is exactly the bug class the helper exists to remove.

### Outcomes

- tu.sql 12,279 → 13,241 lines (pure appends; anchors 337/3600/3679 intact). Catalog after -02: 66 tables / 65 policies / 64 FORCE-RLS / 229 CHECKs / 1 EXCLUDE / 70 triggers / 477 indexes / 275 FKs. Fresh build zero errors; all batteries green on the fresh build (`sql/DEPLOY-VERIFICATION.md`).
- GBM: CI-004/006/017/018/027/032/093/118/122 re-checked — **every grade token unchanged**, descriptive text corrected; family-15 intro four → three; Appendix A-22 added; parity plan Phase 2 ✅; ingestion Sections AL + AM; `ryan` 15 commits ahead of `origin/main` (catch-up is Ryan's call).
- Next: Phase 4 Wave 1 — A-4 → A-1 → A-3.

---

## Before 2026-08-20

Decisions from Phase 0/1 and the first half of v5.4.1-01 (2.1/2.2/2.3/2.5) are recorded in `CHANGELOG.md` entries dated 2026-08-18/19 and in each patch file's own header (`sql/v5.4.0-0*.sql`, `sql/v5.4.1-01-*.sql`, "Drafting decisions" section) — the headers are the authoritative per-patch record. Kyle rulings: `gas-billing-memory/application/wu5-wu6-kyle-decisions-2026-07-10.md` and the decision tables.
