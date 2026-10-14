# v5.4.2-20 source inventory: the version-check and void seals

**Authority:** Ryan, 2026-10-14: "yes, go ahead and draft it". This is the corrected design: the rate check sealed with a receipt that binds the version; the void sealed by its own role; dedicated owners; rebuilt grants; the core write path closed; the cross-tenant void bug fixed and the void locked. Codex's identity question is excluded; it is Ryan's next call.
**Sources:**
- `brief.md` (md5 `0246a2ae`);
- `review-opus.md` (O);
- `review-fable.md` (F);
- `review-codex.md` (C).
Tags such as `O-B2` name the finding.

Every requirement below is a row of the battery, or of an invariant the CI runs.

## R: roles

- **R1.** Two roles, `tally_seal` (the version check) and `tally_void` (the void). [O-B2, O-B3]
  - Why two: the void guards key on the void's own role, so the version check must not share it.
  - Both are NOLOGIN, with no SUPERUSER, BYPASSRLS, CREATEROLE, CREATEDB or REPLICATION.
  - Both are members of no role and have no members.
  - Both have no TEMP or CREATE on the database or any schema, and no default ACL entry. [O-B2, F-Q3, C-B7]
- **R2.** Each owns exactly its sanctioned functions, each SECURITY DEFINER and pinned to `public, pg_temp`, and owns no relation. [O-B2]
  - `tally_seal`: `assert_reference_version`, `reference_version_receipt_held`.
  - `tally_void`: `void_invoice`.
- **R3.** Their grants are enumerated, with no blanket SELECT. The test is an end-to-end run as `tally_app`. [F-B4, C-B7, O-B2]
  - Both get EXECUTE on `get_user_tenant_id()` and `is_platform_admin()`, which the canonical policy calls. [F-B4]
- **R4.** `assert_seal_role_invariants()` checks R1–R3 and R5, O4 and O5 by shape. It runs in the patch tail and in CI. [O-B2, F-Q3, C-B4]
- **R5.** `tally_core` executes no SECURITY DEFINER function except the two RLS helpers. Its EXECUTE on `assert_reference_version` is revoked. [O-B4, C-B4]

## S: the version check (CI-011)

- **S1.** On the three headers, revoke table-level UPDATE from `tally_app`, then grant back exactly these columns. [O-S1, F-B2, C-B1]
  - `rate_schedules`: `status`, `updated_at`, `archive_reason`, `activated_at`, `archived_at`.
  - `rate_items`, `wna_zones`: `status`, `updated_at`.
  - `updated_at` stays because of the dependency mutex.
- **S2.** A header is born at `version = 1`. The INSERT path is not covered by the header guard today. [C-B1]
- **S3.** `reference_version_receipts` is a new table: `(xact xid8, header_table, entity_id, version, tenant_id, at)`. [F-B1, F-S8, O-Q6, C-S1]
  - PK `(xact, header_table, entity_id, version)`.
  - RLS on, FORCE, with the canonical policy.
  - `REVOKE ALL` from PUBLIC, `tally_app` and `tally_core`; the default ACL would otherwise make it writable.
  - `tally_seal` gets SELECT and INSERT.
  - UPDATE, DELETE and TRUNCATE are refused for every role.
- **S4.** `assert_reference_version` becomes a definer owned by `tally_seal`. [O-S3, F-S4, O-B1, C-B5]
  - It first reads the header under RLS. If the header is not visible it raises a distinct, non-retryable error (`P0002`) that names nothing of another tenant.
  - Only a version mismatch raises `40001`.
  - On success it bumps the version and writes the receipt, stamping the xact, version, tenant and `at = now()` itself.
  - PUBLIC and `tally_core` lose EXECUTE; `tally_app` keeps it.
- **S5.** `reference_version_receipt_held(header_table, entity_id)` is a definer owned by `tally_seal`. [O-S4, C-B5, C-Q2, F-Q2]
  - It returns true only for a receipt with `xact = pg_current_xact_id_if_assigned()`, `at = now()` and `version =` the header's current version.
  - The `at` binding defeats xid reuse after a restore. The version binding answers Codex. Fable's two-asserts case still passes, because the latest receipt matches.
  - The caller supplies no xact. EXECUTE goes to `tally_app` only.
- **S6.** A guard `a0_enforce_reference_version_receipt` fires BEFORE INSERT OR UPDATE on each of the three version tables and requires S5 for its entity. [O-S5, F-S1, C-B5]
  - It sorts first.
  - It has no superuser or depth carve-out.
