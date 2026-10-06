# Review: rule-terms convention proposal (2026-10-06)

Reviewer: Fable (independent; the other two reviews unseen).
Proposal: `application/rule-terms-convention-proposal-2026-10-06.md`, md5 `4b30e3704881764670d4ee34c199bec3` — **matches** the brief.

What I read: the proposal; `sql/v5.4.2-15-deposits-law-to-core.sql` in full (2,909 lines); `sql/tu.sql` for the -13 rule tables (23,984–24,430), the -13 record guards (25,170–25,384), `regulatory_surcharge_rules` (18,842), `program_types` (11,723), `meter_accuracy_thresholds` (22,246), the jsonb precedents (`rate_items.tier_config` 4,102–4,137; `validate_custom_fields` 956; `invoice_calculation_snapshots` 16,292–16,476); the survey; the audit; rules-for-the-core; `tests/v5.4.2-15/review/review-findings-15-r2.md`. Read-only queries against the live container (PostgreSQL 16.14) where noted.

How to read "verified": I ran it or read it at the cited line. "From knowledge": PostgreSQL or .NET behaviour I did not test here.

---

## 0. Verdict in one paragraph

**Adopt with changes.** The direction is right and the survey is decisive: a typed column per setting is a DDL treadmill, and v5.4.2-13 already needed a part table plus a seven-row kind vocabulary to hold *one clause* of one statute (`backbilling_rule_window_terms`, `backbilling_window_term_kinds`, tu.sql:23,984–24,170). But the proposal as written has four gaps that would cause regret within two years, and they are all about *who validates what, when*: (1) §2.5 puts the utility's tariff values into `terms` too, and those rows are written by `tally_app` at runtime, so §2.2's "written only by reviewed migrations, CI loads every row" does not cover them at all; (2) nothing in the proposal stops a misspelt optional key from being silently read as "absent = default" by the core, which is the one failure mode that turns a representation change into a wrong-law-applied bug; (3) versioning is left open while the citation guarantee ("every record cites its rule row, whose terms are immutable") depends on resolving it one specific way; (4) there is no validator at all until a core exists, and "the core owns the definition" has no owner today. Each is fixable in the convention document before anything is built. Details below; the findings list is in §9.

---

## 1. The seven questions

### Q1. Is the A/B split right? Is any (B) guard really record integrity?

**Verdict: the dichotomy is right, but mis-labelled and under-enumerated, and there is a third class the proposal does not name.**

*What is actually in (B) in the draft patch.* The proposal's four examples (§1) are about a quarter of it. Every guard that reads a rule's settings (not its key) in `v5.4.2-15`:

| Where | Lines | Reads | What it refuses |
|---|---|---|---|
| `enforce_deposit()` | 1373–1377 | `cap_combinator` | a deposit with no recorded cap under a rule that caps |
| same | 1381–1387 | `deposit_rule_cap_parts`, `cap_scope` | a statutory cap not of a rule part's kind; `cap_other_held` other than under combined scope |
| same | 1402–1408 | `deposit_rule_trigger_thresholds` | a trigger deposit citing no threshold where the rule sets one |
| same | 1409–1438 | threshold `measure`, `min_count`, `min_ratio` | citing the wrong threshold; observed measure below it; non-integer count |
| `enforce_deposit_instalments_complete()` | 1568–1596 | `deposit_rule_instalments` | instalment count ≠ schedule (the "sum to principal" half is arithmetic) |
| `enforce_deposit_return_due_record()` | 2210–2215 | `refund_mandatory`, `return_mandatory_instruments` | a due row under a rule with no mandatory return for the instrument |
| same | 2218–2223 | `refund_excess_over_cap` | a partial due row under a rule that returns no excess |
| `enforce_deposit_return_due_evidence()` | 2325–2342 | `refund_after_count`, `refund_on_account_close`, `refund_excess_over_cap`, `refund_measure` | a reason the rule does not enable; a measure the rule does not count in |
| FK `deposits_trigger_rule_threshold_fkey` | 1283 | part table | a citation of a non-existent threshold row |
| `deposit_return_reasons.enabled_by` / `requires_measure` | 382–384, 399–408 | (names rule attributes) | the vocabulary itself binds reasons to rule columns |

All of these go under the proposal. The proposal should enumerate them (with lines) before Ryan decides §5 step 1, because "drop (B)" is being decided on a list a quarter the length of the real one.

*The third class, (C): law-row self-consistency.* These are guards on the **law table**, not on records: parts only in the rule's transaction (735–829), cap parts fit the combinator and instalments sum to 1 at commit (833–863), a reach row names a trigger only on a basis that requires one and one class reaches a rule one way (773–791), a disqualifier only with a count trigger, a threshold only on a trigger basis, `UNIQUE (rule_id, cap_kind)` (669), the paired-NULL CHECKs on `deposit_rules` (505–566). Under the proposal all of (C) leaves the database and lives only in the core's types and the CI load test. That is acceptable *because law rows are migration-written*, but it must be said: the database will accept `{"cap": {"combine": "lesser_of", "parts": [one part]}}` and only CI will notice. (C) is also exactly the class that §2.5 silently extends to `tally_app`-written tariff rows (see Q6/B1).

