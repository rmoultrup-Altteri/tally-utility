# The rule-terms convention (v2)

**Status:** ADOPTED by Ryan, 2026-10-06. Nothing in it is built yet.
**Supersedes:** `rule-terms-convention-proposal-2026-10-06.md` (v1, frozen `4b30e370`, reviewed).
**Reverses:** audit rule 2 ("one table per rule family, with typed columns", `texas-only-architecture-audit-2026-09-28.md` §2). See §11.
**Reviews and research:** `application/rule-terms-review/` — independent reviews by Opus, Fable and Codex (all "adopt with changes"), and a research report on established patterns. §10 maps every converging finding to where v2 answers it.

---

## 1. Why

- A law held as one typed column per setting needs DDL, a migration and a review round for every new shape.
  - The deposits patch (v5.4.2-15) found five such shapes in two review rounds.
  - A survey of 10 more states found 29 more (`deposits-source-survey-2026-10-06.md`).
  - Every remaining law area would repeat this.
- v2 keeps what the typed design did well: database integrity, readable keys, close floors, citations.
- It moves the law's *content* into a document that is checked on every write, and its *logic* into named, versioned strategies in the C# core.
- The pattern is established, not invented here:
  - Oracle CC&B: algorithm types with declared parameters; an XML content column validated against its schema on every write.
  - OpenFisca: dated parameters with a citation per value; logic in versioned formulas; tests shipped with the law.
  - Guidewire rate books: locked once activated.
  - Event-sourcing upcasting: old document versions read through converters, never rewritten.

## 2. The three layers

| Layer | Holds | Where | Changes by |
|---|---|---|---|
| **Logic** | How a decision is made: a cap combiner, a late-payment test, an interest method | Named strategies in the C# core (§4) | Code: a new strategy name or a new strategy version |
| **Law content** | Which strategies a rule uses, with their parameters | `terms jsonb` on the law row, checked against a registered schema on every write (§3, §5) | A new dated law row |
| **Published values** | Numbers published on their own schedule: an annual commission rate, Treasury yields, an indexed threshold | `rule_parameter_values`, dated per value, with a citation per value (§6) | A new dated value; no law row changes |

**Records** (deposits, events, due rows) cite the law row they were decided under, and keep the core's working in `inputs jsonb` with a defined fingerprint (§8).

## 3. A law row

**Typed, as today:**
- the applicability key: state, service type, customer class, basis or cause, and **utility type** (§9);
- `effective_from` and `effective_to`, with the no-overlap exclusion per key;
- `source_note`;
- the stamps: `created_at`, `recorded_txid`, `closed_at`, `closed_by`;
- the close floor.

**New:**
- **`terms_kind` and `terms_version`:** for example `deposit` / `1`. This is a foreign key to `rule_term_schemas`, and a CHECK fixes the kind allowed on each table, so a deposit row cannot carry a backbilling document.
- **`terms jsonb NOT NULL`:** the law's content, as strategy choices plus parameters.
- **Typed facets:** stored columns derived from `terms` when the row is inserted (§7). These are the few facts that database guards and ledger arithmetic read.

