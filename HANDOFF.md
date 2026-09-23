# Handoff: the meter test history is LANDED (v5.4.2-12); A-2 re-drafts next as -13

**Generated**: 2026-09-23 (end of session)
**Branch**: tally-utility `main` · gas-billing-memory `main` (both pushed at wrap)
**Status**: tu.sql **23,452 lines, through v5.4.2-12** (22 landed patches), md5 `2aa59147bfde61d86991f7f0a5c5d22a`; `tally-pg` rebuilt fresh from it and hash-verified. The A-2 draft is `sql/v5.4.2-13-backbilling-caps.sql` — renumbered, still saying -12 inside, still predating Kyle's R-32…R-39. **Next is its re-draft.**

## THE ONE THING TO CARRY FORWARD

**Re-draft A-2 as v5.4.2-13 on top of the landed meter test history, to Kyle's R-32…R-39** (GBM `application/kyle-decisions-2026-09-22-a2-straddle-and-meter-test-anchor.md` §8 and `kyle-decisions-2026-09-23-a2-override-and-cause-freeze.md` "What changes in the A-2 patch"). The landed -12 hands A-2 its facts: call **`meter_governing_test(meter, anchor)`** for "the last test" (never `meters.last_test_date`), cite **`meter_test_id`** on the evidence row, **enforce** the returned `supervisor_gate` (R-36) — -12 computes it but nothing acts on it yet — and flag evidence when a test arrives `entered_out_of_order` (D-5). The window is `max(anchor − 6 months, governing test_date)`; with no qualifying test, the six-month cap alone (R-35 ref. 5 — the old draft's refusal is wrong).

**Every patch ends by calling `public.assert_tenant_isolation_invariants()`** (AC-32), shown to RAISE on planted drift. **Speak to Ryan in plain language** (memory `explain-jargon-in-the-question`); he prefers tradeoffs in prose over option menus.

## Done this session (2026-09-23)

