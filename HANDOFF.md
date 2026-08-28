# Handoff: A-3 landed (v5.4.2-04) — Wave 1 complete; next is Wave 2 (A-20)

**Generated**: 2026-08-28 (session wrap — A-3 drafted, reviewed twice, mirrored, fresh-build verified, docs in both repos)
**Branch**: tally-utility `main` (committed + pushed) · gas-billing-memory `main` (committed + pushed; unrelated untracked `Clippings/` left alone)
**Status**: **A-3 DONE.** `sql/v5.4.2-04-invoice-calculation-snapshots.sql` (722 lines) is mirrored into `sql/tu.sql` (16,245 → 16,811, pure append; anchors 337/3600/3679 intact). Container `tally-pg` is a fresh build of the committed tu.sql. Phase 4 **Wave 1 is complete** (A-4 ✅ → A-1 ✅ → A-3 ✅). Next: **Wave 2 — A-20 → A-21, A-7.**

## Goal

Bring `sql/tu.sql` (the only enforcement artifact — no application code exists) to parity with the spec corpus per `gas-billing-memory/application/schema-parity-plan.md`. This session closed A-3 (CI-015, Option B). Next: A-20 (read/bill exception queue + validation-state substrate — "fully ruled and ready", D14-1 per-meter counter), then A-21, A-7.

## Completed (this session)

- [x] **Drafted v5.4.2-04**: `invoice_calculation_snapshots` (one per invoice; composite FK to `invoices(id, tenant_id)` — new UNIQUE on invoices; the run's `(valid_at, recorded_at)` pair per AC-15; `snapshot_schema_version` enforced by `validate_calculation_snapshot()` against an enumerated `v1` key contract incl. nested `items[]`/`reads[]`/`line_items[]` and WNA-when-applied keys; `formula_version`; eight JSONB sections; GENERATED sha256 `content_hash`), `invoice_snapshot_references` (citations into the seven A-1 tables, verified open at the snapshot's `recorded_at`, same tenant), DEFERRABLE `enforce_invoice_has_snapshot` on `invoices` (exactly one snapshot agreeing with period/run/customer/lines at commit of any move into an issued status; draft/held → void exempt), immutability (UPDATE never; INSERT/DELETE only while draft/held; frozen after issuance; cascade on draft delete; TRUNCATE rejected; `REVOKE UPDATE` from `tally_app`), RLS + FORCE, every guard `ENABLE ALWAYS`.
- [x] **Verified**: strict apply ×2 on a fresh-loaded scratch (idempotent) and over the mirrored build; **battery 90 checks green** (scratch + fresh build; run inside one transaction so `SET LOCAL ROLE tally_app` is real); four two-session races (issue vs snapshot delete / line edit / delete-then-issue / citation insert) each reject exactly one side, no deadlock; fresh rebuild zero init errors, catalog parity (71 tables / 201 triggers, 134 ENABLE ALWAYS / 294 CHECKs / 308 FKs / 7 EXCLUDE / 70 policies / 69 FORCE RLS / 517 indexes / 46 UNIQUEs).
- [x] **Two independent adversarial reviews, two rounds each** (Fable `general-purpose`, Codex `codex:codex-rescue`). Round 1 found real defects (below); round 2: both "sound enough to mirror".
- [x] Docs: `sql/DEPLOY-VERIFICATION.md`; `application/DECISION-LOG.md` D-2026-08-28-16…-24 (+ flagged, failed, outcomes); `application/APPLICATION-CONTRACTS.md` AC-18/AC-19; tally `CHANGELOG.md`. GBM: CI-015 → `structurally-enforced` (boundary stated); Appendix A-3 LANDED; A-23 (1c) amended; parity plan A-3 struck (Wave 1 complete); `bi-temporal-decision.md` §2.3 annotated; ingestion Section AR; GBM `CHANGELOG.md`.
- [x] Memory: `strict-pin-vs-rls-helpers` (trigger functions reading RLS tables must not pin `search_path = ''` until A-23).

## Not Yet Done

