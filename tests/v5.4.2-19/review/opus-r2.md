# v5.4.2-19 r2 — Opus review

**Artefacts checked.** All four match the brief: patch `7e7416ab…` (1,409 lines), battery `8fab4853…`, race `91f28175…`, ci.sh `a5e640c0…`.

**Verdict: ready.** No blocking items. Every blocking item from the three r1 reviews is closed. I reproduced each one or confirmed it with a battery case that fails without its guard. The should-fix items below are documentation that went stale between r1 and r2, two overclaims, and one unfrozen column. None of them lets a one-statement write get past a guard the patch claims to have.

## What I ran
- **Clone and apply.** Clone `opus19` from `tally`, TEMP revoked, strict apply (`search_path=''`, `check_function_bodies=on`, ON_ERROR_STOP). It applies cleanly; the only notices are the expected `DROP TRIGGER IF EXISTS` ones. A second run takes the `\if` gate ("already applied") and exits 0.
- **Battery.** battery-19 r2 runs to "battery-19: complete" (every `refuses()` matched its SQLSTATE).
- **Races.** `cycle-19.sh` on a throwaway clone (`opus19r`): C1–C7 all PASS, exit 0.
- **void_invoice() for real.** The battery only simulates void_invoice()'s write (R6). I called the function itself as `tally_app` on an issued invoice whose locked read it held. Result: the read went to `void_released`, `locked_by_invoice_id` NULL, `voided_from_invoice_id` = the invoice, run unchanged, `app.void_operation` back to `false`. `credit_balance` was 5.00, equal to the ledger sum (75 charged − 70 reversed).
- **Probes.** Two probe files reusing the battery fixtures (battery lines 26–69) and a `pg_temp.try()` helper that reports ACCEPTED/REFUSED. All run as `tally_app` and rolled back. Results are quoted below.
- **Not re-run:** the full CI suite (the freeze state says 25/25). Databases `opus19` and `opus19r` were dropped.

## 1. Round-1 closure

| r1 item | Status | Evidence |
|---|---|---|
| Opus B1 / Codex B1: read born locked | **closed** | `enforce_reading_born_unconsumed` (patch 412–435): BEFORE INSERT, ENABLE ALWAYS. Battery RB1–RB4. Without it, RB2–RB4 would be accepted and RB1 would fail with 23503 (the meter FK), not 23514, so each case is tied to the guard. |
| Opus B2 / Fable S1: void-released pointers writable | **closed** | Block 3 is now keyed on `OLD.billing_period_locked` (patch 380–396). RV1–RV6 refuse. My probe RL1: a re-lock that clears `voided_from_invoice_id` is refused. |
| Opus B3 / Fable B1 / Codex B3: a duplicate posting labelled as a refund or replacement | **closed** | `payments_refund_is_refund_check` plus an index keyed on `amount > 0` (patch 585–590). P7 (23514) and P7b (23505) each pin a different guard. My probe PR5/PR6: a negative row on the same transaction, flipped positive while pending, is refused by the index on UPDATE. |
| Opus B4: AI citation to another tenant, citation clearable | **closed** | Composite FKs (patch 791–797) and `enforce_ai_provenance_write_once` (801–825). L6/L6b/L7/L7b/L7c. My probe AI2: a non-AI order citing T2's audit row is refused by the composite FK too. |
| Opus B5 / Fable B2: import slot freed by editing | **closed** | `enforce_import_job_record` (974–1008); index on `(tenant, hash)` for commits only (968–970). J6–J9 and J2c. |
| Codex B2: `days_in_period` | **closed** | Block 2 is now a whitelist (355–369). RW1–RW5. |
| Codex B4: inactive-predecessor reactivation race | **closed** | Unconditional predecessor write (717–718). C5 (REPEATABLE READ gets 40001) and C6 (READ COMMITTED gets 23514) pass. C5 reactivates an already-inactive method, which is exactly the case r1's conditional write let through. |
| Codex B5 / Opus S1 / Fable S4: ledger `created_at` caller-written | **closed** | `a_stamp_created_at` on account_ledger (829–832). L8. |
| Opus S3 / Fable S2: lock flag set on an unconsumed read | **closed** | Patch 340–344. RF1 and RB4. |
| Opus S4/S5: preview blocking; one file under two types | **closed** | Previews are left out of the index; J3 positive, J2c negative. Hash case remains as R13. |
| Opus S6 / Fable N4 / Codex S3: lock order | **closed** (stated) | Patch 494–496 and R12. |
| Opus S7: path-enumerating walk | **closed** | A set walk (509–519). Q5: a 40-layer diamond is checked fast. |
| Fable S3: draft URL and hash drift apart | **closed** | Patch 930–938. I4, I3 positive, I5/I6 for issued. |
| Fable S6: superseded method made default | **closed** | Patch 697–702. M9. |
| Fable S7 / Codex S4: anomaly subject and detection | **closed** | Patch 857–862. N4, N4b. |
| Codex S1: CI skips the race after a clone failure | **closed** | `cstep` (ci.sh 56–61, 114). |
| Opus Q3d `WHEN OTHERS` / Codex S2: weak tests | **closed** | Q3d is pinned to 23001. Q4c no longer has the shortcut edge. Q4h covers the reversed lone edge. The race script now checks `pg_blocking_pids(B) ∋ A`. |
| **Opus r1 S8: a superseded method stays usable** | **not closed** (should-fix S3 below) | Probe PM2: a payment with `payment_method_id` = the superseded method was ACCEPTED. The comment at patch 723 still says "so a draft can no longer use the replaced account". |

