**Verdict: do not approve the proposal as written. Approve sealing both gaps, subject to the blocking changes below.**

This is a static review of `sql/tu.sql` and the patch SQL. **All behavioral findings and test outcomes below are predictions from SQL, not executed results.** I did not query the container, modify files, or read other reviewers’ files. The catalog facts in the brief are treated as supplied facts.

The reference receipt approach can enforce “a successful compare-and-bump occurred before this entity’s version writes.” The void proposal has a different problem: a permanent receipt authorizes subsequent statements in the transaction, whereas the existing function deliberately clears its authorization before returning. These should not share the same authorization lifetime.

**B1 — Rebuild the effective privileges; a column REVOKE alone does not work.**

The baseline grants table-level UPDATE to `tally_app` at [tu.sql:11381](/Users/ryanscomputer/code/tally-utility/sql/tu.sql:11381). PostgreSQL privileges are additive: revoking `UPDATE(version)` does not override table-level UPDATE.

For each header, the patch must revoke table-level UPDATE, remove any existing column grants that admit `version`, and grant UPDATE only on the sanctioned columns. Check effective privileges through PUBLIC and memberships, not just ACL entries naming `tally_app`.

Also address INSERT. The three counters default to 1, but the header guard covers UPDATE/DELETE, not INSERT. An unrestricted INSERT can choose the initial counter. This does not bypass a correctly implemented version-row receipt guard, but it contradicts a DB-controlled token and makes alternative (b) even weaker. Stamp or require the initial value, or exclude `version` from INSERT privileges.

Retain `updated_at` privileges needed by the dependency trigger. Do not turn that trigger into a definer merely to compensate for an incomplete grant list.

**B2 — A permanent void receipt must not remain an active authorization.**

The latest function clears its GUC before returning at [tu.sql:37986](/Users/ryanscomputer/code/tally-utility/sql/tu.sql:37986). Replacing that with an enduring `(transaction, invoice)` existence test reopens the rest of the caller’s transaction.

A predicted counterexample is:

1. Void invoice A legitimately.
2. In the same transaction, attach a new or editable charge to A and mark it billed.
3. Unbill that charge using A’s still-valid receipt.

The receipt proves that A was voided earlier; it does not prove that this charge was disposed of by that invocation. The same distinction matters for subsequently attached or re-locked reads. A different invoice’s receipt must also never authorize the act.

Use **function-scoped authority**, with audit evidence separate from authorization. A suitable design is a dedicated void-executor role, inaccessible through membership to application/core logins, with the transition guards accepting the exact void writes only when executing under that role. Keep those guards invoker-rights if they inspect execution identity; making the guard itself a definer would destroy that distinction.

Alternatively, use a private active-operation record created and removed within `void_invoice()`, including safe exception and nesting behavior. That record is transient control state, not a permanent append-only log.

Whichever mechanism is chosen:

- Derive the invoice from **OLD** locked/billed pointers, and from the invoice row’s immutable identity.
- Refuse missing pointers.
- Check tenant consistency.
- Preserve the meter-reading transition and pointer whitelist.
- Tighten the charge guard to the exact permitted disposition.

The last item is substantive: [enforce_adhoc_charge_immutable()](/Users/ryanscomputer/code/tally-utility/sql/tu.sql:13600) currently stops checking billed pointers altogether when the carve-out is active. It does **not** constrain every pointer to the exact values `void_invoice()` writes. An invoice-scoped receipt alone would preserve that excessive permission.

**B3 — The proposed tenant check is not an unforgeable caller identity check.**

The current definitions of `get_user_tenant_id()` and `is_platform_admin()` read `public.users` using caller-settable `app.user_id`; see [tu.sql:21186](/Users/ryanscomputer/code/tally-utility/sql/tu.sql:21186). The lookup is protected from search-path substitution, but its identity input is not authenticated by the database.

A caller able to issue arbitrary SQL as `tally_app` can choose another existing user ID, including a platform administrator’s. A DB lookup does not make a caller-selected identity trustworthy.

