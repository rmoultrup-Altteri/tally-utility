# Review: rule-terms convention proposal (Opus)

**File reviewed:** `application/rule-terms-convention-proposal-2026-10-06.md`. The md5 is `4b30e3704881764670d4ee34c199bec3`, which **matches** the frozen hash.
**Read:** the proposal in full, and `sql/v5.4.2-15-deposits-law-to-core.sql`: the rule tables (L465–730), the part guards (L757–860), the close floor (L869–917), `enforce_deposit` (L1307–1480), instalments (L1568–1600), return-due and evidence (L2185–2440), and the accrual and return arms of `enforce_deposit_event` (L2533–2770). Also `deposits-rules-for-the-core.md`, the survey's gap list (G1–G29), audit §§3–4, and the `tu.sql` backbilling tables and guards (L23984–25390).
**Database:** read-only queries against `tally-pg`, which is PostgreSQL 16.14 with -15 not applied. Any PostgreSQL behaviour marked **[verified]** was run there. Everything else is reasoning from knowledge and is marked **[knowledge]**.

---

## Overall verdict: adopt with changes

The diagnosis is right. One typed column per setting, plus a CHECK list and a part table per multi-valued setting, does not scale across states and law areas. The two review rounds and the 29 survey gaps show that. Typed key + versioned `terms` + core-owned types is the standard rules-as-data shape. -13 shows the migration is cheap: its record guards read only the rule's **key** columns (cause, service, class, state — `tu.sql` L25180–25190, L25343–25360), not its settings.

The proposal does not survive as written, for three reasons:
1. Its validation argument (§2.2) rests on "law rows are written only by reviewed migrations". §2.5 then extends the pattern to **tenant-written** tariff rows. One of those tariff values, the utility's interest rate, is read by an (A) guard.
2. The (A)/(B) line is drawn by *which column a guard reads*, not by *what the guard protects*. Some (B) guards protect the truth of a citation, not the law's evaluation.
3. "(A) stays unchanged" is not true. Several (A) guards encode law-shaped assumptions that survey gaps break, so jsonb cures only part of the "each shape is DDL" problem.

The changes are listed at the end (§5).

---

## 1. Findings by severity

### Blocking

**X1. Tariff rows break the validation story, and one tariff value is read by an (A) guard.**
- §2.2 justifies DB-light validation with "Law rows are written only by reviewed platform migrations (`tally_app` cannot write them)" plus a CI load test.
- §2.5 puts tariff rows on the same pattern: "the utility's interest rate, tariff waiver grounds, tariff thresholds, tariff caps … typed key plus `terms`".
- Tariff rows are written by the utility through RLS at runtime. -15 says of `deposit_tariff_trigger_thresholds`: "Written by the utility (RLS)" (L1953 comment). CI never sees those rows, so nothing validates them before the core trips over them.
- The utility's interest rate is read by an (A) arithmetic guard: `IF NEW.rate_applied <> v_rate.annual_rate THEN RAISE` (-15 L2669). If the rate moves into `terms`, either that (A) guard reads `terms` (contradicting §2.3, "None of it reads `terms`") or it is dropped.
- Today the database also refuses a tariff ground "scoped to an unknown basis, class or trigger" (-15 header, "Waivers"). In jsonb that reference check is gone at runtime.
- **Required:** either keep tariff rows typed (their shapes are narrower: a rate, a threshold, a ground with a scope), or give tenant-written `terms` a runtime structural validator plus typed facets for anything an (A) guard reads (see X2 and §5). Also state where "utility settings may be stricter than the law, never looser" (audit §4 step 1) is checked for tenant-entered values. Today nothing checks it, and the proposal moves the only place it could live (law row ↔ tariff row) out of reach.

