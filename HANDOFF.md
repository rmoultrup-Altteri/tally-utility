# Handoff: A-2 is unfenced and specced — one scope call stands between it and DDL; `ui-concepts/` still awaits a direction call

**Generated**: 2026-09-22 (wrap — documentation and scoping session, no DDL; both repos committed and pushed, working trees clean)
**Branch**: tally-utility `main` · gas-billing-memory `main` @ `a8d3478`
**Status**: **Kyle's Part 4 CLOSED 2026-09-14 — the A-2 fence is LIFTED.** v5.4.2-11 remains the last patch (tu.sql 21,916 lines; container rebuilt and verified this session, zero init errors). A-2 is consolidated into an implementation brief with Ryan's four scope decisions taken; two questions are with Kyle and are not blocking. One scope call is open (below). Also found and documented: **229 tenant-blind foreign keys**, live-verified.

## THE ONE THING TO CARRY FORWARD

**Read `gas-billing-memory/application/a2-implementation-brief-2026-09-21.md` first — sections 7 and 8 especially.** It consolidates R-19…R-31 plus the CCK rulings into a buildable spec, re-based against `tu.sql`, and records eight places where the rulings collide with the shipped schema. Four of those are decided (§7); the fifth is the only thing still open.

**Speak to Ryan in plain language.** He owns the schema but did not author the decision corpus — item codes (F-5), ruling codes (R-19, CCK-14), contract codes (AC-32) and register entries (CI-046) mean nothing to him on sight. Build the meaning into the question. He asked for this explicitly on 2026-09-21; memory `explain-jargon-in-the-question`.

**Every patch still ends by calling `public.assert_tenant_isolation_invariants()`** (AC-32), now written into the parity plan's per-wave acceptance rather than living only in narrative about v5.4.2-11.

## THE OPEN CALL — where the FK remediation patch sits

229 foreign keys name a target row's id without its tenant. The question is whether that patch lands **before** A-2, **after** it, or is **split** with the 96-link `users` tier going early on its own. My recommendation is after: A-2 has statutory weight and a closed ruling set, and this has been latent since the schema was written. Full inventory and reasoning in `tenant-blind-foreign-keys-2026-09-22.md`.

## Workstream C — A-2 (the live workstream)

**Decided by Ryan 2026-09-22** (all recorded in the brief §7, in plain language):

1. **Ship the simple protection default.** CCK-14's `all_non_residential_protected` — no volumetric resolver, no per-meter determination record, no promote/demote hysteresis inside A-2. Roughly halves the patch and errs toward protection, which can never be a violation. CCK-4…CCK-13 become their own later patch.
2. **The under-reach override gets a database-stamped write-once home**, not a row in `invoice_events` — that log is app-insertable, so the software could otherwise clear its own warning. The log keeps the audit trail; it stops being what the gate believes.
3. **The correction-run target rows get their own append-only log** for setup-time events, because `invoice_events.invoice_id` is NOT NULL and at gate (ii) no correction invoice exists yet.
4. **Build narrow on both Kyle questions.** `backbill_cause` / `anchor_date` freeze at snapshot existence rather than at post; the override takes a short evidentiary-impossibility reason-code list rather than free text. Both are narrower than R-19 / R-27 as written, both are with Kyle, and narrow-first is the cheap direction under an append-only schema.

**With Kyle, not blocking** — `application/kyle-questions-2026-09-22-a2-override-and-cause-freeze.md`: is the evidentiary-impossibility list the right list, and is freezing the cause at the snapshot consistent with what R-19 intended?

**Still to decide inside the patch** (recorded in the brief §4): `invoice_events.event_type` needs new values; `jurisdictions` needs `UNIQUE (id, tenant_id)` before A-2's link can be tenant-checked; the billable bound needs the same explicit discriminator R-20 gave the enforceable one (a NULL read as "no limit" bills past statutory authority); and both new tables are born leaky under AC-32.

