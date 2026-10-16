# Review brief: v5.4.2-22 r6 — wave 2, part 1: accounting periods as freeze boundaries, the close snapshot, GL mapping, receivables aging, write-off recovery

**Date:** 2026-10-16. **Kind:** patch review, round 6.
**Reviewers:** Opus, Fable, Codex, independently. Do not read each other's files.

## Frozen files

Review exactly these. Check the hashes first, and stop and report if one differs.

| File | md5 |
|---|---|
| `tests/v5.4.2-22/review/patch-22-frozen-r6.sql` | `b3a3c98252004b7351c470dcf344d8fe` |
| `tests/v5.4.2-22/review/battery-22-frozen-r6.sql` | `70b1003c65cfef0179eff53ef0682447` |
| `tests/v5.4.2-22/review/close-22-frozen-r6.sh` | `512cf9c97d7bf71f5d198c56fd8dedcc` |
| `tests/v5.4.2-22/review/mutations-22-frozen-r6.py` | `06f6f920931d8feb60f7ebebcf63dcc3` |

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

## What changed since r5

Round 5: Opus, Fable and Codex all "ready". `review-findings-22-r5.md` lists each finding and its disposition. Your own r5 report is in this directory; read it, and do not read the other reviewers' reports. `diff-22-r5-r6.diff` is the patch diff. This is a **short round**: r6 changes wording, one refusal's SQLSTATE, and tests.
- **Lock order (header and the close's comment).** It states every lock the close takes after the head (the period; FOR KEY SHARE on the tenant row and on the closing user's users row) and every cycle they make: writers under two write-offs; a withdrawal then a write; the tenant or a users row held FOR UPDATE then the head (money, GL mapping or edges write); two transactions that each write and then close.
- **One refusal changes.** A row whose recorded time was chosen (`created_at <> now()`, the owner's history load) and falls before a row already in its tree is refused for good, 23514. A row stamped at its transaction's start still gets 40001. R12 updated.
- **Messages and comment.** "recorded at a non-finite or future time"; the recovery function's comment names the write-off firing and both rules.
- **Tests.**
  - Battery 166: R11b, R11c, R12e (now 23514), R12i–R12o; R9b relabeled.
  - Races: CR15 ordered by barriers; CR16–CR18, one per stated deadlock shape.
  - Mutations M73–M79.

Check in particular:
- that the lock-order paragraph is now true and complete: no cycle it omits, none it states that cannot happen;
- that the 23514/40001 split cannot refuse an honest writer for good, nor let a chosen-time row retry forever;
- that each new check and race catches what its label says, and each new mutation is caught for the right reason.

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`. The second run is skipped by its marker, the table `accounting_periods`.
- **`tests/ci.sh`:** `ci: all pass`, 35 steps, with -22 PENDING (strict apply twice, battery 166, races CR1–CR18).
- **`battery-22.sql`:** 166 checks, on a vacuumed ledger. **`races/close-22.sh`:** CR1–CR18, 28 PASS lines, three runs on fresh clones.
- **`mutations-22.py`:** 79/79 caught (the runner VACUUMs the ledger before each battery).

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
- Opus: `rv22opus6`;
- Fable: `rv22fable6`.

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

**Codex** reviews source only. Write each database claim as a probe in `TU/tests/v5.4.2-22/review/codex-r6-probes/`. Each probe:
- runs as the owner on a fresh clone with the frozen r6 patch applied;
- ends in ROLLBACK;
- reports caught errors with RAISE NOTICE, SQLSTATE and message.

Do not rely on psql's `LAST_ERROR_SQLSTATE` after a COPY: it stays `00000` (r3 n7). Print the error itself. The author runs the probes.

## Output

Write your full review to `tests/v5.4.2-22/review/<reviewer>-r6.md` (`opus`, `fable` or `codex`). It contains:
- a verdict: "ready" or "not yet";
- blocking items (B1…), each with the concrete path or repro;
- should-fix items (S1…);
- notes (N1…).

Mark each claim as **executed** or **predicted**. Your final message, under 2 KB, gives the verdict, the blocking items in one line each, and the file path. If you cannot write the file, send the review to main as several messages, each under 3 KB.
