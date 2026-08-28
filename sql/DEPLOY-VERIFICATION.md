# Deploy verification — tu.sql

**Current: v5.2.1 + v5.4.0-00 through v5.4.0-06 + v5.4.1-01 + v5.4.1-02 + v5.4.2-01 through v5.4.2-05, verified 2026-08-28.** After v5.4.2-05: **73 tables** / **72 policies** / **71 FORCE-RLS** / **316 CHECKs** / 7 EXCLUDE / **213 triggers** (**146 ENABLE ALWAYS**) / 531 indexes / 324 FKs / 50 UNIQUEs; tu.sql **17,704 lines** (pure appends; anchors 337/3600/3679 intact).

## v5.4.2-05 — A-20: read/bill exception queue and validation-state substrate (Phase 4 Wave 2; CI-112/113/115/023; Kyle D14-1)

`sql/v5.4.2-05-read-and-bill-exception-substrate.sql` (1,081 lines), mirrored into tu.sql (16,811 → **17,704**, pure append; anchors intact). New `read_validation_exceptions` (CI-112 queue: born open, resolved once with a disposition / reason / resolver / server time, frozen after; over-cap rows resolve only by override or field order), `invoice_exceptions` (CI-115 queue with table #35's routing outputs; resolved/overridden with reason, frozen; `blocks_delivery` frozen at insert), the read gate `enforce_read_exception_gate` (no open exception on any step into approved/released/locked; `validated_at` server-stamped on the first billable entry and frozen; validated-read facts frozen), the D14-1 counter on `meters` (`consecutive_estimate_count` / streak start / last validated actual, maintained only by the gate — `pg_trigger_depth` guard — and equal to `consecutive_estimate_state()` by construction: validated estimates dated after the latest-dated validated actual), the auto-raised `consecutive_estimate_over_cap` exception (`max_consecutive_estimates()` from tenant settings, default 3), `billing_run_meters` gates for open exceptions and `meter_master_incomplete_reasons()` (CI-023), the `invoices` pre-delivery gate (no pending/sent/`sent_at`/`delivery_confirmed_at` with an open blocking exception), `invoice_events` lineage (enum + 3), tenant-bound composite FKs (new UNIQUEs on meters/meter_readings/service_orders) and same-tenant user/anomaly checks, RLS + FORCE, `REVOKE DELETE`, every guard `ENABLE ALWAYS`. Backfill: `validated_at` stamped on historical billable reads (stray values on non-billable reads cleared), counter derived from the same function, three reporting NOTICEs, never a refusal.

**Method.** Fresh-loaded scratch → strict apply ×2 → **battery 154 checks green** (inside one transaction; `tally_app` end-to-end for both queues) → pre-seeded scratch (mixed history incl. same-day estimate+actual, back-dated actual, excluded-after-approval, stray `validated_at`, cap-0 tenant) → apply: stored = derived on every meter, NOTICEs, re-apply a no-op → mirror → **fresh rebuild** zero init errors, catalog identical to the patched scratch (73 tables / 213 triggers, **146 ENABLE ALWAYS** / 316 CHECKs / 324 FKs / 7 EXCLUDE / 72 policies / 71 FORCE RLS / 531 indexes / 50 UNIQUEs) → patch re-applied over the build clean → battery 154 green on the build.

**Reviews (fresh-load scratch DBs incl. pre-seeded, strict prelude, two rounds each; the file changed four times between rounds and both re-loaded).** Round 1 — Fable: CRITICAL (backfill aborted on a same-day estimate+actual), HIGH ×2 (the rework loop approved→pending→approved recounted one estimate to the cap; an exception raised after approval was not gated into released/locked), MEDIUM ×2 (stored ≠ derived after exclusion and after a back-dated actual; the backfill NOTICE raised on a cap < 1), LOW ×2 (INSERT skipped the reviewed_* checks; estimates pending together never auto-raised). Codex: CRITICAL (void_released → released_to_billing bypassed the gate), HIGH (derive dropped excluded reads), MEDIUM (cross-tenant `resolved_by`/`raised_by`/`assigned_to`/`anomaly_id`), then in round 2 a second CRITICAL against the first rework: a back-dated actual validated after in-streak estimates reset the streak and let five estimates pass a cap of 3. The author's own passes found: post-approval edits to `is_estimated`/register/date desyncing the counter; the backfill's trigger toggle failing on queued deferred-FK events; the v5.2.1 meters triggers breaking under the strict prelude inside the backfill. **All fixed by mechanism** (D-2026-08-28-25…-33): the streak is now defined once — validated estimates dated after the latest-dated validated actual — and the gate, the derivation and the backfill all use it. Round 2 — both "sound enough to mirror"; Fable wrote an independent battery of the date-bounded rule (chained back-dates, same-day actual, concurrent estimate + back-dated actual) and Codex re-ran all its repros incl. chained back-dating.

| test | result |
|---|---|
| strict apply ×2 fresh; ×1 over the mirrored build; ×3 after committed rows (reviewers) | clean, idempotent |
| read exception: born resolved / meter or tenant mismatch / duplicate open rule / resolve without reason / field order missing or other meter / replacement = same read / identity edit / edit resolved / DELETE / unknown rule / cross-tenant raised_by or resolved_by | each rejected; notes+severity edit on open ok |
| read gate: approve or reviewed_clean with open exception; reviewed_with_exception without a row (UPDATE and INSERT); approve after resolve; exception raised after approval blocks released_to_billing; exception on locked/void_released read; void_released → released_to_billing with an open exception | as designed |
| billing_run_meters: billed against open-exception read; billed on incomplete master (no pressure class / elevated without factor / no rollover or dials); skipped outcomes; complete → billed | as designed |
| counter: actual approved → 0 + last; estimates → 1, 2 (RF-collision counts); 3rd insert auto-raises; approve refused; resolve as estimate_accepted refused; override → 3; 4th → field order → 4; secondary register / excluded-before-approval / failed actual do not move it; validated actual → 0; direct writes to the three columns rejected (also replica mode); rework loop counts once; exclusion after validation keeps the count; back-dated actual does not clear later estimates and the next estimate is refused at cap; latest-dated actual clears; estimate dated before the last actual uncounted; three pending together → third auto-raises; cap 1 born-approved refused; cap 0 raises; default 3; cap lowered after insert → refused until an operator raises + overrides; stored = derived asserted after every step | as designed |
| validated-read freeze: is_estimated / register_type / meter_id / reading_date after approval; caller-supplied validated_at | rejected / replaced |
| invoice exceptions: blocking on draft → `exception_raised` event; born resolved / tenant or run mismatch / duplicate open criterion / carry-forward without link / flip blocks_delivery / resolve without reason / cross-tenant assigned_to or resolved_by / DELETE / bogus criterion or queue / blank routing_reason | each rejected |
| pre-delivery gate: draft→pending, held→pending blocked; override with reason → `exception_overridden` event; second blocking criterion still blocks; resolve → pending ok; pending→sent and `sent_at` blocked by a new blocking row; resolve → sent; blocking row on a delivered invoice rejected, non-blocking ok; non-blocking never gates; draft delete cascades; invoice_events append-only, old types valid | as designed |
| `tally_app`: raise/resolve read exception; estimate insert (auto-raise path) and approval (counter path); raise + override invoice exception and release; DELETE denied; op1 sees only T1; op2 sees nothing of T1 and cannot raise on it | as designed |
| backfill on seeded history: same-day tie / back-dated actual / excluded-after-approval / stray validated_at / cap-0 tenant | stored = derived on every meter; NOTICEs; re-apply no-op |
| fresh rebuild: init errors / catalog parity / patch re-apply / battery | 0 / identical / 0 errors / 154 green |

## v5.4.2-04 — A-3: invoice calculation snapshots, Option B (Phase 4 Wave 1; CI-015)

`sql/v5.4.2-04-invoice-calculation-snapshots.sql` (722 lines), mirrored into tu.sql (16,245 → **16,811**, pure append; anchors 337/3600/3679 intact). New `invoice_calculation_snapshots` (one per invoice, composite-FK'd to `invoices(id, tenant_id)` — new UNIQUE on invoices; the run's `(valid_at, recorded_at)` pair; `snapshot_schema_version` with an enumerated key contract `v1` enforced by `validate_calculation_snapshot()`; `formula_version`; eight JSONB sections mirroring CI-015's input list; GENERATED sha256 `content_hash`), `invoice_snapshot_references` (provenance citations into the seven A-1 tables, verified open at the snapshot's `recorded_at`), the DEFERRABLE `enforce_invoice_has_snapshot` completeness gate on `invoices` (draft/held → void exempt), immutability guards (UPDATE never; INSERT/DELETE only while the parent is draft/held; cascade on draft delete), RLS + FORCE, `REVOKE UPDATE` from `tally_app`, every guard `ENABLE ALWAYS`.

**Method.** Scratch DB fresh-loaded from the committed tu.sql → strict apply (`SET search_path = ''; SET check_function_bodies = on;`) twice, and again over the mirrored fresh build → **battery 90 checks green** (run inside one transaction so `SET LOCAL ROLE tally_app` takes effect) on the scratch DB and again on the fresh build → four two-session races (issue vs snapshot delete / line edit / delete-then-issue / citation insert) each rejecting exactly one side, no deadlock → **fresh rebuild** from `postgres/Dockerfile`: zero init errors, catalog identical to the patched scratch (71 tables / 201 triggers, **134 ENABLE ALWAYS** / 294 CHECKs / 308 FKs / 7 EXCLUDE / 70 policies / 69 FORCE RLS / 517 indexes / 46 UNIQUEs).

**Reviews (fresh-load scratch DBs, strict prelude, two rounds each).** Round 1 — Fable: CRITICAL ×2 (`SET search_path = ''` on the new functions made the first RLS policy evaluation call the unqualified v5.2.1 helpers `get_user_tenant_id()`/`is_platform_admin()` — `tally_app` could not write a snapshot or issue an invoice at all; a two-session race let an invoice commit as issued with its snapshot deleted / a line edited / a citation added), HIGH (`void_invoice()` on a held invoice demanded a snapshot), MEDIUM (amounts compared after a `numeric(12,2)` cast — `20.004` matched `20.00`; string amounts accepted), LOW ×2 (contract text; `CREATE TABLE IF NOT EXISTS` does not migrate an FK change) + a cascade addendum (replica-mode draft delete orphans a snapshot — accepted, noted). Codex: the same CRITICAL (search_path/RLS), everything else sound. The author's own second pass found the draft-delete FK block. **All fixed by mechanism** (D-2026-08-28-16…-23). Round 2 — both: "sound enough to mirror"; Fable re-ran every round-1 repro; Codex ran the races live with `clock_timestamp()` blocking proof and chained the void exemption (void is terminal; dead end).

| test | result |
|---|---|
| strict standalone apply on a fresh-loaded scratch, ×2; over the mirrored fresh build ×1; after committed post-patch rows (both reviewers) | clean, idempotent |
| valid `v1` snapshot on a draft; second snapshot; UPDATE (content, notes); `content_hash` write; `captured_at` forgery | ok; unique violation; rejected ×2; rejected; replaced by `now()` |
| unknown/malformed schema version; missing keys in every section incl. nested `items[]`/`reads[]`/`line_items[]`; WNA-when-applied keys; non-boolean `applied`; non-array/non-object sections | each rejected with the key named |
| period / customer / billing_run / tenant mismatch; future `recorded_at`; blank `formula_version` | each rejected |
| `line_items` missing a line, wrong amount, another invoice's line, duplicate citation, `20.004` vs `20.00`, amount as JSON string | each rejected |
| provenance: open version / active exemption cited; duplicate; cross-tenant; nonexistent; unknown `source_table`; tenant mismatch; UPDATE; row not yet asserted at the coordinate; row closed before it; pending (draft) exemption | as designed (draft and closed rows are not citable) |
| issuance: with snapshot; without; held without; stale (line edited) → delete + re-snapshot → issue; period changed after snapshot; new invoice draft → lines → snapshot → pending in one batch; direct INSERT as pending | as designed |
| after issuance: DELETE snapshot / INSERT+DELETE citation / TRUNCATE ×2; `void_invoice()` keeps the snapshot; voided snapshot DELETE; snapshot for a legacy already-issued invoice; `void_invoice()` on a held invoice without snapshot | rejected ×5; kept; rejected; rejected; allowed |
| replica mode: UPDATE snapshot; issue without snapshot | both still rejected |
| `tally_app`: no UPDATE privilege; no context → 0 rows; op1 sees only T1 on both tables; cannot write a T2 snapshot; **end-to-end draft → snapshot → citation → issue as tally_app**; cannot delete the issued snapshot; op2 sees only T2 | as designed |
| draft invoice DELETE with snapshot + citation cascades; issued invoice DELETE still rejected (A-4) | as designed |
| two-session races A/B/C/D (author; Fable both orderings; Codex with blocking timings) | exactly one side rejected each time; no deadlock |
| fresh rebuild: init errors / catalog parity / patch re-apply / battery | 0 / identical / 0 errors / 90 green |

## v5.4.2-03 — A-1: bi-temporal transaction-time substrate (Phase 4 Wave 1; CI-001/002/005/011; Kyle R-9…R-17)

`sql/v5.4.2-03-bitemporal-substrate.sql` (1,909 lines), mirrored into tu.sql (14,499 → **16,245**, pure append; anchors 337/3600/3679 intact). Header/version split for `rate_schedules` / `wna_zones` / `rate_items` (new `rate_schedule_versions`, `wna_zone_versions`, `rate_item_versions`); in-place `recorded_at`/`recorded_until` + closing-event columns on `rate_schedule_items`, `franchise_fee_rules`, `customer_tax_exemptions`, `wna_monthly_adjustments`; three table-wide UNIQUEs → open-rows exclusion/partial constraints; seven two-axis `*_as_of()` lookups; `should_charge_tax` / `get_partial_period_policy` re-issued on both axes; `get_effective_rate` and `archive_rate_item_history` disabled; `rate_item_history`/`_archive` retired read-only; six CASCADEs stripped; ten tables join the CI-014 set; every new guard `ENABLE ALWAYS`. Self-verifying preconditions refuse `industrial` exemptions, unverified asserted exemptions, unapproved non-pending WNA rows, `superseded` franchise rows, archived rows without an expiry, `expired`/`archived` schedules.

**Method.** Fresh container from the committed v5.4.2-02 build → pre-patch seed (2 tenants, schedule active + draft, zone, 3 rate items incl. 3 `rate_item_history` brackets, override, franchise rule, exemptions active/pending/**industrial**, WNA approved/pending, meter, draft invoice line) → strict apply refused on the `industrial` row (R-13) → re-keyed → strict apply (`SET search_path = ''; SET check_function_bodies = on;` prelude, `-1`) clean → applied again twice, and a fourth time after committing post-patch rows (Fable H7): all zero errors. **Battery: 166 checks green** on that container (backfill of all three history cases; guards; corrections/retractions/successions; R-9/R-11/R-12/R-13/R-14/R-17 rules; RLS as `tally_app` for two tenants; replica-mode bypass; every review finding). **Fresh rebuild** from `postgres/Dockerfile`: zero init errors; catalog identical to the patched container (69 tables / 194 triggers, **127 ENABLE ALWAYS** / 283 CHECKs / 302 FKs / **7 EXCLUDE** / 68 policies / 67 FORCE RLS / 333 functions / 507 indexes); the patch file re-applied over the mirrored build: zero errors; an 18-check functional smoke set on the fresh build green (the 166-battery needs pre-patch seed rows, so it runs on the upgrade path only — recorded, not hidden).

**Reviews (fresh-load scratch DBs, strict prelude, two rounds each).** Round 1 — Codex: CRITICAL (cross-entity `supersedes_id` / table-wide successor check on 6 of 7 tables — reproduced: a zone silently lost its current assertion under a "superseded" label), MEDIUM (caller-forgeable `recorded_at`). Fable: CRITICAL ×2 (caller-supplied transaction time on both axes; post-patch `backfill` inserts as a born-closed door), HIGH ×7 (lineage unvalidated; revoke-beside-active kept a customer exempt; R-9 bracket shift; R-17 bypass via retract-then-`initial`; retracted rows gaining successors; drafts satisfying "superseded"; re-apply broken by a post-patch row), MEDIUM ×5 (headers unreconciled with archive; version rows not tenant-bound; `should_charge_tax` definer leak; `get_correction_rate_date` unpinned; free-hand stamps), LOW ×5. **Every CRITICAL/HIGH/MEDIUM fixed** (DECISION-LOG D-2026-08-28-02…-12). Round 2 — both: "sound enough to mirror"; every round-1 repro re-run and rejected; residuals taken (N4 successor-retracted-in-txn, M1b archived terminal on all headers, N7/timing COMMENTs) or recorded (raw version bump; N anomalies per bracket; draft-header versions assert immediately; fan-out of `supersedes_id`).

| test | result |
|---|---|
| strict standalone apply on seeded v5.4.2-02 container; then ×3 more (one after committed post-patch rows) | clean, idempotent |
| R-13 precondition with a seeded `industrial` exemption | refused with count; clean after re-key |
| backfill: schedule/zone → one `backfill` version at `created_at`; rate item no-history → live row; closed+open brackets → two rows; all-closed → bracket + live row from `max(end_date)+1` | as designed (7 checks) |
| in-place edit / DELETE / TRUNCATE / born-closed / close without reason / close with content change / overlap / correction without reason / successor of open predecessor | each rejected |
| caller-supplied `recorded_at` (insert, draft→asserted) and `recorded_until` (close) | replaced by `now()`; `backfill` insert rejected |
| cross-entity, cross-tenant, retracted-predecessor `supersedes_id`; draft or retracted successor at commit | each rejected |
| correction: as_of at `now()` → corrected; at `now() − 1µs` and at last year → original; closed row frozen; FKs untouched | as designed |
| R-9: valid-time-dated service change; shifted-bracket correction; retract-then-`initial`/`succession` re-tag | each rejected; same-service succession accepted |
| R-17: basis missing / basis without change / illegal basis; legitimate correction on a billed schedule | rejected ×3; anomalies row with `invoices_affected = 1` |
| headers: identity frozen; version +2; DELETE/TRUNCATE; stale token → `serialization_failure`; current token → 2 | as designed |
| R-14: born draft; activate without content; draft/archived not assignable; archive reasons; archive with open unexpired version; archived accepts no versions; archived terminal (all three headers) | as designed |
| R-11: approve needs approver; frozen after; forward-only; draft beside live month; approve-while-open rejected; HDD restatement → 0.94 now / 0.95 at original bill time | as designed |
| R-12/13: DEFAULT pending; `industrial` rejected; activate needs verifier; asserted row frozen; in-place revoke rejected; revoke-beside-active rejected (exclusion); revocation as succession → exempt May, taxed August, still exempt at pre-revocation knowledge | as designed |
| RLS as `tally_app`: no context → 0 rows; operator → own rows; cross-tenant insert rejected; no DELETE; retired tables read-only; tenant-2 operator cannot see tenant-1 exemption through `should_charge_tax` | as designed |
| `session_replication_role = replica` | guards still fire |
| fresh rebuild: init errors / catalog parity / patch re-apply / 18-check smoke | 0 / identical / 0 errors / green |

## v5.4.2-02 — A-4 follow-up: void_invoice() hardened, direct-void gated, guards ENABLE ALWAYS

Triggered by two post-landing assessments of v5.4.2-01 (Fable, Codex) that Ryan requested. **New verification contract, applied to this patch and to every patch from here on:** the patch file must apply cleanly with `SET search_path = ''; SET check_function_bodies = on;` prepended — i.e. without the Docker preamble. v5.4.2-02 does (applied three times that way: scratch container, live container, fresh build); the v5.4.2-01 patch file, as a control, does not (fails at `void_invoice()` compile). Fresh rebuild from `postgres/Dockerfile`: **zero init errors**. Catalog deltas vs -01: none except `tgenabled` (9 → **80** ENABLE ALWAYS) and `void_invoice()`'s `proconfig` (NULL → `search_path=public, pg_temp`); the `enforce_invoice_immutable` trigger now fires on INSERT too. Both reviewers fresh-loaded with the strict prelude; Fable's round found the void gate sat below the draft/held early-return and missed INSERT (fixed, trigger re-created `BEFORE INSERT OR UPDATE OR DELETE`); Codex's round found the header claimed this document was already corrected before it was (it is now). Battery: 89 checks, green on the fresh build.

| test | result |
|---|---|
| strict standalone apply (`search_path = ''`, `check_function_bodies = on`), twice | clean, idempotent |
| same prelude against the v5.4.2-01 patch file (control) | `relation "invoices" does not exist` at `void_invoice()` compile |
| `void_invoice()` diff vs the -01 issue | only the `SET search_path` clause + 11 relation / 2 function qualifications (both reviewers diffed it) |
| `void_invoice()` with `SET search_path = ''` (tried first) | breaks at runtime inside `get_user_tenant_id()` (`users` unqualified, v5.2.1 helper) — hence `public, pg_temp` |
| definer hijack: caller's path `evil, public` with `evil.now()` / `evil.is_platform_admin()` | -01 body: cross-tenant void succeeded (Fable repro); -02 body: `Cross-tenant access denied` / `voided_at` real |
| `void_invoice()` end to end on sent / pending / held invoices | status void, `voided_at` stamped, billed charge reverted, `void_reversal` ledger row, `voided` event, GUC `false` after |
| direct `UPDATE … SET status='void', voided_at=now()` on sent / pending / **held** / **draft**; `INSERT … status='void'` | each rejected (`set by void_invoice() only`) |
| same direct void with `SET LOCAL app.void_operation='true'` | allowed — documented caller-settable carve-out (AC-12) |
| all -01 rules (frozen columns, backward transitions, line items, ledger, payments, adhoc, credits, CI-014 set) | unchanged, 86 earlier checks still green |
| `SET LOCAL session_replication_role = replica` (superuser): DELETE customer, UPDATE posted payment, DELETE sent invoice, TRUNCATE payments | each still rejected (previously bypassed on 68 of 77 guards) |
| `tgenabled = 'A'` count | 80 = 77 v5.4.2-01 guards + `enforce_pga_reconciliation_immutable` + the two `tenant_configuration_history` guards |
| `tally_app`: `SET session_replication_role` | permission denied (non-superuser) |

## v5.4.2-01 — bill immutability, append-only ledger, no hard deletes (Phase 4 Wave 1, A-4)

Fresh rebuild from `postgres/Dockerfile`: **zero init errors**; both reviewers (Fable, Codex) also fresh-loaded tu.sql + patch into throwaway containers and applied it twice (idempotent). **Correction (v5.4.2-02):** the original sentence here said "`search_path = ''` clean" — that was false. The re-issued `void_invoice()` in section 5 carried eleven unqualified relation references and compiled only because `postgres/00_preamble.sql` sets `check_function_bodies = off`; the patch file itself fails a standalone apply under `search_path = ''` with default body checking (control re-run confirmed: `ERROR: relation "invoices" does not exist`). Every fresh-load — mine and both reviewers' — went through the Docker image and inherited the preamble. Fixed by v5.4.2-02; the strict prelude is now part of the verification method below. No new tables/CHECKs/indexes/FKs — this patch is triggers and privileges: +77 triggers (33 tables × `no_hard_delete` + `no_truncate` from one generic function; three more `no_truncate` twins; eight table-specific guards), 9 of them `ENABLE ALWAYS`; `REVOKE DELETE` from `tally_app` on the 33 protected tables, `REVOKE UPDATE` on `account_ledger`/`invoice_events`, `REVOKE UPDATE, DELETE` on `pga_monthly_reconciliations`/`tenant_configuration_history`; `void_invoice()` re-issued with a `set_config('app.void_operation','false',true)` before `RETURN`. Battery: 83 checks, all green on the iteratively-patched container and again on the fresh build.

| test | result |
|---|---|
| draft / held invoice: edit totals, edit/add line items; held → pending | allowed |
| pending → held, pending: edit total; sent → draft | rejected (backward / frozen) |
| sent: amount_due, due_date, customer_id, pdf_url (once set), tax_breakdown, `id` | each rejected, column named in the message |
| sent: status → void without `voided_at`; `voided_at` set without status void | rejected both ways |
| sent: amount_paid/balance/status=partial, dunning_stage, late_fee_*, delivery_*, notes, metadata | allowed |
| sent: UPDATE / INSERT / DELETE line item; move a draft line onto a sent invoice | rejected |
| DELETE sent invoice, DELETE pending invoice, TRUNCATE invoices CASCADE, UPDATE/DELETE invoice_events | rejected |
| DELETE draft invoice | allowed; its line items and events cascade (0 left) |
| DELETE draft invoice with a billed adhoc charge attached | rejected (review fix — `fk_adhoc_invoice` is SET NULL) |
| `void_invoice()` on sent and on pending invoices | succeed under all new guards; status void, `voided_at` stamped; billed charge reverted to pending with `voided_from_invoice_id` |
| after `void_invoice()`: `current_setting('app.void_operation')`; un-bill an UNRELATED billed charge in the same transaction | **`false`**; **rejected** (review fix — previously `true` / allowed) |
| ~~sent: direct void with `voided_at` set~~ | *was accepted in -01 (assessment finding) — gated in v5.4.2-02* |
| void: un-void, change void_reason_code | rejected; notes allowed |
| account_ledger UPDATE / DELETE / TRUNCATE | rejected |
| payments: pending edit amount → posted; posted: amount, check_number, `id`, → pending | allowed; each rejected |
| payments: posted apply, → nsf; nsf → posted, change nsf_date; DELETE | allowed; rejected |
| payment inserted with DEFAULT status | `posted` — frozen immediately (Codex finding; rationale corrected, AC-11) |
| invoice_applications: change amount, reversed_by without reversed_at, re-stamp reversal, DELETE | rejected; notes + one reversal stamp allowed |
| adhoc_charges: pending edit amount → billed; billed: amount, description, repoint `billed_on_invoice_id`, → pending/void without GUC | allowed; each rejected |
| adhoc_charges: reverted-to-pending edit, pending → void, void → pending, DELETE | allowed, allowed, rejected, rejected |
| customer_credits: original_amount, source_reference; apply; → voided; voided → active; DELETE | rejected; allowed; allowed; rejected; rejected |
| DELETE customer / service_location / tenant; TRUNCATE meters CASCADE | rejected (cascade hits the first protected child) |
| `tally_app` privileges (`has_table_privilege`) | no DELETE on protected tables, no UPDATE on account_ledger/invoice_events; import_staging untouched; invoices keep DELETE for the draft exception |
| full patch re-applied on top of itself | idempotent, zero errors |

## v5.4.1-02 — tenant_configuration_history + time-aware get_partial_period_policy() (Phase 2 item 2.4)

Fresh rebuild from `postgres/Dockerfile`: **zero init errors** (both reviewers also fresh-loaded tu.sql + patch into throwaway databases before the mirror — clean). New table `tenant_configuration_history` (append-only, RLS + FORCE, identity `seq` tiebreaker), recorder trigger on `tenants`, immutability + TRUNCATE + source-guard triggers, backfill, and `get_partial_period_policy(uuid, timestamptz)` replacing the dropped one-arg form (only the two-arg signature exists in the catalog). Counts delta vs -01: +1 table, +1 policy, +5 CHECKs, +4 triggers, +3 indexes, +2 FKs.

| test | result |
|---|---|
| tenant INSERT (default settings `{}`) | 13 `onboarding` rows, one per policy key; `donation_program_name` recorded as JSON `null` |
| UPDATE two policy columns + add a settings key | exactly 3 `trigger` rows with old/new |
| UPDATE `name` only / numeric no-op (`5` on `5.00`) | 0 rows |
| nested change inside `settings.estimation` | 1 row, whole sub-object before/after |
| UPDATE / DELETE / TRUNCATE on history | each rejected (`enforce_tenant_configuration_history_immutable`) |
| manual row with `old_value = new_value` / unknown `config_key` / bogus `default_partial_period_policy` value / direct insert claiming `change_source='trigger'` | each rejected on its named CHECK or guard |
| history Jan=prorated, Jun=charge_both; as-of March / June 15 / now | prorated / charge_both / charge_both |
| two changes to one key in one transaction | latest wins (`seq DESC`) |
| `p_as_of` before the tenant's first row | **NULL** (no live fallback — review fix) |
| `p_as_of = NULL` | **RAISES** (review fix) |
| schedule override set | override wins regardless of date |
| unknown rate schedule | NULL |
| old one-arg signature | "function does not exist" |
| backfill on a simulated pre-existing tenant (trigger disabled, `created_at` 2025-01-01) | 13 rows at 2025-01-01 with the approximation `change_reason`; re-run inserts 0 |
| RLS as `tally_app` | sees own tenant's rows only; own-tenant UPDATE records with `changed_by` = GUC user; cross-tenant manual insert rejected |
| full patch re-applied on top of itself | idempotent, zero errors |

## v5.4.1-01 — factual-defect hardening, set 1 (Phase 2 items 2.1/2.2/2.3/2.5/2.6 + v5.4.0-06 review carryover)

Fresh rebuild from `postgres/Dockerfile`: **zero init errors**. First attempt FAILED — `CREATE EXTENSION IF NOT EXISTS btree_gist` without `WITH SCHEMA public` under tu.sql's `search_path = ''` ("no schema has been selected to create in"); masked all session by the iteratively-patched container's default search_path. Fixed in both the patch and the mirror before commit. All 11 new constraints, 5 new triggers, `import_jobs.idempotency_key` NOT NULL, and `meter_readings.location_id` confirmed in the catalog on the fresh build. Counts delta vs -06: +7 CHECKs, +1 EXCLUDE, +5 triggers, +3 indexes (1 UNIQUE, 1 EXCLUDE-backing, 1 partial), +2 FKs.

| test | result |
|---|---|
| 2.1 `final_read` order with no customer/location/meter | rejected (`service_orders_final_read_referents_check`) |
| 2.2 csv import, no key supplied | `idempotency_key` derived `f.csv:abc:preview` by trigger before insert |
| 2.3a landlord A→B then B→A | rejected (`landlord_customer_cycle`) |
| 2.6a second open deployment, same meter | rejected (`meter_deployments_no_overlap_excl`) |
| 2.6a closed range overlapping a closed range | rejected (EXCLUDE) |
| 2.6a `removal_date < install_date` | rejected (`…_removal_after_install_check`) |
| 2.6a same-day close + reopen (half-open) | allowed; `sync_meter_deployments` inactive→active round-trip passes |
| 2.6a Pattern A reactivation with stale `start_date` | rejected inside `sync_meter_deployments` (AC-1) |
| 2.6b read inside deployment #1 / on the boundary day / before any deployment | L1 / L2 / `meters.location_id` fallback — all as documented |
| 2.6b caller-supplied `location_id` | passes through; bogus value rejected by FK |
| 2.6b move deployment after the read | read's `location_id` unchanged (snapshot) |
| 2.6b same-day pull A → reinstall B: `removal` read / `regular_cycle` read / `final_read` with no move | A / B / A (review fix M2) |
| carryover `low=-5, medium=0` | rejected (`…_low_positive_check`) |
| carryover negative `actual_gas_cost` / `pga_recovered_revenue` | each rejected on its named CHECK |
| carryover negative `monthly_variance` (over-recovery) | allowed (signed by design) |
| full patch re-applied on top of itself | idempotent, zero errors |

Two independent adversarial reviews (Fable + Codex) on 2.6 + carryover before the mirror; consensus finding (in-place `meters.location_id` edit on an active meter leaves deployment history stale) recorded as APPLICATION-CONTRACTS AC-7 and as the leading reason CI-027 stays partial. Header's CI-032 grade corrected (register says partial, not enforced).

## v5.4.0-06 — PGA set (backlog item 14; ruling D3D-1) — Phase 1 complete

Two new tables: `pga_monitoring_settings` (tenant-overridable thresholds, one row per tenant, mutable, column defaults 10.00/20.00) and `pga_monthly_reconciliations` (immutable input-snapshot rows — **trigger-enforced**, the drafting call — with CHECK-enforced variance arithmetic and threshold-band consistency against the row's own snapshotted values). Both RLS + FORCE + `tenant_isolation`; grants via v5.4.0-01 default privileges. Runtime-tested:

| test | result |
|---|---|
| settings defaults | 10.00 / 20.00 / re-alert NULL |
| `medium <= low` / `re_alert_interval_days = 0` | each rejected on its named CHECK |
| settings UPDATE | allowed (mutable config); `updated_at` bumps |
| valid month row, balance at 0.83% of trailing revenue, band `none` | inserted |
| `monthly_variance ≠ cost − revenue` | rejected (`…_variance_arithmetic_check`) |
| `reconciliation_month` = mid-month date | rejected (`…_month_first_day_check`) |
| band `none` claimed at 25% ratio | rejected (`…_band_consistent_check`); same row as `medium` inserted |
| boundary: exactly 10% (negative balance, abs applies) | `none` rejected, `low` accepted (>= boundary) |
| `trailing_12mo_pga_revenue = 0` | band check disabled; row inserted |
| duplicate `(tenant_id, reconciliation_month)` | rejected (UNIQUE — CI-117) |
| UPDATE / DELETE on a posted month | **both rejected** (`enforce_pga_reconciliation_immutable`) |
| `metadata = []` | rejected (object-shape CHECK) |
| RLS as `tally_app` | no GUC → 0 rows both tables; operator → own tenant only (3 recon + 1 settings); cross-tenant INSERT denied; own-tenant INSERT succeeds |

The mid-year-config-change scenario (D3D-1's test note) is covered by construction: thresholds are snapshotted per row and the row can never be updated, so a settings change cannot rewrite prior months' workpapers.

## v5.4.0-05 — pipeline & events set (backlog items 11, 12, 13; rulings D3C-6/Part 4, D1-3, D3B-1/2)

Dry-run isolation is now a database property: guards on `invoices`, `account_ledger`, the read-lock transition, and `billing_runs` status; `dry_run` dropped from the `run_type` enum; `is_dry_run` immutable. Reversal-chain depth >3 auto-emits an `invoice_events` row. D3B-1/2 confirmation columns pair-CHECKed. Runtime-tested:

| test | result |
|---|---|
| `run_type = 'dry_run'` | rejected (enum value gone — split-brain closed) |
| invoice referencing a dry run | rejected (`enforce_dry_run_no_invoices`) |
| ledger entry referencing a dry run | rejected (`enforce_dry_run_no_ledger`) |
| read lock by a dry run | rejected (`enforce_dry_run_no_read_locks`) |
| dry run → `approved` / `is_dry_run` flip | both rejected; → `review` allowed |
| invoice on a real run | inserted |
| reversal chain to depth 3 | silent (legitimate bill→void→rebill→void) |
| chain link #4 | `reversal_chain_depth_exceeded` event, metadata `{depth: 4, severity: medium}` |
| `zone_confirmed_at` without `_by` | rejected (pair CHECK); full pair accepted |
| `fp_mismatch_confirmed_at/by` without reason | rejected (all-or-nothing CHECK); all three accepted |

Incidental discovery: creating a meter auto-creates `meter_deployments` row #1 (existing trigger behavior), so fixture deployments start at #2.

---
### Earlier v5.4.0-04 state Deploys **clean, zero errors** on fresh PostgreSQL via the repo harness (`postgres/Dockerfile`, base `postgres:16`, `check_function_bodies = off` preamble). Counts after v5.4.0-04: **63 tables** / **62 policies** / 61 FORCE-RLS / role `tally_app` present / 11 seeded `program_types` rows / 4 `customers.disconnect_protection_*` columns dropped / `compliance_statistics` rebuilt. tu.sql is now **11,966 lines** (11,351 baseline; all patch mirrors are pure appends at EOF, so every pre-existing line number — including anchors 337/3600/3679 — is unchanged and all register citations remain valid).

## v5.4.0-04 — programs & lifecycle: A-11 substrate + item 10 (D8-2)

`program_types` (platform-global, no RLS, **app-role read-only** — DML revoked from `tally_app`) and `customer_program_enrollments` (RLS + FORCE, full A-11 index set incl. the one-active-per-type partial UNIQUE and GIN on `enrollment_data`), three guard triggers, the `do_not_disconnect` denormalization, single-slot column drop, matview rebuild with `LEFT JOIN LATERAL`. Behavioral suite, all green:

| test | result |
|---|---|
| pending enrollment | `do_not_disconnect` stays false; flips true on activation |
| second active enrollment, same type | rejected (`idx_cpe_one_active_per_type`) |
| supersede flow (superseded → new active with lineage link) | works; flag stays true |
| supersede link crossing program_type | rejected (`validate_enrollment_supersedes_chain`) |
| `customer_id` UPDATE | rejected (`enforce_enrollment_customer_immutable`) |
| cancel last protective enrollment | flag flips false |
| active `budget_billing` (non-protective) | flag stays false |
| `enrollment_data` array / end<start / bad expiry_type | each rejected on its named CHECK |
| D8-2: bankruptcy, `expiry_type='event'`, NULL end date | inserted; flag true |
| matview refresh | shows `bankruptcy_automatic_stay` / `permanent` (surface preserved) |
| RLS as `tally_app` | enrollments tenant-scoped; `program_types` readable (11 rows) but INSERT → permission denied |

## v5.4.0-03 — rating & WNA set (backlog items 4, 5, 6, 7; Kyle rulings D7-2, D5-2, T-4, T-3)

New objects: `jurisdictions` and `wna_clamp_events` tables (both RLS + FORCE + `tenant_isolation` policy; grants arrive via v5.4.0-01's default privileges), `regulatory_class` NOT NULL on `rate_items` + `adhoc_charges`, floor/ceiling/basis on `wna_zones`, `service_locations.jurisdiction_id` FK, `prorate_tier_breakpoints` default → true. Runtime-tested:

| test | result |
|---|---|
| rate_item / adhoc_charge without `regulatory_class` | rejected (NOT NULL, both tables) |
| `regulatory_class = 'sorta'` | rejected (`rate_items_regulatory_class_check`) |
| valid `regulated` rate_item / `unregulated` adhoc charge | inserted |
| duplicate `(tenant_id, jurisdiction_code)` | rejected (UNIQUE) |
| jurisdiction → wna_zone pointer + service_location → jurisdiction link | both resolve |
| WNA floor set without `wna_clamp_basis` | rejected (`wna_zones_clamp_basis_required_check`) |
| floor > ceiling | rejected (`wna_zones_floor_le_ceiling_check`) |
| clamp event `bound_hit = 'middle'` | rejected; `'floor'` with snapshot bounds inserted |
| new rate_schedule | `prorate_tier_breakpoints = true` by default |
| RLS on both new tables as `tally_app` | no context → 0 rows; operator context → own rows |

## v5.4.0-02 — meters & reads set (backlog items 1, 2, 8, 9; Kyle rulings D3-1, D3A-3, D3A-4)

Six columns on `meters` (`rollover_point`, `meter_pressure_class`, `tamper_flag` + `tamper_reported_at`/`tamper_signal_source`/`tamper_reason`) and two constraints on `read_cycle_meters.skip_reason` (ruled enum; `other` requires `notes`). All six new CHECKs runtime-tested on the deployed instance:

| test | result |
|---|---|
| `meter_pressure_class = 'medium'` | rejected (`meters_meter_pressure_class_check`) |
| `rollover_point = -5` | rejected (`meters_rollover_point_check`) |
| `tamper_flag = true` without reported_at/source | rejected (`meters_tamper_flag_consistency_check`) |
| valid meter: elevated / 1,000,000 / tamper fully recorded | inserted |
| `skip_reason = 'poodle'` | rejected (`read_cycle_meters_skip_reason_check`) |
| `skip_reason = 'other'` without notes | rejected (`read_cycle_meters_skip_other_notes_check`) |
| `skip_reason = 'dog'`; `'other'` + notes | both inserted |

Incidental confirmation: `read_cycle_meters` UNIQUE (instance, meter) fired correctly during testing. Fixture note: the FK chain for these tests is tenant → customer → service_location → meter and billing_cycle → read_cycle_instance.

## v5.4.0-01 — app role, GRANTs, FORCE RLS (decision: Ryan, 2026-08-19 — split-role model)

Role `tally_app` (NOLOGIN privilege bundle; production LOGIN users get membership) with full DML GRANTs + default privileges for future objects; `FORCE ROW LEVEL SECURITY` on all 58 RLS tables (`materialized_view_refresh_log` stays non-RLS by design). Migrations remain the owner's job. **This is the moment the 59 policies bind anyone at all** — and the first true end-to-end RLS test (v5.4.0-00's caveat is closed):

| context (as `tally_app` via SET ROLE) | result |
|---|---|
| no `app.user_id` set | 0 users, 0 tenants visible — fail-closed |
| operator (tenant A) | only tenant-A rows (2 users, 1 tenant) |
| operator (tenant A), INSERT into tenant B | **denied** — `new row violates row-level security policy for table "customers"` |
| operator (tenant A), INSERT into own tenant | succeeds (grants + WITH CHECK both verified live) |
| platform_admin | all rows (3 users, 2 tenants) — policy branch, not role bypass |

**Caveat that remains:** the container owner (`tally`) is a superuser, and superusers bypass RLS regardless of FORCE — so FORCE's binding of the *owner* is only observable on AWS, where the owner won't be superuser. Fixture note: `customers.customer_number` is NOT NULL with no default (app-assigned).

## v5.4.0-00 — Supabase substrate removed (decision: Ryan, 2026-08-18 — PostgreSQL on AWS)

`get_user_tenant_id()` / `is_platform_admin()` now read the `app.user_id` session GUC instead of Supabase's `auth.uid()`; no `auth.*` references remain. **Runtime-tested for the first time** (impossible pre-patch — the old bodies would have raised `auth.uid() does not exist`):

| context | `get_user_tenant_id()` | `is_platform_admin()` |
|---|---|---|
| none set | NULL (all tenant policies deny — fail-closed) | false |
| operator user | their tenant uuid | false |
| platform_admin user | — | true |

**Caveat:** these were run as the `tally` superuser, which owns the tables — RLS never applies to owners (and no table sets FORCE). A true end-to-end policy test requires the app role, which is the open Phase 0.5 item (roles/GRANTs + the FORCE-RLS decision).

---

## Original baseline verification — v5.2.1 (2026-08-18)

## Provenance (why this file exists)

The schema was authored by Kyle Shaffer with Claude Opus and never run by Kyle. Ryan ran a version on a local PostgreSQL in May 2026 and exported a tables-only listing (`application/database/schema.sql`); that machine has since died and **no database with data exists anywhere**. This verification re-establishes the executable baseline from what is in the repo. `tu.sql` is the canonical schema; `schema.sql` is a column-reference document only.

## Deployed object counts (queried from the running instance)

| object | count | expected (from tu.sql) | note |
|---|---|---|---|
| tables | 59 | 59 | |
| triggers (non-internal) | 49 | 49 | |
| RLS policies | 59 | 59 | |
| functions (non-extension) | 23 | 23 | |
| CHECK constraints | 188 | — | grep of tu.sql says 191; 188 is the real count (grep hits include comments) |
| plain indexes | 352 | ~348 | grep undercounts; DB is authoritative |
| foreign keys | 252 | 252 | confirms the corpus finding: all single-column |
| RLS-enabled tables | 58 of 59 | — | |
| **FORCE ROW LEVEL SECURITY tables** | **0** | — | **independently confirms CI-116's read-isolation gap** |
| views + materialized views | 2 + 4 | 6 | the corpus's "six views" = both kinds |

## Method

```bash
docker build -t tally-postgres -f postgres/Dockerfile .
docker run -d --name tally-pg -e POSTGRES_PASSWORD=tally tally-postgres
docker logs tally-pg   # zero error/fatal lines
docker exec tally-pg psql -U tally -d tally -c "<catalog queries>"
```

No host port is required (5432 was occupied locally); use `docker exec`. Each container start applies the schema fresh — this is the standing deployability test. **Re-run this verification after every patch set and update this file's counts.**