**`terms` holds parameters and strategy choices, never logic.** No expressions, no conditions, no formulas. "2 consecutive or 3 in 12 months" is a strategy named `consecutive_or_window` with three numbers, not an expression in JSON. This is the line that keeps `terms` from becoming a homemade rules language (Fowler's rules-engine warning).

The Texas residential deposit rule, sketched:

```json
{ "cap": {"strategy": "single", "parts": [{"id": "p1", "kind": "annual_billing_divisor", "divisor": 6}], "scope": "per_deposit",
          "citation": "16 TAC 7.45(5)(C)"},
  "interest": {"strategy": "simple_actual_365", "instruments": ["cash"], "min_hold_days": 30, "retroactive": true,
               "credit": "at_refund", "rate": {"source": "utility_rate"}},
  "return": {"test": {"strategy": "clean_bills", "count": 12, "max_delinquencies": 2},
             "on_close": true, "instruments": ["cash"], "disqualifiers": ["disconnect_nonpayment"], "obligation_vests": "unruled"},
  "triggers": {"usage_doubled": {"strategy": "usage_ratio", "ratio": 2, "pay_within_days": 2, "citation": "16 TAC 7.45(5)(C)(ii)"}},
  "waivers": [{"class": "family_violence_certified", "effect": {"strategy": "excuse"}}] }
```

- **Component ids** (`"id": "p1"`) are stable within a row. A record names the part that governed by its id, never by its position in an array.
- **Citations may be per section.** One row draws on several provisions.
- **"Unknown" stays distinct from "absent".** `"obligation_vests": "unruled"` is an explicit value; no setting silently defaults to false or zero.
- **Units are explicit in the parameter's name.** `annual_billing_divisor`, not an ambiguous `fraction: 6`.

### Tariff rows: the utility's own law content

- Tariff rows follow the same convention: tenant-owned (RLS), dated, cited to the tariff, with a typed key plus `terms` checked against a registered schema.
- They are written by `tally_app` at runtime, so **write-time validation (§5) is what protects them**. The build-time check never sees them.
- "Stricter, never looser" (audit rule 5) is a typed comparison between the tariff row's facets and the law row's facets, made at insert (§7).

## 4. Strategies in the core

**The Strategy pattern, selected by name, never by state:**
1. The core looks up the law row in force for the premise's applicability key on the date. This is the only step where the state matters.
2. It reads each strategy name from `terms`.
3. A registry resolves `(decision point, name, version)` to an implementation, built with the parameters.

```csharp
public interface IDepositCapRule { decimal Cap(CapInputs inputs); }

[Strategy("deposit.cap", "greater_of", version: 1)]
public sealed record GreaterOfCap(IReadOnlyList<CapPart> Parts) : IDepositCapRule {
    public decimal Cap(CapInputs i) => Parts.Max(p => p.Amount(i));
}

IDepositCapRule cap = strategies.Resolve<IDepositCapRule>(rule.Terms["cap"]);
```

- **One interface per decision point,** not one class per state. A state's law is the combination its row names. A new state is usually a new row of existing strategies; only a new mechanism adds a class.
- **The set of names is closed and registered** (§5). A row cannot name a strategy the core lacks.
- **Strategies are versioned and frozen once any row uses them.** Changed behaviour gets a new version, so old decisions still reproduce.
- **Exceptions are structure** (Catala): a base rule plus labelled overrides, not nested conditionals.
- **Date arithmetic is a strategy concern, made explicit:** bills versus months, day counts, inclusive ends, time zones.

## 5. Schemas and validation

**`rule_term_schemas (kind, version, json_schema, schema_hash, introduced_on, description)`:** one row per (kind, version). It declares:
- the strategies allowed at each decision point;
- each strategy's parameters: types, units, required or optional, and allowed vocabulary codes;
- that unknown keys are rejected and no field may be null.

**One source of truth.** Until the core exists, the JSON Schema is authored by hand and checked in. Once the core exists, the schema is generated from the core's types (or the types from the schema), so the two never need keeping in step by hand.

**Validated on every write, law and tariff alike.** There is no `pg_jsonschema` in the image (verified), so a generated, per-version, `IMMUTABLE` validation function is called from the row's insert trigger. It refuses:
- unknown keys;
- missing required keys and nulls;
- a strategy not registered for that decision point;
- parameters of the wrong type or outside their range;
- duplicate component ids;
- vocabulary codes that do not exist for the row's state and service (§7).

**Duplicate keys** cannot be caught after the cast to `jsonb`, which keeps only the last value (verified). Law content is therefore authored as files (§6) and linted for duplicates before loading. The tariff write API accepts JSON text, checks it for duplicates, then casts.

**CI, as well:**
- every stored row round-trips (parse, serialise, compare equal as `jsonb`);
- every row loads through the core's reader for its version;
- every row's golden scenarios pass (§6).

**Seeds are idempotent and strict.** Inserting a row whose key already exists with different `terms` raises; never upsert over immutable content.

## 6. Authoring, published values and tests

- **Law content is authored as files in git** and loaded by a reviewed migration. We adopt OpenFisca's parameter-file conventions: YAML, dated values, a citation and unit per value. This gives reviewable diffs in a documented format. We take the format only: no Python, no OpenFisca runtime.
- **`rule_parameter_values (name, effective_from, effective_to, value numeric, unit, citation)`:** a platform table for values published independently of the law, such as a commission's annual deposit rate, Treasury yields or indexed dollar thresholds. `terms` refers to them by name; the core reads the value in force on the date. A new publication is a new dated value, not a new law row.
  - The utility's *applied* rate stays its own tenant row (R-D1).
- **Golden scenarios sit beside each law row:** inputs mapped to expected outputs, run by the core's CI against the strategies the row names. They are the executable meaning of the row. The boundary cases in `deposits-rules-for-the-core.md` become the first set.

## 7. Typed facets: what the database still guards

Reviewers found the v1 split ("drop every guard that reads a setting") too coarse. v2 separates four kinds of check:

| Kind | Example | Where |
|---|---|---|
| **Record integrity** | Ledger arithmetic, identity frozen, append-only, citation of the right key in force, mutexes and race locks, tenancy | Database, unchanged |
| **Reference integrity** | "This deposit says its cap is statutory, so its rule has a cap with that part id"; "a trigger deposit cites a threshold its rule or the utility's tariff actually sets"; "the instalments sum to the principal" | Database, over **typed facets** |
| **Document validity** | Shape, strategy names, parameter types, vocabulary codes | Database, by the §5 validator on write |
| **Legal evaluation** | Is the deposit within the cap? Did the trigger fire? Is the refund due? Does the instalment count match the schedule? | Core |

**Typed facets** are columns on the law row (and tariff row) that the insert trigger fills from `terms`, and that no one can set directly. Examples:
- `cap_part_ids text[]`;
- `return_mandatory_instruments text[]`;
- `refund_reason_enablers text[]`;
- `trigger_codes text[]`;
- `waiver_classes text[]`;
- `instalment_count int`.

Ordinary constraints and the existing guards read the facets, never `terms`. Vocabulary codes are checked through the facets against the vocabulary tables. A misspelled waiver class is refused, rather than becoming a waiver that silently reaches no one.

**Which v5.4.2-15 guard goes where** is decided predicate by predicate, not table by table, when -15 is rebuilt. The reviewers' predicate tables (`rule-terms-review/fable.md`, `codex.md`) are the starting inventory.

## 8. Records, audits and the ledger

- **Amounts and operands the ledger arithmetic reads stay typed:** principal, received, cap amount, `cap_other_held`, event amounts, due amounts, and the resolved rate an accrual applied.
- **The core's working goes into `inputs jsonb`** with a defined fingerprint: an input schema version, canonical serialisation, a named hash algorithm, the source-record versions it read, rounding, and the core's release identity (`calculated_by`).
- **The discrepancy views are replaced by core audit passes.**
  - A SQL view that reads `terms` would be a second interpreter of the law, and it cannot see omissions.
  - The core runs scheduled and event-driven audits. It writes findings (rule, terms version, core release, coverage, time) to a tenant-safe findings table, including **missed decisions**: a return that should have fallen due and was never recorded.
  - Who acts on a finding is part of the design of each area.
- **The ledger changes the survey forces.** These are record shapes with real sources, not `terms`:
  - an `interest_forfeited` event (California PG&E Gas Rule 7: interest forfeited on disconnection for nonpayment). This settles the DIVERGENCE: "accrued must be credited" becomes "accrued must be credited **or forfeited** by the last event";
  - interest capitalisation for compounding (PG&E);
  - the remaining shapes the reviewers marked "record DDL" (about G5, G11, G13, G16, G17, G18, G20, G22, G23), each in its area's source inventory. G17 (Kansas K.S.A. 12-822's separate municipal deposit account) is treasury law and belongs to that area.
