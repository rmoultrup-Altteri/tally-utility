# Handoff: v5.4.2-17 (rule-terms step 2) is frozen at r4; next, Codex's review, then Ryan approves the mirror

**Generated**: 2026-10-07, end of session
**Branch**: `main` at `37d98bc`, pushed. gas-billing-memory unchanged (`091c990`).
**Status**: Waiting on a review. Opus and Fable say "ready" (on r3; r4 folds their last points). Codex has not yet reviewed r3 or r4: its CLI hit its usage limit. **Ryan's instruction:** wait for Codex's review of r4, then ask him to approve mirroring -17 into `tu.sql`.

## Goal

Rule-terms v2 §12 step 2: the convention infrastructure, written once, so that two consumers can build on it:
- the -13 migration (backbilling);
- the -15 rewrite (deposits).

Both lead toward the C# core billing engine.

## Completed (this session)

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

- [ ] **Codex review of r4.** Brief: `tests/v5.4.2-17/review/review-brief-17-r4.md`. It asks Codex to verify its round-2 B1–B3 and should-fixes, and the r3/r4 changes.
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
