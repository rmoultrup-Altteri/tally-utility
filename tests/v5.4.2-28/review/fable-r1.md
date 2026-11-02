# Fable review — v5.4.2-28 r1 (rates small fixes)

**Date:** 2026-11-02. **Reviewer:** Fable (Claude Fable 5.1), independent; `opus-r1.md`, `codex-r1.md` and `codex-r1-probes/` not read.
**Frozen files:** all four md5s match the brief (executed). Scratch database `rv28fable` (TEMP revoked from PUBLIC, tally_app, tally_core), dropped at the end.

## Verdict: **ready**

No blocking item. One should-fix in the tests (a battery claim the battery does not check, with a mutation the runner would miss), one small hole in the new four-decimal check, and notes. Each claim is marked **executed** (run on `rv28fable`) or **predicted** (from reading).

## What I reproduced (executed)

- Strict apply (`search_path=`, `check_function_bodies=on`) twice on a clone of `tally`: clean both times; the second run is a no-op in effect.
- `battery-28-frozen-r1.sql` on `tally` + -28: 77 PASS, "all checks passed".
- Re-apply with rows present: after the race scripts committed 4 dependency rows (1 closed), the frozen patch strict-applied again cleanly (the exclusion constraint, CHECKs and triggers rebuilt over live rows).
- `cycle-19.sh` and `labels-21.sh` against `rv28fable` (`tally` + -28 only): every dependency case passes — C1 (READ COMMITTED: second half of a cycle waits, then refused), C2 (REPEATABLE READ: fails to serialise), C4 (one half stored), LR4 (B on A while A on B is being closed: waits on the header, then passes), LR5 (re-add while the reverse is open: refused). C8/C9 and AR1 fail on `payments_refund_is_refund_check` / `assert_reference_version` setup — the payments sections, which need -23, as the brief says. Not a -28 matter.
- The body of `assert_surcharge_line` differs from -08's (tu.sql 19846) only in the zone block (diff executed): `v_tz` declared, the one `AND customer_is_state_agency_as_of(...)` turned into the nested IF with `invoice_time_zone_as_of`. Nothing else in -07/-08 moved.
- Callers of the two-argument `customer_is_state_agency_as_of(uuid, date)`: only the two bodies of `assert_surcharge_line` in tu.sql (19429, the -07 copy already replaced by -08's, and 19902, replaced here). Nothing in `application/*.md`, the other patches or the tests calls it. The DROP is safe (strict apply confirms no dependent view).

## Blocking items

None.

## Should-fix items

### S1. Battery D7c claims the close "took the schedule header" but cannot see it (executed)

`battery-28-frozen-r1.sql:289-292` back-dates `rate_schedules.updated_at` to 2000 **before** section D's first insert (D2d). Every insert from D2d to D7b bumps the header to `now()` through the insert path, and inside one transaction `now()` is constant, so by D7c the header already reads `now()` whatever the close path does. The third conjunct of D7c (`updated_at = now()`) is therefore always true.

Proof: I replaced the close-path bump (`patch-28-frozen-r1.sql:421`, `UPDATE public.rate_schedules s SET updated_at = now() ...` inside the `IF OLD.recorded_until IS NULL AND NEW.recorded_until IS NOT NULL` branch) with `NULL;`, applied that patch to `rv28fable`, and ran the frozen battery: **"battery-28: all checks passed"**. The mutation runner has no case for this bump either (N6 mutates `closed_by`, not the header), so a regression that drops the mutex from the close would ship unseen. This is the -21 r2 guarantee LR4 relies on (a close serialises against an insert of the reverse link); the race script does test it, but the race scripts are not in the per-patch mutation loop.

Fix (test only, no patch change): just before the D7 close (`battery-28-frozen-r1.sql:345`), `RESET ROLE; SET LOCAL session_replication_role = replica; UPDATE public.rate_schedules SET updated_at = '2000-01-01' WHERE id = ...; SET LOCAL session_replication_role = origin; SET ROLE tally_app; SELECT set_config('app.user_id', ..., true);` — the same shape battery-21 K5-fixture uses (where the back-date sits directly before the retirement, so K5a is sound). Then add a mutation to `mutations-28.sh`: anchor the 12-space-indented close-path `UPDATE public.rate_schedules` line (unique by indent), expected first FAIL D7c. The lesson is PATCH-LESSONS `checks-narrower-than-their-claim`.

### S2. `NaN` passes the four-decimal rate check (executed)

`rate_item_versions_rate_four_decimals_check` is `rate_value = round(rate_value, 4)`. PostgreSQL's numeric `NaN` equals `NaN`, so `rate_value = 'NaN'` is admitted (executed on `rv28fable` as the owner: accepted; `'Infinity'` is refused, but only by `numeric(14,6)` overflow, 22003). The same holds for `rate_schedule_items.rate_override`. `NaN` was storable before -28, so this is not a regression, but the check now claims "a rate carries at most four decimals" and `NaN` is not a rate with four decimals. One clause closes it: `rate_value IS NULL OR (rate_value <> 'NaN' AND rate_value = round(rate_value, 4))` (and the same on the override). The jsonpath tier check is not affected (jsonb has no NaN).

## Notes

### N1. The tier check reads exactly `$.tiers[*].rate`; other shapes pass by scope (executed)

Probed as the owner on a `per_unit_usage` version (so the tiered-shape CHECK does not interfere): `{"blocks":[{"rate":0.12345}]}` accepted; `{"tiers":[{"tiers":[{"rate":0.12345}]}]}` accepted; a tier with no `rate` key accepted; `{"tiers":{"rate":0.12345}}` (an object, lax-mode wrapped) refused; `{"rate": null}` refused (type is "null", not "number"); `1e-5` refused; `0.12340` accepted (the value is 0.1234); `123456789012.12345` refused. The existing `rate_item_versions_tier_config_required_for_tiered` only requires `tiers` to be an array, so nothing in the schema fixes the tier shape beyond that. The check does what the header says ("each tier's rate"); the header could add that a tier without a numeric `rate` is the shape check's concern, not this one's. Not a defect.

### N2. A close or insert by the owner with no session user stamps NULL (executed)

As the owner with `app.user_id` unset, a close is admitted with `closed_by = NULL` and an insert with `changed_by = NULL`; `close_consistent_check` does not require `closed_by`. `tally_app` cannot reach this (RLS's `get_user_tenant_id()` fails on an empty `app.user_id`). -21's `retired_by` was nullable in the same way, and the other A-1 group-2 tables do the same. Carried, not new.

### N3. The zone read is not serialised against concurrent child-invoice writes (predicted)

`invoice_time_zone_as_of` reads a parent's children with a plain SELECT; no lock. A session writing a fee line on a parent whose live children are all in El Paso, concurrent with another session attaching an Austin child (or un-voiding one), both commit; the parent then spans two zones with a non-zero line admitted under Mountain. The line guard and the issuance gate both call `assert_surcharge_line(..., now())` (tu.sql 19519, 19562, 19838), so the parent is refused at issue rather than at the line write (`cardinality_violation`), and no exempt customer is charged on an issued bill. The brief's question ("can the children change in a way that matters?") — yes, but it is caught later by the same rule; a lock on the children here would be a bill-assembly rule (the money stream's). Acceptable.

### N4. A parent that has its own premise ignores its children (predicted)

`invoices_check` allows `location_id` set on an `is_consolidated` row. `invoice_time_zone_as_of` returns the premise's zone first (`patch-28-frozen-r1.sql:134`) and never looks at the children. That is the ruling's "the bill's premise decides"; stating it in the function comment would save a later reader the question.

### N5. Successor paths (executed)

- A successor that extends A-on-B from [Jan, Mar] to [Jan, open) while B-on-A from April is open is refused as a cycle: the closed predecessor is out of the walk, the open reverse link overlaps. Correct.
- A correction with a different bracket on the same link (predecessor closed as superseded) is admitted; two successors of one predecessor are admitted. The second is A-1-wide (nothing in `enforce_superseded_has_successor` or the predecessor check limits a predecessor to one successor); not -28's.
- A close that also rewrites `changed_by` is refused by the row guard (never edited in place); `closed_type` set without `recorded_until` is refused by `close_consistent_check`; a self-dependency A on A is refused — by the cycle walk's message, which runs before the table CHECK `dependent <> base`. Cosmetic.
- `d.id <> NEW.id` in the walk is dead on INSERT (a BEFORE trigger's row is not yet visible). Harmless.

### N6. Trigger order and the close stamps (predicted, consistent with the battery)

`a_enforce_bitemporal_assertion` < `a_enforce_rate_item_dependency` by name. The row guard stamps `recorded_until := now()` and leaves the closing set (`recorded_until, closed_type, closed_reason, closed_by`) out of its byte-identity test; the dependency trigger then overwrites `closed_by` from the session and bumps the header. A caller can set `closed_by` only together with a close, and it is overwritten (D7c); alone it fails `close_consistent_check` (ported K3b). `changed_by` is outside both the closing and the mutable set, so a caller cannot change it after insert (K4 above) and the insert path overwrites it (D2e). The predecessor check runs inside the row guard on INSERT, before the walk, with the entity key `(schedule, dependent, base)` plus tenant. Nothing relies on the order wrongly.

### N7. Lock order (predicted)

Insert: header then the new row (exclusion index). Close: the dependency row (locked by the UPDATE before its BEFORE trigger) then the header. A close followed by a successor in one transaction takes row, header, then inserts under the held header — consistent. The cross deadlock (one holding the header then closing a row, against one closing that row) is the one -21 stated and the patch restates; PostgreSQL cancels one and the AC says retry. Unchanged.

### N8. The -21 guarantees after the meaning change (executed via the ported batteries' logic and D3/D9e)

No hard delete: the row guard refuses DELETE as the owner (D9e), `tally_app` has no DELETE (D3c; `assert_no_hard_delete_invariants` still lists the table and passes in the patch tail), `tally_core` has SELECT only (probed: INSERT/UPDATE/DELETE denied). Write-once: the row guard, stricter than -21 (even `notes` frozen, D3b). Stamped closer: D7c. The mutex on a close: in the code and in LR4, but not in the battery (S1). The ported K cases map one-to-one: K2 born closed, K3a/K3a2 edits, K3b closer without close (now the CHECK), K1 blank reason (now `close_consistent_check`), K3c/K3e stamps, K5a mutex (sound there), K3d/K3d2 immutability, K4/K4b exclusion, K5/K5b cycle. Nothing lost.

### N9. The jsonpath check is exact (executed)

jsonb numbers are numeric; `@ * 10000 != (@ * 10000).floor()` on `0.43215` gives `4321.5 != 4321` → refused; on `-0.00001` → `-0.1 != -1` → refused; `-12.0001` passes. `exists (@.rate)` in lax mode is true for `"rate": null`, and the type test then refuses it (B3 above).

### N10. The time-zone reading (executed Z1/Z2 logic, predicted DST)

`(p_on + 1)::timestamp AT TIME ZONE p_time_zone` is the first instant of the next local day; `customer_attribute_as_of` takes `effective_at <= p_at`, so a change effective exactly at local midnight counts as in force at the end of `p_on` — -07's boundary, unchanged. An unknown zone raises 22023 from the operator (Z3b). No zone in the US shifts at midnight, so there is no nonexistent-local-midnight case for the seeded counties.

### N11. Known limits L1–L5

None blocking. L1 is the ruling. L2 (conservative walk) is stated and tested (D6). L3 is a property of one-transaction batteries. L4 names the money stream's columns. L5 is -07's fallback, unchanged.

### N12. Mutation runner

11 of 11 named mutations are plausible and anchored uniquely (read, not run, per the brief). Missing: the close-path header bump (S1). A mutation on the predecessor/tenant checks is covered by the ported -19 battery under `ci.sh`, not by `mutations-28.sh`; acceptable since those lines did not change.

## Answers to the brief

1. Each section does what its ruling says and nothing more; the surcharge function changed only in the zone block.
2. No path around a rule found for `tally_app`, `tally_core` (read-only on the table) or the owner, at any isolation level; `NaN` (S2) is the one value that slips the new check.
3. Nothing earlier weakened; -21's guarantees carried (N8), -19's cycle rule now dated and still race-safe (C1/C2/C4/LR4/LR5).
4. Concurrency: the mutex and lock order hold; the zone read is unlocked but re-checked at issue (N3).
5. Tests: D7c's header claim is hollow (S1); everything else claims what it checks.
6. L1–L5: none blocking.