- **A separate core role (`tally_core`).** Core-only records are writable only by the core: due rows, accruals, audit findings, decisions. Operator screens and the assistant's staged imports, which run as `tally_app`, cannot write them. This also narrows what "a buggy core" can mean.

## 9. Applicability comes first

- The survey shows the law varies by **utility type**: municipal, investor-owned, cooperative.
  - Kansas binds municipal utilities directly.
  - Illinois exempts them.
  - Whether Texas §7.45 binds Texas municipal systems at all is open (Kyle question K10).
- The applicability key therefore needs utility type and, where the law needs it, a smaller place. That depends on the **places foundation** (audit §4 step 2): places, a dated premise-to-place link, jurisdictions pointing at places, and the fictional-state fixture.
- `terms` never selects among rules. Every discriminator is a key column or a class row: New York's heating customers, Arkansas's prepaid and landlord customers.

## 10. How v2 answers the reviews

| Converging finding (reviewers) | v2 |
|---|---|
| Tariff rows break the validation argument (all three) | §3: tariff rows validated on write; §5 |
| The core-only check misses typos and unknown keys; nothing validates before the core exists (all three, research) | §5: a registered schema, validated on write now, generated from the core later |
| Dropping all (B) loses reference integrity (all three, research) | §7: four kinds of check; typed facets |
| Vocabulary codes in `terms` lose their foreign keys (all three, research) | §7: facets checked against the vocabularies |
| Versioning: rows immutable, never retire a cited version (all three, research) | §4, §5, §11: frozen versions, readers for every cited version, no in-place upgrade |
| Discrepancy views become a second interpreter and miss omissions (Codex, Opus, Fable) | §8: core audit passes with findings, including missed decisions |
| The ledger itself encodes law (G27, G28, rate equality) (all three) | §8: forfeiture and capitalisation events; the resolved rate stays typed |
| Applicability: utility type, places first (Codex, Opus) | §9; K10 |
| Logic versus parameters; dated published values (research) | §2, §4, §6 |
| `tally_app` is the only writer (Opus) | §8: `tally_core` |
| The close floor races a new citation (Codex) | Already stated as residual R5 in -15; to be designed with the shared serialisation protocol when -15 is rebuilt |
| Reverses audit rule 2 (Fable) | §11; the correction note in the audit |

