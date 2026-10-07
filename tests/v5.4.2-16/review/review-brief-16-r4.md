# Review round 4: v5.4.2-16 — places and applicability

You are one of three independent reviewers (separate models; you will not see each other's work).

**Frozen artefacts** (repo `/Users/ryanscomputer/code/tally-utility`; check the hashes and say if they differ):
- patch `tests/v5.4.2-16/review/patch-16-frozen-r4.sql` — md5 `a0b43c01bda36c127707100c9726643f`
- battery `tests/v5.4.2-16/review/battery-16-frozen-r4.sql` — md5 `15eea127cf8d34da55d917325d947659`
- race script `tests/v5.4.2-16/races/place-close-16.sh`; mutations `tests/v5.4.2-16/mutations-16.py`

**The spec it was drafted against:** `application/places-source-inventory-2026-10-06.md` (requirements P1–P10, A1–A7, D1–D3) and `application/rule-terms-convention-v2-2026-10-06.md` §9. Research behind it: `application/places-sources/`. The base schema is `sql/tu.sql` (the -14 build; grep, don't read whole). House patterns to compare against: `sql/v5.4.2-13-backbilling-caps.sql` and the draft `sql/v5.4.2-15-deposits-law-to-core.sql`.

**Context.** Gas-utility billing platform; PostgreSQL with RLS (`tally_app` is the application role; platform tables are read-only to it); a C# core is planned but not written; nothing is live. Launch customers are Texas municipal gas systems, which Texas gas law does not reach (Utilities Code §101.003(7)(A)). The patch is foundation: every law and tariff row will later key on places, owner type and jurisdiction status.

**Rounds 1-3** (all three said "not yet" each time; in rounds 2 and 3 each on the same item): `tests/v5.4.2-16/review/review-findings-16-r{1,2,3}.md` list every finding and its disposition; the reviews are `review-r{1,2,3}-{opus,fable,codex}.md`. Review the revision fresh.

## What to do
0. **Did round 3's fixes hold?** For each item in `review-findings-16-r3.md` (B, S-d′, S-tz, S-key, S-err, S-uninc, T), say whether the revision fixes it and try to break it — especially: NaN and every other non-finite or non-positive distance; the state close floor and the profile's state-place lock (both orders, voided and boundary-dated profiles, a state with several rows); the time-zone lookup's new answering level (a place with no zone at that level, a level with none falling through, outside and voided rows, a city's zone over its county's, agreeing duplicates); the citation-form fact key (what real citations it refuses, what blanks still pass); the error code; one unincorporated area per state. Did a fix introduce a new hole? Rounds 1-2 fixes held under all three in round 3; recheck only what round 3's changes touch.
1. **Does it hold the spec?** For each inventory requirement, say whether the patch holds it, states it as a residual, or misses it. Is any modelling choice wrong for where this goes next (law rows keyed on owner type; tax jurisdictions; annexation; a utility in two states; a city system serving outside its limits)?
2. **Integrity.** Find ways to put the records in a state the header says is refused, or to make a lookup return a wrong answer instead of refusing. Think about: NULL legs; races (memberships/profiles vs a place close; two memberships racing the single-per-premise exclusion; profile overlap); RLS and tenant leakage through the shared tables, the lookups (invoker rights) or `jurisdictions.place_id`; the advisory-lock protocol; isolation levels; the normalised state read; the time-zone precedence; closes that orphan facts/children; anything a SECURITY or trigger-depth assumption gets wrong.
3. **Tests.** Is every guard tested by a case only it can refuse? Missing negative cases? Mutations that would be missed? (`mutations-16.py` now has 132; races R1-R18.)
4. Verdict: **ready** / **not yet** (list blocking items). Separate findings: blocking, should-fix, note. Ground every claim in file:line or a reproduction.

## How to probe (Opus and Fable)
Never touch the `tally` or `postgres` databases or the repo files. Make your own clone:
```
docker exec tally-pg psql -U tally -d postgres -c "CREATE DATABASE <yourname>16r4 TEMPLATE tally"
docker exec tally-pg psql -U tally -d <yourname>16r4 -c "REVOKE TEMP ON DATABASE <yourname>16r4 FROM PUBLIC, tally_app"
(echo "SET search_path = ''; SET check_function_bodies = on;"; cat tests/v5.4.2-16/review/patch-16-frozen-r4.sql) | docker exec -i tally-pg psql -U tally -d <yourname>16r4 -1 -v ON_ERROR_STOP=1 -q -f -
```
(`CREATE DATABASE … TEMPLATE` drops the database ACL, hence the REVOKE.) Write probes as `tally_app` with `SET LOCAL app.user_id` where the guard is about the application. Drop your database when done.

## Output
Write the full review to `OUTPUT_PATH`. Final reply SHORT (under 2,500 characters): verdict, blocking items, top should-fix.