- **S7.** A header lifecycle move needs S5: a change to `status`, `archive_reason`, `activated_at` or `archived_at`. [F-S6; O-S8 and C's table had it as the boundary; settled by rule: an archive is an edit of the entity]
  - A bump by the check itself changes only `version` and `updated_at`, and needs nothing.

## V: the void (A-23 item 1, AC-12, -19 R14)

- **V1.** `void_invoice()` is re-owned to `tally_void`. Its writes now meet every superuser-keyed fence, and the battery runs it end to end. [O-B2, F-Q3]
- **V2.** The three guards admit the void's writes only when `current_user = 'tally_void'`. The GUC is removed from every function body, and the invariant asserts that no live body names `app.void_operation`. [O-B3, C-B2, F-Q1]
  - Why this works: the window is exactly the call, so nothing survives the return, which preserves the v5.4.2-01 property. Fable's alternative, S2's `completed_at`, buys the same thing with a table.
  - Every guard stays invoker-rights and none is moved to deferred. [O-B3, C-B2]
  - **Readings:** the move `locked` to `void_released` also requires `OLD.locked_by_invoice_id IS NOT NULL`. [C-B2]
  - **Charges:** under the void role exactly the disposition it writes is admitted. [C-B2]
    - `status` goes to `pending` or `void_pending_rebill`.
    - `billed_on_invoice_id`, `billed_on_line_item_id` and `billed_at` are cleared.
    - `voided_from_invoice_id` becomes `OLD.billed_on_invoice_id`, which must be non-null.
    - `billed_by_billing_run_id` is unchanged.
    - `voided_from_invoice_id` changes only under the void role.
  - **Invoices:** `status = 'void'` is written only by an UPDATE under the void role, never by an INSERT. [C-B2]
- **V3.** The tenant check in `void_invoice()` is NULL-safe, and its refusal names no invoice number. [O-B1, C-B3, O-S6]
  - RLS now hides other tenants: with a `tally_void` owner, a not-found is the refusal.
  - The explicit check is kept as defence and fails closed when the caller's tenant is NULL.
- **V4.** The void locks the invoice before reading its status. [C-B6]
  - `void_invoice()` takes `SELECT … FOR UPDATE` on the invoice.
  - A new guard, `enforce_attach_to_live_invoice`, on `meter_readings.locked_by_invoice_id` and `adhoc_charges.billed_on_invoice_id`: a write that sets either to an invoice takes `FOR SHARE` on that invoice and refuses one that is void.
  - Lock order: invoice before children in the void; a child before its invoice in an attach. These cannot deadlock, because the void's child UPDATEs skip rows not yet attached (READ COMMITTED). A race test covers it.

## O: other

- **O1.** Every object the patch creates is born with an explicit `REVOKE ALL … FROM PUBLIC, tally_app, tally_core` before its grants. [F-B1, C-S1]
- **O2.** A battery case shows `SET LOCAL app.void_operation = 'true'` now admits nothing. [O-Q7, F-Q7]
- **O3.** Cases cover savepoint rollback, a released savepoint, a read-only transaction, a two-entity multi-row statement, writable CTEs in both orders, COPY and TRUNCATE. [O, F, C test lists]
- **O4.** No live function body names `app.void_operation`. This is part of R4. [F-Q1]
- **O5.** `tally_app` has no write privilege on the receipts and no UPDATE on any header's `version`. This is part of R4. [F-B1, F-B2]

## Residuals, left on purpose (each goes in the patch header)

- **The caller's identity is caller-asserted.** `app.user_id` decides every tenant wall. This is Codex B3, Ryan's next decision. [C-B3]
- **The token is the caller's.** The database proves a check ran under the row lock, not that the token came from the read the edit is based on. This becomes an AC entry. [O-S2, F-Q1]
- **The write API (Codex's alternative a)** is the next step if the version tables ever get a second writer. [C-Q5, F-Q5]
- **Optional: `header_version` stamped on version rows.** Not now. [O-S7]
- **Fences keyed on `current_user <> 'tally_app'`** (the platform-admin and tenant-admin grant guards on `users`) stand aside inside any definer. Neither seal role holds a privilege on `users` (asserted by R4), so the fences are unreachable from them. Inverting them waits for a definer that writes `users`. [F-S5]
- **Schedule composition** (`rate_schedule_items`, `rate_item_dependencies`) is outside the token, by the D1-1 design. [O-S8]
- **The caller contract changes.** The check must now be called before a first version, before every close, and before a lifecycle move, in the same transaction as the write. Autocommit between the check and the write fails. This becomes an AC entry. [C-S2]
