# A-23 seal design review — Opus

**Brief:** `brief.md`, md5 `0246a2ae642dfb3dbb2196ae58c24db3` (checked before starting).
**Probed on:** clone `a23opus` of `tally` (the -19 build), TEMP revoked from PUBLIC and `tally_app` right after cloning (`has_database_privilege(..., 'TEMP')` = f for both app roles). The clone is dropped. Two cluster-wide scratch roles (`tally_seal`, `tally_void`) were created for the prototype and dropped afterwards. `tally`, `sql/tu.sql` and the repo are untouched.
**Fixture:** two tenants (A, B), one user each, a tenant-B customer, location, held invoice `INV-1`, and two tenant-B rate schedules (`GAS-R1`, `GAS-R2`, version 1).

Tags: **[executed]** = I ran it on the clone. **[predicted]** = read from the SQL, not run.

---

## Verdict: **sound with changes**

The direction is right. Gap 1 needs a DB-stamped fact that a version check ran in this transaction. A receipt written by a definer that `tally_app` cannot write gives exactly that. I built the receipt half on the clone and it held against every path in question 1 (battery below).

Three things must change before drafting:
- The tenant check, as described and as `void_invoice()` writes it today, is open to a caller with no identity.
- Owning the new definer by `tally`, a superuser, is the wrong default.
- For Gap 2 a receipt is the wrong tool. It reopens the window that v5.4.2-01 closed, and a better predicate exists: the role the function runs as.

---

## Blocking

### B1. The tenant check fails open on a NULL tenant, and `void_invoice()` is open today **[executed]**

`void_invoice()` checks `IF v_invoice.tenant_id != public.get_user_tenant_id() AND NOT public.is_platform_admin()`. `get_user_tenant_id()` returns NULL when `app.user_id` is unset or names no user. `x != NULL` is NULL, so the IF is not taken. The function's owner bypasses RLS, so its `SELECT` finds every tenant's invoice.

What I ran, as `tally_app` with tenant-B invoice `INV-1`:
- **Tenant-A user:** refused, but the message reads "Cross-tenant access denied for invoice INV-1". It hands another tenant's invoice number to the caller (see S6).
- **`app.user_id` unset, fresh session:** `SELECT count(*) FROM invoices` returns 0, because RLS hides everything. Then `void_invoice(INV-1, NULL, 'system_error')` returns `INV-1`. The invoice is `void` and a `void_reversal` row of −100.00 is posted in tenant B's ledger.
- **`app.user_id` set to a uuid that names no user:** same result, voided.

So a caller that RLS shows nothing can void any tenant's invoice by id. That is a cross-tenant ledger write in the live schema, and it bears on brief question 3 ("is the same question open for `void_invoice()` today?"): yes, and worse.

Proposal item 2 says the function "checks that the header's tenant_id is the caller's tenant". Written as `<>`, it reproduces this hole in `assert_reference_version`.

The drafting must:
- write the check NULL-safe: `IF public.get_user_tenant_id() IS NULL AND NOT public.is_platform_admin() THEN raise; IF v.tenant_id IS DISTINCT FROM public.get_user_tenant_id() AND NOT public.is_platform_admin() THEN raise`;
- fix `void_invoice()` in the same patch;
- add a negative test for unset, unknown and other-tenant `app.user_id` on every definer.

B2 removes most of this class structurally.

### B2. Definer owner: use dedicated NOLOGIN, non-BYPASSRLS roles, not `tally` (answers Q3, most of Q4) **[executed]**

A superuser-owned definer does more than skip RLS. Every trigger fired inside it runs its superuser branch. `tu.sql` has about 12 `rolsuper` carve-outs, among them:
- `enforce_reading_born_unconsumed`, which returns early for a superuser;
- `stamp_log_created_at`, which keeps a superuser's `created_at`;
- `enforce_event_written_by_db`, which admits a superuser's direct insert;
- the off-run `created_at` write-once check.

Inside `void_invoice()` today, every one of those guards treats the statement as a history load. A bug in a superuser definer is a bug with every guard's back door open.

I re-owned `void_invoice()` to a NOLOGIN role `tally_void` (not super, not BYPASSRLS, member of nothing, `tally_app` not a member of it) **[executed]**. That role held SELECT on the tables, UPDATE on `meter_readings`, `adhoc_charges` and `invoices`, INSERT on `account_ledger` and `invoice_events`, and EXECUTE on the two RLS helpers. The results:
- **Tenant-B user:** the void runs end to end (reads released, charges disposed, ledger row posted, event logged).
- **Unknown or absent user:** "Invoice not found". RLS now does the tenant check, NULL-safe, and leaks nothing.
- **Platform admin:** the canonical policy `is_platform_admin() OR tenant_id = get_user_tenant_id()` admits admins to both the tables and the definer, so no special path is needed.