- [ ] **Wave 2**: A-20 → A-21, A-7. Same loop as A-1/A-3 (below). A-20's Kyle rulings are already in (`kyle-decisions-2026-08-18-coda-items.md`, D14-1).
- [ ] **Before the first bill-run calculation code** (whenever that is): CI-003's GUC coordinate net (R-16) AND the snapshot value-domain contract per section + a replay function (D-2026-08-28-17; `v1` checks key presence and JSON type only).
- [ ] **Open for Ryan** (flagged, not changed): CI-015 graded `structurally-enforced` with a boundary — Ryan may prefer `partially-structurally-enforced` (the boundary text reads true under either); every invoice type is gated incl. consolidated parents / duplicates / credit memos; the deferred gate queues an event on every `invoices` write (cost only); A-23's three unpinned definers are now a demonstrated trap (pin them); the raw `version` bump (A-1) and R-18 (v5.5) remain.
- [ ] Test artifacts live only in this session's scratchpad (`battery-04.sql`, `review-brief-04.md`, `catalog.sql`); unlike A-1's, this battery needs no pre-patch rows and runs on a fresh build — a `tests/` home is Ryan's call.

## Failed Approaches (Don't Repeat These)

- **`SET search_path = ''` on trigger functions that read RLS-protected tables** — the first policy evaluation calls `get_user_tenant_id()`/`is_platform_admin()`, whose v5.2.1 SQL bodies name `users` unqualified and inherit the empty path: `tally_app` was locked out of the whole feature; the superuser battery bypassed RLS and missed it (both reviewers, CRITICAL). Pin `public, pg_temp` (the `void_invoice`/A-1 precedent) with every reference qualified; prove qualification with the strict prelude. **Add an end-to-end `tally_app` write to every battery.**
- **Locking the snapshot row `FOR UPDATE` inside the deferred completeness check** — deadlocked against a waiting DELETE (a BEFORE DELETE trigger already holds the tuple) and needs the UPDATE privilege `tally_app` lacks. Lock the *parent invoice* `FOR SHARE` in the child guards instead; lock lines `FOR SHARE` in the deferred check.
- **STABLE expressions in a GENERATED column** — `convert_to()`, `date::text`, `timestamptz::text` are STABLE; use `public.digest(text,'sha256')`, `date - DATE '1970-01-01'`, `extract(epoch from ts AT TIME ZONE 'UTC')`.
- **`text[] || 'literal'`** — resolves as array-literal concatenation; `malformed array literal` on the first message with parentheses. Use `array_append(arr, (…)::text)`.
- **Assuming a CHECK constraint runs before a BEFORE trigger** — it does not; re-check the enum inside the trigger before dynamic `format('%I')` SQL.
- **Mirroring from the second `-- ====` line** — the header has three banners; the body starts after the LAST. Caught before the build this time; reverted with `head -n 16245`.
- **Running the battery standalone** — `SET LOCAL ROLE tally_app` needs one transaction (BEGIN wrapper or `psql -1`); standalone it silently tests as superuser. `ALTER TABLE invoices` fails while deferred events are pending — flush with `SET CONSTRAINTS ALL IMMEDIATE` (then `DEFERRED`).
- A-4/A-1 fixture rules still bite: lines cannot be added to an issued invoice (insert draft → lines → snapshot → flip); held needs `hold_reason`; a pending exemption has `recorded_at IS NULL` and is not an assertion.
- All prior tu.sql traps still apply (`application/DECISION-LOG.md`): append-only file, fresh rebuild mandatory, strict-apply prelude per patch, register grades from `canonical-invariants.md` only, never `git add -A` in GBM, `SendMessage` to resume a named reviewer agent rather than respawning.

## Key Decisions (durable copies: `application/DECISION-LOG.md` D-2026-08-28-16…-24)

