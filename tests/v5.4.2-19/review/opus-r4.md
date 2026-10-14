# v5.4.2-19 r4: Opus review

**Artefacts checked.** All four match the brief:
- patch `f1d234f0…` (1,561 lines)
- battery `9a80d4a7…`
- race `b7367898…`
- ci.sh `a5e640c0…`

`sql/v5.4.2-19-hardening-batch-1.sql` in the working tree is byte-identical to the frozen patch. The r3 → r4 patch diff is 62 lines, and every line belongs to the "Revision r4" paragraph.

**Verdict: ready.** Nothing is blocking.
- Every r3 blocking item is closed, and so is every r3 should-fix, apart from two partial test-coverage items.
- I found two small should-fix items, both about tests or wording:
  - the two newest import freezes have no test (a mutation that removes them still passes 171/171);
  - correcting a pending payment *together with* the pending refund that cites it only works in one statement order, and nothing documents that.

## What I ran
- **Setup.** Clone `opus19` from `tally`, TEMP revoked, strict apply (`search_path=''`, `check_function_bodies=on`, ON_ERROR_STOP).
  - The apply is clean; the only notices are the expected `DROP TRIGGER IF EXISTS` ones.
  - The second run takes the gate (`already applied … nothing to do`).
- **Battery r4.** 171 PASS, then "battery-19: complete".
- **Races.** `cycle-19.sh` on `opus19r` (a clone of the patched DB): C1–C8 and C4 all PASS.
- **Mutations**, each on a fresh clone of the patched DB:

  | Mutation | Result |
  |---|---|
  | m1: r3's single-column lineage FKs restored, composite key dropped | **C8 FAIL**: "session B was never seen waiting on a lock". Before r4, `customer_id` was not a key column, so the move took FOR NO KEY UPDATE, which does not conflict with the FK check's KEY SHARE. C8 therefore proves that B was blocked by A's key lock. |
  | m2: the r4 `validation_errors` and `completed_at` freeze lines removed from `enforce_import_job_record` | **171/171 PASS.** No case covers them (S1). |

  I did not repeat the brief's own mutations (P9c, RF2).
- **Probes.** OX1–OX9 ran after the battery's fixtures, before its ROLLBACK, as `tally_app` with `app.user_id` set unless marked "owner". Each probe was rolled back unless marked "kept".
- **Reverse-order races (not in C8).** Two-session runs on `opus19r`, described in §2.
- **Not re-run:** the CI suite. ci.sh is unchanged.
- **Cleanup.** `opus19`, `opus19r`, `opus19m1` and `opus19m2` are dropped, and the /tmp files in the container are removed.

## 1. Round-3 closure

| r3 item | Status | Evidence |
|---|---|---|
| **Codex B1 / Opus S1 / Fable S1**: a cited pending payment moves to another customer | **closed** | Patch 720–729: composite FKs on `(pointer, tenant_id, customer_id)` against `UNIQUE (id, tenant_id, customer_id)`. Battery P9c and P9d (430, 432) refuse by constraint name. OX7: even the owner is refused (23503 `payments_refunds_payment_id_fkey`). C8 passes, and mutation m1 fails it. Reverse order: see §2. |
| Opus N2 (self-citation) | **closed** | `payments_lineage_not_self_check` (patch 728–729); P9f (443) by name. |
| Opus N3 / Fable N3 / Fable XS2: superuser-loaded `locked` read without the flag | **closed** | Patch 505–507. RF2 (battery 123) by name. OX8: the owner loading `void_released` with the flag false is refused 23514 `meter_readings_consumed_flag_check`. OX8b: a locked load *with* the flag is accepted. |
| Fable S3 / Opus N4: finished import's summary, errors and completed_at | **closed in code; partly tested** | Patch 1139–1142, comment 1154, header 131–132. OX9b refuses `completed_at` after finish, and OX9c refuses `validation_errors`. **But** only `import_summary` has a battery case (J10h, 679), and m2 passes 171/171. See S1. |
| Fable S2 / Opus N1: the money-out rule for every negative row | **closed** | Index comment 681 (chargebacks, a dispute id, or status reversed on the original). R17 addition at 234–239 covers intake's duty on a 23505 from `payments_provider_refund_once`. |
| Fable N2: ACH re-presentment id | **closed** | Patch 238–239. |
| Opus N5: `trg_populate_reading_location` ENABLE ORIGIN | **closed** | Patch 501. |
| Opus N6 / Codex caveat: RW3 used `'x'` | **closed** | Battery 170 now uses `'other'`. |
| Codex S1: lineage UPDATE and parent-side matrix | **partly closed** | Now covered: parent move on both pointers (P9c, P9d), a pending retarget to another customer's payment (P9g), self-citation (P9f), and an uncited move (P9e, positive). Still with no case (my probes show each behaves correctly): a valid combined customer-and-pointer re-home (OX3, accepted), both pointers with one mismatched (OX4b, refused), a tenant-only parent change, and the order-dependent family move (S2). Coverage gap, not a defect. |
| Codex S2: import-freeze boundaries | **mostly closed** | J10c size, J10d count set to NULL, J10e failed job, J10f finish-in-one-write (positive), J10g partial job, J10h summary. A cancelled job and the two new fields are not covered (S1). |
| Fable N1, N4–N7; Opus r3 notes on R15/R16/R18 | **unchanged; accepted as residuals** | No r4 change was asked for. |

