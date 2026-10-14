# v5.4.2-19 r3: Opus review

**Artefacts checked.** All four match the brief: patch `4ef0d4d0…` (1,519 lines), battery `32ecc5a7…`, race `91f28175…`, ci.sh `a5e640c0…`.

**Verdict: ready.** Nothing is blocking. Every r2 blocking and should-fix item is closed, or is accepted as a residual that I agree with. I found one new should-fix. The lineage trigger checks a refund against the payment it cites, but a change to the cited payment is not checked. So a pending original moved to another customer leaves its refund citing that other customer's payment (probe PA10). It needs a one-line fix, and nothing pays out twice because of it. Everything else is notes.

## What I ran
- **Setup.** Clone `opus19` from `tally`, TEMP revoked, strict apply (`search_path=''`, `check_function_bodies=on`, ON_ERROR_STOP).
  - The apply is clean; the only notices are the expected `DROP TRIGGER IF EXISTS` ones.
  - A second run takes the gate ("already applied; nothing to do").
- **Battery r3.** 159 PASS, ending with "battery-19: complete".
- **Mutations**, each on a fresh clone of the patched DB, with the battery re-run:

  | Mutation | Result |
  |---|---|
  | `enforce_ai_provenance_write_once` dropped on adhoc_charges | **FAIL L7c accepted** (the r3 swap case now isolates the trigger) |
  | `IF NOT OLD.billing_period_locked THEN` → `IF false THEN` in the new RL fence (patch 380) | **FAIL RL1 accepted** |
  | the `source_file_url` freeze disabled (patch 1095) | **FAIL J10 accepted** |

  The brief's own mutations (P7c, P9, J2c, B5) I did not repeat. The new cases (RL1–4, Q4i, P7c/e, P9/P9b, J2c, J10/J10b) use `refuses_at` with a constraint name or a fragment of the guard's own message. A pass therefore requires that guard to fire, and removing the guard fails the case whichever way it then goes.
- **Probes.** I ran the battery with its ROLLBACK replaced by about 35 probes, as `tally_app` with `app.user_id` set, plus a few as the owner where stated. Results are quoted below.
- **Not re-run:** `cycle-19.sh` and the CI suite. Both are unchanged since r2, and r3 does not touch the rate graph.
- Databases `opus19`, `opus19m1`, `opus19m2` and `opus19m3` were dropped.

## 1. Round-2 closure

| r2 item | Status | Evidence |
|---|---|---|
| **Fable B1** / Opus S4 / Fable S5: money out delivered twice | **closed** | `payments_provider_refund_once` (patch 655–659). P7c/P7e refuse by constraint name; P7d is the positive case. My PA1/PA2: two partial refunds under their own ids (`re_1`, `re_2`) are ACCEPTED. PA3: one refund under the original's id is ACCEPTED. The index comment states the zero-amount case (659) and R17 repeats it. |
| Fable S1: unconsumed read's lock record | **closed** | Patch 380–390. RL1–RL4, with the mutation above. My RX1: a move to locked that also sets `voided_from_invoice_id` is refused. |
| Fable S2 / Opus r2 PR3: refund or replacement cites another customer's payment | **closed for the citing row**, one gap | Patch 661–691; P9/P9b. PA11 (re-pointing) and PA13 (moving the refund to another customer) are refused. **The gap is should-fix S1 below:** moving the cited payment to another customer (PA10). |
| Fable S3 / Opus S3 / Codex S2: payment on a superseded method | **accepted as R16**, and I agree | See §2. The comment (822) no longer overclaims. |
| Fable S4 / Opus S1 / Codex S2: stale `account_ledger` comment, header CI-055/CI-118, `:1078` | **closed** | Patch 1511 (catalog comment verified after apply), header 82–87 and 117–122, function comment 1186. |
| Opus S2: finished import's URL and counts | **closed** | Patch 1090–1100; J10/J10b. My IX3/IX4/IX5 refuse `held_rows`, size, and a count set to NULL (the row compare treats NULL correctly). |
| Codex S1: J2c isolation; B5 behavioural balance | **closed** | J2c uses its own file name and key, and requires `import_jobs_file_once`. B5 calls `void_invoice()` as `tally_app` and pins 1.00, with C1's rows and the other tenant's rows present. A stub returning 0 fails, per the brief's mutation. |
| Codex S3: headers-before-edges lock order | **closed** (stated) | Patch 546–553. |
| Fable N6: L7c isolation | **closed** | It now cites a different valid audit row (battery 511–514); mutation m1 fails it. |
| Fable N7: foreign schedule case | **closed** | Q4i. |
| Fable N8: ENABLE ORIGIN | **closed** | Catalog after apply: `trg_enforce_reading_validation_workflow`, `trg_populate_reading_calculations` and `dry_run_no_read_locks` are `A`. `trg_populate_reading_location` (INSERT only) is still `O` (note N5). |
| Opus N2 / Fable N1: read locked without a bill is stranded | **accepted as R15**, agree | A run can lock before its invoice exists, so requiring the bill at lock time would be wrong. The contract "same write" belongs in R9. |
| Opus N3 / Fable N3: dedup keyed on channel; zero amount; pending amount editable | **accepted as R17**, agree | PA7: the same refund id arriving through `imported` is ACCEPTED, as R17 says. PA15: two zero-amount rows with one id are ACCEPTED, as stated. |
| Opus N5 / N1: status on a consumed read moves the next read's "previous"; field confirmation frozen | **accepted as R18**, agree | |
| Opus N8 / Fable N2: only the latest void is kept | **closed** (comment) | Patch 486–487. |
| Codex RW3 (`estimation_reason='x'` is an enum failure) | **not changed** | battery 128 still uses `'x'`. It still fails for the right SQLSTATE (23001 fires before the enum CHECK), so this is cosmetic. Note N6. |

