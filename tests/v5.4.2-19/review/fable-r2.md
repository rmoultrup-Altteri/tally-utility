# v5.4.2-19 r2 — Fable review

Reviewer: Fable 5.1. Date: 2026-10-13. Clones: `fable19` (patch + battery + probes), `fable19r` (race script), `fable19m` (one per mutation run); all dropped.

Hashes match the brief: patch `7e7416ab…` (1,409 lines), battery `8fab4853…`, race `91f28175…`, ci.sh `a5e640c0…`.

## What I ran

- Strict apply (`search_path=''`, `check_function_bodies=on`, ON_ERROR_STOP) on a clone of `tally`: clean, only the expected `DROP TRIGGER IF EXISTS` notices. Second run on the same clone: the `\if` gate fires ("already applied"), nothing executed.
- battery-19-frozen-r2: 146 PASS, "battery-19: complete".
- `cycle-19.sh` on `fable19r`: C1–C7 PASS, exit 0. Every leg's `waiting()` saw B's backend in `pg_blocking_pids` of A's, so no leg passed sequentially.
- **Mutation runs** (one guard removed on a fresh clone of the patched DB, battery re-run; "does each new case fail without its guard?"):

  | removed | battery result |
  |---|---|
  | `a_enforce_reading_born_unconsumed` | FAIL RB1 (refused with 23503 — the FK accident, not the guard) |
  | lock-flag rule (`:340` turned to `IF false`) | FAIL RF1 accepted |
  | `a_enforce_import_job_record` | FAIL J6 accepted |
  | `enforce_ai_provenance_write_once` on service_orders | FAIL L7 accepted |
  | `enforce_ai_provenance_write_once` on adhoc_charges | FAIL L7c — refused with 23514 instead of 23001 (see N6) |
  | `a_stamp_created_at` on account_ledger | FAIL L8 |
  | `payments_refund_is_refund_check` | FAIL P7 (refused 23505 instead of 23514) |
  | index predicate without `amount > 0` | battery aborts at :329 (P6b's refund is a duplicate) |
  | single-column AI FKs restored | FAIL L6 accepted |
  | `enforce_invoice_image_hash` | FAIL I2 accepted |
  | `a_enforce_anomaly_record` | FAIL N3b accepted |
  | conditional supersession write (r1 shape) | race: **FAIL C5** (B committed), FAIL C7 (1 of 2 inactive), C6 still PASS |

  Every new guard has at least one test that goes red without it. C5 is the test for Codex B4 and only C5 catches the r1 shape; C6 passes either way (READ COMMITTED re-reads), so C5 is load-bearing.
- Probes as `tally_app` (`SET LOCAL app.user_id`, `pg_temp.probe` reports ACCEPTED/REFUSED, rolled back): XR*, XP*, XA*, XJ*, XM*, X8 — quoted below where they matter.

## Verdict: **not yet** — one blocking item, a one-index fix (verified: battery still 146/146 with it).

## Blocking

**B1. CI-055: a refund (or any money-out row) delivered twice posts twice** — `patch-19-frozen-r2.sql:588-592`.
The r2 index keys the once-only rule on `amount > 0`. Its own comment (:592) says "a webhook or file delivered twice cannot post twice, whatever lineage it claims". A refund webhook is a webhook. As `tally_app`, after P-2 (`+20 ach, paymentus_webhook, TXN-1`):
```
INSERT … -20 'refund' TXN-1 refunds_payment_id=P-2          -> ACCEPTED (XP1a)
the identical row again                                      -> ACCEPTED (XP1b)
INSERT … -5 'refund' RFND-7 refunds_payment_id=P-2           -> ACCEPTED (XP1c)
the identical row again                                      -> ACCEPTED (XP1d)
-> 4 refund rows, sum -50, against a 20.00 receipt
INSERT … -20 'ach' TXN-9 (no lineage); again                 -> both ACCEPTED (XP2a/b)
```
r1 closed the positive side (P7/P7b/P8 prove it); the negative side is the same defect with the sign flipped, and it is money the utility pays out. Rule 3: the check is narrower than its claim. **Fix:** a second partial unique index, `(tenant_id, source_system, provider_transaction_id) WHERE provider_transaction_id IS NOT NULL AND amount < 0` (keeps P6b's design where a refund may share its original's id: one receipt and one refund per id, never two of either). Tried on a clone: battery 146/146, XP1b/XP1d/XP2b refused 23505. Add the negative case (the same refund twice) to P7, and say in the index comment what the zero-amount row does (XP3: `amount = 0` rows are never counted — fine if stated).

## Round-1 closure

| r1 item | status | where |
|---|---|---|
| Opus B1 / Codex B1 — read born locked | **closed** | `:412-435` BEFORE INSERT, superuser exempt; RB1–RB4; mutation M1 |
| Opus B2 / Fable S1 — void-released pointers writable | **closed** | Block 3 `:380-396`; RV1–RV6, R8 keeps voided_from; see N2 (a second void overwrites it, by the rule's own shape) |
| Opus B3 / Fable B1 / Codex B3 — duplicate via lineage label | **closed for money in**, reopened for money out as B1 | `:585-590`; P7/P7b/P8 |
| Opus B4 — AI citation cross-tenant, flag removable | **closed** | `:791-797` composite FKs (both tenant_id columns NOT NULL, so MATCH SIMPLE cannot leak), `:801-825` write-once; L6/L6b/L7/L7b/L7c; mutations M3/M6 |
| Opus B5 / Fable B2 / Codex S4 — import key mutable | **closed** | `:974-1008`; J6–J9; mutation M2. `tally_app` has no DELETE (XJ4, 42501) |
| Codex B2 / Fable S5 / Opus S2 — days_in_period, raw value, HINT wider than truth | **closed** | whitelist `:355-369`; RW1–RW5; HINT `:402` now lists exactly the open set |
| Codex B4 — supersession of an inactive predecessor | **closed** | `:717-718` unconditional; C5–C7; mutation M7 shows C5 fails on the r1 shape |
| Codex B5 / Opus S1 / Fable S4 — ledger created_at app-written | **closed** | `:829-832`; L8; mutation M4; X8 shows void_invoice's own reversal row stamped `now()` |
| Fable S2 / Opus S3 — flag set on an unconsumed read | **closed** | `:340-344`; RF1; mutation M10 |
| Fable S3 / Codex S4 — hash write-once while draft URL free | **closed** | `:932-938`; I2/I4/I3 draft, I5/I6 issued; mutation M8 |
| Fable S6 / Opus — superseded method made default | **closed** (M9); siblings not taken: a successor born inactive and a `method_type` change on supersede are accepted (XM3) — acceptable under "a change to the account identity is a new row"; say so in the column comment |
| Fable S7 / Codex S4 — anomaly subject | **closed** | `:857-862`; N4/N4b; mutation M9 |
| Opus S4 — a finished preview blocks later previews | **closed** | `:970` previews excluded; J3 |
| Opus S5 — one file under two import types | **closed** | import_type out of the key; J2c. Hash format: not done, recorded as R13 (XJ3 `H-FEB` vs `h-feb` are two files) |
| Opus S6 / Fable N4 / Codex S3 — lock order | **closed** | `:494-496` comment + R12 |
| Opus S7 — paths vs nodes | **closed** | `:509-519` set walk; Q5 (40 layers, 2^40 paths) |
| Opus S8 — payment on a superseded method | **not closed** | see S3 below (XM1) |
| Opus S9 / Codex S2 — battery gaps | **closed** except: Q4c no longer has the shortcut; Q3d pinned to 23001; still no foreign-*schedule* case for the tenant check (only foreign item, Q4e/Q4g) — N7 |
| Codex S1 — CI skips a race when the clone fails | **closed** | `tests/ci.sh:56-61` `cstep` |
| Fable N1 / Opus note — GUC still caller-settable | recorded as R14, unchanged (as agreed) |
| Fable N5 / Opus note — `trg_enforce_reading_validation_workflow` ENABLE ORIGIN | **not changed**: catalog still shows it, `trg_populate_reading_calculations` and `dry_run_no_read_locks` as `O`, every new trigger `A`. Pre-existing; N8 |

## New code

**Born-unconsumed INSERT (`:412-435`).** Correct shape; superuser exemption keys on `current_user` rolsuper (XR9: owner inserts a 2020-locked read, accepted, by design). No SECURITY DEFINER function owned by `tally` inserts reads (catalog: only `void_invoice` touches `meter_readings`, UPDATE only), so the exemption is not reachable from the app today. But see S1: the same six fields the INSERT guard protects are freely writable by UPDATE on an unconsumed read.

**Block 2 whitelist (`:355-369`).** Every name in the list is a real `meter_readings` column (checked against the 100-column catalog list); none of the three lock-pointer/flag fields leaks in. The `jsonb_each(to_jsonb(OLD))` compare handles NULL (JSON null = JSON null) and a no-op UPDATE (XR3c accepted). Legitimate writes after consumption all pass: `void_invoice()`'s exact write (R6; X8 end to end), the correction re-lock (R8; XR11 re-lock under the *same* run with a new bill also passes), `void_released -> released_to_billing` (R8), follow-up and dispute fields (RW6), tamper fields (XR3b), the void write with a `notes` change in the same statement (XR6, harmless). Frozen that a field crew might want: `access_notes`, `access_status`, `skip_code`, `attempted_count` (XR3 refused) — a deliberate choice; `followup_notes`/`notes` stay open, so fine, but the application contract (R9) should say field-visit notes on a billed read go in `notes`. Boundary (XR4): the lock write itself may rewrite `reading_value` and `consumption` in the same statement (OLD is unconsumed) — by R3's design the core owns pre-lock values; recorded, not a finding.

**Payments (`:585-592`).** `payments_refund_is_refund_check` is complete on both legs (`refunds_payment_id IS NULL` short-circuits; `amount` NOT NULL). B1 above for the index. Also open: a refund may cite another customer's payment (XP4 accepted; single-column FK, same tenant) and exceed it (XP5 — the core's arithmetic, not asked for); a "replacement" may cite a payment that never bounced (XP7) — harmless now the index ignores the label. A pending row's amount flip frees the slot (XP6a/b) and the flip back is refused by the index (XP6c) — intake edits on a pending row are allowed by `enforce_payment_immutable`, acceptable.

**AI (`:787-825`).** Composite FKs with both `tenant_id` columns NOT NULL; `created_by_ai` NOT NULL on both tables so the required-check has no NULL leg. Write-once trigger correct. Not bound: the cited row's `action_type` (XA2: a `query` row cites fine) and `adhoc_charges.source` may be relabelled `manual` while pending with the citation kept (XA1) — notes, not holes.

**Import job record (`:974-1008`).** Write-once set and final statuses as stated; `trg_populate_import_job_idempotency_key` is BEFORE INSERT only, so it cannot rewrite the frozen key behind the guard. A live job may still be cancelled mid-import (XJ2b) — R13, as stated. API-source jobs with no hash are uncounted (XJ1a/b) — the CHECK scopes the file rule to the four file sources, as the header says.

**Unconditional supersession write (`:717-718`).** Verified by C5 against the r1 shape (M7). The AFTER UPDATE re-enters the BEFORE trigger with no identity change and `is_active` false→false, so no recursion and no false "reactivation".

**Rider walk (`:509-519`).** Set semantics; `d.id <> NEW.id` correct on UPDATE (Q4h); Q5 shows the 2^40-path graph in milliseconds.

## Section 8 (running balance)

- `void_invoice()` body: diffed `tu.sql:14039-14337` against `:1094-1398`. The only body difference is step 6 (`SELECT running_balance … WHERE id = v_ledger_entry_id` → `coalesce(sum(amount),0)` over the customer's rows, tenant-qualified). Header differences are formatting only (`SET search_path TO 'public','pg_temp'` ≡ `= public, pg_temp`). Catalog after apply: `prosecdef = t`, `proconfig = {search_path=public, pg_temp}`, owner `tally`, ACL `{tally=X, tally_app=X}` with no PUBLIC — the same as `tu.sql:21499/21509`. The function COMMENT (tu.sql:1395) survives CREATE OR REPLACE and does not mention the column.
- End to end (X8, as `tally_app`): invoice `pending` 70.00, ledger 70 charge / −30 payment, a locked read under it; `void_invoice(..., 'wrong_read')` returns `credit_balance = -30.00` (70 − 30 − 70), `reads_released = 1`, the read is `void_released` with `voided_from_invoice_id` = the bill, the reversal row's `created_at = now()`, the carve-out is `false` afterwards, the invoice is `void`. Another tenant's 999.00 row for a different customer is not summed. `account_balance_as_of` for the same customer gives −30.00.
- `running_balance` elsewhere: pre-patch (`fable19r` before apply) the only references were `void_invoice` and `compute_ledger_running_balance`; no index, view, materialized view, policy or `pg_depend` entry on the column (DROP COLUMN without CASCADE succeeded, which proves it). `compute_ledger_running_balance` had one caller, the dropped trigger. After apply only the two comments in S4 still name it.
- `v_new_running_bal DECIMAL(12,2)` and the payload key `credit_balance` are kept — same contract, new meaning (sum of all rows, not the running figure at the reversal row). State that in the function COMMENT (it still describes "return a JSONB payload" generically; fine).

## Should-fix

**S1. The lock record is refused at INSERT but written freely by UPDATE before the lock** — `:412-435` vs `:340-396`. The INSERT message (:424) says the lock record "is written only by a billing run's move to locked and by void_invoice()". As `tally_app` on a `pending_review` read: `SET locked_by_billing_run_id = R1` (XR10a), `locked_by_invoice_id = I2` (XR10b), `locked_at = '2020-01-01'` (XR10c), `voided_from_invoice_id = I2` (XR10d) — all ACCEPTED; the row is pending, flag false, and carries a run, a bill, a lock time and a voided bill. Blocks 1–3 only act when `OLD.billing_period_locked` or on a transition, so an unconsumed read's lock record is open. Harm is bounded (a later real lock re-stamps `locked_at`; the false pointers are not read by any guard) but it is the same class as r1's S2 and the claim is wider than the check. Fix: when `NOT OLD.billing_period_locked`, refuse a change to `locked_at`, `locked_by_billing_run_id`, `locked_by_invoice_id` unless `NEW.validation_status = 'locked'`, and `voided_from_invoice_id` always. Battery: the four XR10 cases.

**S2. A refund may cite another customer's payment** — `:585-587`. `refunds_payment_id` is a single-column FK; XP4 (C1 refunds C2's payment) ACCEPTED. Rule 7 is satisfied for the tenant (RLS makes the other tenant's row invisible) but not for the customer, and r2 made the same customer check for `payment_methods` supersession. A composite FK `(refunds_payment_id, customer_id) -> payments (id, customer_id)` (needs `UNIQUE (id, customer_id)`) or a line in a trigger. Same for `nsf_original_payment_id`.

**S3. `payment_method_after_supersede` comment claims what no guard does** — `:723` "so a draft can no longer use the replaced account". XM1: a payment with `payment_method_id` = the superseded, inactive method is ACCEPTED (Opus S8, not closed). Either refuse `payment_method_id` pointing at an inactive method on INSERT (schema protects the record), or change the comment to "the core must not draw on an inactive method".

**S4. Two comments still describe the dropped column** — `tu.sql:13725` (table comment on `account_ledger`: "running_balance is computed on INSERT by compute_ledger_running_balance()") is not rewritten by section 8, and the patch's own `:1078` says "unlike running_balance". Add `COMMENT ON TABLE public.account_ledger` to section 8 and drop the clause at :1078. Cheap, and it is the first thing a reader of `\d+ account_ledger` sees.

**S5. Index comment claim (part of B1)** — `:592` should say what is and is not counted once B1 is fixed, including `amount = 0`.

## Notes

- N1. XR5: a read locked with no bill pointer (legal: the lock requires only the run) and then void-released by the exact write ends with `voided_from_invoice_id = NULL` — the write is "exact" relative to an empty pointer. Pre-existing shape (r1 N2).
- N2. XR8: a second void (after re-lock under I2) overwrites `voided_from_invoice_id` from I1 to I2 — Block 3 requires exactly that. The first void survives only in `invoice_events`. Say so in the column comment, or it reads as lost history.
- N3. XP3: `amount = 0` rows with a processor id are never counted; XP6: a pending row's amount is editable, so a webhook row inserted pending and flipped frees the slot until flipped back.
- N4. XA2: any `ai_audit_log.action_type` is a valid citation (Opus suggested `mutation_executed`/`suggestion_approved`); XA1: `source` is editable while pending. Both consistent with "schema represents".
- N5. `ai_audit_log.session_id … ON DELETE CASCADE` and `ai_tool_calls.audit_log_id ON DELETE CASCADE` remain; `append_only` refuses the cascade at run time (23001), so a session delete with audit rows fails — safe, but RESTRICT would say it in the catalog, as dunning now does.
- N6. L7c proves the adhoc write-once trigger only by SQLSTATE mismatch: without the trigger the row is refused by `adhoc_charges_ai_audit_required_check` (NULL citation on an `ai_suggestion` row). Change L7c to cite a *different* audit row so the trigger is the only thing refusing it.
- N7. The tenant check for a foreign *schedule* (`:482`) has no battery case (Q4e/Q4g use a foreign item). One line.
- N8. `trg_enforce_reading_validation_workflow`, `trg_populate_reading_calculations`, `dry_run_no_read_locks` are still ENABLE ORIGIN while every trigger this patch adds is ALWAYS; `session_replication_role` is superuser-only so it does not matter today. Align when convenient.
- N9. `enforce_reading_born_unconsumed` and `stamp_log_created_at` exempt `current_user` rolsuper; inside a `tally`-owned SECURITY DEFINER function that is true. None of those functions inserts reads or log rows except `void_invoice` into `account_ledger` (X8 shows it is stamped `now()` anyway because it passes no `created_at`). A future definer that writes a `created_at` would keep it.
- N10. Battery assertions checked for accidental truth: R1/L1/L8 compare to `now()` (constant within the transaction — right); B1's five balances are pinned to concrete values on both sides of each coordinate; B4 asserts the column, the function and the reader are gone; Q5 asserts refusal *and* time. Nothing passes by accident that I could find beyond N6.

## Probe transcript (abridged)

ACCEPTED where the patch does not claim otherwise: XR4, XR6, XR8, XR9 (owner), XR11, XR3b, XR3c, XP6a/b, XA1, XA2, XJ1a/b, XJ2a/b/c, XJ3, XM3, XM4. REFUSED as expected: XR2, XR3, XR3d, XR3e (23001), XR12 (locked -> excluded, P0001), XP6c (23505), XJ4 (42501). Accepted against the claim: XP1b, XP1d, XP2b (B1); XR10a–d (S1); XP4 (S2); XM1 (S3).
