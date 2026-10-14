# Design review brief: sealing the version check (CI-011) and the void carve-out (A-23 / AC-12)

**Date:** 2026-10-14. **Kind:** design review. No patch exists yet; you are reviewing a proposal before it is drafted.
**Live schema:** `sql/tu.sql` (the -19 build, mirrored). The running container `tally-pg` (user `tally`, db `tally`) holds that build.
**Reviewers:** Opus, Fable, Codex, independently. Do not read each other's files.

## Why this is being asked

Ryan (schema owner) must decide whether to seal two places where the database trusts the caller to run a check. He asked to hear the reviewers before deciding. Your review decides two things:
- whether the proposal is sound;
- what must change before it is drafted.

Standing project rules apply:
- A guard must act, not merely record its own enforcement.
- A fact a guard relies on must be DB-stamped and unforgeable by `tally_app`; an app-writable log or a caller-settable GUC is not a guard.
- A guard keyed on a caller-chosen label is bypassed by choosing another label; write the predicate from the act.
- Trigger and definer functions pin `search_path` (`public, pg_temp` where they read RLS tables).
- Nothing is live: no "until the core exists" interim options.

## The two gaps

### Gap 1: CI-011, the optimistic version check is optional

The A-1 (v5.4.2-03) and D1-1 design:
- The headers `rate_schedules`, `rate_items` and `wna_zones` carry `version integer`.
- Their correctable content lives in `rate_schedule_versions`, `rate_item_versions` and `wna_zone_versions` (bi-temporal: `recorded_until IS NULL` = open).
- `public.assert_reference_version(p_table text, p_id uuid, p_expected_version int)` (tu.sql ~14802) runs `UPDATE <header> SET version = version + 1 WHERE id = $1 AND version = $2`.
  - 0 rows: it raises `40001`, meaning "modified since read, review and retry".
  - Otherwise it bumps the version and row-locks the header until commit, serialising writers on one entity.
- `enforce_reference_header()` (~14745) allows `version` to stay or move by +1 only.

The gap (parity measurement, verified):
- `tally_app` holds UPDATE on the headers, so a raw `UPDATE … SET version = version + 1` passes.
- Nothing ties a write to a `*_versions` table to a check having run. A caller can insert or close version rows without ever calling `assert_reference_version`, and two editors then overwrite each other.

`assert_reference_version` is currently `SECURITY INVOKER`, owned by `tally`, `search_path = public, pg_temp`.

### Gap 2: A-23 item 1 / AC-12, the void carve-out is a caller-settable GUC

`void_invoice()` (latest definition ~tu.sql:37701) is already `SECURITY DEFINER`, owned by `tally`, with a pinned `search_path`. It `SET LOCAL app.void_operation = 'true'` while it:
- posts the reversal;
- releases the invoice's locked reads (`locked` → `void_released`);
- disposes of billed adhoc charges.

It clears the setting before returning. The guards that stand aside for it read `current_setting('app.void_operation', true)`:
- the meter_readings locked-read guard (~249, and its later rewrite ~36779);
- the adhoc_charges guard (~13605);
- the invoices guard refusing a direct write of `status = 'void'` (~14380).

Any caller can `SET LOCAL app.void_operation = 'true'`. The guards narrow what is admitted ("only the pointer write void_invoice() does"), but the residual is open (-19 residual R14).

**Catalog facts (checked 2026-10-14):**
- `tally` is `rolsuper` and `rolbypassrls`, and owns the tables (RLS enabled + FORCE).
- `tally_app` is neither.
- The only SECURITY DEFINER functions in `public` are `void_invoice`, `get_user_tenant_id` and `is_platform_admin`.
- `tally_core` exists (from -17): explicit grants only, member of no role, checked by `assert_core_role_invariants()`.

## The proposal (as put to Ryan)