**X2. The CI load test, as described, passes on the most likely authoring errors.**
- **Unknown or misspelled keys.** `System.Text.Json` ignores unknown members by default **[knowledge]**. A misspelled optional key (`"retroactve": true`) loads cleanly, and the setting takes its C# default. That is silently different law.
- **Duplicate keys.** jsonb keeps the **last** duplicate key without error: `'{"a":1,"a":2}'::jsonb` → `{"a": 2}` **[verified]**. A migration that pastes a block twice and edits one copy loses an edit silently. No load test after insert can see it.
- **Missing keys.** A missing non-nullable key deserializes to the default unless members are `required` **[knowledge]**.
- **Required in the convention:**
  - strict deserialization (`JsonUnmappedMemberHandling.Disallow`, `required` members, no default-valued optional settings);
  - a **round-trip equality** check: deserialize, re-serialize, and compare to the stored jsonb with `=`. jsonb equality is semantic, so `6` = `6.0` and key order does not matter **[verified]**. This catches unknown keys and type coercions;
  - `terms` authored as one canonical file per law row and linted *before* SQL generation, which is the only place duplicate keys are visible;
  - the same validator run by the core when it loads a row, refusing that row and failing closed, so a row written outside CI (a superuser repair, residual R4) cannot be evaluated half-parsed.

### Should-change

**S1. Some (B) guards protect the truth of a citation, not the law's evaluation. Keep them without parsing evaluation logic.**
- `cap_source = 'statute'` says "this cap is the cited rule's cap". A deposit claiming a statutory cap under a rule with no cap is a **false provenance statement** in an append-only record. That is the same kind of integrity as "the cited rule is of this key" (A), not evaluation.
- The same holds for `trigger_threshold_source = 'statute'` under a rule that sets no threshold for that trigger.
- Today both are FK- or EXISTS-backed (-15 L1284 FK to `deposit_rule_trigger_thresholds(id)`; L1381 EXISTS on `deposit_rule_cap_parts`). The proposal deletes the part tables but never says what replaces the records' FK `deposits.trigger_rule_threshold_id`. §2.4 puts "the threshold" in `inputs`, so the citation becomes an unchecked copy.
- **Fix:** give the law row a few **typed facets** written from `terms` at insert, under a convention trigger or a CI-checked equality, e.g. `has_statutory_cap boolean`, `statutory_cap_kinds text[]`, `statutory_threshold_triggers text[]`, `return_mandatory_instruments text[]`, `returns_excess_over_cap boolean`. Guards keep reading typed columns, so evaluation stays out of triggers.
- "Parsing `terms` puts evaluation back in triggers" (§2.3) is a false dichotomy. Resolving a reference ("does the rule have a part of kind K?") is not evaluating the law ("does this customer owe a deposit?"). Facets keep even that out of triggers.

**S2. Name the real writer set. It is not "a buggy core".**
- §2.3 frames the loss as "the database no longer refuses a buggy core's record".
- `tally_app` is the single application role (`tu.sql` L11366, default privileges L11388–11391). No separate core role exists, so every app path writes deposits and due rows with the same rights: operator screens ("Edit for accounts", commit `e89b1ba`) and the assistant's staged imports (commit `6641bdf`).
- Under "guard the act, not the label", the exposure is "any `tally_app` writer", not "the core". Either accept that explicitly, or add a `tally_core` role that alone may insert core-decided records. That is (A)-type and reads nothing from `terms`.

**S3. (A) is not law-free. Audit it with the same test the sweep uses.** Several survey gaps need (A) or record-side DDL whatever `terms` can hold:
- **G28** (PG&E: interest forfeited on disconnection for nonpayment) collides with the DIVERGENCE guard `IF b.interest_credited <> b.interest_accrued THEN RAISE` (-15 L2747). PG&E also compounds monthly (G27), so interest *must* be accrued monthly, and forfeiting it then blocks the refund. This needs an `interest_forfeited` event type, but the `event_type` CHECK list is closed (-15 L2471–2473).
- **G27** (monthly compounding): the accrual guard `IF NEW.principal_basis > v_held` (L2704) makes `principal_basis` mean principal only. `compound_annual` is already an allowed method (L531), so this is a latent semantic conflict today.
- **G2** (Oklahoma: the rate depends on how long the deposit was *eventually* held) conflicts with "accrual cites a rate row at that row's rate" (L2669) together with append-only accruals. It needs design, not a `terms` key.
- **G4** (Louisiana: a binding statutory rate) cuts against R-D1, "the utility owns its rate". This is a policy question.
- **G5** (penalty interest after a refused demand), **G13** (disputed bills), **G16** (cash election), **G18** (bankruptcy discharge), **G20** (notice before a deposit), **G22** (return after disconnect, already DG1) and **G23** (return on entering a waiver class) all need **record facts** the schema lacks: a demand, a dispute flag, an election, a notice, a disconnect reason, a waiver determination as evidence. G23 also needs the `evidence_kind` CHECK list (L391) to grow.
- **G17** (Kansas K.S.A. 12-822: a separate account, investment limits, escheat to the operating fund) is treasury and unclaimed-property law, not deposit terms. §1 uses it as a motivating example for `terms`, and `terms` cannot hold it in any useful sense.
- By my reading, about 10–12 of the 29 shapes still need DDL under the proposal (§4 below). The proposal should say so, so the expected payoff is calibrated: jsonb ends DDL for the *parameters and formulas* of law, not for new *facts* or new *money movements*.