Under the standing requirement in this brief, drafting must include a protected identity boundary: for example, a mapping from authenticated database principals, or validated credentials whose verification material and identity mapping `tally_app` cannot alter. Merely moving `app.user_id` into another table through a publicly callable setter is insufficient.

There is also an immediate NULL bug in the existing void check:

```sql
IF v_invoice.tenant_id != public.get_user_tenant_id()
   AND NOT public.is_platform_admin()
```

With an unset or unknown user, the comparison is NULL and the IF does not reject. A superuser-owned definer can then continue despite missing identity. Use a positive, fail-closed authorization test; reject missing identity explicitly.

A platform-admin branch is needed **if preserving today’s authorized cross-tenant behavior is required**. It must use protected authority, not just the current `is_platform_admin()` input. Otherwise document the deliberate removal of that behavior.

This identity issue is broader than CI-011, but Ryan cannot approve the claim that the proposed tenant check is secure against arbitrary `tally_app` SQL while it remains unresolved.

**B4 — Changing SECURITY INVOKER to SECURITY DEFINER changes existing EXECUTE grants into write capabilities.**

The -17 grant loop gives `tally_core` EXECUTE on existing invoker functions, including `assert_reference_version()`; see [tu.sql:30310](/Users/ryanscomputer/code/tally-utility/sql/tu.sql:30310).

Changing the function’s security mode preserves its ACL. Consequently, the proposal would let `tally_core` bump counters and mint receipts even though its direct privileges on these reference tables are SELECT-only.

Explicitly revoke this function from `tally_core` unless that capability is intentionally authorized. Review PUBLIC, all explicit grantees, and inherited access. New receipt writers and internal helpers must not inherit blanket application EXECUTE grants.

The existing `assert_core_role_invariants()` does not comprehensively prohibit dangerous definer EXECUTE grants. Extend verification to cover the intended function capabilities and effective write privileges. Do not grant the executor role to `tally_core`: its no-membership invariant expressly forbids that.

**B5 — Specify how guards read private receipts without creating another privilege escalation.**

An invoker trigger running for `tally_app` cannot SELECT a receipt table on which the role has no privileges. As stated, the proposal would either fail legitimate writes or require an unspecified elevation.

Prefer a small, pinned definer predicate that only checks the current transaction and the exact entity. It must not mint receipts, accept a caller-selected transaction ID, or expose unrestricted cross-tenant receipt contents. Alternatively, a narrowly privileged definer trigger can read receipts, but its changed execution identity and any nested calls need review.

The receipt writer must stamp the transaction ID, entity kind, entity ID, tenant, returned counter and timestamp itself. Retain the current three-table allowlist and schema-qualified dynamic SQL. Do not allow callers to supply authorization fields.

Guard INSERT and actual closing UPDATEs regardless of `change_type`, `closed_type`, source labels, or trigger depth. Guarding every UPDATE is a reasonable simpler rule for these three tables: their existing bi-temporal triggers have no mutable-content exception, and `recorded_at` is NOT NULL. Their generic helper’s “draft is freely editable” branch is therefore not a current escape route.

**B6 — Resolve void locking and child-attachment races as part of sealing the operation.**

The latest `void_invoice()` initially reads the invoice without a row lock, validates that snapshot, then releases children and posts a reversal before updating the invoice.

Lock the invoice before evaluating its status and amount. A second void must wait and then reject the already-void state before performing side effects. Do not rely on a later immutable-row failure to make duplicate attempts safe.

The other half of this protocol is equally important: writers attaching billed charges or locking reads to an invoice must participate in compatible locking and reject a void invoice. Otherwise a child can arrive after the function’s release/disposition statement. Merely locking the parent inside `void_invoice()` does not establish that protocol for all child writers.

Specify lock order alongside the existing invoice/snapshot and schedule/dependency orders. The receipt itself supplies no serialization beyond the locks taken by its writer.

**B7 — Own the elevated entry points with narrowly privileged roles, not `tally`.**