## 2. New code

### Composite lineage FKs (patch 714–729)

**Child side, legitimate flows.**
- **OX3:** a pending refund re-homed to C2 with its pointer moved to a C2 payment in the same UPDATE is ACCEPTED.
- **OX3b:** changing only the customer is REFUSED by the lineage trigger (23503). That is correct.
- **OX4:** a row carrying both pointers, both to the same customer, is ACCEPTED.
- **OX4b:** with one pointer to the other customer, it is REFUSED.
- **P9e:** an uncited pending payment still moves.

**Parent side.**
- **OX5:** delete is already refused for `tally_app` (42501, no privilege). The FK refuses it anyway.
- **OX7:** a move by the owner is REFUSED by the FK.

**Correcting a pending family together (S2).**
- A pending parent P and a pending refund R citing it both turn out to belong to C2.
- **OX1** (both rows in one UPDATE) is ACCEPTED only when P is processed first.
- In a scratch DB I forced R first, both with a seq scan in ctid order and with a VALUES-join. Both were REFUSED: R's BEFORE trigger reads P's pre-statement version, still C1.
- Postgres row order is not guaranteed, so the one-statement correction is non-deterministic.
- The deterministic path works (OX2): clear R's pointer, move P, then re-home R with its pointer in one UPDATE. It is not written down anywhere.
- No data risk. This is an intake-contract sentence.

**Superuser loads.**
- **OX7c:** child before parent is REFUSED by the lineage trigger. The single-column FK refused this before, so it is unchanged.
- **OX7d:** in a multi-row INSERT, a child listed before its parent is REFUSED by the trigger, because the parent is not yet visible.
- **OX7e:** parent listed first is ACCEPTED. A history load must be ordered parent-first, as before.
- **OX7b:** with `session_replication_role = replica`, the owner *can* move a cited parent. RI triggers do not fire in replica mode, and the trigger guarding this side is the FK only. This is superuser-only and the same as every FK in the schema. Note N1.

**Writers of `payments` in tu.sql.**
- The only function bodies that write `payments` are the v5.4.2-06 deposit backfill (tu.sql 18201, 18204), which runs before this patch. It touches `deposit_status` only, not a key column.
- No function or trigger writes `customer_id`, `tenant_id` or either pointer.
- Other FKs into `payments` are unaffected: `customer_credits`, `adhoc_charges`, `provider_log` and `deposits (source_payment_id, tenant_id)` all target existing keys, and the new unique key is additive.

**Dropping and re-adding by name.**
- The only references to `payments_refunds_payment_id_fkey` and `payments_nsf_original_payment_id_fkey` are their definitions (tu.sql 10175, 10199), the patch, the battery (431, 433) and the race (130).
- The originals were plain NO ACTION, so the delete and update semantics are unchanged.
- The drop and add sit in one `ALTER TABLE`, and the UNIQUE is created before the FKs that need it.
- Mirror note: tu.sql's FK section must replace those two definitions, and the unique key belongs with the table constraints.

**Concurrency.**
- `customer_id` and `tenant_id` are now key columns, so changing them takes FOR UPDATE, which conflicts with any FK check's KEY SHARE on that payment.
- C8 covers A citing first and B moving second. I ran the reverse on `opus19r`: A moves P to C2 and holds; B inserts a refund citing P as C1.
  - **READ COMMITTED:** B is seen blocked by A (`pg_blocking_pids`). After A commits, B fails with 23503 `payments_refunds_payment_id_fkey`: the RI recheck reads P's new version.
  - **REPEATABLE READ:** B is seen blocked, then fails with 40001.
  - In both, zero mismatched lineage rows afterwards.
- Both directions hold. Only one is in C8 (note N2).
- Side effect: a correction of a pending payment's customer now also waits on unrelated in-flight FK checks against that payment, for example an application insert. This is harmless.
- The RI lookup on the child side can use `idx_payments_customer`.

**Two-cycle.** OX6: two pending refunds citing each other is ACCEPTED. The CHECK only stops a length-1 cycle. This is the existing "a refund may cite a refund" residual (Fable r3 N1), core arithmetic. Note N3.

### `meter_readings_consumed_flag_check` (patch 505–507)

Writers of `validation_status` and of the flag in tu.sql:
- **void_invoice.** All four bodies (1233, 12651, 13841, 14148; live: patch 1355–1357) write `locked → void_released` and never touch `billing_period_locked`.
- **The flag cannot drop.** Block 2 freezes it once true, because it is not on the whitelist (patch 416–429).
- **Correction flows.** `void_released → released_to_billing → locked` keeps the flag true. The CHECK does not constrain `released_to_billing`.
- **Exception gate** (17241, 17246). It only reads the `reviewed_*` statuses.
- **No INSERT** of meter_readings anywhere in tu.sql's function bodies.
- **App inserts** are already refused by `a_enforce_reading_born_unconsumed`. The CHECK adds the owner and replica cases (OX8).