**S4. Fix the versioning policy in the convention. Don't leave it open.** Recommended answers to Q4 are in §2. In short:
- no version is ever retired, because append-only records cite rows forever;
- no in-place upgrade;
- a new law is a close plus a successor;
- a new format version for an unchanged law gets no new row, and the core upcasts in code with golden tests per version;
- the registry gets `accepts_new_rows` so old versions can be frozen for new writes.

**S5. Vocabulary references inside `terms` lose their FKs.**
- §2.1 keeps vocabularies "where records reference them by foreign key" and leaves values "used only inside `terms`" to the core's schema.
- Waiver classes, triggers and disqualifiers are *both*: records cite them (determinations, `deposits.trigger_basis`), and `terms` cites them too (reach, thresholds).
- Today the reach row has a composite FK to `deposit_waiver_classes(state_code, service_type, class_code)` (-15 L626–628), so a Texas rule cannot name another state's class. It also has an FK to `deposit_triggers` (L630), and disqualifiers have one to their vocabulary (L648–649).
- In `terms`, a typo such as `family_violence_certifed` simply means "no waiver reaches", which is the customer-adverse failure. The CI test must load the vocabulary tables and check every code in `terms` against them, including the state/service scoping. Or make the convention insert trigger do it: a pure membership lookup, not evaluation.

**S6. The discrepancy report pattern re-creates a second interpreter.**
- Today's `deposit_interest_rate_discrepancies` compares two typed numbers (L1630ff).
- A view of "records that disagree with their rule's terms" (§2.3) must interpret `terms` in SQL, version by version. That is the evaluation in SQL that the convention is trying to avoid, and it will drift from the core.
- **Fix:** views compare typed facets (S1) and records only. Everything that needs `terms` semantics is a **core audit pass** that writes findings rows (or reports) with the core version that judged them.

**S7. Write the contract artifact before the first row, not with the core.**
- The core does not exist. If the C# types "own the definition", the Texas `terms` written in the -15 rewrite have no validator for as long as the core is unwritten.
- That is not a stop-gap question, because the artifact is permanent. Write the per-(kind, version) contract now: either a small C# `Law.Terms` package with the strict loader, or a JSON Schema as the canonical source with the C# types generated from it.
- `pg_jsonschema` is **not available** in this image (`pg_available_extensions` lists no JSON-schema extension **[verified]**). Its availability on managed hosts is uneven **[knowledge]**. Rejecting it is right. A schema file in the repo used by CI is not the same as the extension.

**S8. The key can need DDL too, and the sweep should test it.**
- The survey shows the law varies by **regulated-entity type**:
  - K.S.A. 12-822 binds municipal utilities specifically;
  - Kansas cooperatives with turn-around billing get different caps (survey, Kansas §III.D);
  - Arkansas caps vary by prepaid/postpaid and landlord status;
  - the survey's own open item, "Municipal exclusion statutes not fetched".
- For a product selling to *municipal* gas systems, "does this body of law bind this utility at all?" is a key dimension. The `(state, service, class, basis)` key cannot express it.
- If such a selector goes into `terms`, the `EXCLUDE` constraint can no longer stop two rows with the same typed key from overlapping. Settle the key's dimensions (entity type, place below state per audit §4 step 2) before rewriting -15. Changing a key is a meaning-changing migration; adding a `terms` key is not.
- I also could not confirm that 16 TAC §7.45 binds Texas *municipal* gas systems at all. That is worth a Kyle question before Texas launch rows are re-seeded.

