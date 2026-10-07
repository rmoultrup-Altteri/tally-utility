# Review r1 — v5.4.2-17 (the rule-terms convention, written once)

**Reviewer:** fable. **Date:** 2026-10-07.
**Artefacts checked:** patch `bf006d2a6722035d928e34177fdf60a0` (2558 lines), battery `43c4132fb4ed8d2cdebfd77c30429c15` — both match the brief; `sql/v5.4.2-17-rule-terms-convention.sql` and `tests/v5.4.2-17/battery-17.sql` carry the same hashes.
**Environment:** `fable17` (CREATE DATABASE … TEMPLATE tally, TEMP revoked), strict apply (`search_path=''`, `check_function_bodies=on`) — clean, and a second strict apply is clean (idempotent). Scratch clones `fable17_iso`, `fable17_race`, `fable17_law`, `fable17_m*`; all dropped at the end.

## Verdict: **not yet** — one blocking item, a short list of should-fixes

What ran and passed, unmodified:
- battery: 177 PASS, rolled back;
- `isolation-17.sh` X1–X5: 5/5; `races/rule-close-17.sh` RC1–RC4: 4/4 (second session seen waiting in every leg);
- `lawfiles-17.sh` W1–W5: all pass; crosscheck 478 + 79 + 77 documents, 0 disagreements;
- `mutations-17.py` (a scratch copy pointed at the frozen patch and `fable17_m*` names): sample M23, M41, M44, M59, M66, M69, M74, M97 — 8/8 caught, so the harness is sound; I did not run all 104.
- privilege audit: the set of tables/views `tally_core` can SELECT equals `tally_app`'s (both directions empty diff); no function `tally_core` can EXECUTE that `tally_app` cannot; `tally_core` writes only `rule_audit_findings`; every public view is `security_invoker=true`; no sequence privileges; no TEMP/CREATE; not a member of `tally_app` nor the reverse.

### Blocking

**B1. `rule_tariff_check` reads the law rows before it locks them, so the T4 handshake it claims is not one (patch 1716–1730).**
The query `FOR l IN EXECUTE 'SELECT … FROM <law table> …' LOOP PERFORM pg_advisory_xact_lock_shared(rule_row_lock_key(law_table, l.id)) …` takes its snapshot when the query starts; the shared lock is acquired per row *after* the row (and its `daterange`) has been read. Under READ COMMITTED a close in flight on that row makes the tariff wait on the lock, and when the close commits the tariff carries on with the stale range. Reproduction on `fable17_law` (committed ZZ fixture, T2 investor-owned profile, IOU residential law row from 2000, open):

```
A: BEGIN; UPDATE zz_fee_rules SET effective_to = DATE '2010-01-01' WHERE id = <iou row>; pg_sleep(3); COMMIT;
B (1 s later, tally_app, T2): INSERT INTO zz_fee_tariffs (… customer_class 'residential', effective_from 2020-01-01, open …)
  -> B seen waiting on Lock (pg_stat_activity: 1)
  -> B: TARIFF ACCEPTED 744963f3-…
after: law row effective_to = 2010-01-01; tariff rows: 1, from 2020-01-01, open
```

The header says a tariff "over part of its range with no law known is refused" (111) and that a close "takes it exclusive and then reads its floor" (62–63); the record is in the refused state, under the exact interleaving the lock exists for. `rule_row_cite` does this right (lock, then re-read, 1854–1856); the tariff check is the one path that does it backwards. Fix: collect the candidate ids, take every lock, then re-run the query (or re-read each row by id) and compute `v_lawed`/`v_rows` from the second read. Note also that the law table's close floor is the area's and counts citing *records* only (`zz_fee_floor` reads charges), so a close under a tariff is allowed even without a race; R6 covers a later *insert* but not a *close* — say so in R6 (or add tariffs to the law floor), otherwise the shared lock protects nothing durable and a reader of the code will think it does.

### Should-fix