It validated cleanly against the `tally` data, and nothing legitimate is caught.

### Import freeze (patch 1139–1142)

- **Who writes `completed_at` after the terminal status?** Nothing in tu.sql.
  - No function updates `import_jobs`, apart from the one-off idempotency-key backfill (12354), which runs before the patch.
  - `set_updated_at` writes `updated_at` only. OX9d, a no-op touch of a finished job, is ACCEPTED.
- **The finishing write.** OX9 (`status='complete'` together with `completed_at`, summary and errors) is ACCEPTED.
- **After finish.** OX9b (`completed_at` later) and OX9c (`validation_errors`) are REFUSED 23001.
- **Worker contract.** An external worker that writes the terminal status and *then* stamps `completed_at` in a second statement will now be refused. The function comment (1154) says "frozen with it", and R9/R13 should say "in the finishing write". Covered in S1's wording ask.
- **jsonb comparison.** It is semantic: OX9f, a key-order or whitespace-only rewrite, is ACCEPTED as no change.
- **Not claimed and still writable:** `started_at` (OX9e), `column_mapping`, `ai_extraction_log`, `mapping_*`. These are consistent with the comment.

## 3. Tests

- **P9c and P9d** refuse by FK name. They are accepted under the r3 FKs (the brief's mutation), so they fail without the guard.
- **P9f** refuses by CHECK name. Without the CHECK, the self-pointer passes both the trigger (the row sees itself) and the composite FK (it references itself), so the case would fail.
- **P9g** pins the trigger's message. Without the trigger, the composite FK would refuse under another name, so P9g fails. It isolates the trigger, not the FK.
- **RF2** refuses by CHECK name. Without the CHECK, the owner's insert is accepted (the born guard exempts superusers).
- **J10c–J10h** pin message fragments. J10h's `import_summary` appears in the message only when that freeze fires.
- **Gap (S1):** m2 shows the `validation_errors` and `completed_at` freezes are untested.
- **C8** requires B to be seen in `pg_blocking_pids` with A's pid, and m1 shows it fails without the composite key. So it proves B was blocked by A, not just refused.

## Blocking
None.

## Should-fix
1. **Two r4 freezes have no test.** Patch 1141–1142; battery 669–680.
   - Mutation m2 (both lines deleted) still gives 171/171 PASS.
   - Add two `refuses_at` cases on job `…19b7` after J10f: `validation_errors` and `completed_at`.
   - Optionally add a cancelled-job case, since Codex S2 named all four final statuses.
   - Also state in R9/R13 that `completed_at`, the summary and the errors are written in the finishing write, because a later stamp is refused.
2. **The family correction is order-dependent.** Patch 687–712 with 720–727.
   - Moving a pending payment and the pending refund that cites it to another customer in one UPDATE succeeds only if the parent row is processed first. I reproduced both outcomes (OX1 accepted; forced child-first refused).
   - The deterministic sequence is: clear the refund's pointer, move the parent, then re-home the refund with its pointer in one UPDATE (OX2). Add it to R17 or R9.
   - Optionally add the combined re-home (OX3) as a positive case, since Codex S1 asked for it.

## Notes
- **N1.** Under `session_replication_role = replica` the owner can move a cited parent (OX7b): RI triggers do not fire. This is superuser-only and the same for every FK. If "for every role" is meant to cover replica loads as it does for the CHECK, the header (38–46) should not imply it.
- **N2.** C8 races one direction (cite, then move). The reverse (move, then cite) also holds: in READ COMMITTED B waits and then gets 23503 from the FK; in REPEATABLE READ B waits and then gets 40001. A C9 leg would pin it cheaply.
- **N3.** Two pending refunds may cite each other (OX6). This is the same residual as "a refund may cite a refund" (Fable r3 N1).
- **N4.** P9g isolates the trigger. No case isolates the composite FK's *child* side, but the trigger covers it and adds the RLS visibility.
- **N5.** Mirror: tu.sql's FK definitions at 10175/10199 change shape, and `payments_id_tenant_customer_key` must precede them.

## Probe transcript (abridged)
- **ACCEPTED:**
  - OX1 (parent processed first)
  - OX2a, OX3, OX4, OX6
  - OX7b (replica), OX7e, OX8b
  - OX9 (kept), OX9d, OX9e, OX9f
- **REFUSED:**
  - OX3b, OX4b, OX7c, OX7d (23503, lineage trigger)
  - OX5 (42501)
  - OX7 (23503 `payments_refunds_payment_id_fkey`)
  - OX8 (23514 `meter_readings_consumed_flag_check`)
  - OX9b, OX9c (23001)
  - OX1 with the child forced first (23503, lineage trigger)
- **Races on `opus19r`:**
  - C1–C8 PASS
  - reverse order in READ COMMITTED: B blocked by A, then 23503 FK
  - reverse order in REPEATABLE READ: B blocked by A, then 40001
  - mismatched lineage rows afterwards: 0