**S9. Make the seed's idempotence honest.**
- Seeds skip a row when `(key, effective_from)` exists (-15 L982–986 `IF EXISTS … CONTINUE`).
- With all of a rule's content in one `terms` value, an edited seed that is re-run is silently skipped, and the database keeps the old law.
- The convention seed should `RAISE` when the row exists with different `terms` (jsonb `=` is a sound comparison **[verified]**).

### Notes

- **N1. Close floor, citation rule, no-overlap and immutability all carry over.**
  - The close floor reads only citing records (`posted_on`, `period_end`/`effective_on`, `due_on`; -15 L889–896), never settings.
  - `deposit_rule_citable` reads only key and dates (L2025–2036).
  - The history guard compares `to_jsonb(NEW) - close_cols` with OLD (L884), which works unchanged with a jsonb column and ignores key order.
  - The "parts only in the rule's transaction" guards (L766, `tu.sql` L24282) become unnecessary, because `terms` is atomic with the row. That is a real simplification.
- **N2.** -15 already contains a guard that is plain evaluation: `observed ≥ threshold` (L1433). It goes regardless.
- **N3. Fractions.** `deposit_rule_instalments.fraction numeric(5,4)` with "sum = 1" (L849) cannot hold thirds: 0.3333 × 3 ≠ 1. Illinois' ⅓ / ⅔ (G11) needs a rational form in `terms`, such as `{"num":1,"den":3}`. Use rationals for all statutory fractions; Texas already stores the cap as a divisor.
- **N4. Generated columns.** If facets are to be *generated* from `terms`: `->>` and casts to boolean, int and numeric are immutable, but `date_in` is **stable** (`provolatile = 's'` **[verified]**), so a date facet cannot be a generated column. Arrays need an IMMUTABLE wrapper function. A BEFORE INSERT trigger that writes the facets is simpler, and law rows are migration-written, so it costs nothing.
- **N5. Queryability.** jsonb with a GIN `jsonb_path_ops` index answers "which rules credit annually" **[knowledge]**, but each query must know each version's paths. Operator and UI display of "the resolved rule and its citation" (audit §3.9) needs a renderer per version. Have the core expose it, so the UI isn't a third interpreter.
- **N6.** "236 CHECK lists": the live DB (tu.sql state, -15 not applied) has **243** CHECK constraints containing `ANY (ARRAY[` **[verified]**. Close enough. The claim's point, that most are record states, stands.
- **N7.** "-13 migrates `backbilling_window_term_kinds`": that table is a vocabulary referenced only by window-term part rows (`tu.sql` L24151), not by records. Under §2.1 it is *dropped* into the core's schema, not migrated. Say which. Also, its `description` text is the only human-readable statement of what each kind means; keep it somewhere.
- **N8.** "About 30 of its 140 mutations": `mutations-15.py` has 140 entries **[verified count]**. I did not verify the 30.
- **N9.** `terms_kind` on a per-area table is redundant (`deposit_rules` is always `deposit`). Use a CHECK pinning it, or drop it and key the registry by table.

---

## 2. Answers to §6

