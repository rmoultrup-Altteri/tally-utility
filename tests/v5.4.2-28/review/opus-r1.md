# v5.4.2-28 r1 — Opus review

**Date:** 2026-11-02. **Verdict: not yet** (one blocking item, small to fix).

Frozen md5s checked first: all four match the brief. Scratch clone `rv28opus` (TEMP revoked from PUBLIC, tally_app, tally_core), frozen patch strict-applied twice: clean (executed). Re-applied a third time after committing dependency rows: clean (executed). Battery-28 run on the clone: all PASS (executed). Clones dropped at the end.

## Blocking

### B1. The tier-rate CHECK cannot be dumped and restored: `pg_dump` / `pg_restore` (and so `pg_upgrade`) lose `rate_item_versions` entirely (executed)

PostgreSQL 16's jsonpath printer drops the parentheses around `(@ * 10000).floor()`. The stored constraint prints as

```
... || @ * 10000 != @ * 10000.floor())
```

and that text does not parse: `ERROR: trailing junk after numeric literal at or near "10000.f" of jsonpath input` (executed: `'... (@ * 10000).floor() ...'::jsonpath::text::jsonpath` fails on PG 16.14).

pg_dump writes this constraint inline in `CREATE TABLE public.rate_item_versions`, so the whole table fails to restore. Executed: `pg_dump -Fc` of the clone, `pg_restore` into a fresh database → 33 errors, all from this one (1 jsonpath parse error, 28 "relation rate_item_versions does not exist", 1 type, 3 `rate_item_as_of` functions); the restored database has 136 tables against 137. Any backup and restore, environment copy, or `pg_upgrade` (which goes through `pg_dump --schema-only`, predicted) of a database carrying -28 breaks. The `pg_dump --schema-only` comparisons in DEPLOY-VERIFICATION still "match", because the dump is produced fine; only reading it back fails.

**Fix (executed):** write the test without a method on a parenthesised expression: `@ * 10000 % 1 != 0`. It prints as `(@ * 10000) % 1 != 0`, reparses, and gives the same answers on the cases I tried (0.12345 refused, 0.1234 admitted, -0.12345 refused, 1e-5 refused). Mutation N10's anchor changes with it. Add a battery case that round-trips every jsonpath CHECK's `pg_get_constraintdef` text back through `::jsonpath` (or a dump/restore step), so a future jsonpath CHECK cannot repeat this.

## Should fix

### S1. A long transaction can record a cycle in the past: the as-of read returns both A on B and B on A (executed)

`recorded_at` is the transaction's `now()` (its start), but the cycle walk reads only rows open *when the insert runs*. Executed on the clone with two committed sessions:

1. B on A exists (row 01).
2. Session 1 begins (now() = 18:57:37.555), sleeps.
3. Session 2 retracts B on A and commits (recorded_until = 18:57:39.047).
4. Session 1 inserts A on B: the walk sees B on A closed, admits it; recorded_at = 18:57:37.555. Commit.
5. `rate_item_dependencies_as_of(schedule, 2026-06-01, 18:57:38.055)` returns `{aa>bb, bb>aa}`: a cycle.

A replay of a bill run made in that window gets an evaluation order with a cycle. The header mutex does not help: session 2 has already committed when session 1 bumps it. The patch's claim "it never admits a real cycle" holds on the valid-time axis only.

**Fix (predicted):** in the walk, count a row that is open *or was closed after this transaction began*: `AND (d.recorded_until IS NULL OR d.recorded_until > NEW.recorded_at)` in place of `d.recorded_until IS NULL`. Rows this transaction closed itself carry `recorded_until = now() = NEW.recorded_at` and stay out, so close-then-successor still works. Session 1 above would then be refused (and retry with a fresh now()). Add a race case beside `cycle-19.sh`.

### S2. The four-decimal rule depends on the unit, which the ruling did not weigh (executed; needs Ryan)

