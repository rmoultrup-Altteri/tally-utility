# Review r8 — v5.4.2-17 (the rule-terms convention, written once)

**Reviewer:** fable. **Date:** 2026-10-09.
**Artefacts checked:** patch `3da8dfa0a23f68bb25c4a4c9b3dbd389` (3452 lines), battery `49779ba424c6638df174bf41e4641a81` — both match the brief. The working copies `sql/v5.4.2-17-rule-terms-convention.sql` and `tests/v5.4.2-17/battery-17.sql` carry the same two hashes, so the runners (which read the working copies) tested the frozen revision. `diff patch-17-frozen-r7.sql patch-17-frozen-r8.sql` is exactly the six r8 changes the brief lists: header 58–67; the note rule 1609–1619; `v_cfg`/`v_row`/`v_msg`/`v_bad` and the generated-column clause 1666–1669, 1760–1766; the per-row registration loop 1795–1830; `rule_row_scope_check` 1942–1980 and its call at 2092 (the inline state and system-kind checks removed from `rule_row_prepare`); the audit guard 3066–3072; R14, R22 wording 3370–3371, 3421–3423; R26 3443–3449. The battery diff adds T1za–T1ze, A1h–A1l, K4i and the A1f phrase change (`'a blank key'` → `'non-blank'`, since the message is now `rule_key_check`'s own).
**Environment:** `fable817` (TEMPLATE tally; TEMP revoked from PUBLIC, tally_app, tally_core); strict apply (`search_path=''`, `check_function_bodies=on`) in one transaction, 0 errors. Clones `fable817iso`, `fable817race`, `fable817law`, `fable817ma`–`mc` (three hand mutants), `fable8m17*` (a scratch copy of the mutation runner, pointed at the frozen r8 file and at its own battery copy under `/tmp/fable8-*` in the container, so it never raced the shared `/tmp/law`). All dropped at the end; my container files removed.

## Verdict: **ready** — no blocking item; two should-fixes in the tests (a clause present and correct in the patch but with no case that only it can fail), one wording note on R26

What ran and passed, unmodified, on `fable817`:
- battery r8: **272 PASS, 0 FAIL**, rolled back (262 in r7 → 272: T1za–T1ze, A1h–A1l, K4i);
- `isolation-17.sh` X1–X6; `races/rule-close-17.sh` RC1–RC7; `lawfiles-17.sh` W1–W5 (899 documents, 0 disagreements);
- `assert_rule_table_invariants()` after all my probes (P17);
- `mutations-17.py` (scratch copy) M184–M195: **12/12 caught at their named checks**, as the brief states.

## 1. The six r8 changes, each against what the finding asked

All probes (P1–P17) appended to the frozen battery inside its transaction, each in a subtransaction, rolled back; the fixture, the half-adopted `zz_legacy_rules`, the T1za/T1zb kinds and the roles are as the battery leaves them.

### 1. The note tried only where admitted (1609–1619) — does what Codex B1 / Opus S2 asked

The registry (1046–1057) pins every delegated branch to `additionalProperties: false` with properties ⊆ {governs, citation, note}, so "the branch has `properties.note`" is exactly "some document of the kind may carry a note"; the detection resolves the branch through `rule_terms_resolve` (a `$ref` branch, the fixture's shape, T1za) and reads `properties.note` whether inline or itself a `$ref`.

| Shape | Result |
|---|---|
| T1za (branch without note, `$.note` integer) / T1zb (strict `$.note`, note optional) | registers / refused naming the no-note document |
| P8a–P8d: the delegated branch written **inline** in `oneOf` (no `$ref`), without and with a note | without: `$.note` integer registers; with: refused on the note document |
| P8e–P8f: `properties.note` is itself a `$ref` (`#/$defs/citation`) | detected: `$.note` integer refused |
| P9a–P9c: one kind, v1 without a note, v2 with; `$.note` integer declared on both | refused, naming **v2 only** (the loop at 1836 runs the dry-run per version, and `v_note` is computed per version) |
| P9d–P9e: lax `$.note` text on both versions registers; strict `$.note` on v2 only refused naming `zz_w v2` and the no-note document | right |
| P16a–P16b: a note on the **law** branch only, delegated branch without | `$.note` integer registers (the `governs` filter at 1615 is what makes this right; see §3 mutant a) |

### 2. Registration runs the fill's own checks per legacy row (1795–1830; `rule_row_scope_check` 1942–1980) — does what Opus S1 / Fable S1 asked

`rule_row_scope_check` is the r7 code of 2010–2016 and 2020–2029/2036–2041 moved verbatim into one function keyed on `p_role`; `rule_row_prepare` calls it at the same point (after facets, before applicability), so a tariff row sees the same two refusals with the same messages as in r7: P7 (`water` + `master_meter`: 23514 "is not a kind of water system"), P7b (`QQ`: 23503 "is not a known state"). The battery's T5d/T5e (law rows) and U-section (valid tariff rows) still pass.

The registration loop (1808–1826) puts each row through `rule_key_check` with the key projected from the row (1810), the scope check as `'law'` (1811), and the three span legs (1812–1816), in a per-row `BEGIN … EXCEPTION WHEN OTHERS` — so every refusal, including `rule_applicability_span`'s own, is collected into the combined 42P16 report with the row's id and the function's message. Edges probed:

| Edge | Result |
|---|---|
| P1 an empty adopting table | registers (zero iterations) |
| P2 six rows with a blank key | three named by id with `rule_key_check`'s message, then "6 legacy rows in all cannot be adopted" |
| P3 one row bad for two reasons (blank key, unknown state) | the first reason only (key); the next registration attempt finds the state — acceptable: one repair at a time, named precisely |
| P4 the area key column missing | "has no column customer_class (text)" from the column checks; the loop is skipped (1803–1805), no exception leaks |
| P5a–c `owner_types` `{bogus}` / `{municipal,municipal}` / `{}` | each collected: "legacy row … cannot be adopted: owner_type bogus: not a known code with an ordinal" / "… without blanks or repeats: {municipal,municipal}" / "… {}" |
| P5d `state_code` NULL (column made nullable) | both: "state_code must be NOT NULL" and the scope check's "is not a known state" |
| P6 an integer key column | both: "customer_class is integer, not text" and `rule_key_check`'s "each a non-blank string; got {"customer_class": 7}" |
| A1j / A1k (battery) a row passing the key check but not the scope check (unknown state; a water `master_meter`) | refused with the scope messages |
| P12 an empty area key, one legacy row | registers (`jsonb_object_agg` over nothing → `'{}'`, which `rule_key_check` accepts for an empty `area_key`) |
| P13 a set in another order than the span was computed from | registers (both sides are the multirange's canonical text) |
| A1b/A1d (battery) the three fixture rows | adopted as before — nothing valid refused |

`WHEN OTHERS` does not swallow `QUERY_CANCELED`, so a cancelled migration still cancels. One subtransaction per legacy row is a one-time migration cost; fine.

### 3. The audit guard (3066–3072) — does what Fable S4 / Codex S1 asked

K4i: a finding against the unfilled `e3` is refused 23514 "not yet adopted". P11a a finding on a tariff row and P11b on the filled legacy row `e1` are accepted, `e1` stamped `zz_fee v1` (P11c). The test `jsonb_typeof(terms) IS DISTINCT FROM 'object'` is the right predicate: a filled document is always an object (the validator), and the adopting table's CHECK (1878) ties the four columns together.

### 4. Generated columns refused (1760–1766) — does what Opus asked

T1ze (a `STORED` facet column); P10a a NOT NULL `GENERATED … STORED` `terms` refused "terms is a generated column"; P10b a generated key column refused; P10e a generated column that is none of template, key or facet registers (right: the template never writes it). Identity columns (`attidentity`, not `attgenerated`): P10c/P10d an identity facet column is refused by the existing NOT NULL dry-run, since an identity column is implicitly NOT NULL and the delegated document gives the facet no value; where a facet could never be NULL the BEFORE trigger's assignment is what is stored (the identity only supplies a default), so no identity shape stores what the document does not say. This server (16) has no virtual generated columns; `attgenerated <> ''` would catch them too.

### 5. The new cases for r7 clauses (T1zc, T1zd, A1h, A1i)

Each fails exactly the clause it names: T1zd needs the `pronamespace` filter (M188), T1zc the `m.fn = t.fn` half of the sorts-after exemption with the identity clause inactive (M189: 42710 instead of 42P16 on the mutant), A1h/A1i one span leg each (M194, M195). My r7 mutants a–d are all caught now.

### 6. R14, R22, R26, header, README

R14 and R22 (3370–3371, 3421–3423) and `law/README.md` 107 say what the code does. **R26 (3446–3449) does not, in one clause:** "a non-text key column, or repeated owner types in a legacy row, refuse registration with the underlying error rather than the combined message" was true of r7 (my r7 N3) but r8's per-row `EXCEPTION` block collects them *into* the combined message — P5b (`{municipal,municipal}`) and P6 (an integer key) above show the combined 42P16 report with the underlying message as the row's reason. See N1.

## 2. Did any r8 change open a hole in rounds 1–7?

No. The note rule only removes a document from the dry-run where no document of the kind can carry it (registry 1046–1057); the registration loop replaces two inline tests with calls to the same functions the fill uses plus two more; `rule_row_scope_check` is the r7 code moved, called at the same point with the same role; the audit guard and the generated-column clause are additive refusals before anything is written. The r1–r7 cases all ran in the 272; X1–X6, RC1–RC7, W1–W5 pass.

## 3. Tests: which mutation survives

M184–M195 all caught. Three hand mutants, applied strictly to `fable817ma`–`mc`, the battery **272 PASS on each**:

| Mutant | Survives because | What it opens (on r8 / on the mutant) |
|---|---|---|
| **a** drop the `governs const = delegated_to_utility` filter (1615), so `v_note` is "any branch has a note" | no battery kind has a note on a non-delegated branch | P16: a kind whose law branch has a note and whose delegated branch has none, facet `$.note` integer — registers on r8, **refused** on the mutant: the Codex B1 false refusal back, one branch over |
| **b** narrow the generated clause to `ANY (p_facet_columns)` (1764) | T1ze is a facet column | P10b a generated key column **registers**; Q2/Q3 a NOT NULL generated `terms` registers and a flat row is stored as `terms = {"governs": "law"}`, `fee_strategy = flat`, `fee_cap = 50` — the stored document is not the validated one (the hole Opus named, for the template leg) |
| **c** drop the tariff leg of `rule_row_scope_check` (1973–1977) | no tariff-row case has a cross-service kind | nothing in practice: P7 on the mutant is still refused by the profile lookup (P0002 "no profile for water (master_meter)"), and the -16 profile trigger refuses a cross-service profile (Q1: "a master_meter system is not one of water service"). An equivalent mutant; the state leg is shared with law rows (T5e) |

### Should-fix (tests)

- **S1.** Pin the `governs` filter of the note rule: a kind with `note` on the **law** branch only (`jsonb_set(s('fee') #- '{$defs,delegated,properties,note}', '{$defs,law,properties,note}', '{"type": "string", "pattern": "[A-Za-z0-9]"}')`), facet `$.note` integer, `does(...)` register; and a mutation dropping the `AND … = 'delegated_to_utility'` line at 1615 (M184 mutates the `CASE`, not the filter).
- **S2.** Pin the template and key legs of the generated-column clause: a generated key column (`customer_class text NOT NULL GENERATED ALWAYS AS ('x') STORED`, expect "customer_class is a generated column") and a NOT NULL generated `terms` (expect "terms is a generated column"); and a mutation replacing `c_template_cols || p_area_key || p_facet_columns` with `p_facet_columns` at 1764 (M186 drops the whole clause).

### Notes

- **N1.** R26's third sentence (3447–3449) describes r7. In r8 a repeated owner set, an unknown code, an empty set and a non-text key are all collected per row into the combined "does not fit" message, with the underlying message as the reason (P5a–c, P6). Reword to say so; the behaviour is the better one.
- N2. A row bad for two reasons is named for the first only (key, then scope, then spans — P3). Fine: the message says which row and why; the next attempt names the next reason.
- N3. The tariff leg of `rule_row_scope_check` has no case of its own; it is defended by the profile lookup and the -16 profile trigger (mutant c). A tariff-row case (`water` + `master_meter`, expect 23514 "is not a kind of water system" — my P7) would still be cheap and would make the function's two legs each pinned, but nothing rests on it.
- N4. The dry-run's early `RETURN` on the first `data_exception` (1624) returns before the second document is tried, so P9e names only the no-note document even if the note document would also fail; the registrant fixes one and sees the next. Unchanged from r7.

## 4. Housekeeping

Databases `fable817`, `fable817iso`, `fable817race`, `fable817law`, `fable817ma`–`mc` and the scratch runner's `fable8m17*` dropped; `/tmp/fable8-*` removed from the container; the runners' `/tmp/law` and `/tmp/battery-17.sql` left as they wrote them. No repo file other than this one written; the patch untouched.
