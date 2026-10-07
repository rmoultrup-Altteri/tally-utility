# Review r2 — v5.4.2-17 (the rule-terms convention, written once)

**Reviewer:** fable. **Date:** 2026-10-07.
**Artefacts checked:** patch `896915806252050afc5627ea7ff5def0` (2939 lines), battery `5da3cb4c31ec909eff92dd2b9bead7d5` — both match the brief; `sql/v5.4.2-17-rule-terms-convention.sql` and `tests/v5.4.2-17/battery-17.sql` carry the same hashes.
**Environment:** `fable17r2` (TEMPLATE tally, TEMP revoked), strict apply clean; a second strict apply printed no error. Clones `fable17r2_iso`, `_race`, `_law`, `_m*`; all dropped at the end.

## Verdict: **ready** — no blocking item; two should-fixes to land before the -13 migration builds on the template (F1, F2)

What ran and passed, unmodified:
- battery: 202 PASS, rolled back (176 → 202);
- `isolation-17.sh` X1–X6: 6/6; `races/rule-close-17.sh` RC1–RC5: 5/5 (second session seen waiting in each);
- `lawfiles-17.sh` W1–W5: all pass; W4 now discovers every schema, checks each equals the registered one, 899 documents, 0 disagreements; `--inputs` for the inputs kind;
- `mutations-17.py`, scratch copy pointed at the frozen r2 patch (`fable17r2_m*`): M105 (caught only by W4), M106 (RC5), M108, M109, M110, M113, M116, M124 — 8/8 caught; round 1's sample was 8/8 as well. I did not run all 124;
- privilege audit on r2: tables/views/matviews `tally_core` can read (by `has_any_column_privilege`) = `tally_app`'s, both directions empty; no function `tally_core` can EXECUTE that `tally_app` cannot; `tally_core` writes only `rule_audit_findings`; among `rule_*`, `tally_app` writes only `rule_audit_finding_dispositions`; every view `security_invoker`; role attributes all false.

## 0. Round-1 findings, re-run against r2

| r1 | Re-run | Result |
|---|---|---|
| **B1** tariff check read-then-lock | same race on `fable17r2_law`: law close to 2010 in flight, tariff from 2020 inserted 1 s later, B seen waiting on Lock | **held**: `no law is known in zz_fee_rules for this utility over {[2020-01-01,)}`; 0 tariff rows. The loop (patch 1836–1885) is right: a read counts as current only when every row it returned was locked before it began; a successor found by a re-read is locked and the read repeated; 5 reads then 55P03. RC5 covers the stricter-successor case. R17 states the close-under-tariff policy |
| **S1** `$` before newline | V23; W4 corpus has `"f1\n"`, `"a\tb"`, `"é"`, 201 chars | **held**: control characters U+0001–U+001F, U+007F refused in strings and keys in both validators. C1 controls (U+0085) and U+2028 pass both — agree (probed) |
| **S2** `stamp_core_inputs` under RR | `BEGIN ISOLATION LEVEL REPEATABLE READ; SET LOCAL ROLE tally_core; INSERT INTO zz_charge_calcs …` | **held**: `writing a core record of zz_charge_calcs runs only under READ COMMITTED`; X6 |
| **S3** citation not tied to the utility | T1 (municipal) `rule_law_row_cite(... iou row ...)` | **held**: `is not the law for this utility on 2005-01-01: its law row is <delegated>`; the delegated row cites fine; C2c/C2d. Resolution runs after the cited row's lock (2088–2093) |
| **S4** seed drops unknown keys | T4i; probe: a seed naming `closed_at` and a facet | **held**: unknown column → 42703; named columns only, so `id` keeps its default; a named `closed_at` is overwritten to NULL by the trigger, a named facet compared (probed) |
| **S5** non-empty registration | A1d | **held** (`already holds rows`) |
| **S6** P1 class scope | — | residual R10 with the reasoning (no source publishes per class); `rule_units` built, P3i. Acceptable under the stopping rule |
| **S7** dispositions | K7a–e | **held**: append-only, tenant RLS, (tenant, finding) composite FK, `decided_by` from `app.user_id`, `tally_app` writes, `tally_core` cannot |
| **S8** V5 version | R4n | **held**; a branch whose `version` is a `$ref` is refused too (probed) — stricter than needed; see N3 |
| **S9** W4 proves nothing | M105 | **held**: M105 is caught only at W4 (verified) |
| **S10** state known | T5e | **held** (state place required, 1727–1734) |
| **S11** -13 sequencing | — | residual R14; the equivalence check moved into `insert_check` — see **F2** |
| N2 scale rewrite | T8c | **held** (text comparison, 1932) |

## New findings

### Should-fix