### Q1. Is the A/B split right?
**Mostly. Three misclassifications.**
1. **Citation provenance is (A), not (B).** `cap_source='statute'` and `trigger_threshold_source='statute'` are statements about the cited row's content (S1). Keep them by typed facets (or by part keys inside `terms`, checked by a membership lookup). Either way, no evaluation.
2. **Tariff ↔ law bounds are not "record matches rule".** They guard tenant-entered values, not core output (X1). The proposal doesn't classify them.
3. **"Return mandatory for this instrument" on a due row (L2210–2214)** is borderline. Money does not move on a due row (`principal_returned` and `refunded` don't require one; `return_due_id` is optional, L2465), but a false row appears in the operators' "refunds owed" list. A facet keeps it for free.

Genuinely (B), and fine to drop:
- observed ≥ threshold (L1433);
- instalment count = schedule (L1581);
- history reason's measure matches the rule (L2338);
- reason enabled by the rule (L2326; a facet could keep this cheaply);
- `cap_other_held` exactly under combined scope (L1383).

Separately, (A) itself encodes law (S3).

### Q2. What does jsonb lose besides (B)?
- **FKs from settings to vocabularies:** lost, including state/service-scoped composite FKs (S5).
- **The record → part FK** (`deposits.trigger_rule_threshold_id`): lost, and the proposal doesn't say what replaces it (S1).
- **Range and shape CHECKs** (`reduce_fraction` in (0,1), "exactly the figure it needs" equivalences, L632–635, L672–675): these move to the validator, so they are only as good as X2.
- **Queryability:** kept but version-aware (N5).
- **Close floor:** unaffected (N1).
- **Idempotent seeding:** weaker unless S9.
- **No-overlap exclusion:** unaffected *for the typed key*, but any applicability selector placed in `terms` escapes it (S8).
- **Review diffs:** worse by default. A superseding row restates the whole document in a SQL string literal. Author `terms` as files, generate migrations, and CI-diff old vs new terms per key.
- **Gained:** atomicity of a rule's content (N1), and no DDL per parameter shape.

### Q3. Validation
Core-owned plus a CI load test is enough **for migration-written law rows, provided** it is strict and round-trips (X2) and the core re-validates on load. It is **not enough for tenant-written tariff rows** (X1): those need runtime validation, either an insert trigger running a structural check of required keys and `jsonb_typeof`, or keeping tariff rows typed.
- `pg_jsonschema`: not available here **[verified]**, so rejecting it is right.
- A per-version CHECK function: workable only as an IMMUTABLE function over `terms` alone (a CHECK must not read the registry table) **[knowledge]**. A BEFORE INSERT trigger is the cleaner home.
- Generated columns: only for facets, with the date caveat (N4).

### Q4. Versioning
- **A version is never dropped** while any row cites it, which is forever, because records are append-only and replay and disputes need the original terms. The core keeps a reader for every registered version. Add `accepts_new_rows boolean` (or `superseded_by_version`) to the registry to stop new rows on old versions.
- **No in-place upgrade.** It breaks "never edited", and the close floor and `EXCLUDE` make "close and re-add the same law in v4" produce a row whose dates misstate when the law changed.
- **A new law** is close + successor (as today) and may use the newest version.
- **A new format for unchanged law** gets no new row. The core **upcasts** vN→vN+1 in code (a pure function), with per-version golden scenarios proving the upcast keeps meaning, so evaluation logic targets one shape.
- **A version's semantics are frozen.** A changed *meaning* of an existing key is a new version, never a reinterpretation. Records already carry `decided_by` (core version); together with `terms_version` that gives replay.

### Q5. A middle path?
**Yes. Use this test rather than "stable across sources":** a setting is a typed column iff a database guard, FK or exclusion needs it. That means:
- the key, including entity type and place (S8);
- the dates and citation;
- the facets that (A) and provenance guards read (S1).

Everything else goes in `terms`. Facets are derived from `terms` at insert, so the two can't drift. Stability across the survey is a poor criterion: Texas looked stable until the survey.

### Q6. Sweep test and candidates
- **The test** ("would a second state or utility need a schema change?") is right but should add "**or a second regulated-entity type**" (municipal / IOU / co-op), and should be applied to **record shapes** too (event types, evidence kinds, record facts), not only law rows (S3).
- **Missing candidates:**
  - the instrument list (CHECKs on rules and deposits; L520, L547);
  - `deposit_events.event_type` (G5, G28);
  - `deposit_return_reasons.evidence_kind` and `qualifying_statuses` (G22, G23);
  - `deposits.cap_basis_kind` (L1248; G9 — §2.4 implies it goes to `inputs`, so say so);
  - meter testing -12 (audit §3.3: accuracy thresholds, test kinds, "last test" selector, test fee);
  - the customer-class closed list of 7 (audit §3.8);
  - gas measurement bases, the PGA pool, the correction rate mode (§3.8);
  - disconnection, notice and moratorium rules (§3.5; `program_types` is only one symptom);
  - payment terms and notice languages (§3.11);
  - franchise-fee ceiling (§3.7);
  - deposit escheat (G17), which crosses deposits and unclaimed property.

### Q7. Contradictions with the codebase
1. "(A) … None of it reads `terms`" vs §2.5 moving the utility's interest rate into `terms`: the accrual guard reads `annual_rate` (-15 L2669). (X1)
2. "Values used only inside `terms` are defined by the core's schema" vs waiver classes, triggers and disqualifiers, which are FK-referenced from the parts today (L626–631, L702, L648) and also cited by records. (S5)
3. "§3: the citation rule … the close floor … carry over": **confirmed**. Neither reads settings (N1).
4. "`deposit_return_due` already uses `inputs jsonb` + `inputs_fingerprint`": **confirmed** (L2080–2081, L2096).
5. §1's Kansas 12-822 example is mostly not a `terms` shape (S3, G17).
6. -15's own header says "A second state is rows, not DDL (the battery's group Z)". The survey refutes that, and the proposal is right to say so.
7. "236 CHECK lists": 243 by my count (N6).
8. -13's guards read only key columns, so the -13 migration really is cheap. This supports §3.

