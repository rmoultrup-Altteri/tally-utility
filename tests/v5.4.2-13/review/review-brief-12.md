# Review brief — v5.4.2-12 (round 1, frozen)

| Artefact | Lines | md5 |
|---|---|---|
| `sql/v5.4.2-12-backbilling-caps.sql` | 1777 | `3bd2ab36b384142deba494913beec7f1` |
| `tests/v5.4.2-12/battery-12.sql` | 573 | `91cc78fecc32e421015b0a6bd6bab771` |

The patch file is **frozen** for this round. Do not review a different hash;
if you believe the file changed under you, stop and say so.

## What this patch is

16 TAC §7.45 limits how far back a Texas gas utility may **bill** a customer
it under-charged, and — separately, with different numbers — how far back it
may **enforce collection** on what it billed. For a meter found not to
register, three months may be billed and none of it may ever be enforced.
For a meter found more than 2% fast, the correction runs the other way and is
**mandatory**, not optional.

This patch is the enforcement of that. There is no application code anywhere
in this project; `sql/tu.sql` is the only artefact, so every rule here is a
constraint, a trigger or a function.

Authority is Kyle's closed ruling set R-19…R-31 plus CCK-1…CCK-14,
consolidated in `gas-billing-memory/application/a2-implementation-brief-2026-09-21.md`.
**No statutory claim here is a fresh reading of the rule** — all of it is
carried from Kyle's record, and R-28's caveat (the (4)(E)(vi) closing clause
was not re-read on 2026-09-14) travels unchanged.

## What lands

1. `tenants.regulatory_class_mode` — CCK-14. v1 default
   `all_non_residential_protected`, under which every account is protected.
   `volumetric_threshold` is declared but **RAISES** rather than degrading
   to the default.
2. `UNIQUE (id, tenant_id)` on `jurisdictions` and `correction_run_targets`,
   and `service_locations.jurisdiction_id` repaired to a tenant-composite FK.
   Three of the 229 tenant-blind links; the rest are their own patch (Ryan,
   2026-09-22: A-2 lands first).
3. `backbilling_cap_rules` — two bounds per row, both with explicit non-null
   scope enums. Texas gas seeds for **both** customer classes: an unprotected
   row is written explicitly `uncapped` rather than left absent.
4. `backbill_cause` + `anchor_date` on the target (R-19), findings-based.
5. The under-reach override in **database-stamped write-once columns** (F-3),
   from a three-value evidentiary-impossibility list (R-27, narrowed).
6. `correction_run_target_events` — append-only setup-time log (F-1).
7. `invoice_events.event_type` widened by two values (F-2).
8. `backbilling_read_classification()` — R-30's platform-fixed mapping.
9. `backbilling_period_evaluations` — append-only, one row per (target,
   original period) per evaluation (R-25).
10. Gate (ii) on target setup; gate (iii) on **issuance**, not inside
    `void_invoice()` (R-22).
11. The v5.4.2-10 target freeze extended to the two new columns (F-4).
12. The AC-32 tail.

## Verification already done (please re-run, do not take my word)

- Strict apply ×2 (`search_path=''`, `check_function_bodies=on`) on a fresh
  `TEMPLATE tally` clone — clean and idempotent.
- `battery-12.sql`: **55 PASS**, zero failures.
- Regression on the patched build: battery-09 **28**, battery-10 **58**,
  battery-11 **41** — each matching its recorded count. This matters most for
  battery-10: this patch re-issues `enforce_correction_target_frozen_under_snapshot()`
  and re-creates its trigger with two extra columns in the column list.
- Catalog delta: +3 tables, +3 policies, +3 FORCE RLS, +6 triggers,
  +11 functions, +8 FKs. Nothing else moved.
- AC-32 is shown to **RAISE** on four planted drifts on this patch's own
  tables (battery H4–H7), not merely to pass.

```sh
docker exec tally-pg psql -U tally -d tally -c "CREATE DATABASE r12 TEMPLATE tally"
docker exec -i tally-pg psql -U tally -d r12 -v ON_ERROR_STOP=1 \
  -c "SET search_path=''; SET check_function_bodies=on;" -f - < patch-12-frozen-r1.sql
docker exec -i tally-pg psql -U tally -d r12 -v ON_ERROR_STOP=1 -q -f - < battery-12.sql 2>&1 | grep -E 'PASS|FAIL|ERROR'
```

