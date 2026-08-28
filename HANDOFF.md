# Handoff: A-21 landed (v5.4.2-06) — next is A-7 (closes Wave 2)

**Generated**: 2026-08-28 (session wrap — A-3, A-20 and A-21 all landed this session; A-21 drafted, reviewed up to four rounds, mirrored, fresh-build verified, docs in both repos)
**Branch**: tally-utility `main` (committed + pushed) · gas-billing-memory `main` (committed + pushed; unrelated untracked `Clippings/` left alone)
**Status**: **A-21 DONE.** `sql/v5.4.2-06-account-lifecycle-and-deposits.sql` (1,328 lines, md5 `66c8babf…`) is mirrored into `sql/tu.sql` (17,704 → 18,822, pure append; anchors 337/3600/3679 intact). Container `tally-pg` is a fresh build of the committed tu.sql. Phase 4: Wave 1 complete; Wave 2: A-20 ✅ A-21 ✅ → **A-7 next** (PSF surcharge, launch-blocking).

## Goal

Bring `sql/tu.sql` (the only enforcement artifact — no application code exists) to parity with the spec corpus per `gas-billing-memory/application/schema-parity-plan.md`. Next: **A-7** — the Texas PSF surcharge (on every Texas bill; promoted into Wave 2 by Ryan 2026-08-19). Read Appendix A-7 and CI-038 first; it composes with A-1's rate layer (a rate item / rider with its own base rules) and CI-045's base-composition pattern.

## Completed (this session, A-21 half)

- [x] **Drafted v5.4.2-06**: `customer_state_events` (the lifecycle guard writes the event from `status_reason` and clears it; closed reopens only to active; closed refused while a deposit is unsettled; `customer_status_as_of()`), `customer_attribute_history` (eight attributes; initial rows at insert; `customer_attribute_as_of()`), `deposit_interest_rates` (effective-dated per tenant; no-fallback lookup; backdating refused once an accrual is settled), `deposit_waiver_determinations` (CI-129), `deposits` (basis / instrument / cap; identity frozen; status projected from events), `deposit_events` (append-only sub-ledger — every CI-125/130/131 rule is a refusal; accrual horizon = min(return, exhaustion); `applied` + zero refund), `deposit_balance()` / `deposit_principal_in_force()` / `deposit_refund_trigger_state()` / `deposits_refund_due` (security_invoker), `customers.deposit_*` as a DB projection, payments reconciled + CHECK, `customer_credits.deposit_id` lineage trigger, ledger enums, composite FKs, RLS/FORCE, **REVOKE TEMP on the database from PUBLIC/`tally_app`**, every guard ENABLE ALWAYS, reporting-only backfill (legacy deposits incl. applied/refunded via synthetic events).
- [x] **Verified**: strict apply ×2 fresh + over the build; **battery 141 green** (scratch + fresh build; `tally_app` end-to-end); pre-seeded backfill (every deposit_status, inconsistent payments, a legacy credit) correct and re-apply a no-op; fresh rebuild zero init errors; catalog parity (79 tables / 237 triggers, 170 ENABLE ALWAYS / 344 CHECKs / 345 FKs / 8 EXCLUDE / 78 policies / 77 FORCE RLS / 555 indexes / 56 UNIQUEs); `has_database_privilege('tally_app', db, 'TEMP') = false`.
- [x] **Two reviewers** (Fable `general-purpose`, Codex `codex:codex-rescue`), plain + pre-seeded scratch DBs, four file revisions verified by hash. Final: both "sound enough to mirror" on `66c8babf…` with boundary matrices of the day-30/31 and exhaustion rules; Fable exhausted the TEMP fence.
- [x] Docs: DEPLOY-VERIFICATION; DECISION-LOG D-2026-08-28-34…-43; AC-23…AC-25; tally CHANGELOG. GBM: CI-130 → `structurally-enforced`; CI-121/125/129/131/077 → `partially-structurally-enforced`; CI-126 amended; Appendix A-21 LANDED; A-23 (1d); parity plan A-21 struck; ingestion Section AT; GBM CHANGELOG.
- [x] Memory: `depth-fence-needs-no-temp` (pg_trigger_depth fences hold only while the app role can define no code).