**S1. The reference validator and the database disagree on `$` with a trailing newline; the "same meaning in ECMA-262, Python and PostgreSQL" claim (345–346, README) is false for the whitelisted code pattern.** Python `re.search("^[a-z][a-z0-9_]*$", "f1\n")` is True and `Draft202012Validator(...).iter_errors("f1\n")` is empty; PostgreSQL `E'f1\n' ~ '^[a-z][a-z0-9_]*$'` is false, and `rule_terms_errors(tariff schema, {"fee": {… "id": "t1\n" …}})` returns `/fee/id: does not match`. ECMA-262 agrees with PostgreSQL, so the reference tool is the outlier, but W4's corpus never produces a string with a newline (the replacements are `"x"`, `""`), so W4 passes while the claim is wrong (memory: checks narrower than their claim). Fix: in `lawc.py` pre-process patterns (`$` → `\Z`) or add `"f1\n"`-style mutations and accept the documented divergence; either way correct the comment and README.

**S2. `stamp_core_inputs` takes the schema lock shared but does not assert READ COMMITTED (2240–2288).** Under REPEATABLE READ it can wait for a freeze and then read the pre-freeze snapshot — the gap `assert_rule_read_committed` closes everywhere else. Reproduced: `BEGIN ISOLATION LEVEL REPEATABLE READ; SET LOCAL ROLE tally_core; INSERT INTO zz_charge_calcs …` → `CALC ACCEPTED UNDER REPEATABLE READ`. One line.

**S3. `rule_row_cite` ties a citation to a date only, not to the utility (1842–1868).** Spec U4/T3: records cite "the law row in force" for the premise/tenant. Reproduced: tenant T1 (municipal) — `rule_law_row_as_of` says its row is the delegated row `22f81419…` — inserts a charge citing the IOU row `a918f8a7…` (in force on the date): `T1 CHARGE CITING IOU ROW ACCEPTED`. Every area would re-implement the check; offer `rule_law_row_cite(table, id, tenant, service, system_kind, state, key, on)` = `rule_row_cite` + `rule_law_row_as_of(...) = id`, or state it as a residual that the area's guard must do.

**S4. `rule_row_seed` silently ignores keys that are not columns (2003–2004).** `jsonb_populate_record` drops unknown keys. Reproduced: a seed row with `"effective_too": "2030-01-01"` inserted with `effective_to = NULL`. The function's own comment is "never a silent skip". `lawc.py` cannot emit such a key, but the function is the migration's API. Fix: compare `jsonb_object_keys(p_row)` with `pg_attribute` and raise.

**S5. `rule_table_register` with `adopts_legacy_rows = false` accepts a table that already holds rows and never validates them (1444–1486).** Reproduced: `zz_pre` with `terms = {"garbage": true}`, `fee_cap = 12345` registered cleanly; the stored row stands. Refuse a non-empty table unless adopting (one `EXISTS`), or validate.

**S6. P1 is missed in part: `rule_parameters.scoped_by` allows `{}`, `{state_code}`, `{state_code, service_type}` only (2068–2069); the inventory's P1 scope is state, service **and class**, and -15's `deposit_interest_rate_law` has `customer_class`.** Either add the dimension now (a third column on `rule_parameter_values`, the trigger and `rule_parameter_value_as_of` already generalise) or record as a residual with the reasoning (§183.003 is one rate per state, so class may never be needed).

**S7. C3's "dispositions as separate append-only rows" is neither built nor a residual.** The table comment says "who acts on a finding … is each area's design" (2380), which is a decision the inventory classed Step 2. Build the table (finding_id, disposition kind, by, at, note; append-only; tenant RLS) or add it to section 11 explicitly.

**S8. V5 ("a strategy reference names its version") is a format rule the registry could enforce and does not.** Reproduced: a tariff kind whose `strategy`-discriminated branches have no `version` property registered (`zz_nover`). Registration already inspects every union; requiring `version` (integer, `minimum = maximum`) in a branch whose discriminator is `strategy` is a few lines, and it is the rule that lets the core reproduce old decisions. V6, V7 and P3 are README-only too; those are fine as conventions, V5 is load-bearing.

