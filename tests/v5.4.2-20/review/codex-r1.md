**Verdict: request changes.** The original direct-write gaps are substantially closed, but the attach protocol has three predicted correctness holes, and the new triggers violate the existing `ENABLE ALWAYS` decision.

All three frozen MD5 hashes match the brief. This is a **static review: every behavioral finding and proposed test outcome below is predicted from SQL, not executed**. I did not run PostgreSQL, reproduce CI or mutation results, modify files, or read the other reviewers’ reports.

References to “patch,” “battery,” and “race script” below mean the frozen r1 copies.

**B1 — A charge can become billed on a void invoice without changing its pointer.**

The [attach guard](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-20/review/patch-20-frozen-r1.sql:800) fires on INSERT or UPDATE **OF `billed_on_invoice_id`**, and returns immediately when that pointer is unchanged. Neither the table constraints nor the charge guard require a pending charge’s billing pointer to be NULL.

Predicted sequence, entirely as `tally_app` with its own tenant:

1. Set a pending charge’s `billed_on_invoice_id` to live invoice H, leaving its status pending.
2. Call `void_invoice(H)`. Its charge UPDATE matches only `status = 'billed'`, so this charge is untouched.
3. Set the charge’s status to billed and populate `billed_at`, without assigning `billed_on_invoice_id`.

Step 3 does not fire the attach trigger. Even explicitly assigning the existing pointer would hit its unchanged-pointer early return. The charge guard admits pending → billed. The result is a billed charge attached to a void invoice.

**Required change:** validate entry into billed status as well as pointer changes. Establish a consistent relationship between charge status and billing pointers, and ensure every transition that creates an effective attachment participates in the invoice locking protocol. Add this three-step regression.

This is a missed part of inventory **V4**, separate from residual R8.

**B2 — The attach guard fails open for an RLS-hidden invoice.**

The same guard treats an invisible invoice as something “left to the foreign key.” That foreign key checks existence, not tenant visibility or invoice status.

The current FKs are:

- `adhoc_charges.billed_on_invoice_id → invoices(id)`;
- `meter_readings.locked_by_invoice_id → invoices(id)`.

They do not bind tenant IDs.

Predicted counterexample:

1. As tenant A’s application user, insert or update an A-owned charge to billed, naming tenant B’s existing void invoice.
2. The guard’s SELECT finds no visible invoice; `v_status` is NULL.
3. `IF v_status = 'void'` does not reject.
4. The FK accepts the existing invoice.

This bypass does **not** require impersonating another user through residual R1. A foreign invoice UUID suffices. It also permits attachments to a foreign live invoice that a later tenant-scoped void cannot see among its children.

**Required change:** reject a non-NULL pointer whose parent cannot be found under RLS. Bind child and parent tenants too—preferably with composite FKs—because a platform administrator can see both tenants and otherwise still create a mismatched relationship.

**B3 — REPEATABLE READ can leave a newly attached child on a void invoice.**

The parent lock serializes the demonstrated READ COMMITTED cases, but it does not refresh a REPEATABLE READ snapshot.

Predicted schedule:

1. A attaches a new billed charge to H and holds H `FOR SHARE`, without committing.
2. B begins REPEATABLE READ and calls `void_invoice(H)`. Its snapshot excludes A’s attachment; its `FOR UPDATE` waits for A.
3. A commits.
4. B acquires H’s lock. A only locked H; it did not create a new invoice row version, so this does not inherently cause a concurrent-update serialization failure.
5. B’s child UPDATE uses its old snapshot and misses A’s newly inserted charge.
6. B voids H and commits.

Both transactions can succeed with the charge stranded. A newly attached read has the same issue.

**Required change:** either enforce READ COMMITTED for this operation or introduce a parent row-version handshake that makes stale-snapshot execution fail. The repository already uses row-version writes for related snapshot coordination. Add both attach-first and void-first REPEATABLE READ cases.

The patch’s READ COMMITTED **migration precondition** does not constrain later calls to `void_invoice()`.

**B4 — The new guards are replication-skippable, contrary to the standing decision.**

The new receipt stamp, receipt delete/truncate guards, version-receipt guards, header-birth guards, and attach guards are created with ordinary trigger enablement. None is changed to `ENABLE ALWAYS`.