## 2. New code

**Born unconsumed (412–435).** Every lock-record field is covered. `billing_period_locked` is NOT NULL (default false), so the OR leg cannot pass on a NULL. The superuser exemption keys on `current_user`. The only SECURITY DEFINER writer of `meter_readings` is `void_invoice()`, which never INSERTs, so nothing can launder a born-locked read through a definer. An `INSERT … ON CONFLICT DO UPDATE` goes through the UPDATE matrix, which refuses `pending → locked`.

**Block 2 whitelist.** I compared it against all 99 `meter_readings` columns. Every whitelisted name exists; there is no `updated_at` column to trip it. Two other BEFORE UPDATE triggers run on the table:
- `dry_run_no_read_locks` only raises.
- `z_enforce_read_exception_gate` runs after the workflow trigger. On UPDATE it only resets `validated_at := OLD.validated_at`. On the re-lock `v_first` is false, so it changes nothing on a consumed read.

Things that are no longer refused and must stay allowed, all verified working:
- `void_invoice()` itself (the real call above).
- The correction re-lock `void_released → released_to_billing → locked`, under a new run and bill, with `voided_from` kept (R8).
- The follow-up workflow fields (RW6, my W1).

Newly refused on a consumed read and arguably follow-up work:
- `confirmed_by_field_reader_at` / `_id` (probe W2 refused). A field re-read that confirms a disputed bill is plausibly done after billing. Note N1.
- `quality_flag` (W3 refused).

Both are domain calls, not defects.

**Block 3.** The void branch requires `voided_from := OLD.locked_by_invoice_id` and a cleared bill pointer, with run and lock time unchanged. The re-lock branch admits a new run, a stamped time, and a bill only where there was none. `voided_from` is frozen everywhere else. Each holds under probe.

**Payments CHECK and index predicate.** Checked against tu.sql: no function inserts payments with `refunds_payment_id`, so the new CHECK breaks no writer. The index holds on UPDATE as well as INSERT (PR6). The claim is now limited to receipts, and that holds. What it does not cover is in should-fix S4 and note N3.

**AI composite FKs and write-once.** The old FKs were plain NO ACTION, so the composite ones change no delete behaviour. Under MATCH SIMPLE, a NULL citation passes, and the CHECKs decide when a citation is required. The write-once trigger compares only the two columns, so `void_invoice()`'s adhoc_charges UPDATE is unaffected. Probe AI1: `source` can go `ai_suggestion → manual` while the citation stays. Harmless, because the provenance survives in `created_by_ai`/`ai_audit_id`. Note N4.

**Import job record trigger.** It fires first (`a_`). `trg_populate_import_job_idempotency_key` is INSERT-only, so nothing rewrites a frozen column after the check. See should-fix S2 for `source_file_url`.

**Unconditional supersession write.** Verified by C5/C6/C7. The AFTER write re-enters the BEFORE trigger and changes only the allowed fields.

## 3. Section 8 (running balance)

**Is void_invoice() otherwise identical?** Yes. `pg_get_functiondef` before (`tally`) and after (`opus19`) differs only at body lines 269–271: `SELECT running_balance … WHERE id = v_ledger_entry_id` becomes a `coalesce(sum(amount),0)` filtered on tenant AND customer. The rest is unchanged:

| Property | Before and after |
|---|---|
| SECURITY DEFINER | yes |
| `search_path` | `public, pg_temp` |
| Owner | `tally` |
| ACL | `{tally=X/tally,tally_app=X/tally}` |
| Volatility | volatile |
| Function comment | unchanged; it never mentioned the balance |

The tenant filter is right: a definer sees every tenant. The returned key is still `credit_balance`, with the same sign. The function now returns the true sum rather than an order-dependent value.

**Does anything else still reference `running_balance`?**
- After the patch, no `pg_proc` body names the column. The only match on `running_bal` is void_invoice's local variable `v_new_running_bal`.
- The column drop succeeded without CASCADE, so no view or materialized view depended on it. Column-level grants go with the column.
- **Stale:** the `account_ledger` table COMMENT (tu.sql:13726) still says "running_balance is computed on INSERT by compute_ledger_running_balance()". Should-fix S1.
- Outside the database: `ui-concepts/schemas/models.ts` and `application/database/schema.sql` still list the column. Those are reference artefacts, not live. Note N6.

**Is the dropped trigger's function used anywhere else?** No. `compute_ledger_running_balance` appears in no other body, and `DROP FUNCTION` without CASCADE succeeded.