The same held for a `tally_seal` owner of `assert_reference_version` (battery T10).

What each role needs:
- **`tally_seal`:**
  - SELECT on the three headers;
  - UPDATE (`version`, `updated_at`) on the three headers;
  - SELECT on the three version tables, which the header trigger reads when archiving;
  - SELECT on `users`, for the policy helpers;
  - INSERT and SELECT on the receipt table;
  - EXECUTE on `get_user_tenant_id()` and `is_platform_admin()`, which were revoked from PUBLIC at -11, so the policy expression needs it.
- **`tally_void`:**
  - exactly what `void_invoice()` and every trigger it fires reads and writes;
  - the drafting must enumerate this. My prototype used SELECT on every table, which is too broad.

How it interacts with `assert_core_role_invariants()`:
- Add a sibling `assert_seal_role_invariants()`, run in every patch tail and in CI. For each seal role it asserts:
  - NOLOGIN, no SUPERUSER, BYPASSRLS, CREATEROLE, CREATEDB or REPLICATION;
  - **no members**: no `pg_auth_members` row with `roleid` = the seal role;
  - member of no role;
  - no TEMP or CREATE on the database or any schema;
  - no default ACL;
  - it owns exactly the sanctioned functions, which are `prosecdef` and pinned, and no table.
- Also assert by shape that `void_invoice`, `assert_reference_version` and the receipt trigger function are owned by their seal role. `CREATE OR REPLACE` keeps the owner, but a DROP + CREATE silently reverts it to `tally`, and `void_invoice()` has been re-issued five times.
- Extend the isolation assertion's definer checks (7.4a/b/c already apply by shape) to the new functions.

### B3. Gap 2: do not replace the GUC with a transaction-scoped receipt. Key the carve-out on `current_user` = the void owner role **[executed / predicted as marked]**

- **The window [predicted].** A receipt `(xact, invoice)` lives until commit. v5.4.2-01 deliberately cleared `app.void_operation` before `void_invoice()` returns, because both review rounds reproduced a bypass through the leaked window. A receipt reopens that window for the rest of the caller's transaction, now unforgeable but still open.
  - Scoping to "the invoice this row belongs to" narrows it a lot. After the void, no read is locked to X, no charge is billed on X, and X is void and sealed. So I predict nothing is admitted today.
  - That safety comes from the state machines, not from the seal. A later change, such as a correction run re-locking to a void bill or billing a charge onto one, would walk through.
- **The privilege [predicted].** The three guards run as invoker. Outside `void_invoice()` they run as `tally_app`, which "holds no privilege" on the receipt table. A guard that looks up the receipt raises `permission denied`. The reading guard computes `v_is_void_operation` unconditionally at the top, so every ordinary UPDATE of a reading would raise. The lookup must go through a definer helper, or tally_app gets SELECT on the receipt table.
- **The better predicate [executed].** Inside a SECURITY DEFINER function, every trigger fired by its statements sees `current_user` = the function owner. After it returns, the same transaction sees `tally_app` again. I tested this with a probe trigger on `invoices` and `invoice_events`:
  - inside the call: `current_user=tally_void`;
  - after the return, on an UPDATE in the same transaction: `current_user=tally_app`.

  `tally_app` cannot become that role: it is not a member, and PostgreSQL refuses `SET ROLE` inside a definer. So the guards' predicate becomes `current_user = 'tally_void'`, the role the act runs as, plus the exact write shapes they already enforce. It needs no table, no xid and no GUC, and its window is exactly the function call. It holds only while the seal-role invariants in B2 hold, the no-members one above all, so they are part of this fix.
- **One caveat [predicted].** A deferred constraint trigger fires at commit as the session role, so it can never see this carve-out. None of the three guards is deferred, and the drafting must not move one to deferred.

### B4. `tally_core` gains a write path **[executed]**

`tally_core` holds EXECUTE on `assert_reference_version` and only SELECT on the headers. With the function made a definer, `tally_core` bumped `GAS-R1` from 1 to 2 (battery T14). A core that should be read-only can then invalidate every editor's token and take header row locks.

The drafting must:
- revoke EXECUTE on the function from `tally_core`;
- add to `assert_core_role_invariants()` a by-shape check: `tally_core` may execute no `prosecdef` function except `get_user_tenant_id` and `is_platform_admin`.

---

## Should-fix

