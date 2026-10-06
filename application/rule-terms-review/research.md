# Research: established patterns for jurisdictional, time-versioned rules as data

Reviewing: `application/rule-terms-convention-proposal-2026-10-06.md` (typed key + `terms_kind`/`terms_version` + `terms jsonb`, core-validated, DB guards record integrity only).

Date: 2026-10-06. Tags: **[P]** = primary source (vendor documentation, specification, the paper itself, or the author's own text). **[S]** = secondary (third-party summary, forum, blog, or a patent standing in for product documentation). **[I]** = my inference, not a sourced claim.

Limits: Vertex and Duck Creek publish no detailed public data-model documentation. For SAP IS-U I found only training and community material. Guidewire documentation sits behind a login, so its patents stand in for it. Claims about those four products are thinner than the claims about Oracle and OpenFisca.

---

## 1. Utility CIS products

### 1.1 Oracle Utilities Customer Care & Billing / Customer Cloud Service (closest match)

Oracle's framework has three layers, and each one maps onto part of the proposal.

**(a) Algorithm Type → Algorithm → control table (parameters plus pluggable logic).**
- "An Algorithm Type defines the program that is called when an algorithm of this type is executed. It also defines the types of parameters that must be supplied to algorithms of this type." An Algorithm "references an Algorithm Type. It also defines the value of each parameter. It is the algorithm that is referenced on the various control tables." [P] https://docs.oracle.com/cd/E17998_01/doc/doc.22/e17871/F1/08Algorithms.html
- Parameter values are kept in an **"Effective-Dated scroll"** on the algorithm, and "the Algorithm Type controls the number and type of parameters." [P] same page.
- Control tables attach algorithms to business functions. For example, "the algorithm … used to calculate late payment charges on each Service Agreement Type." [P] same page.
- **Deposit Class**, the direct analogue of a deposit law row: the typed fields are few (id, description, refund description on the bill). Almost all behaviour sits in algorithm slots: Good Customer, Recommendation (with a Review Tolerance %), Refund Method, Refund Criteria, Interest Refund (with Months Between Interest Refund), and Review Method. [P] https://docs.oracle.com/en/industries/energy-water/ccb/29012/ccb-user-guides/Topics/C1_03Finan_Deposit_Class_Main.html
- The shipped recommendation algorithms are named strategies with parameters, for example AVGBILL-RES ("average bill … 12 months × 150%"), DEPRECOM-MBA ("maximum bill … × 150%") and DEPRECOM-GSP. [P] Oracle business-process docs, https://docs.oracle.com/cd/E93687_01/DOC/ (3.3.3.2 Determine Customer Deposit)
- **What this means here [I]:** Oracle does not try to give each jurisdiction's shape a column. Each variant shape is a **named strategy registered in code** with a **typed, effective-dated parameter set**, and the configuration row picks the strategy. "Max of highest bill × 150%" and "1/6 of annual billing" are two algorithms, not two column sets.

**(b) Business Object schema over an XML/CLOB extension column, the same move as `terms jsonb`.**
- "The structure of a business object is defined using an XML schema … One or more business object elements may be mapped to the MO's XML structure field." [P] https://docs.oracle.com/en/industries/energy-water/ccb/254/ccb-user-guides/Topics/F1_97ConfigurationTools_A_Business_Object_Has_Properties.html
- Oracle states the limit of that approach plainly: "If the MO's XML structure field is of the data type CLOB, indexing or joining to elements in this column via an SQL statement is not typically supported. Note that most MOs are currently using the CLOB data type." Its guidance is to put a property in the XML extension only when it "will never be indexed or joined." [P] same page.
- The schema is not documentation only. The framework **validates against it**: required elements, defaults, lookup values ("the lookup may be specified to validate that the value of the element is a valid lookup value"), and FK references ("the FK Reference may be specified to validate the data"). "The system will check the validity of the data based on the schema definition." [P] same page.
- Beyond the schema, rule checks are **BO Validation algorithms that run in the application tier on add and update**, after the MO's core validation. [P] https://docs.oracle.com/en/industries/energy-water/ccb/254/ccb-user-guides/Topics/F1_97ConfigurationTools_BO_Algorithm_Execution_Order.html

**(c) Effective-dated leaf values.** Bill Factor Value: "The Effective Date and respective Value … subsequent effective dates and values required whenever the value changes." Rate selection on the service agreement chooses which date picks the effective rate: bill start, bill end, or accounting date. [P] https://docs.oracle.com/en/industries/financial-services/revenue-management-billing/70000/ormb-online-help/Topics/C1_BP14Rates_Bill_Factor_Value_Main.html. The deposit interest docs say the same about choosing the date the effective rate is read at. [P] Oracle 3.3.3.4 Monitor Deposit – Calculate Interest.

### 1.2 SAP IS-U / S/4HANA Utilities

- Billing logic is built from small code units called **variant programs** ("elementary calculation steps") over typed **operands**, assembled into rates and billing schemas. Operand values such as prices are time-dependent. [S] https://learning.sap.com/courses/configuring-billing-and-invoicing-in-sap-s-4hana-utilities/understanding-billing-processes-and-master-data-in-sap-utilities and community material. This is the same pattern as Oracle: a code-registered calculation step plus typed, dated parameters.
- Security deposit interest runs through FI-CA **interest keys**, which point to typed calculation rules and dated interest rates. Interest documents record the period and the interest key used, so a record cites the rule key. [S] https://learning.sap.com/courses/implementing-sap-financial-contract-accounting/configuring-interest-keys ; https://help.sap.com/saphelp_46c/helpdata/en/2a/f9f68c493111d182b70000e829fbfe/content.htm
- SAP's escape hatch for variable decision logic is **BRFplus decision tables** (an application-tier rule engine), used for example in collection strategies. [S] SAP community.
- No source found showing that SAP stores jurisdictional rule content as untyped documents.

---

## 2. Tax engines and insurance rating

### 2.1 Avalara AvaTax (customer-side TaxRule)
- A TaxRule has typed key fields (jurisdiction code and type, state and county FIPS, `IsAllJuris`, tax code), typed dates (`EffectiveDate`, and `EndDate`, which applies "indefinitely if null"), a typed `TaxRuleTypeId` that "determines the behavior of the tax rule", typed-ish `Value`, `Cap` and `Threshold` fields, **and a free-form `Options` string ("Supports custom options for your tax rule")**. [S: field descriptions from the CData connector docs, which mirror the API] https://cdn.cdata.com/help/GEN/py/pg_table-taxrules.htm
- **What this means here [I]:** the key and the rule type are typed, and a fixed set of common slots (value, cap, threshold) is typed. Only the long tail goes into an opaque field. The **behaviour lives in the engine and is selected by rule type**, the Oracle pattern again. Avalara's own statutory content (rates and rules for some 12,000+ jurisdictions) is proprietary, and its storage is not documented publicly.

### 2.2 Vertex O Series
- Public material describes only "Vertex-supplied or user-defined tax rules", "taxability drivers", and categories "supporting standard and nonstandard rules, rates, surcharges, and fees." [P marketing] https://www.vertexinc.com/solutions/products/vertex-indirect-tax-leasing. The internal representation is undocumented, so I draw no conclusion.

### 2.3 Guidewire PolicyCenter Rating Management
- A **rate book** holds **rate tables** (typed factor lookups) and **rate routines** (step logic). A rate book is scoped by "code, name, edition, description, status, underwriting company, **jurisdiction**, policy line, offering, **effective date, renewal effective date, expiration date**." [S: Guidewire patent US9858623B1] https://patents.google.com/patent/US9858623
- Rate tables follow a **definition/instance** pattern: "rate tables are instances of rate table definitions." [S] same.
- **Activated rate books are locked**: "the rate tables … associated with activated ratebooks are locked and prevented from being editable". This is the proposal's "never edited". [S] same.
- **Editions** are variants that share routines but carry different table values. [S] same.
- **What this means here [I]:** logic (routines) and parameters (tables) are separate artefacts, each with a typed definition. Versions are whole immutable books with a draft → approved → active lifecycle.

### 2.4 Duck Creek
- Product definitions are "manuscripts" (XML) with inheritance per carrier, line and state. That is widely reported, but I found no citable primary documentation. [S, unverified] It is mentioned because inheritance (a state manuscript overriding a base manuscript) is a pattern the proposal does not have.

---

## 3. Rules-as-code and legal rule representation

### 3.1 OpenFisca (the most relevant reference for the parameter-vs-logic split)
- **Parameters** ("a property of the legislation that changes over time") are YAML files in a tree. **Each leaf carries its own dated values**, for example: "undefined before 1993; equal to 1000 from 1993 to 2010; equal to 1500 in 2010." Metadata includes `reference` (a legal citation **per dated value**) and `unit` (currency, `/1`, year). Scales (marginal-rate, marginal-amount and single-amount brackets) are a built-in parameter type. [P] https://openfisca.org/doc/coding-the-legislation/legislation_parameters.html ; https://openfisca.org/doc/key-concepts/parameters.html
- The project's rule: "create a parameter for any number described in the law and used in formulas rather than 'hard coding' the number." [P] key-concepts/parameters.
- **Variables and formulas are logic, written in Python.** When "a simple parameter adjustment is not enough" because the "mechanism significantly evolve[s]", you add a **dated formula** such as `formula_2017_01_01`; a formula is active until the next formula starts. Variables carry an inclusive `end`. [P] https://openfisca.readthedocs.io/en/latest/coding-the-legislation/40_legislation_evolutions.html
- Parameters and formulas **ship together in one versioned package**, the country package, under git and semver. [P] https://openfisca.readthedocs.io/en/latest/contribute/semver.html
- **What this means here [I]:** OpenFisca has two kinds of change. A *value change* means new dated leaf values, with no code change. A *shape change* means a new dated formula, which is code. The proposal has only one: a new row with a new terms document, plus a new `terms_version` when the shape changes. It does not distinguish leaf-level dating.

### 3.2 Catala
- A DSL for a "straightforward and systematic translation of statutory law into an executable implementation". It is literate (code interleaved with the statute text), built on default logic (base case plus labelled exceptions, which mirrors how statutes are drafted), has a proven compiler, and found a bug in France's official family-benefits implementation. [P] https://arxiv.org/abs/2103.03198
- Dates are first-class, with a formal treatment of date arithmetic and rounding ambiguities, which is relevant to "12 bills" versus "12 months" and to day-count rules. [P] https://arxiv.org/pdf/2403.08935
- Law evolution is handled **in code**, by conditioning definitions on dates inside scopes, not through a separate parameter store. [I, from the paper and examples; not quoted]
- **What this means here [I]:** Catala answers "how do we evaluate the law correctly". The proposal already defers evaluation to the C# core. Catala's lesson for us is *exceptions as structure* (base rule plus override), and that date arithmetic has to be pinned down explicitly.

### 3.3 DMN (OMG Decision Model and Notation)
- Decision tables have typed inputs and outputs (item definitions), cells in the FEEL expression language, and **hit policies** (Unique, Any, Priority, First, …) that say what happens when several rows match. [S] https://arxiv.org/pdf/1603.07466 ; https://flowable.com/open-source/docs/dmn/ch06-DMN-Introduction
- Versioning in practice (Camunda): every deployment creates a new decision-definition version, and callers bind to `latest`, `deployment`, `version` or `versionTag`. [P] https://docs.camunda.io/docs/components/best-practices/modeling/choosing-the-resource-binding-type/ ; https://docs.camunda.org/manual/7.9/user-guide/process-engine/decisions/repository
- **What this means here [I]:** "Bind to a fixed version" is what the proposal's record → rule-row citation already does. Hit policies are relevant to the "2 consecutive or 3 in 12" disjunctions.

### 3.4 Blawx
- A visual (Blockly) front end over s(CASP), goal-directed constraint answer set programming. It produces explanations ("natural language answers and logical explanations") and is used in the Canadian federal government. [P] https://popl23.sigplan.org/details/prolala-2023-papers/12 ; [S] https://oecd-opsi.org/wp-content/uploads/2024/04/Rules-as-Code-in-Canada.pdf
- Relevant here only as evidence that explainability ("why was this deposit required?") is a first-class requirement in rules-as-code. The proposal's `inputs jsonb` + fingerprint on records is a weak form of it.

---

## 4. Database patterns

### 4.1 EAV versus JSONB versus typed columns
- **EAV** (Karwin, *SQL Antipatterns*): you cannot enforce mandatory attributes, cannot use SQL data types, have limited or no foreign keys on values, and cannot enforce consistent attribute names. [S, book summaries] https://www.oreilly.com/library/view/sql-antipatterns/9781680500073/
- **JSONB**: PostgreSQL keeps no planner statistics for keys inside JSONB, which leads to bad join plans, and keys repeat on every row. The advice is to use columns when the shape is known and stable and JSONB when "the shape of data varies meaningfully per row and you do not need … aggregations." A **hybrid** is recommended: hot fields as columns, the tail in JSONB. [S] https://heap.io/blog/when-to-avoid-jsonb-in-a-postgresql-schema
- **Oracle states the same rule for its CLOB extension**: put something there only if it is never indexed or joined. [P] (§1.1b)
- [I] Rule rows are few (perhaps hundreds to thousands) and are read by key, so the statistics and storage costs do not matter here. The real costs are **lost foreign keys, lost per-field CHECKs, and harder review diffs**.

### 4.2 Temporal versioning of reference data
- **Effectivity**: "adds a time period to an object to show when it is effective." [P] https://martinfowler.com/eaaDev/Effectivity.html
- **Temporal Object**: one continuity (identity) plus several versions, "any time the value of any property changes, you get a new version." [P] https://www.martinfowler.com/eaaDev/TemporalObject.html
- **Temporal Property**: version single properties. Use it when "a few properties … display temporal behavior"; use Temporal Object when most properties are temporal. [P] https://martinfowler.com/eaaDev/TemporalProperty.html
- **SQL:2011 / PostgreSQL 18**: `PRIMARY KEY (…, valid_period WITHOUT OVERLAPS)` and temporal `FOREIGN KEY (…, PERIOD valid_period) REFERENCES …`, where the FK checks range *containment*. [S] https://neon.com/postgresql/postgresql-18/temporal-constraints ; https://www.depesz.com/tag/period. Snodgrass's *Developing Time-Oriented Database Applications in SQL* is the classic treatment of valid time versus transaction time (bitemporal). [P, book]
- [I] The proposal's row model is **Temporal Object with bitemporal stamps**: valid time comes from the effective range, transaction time from `created_at`/`recorded_txid`/`closed_at`. A temporal FK with PERIOD is the declarative form of "a citation of the right key in force on its dates". If the stack is on PostgreSQL 18, it could replace part of the trigger logic. (The repo uses 21 `EXCLUDE` constraints today, and I did not verify the PostgreSQL version.)

### 4.3 Validating JSON in PostgreSQL
- **pg_jsonschema** (Supabase, Rust/pgrx) provides `jsonb_matches_schema(schema, instance)` and `jsonschema_is_valid` for use in CHECK constraints. Validators can be cached per callsite with a `jsonschema` cast. [P] https://github.com/supabase/pg_jsonschema
- Without an extension: a per-version CHECK through an IMMUTABLE plpgsql function, `jsonb_typeof`/`?&` key checks, `jsonb_path_exists` predicates, and **STORED generated columns that extract jsonb paths** into typed columns that ordinary CHECKs and FKs can then constrain. [I; standard PostgreSQL features]

### 4.4 Keeping documents and code types in sync
- **Schema registry compatibility modes**: BACKWARD (new readers read old data), FORWARD, FULL, and `_TRANSITIVE` variants that check against *all* earlier versions. BACKWARD is the default "so that you can rewind consumers to the beginning of the topic." [P] https://docs.confluent.io/platform/7.2/schema-registry/avro.html
- **Event-sourcing versioning** (Greg Young): *weak schema* (map by name, defaults for missing fields; "you are not allowed to rename anything, and you may not change the semantic meaning of a property") and **upcasting** (transform old versions into the current shape when read, so consumers see only the latest). [P] https://leanpub.com/esversioning/read ; [S] https://event-driven.io/en/simple_events_versioning_patterns/
- [I] The rule rows are immutable and are cited forever, which makes them an event log as far as versioning goes. Either the core reads every `terms_version` ever written (BACKWARD_TRANSITIVE), or it upcasts old versions to the current type when it reads them. Stored rows are never rewritten.

---

## 5. Failure modes and practitioner mitigations

| Approach | Failure mode | Mitigation (source) |
|---|---|---|
| Typed column per setting | Every new jurisdiction's shape becomes DDL plus a migration (the problem the proposal reports: 29 shapes). | Move variation into **named strategies plus parameters** (Oracle, SAP, Avalara rule types) [P/S]. |
| EAV | No types, no mandatory fields, no FKs, inconsistent names. | Avoid it, or keep a typed attribute registry [S Karwin]. |
| JSONB / CLOB documents | An untyped dumping ground; fields nobody can join or index; silent drift between document and code. | Keep anything joined or indexed out of the document (Oracle [P], Heap [S]). Validate against a declared schema (Oracle BO schema [P], pg_jsonschema [P]). |
| General rule engines (Drools, BRFplus, DMN/FEEL) | "Very hard to reason about and debug"; the promise that business users will edit rules "rarely works out"; "any system with enough rules to need sophisticated algorithms probably has too many rules to be understood." | "Build a limited rules engine that's only designed to work within that narrow context." Test with production data. [P] https://martinfowler.com/bliki/RulesEngine.html |
| Version proliferation | Every edit becomes a version and readers multiply. | Separate *value* changes (new dated values, same shape) from *shape* changes (new version) (OpenFisca [P]). Compatibility policy with transitive checks (Confluent [P]). Upcast old versions on read (Young [P]). |
| Mutable activated rules | Historic results can no longer be reproduced. | Lock on activation (Guidewire [S]). Records bind to a fixed version (Camunda `version` binding [P]). |
| Parameters hard-coded in logic | The law changes and the code silently keeps the old value. | "Create a parameter for any number described in the law" (OpenFisca [P]). |

---

## 6. Synthesis

### 6.1 What the proposal most resembles
1. **Oracle CC&B's Business Object over an XML/CLOB extension column**, almost exactly: a typed maintenance-object key plus a schema-described document column that is not indexed or joined, validated in the application tier (BO schema plus BO Validation algorithms), not by the database. [P basis]
2. **Guidewire rate books / Fowler's Temporal Object**: whole-row immutable versions, scoped by jurisdiction, line and effective dates, locked once active. [S/P]
3. **Event-sourced payloads with weak schema**: an immutable, versioned JSON document read by code that owns the type. [P]

So the proposal is on an established path. Oracle in particular moved rule content out of typed columns for the same reason the proposal gives, and accepted the same loss of joins and indexes.

### 6.2 What those systems do that the proposal lacks
1. **A split between strategy and parameters.** Oracle (Algorithm Type → Algorithm), SAP (variant program → operands), Avalara (rule type → value/cap/threshold), Guidewire (routines → tables) and OpenFisca (formulas → parameters) all separate **which logic** from **which numbers**. The proposal's `terms` mixes them: `"combine": "single"`, `"method": "simple"`, `"measure": "bills"` are logic selectors sitting beside numbers. Without an explicit vocabulary of strategies, `terms` drifts towards an expression language, which is Fowler's rules-engine trap.
2. **A declared parameter schema held in the registry.** Oracle's Algorithm Type *declares* its parameter types, and its BO schema declares required elements, lookups and FK references. The proposal's `rule_term_kinds` holds only `(kind, version, introduced_on, description)`. The schema exists only in C#, and C# does not exist yet.
3. **Leaf-level dating for values that move independently** (OpenFisca parameters, Oracle bill factor values, SAP time-dependent operands). The proposal dates only whole rows. Shapes such as "interest indexed to Treasury yields by holding period" or an annually published rate would force a new law row each time the index publishes, even though the law has not changed.
4. **Lookup and FK validation inside the document.** Oracle's schema validates lookup values and FK references inside the XML. The proposal says vocabulary values used inside `terms` are "defined by the core's schema", so a waiver class named in `terms` has no referential check at all.
5. **A stated compatibility and upcasting policy** (Confluent, Young). Proposal question 4 leaves this open.
6. **A citation per value.** OpenFisca attaches `reference` to each dated value. The proposal has one citation per row, but a deposit row draws on several sections (cap, interest, refund), often from different rules or orders.
7. **Golden scenario tests stored with the law.** OpenFisca ships YAML tests in the country package, and Catala tests sit beside the statute text [P, project docs]. The proposal mentions core scenario tests but does not tie them to rows.
8. **Explanation.** Blawx and Catala produce a trace of why a result came out. `inputs jsonb` is a partial form of that.

### 6.3 Recommendations
1. **Make `terms` parameters-only, with strategies named from a closed, registered set.** Each logic variant (cap combiner, interest method, refund-eligibility test, "N consecutive or M in 12" late-pay test) is a **named strategy registered in the core**, the equivalent of Oracle's algorithm type. `terms` selects it by name and supplies its typed parameters. New jurisdiction shapes then become *new strategies* (code plus a registry row), not new expression syntax inside JSON. [follows Oracle/SAP/OpenFisca P]
2. **Put the schema in the registry, generated from one source.** Add `json_schema jsonb NOT NULL` (or at least a schema hash) to `rule_term_kinds` for each (kind, version). Make one artefact the source of truth and generate the other, either JSON Schema → C# records or C# → JSON Schema, so the argument that pg_jsonschema means keeping two schemas in step goes away. Then the DB can validate cheaply: through pg_jsonschema, or without the extension through a generated per-version IMMUTABLE CHECK function. Since the core does not exist yet, **schema-first is the only way `terms` gets validated before the core is written**. [I; tools P]
3. **Promote the facts the record guards need into STORED generated columns on the law row.** Examples: `return_mandatory_instruments text[]`, `cap_part_kinds text[]`, `trigger_codes text[]`, each derived from `terms` by an IMMUTABLE expression. The (B) guards can then stay as plain FK/CHECK/trigger logic over typed columns *without parsing JSON in triggers*. This is Oracle's "map what is joined to a column" rule and the Heap hybrid. It is the concrete "middle path" for proposal question 5, and it keeps the guards that prevent the worst errors (a return-due row with no mandatory return, a cap kind the rule does not have). [I, grounded in P/S]
4. **Separate dated leaf parameters from law rows** for values published on a schedule independent of the law: Treasury and index yields, a commission-set annual deposit interest rate, inflation-adjusted thresholds. Use a typed `rule_parameter_values (name, effective range, value numeric, unit, citation)` table, referenced by name from `terms`. This is OpenFisca parameters, Oracle bill factor values, and Fowler's Temporal Property. Law rows then change only when the law changes. [P]
5. **Versioning policy (answers question 4).** Rows are never rewritten. A `terms_version` bump happens only on a *breaking* shape change; additive optional fields with defined defaults do not bump it (weak schema). The core keeps a reader or **upcaster** for every version any row uses (BACKWARD_TRANSITIVE). Retiring a version means adding an upcaster, never migrating rows. The CI test loads every historic row through the upcaster chain and re-runs that row's golden scenarios. [Young P, Confluent P]
6. **Validate vocabulary references inside `terms`**, in the CI load test and ideally in the DB through the generated columns from recommendation 3 plus ordinary FKs or array-containment checks against the vocabulary tables. [Oracle P]
7. **Allow citations per section**: `terms.<section>.citation`, or a typed `rule_citations(rule_id, json_path, citation)`. [OpenFisca P]
8. **Store golden scenario fixtures beside each law row** (an inputs → expected outputs table, or files keyed by rule id), which the core's CI runs. [OpenFisca/Catala P]
9. **Consider PostgreSQL 18 temporal PK/FK** (`WITHOUT OVERLAPS`, `PERIOD`) for "the citation is in force on its dates", if the target version allows. [S]
10. **Do not adopt a general rule engine or expression language** (DMN/FEEL, BRFplus-style) inside `terms`. Keep strategies in C#. [Fowler P]

### 6.4 What argues against the proposal, or parts of it
- **Dropping (B) entirely has weak precedent.** Oracle validates documents against a schema *at write time* and runs BO validation on every write. Its guard sits in the single application tier that every write must pass through. In this design the core writes through `tally_app`, and the proposal leaves nothing at write time: only an after-the-fact report and tests. Recommendation 3 recovers most of (B) cheaply.
- **"Core-owned validation" has no owner today.** The core is not written, so until it is, `terms` is checked only for "is an object" and "kind/version registered". That is the dumping-ground failure mode at the point where the most rows are being authored (the sweep). Schema-first (recommendation 2) closes the gap.
- **Whole-row versioning will multiply rows** for indexed or annually published values (recommendation 4). This is the version-proliferation failure mode.
- **Vocabulary FKs disappear for values inside `terms`.** That is the EAV weakness: no referential integrity on the value side.
- **Rules-as-code projects (OpenFisca, Catala) keep law in versioned code, not the database.** This is an argument *for* the proposal's direction (the core owns the meaning, reviewed migrations write the rows). The caveat [I] is that their correctness comes from tests shipped with the law, which the proposal mentions but does not yet structure.