**S9. W4 is never shown to catch anything.** No mutation names a W check; every validator mutation is caught by the battery first. Add at least one mutation only W4 catches — e.g. disable `minLength` (the battery tests `maxLength` only, V19; the corpus replaces `note` with `""` and the reference says invalid). Also worth adding to the corpus: a string with `\n`, a non-ASCII string, a nested depth past 64 with a recursive schema (see N3).

**S10. The header overclaims "a state not known" is refused (106).** `state_code` has only `^[A-Z]{2}$`; a law row for `QQ` (no place) is stored. Either FK/EXISTS against the state places (-16 has them) or drop the claim.

**S11. -13 adoption needs two things the patch and README do not say.** (a) The template requires `owner_types/system_kinds/commission_jurisdiction/*_span` on a law table, and adoption refuses to move spans ("fix the spans first", 1826); `backbilling_rules` has none, so the migration must add the columns and set the 16 rows' applicability *before* `rule_table_register` installs the history trigger — an unaudited UPDATE window that should be stated as the sanctioned sequence. (b) `a_enforce_backbilling_rule_history` (tu.sql 24267) refuses every UPDATE but a close and fires before `rule_row_history` ("a_" < "r"); it must be dropped or taught the adoption shape in the same migration. Also, the inventory §4A check "the document equals what the old typed columns said" is not the template's — point -13 at `insert_check`, which receives the whole row (old typed columns included) during adoption (1642).

### Notes

- N1. `-0` and `1e2` reach the DB as `0` and `100` (parser), so the DB says valid while `lawc`'s fixed rule says non-canonical (`Decimal("-0")`, `Decimal("1E+2")`); YAML refuses exponents, so only a JSON example could show it. Harmless; mention in README if a JSON corpus ever grows.
- N2. A close may rewrite a numeric facet's representation: `UPDATE … SET effective_to = …, fee_cap = 50.000` passes the whole-row comparison (jsonb `50 = 50.000`) and stores `50.000`. Meaning unchanged; strictly an edit. Compare `::text` for numeric columns or accept.
- N3. Recursive schemas register (a `$def` referring to itself is not a chain) and the document depth cap of 64 then becomes a divergence from the reference validator; document it.
- N4. `vocabulary_scope` maps a vocabulary column to a rule-row column name that is checked only at row insert (`p_row ? …`, 1595) — fails closed, but a typo surfaces at the first row, not at declaration. Cheap to check at declaration when the table is registered later… it is not known then; note only.
- N5. `tally_core` and `tally_app` get EXECUTE on `rule_terms_errors`, lookups and `rule_row_cite`; seed and register are revoked from both (verified). Fine.
- N6. L1 says one file per (kind, state, service, **owner type**); the fixture file mixes owner types and the loader does not enforce the partition. The README states (state, service). Settle which.
- N7. A row inserted with `effective_to` already set has `closed_at NULL` and can never be closed earlier ("never edited"). Intentional, I think; say so in the template comment.
- N8. `rule_tariff_check` locks law rows but the comparator gets `to_jsonb(law row)`, so the area's comparator reads facets, not `terms` — good; the comment at 1753 could say that is the contract.
- N9. CI: `.github/workflows/ci.yml` + `tests/ci.sh --build` not runnable here; `tests/ci.sh` without `--build` matches what I ran by hand. `pointer-mutex-12.sh` clones from `tally`, not `$BASE` — reads only, fine.

## 1. The spec, requirement by requirement