**Known provisional:** A-2's jurisdiction work may be partly redone if the shared-place split goes ahead — see `jurisdictions-shared-place-modelling-2026-09-22.md`. One constraint and one FK, cheap to redo, recorded knowingly rather than discovered later.

**Then, immediately behind A-2:** CI-091's append-only meter test history table (R-31) — its own brief and patch, required before the first gas tenant goes live, because `meters.last_test_date` is a single mutable field overwritten by each test, so any period without history is a permanent hole.

---

## Workstream A — `ui-concepts/` (parked, awaiting Ryan's direction call)

**Status:** fifteen screens, all ten from the domain report's Screen list, on fixtures. `pnpm dev` on **port 4182**; `pnpm build` and `pnpm check:fixtures` both green; every screen shot in both themes with no console errors. Nothing writes — interactions are presentational by design.

**THE ONE THING TO CARRY FORWARD (UI):** run **`pnpm check:fixtures`** after any fixture edit, and add a check whenever a screen starts *stating* something about data it does not compute. It exists because the bill's derivation rail multiplied by the meter multiplier twice and looked correct on every account for as long as every multiplier was 1.0000. That is the shape of the whole class — an identity that holds for free until the one record arrives where it does not — and four of the five defects found this session were invisible to screenshots. The checks are mutation-tested; a check that has never failed is not evidence of anything.

**Waiting on Ryan:** whether this iteration is the direction. Everything below is cheap to redo and should not be built on until that call is made.