Yes: use dedicated NOLOGIN, non-superuser roles, preferably separate reference and void executors. They should not own the business tables, hold role-management privileges, or be assumable by application/core logins.

The reference executor needs:

- Schema usage and necessary helper EXECUTE privileges.
- SELECT on the required header columns.
- UPDATE on `version` and `updated_at`.
- Receipt INSERT, if receipts remain.
- The reads required by header triggers fired during that UPDATE.

The void executor needs its explicit invoice/read/charge UPDATE columns, ledger/event INSERT privileges, necessary reads, and privileges required by all invoked triggers and defaults. Work out that transitive set; the top-level function body is not the whole grant inventory.

Prefer NOBYPASSRLS with policies admitting the necessary operations under a protected identity. A BYPASSRLS executor is still much safer than a superuser if its object privileges are narrow, but tenant isolation then depends on explicit checks throughout its elevated work. FORCE RLS does not constrain BYPASSRLS.

Special role-specific policies or private receipt policies may require a deliberate update to `assert_tenant_isolation_invariants()`, whose current public-table checks require canonical tenant policies. Do not weaken that assertion generally to accommodate one executor.

The same ownership question is open for `void_invoice()` today, and for the identity helpers. Moving identity helpers to ordinary RLS-constrained owners also requires avoiding recursive evaluation of the `users` policy.

**Path inventory — what remains possible, and what does not bypass a correctly drafted guard**

These are predictions from the inspected SQL, not runtime confirmations.

| Path | Assessment |
|---|---|
| Raw header `version = version + 1` | Remains possible if only column privileges are revoked while table UPDATE survives. Correct effective privilege removal closes it. |
| Header INSERT with chosen `version` | Currently possible through unrestricted INSERT; must be separately controlled. |
| Raw version INSERT or close | Blocked by a correctly implemented per-row receipt guard, including `initial`, succession, correction and retraction. No label exemption is justified. |
| Other version UPDATEs | Existing bi-temporal guard prohibits asserted-content changes and changes to closed rows. No-op writes need not represent a new logical edit. |
| Header status/archive writes | Remain possible through sanctioned column grants without an optimistic check. If CI-011 is intended to cover lifecycle edits too, the proposal does not achieve that scope. |
| `assert_reference_version()` | The intended counter writer. Its current atomic conditional UPDATE is the correct comparison/locking primitive. |
| `enforce_rate_item_dependency()` | Writes `rate_schedules.updated_at` without a version check at [tu.sql:37039](/Users/ryanscomputer/code/tally-utility/sql/tu.sql:37039). It does not increment `version`, but defeats `xmin` as proof of checking. |
| Snapshot validator | Updates invoice timestamps for locking at [tu.sql:20900](/Users/ryanscomputer/code/tally-utility/sql/tu.sql:20900); does not independently void invoices. Existing guards still fire. |
| `void_invoice()` | The surviving definer write path for the three void effects. Earlier definitions in the mirror are superseded, not additional callable implementations. |
| Other existing definers | The two identity helpers read `users`; they do not independently write the target tables. Their identity weakness still matters. |
| `rule_*` helpers | Invoker-rights helpers confer no extra table privileges. `rule_row_seed()` writes registered law tables, is migration-only, and has EXECUTE revoked from PUBLIC/app/core. `rule_table_register()` is likewise restricted. No inspected helper supplies an alternate privileged reference-version writer. |
| Migration backfills | The mirror contains historical version inserts and other updates executed during migration. These are owner operations, not application-callable bypasses. |
| `tally_core` | Direct reference writes are not granted, but the preserved EXECUTE grant would become an elevated counter-write path under this proposal. |
| DELETE / FK actions | Existing no-delete/immutability guards remain necessary. Ordinary FK-triggered changes do not escape applicable row triggers. |
| TRUNCATE, including CASCADE | Does not fire row receipt guards. Existing statement-level no-truncate guards cover the three headers/version tables, reads, charges and invoices. Preserve them and add separate protection for permanent receipts. |
| COPY FROM | Does not bypass ordinary row triggers. Application COPY into RLS-protected tables is additionally restricted; privileged loading must not be treated as exempt from guard design. |
| Writable CTEs | Do not bypass triggers, but textual CTE order is not a safe “check first” protocol. Use separate ordered statements or one controlled write API. |
| Multi-row statements / UPSERT / MERGE | Every affected row must satisfy the applicable check. Authorization for one entity cannot authorize another; one rejected row must roll back the statement’s effects. |
| Owner/superuser DDL | Outside this application boundary: a superuser can disable/drop enforcement. Do not claim protection against the migration administrator. |

