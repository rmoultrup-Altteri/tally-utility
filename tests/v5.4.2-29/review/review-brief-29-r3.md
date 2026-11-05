# Review brief: v5.4.2-29 r3 — every Texas county and its time zone

**Date:** 2026-11-05. **Kind:** patch review, round 3.
**Reviewers:** Codex (said not yet on round 2: `codex-r2.md`), Opus and Fable (ready on round 1; they have not reviewed round 2 or 3). Read your own earlier file, and the round-2 and round-3 plans (`application/rates-build-2026-11-04/v5.4.2-29-r2-plan.md`, `-r3-plan.md`). Do not read the other reviewers' files.
**Stream:** rates (`~/code/tally-utility-rates`).

## Frozen files

Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-29/review/patch-29-frozen-r3.sql` | `a3030b836fce0eeb6609a2464a797362` |
| `tests/v5.4.2-29/review/battery-29-frozen-r3.sql` | `c33a30571096b7254a227d38e46596d3` |
| `tests/v5.4.2-29/review/reapply-29-frozen-r3.sh` | `e949fbc171ea4f814f179c55a01e4424` |
| `tests/v5.4.2-29/review/source-check-29-frozen-r3.sh` | `efb33dd9c856e70e4c10ef893a8e4449` |
| `tests/v5.4.2-29/review/mutations-29-frozen-r3.sh` | `7cc5ae564b136f04803dd7a5fe521af6` |
| `tests/v5.4.2-29/review/older-tests-29-r2-to-r3.diff` | `a2472b325a0a10655bb4cbf7036326a6` |
| `application/places-sources/census-st48_tx_cou2020.txt` | `e1ea7280eb41b680feb924b3bef2c411` |

The live copies are identical to these. The frozen source check resolves its root two levels up, so run the live copy against the frozen patch: `tests/v5.4.2-29/source-check-29.sh tests/v5.4.2-29/review/patch-29-frozen-r3.sql`. To see what round 3 changed, diff the `-frozen-r2` and `-frozen-r3` pairs (battery and source check are unchanged); if you have not reviewed round 2, diff r1 against r2 as well. `older-tests-29-frozen-r1.diff`, `older-tests-29-r1-to-r2.diff` and `older-tests-29-r2-to-r3.diff` (`tests/ci.sh` only) are each round's change to files outside -29's own.

## What the patch does

A data-only patch (no DDL). It loads the 252 Texas counties that -16 did not seed as `places` rows (kind county, the Census FIPS code and name, parent Texas, from 1900-01-01), each with one `time_zone` fact: Central for all but El Paso and Hudspeth, which -16 seeded in Mountain and which are checked, not reloaded. Sources: the Census 2020 Texas county list (copied into `application/places-sources/`) and 49 CFR 71.6(a), 71.7(e), 71.8. Why: Ryan, 2026-11-04 (DECISION-LOG, the -28 r2 entry); -28 known limit L1; -16 residual R2.

## What round 3 changes

The fix list is `application/rates-build-2026-11-04/v5.4.2-29-r3-plan.md`:
- **B1 (Codex B1):** Texas is looked up as the row in force on 1900-01-01, not the open one, so re-applying after Texas is closed and succeeded is a no-op. Reapply P10 and P10b (both fail on r2); mutation N18. This is the only change to the patch (two lines, the message and the header).
- **S1 (Codex S1):** a failing re-apply case says how it failed (`[admitted]`, `[refused otherwise]`, `[refused]`, `[changed]`), and each RE mutation names the outcome it requires.
- **S2 (Codex S2):** `tests/ci.sh` checks the second read of the -29 pending marker as it checks the first.
- **S3 (Codex S3):** P7, P8 and P10 compare every places and place_facts row before and after; P8's successors differ from what they replace, and one county is closed with no successor.

Round 2 (for Opus and Fable, who have not seen it) is summarised in its plan: everything judged as of 1900-01-01, the 71.6(a)/71.8 citations, the two layers (diagnostic and guard), the role cases, the CI marker.

## Drafting calls to check in particular

- **As of 1900.** Is "the row in force on 1900-01-01" the right identity for "already present"? What does the load do with a county closed before today, a county whose 1900 row was closed and succeeded, or a Texas state row that is closed and succeeded (round 3's fix)? Is the parent rule the right refusal for a county inserted under a Texas closed since (P10b)?
- **Refuse, not overwrite**, and the closed list as of 1900. Can a legitimate row trip either?
- **Culberson** stored as Central (L2); the citations.
- **The fixture moves** (round 1's diff), and the CI marker.

## Known limits (in the patch header)

L1 a premise still needs its county recorded. L2 Culberson is Central by law. L3 towns on the line (71.7(g)) are a city-load question. L4 counties only. L5 dated from 1900. L6 El Paso and Hudspeth keep -16's notes.

## Results so far (reproduce them)

- **Strict apply, twice:** clean (252 loaded, then none).
- **`battery-29.sql`:** 22 PASS on `tally` (with -23 and -28) + -29.
- **`reapply-29.sh`:** 12 of 12. On frozen r2, P10 fails `[refused]` and P10b `[refused otherwise]`.
- **`source-check-29.sh`:** 5 of 5.
- **`mutations-29.sh`:** 20 of 20, each at its named place and in its named way.
- **`tests/ci.sh`:** all 54 steps pass on `tally` (with -23 and -28), -29 r3 pending (battery -15 V23 is fixed: the money stream, 2026-11-04).
- **Codex's r2 probes:** all five executed; every prediction held (`codex-r2.md`, the author's section).

## What to answer

1. Does each round-3 fix (and, if you have not reviewed it, each round-2 fix) close its finding, with nothing the ruling didn't ask for?
2. Is the data right, against the two sources?
3. Is there a path around any rule (roles, isolation levels, a partly loaded state, a re-apply after a correction)?
4. Did round 3 break anything round 2 had right?
5. The tests: is any claim narrower than its check, or any mutation caught for the wrong reason?
6. Do L1–L6 block?

## How to probe

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, `reapply-29.sh` or the mutation runner. You may run `source-check-29.sh` (it reads files only) and read-only shell commands. Every database claim must be a probe file in `tests/v5.4.2-29/review/codex-r3-probes/`. Each probe runs as the owner on a fresh clone of `tally` with frozen r3 applied, ends in ROLLBACK, and prints the SQLSTATE and message of each caught error with RAISE NOTICE.

**Opus and Fable:** scratch database `rv29opus3` / `rv29fable3`, cloned from `tally`, TEMP revoked from PUBLIC, `tally_app` and `tally_core` right after creating it; apply the frozen patch strictly.

**Restrictions:** do not create, drop or alter any role; never modify `tally`, `sql/tu.sql` or any repo file except your output (and Codex's probes); drop your clone; do not run `tests/ci.sh`.

## Output

Write your full review to `tests/v5.4.2-29/review/<reviewer>-r3.md`: a verdict ("ready" or "not yet"); blocking items (B1…) with the concrete path or repro; should-fix items (S1…); notes (N1…). Mark each claim executed or predicted. Your final message gives the verdict, the blocking items in one line each, and the file path, in several messages each under 3 KB.
