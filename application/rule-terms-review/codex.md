**Overall verdict: adopt with changes.** The typed envelope plus versioned `jsonb` is a reasonable direction. Do not adopt the blanket removal of (B), the CI-only validation policy, or the claim that the ledger can carry over unchanged.

MD5 matches: `4b30e3704881764670d4ee34c199bec3`. No repository files were modified and no database commands were run.

Citation shorthand below:
- **P** = `application/rule-terms-convention-proposal-2026-10-06.md`
- **D** = `sql/v5.4.2-15-deposits-law-to-core.sql`
- **S** = `sql/tu.sql`
- **Survey**, **Audit**, **Core** = the three supplied application documents.

This is a static review. PostgreSQL behavior explicitly identified as documentation-verified was checked against official documentation; application-level consequences remain reasoned findings, not database reproductions.

**Blocking**

**Q1 — Is the A/B split right? Verdict: useful distinction, insufficient removal policy.**

“Does this read terms?” is the wrong boundary. Distinguish **document validity**, **record/citation integrity**, and **legal evaluation**. Parsing a document to validate its shape is not evaluating law.

Several existing guards combine responsibilities:

- `enforce_deposit_instalments_complete()` checks both the rule’s instalment count and whether receipts plus scheduled amounts equal principal (`D:1580–1582`). Move the former; retain the latter.
- Tariff threshold handling checks tenant, jurisdiction, trigger, dates and takes a share lock (`D:1417–1428`), then checks whether the observed value meets the threshold (`D:1433–1437`). Only the latter is legal evaluation.
- Return evidence checks whether the rule enables the reason (`D:2324–2342`), but separately checks partial/full consistency, customer identity and evidence dates (`D:2343–2366`). Preserve record consistency and ownership; inspect date/status restrictions individually for hidden policy.
- A partial return’s amount must leave a remainder (`D:2224–2228`); a settlement must match the cited obligation (`D:2581–2599`). Those are record integrity regardless of what made the return due.

Keep tariff/rate references as typed FKs, or typed citation rows with tenant, purpose and relevant dates. Keep evidence references relational. A JSON copy of a tariff threshold’s identifier does not preserve its FK, tenant check or close-floor participation.

A statutory cap-part membership check can move to the core. If part identity needs database enforcement, retain a small immutable component-reference relation with `(rule_id, component_id)`; that need not contain the entire rule language. Otherwise explicitly acknowledge loss of that structural guarantee.

Require a **predicate-by-predicate disposition**, not a list of triggers to delete. P:65’s “(A) stays unchanged” is not an implementation specification.

**Q3 — Is core-owned validation plus a CI load test enough? Verdict: no, as specified.**

Deserialization alone does not establish valid meaning. The replacement must reject unknown fields/operators, missing required fields, unsupported versions, invalid units, impossible combinations, duplicate component identifiers, and invalid references. Current SQL checks relationships among fields, not merely their types (`D:514–563`, `D:631–635`; instalment completeness at `D:833–858`).

The strongest contradiction is **utility-written terms**. P:61 justifies weak database validation because law rows are reviewed migrations. P:77 extends the convention to tenant-owned tariff data. Existing tariff thresholds are explicitly “Written by the utility (RLS)” (`D:1953`). Build-time CI cannot validate future tenant submissions.

Required changes:

- Define one authoritative, immutable contract per kind/version, including semantic validation beyond structural JSON validation.
- Validate every write path, including tariff entry, imports and repairs. Tenant terms need database structural validation or a demonstrably exclusive validated write API with direct writes revoked.
- Constrain the allowed kind per table. Merely referencing a registered pair permits, for example, a deposit row containing a registered backbilling document.
- Validate deployed rule content against the actual supported core release. Registration is not proof of evaluator availability.
- Test the migrated database contents, including historical versions and vocabulary references, rather than only source fixtures.

I would use database document validation for both law and tariff terms, with the core retaining legal evaluation. Whether that uses `pg_jsonschema` or a narrowly scoped versioned validator is secondary. P:62’s duplication concern can be reduced through a shared contract and conformance tests; C# types alone are not the complete contract.

