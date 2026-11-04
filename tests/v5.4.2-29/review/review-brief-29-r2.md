# Review brief: v5.4.2-29 r2 — every Texas county and its time zone

**Date:** 2026-11-04. **Kind:** patch review, round 2.
**Reviewers:** Codex (its round 1 did not run: usage limit). Opus and Fable said ready on round 1 and may be asked to confirm the round-2 fixes. Read your own round-1 file if you have one, and the round-2 plan. Do not read the other reviewers' files.
**Stream:** rates (`~/code/tally-utility-rates`).

## Frozen files

Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-29/review/patch-29-frozen-r2.sql` | `0d0f118056684d942417493a46f6b43d` |
| `tests/v5.4.2-29/review/battery-29-frozen-r2.sql` | `c33a30571096b7254a227d38e46596d3` |
| `tests/v5.4.2-29/review/reapply-29-frozen-r2.sh` | `521fc0d02ca0c884dceaa30b81bc3a98` |
| `tests/v5.4.2-29/review/source-check-29-frozen-r2.sh` | `efb33dd9c856e70e4c10ef893a8e4449` |
| `tests/v5.4.2-29/review/mutations-29-frozen-r2.sh` | `c560c150ec066ed896c9bfc0c026875b` |
| `tests/v5.4.2-29/review/older-tests-29-frozen-r1.diff` | `e3deb2d46247209bd18f82a4350acbcc` |
| `tests/v5.4.2-29/review/older-tests-29-r1-to-r2.diff` | `cca76dd90e3ad57384062a4b84bbbbc5` |
| `application/places-sources/census-st48_tx_cou2020.txt` | `e1ea7280eb41b680feb924b3bef2c411` |

The live copies are identical to these. The frozen source check resolves its root two levels up, so run the live copy against the frozen patch: `tests/v5.4.2-29/source-check-29.sh tests/v5.4.2-29/review/patch-29-frozen-r2.sql`. To see everything round 2 changed, diff `patch-29-frozen-r1.sql` against `patch-29-frozen-r2.sql` (and the other frozen pairs). `older-tests-29-frozen-r1.diff` is round 1's change to earlier tests; `older-tests-29-r1-to-r2.diff` is round 2's (battery -16 comments, `tests/ci.sh`).

## What the patch does

A data-only patch (no DDL). It loads the 252 Texas counties that -16 did not seed as `places` rows (kind county, the Census FIPS code and name, parent Texas, from 1900-01-01), each with one `time_zone` fact: Central for all but El Paso and Hudspeth, which -16 seeded in Mountain and which are checked, not reloaded. Sources: the Census 2020 Texas county list (copied into `application/places-sources/`) and 49 CFR 71.6(a), 71.7(e), 71.8. Why: Ryan, 2026-11-04 (DECISION-LOG, the -28 r2 entry); -28 known limit L1; -16 residual R2.

## What round 2 changes

The fix list is `application/rates-build-2026-11-04/v5.4.2-29-r2-plan.md`:
- **S1 (Opus S1, Fable S1):** the load judges everything as of 1900-01-01, not "open today", so it re-applies as a no-op after a later correction. Reapply P8 and P9 (both fail on r1); mutations N16 and N17.
- **S2 (Fable S2):** the stored citations now name 71.6(a) (Central) and 71.8 (Mountain) beside 71.7(e); battery C5.
- **S3 (Opus S2):** the in-loop comparison is diagnostic and the postcondition is the guard; mutations N14 and N15 remove a comparison from both layers (the load is then admitted).
- **S4 (Opus S3):** P6 and P6b grant TEMP on the clone and expect "permission denied for table places" (tally_app, tally_core).
- **S5 (Fable S3):** battery -16's comments.
- **Notes:** the CI marker is one variable, and a marker that errors stops the run; L3 (towns on the Texas–New Mexico border); L6 (provenance of the two seeded rows); `our-sources.md`.

Since round 1, the money stream mirrored -23 into `tu.sql` and rebuilt `tally` (2026-11-04). Round 2's results are on that build.

## Drafting calls to check in particular

- **As of 1900.** Is "the row in force on 1900-01-01" the right identity for "already present"? What does the load do with a county closed before today, a county whose 1900 row was closed and succeeded, or a Texas state row that is closed and succeeded?
- **Refuse, not overwrite**, and the closed list as of 1900. Can a legitimate row trip either?
- **Culberson** stored as Central (L2); the citations.
- **The fixture moves** (round 1's diff), and the CI marker.

## Known limits (in the patch header)

L1 a premise still needs its county recorded. L2 Culberson is Central by law. L3 towns on the line (71.7(g)) are a city-load question. L4 counties only. L5 dated from 1900. L6 El Paso and Hudspeth keep -16's notes.

## Results so far (reproduce them)

- **Strict apply, twice:** clean (252 loaded, then none).
- **`battery-29.sql`:** 22 PASS on `tally` (with -23) + -29.
- **`reapply-29.sh`:** 10 of 10.
- **`source-check-29.sh`:** 5 of 5.
- **`mutations-29.sh`:** 19 of 19, each at its named place; N14's load was checked to exit 0 (admitted).
- **`tests/ci.sh`:** every step passes (53) except battery -15 case V23, the money stream's fixed date that has passed (unchanged).

## What to answer

1. Does each round-2 fix close its finding, with nothing the ruling didn't ask for?
2. Is the data right, against the two sources?
3. Is there a path around any rule (roles, isolation levels, a partly loaded state, a re-apply after a correction)?
4. Did round 2 break anything round 1 had right?
5. The tests: is any claim narrower than its check, or any mutation caught for the wrong reason?
6. Do L1–L6 block?

## How to probe

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, `reapply-29.sh` or the mutation runner. You may run `source-check-29.sh` (it reads files only) and read-only shell commands. Every database claim must be a probe file in `tests/v5.4.2-29/review/codex-r2-probes/`. Each probe runs as the owner on a fresh clone of `tally` with frozen r2 applied, ends in ROLLBACK, and prints the SQLSTATE and message of each caught error with RAISE NOTICE.

**Opus or Fable**, if asked: scratch database `rv29opus` / `rv29fable`, cloned from `tally`, TEMP revoked from PUBLIC, `tally_app` and `tally_core` right after creating it; apply the frozen patch strictly.

**Restrictions:** do not create, drop or alter any role; never modify `tally`, `sql/tu.sql` or any repo file except your output (and Codex's probes); drop your clone; do not run `tests/ci.sh`.

## Output

Write your full review to `tests/v5.4.2-29/review/<reviewer>-r2.md`: a verdict ("ready" or "not yet"); blocking items (B1…) with the concrete path or repro; should-fix items (S1…); notes (N1…). Mark each claim executed or predicted. Your final message gives the verdict, the blocking items in one line each, and the file path, in several messages each under 3 KB.
