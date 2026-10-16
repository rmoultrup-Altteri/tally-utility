# Review brief: v5.4.2-22 r5 — wave 2, part 1: accounting periods as freeze boundaries, the close snapshot, GL mapping, receivables aging, write-off recovery

**Date:** 2026-10-16. **Kind:** patch review, round 5.
**Reviewers:** Opus, Fable, Codex, independently. Do not read each other's files.

## Frozen files

Review exactly these. Check the hashes first, and stop and report if one differs.

| File | md5 |
|---|---|
| `tests/v5.4.2-22/review/patch-22-frozen-r5.sql` | `7e914bdacf1d2b19c3e6fc34b325d17e` |
| `tests/v5.4.2-22/review/battery-22-frozen-r5.sql` | `a5369adf6c44f61932ba79a84bdd0aa7` |
| `tests/v5.4.2-22/review/close-22-frozen-r5.sh` | `59554ed29cf52aa87bbda0d7886a0b77` |
| `tests/v5.4.2-22/review/mutations-22-frozen-r5.py` | `8513d1d2168232a0ba477891cbc3b691` |

The live copies (`sql/v5.4.2-22-periods-snapshot-gl-aging.sql`, `tests/v5.4.2-22/battery-22.sql`, `tests/v5.4.2-22/races/close-22.sh`, `tests/v5.4.2-22/mutations-22.py`) are identical to the frozen ones today. Review the frozen copies.

## Background

All paths are absolute below. `TU` is `/Users/ryanscomputer/code/tally-utility`; `GBM` is `/Users/ryanscomputer/code/gas-billing-memory`.

The base is the `tally` database: `TU/sql/tu.sql` through v5.4.2-21. -20 sealed the version check and the void with owner roles `tally_seal` and `tally_void`. -21 added retention, bill-line arithmetic, lineage and identity.

The rulings are in **GBM** `application/`:
- **D-2** (`GBM/application/kyle-decisions-2026-08-18-coda-items.md` Part 2) says the platform is a receivables subledger that exports, not a GL. Accounting periods are freeze boundaries, not a reporting grain. It requires a close snapshot and GL code mapping held as tenant configuration. The unbilled-revenue accrual is never a ledger row.
- **D-3** (same file, Part 3) says the aging carries the customer's status.
- **R-02** (`GBM/application/kyle-decisions-2026-10-15-waves-1-to-7-and-texas-first.md`) says a reversal names its entry and is capped. Here it applies to write-offs only; the general rule is -23's.

The requirements and drafting calls are in **TU**, not GBM:
- the source inventory, `TU/application/wave2-build-2026-10-15/source-inventory-wave2.md` (requirements P, S, G, W; its "-22 as drafted" section maps them to checks);
- `TU/application/DECISION-LOG.md`, entries dated 2026-10-15 (the seven drafting calls, and round 2's three calls).

The residuals left on purpose are R1–R12 in the patch header.

## What changed since r4

Round 4: Opus "ready", Fable "ready", Codex "not yet". `review-findings-22-r4.md` lists each finding and its disposition. Your own r4 report is in this directory; read it, and do not read the other reviewers' reports. `diff-22-r4-r5.diff` is the patch diff. r5 is small:
- **A row in a write-off's tree is recorded at a finite time already reached** (Codex B1). This covers the write-off itself: `enforce_write_off_recovery` now also fires for `transaction_type = 'write_off'` (new WHEN clause, pinned).
- **The invariant pins the walks' plan settings** (`proconfig` of both walk functions).
- **Header.**
  - The r5 paragraph.
  - The lock order states the deadlock between the close's snapshot tenant key and an edges change that holds the tenant row.
  - New residual R12: history loads post one statement per recorded instant.
- **Tests.**
  - Battery: R12f, R12g, R12h.
  - CR15 asserts SQLSTATE 40001.
  - Mutations: M69–M72. M68 is now caught at apply.

Check in particular:
- that each r4 finding is closed, without a new path around it;
- that the future-time rule cannot strand an honest writer or a legitimate history load (past times are kept), and that the widened trigger changes nothing for ledger rows outside a write-off tree;
- that the stated deadlocks are the only ones the locks can produce.

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`. The second run is skipped by its marker, the table `accounting_periods`.
- **`tests/ci.sh`:** `ci: all pass`, 35 steps, with -22 PENDING (strict apply twice, battery 157, races CR1–CR15).
- **`battery-22.sql`:** 157 checks, on a vacuumed ledger. **`races/close-22.sh`:** CR1–CR15.
- **`mutations-22.py`:** 72/72 caught (the runner VACUUMs the ledger before each battery).
## What to answer

1. **Does the patch implement the inventory and the rulings?** Name any requirement missed or half-done.
2. **Is there a path around any rule?** Consider:
   - money dated in a closed period, by any table, role, isolation or statement shape;
   - a period reopened, edited, deleted, born closed, or withdrawn without a user;
   - a gap or overlap in periods;
   - a close out of order or before the period ends;
   - a snapshot written or changed outside the close;
   - a head moved backward or by anyone but the close;
   - **anything netted into a write-off past its cap or below zero**;
   - a recovery of the wrong customer or sign;
   - a reversal loop or over-long chain admitted;
   - a GL mapping changed in place, or in force inside a closed period.
3. **The seal.** Does `tally_close` still meet the -20 seal pattern with its changed grants? Is its grant list the least the close needs?
4. **The snapshot.** Are the figures right? Are the edges the tenant's at the instant?
5. **The aging function.** Is it still correct for the cases above? Is it RLS-safe, with the coordinates required?
6. **The invariants.** Does each catch what it claims? Is any claim narrower than its check?
7. **The tests.** Is any check weaker than its label? Does any mutation pass for the wrong reason? What is missing?
8. **Residuals R1–R12.** Is any of them actually blocking?

## How to probe

You may query the running `tally-pg` read-only. For experiments, clone into your own scratch database, named for you only:
- Opus: `rv22opus5`;
- Fable: `rv22fable5`.

Clone with `CREATE DATABASE <name> TEMPLATE tally`. Revoke TEMP from PUBLIC, `tally_app` and `tally_core` on the clone right after creating it. Then apply the frozen patch strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

(`docker cp` the file into the container first.)

**Restrictions:**
- Roles are cluster-wide. Do not create, drop or alter any role. The patch creates `tally_close` if it is missing. It already exists in the cluster, from the author's scratch runs.
- Do not run `mutations-22.py`: it uses the fixed name `m22`.
- Do not run `close-22.sh` against anything but your own clone.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file.
- Drop your clone when done.

**Codex** reviews source only. Write each database claim as a probe in `TU/tests/v5.4.2-22/review/codex-r5-probes/`. Each probe:
- runs as the owner on a fresh clone with the frozen r5 patch applied;
- ends in ROLLBACK;
- reports caught errors with RAISE NOTICE, SQLSTATE and message.

Do not rely on psql's `LAST_ERROR_SQLSTATE` after a COPY: it stays `00000` (r3 n7). Print the error itself. The author runs the probes.

## Output

Write your full review to `tests/v5.4.2-22/review/<reviewer>-r5.md` (`opus`, `fable` or `codex`). It contains:
- a verdict: "ready" or "not yet";
- blocking items (B1…), each with the concrete path or repro;
- should-fix items (S1…);
- notes (N1…).

Mark each claim as **executed** or **predicted**. Your final message, under 2 KB, gives the verdict, the blocking items in one line each, and the file path. If you cannot write the file, send the review to main as several messages, each under 3 KB.