A caller can also read the current version and immediately present it to the assertion. The database can enforce comparison with a supplied token; it cannot prove that this was the token the human originally reviewed.

**Transaction identity and receipt predicate**

`pg_current_xact_id()` returning `xid8` is appropriate for a transaction-scoped receipt within this database.

- **Savepoints:** It identifies the top-level transaction, including work performed in subtransactions. Rolling back the savepoint that created a receipt also rolls back that receipt and the associated counter update. A surviving receipt created before a savepoint remains usable after rollback to that savepoint. A receipt from a successfully released subtransaction can authorize later subtransactions.
- **Read-only transactions:** The function can assign an ID where none was assigned; assignment is not authorization and does not make a read-only transaction writable. The header UPDATE and receipt INSERT cannot succeed in a read-only transaction. A read-only predicate can use `pg_current_xact_id_if_assigned()` and treat NULL as no authority.
- **Wraparound:** Store `xid8` without narrowing it to `xid`, integer, or the header’s 32-bit `xmin`. Epoch extension avoids ordinary 32-bit reuse.
- **Prepared transactions:** Preparation retains transactional state and locks. Receipts become committed evidence only on COMMIT PREPARED and disappear on rollback. A later transaction cannot reuse their transaction ID. Long-lived prepared transactions can retain header locks, so operational support must be deliberate.

For CI-011, `(xact, entity kind, entity ID)` is sufficient to prove **at least one successful check in this transaction**, provided that successful checking remains the only way to mint a receipt and the header lock survives.

I would nevertheless record the **returned, post-bump version** and require it to match the current header counter. That makes the authorized generation explicit and prevents an older receipt from satisfying a later-generation check accidentally. The counter belongs to the header; do not confuse it with a version-row UUID or valid-time sequence.

Decide whether one check authorizes a batch of closes/inserts for an entity. That is normally desirable. A receipt is not inherently a single-use authorization, and version binding does not make it one.

For voiding, transaction identity is correct but transaction-wide authorization lifetime is wrong.

**Recommendation on alternatives: choose (a), a complete write API.**

Revoke direct INSERT/UPDATE on the three version tables and expose narrowly privileged functions that accept the expected header version and perform the complete operation: compare-and-bump, close/retract as required, and insert successors atomically.

Provide initial creation, succession, correction, retraction and multi-row entity edits explicitly. Keep the existing bi-temporal constraints and triggers. This avoids a permanent receipt subsystem merely to connect two separately callable actions.

For voiding, retain `void_invoice()` as the sole operation and use narrowly scoped executor authority plus exact transition guards. The API still needs B3’s protected identity and B6’s locking protocol.

Comparison:

- **Receipt design:** Viable for references after the blocking fixes; preserves the existing multi-statement calling shape, but adds private storage, elevated lookup code, lifecycle rules and verification burden.
- **(a) Write API:** Recommended. Places comparison and mutation in one authorized operation. It changes the application calling contract, which must be acknowledged.
- **(b) Header `xmin`:** Reject. Timestamp-only updates—including the existing dependency trigger—change `xmin` without checking the expected token. INSERT also creates a current-transaction tuple. Subtransaction IDs and 32-bit transaction identity create further mismatch with a top-level `xid8` test.
- **(c) Application contracts:** Reject for these gaps. Core tests cannot prevent raw application SQL from bypassing the checks, and no interim core-dependent arrangement satisfies the brief.

