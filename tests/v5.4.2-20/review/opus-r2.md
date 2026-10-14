# v5.4.2-20 r2 review: Opus

**Date:** 2026-10-14. **Reviewer:** Opus. **Scratch DB:** `rv20opus` (dropped at the end).

**Hashes (executed):** the brief `663564e6…` matches its `.md5`. Patch `382fa4d3…`, battery `a0b6ec64…` and race script `dc36ebd2…` match the brief. The live copies are identical to the frozen ones.

**Reproduced (executed):**
- Strict apply, twice: the first run applies, the second is skipped by its marker.
- `battery-20`: 79 PASS, ends "complete".
- `seal-20.sh` on my clone: RC1–RC6, RC3b and T1–T7 all PASS.
- Not run: `ci.sh` and `mutations-20.py`.

## Verdict: ready

Both round-1 blocking items are closed. No r2 change opened a path I could find. The two should-fix items below are gaps in the invariant. Neither is a path around a seal today.

---

## 1. Round-1 blocking items

**B1 (cross-tenant attach to a void bill): closed (executed).**
- My round-1 repro: tenant 2's held bill is voided by tenant 2's platform admin and committed. A tenant-1 operator then bills a tenant-1 charge onto it.
- r2 refuses it: "names no invoice of this row's tenant visible to the caller".
- The same write by tenant 2's platform admin, who can see both bills, is refused by the tenant comparison.

**B2 (a void at REPEATABLE READ misses an attach): closed (executed).**
- My round-1 race: the void at REPEATABLE READ, the attach at READ COMMITTED committing in between.
- r2: the void raises "void_invoice() runs at READ COMMITTED" before it locks anything. The bill stays held, and the attached charge sits on a live bill.
- RC3b covers the reverse: the attach at REPEATABLE READ fails to serialise.

**Round-1 S1 (the deadlock): restated correctly (executed).** My repro still deadlocks: the attach is aborted and the void completes with the charge reverted. RC6 passes, and the header now says this.

## 2. Did an r2 change open something?

**The CHECK on `adhoc_charges` (executed and reasoned).**
- The constraint is validated, and `status` is NOT NULL, so the CHECK cannot pass through a NULL status.
- Every path that writes a charge's status:
  - Billing sets the pointer from NULL, so the attach guard fires.
  - A rebill from `void_pending_rebill` also sets the pointer from NULL.
  - The void clears the pointer together with leaving `billed`. I ran every reason-code branch end to end, committed: `wrong_rate`, `wrong_customer`, `duplicate`, `other` with notes, `system_error` on a held bill, a bill with no reads or charges, and another tenant's platform admin.
  - `fk_adhoc_invoice ON DELETE SET NULL` would now hit the CHECK, which fails closed. The invoice guard already refuses deleting a draft that has charges attached.
- The Codex B1 vector is refused: a pending charge carrying a pointer violates the CHECK (V4g).

**READ COMMITTED against a caller's savepoints (executed).**
- `SET TRANSACTION ISOLATION LEVEL` inside a savepoint raises "must not be called in a subtransaction".
- After the first query it raises "must be called before any query".
- A savepoint keeps the outer level.
- Before the first query, `SET LOCAL transaction_isolation = 'read committed'` in a REPEATABLE READ block does change the level. That is a real READ COMMITTED transaction, so the check is honest.

**The trigger-shape strings (executed).** `assert_seal_role_invariants()` passes with the session's `search_path = pg_catalog`. The function pins `public, pg_temp`, so `pg_get_triggerdef` renders function names the same way whatever the caller's path. On PG 16 the table name is always qualified. Each string also names its table, so the unanchored match cannot pass on another table's trigger.

**The temp-schema exclusion (executed).** `CREATE SCHEMA pg_temp_999` is refused ("unacceptable schema name"), so no permanent schema can match `pg\_temp\_%`. The exclusion covers only functions: a temp table granted to a seal role would still show up.

**The narrower void grants (executed).** Every committed void above succeeded with the r2 column-level grants, including I1, whose reversal names a posted charge row (`reverses_ledger_entry_id` set).

**The invariant now catches each of my round-1 cases (executed, each in a rolled-back transaction):**
- a column-level INSERT on the receipts for `tally_app`;
- a column-level UPDATE on `users.email` for `tally_seal`;
- a header guard set back to origin-only (`ENABLE TRIGGER`);
- a disabled charge guard.

## 3. "Not taken"

- **The version guard also checking the OLD entity (Fable S5):** not a mistake. But the reason given, "the bitemporal guard freezes the entity column", relies on a trigger that the invariant does not hold (S2 below).
- **Composite tenant foreign keys:** fine to leave to Ryan. F1 closes the attach case.
- **A check-first writable CTE case:** fine, since AC-42 says to use separate statements.

## Blocking

None.

## Should fix

**S1. The F3 CHECK is not in the invariant (executed).** In a rolled-back transaction, `ALTER TABLE adhoc_charges DROP CONSTRAINT adhoc_charges_billed_names_its_bill` leaves `assert_seal_role_invariants()` passing. With the CHECK gone, the Codex B1 path (pointer on a pending charge, void the bill, mark the charge billed) reopens and nothing reports it. Assert that the constraint exists, is validated, and has exactly this definition: `pg_get_constraintdef = 'CHECK (((status = ''billed''::text) = (billed_on_invoice_id IS NOT NULL)))'`, or whatever PG 16 renders.

**S2. The bitemporal guard on the three version tables is not in the trigger list (executed).** With `a_enforce_bitemporal_assertion` disabled on `wna_zone_versions`, the invariant passes. The receipt guard checks only the NEW row's entity, and the patch's own comment says that is safe *because* the bitemporal guard freezes the entity column. Add those three triggers to `c_triggers`. They are already `ALWAYS`.

## Notes

**N1. PUBLIC grants are outside the allowlist (executed).** `seal_role_privileges()` lists direct grants only, as its comment says. `GRANT SELECT ON users TO PUBLIC` passes the invariant. No table in `public` has a PUBLIC grant today, so nothing is reachable this way now. To make R6 independent of PUBLIC, also refuse any table privilege granted to PUBLIC on the tables that matter, or at least on `users`.

**N2. The trigger check does not reject extra triggers (executed).** An added BEFORE trigger that sorts before `a0_` passes the invariant. Only an owner or superuser can add one, which is outside the stated boundary ("an administrator … is outside it"). Recorded so that nobody reads the 17-trigger check as "these and only these".

**N3. Residuals.** Nothing in R1–R9 blocks. The deployment precondition from my round 1 (N5) still holds: in this cluster the only role that can log in is the superuser `tally`, which can `SET ROLE tally_void`. AC-42 or R1 should say the application connects as a non-superuser login role that is a member of `tally_app` only.
