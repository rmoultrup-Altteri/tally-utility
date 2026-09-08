# Handoff: v5.4.2-10 landed (A-3 follow-up — the snapshot coordinate pair is bound; A-23 1e closed); A-2 fenced on Kyle's Part 4; next is the rest of the Kyle-independent queue

**Generated**: 2026-09-08 (evening — v5.4.2-10 landed after five hash-frozen review rounds; housekeeping earlier the same day)
**Branch**: tally-utility `main` · gas-billing-memory `main` (both committed + pushed at wrap; GBM's unrelated untracked `Clippings/` left alone)
**Status**: **v5.4.2-10 DONE** (`sql/v5.4.2-10-snapshot-coordinate-binding.sql`, 980 lines, md5 `f143c1cb…`; tu.sql 20,407 → **21,165**; battery 58 in `tests/v5.4.2-10/`; catalog 82 tables / 255 triggers (187 ENABLE ALWAYS) / 392 functions / 357 FKs; container `tally-pg` = fresh build of the committed tu.sql). Earlier: **A-9 DONE** (`sql/v5.4.2-09-tax-exemption-renewal-and-certificate-evidence.sql`, 464 lines, md5 `90af192e…`, three hash-frozen review rounds; tu.sql 20,094 → **20,407**). **A-2 is a brief, not a patch, and is fenced**: Kyle's own 2026-09-02 record says "do not implement until Part 4 is empty" — items 3–7 plus the item-2 semantics pick remain, worked one per Kyle session. **A-8 held** for its brief. Phase 4: Wave 1 ✅, Wave 2 ✅, Wave 3: A-9 ✅ · A-2 ⏸ (Kyle) · A-10 open. Batteries live in `tests/`.

## Goal

Bring `sql/tu.sql` (the only enforcement artifact — no application code exists) to parity with the spec corpus per `gas-billing-memory/application/schema-parity-plan.md`. While Kyle works Part 4, do the Kyle-independent queue (below) rather than idle or pre-empt his rulings.

## Completed

**2026-09-08 (evening, v5.4.2-10):**
- [x] Read A-23 1e, the -04 patch, the resolver, CI-003/005/015; wrote the design question up for Ryan in plain language; Ryan: strict on both calls.
- [x] Drafted, five review rounds (Fable + Codex; hashes `bb7cdbd9` → `9160f8af` → `2530daf7` → `2d0ece3c` → `f143c1cb`), every finding folded into one body per round; round 5 clean.
- [x] Battery 58 (clean, pre-seeded, build), nine live races, mirror, fresh rebuild, catalog parity, -09 battery still green; DEPLOY-VERIFICATION, D-2026-09-08-01…-09, AC-31, CHANGELOG; GBM CI-015/CI-005/CI-003 re-checks, A-23 (1f), parity plan, ingestion Section BA, GBM CHANGELOG.
- [x] Memory: `count-guards-need-lock-handshake` refined (row-version mutex; FOR KEY SHARE on heartbeated rows; stated lock order), `app-written-logs-are-not-guards`.

**2026-09-08 (morning, housekeeping):**
- [x] `tests/` created; `tests/v5.4.2-09/` holds the battery (28 checks), review brief, reviewer seed, precondition seed, nine repros, four author attacks. Battery re-run from `tests/` against a clone of the container build: 28 PASS. `tests/README.md` = run recipe + battery conventions. The -07 / -08 batteries were lost with their scratchpads (recorded).
- [x] CHANGELOG repaired: the -09 entry had been written into the -08 entry; the -08 header is restored, -09 has its own Next. Housekeeping entry added.
- [x] Container verified against the committed file by hash and by catalog counts (not by timestamp).
- [x] This HANDOFF rewritten.

**2026-09-04 (A-9 session):**
- [x] Kyle's four records processed (R-19…R-25 backbilling; CCK-1…14 customer-class keying; CCK-15/15b + dashboard composition). Nothing folded into the schema — Part 4 fence.
- [x] Part 4 item 2's Ryan-assigned half verified against tu.sql (GBM `259efe2`, `application/a2-part4-item2-tu-rebase-verification-2026-09-04.md`): a plain child of `jurisdictions` fails on state-default rows and NULL premises — the cap table needs fallback semantics (nullable `jurisdiction_id` = state default) or folds into A-8; Kyle picks. The `applies_to_customer_types` size-tier defect re-targeted to `franchise_fee_rules` (tu.sql 3022) + `rate_item_versions` (15376); the AR-tile hazard confirmed.
- [x] **v5.4.2-09 landed** (CI-046's remainder — A-1 had already rebuilt `customer_tax_exemptions`): `tax_exemption_certificate_required(tenant, type)` (settings accessor, DEFAULT TRUE per R-13 / Rule 3.287, raises on unknown category or wrong shape at ANY path level); evidence gate folded into `enforce_tax_exemption_lifecycle` (entry to any asserted state needs `certificate_number` or `certificate_url` with ≥1 alphanumeric char; drafts free; asserted rows never re-judged; config flips audited by `tenant_configuration_history`); self-verifying precondition over every CURRENT head (active / expired / revoked — `customer_tax_exemption_as_of` does not filter status); `tax_exemption_renewal_notice_days(tenant)` (default 60) + `customer_tax_exemptions_renewal_due` (security_invoker; enters at exactly N days remaining, `<=`; lapsed rows stay until their expiry succession).
- [x] Reviews: `b8318398` → `af834c44` → `90af192e`; round 1 Codex CRITICAL (btrim passed a tab as evidence) + HIGH (precondition ignored current revoked heads); round 2 Codex caught the `<` boundary bent to the display and the ancestor-shape hole; round 3 both "sound enough to mirror".
- [x] Docs: DEPLOY-VERIFICATION -09; D-2026-09-04-01…-07; AC-30; tally CHANGELOG. GBM: CI-046 amended, Appendix A-9 LANDED, parity plan A-9 struck / A-2 annotated Kyle-fenced (Section AY); Kyle outstanding-items index (`kyle-outstanding-2026-09-05.md`, Section AZ).
- [x] Memory: `blank-checks-whitelist-alnum`, `test-the-boundary-not-the-formula`.

**Earlier (2026-08-31):** A-7 (v5.4.2-07) and its freeze family (v5.4.2-08) — see CHANGELOG entries and DEPLOY-VERIFICATION; the -08 contract is AC-29.

## Not Yet Done — the Kyle-independent queue, in order

- [ ] **Small structural residuals** as a sibling patch: the four pre-existing views' `security_invoker` check; A-23's three unpinned SECURITY DEFINER functions (`get_user_tenant_id`, `is_platform_admin`, `validate_custom_fields`) and — new from -10 — revoking `tally_app`'s direct EXECUTE on `get_correction_rate_date` (SECURITY DEFINER, reads any tenant's target by id); `anomalies.entity_type` CHECK.
- [ ] **Socialize the -08 / -09 / -10 contracts** (AC-31: the coordinate binding, the freezes, READ COMMITTED for run-election edits, the lock order invoice → lineage root → replaced bill → target → run; AC-29: rule corrections under READ COMMITTED only, capped-line writers retry on serialization failure; AC-30: certificate evidence + config shape + renewal queue) into the parity plan / ingestion where they are not yet referenced.
- [ ] **Consolidate the Kyle brief candidates** into one document (GBM already has the Part 4 index; the carried items below are not in it): the PSF cap figure ($1.00 CI-038 / KB vs $0.50 D4-1 note); whether `is_state_agency` needs a verifying document; meter change-out mid-cycle vs the per-meter cap; K1 (`is_taxable_default`'s silent false) and K4 (`applies_to` vs `is_taxable`); `customers.status` matrix; legacy-deposit refund policy; credit vs disbursement; residential non-cash instruments; instrument-expiry alerting; D14-1b; the Texas deposit-cap ceiling; the `applies_to_customer_types` default-widening confirmation.
- [ ] **A-10** (revenue distribution matrix) — the last unfenced Wave 3 item; composes with GL neighbours behind the finance gate, so decide with Ryan whether it goes now or slips.
- [ ] **A-2** when Part 4 is empty (Kyle: items 3–7 + item-2 semantics pick). **A-8** when its brief is answered.
- [ ] **-10 residuals (stated in its header):** AC-15 "one pair per run" unenforced; `duplicate` unbound; `data_cutoff_at` deliberately not a coordinate; `first_issued_at` backfill for pre-patch void rows is an approximation; the current-rules election inherits `CURRENT_DATE`'s session day boundary.
- [ ] Carried "Open for Ryan": `meter_id` swap on a capped line moves the attribution (stated, not closed); the -07 LOW residuals (kind-labelled PSF EXCLUDE; mutex-row deadlock = retry); the -09 residuals (letter-bearing placeholders like "N/A" pass the evidence test; one tenant's bad notice-days value loud-blocks the platform-admin's global queue; legacy `customers.is_tax_exempt` unguarded, display-only).

## Failed Approaches (Don't Repeat These)

- **`btrim(x) <> ''` as a blank check** — passed a single tab / NBSP as certificate evidence. Whitelist ≥1 `[[:alnum:]]` character; coalesce the NULL leg in trigger IFs (memory: `blank-checks-whitelist-alnum`).
- **Fixing an off-by-one's display column instead of its boundary** — a battery check that asserts a column against its own formula proves nothing. Decide which side is right, then pin both sides to concrete dates (memory: `test-the-boundary-not-the-formula`).
- **Checking config shape only at the leaf** — a malformed `tax_exemptions` node itself silently defaulted. Raise at every path level.
- **Trusting a container by its timestamp** — the image was built an hour before the commit. Hash the init-dir schema file against the repo and compare catalog counts.
- **Freezing `created_at` only while a snapshot exists** — the unsnapshotted draft is where a caller moves it. Write-once always.
- **Accepting any `void` row as a correction's original** — a held-then-voided discard is void and never billed; the app-written `invoice_events` cannot be the check (tally_app can INSERT there). The DB needs its own stamp (`first_issued_at`).
- **Uniqueness per (run, replaced bill), then per bill** — a second run, then a second hop, rebilled the same bill. Scope to the lineage; mutex on the root.
- **FOR SHARE on a heartbeated row** — every plain UPDATE waits behind the writer; two workers deadlock. FOR KEY SHARE + FOR UPDATE escalation in the waiting guard.
- **An isolation pin where a row version does the work** — write `updated_at` on the row the editor must also update; Postgres's own `serialization_failure` handles RR. Pin only where no version can be written (the heartbeated run row).
- **Counting rebills by caller-chosen `invoice_type`** — count by the lineage link; refuse the link on non-rebill types.
- **Templating two-session race scripts with sed** — a broken session never committed and the race "passed". Write each session's SQL in full.
- **A disk-wide `find` for stray files** hangs the shell; search the known scratchpad roots.
- **Leaving batteries in the scratchpad** — -07 and -08 are gone. Commit to `tests/` in the same commit as the patch.
- **`pg_trigger_depth() = 0` as an INSERT fence** — inside the trigger a direct statement is depth 1. `< 2`.
- **An advisory lock as a count-guard's concurrency control** — serialises writers, not snapshots. Mutex row + FOR SHARE handshake + READ COMMITTED pin.
- **Netting negative lines against a cap** — leaks via discard / void. Positives only.
- **Trusting the snapshot's (valid_at, recorded_at) in a gate** — caller-supplied by A-3's design. Judge on now() (until A-23 1e lands).
- **Later facts on a frozen bi-temporal row** (`remitted_on`, `renewal_notice_sent_at`) — those are communication-log work.
- **Editing the patch while reviewers test** — freeze the hash, one revision per round.
- **Closing one vector at a time and disclaiming the rest** — enumerate the family first (-08 had five legs).
- **`WHERE _f.k = k` in a SQL helper** — the column shadows the parameter; prefix `p_`.
- **`INSERT INTO t SELECT … FROM (INSERT … RETURNING)`** — not SQL; use a `WITH … RETURNING` CTE.
- **A serial column in a results table under `SET ROLE tally_app`** — default privileges skip sequences; GRANT USAGE.
- **`docker run -p 5432:5432`** — the port belongs to another project; run without `-p`, use `docker exec`.

## Key Decisions (durable copies: `application/DECISION-LOG.md`)

| Decision | Rationale |
|---|---|
| D-2026-09-04-01: evidence = ≥1 alphanumeric character, a content whitelist | Every whitespace blacklist has a next member |
| -02: precondition blocks on EVERY current head (active / expired / revoked) | A current revoked head still suppresses tax on rebills |
| -03: certificate-required is per category in `tenants.settings`, DEFAULT TRUE, raising accessor, wrong shape at any level raises | R-13 / Rule 3.287; silent defaults hide misconfiguration |
| -04: no stored renewal fields; the prompt is a view + a window config | The `remitted_on` lesson — later facts on a frozen assertion |
| -05: queue admits at exactly N days (`<=`); lapsed stays listed until the expiry succession | `<` silently gave N−1 days; a renewal on file does not close a lapse |
| -06: legacy `customers.is_tax_exempt` stays unguarded | `should_charge_tax` never reads it — display-only, recorded residual |
| -07: no per-category validity period seeded | No citable figure (the R-21 lesson) |
| A-2 is a brief, not a patch, until Part 4 is empty | Kyle's own record fences it; implementing now decides open items by inertia |
| -08 (D-2026-08-31-09…-12): line, invoice and rule move only together; corrections under READ COMMITTED only | The five 2.00-on-a-1.00-cap vectors were one family |
| -07 (D-2026-08-31-01…-08): D4-1 read strictly — cap + exemption + exclusion, no remittance gate | Kyle decided the gate the other way |

## Current State

**Working**: tu.sql 21,165 lines (through -10). `tally-pg` = fresh build of that file (zero init errors; catalog 82 tables / 81 policies / 80 FORCE RLS / 357 CHECKs / 357 FKs / 10 EXCLUDE / 59 UNIQUEs / 255 triggers, 187 ENABLE ALWAYS / 571 indexes / 392 functions; TEMP revoked). Only database `tally` exists on it — clone with `CREATE DATABASE x TEMPLATE tally`.
**Broken**: nothing known.
**Uncommitted**: nothing after the -10 commit (both repos pushed).

## Code Context

Patch headers are the contracts (`sql/v5.4.2-09-…` lines 1–~150 for A-9). Write protocols: AC-26…AC-30. A-9 in one glance:

```sql
-- per-category knob (DEFAULT TRUE when absent); wrong shape at any level raises
UPDATE public.tenants SET settings = jsonb_set(settings, '{tax_exemptions,certificate_required,government}', 'false') WHERE id = :t;
-- draft needs nothing; entry to assertion needs evidence with >=1 alphanumeric char
INSERT INTO public.customer_tax_exemptions (tenant_id, customer_id, exemption_type, effective_start) VALUES (:t, :c, 'religious', '2026-01-01');
UPDATE public.customer_tax_exemptions SET status = 'active', verified_by = :u, verified_at = now(), certificate_number = 'TX-12345' WHERE id = :e;
SELECT * FROM public.customer_tax_exemptions_renewal_due;   -- due (<= N days) and lapsed rows, renewal-suppressed
```

Battery recipe: `tests/README.md`.

## Resume Instructions

1. Next Kyle-independent item: the **structural residuals patch** (`v5.4.2-11`): four pre-existing views' `security_invoker`; pin/qualify the three unpinned SECURITY DEFINER helpers (A-23 1b/1c — after this, trigger functions may pin `''`); revoke `tally_app`'s direct EXECUTE on `get_correction_rate_date` or wrap it invoker-rights; `anomalies.entity_type` CHECK. Small header, full loop.
2. Same loop as -09: fresh clone (`docker exec` only) → strict apply ×2 → battery inside one transaction as `tally_app` → pre-seeded precondition check → brief with `wc -l` + `md5 -q` → **freeze, launch both reviewers** → fold → next round → mirror after the LAST banner → fresh rebuild + catalog parity → battery green on the build → DEPLOY-VERIFICATION → CI re-grade → Appendix → DECISION-LOG / APPLICATION-CONTRACTS → ingestion section → both CHANGELOGs → **battery + repros into `tests/v5.4.2-NN/`** → commit + push both repos.
3. Check GBM for a new Kyle record before each session (`git -C ~/code/gas-billing-memory log --oneline -5`; `application/kyle-decisions-*`). If Part 4 has emptied, A-2 moves ahead of everything.

## Warnings

- tu.sql APPEND-ONLY; anchors 337/3600/3679. Pin `public, pg_temp`; prove qualification with the strict prelude; guards after the backfills they would refuse; a "written by the DB" fence is `pg_trigger_depth() < 2`.
- Never grant TEMP / CREATE / TRIGGER to `tally_app` without re-reading A-23 (1d).
- Wait for `PostgreSQL init process complete` before touching a freshly run container; run `tally-pg` without `-p`; connect as `-U tally` (there is no `postgres` role).
- Never `git add -A` in GBM. Record every GBM canonical-data change in `application/wiki-ingestion-pending.md`.
- Fixtures for later patches: customers need `status_reason` on any status change and their history is DB-written only; deposits are events-only; issued invoices reject content edits; reads born `pending_review` → approve; a surcharge line needs `meter_id` when capped and must be written before its bases; issuance needs snapshot + bases; a ruled line's `rate_item_id`/`invoice_id` and its invoice's `invoice_date` are frozen; rule corrections/retractions run only under READ COMMITTED (AC-29); an asserted exemption needs alphanumeric certificate evidence unless its category is flag-only (AC-30); a snapshot's `valid_at` = `period_end`, `recorded_at` ≥ the run's `started_at` (the run must have started) or the draft's `created_at`; a correction needs a correction run + target row and a void, once-issued original (`void_invoice()` after issuing to pending); `started_at` / `created_at` / `first_issued_at` are DB-stamped; edit a run's election under READ COMMITTED only (AC-31).
- Do not draft A-2 or A-8 DDL while Kyle's Part 4 is open. Finance gate holds A-15 / A-6 remainder and may hold A-10. Texas-only launch scope.