**Residual over guard: supersession (R16).** I agree with the residual. A payment row records what the processor actually drew. Refusing a settlement or late confirmation on the replaced account would force intake to misstate the method or drop a true record. Choosing which account to draw on is the core's decision, and the comment now says so.

## 2. New code

### Refund index (patch 655–659), against legitimate flows
- **Two partial refunds.** These work when each carries the processor's refund id (PA1/PA2). A second refund under the *original* charge id is refused. That is the stated contract (comment 659).
- **Refund of an NSF'd payment.** The battery's P-4 cites `1962`, which is `nsf` by then, and it is accepted. The index does not look at the original's status. Whether such a refund makes sense in the domain is the core's call.
- **Reversal and refund of one payment.** A reversal is a status on the original (`reversed`, `reversed_at`), not a row. PA5 (reversed after refunds) and PA6 (refund of a reversed payment) are both ACCEPTED, and the index does not interact with either.
- **What the index does catch beyond refunds.** It keys on *any* negative row. PA4: a chargeback (`-30`, method `other`) under the original's id, after a refund already used that id, is REFUSED with 23505. That is correct if intake always stores the processor's own event id (Stripe gives disputes their own id).
  - **Risk:** an intake that treats 23505 as "already have it, ignore" would silently drop a real chargeback that reused the charge id.
  - Note N1: add a clause to R17 or R9 that every money-out event (refund, chargeback, reversal row) carries its own processor event id, and that intake must not treat a 23505 on `payments_provider_refund_once` as a harmless duplicate unless the stored row matches the incoming one.

### Lineage trigger (patch 661–691)
- **RLS.** The trigger is not SECURITY DEFINER, so the lookup runs under the caller's RLS. PA8: citing T2's payment is refused with 23503. The positive check makes absence fail closed.
- **Superuser.** There is no exemption, and the tenant is compared explicitly. PA16: the owner citing T2's payment is refused. That is right; no history load should carry a cross-customer lineage.
- **`UPDATE OF` composite.** It covers both pointers plus `customer_id` and `tenant_id` *of the citing row* (PA11 and PA13 refused). It does not cover the **cited** row. See S1.
- **Self-citation.** PA12 (`refunds_payment_id = id` on a pending refund) and PA14 (`nsf_original_payment_id = id`) are ACCEPTED. On UPDATE the row sees its own OLD version, which has the same customer. Note N2.

### Unconsumed-read fence (patch 377–390)
- **Legitimate writers in tu.sql.** The only UPDATEs of `meter_readings` lock fields are the four `void_invoice()` bodies (1229, 12647, 13837, 14144; only the last is live). Each touches only reads with `validation_status = 'locked'`. The backfills at 12953/12960/16943/16951 run before this patch. No other function writes `locked_*` or `voided_from_invoice_id`.
- **Correction flow.** `void_released` keeps `billing_period_locked = true` (Block 2 comment, R8), so `void_released → released_to_billing → locked` goes through Block 3, not this fence. The fence never meets it.
- **Block 1 stamping.** It stamps `locked_at` only when `NEW.validation_status = 'locked'`, and the fence exempts exactly that case. RX2: a lock move carrying run, bill and a backdated time is ACCEPTED, and `locked_at = now()` (RX2b true).
- **Superuser-loaded reads.** The exemption is keyed on `NEW.validation_status = 'locked'`, not on the *transition* into locked, and Block 2 is keyed on the flag. A read that a superuser loaded as `locked` with `billing_period_locked = false` can therefore be rewritten freely by the app (RX3: run, time and bill rewritten; RX4: `reading_value` rewritten; both ACCEPTED). It is also unreleasable, because `void_invoice()` setting `voided_from` would trip the fence.
  - This is pre-existing: the born guard exempts superusers by design, and no application path creates such a row.
  - Note N3: a table CHECK `validation_status NOT IN ('locked','void_released') OR billing_period_locked` would make that inconsistent state impossible for every role.