## Not Yet Done

- [ ] **A-7** (same loop, below). Then Wave 3 (A-2 → A-9 → A-10; A-8 held for a Kyle brief).
- [ ] **For Kyle** (brief candidates): the full `customers.status` matrix (`final_billed → closed`); whether a legacy deposit may be refunded without an accrual history (allowed with a reason today); credit vs disbursement on refund + the `minimum_refund_amount` exclusion; residential non-cash instruments; instrument-expiry alerting; from A-20: the D14-1b refinement and the Texas cap ceiling.
- [ ] **Open for Ryan**: the CI-121/125/129/131 partial grades (each entry states its boundary — re-cut if wanted); the four pre-existing views in tu.sql should be checked for `security_invoker` (Fable); the enrollment state-change audit deferred from v5.4.0-04 is a small rider not in A-21 (noted in the parity plan); A-23's three unpinned definers; `anomalies.entity_type` CHECK.
- [ ] Test artifacts in this session's scratchpad only (`battery-06.sql`, `battery-05.sql`, `battery-04.sql`, `review-brief-06.md`, `catalog.sql`); a `tests/` home is Ryan's call.

## Failed Approaches (Don't Repeat These)

- **`pg_trigger_depth() < 2` as a privilege boundary while the app role has TEMP** — Fable created a temp table + `pg_temp` trigger function as `tally_app` and rewrote every projection at depth 2. Close the route: no TEMP, no CREATE on schemas, no TRIGGER on tables. A GUC sentinel is forgeable (any role can `set_config`). Record in A-23 before ever granting those.
- **A superuser-owned view over RLS tables** — bypasses RLS for every reader. `CREATE VIEW … WITH (security_invoker = true)`.
- **NOT VALID CHECKs to tolerate legacy rows** — they still fire on any UPDATE of the offending row. Reconcile then add VALID, or enforce with a trigger on INSERT / changed columns.
- **"Accrue to the return date" with no exhaustion horizon** — a deposit consumed by the final bill was unsettleable and the customer could never close; then an accrual admitted for the pre-exhaustion days of a deposit exhausted within 30 days blocked the zero refund forever (append-only). Refuse it up front; define the horizon on money held.
- **A reason column that lingers on the row** — reused by the next transition. Consume it into the event in the BEFORE trigger and clear it.
- **`now()` / uuid tiebreak for event ordering** — same-transaction transitions read the wrong state. `clock_timestamp()` + identity `seq`.
- **A backfill stamp behind the guard that resets it** — create the guard after the backfill (now three triggers use this ordering: lifecycle, deposit, deposit_event).
- **A set-returning function inside CASE / an aggregate** — `set-returning functions are not allowed in CASE`; `CROSS JOIN LATERAL`.
- **Reviewers reading a stale file** — both did it twice this session; every round-2 request now carries `wc -l` + `md5 -q`, and reviewers are told to verify the hash before testing.
- All A-20/A-3 traps still apply: `public, pg_temp` pin (never `''` on anything reading an RLS table); battery inside one transaction with an end-to-end `tally_app` path; an expected-error chunk must not contain its own setup; mirror from the LAST header banner.

## Key Decisions (durable copies: `application/DECISION-LOG.md` D-2026-08-28-34…-43)

| Decision | Rationale |
|---|---|
| State log written by the database; reason consumed into the event and cleared | An app-written log can be skipped; a lingering reason was reused |
| Attribute history is a change log, not versioned `customers` | "Value on date X" without a header/version split on the widest table |
| Deposit status and `customers.deposit_*` are projections of `deposit_events` | Six disagreeing representations existed because each was written independently |
| TEMP revoked from PUBLIC/`tally_app` | The depth fence is structural only while the app role can define no code |
| Interest is events recomputed by the guard; first period ON posting; no accrual until day 31; none at all if refunded/exhausted ≤ 30 days | CI-125/130's failures are all "wrong rate over the wrong span"; the cliff must be visible in the events |
| Accrual horizon = min(return, exhaustion); `applied` settles by a zero refund | Interest is owed on money held; CI-131 Alt 2 still records the obligation |
| Waiver = recorded determination in its own RLS table; §7.45 deposits refused while in force, §366 not | Point-in-time determination; most sensitive data; rank 0 over rank 5 |
| Cap on the record, required for TX residential cash, principal ≤ cap | The database enforces what was decided; it cannot compute estimated annual billing |
| Legacy history carried, never refused; legacy refund allowed with a reason | No rate history exists to accrue against; freezing legacy rows was the alternative |
| CI-131 = derivation + security_invoker view | The unmade refund becomes visible; the job is the application's |

