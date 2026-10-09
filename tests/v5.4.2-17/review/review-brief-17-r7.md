# Review round 7 (all three reviewers) — the r6-to-r7 diff only: v5.4.2-17 — the rule-terms convention, written once

You are one of three independent reviewers (separate models; you will not see each other's work).

**Frozen artefacts** (repo `/Users/ryanscomputer/code/tally-utility`; check the hashes and say if they differ):
- patch `tests/v5.4.2-17/review/patch-17-frozen-r7.sql` — md5 `b2684ffd74aaa19998cd58b470ba6883` (3377 lines)
- battery `tests/v5.4.2-17/review/battery-17-frozen-r7.sql` — md5 `e07b5516aa22f0103ab15086c93d5937` (262 PASS lines)
- the ZZ fixture area `law/fixtures/zz/` (`fixture-zz.sql`, three schemas, a law file, its seed SQL, examples)
- isolation `tests/v5.4.2-17/isolation-17.sh` (+ `fixture-iso-17.sql`); races `tests/v5.4.2-17/races/rule-close-17.sh`; law files `tests/v5.4.2-17/lawfiles-17.sh`; mutations `tests/v5.4.2-17/mutations-17.py`
- tooling `tools/law/lawc.py` (+ `requirements.txt`); `law/README.md`; CI `tests/ci.sh`, `.github/workflows/ci.yml`

**The spec it was drafted against:** `application/rule-terms-step2-source-inventory-2026-10-07.md` (requirements V1–V10, F1–F7, T1–T7, U1–U5, P1–P4, C1–C4, L1–L4; §3 lists the design points settled by standing rules; §4 the three defaults Ryan approved). The convention itself: `application/rule-terms-convention-v2-2026-10-06.md` (adopted). Its first two consumers, which this machinery must serve: `sql/v5.4.2-13-backbilling-caps.sql` (in tu.sql; to be migrated) and the draft `sql/v5.4.2-15-deposits-law-to-core.sql` (to be rewritten). The base schema is `sql/tu.sql` (the -16 build; grep, don't read whole). House patterns: `sql/v5.4.2-16-places-and-applicability.sql`.

**Context.** Gas-utility billing platform; PostgreSQL 16 with RLS (`tally_app` is the application role; platform tables are read-only to it); a C# core is planned but not written; nothing is live. Launch customers are Texas city-owned gas systems, which Texas gas law does not reach — their policy is their own tariff rows, under a "delegated_to_utility" law row. This patch ships no area's tables: only the machinery (registry, validator, facets, the law/tariff template, published values, `tally_core`, audit findings, the inputs fingerprint) and a fictional-state fixture that proves it.

## Scope: the r6-to-r7 diff only
Round 6 (Opus, Fable, Codex): all three **ready**, no blocking item; six should-fix groups (`review-r6-*.md`; dispositions in `review-findings-17-r6.md`). r7 folds them and nothing else. Read `diff patch-17-frozen-r6.sql patch-17-frozen-r7.sql` and `diff battery-17-frozen-r6.sql battery-17-frozen-r7.sql`; everything outside those diffs was reviewed in rounds 1-6 and is not under review again unless an r7 change touches it. The r7 changes:
1. `rule_table_trigger_errors` (and the assertion that uses it): each template trigger is known by function (resolved by name, no forward reference), `tgtype` 7 / 27 / 34, no WHEN, no column list, ENABLE ALWAYS; the sorts-after exemption is by name and function; a table with an inheritance child or any rewrite rule is refused (Codex S2, Opus S1, Fable S1). Cases T1q-T1v, mutations M169-M174.
2. A pre-convention row with `terms IS NULL`: `rule_law_row_as_of`, `rule_row_cite` and the tariff check's law read refuse it ("not yet adopted", 23514); adopting registration refuses a legacy row with a blank key or with spans that differ from its sets (Fable S2, Codex N2). Cases A5a-A5c, A1f, A1g, mutations M179-M183. The A fixture's mismatched-span row is now made after registration.
3. `rule_law_delegated_facet_errors` runs both standard delegated documents, with and without a note (Opus S2). T1z, M178.
4. The version clause also requires `strategy` (Fable S3). R4y, M167.
5. Cases for the trigger-name clauses: T1w (`rulerowa`), T1x (`Zz_early`), T1y (an AFTER ROW trigger), M175-M177. **Note:** dropping `COLLATE "C"` alone is behaviour-neutral (`pg_trigger.tgname` is C-collated and the cast keeps it); the patch keeps it with a comment and M175 compares in `en_US.utf8` instead. Say if you see a case where it is not neutral.
6. The discriminator message and `law/README.md` say a discriminator is written inline (Codex S1, Fable N2, Opus N5). R3j, M168. Residuals R22-R25 and the R14 wording are new.
Checks run: `tests/ci.sh` all pass; `mutations-17.py` 182/182 caught at their named checks (M167-M183 new; M63, M156, M159, M162 re-anchored); each new refusal case was run alone against r6 first (`tests/v5.4.2-17/r7-fail-first.py`) and failed there.

## What to do
1. **For each r7 change above:** does it do what the finding asked, with nothing it should refuse left through and nothing it should allow refused? Probe the edges: trigger shapes (a template trigger recreated with the right function on the wrong table events, with a transition table, deferrable constraint triggers, a trigger on a partition), tables with a partition child or a view over them, rules of every event, an inheritance child created and dropped; an unfilled legacy row reached by any other reader than the three fixed (seed, audit subjects, `rule_tariff_row_as_of`, the close floor); an adopting registration whose legacy rows are fine but whose spans compare unequal because of ordering or representation; the dry-run on a facet that depends on `note` in other ways.
2. **Did any r7 change open a hole in rounds 1-6?** Name the check and the probe.
3. **Tests.** Is every new clause caught by a case only it can fail? Say which mutation would survive.
4. Verdict: **ready** / **not yet** (blocking items). Separate blocking, should-fix, note. Ground every claim in file:line or a reproduction.

## How to probe (Opus and Fable)
If your sandbox cannot reach Docker, say so in the review and list what you could not run. Never touch the `tally` or `postgres` databases or the repo files. Make your own clone:
```
docker exec tally-pg psql -U tally -d postgres -c "CREATE DATABASE <yourname>17 TEMPLATE tally"
docker exec tally-pg psql -U tally -d <yourname>17 -c "REVOKE TEMP ON DATABASE <yourname>17 FROM PUBLIC, tally_app"
(echo "SET search_path = ''; SET check_function_bodies = on;"; cat tests/v5.4.2-17/review/patch-17-frozen-r7.sql) | docker exec -i tally-pg psql -U tally -d <yourname>17 -1 -v ON_ERROR_STOP=1 -q -f -
```
(`CREATE DATABASE … TEMPLATE` drops the database ACL, hence the REVOKE.) To load the ZZ fixture area into your clone: `docker cp law tally-pg:/tmp/law`, then run `BEGIN; \i /tmp/law/fixtures/zz/fixture-zz.sql` … in psql (it registers kinds and tables; the battery shows how rows, profiles and tariffs are written). Write probes as `tally_app` or `tally_core` with `SET LOCAL app.user_id` where the guard is about the application or the core. The tooling runs with `tools/law/.venv/bin/python tools/law/lawc.py` and `LAWC_DB=<yourname>17`. Drop your databases when done.

## Output
Write the full review to `OUTPUT_PATH`. Final reply SHORT (under 2,500 characters): verdict, blocking items, top should-fix.
