# v5.4.2-20 r1 review: Opus

**Date:** 2026-10-14. **Reviewer:** Opus. **Scratch DB:** `rv20opus` (dropped at the end).

**Hashes checked (executed):** brief `7b913151…` matches its `.md5`. Patch `62e37198…`, battery `27d501e2…`, race script `52d4d8b5…` match the brief. The live patch is identical to the frozen one.

**Reproduced (executed):** I cloned `tally`, revoked TEMP, and strict-applied the patch twice. The first run applied it. The second hit its marker and skipped. `battery-20` gives 74 PASS. I did not run `ci.sh`, `seal-20.sh` or `mutations-20.py`.

## Verdict: not yet

Both seals hold against every direct write I tried. The open paths are both in the attach guard (V4), which keeps a voided bill from collecting a charge. Neither needs a superuser. Each has a small fix.

---

## Blocking

### B1. The attach guard admits a void bill the caller cannot see (executed)

`enforce_attach_to_live_invoice` reads the invoice under row-level security. If the read finds nothing (`v_status IS NULL`), the guard admits the write and leaves the rest to the foreign key. But both foreign keys are on `id` only (`fk_adhoc_invoice`, `fk_readings_locked_by_invoice`), and foreign-key checks ignore row-level security. So an invoice the caller cannot see is never checked for void.

Repro, committed:
1. As tenant 2's platform admin, void the held bill OP-H9.
2. As a tenant-1 operator (`tally_app`), run:
   `UPDATE adhoc_charges SET status='billed', billed_on_invoice_id='<OP-H9>', billed_at=now() WHERE id='<a tenant-1 pending charge>'`
3. Commit.

Result: the charge is billed on a void bill in another tenant. It can never leave `billed`, because only `void_invoice()` on that bill releases it, and that bill is already void. This is the stranded charge V4 exists to prevent. The same path works for `meter_readings.locked_by_invoice_id`.

**Fix:** refuse on not-found as well: `IF NOT FOUND OR v_status = 'void'`. A superuser history load bypasses RLS, so it still sees the bill. Add a battery case for it.

