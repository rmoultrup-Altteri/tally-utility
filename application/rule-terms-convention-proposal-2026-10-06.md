# Proposal: law rows as a typed key plus a versioned terms document

**Status:** proposal for independent review (2026-10-06). Not decided. Nothing in it is built.
**Author:** Claude (session with Ryan), after the v5.4.2-15 round-3 revision (`7442c68`) and the 10-state deposit source survey (`application/deposits-source-survey-2026-10-06.md`).

## 1. The problem

The platform is a customer-information and billing system for small gas utilities: launching in Texas (municipal gas), designed for any state. Standing principles, decided by Ryan:

- **Schema represents, core evaluates.** The database stores law and records; a future C# calculation core evaluates the law.
- **Launch scope is not architecture scope.** Texas-first never justifies Texas-only design; statutory rules are per-jurisdiction rows.
- **Design permanent, record on change.** Nothing is live yet; no stop-gap options.
- **The utility owns its regulated values.** A value the utility answers for, such as its interest rate or its tariff waivers, is its own row. The platform keeps the legal value as a reference.

Current representation of a law (v5.4.2-13 backbilling, landed; v5.4.2-15 deposits, draft):
- one platform table per law area, with a row per (state, service, class, …, effective range);
- **one typed column per setting**, with CHECK lists of the allowed values;
- **child "part" tables** for multi-valued settings: waiver reach, disqualifiers, cap parts, trigger thresholds, instalment schedules;
- rows dated, cited, never edited — closed and superseded — with a close floor so a row is never closed under a date it is cited for;
- record tables (deposits, deposit events, return-due rows) cite the rule row they were decided under.

**Database guards fall into two kinds today:**
- **(A) Record integrity.** Ledger arithmetic, identity frozen, append-only, a citation of the right key in force on its dates, row-version mutexes and race locks, tenant isolation (RLS).
- **(B) Record matches the rule's settings.** Examples:
  - a return-due row needs a rule whose settings make the return mandatory for the deposit's instrument;
  - a statutory cap names one of the rule's cap parts;
  - a trigger deposit cites the threshold its rule sets;
  - the instalment count equals the rule's schedule.

**What broke it.** The deposits patch went through two review rounds. Each round found rule shapes the columns could not hold (D1-D5). A survey of 10 more states' gas deposit rules found **29 further shapes** the round-2 schema cannot hold. Examples:
- interest indexed to Treasury yields by holding period;
- caps on the highest or the heating-season bill;
- "2 consecutive or 3 in 12" late payments;
- refund thresholds in dollars;
- periodic recalculation with a 25% tolerance band;
- interest credited every January 1, with a cash election;
- a separate municipal deposit account (Kansas K.S.A. 12-822, which binds municipal utilities).

Each shape would be DDL, a migration and a review round. Every remaining law area would repeat this (audit `application/texas-only-architecture-audit-2026-09-28.md` §4).

## 2. The proposal

### 2.1 A law row
- **Typed, as today:** the key (state, service type, customer class, basis or cause, and so on), effective range, source citation, the stamps (`created_at`, `recorded_txid`, `closed_at`, `closed_by`), and the no-overlap exclusion per key.
- **`terms_kind` and `terms_version`:** for example `deposit` / `3`. They reference a small platform registry, `rule_term_kinds (kind, version, introduced_on, description)`.
- **`terms jsonb`:** the law's content. Texas residential deposits, sketched:
  ```json
  { "cap": {"combine": "single", "parts": [{"fraction_of_annual_billing": 6}], "scope": "per_deposit"},
    "interest": {"instruments": ["cash"], "min_hold_days": 30, "retroactive": true, "method": "simple", "day_count": "actual_365", "credit": "at_refund"},
    "return": {"after": {"count": 12, "measure": "bills", "max_delinquencies": 2}, "on_close": true, "instruments": ["cash"], "disqualifiers": ["disconnect_nonpayment"]},
    "triggers": {"usage_doubled": {"ratio": 2, "pay_within_days": 2}},
    "waivers": [{"class": "family_violence_certified", "effect": "excuse"}] }
  ```
- **The part tables disappear.** Their content goes into `terms`.
- **Vocabularies stay rows** where records reference them by foreign key: bases, triggers, customer classes, waiver classes, return reasons. Values used only inside `terms` are defined by the core's schema for that version.