[Decision D-2026-08-20-27](/Users/ryanscomputer/code/tally-utility/application/DECISION-LOG.md:651) explicitly requires all immutability guards to be `ENABLE ALWAYS`, including protection against replication-apply omissions.

Predicted consequences under `session_replication_role = replica` include:

- version-row writes without receipts;
- arbitrary header birth versions;
- receipt modification or removal;
- attachments that skip the live-invoice check.

Existing ALWAYS triggers may reject particular malformed rows, but they do not replace these new checks. The invariant actually requires `tgenabled = 'O'`, so it would reject strengthening the version guards to ALWAYS.

**Required change:** enable the new guards ALWAYS and change the invariant accordingly. Rework S13’s privileged fixture construction; disabling protection for test convenience is not a reason to weaken production trigger enablement.

This is an administrative/replication-path defect, not evidence that ordinary `tally_app` currently has permission to set that parameter.

**S1 — The invariant implements substantially less than its advertised contract.**

[The assertion](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-20/review/patch-20-frozen-r1.sql:1151) has useful checks, but inventory **R4** is half-done.

| Clause | Static assessment |
|---|---|
| Role existence and six prohibited attributes | Checks what it claims. |
| No incoming or outgoing memberships | Checks a stronger condition than merely preventing application/core `SET ROLE`; intentionally reasonable. |
| No default privileges | Detects exploded entries naming the role or owned by it. An empty ACL produces no exploded rows, so “no default ACL entry” is stronger than this check. |
| No TEMP/database CREATE/schema CREATE | Effective privileges are checked, but schemas matching `pg_%` and `information_schema` are excluded. The claim should reflect that scope. |
| Exactly the sanctioned pinned functions | Uses names, not exact signatures. Additional overloads with sanctioned names pass. The required-owner check can also be satisfied by the wrong overload. |
| Search-path pin | `NOT (... AND p.proconfig @> ...)` becomes NULL when `proconfig` is NULL, so this assertion alone misses a missing pin. The separate tenant invariant catches the current public-definer NULL case. |
| No relation ownership | Checks what it claims. |
| Cannot write `users` | Misses column-level INSERT/UPDATE grants and TRUNCATE. |
| Core executes only the two RLS definers | Exceptions are by `proname`, permitting same-named functions in another schema or overloads. Use exact function identities. |
| Private receipts | Misses column-level grants; checks only INSERT for core, rather than all writes. |
| Header version UPDATE | Correctly uses effective column privileges, covering table-level grants too. |
| No old void setting | A lexical check over public function source, not proof that no code reads the setting. It also flags a comment containing the literal and misses a constructed name. |
| Enabled version guards | Checks only function identity and enablement. It does not check timing, events, row/statement level, arguments, WHEN conditions, or deferrability. |
| Header guards | Despite the nearby comment, none is checked. |
| Enumerated seal-role grants, R3 | No complete allowlist check exists. Unexpected privileges on reused cluster-wide roles survive. |

Use exact `regprocedure` identities, NULL-safe predicates, effective column privilege checks, and exact trigger shapes. Add mutations for these omissions.

In particular, “nothing but `assert_reference_version()` can write the receipts or a header version” is broader than what this assertion proves.

**S2 — The “cannot deadlock” statement is too broad.**

The fresh, single-child attach races in RC3/RC4 have the stated READ COMMITTED behavior. Arbitrary transactions do not.

Predicted example:

1. B updates an allowed annotation on an already billed charge C belonging to H, retaining C’s row lock.
2. A starts voiding H, locks H, then waits to update C.
3. B attempts to attach another charge to H and waits for H.

That is a child → parent / parent → child cycle. An equivalent situation can arise in a multi-row operation that touches an already attached row before a new attachment.

PostgreSQL should abort one participant; this is not a silent successful bypass. Either impose a consistent caller-level lock order or document deadlocks and whole-transaction retries. Replace the unconditional claim at patch lines 75–78 and add a deterministic test.

**S3 — The void grants appear sufficient, but they are broader than necessary.**

I found no missing grant on the existing valid void paths:

