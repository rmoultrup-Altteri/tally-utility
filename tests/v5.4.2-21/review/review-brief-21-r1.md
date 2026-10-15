# Review brief: v5.4.2-21 r1 — wave 1 built (retention, bill-line arithmetic, lineage), the void's reversal, identity follow-ups

**Date:** 2026-10-14. **Kind:** patch review, round 1.
**Reviewers:** Opus, Fable, Codex, independently. Do not read each other's files.

## Frozen files

Review exactly these. Check the hashes first, and stop and report if one differs.

| File | md5 |
|---|---|
| `tests/v5.4.2-21/review/patch-21-frozen-r1.sql` | `0900a47c5d7baf90e43e9064162ae4b7` |
| `tests/v5.4.2-21/review/battery-21-frozen-r1.sql` | `da9e348164fba0f955068a28ed9e9a25` |
| `tests/v5.4.2-21/review/labels-21-frozen-r1.sh` | `12cb39e6948c63fbdaf9b51d15c40365` |
| `tests/v5.4.2-21/review/mutations-21-frozen-r1.py` | `d263033b4b0760e84c7cf492340839f0` |

The live copies (`sql/v5.4.2-21-wave1-lineage-arithmetic-retention.sql`, `tests/v5.4.2-21/battery-21.sql`, `tests/v5.4.2-21/races/labels-21.sh`, `tests/v5.4.2-21/mutations-21.py`) are identical to the frozen ones today. Review the frozen copies.

## Background

The base is the `tally` database: `sql/tu.sql` through v5.4.2-20, which sealed the version check and the void (owner roles `tally_seal` and `tally_void`).

Ryan decided these on 2026-10-14. They are in `application/DECISION-LOG.md`, newest first:
- **CI-014:** 16 more tables are never hard-deleted; the custom labels are refused while in use.
- **CI-016:** which bill lines carry their arithmetic at issue.
- **CI-017:** every reversal that undoes one thing names it.
- **R1:** the database trusts the app's Cognito-verified identity. Consequences: a Cognito binding on `users`, and the RLS helpers require an active user. AC-43 is in `application/APPLICATION-CONTRACTS.md`.
- **The void's reversal:** a posted bill's void names its charge entry, or is refused; a never-posted bill's void writes no ledger entry.
- **A drafting call, reported to Ryan:** rate dependencies are retired, not deleted.

`application/wave1-build-2026-10-14/source-inventory-21.md` lists every requirement (D, L, K, A, G, V, U, N, T). The residuals left on purpose are R1–R5 in the patch header.

Drafting calls to check in particular:
- **A4.** A surcharge line must name its rate item at issue (fail safe). A per-unit or tiered surcharge on a gas line needs the gas figures too, read literally from "as for usage_charge".
- **G1.** No duplicate guard for "the replaced bill is void": `calculation_snapshot_coordinate_violation(…, true)` already refuses it at issue.
- **G3.** The ledger's reversal FK is now tenant-bound. The customer is not bound, because a reversal across customers was not ruled.
- **L3.** The in-use check takes `LOCK TABLE <entity> IN SHARE MODE` and refuses anything but READ COMMITTED, with no writer-side code.
- **K.** Retirement is permanent; uniqueness and the cycle walk count live rows only.
- **G6.** A charge born with `voided_from_invoice_id` is refused, except a superuser load (the `first_issued_at` precedent).

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`. The second run is skipped by its marker, the column `users.cognito_sub`.
- **`tests/ci.sh`:** passes in full with -21 pending. That covers:
  - batteries 09–21 and the -15/-17 runners;
  - every race script, -21's included;
  - the tenant-isolation, core-role, seal-role, rule-table and new retention invariants.
- **`battery-21.sql`:** 103 checks. **`races/labels-21.sh`:** LR1–LR5.
- **`mutations-21.py`:** 44 of 44 caught at their named checks.
- **Older tests changed for the new rules.** Check that each change keeps its test's purpose:
  - battery-10, -11 and -13 lines now carry their rate (and gas figures);
  - battery-10, -11 and -19 and race RC5b plant a posted bill's charge entry before its void;
  - battery-10 F11a is refused at insert now;
  - battery-19 Q4d expects the write-once refusal, and Q4f/Q4h retire and re-add instead of editing;
  - battery-15 C8 expects 42501, because DELETE was revoked.

## What to answer

1. **Does the patch implement the inventory and the decisions?** Name any requirement missed or half-done.
2. **Is there a path around any new rule?** Consider:
   - a delete or truncate of the 16 by any role, including through a cascade, a definer function or a rule;
   - a label deleted while in use, under any isolation or with a writer racing it (a COPY or a writable CTE);
   - a dependency edited rather than retired, or a retirement undone;
   - a bill issued with a line lacking its arithmetic: through INSERT born issued, a status path that skips the gate, a line added or changed after the check ran in the same transaction, a rate item reclassified at another coordinate, or the deferred check being SET IMMEDIATE / DEFERRED by the caller;
   - a void_reversal, correction or refund without its link;
   - a Cognito binding changed;
   - an inactive user passing RLS by another helper.
3. **The void.** Is "posted" exactly `first_issued_at`? Can a bill be posted without the stamp, or carry it without being posted? Is the charge lookup right (RLS as `tally_void`, `ORDER BY created_at, id`)? Does every path still meet `assert_seal_role_invariants()` and the -20 races?
4. **The label lock.** Is the deadlock note right? Does `SHARE` on a busy entity table (`customers`, `invoices`, `payments`) harm normal work beyond what the header says? Is the RLS reasoning (L4) right for a platform admin and for a caller with no user?
5. **The arithmetic check.** Is the gate right: issuance only, not a void-discard, not issued→issued? Is `(period_end, now())` the right coordinate for the calculation type? Is anything required that a legitimate line cannot supply?
6. **The invariants.** Does `assert_no_hard_delete_invariants()` catch what it claims? Is any claim narrower than its check?
7. **The tests.** Is any check weaker than its label? Does any mutation pass for the wrong reason? What is missing? (Known gaps: the issued→issued gate and the lines' FOR SHARE have no mutation.)
8. **Residuals R1–R5.** Is any of them actually blocking?

## How to probe

You may query the running `tally-pg` read-only. For experiments, clone into your own scratch database, named for you only:
- Opus: `rv21opus`;
- Fable: `rv21fable`.

Clone with `CREATE DATABASE <name> TEMPLATE tally`. Revoke TEMP from PUBLIC, `tally_app` and `tally_core` on the clone right after creating it. Then apply the frozen patch strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

(`docker cp` the file into the container first.)

**Restrictions:**
- Roles are cluster-wide. Do not create, drop or alter any role.
- Do not run `mutations-21.py`: it uses the fixed name `m21`.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file.
- Drop your clone when done.

## Output

Write your full review to `tests/v5.4.2-21/review/<reviewer>-r1.md` (`opus`, `fable` or `codex`). It contains:
- a verdict: "ready" or "not yet";
- blocking items (B1…), each with the concrete path or repro;
- should-fix items (S1…);
- notes (N1…).

Mark each claim as **executed** or **predicted**. Your final message, under 2 KB, gives the verdict, the blocking items in one line each, and the file path. If you cannot write the file, send the review to main as several messages, each under 3 KB.
