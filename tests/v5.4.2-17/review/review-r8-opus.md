# Review round 8 — Opus — v5.4.2-17 (r7-to-r8 diff)

**Hashes verified:** `patch-17-frozen-r8.sql` = `3da8dfa0a23f68bb25c4a4c9b3dbd389`, `battery-17-frozen-r8.sql` = `49779ba424c6638df174bf41e4641a81` — both match the brief. Working copies `sql/v5.4.2-17-rule-terms-convention.sql` and `tests/v5.4.2-17/battery-17.sql` are byte-identical to the frozen files.

**Environment:** Docker reachable; PostgreSQL 16.14 (so no virtual generated columns exist to test). Clone `opus817` from `tally` (TEMP revoked), patch strict-applied (`search_path=''`, `check_function_bodies=on`) cleanly. Frozen battery against it: **272 PASS**, no failure. Mutation probes ran in `opus817mut` (re-cloned per mutation). Both databases dropped. Housekeeping note: while running the battery I replaced the container's `/tmp/law` with a fresh copy of the repo's `law/` (same commit, identical content), because the battery `\i`s that path.

## Verdict: **ready**

No blocking items. Two test gaps (clauses no case can fail) and one stale residual sentence, all should-fix.

---

## 1. Each r8 change

### 1.1 Note dry-run only where the delegated branch admits one (`patch:1608-1619`)
Does what Codex B1 and Opus S2 asked. Because the V8 trigger (`patch:1038-1058`) pins the delegated branch to `additionalProperties: false` with properties ⊆ {governs, citation, note}, "the resolved branch has `properties.note`" is exactly "a document of the kind may carry a note". It handles a `$ref` branch (the fixture's own branch is `#/$defs/delegated`, and T1za runs through that). It also handles a `note` property that is itself a `$ref`, since only the key's presence is tested. Several versions work too: the function filters on `(p_kind, p_version)`, and registration and `rule_row_prepare` call it once per version. One resolve level only, which matches the V8 trigger (a `$ref`→`$ref` branch is refused there first).

Mutations I ran beyond M184/M185:
- `CASE WHEN v_note` → `CASE WHEN false` (note never tried): **caught** by T1z.
- dropping `rule_terms_resolve` inside the `bool_or`: **caught** by T1z.
- **dropping the `governs = 'delegated_to_utility'` filter: survives (272 PASS).** See S2.

### 1.2 `rule_row_scope_check` extracted; registration runs the fill's checks per legacy row (`patch:1796-1830`, `1948-1977`, `2091-2092`)
- **`rule_row_prepare` behaviour is unchanged.** The order is the same as before: key check, then document and facet checks, then state, then system kind(s), then spans. Messages are identical, because `p_cfg.table_name` is passed as `p_table`. The tariff path's single system-kind check moved before the (law-only) span block, which has no effect on a tariff row. 272/272 still pass.
- **The registration loop fails closed.** Every exception inside the per-row block, of any class, increments `v_bad`, and any `v_bad > 0` refuses registration. So `WHEN OTHERS` cannot let a row through, it can only reword the refusal. `query_canceled` is not caught by `OTHERS`, as it should be.
- **The span compare matches the fill's** (`patch:2328-2330`). Both sides are `to_jsonb` of the range value, compared as jsonb, with the same CASE on `jsonb_typeof(... ) = 'array'`.
- Probes (all against r8):
  - **P1, empty adopting table:** registers.
  - **P2, six legacy rows:**
    - one has two faults (unknown state `QQ` and a blank key), one has an unknown owner code, one has repeated owner codes, one has `{}`, one is good, one has a span off its set.
    - Result: refused with the first three by id, then "5 legacy rows in all cannot be adopted". The good row is not counted.
    - A row with two faults reports the first (the key). That is acceptable: the repair loop finds the second on the next run.
  - **P3, area key column missing:** the loop is skipped (`patch:1803-1805`). The refusal is only "has no column customer_class (text)". Correct, and no raw error.
  - **P4, `rule_applicability_span` raising (unknown, empty or repeated codes):** caught and reported per row ("a set of owner_type codes is … {}").
  - **P5, a row that passes everything:** registers, and the later fill succeeds.
  - **A key-OK, scope-bad row:** A1j and A1k cover this, and both expect the scope message, so the key check is shown to have passed.
- No hole opened in rounds 1–7. The new function is invoker, `STABLE`, read-only, and EXECUTE-able by `tally_app`/`tally_core` like the sibling helpers (`rule_row_prepare`, `rule_key_check`): it reveals only whether a state or system kind exists. Registration stays owner-only (`proacl {tally=X/tally}`).

### 1.3 Audit guard refuses an unfilled rule row (`patch:3066-3072`)
Correct. It is placed after the existence and tenant checks, so "no such row" still wins. A tariff row is never unfilled: tariff tables cannot adopt (`patch:1691`), and every insert fills `terms`. So the guard is a no-op there, which is right. K4i targets `…17e3`, which is still unfilled at `battery:1212` (its only fill attempt, A3e, is refused).

### 1.4 Generated columns refused (`patch:1759-1765`)
- **Facet, key and template columns:** refused (T1ze; my G1/G2 probes).
- **A generated non-template column:** registers (P7). Correct.
- **Identity columns are not covered** (`attidentity`, not `attgenerated`):
  - P6/P10: a non-adopting law table with `terms_version GENERATED ALWAYS AS IDENTITY` registers. An insert that omits the version is then validated against whatever version the sequence hands out.
  - Nothing invalid is stored, because the row is validated against the version it records.
  - On an adopting table the column must allow NULL, so identity is refused there anyway (P9: "must allow NULL").
  - Note only (N1).

### 1.5 / 1.6 Cases, mutations, residuals
A1g/A1h/A1i each break exactly one span leg. A1h and A1i use a gas kind and the default spans, so only the compare can refuse them, and the expected "stored spans" phrase proves it. T1zc and T1zd are sound.

---

## 2. Findings

### S1 (should-fix, test) — the key and template legs of the generated-column refusal are unpinned
M186 kills the whole clause (`attgenerated <> ''` → `false`). But narrowing `ANY (c_template_cols || p_area_key || p_facet_columns)` to `ANY (p_facet_columns)` **survives: 272 PASS** (run in `opus817mut`). On that mutant:
- G1: a `customer_class text NOT NULL GENERATED ALWAYS AS ('residential') STORED` key column registers. On r8 it is refused only by this clause.
- G2: a `source_note … NOT NULL GENERATED ALWAYS AS ('fixed') STORED` template column registers. On r8 it is refused only by this clause.

Fix: add T1zf (a generated NOT NULL key column) and T1zg (a generated NOT NULL template column, e.g. `source_note` or `effective_to`), each expecting `is a generated column`, plus a mutation per leg.

### S2 (should-fix, test) — the `governs` filter in the note rule is unpinned
`patch:1615`. Dropping `AND rule_terms_resolve(...) #>> '{properties,governs,const}' = 'delegated_to_utility'` survives (272 PASS), because the ZZ `law` branch has no `note` property. Without the filter, a kind whose **law** branch has a `note` but whose delegated branch does not would again get the note document tried. That is the r7 B1 false refusal, back for that shape.

Fix: one case, a `zz_lawnote` kind with a law-branch `note`, no delegated `note`, and a `$.note` integer facet, which must register. Plus a mutation dropping the filter.

### S3 (should-fix, wording) — R26's last sentence is now false
`patch:3446-3449` says a non-text key column or repeated owner types "refuse registration with the underlying error rather than the combined message". In r8 both go through the per-row loop and come out inside the combined message:
- P4: `lg4.customer_class is integer, not text; legacy row … cannot be adopted: the key of lg4 names exactly {customer_class}, each a non-blank string; got {"customer_class": 7}`.
- P2: `legacy row … cannot be adopted: a set of owner_type codes is … {}`.

Drop the sentence or reword it: "…are reported per row inside the combined message, the key also as a column-type error".

### N1 (note) — identity columns are not "generated"
See 1.4. `GENERATED … AS IDENTITY` on `terms_version` (or `recorded_txid`, which the trigger overwrites anyway) passes registration. Nothing unvalidated can be stored, but the version a row is checked against would be chosen by a sequence. If the clause is meant as "no column the server computes", add `OR a.attidentity <> ''` for template, key and facet columns. A cheap tidy-up.

### N2 (note) — one reason per legacy row, three rows reported
The first fault per row and the first three rows by id are shown. The total is still exact. That is fine for a migration loop; README's "registration runs the fill's own checks on each" is accurate. No `v_bad > 3` summary case exists. It is not a safety property, so no mutation is needed.

### N3 (note) — registration reads legacy rows without a lock
The scan (`patch:1808`) runs before `ALTER TABLE … ADD CONSTRAINT` takes ACCESS EXCLUSIVE. Only the owner can write a law table, and registration is a migration, so this is not reachable by `tally_app`. Mention only.

---

## 3. Tests summary
- Every r8 refusal clause has a case that fails without it, except the two legs in S1 and S2.
- Surviving mutations I found: (a) generated-column check narrowed to facets only; (b) the note rule without its `governs` filter.
- Mutations I ran that were caught: note never tried (T1z), resolve dropped from the note test (T1z).

## 4. Not run
`isolation-17.sh`, `races/rule-close-17.sh`, `lawfiles-17.sh` and the full `mutations-17.py` were not rerun. They use the runner's default database names, which the brief forbids me to use. The r8 diff touches no lock, isolation or law-file path.