- The four auto-revert reasons share one charge UPDATE branch.
- Other valid reasons share the parked-charge branch.
- `duplicate` additionally reads invoices, already granted.
- `other` validates its notes without another table access.
- Held → void clears hold metadata through the existing trigger; it does not require another table grant.
- Empty read/charge sets require no additional capability.
- Platform-admin access is supplied by the RLS helpers.
- Existing issued bills, including bills with lines, take the early-return paths in the snapshot and surcharge/base issuance checks.
- The event tenant-sync trigger reads invoices, already granted.
- `billing_runs` access covers the existing dry-run guard dependency.

The absence of grants on line items, snapshots, and surcharge bases is therefore **not** a missing-grant finding for voiding. Those checks do not inspect that data on the void transition.

However:

- SELECT on `invoice_events` is not used by this function or its event INSERT trigger path.
- Whole-table UPDATE on invoices, reads, and charges exceeds the columns written by the function.
- Whole-table INSERT grants can also be narrowed.

Narrow the grants and assert the intended effective allowlist, particularly because the patch accepts pre-existing cluster-wide roles.

**S4 — Coverage and mutation claims need qualification.**

The named-error checks are stronger than generic “an error occurred” tests. Nevertheless:

- **O3 is incomplete:** the frozen files contain no COPY test and only the write-before-check writable CTE case. They do not test both CTE orders.
- MERGE is not covered.
- The only explicit receipt TRUNCATE test exercises application privilege denial, not the owner-facing trigger.
- S4e says “writes no receipt” but checks only the unchanged header version.
- S10g checks matching stored values, but does not challenge the stamp with deliberately wrong supplied transaction/time values.
- V11 proves INSERT privilege denial for `tally_void`; it does not exercise the invoice trigger’s INSERT rejection.
- V1’s comment says its line makes the void meet the line/base guards. Those guards return before examining lines on this transition.
- The void fixture section defers constraints and ultimately rolls back. Its unsnapshotted issued fixtures therefore do not demonstrate successful deferred-trigger completion.
- Add a valid issued-invoice fixture with constraints drained after the void, alongside the committed held-invoice races.
- Add B1–B3 regressions, a same-UUID/different-header-table receipt test, and mutations for exact invariant shapes.

The mutation harness recognizes a matching `FAIL <label>` anywhere in output; it does not enforce the “first failing check” claim for a race script that continues after failures. It also does not check every database setup command’s return status.

I did not establish an ordinary wrong-guard explanation for the listed mutation catches from inspection alone. But **38/38 is not reproduced here**, and the S13 mutations establish predicate sensitivity, not reachability of their forged states.

**N1 — Inventory implementation assessment.**

- **R1:** implemented for the intended roles, subject to the invariant scope details in S1.
- **R2:** ownership and pinning are set correctly; the continuing assertion is weaker than the requirement.
- **R3:** grants are enumerated and appear sufficient; they are not minimal or fully asserted.
- **R4:** incomplete; see S1.
- **R5:** the existing core EXECUTE capability is revoked correctly; the invariant’s name-only exceptions need tightening.
- **S1–S7:** implemented for ordinary origin-mode execution. B4 affects replication behavior and append-only guarantees.
- **V1–V2:** the dedicated role and immediate invoker guards implement the intended function-scoped authority.
- **V3:** the explicitly approved substitution of RLS for the duplicate tenant comparison is sound for invoice lookup. The inventory should be updated to describe that approved change.
- **V4:** incomplete; B1–B3.
- **O1–O2:** implemented.
- **O3:** incomplete; S4.
- **O4:** current live public bodies are replaced as intended; the continuing assertion is lexical.
- **O5:** current application grants are removed correctly; continuing verification misses column-grant drift.

**N2 — Receipt bindings: sound predicate, narrower evidence than claimed.**

The entity binding must include **both header table and UUID**. UUID equality across different header tables must not transfer authority.

The transaction ID prevents use of another transaction’s receipt. The start time additionally distinguishes restored historical transaction IDs. Time alone is not a unique transaction identity, and the claim that a restored transaction can “never” share an old wall-clock timestamp is too absolute.

The current-version binding enforces the advertised generation match. It is useful defense against stale evidence or privileged drift. However, under the current ordinary-writer protocol, each successful bump inserts its receipt atomically and retains the header lock. Removing the version predicate does not by itself demonstrate an application-reachable bypass: any successful check already supplies the latest receipt.

S13 is a legitimate isolated predicate test:

- It independently perturbs selected fields.
- S13a approximates stale evidence after transaction-ID reuse.
- S13c’s current-transaction receipt for a generation the header never reached is not a state the sealed function can produce.
- Privileged `session_replication_role` forgery is not a faithful simulation of an ordinary application attacker.

The four bindings are sufficient **conditional on exclusive trusted receipt production, intact triggers, and the stated identity boundary**. They are not sufficient against an administrator inserting an otherwise valid receipt.

Savepoint rollback removes both bump and receipt; releasing a savepoint preserves them. The non-allocating transaction-ID lookup supports the read-only false result. Prepared transactions retain their writes and locks; their eventual commit does not make their receipts usable by another transaction.

**N3 — Other write paths and execution identity.**

For ordinary application/core access under the current grants and origin-mode triggers, I found no additional path that directly:

- bumps a header version;
- writes a protected version row without the receipt predicate;
- releases a consumed read;
- unbills a billed charge; or
- updates an invoice into void outside `void_invoice()`.

The remaining invoker helpers, including rule helpers, do not acquire seal authority. Existing invoker views do not confer the owner’s privileges. No applicable rewrite-rule bypass was identified.

COPY, writable CTEs, multi-row DML, and MERGE do not inherently bypass row triggers. COPY FROM into RLS-protected tables is additionally restricted for ordinary callers. Existing DELETE/TRUNCATE fences remain relevant; the new receipt fences need B4.

The three void authorization guards are immediate invoker triggers. Deferring unrelated constraints does not prolong `current_user = 'tally_void'` after the function returns.

The battery’s `RESET ROLE; SET ROLE tally_void` succeeds because the session user is a superuser. A normal application login cannot reproduce that merely by owning a transaction or calling the definer. Function ownership does not grant membership to callers.

Inside the definer, superuser-keyed exceptions see `tally_void`, even when the session user is a superuser. Removing the duplicate tenant comparison therefore does close the unset-user NULL hole. An empty-string user setting still fails with a UUID-cast error rather than P0002, as the battery records.

Trusted administrators remain able to insert receipts directly, bump a header by the otherwise permitted increment, or assume the seal roles. The “only door” language should distinguish ordinary writers from administrative control. B4 separately concerns the repository’s explicit replication contract.

**N4 — Correction re-lock and inserted-billed paths are covered in their tested forms.**

A correction re-lock that changes `locked_by_invoice_id` from NULL to H runs the attach guard. An INSERT of a charge already billed on H also runs it. The existing reading workflow does not itself stamp a new invoice pointer after the attach guard has run.

Those are useful tests. They do not cover the unchanged-pointer charge transition in B1, the invisible-parent case in B2, or stale snapshots in B3.

**N5 — The three older battery adjustments preserve their purposes.**

- **Battery 10:** supplying the original bill’s tenant user preserves the correction-coordinate and held-discard tests. It removes accidental dependence on the missing-user authorization hole.
- **Battery 11:** supplying each tenant’s operator preserves the cross-tenant view fixtures and parked-charge behavior. The explicit application-call test remains relevant.
- **Battery 19:** checking the zone before writing its version preserves the downstream test’s purpose. Assuming `tally_void` from the superuser test session preserves the exact-disposition tests: it deliberately activates the internal authority so the narrower guards can be challenged.

The last change is appropriate as an internal guard test, provided it is not presented as a capability available to non-superuser callers.

**N6 — Residuals R1–R9 do not independently block this approved patch scope.**

- **R1:** still blocks any claim of authenticated tenant isolation against arbitrary application SQL. The brief explicitly defers that decision, so it is not a new patch blocker.
- **R2:** accurately distinguishes checking a supplied token from proving the token’s origin.
- **R3:** an essential caller contract; document and test it.
- **R4–R5:** acceptable deferred API/audit extensions.
- **R6:** acceptable for current reachable function bodies, but the asserted absence of user-write privileges needs S1.
- **R7:** accepted boundary around schedule composition.
- **R8:** an actual application-reachable lineage forgery on charge INSERT. It does not itself release a read, unbill an existing charge, or void an invoice, so it can remain a separate lineage issue. “No path writes one” should mean no sanctioned workflow, not no SQL path.
- **R9:** accurately describes receipt semantics and retention.

The blocking findings above are not covered by those residuals.