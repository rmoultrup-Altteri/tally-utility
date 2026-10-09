# Handoff: v5.4.2-17 (rule-terms step 2) is frozen at r6; round 6 done (all three "ready"); Ryan to decide on r7

**Generated**: 2026-10-09, end of session
**Branch**: `main`, pushed (last commit `411bfd6`). gas-billing-memory unchanged (`091c990`) as of 2026-10-07; fetch both before orienting.
**Status**: r6 frozen (patch md5 `e56f35010b3697680cff673cf44cbd8e`, 3,256 lines; battery `f65867baaf103dd589c581520cd5228f`). Round 6 (Opus, Fable, Codex): all **ready**, no blocking item, six should-fix groups (below). **Waiting on Ryan:** my recommendation is r7 (all six folded, each test written first and watched failing on r6), then the three reviewers check only the r6-to-r7 diff, then he approves the mirror. The alternatives I gave him: mirror r6 and carry these as residuals, or a full round 7. He has not answered.

## Round 6 findings (reviews: `review-r6-opus.md`, `review-r6-fable.md`, `review-r6-codex.md`; Codex's probes in `codex-r6-probes/`, outputs appended to its review)

1. **Trigger assertion identifies the template's triggers by name only** (Codex S2, Opus S1, Fable S1). Reproduced by Codex and Fable: `CREATE OR REPLACE TRIGGER rule_row_history … BEFORE DELETE` (or another function) passes `assert_rule_table_invariants()`, and an UPDATE of a law row then succeeds. Opus adds, **not yet reproduced by me**: an inheritance child of a law table returns its never-validated row from `rule_law_row_as_of`; a `DO INSTEAD NOTHING` rule passes. Fix: check `tgfoid`, `tgtype` (7/27/34) and no WHEN for each template trigger; refuse inheritance children and rewrite rules; exclude the template's triggers by identity, not name.
2. **An unfilled legacy row on an adopting table (`terms IS NULL`) counts as law** (Fable S2; not yet reproduced by me): lookups, cites and the tariff check read it. r6's blank-key check can make such a row unfillable. Fix: lookups/cite/tariff refuse `terms IS NULL`; adopting registration runs `rule_key_check` and the span compare over existing rows (also Codex N2, Opus note).
3. **Delegated dry-run covers only `{governs, citation}`** (Opus S2): a facet reading `$.note` registers, then the delegated document with a note is refused. Dry-run both.
4. **`strategy` may be optional** (Fable S3): add `required ? 'strategy'` to the version clause.
5. **Two trigger-name clauses untested** (Opus S3): dropping `COLLATE "C"` or the BEFORE bit survives. Add `rulerowa` (refused), `Zz_…` and an AFTER ROW late-named trigger (allowed).
6. **`governs` cannot be a `$ref`** (Codex S1; Fable and Opus note it): decide README/message wording ("the discriminator is inline") rather than resolving it in the interpreter (touches branch selection in SQL and Python).
Notes to record as residuals: a CHECK on a facet column and an unbound `$variable` in a facet path are outside the dry-run; the dry-run is the delegated half only (Codex N1); -13/-15 must make any column named by a facet nullable (facet name = column name); the invariant is vacuous until -13 is mirrored; "must admit" message vs the "exactly" rule.
All three say -13 and -15 can use r6 as built (their rule-table triggers are `a_…`).

## Resume Instructions (this session's)