## 4. Tests
- **Does each new case fail without its guard?** Every r2 case is tied to its guard by SQLSTATE (reasoning in the closure table). Two pairs are discriminating in a useful way:
  - P7 (23514, the CHECK) and P7b (23505, the index) each fail if the other guard were the only one.
  - L7c expects 23001. Without the write-once trigger it would fail on the CHECK with 23514.
- **Is anything true by accident?** Nothing I found:
  - R1, L1 and L8 compare to `now()` as `tally_app`, so they exercise the stamp, not a superuser path.
  - B1's `now() - 1s → 0` case depends on L8's stamped row, which is intended.
  - B4's `strpos(prosrc,'running_balance')` does not match `v_new_running_bal` (correct), but it would also miss a reader spelled differently. Acceptable.
- **Does the race script prove B was blocked by A?** Yes. `waiting()` polls `pg_blocking_pids(b.pid)` for A's pid while A holds, and `check()` fails if the wait was never seen. C5 is the right shape for Codex B4: B's REPEATABLE READ snapshot is taken at its UPDATE, after A's INSERT and before A's commit.
- **Gaps (low):** no battery case for a foreign *schedule* (probe Q: refused 23503); no case for a void on a read whose bill pointer is NULL (probe RL4: refused).

## Blocking
None.

## Should-fix
1. **The header and a table comment contradict r2.**
   - Patch 74–76 still says CI-055 is "for original payments (a refund or an NSF row that cites its original is not counted)". r2 counts every positive payment and NSF replacements.
   - Patch 105–108 still says "one live job per tenant, file hash, import type and preview/commit". r2's key is (tenant, hash), commits only.
   - The `account_ledger` table comment (tu.sql:13726, not touched by the patch) still describes the dropped column and trigger.

   These reach tu.sql with the mirror, and R9's contracts are written from them. Fix the text, and add `COMMENT ON TABLE public.account_ledger` to section 8.
2. **A finished import's stored file can be repointed** (patch 981–990). `source_file_url` and `source_file_size_bytes` are not in the frozen set. Probe IJ1: on a `complete` job, `UPDATE … SET source_file_url = 's3://f/other.csv'` was ACCEPTED. The header (line 20) says "file identity write-once", and the URL is where the evidence for that hash lives. Add both columns. The row counts (`committed_rows` etc., probe IJ2 ACCEPTED) on a finished job are a lesser case of the same thing.
3. **The supersession comment overclaims** (patch 723), carried over from r1 S8. Probe PM2: a new payment drawn on the superseded method was ACCEPTED. Either soften the comment ("the core must not draw on an inactive method") or refuse an inactive `payment_method_id` on payment insert.
4. **Refund deliveries have no idempotency** (patch 585–592). Probe PR2: the same refund (−20, same `provider_transaction_id` `RF-9`, same original) inserted twice was ACCEPTED, so money goes out twice. The index comment's "a webhook or file delivered twice cannot post twice" holds for receipts only. Refunds cannot simply share the key, because partial refunds of one transaction are legitimate. Add a residual saying so (with what a refund's own identity would be), or narrow the comment to "receipt". Related: probe PR3, a −500 refund citing another customer's +20 payment, was accepted. The lineage pointer is not tied to customer or amount; that is pre-existing and goes with R11's FK question.

## Notes
- N1. Whitelist breadth (above): `confirmed_by_field_reader_*` and `quality_flag` are frozen after consumption. Say whether a post-billing field confirmation is follow-up work.
- N2. A re-lock (or a first lock) may leave `locked_by_invoice_id` NULL. Block 1 requires only the run, and that is pre-existing (tu.sql:349 already froze the pointer on a locked read). Probe RL2/RL3/RL4: such a read can never get its bill attached, and void_invoice() can never release it. It is stranded locked. Either require the bill on the move to locked, or write the contract "a run sets the bill pointer in the same write as the lock" into R9.
- N3. CI-055 is keyed on `source_system`, which is the capture channel. One processor transaction arriving by webhook and again in an imported settlement file (`imported`/`bank_lockbox`) posts twice (probe PR4 ACCEPTED; by design per P6b). Worth a line in the residuals.
- N4. `adhoc_charges.source` stays editable after creation (probe AI1). Several AI rows may cite one audit row (probe AI3). Both fine as representation; mention them in R9.
- N5. `status` is whitelisted on a consumed read. `populate_reading_calculations` picks the "previous" read with `status = 'active'`, so marking a locked read `disputed`/`voided` changes the next read's DB-filled `previous_value`/`days_in_period`. The core computes usage, but the auto-fill now depends on an app-editable field of a consumed read. Probe W4: `replaced_by_reading_id` may point at the read itself.
- N6. Off-database references to `running_balance`: `ui-concepts/schemas/models.ts`, `application/database/schema.sql`, and older session docs. Not live.
- N7. Still open from r1 and outside this patch: the superuser exemptions key on `current_user` (definers owned by `tally` count as superuser); `trg_enforce_reading_validation_workflow` is ENABLE ORIGIN; R14 (the GUC).
- N8. A void after a re-lock overwrites `voided_from_invoice_id` with the second bill (only one generation of void history on the row). The invoice_events log keeps both voids.
