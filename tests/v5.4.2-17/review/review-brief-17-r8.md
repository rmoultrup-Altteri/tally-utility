# Review round 8 (all three reviewers) — the r7-to-r8 diff only: v5.4.2-17 — the rule-terms convention, written once

You are one of three independent reviewers (separate models; you will not see each other's work).

**Frozen artefacts** (repo `/Users/ryanscomputer/code/tally-utility`; check the hashes and say if they differ):
- patch `tests/v5.4.2-17/review/patch-17-frozen-r8.sql` — md5 `3da8dfa0a23f68bb25c4a4c9b3dbd389` (3452 lines)
- battery `tests/v5.4.2-17/review/battery-17-frozen-r8.sql` — md5 `49779ba424c6638df174bf41e4641a81` (272 PASS lines)
- the ZZ fixture area `law/fixtures/zz/` (`fixture-zz.sql`, three schemas, a law file, its seed SQL, examples)
- isolation `tests/v5.4.2-17/isolation-17.sh` (+ `fixture-iso-17.sql`); races `tests/v5.4.2-17/races/rule-close-17.sh`; law files `tests/v5.4.2-17/lawfiles-17.sh`; mutations `tests/v5.4.2-17/mutations-17.py`
- tooling `tools/law/lawc.py` (+ `requirements.txt`); `law/README.md`; CI `tests/ci.sh`, `.github/workflows/ci.yml`

**The spec it was drafted against:** `application/rule-terms-step2-source-inventory-2026-10-07.md` (requirements V1–V10, F1–F7, T1–T7, U1–U5, P1–P4, C1–C4, L1–L4; §3 lists the design points settled by standing rules; §4 the three defaults Ryan approved). The convention itself: `application/rule-terms-convention-v2-2026-10-06.md` (adopted). Its first two consumers, which this machinery must serve: `sql/v5.4.2-13-backbilling-caps.sql` (in tu.sql; to be migrated) and the draft `sql/v5.4.2-15-deposits-law-to-core.sql` (to be rewritten). The base schema is `sql/tu.sql` (the -16 build; grep, don't read whole). House patterns: `sql/v5.4.2-16-places-and-applicability.sql`.

**Context.** Gas-utility billing platform; PostgreSQL 16 with RLS (`tally_app` is the application role; platform tables are read-only to it); a C# core is planned but not written; nothing is live. Launch customers are Texas city-owned gas systems, which Texas gas law does not reach — their policy is their own tariff rows, under a "delegated_to_utility" law row. This patch ships no area's tables: only the machinery (registry, validator, facets, the law/tariff template, published values, `tally_core`, audit findings, the inputs fingerprint) and a fictional-state fixture that proves it.

## Scope: the r7-to-r8 diff only
Round 7 (Opus, Fable, Codex): Opus and Fable **ready**, Codex **not yet** on one blocker (`review-r7-*.md`; dispositions in `review-findings-17-r7.md`). r8 folds them and nothing else. Read `diff patch-17-frozen-r7.sql patch-17-frozen-r8.sql` and the same for the battery; everything outside is not under review again unless an r8 change touches it. The r8 changes:
1. `rule_law_delegated_facet_errors` tries the note-bearing delegated document only where a delegated branch of the kind's schema has a `note` property (Codex B1, Opus S2). T1za, T1zb; M184, M185.
2. `rule_row_scope_check(table, role, row)` (state known; system kind(s) of the row's service) is extracted from `rule_row_prepare` and is called by it unchanged in behaviour. Adopting registration now runs, per legacy row, `rule_key_check`, `rule_row_scope_check` and the span compare — the fill's own checks — replacing r7's inline key and span SQL (Opus S1, Fable S1). A1f-A1l; M190-M195.
3. The audit-findings guard refuses a rule row whose document is empty (Fable S4, Codex S1). K4i; M187.
4. Registration refuses a template, key or facet column that is generated (Opus note). T1ze; M186.
5. Cases and mutations for r7 clauses that had none: the `public` schema test on the trigger function (T1zd, M188); the function test in the sorts-after exemption, via a pre-existing impostor `rule_row_insert` (T1zc, M189); each span leg (A1h, A1i, M194, M195).
6. Residual R26; R14, R22 wording; header; README. M179 and M180 retired (their inline code is gone).
Checks run: `tests/ci.sh` all pass; `mutations-17.py` 192/192 caught at their named checks; each new refusal case was run alone against r7 first (`tests/v5.4.2-17/fail-first.py`) and failed there (T1zb-T1zd, A1h, A1i pass on r7 by design: they pin clauses r7 already had).

## What to do
1. **For each r8 change:** does it do what the finding asked, with nothing it should refuse left through and nothing valid refused? Probe edges: the per-row registration loop (an empty adopting table, many legacy rows, a legacy row refused for two reasons, a table whose area key column is missing, `rule_applicability_span` raising on a bad code, a row that passes `rule_key_check` but not the scope check); `rule_row_scope_check` behaving identically for tariff rows in `rule_row_prepare`; the note rule for a branch reached through `$ref`, and for a kind with several versions; generated columns of other kinds (identity columns, virtual columns if the server has them); the audit guard for a tariff row.
2. **Did any r8 change open a hole in rounds 1-7?** Name the check and the probe.
3. **Tests.** Is every new clause caught by a case only it can fail? Say which mutation would survive.
4. Verdict: **ready** / **not yet** (blocking items). Separate blocking, should-fix, note. Ground every claim in file:line or a reproduction.

## How to probe (Opus and Fable)
If your sandbox cannot reach Docker, say so in the review and list what you could not run. Never touch the `tally` or `postgres` databases or the repo files. Make your own clone:
```
docker exec tally-pg psql -U tally -d postgres -c "CREATE DATABASE <yourname>17 TEMPLATE tally"
docker exec tally-pg psql -U tally -d <yourname>17 -c "REVOKE TEMP ON DATABASE <yourname>17 FROM PUBLIC, tally_app"
(echo "SET search_path = ''; SET check_function_bodies = on;"; cat tests/v5.4.2-17/review/patch-17-frozen-r8.sql) | docker exec -i tally-pg psql -U tally -d <yourname>17 -1 -v ON_ERROR_STOP=1 -q -f -
```
(`CREATE DATABASE … TEMPLATE` drops the database ACL, hence the REVOKE.) To load the ZZ fixture area into your clone: `docker cp law tally-pg:/tmp/law`, then run `BEGIN; \i /tmp/law/fixtures/zz/fixture-zz.sql` … in psql (it registers kinds and tables; the battery shows how rows, profiles and tariffs are written). Write probes as `tally_app` or `tally_core` with `SET LOCAL app.user_id` where the guard is about the application or the core. The tooling runs with `tools/law/.venv/bin/python tools/law/lawc.py` and `LAWC_DB=<yourname>17`. Drop your databases when done.

## Output
Write the full review to `OUTPUT_PATH`. Final reply SHORT (under 2,500 characters): verdict, blocking items, top should-fix.