`rate_value` with `rate_unit = 'decimal'` is a fraction, so four decimals there means 0.01 percentage points. Texas's gas utility gross receipts tax (Tax Code §182.022: 0.581%, 1.070%, 1.997% by city size) as a fraction is 0.00581 / 0.01997: refused (executed, P1a). The same rate as `percent` 1.997 is admitted (P1b). The same goes for local sales-tax components in eighths of a percent (0.125% = 0.00125). The decision log's accepted cost names a per-Ccf conversion, not this. Options: check `percent`/`decimal` units at six (or at "four decimals of a percent"), or record that fractional rates must be entered as `percent`. One question for Ryan.

### S3. Read the zone only when it can change the answer (design suggestion; needs Ryan)

The patch reads the zone for every non-zero fee line under an exempting rule, so known limit L1 refuses every Texas pipeline-safety fee line outside El Paso and Hudspeth until that county is loaded. But the zone only matters if the account's `is_state_agency` value changed within the roughly 26 hours that midnight on `period_end + 1` covers across the world's zones (UTC+14 to UTC−12). Outside that window every zone gives the same answer, and answering it assumes nothing. Asking for the zone only when a history row falls inside the window keeps "refuse, never assume" and removes L1 for nearly every bill. It is the patch's own principle ("read only when the answer can matter") carried one step further. Not blocking: L1 as written matches the ruling.

## Notes

- **N1. Consolidated parent, children changing later (executed).** A fee line on parent 40 (Central) was written; an El Paso child was then attached. Nothing rechecked the written line, and `invoice_time_zone_as_of(40)` now refuses with 21000. The issuance gate reruns `assert_surcharge_line` at now(), so the parent cannot be issued in that state. Good. The remaining window is a child attached or un-voided after the parent is issued, or concurrently with the issuing commit (predicted; low stakes: it moves only the midnight used for the state-agency reading).
- **N2. "Live child" set.** `status <> 'void'` is the only terminal non-bill status in `invoices_status_check`, so the set is right. A nested parent (child with no premise) is refused (Z5h). A child that has a premise and is itself consolidated is read by its premise and its own children are ignored. That is acceptable but not stated.
- **N3. The dropped two-argument function.** In the clone, no function or view body except the new ones names `customer_is_state_agency_as_of`. The only other callers in `tu.sql` (lines 19429, 19902) are the -07/-08 bodies of `assert_surcharge_line` that this patch replaces. No AC references it (executed grep).
- **N4. Trigger order and stamps (executed).** `a_enforce_bitemporal_assertion` sorts before `a_enforce_rate_item_dependency` ('b' < 'r'). The row guard excludes the four close columns, so a caller-set `closed_by` passes it and is then overwritten. A `closed_by` set without a close is refused by the close-consistency CHECK (K3b). `changed_by` is refused as an in-place edit. Forging `app.user_id` to another tenant's user moves the session into that tenant, so the target row becomes invisible and nothing is stamped (P6). An owner close with no `app.user_id` leaves `closed_by` NULL (P5), as -21's `retired_by` did. No regression.
- **N5. -21's guarantees.** No hard delete: the row guard and -21's `no_hard_delete`/`no_truncate` are both present, ENABLE ALWAYS. The header mutex on a close is kept (K5a). The stamped closer is kept. The ported K and Q cases keep their meaning. K3b now fails at the CHECK (23514) instead of the trigger (23001), which is acceptable. D3c and K-del prove only that `tally_app` lacks DELETE; D9e covers the guard for the owner.
- **N6. Tier shapes outside the documented contract slip:** a missing `rate` key, or tiers nested elsewhere (e.g. `{"seasons":[{"tiers":[{"rate":0.12345}]}]}`), is admitted (executed P2e). A null rate, an array rate, nested tier arrays and a `tiers` object are all refused (P2a–d). Nothing validates the tier shape itself; that predates -28.
- **N7. Mutation gaps:** no mutation for the rate-override CHECK (R3a), the `changed_by` stamp (D2e), the orphan-child refusal (Z5h), the parent branch's tenant filter, or the trigger-name ordering. Each is a one-line addition.
- **N8. Known limits.** L1–L5: none blocking; see S3 for L1. L3 understates S1: inside one transaction, stamps are now(), but across transactions now() is the start, which is S1's hole.
- **N9. Lock order** (close: dependency row, then header; insert: header, then index) is the deadlock -19 r2/r3 accepted, stated in the comment with retry on 40P01/40001. Unchanged.