**F1. The facet-column fix is half of what the record says it is: the column's type is checked to be *a* facet type, not *its* facet's type (patch 1500–1513).** `review-findings-17-r1.md` #4 says the bug was "`numeric(4,0)` rounds; `text[]` into `text`" and that it is fixed. `numeric(4,0)` is refused (T1g). `text[]` into `text` is not. Reproduced on `fable17r2`: `zz_coerce` = `zz_fee_rules` with `component_ids`, `fee_cap`, `has_fee`, `waiver_classes` all retyped to `text`; `rule_table_register` accepts it; a law row then stores `component_ids = '["f1", "w1"]'`, `fee_cap = '50'`, `has_fee = 'true'`, `waiver_classes = '["senior"]'` — JSON text in a text column, by `jsonb_populate_record`. A record guard reading `component_ids` as a set then never matches (`'f1' = ANY` cannot even be written), and a comparator reading `fee_cap` happens to work because `'50'::numeric` casts. Registration knows the kind, and `rule_term_facets` for that kind's versions is already read at insert time (1569–1577); check there that each facet column's type is the one its facet type stores: `text → text`, `text[] → text[]`, `integer → integer | bigint | numeric`, `number → numeric`, `boolean | present → boolean`. Add a T1h with a `text[]` facet on a `text` column. Migration-only path, so not blocking.

