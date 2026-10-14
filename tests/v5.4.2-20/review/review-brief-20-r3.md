# Review brief: v5.4.2-20 r3, a diff-scoped confirmation round

**Date:** 2026-10-14. **Kind:** a short review of the r2→r3 diff only. Ryan agreed to a diff-scoped round.
**Reviewers:** Opus, Fable, Codex, independently.

## Why this round is short

All three of you said r2 was ready. r3 changes no guard, grant or function that the application or the void runs through. It makes the continuing invariant stricter, answering your r2 should-fix items, and adds test cases. Review only what changed.

## Frozen files

| File | md5 |
|---|---|
| `tests/v5.4.2-20/review/diff-20-r2-r3.diff` (the whole change, 237 lines) | `d95f7302b757c7a13757a031736f2997` |
| `tests/v5.4.2-20/review/patch-20-frozen-r3.sql` | `0ae593499b0dbf52a5bf306b8e7f3eee` |
| `tests/v5.4.2-20/review/battery-20-frozen-r3.sql` | `f5c9f9655d5f6aca8b15f6c9379833db` |
| `tests/v5.4.2-20/review/seal-20-frozen-r3.sh` | `5a2bf6dfc964db283858fd598437acd9` |

## The changes

- **Opus S1, Codex S2.** The invariant asserts `adhoc_charges_billed_names_its_bill`: present, validated, and with its exact expression.
- **Opus S2.** The trigger-shape list adds the three version tables' `a_enforce_bitemporal_assertion` guards (exact definition, `ALWAYS`), so it now holds 20 guards.
- **Codex S1.**
  - `seal_role_privileges()` records grant options.
  - The temporary-schema exclusion covers non-definer functions only.
  - The invariant refuses any table or column privilege held by PUBLIC in `public`. None exists today.
- **Codex S3.** The mutation harness:
  - stops a mutation on any setup failure;
  - reads the runner's output as one ordered stream;
  - requires the first failure line of any kind, infrastructure errors included, to be the named check.
- **Tests:**
  - S10h: the owner TRUNCATEs the receipts.
  - T7b: a void at SERIALIZABLE.
  - T7c: a void at REPEATABLE READ inside a savepoint.
  - The V1 fixture comment is corrected.
- **Mutations:** M41 is now caught at apply by the new CHECK assertion, and M50–M52 are added. The total is 53 of 53.

## Results (reproduce them)

- Strict apply, twice.
- `tests/ci.sh` passes in full.
- `battery-20`: 80 checks.
- `seal-20.sh`: RC1–RC6, RC3b, T1–T7c.
- `mutations-20.py`: 53 of 53.

## The one question

**Does any new check fail to catch what it claims, or refuse a correct state?** Consider:
- the PUBLIC clause, which might refuse something `tu.sql` or a later patch legitimately grants;
- the constraint-definition string, which might change with the deparser or the `search_path`;
- the grant-option strings;
- the narrowed temp exclusion against the battery's helpers.

Reply **"ready"** or name the blocking item. Should-fix items are welcome but optional.

## How to probe

As before. Your scratch database is `rv20opus` or `rv20fable`. Strict-apply the frozen r3 patch to a fresh clone with TEMP revoked. Do not create, drop or alter roles. Do not run `mutations-20.py`. Touch no file but your output. Drop your clone.

## Output

Write `tests/v5.4.2-20/review/<reviewer>-r3.md` (`opus`, `fable` or `codex`). Keep it short: a verdict, any blocking items, any should-fix items. Mark each claim as executed or predicted. Your final message must be under 1 KB.
