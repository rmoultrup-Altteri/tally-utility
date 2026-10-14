**Verdict: approve with non-blocking follow-ups.** All four Codex r1 blocking items are closed by the frozen r2 SQL. I found no new ordinary-writer bypass within the patch’s stated boundary.

**Review basis:** all three MD5 hashes match the brief:

| Frozen file | Verified MD5 |
|---|---|
| `patch-20-frozen-r2.sql` | `382fa4d39341d2398c82775c779a66ac` |
| `battery-20-frozen-r2.sql` | `a0b6ec64c7e2b3ec51feaf1e617319ea` |
| `seal-20-frozen-r2.sh` | `dc36ebd2e1730d4dbd93bc4cd805a02e` |

This is a **static review**. Every behavioral conclusion and repro outcome below is **predicted from the SQL, not executed**. I did not run PostgreSQL, CI, batteries, races, or mutations; modify files; or read another reviewer’s r2 report. The reported execution results remain unverified here.

**B1–B4 — Round-1 blocking items: closed.**

| R1 item | Re-evaluated repro against r2 — predicted outcome |
|---|---|
| **B1: pending charge carries a pointer through void, then becomes billed** | The first step now fails with `23514` on `adhoc_charges_billed_names_its_bill`. Conversely, entering billed without a pointer fails. A valid transition into billed must assign its previously NULL pointer and meet the attach guard. |
| **B2: RLS-hidden or cross-tenant parent** | The attach guard now rejects both a lookup returning no row and a visible invoice whose tenant differs from `NEW.tenant_id`, with `23001`. This covers ordinary tenant callers and platform administrators. |
| **B3: stale-snapshot void misses an attachment** | REPEATABLE READ and SERIALIZABLE calls fail with `25000` before acquiring the invoice lock or making writes. The original attach-first schedule cannot reach the child updates. At READ COMMITTED, the later child statements can see the attachment committed while the invoice lock was awaited. |
| **B4: replication skips the new guards** | The new guards are explicitly ALWAYS; the rewritten guards retain their existing ALWAYS state, which the final assertion requires. Replica mode therefore does not provide the r1 bypass. |

The relevant fixes are in the frozen [attach guard and CHECK](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-20/review/patch-20-frozen-r2.sql:832), [isolation refusal](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-20/review/patch-20-frozen-r2.sql:915), and [trigger assertion](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-20/review/patch-20-frozen-r2.sql:1421).

**No additional blocking item identified.**

**S1 — The privilege assertion still proves less than “exact privileges.”**

The [privilege enumerator](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-20/review/patch-20-frozen-r2.sql:1215) substantially improves r1, but it enumerates direct ACL entries and omits `is_grantable`.

Two predicted counterexamples to the broad claim:

- Adding `WITH GRANT OPTION` to an already allowed grant produces the same privilege string and passes this comparison.
- Granting an additional table/column privilege through PUBLIC does not appear in either seal role’s direct list. For example, PUBLIC UPDATE on `users.display_name` would give both roles that effective privilege without this allowlist noticing it.

Some PUBLIC exposures are caught separately, notably receipt access, header-version UPDATE, code-creation privileges, and core access to definers. Those checks do not make the entire seal-role allowlist effective-privilege complete.

The temporary-function exclusion is also broader than the test helpers: it excludes functions in **every** schema matching `pg_temp_%`, without checking function identity or whether it is SECURITY DEFINER. Session lifetime is not itself an authorization guarantee.

**Suggested change:** check grant options; explicitly account for relevant PUBLIC-derived privileges; and run the production assertion outside the temporary-helper grants, or narrowly specify the test exception. Otherwise qualify the contract as an exact list of direct privilege names, subject to the documented exclusions.

These are continuing-verification gaps. I did not identify a current sanctioned function path that exploits them.

**S2 — Assert the CHECK that now closes B1.**

The trigger assertion checks all 17 listed trigger definitions and their ALWAYS state, but does not check `adhoc_charges_billed_names_its_bill`.

**Predicted repro:** after application, drop that constraint as the owner and call `assert_seal_role_invariants()`. The assertion does not detect its absence, although the r1 B1 sequence becomes possible again.

Battery V4g and mutation M41 cover the constraint behavior, so this is not an absent implementation or absent regression test. It is a gap in the continuing assertion.

**Suggested change:** assert the constraint’s presence, validated state, and expression alongside the attach triggers.

**S3 — The mutation harness improvement is real, but setup failures remain unchecked.**

The [revised harness](/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-20/mutations-20.py:208) now checks the first matching named `FAIL`, closing the principal r1 ordering concern.

However:

- DROP DATABASE, CREATE DATABASE, and TEMP-revocation return codes are still ignored.
- Acceptance considers the first *named* failure matching `FAIL [A-Z]+\d`, rather than the first error of any kind.
- Runner return status is not part of the acceptance condition.
- Concatenating stdout and stderr does not preserve ordering between streams.

**Suggested change:** stop a mutation on any setup failure, combine runner output in execution order, and reject earlier infrastructure errors before accepting its named failure.

