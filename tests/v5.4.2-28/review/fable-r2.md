# Fable review — v5.4.2-28 r2 (rates small fixes)

**Date:** 2026-11-04. **Reviewer:** Fable (Claude Fable 5.1), independent; `opus-r2.md`, `codex-r2.md` and `codex-r2-probes/` not read. Read: the r2 brief, my `fable-r1.md`, the r2 plan, the five frozen files, the r1→r2 patch diff.
**Frozen files:** all five md5s match the brief (executed). The live copies (`sql/v5.4.2-28-rates-small-fixes.sql`, `tests/v5.4.2-28/battery-28.sql`, `mutations-28.sh`, `races/past-cycle-28.sh`) hash the same as the frozen ones today (executed). Scratch database `rv28fable` (TEMP revoked from PUBLIC, `tally_app`, `tally_core`; frozen r2 strict-applied), dropped at the end; two throwaway clones (`rv28fable_restore`, `rv28fable_r1`) were created for the dump/restore and the round-1 race and dropped.

## Verdict: **ready**

No blocking item. Two should-fix items, both in the tests and both small (a mutation the brief asked about, and a widening of the reparse scan). Each claim is marked **executed** (run on `rv28fable`) or **predicted** (from reading).

## What I reproduced (executed)

- **Strict apply, twice** (`search_path=`, `check_function_bodies=on`): clean both times; the second run is a no-op in effect.
- **`battery-28-frozen-r2.sql`** on `tally` + -28: 99 PASS, "all checks passed".
- **`past-cycle-28-frozen-r2.sh`** against `rv28fable` (r2): P1, P2, P3 pass, with the script's own check that session 1 started before session 2's close (start 17:10:15.100 < close 17:10:15.927). Against a fresh clone with **frozen r1** applied: FAIL P1 (A on B admitted), FAIL P2 (9 instants hold both links), and P3 fails as a consequence. The race discriminates the two rounds.
- **REPEATABLE READ variant of the race** (my own, on the race's committed fixtures): session 1 at REPEATABLE READ takes its snapshot, session 2 retracts the open link and commits, session 1 inserts the reverse link: session 1 fails with `could not serialize access due to concurrent update` at the header bump (`UPDATE public.rate_schedules ...`), and no cycle is recorded. The row-version mutex does what the comment says at that isolation level too.
- **Dump and restore:** `pg_dump -Fc` of `rv28fable`, `pg_restore` into a fresh database: exit 0, no errors; 137 tables, 1365 constraints, 555 functions, 474 triggers on both sides; the deparsed text of `rate_item_versions_tier_rates_four_decimals_check` and of the exclusion constraint `rate_item_dependencies_open_no_overlap_excl` is byte-identical (md5) before and after.
- **Mutation anchors:** every `old` text of N1–N23 (and the two EXTRA edits of N15) occurs exactly once in the frozen r2 patch (counted, not run; the brief forbids running `mutations-28.sh`).
- **Round-2 fixes on the running schema** (my probes, one rolled-back transaction on the battery's fixtures): see B1–S2 below.

## Blocking items

None.

## Should-fix items (tests only; no patch change)

### S1. Add the cross-tenant child fixture and mutate the tenant filter in the zone read (the brief's open question; executed)

The brief asks whether `c.tenant_id = v_inv.tenant_id` in `invoice_time_zone_as_of` should be mutated. It should, because the schema admits the row that makes the filter matter: as `tally_app` of a second tenant I inserted a draft invoice with `parent_invoice_id` = tenant 1's consolidated parent (battery bill 10, El Paso + Hudspeth) — **admitted** (the parent FK is single-column and bypasses RLS; nothing on `invoices` requires a child's tenant to be its parent's). The owner can write the same row. With the filter in place the parent still reads `America/Denver` (executed, Q7b); with the filter removed the Austin child would join the agreement and the parent would be refused as two-zone, or, with a Mountain foreign child under an Austin parent, agree wrongly. The fixture is five statements (a tenant, a user, a customer, a premise with a Travis membership, the child). Mutation: anchor the `WHERE c.parent_invoice_id = v_inv.id AND c.tenant_id = v_inv.tenant_id AND c.status <> 'void'` line of the count query (it occurs twice in the function — once in the count, once in the zone subquery — so anchor with its preceding line, or mutate both via EXTRA), expected at a new Z5 case ("a child of another tenant does not count"). Lesson: `checks-narrower-than-their-claim`.

(That a child can be attached under another tenant's parent at all is an `invoices` matter, the money stream's — see N6.)

### S2. R6 scans CHECK constraints only; include the exclusion constraint (predicted; the restore itself executed clean)

`R6` reads `pg_constraint` with `contype = 'c'`. `pg_dump` writes the exclusion constraint and the partial indexes from `pg_get_constraintdef` / `pg_get_indexdef` by the same mechanism, and -28 adds one of each kind. Today the real dump/restore covers them (executed, above), but the battery is what runs every time. Adding `'x'` to the `contype` filter costs one character and the `ADD CONSTRAINT` path already handles it (`pg_get_constraintdef` of an EXCLUDE prints `EXCLUDE USING gist (...) WHERE (...)`). Indexes would need `CREATE INDEX` on the scratch table instead; optional. The `n < 10` floor stays right (there are more than ten CHECKs on the four tables).

## Notes

### N1. Each round-2 fix closes its finding (executed unless marked)

- **B1 (dump):** the stored form is `(@ * 10000) % 1 != 0` (R6b) and reparses (R6); the real restore is clean (above). Mutation N23 puts the old form back; the mutant patch applies (the CHECK is accepted on definition) and only R6 catches it, which is the right place.
- **B2 (reason):** `closed_reason IS NOT NULL AND closed_reason ~ '[[:alnum:]]'`; D7a–D7a8 cover both close kinds and each way of saying nothing. N18 removes the NULL leg; D7a (a blank, regex false) still refuses, so D7a2 (the column left out) is the first FAIL — the named check.
- **B3 (consolidated parent with a premise):** the branch is `is_consolidated`. Executed beyond the battery: a consolidated parent whose **own premise has no answerable zone** (the no-county premise D4) over El Paso + Hudspeth children is refused with `no time zone can be read` (`premise_time_zone_as_of` raises inside the UNION ALL, as the brief expects); a `write_off` child counts as live. The union is right: `premise_time_zone_as_of` never returns NULL (it raises), so no NULL enters `array_agg(DISTINCT ...)`, and a one-element array is the answer.
- **B4 / L6:** stated, no code; Ryan's call.
- **S1 (the walk):** `recorded_until > NEW.recorded_at`. `NEW.recorded_at` is always the transaction start when the walk runs: the row guard (sorted first) overwrites a supplied value with `now()`, and an omitted one takes the column `DEFAULT now()`; a NULL fails NOT NULL (executed: Q5a; battery D2d/D2e). A close in the same transaction stamps `recorded_until := now()`, equal, so `>` excludes it: close B on A then insert A on B in one transaction is admitted (executed, Q5b; battery D8/D8c). A row closed by a transaction that **started after** NEW's and committed before NEW's insert carries `recorded_until` > NEW's start and is counted (the race's P1). A row closed by a transaction that started **before** NEW's and committed after NEW's start is not counted, and that is right by the stamps: its `recorded_until` precedes NEW's `recorded_at`, so no as-of instant holds both; the real-world window where it was still visible open is the A-1 "keep correction transactions short" caveat stated on the row guard, not -28's. Under REPEATABLE READ the header mutex turns the race into a serialization failure (executed, above). I found no row the predicate keeps out that it should count, or counts that it shouldn't.
- **S2 (NaN):** R1e, R3c, R5c; mutations N19, N20.
- **S3:** comment only, as settled.
- **S4 (tests):** D7c is now sound: the back-date sits directly before the close and the check reads the header before D7b's insert bumps it; N21 (the close-path bump removed) is caught there. The runner's "wrong check" fail is in place; no mutation declares an alternate. K3b and K-del relabelled; D3c says what it proves.
- **Percentage rates (AC-45):** see N2.
- **The zone read stays (2026-11-04):** L1 restated; no code change.

### N2. The two rate checks are airtight by unit (executed)

A five-decimal rate with `rate_unit` NULL or `'percent'` is refused by the general check; with `'decimal'` by the fraction check (`IS NOT DISTINCT FROM` / `IS DISTINCT FROM` are complementary, so NULL falls to the general check and no row meets both). A version's unit cannot change in place: the A-1 row guard on `rate_item_versions` refuses the UPDATE (23001), and it is ENABLE ALWAYS, so `session_replication_role = replica` does not switch it off (executed, my Q3c failed for that reason). Were it ever bypassed, a CHECK is re-evaluated on every UPDATE, so the fraction check would still judge the re-united row (predicted). The override: `rate_override` is checked whatever `rate_unit_override` says, so a fraction override of five decimals is refused — by `rate_schedule_items_rate_override_four_decimals_check`, whose name does not say "store as percent" (its COMMENT does). Airtight; the asymmetry is in the message, not the rule. If the author wants parity, a second override check split on `rate_unit_override` is the same two-line pattern; not needed for the rule.

### N3. R6 does reparse what pg_dump writes (predicted, confirmed by the restore)

`pg_dump` emits each CHECK as `CONSTRAINT name CHECK (...)` from `pg_get_constraintdef`, the same text R6 feeds back through `ALTER TABLE ... ADD CONSTRAINT` on a `LIKE` copy. The round trip is the right test. R6b's `LIKE '%(@ * 10000) % 1 != 0%'` has an unescaped `%` in the middle (a wildcard), so it is slightly looser than its label; harmless, since the old form prints without the parentheses and would fail the pattern anyway, and N23 is caught at R6. Cosmetic.

### N4. Mutations: each caught for its stated reason (predicted from the texts)

N7 (every closed row counted) is caught at D7d because the same-transaction close of C on D (row 03) would otherwise overlap D on C from July 2027; it proves the "same transaction stays out" leg, and the race proves the other leg, as the runner's tail comment says. N15 (the dependency guard renamed to sort first) survives every case up to D11 — with the guard running before the row guard, the walk reads a not-yet-stamped `recorded_at`, which only makes it stricter (a past value counts more closed rows; a future one is overwritten anyway), and the stamps still land — so D11's exact-definition check is the one that pins the order, which is right. N14/N16/N17 each fail at the first case that distinguishes them (Z5h2, Z5m, Z5n), as named.

### N5. Roles and shapes (executed where stated)

`tally_core` has SELECT only on the four tables; `tally_app` has no DELETE on dependencies (D3c) and the owner's DELETE is refused by the row guard (D9e). No statement shape reaches the rules in a different order: the row guard sorts first on INSERT, UPDATE and DELETE, the dependency guard second, the CHECKs after both, the successor check at commit.

### N6. For the money stream, not -28 (executed)

The schema admits an invoice of tenant B as a child (`parent_invoice_id`) of tenant A's consolidated parent, written by `tally_app` of tenant B or by the owner: the FK is single-column and nothing on `invoices` checks the parent's tenant. -28's zone read is immune (the tenant filter, S1). `invoices` is the money stream's; a board note would fit beside L6.

### N7. Known limits L1–L6

None blocking. L1 is Ryan's 2026-11-04 ruling with -29 claimed. L2 stated and tested (D6). L3 now names the race. L4 names the money stream's columns. L5 is -07's. L6 is Ryan's option 1.

## Answers to the brief

1. **Each fix closes its finding** with nothing the ruling did not ask for; the one addition, the fraction-unit check, is Ryan's 2026-11-02 call (AC-45).
2. **No path around a rule** for `tally_app`, `tally_core` or the owner, at READ COMMITTED or REPEATABLE READ, by any statement shape I tried (N2, N5; the race and its RR variant).
3. **Nothing round 1 had right is broken**: the surcharge function still changes only in its zone block (the r1→r2 diff touches `invoice_time_zone_as_of`, the CHECKs, the walk predicate and comments); -19/-21 guarantees carried (r1 N8 still holds; D11 pins the trigger set).
4. **Tests:** no claim narrower than its check that matters (R6b's wildcard is cosmetic, N3); no mutation caught for the wrong reason (N4). Two additions wanted: S1, S2.
5. **L1–L6:** none blocks.
