# v5.4.2-19 r3 — Fable review

Reviewer: Fable 5.1. Date: 2026-10-13. Clones: `fable19` (patch + battery + probes), `fable19m` (one per mutation run), `fable19r` (race script); all dropped.

Hashes match the brief: patch `4ef0d4d0…` (1,519 lines), battery `32ecc5a7…`, race `91f28175…`, ci.sh `a5e640c0…`.

## What I ran

- Strict apply (`search_path=''`, `check_function_bodies=on`, ON_ERROR_STOP) on a clone of `tally`: clean. Second run: the `\if` gate fires ("already applied"), exit 0.
- battery-19-frozen-r3: 159 PASS, "battery-19: complete". The battery ends in ROLLBACK, so the clone was clean for probes.
- `cycle-19.sh` on `fable19r` (r3 applied): C1–C7 PASS.
- **Mutation runs** (one guard removed on a fresh clone of the patched DB, battery re-run):

  | removed | battery result |
  |---|---|
  | `DROP INDEX payments_provider_refund_once` | FAIL P7c accepted (73 PASS before) |
  | `DROP TRIGGER a_enforce_payment_lineage` | FAIL P9 accepted |
  | lock-record fence (`:377-390` deleted from the function) | FAIL RL1 accepted |
  | r2's `enforce_import_job_record` restored | FAIL J10 accepted |
  | `import_jobs_file_once` re-keyed on `(tenant, hash, import_type)` | FAIL J2c accepted (Codex S1 closed: the key is now the only thing refusing it) |
  | `DROP TRIGGER enforce_ai_provenance_write_once ON adhoc_charges` | FAIL L7c accepted (Fable N6 closed) |
  | `void_invoice()` sum replaced by `SELECT 0` | FAIL B5 (`credit_balance` 0.00) |
  | rider schedule-tenant check turned to `WHERE false` | FAIL Q4i accepted (Fable N7 closed) |

  Every r3 case fails exactly at its own guard; none passes on a neighbour.
- Probes as `tally_app` (`SET LOCAL app.user_id`, `pg_temp.probe` reports ACCEPTED/REFUSED with SQLSTATE and constraint, all rolled back): XP1–XP7, XR1–XR9, XJ1–XJ7, XS1–XS2 — quoted where they matter.

## Verdict: **ready.** No blocking items. Three should-fix, all small; one is a one-sided check.

## Round-2 closure