| Req | Status | Where / remark |
|---|---|---|
| V1 | held | `rule_term_schemas` 789–818; `rule_role` added; freeze is the one edit (R7/R8) |
| V2 | held (pattern) | kind CHECK + FK added by `rule_table_register` 1445–1447 |
| V3 | held | 570–711; rationals by composition (`{num, den}` as an object) — no fixture exercises one |
| V4 | held | oneOf by const discriminator 596–617; V6/V7 |
| V5 | **not enforced** | format rule only (README); S8 |
| V6, V7 | convention | README; fixture uses per-section citations; `unruled`-style enums are the area's |
| V8 | held | 876–900, R3a–c, V17 |
| V9 | held | `rule_terms_schema_errors` 524–566; R4a–m |
| V10 | held, narrow | `lawc crosscheck` + W4; S1, S9 |
| F1–F3 | held | 935–1086, 1569–1611; F1–F5, T6d/h/i |
| F4 | held | `insert_check(jsonb)` receives row ∪ facets 1641–1643; T6j |
| F5, F6 | area | — |
| F7 | held (pattern) | `component_ids text[]` facet; the `(rule_id, 'p1')` check is the area's |
| T1 | held | template columns 1368–1403; triggers 1480–1485 |
| T2 | held | spans 1090–1218; T3/T4; state has no vocabulary (S10) |
| T3 | held | `rule_law_row_as_of` 1875–1922; L1–L2f; citation not tied (S3) |
| T4 | held except tariff | cite/close/freeze/insert lock-then-read; **tariff check reads-then-locks (B1)**; inputs lack RC assert (S2) |
| T5 | held | `rule_row_seed` 1967–2026; T4d–g; unknown keys (S4) |
| T6 | held | adoption 1801–1830; A1–A3g; -13 sequencing (S11) |
| T7 | residual R2 | as the inventory allows |
| U1 | held | tariff template 1392–1398, 1462–1479; FORCE RLS, canonical policy |
| U2 | held | `rule_terms_parse` 758–782; V21a–d, T6b; escaped-duplicate keys (`"a"`) are caught too |
| U3 | held (hook) | `rule_tariff_check`; comparator is the area's; U2a/U3a–c; B1 |
| U4 | held (pattern) | `rule_tariff_row_as_of`; S3 |
| U5 | area | — |
| P1 | **partly missed** | class scope absent (S6) |
| P2, P4 | area / — | — |
| P3 | convention | README |
| C1 | held, verified | section 1; privilege audit above |
| C2 | held (pattern) | fixture `zz_charge_calcs` shows it; `evaluated_by` → R1 |
| C3 | held except dispositions | 2297–2462; K3–K6; S7 |
| C4 | held | `stamp_core_inputs`; I1–I3f; S2 |
| L1 | held, loosely | README; file partition not enforced (N6) |
| L2 | held | `StrictLoader`, `typed()`; W5 |
| L3 | held | `tests/ci.sh`, workflow; builds unverified here (N9) |
| L4 | held | `law/fixtures/zz/`: a law row (`residential_iou`), a delegated row (`residential_city`), and `commercial_all` (`owner_types: any`) binds a municipal system under law. The battery never resolves the *municipal* profile to that binding row (L1 looks up T1 residential and T2 commercial only) — add T1 commercial → lr3 |

**Will -13 and -15 be able to use it?** Yes, with S11 for -13 (add columns, set applicability before registering, drop its own history trigger, use `insert_check` for the old-columns equality) and S6 settled for -15. The template choices the brief asks about:
- *Applicability as sets with NULL = every one, spans in the exclusion* — right; T4a/b prove the catch that `=` on text could not make; "every" including future codes is the correct reading of a law that names none.
- *Area key NOT NULL, `=`* — right; R3 states the consequence (a row per class). For -15 that means (class, basis) rows; fine.
- *Law always, tariff optionally* — right, and the delegated row makes the city case uniform; the missing piece is that nothing ties the cited law row to the utility (S3).
- *Tariff checked against law rows sharing key columns* — right as a rule; the mechanism needs B1.
- *One-time adoption* — right; narrower than R7's "disable the guard" and auditable; needs S11's sequencing.
- *`rule_row_seed`'s "same row" = (state, service, start, the three spans, area key)* — reasonable; `effective_to`, note, kind, version, terms must then match or it raises; a file that changes applicability yields a new row that the exclusion refuses, which is the right answer. S4.

