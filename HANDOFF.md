# Handoff: docs back in parity with the schema; A-2 still held on Kyle; the meter test history is the next build

**Generated**: 2026-09-23 (documentation-parity session — no schema change landed)
**Branch**: tally-utility `main` · gas-billing-memory `main` (commits for this session follow this file)
**Status**: tu.sql **21,916 lines, through v5.4.2-11** (21 landed patches). **v5.4.2-12 (A-2 backbilling caps) is DRAFTED, reviewed once, NOT landed** — held on two Kyle questions. The planning docs in both repos were brought into parity with the schema this session.

## THE ONE THING TO CARRY FORWARD

**Two things block the critical path, and both are Ryan's to move:**
1. **Has the Kyle brief gone out?** `gas-billing-memory/application/kyle-brief-2026-09-22-a2-two-rulings.md` is "ready to send"; nothing records that it was sent or answered. Q-C (a billing period that straddles the window opening — bill it whole, forfeit it, or split it?) and Q-D ("the last test" — the one that found the error, or the last one that found the meter accurate?) both change the code. Q-D may put the meter test history AHEAD of A-2 (it would become -12 and A-2 -13).
2. **Ryan's six design calls on the meter test history** (brief §8). It is required before launch either way, so it can be drafted now.

**Every patch still ends by calling `public.assert_tenant_isolation_invariants()`** (AC-32), shown to RAISE on planted drift.

**Speak to Ryan in plain language** — item codes (F-5), ruling codes (R-19), contract codes (AC-32) and register entries (CI-046) mean nothing on sight; build the meaning into the question (memory `explain-jargon-in-the-question`). He prefers tradeoffs walked in prose over option menus.

## Done this session (2026-09-23)

