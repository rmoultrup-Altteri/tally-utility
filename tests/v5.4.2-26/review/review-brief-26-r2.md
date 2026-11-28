# Review brief: v5.4.2-26 r2 — collections decisions and field verification

**Date:** 2026-11-27. **Kind:** patch review, round 2.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's round-2 files.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-26/review/patch-26-frozen-r2.sql` | `af02fd6311471b8bef4822f7b6d124a0` |
| `tests/v5.4.2-26/review/battery-26-frozen-r2.sql` | `2ff3ca08f94321b433fcc658ee9ec66c` |
| `tests/v5.4.2-26/review/collections-26-frozen-r2.sh` | `43e8fda4bd163d17bdea6763a60516a4` |
| `tests/v5.4.2-26/review/mutations-26-frozen-r2.py` | `2610f21cfaa2fd0814c8d3569e5ac23a` |
| `tests/v5.4.2-26/review/migration-26-frozen-r2.py` | `607a7f540c80a24dc6cb76f4a6871152` |
| `tests/v5.4.2-26/review/fill-manifest-26-frozen-r2.py` | `0f10a4d77046059b4effdb9e049bc8eb` |
| `tests/v5.4.2-26/review/battery-21-for-26-frozen-r2.sql` | `0b1fc800443eecee12e184eac9eab5d4` |

The live copies (`sql/v5.4.2-26-collections-decisions.sql`, `tests/v5.4.2-26/`, `tests/v5.4.2-21/battery-21.sql`) are identical today. Diffs from round 1: `tests/v5.4.2-26/review/r1-to-r2.diff` (the patch), `tests/v5.4.2-26/review/battery-r1-to-r2.diff`, `tests/v5.4.2-26/review/battery-21-r1-to-r2.diff`.

## Background

Round 1 (`review-brief-26-r1.md`; your own round-1 review is `<you>-r1.md`) found five blocking and ten should-fix items; all three said "not yet". The merged list, and what r2 did with each, is `application/wave3-build-2026-10-18/v5.4.2-26-r2-plan.md` ("Round 1 reviewed", "As built", "Tests (r2)"). Read it first. Read round 1's brief for the background, rulings and probing rules; they are unchanged except as below.

## What to answer

1. **Is each round-1 finding fixed?** Go through the plan's items 1 to 15 and your own round-1 items. For each: fixed, partly fixed (what is left), or not fixed. Try to get round each fix the way you got round the original.
2. **Did r2 break anything?** In particular:
   - **The subject lock without the meter** (item 2): every subject at one location shares one advisory lock. Is the A10 check complete (an order naming no meter; a notice with and without a meter; an execution)? Can a decision written concurrently with an act escape it?
   - **The stage read from the events** (item 4) and **forward only** (item 6, settled by rule, not Ryan's: plan item 6 explains why). Is `record_seq` ordering sound under concurrency (two sessions, one bill)? Is the ladder right, and what should an escalation step do from `payment_plan`, `resolved` or `written_off`?
   - **The late-fee line gate** (item 7): a new trigger on `invoice_line_items`, a mirrored table. Which roles write it (`triggers-run-as-every-writer`)? Does any mirrored path write a `late_fee` or `penalty` line? `battery-21` now depends on -26 objects: is that acceptable?
   - **The approver** (item 5): an active `tenant_admin` of the order's utility; `session_is_supervisor()` is no longer called. Is anything that relied on a platform administrator approving now wrongly refused?
   - **Execution dates** (item 9): no earlier than the order's and the decision's `created_at`, not in the future. Can a caller set `created_at` on an order? Is the bound fair to a field tool that syncs late?
   - **`assert_collections_guard_invariants()`** and `fill-manifest.py` (item 11): does it pin what it claims, and catch drift? Does the mutation runner's dropping of its call (behavioural mutations only) hide anything?
   - **`enrollment_recompute_dnd` ENABLE ALWAYS** (item 10): a mirrored trigger's mode changed. Any load path that now misbehaves?
3. **The tests.** Is any new check weaker than its label? Does any new mutation pass for the wrong reason? Plan "Not done": the "decision recorded before the act" bound applies to executions only. Agree?
4. **Residuals** R1 (extended), R6 and R7 (new). Is any blocking?

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`; the second run is skipped.
- **`battery-26.sql`:** 249 checks, one transaction, rolled back.
- **`races/collections-26.sh`:** CR1–CR8d, 13 results.
- **`migration-26.py`:** P0–P7b, 0 failures.
- **`mutations-26.py`:** 152 of 152 caught, each at its named check as the first failure.
- **`battery-21.sql`** with -26 applied: passes.
- **`tests/ci.sh`:** 56 steps, all pass, with -26 pending.

## How to probe

As round 1. Scratch clones: Opus `rv26opus`, Fable `rv26fable`; revoke TEMP from PUBLIC, `tally_app` and `tally_core` after creating each; strict-apply the frozen r2 patch. **Codex reviews source only**; its probes go in `tests/v5.4.2-26/review/codex-r2-probes/` (owner, fresh clone with frozen r2 applied, ending in ROLLBACK, printing SQLSTATE and message for each caught error; a COPY probe prints its own error). Do not run `mutations-26.py`, `fill-manifest.py` or `tests/ci.sh`; run `collections-26.sh` only against your own clone. Do not create, drop or alter roles. Modify nothing but your output file (and Codex's probes). Drop your clone when done.

**Output:** `tests/v5.4.2-26/review/<you>-r2.md` (opus, fable, codex): verdict "ready" or "not yet"; items B (blocking), S (should fix), N (note), each marked executed or predicted, with the evidence.