(A cross-tenant pointer onto a *live* bill is also admitted. That is an older tenant-wall gap and not this patch's, but the same fix closes it for these two pointers.)

### B2. A void under REPEATABLE READ or SERIALIZABLE leaves an attach behind (executed)

The lock-order argument assumes the void runs under READ COMMITTED: each of its statements takes a fresh snapshot, so it sees what an attach committed while the void waited. `void_invoice()` does not enforce that isolation level.

Race, committed (session A is the void, B the attach):
1. A: `BEGIN ISOLATION LEVEL REPEATABLE READ`, then any read (this takes the snapshot), then a sleep.
2. B, at READ COMMITTED, bills a charge onto the held bill H and commits. A holds no lock yet, so B does not wait, and its attach guard sees H as live.
3. A calls `void_invoice(H)`. Its `FOR UPDATE` raises nothing, because B only locked H and did not update it. Its charge UPDATE matches through A's snapshot, where the charge is not yet attached.

Result: `charges_auto_reverted = 0`. The bill is void and the charge stays `billed` on it. The same happens with A at SERIALIZABLE and B at READ COMMITTED (executed). An application that reads before voiding at a higher isolation level hits this without trying.

**Fix:** `void_invoice()` refuses unless `current_setting('transaction_isolation') = 'read committed'`. That fails closed, with a message naming the requirement. Add RC6 to `seal-20.sh` with the void at REPEATABLE READ.

---

## Should fix

**S1. "Cannot deadlock" is false (executed).** Suppose the attaching transaction first locks a child that is already attached to H (for example, `UPDATE adhoc_charges SET updated_at = now()` on a charge billed on H). It then attaches another charge to H. Meanwhile a void takes H `FOR UPDATE` and waits on that first child. Result: `ERROR: deadlock detected`. The attach rolls back and the void completes. Nothing is stranded, because PostgreSQL resolves the deadlock. But the header's lock-order paragraph and the comments on V4 and the guard claim it cannot happen. Restate the claim as "an attach that has not touched the bill's children cannot deadlock; otherwise one side gets 40P01 and retries", or have the attach take the bill `FOR SHARE` before its first child write.

**S2. The invariant misses column-level grants on the receipts (executed).** O5 tests `has_table_privilege(..., 'INSERT')`, which is false for a column grant. In a rolled-back transaction I ran:
`GRANT INSERT (header_table, entity_id, version, tenant_id) ON reference_version_receipts TO tally_app`
The invariant passed. `tally_app` then inserted a receipt, which the trigger stamped with its own transaction and time, and wrote a zone version with no check. The header version stayed at 1: a full bypass that the invariant claims to catch. Use `has_any_column_privilege` for INSERT and UPDATE, and cover `tally_core` and PUBLIC for UPDATE, DELETE and TRUNCATE as well.

**S3. The users fence (R6) misses column grants (executed).** `GRANT UPDATE (email) ON users TO tally_seal` passed the invariant, and so did `GRANT SELECT ON users, customers TO tally_void`. Use `has_any_column_privilege` for INSERT and UPDATE. More broadly, R3's enumerated grants are not checked at all: an extra privilege on any table passes. Assert each seal role's exact privilege set from `aclexplode(relacl)` and the column ACLs, so a later `GRANT … ON ALL TABLES` is caught.

**S4. The trigger check is narrower than its comment (executed).** The comment says "the three version tables and the three headers carry their guards", but the code checks only `a0_enforce_reference_version_receipt` on the version tables. In a rolled-back transaction I disabled four triggers: `enforce_reference_header` and `enforce_reference_header_birth` on `wna_zones`, `a_enforce_attach_to_live_invoice` on `adhoc_charges`, and `enforce_invoice_immutable`. The invariant passed. Extend it to the header guard, the birth guard, both attach guards and the three void guards (read, charge and invoice).

**S5. The new guards are `O`, the house guards are `A`, and the invariant rejects `A` (executed).** The patch's triggers are enabled `O` (origin): `a0_…`, `enforce_reference_header_birth`, both `a_enforce_attach_to_live_invoice`, and the receipts' stamp, `no_hard_delete` and `no_truncate`. The guards next to them are `A` (always): `a_enforce_bitemporal_assertion`, `no_hard_delete`, `enforce_reference_header` and the invoice guards. An `O` trigger is skipped under `session_replication_role = replica`, which a superuser can set and a logical-replication apply worker runs under. So S6's "no superuser or depth carve-out" holds only outside replica mode. After `ENABLE ALWAYS` on the version guard, the invariant raises "lacks the enabled version-receipt guard": it rejects the stronger setting. Make the guards `ENABLE ALWAYS` and accept `tgenabled IN ('O','A')`, or require `'A'`. S13's forgery depends on replica mode skipping the stamp, so it would then plant its receipts with `ALTER TABLE … DISABLE TRIGGER` inside the transaction instead.

**S6. `tally_void`'s grants are wider than its path (executed).** I voided committed issued bills with a snapshot, a line item, a locked read and billed charges, plus a held bill. I used every reason-code branch: `wrong_rate`, `wrong_customer`, `duplicate`, `other` with notes, and `system_error` on the held bill. I also voided as another tenant's platform admin. Every void passed and committed. Then I removed grants one at a time (rolled back) and voided again:
- Still worked without `SELECT ON billing_runs`. The only trigger that reads it is `dry_run_no_invoices`, which is `UPDATE OF billing_run_id`, and the void never sets that column.
- Still worked without `SELECT ON invoice_events`.
- Still worked with column-level UPDATE in place of table-level UPDATE: on `invoices` (status, voided_at, voided_by, void_reason_code, void_reason_notes, void_rebill_expected, updated_at), on `meter_readings` (voided_from_invoice_id, locked_by_invoice_id, validation_status), and on `adhoc_charges` (status, voided_from_invoice_id, billed_on_invoice_id, billed_on_line_item_id, billed_at, target_billing_period, updated_at).
- Failed without `SELECT ON account_ledger`, so that one is needed.

Grant the column sets and drop the two SELECTs. That makes R3's "enumerated" true.

**S7. O3 is half-done in the tests (executed for the missing cases).**
- **COPY:** no case. As `tally_app`, COPY into a version table is refused before the guard ("COPY FROM not supported with row-level security"). That is worth a line, because the closure comes from RLS, not from the seal.
- **Writable CTE, check first:** only the write-first order (S7c) is tested. The check-first order (`WITH c AS (SELECT assert_reference_version(...)) INSERT … SELECT … FROM c`) is admitted. Add it as an admits case, so a change that breaks it is seen.
- **MERGE:** no case. An unchecked MERGE INSERT is refused by the guard.
- **TRUNCATE of a version table:** no case. It is refused on privilege.

**S8. V11 passes on privilege, not on the guard (predicted for the mutation).** `tally_void` has no INSERT on invoices, so V11 is refused with 42501 and never reaches the guard's `TG_OP = 'UPDATE' AND current_user = 'tally_void'`. A mutation that drops `TG_OP = 'UPDATE' AND`, so that the void role may insert a bill born void, passes every check: V2d runs as `tally_app`, and no mutation in the list targets that clause. Either test the clause as a superuser session with `SET ROLE tally_void` after granting INSERT in the transaction, or record that the privilege is the guard and drop the clause.

**S9. No committed void of an issued bill in the -20 tests (executed in the clone).** V1 runs with constraints DEFERRED and the battery rolls back, so the deferred triggers `enforce_invoice_has_snapshot` and `…_surcharge_lines_and_bases` never fire after a void as `tally_void`. The race script voids held bills only. I committed voids of bills issued with a snapshot (above), and they work: both deferred triggers return early for `void`. Note that deferred triggers run at commit as the caller (`tally_app`), not as `tally_void`, so a future deferred guard keyed on `current_user = 'tally_void'` would never admit. Add one committed void of an issued, snapshotted bill to `seal-20.sh`, and record that deferred triggers do not see the void's role.

---

## Notes

**N1. The receipt test (Q4) (reasoned).**
- **Entity** and **transaction**: necessary. Without the transaction, two transactions that start in the same microsecond could share a receipt once the first commits.
- **Start time**: necessary against an id reused after a dump and restore.
- **Version**: adds nothing against `tally_app`. After its check, this transaction holds the header row lock, and only this transaction's own checks can move the version, each writing a matching receipt. It is defence in depth against a superuser bumping the version directly, which the header guard allows by +1.
- With `header_table`, the four are sufficient.
- S13's forgery is a faithful model of the predicate: each planted receipt is wrong in exactly one part. It is not a model of an attacker, since only a superuser can plant one. `header_table` is a fifth binding that S13 does not exercise.

**N2. The version guard checks only NEW's entity (executed).** A version row moved from an unchecked entity into a checked one is refused, but by `a_enforce_bitemporal_assertion` ("never edited in place"), not by the receipt guard. The seal depends on that guard keeping the entity column immutable. Say so in the guard's comment.

**N3. A header can be born `archived` with no check (executed).** A `wna_zones` INSERT with status `archived` is admitted. That is a birth, not a move, so S7 holds as written. A schedule born `active` is refused by R-14.

**N4. The invariant matches owned functions by name, not signature (predicted).** A second definer overload named `void_invoice`, owned by `tally_void` and pinned, would pass. Compare `oid::regprocedure` instead.

**N5. Deployment (executed).** In this cluster the only role that can log in is `tally`, a superuser, and a superuser can `SET ROLE tally_void`. "No caller can become it" therefore assumes the application connects as a non-superuser login role that is a member of `tally_app` and nothing else. Record that in R1 or AC-42. PG 16's CREATEROLE rules keep a CREATEROLE role out, and none exists.

**N6. Stale references in the tests.** The battery header names `txn-20.sh`, but the T cases are in `races/seal-20.sh`. Its section list says S1–S12, but S13 exists.

**N7. The residuals R1–R9.** None blocks. R6's "asserted" is weaker than stated (S3). The same `current_user <> 'tally_app'` stand-aside also exists in `enforce_meter_deployment_history`. Neither seal role has privileges there, but R6 names only `users`.

**N8. Inventory coverage (Q1).**
- R1, R2, R5, S1–S7, V1, V2, O1, O2 and O4 are implemented as written.
- V3's explicit tenant comparison was dropped as the brief describes. Row-level security alone gives a NULL-safe refusal (V5b, T3).
- Half-done: R3 (S6), R4 and O5 (S2–S5), V4 (B1, B2, S1) and O3 (S7).