1. **Column privilege.** Revoke `tally_app`'s UPDATE on `version` of the three headers. Its other sanctioned mutable columns stay updatable through column-level grants.
2. **Definer check.** Make `assert_reference_version` `SECURITY DEFINER`, with a pinned `search_path` and schema-qualified throughout. Because its owner bypasses RLS, the function itself checks that the header's `tenant_id` is the caller's tenant (`get_user_tenant_id()` or equivalent), and refuses otherwise.
3. **Receipt.** On success the function inserts a receipt row `(xact = pg_current_xact_id(), table, entity id, version, at)` into a new table on which `tally_app` holds no privilege. Receipts are kept as a permanent, append-only log.
4. **Version-row guard.** A BEFORE trigger on each `*_versions` table refuses an INSERT, or a close (`UPDATE` setting `recorded_until`), unless a receipt exists for this transaction and this entity.
5. **The void, sealed the same way.** `void_invoice()` writes a receipt `(xact, invoice id)` instead of the GUC. Each guard that read `app.void_operation` instead asks "is there a void receipt in this transaction for the invoice this row belongs to?". The GUC is removed.

Ryan was told:
- To the app, the right path looks the same as today.
- The change is schema-only and additive. The tables are empty, so there is no data migration.

## What to answer

1. **Soundness.** Does the proposal close both gaps? Name every path that still writes a version row, bumps a version, releases a locked read, un-bills a charge, or sets `status = 'void'` without the check. Include:
   - other definer or trigger functions that write these tables;
   - `rule_*` helpers;
   - `tally_core`;
   - TRUNCATE;
   - COPY;
   - writable CTEs;
   - multi-row statements.
2. **Transaction identity.** Is `pg_current_xact_id()` right for the receipt? Consider:
   - savepoints and subtransactions (a receipt written inside a savepoint that is rolled back; a version write in a later subtransaction);
   - read-only transactions, where no xid is assigned yet;
   - wraparound (`xid8` is epoch-extended);
   - prepared transactions.
   Is "receipt for this xact and entity" the right predicate, or should it also bind the version number?
3. **Definer owner.** The owner today would be `tally`, a superuser.
   - Should the definer functions be owned by a dedicated NOLOGIN role holding only the grants they need, so that a bug in them is not a superuser bug?
   - What does that role need (RLS: does it bypass, or must the policies admit it)?
   - How does it interact with `assert_core_role_invariants()`?
   - Is the same question open for `void_invoice()` today?
4. **Tenant check inside the definer.** Is checking `tenant_id` against the caller's tenant sufficient? What does `get_user_tenant_id()` read, and can `tally_app` influence it? Is a platform admin path needed?
5. **Alternatives.** Compare these against the receipt design. Recommend one.
   - (a) Revoke INSERT/UPDATE on the `*_versions` tables from `tally_app` entirely, and route every version write through definer functions (a write API).
   - (b) A trigger test that the header row was updated by the current transaction (`xmin`), instead of a receipt table.
   - (c) Leave both as application contracts (AC entries), tested in the core.
6. **Receipts as a permanent log.** Is keeping them right (growth, the CI-014 no-delete set, RLS on the receipt table, whether `tally_app` may read them)?
7. **Anything else** that would make Ryan's yes a mistake, or that the drafting must not miss: the mutation and race tests a patch must carry, and how to fence the `pg_trigger_depth` and TEMP rules.

## How to probe

You may query the running `tally-pg` read-only. For experiments, clone into your own scratch database. Use only your own name:
- Opus: `a23opus`;
- Fable: `a23fable`.

Clone with `CREATE DATABASE <name> TEMPLATE tally`. **Revoke TEMP from PUBLIC and `tally_app` on the clone right after creating it** (a template clone restores TEMP). Act as `tally_app` with `SET ROLE tally_app` plus the tenant settings the RLS helpers read. Drop your clone when done. Never modify `tally`, `sql/tu.sql` or any repo file except your output file.

## Output

Write your full review to `application/a23-seal-review-2026-10-14/review-<reviewer>.md` (`opus`, `fable` or `codex`). It contains:
- a verdict: "sound as proposed", "sound with changes", or "not sound";
- blocking items (B1…), each with the concrete path or repro;
- should-fix items (S1…);
- your recommendation on question 5.

Mark each claim as **executed** (you ran it) or **predicted** (read from the SQL). Your final message, under 2 KB, gives the verdict, the blocking items in one line each, and the file path.
