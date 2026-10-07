# Rule-terms v2, step 2: source inventory

**Date:** 2026-10-07.
**Purpose:** the spec for step 2 of `rule-terms-convention-v2-2026-10-06.md` §12, the convention infrastructure written once. It lists what the two first consumers need from that infrastructure:
- the **-13 migration** (backbilling; in `tu.sql`);
- the **-15 rewrite** (deposits; never mirrored).

The step-2 patch (v5.4.2-17) is drafted against this list, and reviewers check the draft against it.

**Sources:**
- `sql/v5.4.2-13-backbilling-caps.sql`;
- `sql/v5.4.2-15-deposits-law-to-core.sql`;
- the reviews in `application/rule-terms-review/` (Opus, Fable, Codex, research);
- `places-source-inventory-2026-10-06.md` finding 1 (Texas city-owned gas systems are outside §7.45);
- `tu.sql` as of -16.

Two read-only passes did the extraction; their full notes, with line numbers, were kept in the session scratchpad. The citations below use patch line numbers (`13:`, `15:`).

**Method** (memory `source-inventory-first-triage-by-rule`): each requirement names its consumer and its line evidence. Each is classed as **Step 2** (built once, now), **Area** (built by that area in step 4 on the step-2 template), or **Out** (recorded, not built). Section 3 settles the open design points by standing rules. Section 4 holds the few items for Ryan, each with the default I'll take.

---

## 1. What the consumers have today, in one paragraph each

**-13 (backbilling).**
- **The law:** `backbilling_rules`, platform-held, has 11 content columns plus a child table `backbilling_rule_window_terms` (13:674–807).
- **The seed:** 16 Texas rows, 8 window terms and 5 vocabularies.
- **Guards:** none reads rule content for a record. Every content guard is a document-shape check (13:705–738, 783–798, 824–825, 926–927). Record guards read only key columns (13:1817–1827, 1979–1995).
- **Citations:** evaluations and period evidence cite `rule_id` by plain foreign key. No "in force on date" check exists (residual R3).
- **Cheap to migrate, except:** the history trigger refuses every UPDATE but a close (13:866–871), and the backfill needs one.

**-15 (deposits).**
- **The law:** `deposit_rules`, with 17 content columns and five child tables (15:465–731). The seed is §7.45 for Texas gas.
- **The utility's own rows:**
  - only waiver grounds and trigger thresholds exist, and both hang off a law row;
  - a tariff cap is free text on the deposit;
  - "stricter, never looser" is enforced nowhere (15:1373, 1404–1432, 1967–1973).
- **Guards:** 37 read rule content. Of these, 9 are reference integrity that needs typed facets, 1 is legal evaluation, and the rest are record integrity.
- **Writers:** core-only records (return-due rows, evidence, instalments, accruals) are all insertable by `tally_app`.
- **The gap:** every deposit must cite a `deposit_rules` row (15:1350), and the only Texas rows are §7.45's. So a city-owned system, our first customer, would have to cite law that doesn't bind it.

---

## 2. The requirements

### 2.1 The registry and the document validator