**S1 — Separate permanent audit evidence from authorization state.**

Permanent reference receipts are not required for enforcement after commit. If retained as audit records, explain their evidentiary limits: a successful assertion can commit without any version mutation. Such a receipt proves a check/bump occurred, not that a particular edit was completed.

If permanent receipts are chosen:

- Add them explicitly to the CI-014 protected set, with UPDATE/DELETE and statement-level TRUNCATE protection.
- Revoke inherited/default application privileges immediately; the schema’s default grants otherwise undermine “private at creation.”
- Index the actual authorization key and plan for indefinite growth.
- Store tenant identity and protect any application-readable projection with RLS.
- Default to no application SELECT; the application does not need receipt contents to edit.
- Do not permit arbitrary cleanup while simultaneously promising append-only permanence.

A private active void-operation table must have a different lifecycle from an immutable audit log.

**S2 — Correct the compatibility claim.**

“Schema-only and additive” is inaccurate: privilege revocation and SECURITY DEFINER conversion change security semantics and caller behavior.

Even retaining receipts requires all initial version creation and all existing edit paths to call the assertion in the same transaction. Autocommit between checking and writing must fail. The write-API recommendation requires caller changes outright.

Empty tables remove a historical-data conversion problem; they do not remove deployment, privilege or application-contract work.

**S3 — Fence trigger depth, TEMP and executor identity explicitly.**

Do not add `pg_trigger_depth()` exemptions to either new guard. Depth establishes nesting, not which operation authorized a write.

Preserve the existing restrictions on TEMP, database/schema CREATE, TRIGGER privileges, dangerous role memberships and trigger-disabling capabilities. Check effective privileges of actual service logins as well as group roles. A login can inherit capabilities not visible when testing only `tally_app`.

Run the TEMP checks after template cloning: database ACLs need explicit treatment, as the project’s -11/-17 SQL already notes. Pin every new trigger/definer search path, qualify relations, and keep writable schemas outside the resolution boundary.

**Required patch tests — predicted acceptance criteria, not executed**

- Direct counter bump fails; allowed header updates and dependency-trigger timestamp writes still work.
- Chosen initial counters, unauthorized receipt INSERT/UPDATE/DELETE/TRUNCATE, and direct internal-helper calls fail.
- Every reference table rejects unchecked INSERT and close, across all labels and raw SQL/helper paths.
- Correct expected version succeeds; stale expected version fails with `40001`; wrong entity/table/tenant receipts fail.
- Savepoint rollback removes newly minted authority; surviving earlier authority behaves as specified; full rollback removes every effect.
- Separate transactions and autocommit cannot share authority; read-only and prepared-transaction behavior matches the documented contract.
- Two connections editing one entity serialize: the same expected version yields one successful editor, and the loser leaves no receipt or partial version history.
- Mixed-entity batches, writable CTEs, COPY where supported, UPSERT and MERGE cannot use one row’s authorization for another.
- Missing, unknown, empty and forged identity inputs fail closed; authenticated tenant and platform-admin paths behave as intended.
- `tally_core`, PUBLIC and actual service logins cannot gain unintended elevated writes through preserved EXECUTE grants.
- Direct void status writes—including INSERT—locked-read release and billed-charge pointer changes fail outside `void_invoice()`, even after setting the old GUC.
- A completed void cannot authorize later writes, another invoice, newly attached children, or repeated release/disposition in the same transaction.
- Concurrent voids produce one committed reversal/disposition; concurrent child attachment cannot strand billed charges or locked reads on a void invoice.
- Injected failure after each void stage rolls back all effects and leaves no active authority.
- TEMP/CREATE/role-grant mutations and trigger removal/disablement are detected by catalog assertions; restored/cloned databases retain the same boundary.

Ryan should authorize drafting **the complete reference write API and a function-scoped void authorization design**, with protected caller identity, narrow executor ownership and explicit locking. The proposed permanent-receipt mechanism is a workable fallback for references, but it is not an adequate shared solution for both gaps.