**F2. The adoption equivalence check lives in the permanent `insert_check`, which also runs on every future insert, and the fixture's own check then refuses every new row (fixture 645–652; patch 1525–1530).** Reproduced on `fable17r2`: register `zz_legacy_rules` adopting with `zz_legacy_check`, adopt the row (`fee_cap = 50`), then insert a new commercial law row with a valid document → `zz: the document's cap 75 is not the legacy cap <NULL>`; the same after `DROP COLUMN legacy_cap`. `rule_tables` is never edited (1271–1280), so a wrong check leaves the table unable to take a new row forever — the only way out is a new table. The battery never inserts a valid new row into `zz_legacy_rules` after adoption (A3f sends no document, so the parser refuses first), which is why this passed. For -13 this means `backbilling_rules` would take no new row after its migration unless its check is written to skip when the old column is absent (`p_row ? 'anchor_basis'` …) — and then a legacy row whose old value is NULL is adopted unchecked. Fix: a separate `p_adopt_check regprocedure` on `rule_table_register`, called only on the adoption path (`enforce_rule_row_history` 1801–1830) with the whole row, required when `p_adopts_legacy_rows`; or at least pass `"_adopting": true` in `p_row` and document the pattern in R14 and the fixture. Either way add a battery case: a new valid row into an adopting table after adoption succeeds. Should land before the -13 migration, which is the one consumer of this path.

**F3. The depth rule counts a `oneOf` hop as a level in the database and not in `lawc`, so the two validators disagree at nesting 64 under a union.** `rule_terms_node_errors` recurses with `p_depth + 1` when it selects a branch (616); `fixed_rule_errors.walk` increments only on list/dict children. Reproduced: a recursive schema whose root is a `oneOf`; a document 64 deep is `nested more than 64 levels deep` in the DB and error-free in Python; with a plain object root both accept 64 and refuse 65. Count the same thing (don't increment on the branch hop, or make Python count unions) and add a 64-deep example to the W4 corpus; today's corpus never reaches the cap, so W4 cannot see it.

### Notes

- N1. Under a `delegated_to_utility` law row with no tariff, the ZZ citing pattern cannot record a charge at all: `fee_component` is NOT NULL and the delegated row's `component_ids` is `{}` (probed: `component f1 is not a component of the row that governed ({})`). Consistent with "the core refuses a decision with no policy recorded", but say so in the fixture comment, and add the negative case.
- N2. `rule_terms_errors` now takes `p_component_ids boolean DEFAULT true`; the EXECUTE grant loop covers the new signature, and the old two-argument calls resolve to it. Fine.
- N3. V5's registration rule reads `properties.version` inline: a `version` declared through `$ref` to a shared `{integer, minimum = maximum}` definition is refused as if absent. Stricter than the convention needs; either resolve the `$ref` there or say inline is required (README does not).
- N4. `rule_law_row_cite` on a tariff table fails on the row read before `rule_law_row_as_of` gets to refuse the table (probed); harmless.
- N5. The adoption path's `insert_check` is the same hook for both purposes (F2); the fixture comment at 645 should also say the check must tolerate rows that carry no old columns.
- N6. CI: `tests/ci.sh --build` and the Actions workflow still unverified here; the local path (`tests/ci.sh`) matches what I ran by hand.

## 1. The spec, requirement by requirement (changes from r1 in bold)

| Req | Status | Where / remark |
|---|---|---|
| V1, V2, V3, V4 | held | as r1 |
| V5 | **held** | R4n (464–477); N3 |
| V6, V7, P3 | convention | README; P3 checkable through a `text[]` facet with `rule_parameters` as vocabulary (README) |
| V8, V9 | held | as r1 |
| V10 | **held** | W4 over every schema, 899 docs, M105 proves it catches; F3 is the one divergence I found |
| F1–F3, F4 | held | **facet column types half-checked (F1)** |
| F5, F6 | area | — |
| F7 | **held (pattern shown)** | fixture `zz_charge_cites` checks `fee_component` against the governing row's `component_ids`; C2e |
| T1 | held | **adopting tables must name `insert_check` (A1c); non-empty tables refused (A1d)** |
| T2 | **held** | state must be a state place (T5e) |
| T3 | held | — |
| T4 | **held** | tariff check lock-then-reread (RC5); core record RC assert (X6); R17 |
| T5 | **held** | named columns, unknown refused (T4i/j) |
| T6 | held, with F2 | R14 |
| T7 | residual R2 | — |
| U1, U2, U3 | held | R12 (a tariff table with no law table) stated |
| U4 | **held** | `rule_law_row_cite` (2078–2104); C2c/C2d |
| U5 | area | R16 |
| P1 | **partly, residual R10** | `rule_units` + FK (P3i); class scope deferred with reasoning |
| P2, P4 | area / — | — |
| C1 | held, verified | attributes, TEMP/CREATE, column grants asserted at apply (210–217, 2815–2834) |
| C2 | held (pattern) | fixture shows `(tenant, id)` FK and `tally_core`-only INSERT |
| C3 | **held** | dispositions (2694–2784); the expected pair CHECK closed (2593; K4i) |
| C4 | **held** | RC assert; inputs exempt from the component-id rule |
| L1 | held, amended | inventory now says (table, state, service) |
| L2 | held | `!` refused too (W5 `bang`); exponents refused in JSON |
| L3 | held | R11 for scenarios |
| L4 | held | municipal-bound-by-law case now looked up (L1 battery) |

**-13 and -15 as built:** yes. -13 follows R14 and must write its equivalence check to survive after the old columns are gone (F2) — better, land F2 first so the check is adoption-only. -15 gets everything it needs; class-scoped published values wait for a source (R10). The template choices the brief lists stand as in r1; `rule_law_row_cite` closes the one gap (a record cites *its* law row), and R16 says how a tariff keyed on the utility's own vocabulary avoids the shared-column filter.

## 2. Integrity — what held under probing on r2

- Validator: control characters refused in strings and keys (both validators), C1/U+2028 accepted by both, `-0`/`1e2` no longer reach a JSON example (lawc refuses exponents; YAML never allowed them); `$ref`-typed discriminators and `version` still refused at registration; recursion registers; depth per F3.
- Parser: NUL named as unstorable, not as a duplicate key (V21e).
- Template: template/key columns cannot be facets (T1f); `numeric(4,0)` refused (T1g); **`text` columns accept array/number/boolean facets (F1)**; seeds name their columns; a close that changes a number's scale is an edit.
- Handshakes: tariff/close/successor (RC5 and my race), cite/close (RC1/2), freeze/insert (RC3/4), core record under RR (X6) — all refuse as the header says.
- Tenancy: dispositions reach another tenant's finding only through the composite FK, which fails (K7d); profiles, tariffs, charges and findings as in r1; `assert_tenant_isolation_invariants()` passes with four fixture tenant tables.
- Privileges: see the audit above; the apply-time assertions (TEMP via PUBLIC, attributes, matview column grants) are the right place for them.

## 3. Tests

- Added since r1 and verified by name: R4n, V21e, V23, F2g, T1f/g, T4i/j, T5e, T8c, A1c/d, A3h/i, C2c–f, P3i, K4i, K7a–e, X6, RC5, W4 discovery, M105–M124.
- Still missing: a **valid new row into an adopting table after adoption** (would have caught F2); a `text[]`/`number`/`boolean` facet on a `text` column (F1); a 64-deep document under a `oneOf` in the W4 corpus (F3); a charge under a delegated row with no tariff (N1); a tariff spanning a `law` row and a `delegated` row; `tally_core` UPDATE on a tariff/law row refused; `coverage_to >= coverage_from`.
- W4 now proves agreement on a corpus that reaches strings, lengths, numbers, branch switches and control characters, and M105 shows it fails when the DB drifts. It still does not reach the depth cap (F3); the README now says what it does and does not prove, which is right.

## 4. Housekeeping

Databases `fable17r2*` dropped. No repo file other than this one written.
