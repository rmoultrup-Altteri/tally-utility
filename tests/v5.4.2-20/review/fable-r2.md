# v5.4.2-20 r2 review — Fable

**Brief:** `review-brief-20-r2.md`, md5 `663564e665f12b7be640db0c0903a56d` (checked). Frozen files checked: patch `382fa4d3…`, battery `a0b6ec64…`, seal-20.sh `dc36ebd2…`, all match. Read `review-findings-20-r1.md` and the r1↔r2 diffs of all three files.
**Date:** 2026-10-14. **Clone:** `rv20fable` rebuilt (TEMPLATE tally, TEMP revoked from PUBLIC/tally_app/tally_core, frozen r2 patch strict-applied with `search_path=''` + `check_function_bodies=on`; second apply skipped by the marker). Dropped at the end. Every claim is **executed** unless marked **predicted**.

**Reproduced:** strict apply twice (rc 0, 0); battery-20 r2: 79 PASS, `complete`, no FAIL; `seal-20-frozen-r2.sh rv20fable`: RC1–RC6, RC3b, RC5b, T1–T7 all PASS. Did not run mutations-20.py.

## Verdict: ready

Both of my round-1 items that mattered are closed by the patch itself, not by a test, and the r2 changes opened nothing I could find.

## Blocking

None.

## Should-fix

None that should hold the mirror. See N5 for one wording-level note on the allowlist.

## Notes

**N1. Round-1 B1 (REPEATABLE READ void strands an attach) is closed.** `void_invoice()` refuses with `25000`-class `invalid_transaction_state` and the stated message under REPEATABLE READ and under SERIALIZABLE, before taking any lock; also when the call is inside a savepoint of an RR transaction (T7 and my own runs). No savepoint trick around it: `SET TRANSACTION ISOLATION LEVEL` and `SET LOCAL transaction_isolation` both fail with "must be called before any query" once the transaction has run one, and "must not be called in a subtransaction" inside a savepoint; a downgrade to READ COMMITTED *before* the first query is real (current_setting reports it), so a caller who does that gets a genuine READ COMMITTED void. RC3b shows the attach side at RR fails to serialise (40001), fail-closed, as before.

**N2. Round-1 S3 (cross-tenant attach) is closed, both legs.** T1 billing its pending charge onto a T2 live bill it cannot see: `23001 … names no invoice of this row's tenant visible to the caller`; T1 locking a released read onto the same bill: same refusal from `meter_readings`; a platform administrator (who sees both) billing a T1 charge onto a T2 bill: refused by the tenant comparison; the same attach onto a live T1 bill: admitted (control). Battery V4e/V4f cover the first and third.

**N3. Round-1 S1 (invariant narrower than its claim) is closed, and now errs strict.** The seven r1 drifts are all within the new checks by construction (exact `pg_get_triggerdef` + `tgenabled = 'A'` for 17 triggers, exact grant allowlists, column-level receipts check); I verified all 17 guards are `A` on the clone and that the strict apply's tail (which runs the invariants under `search_path=''`) passes. The allowlist comparison catches an extra temp-*table* grant to tally_void (`extra table pg_temp_3.tt SELECT`), and passes again after revoke: the temp-schema exclusion is for functions only, which is what the batteries grant (`pg_temp.refuses_at`, `pg_temp.try`). That asymmetry is fine: only the superuser can create temp objects here (no seal role, tally_app or tally_core holds TEMP), so a temp grant is never a path, only a battery convenience.

**N4. Trigger-shape strings do not depend on the session's `search_path`.** Executed: `assert_seal_role_invariants()` passes with the session at `search_path = ''`, and with `search_path = pg_temp, public` plus a same-named `pg_temp.enforce_reference_version_receipt()` created to shadow the real one. Reason (predicted from the catalog code): `pg_get_triggerdef` always schema-qualifies the table and qualifies the function only when it is not visible on the *current* search_path, and the invariant function pins `public, pg_temp`, so the rendering is fixed by the function, not the caller. The strings in `c_triggers` are written for exactly that rendering (table qualified, function not).

**N5. The narrower void grants hold on every path.** As tally_app: `duplicate` (park: charge → `void_pending_rebill`, pointer cleared, `voided_from` set, run kept; read → `void_released`), `paid` + `other` with notes, `held` with read + charge, an empty bill, `p_voided_by` NULL, and a platform admin voiding another tenant's bill — all admitted. As tally_void directly: an identity edit, moving the run, editing a read's `locked_at`, editing `amount_due` — all `42501` (the grant fences them, which is why -19 R4/R5c and -20 V9c/V10 now expect 42501; the same acts by the application still meet the guards). A void disposition that keeps the pointer is still the guard's refusal (23001), so the exact-disposition clause that remains is the one the grant cannot express. Wording: the allowlist comment says "enumerated by end-to-end runs for every reason code"; the invoices CHECK admits only `wrong_read, wrong_rate, service_date_error, system_error, duplicate, other` plus whatever else `invoices_void_reason_code_check` lists (`customer_request` is not one, executed in r1), so "every reason code" is literally true of the CHECK's set — fine.

**N6. The CHECK `adhoc_charges_billed_names_its_bill` opens nothing.** Live data on `tally` has only `billed` with a pointer and `pending` without. The only function body that writes a charge's status or pointer is `void_invoice()` (catalog scan), whose two dispositions clear the pointer as they leave `billed`. Executed: `pending → waived` and `pending → void` admitted (no pointer); a pending charge given a pointer and a `billed` with no pointer both refused by the CHECK; a billing run's one-statement `billed + pointer` admitted onto a live bill. `fk_adhoc_invoice`'s `ON DELETE SET NULL` would now also violate the CHECK for a billed charge, which only strengthens the existing draft-delete refusal (predicted).

**N7. Deadlock (r1 S4) is now stated correctly and tested.** RC6 reproduces the child-first deadlock with one abort and no charge left on a void bill; the lock-order paragraph now says what a caller can meet and what to do. The mitigation I floated in r1 (lock the bill before the child) is indeed not available from a BEFORE UPDATE trigger; restating was the right call.

**N8. "Not taken."** Fable S5 (OLD entity on UPDATE): agreed, the bitemporal guard freezes the entity column and a second check could never fail on its own; the comment records it. Codex's composite FKs: Ryan's -19 R11; F1's tenant comparison closes the attach case. The check-first CTE: agreed, AC-42 makes it a non-protocol.

**N9. Small observations, no action needed.** (a) `c_triggers` pins the exact definitions of four pre-existing triggers (`enforce_invoice_immutable`, `enforce_adhoc_charge_immutable`, `trg_enforce_reading_validation_workflow`, `enforce_reference_header` ×3): any later patch that re-creates one must update the list — intended, and the message names the missing line. (b) The O4 check is lexical and says so. (c) The S13 forgery now uses `ALTER TABLE … DISABLE TRIGGER` inside the rolled-back battery, which takes ACCESS EXCLUSIVE on the receipts for the transaction — fine in a test, and it re-enables `ALWAYS`, so G8 at the end still passes.