---

## 3. What I'd adopt (the changes, consolidated)

1. **Tariff rows (X1).** Keep them typed, or give tenant-written `terms` runtime validation. In either case, any value an (A) guard reads stays typed (the utility rate). State where "never looser than the law" is enforced.
2. **Strict validation (X2).** Unknown members disallowed, `required` members, a round-trip jsonb `=` check in CI, a lint on the `terms` source files, and core re-validation on load that fails closed per row.
3. **Typed facets on law rows (S1).** Derived from `terms` at insert, read by the provenance guards (statutory cap, statutory threshold, mandatory-return instruments, excess return). Replace the lost part FK with a facet check.
4. **Writer role (S2).** Name the writer set, and decide on a `tally_core` role.
5. **Audit (A) and the record shapes (S3).** List the survey gaps that still need DDL. Plan `interest_forfeited` and the record facts.
6. **Versioning (S4).** Never retire, no in-place upgrade, upcasters in code, frozen semantics, `accepts_new_rows`.
7. **Vocabulary references in `terms` (S5).** Checked against the vocabulary tables, with state/service scope, at insert or in CI.
8. **Discrepancy reports (S6).** Views over facets and records; anything needing `terms` semantics is a core audit pass.
9. **Contract first (S7).** The contract artifact exists before the first `terms` row.
10. **Key (S8).** Settle the key's dimensions (entity type, place) before the -15 rewrite. Ask Kyle whether §7.45 binds Texas municipal systems.
11. **Seeds (S9).** Raise on a `terms` mismatch.
12. **Fractions (N3).** Rationals.

---

## 4. Survey gaps under the proposal (my reading)

| Gap | Holdable in `terms` alone? | What else it needs |
|---|---|---|
| G1 trigger events | Yes (trigger vocabulary rows + `terms`) | Record facts for late payments and final notices may already exist (invoices) |
| G2 rate by holding period | **No** | Rate-row / accrual (A) redesign |
| G3, G6, G7, G8, G10, G12, G24, G25, G29 | Yes | — |
| G4 binding statutory rate | Policy | R-D1 exception |
| G5 penalty after demand | **No** | Demand record, new event type |
| G9 cap bases | Yes | `deposits.cap_basis_kind` CHECK moves to `inputs` |
| G11 instalments | Yes, with rationals | — |
| G13 disputed bills | **No** | Dispute flag on invoices |
| G14 interest stop events | Partly | Service-termination fact |
| G15 guarantor cap | Partly | Guarantor amount on the record |
| G16 calendar credit, cash election | Partly | Election record |
| G17 separate account, escheat | **No** | Treasury and unclaimed-property area |
| G18 bankruptcy | **No** | Discharge record |
| G19 periodic recalculation | Yes | New deposit or `principal_returned` (existing) |
| G20 deadline and notice | **No** | Notice record |
| G21 cure by payment arrangement | Yes | Payment-arrangement records |
| G22 return after disconnect | **No** | Disconnect reason (DG1), evidence kind |
| G23 return on waiver | **No** | Evidence-kind CHECK, an evidence FK |
| G26 waiver's own disqualifier | Yes | — |
| G27 monthly compounding | Partly | `principal_basis` semantics (L2704) |
| G28 forfeiture | **No** | `interest_forfeited` event, DIVERGENCE guard (L2747) |