1. **Full project assessment** (four parallel read-only reviews) and a **documentation-parity pass** in both repos (CONTEXT ×2, the parity plan's status table, answered-but-OPEN Kyle documents, staleness banners on the invariant register and feature list, -12's comments corrected to its code).
2. **Kyle's R-32…R-39 found at push time** (he had answered everything) and folded into every status line.
3. **v5.4.2-12, the meter test history — drafted, five review rounds, LANDED.** `meter_tests` (append-only; outcome and `found_defective` derived by the database from submitted raw readings against the platform-fixed `meter_accuracy_thresholds`), `meter_test_load_results`, the meters test columns as a refused-to-write pointer, `meter_test_absence_declarations`, `meter_governing_test()` (R-34, with R-36's gate flag), `meter_test_history_gaps`, **`tenants.cutover_date`** (platform-set; migrated ≤ cutover ≤ recorded; logged), and a guard that only a platform admin makes a platform admin. Ryan chose the `test_kind` list (D-2). Battery **116**, isolation 3, race script PASS, regressions 28/58/41, **21 planted mutations each caught**; catalog parity on a fresh build. Records: DEPLOY-VERIFICATION, DECISION-LOG D-2026-09-23-01…-10, **AC-33**, GBM CI-091 re-graded / CI-092 noted, parity plan, ingestion **Section BL**, both CHANGELOGs.
4. The A-2 draft renamed to `v5.4.2-13-backbilling-caps.sql`; its tests to `tests/v5.4.2-13/`.

## Workstream C — A-2 re-draft as v5.4.2-13 (the live workstream)

**What Kyle's R-32…R-39 change in the old draft:** the trim mechanism is deleted — an adverse period straddling the window is **forfeited whole** (R-32) with an append-only forfeiture row; `meter_error` corrections are **adjustments on a subsequent bill**, not void-and-rebill (R-33) — which likely moves the gate off `correction_run_targets` (its `voided_invoice_id` is NOT NULL) toward `adhoc_charges`, **but Kyle's OQ-1 (does R-33 also cover non-registering and tampering causes?) must be ruled before the adjustment-path DDL**; meter-error corrections are non-disconnectable except tampering (F-1); no qualifying prior test → six-month cap, not refusal (R-35 ref. 5); the under-reach override is withdrawn in the favourable direction for a computed bound, meter-scoped targeting and a two-code hold (R-37); cause and anchor freeze at evidence-freeze with supersession and a tamper gate (R-38); an eight-value cause domain, `tampering_theft` renamed `tampering_bypass` (R-39). New schema homes still undesigned: a per-service-location predecessor acquisition date (R-37). (-12 supplied the per-tenant cutover date.)

**Still true of the old draft, and worth keeping:**
**Round 1 (Codex + Fable, both on the frozen hash) found four critical/high defects. All fixed, all pinned by battery group J:**

1. **The trim was recorded and never applied** — the evidence row said "forfeited" and the bill issued at the full delta, because the gate only refused a TOTAL trim. Now refused outright pending Q-C.
2. **`amount_due` is caller-set and tied to nothing** (both reviewers, independently). **The first fix was the same defect mirrored** — reading only the line items left the ledger path open, since `void_invoice()` reverses exactly `-(amount_due)`. The measure is now the GREATER of the two paths.
3. **The gate was keyed on `invoice_type`** — a `duplicate`, a `credit_memo`, and a plain `regular` rebill of the voided period all walked past it. Re-keyed on the act: was this premise and period billed before, and does this bill charge more.
4. **The target's `meter_id` / `customer_id` were unbound to the bill they correct**, and both choose the cap. Now bound; the evidence row records the meter and the `last_test_date` it used.

**Residuals stated in the patch tail, R1–R9.** The ones that matter: only Texas gas is seeded (anything else refuses); a tenant created after this patch has no cap rules until onboarding calls `seed_backbilling_cap_defaults()`; an adverse period on a meter with no recorded test refuses rather than inferring a date (R-31); `anchor_basis` is hard-coded `test_date` even for discovery-anchored causes; the enforceable bound is recorded but wired to nothing; and **R9 — `invoices.amount_due` has no tie to its line items**, which A-2 is the first thing to rest a statutory gate on.

**Also recorded for the register, pre-existing and not A-2's:** `tally_app` can post a charge directly into `account_ledger` outside any invoice gate — the ledger and the bill are both application-asserted.

**Open for review round 2 (found 2026-09-23, comment vs code, logic NOT changed):** gate (iii) measures the previously-billed charge as the MAX over prior voided bills of `backbilling_invoice_charge()` — the GREATER of lines and `amount_due`. An earlier comment claimed the prior side used the LESSER, so an already-divergent legacy bill could not raise the bar. The comment now describes the code and flags the question; the reviewers should decide which measure the prior side needs.

## Not Yet Done — from the assessment

- **Scenarios: zero written.** WU5 has axes only; WU7–WU12 not started; they gate application code. The fixture catalog (WU4) awaits Kyle's sign-off.
- **Re-grade the invariant register** (~87 entries still v5.2.1 grades) and **the feature list** (a May baseline).
- **Wiki ingestion:** Sections A–BL queued, none ingested; the wiki copy is frozen at 2026-06-07.
- **Knowledge file 23** (competitor claims) was never committed.
- **Open calls for Ryan:** the UI prototype's direction; whether Kyle's D-2 satisfies the finance gate; which of `meters.num_dials` / `dial_count` is authoritative (Kyle's side finding); whether to delete `application/draft-candidates.md` and `session-1-recon.md` (unreferenced duplicates of GBM files).
- **Open with Kyle:** OQ-1 (above); **whether a meter test recorded against the wrong date may be corrected, and under what gate** (new, -12 residual R13); the counsel bundle; the customer-type default widening; the A-8 brief.
- **Codex as a reviewer:** it is installed only under Node v24.15.0 (`~/.nvm/versions/node/v24.15.0/bin/codex`); this shell uses v24.19.0, so the plugin cannot find it, and a direct run stalled with no output (likely an unanswered sandbox approval for `docker exec`). Fable + Opus reviewed -12. Ryan to decide how Codex should run before relying on it again.

## Workstream A — `ui-concepts/` (parked, awaiting Ryan's direction call; unchanged since 2026-09-18)

**Status:** fifteen screens, all ten from the domain report's Screen list, on fixtures. `pnpm dev` on **port 4182**; `pnpm build` and `pnpm check:fixtures` both green; every screen shot in both themes with no console errors. Nothing writes — interactions are presentational by design.

**THE ONE THING TO CARRY FORWARD (UI):** run **`pnpm check:fixtures`** after any fixture edit, and add a check whenever a screen starts *stating* something about data it does not compute. It exists because the bill's derivation rail multiplied by the meter multiplier twice and looked correct on every account for as long as every multiplier was 1.0000. That is the shape of the whole class — an identity that holds for free until the one record arrives where it does not — and four of the five defects found this session were invisible to screenshots. The checks are mutation-tested; a check that has never failed is not evidence of anything.

**Waiting on Ryan:** whether this iteration is the direction. Everything below is cheap to redo and should not be built on until that call is made.

**Ordered queue if it is:** Screen 4's editor half (rate item rows, tier/bracket editor, version diff, rollback — the sandbox half is built); Screen 6's standalone portal view plus hover tooltip, click-a-bar explainer and balance-point line; AR bucket drilldowns (they must sum back to the tile — that reconciliation is T8-6/7's acceptance test); wiring the keyboard affordances, which are drawn but inert.

**Open decision, not a bug:** the shell overflows horizontally below ~600px on every screen — the 208px sidebar and the fixed-width quick-find never collapse. The target user is at a desk, but that should be a decision rather than an accident.

**Do not ingest as canonical:** the G-1 tariff rates, the Texas collections parameters (§7.460 scope is real; the forecast values are not) and the January exposure volumes are prototype inventions chosen to make screens legible. They are internally consistent, which is not the same as true.

---

## Workstream B — schema background: the queue behind A-2

1. The **229-link tenant-blind FK remediation** (~226 remaining; GBM `tenant-blind-foreign-keys-2026-09-22.md`).
2. **A-8** tax jurisdictions (needs a Kyle brief; the shared-place question rides in it), **A-10** revenue distribution (maybe finance-gated), **Wave 4** A-13…A-19, the **customer-class resolver** patch, the **`applies_to_customer_types` defaults** that omit small/large commercial, and **Kyle's coda backlog A1–A19** — all now tracked in the parity plan's status table.
3. **Residuals still open:** -12 R1–R19 (stated in its tail: the fee rule unenforced; customer not bound to the location on the test date; the threshold keyed by the meter's current location, which tally_app can move; the A-2 couplings recorded but not enforced; the platform guards name `tally_app`; section 1b is not a role model; same-day readings rows ranked by entry order).  -11 R1–R7 (`void_invoice` keeps `public, pg_temp`; ~190 trigger functions not re-pinned; non-definer functions unaudited for PUBLIC EXECUTE; `anomalies.entity_id` has no FK; the matviews have no read path and **`refresh_statistics_views()` has never worked**; a permissive policy with neither clause passes the assertion; the checks name only `tally_app`/PUBLIC). -10: AC-15 "one pair per run" unenforced; `duplicate` unbound; `data_cutoff_at` not a coordinate; `first_issued_at` backfill approximate; `CURRENT_DATE` day boundary. -09: placeholder text like "N/A" passes the evidence test; one tenant's bad notice-days blocks the global queue; legacy `customers.is_tax_exempt` unguarded. Carried: `meter_id` swap on a capped line moves the attribution; -07 LOW residuals. Pre-existing and register-worthy: `tally_app` can post straight into `account_ledger`; `amount_due` is tied to nothing.
4. **Kyle brief candidates, never consolidated:** the PSF cap figure ($1.00 CI-038 vs $0.50 D4-1); whether `is_state_agency` needs a verifying document; meter change-out mid-cycle vs the per-meter cap; K1 (`is_taxable_default`'s silent false) and K4 (`applies_to` vs `is_taxable`); `customers.status` matrix; legacy-deposit refund policy; credit vs disbursement; residential non-cash instruments; instrument-expiry alerting; D14-1b; the Texas deposit-cap ceiling.

## Failed Approaches (Don't Repeat These)

**New in -12, the meter test history (each found by review, each pinned by a battery check and a planted mutation):**
- **Fixing a rule for the linked path and leaving the parallel path open.** Correction rules on `supersedes_test_id` were walked around three rounds running by a second same-date row that superseded nothing. A rule about what may replace a fact has to bind every row that can displace it — here, the readers' ranking.
- **A "platform-only" control resting on a column nothing guards.** The cutover rested on `is_platform_admin()`; `users.role` was writable by the tenant, then `users.id` (the lookup key) was. Check what the predicate reads, not just what it names.
- **Stating a gate in the inverse arithmetic of the bound it guards.** `anchor < cutover + 6 months` is not `anchor − 6 months < cutover` at month ends; 48 cutover dates in 2024–2030 lapsed the gate early.
- **A caller-chosen input choosing the rule** (the threshold's state from a caller-named location) — the HANDOFF already listed this shape; the first draft still had it.
- **Locks stronger than the conflict needs.** `FOR SHARE` on the tenant deadlocked; `FOR UPDATE` on the meter blocked every FK insert. `KEY SHARE` / `NO KEY UPDATE` sufficed.
- **A pointer written only when it changes.** A snapshot-isolation insert then refreshed it from a stale view; writing unconditionally makes the row version the mutex.
- **A planted mutation that "fails" for the wrong reason.** Two mutations first failed on a PK error or a broken `sed`, not on the guard — read the failing check's name before counting it caught.

**From the A-2 draft (now -13), found by its review round 1:**
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
| D-2026-09-23-01…-10 (v5.4.2-12): Ryan's `test_kind` list; results derived from raw readings; cutover platform-set with migrated ≤ cutover ≤ recorded; the R-36 gate in A-2's arithmetic; corrections keep date/basis/readings; same-date ranking readings → failure → result → basis → entry; only an admin makes an admin, ids immutable; pointer written every insert; KEY SHARE / NO KEY UPDATE locks; A-2 renumbered -13 | See DECISION-LOG 2026-09-23 |

## Current State

**Working**: tu.sql 23,452 lines (through -12), md5 `2aa59147bfde61d86991f7f0a5c5d22a`. `tally-pg` = fresh build of that file (image rebuilt, fresh volume), hash-verified, zero init errors. Only database `tally` exists — clone with `CREATE DATABASE x TEMPLATE tally`.
**Broken (pre-existing, recorded not fixed)**: `refresh_statistics_views()` raises `column reference "view_name" is ambiguous` for every caller.
**Uncommitted**: nothing once this session's commits are pushed.

## Resume Instructions

1. `git fetch` BOTH repos first — Kyle pushes to GBM `main` directly (memory `fetch-gbm-before-orienting`).
2. Read Kyle's two records' "what changes" sections and the -12 header (it is the contract A-2 builds on: AC-33).
3. Re-draft `sql/v5.4.2-13-backbilling-caps.sql` (rename its internal -12 references; rename `tests/v5.4.2-13/battery-12.sql`). Build everything except the adjustment path; ask Kyle for OQ-1 in a short plain-language brief if it is still open.
4. The loop, as for -12: fresh clone → strict apply ×2 → battery as `tally_app` → **mutation-test every guard** → freeze → two independent reviewers → one revision per round → mirror after the last "sound enough to mirror" → rebuild → catalog parity → batteries on the build → DEPLOY-VERIFICATION → CI re-grades → DECISION-LOG / APPLICATION-CONTRACTS → ingestion section → both CHANGELOGs → commit + push both repos.

## Warnings

- tu.sql **APPEND-ONLY**; mirror the patch BODY only (headers are omitted from mirrors by convention) and `diff` it against the source afterwards.
- **Definer functions running as a superuser pin `SET search_path = ''` with everything qualified; invoker functions keep `public, pg_temp`.** A trigger function MAY now pin `''` (A-23 1c lifted) — the existing ~190 are not re-pinned.
- Never grant TEMP / CREATE / TRIGGER to `tally_app` without re-reading A-23 (1d) — and note the batteries run on clones that HOLD TEMP, so they are not testing the deployed shape.
- Wait for `PostgreSQL init process complete`; run `tally-pg` without `-p`; connect as `-U tally` (there is no `postgres` role).
- Never `git add -A` in GBM. Record every GBM canonical-data change in `application/wiki-ingestion-pending.md`.
- Fixtures for later patches: customers need `status_reason` on any status change; deposits are events-only; issued invoices reject content edits; reads born `pending_review` → approve → `released_to_billing` → `locked` (needs `billing_period_locked` AND `locked_by_billing_run_id`); a surcharge line needs `meter_id` when capped and must be written before its bases; issuance needs snapshot + bases; a billing run needs `started_at` before any snapshot; rule corrections/retractions run only under READ COMMITTED (AC-29); an asserted exemption needs alphanumeric certificate evidence (AC-30); a snapshot's `valid_at` = `period_end`, `recorded_at` ≥ the run's `started_at` (AC-31); `pg_temp` helper functions now need explicit `GRANT EXECUTE … TO tally_app` (the PUBLIC default is revoked).
- Do not draft A-2's adjustment path before Kyle rules OQ-1. A-8 needs its Kyle brief first. The finance gate holds A-15's finance parts and the A-6 remainder and may hold A-10 — whether Kyle's D-2 (receivables subledger that exports) already satisfies it is an open question for Ryan. Texas-only launch scope.
- `sql/tu.sql`'s header comment is stale (says "v5.2.1 + v5.4.0-00", "roles and GRANTs not yet defined", "regenerated — never hand-edit"). Left untouched on purpose: the file is append-only and the container is hash-verified against it. Fix it, if at all, with the next mirror.

- **Fixtures that touch meter tests (from -12 on):** set `tenants.cutover_date` as the owner (or a platform admin) before any test; recorded tests must be dated on or after it, migrated ones on or before; a recorded full test needs `performed_by_name`, `test_equipment`, `meter_serial_at_test`, `multiplier_at_test` and readings (or an `inconclusive_reason`); the premise's `state` must be `TX` for a gas threshold to resolve; `meters.last_test_*` cannot be set by any fixture.
- **Mutation-test every guard before freezing** (-12 did 21): break it with `sed`, confirm the NAMED check fails for the RIGHT reason, restore. A check no mutation can fail is not evidence.
