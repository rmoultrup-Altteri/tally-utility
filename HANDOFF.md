# Handoff: A-20 landed (v5.4.2-05) — Wave 2 open; next is A-21

**Generated**: 2026-08-28 (session wrap — A-3 and A-20 both landed this session; A-20 drafted, reviewed twice, mirrored, fresh-build verified, docs in both repos)
**Branch**: tally-utility `main` (committed + pushed) · gas-billing-memory `main` (committed + pushed; unrelated untracked `Clippings/` left alone)
**Status**: **A-20 DONE.** `sql/v5.4.2-05-read-and-bill-exception-substrate.sql` (1,081 lines) is mirrored into `sql/tu.sql` (16,811 → 17,704, pure append; anchors 337/3600/3679 intact). Container `tally-pg` is a fresh build of the committed tu.sql. Phase 4: Wave 1 complete (A-4 ✅ A-1 ✅ A-3 ✅); Wave 2: A-20 ✅ → **A-21 next** → A-7.

## Goal

Bring `sql/tu.sql` (the only enforcement artifact — no application code exists) to parity with the spec corpus per `gas-billing-memory/application/schema-parity-plan.md`. Next: **A-21** — account lifecycle state-events, date-effective account attributes, deposit/interest ledger (Texas deposit family CI-129–131; the enrollment state-change audit deferred from v5.4.0-04). Then A-7 (PSF surcharge, launch-blocking).

## Completed (this session, A-20 half)

