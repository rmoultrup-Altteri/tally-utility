# Review r7 — v5.4.2-17 (the rule-terms convention, written once)

**Reviewer:** fable. **Date:** 2026-10-09.
**Artefacts checked:** patch `b2684ffd74aaa19998cd58b470ba6883` (3377 lines), battery `e07b5516aa22f0103ab15086c93d5937` — both match the brief. The working copies `sql/v5.4.2-17-rule-terms-convention.sql` and `tests/v5.4.2-17/battery-17.sql` carry the same two hashes, so the runners (which read the working copies) tested the frozen revision. `diff patch-17-frozen-r6.sql patch-17-frozen-r7.sql` (246 lines) is exactly the six r7 changes the brief lists: header 58–69; the discriminator message 504; the strategy clause 562–567; `rule_table_trigger_errors` and its assertion 1499–1580; the delegated dry-run 1582–1617; the adopting-registration checks 1764–1787; the three unfilled-row refusals 2139–2154, 2295–2313, 2339–2370; R14 wording 3303–3305; R22–R25 3353–3374. The battery diff adds R4y, R3j, T1q–T1z, A1f, A1g, A5a–A5c and moves the A fixture's mismatched-span row after registration (934–937).
**Environment:** `fable717` (TEMPLATE tally; TEMP revoked from PUBLIC, tally_app, tally_core); strict apply (`search_path=''`, `check_function_bodies=on`) in one transaction, 0 errors. Clones `fable717iso`, `fable717race`, `fable717law`, `fable717ma`–`md` (my four hand mutants), `fable717m*` (a scratch copy of the mutation runner). All dropped at the end; my probe files removed from the container; `/tmp/law` left as the runners put it.

## Verdict: **ready** — no blocking item; three should-fixes, all in the tests (a clause present and correct in the patch but with no case that only it can fail), and one low should-fix in the patch

What ran and passed, unmodified, on `fable717`:
- battery r7: **262 PASS, 0 FAIL**, rolled back (247 in r6 → 262: R3j, R4y, T1q–T1z, A1f, A1g, A5a–A5c);
- `isolation-17.sh` X1–X6; `races/rule-close-17.sh` RC1–RC7; `lawfiles-17.sh` W3–W5 (899 documents, 0 disagreements);
- `assert_rule_table_invariants()` at the end of the battery plus my probes (7a);
- `mutations-17.py` (scratch copy pointed at `fable717m*`), the seventeen r7 mutations M167–M183: see §3.

## 1. The six r7 changes, each against what the finding asked

All probes appended to the frozen battery in its transaction (so the fixture, `zz_fee_rules`, `zz_fee_tariffs`, the half-adopted `zz_legacy_rules` and the roles are as the battery leaves them), each probe in a subtransaction, rolled back.

### 1. Template triggers by identity; inheritance children; rewrite rules (1513–1556) — does what Codex S2 / Opus S1 / Fable S1 asked

`trg` (1523–1528) resolves each trigger's function to its name only when it is a zero-argument `public` function (1527); `template` (1517–1520) names the function, the exact `tgtype` (7 = ROW|BEFORE|INSERT, 27 = ROW|BEFORE|DELETE|UPDATE, 34 = BEFORE|TRUNCATE — what registration's own `CREATE TRIGGER` at 1862–1864 produces, as the battery's T1k/T1y and my 7a confirm) and the WHEN/column-list absence (1548). The sorts-after exemption (1537) is by name **and** function. Probed on the registered `zz_fee_rules`:

| Shape | Result |
|---|---|
| T1q–T1t (battery): foreign function, fewer events, a WHEN, a column list | caught, named by the identity clause |
| 1a: template function on **more** events (BEFORE INSERT OR UPDATE, tgtype 23) | refused, "not the template's" — right: the insert guard running on UPDATE is not the template either |
| 1b: `ENABLE TRIGGER` (origin, `tgenabled = 'O'`) | refused, "missing or not ENABLE ALWAYS" |
| 1c: `zzs.enforce_rule_row_insert()` — the template's name in another schema | refused (twice: the sorts-after clause, since `fn` is NULL for a non-public function, and the identity clause) |
| 1d: the template function as a DEFERRABLE CONSTRAINT TRIGGER under the template name | refused (AFTER-only, so tgtype ≠ 7). A transition table (`REFERENCING`) is AFTER-only too, so it can never match tgtype 7/27 |
| 1e: a second trigger running `enforce_rule_row_history` under a late name (`zzz_dup`) | refused by the sorts-after clause (the exemption is by name and function, so a template function under another name is not exempt — fine, nothing legitimate does that) |
| 1f: an area trigger `a_area` BEFORE INSERT | **accepted** (the -13 shape) |
| 1g/1g2/1g3: rules ON UPDATE DO ALSO NOTHING, ON DELETE DO INSTEAD NOTHING, ON INSERT DO ALSO (a copy) | all refused, "has a rewrite rule" (`pg_rewrite.ev_class`, every event) |
| 1h: a view over the table | **accepted**, right: 1h2 shows an insert through the auto-updatable view is validated by `rule_row_insert` (23514 from the validator) |
| 1i: an inheritance child created and dropped | accepted after the drop (T1u refuses while it exists) |
| 1j: a partitioned table (`PARTITION BY HASH (id)`, PK id) registered | refused earlier, 22023 "not an ordinary table" — so no registered table can have a partition child |
| 1k: a registered **law** table ATTACHed as a partition of a new parent | assertions pass (the registered table is the child, not the parent). 1k4: an insert routed through the parent is validated by the partition's `rule_row_insert` (23514). 1k2: a late BEFORE ROW trigger on the parent is cloned onto the partition and the assertion **catches the clone** (`tgisinternal` is false for clones in 16). 1k3: a template-named trigger on the parent fails at the clone (42710). So a parent above a registered table cannot route a row around the template |
| 1l/1l2: a registered **tariff** table ATTACHed as a partition of, or INHERITing from, an RLS-less parent granted to tally_app | `assert_rule_table_invariants()` passes (right: not its concern); `assert_tenant_isolation_invariants()` refuses the parent (42501, "lack RLS") — which is the control that matters, since 1l3 shows tally_app u1 sees `own=1, via_parent=2` through such a parent. That assertion runs in the tail and in CI; nothing for r7 |

Nothing it should allow is refused (1f, 1h, 1i, 1k, T1x, T1y); nothing it should refuse is let through in the shapes above.

### 2. A pre-convention row with `terms IS NULL` (2139–2154, 2295–2313, 2339–2370; 1764–1787) — does what Fable S2 / Codex N2 asked