## Two defects I found in my own draft before freezing

Both are **closed** in this hash. I record them because they name the shape I
most want you hunting, and because a reviewer should know where the draft was
already weak rather than rediscovering it and stopping there.

1. **Stale evidence at issuance.** The evaluation is written against a DRAFT,
   and a draft's `amount_due` is not frozen by the -10 snapshot guard.
   Sequence: evaluate a $5 correction, inflate the draft to $5,000, issue.
   Every other check in gate (iii) passed — cause matched, evidence row
   existed, window computed, nothing trimmed. Gate (iii) now re-derives the
   delta and refuses a mismatch (battery I1).
2. **A constraint that contradicted its own table.** I had put
   `UNIQUE (target_id, period_start, period_end)` on the evidence table while
   ALSO making it append-only and having the gate read the newest row. Those
   three cannot all hold: the gate demands a fresh answer, append-only forbids
   editing the old one, and the unique key forbids adding one — so a changed
   draft could never issue at all. The unique is gone; ordering is by a
   monotonic `evaluation_seq`, **not** `evaluated_at`, because `now()` is
   constant within a transaction and a tie would silently pick one of two
   different answers (battery I2).

## Where I most want an adversarial read

1. **The straddling period is the weakest thing here, and it is not ruled.**
   R-25 makes the original billing period the unit; R-23 says the rebill
   proceeds for the permitted window with the remainder forfeited. Neither
   addresses a period that BEGINS before `window_start` and ENDS after it.
   I prorate the adverse delta by days, which assumes uniform consumption —
   false for gas, especially in winter. Is there a defensible third option I
   have missed? Is day-proration actively wrong in a way that shows up as a
   specific bad number?
2. **Can a correction be charged without passing gate (iii)?** The gate is
   `BEFORE UPDATE OF status` on `invoices`, firing on the transition INTO an
   issued status. What about an INSERT that is born issued? A status moved by
   a definer function? `COPY`? A path that bills through
   `invoice_line_items` without moving `invoices.status`? Enumerate the ways
   money reaches a customer and tell me which ones this gate does not stand in.
3. **Gate (iii) trusts `amount_due`.** Is `amount_due` actually the bill's
   total in this schema, maintained by something, or is it a denormalised
   field a caller sets? If a caller sets it, the delta test is checking a
   number the attacker controls on BOTH sides. This is the finding I would
   most expect to have missed.
4. **The window arithmetic.** `greatest(anchor - N months, last_test)` — is
   "the shorter of six months and the last test" really the LATER start?
   Month arithmetic near month ends (`2026-03-31 - interval '1 month'`)?
   The battery pins the boundary day and one day either side, but only for
   one anchor.
5. **The freeze extension (item 11).** I re-issued a v5.4.2-10 function and
   re-created its trigger with a longer column list. Did I change its
   behaviour for the four original columns in any way? Battery-10's 58 still
   pass, but that battery was written before these columns existed.
6. **The under-reach warning is computed twice** — once in gate (ii) from the
   target, once in `backbilling_evaluate_period()` for the evidence row.
   Two expressions of one rule is a divergence waiting to happen. Are they
   actually equivalent? Should one call the other?
7. **Fail-closed choices that might be too closed.** An adverse period on a
   meter with no recorded test date REFUSES (R-31 forbids deriving a date,
   and there is no operator-confirmation surface). A tenant created after
   this patch has no cap rules and every correction refuses until onboarding
   seeds them. Are these defensible, or do they brick a real workflow?
8. **`backbilling_customer_class` reads `customers` and `tenants` under
   invoker rights.** Is there a call path — a definer caller, a background
   job with no `app.user_id` — where it returns the wrong class rather than
   raising?

## Rules of engagement

- Severity: CRITICAL / HIGH / MEDIUM / LOW, each with a reproduction I can run.
- If a finding is "this is fine but undocumented", say LOW and name the line.
- **Do not propose building the CCK volumetric resolver** (F-5, Ryan's scope
  decision), the meter test history table (R-31, its own patch behind this
  one), or collections behaviour on the enforceable bound (R-20 hands it to
  Family 9). Those are out of scope by ruling, not by oversight.
- A finding against the straddle proration is welcome; a finding that says
  "ask Kyle" is already recorded as residual R1 and is not news.