- [x] **Drafted v5.4.2-05**: `read_validation_exceptions` (CI-112 queue; born open, resolved once with disposition/reason/resolver/server time, frozen, never deleted; over-cap rows resolve only by override/field order); read gate `enforce_read_exception_gate` (no open exception on ANY step into approved/released/locked; `validated_at` server-stamped on the first billable entry and frozen; validated-read facts frozen; reviewed_* checks incl. INSERT); D14-1 counter on `meters` (stored, gate-maintained only via `pg_trigger_depth`, derived by `consecutive_estimate_state()` = validated main-register estimates dated after the latest-dated validated actual); auto-raised `consecutive_estimate_over_cap` (counts pending estimates; `max_consecutive_estimates()` from tenant settings, default 3, ≥ 1) + cap re-check at approval; `billing_run_meters` gates (open exception; CI-023 via `meter_master_incomplete_reasons()`); `invoice_exceptions` (CI-115 queue with table #35 outputs; `blocks_delivery`/`routing_reason` frozen; resolved/overridden with reason) + `enforce_invoice_predelivery_gate` (no pending/sent/`sent_at`/`delivery_confirmed_at` with an open blocking row) + `invoice_events` lineage (enum +3); composite FKs (new UNIQUEs on meters/meter_readings/service_orders) + `assert_same_tenant_user()`; RLS/FORCE/REVOKE DELETE/ENABLE ALWAYS; reporting-only backfill (stamps `validated_at` on history, clears strays, derives counters, three NOTICEs).
- [x] **Verified**: strict apply ×2 fresh + over the build (idempotent); **battery 154 green** (scratch + fresh build; `tally_app` end-to-end for both queues); pre-seeded backfill (same-day tie, back-dated actual, excluded-after-approval, stray `validated_at`, cap-0 tenant) stored = derived on every meter; fresh rebuild zero init errors; catalog parity (73 tables / 213 triggers, 146 ENABLE ALWAYS / 316 CHECKs / 324 FKs / 72 policies / 71 FORCE RLS / 531 indexes / 50 UNIQUEs).
- [x] **Two reviewers × two rounds** (Fable `general-purpose`, Codex `codex:codex-rescue`; plain + pre-seeded scratch DBs; the file changed four times between rounds, both re-loaded). Round 2: both "sound enough to mirror", each with an independent battery of the date-bounded streak.
- [x] Docs: DEPLOY-VERIFICATION; DECISION-LOG D-2026-08-28-25…-33; AC-20…AC-22; tally CHANGELOG. GBM: CI-113 → `structurally-enforced`, CI-023 → `partially-structurally-enforced`, CI-112/115 text (tokens unchanged); Appendix A-20 LANDED; parity plan A-20 struck; decision table `consecutive-estimate-enforcement` annotated; ingestion Section AS; GBM CHANGELOG.

## Not Yet Done

- [ ] **A-21** (same loop, below). Read Appendix A-21, CI-129–131, the v5.4.0-04 deferral note, and the WU rulings for deposits before drafting.
- [ ] **A-7** after A-21 (PSF surcharge; Texas-only launch scope).
- [ ] **For Kyle** (brief candidates, not blocking): D14-1b refinement — a back-dated actual validated after later-dated estimates does NOT clear them (should it raise its own review exception?); the tenant cap is not bounded at the Texas 6-month ceiling.
- [ ] **Open for Ryan**: CI-112/115 kept `partially` (detection/routing are application code) — re-cut if wanted; `anomalies.entity_type` has no CHECK (factual-defect candidate); queue/role substrate and SLA escalation wait for rbac-model; reason codes are free text until a catalogue exists; A-3's CI-015 grade call; A-23's three unpinned definers.
- [ ] Test artifacts in this session's scratchpad only (`battery-05.sql`, `battery-04.sql`, `review-brief-05.md`, `catalog.sql`); a `tests/` home is Ryan's call.

## Failed Approaches (Don't Repeat These)

- **Defining the estimate streak by status transitions** (double-counted approved→pending→approved; dropped excluded reads) and then **by validation order** (a back-dated actual validated later cleared later-dated estimates — Codex ran five estimates past a cap of 3). The definition that held: validation (`validated_at`) decides membership, reading date decides order; one function used by the gate, the derivation and the backfill.
- **Gating only the first entry into a billable state** — the `void_released → released_to_billing` re-lock and an exception raised after approval both walked through. Check every status change into approved/released/locked.
- **`ALTER TABLE … DISABLE/ENABLE TRIGGER USER` around a backfill UPDATE** — ENABLE fails on the deferred FK's queued events; and without it the v5.2.1 meters triggers break under the strict prelude. Use `set_config('search_path','public, pg_temp', true)` inside the DO block.
- **`now()` as an ordering stamp** (identical within a transaction) — `clock_timestamp()`.
- **`length(btrim(col)) > 0` as a NOT-NULL check** — NULL passes a CHECK; add `col IS NOT NULL`.
- **A raising function inside a backfill NOTICE query** — a misconfigured tenant made the patch refuse; report with a non-raising expression.
- **Battery traps**: an expected-error chunk that contains its own setup rolls the setup back (split them); `jsonb_set` does not create a missing parent key (use `||`); `billing_run_meters` has UNIQUE (run, meter); `meters` has no `notes`; a python heredoc that references a shell var (`SP`) fails after the first file write — check what landed.
- **All A-3 traps still apply**: `search_path = ''` on trigger functions that read RLS tables locks `tally_app` out (pin `public, pg_temp`); batteries run inside one transaction with an end-to-end `tally_app` write; don't lock the child row in a deferred check; mirror from the LAST header banner.

## Key Decisions (durable copies: `application/DECISION-LOG.md` D-2026-08-28-25…-33)

| Decision | Rationale |
|---|---|
| Exceptions are rows born open, resolved once, frozen, never deleted | The resolution IS the lineage (CI-088); dispositions per CI-112, narrowed per rule |
| Every step into a billable state is gated; no exception on a billed read | First-entry-only gating had two bypasses; a billed read is corrected by replacement |
| Streak = validated estimates dated after the latest-dated validated actual | Membership by validation, order by reading date — the only definition that survived review; refines D14-1b (for Kyle) |
| `validated_at` repurposed as the server-stamped validation event; facts freeze with it | A once-only event that survives status churn; the v5.2.1 whitelist froze facts only at `locked` |
| Counter stored, written only from inside the gate (`pg_trigger_depth`), equal to the derivation | Cap check without a history scan; auditable; no GUC carve-out |
| The database raises the over-cap exception | An exception the app forgot is no enforcement |
| Pre-delivery gate refuses, never auto-holds | A-4 forbids pending → held; the operator's hold is the recorded action |
| Plain FKs to users/anomalies tenant-checked in guards | FK checks bypass RLS; `users` is the RLS root, platform admins cross tenants |
| CI-023 = function + refusal at billing, not NOT NULL | Attributes nullable by ruling; the invariant's clause is the refusal |

## Current State

**Working**: tu.sql 17,704 lines, committed and pushed; `tally-pg` = fresh build of it (zero init errors). Catalog above.
**Broken**: nothing known.
**Uncommitted**: nothing (GBM's untracked `Clippings/` is not ours).

## Code Context

Patch headers are the contracts (`sql/v5.4.2-05-…` lines 1–192; `sql/v5.4.2-04-…` lines 1–160). The write protocols every future workflow must follow are AC-18…AC-22. The read path in one glance:

```sql
-- VEE/operator finds a failed rule → row (the DB raises consecutive_estimate_over_cap itself on insert of an at-cap estimate)
INSERT INTO public.read_validation_exceptions (tenant_id, meter_reading_id, meter_id, rule_code) VALUES (…);
-- resolve (once): disposition + reason + resolver; field order / replacement read for the dispositions that need one
UPDATE public.read_validation_exceptions SET status='resolved', resolution_disposition='override', resolution_reason_code='…', resolved_by=:user WHERE id=:e;
-- then the read may move on; the gate stamps validated_at and moves the meter's streak once
UPDATE public.meter_readings SET validation_status='approved' WHERE id=:r;
SELECT * FROM public.consecutive_estimate_state(:meter);   -- must equal meters.consecutive_estimate_count / streak / last actual
-- bill side: exception row (table #35 outputs) → hold → resolve/override with reason → release; the gate refuses pending/sent otherwise
```

## Resume Instructions

1. Read Appendix A-21 and CI-129–CI-131 in `canonical-invariants.md`, the v5.4.0-04 patch header's deferral note, `schema-parity-plan.md` Wave 2, and the deposit decision tables (`deposit-eligibility-and-waiver`, `deposit-refund-and-interest`, `deposit-alternatives-and-triggers`) + workflows (`deposit-interest-accrual-cycle`, `deposit-refund-processing`). Note Family 16's sequencing flag: the day-30-vs-day-31 interest boundary.
2. Draft `sql/v5.4.2-06-…` for A-21. Same loop: fresh-load scratch → strict apply ×2 → battery inside one transaction with an end-to-end `tally_app` path → pre-seeded backfill check if the patch touches history → two independent reviews (`general-purpose` + `codex:codex-rescue`, fresh-load scratch DBs, expect a round 2, `SendMessage` to continue; tell them the file's line count/md5 when it changes — Codex reviewed a stale copy twice this session) → mirror after the LAST header banner → fresh rebuild with catalog parity → patch re-apply over the build → DEPLOY-VERIFICATION → register re-grade of exactly the CIs the header names → Appendix → DECISION-LOG / APPLICATION-CONTRACTS → ingestion section → both CHANGELOGs → commit + push both repos.
3. Before the first bill-run calculation code: CI-003's GUC net (R-16) and A-3's snapshot value contract + replay function.

## Warnings

- tu.sql APPEND-ONLY; anchors 337/3600/3679. Pin `public, pg_temp` on anything that reads an RLS table (until A-23); prove qualification with the strict prelude; backfills that fire v5.2.1 triggers need a txn-local search_path.
- Wait for `PostgreSQL init process complete` before touching a freshly run container.
- Never `git add -A` in GBM.
- Fixtures for later patches: reads born `pending_review` → approve (the gate stamps `validated_at`); an estimate at the cap needs its exception overridden first; invoices draft → lines → snapshot → (exceptions/hold) → pending → sent; issued invoices reject content edits, line changes, snapshot changes, DELETE.
- Phase 3 judgment-gated items wait; A-8 needs a Kyle brief; finance gate holds A-15/A-6 remainder. Texas-only launch scope.
