# v5.4.2-19 r4 — Fable review

Reviewer: Fable 5.1. Date: 2026-10-13. Clones: `fable19` (patch + battery + probes), `fable19m1`–`m4` (one per mutation run), `fable19r` (race script), `fable19r2` (race script with the refunds FK restored to single-column); all dropped.

Hashes match the brief: patch `f1d234f0…` (1,561 lines), battery `9a80d4a7…`, race `b7367898…`, ci.sh `a5e640c0…`. `sql/v5.4.2-19-hardening-batch-1.sql` is byte-identical to the frozen patch.

## What I ran

- Strict apply (`search_path=''`, `check_function_bodies=on`, ON_ERROR_STOP) on a clone of `tally`: clean (only the expected `DROP TRIGGER IF EXISTS` notices). Second run: the `\if` gate fires, exit 0.
- battery-19-frozen-r4: 171 PASS, "battery-19: complete", ends in ROLLBACK.
- `cycle-19.sh fable19r` (r4 applied): C1–C8 PASS.
- **Mutation runs** (one guard removed on a fresh clone of the patched DB, battery re-run):

  | removed | result |
  |---|---|
  | `DROP CONSTRAINT payments_lineage_not_self_check` | **FAIL P9f accepted** (83 PASS before) |
  | `payments_nsf_original_payment_id_fkey` restored to `(nsf_original_payment_id) → payments(id)` | **FAIL P9d accepted** (80 before) |
  | the three r4 lines of `enforce_import_job_record` (`import_summary`, `validation_errors`, `completed_at`) deleted | **FAIL J10h accepted** (152 before) |
  | the `source_file_size_bytes` line deleted | **FAIL J10c accepted** (148 before) |
  | race clone: `payments_refunds_payment_id_fkey` restored to single-column | **FAIL C8**: B was still seen blocked by A (customer_id is a key column through `payments_id_tenant_customer_key`, so the move still waits), but after A committed the move was **accepted** — "got: (empty)". C1–C7 and C4 pass. |

  With the brief's own two (P9c on the restored single-column FKs, RF2 on the dropped CHECK), every r4 case fails exactly at its own guard.
- Probes as `tally_app` (`SET LOCAL app.user_id`, `pg_temp.probe` reports ACCEPTED/REFUSED with SQLSTATE and constraint; whole transaction rolled back): XF1–XF9, XM1–XM4, XJ8–XJ15, quoted below. One hand-run race in the other order (move first, citation waits).
- Not re-run: the CI suite (unchanged since r2; r4 does not touch the rate graph or the CI steps).

## Verdict: **ready.** No blocking items. Two should-fix (both documentation/precondition), the rest notes.

## Round-3 closure

