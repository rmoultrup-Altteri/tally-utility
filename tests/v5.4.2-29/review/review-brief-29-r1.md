# Review brief: v5.4.2-29 r1 — every Texas county and its time zone

**Date:** 2026-11-04. **Kind:** patch review, round 1.
**Reviewers:** Opus, Fable and Codex, independently. Do not read the other reviewers' files.
**Stream:** rates (`~/code/tally-utility-rates`). Read the repo at that path.

## Frozen files

Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-29/review/patch-29-frozen-r1.sql` | `766357ccbbb3aa6cd03937ca14df59d8` |
| `tests/v5.4.2-29/review/battery-29-frozen-r1.sql` | `3c504844eb5b67d1509ae4b43999df0f` |
| `tests/v5.4.2-29/review/reapply-29-frozen-r1.sh` | `3530ea5ccf80a30201c6cf15332e1331` |
| `tests/v5.4.2-29/review/source-check-29-frozen-r1.sh` | `efb33dd9c856e70e4c10ef893a8e4449` |
| `tests/v5.4.2-29/review/mutations-29-frozen-r1.sh` | `b5aa46663627993ef839187ff52f7c2c` |
| `tests/v5.4.2-29/review/older-tests-29-frozen-r1.diff` | `e3deb2d46247209bd18f82a4350acbcc` |
| `application/places-sources/census-st48_tx_cou2020.txt` | `e1ea7280eb41b680feb924b3bef2c411` |

The live copies (`sql/v5.4.2-29-texas-counties.sql`, `tests/v5.4.2-29/`) are identical to these today. `older-tests-29-frozen-r1.diff` is the change to earlier tests: fixture county codes moved off real FIPS codes in battery -16, race place-close-16 and battery -28, and -29's lines in `tests/ci.sh`.

## What the patch does

A data-only patch (no DDL). It loads the 252 Texas counties that -16 did not seed as `places` rows (kind county, the Census FIPS code and name, parent Texas, from 1900-01-01), each with one `time_zone` fact: Central (`America/Chicago`) for every county but El Paso and Hudspeth, which -16 seeded in Mountain (`America/Denver`) and which are checked, not reloaded. The source files are the Census 2020 Texas county list (copied into `application/places-sources/`) and 49 CFR 71.7(e) (the line is Hudspeth County's east line). A county already present must match by name and zone, or the whole load refuses. Afterwards the open Texas counties must be exactly the list. Re-applying is a no-op.

Why: Ryan, 2026-11-04 (DECISION-LOG, the -28 r2 entry). -28's state-agency fee check reads the bill's premise's time zone, and refuses when none can be read. Until now only El Paso and Hudspeth could be recorded, so a non-zero fee anywhere else was refused (-28 known limit L1). Counties and their zones rarely change, so they are loaded once as shared platform data. -16 residual R2 already said counties would come by reviewed migration from the Census.

## Drafting calls to check in particular

- **Refuse, not overwrite.** A present county that differs refuses the whole load rather than being corrected. Is that right for a platform load, given that a correction is a close plus a successor?
- **The closed-list postcondition.** An open Texas county not on the Census list refuses the load. Can a legitimate row trip it (a test fixture committed into a shared database, or a future county)?
- **Culberson.** It is legally Central and locally Mountain. The patch stores the legal zone (known limit L2). Is anything in the schema hurt by that?
- **Dates.** From 1900-01-01, per -16's R2. Is there any interaction with facts or memberships dated earlier?
- **The fixture moves.** Real codes in older tests are replaced by even codes (48990–48998); Texas county codes are odd. Does any older test lose what it proved?
- **CI.** The new `?` marker form in `tests/ci.sh` (an SQL condition true while pending), and `reapply-29.sh` running only while pending.

## Known limits (in the patch header)

- **L1.** A premise still needs its county recorded (a membership, the utility's data). One with none is refused as before.
- **L2.** Culberson: the legal zone is stored, not local practice.
- **L3.** 49 CFR 71.7(g), a municipality on the line: cities are not loaded here.
- **L4.** Counties only; cities, districts, transit and tax jurisdictions come later.
- **L5.** Dated from 1900-01-01.

## Results so far (reproduce them)

- **Strict apply, twice:** clean; the first loads 252 counties, the second none.
- **`battery-29.sql`:** 22 PASS on `tally` + -29.
- **`reapply-29.sh`:** 7 of 7 (refusal of a misnamed, wrongly zoned, or zone-less present county; refusal of a county not on the list; refusal under REPEATABLE READ and as tally_app; idempotence).
- **`source-check-29.sh`:** 5 of 5.
- **`mutations-29.sh`:** 15 of 15, each at its named place.
- **`tests/ci.sh`:** every step passes (56, including -29's strict apply, battery, source check and load rules, and every older battery and race on the moved fixtures) except battery -15 case V23, the money stream's fixed due date that has passed (a board note, unchanged).

## What to answer

1. Is the data right: every county, every name, every zone, against the two sources?
2. Is there a path around any rule (roles, isolation levels, a partly loaded state, a re-apply after a correction)?
3. Does the patch or the fixture move break anything earlier patches had right?
4. The tests: is any claim narrower than its check, or any mutation caught for the wrong reason?
5. Do L1–L5 block?

## How to probe

**Opus and Fable** may query the running `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv29opus`, Fable `rv29fable`):
1. `CREATE DATABASE <name> TEMPLATE tally`.
2. Right after creating it, revoke TEMP on the clone from PUBLIC, `tally_app` and `tally_core`.
3. `docker cp` the frozen patch into the container and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

**Codex reviews source only.** Do not run docker, psql, `ci.sh` or the scripts. Every database claim must be a probe file in `tests/v5.4.2-29/review/codex-r1-probes/`. Each probe runs as the owner on a fresh clone of `tally` with frozen r1 applied, ends in ROLLBACK, and prints the SQLSTATE and message of each caught error with RAISE NOTICE. You may run `source-check-29.sh` (it reads files only) and any read-only shell command over the repo.

**Restrictions (everyone):**
- Do not create, drop or alter any role.
- Do not run `mutations-29.sh` or `reapply-29.sh`; they use fixed database names.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done. Do not run `tests/ci.sh`.

## Output

Write your full review to `tests/v5.4.2-29/review/<reviewer>-r1.md` (`opus`, `fable` or `codex`): a verdict ("ready" or "not yet"); blocking items (B1…) with the concrete path or repro; should-fix items (S1…); notes (N1…). Mark each claim **executed** or **predicted**. Your final message gives the verdict, the blocking items in one line each, and the file path, in several messages, each under 3 KB.