For PostgreSQL specifically, `CHECK` accepts SQL NULL, and replacing a CHECK function does not automatically revalidate existing rows. Use explicit `NOT NULL` and immutable version-specific validation semantics; do not hide mutable registry lookups inside a CHECK. These behaviors are **documentation-verified**, not tested locally. [PostgreSQL constraints](https://www.postgresql.org/docs/current/ddl-constraints.html)

Do not remove the existing validation before the replacement validator and representative scenario suite exist. “The core takes on the work earlier” understates this prerequisite.

**Q4 — What happens to old versions? Verdict: retain readable/evaluable historical contracts; neither proposed upgrade shortcut is acceptable.**

A document format version, a legal effective date, a correction of erroneous law data, and an evaluator release are different dimensions.

Old versions cannot simply become unsupported while records cite them. This affects ongoing operations, not just audits: `deposit_rule_citable()` deliberately permits later events to cite the deposit’s original rule outside that rule’s effective range (`D:2020–2040`). A held deposit can therefore still require an old evaluator contract.

Recommended policy:

- Preserve original terms and rule IDs.
- Maintain versioned readers/evaluators, or verified adapters to an internal model.
- Keep evaluator release identity separately from terms version; preserve the implementation or reproducible artifact needed to explain historical decisions.
- Use a new legal row when the law changes. Do not close a legal rule merely because its serialization format changes.
- If an alternate representation is stored, make it a separately identified derivative with a verified mapping to the immutable original.

Also resolve **corrections effective in the past**. The existing close floor refuses closure on or before any cited date and labels a rule wrong from inception a “reviewed platform repair” (`D:894–909`; `S:24244–24254`). Close-and-supersede cannot by itself represent correcting a mistaken rule after a later-date decision has cited it.

Specify correction lineage, selection of corrected versus originally known law, and reevaluation of affected records. That may require separate legal-validity and recorded-revision histories. Preserve what was used without forcing erroneous law to remain authoritative.

**Q7 — Does current code contradict proposal claims? Verdict: yes, materially.**

Three contradictions and one unresolved concurrency issue:

1. **“Citation … in force on its dates” is not universally true.** P:23 omits the grandfathered original-rule branch in `D:2033–2037`. Preserve and document that distinction; do not accidentally tighten it during the rewrite.

2. **The ledger cannot necessarily carry over unchanged.** Survey G28 describes forfeiture of accrued interest, but `D:2744–2750` requires all accrued interest to be credited before final settlement. Once interest has accrued, different JSON terms cannot make forfeiture recordable through that path. Survey G27 also requires monthly compounding; `D:2700–2707` limits `principal_basis` to principal held. An explicit capitalization or alternative calculation representation needs design and tests. These are surveyed operational shapes, not merely missing settings.

3. **Rate equality is a record-consistency check that reads a utility setting.** `D:2669–2672` requires `rate_applied` to equal the cited rate’s `annual_rate`. P:77 moves utility rates into terms, yet P:65 promises A stays unchanged without reading terms. Retain a typed resolved rate, permit structural extraction, or explicitly surrender this guarantee. All three claims cannot stand together.

4. **The law close floor appears vulnerable to concurrent citation insertion.** `enforce_deposit()` reads the rule without a share lock (`D:1354–1369`); `deposit_rule_citable()` also does an ordinary read (`D:2029–2037`). The close trigger scans committed citations (`D:894–902`). A writer can validate the open range while a closer fails to see its uncommitted citation, then both can commit a citation outside the closed range.

   This is a **static race finding, not reproduced**. PostgreSQL documents that key-share locks do not block non-key updates; the relevant lock compatibility is verified. The draft itself uses stronger locking for tariff closure (`D:1422`, `D:1873–1875`). Define and test a shared serialization protocol for law closure and citation insertion at supported isolation levels before declaring race guards reusable. [PostgreSQL locking](https://www.postgresql.org/docs/current/explicit-locking.html)

**Additional blocker — the discrepancy-report replacement is not designed.**

P:68 promises a view listing records that disagree with arbitrary versioned terms. The existing rate view compares typed rates and explicitly leaves whether a difference is lawful to the utility/core (`D:1621–1629`). That is much weaker.

A SQL view detecting arbitrary legal disagreement must implement legal semantics, call the core, or read stored core audit results. Choose explicitly. I recommend core-produced audit findings with a tenant-safe report view, recording evaluator version, rule version, audit time and coverage.

Crucially, auditing only existing records misses **omissions**: a deposit that should have generated a return-due row but never did. Scenario tests and citation immutability do not detect that production failure. Define scheduled/event-driven reevaluation, missed-work recovery, and who acts on findings. This belongs in the cost estimate.

**Should-change**

**Q2 — What else is lost by moving settings to JSON? Verdict: substantial guarantees and tooling, although key/range integrity can remain.**

Concrete losses include:

- **Referential and jurisdiction integrity:** waiver reach currently references the waiver vocabulary using state/service/class (`D:623–628`). Keeping that vocabulary table does not validate a class name embedded in JSON. Backbilling settings likewise have FKs to anchor bases and enforcement conditions (`S:24068–24079`).
- **Component uniqueness and completeness:** waiver uniqueness (`D:622`), cap-part identity (`D:668–670`), and instalment numbering/sums become validator responsibilities.
- **Stable component addressing:** array position is a poor identifier for “the cap part that governed.” Use explicit immutable component IDs scoped to a rule.
- **Discoverability and reporting:** column types, constraints and relational joins become version-dependent document paths and interpretation. JSON remains queryable, but cross-version reporting needs maintained projections.
- **Readable diffs:** require deterministic source formatting and rendered semantic diffs. PostgreSQL `jsonb` does not preserve object key order or duplicate object keys; reject duplicate keys before conversion if authoring mistakes must be caught. This is **documentation-verified**. [PostgreSQL JSON types](https://www.postgresql.org/docs/current/datatype-json.html)

No-overlap exclusion can remain on the typed applicability key and range. Close floors remain possible only if **every citation remains discoverable**, including tariff citations. Neither protection follows automatically from using JSON.

For seeds, keep stable identity/key lookup, compare expected existing content, and fail on unexpected differences. Do not use upserts that silently replace immutable terms.

For backbilling migration, preserve rule IDs and effective dates, prove conversion parity, and check both fresh-schema and upgrade paths. Existing immutability checks explicitly reject changes beyond closure (`S:24229–24233`), so conversion needs an intentional migration procedure. Nothing being live reduces data risk, not dependency work.

**Q5 — Is there a middle path? Verdict: yes; choose by responsibility, not presumed universal stability.**

Keep relational:

- identity, applicability, tenant, dates, provenance and version;
- cited law/tariff/rate/evidence identities;
- ledger amounts and other operands used by retained arithmetic;
- operational records such as instalments, obligations and settlements.

Use versioned documents for legal formulas, conditions, thresholds and combinations. Add typed projections only for demonstrated integrity or reporting needs, with a single source of truth.

A useful example is `cap_other_held`: P:73’s amount list omits it, but existing arithmetic reads it in both the cap and binding checks (`D:1263–1271`). Likewise, turning the resolved utility rate into JSON affects rate equality. Inventory operands before moving fields.

“Stable across all sources” is not a provable permanent boundary. A relational envelope plus validated terms is already a middle path; it does not require moving every setting or deleting every child table.

**Q6 — Are the sweep and its test right? Verdict: the candidates are sensible; the test is too narrow and absolute.**

The stronger test is:

> Can the system select, evaluate, evidence, schedule, settle and later reproduce this source’s requirements?

“Can JSON hold it?” answers only the storage question. Survey G17 requires fund accounting/investment records; G20 requires notice timing; G27–G28 affect interest accounting; G29 requires deadlines. Distinguish terms, input facts, operational records and evaluator capabilities.

Also, not every new surveyed shape requires DDL. Survey G1 includes missing trigger types, while `deposit_triggers` is already a vocabulary table (`D:284–295`). Some additions need vocabulary rows and core behavior. P:39 overstates the schema-change argument.

Missing or under-specified sweep work:

- **Applicability:** utility/regulatory type, municipal jurisdiction, smaller places, overlapping legal authorities and tariff precedence. The survey’s applicability uncertainties are explicit (`Survey:437–444`). A state/service/class/basis key cannot distinguish all of these by itself.
- **Rule selection:** jurisdiction from dated premise facts; conflicting rules; no known rule versus an explicit absence of a restriction; grandfathering and transitions.
- **Fact history:** disputes, service changes, notices, customer elections, rate observations and class-average inputs. Terms cannot manufacture unavailable evidence.
- **Time:** calendar/billing/business periods, deadlines, holidays and timezone boundaries.
- **Execution:** timers and recalculation triggers, retry/idempotency, and detection of missed obligations.

Restore the foundation work from Audit §4: places, dated premise-place links, jurisdiction linkage and fictional-state tests (`Audit:394–400`). The current backbilling schema itself says city-level rows await places (`S:24117`). A reusable JSON envelope does not complete that foundation.

**Notes**

- **Inputs plus fingerprint are not reproducibility by themselves.** The existing fingerprint check only requires an alphanumeric character (`D:2095–2097`). Define input schema versions, canonicalization, hash algorithm, source-record versions, rounding and evaluator identity. A hash neither reconstructs missing inputs nor proves their correctness.
- **The example needs semantic precision.** `fraction_of_annual_billing: 6` means a divisor in the draft (`D:1017–1018`), but reads like a multiplier or fraction. Name it `annual_billing_divisor`, or represent the fraction explicitly.
- **Preserve unknown versus absent.** Existing rules distinguish unresolved values such as `refund_obligation_vests` (`D:542–543`). Optional JSON fields must not silently become false or zero. The core document also identifies special handling of unevaluable inputs (`Core:160`); one universal default is unsafe.
- **The savings estimate is incomplete.** Fewer DDL statements exchange database work for contract maintenance, historical adapters, audit execution, authoring tools and operational recovery. Budget those before citing “about half the patch goes.”

**Required adoption changes:** replace the binary deletion policy with a predicate inventory; implement strict write-time validation; preserve relational citations and arithmetic operands; define historical-version and correction policy; implement operational auditing including missing decisions; fix and test closure races; and prove representative survey scenarios through the ledger before rewriting deposits and backbilling.