## 11. Policies

- **Never edited.** A law row's `terms` are never edited, and its kind and version never change. A change in law is a new dated row (close and supersede, with the close floor). A row wrong from its first day is a reviewed platform repair, with a correction lineage to be designed: separate legal-validity and recorded-revision histories, and re-evaluation of the records it touched.
- **Versions.** A new `terms_version` only for a breaking shape change; additive optional fields (with defined meaning when absent) do not bump it. The core keeps a reader, or an upcaster to the current internal model, for **every version any row has ever used**. A version is retired only when no row carries it, which for cited rows is never.
- **Strategy versions** follow the same rule, independently of `terms_version`.
- **Format changes are not law changes.** A row is never closed just because its serialisation changed.

## 12. Order of work

1. **Places and applicability** (audit §4 step 2), including utility type. Ask Kyle K10.
2. **The convention, written once:**
   - `rule_term_schemas`;
   - the validator generator;
   - the facet pattern;
   - `rule_parameter_values`;
   - the file format and loader;
   - `tally_core`;
   - the audit-findings table;
   - CI (round trip, load, golden scenarios).

   This is the "law-table template, written once" audit §4 step 2 called for.
3. **The sweep.** A source inventory per area before drafting. Classify each source requirement as `terms`, a new strategy, a vocabulary row, a fact the records lack, or a record shape. The test: can the system select, evaluate, evidence, schedule, settle and later reproduce this source's requirement? Not merely: can JSON hold it?
4. **Rebuild:**
   - v5.4.2-15 is rewritten on the convention. It carries over the ledger, due rows, withdrawals, citations, races, close floor and tenancy, and decides guard by guard per §7.
   - v5.4.2-13 is migrated. Its guards read only key columns (verified by Opus and Fable), but it needs an append-only migration procedure.
5. **The remaining law areas**, each as rows, strategies and scenarios: surcharges, tax, program effects and moratoria, the gas-cost pool, unclaimed property, the estimate cap, time zones.
