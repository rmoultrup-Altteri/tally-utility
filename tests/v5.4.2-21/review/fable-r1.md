# Fable review: v5.4.2-21 r1

**Date:** 2026-10-14. **Reviewer:** Fable. **Verdict: not yet** (two blocking items, both in the new rules' own scope; the rest is should-fix).

Hashes checked first, all four match the brief (`0900a47c…`, `da9e3481…`, `12cb39e6…`, `d263033b…`). Everything below was done on a clone `rv21fable` (TEMPLATE tally, TEMP revoked from PUBLIC, tally_app, tally_core), dropped at the end. `tally`, `sql/tu.sql` and every repo file but this one are untouched; no role was created, altered or dropped; `mutations-21.py` was not run.

**Reproduced (executed):** strict apply twice (second run skipped on `users.cognito_sub`); `battery-21-frozen-r1.sql` 103 PASS, "battery-21: complete"; `labels-21-frozen-r1.sh` LR1–LR5 PASS.

Each claim is marked **executed** (I ran it on the clone) or **predicted** (read from the code and catalog).

---

## Blocking

### B1. A label in use is deleted by renaming it first (L1/L2 have a two-statement path around them) — executed

The in-use guard reads `OLD.field_key` against `OLD.entity_type`'s table (and `OLD.type_key` against `service_locations`). Nothing guards an UPDATE of those columns, and `tally_app` holds table-level UPDATE on both label tables. Three repros, all as `tally_app` under `app.user_id`, with `acct_color` set on customer C1 and `kiosk` on location L1:

| | statements | result |
|---|---|---|
| sanity | `DELETE … WHERE id = f1` | refused 23001 "label acct_color is in use on customers" |
| E1b | `UPDATE custom_field_definitions SET field_key = 'acct_color_x' WHERE id = f1; DELETE … WHERE id = f1` | **admitted**; afterwards 0 definitions for `acct_color`, 1 customer still carrying the key |
| E1c | `UPDATE … SET entity_type = 'billing_runs' WHERE id = f1; DELETE …` | **admitted** (the guard sees a table with no `metadata` and returns OLD) |
| E1d | `UPDATE custom_location_types SET type_key = 'kiosk_old' WHERE id = f4; DELETE …` | **admitted**; 1 location still typed `kiosk` |

The rename alone (E1e) is also admitted, which is the same loss without the delete: the row that defined the key in use is gone from under the values. CI-014's rule is "a delete is refused while anything still uses the label"; the label is its key, not its row id.

Fix, either shape (Ryan's call, both small):
- **Keys write-once.** A BEFORE UPDATE guard on `custom_field_definitions` (`tenant_id`, `entity_type`, `field_key`) and `custom_location_types` (`tenant_id`, `type_key`): any change refused; a renamed label is a new definition plus an `archived` old one. Simplest and matches "archive it" in the guard's own message.
- **Or** fire `enforce_custom_label_unused` BEFORE UPDATE OF those columns too, when the value changes, with the same lock and the same OLD-based check. Lets an unused key be renamed.

Either way add the trigger to the retention invariant's exact-definition list, a battery row (rename in use refused; rename unused admitted if shape 2), and a mutation.

### B2. A surcharge whose rate item has no version at the bill's coordinate needs nothing — the "fail safe" of A4 is not implemented — executed

`invoice_line_arithmetic_gap`: `v_per_unit := coalesce(v_calc IN ('per_unit_usage', 'tiered_usage'), false)`. When `rate_item_as_of(item, period_end, now())` returns no row, `v_calc` is NULL and the line is treated as a fixed surcharge. The inventory's A4 says the opposite: "a line that cannot be classified cannot be shown to need nothing; fail safe".

- E3a: a surcharge line on item A (no versions at all): gap = NULL. E3b: with `enforce_invoice_line_arithmetic` and `enforce_invoice_surcharge_lines_and_bases` set IMMEDIATE, the move to `pending` is **admitted** — the surcharge sibling (`assert_surcharge_line`) also returns when it finds no regulatory rule, so nothing refuses it.
- E3c: item PU is `per_unit_usage` from 2026-01-01. The same line evaluated at `period_end = 2025-12-31` (a bill for a period before the item existed) needs nothing; at 2026-01-31 it needs all seven figures.

So a per-unit rider billed for a period in which its item had no version passes with only `rate_item_id`. Fix: in the surcharge branch, `IF v_calc IS NULL THEN RETURN format('rate item %s has no version at (%s, now()) — it cannot be classified', …)`. `calculation_type` is NOT NULL on `rate_item_versions`, so NULL means exactly "no version". Add a battery row (A4g) and a mutation (drop the IS NULL branch).

---

## Should-fix

### S1. The deadlock note is narrower than the deadlock — executed

Header: "the two cannot deadlock, except a transaction that writes the entity table and then deletes **the same label** as another delete". Two sessions each INSERT a customer, then each DELETE a **different** label of `customers`: B fails with 40P01 deadlock detected (my `fable-deadlock.sh`, A exit 0, B exit 3). Both hold ROW EXCLUSIVE on `customers`; each asks SHARE, which conflicts with the other's ROW EXCLUSIVE. Say: "two transactions that each write the entity table and then delete any label of that entity deadlock; one is cancelled, retry it." Not a correctness hole (a cancelled participant deletes nothing), but the header is the document the app team reads.

### S2. No invariant watches the three new guards' ENABLE ALWAYS — executed

`ALTER TABLE … ENABLE TRIGGER` (origin-only) on `a_enforce_adhoc_charge_born_unvoided`, `a_enforce_user_cognito_sub_write_once` and `enforce_invoice_line_arithmetic`, then all four invariants: **all pass**. -20 put its guards into `assert_seal_role_invariants`'s exact-definition list; -21's G6, U1 and A1 guards are in no list. The battery runs as origin, so a mutation dropping an `ENABLE ALWAYS` line passes 44/44 too. Likewise (E11b) `DISABLE TRIGGER no_truncate` on `custom_location_types` passes `assert_no_hard_delete_invariants()`: L5 is claimed in the patch header ("both guards ENABLE ALWAYS") and D4 says the invariant checks "L's guards", but only `a_enforce_custom_label_unused` is checked. Add the four trigger definitions (three new guards, the labels' `no_truncate`) to a list in `assert_no_hard_delete_invariants` or a new `assert_wave1_guard_invariants`, and one mutation per ENABLE ALWAYS line.

### S3. R2 is wider than the header says, and cheap to narrow — executed

As `tally_app`: a `void_reversal` naming a **payment** entry (E7a), a `void_reversal` on customer C1 naming **C2's** charge (E7b), and **two** `void_reversal`s naming the **same** charge (E7c) are all admitted. The CHECK proves only that *some* same-tenant row is named. CI-017 is "every reversal that undoes one thing names **it**". What a trigger-free pair buys now: `UNIQUE (reverses_ledger_entry_id) WHERE transaction_type = 'void_reversal'` (one reversal per charge; it also makes R1's "several charges, one reversal" visible rather than silent), and, if Ryan wants it, binding the FK to `(id, tenant_id, customer_id)` as the payments FKs already do. "The named entry is a charge" needs a BEFORE INSERT trigger; its absence can stay a residual if stated as such.

### S4. A4 read literally makes a gas rider carry the commodity rate — predicted, for Ryan

On a `gas` per-unit surcharge the check requires `gas_meter_factor`, `gas_ccf_used`, `gas_therms_billed` **and** `gas_commodity_rate`. The first three are meter figures a therm-based rider legitimately repeats; `gas_commodity_rate` is the usage line's rate, not the rider's — the rider's arithmetic is `usage_quantity × rate`. The brief flags A4 as a drafting call; I read the decision's "as for usage_charge" as the quantity/unit/rate rule plus the gas *quantities*, and would drop `gas_commodity_rate` from the surcharge branch. If Ryan keeps the literal reading, say so in the function comment so a future line writer is not surprised. Battery A4e/A6 cover whichever is chosen.

### S5. Tests and mutations missing (Q7) — predicted unless noted

- No test for B1 or B2 (above).
- **INSERT born issued** has no row and no mutation. It is moot for the app (E4a, executed: a line cannot be inserted on a bill born `pending`, so the check passes vacuously), but a superuser load of a `void` or `pending` bill with legacy lines **is** checked (the gate exempts only an UPDATE to void). State that in the comment and give it one row, or exempt a superuser INSERT as `first_issued_at` does.
- The payments FK triple (`refunds_customer_credit_fkey` customer-binding) has a battery row (G4c) but no mutation; M30 covers only the ledger FK.
- `V1d the refused void wrote nothing` is tautological: an exception rolls the function back whether the check sits before or after the writes. The claim "refused before anything is written" is a property of the code order, not testable this way; relabel it or drop it.
- `G7` counts five index names and never checks their columns; M35 catches a dropped index, not a wrong one. Check `indexdef`.
- Known gaps acknowledged in the brief (issued→issued gate, FOR SHARE) stand.

### S6. `assert_no_hard_delete_invariants` claims vs checks (Q6) — predicted

Catches what it claims for D1/D2 (exact triggerdef, ENABLE ALWAYS, tally_app's DELETE/TRUNCATE set). Narrower than its comment in two places: L5's `no_truncate` on the label tables (S2, executed), and "for every role" in the header — the invariant looks at `tally_app` only; `tally_core` is the core invariant's and PUBLIC the seal invariant's, which is fine, but say so in the comment.

---

## Notes

- **N1. Retention cascades (Q2) — executed.** `DELETE FROM tenants` with an `alerts` row: refused 23001 by the cascaded delete's `no_hard_delete` (E6b). `session_replication_role = replica` as the owner: refused (E6c, ENABLE ALWAYS works). No function in `public` DELETEs from or TRUNCATEs any of the 18 tables (catalog grep); no rules exist; the only definers are the two RLS helpers and the three sealed functions. `tally_app` has no DELETE on `users`, `tenants`, `customers` either, so "delete the user and recreate it with a new sub" is closed. A consequence worth a line in the header: `tenants`, `customers` (via `auto_pay_settings`) and `read_cycle_instances` (via `read_cycle_meters`) can no longer be deleted once a retained child exists — correct, but it changes those tables' effective rule.
- **N2. The label lock (Q4) — executed/predicted.** `tally_app` holds UPDATE on all ten `entity_type` tables, so `LOCK TABLE … IN SHARE MODE` is permitted (UPDATE suffices). SHARE also conflicts with SHARE UPDATE EXCLUSIVE: a label delete waits behind a running autovacuum of `customers`/`invoices`, and autovacuum cancels itself when it blocks one — fine, but a manual `VACUUM`/`ANALYZE`/`CREATE INDEX CONCURRENTLY` on the entity table is a blocker in both directions. L4 holds: a platform admin's DELETE sees all tenants' labels and the guard filters by `OLD.tenant_id`; a caller with no user deletes zero rows (RLS) and the trigger never runs. Values are top-level keys (`validate_custom_fields` reads `p_metadata -> field_key`), so `metadata ? key` is the right test.
- **N3. The void and the stamp (Q3) — executed.** For app-written bills "posted" is exactly `first_issued_at`: `enforce_invoice_first_issued` NULLs it on a non-superuser INSERT, forbids a non-superuser write, and stamps the first move into an issued status other than void; no backward transition exists. A superuser load can break it both ways: E12a/b, a bill inserted born `pending` with no stamp is voided as a discard (no refusal, no ledger row). battery-19's I4 and seal-20's H3 now set the stamp by hand for that reason — worth a sentence in the void's comment ("a superuser load that posts a bill sets `first_issued_at`"). E12c: two charge entries, the earlier `created_at` is named and the amount is `-(amount_due)` (R1 as described). The lookup filters tenant but not `customer_id`; the ledger is append-only (`enforce_account_ledger_immutable`), so a charge filed under the wrong customer is a core bug the void would then name — acceptable with R1. `created_at` is stamped by `a_stamp_created_at`, so the ORDER BY is sound. RLS as `tally_void`: the SELECT runs under the caller's `app.user_id`, same policy that found the bill. `assert_seal_role_invariants()` passes after the replacement (battery V3; grants unchanged: SELECT on `account_ledger` was already granted).
- **N4. The arithmetic gate (Q5) — predicted.** Gated identically to `enforce_invoice_has_snapshot` and the surcharge check (issuance only; issued→issued skipped; UPDATE to void skipped). `(period_end, now())` is the siblings' coordinate for classification (`line_item_carries_base` uses it); a version written in the same transaction is seen (`recorded_at <= now()`), which is the rule, not a hole. Lines cannot be added or changed after the gate (E4a; `enforce_invoice_line_items_immutable` reads the invoice's current status in-transaction). SET CONSTRAINTS IMMEDIATE/DEFERRED only moves the check; it cannot skip it.
- **N5. Older tests (Q7) — predicted.** Each change keeps its purpose: battery-10/-11/-13 lines now carry rate (and gas figures); F11a moves to insert and still proves "correction without link refused" (23514 both before and after); battery-19 Q4d expects 23001 and Q4f/Q4h retire-and-re-add, which still exercises the acyclic edit and the lone-edge reversal; C8 expects 42501 with the 23001 guard behind it. One thing to know: battery-20's I1 (line 317) still has a `base_charge` line with no `rate` and is moved to `pending`; it passes only because `SET CONSTRAINTS ALL DEFERRED` precedes it and the battery rolls back, so the deferred arithmetic check never fires. Give it a rate now, or the next `SET CONSTRAINTS ALL IMMEDIATE` added below it fails for a reason unrelated to the -20 case.
- **N6. Mutations — predicted.** 44 named checks read right. M36 (`IF false` on the not-found branch) is caught at V1c, but by `account_ledger_void_reversal_lineage_check` (23514 instead of P0002), not by the function: the explicit check is a better message on top of the CHECK, which is fine, but the first-FAIL rule makes the mutation pass for the CHECK's reason. Also `invoice_line_arithmetic_gap` is executable by `tally_app` (REVOKE lists PUBLIC and tally_core only) — intended as a preflight? Say so, or revoke like its siblings.
- **N7. K — executed.** `retired_by` accepts another tenant's user id (E15 admitted; the FK bypasses RLS and the trigger does not check it). Low value to an attacker, but the -19 insert path checks every FK target's tenant; mirror it for `retired_by`, or drop the column in favour of `app.user_id` stamped by the database (the pattern R1 just adopted).
- **N8. U2 — predicted.** Every policy uses the two helpers except `invoice_events_insert`, which uses them too in `with_check`. `session_is_supervisor()` goes through `is_platform_admin()` and `get_user_tenant_id()`, so a deactivated supervisor is none. No other helper reads `app.user_id` for a policy.
- **N9. R1–R5 (Q8).** None blocking. R2 is wider than stated (S3). R1's "earliest entry" is sound given `a_stamp_created_at`. R3, R4, R5 as described.
- **N10. D0.** "17 listed as 16": the list is the authority; the catalog agrees. Fine.

---

## What I ran

- `rv21fable`: clone, REVOKE TEMP, strict apply ×2, frozen battery (103 PASS), frozen races (LR1–LR5 PASS).
- `fable-probes.sql` (one rolled-back transaction, `pg_temp.try` wrapper): E1a–f, E3a–d, E4a, E6b–d, E7a–c, E11b, E12a–c, E15. `fable-deadlock.sh`: E5 (two sessions). A separate transaction for E11 (origin-only guards vs the four invariants) and for the G6 UPDATE path (refused 23001 by `enforce_adhoc_charge_immutable`, -20).
- Clone dropped.