1. Fetch both repos. Read this file and `tests/v5.4.2-17/review/review-findings-17-r5.md` (the format for a findings record); write `review-findings-17-r6.md` the same way once r7 is built.
2. Ask Ryan only if he has not answered the r7 question above. If he says go: write the failing tests first (inheritance child, rewrite rule, replaced trigger, unfilled legacy row, note dry-run, optional strategy, trigger names), confirm each fails on r6, fold, then `tests/ci.sh`, the full `mutations-17.py` (re-anchor any that move; run **all** after each patch edit), freeze r7 (`patch-17-frozen-r7.sql`, `battery-17-frozen-r7.sql`, `review-brief-17-r7.md` limited to the r6-to-r7 diff), commit.
3. Review method: Opus and Fable as background agents (own database prefixes, never the mutation runner's default `m17*` names); Codex via `codex exec -s workspace-write` writing probe `.sql` files, which I run (see memory `codex-reviewer-node-path`). A "completed" notice for a `nohup … &` launcher is the shell, not the reviewer.
4. Never edit the patch while reviewers test it; one revision per round; hash in every request. Mirror into `tu.sql` only on Ryan's approval (procedure in `sql/DEPLOY-VERIFICATION.md`, listed below under Not Yet Done).

## Goal

Rule-terms v2 §12 step 2: the convention infrastructure, written once, so that two consumers can build on it:
- the -13 migration (backbilling);
- the -15 rewrite (deposits).

Both lead toward the C# core billing engine.

## Round 5 and r6 (2026-10-09)

All three reviewers: ready. Folded into r6, each with a test and a mutation (battery 247 checks, mutations 165/165, `tests/ci.sh` all pass, including the new `assert_rule_table_invariants()` step):
- a law table's facets are dry-run on the standard delegated document (Opus S2); a strategy is a string with a const or enum (Opus S3); the delegated branch may use property `$ref`s (Fable S1);
- no BEFORE ROW trigger may sort after `rule_row_history`; registration refuses it and CI asserts it (Fable S2);
- a direct insert refuses a blank area key (Codex S1); published values and bounds refuse infinities (Codex S2);
- the tests the r5 clauses lacked (Opus S1: R3h, R4s-R4v).
Residuals R19-R21 record the notes. Method that worked: Codex writes probes, I run them (it cannot reach Docker); mutations re-anchored after each patch edit.

## Round 4 and r5 (2026-10-09)

Codex: not yet. I reproduced B1, B2 and S1 on a scratch clone before folding (`review-findings-17-r4.md`):
- **B1:** a law kind registered with a delegated branch no document could satisfy (`maxLength: 1` on `governs`). Now the branch must equal the standard one, annotations aside.
- **B2:** the strategy-version rule only ran inside a union discriminated by `strategy`. Now any object with a `strategy` property requires a bounded integer `version` (one guard, in the object case).
- **S1:** `rule_row_seed` read a malformed applicability value as NULL ("every one") and matched an existing wildcard row. Now typed first.
- **S2:** lawc checks lone surrogates in keys. **S3:** adoption wording.
Tests: battery 230, `tests/ci.sh` all pass, mutations **147/147** caught (M141-M148 new; M112 retargeted).

## Completed (through r4)

- [x] **Source inventory** `application/rule-terms-step2-source-inventory-2026-10-07.md` (`e34b58e`). Requirements V/F/T/U/P/C/L. Amended after round 1: P1 class scope moved to a residual; L1 is one file per (table, state, service); L3 scenarios are shape-checked only.
- [x] **Ryan's three defaults:**
  - -13's rows are adopted in place;
  - law-file tooling in Python;
  - CI as GitHub Actions.
- [x] **`sql/v5.4.2-17-rule-terms-convention.sql`**, r4, 3,080 lines, md5 `ad7045b9e680af4ca0f72212013a7cd5`:
  - `tally_core`;
  - the `rule_term_schemas` registry, with a JSON Schema subset interpreter (`rule_terms_errors`);
  - the duplicate-key parser (`rule_terms_parse`);
  - facets;
  - applicability spans;
  - the law/tariff template (`rule_table_register`, generic triggers, lookups, `rule_row_cite` / `rule_law_row_cite`, the tariff check, adoption, `rule_row_seed`);
  - published values (`rule_units`, `rule_parameters`, `rule_parameter_values`);
  - `stamp_core_inputs`;
  - audit findings and their dispositions;
  - `assert_core_role_invariants()`;
  - residuals R1–R18.
- [x] **Tests:**
  - battery 220 (`tests/v5.4.2-17/battery-17.sql`, run with `run-battery-17.sh`);
  - `isolation-17.sh` X1–X6;
  - `races/rule-close-17.sh` RC1–RC7;
  - `lawfiles-17.sh` W1–W5 (the cross-check covers 899 documents, 0 disagreements);
  - `mutations-17.py` **139/139** caught at named checks.
- [x] **ZZ fixture area:** `law/fixtures/zz/` (`fixture-zz.sql`, 3 schemas, a law file, its seed SQL, examples). `law/README.md` documents the format.
- [x] **Tooling and CI:**
  - `tools/law/lawc.py` with `requirements.txt` (pinned; venv at `tools/law/.venv`);
  - `tests/ci.sh` (`--build` builds the image) and `.github/workflows/ci.yml`. GitHub runs are green (about 2 minutes).
- [x] **Review rounds** (all in `tests/v5.4.2-17/review/`):
  - round 1: all three "not yet", 8 blocking items;
  - round 2: Opus and Fable "ready", Codex "not yet" with 3 blocking items;
  - round 3: Opus and Fable "ready"; Codex did not run.
  - Briefs, frozen patches and batteries r1–r4, reviews and `review-findings-17-r1..r3.md` are all there.

## Not Yet Done

- [ ] **Review round 5** on the r5 freeze (brief above). Opus and Fable have not seen r4 or r5; Codex needs a working Docker path.
- [ ] Triage Codex's findings by rule (into r5 if needed, with one revision per round). Then **ask Ryan to approve the mirror**.
- [ ] **Mirror into `tu.sql`**, following the -16 procedure in `sql/DEPLOY-VERIFICATION.md`:
  - append the body with a banner, omitting the header;
  - `cmp` the prefix and the body;
  - rebuild `tally-pg`;
  - check catalog identity and counts;
  - run every battery;
  - add a DEPLOY-VERIFICATION entry;
  - then remove the patch from `PENDING` in `tests/ci.sh`.
- [ ] **Then step 4:**
  - the -13 migration (follow residual R14's sequence);
  - the -15 rewrite on the template: drop or justify its class-scoped rate (R10); city classes (R16).
- [ ] Bump the GitHub Actions versions (`checkout@v4` and `setup-python@v5` warn about Node 20).

## Failed Approaches (Don't Repeat These)

- **Tariff check: read the law rows, then lock them** (r1): a close or a stricter successor committed while the lock was awaited was compared stale, and a looser tariff was accepted (reproduced by Opus and Fable). Fix: lock, then re-read until no unlocked row appears (≤5 reads, then 55P03). Race RC5 covers it.
- **The adoption equivalence check inside the permanent `insert_check`** (r2): after adoption, every new row was refused (`cap 75 is not the legacy cap <NULL>`). Fix: a separate `p_adoption_check`, run only when an empty document is filled.
- **Checking a facet column's type against an allowed list** (r2, wrongly recorded as fixed in r1): a `text[]` facet over a `text` column stored JSON text. Fix: `rule_facet_column_errors()` pairs each facet type with its column type.
- **Counting a oneOf branch as a depth level:** the database refused at depth 65 what `jsonschema` accepted. A branch keeps the depth.
- **The whitelisted pattern `^[a-z][a-z0-9_]*$` claimed to be identical across engines:** Python's `$` matches before a trailing newline. Fix: a fixed rule refusing control characters, on both sides.
- **Decimal `normalize()` in lawc:** rounds beyond 28 digits. Use `format(d, "f")`.
- **Mutation harness:**
  - the race check names R1–R4 collided with battery R1 (renamed RC1–RC7);
  - its regex was not widened when RC6 and RC7 were added;
  - APPLY counted any failed apply. It now needs a phrase: `"APPLY:<phrase>"`.
- **Redundant guards make a mutation miss** (M16, M62, M110). Remove the duplicate or retarget the mutation; never loosen the rule.
- **`psql -c` does not substitute `:'var'`.** Pipe a script on stdin. macOS bash 3 with `set -u` dies on an empty `"${arr[@]}"`; use `${arr[@]+"${arr[@]}"}`.

## Key Decisions

| Decision | Rationale |
|---|---|
| One IMMUTABLE interpreter for a JSON Schema subset, not a generated function per version (v2 §5 wording) | Reviewed once. Registration refuses any unenforced keyword (V9). W4 checks agreement with `jsonschema` |
| Applicability: `owner_types` / `system_kinds` text[] and `commission_jurisdiction`, each NULL = every one, stored as int multirange spans in the exclusion | Sets plus "every one" without duplicating rows; the exclusion still catches every-vs-one overlaps |
| Records always cite the law row and optionally a tariff row; law kinds must admit `{"governs":"delegated_to_utility","citation":…}` | City-owned systems (TX §101.003(7)(A)) use a delegated row plus their own tariff; unknown law is not permission |
| A tariff is checked only against law rows sharing its key columns; a later law change is an audit finding, not a refusal (R6, R17) | The law row records the law |
| Published values: no class scope (R10); `rule_units` vocabulary | Stopping rule: no source publishes a rate by class |
| `tally_core`: explicit grants only, no default privileges, member of no role; checked by `assert_core_role_invariants()` in the tail and in CI | Fails closed; keeps matviews out of reach |
| -13 adoption sequence (R14): template columns and spans first, then register with `p_adoption_check`, drop `enforce_backbilling_rule_history`, compare window terms in the check | Each step reviewed with that migration |
| Wait for Codex before the mirror (Ryan, 2026-10-07) | Memory `all-three-reviewers-before-mirror` |

## Current State

**Working:** `tally-pg` runs the **-16 build** (`tally` = `tu.sql` md5 `9c1d0813`); -17 is not mirrored. `tests/ci.sh` passes in full locally and on GitHub.
**Broken:** nothing.
**Uncommitted changes:** none apart from this HANDOFF and the CHANGELOG entry.

## Code Context

```sql
-- registration (migration-only)
public.rule_table_register(p_table regclass, p_role text /*law|tariff*/, p_terms_kind text, p_area_key text[], p_facet_columns text[],
  p_close_floor regprocedure /*(uuid)→date*/, p_insert_check regprocedure /*(jsonb)→void*/,
  p_law_table regclass, p_compare_function regprocedure /*(jsonb,jsonb)→text[]*/, p_adoption_check regprocedure /*(jsonb)→void*/)
public.rule_row_seed(p_table regclass, p_row jsonb) RETURNS uuid   -- whole envelope, no id; same row → id; different → 23505
-- rows: write terms_source (JSON text); the trigger writes terms, facets, spans, stamps
public.rule_law_row_as_of(table, tenant, service, system_kind, state, key jsonb, on) RETURNS uuid  -- no law → P0002
public.rule_tariff_row_as_of(...same...) RETURNS uuid                                              -- NULL if none
public.rule_law_row_cite(table, id, tenant, service, system_kind, state, key, on)  -- an area's citing guard calls this
public.rule_terms_errors(schema jsonb, doc jsonb, p_component_ids boolean DEFAULT true) RETURNS text[]
public.rule_parameter_value_as_of(name, state, service, on)
public.assert_core_role_invariants()   -- owner-only; CI runs it
```

## Resume Instructions

1. Fetch both repos, as usual:
   ```
   cd ~/code/tally-utility && git pull --ff-only
   cd ~/code/gas-billing-memory && git fetch && git log --oneline HEAD..origin/main
   ```
   - Expected: nothing new.
2. Check the frozen hash: `md5 -q tests/v5.4.2-17/review/patch-17-frozen-r4.sql`.
   - Expected: `ad7045b9e680af4ca0f72212013a7cd5`.
3. Run Codex on r4:
   ```
   B=$(mktemp); python3 - "$B" <<'EOF'
   import sys; s=open('tests/v5.4.2-17/review/review-brief-17-r4.md').read()
   i=s.index('## How to probe'); s=s[:i]+"## How to probe\nYou run read-only: a static review of the files. Mark any reproduction as predicted from the SQL, not executed. Do not modify any file.\n\n## Output\nYour final message is the full review (it is saved as the review file).\n"
   open(sys.argv[1],'w').write(s)
   EOF
   PATH=~/.nvm/versions/node/v24.15.0/bin:$PATH codex exec -s read-only -C "$PWD" -o "$PWD/tests/v5.4.2-17/review/review-r4-codex.md" - < "$B"
   ```
   - Expected: about 10 minutes; the review lands in `review-r4-codex.md`.
   - If you see "You've hit your usage limit", wait and retry. Do not mirror without it.
4. Triage by rule:
   - **"ready":** ask Ryan to approve the mirror (step 5).
   - **Blocking items:** fold them into r5 (`review-findings-17-r4.md`; re-run the CI suite and `python3 tests/v5.4.2-17/mutations-17.py`, about 30 minutes, which must be all caught). Freeze r5 and send it to all three reviewers.
5. On Ryan's approval, mirror into `tu.sql` as in the -16 entry of `sql/DEPLOY-VERIFICATION.md`.
   - Expected new counts: about +12 tables.
   - Remove the -17 line from `PENDING` in `tests/ci.sh`.

## Warnings

- **`tu.sql` is append-only.** Mirror only after Ryan approves.
- **Revoke TEMP after every `CREATE DATABASE … TEMPLATE`.** Since -17, `assert_core_role_invariants()` also refuses a clone where PUBLIC still holds TEMP. The helper scripts do this.
- **Freeze the hash before any review; one revision per round.**
- **`mutations-17.py` clones into fixed names** (`m17`, `m17iso`, `m17race`, `m17law`). Don't run two at once, and keep reviewers on their own names.
- **Every mutation must be caught at its named check.** A catch by an earlier check means the name is wrong, or a guard is redundant.
- **Never `git add -A` in gas-billing-memory.**
- **Explain choices to Ryan in prose. Ask only on rule conflicts.**