| # | Requirement | Consumer, evidence | Class |
|---|---|---|---|
| V1 | `rule_term_schemas (kind, version, json_schema, schema_hash, introduced_on, description, accepts_new_rows)`: platform-held and never edited; a version is never deleted | Both; v2 §5, §11; Opus S4 (`accepts_new_rows`) | Step 2 |
| V2 | **Kinds:** `backbilling` (law); `deposit` (law); the utility's deposit tariff (one kind or a sibling, settled in -15's rewrite) | -13, -15 | Kind rows: Area. Pinning a kind per table (CHECK + FK): Step 2 pattern |
| V3 | **The checks the validator runs:**<br>• closed objects (unknown keys refused);<br>• required keys, and no nulls anywhere;<br>• types: string, integer, exact decimal, boolean, array, object;<br>• enumerations; numeric ranges, inclusive and exclusive;<br>• array size, and uniqueness of items;<br>• **strategy unions**: the `strategy` value selects which parameter set is allowed;<br>• stable component ids, unique within the document;<br>• rationals `{num, den}` | **-13:** five content CHECK lists (13:711–738); the window-term shapes (13:789–798); the two uniqueness rules (13:783–784).<br>**-15:** CHECK lists and paired-NULL groups (15:512–566); child-table CHECKs (15:622–726); part rules (15:773–809); the at-commit schedule rules (15:841–853).<br>**Fractions:** Opus N3 (Illinois ⅓/⅔) | Step 2 |
| V4 | **Rules that depend on a vocabulary attribute**, expressed as strategy unions in the schema rather than as table lookups. The validator is IMMUTABLE and can't read tables.<br>• -13's "test outcomes present iff the anchor rests on a test" (13:824–825) becomes `anchor: {strategy: test_date, qualifying_outcomes: [...]}` or `{strategy: discovery_date}`.<br>• "A window term takes a quantity" (13:926–927) becomes a per-kind parameter set | -13 | Step 2 (union support); the schemas are Area |
| V5 | **A strategy reference names its version:** `{"strategy": "...", "version": n, ...}`. v2 §4 freezes strategy versions independently of `terms_version`, so a row must say which version it was written for, or the core can't reproduce an old decision | Both; v2 §4, §11 | Step 2 (format rule) |
| V6 | **Per-section citations inside `terms`.** -13's 16 long `source_note`s cite several §7.45 clauses each; -15's rows do the same | Both; v2 §3 | Step 2 (format rule) |
| V7 | **"Unknown" distinct from "absent":** an explicit `unruled` value is allowed where the schema says so; no setting defaults silently | -15 (`refund_obligation_vests` NULL = unruled, K6); -13 (`delivery_path` `unruled`) | Step 2 (format rule) |
| V8 | **"The law leaves this to the utility"** as an explicit document, distinct from "no law known":<br>• Texas LGC §552.0025(c) (municipal deposits);<br>• the §7.45 exclusion for city-owned systems (places finding 1) | -15 §6; -13 (city backbilling likewise) | Step 2 (format rule: every kind's schema allows a cited `delegated_to_utility` document). The rows themselves are Area |
| V9 | **The registry refuses a schema that uses a keyword the validator does not enforce.** Otherwise a schema can claim a check that never runs (memory `checks-narrower-than-their-claim`) | Both | Step 2 |
| V10 | **A cross-check against a reference validator:** golden valid and invalid documents are run through both the database validator and a standard JSON Schema (2020-12) validator, and must agree | Both; memory `checks-narrower-than-their-claim` | Step 2 (CI) |

### 2.2 Typed facets and vocabulary references

| # | Requirement | Consumer, evidence | Class |
|---|---|---|---|
| F1 | **The facet pattern:**<br>• the registry declares, per (kind, version), each facet's name, type and JSON paths;<br>• the insert trigger derives them;<br>• no one sets them directly;<br>• the history guard's whole-row comparison covers them | Both; v2 §7 | Step 2 |
| F2 | **Facet types:** `text`, `text[]`, `int`, `boolean` | -15's facets below | Step 2 |
| F3 | **Facets a vocabulary checks**, scoped by the row's state and service: the registry names the vocabulary table, its code column and its scope columns; the insert trigger checks each element. This replaces the lost composite foreign keys | **-15:** waiver classes (15:626–628), triggers (15:630), disqualifiers (15:648), the tariff scope arrays (15:1770–1780) | Step 2 (mechanism) |
| F4 | **Facets checked against the row's own key:** for example, triggers only on a trigger basis (15:773–809, `deposit_bases.requires_trigger`) | -15 | Step 2 (hook); the predicate is Area |
| F5 | **-15's facets:**<br>• `cap_part_ids text[]`;<br>• `cap_scope text`;<br>• `trigger_codes text[]`;<br>• `instalment_count int`;<br>• `return_mandatory_instruments text[]`;<br>• `return_reason_codes text[]` (replaces `enabled_by` and `requires_measure`);<br>• `waiver_classes text[]`, including the tariff-permission class | 15:1373–1387, 1402–1416, 1580–1586, 2210–2223, 2325–2342, 1866 | Area (declared on the step-2 pattern) |
| F6 | **-13's facets:** none. No record guard reads rule content | 13 §2 | — |
| F7 | **A record cites a component** (for example `(rule_id, 'p1')`), checked against a facet array. This replaces the lost foreign key `deposits.trigger_rule_threshold_id` (15:1282–1284) | -15 | Step 2 (pattern); the use is Area |

### 2.3 The law-table template

| # | Requirement | Consumer, evidence | Class |
|---|---|---|---|
| T1 | **Standard envelope:**<br>• the typed key;<br>• `effective_from` and `effective_to`, with the no-overlap exclusion;<br>• `source_note`;<br>• the stamps;<br>• `terms_kind`, `terms_version` and `terms`;<br>• the facets;<br>• the never-edited history guard, whose only UPDATE is a close;<br>• the close floor over citing records | Both (13:674–906; 15:465–919) | Step 2 (template plus shared functions) |
| T2 | **Standard applicability key columns from -16:** owner type, and commission jurisdiction where the law needs it. These join each area's own key (class, cause, basis). Law keys on the system (-16, Ryan 2026-10-07) | Both; -16 R1 (`tu.sql` 27213); v2 §9 | Step 2 (columns, vocabulary FKs, how "any" is spelled inside an exclusion); the values are Area |
| T3 | **The lookup:** premise or tenant → profile (`utility_service_profile_as_of`) → the law row in force. It refuses when nothing answers and never falls back | -15 (15:1356–1366 has no owner type); -13 (R3: no date-selection check) | Step 2 (shared resolution helper); each area's lookup is Area |
| T4 | **One serialisation protocol between a close and a new citation**, for law and tariff rows alike: citers take a shared lock, a close takes it exclusive, and a close re-reads its floor | -15 R5 (15:2834–2836); -13 R12 (13:2545–2548); -16's `place_lock_key` pattern | Step 2 |
| T5 | **Strict, idempotent seeding:** the same key with different `terms` raises; the same `terms` is a no-op | **-13:** 13:1028–1032 skips with no compare. **-15:** 15:982–986 likewise. Opus S9 | Step 2 (loader plus a seed helper) |
| T6 | **Format adoption:** once per row, write `terms`, the kind, the version and the facets onto an existing pre-convention row, under a check that the document equals what the old typed columns said. The row id and dates are kept, and the law doesn't change | **-13:** 16 rows; the history trigger refuses (13:866–871). v2 §11: "format changes are not law changes" | Step 2 (the sanctioned path); its use is -13's migration |
| T7 | **Correction lineage** for a row wrong from its first day | -15 R4 (15:2830–2832); -13 R7 (13:2508–2513) | **Out** of step 2. v2 §11 says it is "to be designed"; no consumer needs it to land. Recorded as a residual |

### 2.4 The utility's own rows (tariff rows)

| # | Requirement | Consumer, evidence | Class |
|---|---|---|---|
| U1 | **Tariff-row envelope:**<br>• tenant-owned under RLS, written by `tally_app`;<br>• the same `terms` validation on every write (v2 §3);<br>• key: tenant, state, service, **system kind**, plus the area's key;<br>• a tariff citation (ordinance or tariff sheet, K11);<br>• a close floor and the T4 lock | -15 (15:1698–2013 are the partial precedent); -13 (`tenants.backbilling_adverse_limit_months` could become one) | Step 2 (template) |
| U2 | **Duplicate keys in tenant-written JSON:** `jsonb` keeps the last duplicate silently. Tenant `terms` therefore enter as text through a parser that refuses duplicates | -15 tariff writes; v2 §5; Opus X2 | Step 2 |
| U3 | **"Stricter, never looser":** when a tariff row is written, a per-kind comparator checks its facets against the law row in force over its whole range. Against a `delegated_to_utility` law row (V8) there is nothing to compare. A law change after the tariff produces an **audit finding**, not a refusal: the law wins, and the core applies it | -15 §2: enforced nowhere today | Step 2 (hook and finding); the comparators are Area |
| U4 | **Records cite the law row in force (always) plus the tariff row they used (optional).** For a city-owned system the law row is the `delegated_to_utility` row, so the tariff governs. For an investor-owned utility the law governs and the tariff adds to it. This keeps -15's required `rule_id`, and no citation has to point at more than one table | -15 §6 | Step 2 (pattern); the use is Area |
| U5 | **The city's own customer classes:** `deposit_customer_classes` holds only the law's classes (15:308–337), and LGC §552.0025(c) allows varying deposits | -15 §6 | Area (-15). Tenant-owned class vocabularies follow F3 with tenant scope |

### 2.5 Published values

| # | Requirement | Consumer, evidence | Class |
|---|---|---|---|
| P1 | **`rule_parameter_values`:**<br>• columns: name, **a typed scope** (state code, NULL = national; service type, NULL = all; class, NULL = all), `effective_from` and `effective_to` with no overlap per (name, scope), value as an exact numeric, a unit from a vocabulary, a citation per value;<br>• never edited; a close floor once records cite it | -15: `deposit_interest_rate_law` (15:1138–1203) is keyed by state, service and class, which the v2 §6 column list leaves out | Step 2 |
| P2 | **The first name:** the Texas annual deposit interest rate (Utilities Code §183.003), unit an annual fraction. Whether chapter 183 binds a city is still open (K10) | -15 | Area (-15) |
| P3 | **`terms` refers to a published value by name** (for example `{"rate": {"source": "published", "name": "..."}}`); the core reads the value in force on the date | -15; v2 §6 | Step 2 (format rule) |
| P4 | **Nothing from -13.** Its 6- and 3-month windows are statute, so they live in `terms` | -13 §8 | — |

### 2.6 `tally_core` and the audit-findings table

| # | Requirement | Consumer, evidence | Class |
|---|---|---|---|
| C1 | **A `tally_core` role:**<br>• NOLOGIN, with a login role granted to it;<br>• no TEMP, no CREATE (memory `depth-fence-needs-no-temp`);<br>• not a member of `tally_app`, nor `tally_app` of it;<br>• works under the existing tenant RLS policies, which name no role (`tu.sql` 10782ff), through the same tenant session settings | Both; v2 §8; Opus S2 | Step 2 |
| C2 | **A grant pattern for core-only tables:** INSERT for `tally_core` alone; SELECT for both. Moving existing tables is the consumer's job:<br>• **-13:** `meter_correction_evaluations` and `_period_evidence` (13:1716, 1787, 1968). `tally_core` then needs INSERT on case events (written by the evaluation's AFTER trigger), the column-level UPDATE privilege its `FOR SHARE` lock needs (13:1808–1811), and a meaning for `evaluated_by`.<br>• **-15:** return-due rows and their evidence, instalments, accrual events, and the deposit's decision columns | Both | Step 2 (role, pattern, `evaluated_by` meaning); the moves are Area |
| C3 | **`rule_audit_findings`:**<br>• tenant-owned under RLS; written only by `tally_core`; append-only;<br>• columns: finding kind (vocabulary), subject record, the law or tariff row and its terms version, core release, coverage (what was examined, over which span), the expected decision and its due date for a **missed decision**, and when it was found;<br>• dispositions as separate append-only rows;<br>• must pass `assert_tenant_isolation_invariants()` (AC-32) | **-15:** the discrepancy view (15:1630–1683) and R6/R10 (15:2838–2864). **-13:** nothing today, but the core's audits need it. Also U3's law-after-tariff finding | Step 2 |
| C4 | **The inputs fingerprint, defined once:**<br>• `inputs jsonb`, an inputs schema reference, and `calculated_by` (core release);<br>• **the database computes the fingerprint** (`sha256` of the stored `jsonb` text) in a trigger rather than accepting one from the writer (memory `app-written-logs-are-not-guards`);<br>• exact numbers are sent canonically, so `1.0` and `1` cannot hash differently | **-13:** `inputs`, `inputs_fingerprint` and `calculated_by` are only checked for being non-blank (13:1743–1776). **-15:** the same (15:2080–2097) | Step 2 (columns and trigger); retrofitting -13's evaluations is Area (needs a default because they're append-only) |

