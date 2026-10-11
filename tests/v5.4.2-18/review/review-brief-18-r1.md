# Review round 1: v5.4.2-18 — backbilling at the rule-terms convention (the -13 migration)

You are one of three independent reviewers (separate models; you will not see each other's work).

**Frozen artefacts** (repo `/Users/ryanscomputer/code/tally-utility`; check the hashes and say if they differ):
- patch `tests/v5.4.2-18/review/patch-18-frozen-r1.sql` — md5 `db6179fda7501533dd8e0892a5690bb7` (703 lines)
- battery `tests/v5.4.2-18/review/battery-18-frozen-r1.sql` — md5 `5a4f0271b84d06abf0ab2637ec7d3e4d`
- the kind's schema and law file: `law/backbilling/` (`backbilling.v1.schema.json`, `examples/`, `backbilling_rules.yaml`, its generated `.seed.sql`)
- migration tests `tests/v5.4.2-18/migration-18.py` (P1–P7); mutations `tests/v5.4.2-18/mutations-18.py`; the rewritten groups C and Z of `tests/v5.4.2-13/battery-13.sql`; CI `tests/ci.sh`
- the machinery it uses: `sql/v5.4.2-17-rule-terms-convention.sql` (built into `tally`; **read its header, section 6 and residuals R14, R23, R24 first**) and `law/README.md`

**What it is.** -17 shipped the rule-terms convention (a registry of JSON-Schema documents, a validator, facets, a law/tariff table template with a one-time "adoption" of pre-convention rows). -18 is its first consumer: `backbilling_rules` (the `sql/v5.4.2-13` law table: 16 Texas gas rows, each 11 content columns plus a child table of "window terms" and two vocabulary tables) is **adopted in place**: every row keeps its id, key, dates, note and stamps and gains a document that must say exactly what the old columns and window terms said; then the ten content columns, the child table and the two vocabularies are dropped. Spec: `application/rule-terms-step2-source-inventory-2026-10-07.md` (V2, V4, V6–V8, F6, T5, T6, C2, L1; §3 point 2, §4 A, §5), `application/rule-terms-convention-v2-2026-10-06.md`, and -17's R14.

**Decisions the author took (challenge them):**
1. **Who the rows bind.** `owner_types = {investor_owned, cooperative}`, every system kind, every jurisdiction status. Basis: 16 TAC 7.45 applies to "gas utilities"; Utilities Code 101.003(7) defines a gas utility as a person or river authority and excludes (A) a municipal corporation, (B)–(E) production/LPG/vehicle fuel/own use/LNG terminals, (F) electric cooperatives' gas storage (§121.008) — none excludes a retail gas distribution cooperative. A municipal utility finds no row (the lookup refuses). City-owned systems are the platform's first customers; their backbilling policy is their own tariff, which -18 does not write (residual R2).
2. **One facet** (`anchor_basis`, from `$.anchor.strategy`, in `backbilling_anchor_bases`); everything else is read by the core from the document (inventory F6: no record guard reads rule content).
3. **Window terms are a list in the document**, in a canonical order (by kind, byte order) with the area's insert check refusing a repeated kind or priority per direction. The two UNIQUE constraints of the child table become that check.
4. **A new anchor basis or enforcement condition is a new schema version** (code plus core change), no longer "a vocabulary row".
5. **The document's `citation` is the lead clause of the row's `source_note`** (before its first " — " or ";"), derived, never invented; the adoption check compares it.
6. The old no-overlap exclusion, range and note CHECKs, the history trigger and the record trigger are dropped in favour of the template's. The close floor function is -13's, unchanged.

## What to do
1. **Fidelity.** Is there anything the old columns, child rows, constraints or triggers said that the document, the schema, the template or the area's hooks do not now hold? (Think: ordering, uniqueness, NULL semantics, `units_invariant`, `delivery_path` = 'unruled', the straddle values, the quantity/unit pairing, priorities, the vocabulary FKs, `created_at`/`recorded_txid` stamps, the close rules and who may close.) Is the adoption check (`backbilling_rule_adoption_check`) genuinely independent of the migration's builder, and does it compare every key? Could a wrong document be adopted?
2. **The migration.** One DO block; idempotent by the registration check. Find a partial state, a lock or isolation problem, a way for the fill to move a row's identity, an ordering problem (defaults evaluated once at ADD COLUMN; the history trigger dropped before the fill; the registration's legacy-row checks), a dependency of a dropped object that the patch misses (views, functions, comments, grants, policies, other patches), or a failure under a non-superuser owner. Does it behave on a database that already has rows beyond the 16?
3. **Applicability and the law.** Are `{investor_owned, cooperative}`, `system_kinds` NULL and `commission_jurisdiction` NULL right for 16 TAC 7.45 and §101.003? Is refusing a municipal owner right (unknown law is not permission) rather than writing delegated rows now?
4. **Integrity of the new gate.** Documents the schema should refuse but the validator/insert check accepts (or the reverse); the discriminator unions (`anchor`, `enforcement`, `term`); `uniqueItems` and canonical order; two rows the exclusion lets coexist that should not; the close floor against citations; the hook functions' privileges.
5. **Tests.** Is every guard tested by a case only it can refuse? Missing negative cases? Mutations that would be missed? Do the battery-13 rewrites keep every protection group C/Z gave? Does CI exercise the migration (P-checks) and skip it correctly once mirrored?
6. Verdict: **ready** / **not yet** (list blocking items). Separate findings: blocking, should-fix, note. Ground every claim in file:line or a reproduction. **Send your report as several messages to main (SendMessage), each under ~3 KB, one finding per message** — a single long final reply is cut at about 4 KB.

## How to probe (Opus and Fable)
Never touch the `tally` or `postgres` databases or the repo files. Make your own clones, prefixed with your name:
```
# a PRE-18 base (the -17 build) to run the migration on:
docker exec tally-pg psql -U tally -d postgres -c "CREATE DATABASE <you>18pre TEMPLATE tally"
docker exec tally-pg psql -U tally -d <you>18pre -c "REVOKE TEMP ON DATABASE <you>18pre FROM PUBLIC, tally_app, tally_core"
(echo "SET search_path = ''; SET check_function_bodies = on;"; cat tests/v5.4.2-18/review/patch-18-frozen-r1.sql) | docker exec -i tally-pg psql -U tally -d <you>18pre -1 -v ON_ERROR_STOP=1 -q -f -
tests/v5.4.2-18/run-battery-18.sh <you>18pre      # copies the battery from the repo: use the frozen copy if the repo moved
```
`CREATE DATABASE … TEMPLATE` drops the database ACL, hence the REVOKE. `tally` is the pre-18 base (it will gain -18 only on Ryan's approval). To try the migration on damaged data, clone `tally` again and break a row first (`ALTER TABLE … DISABLE TRIGGER a_enforce_backbilling_rule_history` lets the owner edit one). Write probes as `tally_app` or `tally_core` with `SET LOCAL app.user_id` where the guard is about them. Drop your databases when done.

## Output
Write the full review to `OUTPUT_PATH` if you can; send findings to main as above. Final reply SHORT (under 2,500 characters): verdict, blocking items, top should-fix.