### 2.2 Who validates `terms`
- The **core** owns the definition of each (kind, version): its types, its evaluation, and its scenario tests.
- The **database** checks only that `terms` is a JSON object and that (kind, version) is registered.
- A **CI test** loads every law row into the core's types, so a malformed row fails the build.
- Law rows are written only by reviewed platform migrations (`tally_app` cannot write them).
- **Alternative considered:** validating in the database with a JSON Schema extension (`pg_jsonschema`). Rejected for now: it adds an extension dependency, and the JSON Schema would have to be kept identical to the core's own types.

### 2.3 Which guards the database keeps
- **(A) stays unchanged.** None of it reads `terms`.
- **(B) is dropped and moves to the core.** A (B) guard would have to parse `terms`, which puts evaluation back in triggers. What replaces it:
  - every record cites its rule row (whose terms are immutable), so the terms it was decided under are always known;
  - a report view per area lists records that disagree with their rule's terms, like today's `deposit_interest_rate_discrepancies`, which compares two records rather than refusing a write;
  - the core's scenario tests.
- **What is lost:** the database no longer refuses a buggy core's record that contradicts its rule. For example: a return-due row under a rule with no mandatory return; a cap of a kind the rule lacks.

### 2.4 Records
- **Amounts the (A) arithmetic reads stay typed:** principal, received, cap amount, event amounts, due amount.
- **The core's working goes into `inputs jsonb` + `inputs_fingerprint` on the record.** That covers which cap part governed and its basis figure, the threshold and the measure observed, and so on. This is the pattern `deposit_return_due` already uses.

### 2.5 The utility's own values
- Tariff rows (the utility's interest rate, tariff waiver grounds, tariff thresholds, tariff caps) follow the same pattern: tenant-owned, dated, cited to the tariff, typed key plus `terms`.
- The law row records what the law permits a tariff to do.

## 3. Cost

- **v5.4.2-15** is not landed in `tu.sql`, so it is rewritten rather than migrated.
  - About half the patch goes: most rule columns, five part tables, the (B) guards, and about 30 of its 140 mutations.
  - The ledger, return-due rows, withdrawals, the citation rule (`deposit_rule_citable`), the race locks, the close floor and tenancy carry over.
- **v5.4.2-13 backbilling** (in `tu.sql`) migrates `backbilling_rules`, `backbilling_rule_window_terms` and `backbilling_window_term_kinds` to the convention. Nothing is live, so the migration is cheap now.
- **The core** takes on the work earlier.

## 4. The sweep

**Test:** would a second state, or a second utility, need a schema change to express its rule? Record states (invoice status and the like) are not law and pass. `tu.sql` has 236 CHECK lists; most are record states.

Candidates found so far:
- backbilling (-13): the same pattern;
- `regulatory_surcharge_rules` (-07/-08): Texas-shaped settings held as typed columns (`surcharge_kind`, `cap_per_service`, `exempts_state_agencies`, `excluded_from_tax_bases`), and per tenant, with no law half;
- `program_types.is_disconnect_protective`: one boolean for disconnect protection, which varies by state (moratoria, medical certificates, temperature, duration);
- audit §4's remaining items: tax exemptions and taxability, the gas-cost (PGA) pool, unclaimed property, the estimate cap, `America/Chicago`;
- the decision tables in gas-billing-memory's `configurable-rules/` that these patches were built from.

## 5. Proposed order
1. Ryan decides 2.3: drop (B), or keep some of it.
2. Write the convention once: registry, law-row pattern, the guard policy, the discrepancy-report pattern, the CI load test. This is the "law-table template, written once" of audit §4 step 2, which was never built.
3. The sweep, with a source inventory per area before drafting.
4. Rebuild: -15 rewritten, -13 migrated, the remaining strip items as rows plus core code.

## 6. Questions for reviewers
1. Is the A/B split right? Is any (B) guard actually record integrity that must stay in the database, and how would it be kept without reading `terms`?
2. Does moving settings into `jsonb` lose anything the typed columns gave besides (B)? For example: foreign keys from settings to vocabularies, queryability, the close floor, idempotent seeding, the no-overlap exclusion, review diffs.
3. Validation: is core-owned plus a CI load test enough, or should the database validate (`pg_jsonschema`, a per-version CHECK function, generated columns)?
4. Versioning: what happens to rows on an old `terms_version` when the core drops support? Is a new version a new row (close and supersede) or an in-place upgrade (which breaks "never edited")?
5. Is there a middle path: typed columns for settings that are stable across all sources, `jsonb` for the long tail?
6. Are the sweep candidates and the test right? What is missing?
7. Anything in the current codebase (`sql/tu.sql`, `sql/v5.4.2-15-deposits-law-to-core.sql`) that contradicts a claim above.