The three readers refuse by name (A5a–A5c; my 2d shows `rule_law_row_cite` refuses through `rule_row_cite`). The filled rows are still read (2e, 2f: e1 is looked up and cited after the battery's A2). The other readers, on the still-unfilled e3:
- 2a `rule_row_seed`: refused, 23505 "already holds this law row … with a different terms, terms_kind, terms_version" — the seed's compare sees the NULL document as a difference. Right outcome, by a general rule rather than a named one; fine.
- 2b the close: **accepted** (an owner closes e3). That is the exemption the brief names; retiring a row that will never be adopted is the only way to end it, and nothing reads a closed unfilled row as law.
- 2c an audit finding naming e3 as its rule row (`tally_core`): **accepted**, with `terms_kind`/`terms_version` stamped NULL (3006–3007; the table has no CHECK tying `rule_table` to `terms_kind`, only to `rule_row_id`). Low: the core cannot have decided under e3, since every lookup refuses it — see S4.

Adopting registration (1770–1787): the blank-key test is the same `[[:alnum:]]` predicate as `rule_key_check` (2575), so what registration admits the fill admits (3f `é` and 3h `42` accepted; 3g tab+NBSP refused; A1f). The span compare is multirange `IS DISTINCT FROM` against the same functions the fill uses (2031–2035, compared as jsonb text at 2268–2270 — both canonical): a set in another order than the span was computed from registers (3a); a span written as adjacent ranges registers (3b: ordinals are 0–4, so `{[0,1),[1,2)}` canonicalises to `{[0,2)}`); both failures of one table are reported together (3i). A legacy row whose **set** is bad — `{}` (3c), `{bogus}` (3d), `{municipal,municipal}` (3e) — is refused at registration by `rule_applicability_span`'s own exception (23514/23503) rather than collected into the "does not fit" report; a refusal at the right time with a clear message, so a note (N3).

### 3. The delegated dry-run on both documents (1598–1612) — does what Opus S2 asked

T1z (a facet reading the note as a number) is refused on the document with a note. Probed facets that depend on the note in other ways: lax `$.note` text on a nullable column registers (4a); `strict $.note` is refused on the **no-note** document, named in the message (4b); lax `$.note` into a NOT NULL column is refused naming the no-note document (4c); a `present` facet into a NOT NULL boolean registers (4d: present is never NULL); `$.note.size()` as integer (4e) and a filtered path (4f) register. The early `RETURN` on the first exception (1604) returns whatever NOT NULL findings the earlier document produced; fine.

### 4. `strategy` required (565–567) — does what Fable S3 asked

R4y (declared, `required: ["version"]`) refused; 5a (no `required` at all) refused with both messages; the ZZ tariff schema still registers under a new kind (5b).

### 5. The trigger-name cases, and `COLLATE "C"`

T1w/T1x/T1y pin byte order, upper case and AFTER ROW. The collation question: `pg_collation_for(tgname::text)` through the `trg` CTE is `"C"` (6a) — a cast carries its argument's collation, and `name` is C-collated — and `rulerowa >= 'rule_row_history'` is **true** through the CTE without the `COLLATE` (6b) while the same literal compare is false in the database's `en_US.utf8` (where M175 bites). So dropping `COLLATE "C"` alone is behaviour-neutral, as the brief says. The case where it would not be neutral is the one the comment at 1534–1535 guards: a rewrite that routed the name through a `text` of the database's collation first — a temp table, a `format()`-built string, a `text[]` parameter — would lose the C derivation and compare in `en_US`. Nothing in the patch does that.

### 6. The discriminator message (504) and `law/README.md` 82, 98

Say "written inline — a discriminator is never a `$ref`"; R3j pins the message. R22–R25 state the r6 notes as I read them (R22 ↔ my r6 N3/N4, R23 ↔ N5, R24 ↔ N6, R25 ↔ Opus S1's "not ONLY"); R14 now names the registration refusals.

## 2. Did any r7 change open a hole in rounds 1–6?

No. The r7 code is additive: new UNION ALL branches and a CTE in `rule_table_trigger_errors` (the sorts-after clause keeps `NOT tgisinternal`, the BEFORE|ROW test and the C compare); new checks after the "already filled" check in registration, before the schema lock; a raise before the row is used in each of the three readers. The identity clause is gated on `rule_tables` (1546), so at registration a pre-existing trigger under a template name is still refused by the sorts-after clause (BEFORE ROW) or by `CREATE TRIGGER`'s 42710 (r6 N7, my 1k3) — never adopted silently. The battery's `DISABLE TRIGGER … ENABLE ALWAYS TRIGGER` around the A fixture's span edit (934–937) leaves the triggers as the template made them (7a passes afterwards). The r1–r6 cases all ran in the 262.

## 3. Tests: which mutation survives

The seventeen r7 mutations M167–M183, run through a scratch copy of `mutations-17.py` pointed at `fable717m*`: **17/17 caught at their named checks** (M167 R4y … M183 A5c), as the brief states. Each new clause has a case, but four clauses are caught only by a case that also fails for another reason, so a mutant of each survives the whole battery — built by hand, applied strictly to `fable717ma`–`md`, battery **262 PASS, 0 FAIL on every one**, and each hole demonstrated:

| Mutant | Survives because | The hole it opens (refused on r7, ACCEPTED on the mutant) |
|---|---|---|
| **a** drop the `system_span` leg (1782) | A1g's row is off on `owner_types` only | 3j: a legacy row with `system_kinds = {distribution}` and the default system span registers — a row the fill refuses (2269), unfillable for good: the r6 S2 (ii) gap re-opened on one leg |
| **b** drop the `jurisdiction_span` leg (1783) | same | 3k: `commission_jurisdiction = true` with span `[0,2)` registers |
| **c** drop `p.pronamespace = 'public'::regnamespace` (1527) | T1q's foreign function has another **name** | 1c: `zzs.enforce_rule_row_insert()` under the template name passes the assertion and the sorts-after exemption — rows unchecked |
| **d** drop the no-note document (1598) | T1p's `strict $.fee.cap` raises on both documents | 4b: a `strict $.note` facet registers; the first real delegated row without a note fails loudly (R22 class) |

`p.pronargs = 0` (1527) and the `m.fn = t.fn` half of the sorts-after exemption (1537) are equivalent mutants (trigger functions take no arguments; a foreign function under a template name is caught by the identity clause once registered and by 42710 at registration), not holes.

### Should-fix (tests)

- **S1.** A1g covers the owner leg only. Add a `system_kinds` row and a `commission_jurisdiction` row (my 3j, 3k: `LIKE zz_legacy_rules`, one row each, register as adopting), and mutations dropping each leg of 1781–1783 (M180 drops the whole `IF`).
- **S2.** Add a case for the template's function **name** in another schema (`CREATE SCHEMA zzs; CREATE FUNCTION zzs.enforce_rule_row_insert() …; CREATE OR REPLACE TRIGGER rule_row_insert … EXECUTE FUNCTION zzs.enforce_rule_row_insert()` on `zz_trig`, expect "not the template's"), and a mutation dropping the `pronamespace` filter at 1527.
- **S3.** Add a case that only the no-note document fails: a kind whose facet is `strict $.note` (text, nullable column), expect "cannot be derived from the standard delegated document {"governs": "delegated_to_utility", "citation": "x"}"; and a mutation dropping the first document at 1598 (M178 drops the second).

### Should-fix (patch, low)

- **S4.** `rule_audit_findings`' guard accepts a rule row whose document is empty and stamps `terms_kind`/`terms_version` NULL (2c; 3000–3007). The core cannot have decided under such a row (every lookup refuses it), so a finding that names one is a mistake worth refusing: after 3005, `IF (v_rule -> 'terms') = 'null'::jsonb THEN RAISE … 'is not yet adopted into the convention'` (check_violation), the wording of 2311. One case (a finding against the A fixture's e3 as `tally_core`), one mutation.

### Notes

- N1. The close of an unfilled legacy row is accepted (2b). Right, and the brief's exemption; stated here so the record shows it was probed.
- N2. A parent above a registered table (partition or inheritance) cannot bypass the template (1k2–1k4) and, for a tariff table, is caught by `assert_tenant_isolation_invariants()` (1l, 1l2, 1l4) — the AC-32 assertion, not r7's. R25 could say so in one clause ("… and a parent above it is caught by the tenant-isolation assertion"), since 1l3 shows what tally_app would otherwise see through it.
- N3. A legacy set that is empty, repeated or unknown is refused at registration by `rule_applicability_span`'s exception (3c–3e: 23514/23503 with the function's message) rather than in the "does not fit" report. A refusal at the right moment; collecting it would need a per-row `BEGIN … EXCEPTION` and is not worth it.
- N4. 1c is reported twice (sorts-after and identity). Harmless.
- N5. The seed's refusal of an unfilled row (2a) comes from the "same row" compare, so its message says "a different terms" rather than "not yet adopted". Fine; a seed never fills a legacy row.
- N6. `rule_tariff_row_as_of` cannot meet an unfilled row: only a law table adopts (A1a), and a non-adopting table's `terms` is NOT NULL (1685, `v_doc_nn`).

## 4. Housekeeping

Databases `fable717`, `fable717iso`, `fable717race`, `fable717law`, `fable717ma`–`md` and the scratch runner's `fable717m*` dropped; `/tmp/fable7-*.sql` removed from the container; `/tmp/law` and `/tmp/battery-17.sql` left as the runners wrote them. No repo file other than this one written; the patch untouched.