## 2. Integrity — what I tried that held

- Validator subset: `$ref`+`type`, type lists, `"null"`, `format`, `$defs` below root, patterns outside the whitelist, chained `$ref`, discriminator via `$ref`, `const` on integer, `minItems` on string — all refused at registration (R4a–m and my P-H/P-N/P-O probes). Branch selection by const agrees with "exactly one of" because consts are distinct. `enum`, `const`, bounds inclusive/exclusive at the edges, `uniqueItems` (jsonb equality = JSON Schema equality), `char_length` = code points = Python `len`, `[A-Za-z0-9]` on `é` false in both.
- Numbers: canonical rule refuses `1.50`, `2.0`, `0.0`, `100e-2` (→ `1.00`); accepts `1e2` (→ `100`), `-0` (→ `0`) — N1.
- Parser: duplicate keys at any depth, including a key written as `"a"` next to `"a"` — PostgreSQL's `IS JSON WITH UNIQUE KEYS` compares decoded keys (verified false = duplicate).
- Facets: writer-set facet differing from the derived value refused, including a `text[]` in another order (ordered equality; stricter than needed, not wrong); single-valued facet matching twice raises; `strict $.**.id` does not duplicate through arrays (lax does: verified `["z","x","x"]` vs `["z","x","y"]`).
- `to_jsonb(NEW)`/`jsonb_populate_record`: multiranges round-trip as text; writer-supplied stamps are overwritten; `closed_at/closed_by` forced NULL at insert; a close that also edits anything else is refused (T7c); N2 is the only slack I found.
- Dynamic SQL: every identifier through `%I`, every value through `%L` or `USING`; `vocabulary_table` is a `regclass::text`; `to_regclass` under `search_path = public, pg_temp` with no TEMP for either role.
- Tenancy: tariff insert for another tenant fails on the profile read under RLS (U3c) and on WITH CHECK; `rule_row_cite` on another tenant's tariff fails on visibility (C2b); audit-finding subject and tariff rule row checked in-tenant under RLS (K4d/g); `assert_tenant_isolation_invariants()` passes with the fixture's three tenant tables present.
- Privileges: see the audit above; a second strict apply changes nothing.
- Depth/recursion: recursive schema registers; 70-deep document refused at 64 (N3).

## 3. Tests

Guards tested by a case only they can refuse: nearly all; `pg_temp.refuses()` requiring SQLSTATE + the guard's own phrase is the right discipline, and the eight sampled mutations prove the harness catches by the named check. Gaps:
- no negative case for `rule_row_seed` differing in `effective_to`, `terms_kind` or `terms_version` (only terms and note);
- no case for a tariff whose range spans two law rows (one `law`, one `delegated`) — the comparator's "nothing to compare" branch is asserted only indirectly (U1);
- no case that `tally_core` cannot UPDATE/close a tariff or law row (grants are right; untested);
- no case for `minLength`, for `coverage_to >= coverage_from`, for the depth cap, for `effective_to > effective_from`;
- W4 has no mutation (S9); none of W1–W5 is mutated;
- B1 has no race leg: add RC5 = "a tariff insert waits for a close of a law row it is measured against, then sees the close and is refused";
- S2 has no isolation leg: add X6 = a core record under REPEATABLE READ;
- the fixture has a municipal system bound by law (`commercial_all`), but no lookup or citation exercises it from the municipal profile — the one case the Texas launch does *not* have (a city bound by state law, as in Kansas).

Does W4 prove what it claims? It proves agreement on the corpus it generates — 634 documents — and that corpus is good at structural edits. It does not reach string semantics (S1) or depth (N3), and nothing shows W4 would fail if the DB validator drifted (S9).

## 4. Housekeeping

Databases `fable17*` dropped after this review. No repo file other than this one written.