### 2.7 Files, loader and CI

| # | Requirement | Consumer, evidence | Class |
|---|---|---|---|
| L1 | **Law files** (YAML, OpenFisca conventions):<br>• one file per (kind, state, service, owner type), holding dated rows;<br>• a citation per section;<br>• golden scenarios beside each row | **-13:** the 16 rows plus window terms; per-section citations from the `source_note`s. **-15:** 8 rows plus the reach, cap, threshold and disqualifier parts | Step 2 (format); the files themselves are Area |
| L2 | **A strict loader:**<br>• every scalar is read as a string, and types come from the schema, so YAML's `yes`/`no`, dates and floats can't change meaning;<br>• duplicate keys, anchors, aliases and tags are refused;<br>• decimals are exact.<br>It emits a reviewed SQL migration using the T5 seed helper | Both; Opus X2; v2 §5 | Step 2 |
| L3 | **CI:**<br>• builds `tu.sql` in PostgreSQL 16;<br>• every stored row round-trips (file → `jsonb` → file, compared as `jsonb`);<br>• every file loads;<br>• validator agreement (V10);<br>• golden scenarios are **schema-checked** now and **run** once the core exists;<br>• the batteries run | Both; v2 §5. The repo has no CI today (no `.github/`) | Step 2 |
| L4 | **A fictional-state fixture (ZZ):** law rows of every kind using strategies Texas doesn't, a municipal row under a law that binds it, and a `delegated_to_utility` row. It builds on -16's ZZ places | Both; Opus; -15's group Z; -16's battery | Step 2 |

