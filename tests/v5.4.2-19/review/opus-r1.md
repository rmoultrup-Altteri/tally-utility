# v5.4.2-19 r1 — Opus review

**Artefacts checked.** patch md5 `63157e6e3343e62d4e547c31e6c02e14` (897 lines), battery `f4f321db406e717074fc54a05e596371`, race `3ab9a3e34e1f8a15a5548d8fd6b9ccbf`. All three match the brief.

**Verdict: not yet.** Five blocking items. Each one is a guard that a one-statement write as `tally_app` gets around, and each contradicts something the patch header says it does. All five are small fixes on empty tables.

## What I ran
- Clone `opus19` from `tally`, TEMP revoked, strict apply (`search_path=''`, `check_function_bodies=on`, ON_ERROR_STOP). It applies cleanly. A second run takes the `\if` gate ("already applied") and returns 0.
- battery-19: all checks PASS, ending "battery-19: complete".
- Batteries 09, 10, 11 (as amended), 12, 13, 14 and 16 on a patched clone (`opus19c`): all OK. Nothing that depends on the two rewritten functions, the anomaly unique key or the dunning FK broke.
- `cycle-19.sh` on a throwaway clone (`opus19r`): C1–C4 PASS.
- Probes: the battery's fixture block (lines 23–67) plus a `pg_temp.try()` helper that reports ACCEPTED/REFUSED, run as `tally_app` with `app.user_id` set, rolled back. Each probe is quoted below with its result.

## Blocking

### B1. A read can be inserted already locked: no run, and the caller's lock time is kept (patch 289–302; trigger is BEFORE UPDATE only)
Header line 29: "locked_at is stamped by the database on every move to locked." Block 1 runs only on UPDATE, and nothing checks INSERT.
```
-- tally_app
INSERT INTO meter_readings (..., is_estimated, validation_status, billing_period_locked, locked_at)
VALUES (..., true, 'locked', true, '2020-01-01Z');          -> ACCEPTED
-> validation_status=locked, locked_at=2020-01-01, locked_by_billing_run_id=NULL
INSERT ... validation_status='void_released', billing_period_locked=true,
           voided_from_invoice_id=<any invoice>               -> ACCEPTED
```
(An actual, non-estimated read born locked happens to fail today on `meters_last_validated_actual_reading_id_fkey` with constraints immediate. That is an accident of the CI-113 counter, not a guard.)
This bypasses the two Block 1 requirements (`billing_period_locked`, `locked_by_billing_run_id`) and the new locked_at stamp. The battery's R1 covers only the UPDATE path.
**Fix:** a BEFORE INSERT leg. For a non-superuser, refuse a read whose `validation_status` is `locked` or `void_released`, or whose `billing_period_locked`, `locked_*` or `voided_from_invoice_id` is set. Reads are born `pending_review` (or another pre-lock state) and reach the lock only through Block 1.

### B2. A void-released read's lock pointers are freely writable (patch 343–353: Block 3 is gated on `OLD.validation_status = 'locked'`)
Header lines 25–26 and the Block 2 comment (308–310) say a void-released read "is the evidence the correction run rebills from, and is frozen like a locked one". The values are frozen, but the pointers that say which bill was voided and which run consumed the read are not:
```
-- after void_invoice()'s exact write (R6), app.void_operation back to 'false'
UPDATE ... SET voided_from_invoice_id = '<I2>'                 -> ACCEPTED
UPDATE ... SET voided_from_invoice_id = NULL                   -> ACCEPTED
UPDATE ... SET locked_by_billing_run_id = '<R2>', locked_at = '2020-01-01Z' -> ACCEPTED
UPDATE ... SET locked_by_invoice_id = '<I1>'                   -> ACCEPTED
-> void_released | voided_from NULL | locked_by_invoice I1 | run R2 | 2020-01-01
```
CI-031 (parity row 144) names exactly these fields as the lock metadata, and calls the `void_released` hole the defect. The void-tracking evidence can be erased, and a released read can point at a live bill while its status says released.
**Fix:** while `OLD.validation_status = 'void_released'`, freeze `voided_from_invoice_id`, `locked_by_invoice_id` and `locked_at`. Let `locked_by_billing_run_id`, `locked_by_invoice_id` and `locked_at` change only on the re-lock (`released_to_billing -> locked`, which already goes through Block 1). Keep `voided_from_invoice_id` frozen across the re-lock as well, or say on purpose that it is cleared. Add battery cases for each pointer on a void_released read.

