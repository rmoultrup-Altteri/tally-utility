# Deploy verification — tu.sql

**Current: v5.2.1 + v5.4.0-00 through v5.4.0-06 + v5.4.1-01 + v5.4.1-02 + v5.4.2-01, verified 2026-08-20.** After v5.4.2-01: **66 tables** / **65 policies** / **64 FORCE-RLS** / **229 CHECKs** / 1 EXCLUDE / **147 triggers** (9 ENABLE ALWAYS) / 477 indexes / 275 FKs; tu.sql **14,030 lines** (pure appends; anchors 337/3600/3679 intact).

## v5.4.2-01 — bill immutability, append-only ledger, no hard deletes (Phase 4 Wave 1, A-4)

Fresh rebuild from `postgres/Dockerfile`: **zero init errors**; both reviewers (Fable, Codex) also fresh-loaded tu.sql + patch into throwaway containers and applied it twice (idempotent, `search_path = ''` clean). No new tables/CHECKs/indexes/FKs — this patch is triggers and privileges: +77 triggers (33 tables × `no_hard_delete` + `no_truncate` from one generic function; three more `no_truncate` twins; eight table-specific guards), 9 of them `ENABLE ALWAYS`; `REVOKE DELETE` from `tally_app` on the 33 protected tables, `REVOKE UPDATE` on `account_ledger`/`invoice_events`, `REVOKE UPDATE, DELETE` on `pga_monthly_reconciliations`/`tenant_configuration_history`; `void_invoice()` re-issued with a `set_config('app.void_operation','false',true)` before `RETURN`. Battery: 83 checks, all green on the iteratively-patched container and again on the fresh build.

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