---

## 3. Settled by standing rules (no question needed)

1. **The validator is one IMMUTABLE interpreter**, `rule_terms_check(schema jsonb, doc jsonb)`, called by the insert trigger with the registry's schema. It is not a generated function per version.
   - It is reviewed once rather than once per version. The registry is never edited, so the result for a given row cannot change.
   - v2 §5's text says "generated, per-version". Its intent is a check on every write that can't drift, and the interpreter keeps that. V9 and V10 prove the interpreter enforces what each schema claims.
   - (KISS; `checks-narrower-than-their-claim`.)
2. **Strategy-like codes go in the schema, not in vocabulary tables.** The test is: a record cites it → a vocabulary table with a foreign key; it appears only inside `terms` → the schema.
   - So `backbilling_window_term_kinds` and `backbilling_enforce_conditions` move into the schema, with their descriptions kept as schema `description` text. This resolves the -13 pass's flagged conflict: v2 §7's facet check is for codes that records also cite.
   - `backbilling_anchor_bases` stays a table: cases and evaluations cite it (13:1297, 1481–1490).
3. **`rule_parameter_values` gets typed scope columns** (P1). §9 says every discriminator is a key column; burying the scope in a name would hide a key in a string.
4. **The law is always cited, and the tariff optionally** (U4). This avoids citations that point at one of several tables and keeps -15's required `rule_id`. The city case works through V8's `delegated_to_utility` row. ("Unknown is not absent"; places finding 1.)
5. **A law change that makes an existing tariff looser is an audit finding, not a refusal** (U3). The law row records what the law says; refusing it would make the database misstate the law to protect a tariff. (`utility-owns-regulated-values`.)
6. **The fingerprint is computed by the database** (C4). (`app-written-logs-are-not-guards`.)
7. **Correction lineage stays out of step 2** (T7). No consumer needs it to land. It is recorded as a residual with the v2 §11 sketch.
8. **Kinds, schemas and facet declarations for backbilling and deposits are area work.** Step 2 ships the machinery and the ZZ fixture's kinds only; -13 and -15 register their own kinds in step 4.
   - Settling a shape before its rewrite would mean reviewing it twice (`source-inventory-first-triage-by-rule`).

