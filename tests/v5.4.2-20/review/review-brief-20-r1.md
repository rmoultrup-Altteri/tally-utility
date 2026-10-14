# Review brief: v5.4.2-20 r1, the version-check and void seals

**Date:** 2026-10-14. **Kind:** patch review, round 1.
**Reviewers:** Opus, Fable, Codex, independently. Do not read each other's files.

## Frozen files

Review exactly these. Check the hashes first, and stop and report if one differs.

| File | md5 |
|---|---|
| `tests/v5.4.2-20/review/patch-20-frozen-r1.sql` | `62e37198a7c0aa82086f16dbc24c9b8c` |
| `tests/v5.4.2-20/review/battery-20-frozen-r1.sql` | `27d501e2811ae7f1e4a7abce82133c7a` |
| `tests/v5.4.2-20/review/seal-20-frozen-r1.sh` | `52d4d8b5d4e5f22a3d79e19bd0b18c30` |

The live copies (`sql/v5.4.2-20-seal-version-check-and-void.sql`, `tests/v5.4.2-20/battery-20.sql`, `tests/v5.4.2-20/races/seal-20.sh`) are identical to the frozen ones today. Review the frozen copies.

## Background

You reviewed the design (`application/a23-seal-review-2026-10-14/brief.md` and your own `review-<you>.md` there). Ryan approved drafting the corrected design.

`application/a23-seal-review-2026-10-14/source-inventory-20.md` lists every requirement (R1–R5, S1–S7, V1–V4, O1–O5), each tagged with the finding it answers. The residuals left on purpose are R1–R9 in the patch header.

Changes since the design, made during drafting:
- **The void's explicit tenant comparison is removed.** RLS binds the owner, `tally_void`, so the comparison was a duplicate the mutation tests could not kill. The invariant asserts that the role cannot bypass RLS.
- **The receipt's transaction and time are stamped only by the receipts' trigger,** not also by the function. The duplicate stamping is removed.
- **The receipt test binds four things:** the transaction id, the transaction start time (`at = now()`, against id reuse after a restore), the entity, and the header's current version.
- **A bill is born void only in a superuser's history load.**

## Results so far (reproduce them)

- Strict apply, twice: `search_path = ''`, `check_function_bodies = on`. The second run is skipped by its marker.
- `tests/ci.sh` passes in full, with -20 pending. This includes batteries 09–20, the -15/-17 runners, every race script, and the tenant-isolation, core-role, seal-role and rule-table invariants.
- `battery-20.sql`: 74 checks. `races/seal-20.sh`: RC1–RC5, T1–T5.
- `mutations-20.py`: 38 of 38 caught at their named checks.
- Three older batteries changed (see the patch header, "Tests"):
  - battery-10 and battery-11 voided with no `app.user_id`, which passed only through the hole the patch closes;
  - battery-19 wrote a zone version with no check and used the old setting.
  Check that each change keeps its test's purpose.

## What to answer

1. **Does the patch implement the inventory?** Name any requirement missed or half-done.
2. **Is there a path around either seal?** That means any write of a version row, a header version or lifecycle move, a receipt, a lock release, an un-billing, or `status = 'void'` that does not go through the sealed act. Include:
   - other functions, triggers, rules and policies;
   - `tally_core`;
   - the superuser carve-outs that bind inside the void;
   - the owner session's `SET ROLE tally_void`, which the battery uses and whether a non-superuser can reach it;
   - deferred triggers;
   - COPY, TRUNCATE, writable CTEs, multi-row statements and MERGE.
3. **Grants.** Is `tally_void`'s grant list complete for every path `void_invoice()` takes? Consider each reason code, a `held` bill, a bill with line items, a bill with no reads or charges, and a platform administrator. Is anything granted that is not needed?
4. **The receipt test.** Is each of its four bindings necessary and sufficient? Is the `session_replication_role` forgery in S13 a faithful model of the attacks it stands for?
5. **The lock order and the attach guard.** Can a void and an attach deadlock? Is there an attach path the guard misses, for example a correction run's re-lock or a charge inserted billed? Under REPEATABLE READ?
6. **The invariants** (`assert_seal_role_invariants()`): does each clause catch what it claims, and is any claim narrower than its check?
7. **The tests.** Is any check weaker than its label? Does any mutation pass for the wrong reason? What is missing?
8. **The residuals R1–R9.** Is any of them actually blocking?

## How to probe

You may query the running `tally-pg` read-only. For experiments, clone into your own scratch database. Use only your own name:
- Opus: `rv20opus`;
- Fable: `rv20fable`.

Clone with `CREATE DATABASE <name> TEMPLATE tally`. Revoke TEMP from PUBLIC, `tally_app` and `tally_core` on the clone right after creating it. Then apply the frozen patch strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

The roles `tally_seal` and `tally_void` are cluster-wide and already exist. Do not drop or alter them; test attribute changes only inside a transaction you roll back. Do not create other roles.

Do not run `mutations-20.py`: it uses the fixed name `m20`. Never modify `tally`, `sql/tu.sql` or any repo file except your output file. Drop your clone when done.

## Output

Write your full review to `tests/v5.4.2-20/review/<reviewer>-r1.md` (`opus`, `fable` or `codex`). It contains:
- a verdict: "ready" or "not yet";
- blocking items (B1…), each with the concrete path or repro;
- should-fix items (S1…);
- notes (N1…).

Mark each claim as **executed** or **predicted**. Your final message, under 2 KB, gives the verdict, the blocking items in one line each, and the file path.