*Is any (B) guard really integrity?* I looked for guards that look like (B) but can be kept without reading `terms`:

- **Keep (they only look like (B)):** instalments sum to the principal and `received_at_posting < principal` (1288–1290, 1568–1596: the arithmetic half); a partial due row's amount `< remainder` (2224–2228); `cap_amount`/`cap_other_held` arithmetic (1263–1271); a cited due row is live, of the event's kind, dated on or after `due_on` (2581–2601). None read a rule. The proposal's §2.3 says "(A) stays unchanged" and these are (A); good, but the rewrite must keep the arithmetic half of each mixed guard when it strips the rule half, and the draft currently fuses them (e.g. `enforce_deposit_instalments_complete` checks count and sum in one place).
- **Cannot be kept without reading `terms`:** everything in the table above. There is no trick that makes "the return is mandatory for this instrument" checkable from records alone, because the fact lives only in the rule. The honest statement is: any check of a record against the law's content reads `terms`, whether it is a trigger or a view.

*The mis-labelling.* The proposal's replacement for (B) is "a report view per area lists records that disagree with their rule's terms" (§2.3). Such a view **reads `terms`** — it is a (B) reader by another name, written in SQL, coupled to one `terms_version`'s key paths. That is fine as a choice (a report cannot block a write, which is Ryan's ruling), but the proposal frames (B) as "would have to parse `terms`, which puts evaluation back in triggers" and then proposes views that parse `terms`. Say it plainly: **the database holds no refusal that reads `terms`; it may hold version-bound readers of `terms` (views), which are the core's artefacts and are tested with it.** See S2 for the failure mode (a view written for v3 paths returns nothing for v4 rows and reads as "no discrepancies"; the memory rule "prove the check catches drift" applies).

*What `deposit_interest_rate_discrepancies` does and does not prove.* The proposal cites it as the pattern (§2.3). It compares two typed numeric rows (1630–1678); it reads no settings. It is a precedent for "report, don't refuse", not for "a view that reads terms". Worth noting because the hard part — a view over jsonb paths that must track the core's versions — has no precedent in the codebase.

### Q2. What do typed columns give besides (B)?

**Verdict: four real losses, two of which the proposal lists as if they were safe; one genuine gain it does not claim.**

1. **Foreign keys from settings to vocabularies — lost, and this is the one that bites.** Today `deposit_rule_waiver_reach.waiver_class` FKs to `deposit_waiver_classes(state, service, class)` (626–628), disqualifiers FK to their vocabulary (648–649), thresholds FK to `deposit_triggers` (702), cap kinds are a CHECK list (672–675). Under `terms`, `"waivers":[{"class":"family_violence_certifed"}]` is a string. A typo produces a waiver class that reaches nothing; the determination (a record, still FK'd to the vocabulary) is valid, the rule is valid, and the customer gets charged a deposit the law waives. Nothing in the database catches it; the CI load test catches it **only if** the core's loader resolves every vocabulary reference against the database rows of the same state and service — which the proposal does not say. It must (S1). Where the referenced vocabulary is per-state (classes, waiver classes), the check must be keyed by the rule's state and service, as the composite FK is today (623–625).

2. **Records citing parts by FK — lost.** `deposits.trigger_rule_threshold_id → deposit_rule_trigger_thresholds(id)` (1283) is a record citing a law *part* with referential integrity. Under `terms` the deposit cites a path or name inside `inputs`. Acceptable if `inputs` carries a snapshot of the threshold it used (count, window, ratio) so the record is self-describing; say so (S4).

3. **Documentation — lost unless re-homed.** `deposit_rules` carries fifteen `COMMENT ON COLUMN` statements (583–598) that are the only in-database statement of what each setting means, with the Kyle question it is waiting on. jsonb keys cannot carry comments. `rule_term_kinds.description` is one text field per version. Either the registry carries a per-key documentation document, or the core repo owns a schema document per version and the registry links to it (S8). Operators running `\d deposit_rules` will learn nothing about the law.

4. **Review diffs — degraded unless formatted.** A migration becomes an INSERT with a JSON literal. Readable only if every migration uses one canonical layout (sorted keys, one key per line). Note that jsonb normalises on storage: key order is lost, duplicate keys collapse last-wins, and `6` and `6.0` compare equal (from knowledge). A duplicate key in a hand-written literal is therefore *silently* resolved by PostgreSQL, never rejected — a second reason to generate law rows from the core's typed objects rather than hand-write them (S7).

Things the proposal lists in Q2 that are **not** lost:

- **The close floor** — reads citations (`deposits.posted_on`, event dates, `due_on`; 895–902), never settings. Unaffected. Verified by reading `enforce_deposit_rule_history`.
- **The no-overlap exclusion** — on the typed key (571–573). Unaffected. But see S3: the key must stay the *only* place the law's discriminators live, or "one row in force per key" stops meaning "one rule applied".
- **Idempotent seeding** — today's seeds skip on key + `effective_from` match without comparing content (982–986; -13 at tu.sql:24,391–24,396). Unchanged by jsonb; if anything jsonb equality makes a content comparison *easier* (`terms = $1::jsonb` is order-insensitive).
- **"Never edited"** — the guard compares `to_jsonb(NEW) - close_cols` with `to_jsonb(OLD) - close_cols` (883–884); a jsonb column participates in that comparison correctly.

**The gain the proposal should claim:** the parts-in-the-rule's-transaction handshake (`recorded_txid`, `enforce_deposit_rule_part_record` 757–829; -13's `enforce_backbilling_window_term_record` tu.sql:24,274–24,306) exists only because a rule was split over several tables. A document in one row is atomic by construction. That is five triggers and a residual (R5-style "a part added later") that simply disappear.