### B3. A second posting of one processor transaction gets past CI-055 by citing any payment (patch 508–510)
The brief asks whether a duplicate posting can slip through as a "refund". It can. Nothing ties `refunds_payment_id` or `nsf_original_payment_id` to a refund or NSF row, or to the same transaction, customer or sign:
```
-- TXN-1 already posted (+20 ach, paymentus_webhook)
INSERT ... amount 20, 'ach', status default posted, provider_transaction_id 'TXN-1',
           refunds_payment_id = <an unrelated cash payment of another customer>      -> ACCEPTED
INSERT ... same, nsf_original_payment_id = <unrelated payment>                         -> ACCEPTED
```
**Fix (pick one):** limit the index exclusion to real refund and NSF rows, e.g. `CHECK (refunds_payment_id IS NULL OR (payment_method = 'refund' AND amount < 0))` and the matching shape for NSF rows (sign or status). Or have a trigger require that the cited original carry the same `(tenant_id, source_system, provider_transaction_id)`. Add a negative case to P6.

### B4. An AI order or charge can cite another tenant's audit row, or any unrelated one (patch 698–702) — standing rule 7
```
-- owner: ai_audit_log row in T2 (action 'query')
-- tally_app in T1:
INSERT INTO adhoc_charges (... source 'ai_suggestion', ai_audit_id = <T2 row>)        -> ACCEPTED
INSERT INTO service_orders (... created_by_ai true, ai_audit_id = <T2 row>)           -> ACCEPTED
UPDATE service_orders SET created_by_ai = false, ai_audit_id = NULL                    -> ACCEPTED
```
The FKs (`fk_adhoc_ai_audit`, `service_orders_ai_audit_id_fkey`) are single-column and bypass RLS. The new CHECK only asks for "not NULL". That is the "visible AND of this tenant" class that rule 7 says must be positive, and the citation does not have to be the action that created the row. On service orders the AI flag and the citation can also be removed afterwards.
**Fix:** composite FKs `(ai_audit_id, tenant_id) -> ai_audit_log (id, tenant_id)`, which needs a UNIQUE (id, tenant_id) on ai_audit_log. Optionally limit the cited `action_type` to `mutation_executed` or `suggestion_approved`. Freeze `created_by_ai` and `ai_audit_id` once set.

### B5. The file-import guard is cancelled by one UPDATE (patch 814–816)
The header claims "a renamed copy of a file already imported is refused". `import_jobs` has no status machine and no write-once columns, and `tally_app` holds UPDATE:
```
UPDATE import_jobs SET status='complete' WHERE id=J;    -- committed import
UPDATE import_jobs SET status='cancelled' WHERE id=J;   -> ACCEPTED
INSERT same tenant/hash/type, new name                  -> ACCEPTED   (re-import)
UPDATE import_jobs SET source_file_hash='zzz' WHERE <live job>   -> ACCEPTED (frees the slot)
```
**Fix:** a BEFORE UPDATE guard. Make `source_file_hash`, `source_filename`, `import_type`, `is_dry_run` and `tenant_id` write-once. Make `complete` and `partial` terminal (never to `failed` or `cancelled`), and refuse a failed or cancelled job being revived to a live status.

## Should-fix
1. **Ledger `created_at` is caller-written, and `account_balance_as_of` reads it as "recorded at"** (patch 879–883; standing rule 4). `tally_app` inserted an `account_ledger` row with `created_at = 2020-01-01`. It was kept, and `account_balance_as_of(c, 2026-12-31, 2021-01-01)` returned -10.00. The "recorded by" coordinate is only as good as a value the app picks. Stamp `account_ledger.created_at` with the patch's own `stamp_log_created_at()` (superuser kept), or note it as a residual next to R2.
2. **`days_in_period` is not frozen on a consumed read** (patch 313–336). `UPDATE ... SET days_in_period = 99` on a locked read was ACCEPTED. It is a proration input, and Block 2 freezes `previous_reading_date` but not the day count derived from it. Also editable and arguably billing-relevant: `estimation_reason` (the disclosure partner of `is_estimated`), `raw_read_value` and `register_label`. The HINT (line 359) lists the "editable" set as notes, tamper, dispute, status and followup, but the real editable set is far wider. Either freeze every column outside an explicit allowed list (a true whitelist), or make the HINT say what is really open.
3. **`billing_period_locked` can be set on a read no run consumed** (patch 313/335). On a `pending_review` read, `UPDATE ... SET billing_period_locked = true` was ACCEPTED. After that, value edits are REFUSED for good, with a message saying the read "was consumed by a billing run" (false). Let the flag turn true only on the move to `locked`.
4. **A completed preview blocks every later preview of the same file** (patch 815). A second dry run of `h-r` after the first completed was REFUSED by `import_jobs_file_once`, even with a fresh idempotency key. Re-previewing after a mapping fix is normal, and today the only way through is the B5 hole. Count completed previews out of the index (e.g. `WHERE NOT (is_dry_run AND status IN ('complete','partial'))`).
5. **One file can be committed under two import types.** The same hash under `payments` and `lockbox` was ACCEPTED (Y6e). For payment files that is a double-post path, which is CI-118's whole point. Consider leaving `import_type` out of the key for payment-bearing types (`payments`, `lockbox`, `ach_return`). Hashes also have no format: `H-FEB` and `h-feb` are separate keys. Require lowercase hex SHA-256, as `invoices.pdf_sha256` does.
6. **Lock order for the rider mutex is not stated** (patch 426–432; standing rule 5). Two transactions writing dependencies on schedules S1 then S2, and S2 then S1, deadlock. Add one line to the header (one schedule per transaction, or ascending schedule id).
7. **The cycle search enumerates paths, not nodes** (patch 436–446). `UNION` over `(item_id, path)` grows with the number of distinct paths. On a 17-layer, 2-wide diamond ladder (68 edges), one acyclic insert took 434 ms, and each extra layer doubles that. `reach(item_id)` with plain `UNION` terminates on its own (it deduplicates) and is linear. The `path` array is not needed.
8. **Payment-method supersession does not stop use of the old account** (comment at line 640 says "a draft can no longer use the replaced account"). A new payment with `payment_method_id = <superseded method>` was ACCEPTED (Y9). Either refuse an inactive method on payment insert, or soften the comment so it says the core enforces this.
9. **Battery gaps:**
   - No INSERT-path case for reads (B1).
   - No void_released pointer cases (B2).
   - No P6 negative for a non-refund citing a payment (B3).
   - No cross-tenant AI citation case (B4).
   - No status-flip or hash-rewrite case for imports (B5).
   - Q3d (battery 168–176) accepts any exception (`WHEN OTHERS`). Pin it to the bitemporal guard's SQLSTATE, or it can pass on an unrelated error.
   - Q4e/Q4g test only a foreign item, never a foreign *schedule*.