| r2 item | status | where |
|---|---|---|
| **Fable B1 / Opus S4** — refund delivered twice | **closed** | `:655-659` `payments_provider_refund_once`; P7c (same refund twice, 23505 by name), P7d (partial under its own id accepted), P7e (negative row with no lineage twice); mutation above. XP1a–c: three partial refunds (one on the original's id, two on refund ids) accepted; XP1d (a second partial re-using the charge id) refused — by the stated design |
| Fable S5 — index comment | **closed** | `:649-650` and `:658-659` say what is counted, including `amount = 0` (XP6: two zero rows accepted, as stated; R17) |
| **Fable S2 / Opus PR3** — refund cites another customer's payment | **closed on the citing side**, see S1 | `:665-692`; P9/P9b. XP4b (customer moved on a pending refund), XP4c/d (retarget to C2's, to T2's invisible payment), XP4e (nsf_original to T2), XP4g/h (INSERT) all refused 23503 with the trigger's message; XS1: the owner is refused too (no superuser exemption, correct). XP7: a posted refund's citation retarget is refused by this trigger before `enforce_payment_immutable` (a_ sorts first; both would refuse) |
| **Fable S1** — lock record writable on an unconsumed read | **closed** | `:377-390`; RL1–RL4; mutation. XR1/XR1b: a bill or run pointer written ahead of the lock on a `released_to_billing` read refused; XR2: the lock write carrying `voided_from` refused; XR3: the real lock write (run, bill, flag, caller `locked_at` 2020) accepted and `locked_at = now()` (Block 1's stamp; no bad interaction: the fence admits the move to locked, Block 1 then stamps); XR5c: a no-op write of the NULL record accepted |
| Fable S3 / Opus S3 / Codex S2 — supersession comment | **closed as R16** | `:822` comment rewritten; R16 `:217-219`. **I agree**: a late capture on the replaced account is a true record of what was drawn, and refusing it would make the schema lie about money that moved. The core picks the account |
| Fable S4 / Opus S1 / Codex S2 — stale comments | **closed** | `:1511-1512` `COMMENT ON TABLE account_ledger`; `:1186` drops "unlike running_balance"; header `:82-87` (CI-055) and `:117-122` (CI-118) now describe r2/r3 |
| Opus S2 — finished import's file repointed | **closed** | `:1090-1100`; J10/J10b; mutation. XJ1: a live (`importing`) job writes counts and URL/size freely; XJ2: the finishing write (`partial` + final counts + `completed_at`) in one statement accepted; XJ4 (a count to NULL) and XJ5 (size) refused on the finished job; XJ6 no-op accepted. No function in tu.sql updates `import_jobs` (only the one-time key backfill at `tu.sql:12354`), so nothing legitimate is caught |
| Opus N2 — read locked without a bill is stranded | **R15** (`:211-216`) | XR4/XR4b reproduce it (lock with run only accepted; attaching the bill later refused 23001). Agree it is a contract, not a guard: the move to locked has never required the bill, and requiring it now would be a rule on the run's shape |
| Opus N3 — dedup keyed on capture channel | **R17** | XP1e: the same refund `RF-1` by `paymentus_webhook` and by `imported` both accepted. Agree |
| Opus N5 — `status` moves the next read's "previous" | **R18** | stated; agree it is a domain call |
| Codex S1 — J2c isolation; B5 | **closed** | `refuses_at` requires the constraint name (`:48-67`); J2c `:608-612` own file name and key; B5 `:716-739` pins 1.00 against `account_balance_as_of` on both customers and another tenant; both mutations above |
| Codex S3 — lock order headers before edges | **closed** | `:546-553` |
| Fable N2 — `voided_from` holds the latest void | **closed** | `:486-487` column comment |
| Fable N6, N7, N8 | **closed** | L7c `:511-514`; Q4i `:279-282`; `:482-485` ENABLE ALWAYS (catalog: every trigger on `meter_readings` is `A` except `trg_populate_reading_location`, `O`, untouched) |

## New code

**Refund index (`:655-659`).** Legitimate flows: two (three) partial refunds pass when the processor gives each refund its id (XP1a–c). A refund of an NSF'd payment is accepted (XP2a: the original has `status = 'nsf'`; the schema does not tie a refund to the original's status — the core's call, note N1). A replacement for a bounced payment under its own id passes (XP2b); re-presented under the *same* processor id it is refused by the receipt index (XP2c) — right for one receipt per id, and the intake contract must know an ACH re-presentment carries a new trace. A reversal and a refund of one payment: the status path (`reversed`, `reversed_at`) needs no row (XP3d); if the app records a chargeback as a negative row *and* a partial refund already used the charge id, the chargeback on the charge id is refused (XP3b) and passes on its own dispute id (XP3c). That is the design the index comment states for refunds; see S2 for saying it about every money-out row. No zero-amount leg (R17). The index holds on UPDATE (r2's PR6 reasoning unchanged; a pending refund cannot flip positive — `payments_refund_is_refund_check`).

**Lineage trigger (`:665-692`).** Positive check (visible AND tenant AND customer); runs as the caller so RLS hides the other tenant's row and the FK's cross-RLS existence does not help (XP4d/g). `UPDATE OF refunds_payment_id, nsf_original_payment_id, customer_id, tenant_id` covers every column of the predicate on the citing row (XP4b–e); an unrelated UPDATE does not fire it (XP4f), fine since the predicate's inputs are unchanged. Superuser: no exemption (XS1), correct — nothing legitimate needs one. `customer_id` and `tenant_id` are NOT NULL so the `NOT EXISTS` has no NULL leg. **Gap (S1):** the predicate has two rows and the trigger watches one. XP5: a pending payment P (C1) cited by a pending refund R (C1); `UPDATE P SET customer_id = C2` is accepted (`enforce_payment_immutable` allows it while pending) and R now cites another customer's payment (`mismatched_lineage = 1`). Bounded to pending originals, but the comment at `:689-690` claims the relation, not the write.

**Lock-record fence (`:377-390`).** Keyed on `OLD.billing_period_locked = false`, which is exactly the set Blocks 2/3 do not cover; `voided_from` frozen unconditionally, the three lock fields admitted only when `NEW.validation_status = 'locked'`, which Block 1 then constrains (flag true, run present, stamp). Paths in tu.sql that write these columns on `meter_readings`: only `void_invoice()` (`tu.sql:14144-14147`), which writes WHERE locked (flag true) — never on an unconsumed read. Billing runs and gates write no read columns in-schema; the core does the lock in one write (R15 contract). Correction flows: void_released and released_to_billing keep the flag true (XR8 shows `billing_period_locked = t` after the void and the move back), so the re-lock (XR9) and the void (XR7) never meet the fence; XR9b (re-lock clearing `voided_from`) is still refused by Block 3. Interaction with Block 1's stamping: none adverse (XR3). `dry_run_no_read_locks` only raises. Residual (N3): a superuser history load may insert `validation_status = 'locked'` with the flag false (XS2 accepted); on such a row the fence admits lock-record writes because `NEW.validation_status = 'locked'`. Owner-only; arguably the repair path a history load wants.

**Import freeze (`:1090-1100`).** The seven counts are compared as a row (`IS DISTINCT FROM` on row values handles NULL). A finished job leaves `import_summary`, `validation_errors`, `column_mapping`, `ai_extraction_log`, `mapping_*`, `started_at`, `completed_at` writable (XJ7: `import_summary` rewritten to `{"committed": 99}` on a `partial` job accepted). The header's claim (`:121-122`) is "status, stored file and row counts", so the check is as wide as its claim; S3 asks whether the summary belongs with the counts.

**ENABLE ALWAYS (`:482-485`).** `session_replication_role` is superuser-only (XR6: `tally_app` gets 42501), so for the app nothing changes. The only effect is under replication/`replica` loads by a superuser, where the three triggers now fire like the new ones — the consistent choice.

**Comments.** `:822` no longer claims a guard; `:546-553` names the header-before-edge order and the retry; `:1511-1512` describes the ledger as it is now. `account_ledger` table comment survives the mirror since it is a `COMMENT ON TABLE` after the column drop.

## Tests

Each new case fails without its guard (table above). Accidental truth: B5's 1.00 depends on L8's stamped 1.00 row for C2 and on the other tenant's 70.00 and C1's rows being excluded — all three are what the test is for. `refuses_at` falls through to `strpos(SQLERRM, p_guard)` when `CONSTRAINT_NAME` is empty (trigger RAISEs), so RL1–4/P9/J10 pin the message fragment; the fragments are distinctive (`no billing run has consumed`, `is not a payment of this customer`, `source_file_url`, `row counts`). J2c pins the index name. Q4i pins the rider message and would not pass on the FK (M8 showed the row is *accepted* without the check — the FK bypasses RLS). Nothing else found true by accident.

## Should-fix

**S1. The lineage check watches the citing row only** — `:665-692`. XP5 above: moving a pending cited payment to another customer leaves its refund citing another customer's payment. Fix in the same trigger: on UPDATE, when `NEW.customer_id IS DISTINCT FROM OLD.customer_id` (or tenant), refuse if any payment cites `OLD.id` via either column (`EXISTS (SELECT 1 FROM payments c WHERE c.refunds_payment_id = OLD.id OR c.nsf_original_payment_id = OLD.id)`); the trigger already fires on `UPDATE OF customer_id, tenant_id`. One battery case: XP5's shape. (A composite FK `(refunds_payment_id, customer_id) → payments (id, customer_id)` would do both sides declaratively but still needs the positive tenant check, so keep the trigger.)

**S2. Say the money-out rule for every negative row, not only refunds** — `:651-659` and R9. XP3b: after a partial refund on the charge id, a chargeback recorded as a negative row on the same charge id is refused; it passes on the processor's dispute id (XP3c) or as the status path (XP3d). The comment says "a further (partial) refund carries the processor's id"; the contract the intake needs is "the first money-out row may carry the charge id; every other money-out row (refund, return, chargeback) carries its own processor id, or is a status change on the original". One sentence in the index comment and R9.

**S3. A finished import's `import_summary` and `validation_errors` stay writable** — `:1094-1100`. XJ7. They are the counts in another shape (jsonb) and the evidence a reviewer reads. Either add them to the frozen set (`IS DISTINCT FROM` on jsonb works) or say in the header that the summary is the core's document and not the record. Low.

## Notes

- N1. XP2a: a refund may cite a payment whose `status` is `nsf`/`reversed`; XP4i: a refund may cite a refund. Both "schema represents"; the core's arithmetic.
- N2. XP2c: a bounced ACH re-presented under the same processor id is refused as a duplicate receipt. Correct for the rule; the intake contract (R9) should say a re-presentment is a new processor transaction.
- N3. XS2: the owner may insert `validation_status = 'locked'` with `billing_period_locked = false` (the INSERT guard exempts superusers wholesale); the fence then admits lock-record writes on it. If the history-load exemption is kept, consider requiring internal consistency even for the owner (locked ⇒ flag true, run present). Owner-only.
- N4. XP1f: two identical manual refunds with no processor id are accepted — uncounted by design (no id to key on); the core's dedup.
- N5. XP7: on a posted refund, `a_enforce_payment_lineage` refuses a cross-customer retarget before `enforce_payment_immutable` would; both refuse, the SQLSTATE a caller sees is 23503 not 23001. Cosmetic.
- N6. The lock-order comment (`:546-553`) is right that an edge UPDATE locks the edge before the bump; the deadlock it describes is the price of the header mutex and the retry contract is stated. Nothing to change.
- N7. Race script unchanged; C1–C7 pass on r3 (the patch changes to payments/reads do not touch the raced tables).

## Probe transcript (abridged)

ACCEPTED: XP1a/b/c/e/f, XP2a/b, XP3a/c/d, XP4a/f/i, XP5 (S1), XP6, XR3 (stamped now), XR4 (R15), XR5c, XR7, XR8, XR9, XJ1, XJ2, XJ3, XJ6, XJ7 (S3), XS2 (N3). REFUSED: XP1d, XP3b (23505 `payments_provider_refund_once`); XP2c (23505 `payments_provider_transaction_once`); XP4b/c/d/e/g/h, XP7, XS1 (23503, lineage message); XR1, XR1b, XR2, XR5 (23514, fence message); XR5b (P0001 transition); XR4b, XR9b (23001 Block 3); XJ4, XJ5 (23001 `row counts` / `source_file_size_bytes`); XR6 (42501).