| Decision | Rationale |
|---|---|
| Completeness is a commit-time gate on `invoices` (deferred), every invoice type included; draft/held → void exempt | The snapshot cites the lines so it must be a child row; carving out types makes "issued without a snapshot" legal again; a void of an unbilled draft is a discard |
| Schema version is a validator with an enumerated key contract, not a label | Option B's advantage is explicit versioning — only real if the DB knows the contract; a new shape is a patch |
| The coordinate pair lives on the snapshot | AC-15: one pair per run; the snapshot records which pair this bill used; off-run invoices still have one |
| Lines stored twice, cross-checked at insert and at issuance, unrounded JSON numbers | CI-016 needs them on the row, CI-015 needs one replayable document; they must agree |
| No snapshot after issuance; pre-patch invoices stay snapshot-less | A later snapshot is a reconstruction from today's reference layer — what CI-015 forbids |
| Provenance is a table with a transaction-time visibility proof (no valid-time check) | Seven tables, no polymorphic FK; "was this row visible at the coordinate" is the structural question; brackets differ per table |
| `public, pg_temp` pin, not `''` | The unqualified RLS helpers (A-23) |
| Child guards lock the invoice `FOR SHARE`; deferred check locks lines, not the snapshot | Serialises the races without deadlock or extra privilege |
| New FKs cascade on delete | Only drafts are deletable (A-4); without it a legitimate draft delete was blocked |

## Current State

**Working**: tu.sql 16,811 lines, committed and pushed; `tally-pg` = fresh build of it (zero init errors). Catalog above.
**Broken**: nothing known. Reviewer residuals recorded, not open.
**Uncommitted**: nothing (GBM's untracked `Clippings/` is not ours).

## Code Context

The patch header (`sql/v5.4.2-04-invoice-calculation-snapshots.sql` lines 1–160) is the contract. The write protocol every future calculation path must follow (AC-18/AC-19):

```sql
-- 1. invoice (draft) → 2. invoice_line_items → 3. snapshot → 4. citations → 5. status flip; all in one txn
INSERT INTO public.invoice_calculation_snapshots (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at,
  snapshot_schema_version, formula_version, rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs,
  customer_inputs, period_inputs, line_items) VALUES (…, p_valid_at, p_recorded_at, 'v1', 'calc-x.y.z', …);
INSERT INTO public.invoice_snapshot_references (tenant_id, snapshot_id, source_table, source_row_id, role) VALUES (…, 'rate_item_versions', :version_id, 'commodity_rate');
UPDATE public.invoices SET status = 'pending' WHERE id = :inv;   -- deferred gate fires at COMMIT
-- recalculating a draft: DELETE the snapshot (cascades citations), re-insert. Never UPDATE.
```

## Resume Instructions

1. Read Appendix A-20 in `canonical-invariants.md`, the D14-1 ruling in `kyle-decisions-2026-08-18-coda-items.md`, and `schema-parity-plan.md` Wave 2; check CI-023's exception-queue rule (deferred from v5.4.0-02 to A-20).
2. Draft `sql/v5.4.2-05-…` for A-20. Same loop: fresh-load scratch → strict apply ×2 → battery run inside one transaction with an end-to-end `tally_app` path → two independent reviews (`general-purpose` for Fable, `codex:codex-rescue`; fresh-load scratch DBs; expect a round 2; `SendMessage` for round 2) → mirror after the LAST header banner → fresh rebuild with catalog parity → patch re-apply over the build → DEPLOY-VERIFICATION → register re-grade of exactly the CIs the header names → Appendix → DECISION-LOG / APPLICATION-CONTRACTS → ingestion section → both CHANGELOGs → commit + push both repos.
3. Before the first bill-run calculation code lands: CI-003's GUC net (R-16) and the snapshot value contract + replay function (D-17).

## Warnings

- tu.sql APPEND-ONLY; anchors 337/3600/3679. Prove qualification with the strict prelude on the patch file; pin `public, pg_temp`, not `''`, on anything that reads an RLS table (until A-23).
- Wait for `PostgreSQL init process complete` before touching a freshly run container.
- Never `git add -A` in GBM.
- Fixtures for later patches: schedules born draft → version → activate; exemptions verified into `active`; WNA approved with an approver; invoices draft → lines → snapshot → flip; issued invoices reject every content edit, line change, snapshot change and DELETE.
- Phase 3 judgment-gated items wait; A-8 needs a Kyle brief; finance gate holds A-15/A-6 remainder. Texas-only launch scope.
