# Review brief: v5.4.2-25 r9 — one sentence of R10, diff only

**Date:** 2026-11-27. **Kind:** patch review, round 9 (a check of a one-paragraph change).
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's files for this round. Each of you may read your own round-8 review (`opus-r8.md`, `fable-r8.md`, `codex-r8.md`).

## Frozen files

Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-25/review/patch-25-frozen-r9.sql` | `9dae050be1a905d5263d9293d8c83976` |
| `tests/v5.4.2-25/review/battery-25-frozen-r9.sql` | `772c6a71dc7fef67220e318a87032cef` |
| `tests/v5.4.2-25/review/disputes-25-frozen-r9.sh` | `ba77a03997a856bd00d90d3c0e7fcb88` |
| `tests/v5.4.2-25/review/mutations-25-frozen-r9.py` | `68ee1252a020b63f67c522e05c120eeb` |
| `tests/v5.4.2-25/review/terms-25-frozen-r9.py` | `83d1484349ef8c3ad654eb40f2264eb6` |
| `tests/v5.4.2-25/review/migration-25-frozen-r9.py` | `55d80759b4066f5a037acc3bd104be20` |
| `tests/v5.4.2-25/review/fill-manifest-25-frozen-r9.py` | `33802a5b696602534f9b1b521981fc5d` |
| `tests/v5.4.2-25/review/dispute_platform_defaults-frozen-r9.yaml` | `deb668299bc3bd44d1eb72a1aeb117d4` |
| `tests/v5.4.2-25/review/dispute_platform_defaults-frozen-r9.seed.sql` | `3832a44f5ae4c788a8451479390906ec` |
| `tests/v5.4.2-25/review/r8-to-r9.diff` | `612c0f9ed6094a015956d19af8b7731c` |

The live copies are identical today. Only the patch changed since r8, and only in its header's residual R10 (a SQL comment). Every other file is byte-identical to its r8 copy.

## Scope

**Review the diff only:** `r8-to-r9.diff` (37 lines). Round 8: Opus and Fable ready; Codex not yet, on R10's last sentence alone ("No seeded law row has a stage that is not final where a policy's could be", which is false: 7.45's employee stage is not final). Opus's S1 named the same sentence. Read `application/wave3-build-2026-10-18/v5.4.2-25-r9-plan.md` (half a page) and the "Round 8 reviewed" section of `v5.4.2-25-r8-plan.md`.

What r9 changes: R10's direction (a) now says that before the law's last stage the law's later stages follow, so the customer keeps every appeal the law gives (7.45's employee stage is such a place), and that only at the law's last stage does which protects more depend on the customer. The seed sentence now reads "No seeded law row has a last stage that is not final". "Both are safe only as the core reads final" became "both rest on the core reading final".

## What to check

- Is R10 now true of the code and of the seeded law rows, in every clause?
- Is "the customer keeps every appeal the law gives" right whenever the replaced stage is before the law's last (including a law stage that the policy's list displaces)?
- Did anything outside that comment change?
- Is any item from your round-8 review still open?

## Results so far

- Strict apply, twice; the second run skipped by its marker.
- `battery-25.sql`: 351 of 351. `mutations-25.py`: 199 of 199, each at its named check. `tests/ci.sh`: 59 of 59.

## How to probe

**Opus and Fable** may query `tally-pg` read-only, and experiment on their own clone (Opus `rv25opus`, Fable `rv25fable`; drop any left over first): `CREATE DATABASE <name> TEMPLATE tally`; revoke TEMP on it from PUBLIC, `tally_app` and `tally_core` at once; `docker cp` the frozen patch in and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Any database claim is a probe file in `tests/v5.4.2-25/review/codex-r9-probes/`: owner, fresh clone with frozen r9 applied, ending in ROLLBACK, printing SQLSTATE and message for each caught error with RAISE NOTICE. The author will run them.

**Restrictions (everyone):** do not create, drop or alter any role; do not run `mutations-25.py` or `tests/ci.sh`; never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes); drop your clone when done.

**Output:** `tests/v5.4.2-25/review/<you>-r9.md` (opus, fable, codex): verdict "ready" or "not yet"; items B (blocking), S (should fix), N (note), each marked executed or predicted, with the evidence. Keep your final message short; the file is the review.
