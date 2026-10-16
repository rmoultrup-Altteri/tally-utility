# Review brief: v5.4.2-22 r3 — wave 2, part 1: accounting periods as freeze boundaries, the close snapshot, GL mapping, receivables aging, write-off recovery

**Date:** 2026-10-15. **Kind:** patch review, round 3.
**Reviewers:** Opus, Fable, Codex, independently. Do not read each other's files.

## Frozen files

Review exactly these. Check the hashes first, and stop and report if one differs.

| File | md5 |
|---|---|
| `tests/v5.4.2-22/review/patch-22-frozen-r3.sql` | `ae35e901b3c0fa0b40804316965eee14` |
| `tests/v5.4.2-22/review/battery-22-frozen-r3.sql` | `36edebe0613f3ccf11f4f70d9988a0dc` |
| `tests/v5.4.2-22/review/close-22-frozen-r3.sh` | `de7a2f6902bb5b7b51a9bdd46b30fd25` |
| `tests/v5.4.2-22/review/mutations-22-frozen-r3.py` | `61104fe10b51e3a8e9ca320dfc6636db` |

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

The residuals left on purpose are R1–R10 in the patch header.

## What changed since r2

Round 2: Opus "not yet", Fable "ready", Codex "not yet". `review-findings-22-r2.md` lists each finding and its disposition. Your own r2 report is in this directory; read it, and do not read the other reviewers' reports. `diff-22-r2-r3.diff` is the patch diff. The changes:
- **The write-off rule runs after the insert.**
  - `enforce_write_off_recovery` is an AFTER INSERT row trigger, so it sees every row of the statement in any order.
  - The recovery's own checks moved with it: it names a write_off of its own customer, with the opposite sign.
- **The cap is on the net of the write-off's tree.**
  - It counts everything aging nets into the write-off: its whole same-customer tree, at any depth, of any type.
  - The net must stay between 0 and the amount written off.
  - It is checked for every write-off above the new row, behind each write-off's advisory lock, taken in id order, at READ COMMITTED.
- **The cap's walks step by link alone** (found before the freeze, when mutation M57 hung the run). Each step of the upward and the downward walk joins only on `id` or `reverses_ledger_entry_id`; the same-customer test is applied apart from the join. With the customer in the join, the planner scanned the customer's ledger at every step on an unanalyzed table: a 400-deep tree in one statement went from over 2 minutes to about 2 s. New checks R10f (another customer's row in the tree is not counted) and R10g (a 300-deep tree within 30 s); mutations M62 and M63; the runner sets a 300 s statement timeout, so a hang reports as a miss.
- **The lineage walk fails closed.** A chain that has not reached an original within 1,000 entries is refused. The bound was 10,000 and did not refuse.
- **The close's aging edges** come from `tenants.receivables_aging_bucket_days` at its instant, not from the configuration history.
  - `tally_close`'s grants changed to match. The seal list is updated.
- **A withdrawal names its user.** It stays an operator's act; the decision log says why.
- **The invariant pins three more constraints:**
  - the history's known-key CHECK;
  - the ledger's not-self CHECK;
  - the reversal FK.
- **The seal invariant** also refuses `tally_app` UPDATE on `closed_by`.
- **Messages and comments.**
  - Closing a withdrawn period says "is withdrawn".
  - The snapshot comment names the 4-argument reproduction.
  - The header states the withdrawal-and-close deadlock.
  - New residual: R10, manual history rows.
- **Tests.**
  - Battery: R9–R11 (R10f, R10g included), P9f, C13b and C16b. C12 reproduces with the stored edges.
  - Races: CR11 and CR12.
  - Mutations: M53–M63.
  - The mutation runner matches labels exactly.

Check in particular:
- that each r2 finding is closed, without a new path around it;
- that the cap's net is right for every shape you can build:
  - trees across statements and within one;
  - a write-off under another write-off's recovery;
  - rows of another customer naming into the tree;
- that moving the rule to AFTER INSERT loses nothing the BEFORE trigger refused, and that the trigger name order really runs the lineage walk first;
- that the cap's locks (several write-offs, id order, after the head's FOR SHARE) add no deadlock the header does not state;
- that the 1,000 bound refuses nothing legitimate the product needs.
- that the link-only walks find the same write-offs and the same tree as a join on the customer would, and that no step of either walk can still scan a ledger.

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`. The second run is skipped by its marker, the table `accounting_periods`.
- **`tests/ci.sh`:** `ci: all pass`, 35 steps, with -22 PENDING (strict apply twice, battery 149, races CR1–CR12).
- **`battery-22.sql`:** 149 checks. **`races/close-22.sh`:** CR1–CR12.
- **`mutations-22.py`:** 63/63 caught (M49 rewritten to read the tenant's live setting, since `tally_close` no longer holds the history function).
- **Codex's r2 probes against r3:**
  - b1: refused;
  - b2's 10,001 ring: refused at insert;
  - n6 loops: refused;
  - s2's dropped CHECK: caught.

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
8. **Residuals R1–R10.** Is any of them actually blocking?

## How to probe

You may query the running `tally-pg` read-only. For experiments, clone into your own scratch database, named for you only:
- Opus: `rv22opus3`;
- Fable: `rv22fable3`.

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

**Codex** reviews source only. Write each database claim as a probe in `TU/tests/v5.4.2-22/review/codex-r3-probes/`. Each probe:
- runs as the owner on a fresh clone with the frozen r3 patch applied;
- ends in ROLLBACK;
- reports caught errors with RAISE NOTICE, SQLSTATE and message.

Test a COPY probe's error capture: the r2 n7 probe reported "accepted" for a refused COPY. The author runs the probes.

## Output

Write your full review to `tests/v5.4.2-22/review/<reviewer>-r3.md` (`opus`, `fable` or `codex`). It contains:
- a verdict: "ready" or "not yet";
- blocking items (B1…), each with the concrete path or repro;
- should-fix items (S1…);
- notes (N1…).

Mark each claim as **executed** or **predicted**. Your final message, under 2 KB, gives the verdict, the blocking items in one line each, and the file path. If you cannot write the file, send the review to main as several messages, each under 3 KB.