This limits confidence in the harness’s reporting under failed setup; it does not establish that any reported catch was wrong.

**N1 — The charge CHECK is compatible with the current write paths.**

Predicted from the current definitions:

- `status` is NOT NULL, so CHECK’s NULL semantics do not create an escape.
- Pending creation with no invoice remains valid.
- Billing must set status and invoice pointer together.
- Both void branches clear the invoice pointer in the same UPDATE that changes status to `pending` or `void_pending_rebill`.
- Non-billed disposition changes remain valid while the pointer stays NULL.
- Annotation updates preserve the relationship.
- No inspected current trigger silently turns a non-billed charge into billed after bypassing pointer validation.

The stronger CHECK intentionally rejects formerly legal inconsistent historical rows during application. It validates existing data rather than silently repairing it.

**N2 — Savepoints do not defeat the isolation refusal.**

The function reads the actual transaction isolation setting on every call; it does not cache authorization in a caller-controlled flag.

Predicted behavior:

- Calling under REPEATABLE READ inside a savepoint still raises `25000`.
- Rolling back to that savepoint can recover the caller’s transaction, but does not convert its isolation level or authorize a later void.
- Catching the exception in PL/pgSQL likewise leaves no void side effects.
- At READ COMMITTED, rolling back a savepoint containing a successful void rolls back its writes; releasing it preserves those writes and the required locks until the enclosing transaction completes.

The frozen tests cover the basic isolation refusal, but not these void-specific savepoint cases or an explicit SERIALIZABLE refusal. Those would be useful additions, not prerequisites for closing B3.

**N3 — Trigger-shape strings depend on a controlled search path.**

`pg_get_triggerdef()` rendering can depend on function visibility. Here, however, `assert_seal_role_invariants()` pins `search_path = public, pg_temp`, and its expected strings use that rendering: qualified relation names and visible, unqualified public trigger-function names.

Consequently, a caller’s empty or reordered search path is not predicted to cause a false mismatch. Temporary functions do not implicitly shadow function resolution through the temporary-schema search mechanism.

The exact string comparison is PostgreSQL-deparser-sensitive across upgrades, but I found no caller-search-path defect in this implementation.

**N4 — The narrower void grants cover the inspected branches.**

Predicted grant sufficiency:

- All four auto-revert reasons use the same granted charge columns.
- Other reasons use the parked-charge branch, also covered.
- `duplicate` reads invoices; `other` validates notes without another relation.
- Ledger lookup, running-balance calculation, INSERT and `RETURNING id` have the required ledger privileges.
- Event insertion and tenant synchronization have the required INSERT and invoice SELECT privileges.
- Held → void clears hold metadata through BEFORE-trigger changes to `NEW`; those assignments do not require additional UPDATE grants on the cleared columns.
- The invoice dry-run trigger is tied to assignment of `billing_run_id`, which this UPDATE does not assign.
- The reading dry-run check does not need to inspect the run when its pointer is unchanged.
- The ledger dry-run branch does not inspect billing runs for an `invoice_void` reference.
- Snapshot and issuance checks take their void-transition exits.

Thus dropping billing-run SELECT is justified; my r1 suggestion that it was needed was too broad.

The revised `42501` expectations for out-of-grant writes in batteries 19 and 20 are appropriate. INSERT on ledger/events remains table-level, so “minimal” should not be read as every privilege being column-minimized.

**N5 — The three “Not taken” decisions are acceptable.**

- **OLD entity check:** the existing bitemporal guard freezes the entity column. Checking NEW’s entity does not authorize a successful move away from OLD’s entity.
- **Composite tenant FKs:** the new visibility refusal and explicit child/parent tenant comparison close the identified attachment bypass. Broader tenant-FK enforcement can remain the recorded separate decision.
- **Check-first writable CTE:** separate statements are the documented protocol. Omitting a positive test for an unsupported ordering convention is reasonable.

None requires reopening a blocking item.

**N6 — R1 follow-up status and evidence limits.**

- **R1 S1:** substantially addressed through exact identities, NULL-safe pin checks, column grants, and trigger shapes; remaining scope gaps are S1–S2 above.
- **R1 S2:** addressed by the deadlock documentation and RC6.
- **R1 S3:** UPDATE grants are narrowed appropriately; no missing runtime grant identified.
- **R1 S4:** substantially addressed by receipt counting, adversarial stamp inputs, same-UUID/different-table coverage, MERGE, COPY, isolation coverage, and revised failure ordering.

Battery 10 F0c does provide the previously requested snapshotted issued-bill void with constraints immediate. Battery 20’s deferred, rolled-back invoice fixtures should still not independently be described as proving deferred-trigger completion.

Two small coverage/documentation leftovers remain: owner-facing receipt TRUNCATE is not exercised, and the comment saying I1’s line makes the void meet line/base guards remains misleading because those guards exit on the void transition.

The strict-apply marker predicts that a second application skips the patch. The supplied CI, 79-check, race, and 50/50 mutation results were **not reproduced in this read-only review**.