**Queryability:** `terms->'interest'->>'min_hold_days'` is fine; jsonb extraction functions are IMMUTABLE (verified in the container: `jsonb_extract_path_text`, `jsonb_object_field_text`, `jsonb_typeof`, `jsonb_path_exists` all `provolatile = 'i'`), so expression indexes and generated columns are available if ever needed. Tables are tiny; no GIN needed.

### Q3. Validation: core + CI enough, or database too?

**Verdict: core + CI is the right *primary* validator for migration-written law rows; it is the wrong *only* validator, for three reasons, and it does not cover tariff rows at all.**

*Facts first.* `pg_jsonschema` is **not** in the container image: `pg_available_extensions` lists only `btree_gist`, `pg_trgm`, `pgcrypto`, `plpgsql`, `uuid-ossp` (verified). It is a pgrx extension; whether production hosting can load it depends on the provider (from knowledge: not on RDS, yes on Supabase). So the proposal's dependency objection stands. Its second objection — "the JSON Schema would have to be kept identical to the core's own types" — is weaker than stated: .NET 9's `System.Text.Json.Schema.JsonSchemaExporter` emits a JSON Schema from the C# types (from knowledge), so the schema can be a build artefact, not a hand-kept twin. That matters for the stopgap below.

*Reason 1 — the dangerous failure is not "malformed", it is "well-formed and silently wrong".* `System.Text.Json` **ignores unknown properties by default** (`JsonUnmappedMemberHandling.Skip`; `Disallow` is opt-in since .NET 8 — from knowledge). With the default, `{"interest": {"retroactve": true, ...}}` loads cleanly, `Retroactive` is `false`, and Texas interest runs from day 31 instead of day 1 — exactly the error rules-for-the-core §3.1 warns "reads as right and is the wrong implementation". A CI test that only "loads every row into the core's types" passes. The convention must require: strict deserialisation (unknown members refuse), **no default for an absent key** (absent = the row is malformed, mirroring the no-fallback rule for missing rows), and a **round-trip assertion**: parse → serialise → `jsonb` equal to the stored value. The round-trip is the real schema check and costs nothing. This is blocking (B2).

*Reason 2 — until the core exists there is no validator.* §2.2 gives the definition to the core; the core "isn't being written yet" (audit §6). The survey's 29 shapes and the ZZ fixture would be authored as `terms` with nothing checking them for however long the core takes. "Design permanent, record on change" argues against stop-gaps, but a committed JSON Schema per `(kind, version)` in the repo, checked in CI by a plain validator, is not a stop-gap: it is the permanent artefact the core will later *generate* (reason 1 above). Blocking (B4).

*Reason 3 — the database can and should check structure cheaply, without mirroring types.* The codebase already does this for the bill snapshot: `invoice_calculation_snapshots` checks each section is an object and that named keys exist with the right `jsonb_typeof` (tu.sql:16,318–16,325, 16,439–16,476). The registry can carry `required_sections text[]` and the record trigger can check `terms ?& required_sections` and `jsonb_typeof(terms -> s) = 'object'` for each. That catches "empty terms", "the cap section is missing", "interest is a string", with no extension and no per-version plpgsql. It does not catch a wrong value; that is the core's. (`validate_custom_fields`, tu.sql:956–1119, is a second precedent: tenant-defined definitions validating `metadata` jsonb in plpgsql, with type, options and min/max. It shows a per-version plpgsql validator is feasible; I would not recommend it for law, for the drift reason the proposal gives.)

*Generated columns:* feasible (immutable expressions, verified above). Use sparingly, only for keys the (A) layer or the exclusion constraint needs, because a generated column is a version-bound reader: if v4 renames `cap` to `caps`, `GENERATED AS (terms ? 'cap')` flips to false for every v4 row without an error. Same hazard as the views (S2).