## Current State

**Working**: tu.sql 18,822 lines, committed and pushed; `tally-pg` = fresh build (zero init errors). Catalog above.
**Broken**: nothing known.
**Uncommitted**: nothing (GBM's untracked `Clippings/` is not ours).

## Code Context

Patch headers are the contracts (`sql/v5.4.2-06-…` lines 1–214). Write protocols: AC-23…AC-25. The deposit path in one glance:

```sql
INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, cap_amount, cap_basis_annual_billing, source_payment_id, created_by) VALUES (…);   -- DB writes the 'posted' event
-- accrual job, once held > 30 days, from posted_on, one event per segment (split at rate changes / applications):
INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, period_start, period_end, rate_applied, principal_basis)
VALUES (:t, :d, 'interest_accrued', public.deposit_accrual_amount(:basis, :rate, :s, :e), :today, :s, :e, public.deposit_interest_rate_as_of(:t, :s), public.deposit_principal_in_force(:d, :s));
-- refund: applied_to_balance (disconnect path) → interest_credited (all accrued) → refund_initiated → refunded (remainder; 0 when fully applied)
SELECT * FROM public.deposit_balance(:d);  SELECT * FROM public.deposits_refund_due;   -- the standing CI-131 obligation
UPDATE public.customers SET status='closed', status_reason='moved', status_changed_by=:user WHERE id=:c;   -- refused until every deposit is settled
```

## Resume Instructions

1. Read Appendix A-7, CI-038 (PSF surcharge; tax-base exclusion), CI-045 (base composition), the v5.4.0-06 PGA patch header, and `schema-parity-plan.md` Wave 2 / Part 6; check what A-1's `rate_item_versions` already carries (calculation_type, display_group, calc_owner, regulatory_class) before adding anything.
2. Draft `sql/v5.4.2-07-…` for A-7. Same loop: fresh-load scratch → strict apply ×2 → battery inside one transaction with an end-to-end `tally_app` path → pre-seeded backfill check if the patch touches history → two independent reviews (`general-purpose` + `codex:codex-rescue`, fresh-load scratch DBs, expect two rounds; send `wc -l` + `md5 -q` with every round-2 request and make reviewers confirm the hash) → mirror after the LAST header banner → fresh rebuild with catalog parity → patch re-apply over the build → DEPLOY-VERIFICATION → register re-grade of exactly the CIs the header names → Appendix → DECISION-LOG / APPLICATION-CONTRACTS → ingestion section → both CHANGELOGs → commit + push both repos.
3. Before the first bill-run calculation code lands: CI-003's GUC net (R-16) and A-3's snapshot value contract + replay function.

## Warnings

- tu.sql APPEND-ONLY; anchors 337/3600/3679. Pin `public, pg_temp`; prove qualification with the strict prelude; backfills that fire v5.2.1 triggers need a txn-local search_path; create guards AFTER the backfill they would refuse.
- Never grant TEMP / CREATE / TRIGGER to `tally_app` without re-reading A-23 (1d).
- Wait for `PostgreSQL init process complete` before touching a freshly run container.
- Never `git add -A` in GBM.
- Fixtures for later patches: customers need `status_reason` on any status change; deposits are events-only; issued invoices reject content edits; reads born `pending_review` → approve.
- Phase 3 judgment-gated items wait; A-8 needs a Kyle brief; finance gate holds A-15/A-6 remainder. Texas-only launch scope.