**Ordered queue if it is:** Screen 4's editor half (rate item rows, tier/bracket editor, version diff, rollback — the sandbox half is built); Screen 6's standalone portal view plus hover tooltip, click-a-bar explainer and balance-point line; AR bucket drilldowns (they must sum back to the tile — that reconciliation is T8-6/7's acceptance test); wiring the keyboard affordances, which are drawn but inert.

**Open decision, not a bug:** the shell overflows horizontally below ~600px on every screen — the 208px sidebar and the fixed-width quick-find never collapse. The target user is at a desk, but that should be a decision rather than an accident.

**Do not ingest as canonical:** the G-1 tariff rates, the Texas collections parameters (§7.460 scope is real; the forecast values are not) and the January exposure volumes are prototype inventions chosen to make screens legible. They are internally consistent, which is not the same as true.

---

## Workstream B — schema background (unchanged since v5.4.2-11; A-2 supersedes its queue)

## Goal

Bring `sql/tu.sql` (the only enforcement artifact — no application code exists) to parity with the spec corpus per `gas-billing-memory/application/schema-parity-plan.md`. **Superseded 2026-09-22:** Kyle's Part 4 is closed and A-2 is the live item — Workstream C above replaces this section's queue. The failed approaches, key decisions and warnings below all still stand.

## THE ONE THING TO CARRY FORWARD

**Every patch from now on calls `public.assert_tenant_isolation_invariants()` in its tail** (contract: AC-32). This is not decoration. The invariants it checks are true when a patch applies and **drift at the next `CREATE`**, because `tu.sql:11388`'s `ALTER DEFAULT PRIVILEGES … ON TABLES TO tally_app` covers views and matviews:

- a new **table** with a `tenant_id` column is born with **no RLS at all** and readable by `tally_app`
- a new **view** is born owner-rights (`CREATE VIEW` has no `security_invoker` default) and the owner is a BYPASSRLS superuser
- a new **matview** is born app-readable and can carry neither `security_invoker` nor RLS — the grant is the only lever
- a new **SECURITY DEFINER function** was born PUBLIC-executable until this patch revoked the global default

The container build runs the assertion last. If it raises, read the HINT — it names the exact DDL.

## Completed (2026-09-09, v5.4.2-11)

- [x] Ten items landed. Two owner-rights views → `security_invoker`; the two RLS policy helpers qualified + pinned `''` (they must stay definer — the `users` policy calls them); `validate_custom_fields` + `get_correction_rate_date` → invoker, the former with an explicit NULL-safe tenant refusal; EXECUTE revoked from PUBLIC on all five definers **and** from the global default; `anomalies.entity_type` gets a 15-value singular domain; four statistics matviews revoked; the verification lifted into `assert_tenant_isolation_invariants()`, extended in round 3 to cover TABLES.
- [x] Five hash-frozen rounds (`133546f8` → `5b27cc38` → `1a0f6c84` → `c35698ac` → `a275c67d`), both reviewers, every finding folded into one revision per round. Rounds 4 and 5 each found a defect in code written *during* the review.
- [x] Verified: strict apply ×2 (`search_path=''`, `check_function_bodies=on`) clean and idempotent; battery 41; probe 11 holes on -10 and 11 `as expected` patched; -09 (28) and -10 (58) green on the shipped build; mirror body byte-identical to the patch body (`diff`); container hash-matched.
- [x] Docs: DEPLOY-VERIFICATION; DECISION-LOG D-2026-09-09-01…-09; **AC-32**; both CHANGELOGs. GBM: **A-23 (1g)** (1c/1d/1f-residue closed, 1d's TEMP premise amended), `exception-threshold-and-routing.md` note 2 RESOLVED, parity plan Wave 3 line, ingestion **Section BB**.
- [x] Memory: `checks-narrower-than-their-claim`, `reviewer-fixes-need-measuring`; `depth-fence-needs-no-temp` amended with the clone/TEMP gap.

## Not Yet Done — the Kyle-independent queue, in order

- [ ] **Socialize AC-29 / AC-30 / AC-31 / AC-32** into the parity plan and ingestion where not yet referenced. AC-32 matters most: it changes how every future patch ends.
- [ ] **Consolidate the Kyle brief candidates** into one document (GBM has the Part 4 index; these are not in it): the PSF cap figure ($1.00 CI-038 / KB vs $0.50 D4-1); whether `is_state_agency` needs a verifying document; meter change-out mid-cycle vs the per-meter cap; K1 (`is_taxable_default`'s silent false) and K4 (`applies_to` vs `is_taxable`); `customers.status` matrix; legacy-deposit refund policy; credit vs disbursement; residential non-cash instruments; instrument-expiry alerting; D14-1b; the Texas deposit-cap ceiling; the `applies_to_customer_types` default-widening confirmation.
- [ ] **A-10** (revenue distribution matrix) — last unfenced Wave 3 item; composes with GL neighbours behind the finance gate, so decide with Ryan whether it goes now or slips.
- [ ] **A-2** when Part 4 is empty (Kyle: items 3–7 + item-2 semantics pick). **A-8** when its brief is answered.
- [ ] **-11 residuals (R1–R7, stated in its header):** `void_invoice` keeps `public, pg_temp`; the ~190 trigger functions are not re-pinned to `''` though A-23 (1c) now permits it; non-definer functions unaudited for PUBLIC EXECUTE; `anomalies.entity_id` has no polymorphic FK; **the matviews have no read path and `refresh_statistics_views()` has never worked** — the dashboard work fixes both; a permissive policy with neither `USING` nor `WITH CHECK` passes the assertion (fail-closed); the matview/definer checks name `tally_app`/PUBLIC, so a future second app role would be unwatched.
- [ ] **-10 residuals:** AC-15 "one pair per run" unenforced; `duplicate` unbound; `data_cutoff_at` deliberately not a coordinate; `first_issued_at` backfill for pre-patch void rows is an approximation; the current-rules election inherits `CURRENT_DATE`'s session day boundary.
- [ ] Carried "Open for Ryan": `meter_id` swap on a capped line moves the attribution; the -07 LOW residuals; the -09 residuals (letter-bearing placeholders like "N/A" pass the evidence test; one tenant's bad notice-days value loud-blocks the platform admin's global queue; legacy `customers.is_tax_exempt` unguarded, display-only).

## Failed Approaches (Don't Repeat These)

**New in -11:**
- **A self-check filtered by a narrower key than the property it certifies.** `relkind = 'v'` while asserting "views run with invoker rights" — blind to four leaking matviews one relkind away and 79 tables two away. Same shape three more times: `has_table_privilege` ignores COLUMN grants; a five-signature by-name check cannot see the sixth function; `coalesce(polqual, polwithcheck)` never inspects `WITH CHECK` while `USING` is non-NULL (read-isolated, write-OPEN). Write the assertion against the property, and **test that it RAISES** (memory: `checks-narrower-than-their-claim`).
- **Folding a reviewer's proposed FIX without measuring it.** Three were wrong; the findings were all real (memory: `reviewer-fixes-need-measuring`).
- **`ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE … FROM PUBLIC`** — a silent no-op. PUBLIC's EXECUTE lives in the GLOBAL, schema-less default; only the unqualified `FOR ROLE` form works.
- **A `security_invoker` wrapper over a materialized view** — impossible; it needs the CALLER to hold SELECT on the matview, which is the grant being removed.
- **`RETURNING` on a cross-tenant INSERT in a test** — it re-applies the SELECT policy and fails with an RLS error that looks like the write was blocked, masking a write hole.
- **Asserting a performance claim instead of measuring it** — "evaluated once per query" was false for seq-scan filters (+45%, measured).
- **Trusting a battery's environment** — `CREATE DATABASE … TEMPLATE` does not copy `datacl`, so every battery here runs with TEMP that the deployed DB revokes.

**Carried from earlier patches:** `btrim(x) <> ''` as a blank check; fixing an off-by-one's display column instead of its boundary; checking config shape only at the leaf; trusting a container by its timestamp; freezing `created_at` only while a snapshot exists; accepting any `void` row as a correction's original; uniqueness per (run, replaced bill); FOR SHARE on a heartbeated row; an isolation pin where a row version does the work; counting rebills by caller-chosen `invoice_type`; templating two-session race scripts with sed; a disk-wide `find`; leaving batteries in the scratchpad; `pg_trigger_depth() = 0` as an INSERT fence; an advisory lock as a count-guard's concurrency control; netting negative lines against a cap; trusting the snapshot's coordinate pair in a gate; later facts on a frozen bi-temporal row; editing the patch while reviewers test; closing one vector at a time; `WHERE _f.k = k` in a SQL helper; `INSERT … SELECT FROM (INSERT … RETURNING)`; a serial column under `SET ROLE tally_app`; `docker run -p 5432:5432`.

## Key Decisions (durable copies: `application/DECISION-LOG.md`)

| Decision | Rationale |
|---|---|
| D-2026-09-09-01: `get_correction_rate_date` → invoker, not revoked | A revoke deletes a documented capability; PUBLIC held EXECUTE anyway, so the revoke was a no-op |
| -02: the blanket PUBLIC EXECUTE cleanup is in scope | Five named revokes do not stop the sixth function |
| -03: fifteen singular `entity_type` values; no `adhoc_charge`/`service_order` | Widening a CHECK is one line; narrowing means cleaning up routed rows |
| -04: the four matviews are REVOKED, not wrapped | A matview takes neither `security_invoker` nor RLS; an owner-rights wrapper is the same shape as the hole |
| -05: the verification becomes a function every patch calls | Invariants are true at apply time and drift at the next `CREATE`; an event trigger would add the privileged surface this patch removes |
| -06: the assertion covers TABLES, folded in not deferred | A gate silent on 79 of 82 tables invites the confidence the `relkind` filter already cost once |
| -07: `polqual`/`polwithcheck` checked independently; RESTRICTIVE exempt | Coalescing left tables write-open; restrictive policies are AND-ed and can only narrow |
| -08: the operand-order false positive is ACCEPTED | Fails closed and loudly; one canonical spelling is worth the friction |
| -09: the broken `refresh_statistics_views()` is recorded, not fixed | Unrelated pre-existing defect; the dashboard work fixes read path and refresh path together |
| A-2 is a brief, not a patch, until Part 4 is empty | Kyle's own record fences it |

## Current State

**Working**: tu.sql 21,916 lines (through -11). `tally-pg` = fresh build of that file, hash-verified. Only database `tally` exists — clone with `CREATE DATABASE x TEMPLATE tally`.
**Broken**: nothing known. (Pre-existing, recorded not fixed: `refresh_statistics_views()` raises `column reference "view_name" is ambiguous` for everyone.)
**Uncommitted**: nothing; both repos pushed.

## Resume Instructions

1. **Read the A-2 implementation brief** (`gas-billing-memory/application/a2-implementation-brief-2026-09-21.md`), §7 and §8 first. Part 4 closed 2026-09-14 — do not re-check the fence, it is lifted.
2. **Get Ryan's one open call** (where the FK remediation patch sits relative to A-2), then draft A-2 DDL against the brief. CI-091's meter test history follows immediately behind it.
3. Still queued but subordinate to A-2: socialize AC-29 / AC-30 / AC-31 (their likely home is the register and the fixture catalog, not the acceptance line — AC-32 is done); consolidate the Kyle brief candidates; A-10 with Ryan when the finance gate is settled.
3. **Whatever you draft, end the patch by calling `public.assert_tenant_isolation_invariants()`** and add its checks to your battery. If you add a table, view, matview or definer function, the assertion tells you what you forgot.
4. Same loop as -10/-11: fresh clone (`docker exec` only) → strict apply ×2 (`search_path=''`, `check_function_bodies=on`) → battery in one transaction as `tally_app` → brief with `wc -l` + `md5 -q` → **freeze, launch both reviewers** → fold into ONE revision per round → mirror after the LAST banner → fresh rebuild + catalog parity → batteries green on the build → DEPLOY-VERIFICATION → CI re-grade → Appendix → DECISION-LOG / APPLICATION-CONTRACTS → ingestion section → both CHANGELOGs → **battery + repros into `tests/v5.4.2-NN/`** → commit + push both repos.

## Warnings

- tu.sql **APPEND-ONLY**; mirror the patch BODY only (headers are omitted from mirrors by convention) and `diff` it against the source afterwards.
- **Definer functions running as a superuser pin `SET search_path = ''` with everything qualified; invoker functions keep `public, pg_temp`.** A trigger function MAY now pin `''` (A-23 1c lifted) — the existing ~190 are not re-pinned.
- Never grant TEMP / CREATE / TRIGGER to `tally_app` without re-reading A-23 (1d) — and note the batteries run on clones that HOLD TEMP, so they are not testing the deployed shape.
- Wait for `PostgreSQL init process complete`; run `tally-pg` without `-p`; connect as `-U tally` (there is no `postgres` role).
- Never `git add -A` in GBM. Record every GBM canonical-data change in `application/wiki-ingestion-pending.md`.
- Fixtures for later patches: customers need `status_reason` on any status change; deposits are events-only; issued invoices reject content edits; reads born `pending_review` → approve → `released_to_billing` → `locked` (needs `billing_period_locked` AND `locked_by_billing_run_id`); a surcharge line needs `meter_id` when capped and must be written before its bases; issuance needs snapshot + bases; a billing run needs `started_at` before any snapshot; rule corrections/retractions run only under READ COMMITTED (AC-29); an asserted exemption needs alphanumeric certificate evidence (AC-30); a snapshot's `valid_at` = `period_end`, `recorded_at` ≥ the run's `started_at` (AC-31); `pg_temp` helper functions now need explicit `GRANT EXECUTE … TO tally_app` (the PUBLIC default is revoked).
- Do not draft A-2 or A-8 DDL while Kyle's Part 4 is open. Finance gate holds A-15 / A-6 remainder and may hold A-10. Texas-only launch scope.