## Notes
- **Void carve-out (brief §2).** With `app.void_operation='true'`, a caller can still release a read of a bill that is not being voided: battery R6 itself does this on the live I1. The read then re-locks under a second bill, so it is billed twice. This is AC-12's accepted "fence against accident", and the patch narrows the write to exactly void_invoice()'s shape (R4/R5 refuse anything more). A cheap later tightening: have void_invoice stamp the invoice void before step 3, so the trigger can require the held bill to be void.
- **Correction re-lock still works** (R8). `void_released -> released_to_billing -> locked` under a new run and bill passes. Block 2 holds the values throughout.
- **Removing the consumption fill** broke nothing in tu.sql. No function reads a DB-filled consumption, and batteries 09–16 pass.
- **`trg_enforce_reading_validation_workflow` is still ENABLE ORIGIN (`O`)**, not ALWAYS, unlike every trigger this patch adds. That is pre-existing, and `session_replication_role` is superuser-only, so it does not matter in practice. It is worth aligning.
- **Superuser exemptions key on `current_user`.** `void_invoice` is SECURITY DEFINER owned by `tally` (rolsuper), so inside it `v_super` is true. Harmless today (it never moves a read to locked or writes these logs). A future definer function that writes logs or locks reads would keep caller timestamps.
- **`ai_audit_log.session_id ... ON DELETE CASCADE`.** `tally_app` holds DELETE on `ai_sessions`. Deleting a session with audit rows is now refused by `append_only` (23001). That is safe, but the FK should say RESTRICT, as was done for dunning (patch 694–696).
- **Anomaly "subject" write-once** covers `entity_type` and `entity_id`. The denormalised `customer_id`, `meter_id` and `location_id` stay editable. `first_detected_at` is caller-supplied on insert (write-once afterwards, but not DB-stamped).
- **ACH-funded `auto_pay` going NSF** needs no return code (Y2 ACCEPTED). Only `payment_method='ach'` triggers the requirement. This could join R10.
- **Single-statement cycle cases hold.** A two-row INSERT forming a cycle, an insert inside a writable CTE, and one UPDATE turning A->B, B->C into A->C, C->A are all REFUSED (23514).
- **The race script proves what it claims.** B is seen in `pg_stat_activity` with wait_event_type Lock before A commits. Without the header bump, C1/C2 would not wait and would fail the WAITED check. C3's wait may be on the unique index rather than the FOR UPDATE, which is still a lock wait.
- **Checked and fine:**
  - The header bump goes through `enforce_reference_header` (version unchanged) and `enforce_rate_schedule_lifecycle` (no status change) for every status.
  - `d.id <> NEW.id` is correct on UPDATE.
  - The tenant test is positive (visible AND same tenant), and Q4g covers the owner.
  - All NOT NULL legs of the new CHECKs were verified.
  - The deadband CHECKs are complete (all-or-none, sign, vocabularies).
  - The payment status paths (pending -> posted/voided/nsf, posted -> nsf/reversed/refunded/voided) agree with the effective-date and return-code CHECKs.
  - The supersede chain cannot cycle (the pointer is frozen on UPDATE and inserts point only at existing rows). Cross-tenant is blocked by the composite FK, and cross-customer by the trigger.
  - The AFTER trigger's UPDATE re-enters the BEFORE trigger cleanly.
  - Reactivation racing a supersede resolves correctly under READ COMMITTED (EvalPlanQual plus a fresh statement snapshot).
  - TRUNCATE on the three logs is covered by the existing `no_truncate` triggers.

Databases `opus19`, `opus19r` and `opus19c` were dropped after the run.
