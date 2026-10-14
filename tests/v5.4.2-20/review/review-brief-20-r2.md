# Review brief: v5.4.2-20 r2, the version-check and void seals

**Date:** 2026-10-14. **Kind:** patch review, round 2.
**Reviewers:** Opus, Fable, Codex, independently. Do not read each other's files from this round.

## Frozen files

Review exactly these. Check the hashes first, and stop and report if one differs.

| File | md5 |
|---|---|
| `tests/v5.4.2-20/review/patch-20-frozen-r2.sql` | `382fa4d39341d2398c82775c779a66ac` |
| `tests/v5.4.2-20/review/battery-20-frozen-r2.sql` | `a0b6ec64c7e2b3ec51feaf1e617319ea` |
| `tests/v5.4.2-20/review/seal-20-frozen-r2.sh` | `dc36ebd2e1730d4dbd93bc4cd805a02e` |

The live copies are identical today. Review the frozen copies.

## What changed since r1

Read `tests/v5.4.2-20/review/review-findings-20-r1.md`. It maps every round-1 finding to its fix (F1–F10), and lists what was not taken and why. Your own round-1 file is `tests/v5.4.2-20/review/<you>-r1.md`. Since r1 you may read the other reviewers' round-1 files.

In short:
- **F1.** The attach guard refuses a bill the caller cannot see, or a bill of another tenant than the row.
- **F2.** `void_invoice()` runs only at READ COMMITTED.
- **F3.** CHECK: a charge is billed if and only if it names its bill.
- **F4.** Every new guard is `ENABLE ALWAYS`.
- **F5.** `assert_seal_role_invariants()` checks exact identities, an exact privilege allowlist per seal role (`seal_role_privileges()`), and the exact definition and `ALWAYS` state of 17 guard triggers.
- **F6.** `tally_void`'s grants are column-level and minimal, and a redundant clause in the charge guard is removed.
- **F7.** The deadlock is stated, and race RC6 covers it.
- **F8.** Test gaps closed.
- **F9.** The mutation harness requires the named check to be the first FAIL.
- **AC-12** is updated for the isolation, deadlock and visibility rules.

## Results (reproduce them)

- Strict apply, twice. The second run is skipped by its marker.
- `tests/ci.sh` passes in full.
- `battery-20`: 79 checks.
- `races/seal-20.sh`: RC1–RC6, RC3b, T1–T7.
- `mutations-20.py`: 50 of 50, each caught at its named check as the first failure.
- batteries 19 (R4, R5c) and 20 (V9c, V10) now expect the void role's own refusal (42501): the write is outside its column grants.

## What to answer

1. **Is each round-1 blocking item closed?** Re-run your repro against r2.
2. **Did any r2 change open something?** In particular:
   - the CHECK on `adhoc_charges` against every path that writes a charge's status;
   - the READ COMMITTED refusal against a caller's savepoints;
   - the trigger-shape strings (do they depend on any `search_path`?);
   - the temp-schema exclusion in `seal_role_privileges()`;
   - the narrower void grants on every path.
3. **Is anything from round 1 that was not taken a mistake?** See the findings file, "Not taken".
4. **Anything else blocking?**

## How to probe

As in round 1. Your scratch database is `rv20opus` or `rv20fable`. Clone `tally`, revoke TEMP from PUBLIC, `tally_app` and `tally_core`, then strict-apply the frozen r2 patch.

Do not create, drop or alter roles. `tally_seal` and `tally_void` already exist; test attribute changes only inside a transaction you roll back. Do not run `mutations-20.py`. Never modify `tally`, `sql/tu.sql` or any repo file except your output file. Drop your clone when done.

## Output

Write `tests/v5.4.2-20/review/<reviewer>-r2.md` (`opus`, `fable` or `codex`). It contains:
- a verdict: "ready" or "not yet";
- blocking items (B1…);
- should-fix items (S1…);
- notes (N1…).

Mark each claim as **executed** or **predicted**. Your final message, under 2 KB, gives the verdict, the blocking items in one line each, and the file path.