**S1. "Revoke UPDATE on `version`" is a no-op as worded** **[executed]**. `REVOKE UPDATE (version) ON rate_schedules FROM tally_app` while the table-level grant is held leaves `has_column_privilege(..., 'version', 'UPDATE')` = t, and a raw `SET version = version + 1` still returned 2. The patch must:
- run `REVOKE UPDATE ON <header> FROM tally_app` and then `GRANT UPDATE (status, updated_at, archive_reason, activated_at, archived_at)` on `rate_schedules`, and `(status, updated_at)` on `rate_items` and `wna_zones`;
- assert in a test that `has_column_privilege` is false for `version`.

After the table-level revoke, the raw bump is refused and an `updated_at`-only write still works (T2, T2b). That matters because the `rate_item_dependencies` mutex bumps `rate_schedules.updated_at` as the invoker.

**S2. Name the residual: the token is the caller's** **[executed]**. After losing the race, a second session called `assert_reference_version(id, (SELECT version FROM rate_schedules WHERE id = …))`. That is the current token, read just in time without re-reading content, and it succeeded (returned 3).
- What the seal proves: a version check ran in this transaction, under a header row lock.
- What it cannot prove: that the token came from the read the edit is based on. That stays an application contract, the honest remainder of CI-011.
- Tell Ryan this plainly. "To the app the right path looks the same" holds, but "two editors overwrite each other" is closed only for a client that passes the token it actually read.

**S3. Distinguish "not visible" from "stale"** **[executed]**. Under a non-BYPASSRLS owner, a hidden header (other tenant, unknown user) makes the UPDATE match 0 rows, and the function raises 40001. The app would retry forever on a 40001 that will never clear. Do this instead:
- first `SELECT … FROM header WHERE id = $1` (RLS-filtered);
- not found raises a distinct, non-retryable errcode (`no_data_found` or `insufficient_privilege`);
- only a version mismatch raises 40001.

**S4. Receipt identity: also bind `at = now()`** **[predicted]**.
- What holds. `pg_current_xact_id()` is the right coordinate:
  - **Subtransactions [executed]:** it returns the top-level xid inside them.
    - T5: a receipt written in a rolled-back savepoint vanishes together with the version bump and the row lock.
    - T6, T6b: a receipt from the top level or from a released savepoint admits a version write in a later subtransaction.
  - **Read-only transactions [executed]:** it assigns an xid even in `BEGIN READ ONLY`, so no NULL. The bump's UPDATE fails there anyway.
  - **Prepared transactions:** `max_prepared_transactions = 0` [executed]. A prepared transaction keeps its xid, so this is not a hazard.
  - **Wraparound:** `xid8` is epoch-extended, so there is none within one cluster.
- The flaw. xid8 is unique only within one cluster's life. After a logical dump/restore (or `pg_resetwal`), the new cluster's counter restarts below the restored receipts' values and sweeps through every one of them. A new transaction that happens to get xid X and writes entity E then passes on a 2026 receipt.
- The fix. Make the guard predicate `r.xact = pg_current_xact_id() AND r.at = now()`. `now()` is the transaction's start time; the receipt is stamped with it and never caller-supplied.
- Binding the version number. Not needed for the guard: the header row lock serialises writers until commit. It is worth stamping on the version rows, though (S7).

**S5. The guard must fire on every UPDATE, and the trigger must be definer-owned** **[executed]**.
- **Which UPDATEs.** Version tables have no drafts (`recorded_at` NOT NULL, default now()), so every UPDATE an open row admits is a close. Fire the guard `BEFORE INSERT OR UPDATE` rather than testing "sets `recorded_until`". It is simpler, and a future mutable column is covered by default.
- **Who it runs as.** It must read receipts that `tally_app` cannot read, so make the trigger function SECURITY DEFINER owned by `tally_seal`, revoked from PUBLIC. My prototype did this.
- **Migrations.** It also binds `tally` (superuser): any later migration or seed that writes version rows must call the check too. Say so in the comment; give it no superuser carve-out.

**S6. `void_invoice()` leaks another tenant's invoice number** **[executed]**. The cross-tenant refusal message interpolates `v_invoice.invoice_number`, which the caller cannot see. With B2 (RLS applies to the owner) it becomes "not found"; keep that, and do not interpolate the row in the explicit check.

**S7. Optional:** stamp the receipt's version onto each version row as a DB-written column, e.g. `header_version`. "Which token was this assertion written under" then becomes readable from the history, which the receipt alone (no user, no row link) does not give.

**S8. Scope the seal honestly** **[predicted]**.
- Header lifecycle writes (status, archive) still need no check. An archive racing an edit is caught by the header row lock plus the archived-entity insert check, but it does not invalidate a stale token.
- Schedule composition (`rate_schedule_items`, `rate_item_dependencies`) is outside the token by the D1-1 design.
- Neither is a hole in this proposal. Ryan should hear that CI-011 covers the three version tables, not "the entity".

---

## Question 1: paths checked

