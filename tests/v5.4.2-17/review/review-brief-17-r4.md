# Review round 4 (Codex): v5.4.2-17 — the rule-terms convention, written once

You are one of three independent reviewers (separate models; you will not see each other's work).

**Frozen artefacts** (repo `/Users/ryanscomputer/code/tally-utility`; check the hashes and say if they differ):
- patch `tests/v5.4.2-17/review/patch-17-frozen-r4.sql` — md5 `ad7045b9e680af4ca0f72212013a7cd5` (3080 lines)
- battery `tests/v5.4.2-17/review/battery-17-frozen-r4.sql` — md5 `a24cdfb2cf48d8ec9e137468d26e84c1`
- the ZZ fixture area `law/fixtures/zz/` (`fixture-zz.sql`, three schemas, a law file, its seed SQL, examples)
- isolation `tests/v5.4.2-17/isolation-17.sh` (+ `fixture-iso-17.sql`); races `tests/v5.4.2-17/races/rule-close-17.sh`; law files `tests/v5.4.2-17/lawfiles-17.sh`; mutations `tests/v5.4.2-17/mutations-17.py`
- tooling `tools/law/lawc.py` (+ `requirements.txt`); `law/README.md`; CI `tests/ci.sh`, `.github/workflows/ci.yml`

**The spec it was drafted against:** `application/rule-terms-step2-source-inventory-2026-10-07.md` (requirements V1–V10, F1–F7, T1–T7, U1–U5, P1–P4, C1–C4, L1–L4; §3 lists the design points settled by standing rules; §4 the three defaults Ryan approved). The convention itself: `application/rule-terms-convention-v2-2026-10-06.md` (adopted). Its first two consumers, which this machinery must serve: `sql/v5.4.2-13-backbilling-caps.sql` (in tu.sql; to be migrated) and the draft `sql/v5.4.2-15-deposits-law-to-core.sql` (to be rewritten). The base schema is `sql/tu.sql` (the -16 build; grep, don't read whole). House patterns: `sql/v5.4.2-16-places-and-applicability.sql`.

**Context.** Gas-utility billing platform; PostgreSQL 16 with RLS (`tally_app` is the application role; platform tables are read-only to it); a C# core is planned but not written; nothing is live. Launch customers are Texas city-owned gas systems, which Texas gas law does not reach — their policy is their own tariff rows, under a "delegated_to_utility" law row. This patch ships no area's tables: only the machinery (registry, validator, facets, the law/tariff template, published values, `tally_core`, audit findings, the inputs fingerprint) and a fictional-state fixture that proves it.

## Rounds 1-3 and what changed
Your round-2 review said "not yet" on three items; round 3 (r3) was reviewed by Opus and Fable ("ready") while you were unavailable, and r4 folds their last points. Dispositions: `review-findings-17-r2.md` (your round-2 items), `review-findings-17-r3.md`. Diffs: `diff …/patch-17-frozen-r2.sql …/patch-17-frozen-r3.sql` and `… -r3 … -r4`.

## What to do
0. **Verify your round-2 findings.** For B1 (facet-to-column type matching), B2 (depth under unions) and B3 (filled documents at adopting registration), and your should-fixes (NUL/surrogates, the reusable core invariant, the freeze hash, isolated guard cases, APPLY phrases), say whether r4 holds each, and whether the r3/r4 changes opened a new hole.
1. **Does it hold the spec?** For each inventory requirement classed Step 2, say whether the patch (or tooling) holds it, states it as a residual (section 11), or misses it. Will the -13 migration and the -15 rewrite actually be able to use this as built? Is any template choice wrong for them — the applicability spans (owner types / system kinds / jurisdiction as sets with NULL = every one), the area key (NOT NULL, `=`), "records cite the law row always and a tariff row optionally", a tariff checked against the law rows that share its key columns, the one-time adoption of pre-convention rows, `rule_row_seed`'s notion of "the same row"?
2. **Integrity.** Find ways to put a record in a state the header says is refused, to make the validator accept a document its schema refuses (or refuse one it accepts), to make a lookup return a wrong row instead of refusing, or to reach data across tenants. Think about: the interpreter's subset (any keyword or combination where it and a standard 2020-12 validator would disagree; the discriminator rule; `$ref`; numbers; strings and Unicode; depth); the duplicate-key parser; facets (paths, types, vocabulary scope and dynamic SQL); the generic triggers' use of `to_jsonb(NEW)` / `jsonb_populate_record`; the close and freeze lock protocols and isolation; `rule_row_seed`; the adoption path; `tally_core`'s privileges (TEMP, CREATE, function EXECUTE, materialized views, default privileges, RLS); audit findings' subject checks; `stamp_core_inputs`; anything that is SECURITY- or trigger-depth-sensitive.
3. **Tests.** Is every guard tested by a case only it can refuse? Missing negative cases? Mutations that would be missed? Does the cross-check (W4) prove what it claims?
4. Verdict: **ready** / **not yet** (list blocking items). Separate findings: blocking, should-fix, note. Ground every claim in file:line or a reproduction.

## How to probe (Opus and Fable)
Never touch the `tally` or `postgres` databases or the repo files. Make your own clone:
```
docker exec tally-pg psql -U tally -d postgres -c "CREATE DATABASE <yourname>17 TEMPLATE tally"
docker exec tally-pg psql -U tally -d <yourname>17 -c "REVOKE TEMP ON DATABASE <yourname>17 FROM PUBLIC, tally_app"
(echo "SET search_path = ''; SET check_function_bodies = on;"; cat tests/v5.4.2-17/review/patch-17-frozen-r4.sql) | docker exec -i tally-pg psql -U tally -d <yourname>17 -1 -v ON_ERROR_STOP=1 -q -f -
```
(`CREATE DATABASE … TEMPLATE` drops the database ACL, hence the REVOKE.) To load the ZZ fixture area into your clone: `docker cp law tally-pg:/tmp/law`, then run `BEGIN; \i /tmp/law/fixtures/zz/fixture-zz.sql` … in psql (it registers kinds and tables; the battery shows how rows, profiles and tariffs are written). Write probes as `tally_app` or `tally_core` with `SET LOCAL app.user_id` where the guard is about the application or the core. The tooling runs with `tools/law/.venv/bin/python tools/law/lawc.py` and `LAWC_DB=<yourname>17`. Drop your databases when done.

## Output
Write the full review to `OUTPUT_PATH`. Final reply SHORT (under 2,500 characters): verdict, blocking items, top should-fix.
