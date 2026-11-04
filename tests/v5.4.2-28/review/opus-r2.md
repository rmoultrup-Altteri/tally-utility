# v5.4.2-28 r2 — Opus review

**Date:** 2026-11-04. **Verdict: ready.** No blocking items. Two should-fix items, both test-only, neither needed before mirror.

Frozen md5s checked first: all five match the brief (executed). Scratch clone `rv28opus` (TEMP revoked from PUBLIC, tally_app, tally_core), frozen r2 patch strict-applied twice: clean (executed). `battery-28-frozen-r2.sql`: 99 PASS, "all checks passed" (executed). `past-cycle-28-frozen-r2.sh rv28opus`: P1, P2, P3 PASS (executed). Clones `rv28opus`, `rv28opus_r` (restore target) and `rv28opus_l` (fresh tally + r2, for -21's race) dropped at the end; container /tmp files removed. I did not run `mutations-28.sh` or `ci.sh`.

## 1. Does each round-2 fix close its finding?

- **B1, dump and restore (my r1 B1): closed (executed).** The stored text is `... (@ * 10000) % 1 != 0` and reparses. I ran my own `pg_dump -Fc` of the patched clone, after committing nine dependency rows (open, closed, retracted) from the races, and restored it into a fresh database: **0 errors**. The counts match: 137 tables, 1365 constraints, 555 functions, 474 triggers, 731 indexes, and all 9 dependency rows. `assert_wave1_guard_invariants()` holds on the restored copy, and battery-28 gives 99 PASS there too. Rows that a CHECK admits restore because pg_dump creates triggers, exclusions and foreign keys after the data.
- **B2, a close with no reason: closed (executed).** D7a2–D7a8 pass. The NULL leg is named in the close branch. -21's K1 and K3b still pass.
- **B3, a consolidated parent with its own premise: closed (executed).** The branch reads `is_consolidated`, which is `NOT NULL DEFAULT false`, so a NULL never takes the wrong branch. My extra probes:
  - PZ1, a consolidated parent whose own premise has no zone, over an El Paso child: refused P0002 by `premise_time_zone_as_of`. The brief says it should be.
  - PZ6, a non-zero fee on that parent: refused P0002.
  - PZ4, a parent that names itself as its own parent: refused as a nested child.
- **B4 / L6:** recorded as a limit with the money stream's rule (board note present). No code was asked for, and none was added.
- **S1, the long transaction: closed (executed); see section 2.**
- **S2, NaN: closed (executed).** R1e, R3c and R5c pass. Infinity is refused by `numeric(14,6)`.
- **S3:** comment only, as the plan says.
- **S4:** D7c is now taken before the successor's insert. The runner refuses a catch at the wrong check. Labels are renamed. See section 4 for the mutations.
- **AC-45, the fraction split:** matches the 2026-11-02 ruling, and adds nothing beyond it.

Nothing was added that a ruling did not ask for. One mild case: B3 also compares the parent's own premise, which the plan asked for. Under L1, a parent whose own premise sits in a county with no zone loaded refuses even when its children agree (PZ1). That is consistent with "refuse, never assume".

## 2. Paths around a rule

**The cycle walk's new predicate `recorded_until > NEW.recorded_at`.** Every case below was run with two committed sessions on my clone:

| Case | Expected | Got |
|---|---|---|
| READ COMMITTED: S1 begins, S2 retracts B on A and commits, S1 inserts A on B | refused | 23514 "closes a cycle" |
| REPEATABLE READ, S1 takes its snapshot before S2 commits | refused | 40001 at the header bump |
| REPEATABLE READ, S1's first query after S2's commit (now() early, snapshot late) | refused | 23514 by the new predicate (r1's walk would have admitted it) |
| SERIALIZABLE, same as above | refused | 23514 |
| S2 begins and closes early (stamp before S1's start) but commits late; S1 waits on the header | admitted, no over-refusal | admitted; the as-of read shows no instant holding both links |
| One transaction: retract A on B, then insert B on A | admitted | admitted; as-of now shows only B on A |
| One multi-row INSERT with both halves; two data-modifying CTEs; a three-link cycle across a CTE | refused | 23514 each |

On the transaction-time axis the predicate is exact. NEW is known over `[NEW.recorded_at, ∞)`, and a row overlaps that span exactly when `recorded_until > NEW.recorded_at`. It counts one thing it need not: a row born and closed by another transaction that began after NEW's, which is a zero-length span. That refusal is harmless, and a retry with a fresh now() passes (predicted; see N1).

**The rate checks.** Both checks test the same predicate, `<> 'NaN' AND = round(..., 4)`, and their guards are complements: `IS NOT DISTINCT FROM 'decimal'` and `IS DISTINCT FROM 'decimal'`. Every row therefore meets exactly one of them, and a NULL unit falls to the general check (PR8, PR9 executed). Versions are frozen even for the owner: an in-place change of `rate_unit` or `rate_value` is refused 23001 (PR13, PR14 executed). tally_core has no INSERT on `rate_item_versions` (PR12, 42501). The override's unit may come from `rate_unit_override`, but its check covers every unit, so nothing slips through. Only the message differs (N3).

**Roles.** tally_app and tally_core meet every guard, and the row guard is ENABLE ALWAYS. Only a superuser can set `session_replication_role`. No new grant to PUBLIC: Z7 and D10 pass.

## 3. Did round 2 break anything round 1 had right?

No (executed where shown).
- Battery-28: 99 PASS.
- -21's race `labels-21.sh` on a fresh tally + r2: LR1–LR7 PASS, including LR4/LR5, the dependency legs. AR1 fails at setup on a column that a pending money patch adds; that is the base, not -28.
- -19's race: C4 "exactly one half of each cycle stored" PASS. Its other failures are money-patch fixtures (payments).
- Batteries -19 and -21 need the money stream's pending patches in the base (`regulatory_class`, `remaining_amount`), so I could not reproduce them on tally + -28 alone. I rely on the author's `ci.sh` result for those two (predicted).
- -21's ported K and LR cases keep their meaning. LR4 now also refuses a B that began before A's retirement was stamped. That refusal is correct (the two links were known together at an instant) and is retried.

## 4. The tests

- **R6 covers the CHECKs of four tables only**, under the battery's search_path. pg_dump writes the same `pg_get_constraintdef` text, schema-qualified, and jsonpath printing does not change with that. R6 does not cover exclusion constraints, index definitions, defaults or triggers. My full dump/restore shows those are fine today, so it does not matter for -28 (see S2).
- **The mutations each hit their rule for the right reason (predicted, by reading each anchor against the battery).**
  - N7 removes the predicate and is caught at D7d, where row 03, closed in this transaction, would block D on C. A `>=` mutant would also be caught there. The r1 form (`IS NULL`) is caught only by the race, which the author ran against r1.
  - N15 is caught by D11's trigger-text check, which is its intended check. Behaviourally the reversed order only over-refuses (the walk would read a caller-forged `recorded_at`), so no earlier case should fail.
  - N21 is now real: nothing bumps the header between the back-date and the close.
- **Gaps (N4):**
  - The fraction check has no NaN-leg or five-decimal mutation of its own; only N22 voids it whole.
  - The parent branch's tenant filter is not mutated (S1).

## Blocking

None.

## Should fix

### S1. Mutate the parent branch's tenant filter, with a cross-tenant child fixture (executed: the shape is writable by tally_app)

The brief asks whether the filter should be mutated. Yes, because the shape it guards can actually be written. **PX1 (executed):** tally_app of tenant T3, with its own customer and premise, inserted a child invoice whose `parent_invoice_id` is T1's parent B28-10. It was accepted: the single-column foreign key bypasses row-level security. That is the class the planned cross-tenant link patch (CI-116) closes, not -28.

Today the filter keeps -28's read consistent. **PZ3 (executed):** a parent with an Austin child plus a cross-tenant El Paso child reads America/Chicago for the owner, tally_app and tally_core alike. Without the filter, the owner, and a platform-admin session (whose row-level policy sees every tenant, predicted), would get 21000 instead.

The fixture is two owner rows and one `ok()` as the owner. The mutation drops `AND c.tenant_id = v_inv.tenant_id` from both children queries. Not blocking.

### S2. Make the reparse guard schema-wide, or put the dump/restore into CI (predicted)

R6 protects the four tables -28 touches. The lesson's failure mode (a CHECK that does not reparse loses its table on restore) applies to any future CHECK on any table. Scanning every CHECK in `public` costs a little more and needs no list of tables. Better still, a `pg_dump -Fc` / `pg_restore` step in `ci.sh` covers exclusions, indexes and function bodies too. Not blocking: today's full dump/restore is clean (executed).

## Notes

- **N1. A zero-length row counts in the walk (predicted).** A row born and closed by another transaction that began after NEW's has `recorded_until > NEW.recorded_at` but was never visible at any instant. NEW is refused, and the retry passes. Harmless; not worth a predicate.
- **N2. Isolation levels (executed; table above).** REPEATABLE READ and SERIALIZABLE either fail 40001 at the header or, when the snapshot comes after the close, are refused by the new predicate. Both are safe.
- **N3. A fraction-unit override is refused under the general name (executed, PR11).** `rate_override` 0.01997 with `rate_unit_override = 'decimal'` is refused by `rate_schedule_items_rate_override_four_decimals_check`, whose message does not say "store it in percent". The constraint comment does. A CHECK cannot read the inherited unit (`COALESCE(rsi.rate_unit_override, ri.rate_unit)`), so a split by `rate_unit_override` alone would be partial. Leave as is, or add the hint to the comment the app maps.
- **N4. Mutation gaps.** The fraction check's NaN leg and its `round(..., 4)` have no mutation of their own (N22 removes the whole check). Each is a one-line addition.
- **N5. A tier rate wrapped in a one-element array passes (executed, PR1).** `"rate": [0.5]` is admitted, because lax-mode jsonpath unwraps the array. `[0.12345]`, nested tier arrays, negative five-decimal rates and `1e-5` are refused (PR2–PR5). `1.5E+2` and a 30-digit rate of four decimals are admitted (PR6, PR7). The old r1 form had the same lax semantics (predicted), so this is not a regression; tier shape is the shape check's job (S3 ruling).
- **N6. Z5n's message reads "its child invoices' premises span more than one time zone"** when the disagreement is the parent's own premise against its one child. A wording fix only.
- **N7. A non-consolidated invoice with children reads its own premise (executed, PZ2).** `invoices` lets a bill that is not flagged consolidated have children. -28 reads by the flag, which is right. Whether such a bill should exist is the money stream's question.
- **N8. A negative fee line on a state agency's bill is refused (executed, PZ5).** -07's `amount <> 0` semantics are kept.
- **N9. Known limits L1–L6.** None blocks. L1 is Ryan's 2026-11-04 call, with the counties loaded in -29. L3 is now accurate: the race covers the long-transaction case. L6 is on the board for the money stream.
- **N10. Lessons.** `jsonpath-check-must-reparse` and `check-passes-null` are in the PATCH-LESSONS index with their sections.