| r3 item | status | where |
|---|---|---|
| **Codex B1 / Opus S1 / Fable S1** — a cited pending payment moves to another customer | **closed** | `:720-729`: `UNIQUE (id, tenant_id, customer_id)` and both lineage FKs recomposed on it, NO ACTION. P9c/P9d by constraint name; mutations above. XF9 (owner moves a cited pending parent): refused 23503 `payments_nsf_original_payment_id_fkey` — no superuser exemption, correct. P9e: an uncited pending payment still moves. C8: a citation and a move serialise (the move waits on the citation's KEY SHARE, then is refused). My reverse run on `fable19r`: A moves the parent and holds; B's refund INSERT is seen blocked by A (`pg_blocking_pids`), then after A commits is refused 23503 `payments_refunds_payment_id_fkey` — the r3 trigger's snapshot passed (parent still C1 at its statement start) and the FK's end-of-statement re-check caught it. Both orders are closed. |
| Opus N2 — self-citation | **closed** | `:728-729` CHECK; P9f (UPDATE) by name; XF7 (INSERT with an explicit id citing itself) refused by the lineage trigger first (23503, "is not a payment of this customer") — the row does not exist yet, as the battery comment at `:439-441` says. |
| Codex S1 — UPDATE and parent-side matrix | **closed** | P9c/P9d (parent move, both pointers), P9e (uncited move accepted), P9g (child retarget), P9f (self). My XF1/XF1b (customer and pointer moved together, and back) accepted; XF1c (customer alone) refused; XF2 (both pointers, both C1) accepted, XF2b/c (one mismatched, INSERT and UPDATE) refused. |
| Opus r3 N3 / Fable XS2 — superuser-loaded locked read without the flag | **closed** | `:505-507` `meter_readings_consumed_flag_check`; RF2 by name; the brief's mutation. XM1 (owner loads `void_released` with flag false) refused 23514 by name; XM2 (locked WITH flag) accepted — the history load that is internally consistent still works; XM3 (owner clears the flag on it) refused by Block 2 (23001). **XM4b: under `session_replication_role = replica` (owner) a locked read with the flag false is refused by the CHECK** — the one path that evades every trigger is closed, which is the reason a table CHECK was the right tool. XM4c: the UPDATE under replica is still refused by Block 2 (ENABLE ALWAYS). `billing_period_locked` is `NOT NULL DEFAULT false`, so the CHECK has no NULL leg. |
| Fable r3 S3 / Opus N4 — `import_summary`, `validation_errors`, `completed_at` on a finished job | **closed** | `:1139-1142`; J10h; mutation. XJ8 (`completed_at` set after `complete`), XJ9 (`validation_errors` on a `partial` job), XJ13 (`completed_at` nudged after a one-statement finish), XJ15 (owner rewrites `completed_at`) all refused 23001 naming the column. XJ11 (a live job writes summary, errors, `completed_at` freely), XJ12 (the finishing write carries status, `completed_at`, summary and counts), XJ14 (no-op write on a finished job) accepted. XJ10: `column_mapping` on a finished job is still writable — not claimed, fine. Both jsonb columns, so `IS DISTINCT FROM` is well-defined. |
| Codex r3 S2 — import freeze matrix | **closed** | J10c–h `:669-680`: size, a count to NULL, a `failed` job's counts, the positive finishing write, summary, held rows after `partial`. The header `:131-132` now says the counts are the snapshot at finish and staging rows the live record. |
| Fable r3 S2 / Opus N1 — money-out rule for every negative row | **closed** | Index comment `:681` names chargebacks and own-row reversals; R17 `:234-239` tells intake not to read a 23505 on `payments_provider_refund_once` as a harmless redelivery without comparing rows, and that an ACH re-presentment is a new transaction. |
| Opus N5 — `trg_populate_reading_location` ENABLE ALWAYS | **closed** | `:501`; catalog after apply: all nine triggers on `meter_readings` are `A`. |
| Opus N6 — RW3 `'x'` | **closed** | battery `:170` uses `'other'`. |
| Fable r3 N1, N2, N4, N5, N6, N7 | notes, nothing to change | N2 is now R17 text. |

## New code

**Composite FKs (`:720-729`).** Legitimate flows I checked:
- *Correcting a pending refund's own customer together with its pointer*: XF1 (C1→C2 with the pointer moved to a C2 payment, in one statement) accepted; XF1b back again accepted. The FK's child-side check sees the final `(pointer, tenant, customer)` and the r3 trigger checks NEW against NEW. Customer alone (XF1c) is refused by the trigger (23503, message) before the FK would.
- *A parent and its pending child both keyed to the wrong customer*: XF4 (`UPDATE … SET customer_id = C2 WHERE id IN (parent, child)`) **accepted** — the FK is checked at end of statement, and a BEFORE row trigger's SQL sees rows the same command already processed (documented behaviour), so the child's check saw the moved parent. XF4b (data-modifying CTE) also accepted. The three-step path (XF4c unlink, XF4d move parent, XF4e move and relink child) works too. So the stricter FK does not strand a wrongly keyed pair.
- *A payment with both pointers*: XF2 accepted (refund of 19f8 and replacement of 19f9, both C1); either pointer at another customer's payment is refused (XF2b INSERT, XF2c UPDATE).
- *Ordinary writes on a cited pending parent*: XF3 (amount) and XF3b (posted with its effective date) accepted — only a change to the key columns triggers the parent-side check, and only a key change takes the FOR UPDATE lock. XF3c (tenant move) is refused by RLS, not by us.
- *Superuser loads*: XF9c — a parent and its child in ONE multi-row INSERT (parent first) accepted; XF9b (owner's refund citing another customer's payment) refused by the trigger; with the trigger disabled (XF9d/e/f) the FK alone refuses a cross-customer and a cross-tenant citation by name. So the FK now carries tenant and customer on its own; the trigger's remaining contribution is the RLS visibility check and the earlier, clearer message.
- *Writers of `payments` in tu.sql*: the only UPDATEs are the one-time -06 deposit backfill at `tu.sql:18201-18210` (`deposit_status` only), which ran before this patch; no function INSERTs into `payments`. Nothing in-schema moves `customer_id`.
- *Dropping and re-adding by name*: `pg_depend` shows only the internal RI triggers hanging off the two FKs; nothing else in tu.sql, ci.sh or the repo references the names except the r4 battery, `cycle-19.sh` and the live copy of the patch. One ALTER TABLE does the four steps atomically. The other FKs into `payments` (`deposits (source_payment_id, tenant_id)`, `customer_credits`, `adhoc_charges`, `payment_provider_logs`) are untouched.
- *Lock semantics*: `customer_id` is now a key column (member of a unique index), so **any** UPDATE of a payment's `customer_id` takes FOR UPDATE and conflicts with the KEY SHARE that every child FK (including `deposits`) holds on the parent. This is what makes C8 serialise. The r2 mutation shows the serialisation comes from the UNIQUE, the refusal from the composite FK; only pending payments can change customer, so the extra contention is negligible.
- *Cycles*: a two-row cycle of pending refunds (XF6/XF6b: A cites B, B cites A) is accepted. "Schema represents"; note N1.

**Consumed-flag CHECK (`:505-507`).** Writers of `validation_status` in tu.sql: the four `void_invoice()` bodies (only `:14144-14150` live; the patch's `:1309-1315`) move `locked → void_released` WHERE `validation_status = 'locked'`, and the flag — true by the CHECK — is frozen by Block 2 (not in the whitelist), so the void keeps it; the exception gate (`tu.sql:17241-17246`) writes `validated_at` and meter counters only; the correction flow `void_released → released_to_billing → locked` keeps the flag true (Block 2) and Block 1 requires it on the re-lock. `trg_enforce_reading_validation_workflow` runs BEFORE, so an app write that would break the CHECK is refused by Block 1 or Block 2 first (23001/P0001) and the CHECK is reached only by the superuser's INSERT (RF2, XM1) and by replica-mode writes (XM4b). No legitimate path is caught; the only rows it could refuse are history loads that are internally inconsistent, which is the point.

**Import freeze (`:1139-1142`).** No function in tu.sql updates `import_jobs` (only the one-off key backfill at `:12354`), so no in-schema path sets `completed_at` after the terminal status. The contract for an external worker is now "finish in one write" (XJ12 accepted, XJ13 refused); the header `:131-132` and the function comment `:1154` say it. `updated_at` stays writable by its trigger (generic, not part of the record).

## Tests

- Each new case fails without its guard: P9c (brief), P9d (m2), P9f (m1), RF2 (brief), J10h (m3), J10c (m4); C8 fails with the single-column FK restored (the move is accepted). P9e and J10f are positive cases and pass without the guard, as they should.
- C8 proves B was blocked by A: `waiting()` (`cycle-19.sh:61-70`) requires A's pid in `pg_blocking_pids(B)` while A holds, and `check()` fails on "never seen waiting" before it looks at B's error; B's refusal is pinned to 23503 and the FK's name. One subtlety from my mutation: with the single-column FK the wait still happens (the UNIQUE alone makes `customer_id` a key column), so C8's "waited" leg proves serialisation and its "refused" leg proves the FK — two guards, both needed, both pinned. The other order (move holds, citation waits) is not in the script; I ran it by hand and it is refused by the FK too.
- Nothing true by accident: P9c/P9d pin constraint names that only the composite FKs produce; P9g pins the trigger's message; P9f the CHECK's name; J10c–h the column fragments of one function's message.

## Should-fix

**S1. The PRECONDITION block (`:246-253`) does not list the two r4 constraints.** It says a new CHECK or NOT NULL fails on a database with rows and names five cases; r4 adds two more that fail the apply on existing data: a refund or replacement already citing another customer's (or tenant's) payment, and a locked/void_released read without the flag. Nothing is live, so this is a sentence, not a migration step — but the apply refuses with a bare FK/CHECK violation and no row list, so a reader of the precondition should know to look. Add the two to the list.

**S2. Say the "finish in one write" contract where the import worker will read it.** The function comment `:1154` and the header `:131-132` describe the snapshot; neither says that a job finished in two statements (status, then `completed_at` or summary) is refused (XJ13). One clause in R13 or R9: "the finishing write carries the final status, counts, file, summary, errors and `completed_at` together; nothing on the job is written after it except staging rows and the follow-up columns". Low.

## Notes

- N1. XF6/XF6b: two pending refunds may cite each other. The not-self CHECK stops the 1-cycle only. Representable, harmless to money (both negative, both pending), the core's arithmetic. Not worth a trigger.
- N2. XF4/XF4b: moving a parent and its child in one statement is accepted because the BEFORE trigger sees earlier rows of the same command; the acceptance is order-dependent in principle (a child processed before its parent would be refused by the trigger). Both orders I tried passed; the three-step path always works. No change needed.
- N3. With tenant and customer in the FK, `enforce_payment_lineage` is now redundant except for RLS visibility and its message. Keep it — the message names the pointer and the customer, which the FK's does not — but its comment `:708-709` could say the FK is the guard and the trigger the visibility check.
- N4. XJ10: `column_mapping`, `ai_extraction_log`, `mapping_*`, `started_at` remain writable on a finished job. Not claimed by the header; fine.
- N5. XF3c: a pending payment's tenant move is refused by RLS (42501) before any lineage guard; the FK would refuse it too for a cited row. Nothing to change.
- N6. The race script's PASS for C8 depends on a 3-second hold and a 10 × 0.15 s poll; on a loaded machine the poll window (1.5 s) is inside the hold. Same as C1–C7.

## Probe transcript (abridged)

ACCEPTED: XF1, XF1b, XF2, XF3, XF3b, XF4, XF4b, XF4c, XF4d, XF4e, XF6, XF6b, XF9c (owner multi-row load), XF9d (DISABLE TRIGGER), XM2 (owner locked WITH flag), XM4 (replica mode set), XJ10, XJ11, XJ12, XJ14.
REFUSED: XF1c, XF2b, XF2c, XF7, XF9b (23503, lineage trigger message); XF9 (23503 `payments_nsf_original_payment_id_fkey`); XF9e, XF9f (23503 `payments_refunds_payment_id_fkey`, trigger off); XF3c (42501 RLS); XM1, XM4b (23514 `meter_readings_consumed_flag_check`); XM3, XM4c (23001 Block 2); XJ8, XJ9, XJ13, XJ15 (23001 naming `completed_at` / `validation_errors`).
Reverse race (`fable19r`): A `UPDATE … customer_id = C2` holds; B's refund INSERT seen blocked by A, then refused 23503 `payments_refunds_payment_id_fkey`.