### Import freeze (patch 1090–1100)
- **Writers.** No function in tu.sql writes `import_jobs` apart from the one-off key backfill at 12354.
- **The finishing write.** IX6: `importing → partial` with the final counts in the same statement is ACCEPTED, because the freeze keys on `OLD.status`.
- **Held rows after finish.** IX7: on a `partial` job, moving held rows to committed afterwards is REFUSED. `import_staging` has `awaiting_dependency` and `awaiting_review` states, so a "release the held rows later" workflow is plausible. Nothing in the repo documents one, though, and `awaiting_error_review` is a pre-finish job status. Note N4: say in R9/R13 that the job's counts are the snapshot at finish and that the staging rows are the live record of held rows.
- **Still writable on a finished job:** `completed_at` (IX1) and `import_summary` (IX2). `completed_at` is arguably part of a finished job's record. Note N4.

### ENABLE ALWAYS
- The change only matters under `session_replication_role = replica`, which is superuser-only.
- The only repo use of replica mode is in battery-13 and fence-and-race-13, and it is applied only to `invoices` fixtures, never to `meter_readings`. So the change does not affect CI.
- `trg_populate_reading_calculations` now also fills `previous_value` under replica mode. That is harmless.

## 3. Tests
- **Does each new case fail without its guard?** Yes, for every case I checked. RL1, J10 and L7c were confirmed by mutation; the `refuses_at` cases are tied to their guard by constraint name or message fragment.
- **Is anything true by accident?**
  - L7c is still `refuses()` (SQLSTATE only). Mutation m1 shows it is now isolated, because nothing else refuses a same-tenant swap. Moving it to `refuses_at(..., 'provenance')` would harden it cheaply.
  - P7d and the B5 balance are value assertions, not accidents.
- **Gaps:** no case for the cited-row direction (S1), self-citation (N2), or a finished job's `completed_at` (N4).

## Blocking
None.

## Should-fix
1. **Lineage is checked from the citing row only** (patch 685–686, trigger `UPDATE OF … customer_id, tenant_id` on the citing row).
   - **Reproduction:** a pending payment X-PEND (C1); a refund X-R7 (C1) citing it is ACCEPTED (PA9); then `UPDATE payments SET customer_id = C2 WHERE id = X-PEND` is ACCEPTED (PA10). X-R7 (C1) now cites C2's payment.
   - The same happens for a replacement citing a pending payment.
   - The header (patch 86–87) claims "a refund or replacement cites a payment of the same customer".
   - **Fix:** in `enforce_payment_lineage`, also require `o.status <> 'pending'` and `o.id <> NEW.id`.
     - A non-pending payment's `customer_id` and `tenant_id` are frozen by `enforce_payment_immutable` (tu.sql 13559–13563), and a payment cannot return to pending (13551). So the citation is permanent once accepted, with no reverse check and no race.
     - Neither a refund nor a replacement legitimately cites money that has not posted.
   - **Battery:** PA9 (now refused) and PA12.

## Notes
- **N1.** The money-out index catches a chargeback or other negative row that reuses an id already used by a refund (PA4, 23505). Add to R17/R9 that each money-out event carries its own processor event id, and that intake must not swallow 23505 on this index as a benign duplicate.
- **N2.** Self-citation is accepted on UPDATE (PA12, PA14). This is covered by the S1 fix (`o.id <> NEW.id`).
- **N3.** A superuser-loaded `locked` read with the flag false is open to app edits and cannot be voided (RX3/RX4). It is pre-existing; a table CHECK tying locked/void_released to the flag closes it for all roles.
- **N4.** On a finished import job, `completed_at` and `import_summary` are still writable (IX1/IX2). Releasing held rows after `partial` is refused (IX7). State that the job counts are a snapshot at finish (R13/R9), and consider freezing `completed_at`.
- **N5.** `trg_populate_reading_location` (BEFORE INSERT on meter_readings) is still ENABLE ORIGIN. Align it with the other three for consistency.
- **N6.** RW3 still uses the invalid `estimation_reason = 'x'` (Codex r2). It passes on 23001 because the freeze fires before the enum CHECK. Use `'other'` for a clean counterexample.

## Probe transcript (abridged)
- **ACCEPTED, consistent with the patch's claims:** PA1, PA2, PA3, PA5, PA6, PA7 (R17), PA9, PA15 (R17), RX2, IX1, IX2, IX6.
- **REFUSED as expected:** PA4 (23505 refund index), PA8 (23503 lineage, RLS), PA11, PA13 (23503), PA16 (owner, 23503), RX1 (23514 RL fence), IX3, IX4, IX5, IX7 (23001).
- **ACCEPTED against the patch's claim:** PA10 (S1), PA12/PA14 (N2).
- **ACCEPTED, pre-existing:** RX3/RX4 (N3).