| Path | Result |
|---|---|
| Raw header version bump by `tally_app` | Refused after the table-level revoke (T2) [executed]. Not refused with a column-only revoke (S1) [executed]. |
| Version-row INSERT without the check | Refused (T3) [executed]. |
| Close (UPDATE) without the check | Refused: the trigger fires on UPDATE [executed in prototype on INSERT; UPDATE is the same trigger]. |
| Multi-row INSERT across two entities, receipt for one | Refused on the second row (T7) [executed]. |
| Writable CTE, check evaluated first | Admitted; the receipt is visible to the same statement's trigger (T8a) [executed]. |
| Writable CTE, insert first | Refused (T8b) [executed]. |
| COPY | `tally_app` gets "COPY FROM not supported with row-level security" on these tables [executed]. A superuser's COPY fires the trigger [predicted]. |
| TRUNCATE | `tally_app` holds TRUNCATE on no public table [executed]. Headers and version tables carry `no_truncate` triggers [executed]. The receipt table needs one too (Q6). |
| Other definer or trigger writers | No function body writes `*_versions`. The only header write outside the check is the `rate_item_dependencies` updated_at mutex, which is admitted and harmless [predicted from grep]. Locked reads, billed charges and `status='void'` are moved only by `void_invoice()`. The other UPDATEs of these tables are -05/-19 migration DO blocks [predicted]. |
| `rule_*` helpers | All invoker and pinned. None writes these tables. `rule_row_seed` and `rule_table_register` are owner-only [executed catalog + predicted body]. |
| `tally_core` | SELECT only on headers and versions [executed], but EXECUTE on the check (B4) [executed]. |
| Receipt forgery | `tally_app` gets `permission denied` on SELECT and on INSERT of receipts (T11) [executed]. |
| Two-session race | The second editor waited about 2 s on the header lock, then got 40001 after the first committed [executed]. |
| `fk_adhoc_invoice ON DELETE SET NULL` | Deleting a draft with billed charges is refused by the invoices guard first, and the adhoc guard refuses the pointer change regardless [predicted]. |

## Question 5: recommendation

**Gap 1: the receipt design**, with B1, B2, B4 and S1–S5.
- **(a) A write API** (revoke INSERT/UPDATE on `*_versions`) is the strongest seal. It is also a large surface: a jsonb-row API over three wide tables, and the app's path does not "look the same". It buys nothing the receipt does not, given S2's residual exists in both (the token is client-held either way).
- **(b) An `xmin` test** is wrong twice [executed]:
  - after the check runs inside a released savepoint, the header's `xmin` (4835) is the subxid, not the top xid (4834);
  - an `updated_at`-only header write, with no check, makes `xmin` match.

  So it keys on "the header was touched", not "a check ran".
- **(c) Application contracts only** fails the standing rule that a guard must act.

**Gap 2: neither receipts nor the GUC.** Use B3's role-identity predicate: `void_invoice()` is owned by `tally_void`, and the three guards admit their exact writes only when `current_user = 'tally_void'`.

## Question 6: receipts as a permanent log

Keep them.
- **Growth:** negligible. One row per entity-edit transaction, on tariff data.
- **Retention:** add the table to the CI-014 set (`no_hard_delete`, `no_truncate`).
- **Privileges:** owned by `tally`; `tally_seal` gets INSERT and SELECT; `tally_app` and `tally_core` get none.
- **RLS:** give it no `tenant_id` column, so it stays out of the RLS invariant and leaks nothing, since nothing but the seal reads it. If an audit UI later needs it, add `tenant_id` with the canonical policy and SELECT for `tally_app`, and the isolation assertion will then cover it.
- **Gap 2:** no receipts needed (B3). `invoice_events` already records the void.

## Question 7: what the patch must carry

- **Mutation tests**, each proving the guard catches it:
  - remove the receipt INSERT;
  - flip the guard's `xact` comparison;
  - drop the `at = now()` bind;
  - restore the table-level UPDATE grant;
  - re-own a definer to `tally`;
  - add `tally_app` as a member of `tally_void`;
  - write the tenant check with `<>`.
- **Race tests:**
  - two sessions with the same token (the second gets 40001 after the first commits);
  - an archive racing a version insert.
- **Void tests:**
  - post-return: after `void_invoice()` returns, the same transaction tries the three carve-out writes on the voided invoice's rows and on another invoice's rows, and must be refused;
  - pre-call: a `SET LOCAL app.void_operation = 'true'` must now admit nothing.
- **Depth fences and TEMP:** the receipt and role guards are not depth-based. Both still rely on `tally_app` defining no code, so keep the TEMP revoke, re-run it after every clone, and print the TEMP state in the battery. The seal roles must hold no TEMP or CREATE (B2 invariants).
