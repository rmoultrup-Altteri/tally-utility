# Review brief: v5.4.2-22 r8 — wave 2, part 1: accounting periods as freeze boundaries, the close snapshot, GL mapping, receivables aging, write-off recovery

**Date:** 2026-10-16. **Kind:** patch review, round 8.
**Reviewers:** Opus and Fable, independently (Codex waived for this round). Do not read each other's files.

## Frozen files

Review exactly these. Check the hashes first, and stop and report if one differs.

| File | md5 |
|---|---|
| `tests/v5.4.2-22/review/patch-22-frozen-r8.sql` | `ad2c6af3a9ec83512265cc0581b9cbec` |
| `tests/v5.4.2-22/review/battery-22-frozen-r8.sql` | `45b95d5cc55c52ab576bc3cd029ed651` |
| `tests/v5.4.2-22/review/close-22-frozen-r8.sh` | `58886f4cc0e7f565725456d23980b8cf` |
| `tests/v5.4.2-22/review/mutations-22-frozen-r8.py` | `aac4990021db9a1329a24fa2f184f253` |

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

## What changed since r7

Round 7: Opus and Fable "ready"; Codex not run, and waived by Ryan for the rounds after r5 (2026-10-16: "let's not wait for codex on this"). `review-findings-22-r7.md` lists each finding and its disposition. **Opus and Fable:** read your own r7 report; `diff-22-r7-r8.diff` is the patch diff, **comment lines only** (no code, no test changed). Do not read the other reviewers' reports.
- **Lock order (r8).** The rule counts waits through other transactions, promises no list of shapes complete, and says every writer retries 40P01. "What takes the rows" adds a bare `SELECT … FOR UPDATE` on the head and the period. One UPDATE of tenants that changes the edges and names `slug` is stated as a shape that deadlocks by itself.

Check in particular:
- that the paragraph now claims nothing false: every row, order and grant it names is right, and no sentence still reads as a complete list;

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`. The second run is skipped by its marker, the table `accounting_periods`.
- **`tests/ci.sh`:** `ci: all pass`, 35 steps, with -22 PENDING (strict apply twice, battery 167, races CR1–CR20).
- **`battery-22.sql`:** 167 checks, on a vacuumed ledger. **`races/close-22.sh`:** CR1–CR20, 30 PASS lines (three runs on fresh clones at r7; r8 changes no code).
- **`mutations-22.py`:** 79/79 caught, one full run

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
- Opus: `rv22opus8`;
- Fable: `rv22fable8`.

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

## Output

Write your full review to `tests/v5.4.2-22/review/<reviewer>-r8.md` (`opus` or `fable`). It contains:
- a verdict: "ready" or "not yet";
- blocking items (B1…), each with the concrete path or repro;
- should-fix items (S1…);
- notes (N1…).

Mark each claim as **executed** or **predicted**. Your final message, under 2 KB, gives the verdict, the blocking items in one line each, and the file path. If you cannot write the file, send the review to main as several messages, each under 3 KB.