*Where validation effort should go — the inverse of the proposal.* Law rows are written by reviewed migrations by a superuser (578–579; 889–894): the least-risky writer. Tariff rows (`deposit_tariff_waiver_grounds`, `deposit_tariff_trigger_thresholds`) are written by `tally_app` under RLS (1748, 1951: only DELETE/TRUNCATE revoked). If §2.5 moves their content into `terms`, the **least-trusted writer gets the least validation**. See B1.

### Q4. Versioning

**Verdict: the proposal leaves open the one choice the citation guarantee depends on. Resolve it as: a row's `terms` and `terms_version` are immutable for ever; the core keeps a reader (or a pure upgrader chain) for every version that any cited row carries; a version is dropped only when no row carries it.**

Walk the options against the existing guards:

- **In-place upgrade** (`UPDATE ... SET terms = v4, terms_version = 4`). Breaks "never edited" (883–888 refuse any change outside the close columns) and breaks the citation: a deposit decided under v3 now points at a row whose content is a *translation*. If the translation is lossless the record is still true; if it is not — and a representation changes precisely because the old one could not say something — the record's meaning has moved under it. `inputs_fingerprint` on the record (2081) would still say what the core read, but the rule row would no longer be it.
- **Close and supersede** (close the v3 row on date D, insert v4 from D). The close floor refuses a close on or before any citation date (903–908), so a long-held deposit blocks it; and it is a lie — the law did not change on D. Worse, `deposit_rule_citable` (2025–2038) lets later records cite "a rule of the same key in force over the record's dates", so after D the v4 row becomes citable as if it were an amendment. Ryan's B1 decision (which rule a later record cites) would be polluted by representation changes.
- **Keep every version readable** (the only option consistent with the guards). The core carries `v3 → v4 → …` pure upgraders; it reads a v3 row by upgrading in memory; nothing in the database changes. The registry records `superseded_by_version` and `superseded_on`, and the CI load test asserts every stored version has a reader. A version may be *retired* (reader deleted) only when `NOT EXISTS (row at that version)` — a CI check, not a trigger.
- **Uncited rows** (never cited by any record: e.g. a ZZ fixture row, or a row seeded and found wrong before use) may be rewritten in place by a reviewed platform migration that disables the guard for that statement — this is the existing residual R4 (2830–2832) and needs no new rule.

Two further things to decide in the convention, which the proposal does not mention:

- **Additive vs breaking.** If every new optional section (Kansas's `credit: {"on": "jan_1", "cash_election": true}`) bumps the version, then every state's novelty forces a re-read of every row and a new reader. Define: adding an optional key or a new enum value with a stated default-free meaning is the *same* version; removing, renaming or re-typing a key is a new version. The registry then needs only a major number, and "the core keeps a reader per version" stays cheap (S12).
- **The version belongs in the record too.** A deposit's `inputs` should carry `terms_version` (and ideally a hash of the rule's `terms`) so the record says what shape it read, independent of the registry (S4).

### Q5. A middle path: typed columns for stable settings, jsonb for the long tail?

**Verdict: no, with one principled exception. A setting lives in exactly one place; the typed place is reserved for (a) the key, (b) what the (A) layer reads, and (c) what records cite by foreign key.**

Why not "stable across all sources" as the criterion: the survey shows the stable-looking settings are the ones that moved. `interest_min_hold_days` looked stable (Texas 30) until Ohio's 180 days *and* "whether retroactive is implied but not stated" (survey, Ohio -05(B)–(C)) and California's "from the date fully paid" with monthly compounding (G27). `cap_combinator` was typed in round 2 and the survey found a *sum* combinator (Ohio, survey "Borderline"). A split by "stable" is a bet, and when it loses you have a column *and* a terms key for the same concept, with a drift guard to write (which reads `terms`, which is (B)).

The principled exception, which is the audit's own line (§2 rule 2's reason was "typed columns can carry checks"): **what the database must check stays typed.** Today that set is the key (state, service, class, basis), the effective range, the citation stamps. If any (A) guard ever needs a setting — I found none in -15 or -13 — that setting is typed *and absent from terms*. One candidate to watch: `deposit_return_reasons.evidence_kind` (380) is a record-vocabulary attribute the evidence guard reads (2317–2323); it stays typed because it describes records, not law. Its siblings `enabled_by` and `requires_measure` describe law and go.

Counter-risk the proposal should record: a middle path invites "just one more column" per review round — the exact pressure that produced D1–D5. The convention is only as strong as its refusal of that.

### Q6. Sweep candidates and the test

**Verdict: the candidates are right but short, and the test needs two more clauses. Three of the biggest omissions are already in the codebase; one is the proposal's own §2.5.**

Missing candidates, with where they are:

1. **The utility's tariff tables, which §2.5 proposes to convert, are `tally_app`-written** — `deposit_tariff_waiver_grounds` (1698–1829), `deposit_tariff_trigger_thresholds` (1909–2013). They are not a sweep item; they are a hole in the validation story. See B1.
2. **`rate_items.tier_config`** (tu.sql:4,102; `rate_item_versions.tier_config` 15,385): a jsonb terms document for a tariff shape, checked only as `jsonb_typeof(tier_config->'tiers') = 'array'` (4,111), with its contract in a COMMENT (4,137). This *is* the proposed pattern, already landed, with no registry and no version. Fold it in (give it a kind and a version) or state why it is exempt.
3. **`meter_accuracy_thresholds`** (tu.sql:22,246–22,283): the audit calls it the model table, then lists four shapes it cannot hold (asymmetric fast/slow limits, per-flow-rate limits, aggregation rule, boundary inclusivity — audit §3.3). One `threshold_pct` column is exactly a typed-settings table about to grow part tables.
4. **`deposit_interest_rate_law`** (1138–1167): the published number per date is right as a typed row and should stay one. But *how the rate is set* — Oklahoma's holding-period bands with a 50-bp change band (G2), New Mexico's Treasury 5-year, Illinois's rounding to 0.5% (survey), Louisiana's binding 5% (G4) — is terms. The sweep should say the derivation goes to `terms` and the published figure stays a row, otherwise someone will add `band_bp` and `treasury_tenor` columns.
5. **`tenants.minimum_refund_amount`, `below_threshold_action`** and the unclaimed-property constants (audit §3.10; rules-for-the-core §4.3 "#54 rule 8"; survey G6): statutory minimum-refund shapes in three states. Listed nowhere in the proposal's sweep.
6. **The correction rules keyed on `service_type = 'gas'`** (audit §4 step 4, second item) and **program effects and moratoria** (fifth item) are in the audit's list the proposal says it is copying, but its own list (§4) omits them.
7. **`deposit_events.event_type` CHECK list** (2471–2473) encodes law by omission: PG&E's forfeiture of interest on disconnection (G28) needs an `interest_forfeited` event, which is record DDL. Record-state lists "pass" the proposal's test by definition, but some record vocabularies are where the law's *verbs* live. The test should ask of each CHECK list: is a new value here a new *fact kind* (DDL is honest) or a new *rule* (it should be terms)?

The test's two missing clauses:

- "**Would a second reading of the same law need a schema change?**" Kyle's K1–K9 show one statute read two ways (per-deposit vs combined cap, K4; delinquency window, K7; `inactive` as closed, K8). Today each reading is a column value, which is fine; but where the two readings differ in *shape* (K7: "over the twelve bills, twelve months, or the whole hold" is three shapes), the typed table loses. The convention should say that a disputed reading is representable as data without DDL.
- "**Apply it per setting, not per table.**" `regulatory_surcharge_rules` (tu.sql:18,842–18,917) is a tenant table with a Texas-shaped CHECK (`psf_shape_check`, 18,877) *and* a plain cap amount that is right as typed. The sweep's answer for that table is "split: the kind's shape becomes platform law terms, the utility's cap stays its typed row", which a per-table test cannot say.