A full project assessment (four parallel read-only reviews), then a documentation-parity pass. **No ruling, decision or SQL logic changed.**
- **`sql/v5.4.2-12-backbilling-caps.sql` — comments only.** The comments said a straddling period was "prorated by days" (the code measures the share and the gate REFUSES it), that the gate measured "from the LINE ITEMS" (it takes the greater of lines and `amount_due`), that R9 "requires them to AGREE" (it does not), and the residuals heading said R1–R8. Fixed; one real question surfaced (see Workstream C). Strict apply ×2 clean, battery 66 PASS.
- **tally-utility:** `CONTEXT.md` rewritten (was May: v5.2.1, Supabase, 60 tables); `sql/DEPLOY-VERIFICATION.md` "Current" line now -11; `postgres/Dockerfile` run notes (no `-p 5432`, `docker exec`, strict-apply loop); `tests/README.md` (-12 entry; -11's rounds 4–5 have no committed brief); `ui-concepts/README.md` (T8-2 is built); historical banners on `INVESTIGATION-BRIEF.md` and the stale paragraph of `TECH-STACK-DISCUSSION.md`.
- **gas-billing-memory:** `schema-parity-plan.md` status table (and Kyle's coda backlog A1–A19, none built, now tracked); `CONTEXT.md` rewritten; stale OPEN statuses on answered Kyle documents annotated; the 09-22 "A-2 first" call recorded in the FK inventory and A-2 brief; `canonical-invariants.md` staleness note (~87 of 135 still graded against v5.2.1) and Appendix A headings; `feature-list.md` May-baseline banner and Texas backbilling row fixed; `knowledge/INDEX.md` marks file 23 missing. Ingestion **Section BJ**.

## Not Yet Done — found by the assessment, not housekeeping

- **Scenarios: zero written.** WU5 has axes only; WU7–WU12 not started. They gate application code (and the testing-approach decision). Fixture catalog (WU4) awaits Kyle's sign-off since July.
- **Re-grade the invariant register** (~87 entries still v5.2.1 grades) and **the feature list's schema-status column** (a May baseline: 283 "gap" rows, some since built). Both are real work, not edits — worth an agent-assisted pass.
- **Wiki ingestion:** 61 sections (A–BJ) queued, none ingested; the wiki copy is frozen at 2026-06-07 (`wiki-vault/wiki/projects/tally-utility`, detached HEAD).
- **Knowledge file 23** (competitor site claims) was never committed — re-research or drop.
- **Open calls for Ryan:** the UI prototype's direction; whether Kyle's D-2 satisfies the finance gate; the meter-test-history D-1…D-6.
- **Duplicates:** `application/draft-candidates.md` and `application/session-1-recon.md` are byte-identical copies of GBM `application/invariants/` files, referenced by nothing — candidates for deletion (Ryan's call).
- Unconsolidated Kyle brief candidates (PSF cap $1.00 vs $0.50, deposit-cap ceiling, legacy deposit refunds, and others — list in the schema background below).

## Workstream C — A-2 and the meter test history (the live workstream)

**What is built** (`sql/v5.4.2-12-backbilling-caps.sql`, committed unlanded at `ef27cb1`; comment-only parity edit 2026-09-23 → 2,002 lines, md5 `98e09d7901319ef7036c9e160c0ddc64`, battery 66 PASS re-verified): `backbilling_cap_rules` with both bounds and explicit non-null scope enums on each side, Texas gas seeds for both classes (unprotected rows written explicitly `uncapped`, so an absent rule is an error not a permission); `backbill_cause` + `anchor_date` on the target with the under-reach override in database-stamped write-once columns; `correction_run_target_events` and `backbilling_period_evaluations`, both append-only; the R-30 read classification as a platform-fixed function; gates (ii) and (iii); the -10 target freeze extended to the two new columns; `tenants.regulatory_class_mode` (CCK-14 default, volumetric mode declared but REFUSING); `UNIQUE (id, tenant_id)` on `jurisdictions` and `correction_run_targets` plus the `service_locations.jurisdiction_id` repair; the AC-32 tail.

**Round 1 (Codex + Fable, both on the frozen hash) found four critical/high defects. All fixed, all pinned by battery group J:**

1. **The trim was recorded and never applied** — the evidence row said "forfeited" and the bill issued at the full delta, because the gate only refused a TOTAL trim. Now refused outright pending Q-C.
2. **`amount_due` is caller-set and tied to nothing** (both reviewers, independently). **The first fix was the same defect mirrored** — reading only the line items left the ledger path open, since `void_invoice()` reverses exactly `-(amount_due)`. The measure is now the GREATER of the two paths.
3. **The gate was keyed on `invoice_type`** — a `duplicate`, a `credit_memo`, and a plain `regular` rebill of the voided period all walked past it. Re-keyed on the act: was this premise and period billed before, and does this bill charge more.
4. **The target's `meter_id` / `customer_id` were unbound to the bill they correct**, and both choose the cap. Now bound; the evidence row records the meter and the `last_test_date` it used.

**Residuals stated in the patch tail, R1–R9.** The ones that matter: only Texas gas is seeded (anything else refuses); a tenant created after this patch has no cap rules until onboarding calls `seed_backbilling_cap_defaults()`; an adverse period on a meter with no recorded test refuses rather than inferring a date (R-31); `anchor_basis` is hard-coded `test_date` even for discovery-anchored causes; the enforceable bound is recorded but wired to nothing; and **R9 — `invoices.amount_due` has no tie to its line items**, which A-2 is the first thing to rest a statutory gate on.

**Also recorded for the register, pre-existing and not A-2's:** `tally_app` can post a charge directly into `account_ledger` outside any invoice gate — the ledger and the bill are both application-asserted.

**Not done, all waiting on Kyle:** round 2 reviews (the `patch-12-frozen-r2.sql` copy is superseded by the 09-23 comment edit — **re-freeze before launching**, and add the open item below to the brief); the mirror into `tu.sql`; DEPLOY-VERIFICATION; CI re-grades (CI-008, CI-092, CI-091); the Appendix and DECISION-LOG entries.

**Then, behind A-2 (or possibly ahead of it — see Q-D):** CI-091's append-only meter test history (R-31), required before the first gas tenant goes live.

**Open for review round 2 (found 2026-09-23, comment vs code, logic NOT changed):** gate (iii) measures the previously-billed charge as the MAX over prior voided bills of `backbilling_invoice_charge()` — the GREATER of lines and `amount_due`. An earlier comment claimed the prior side used the LESSER, so an already-divergent legacy bill could not raise the bar. The comment now describes the code and flags the question; the reviewers should decide which measure the prior side needs.

**Meter test history (CI-091)** — specced in GBM `application/ci091-meter-test-history-implementation-brief-2026-09-22.md`, no DDL. Six calls for Ryan (§8 D-1…D-6: two tables vs jsonb; the `test_kind` list; outcome computed by the DB; when customer/location are required; what a late-entered test does to existing evidence; adding `UNIQUE (id, tenant_id)` to `users`). Three for Kyle (§9 K-1…K-3). Needed before launch whichever way Q-D goes; only the ordering depends on Kyle.

## Workstream A — `ui-concepts/` (parked, awaiting Ryan's direction call; unchanged since 2026-09-18)

**Status:** fifteen screens, all ten from the domain report's Screen list, on fixtures. `pnpm dev` on **port 4182**; `pnpm build` and `pnpm check:fixtures` both green; every screen shot in both themes with no console errors. Nothing writes — interactions are presentational by design.

**THE ONE THING TO CARRY FORWARD (UI):** run **`pnpm check:fixtures`** after any fixture edit, and add a check whenever a screen starts *stating* something about data it does not compute. It exists because the bill's derivation rail multiplied by the meter multiplier twice and looked correct on every account for as long as every multiplier was 1.0000. That is the shape of the whole class — an identity that holds for free until the one record arrives where it does not — and four of the five defects found this session were invisible to screenshots. The checks are mutation-tested; a check that has never failed is not evidence of anything.

**Waiting on Ryan:** whether this iteration is the direction. Everything below is cheap to redo and should not be built on until that call is made.

**Ordered queue if it is:** Screen 4's editor half (rate item rows, tier/bracket editor, version diff, rollback — the sandbox half is built); Screen 6's standalone portal view plus hover tooltip, click-a-bar explainer and balance-point line; AR bucket drilldowns (they must sum back to the tile — that reconciliation is T8-6/7's acceptance test); wiring the keyboard affordances, which are drawn but inert.

**Open decision, not a bug:** the shell overflows horizontally below ~600px on every screen — the 208px sidebar and the fixed-width quick-find never collapse. The target user is at a desk, but that should be a decision rather than an accident.

**Do not ingest as canonical:** the G-1 tariff rates, the Texas collections parameters (§7.460 scope is real; the forecast values are not) and the January exposure volumes are prototype inventions chosen to make screens legible. They are internally consistent, which is not the same as true.

---

## Workstream B — schema background: the queue behind A-2 / CI-091

1. The **229-link tenant-blind FK remediation** (~226 remaining; GBM `tenant-blind-foreign-keys-2026-09-22.md`).
2. **A-8** tax jurisdictions (needs a Kyle brief; the shared-place question rides in it), **A-10** revenue distribution (maybe finance-gated), **Wave 4** A-13…A-19, the **customer-class resolver** patch, the **`applies_to_customer_types` defaults** that omit small/large commercial, and **Kyle's coda backlog A1–A19** — all now tracked in the parity plan's status table.
3. **Residuals still open:** -11 R1–R7 (`void_invoice` keeps `public, pg_temp`; ~190 trigger functions not re-pinned; non-definer functions unaudited for PUBLIC EXECUTE; `anomalies.entity_id` has no FK; the matviews have no read path and **`refresh_statistics_views()` has never worked**; a permissive policy with neither clause passes the assertion; the checks name only `tally_app`/PUBLIC). -10: AC-15 "one pair per run" unenforced; `duplicate` unbound; `data_cutoff_at` not a coordinate; `first_issued_at` backfill approximate; `CURRENT_DATE` day boundary. -09: placeholder text like "N/A" passes the evidence test; one tenant's bad notice-days blocks the global queue; legacy `customers.is_tax_exempt` unguarded. Carried: `meter_id` swap on a capped line moves the attribution; -07 LOW residuals. Pre-existing and register-worthy: `tally_app` can post straight into `account_ledger`; `amount_due` is tied to nothing.
4. **Kyle brief candidates, never consolidated:** the PSF cap figure ($1.00 CI-038 vs $0.50 D4-1); whether `is_state_agency` needs a verifying document; meter change-out mid-cycle vs the per-meter cap; K1 (`is_taxable_default`'s silent false) and K4 (`applies_to` vs `is_taxable`); `customers.status` matrix; legacy-deposit refund policy; credit vs disbursement; residential non-cash instruments; instrument-expiry alerting; D14-1b; the Texas deposit-cap ceiling.

## Failed Approaches (Don't Repeat These)

**New in -12 (all four found by review round 1, or by the author fixing it):**
- **A guard that RECORDS its own enforcement instead of performing it.** The trim wrote "9.00 forfeited" to the permanent evidence row, raised a NOTICE saying so, and then let the bill issue at the full 31.00 — the gate refused only a TOTAL trim. A log asserting a control that did not run is worse than no control, because the log is what a regulator reads.
- **A proportional trim of a figure derived from the thing being trimmed.** It has no fixed point: re-drafting at the trimmed amount re-prorates the already-trimmed number, forever. If a rule reduces X and X is computed from the draft, the draft cannot also be the answer.
- **Fixing "the gate reads the wrong number" by reading the OTHER wrong number.** Told `amount_due` was caller-set, the first fix read only the line items — but `void_invoice()` reverses exactly `-(amount_due)`, so that column reaches the ledger regardless. One direction closed, its mirror opened, reproduced. When two fields are both "the money", the fix is a measure over both, not a swap.
- **Keying a guard on what a thing is CALLED rather than what it DOES.** `invoice_type = 'correction'` was walked past by a `duplicate`, a `credit_memo`, and — needing no `replaces_invoice_id` at all — a plain `regular` rebill of the voided period. The patch had quoted "the regulated act is the charge, not the void" one function earlier.
- **Letting a caller name the inputs that choose the rule.** The correction target's `meter_id` and `customer_id` were unbound to the bill being corrected, and both select the cap: a sibling meter with an older test date lengthens the window; a differently-classed customer uncaps it.
- **Recording a window without recording the mutable fact that produced it.** `meters.last_test_date` is overwritten by each test, so an evidence row naming neither the meter nor the date it read could not be re-derived — which is the entire purpose of an evidence row.
- **A constraint that contradicts its own table.** `UNIQUE (target, period)` on an append-only table whose gate demands a fresh row: the gate wants a new answer, append-only forbids editing the old one, and the unique key forbids adding one, so the flow deadlocks. Also: ordering "the row that governs" by `evaluated_at` when `now()` is constant within a transaction — a tie silently picks one of two different answers.
- **Writing a diagnosis into a comment without measuring it.** The equality rule between `amount_due` and the line items was rejected because it broke batteries 10 and 11 — but that had to be confirmed as the cause, rather than cross-battery contamination, before the reasoning was baked into the patch.
- **A battery fixture less realistic than the thing it tests.** The invoices built no line-item `meter_id`, so the meter binding fell through to a weaker premise-level check and the test passed without exercising the rule it named.

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
| A-2 first, the 229-link tenant-blind FK remediation after (Ryan, 2026-09-22) | A-2 repairs the three links it resolves through; the rest are their own patch |

## Current State

**Working**: tu.sql 21,916 lines (through -11), md5 `6edac2aad61505edd5654f214d62b351`. `tally-pg` = fresh build of that file, hash-verified. Only database `tally` exists — clone with `CREATE DATABASE x TEMPLATE tally`.
**Broken (pre-existing, recorded not fixed)**: `refresh_statistics_views()` raises `column reference "view_name" is ambiguous` for every caller.
**Uncommitted**: nothing once this session's commits are pushed.

## Resume Instructions

1. **Ask Ryan whether the Kyle brief went out and whether anything came back.** Fold any answer first — it decides the patch order.
2. **Get Ryan's D-1…D-6 on the meter test history**, then draft it (numbered -12 if Kyle confirms the prior-accurate reading and A-2 becomes -13; otherwise -13 behind A-2). Confirm the §7.45(7)(B) field list against the rule text before freezing — the brief did not re-fetch it.
3. **When Kyle answers:** fold Q-C / Q-D into -12, re-freeze, launch review round 2 with the prior-side measure question in the brief.
4. Same loop as -10/-11/-12: fresh clone (`docker exec` only) → strict apply ×2 (`search_path=''`, `check_function_bodies=on`) → battery in one transaction as `tally_app` → brief with `wc -l` + `md5 -q` → **freeze, launch both reviewers** → fold into ONE revision per round → mirror after the LAST banner → fresh rebuild + catalog parity → batteries green on the build → DEPLOY-VERIFICATION → CI re-grade → Appendix → DECISION-LOG / APPLICATION-CONTRACTS → ingestion section → both CHANGELOGs → **battery + repros into `tests/v5.4.2-NN/`** → commit + push both repos.

## Warnings

- tu.sql **APPEND-ONLY**; mirror the patch BODY only (headers are omitted from mirrors by convention) and `diff` it against the source afterwards.
- **Definer functions running as a superuser pin `SET search_path = ''` with everything qualified; invoker functions keep `public, pg_temp`.** A trigger function MAY now pin `''` (A-23 1c lifted) — the existing ~190 are not re-pinned.
- Never grant TEMP / CREATE / TRIGGER to `tally_app` without re-reading A-23 (1d) — and note the batteries run on clones that HOLD TEMP, so they are not testing the deployed shape.
- Wait for `PostgreSQL init process complete`; run `tally-pg` without `-p`; connect as `-U tally` (there is no `postgres` role).
- Never `git add -A` in GBM. Record every GBM canonical-data change in `application/wiki-ingestion-pending.md`.
- Fixtures for later patches: customers need `status_reason` on any status change; deposits are events-only; issued invoices reject content edits; reads born `pending_review` → approve → `released_to_billing` → `locked` (needs `billing_period_locked` AND `locked_by_billing_run_id`); a surcharge line needs `meter_id` when capped and must be written before its bases; issuance needs snapshot + bases; a billing run needs `started_at` before any snapshot; rule corrections/retractions run only under READ COMMITTED (AC-29); an asserted exemption needs alphanumeric certificate evidence (AC-30); a snapshot's `valid_at` = `period_end`, `recorded_at` ≥ the run's `started_at` (AC-31); `pg_temp` helper functions now need explicit `GRANT EXECUTE … TO tally_app` (the PUBLIC default is revoked).
- Do not land A-2 until Kyle answers Q-C / Q-D. A-8 needs its Kyle brief first. The finance gate holds A-15's finance parts and the A-6 remainder and may hold A-10 — whether Kyle's D-2 (receivables subledger that exports) already satisfies it is an open question for Ryan. Texas-only launch scope.
- `sql/tu.sql`'s header comment is stale (says "v5.2.1 + v5.4.0-00", "roles and GRANTs not yet defined", "regenerated — never hand-edit"). Left untouched on purpose: the file is append-only and the container is hash-verified against it. Fix it, if at all, with the next mirror.
