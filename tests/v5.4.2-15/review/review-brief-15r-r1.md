# Review round 1: v5.4.2-15 (rewrite) — deposits at the rule-terms convention

You are one of three independent reviewers (separate models; you will not see each other's work).

**Frozen artefacts** (repo `/Users/ryanscomputer/code/tally-utility`; check the hashes and say if they differ):
- patch `tests/v5.4.2-15/review/patch-15r-frozen-r1.sql` — md5 `988d73eff960db25d503cc2a39d10f3a` (5,050 lines; about 1,000 are the two embedded schemas)
- battery `tests/v5.4.2-15/review/battery-15r-frozen-r1.sql` — md5 `595ee401f0cfbc0d9c26f4013a155163` (259 checks)
- the kinds' schemas and examples: `law/deposit/` (`deposit.v1.schema.json`, `deposit_tariff.v1.schema.json`, `examples/`) and `law/fixtures/deposit-states/examples/` (other states' laws, never seeded)
- tests: `tests/v5.4.2-15/migration-15r.py` (P0–P6), `mutations-15r.py` (110 mutations), `evidence-txn-15.sh`, `races/due-mutex-15.sh`, `fail-first.py`, `terms-15.py`
- the design: `application/deposits-terms-v1-design-2026-10-12.md` (read §1, §4, §5, §9)
- the machinery it uses: `sql/v5.4.2-17-rule-terms-convention.sql` and `sql/v5.4.2-18-backbilling-rule-terms.sql` (the worked example). **Read -18 first**, then this patch.

**What it is.** -06 put Texas deposit law in the database (functions, a view, typed checks). The first draft of -15 moved that into typed columns and child tables and was never mirrored; this rewrite replaces it. Law is now a **document** per (state, service, owner types, customer class, basis) in a law table (`deposit_rules`, kind `deposit` v1: cap, triggers for an additional deposit, waivers, interest, return rules, instalments), seeded with 8 Texas rows (16 TAC 7.45 and 11 U.S.C. 366, what -06 enforced) and 8 delegations for a city-owned system. A utility has its own **categories** (`deposit_utility_categories`, each mapped to one law class) and its own **tariff** record per category (`deposit_tariffs`, kind `deposit_tariff` v1), measured against the law by `deposit_tariff_compare`. Every record (`deposits`, `deposit_events`, the return-due record) **cites the law row** it was decided under (and the tariff row when one applied), the component of the document that governed, and the core version. The database no longer evaluates deposit law; the C# core will. The database keeps the *record* coherent.

**Standing rules and decisions (challenge them, but know they are Ryan's):**
1. Nothing is live: the patch refuses to run over any non-legacy deposit, waiver determination or utility rate row (carried `legacy_unknown` deposits go through unchanged).
2. Unknown law is not permission: no row ⇒ the lookup refuses; never a fallback.
3. Customer type stays on the utility's own interest rate (nullable category); the published reference rate has no customer type.
4. A state-set interest rate is a **floor** (`binding: minimum`) the utility's own rate may not go below, refused when written, read as of the row's own date; no published value in force ⇒ refused; a city the law does not bind ⇒ no floor; a later rise in a published value is a core audit finding, never a refusal.
5. The utility's deposit rules are one tariff record per category; a utility defines its own categories; version 1 refuses six shapes on purpose (design §4).
6. Schema vs core: the schema represents, the core evaluates. Do not ask for rule evaluation in triggers.
7. A guard must act, not record; a check narrower than the claim it certifies buys false confidence; test the boundary on both sides.

## What to do
1. **The migration and the template.** Strict application (`search_path=''`, bodies checked); one transaction; the precondition and the re-run. Registration (`rule_table_register` calls), the seeds through `rule_row_seed`, facets, the kinds embedded verbatim. Anything the patch drops or alters that something else depends on (views, functions, grants, other patches, `tu.sql` consumers). Behaviour under a non-superuser owner.
2. **The law table's hooks.** `deposit_rule_close_floor` (does it count every citation, at the right date, in every tenant?), `deposit_rule_insert_check` (cap parts, instalments, triggers, waivers, return rules, published rates). Documents the schema or the check should refuse but accept, or the reverse. Delegated documents.
3. **The tariff side.** `deposit_tariff_insert_check` (it pre-empts row-level security: is that safe?), `deposit_tariff_compare` (the months conversion; lesser-of / greater-of; ratio and count thresholds with `op`; days to pay; which law rows it reads; what it leaves uncompared and says so). Can a tariff be looser than the law and still be accepted? Can a looser tariff be sneaked in by a successor row, a category remap, another utility's data, or an overlapping range?
4. **The rate floor.** `deposit_rate_floor`, `enforce_deposit_interest_rate`: classes a category-less rate must clear; owner type / system kind / jurisdiction lookups; by-hold lists; fixed rates; a rate row backdated under a settled accrual; the lock order and READ COMMITTED requirement.
5. **The citing records.** `enforce_deposit` (insert and identity freeze), `deposit_cite_rule` / `deposit_rule_citable`, `enforce_deposit_event` (accruals, returns, chronology), the return-due record (`enforce_deposit_return_due_*`). Races (the row-version mutex, the shared law-row lock against a close), the isolation levels, tenant isolation (RLS, grants, the owed view), what `tally_app` can write that it should not.
6. **Tests.** Is each guard tested by a case only it can refuse (the mutation runner tries to show this: 110 mutations; read the list in `mutations-15r.py` and find a guard it does not mutate, or a mutation that is equivalent)? Missing negative cases? Boundaries tested on both sides? Does `migration-15r.py` really prove the claims? Anything a battery check asserts that is false in a way the patch happens to satisfy?
7. Verdict: **ready** / **not yet** (list blocking items). Separate findings: blocking, should-fix, note. Ground every claim in file:line or a reproduction. **Send your report as several messages to main (SendMessage), each under ~3 KB, one finding per message** — a single long final reply is cut at about 4 KB.

## How to probe (Opus and Fable)
Never touch the `tally` or `postgres` databases or the repo files. Make your own clones, prefixed with your name:
```
# a PRE-15 base (the -18 build) to apply the patch to:
docker exec tally-pg psql -U tally -d postgres -c "CREATE DATABASE <you>15 TEMPLATE tally"
docker exec tally-pg psql -U tally -d <you>15 -c "REVOKE TEMP ON DATABASE <you>15 FROM PUBLIC, tally_app, tally_core"
(echo "SET search_path = ''; SET check_function_bodies = on;"; cat tests/v5.4.2-15/review/patch-15r-frozen-r1.sql) | docker exec -i tally-pg psql -U tally -d <you>15 -v ON_ERROR_STOP=1 -q -f -
# the battery, one transaction, rolled back:
docker cp tests/v5.4.2-15/review/battery-15r-frozen-r1.sql tally-pg:/tmp/<you>b.sql && docker exec tally-pg psql -U tally -d <you>15 -v ON_ERROR_STOP=1 -q -f /tmp/<you>b.sql
```
`CREATE DATABASE … TEMPLATE` drops the database ACL, hence the REVOKE. `tally` is the pre-15 base. To try the migration on damaged data, clone `tally` again and plant rows first (see `migration-15r.py`). Write probes as `tally_app` or `tally_core` with `SET LOCAL app.user_id` where the guard is about them; the battery's helper functions (`refuses`, `does_as`, `dep_sql`, `acc_sql`, `ins_sql`, `tar_sql`) show how. Drop your databases when done.

## Output
Write the full review to `OUTPUT_PATH` if you can; send findings to main as above. Final reply SHORT (under 2,500 characters): verdict, blocking items, top should-fix.