**Honest accounting of the 29 shapes.** The proposal's headline is that each shape "would be DDL, a migration and a review round" and implies `terms` makes them rows. I went through the survey's G1–G29. About seven need **record-side DDL whatever the law representation**, because they are new *facts*, not new *settings*: G5 (a refund *demand* record), G11 (instalments due with a *bill*, not a day — `deposit_instalments.due_on` is a date), G16 (a customer's cash *election*), G17 (a separate municipal deposit fund and escheat to the operating fund — accounting, not deposits), G20 (a deposit *notice* record with its date), G22 (a disconnection record — already residual R3 waiting on 3K-collections), G28 (an interest-forfeiture event). About four are vocabulary rows plus terms (G1's new trigger kinds; G23's new return reason). The rest — roughly eighteen — are terms-only. So the fair claim is "about two-thirds of the survey's shapes become rows; the rest are new record kinds, which is DDL and should be". Put that table in the proposal; it is still a strong case, and it stops the convention being blamed in two years for DDL it never promised to remove.

### Q7. Contradictions with the codebase

1. **"-13 ... migrates ... the same pattern" (§3) understates how cheap -13 is and misses what it does need.** -13's record guards read only the rule's *key* columns: `enforce_meter_correction_evaluation` reads `b.cause, b.service_type` (tu.sql:25,180); `enforce_period_evidence_with_evaluation` reads `customer_class, cause, state_code, service_type` (25,342–25,354). I grepped the whole -13 trigger region for every settings column (`favourable_duty`, `adverse_straddle`, `enforce_scope`, `delivery_path`, …) and found no reader. No record cites a window-term row by FK (no `term_id` column anywhere after 24,430). So -13 has **no (B)** and its migration is: add `terms`, fold nine setting columns and the window terms into it, drop `backbilling_window_term_kinds`, `backbilling_enforce_conditions` and the three part-record triggers, keep the key, the exclusion, the close floor and the history guard. Two caveats the proposal should state: (a) `backbilling_rules` is landed, so this is an append-only follow-up patch on a live table with 16 rules and 8 terms (counts verified in the container), not an edit of -13; (b) `backbilling_anchor_bases.rests_on_test` and `backbilling_window_term_kinds.takes_quantity` are vocabulary *attributes* that -13's **rule-record** guard reads (`enforce_backbilling_rule_record`, 24,187–24,192) — class (C), goes to the core — while `backbilling_anchor_bases` itself stays because cases cite it (24,727).
2. **"(A) stays unchanged. None of it reads `terms`" (§2.3) is true only after the mixed guards are split.** `enforce_deposit()` (1307–1476) is one function holding tenancy, identity-freeze, basis-insertable, *and* six (B) checks; `enforce_deposit_instalments_complete` holds one (A) and one (B) check; `enforce_deposit_return_due_record` holds the mutex, the citable check, the status check (all (A)) and two (B) checks. The rewrite is a surgical split, not a deletion of functions; the cost estimate "about 30 of 140 mutations go" is plausible but I could not verify the 30 (the mutation list is a Python structure; the round-2 record says 140/140).
3. **"tu.sql has 236 CHECK lists" (§4).** I count 267 lines matching `CHECK … = ANY (ARRAY[` in `sql/tu.sql` (some are the same constraint re-issued by later patches, so distinct constraints are fewer). Same order of magnitude; not material.
4. **§2.5 contradicts §2.2.** §2.2: "Law rows are written only by reviewed platform migrations (`tally_app` cannot write them)." §2.5: tariff rows "follow the same pattern: tenant-owned … typed key plus `terms`." Tenant-owned rows are written by `tally_app` under RLS (1744–1748, 1947–1951). The same pattern cannot have the same validation story. This is B1.
5. **§2.1 reverses audit §2 rule 2 without saying so.** The audit (tu audit §2, rule 2) ruled: "One table per rule family, with typed columns … A generic table would move the Texas assumptions into untyped JSON, where nothing checks them." The proposal keeps one table per family (good — the key differs per family: `basis` vs `cause`) but moves the content to JSON. That is the right reversal, for the reason the survey gives, but a dated correction note belongs on the audit, as the audit itself required for the documents it overturned (§4 step 1). Also: if tables stay per family, `terms_kind` is a constant per table; keep it only as a CHECK (`terms_kind = 'deposit'`) so the registry FK is uniform, or drop it.
6. **§2.3's "every record cites its rule row (whose terms are immutable)"** is only true under the Q4 resolution that forbids in-place upgrades; the proposal lists in-place upgrade as an open option (§6 Q4). Internal tension; resolve by B3.
7. **§2.4 "the pattern `deposit_return_due` already uses"** — true (`inputs jsonb NOT NULL`, `inputs_fingerprint text NOT NULL`, 2080–2081, CHECK 2095–2096). But neither `deposits` nor `deposit_events` has an `inputs` column in the draft; §2.4 adds them. And nothing checks that `inputs_fingerprint` is a hash of `inputs` (the CHECK is `~ '[[:alnum:]]'`). That is an (A) guard the database *can* hold without reading law: `inputs_fingerprint = encode(sha256(convert_to(inputs::text, 'UTF8')), 'hex')` (jsonb text output is canonical — from knowledge). Add it (S5).
8. **The ZZ battery changes meaning.** `battery-15.sql` seeds a fictional state ZZ (55 references; classes `household`/`small_business`/`large_volume`, waiver classes `veteran`/`senior`, lines 481–486). Its purpose per the audit was "a schema check that ZZ's rules *can be stored*". Under `terms`, anything can be stored; the proof that ZZ is *representable* moves to the core's CI (or the interim schema, B4). The proposal should say what the database battery still proves about ZZ: that ZZ's **vocabulary** rows and **records** work through the (A) guards — which is still worth proving.

---

## 2. What the proposal gets wrong or leaves out (the adversarial list)

Ordered by how much Ryan would regret it.

**W1. Tariff terms are app-written and unvalidated (→ B1).** Covered above. Concretely: the audit's rule 5 ("a utility may be stricter than the law, never looser … the utility value is checked against the law row in force") becomes a `terms`-versus-`terms` comparison. Who does it? Not a trigger (reads law content). Not CI (runtime data). Only the core at write time, or a report. The proposal must say which, and if it is "the core at write time" it must say what the database still refuses when the core is bypassed (the whole patch series assumed it could be). My recommendation: tariff rows keep a **typed** shape wherever the law's permission is itself typed (a tariff cap is a number against the law's cap; a tariff threshold is a count+window or a ratio — the two shapes the law's thresholds have), and get `terms` only for the long tail, with the registry's `required_sections` check at the database and the core's validation before write. That is a middle path *for tariff rows only*, justified by the writer, not by stability.

**W2. Silent misread of a key is wrong law applied (→ B2).** Covered under Q3. It is the one failure the typed table could not have: a column either exists or the INSERT fails.

**W3. The discrepancy views go blank, not red (→ S2).** A view over `terms->'return'->>'instruments'` written for v3 returns NULL for a v4 row where the key moved; `NOT (d.instrument = ANY(NULL))` is NULL; the row drops out of the report. Nobody sees a discrepancy because the reader stopped reading. Rule: every discrepancy view declares the versions it reads, the CI test plants one discrepancy per version and asserts the view shows it, and a row at a version no view covers is itself reported (`rule_term_kinds LEFT JOIN view_versions`). Or drop SQL views and have the core run the report — honest about who owns it.

**W4. Key-like discriminators will leak into terms (→ S3).** New York's cap differs for "electric or gas space heating customers" (survey, 16 NYCRR 11.12(h)); Arkansas's by prepaid/postpaid/landlord (4.01.B); Kansas's "small nonresidential ≤ 50 Mcf". Each is a *which rule applies* question. If authored as a branch inside `terms` (`"cap": {"if_heating": …, "else": …}`), the row's `rule_id` no longer pins the terms that applied; the deposit must record which branch, and "no overlap per key" proves nothing about uniqueness of the rule applied. Rule: anything the law uses to *select* a rule is a key column or a class row (classes are already per-state rows, 308–337, so "space_heating" is a class); `terms` describes one rule, never a choice among rules. The core picks the row; it does not pick inside it.

**W5. Absent, null and "unruled" collapse (→ S6).** Today `refund_obligation_vests NULL` under a mandatory return means "unruled, K6" (595–596) and the paired-NULL CHECKs (505–506) make every NULL deliberate. JSON has absent and null. Under strict parsing (B2) absent is an error, so "unruled" needs an explicit value (`"vests": "unruled"`), and `null` should be forbidden outright (a nullable setting is a design smell the typed table had to tolerate). Define it once in the convention.

**W6. What stays typed on records is unstated (→ S4).** §2.4 keeps "amounts the (A) arithmetic reads". But `cap_source` and `cap_tariff_reference` (Ryan's B2 decision, 1253–1260), `cap_binding` ("the customer is entitled to know", rules-for-the-core §2.2), `trigger_observed` and the threshold citation are *operator-facing facts* and today typed with CHECKs. If they go into `inputs`, the operator's "why was this capped" is a jsonb query and the B2 decision has no column. List, per record table, exactly which columns stay (my answer: `cap_amount`, `cap_other_held`, `cap_binding`, `cap_source`, `cap_tariff_reference`, `principal`, `received_at_posting`, `decided_by`, plus `inputs`, `inputs_fingerprint`, `terms_version`).

**W7. No one validates until the core exists (→ B4).** Covered.

**W8. Versioning (→ B3, S12).** Covered.

**W9. Law rows should be generated, not hand-written (→ S7).** A hand-written JSON literal can carry a duplicate key (jsonb keeps the last silently), a misspelt key (W2), or a value outside range. If the core (or, before it exists, a script against the committed schema) *emits* the INSERT from a typed object with sorted keys, the row is valid by construction, the diff is canonical, and the round-trip test is trivially satisfied. The seed blocks in -13 and -15 (tu.sql:24,370–24,427; patch 971–1038) would become generated files.

**W10. The convention's scope statement is missing.** The proposal names deposits and backbilling and gestures at a sweep. It should state the invariant it is adding to `CONTEXT.md` alongside the audit's: "a law row is a typed key, an effective range, a citation, and one immutable versioned `terms` document; the database refuses nothing that reads `terms`; readers of `terms` are the core's and versioned with it." Without the sentence, the next review round will re-litigate per table.

**W11. Operational: who authors `terms` at Tally?** The audit's §5 decision 1 already flagged the running cost of holding law centrally ("someone at Tally has to track amendments to 16 TAC and enter the rows"). Typed columns at least constrained the author to the vocabulary of the table; a document gives the author a blank page. The registry's per-version documentation (S8) and generated rows (S7) are the mitigation; name the role.

---

## 3. What the proposal gets right (so the changes are read in proportion)

- The diagnosis. Two review rounds produced five shape changes (D1–D5), and the survey produced 29 more against a schema that had just absorbed D1–D4; `deposit_rules` is 101 lines of DDL plus five part tables (465–731) for one state's one service. The typed-settings approach does not converge.
- Keeping the key, the range, the citation, the exclusion, the close floor, the stamps, the no-fallback lookup and RLS typed. Those are precisely the things the (A) guards read, and I verified none of them reads a setting.
- Keeping vocabularies as rows where records FK to them (§2.1). Right line; needs the loader cross-check (S1).
- Rejecting `pg_jsonschema` for now (the extension is not in the image; verified).
- Dropping (B) as a *refusal*. The draft's own header (199–201, 2811–2819) already says the database "does NOT decide whether a deposit may be required"; (B) was the residue of the earlier posture that the audit §6 overturned.
- The atomicity gain (Q2) — unclaimed but real.

---

## 4. Answers to §5 (proposed order)

Step 1 (Ryan decides 2.3): decide it as "drop every refusal that reads law content; keep every arithmetic half; the database holds no `terms`-reading refusal and may hold version-declared `terms`-reading reports owned by the core". Step 2 (write the convention once): add B1–B4 and S1–S12 to its contents; it is the audit's "law-table template, written once", and it was never built because each patch re-derived it — that is the real lesson of -13 and -15. Step 3 (sweep): with the per-setting test and the two added clauses. Step 4 (rebuild): -15 rewritten; -13 as an append-only follow-up; `tier_config` folded in.

One sequencing point: the proposal's step 2 cannot be finished without the interim validator (B4), because "the convention" includes "the CI load test", and there is nothing to load into.

---

## 5. Findings by severity

### Blocking (do not adopt until the convention text answers these)

- **B1. §2.5 tariff terms.** Tenant-owned rows are written by `tally_app` at runtime (patch 1744–1748, 1947–1951); §2.2's validation (migration-only writes + CI load) does not reach them; audit rule 5 (stricter-not-looser) becomes a terms-vs-terms check with no stated owner. Decide: typed shapes for tariff values wherever the law's permission is typed, `terms` only for the long tail, database `required_sections` check, core validation before write, and a stated answer to "what if the core is bypassed".
- **B2. Strict parse, no defaults, round-trip.** Require unknown-member refusal, absent-key refusal (no defaults), forbidden `null`, and a CI round-trip (parse → serialise → jsonb-equal). Without this a misspelt key is silently "absent" and the wrong law is applied with a clean build.
- **B3. Versioning.** `terms`/`terms_version` immutable for ever on any row; the core keeps a reader or upgrader for every version carried by a cited row; registry records supersession; a version is retired only when no row carries it (CI check); uncited rows may be repaired under residual R4. Remove "in-place upgrade" from the options.
- **B4. A validator before the core.** A committed JSON Schema per `(kind, version)` in the repo, checked in CI by a plain validator, later generated by the core's types; plus the database `required_sections` structural check in the registry. Otherwise the survey's rows and the ZZ fixture are authored against nothing.

### Should-change

- **S1.** Enumerate every (B) and (C) guard with line numbers before step 1 (table in Q1). Require the CI loader to resolve every vocabulary reference inside `terms` against the vocabulary rows of the rule's state and service.
- **S2.** Discrepancy-view policy: each view declares the versions it reads; CI plants one discrepancy per version and asserts the view shows it; rows at an uncovered version are reported as such. Or: the core runs the reports.
- **S3.** `terms` describes one rule and never selects among rules: every discriminator the law uses to pick a rule is a key column or a per-state class row.
- **S4.** Per record table, the list of columns that stay typed (Q2 item 2, W6); `inputs` carries `terms_version` and a snapshot of any law part the decision used.
- **S5.** Add the (A) check `inputs_fingerprint = encode(sha256(convert_to(inputs::text,'UTF8')),'hex')` on every record table with `inputs`.
- **S6.** Absent / null / unruled semantics defined once (W5).
- **S7.** Law rows are generated from typed objects (core, or a script against the committed schema), sorted keys, one canonical layout; hand-written JSON literals in migrations are refused in review.
- **S8.** Re-home the fifteen `COMMENT ON COLUMN` law explanations (583–598) into per-version documentation the registry links to.
- **S9.** Sweep additions: `rate_items.tier_config`, `meter_accuracy_thresholds`, the rate-derivation half of `deposit_interest_rate_law`, `tenants.minimum_refund_amount`/escheat constants, the `gas`-keyed correction rules, program effects/moratoria; classify the 29 survey shapes into terms-only / vocabulary row / record DDL (my count: ~18 / ~4 / ~7).
- **S10.** Record the reversal of audit §2 rule 2 with a dated note; keep one table per family; `terms_kind` as a per-table CHECK or drop it.
- **S11.** -13: state that it has no (B), that the migration is an append-only follow-up patch on a live table (16 rules / 8 terms in the container), and that `backbilling_window_term_kinds` and `backbilling_enforce_conditions` go while `backbilling_anchor_bases` stays (cases cite it).
- **S12.** Additive vs breaking version policy (optional key = same version; rename/remove/re-type = new version).

### Note

- **N1.** CHECK-list count: 267 matching lines vs the proposal's 236; order of magnitude agrees.
- **N2.** `pg_jsonschema` absent from the image (verified); jsonb extraction functions IMMUTABLE (verified), so generated columns and expression indexes are available but are version-bound readers — same hazard as S2.
- **N3.** jsonb normalisation (key order lost, duplicate keys last-wins, numeric equality) — an argument for S7 and a thing the review checklist should know.
- **N4.** The parts-in-transaction handshake and its residual disappear under a one-row document; claim the gain.
- **N5.** The ZZ battery's "can be stored" proof becomes vacuous under jsonb; say what the database battery still proves (vocabulary rows and records through the (A) guards) and move representability to the core/CI schema.
- **N6.** The mutation count "about 30 of 140" is unverified here; the round-2 record confirms 140 total.
- **N7.** `deposit_interest_rate_discrepancies` is a precedent for "report, don't refuse" over typed rows, not for a view that reads `terms`; the proposal cites it as if it were the latter.