---

## 4. For Ryan: defaults I'll take unless you object

None of these is a conflict between standing rules. Each is a choice with a cost or a lasting effect, so it is stated here rather than made silently.

**A. -13's 16 rows are adopted in place, not closed and re-added (T6).**
- The migration gives each row its `terms` once, through a narrow, audited path: `terms` must be empty before the write, and the new document must equal what the row's old typed columns said, which the database checks before the old columns are dropped.
- Row ids, dates and every citation stay as they are.
- The alternative is closing all 16 rows and adding successors. v2 §11 rules that out ("a row is never closed just because its serialisation changed"), and it would make the dates say Texas law changed on the migration day.
- The other alternative is the residual R7 route: a migration that disables the history guard. That opens the whole row to edits, so I prefer a path that can only fill an empty `terms`.

**B. Law-file tooling in Python, with two pinned dependencies (PyYAML and `jsonschema`) in a project virtualenv.**
- The existing test harnesses are Python (`mutations-*.py`). The core will be .NET (TECH-STACK, locked), and v2 §5 already says the schema becomes generated from the core's types once the core exists.
- At that point the loader can move to .NET or stay as a build tool. It is a build step, not part of the product, so either is cheap.
- Neither library is installed here today.

**C. CI as a GitHub Actions workflow on this repo.** It builds `tu.sql` in a PostgreSQL 16 container and runs L3's checks and the batteries on every push to `main`.
- This is the first CI the repo has.
- It uses Actions minutes on a private repo; a full build plus batteries takes a few minutes.
- If you'd rather keep everything local for now, the same checks ship as one script, `tests/ci.sh`, and the workflow is left out.

---

## 5. Out of step 2, recorded

| Item | Where it goes |
|---|---|
| Correction lineage (v2 §11; -15 R4; -13 R7) | Residual of -17; designed when a repair is first needed |
| The `interest_forfeited` event and capitalisation (v2 §8; 15:2747) | -15's rewrite (ledger record shapes) |
| The city's own customer classes (U5) | -15's rewrite, on F3 with tenant scope |
| Whether chapter 183 binds a city (P2), and K10/K11 | Kyle |
| Whether the -13 rows are investor-owned only, or also cover cooperatives | -13's migration. The saved §101.003(7) text in `places-sources/texas.md` is elided after exclusion (A), "a municipal corporation", so its full list of exclusions has to be read from the primary source before the backfill |
| Retiring `tests/v5.4.2-13` content-column references (64 in `battery-13.sql`) | -13's migration |
