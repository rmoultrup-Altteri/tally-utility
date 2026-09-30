# A-2 rules for the calculation core (2026-09-28)

## 0. What this is

A-2 is the backbilling patch: how far back a correction may reach, and who must approve it. Its r7 draft (`sql/v5.4.2-13-backbilling-caps.sql`, git `570d437`, 3,757 lines) put Texas backbilling law (16 TAC §7.45, the Railroad Commission of Texas gas quality-of-service rule) into PL/pgSQL triggers and functions. Ryan ruled on 2026-09-28 that **rule evaluation belongs to the C# calculation core, not the database**. Evaluation means computing the window, deciding forfeitures, deciding who must approve, and deciding which causes may be reissued. The schema now only stores records and protects their integrity. See [a2-parity-rescope-2026-09-28.md](a2-parity-rescope-2026-09-28.md) §2 for the objects being dropped, and [texas-only-architecture-audit-2026-09-28.md](texas-only-architecture-audit-2026-09-28.md) §2 and §6 for the rule model.

This document holds every rule the dropped code enforced, so nothing Kyle (the domain expert) ruled is lost. A C# engineer should be able to build the evaluation from this document and the rule tables alone, without reading the PL/pgSQL.

**How each rule is phrased.** Each rule is written against the *attributes* of the new platform rule tables (design §3), never against a cause name or a state code:
- `backbilling_rules`: `anchor_basis`, `favourable_duty`, `straddle_treatment`, `delivery_path`, `requires_supervisor_evidence`, `units_invariant`, `enforce_scope` / `enforce_months` / `enforce_condition`, and `source_note`.
- `backbilling_rule_window_terms`: `(direction, term_kind, months)`. A window starts at the **latest** of its terms' dates. A direction with no terms is uncapped.

Where r7 asked "is the cause `meter_error`?", each rule below names the attribute that replaces that test and gives the Texas seed value. Section 1 collects them all in one table.

**Rule of the house.** "The core evaluates, the schema records":
- The core computes the result and writes it as an evaluation plus evidence rows that name the rule row they used (audit rule 6).
- The database refuses only integrity violations (design §4).

### Source identifiers used below

| Written as | Means | Where |
|---|---|---|
| `R-19` … `R-39` | Kyle's A-2 rulings | GBM `application/kyle-decisions-2026-09-02-a2-backbilling-caps.md` (R-19…R-31), `…-09-22-a2-straddle-and-meter-test-anchor.md` (R-32…R-36, findings F-1…F-5), `…-09-23-a2-override-and-cause-freeze.md` (R-37…R-39, erratum E-1, open question OQ-1) |
| `CCK-1` … `CCK-14` | Kyle's customer-class-keying rulings (who is inside §7.45's protected class) | `kyle-decisions-2026-09-02-customer-class-keying.md` |
| `OQ-1` | Kyle's open question: how each cause's correction reaches a bill (adjustment or reissue) | `kyle-brief-2026-09-23-oq1-correction-delivery.md` (unsent) |
| `brief F-1`…`F-8` | Findings in the A-2 implementation brief (not Kyle's F-1…F-5) | `a2-implementation-brief-2026-09-21.md` §4 |
| `residual R1`…`R21` | r7's stated residuals: known limits, written in the patch. Not Kyle rulings, despite the similar names | r7 §15, lines 3550–3745 |
| `U4`, `U5`, `S4`, `U` | Round-6 review findings (Fable U4/U5; Opus S4/U) | r7 header lines 209–224; HANDOFF at `4221d15` |
| `A1`…`Q8`, `K1`…`L3` | r7 battery cases (`tests/v5.4.2-13/battery-13.sql`, 146 PASS) | battery group letters A–Q, K, L |
| `bM1`…`bM12` | Battery **group M** cases (written `M1`…`M12` in the file). Prefixed here so they aren't confused with mutations | battery lines 1137–1289 |
| `M01`…`M86` | Planted mutations (`mutations-13.py`, 84 of them; M43 and M69 don't exist). Each breaks one guard and names the battery case that must catch it | mutations file |
| `FR-A`…`FR-F2` | Checks that need separate transactions (`fence-and-race-13.sh`: A, B, C1, C2, D, E, F1, F2) | fence-and-race file |

"§7.45(7)(B)(v)(I)" and similar are clauses of 16 TAC §7.45. Clause text is carried from Kyle's records, which read the rule in full on 2026-09-02, 09-22 and 09-23. Nothing here is a fresh reading of the statute.

Line numbers such as "r7 1867–1905" are lines of `git show 570d437:sql/v5.4.2-13-backbilling-caps.sql`.

**Date arithmetic.** r7 computes "N months before a date" with PostgreSQL `date - make_interval(months => N)`. That clamps to the end of the month: 2026-08-31 − 6 months = 2026-02-28. C# `DateOnly.AddMonths(-N)` clamps the same way. Use it, and keep the same arithmetic in every rule that counts months (see §9.2 for why that matters). Billing periods are inclusive on both ends, `[period_start, period_end]`. The anchor day itself is outside the window: the window is `[window_start, anchor)`.

---

## 1. The attribute map: every place r7 keyed on a name

The audit's rule 4 says code decides by what a rule says, never by what it's called. This table is the conversion. The "Texas seed" column is the value that keeps Texas behaviour identical to r7.

| # | r7 asked… | r7 lines | The core asks instead… | Texas seed |
|---|---|---|---|---|
| 1 | `cause IN ('meter_error','non_registering_meter')`: derive the anchor from a discovering test, require the test, forbid `claimed_from` | 1689, 1867–1905; `shape_check` 1523–1529 | `anchor_basis = 'test_date'` | `meter_error`: test_date. `non_registering_meter`: test_date (**see disagreement D1**). Every other case cause: discovery_date |
| 2 | `meter_error` needs outcome fast or slow; `non_registering_meter` needs non_registering | 1873–1882 | `qualifying_test_outcomes` on the rule (added after D2) | `meter_error` {fast, slow}; `non_registering_meter` {non_registering} |
| 3 | direction from outcome: fast → customer owed; slow or non_registering → customer owes | 1885 | Not law. It's what the measurement means (a fast meter over-registered). The core may fix this mapping for all states | — |
| 4 | a case the test decided may change only to `tampering_bypass` | 1801–1807 | a case with `anchor_basis = test_date` may change only to another cause whose rule also has `anchor_basis = test_date` and whose qualifying outcomes include the standing test's, or to a cause with `requires_supervisor_evidence = true` | same effect as r7 |
| 5 | `cause = 'tampering_bypass'`: supervisor plus evidence to enter | 1921–1973; `tamper_check` 1542–1550 | `requires_supervisor_evidence = true` on the target cause's rule | `tampering_bypass` true; every other cause false |
| 6 | fast `meter_error`: no withdrawal while the test still finds it fast | 1772–1792 | `favourable_duty = 'mandatory'` and the standing test still gives the favourable direction | `meter_error` mandatory; every other cause permitted |
| 7 | hold only if `cause='meter_error' AND direction='customer_owed'` | 3069–3073 | `favourable_duty = 'mandatory'` and case direction favourable | as row 6 |
| 8 | uncovered-days check only for fast `meter_error` | 3215 | as row 7 | as row 6 |
| 9 | fast-findings surface reads `outcome = 'fast'` | 3517 | standing tests whose outcome qualifies for some cause with `favourable_duty = 'mandatory'` and gives the favourable direction | outcome fast |
| 10 | a zero amount is refused on every period of a test-anchored case with billed usage, **both directions** | 2494–2502 | `anchor_basis = 'test_date'` (the direction is derived). **See disagreement D5** | as r7 |
| 11 | the governing (last) test is read only when `cause = 'meter_error'` | 2230–2231 | read it whenever the resolved rule's terms (for either direction, at case or period level) include a last-test term. This is the latent defect the audit found | Texas: only `meter_error` has one, so there's no change for Texas |
| 12 | `billable_scope = 'shorter_of_months_or_last_test'` / `'months_from_anchor'` / `'uncapped'`, plus the deployment start for either counted scope | 2233–2235, 2284–2288, 2305–2308 | window terms `before_anchor N months`, `last_test_any_outcome`, `deployment_start`; no terms = uncapped | see §4.1 |
| 13 | R-36 gate: `cause='meter_error' AND direction='customer_owes'`, and "anchor − 6 months" | 2329; -12 `meter_governing_test` 1614–1615 | adverse direction, **and** the resolved adverse window has a last-test term, **and** anchor − that rule's adverse `before_anchor` term < cutover | 6 months, `meter_error` only (**see disagreement D3**) |
| 14 | evidence fence reads defective tests "within 6 months" of the anchor | 2167 | within the widest `before_anchor` of the rules the case can resolve | 6 |
| 15 | case-level rule is always the `protected` class at the meter's current premise | 2222–2225 | the widest window (earliest start) across every class and place that could apply to the meter's periods | residual R5 |
| 16 | void-and-reissue admits only `rate_misapplication` | CHECK 964–969; gate 1242–1247 | `delivery_path = 'reissue'` | `rate_misapplication` reissue; `meter_error` adjustment (R-33); the rest `unruled` (OQ-1) |
| 17 | a `rate_misapplication` reissue must bill the same units and the same period | 1249–1282 | `units_invariant = true` | `rate_misapplication` true; every other cause false |
| 18 | `enforceable_scope` `never` / `months` / `uncapped` / `conditional_on_read_classification` | 719, seed 780–813 | `enforce_scope` never / months / uncapped / conditional, with `enforce_condition = 'read_beyond_utility_control'` | see §4.1 |
| 19 | an adverse period straddling the window is forfeited whole | 2686–2689; evidence `forfeit_check` 2605–2609 | `straddle_treatment` | `forfeit_whole` |
| 20 | favourable periods are always included and the tenant limit never applies to them | 2697–2701 | per-direction window terms; `straddle_treatment` governs adverse periods only (R-25, R-32) | favourable terms = adverse terms for `meter_error` |
| 21 | case causes limited to five of the eight | case `cause_check` 1515–1516 | whether a cause can open a case depends on `delivery_path` and on whether it has a billing period. **Open (OQ-1)**; see §2.1 | r7's five: `meter_error`, `non_registering_meter`, `tampering_bypass`, `billing_constant_error`, `crossed_meters` |
| 22 | "same units" compares gas columns (`usage_quantity`, `gas_ccf_used`, `gas_therms_billed`) | 997–1054 | a per-service list of billing quantities (audit §3.2) | gas: those three |
| 23 | `regulatory_class_mode` names and the `customer_type` → class map | 842–882 | per-state class vocabulary (`backbilling_customer_classes`) plus the utility's mode | see §13 |

### 1.1 The Texas gas seed as rule rows

This is r7's seed (lines 766–834, R-20 as amended by R-39) re-expressed as design §3 rows. Effective from 2004-07-12 (design §3). All rows are `state_code TX`, `service_type gas`.

**Protected class (residential and small commercial):**

| cause | anchor_basis | adverse terms | favourable terms | favourable_duty | straddle | delivery_path | req. sup.+evidence | units_invariant | enforce | source (r7 `source_note`) |
|---|---|---|---|---|---|---|---|---|---|---|
| `meter_error` | test_date | before_anchor 6 months; last_test_any_outcome; deployment_start | same three | mandatory | forfeit_whole | adjustment (R-33) | false | false | never | (7)(B)(v)(I); (4)(E)(vi) |
| `non_registering_meter` | test_date in r7 (D1) | before_anchor 3 months; deployment_start | not reached: the direction is always adverse (r7 applied one window) | permitted ((v)(II) says "may") | forfeit_whole | unruled | false | false | never | (7)(B)(v)(II); (4)(E)(vi) |
| `rate_misapplication` | not used (not a case cause in r7) | none (uncapped) | none | permitted | — | reissue | false | true | months 6 | (4)(E)(v); (3)(C)(iii) |
| `estimation_catchup` | not used | none | none | permitted | — | ordinary next bill per OQ-1 text. **The design enum has no such value (D8)** | false | false | conditional, `read_beyond_utility_control` | (6)(C); (4)(E)(vii); R-21 |
| `tampering_bypass` | discovery_date | none | none | permitted | — | unruled | **true** | false | uncapped | (4)(D)(v); (4)(E)(vi) carve-out |
| `billing_constant_error` | discovery_date | none | none | permitted | — | unruled | false | false | never (pending counsel) | R-39 |
| `crossed_meters` | discovery_date | none | none | permitted | — | unruled | false | false | never (pending counsel) | R-39 |
| `unbilled_service` | not used (no billing period, OQ-1 follow-on 1) | none | none | permitted | — | unruled | false | false | never (pending counsel) | R-39 |

**Unprotected class** (large-volume customers outside §7.45's scope): every cause has no terms (uncapped) and `enforce = uncapped`. The citation reads "16 TAC 7.45 does not reach this class; ordinary limitations law and the filed tariff govern" (r7 773). r7 writes these rows explicitly rather than leaving them absent, so a missing rule stays an error.

- Pinned by: C4 (16 rows, 8 causes × 2 classes), C5 (one default per key; uncapped carries no months; no cause `other`; every row cites a source), C6 (tampering uncapped both ways; the R-39 additions enforce never), C1–C3 (the app cannot write, uncap or seed rows; M07).
- R-21 forbids giving `estimation_catchup` meter_error's six months as an uncited number. R-39 forbids a cause `other`, because "`other` resolves to nothing".

---

## 2. Opening a case: cause, direction and anchor

A **meter correction case** is one finding about one meter. It follows the *meter* across every deployment and every occupant (R-37(b)), which is why it's keyed on the meter rather than an account. The `meter_correction_cases` table stays (design §1). What goes is the derivation below.

### 2.1 Which causes open a case

- **Rule.** r7 opens cases only for `meter_error`, `non_registering_meter`, `tampering_bypass`, `billing_constant_error` and `crossed_meters`. It leaves out three:
  - `rate_misapplication`, which travels the reissue path (§12);
  - `estimation_catchup`, which is an ordinary next bill (OQ-1 text);
  - `unbilled_service`, which has no earlier bill, so R-32's "billing period" doesn't exist for it.
- **Attribute form (open).** A cause may open a case when its rule's `delivery_path` is not `reissue` and the cause has earlier billed periods to correct. How `unbilled_service` and `estimation_catchup` are delivered is OQ-1, still open.
- **Source.** R-33, R-39, OQ-1.
- **r7.** Case `cause_check` 1515–1516; header 139–142; §8 comment 1429–1432.
- **Pinned by.** Nothing directly. The CHECK is structural.

### 2.2 A test-anchored cause names its discovering test

- **Rule.** If the rule's `anchor_basis = test_date`, the case must name a discovering meter test, and that test:
  1. is a test of **this** meter (E10);
  2. has **not been superseded** by a correcting test (I12; M44);
  3. has no **opposite-direction standing test on the same meter and date**. "Opposite" means fast against slow or non_registering, and the reverse. A superseded test doesn't count. An accurate test beside a failed one contradicts nothing: as-found/as-left pairs are routine. If there is an opposite test, the history must be corrected before either test is cited (bM9; M60).
- **Source.** §7.45(7)(B)(v)(I) "if any meter test reveals", (v)(II) "found not to register". R-19 says the cause is created by evidence. R-39 says the outcome decides.
- **r7.** 1833–1872.

### 2.3 The outcome decides the cause

- **Rule.** The discovering test's outcome must be one the cause qualifies for:
  - `meter_error` needs fast or slow (E3 refuses accurate; E4 refuses non_registering; M14);
  - `non_registering_meter` needs non_registering, meaning zero registration only. A very slow meter that still registers is `meter_error` (E5; M15).
  - Outcomes come from the -12 test history, which derives them from readings. They are never asserted by the caller. The domain is accurate / fast / slow / non_registering / inconclusive.
- **Attribute form.** This needs a "qualifying outcomes" attribute (map row 2). It isn't in design §3 yet.
- **Source.** R-39 (the definitions bind the build), F-4.
- **r7.** 1873–1882.

### 2.4 Derived anchor, basis and direction

- **Rule.** For `anchor_basis = test_date`:
  - `anchor_date` is the discovering test's `test_date`;
  - the basis is `test_date`;
  - the direction is `customer_owed` if the outcome is fast, and `customer_owes` otherwise.
  - A caller-supplied anchor that differs from the test date is refused, because moving the anchor moves the window (E2; M13).
  - A caller-supplied direction or basis at opening is refused (E7; M17).
  - A test-anchored case carried no `claimed_from` in r7. Since review P1 it may carry one: the date the error is known to have begun, with `claimed_from_evidence`, read by a `claimed_start` window term (§4.1).
- **Source.** R-19 ("anchor_date … (v)(I) runs back from the test"), R-29 (anchor_basis recorded, test_date hard-coded in v1), R-39.
- **r7.** 1883–1905; INSERT fence 1817–1826; `shape_check` 1523–1529.
- **Pinned by.** E1 (a fast test on 2026-06-15 gives anchor 2026-06-15, basis test_date, direction customer_owed), E2, E7.
- **Disagreement D1.** R-19 and R-20 say (v)(II), the non-registering bound, runs back **from discovery** ("previous to the time the meter is found not to be registering"). R-19 warns that treating both anchors as one "silently misdates one of them". r7 anchors `non_registering_meter` at the discovering test's date with basis `test_date`, so it treats "found" as "the test". The design's Texas seed doesn't state this row's `anchor_basis`. Kyle should confirm which basis the (v)(II) row carries.

### 2.5 An adverse test-anchored case needs a test with readings

- **Rule.** If the derived direction is `customer_owes`, the discovering test must have load readings (`load_results` not null). A date-only migrated "slow" is an assertion, and an assertion doesn't bill a customer. A date-only "fast" may open a case, because a refund resting on a weak record errs toward the customer.
- **Attribute form.** This is an evidence policy keyed on direction, not on law. No rule attribute is needed.
- **Source.** An engineering rule in r7 (header 444–447). No Kyle ruling. Contrast R-36: a date-only row may still set a window as the *governing prior* test (§9).
- **r7.** 1886–1891.
- **Pinned by.** E6; M16.

### 2.6 Discovery-anchored causes

- **Rule.** For `anchor_basis = discovery_date`:
  - the operator supplies `anchor_date`, the discovery date, which must be on or before today (E9);
  - the operator also supplies `claimed_from`, the earliest date the fault is claimed to reach back to, which must be on or before the anchor (E8);
  - the case direction is empty. Direction is decided per period from the sign of the amount (R-25; §6.2).
  - For causes with no window terms, the anchor feeds only the tenant's own adverse limit (§4.4), and `claimed_from` bounds the periods evaluated (§5.1).
- **Source.** R-19, R-25, R-39, R-37(d).
- **r7.** 1906–1919; `shape_check` 1527–1529.
- **Pinned by.** E8, E9, F10.

### 2.7 One live case per discovering test

- **Rule.** At most one case that isn't withdrawn may rest on a given discovering test, or delivery would post the correction twice. A withdrawn case frees the test.
- **Source.** Engineering (round 1, Fable).
- **r7.** Unique index 1558–1559. It's integrity, so it stays in the schema.
- **Pinned by.** bM11; M62.

### 2.8 What the database stamps (stays in the schema)

- A case is born `open`.
- `opened_at` and `opened_by` are stamped.
- The meter, tenant and opening never change (E17; M47).
- The freeze and tamper-approval stamps are never caller-written (E18, I3; M46).

These are record integrity. They are listed here only so the core doesn't try to write them.

---

## 3. Cause changes and the tamper/evidence gate

### 3.1 A cause change needs a new reason, and re-evaluation follows

- **Rule.** While a case is open its cause may change. Each change needs a `cause_change_reason` that is present and different from the previous one (E13; M20). Each change is logged as an event with from-cause, to-cause, reason and actor (E15). The cap re-evaluates on every cause change. In this model that means a new evaluation; see §11 for the freeze.
- **Source.** R-19, R-38.
- **r7.** 1808–1815; events 2002–2011.

### 3.2 A test finding keeps its cause

- **Rule.** A case whose cause is test-anchored may move only to another test-anchored cause the same test qualifies for, or to a cause with `requires_supervisor_evidence = true`. Relabelling a fast `meter_error` as `billing_constant_error` or `crossed_meters` would drop the window and the mandatory refund while the test still stands. If the test was wrong, correct the test (supersede it) and withdraw the case. A separate fault on the same meter is a separate case.
- **Source.** An engineering reading of R-19 (meter error → tampering is "the common progression") and R-39 (the outcome decides). There is no explicit Kyle text.
- **r7.** 1801–1807.
- **Pinned by.** E20; M49.

### 3.3 Entering a cause that lifts protection needs a supervisor and evidence

- **Rule.** Moving a case **into** a cause whose rule has `requires_supervisor_evidence = true`, **including at opening**, needs both of these:
  1. **A supervisor's session.** A supervisor is a tenant_admin of the session's own tenant, or a platform administrator (E11, E14; M18).
  2. **Exactly one evidence reference of one of three kinds:**
     - `service_order`: a service order **on this meter**;
     - `deployment_removal`: a deployment **of this meter** whose `removal_reason = 'tamper'` (E12 refuses another meter's tamper removal, and refuses no evidence; M19);
     - `field_report`: a reference containing at least one letter or digit.

  The database stamps the approval time and approver (E12). While the case stays in that cause, its approved evidence can't change. To cite other evidence, leave the cause and re-enter it (E15; M45).
- **Why this transition alone.** It is the one edit that at once lifts the (4)(E)(vi) disconnection bar and uncaps the bill (R-38 attachment 2, F-1).
- **Source.** R-38 attachment 2; R-39 (the rename from `tampering_theft`: "theft" is a criminal conclusion).
- **r7.** 1921–1964; `tamper_check` 1542–1550.
- **Counsel.** "Who tampered" is in the R-39 counsel bundle item 1. A new occupant who inherits a bypass loses protection on the text.

### 3.4 Leaving that cause needs only a reason

- **Rule.** Moving **out** of a `requires_supervisor_evidence` cause moves toward protection. It needs only the reason. The evidence and approval stamps clear, and the event history keeps them (E15).
- **Source.** R-38 attachment 2 ("changes toward protection need only a recorded reason").
- **r7.** 1965–1973.

### 3.5 After posting (not in r7)

R-38 attachment 3 applies once a correction has posted:
- the posted adjustment stands;
- tampering found later raises a supplemental adjustment for periods beyond the window;
- the protection lift on the posted charge is an append-only re-determination row, behind the §3.3 gate.

r7 doesn't implement posting (residual R1). The core's delivery step (-14) must.

---

## 4. The window

### 4.1 Window start = the latest of the rule's terms

- **Rule.** For a direction with terms, the window start is the **latest** date among the terms that produce a date. A term that produces no date drops out. No terms at all means uncapped in that direction. The terms Texas uses:
  - **`before_anchor N months`**: anchor − N months (§0 arithmetic). This is always a date. The term can also count in `days` or `billing_periods` (review P1); Texas uses months only. r7 calls it `statutory_start`.
  - **`last_test_any_outcome`**: the governing prior test's date (§4.2). If there is no prior test, the term drops out and the months term governs alone.
  - **`deployment_start`**: the deployment bound (§4.3). It drops out if there is none or, for the favourable direction, if it isn't corroborated.
- Every term can only move the start **later**, so the months term is the ceiling. The last-test term is the protective one: it shortens the window, it never extends it. So an interim six-month-only bound over-reaches (R-34 build order; 09-22 record §1).
- **Texas example.** `meter_error` protected: window start = MAX(anchor − 6 months, governing prior test date, corroborated deployment start).
- **Source.** §7.45(7)(B)(v)(I) "the shorter of the last six months or the last test"; 09-22 record §1; R-37(a).
- **r7.** 2233–2235, 2284–2288. `meter_correction_inputs()` is the whole of 2178–2336.
- **Pinned by.**
  - F1: no prior test gives window 2025-12-15 = anchor 2026-06-15 − 6 months. `absence = undeclared`; three adverse periods included.
  - F2: a prior accurate test on 2026-03-10 gives window 2026-03-10 (M30).
  - F4: a corroborated deployment start 2026-03-01 gives window 2026-03-01.
  - F9: `non_registering_meter`, anchor 06-15: 3 months gives 03-15; the meter's start 03-20 gives window 03-20.
- **Fallback chains (review P1, 2026-09-30).** A term may carry a `priority`. Terms with no priority always apply. The terms with a priority form one fallback chain per direction: take them in priority order, and only the first whose date is known applies. The window start is the latest of the applying dates. Example (fictional ZZ in the battery): "from when the error is known to have begun, otherwise half the time since the last test, never more than 12 months" is `claimed_start` priority 1, `half_since_last_test` priority 2, and `before_anchor 12 months` with no priority. If no chain term is known, the chain contributes nothing and the unprioritised terms govern. Texas uses no chains.
- **`claimed_start`** reads the case's `claimed_from`. On a test-anchored case that date is optional: it is when the error is known to have begun, with `claimed_from_evidence` saying what shows it. Whether that evidence makes the date "known" is the core's call; if the core rejects it, the term is unknown and the chain falls through.
- **The term kinds, anchor bases and enforcement conditions are rows** (`backbilling_window_term_kinds`, `backbilling_anchor_bases`, `backbilling_enforce_conditions`), not CHECK lists. The core must refuse a rule that names a row it does not know how to evaluate, never skip it.
- **Also in the design vocabulary, unused by Texas:** `last_test_accurate`, `half_since_last_test`, `service_start`, `claimed_start`. R-34 **rejected** an accuracy filter for Texas ("the last test of the meter" has no accuracy qualifier, and the broader reading is more protective).

### 4.2 The governing prior test

- **Rule.** The governing prior test is the most recent **non-superseded** test on the **same meter** dated **strictly before the anchor**, whatever its outcome and whatever its kind (periodic, customer-requested, acceptance, …).
  - **Same-date ties rank:**
    1. a row with readings;
    2. then an asserted failure without readings;
    3. then a row with any outcome;
    4. then the stronger record basis (`recorded` > `migrated_full` > `migrated_date_only`);
    5. then the later insertion (`recorded_seq`).
  - **If none qualifies:** there is no date, and the evidence records `absence`, which is the meter's declared test-history absence (`attested_none` / `unknown`) or `undeclared`.
  - **Never infer a test date** from `meters.last_test_date`, `install_date`, `test_interval_months` or `next_test_due_date − test_interval_months` (R-24 as amended by R-31, R-35 refinement 3).
  - A governing test that itself found the meter defective is flagged `prior_test_failed`, a data-integrity flag for the operator. It is **not** skipped (R-34).
  - The evidence also records `governing_record_basis` and `governing_entered_out_of_order`. The second is D-5 from the -12 test-history brief (CI-091): a test entered after a later-dated one.
- **Source.** R-34, R-35 (refinement 5: no prior test means the months term alone, never a refusal), R-36 (a date-only row sets the window, marked), R-31.
- **r7.** Calls -12's `meter_governing_test(meter, anchor)` at 2230–2231, only when the cause is `meter_error` (map row 11). The function lives in -12 (`v5.4.2-12-meter-test-history.sql` 1544–1618), which has landed and isn't dropped by this re-scope. It is evaluation by the same test, so the core may call it or re-implement it. Record which.
- **Pinned by.** F1, F2, I6 (a test entered late on 2026-05-01 becomes governing, sets window 2026-05-01, and carries `entered_out_of_order`).
- **Defect fixed by the attribute form.** r7 reads the governing test only for `meter_error`. If another state gives a last-test term to another cause, the term silently drops and the window gets longer, against the customer. The rule: read it whenever the resolved rule has a last-test term.

### 4.3 The deployment bound, and corroboration for refunds

- **Rule, the candidate.** Consider the meter's deployments that:
  - overlap `[anchor − months, anchor)`, as `[install_date, removal_date)` overlaps it;
  - and were **created no later than the evidence fence** (§7).

  The candidate is the one with the earliest `install_date`, ties broken by id. Its `install_date` is the bound. If none qualifies, there is no bound. A deployment start **bounds** the window. It is **never** treated as a test date (R-37(a), against R-35 refinement 3). In r7 the candidate exists only when the rule is counted, meaning a months term is present.
- **Rule, corroboration for the favourable direction.** For a refund, the bound applies only if it's corroborated: there is **another** meter's deployment `pd` at the same location where:
  1. `pd.created_at` ≤ fence;
  2. `pd.install_date` < candidate install date;
  3. `pd.removal_date` is set and ≤ candidate install date;
  4. `pd`'s removal was on record before the fence. An app-recorded removal (`removal_recorded_at` set) must be **strictly before** the fence. An owner-loaded removal (no stamp) counts if `pd.created_at` ≤ fence.
  5. `pd.removal_date` ≥ anchor − months, meaning the predecessor served **into** the window.

  An adverse window is shortened by **any** recorded start that passes the fence.
- **Why corroboration.** `sync_meter_deployments()` makes every meter's first deployment from `meters.start_date`, which defaults to the day the meter was *entered*. On a migrated meter, "the start of its deployments" is its onboarding date. Honouring it would end every fast-meter refund at go-live and silently drop the pre-cutover stretch the legacy hold protects (residual R6).
- **Attribute form.** The design's `deployment_start` term doesn't distinguish the two directions. The core applies the corroboration test whenever the term is evaluated for the favourable direction.
- **Source.** R-37(a) ("readings taken by a different meter were never previous readings of this one"). The corroboration test is an **engineering reading** put to Kyle in the OQ-1 brief ("is that reading acceptable?"), and it is unanswered.
- **r7.** Candidate 2239–2246; corroboration 2256–2277; applied only to a refund 2278–2283.
- **Pinned by.**
  - F4: e4 went in 2026-03-01 as its predecessor came out; the bound is corroborated.
  - F5: a deployment created after the finding doesn't bound (M28).
  - F7c: an onboarding-date start with no predecessor doesn't shorten the refund; the window stays 2025-12-15 (M29).
  - F9: an adverse window is shortened by an uncorroborated start.
  - bM6: a predecessor removed in 2015 doesn't corroborate (M56).
  - FR-A: a predecessor entered after the finding doesn't corroborate, even after re-pointing the case at a fresh copy of its test.
- **Known cost.** A genuinely new meter at a new premise with a migrated start reaches back further for a refund than R-37(a) strictly requires. That errs toward the customer and is capped at the months term (residual R6).

### 4.4 The tenant's adverse limit

- **Rule.** `tenants.backbilling_adverse_limit_months` (utility data; kept) is optional. If set, `tenant_limit_start = anchor − N months`.
  - It applies **only to adverse periods**, for **every** cause, including uncapped ones: it's where a tenant's own filed-tariff backbilling limit is expressed.
  - It **never** applies to a favourable period.
  - It is one more candidate that can only move the adverse start later, so it can never lengthen anything. Empty means no tenant limit, and the statute governs alone.
  - Every period it excludes is a forfeiture with reason `tenant_limit` (§6.3).
- **Source.** R-37(d) (directed by Kyle); audit rule 5 ("a utility may be stricter than the law, never looser").
- **r7.** Setting 304–324 (kept); applied 2296–2298, 2690–2692.
- **Pinned by.** A3, A4 (0 refused), F8 (a 2-month limit forfeits April on the adverse case and leaves all six refund periods on the fast case; M27).
- **Consistent by construction.** R-37(d) says the limit is "constrained to ≤ the statutory bound". r7 checks only > 0. Because the limit is a MAX candidate, a longer value has no effect. The core may add the explicit check, but doesn't need to.

### 4.5 The favourable side cannot be shortened by any setting or choice

- **Rule.** No tenant setting and no operator choice shortens the favourable window. It is shorter only where the facts make it so:
  1. a prior test inside the months term;
  2. the customer is outside the protected class (§13);
  3. a lawfully established differing municipal standard (R-26; a city-level rule, design §5.1).

  R-37 withdrew the R-22/R-27 "override with a recorded reason" in the favourable direction. Its three proposed reason codes are rejected as reasons (§15).
- **Source.** R-37 (option C), which amends R-22 and R-27.
- **r7.** Expressed by the absence of any override, plus §10 (holds) and §11 (the freeze coverage check).

---

## 5. Billed periods: what counts as "billed"

### 5.1 The period set

- **Rule.** The periods evaluated for a case are the invoices that:
  - belong to the tenant;
  - were **issued** (`first_issued_at` set, so a discarded draft never counts);
  - are **not void**;
  - have `invoice_type` in {`regular`, `final`, `correction`};
  - carry at least one line naming **this meter**;
  - have a period **overlapping** `[set_start, anchor)`, that is `period_start < anchor` and `period_end ≥ set_start`.

  This is **whoever was billed and wherever the meter stood**. Ordered by `period_start`, then invoice id.
- **Rule, the set start.** `set_start` is the window start if the case-level rule is counted; otherwise `claimed_from`. If neither exists (an uncapped rule and no claimed start), the evaluation is refused as unbounded.
- **Rule, billed units.** `billed_units` for a period is the sum of `usage_quantity` on that invoice's lines for this meter. It is empty if every such line's usage is unknown.
- **Consequences.**
  - A favourable period lying wholly before the window is **not evaluated at all**: the duty reaches back to the window, not beyond it.
  - A period that straddles the set start *is* evaluated and then judged (§6).
- **Source.** R-37(b) (target the meter's readings across every deployment and occupant); R-25.
- **r7.** `meter_correction_billed_periods()` 2103–2132, a definition deliberately shared by the evaluation, the hold checks and the freeze so they can't disagree. Set start 2290–2295.
- **Pinned by.** F7 (February, billed to another customer at another premise, is in scope), F3b (a period wholly before the window isn't evaluated).
- **Limitations.**
  - Invoice types `consolidated`, `duplicate`, `prebill` and `credit_memo` are not "billed" here. How consolidated parents and children are built isn't defined yet (residual R21).
  - `invoice_line_items.meter_id` is tenant-blind today (residual R20).

### 5.2 "Billed" for a date range

- **Rule.** A range `[start, end]` is **billed** if any invoice from the §5.1 definition, with `p_from = start` and `p_before = end + 1`, exists. It is **fully billed** if every day of the range lies inside some such invoice's `[period_start, period_end]`.
- **r7.** `meter_correction_range_billed` 2966–2974; `…_fully_billed` 2977–2989. Used by holds (§10).

---

## 6. Per-period direction, evidence, forfeiture and straddle

The structural ruling of A-2 is R-25: **direction is tested per original billing period, never netted per invoice.** Netting would let time-barred charges ride into a bill hidden behind favourable months.

### 6.1 Each period answers to its own rule

- **Rule.** For each period in the set:
  - resolve the class of **that period's customer** (§13);
  - resolve the rule for **that bill's premise** (`invoice.location_id`), service type, class and cause;
  - compute **that period's own window** from that rule's terms, using the same anchor, the same governing test and the same deployment bound as the case. Class and place can differ across occupants and relocations.
- **Evidence per period records:**
  - the invoice, customer, location, period start and end, billed units, class;
  - the rule row used, and its jurisdiction level;
  - the rule's window shape and the period's window start, and the tenant limit start;
  - the rule's enforceable scope and months;
  - the direction, the caller's amount, the disposition and forfeit reason, the days in the window, and the forfeited amount.
- **Source.** R-25 (governing cap row, direction, window, anchor, trimmed or not); R-26 (jurisdiction level); R-29 (anchor basis, recorded on the evaluation); R-37(b).
- **r7.** Per-period resolution 2300–2316; evidence insert 2659–2717; table 2561–2614 (kept, per design §1).

### 6.2 The amounts: exactly the found periods, signed

- **Rule.** The caller supplies one dollar figure per period, `{invoice_id: amount}`. Positive means the customer owes; negative means the customer is owed. How a test's error becomes dollars is **not ruled**, so the amount is the caller's (residual R2). Validation:
  1. The keys are **exactly** the periods found: none left out (F11; M22), none added (F12).
  2. Each value is a number with at most two decimal places (F14).
  3. For a case with a derived direction (test-anchored), the sign must agree for **every** period. A fast meter can't yield a charge, and a slow or non-registering meter can't yield a refund (F13; M23).
  4. For a case with a derived direction, zero is refused on any period whose `billed_units` isn't exactly 0. Unknown (empty) usage counts as usage (bM10, N4; M61, M68). See disagreement D5.
  5. The period direction is `customer_owes` if amount > 0, `customer_owed` if amount < 0, and `neutral` if amount = 0 (possible on discovery causes, or where billed units are 0).
- **Source.** R-25 (direction is a computed fact), R-37 ("de minimis" is not a lawful reason to decline a refund), R-39.
- **r7.** 2468–2508, 2679–2681.
- **Pinned by.** F10: a discovery case with amounts [10, −5, 10, 0] gives owes/owed/owes/neutral.

### 6.3 Disposition: included or forfeited

- **Rule, for an adverse period** (`customer_owes`). Test in this order; the first that applies decides:
  1. The period's window exists and `period_start < window_start`: **forfeited**. The reason is `straddles_window` if `period_end ≥ window_start`, otherwise `before_window`.
  2. Otherwise, a tenant limit exists and `period_start < tenant_limit_start`: **forfeited**, reason `tenant_limit`.
  3. Otherwise, the case has `claimed_from` and `period_start < claimed_from`: **forfeited**, reason `straddles_claimed_start`. Billing a period that began before the fault is claimed to have begun over-reaches the claim.
  4. Otherwise: **included**.
- **Rule, for a favourable or neutral period.** Always **included**, including one that straddles the window (R-25, R-32). The tenant limit never applies.
- **Rule, what a forfeiture gives up.** Under `straddle_treatment = forfeit_whole` (Texas), a forfeited period gives up the **whole** amount, and `forfeited_amount = correction_amount`. An included period gives up nothing. Only an adverse period can be forfeited.
- **Rule, days in window.** `days_in_window = max(0, period_end − max(period_start, eff) + 1)`, where:
  - for adverse periods, `eff` = the latest of the period window start, the tenant limit start and `claimed_from`;
  - for other periods, `eff` = the latest of the period window start and `claimed_from`;
  - if none applies, `eff` = the period start.

  On a forfeited row, this is the lawfully billable days that were given up with the rest, "so the cost is visible rather than silent".
- **Rule, the forfeiture isn't just recorded.** The included set is what delivery may post. A forfeited period isn't included (the "guard that records its enforcement instead of performing it" shape the round-1 trim had).
- **Attribute form.** `straddle_treatment` governs the **window** edge: `forfeit_whole` (Texas), `prorate_days`, or `include_whole`. The design turns the evidence CHECK into "forfeited amount between zero and the correction". **Open:** r7 also forfeits whole at the tenant-limit edge and at the claimed-start edge. The design doesn't say whether `straddle_treatment` governs those edges too.
- **Source.** R-32 (forfeit whole; the per-day split is an unauthorised estimation method under (v)(I); named revisit trigger: interval read data before the first AMI tenant's first bill run); R-37(d); R-25; R-23 as reshaped by R-32 (no trim).
- **r7.** 2682–2716; `forfeit_check` and `sign_check` 2603–2613.
- **Pinned by.**
  - F3: period 03-01..03-31 against window 03-10 is `straddles_window`, 22 days inside, 20.00 given up (M26).
  - F6: a favourable 12-01..12-31 against 12-15 is included whole, 17 days.
  - F8: `tenant_limit`.
  - F9: March forfeited against window 03-20.
  - F10: `straddles_claimed_start`.
  - F16, F17: evidence is DB-written and append-only (M25; now core-written, still append-only).
  - J2: the forfeitures surface shows only the governing evaluation's rows.

### 6.4 The enforceable bound travels with each period

- **Rule.** Each evidence row carries its rule's enforceable scope, meaning how far back collection (disconnection, refusal of service) may be pursued on what was billed:
  - `never` = never disconnectable (F-1);
  - `months N`;
  - `uncapped`;
  - `conditional` on `read_beyond_utility_control` (the R-30 three-bucket read classification, which is platform-fixed and never tenant-configurable).

  Carrying it onto the posted charge and into collections is delivery (-14) and Family 9's job (residual R8). For `estimation_catchup`, the classification has no path yet (residual R11). Where no basis is recorded, the scope is `never` (R-30).
- **Source.** R-20, R-30, F-1, R-39 (the additions are `never` pending counsel).
- **r7.** 2314–2315, 2713.
- **Pinned by.** F9 (`never`), C6.

### 6.5 Evidence not recorded by r7 that the rulings ask for

- **(v)(II) determination basis.** R-25 and R-23 require the evidence to record, for a (v)(II) (non-registering) cause, **which basis in the prescribed hierarchy** was used (like-period consumption by the same customer at the same location, else similar conditions or customers). r7 doesn't record it, because the amount is the caller's. **Disagreement D6.**
- **The R-36 marker.** R-36 requires the date-only marker to propagate to the evidence row, the audit trail and the customer-facing explanation. r7 records `governing_record_basis` on the evaluation, not on each period row, and has no customer-facing surface. Partial.
- **The estimated-bill marking.** R-23 notes a (v)(II) backbill is by definition estimated, so (6)(B)(viii)'s marking very likely applies. That belongs to delivery.

---

## 7. The evidence fence

### 7.1 What it is

- **Rule.** The fence is **the earliest moment the fault was on record**. It is the earlier of:
  1. the earliest `recorded_at` along the discovering test's correction chain **backwards**: the test, the test it superseded, and so on;
  2. the earliest `recorded_at` of **any** test on this meter that found it defective (`found_defective`), dated in `(anchor − 6 months, anchor]`.

  If the case has no test (a discovery cause), the fence is empty, and every "recorded no later than the fence" filter admits nothing.
- **Attribute form.** The "6 months" is hard-coded. Replace it with the widest `before_anchor` of the rules the case can resolve. Otherwise a 12-month rule would let a deployment forged between month 6 and month 12 through (audit §3.2).
- **r7.** `meter_correction_evidence_fence()` 2147–2169.

### 7.2 What it stops

It stops the forgery of the history a finding rests on. Deployments, removals and acquisitions count as evidence about a finding only if they were on record **no later than the fault was**. Otherwise the app could write, **after** the finding, facts that shorten a refund or excuse unbilled days:
- **A phantom predecessor meter or a late deployment** would move the window start later, shortening the refund (F5, FR-A).
- **A backdated removal of the fast meter**, written after the test directly or through `meters.status` (`sync_meter_deployments()` passes `removal_date` through), would turn the unbilled stretch into a "gap in service" (FR-D, O3). That's why `removal_recorded_at` is stamped (kept, §4 of the patch) and the fence compares that stamp, not the row's creation.
- **Re-pointing the case at a fresh, identical copy of its test**, which -12 allows as a superseding row with a new `recorded_at`, would move a fence keyed on the cited test's own `recorded_at` later. The fence therefore walks the chain back and also takes any earlier defective test (round 1, Opus F3 / Fable F4; FR-A).
- **An acquisition recorded after the finding** would validate a predecessor hold (FR-B).

### 7.3 Where the fence is read

| Use | Test applied | r7 |
|---|---|---|
| Deployment bound (§4.3) | `created_at ≤ fence` | 2243 |
| Corroborating predecessor (§4.3) | `created_at ≤ fence`; removal on record: `removal_recorded_at < fence` (strict), or if unstamped `created_at ≤ fence` | 2261, 2272–2273 |
| Uncovered days (§11.3) | the deployment state as it stood at the fence | 3218, 3241–3255 |
| Predecessor hold (§10.3) | the deployment's `created_at ≤ fence` and the acquisition's `recorded_at ≤ fence` | 3108, 3118–3119 |

**Why strictly before, for app-recorded removals.** `now()` is one instant per transaction, so a removal written in the same transaction as the test would tie with it (round 3, Fable; O3; M71). Owner-loaded rows keep ≤, because a history load and its test are routinely one transaction.

### 7.4 What it does not catch

- **Residual R6 / R16: a history fabricated *before* any defective test is recorded.**
  - It needs no write to `meter_deployments`. A phantom meter inserted with an old `start_date`, then set inactive with a chosen `removal_date`, becomes a closed predecessor row through `sync_meter_deployments()`.
  - Closing this needs the meter's own start and removal dates to become evidence, which is the meter lifecycle's patch.
  - A removal's *date* is still the caller's (residual R16).
- **Cost toward the customer.** A meter pulled on 05-01, bench-tested 06-15 and removed in Tally only afterwards leaves 05-01..06-14 uncovered. The case can't freeze until the owner repairs the removal (residual R6 COST).

---

## 8. The input fingerprint

### 8.1 What the evaluation depends on, as one document

- **Rule.** Each evaluation stores the full input document it was computed from, and a fingerprint of it (md5 of the canonical text in r7). The freeze (§11.2) recomputes the document and compares one value, rather than a list of checks that could fall out of step with the evaluation.
- **The document must cover:**
  - **Case:** case id, meter, cause, discovering test id **and whether it has been superseded (by which test)**, evidence fence, anchor date and basis, direction, `claimed_from`.
  - **Tenant:** service type, `regulatory_class_mode`, tenant limit months and start.
  - **Case-level rule:** the rule row id **and its version** (r7: `updated_at`; with dated immutable rule rows the id suffices), window shape and months.
  - **Governing test:** id, date, record basis, entered-out-of-order, prior-test-failed, absence.
  - **Supervisor gate:** whether it's required (§9.1).
  - **Window:** statutory start, deployment id and bound, whether corroborated, window start, period-set start.
  - **Periods:** for **each period**, the invoice, customer, location, start, end, billed units, class, rule id and version, jurisdiction level, window shape, period window start, enforceable scope and months.
- **Source.** R-38 (freeze when the evidence computed from the cause and anchor is frozen); R-38 attachment 1 (superseded, never deleted); audit rule 6 (every decision records its rule row).
- **r7.** `meter_correction_inputs()` 2178–2336 (the document 2318–2334); stored at 2537–2538.
- **Pinned by.**
  - I4: a legacy bill loaded after the freeze reads as stale.
  - I5: the stale evaluation refuses to freeze (M40).
  - I6: a late-entered test changes the fingerprint.
  - bM4: a corrected discovering test is carried in the document (M54).

### 8.2 What it must **not** leave out (traps)

- **Anything that moves the window or the period set moves the fingerprint.** That includes the **supersession** of the discovering test: round 1 froze a case on a test already corrected to accurate, because supersession wasn't an input (bM4; M53, M54).
- **Bills voided or issued since** change the period list: I4 and I5.
- **A test entered late** changes the governing test: D-5, I6.

### 8.3 What it deliberately does not cover

- **The submitted amounts.** They're stored on the evaluation itself.
- **Holds and approvals.** The freeze checks them separately (§11.2).
- **The tamper evidence.** It lives on the case, which a frozen case can't change.

Residual R12: the fingerprint is the canonical jsonb text. A server upgrade that changed that text would read every open evaluation as stale, which refuses freezes (the safe direction). The core must use its own deterministic serialisation.

---

## 9. Supervisor approval (R-36)

### 9.1 When approval is required

- **Rule.** An evaluation carries the R-36 gate when **all** of the following hold:
  1. the correction is **adverse** (case direction `customer_owes`);
  2. the governing prior test is **weak**: none at all, or `migrated_date_only`. An undeclared absence gates like `unknown`, because the gate is for evidence nobody vouched for;
  3. the months term still reaches back before the tenant's cutover, `anchor − 6 months < cutover_date`, **or** the tenant has no cutover date.

  After that point the gate **lapses on its own**, because a migrated date (always on or before cutover) can no longer affect the window (09-22 record §1).
- **Attribute form.** Condition 3's "6 months" is the resolved adverse rule's `before_anchor`. Condition 1 in r7 is also `cause = 'meter_error'`. The attribute form is "the resolved adverse window has a last-test term", because the gate protects a window whose start a weak prior test can move (residual R18).
- **Month-end arithmetic.** Condition 3 is stated as *anchor − months*, the **same** arithmetic as the window. It isn't written as *cutover + months*: at month ends the two aren't inverses (cutover 2026-08-31 + 6 months = 2027-02-28, but 2027-02-28 − 6 months = 2026-08-28), and the forward form lapsed the gate while a migrated date still set the window (-12 review round 1).
- **Source.** R-36 (the transitional gate), R-35 (refinements 2 and 5), 09-22 record §1.
- **r7.** 2329; -12 `meter_governing_test` 1600–1615.
- **Pinned by.**
  - G1: adverse, no prior test, anchor 2026-06-15, cutover 2026-01-15; 06-15 − 6 = 2025-12-15 < cutover, so gated.
  - G8: anchor 2026-08-20, reach 2026-02-20 ≥ cutover, so lapsed.
  - F7b: a refund never carries the gate.
  - F9: `non_registering_meter` isn't gated.
- **Disagreement D3 (residual R18).** R-36's text covers "an adverse correction anchored on migrated_date_only provenance, **or raised on a meter flagged attested_none or unknown**", with no cause qualifier. r7 gates only adverse `meter_error`, so an adverse `non_registering_meter` on such a meter isn't gated. r7's reasoning is that the (v)(II) window is fixed months from the test, so a weak prior test can't move it. That is an engineering reading awaiting Kyle. Also: R-36 says "the first six months after cutover"; r7's anchor-based form is the engineering equivalent that avoids the month-end drift above.

### 9.2 Who may approve

- **Rule.** An approval:
  - is for **one evaluation**, which must be the case's **latest** (G7; M33) and must carry the gate (otherwise there's nothing to approve);
  - requires the case to be **open**;
  - requires an approver who is:
    - **a supervisor**: a tenant_admin of the session's own tenant, or a platform administrator (G3);
    - **identified**: a user id is present;
    - **neither the case's opener nor the evaluation's author** (G4; M32). Approving one's own charge isn't an approval.
  - carries a note with at least one letter or digit.

  The approver and time are stamped by the database, and a caller-named approver is ignored (G5). Re-evaluating means the gate stands again: **an approval doesn't carry over** (G6).
- **Separation of duties.** Only a supervisor can make a supervisor. That rule is kept in the schema as access control (patch §2; A5–A8; M02).
- **Source.** R-36; r7 header on supervisors 427–438. Kyle names "supervisor approval" but doesn't define the separation. The not-opener/not-evaluator rule is an engineering reading.
- **r7.** `enforce_meter_correction_approval()` 2782–2841.
- **Enforcement.** The freeze refuses while a required approval is missing (§11.2; G2; M31).

### 9.3 The unknown-prior-test default (recorded refinement)

Kyle's 09-14 disposition note adopted "operator confirmation before an adverse charge lands" for an adverse correction with unknown prior-test status. R-35 and R-36 then refined it: fall through to the months term, behind the R-36 gate. §9.1 is that gate. After the transitional period, an adverse charge on a meter with no prior test needs no confirmation.

---

## 10. Holds

A hold is the **only** exception to the mandatory refund. It covers an in-window stretch for which **Tally holds no invoice on that meter**: the correction can't be computed from a bill Tally doesn't have. It is a hold, not a decline:
- it sits on a standing surface;
- it doesn't block the rest of the correction;
- it closes only by completing the correction or, for one code, by a gated unrecoverable closure.

### 10.1 Eligibility (both codes)

- **Rule.** A hold may be opened only if all of these hold:
  1. the case is **open**;
  2. the case's rule has `favourable_duty = 'mandatory'` **and** the case direction is favourable. r7 says `meter_error` + `customer_owed`; H1 refuses a hold on an adverse case (M34);
  3. the case has an evaluation, and the range lies **inside the latest evaluation's window**: `range_start ≥ window_start` and `range_end < anchor` (H5);
  4. **no day** of the range is billed in the §5.2 sense. A billed period is corrected from its bill, never held (H4, H4b; M35);
  5. the range doesn't overlap another hold of the same case, unless that one is **completed** (H8). This constraint stays in the schema. A completed hold covers nothing: its days are covered by bills, or by nothing if those bills are later voided (bM7; M58).
- **Self-lapse.** Once the whole window is billed in Tally, no stretch qualifies. The favourable direction then has **no decline path at all**, enforced by the condition, not by operators.
- **Source.** R-37(c).
- **r7.** 3053–3092.

### 10.2 Code `legacy_records_not_loaded`

- **Rule.**
  - The range must **end before the tenant's cutover date**, and the cutover must be set. The tenant billed that stretch before Tally, and the records exist in its legacy system (H6; M36).
  - It cites no acquisition.
  - It **cannot** close as unrecoverable (H10). It closes only by completion, when the records are loaded or the billed units entered.
- **r7.** 3094–3103.
- **Pinned by.** H7: a legacy hold on 2025-12-15..2026-01-14 covers the pre-cutover stretch, and the rest of the case freezes at once.

### 10.3 Code `predecessor_records_unavailable`

- **Rule.** Valid only if there is a deployment **of this meter** that:
  - covered the **whole** range (`install_date ≤ range_start`, and `removal_date` empty or `> range_end`);
  - at a location whose recorded **acquisition** by the tenant has `acquired_on > range_end`;
  - with the deployment's `created_at` ≤ fence and the acquisition's `recorded_at` ≤ fence (§7).

  The **system finds** the acquisition; the caller doesn't name it (H9). With no acquisition recorded it is refused (H3; M39). For days after the acquisition it is refused, because the tenant billed those (H3b).
- **r7.** 3104–3128. Acquisitions table 1357–1419 (kept; one per location, since small utilities buy part of a neighbour's system).

### 10.4 Closure

- **Rule.** Only an **open** hold closes, and nothing else on it changes (range, code, acquisition, opening). A closed hold is final (H14).
  - **Completed:** only when the range is now **fully billed** (§5.2) (H13; M38). The case should be re-evaluated so those bills are included (I5).
  - **Unrecoverable:** only for `predecessor_records_unavailable`, only by a **supervisor** (H11; M48), and only with an artifact reference containing a letter or digit **and** `counsel_referral = true` (H12). The counsel referral is for successor liability, R-37 counsel bundle item 3.
- **r7.** 3009–3051; the `unrecoverable_check` CHECK 2938–2942 stays in the schema.
- **Residual R13.** A hold's window is checked when it opens. A later re-evaluation with a shorter window leaves the hold partly outside it. It then counts toward coverage only for the days it covers, and closes on its own terms.

---

## 11. Freeze, unfreeze and withdrawal

R-38: the cause and the anchor freeze when the evidence computed from them is frozen. Changing either afterwards means **discard and recompute**, never editing around the evidence. R-38 is consistent with R-19: re-evaluating *is* R-19's "re-evaluate on every cause change" (header 54–58). Posting (-14) is the absolute lock.

### 11.1 Status transitions

| From | To | Rule | Pinned |
|---|---|---|---|
| open | frozen | §11.2 checks pass. The freeze pins the **latest** evaluation, and freeze stamps are set. The statement changes nothing else | G5, H7, I5 |
| frozen | open | Unfreeze. Allowed alone; clears the freeze stamps. The statement may change **nothing** the case froze | I2 |
| frozen | anything but open | Refused | I2 |
| open | withdrawn | Needs a reason. Refused per §11.4 | I10, I11 |
| withdrawn | anything | Refused: terminal. A new finding is a new case | I11b |

- **A status change carries nothing else.** A statement that changes the status may change only the status, its own stamps, the withdrawal reason and the notes. r7 checks this as a whole-row comparison, so a column added later is fenced by default (I13; bM2; M51).
- **The derived columns never move by hand, on any path.** This check has to run **before** the status branches. Round 1's fence sat after them, and `SET status='open', direction='customer_owes'` turned a fast meter's refund into a charge (bM1; M50).
- **The frozen evaluation must be the case's own and database-set** (I3). This is integrity, so it stays (design §1).
- **r7.** 1700–1792.

### 11.2 The freeze checks (open → frozen)

Refuse unless all of these hold, in r7's order:
1. The case has at least one evaluation (I1).
2. The discovering test hasn't been superseded (bM4). If it has, re-point the case at the correcting test and re-evaluate, or withdraw.
3. Recomputing the §8 document yields the **latest** evaluation's fingerprint exactly. Nothing it was computed from has moved: the cause, the test, the governing test, the deployments, a rule row, the tenant limit or class mode, or the billed periods (I4, I5, I6; M40).
4. If the latest evaluation carries the R-36 gate, an approval of **that evaluation** exists (G2, G6; M31).
5. If the case's rule has `favourable_duty = 'mandatory'` and the direction is favourable, **uncovered days = 0** (§11.3) (H2; M37).

- **Source.** R-36, R-37, R-38.
- **r7.** `meter_correction_freeze_check()` 3263–3314.
- **Residual R15, a checkpoint, not the last check.** The freeze locks the case row, not the world. A bill issued, a deployment entered or an unrelated test recorded at the same moment can slip past. Delivery **must re-derive the fingerprint and refuse a stale frozen case**.

### 11.3 Uncovered days (the under-reach check with no override)

- **Rule.** This applies to an evaluation whose case rule has `favourable_duty = mandatory`, whose direction is favourable, and which has a window start. Count the days `d` in `[window_start, anchor − 1]` where all three of these hold:
  1. **no period row of that evaluation** covers `d` (`period_start ≤ d ≤ period_end`);
  2. **no hold of the case that isn't completed** covers `d`. Open **and unrecoverable** holds count as cover; completed holds cover nothing (M57);
  3. `d` is **not in a recorded gap**, judged as the deployments stood **at the fence**. `d` is in a recorded gap only if **both** of these are true:
     - **no** deployment of the meter created at or before the fence is *in service* on `d`. In service means `d ≥ install_date`, **and** one of: no removal date; `d < removal_date`; the removal was recorded at or after the fence; the removal is unstamped and the row was created after the fence;
     - **some** deployment of the meter created at or before the fence has `removal_date ≤ d`, with that removal on record before the fence (strictly before if app-stamped; created at or before the fence if unstamped).

  **Days before the meter's first recorded deployment are never excused.** That deployment may be only the day the meter was entered into Tally. For any other case, the count is 0.
- **Freezing requires the count to be 0.** Every in-window day Tally billed is corrected. Every stretch it didn't bill is held with a validated code. There is no third option.
- **Source.** R-37 (no override in the favourable direction; under-reach detection counts the meter's readings), R-27 (the under-reach guard is `meter_error` only; unchanged by R-37 and R-39).
- **r7.** `meter_correction_uncovered_days()` 3199–3258.
- **Pinned by.**
  - H2: 31 in-window days Tally never billed; the freeze is refused.
  - O3: a backdated removal in the same transaction as the test doesn't excuse (M71).
  - FR-D: the fast meter pulled after its test with a backdated removal doesn't excuse.
  - bM7: voiding the bills that completed a hold reopens the gap.

### 11.4 Withdrawal

- **Rule.** A case whose rule has `favourable_duty = mandatory` can't be withdrawn while the **head of its discovering test's correction chain** still gives the favourable direction. The head is the latest row reached by following `supersedes_test_id` forward; r7 checks "the outcome is fast". A withdrawal would be the decline R-37 forbids.
  - If the test was wrong, supersede it with a row that doesn't find the meter fast. The case may then be withdrawn (I10, I11; M42).
  - The key is **what the test now finds**, not "a correction exists" and not the case's stored direction. A fast test "corrected" to a *faster* reading doesn't free the case (bM3; M52).
  - A period with no Tally bill is **held**, not withdrawn.
- **Source.** R-37.
- **r7.** 1772–1792.
- **Note.** Adverse cases and permitted-duty cases may be withdrawn freely. That is how the utility forgoes a correction to its own disadvantage ((v)(I); R-37(d)).

### 11.5 Tests cited by a frozen case

Kept in the schema (design §1): a test that a **frozen** case rests on can't be superseded until the case is unfrozen. That means its discovering test (I8), or its frozen evaluation's governing test (I7; M41). Unfreeze, correct the test, re-evaluate and freeze again (I9). The old window stays beside the new one in the evaluations.

**Lock order.** The meter's cases are locked before the meter on every path. r7 relies on trigger name order (`a0_…`), and a later trigger named earlier would re-open the deadlock (residual R15; FR-C1, FR-C2, FR-E). With evaluation in the core, the core's transaction must take the case lock before anything on the meter.

---

## 12. The void-and-reissue gate

R-33: *a bill computed wrong is not the same as a meter that measured wrong.* A meter error is corrected by an adjustment on a later bill, not by voiding and reissuing. Void-and-reissue stays correct where the bill itself was computed wrong. This gate is the reissue path's backbilling control. **It asks what the bill does, not what it's called.**

### 12.1 When the gate engages

- **Rule.** On an invoice's transition **into** an issued status (from a non-issued status), and never into `void`, the gate **matches** earlier bills. A bill matches if it belongs to the same tenant, is another invoice, has status `void`, and was **actually issued** (`first_issued_at` set). It also has to satisfy one of these:
  - it is the bill this one names in `replaces_invoice_id`; or
  - its period **overlaps** this one's (inclusive ranges), **and** one of:
    - this bill names a premise, and the voided bill has the **same premise**;
    - this bill names **no** premise, and the voided bill has the **same customer**;
    - the two bills **share a meter**: a line on each names the same meter.
- **Source.** R-22 (the regulated act is the charge, so the gate runs at issuance, not inside `void_invoice()`), R-33.
- **r7.** 1077–1081, 1120–1139.
- **Pinned by.**
  - D2: a "regular" bill charging more for voided days is refused.
  - bM8: shifted by a day, spanning two voided months, or addressed to another premise on the same meter; all refused (M59).
  - N3: no premise and no lines, $400 against voided $100, matched by the customer (M67).

### 12.2 Measuring "charges more": the scope of comparison

- **Rule, the charge measure.** A bill's charge is the **greater** of its line-item sum and its `amount_due`, used on **both** sides. Nothing ties the two fields (residual R9). The lines are the itemised content; `amount_due` is what posts. The greater of a voided bill's two figures is what the customer was exposed to.
- **Rule, whole-charge scope.** Used when the matched bill is the replaced bill, **or** this bill names a premise, **or** they share no meter. Compare this bill's charge with the voided bill's charge.
- **Rule, meter scope.** Used only when the matched bill is **not** the replaced bill, they **share a meter**, **and** this bill names **no premise** (a consolidated bill).
  - **new part** = the sum of this bill's lines on meters that are any of:
    1. **a meter on the voided bill**;
    2. **a meter at one of the voided bill's premises.** Those premises are its header premise, plus every location where its own meters were deployed during its period. In building that premise set, a removal counts only if **on record before the voided bill first went out** (S4 fix; Q7; M84). A meter is "there" if it was ever deployed at such a premise, unless its removal was on or before the new period's start **and** that removal was on record before the voided bill first went out (Q1, Q1b; M77, M78);
    3. **a meter not shown to serve one of this customer's premises during the new period.** It's "shown" only by a deployment at a location whose customer is this customer, overlapping the new period, with `created_at` **before the voided bill's `first_issued_at`** (Q3; M79, M80). Anything else could be anything, another tenant's meter included (residual R20).

    Add to that **the unattributed money**: lines with no meter, plus any `amount_due` above the line sum (O1).
  - **old part** = the sum of the voided bill's lines on meters that also appear on this bill.
- **Rule, what "increase" means.** This bill is an increase if its part exceeds the old part for **any** matched voided bill, not every one. A higher voided bill (a mis-keyed duplicate, or a decoy issued beside the live bill and voided with it) must not excuse a rebill of its neighbour's days (O2; M70).
- **No per-day proration.** It would let a cheap new month dilute an overcharge (declined, round 2).
- **Source.** An engineering reading of R-22, R-25 and R-39 ("a label standing in for an act"). The scope rules came out of review rounds 1–6.
- **r7.** 974–986 (the measure), 1083–1092 (the excess), 1145–1216 (scope and increase).
- **Pinned by.**
  - N2: a consolidated bill with the voided meter at the same $100 plus another premise's $80 issues (M66).
  - O1: at the voided bill's own premise, the whole charge counts: $60 + $90 on another meter, or $100 + a $300 meterless line, is refused.
  - P1: a bill naming the customer's other premise compares whole. With no premise, a second meter at the voided premise ($400) or a meter not the customer's ($150) is refused (M72, M74).
  - Q2: a voided bill with no premise is at the premises its meters stood at (M76).
  - FR-F1, FR-F2: the `first_issued_at` bound, in real time.

### 12.3 What an increase must be

- **Rule.** If this bill charges more for days already billed, refuse unless **all** of the following hold, in r7's order:
  1. It is `invoice_type = 'correction'` with a `replaces_invoice_id` (D2).
  2. A correction-run target on its run names the replaced voided invoice.
  3. That target records a cause (D3; M11), and the cause's rule has `delivery_path = 'reissue'`. r7 enforces "cause = `rate_misapplication`" with a CHECK on the target (D1; M08).
  4. If the rule has `units_invariant = true`:
     - it covers **the same period** as the replaced bill;
     - against **every other** voided bill it charges more than, **usage may not rise** (§12.4) (P4, Q4, Q5, Q6; M75, M81, M82, M83);
     - against the **replaced** bill, **usage matches exactly** (§12.4) (D4, D5, D9, Q8; M10).
- **Rule, reductions.** A reissue that reduces or holds the charge needs no cause (D6). A downward reissue is **not gated** (residual R3): it can't be told apart from a legitimate wrong-read correction.
- **Attribute form.** `delivery_path` and `units_invariant` replace the cause name.
- **The missing cap lookup.** r7's gate **never looks up a rule**, so it's uncapped by omission. The core must resolve the rule for the reissue's cause and apply its window terms, tenant limit and straddle treatment like any other correction. For Texas `rate_misapplication` (no terms) the result is identical. `enforce months 6` should also be recorded for the reissued charge (R-20). The core does not record it today.
- **Source.** R-33, R-39 ("correct units, wrong price"; "not a catch-all for billing errors"), R-19 (cause on the target).
- **r7.** 1219–1282.

### 12.4 The units tests

- **Group lines per meter.** Lines with no meter form their own group. Per group, compute:
  - summed `usage_quantity`;
  - summed `gas_ccf_used`;
  - summed `gas_therms_billed`. Therms are included because a wrong BTU factor is a `billing_constant_error`, not a price error;
  - **the count of lines whose `usage_quantity` is unknown.** A sum skips unknowns, so without the count a $300 line of unknown usage on the replaced bill's own meter matched (U fix; Q8a, Q8b; M85, M86).
- **Match** (against the replaced bill): the same groups on both sides, and each of the four values equal. A missing value equals only a missing value.
- **Not above** (against another voided bill): every group on the correction exists on the other bill. For each of the three quantities, known-ness agrees and the correction's value isn't greater. The unknown-line count isn't greater.
- **Why "not above" and not "match" against other bills.** Equality refused an ordinary misread-down-then-reprice lifecycle: 60u $120 → 50u $100 → voided → 50u $150 must issue (Q4). But skipping the replaced bill's lineage would launder a rise: 50u $100 → 100u $80 (downward, ungated) → 100u $200 must be refused (Q5).
- **Attribute form.** The quantity list is per service type (audit §3.2), not gas columns.
- **r7.** 997–1054.
- **Residual R10.** Sums per meter pass two bills with the same totals but different reads within the period.

### 12.5 The gate's stated refusals and gaps (residual R21, U4, U5)

The gate errs toward refusing. After a void, these ordinary bills are refused when they charge more than the voided bill:
- one spanning the voided month and a new one;
- a full-month bill after a short voided one;
- a consolidated bill with no shared meter covering more;
- a lawful correction ($100 → $150) that is itself voided and re-issued at $150. It needs its cause again;
- a consolidated parent re-summing a live correction of a voided bill.

Each of these is billed as a correction of the voided days instead.

**Not yet written into residual R21**, per the r7 header 220–224 and HANDOFF:
- **U4.** The customer leg reads `service_locations.customer_id` as it is **now**, which the app may rewrite. Reassigning a premise to the customer lets a meter with real history there carry an extra charge. Ryan's call is pending: state it, or fence it with a DB-stamped `customer_recorded_at`. HANDOFF recommends stating it.
- **U5.** Migrated bills carry historical `first_issued_at` but load-time deployment `created_at`, so legacy consolidated rebills are refused until the migration backdates deployments.

### 12.6 The target's cause freezes under a snapshot (kept)

Kept as integrity (design §1): once a calculation snapshot exists for the correction invoice, the target's `backbill_cause` can't change, along with its run, voided invoice and rate-date fields (D7; D8 shows an unrelated update passes; M12). This is R-38 on the reissue path, and the brief's F-4 decision: the freeze happens at the snapshot, not at post.

---

## 13. Customer class resolution (CCK-14) and rule selection (R-26)

### 13.1 Which class a customer is in

- **Rule.** The utility's `regulatory_class_mode` (kept; platform-set only, per A1, A2; M01) decides:
  - **`all_non_residential_protected`** (the v1 default): every customer is `protected`. This is right for any tariff with no size tier, and it fails toward protection.
  - **`explicit_class`**: `customer_type` in {residential, small_commercial, commercial} is `protected`; everything else is `unprotected`. A bare `commercial` reads as protected, the safe direction.
  - **`volumetric_threshold`**: **refuse**, "not implemented". It must never silently behave like the default. Its resolver is CCK-4…CCK-13: per meter, consecutive-period hysteresis, promotions pending review, and append-only determinations that protection decisions read.
  - A customer not visible in the session is refused.
- **Source.** CCK-14, CCK-2, CCK-3 (the resolver must never drive rates or `customer_type`), CCK-13 (insufficient history means protected), brief F-5 / Ryan 2026-09-22 decision 1.
- **r7.** `backbilling_customer_class()` 842–882.
- **Pinned by.** C8 (default protects `large_commercial`; `explicit_class` unprotects it and reads a bare `commercial` as protected; volumetric refuses).
- **Attribute form.** Classes become per-state vocabulary (`backbilling_customer_classes`; Texas gas: protected, unprotected). The mode names stay Texas-shaped until the class resolver patch (design §1 residual).
- **Residual R19.** The class is read **as of now**, not as of the period. It's constant under the default mode. Under `explicit_class`, a reclassified customer changes an evaluation's per-period rule and its fingerprint.

### 13.2 Which rule row applies

- **Rule, r7's form.** For (tenant, jurisdiction, service type, class, cause), take the row for the **premise's jurisdiction** if one exists, else the default row with no jurisdiction. That's two levels, most specific wins. If **no row** resolves, **refuse**: a missing rule is never permission (C7). A premise with no jurisdiction falls to the default row, which is the fail-toward-protection direction (R-26 rationale 4).
- **Rule, the new form (design §3, audit rule 3).**
  - Look up by `(state_code, service_type, customer_class, cause)` in force on the rule date.
  - The **state comes from the premise**, never from the utility (audit rule 1).
  - The lookup **refuses when no row is in force**; there is no default.
  - The evaluation and each evidence row record the rule row used.
- **Open points (design §5).**
  1. City-level rules (R-26): state-level now, and a place key when the places table lands. No Texas city override is seeded.
  2. **Which date picks the rule row**: each period's start, the anchor, or the correction date. That's for Kyle. The evidence records the row per period either way.
- **Source.** R-26, R-20.
- **r7.** `backbilling_resolve_cap()` 887–919.
- **Pinned by.** C6 (a municipal 4-month row wins at City A; City B falls to the default 6), C7.

### 13.3 The period set uses the widest window

- **Rule, r7.** The case-level rule, which sets **which periods are evaluated**, always asks for the **protected** class at the premise in `meters.location_id` (the meter's current premise). The assumption is that protected has the widest reach. Each period then answers to its own rule (§6.1).
- **Rule, the attribute form.** The period set starts at the **earliest** window start across every class and place whose rule could apply to the meter's periods, using the same terms as §4.1. The audit's phrasing: "start from the widest window across the classes that could apply".
- **Residual R5.** A municipal rule **longer** than the state default, at a premise the meter has since left, wouldn't widen r7's set. That's under-reach in a case no tenant has yet. r7 also reads the case-level place from `meters.location_id`, a label the app writes. The per-period place comes from the invoice's premise.
- **r7.** 2215–2225.

---

## 14. Standing surfaces: the R-27 / R-37 fast-finding surface and case status

### 14.1 Fast findings with no case

- **Rule.** List every **standing** (not superseded) test whose outcome is fast, with **no live case** (not withdrawn) resting on it. Not opening a case is the quietest way to decline a mandatory refund, and no guard can refuse an act that never happens. So it's surfaced instead.
- **Columns:** test id, meter, test date, record basis, the largest error %, recorded at, days since the test.
- **Attribute form.** Tests whose outcome qualifies for a cause whose rule has `favourable_duty = 'mandatory'` and gives the favourable direction.
- **Source.** R-27 ("detection without a surface" keeps the cost and discards the benefit; calling it out *is* the control), R-37, R-35 refinement 1 (standing surfaces, not one-off reports).
- **r7.** View `meter_fast_findings_without_case` 3506–3520 (dropped).
- **Pinned by.** bM12 (a fast test with no case is listed; one with a case, or since corrected, isn't; M63).

### 14.2 What the kept views need from the core

Two views stay (design §1), but one of them calls dropped code:
- **`meter_correction_case_status`.** It calls `meter_correction_evaluation_current()` (r7 3393–3413, which recomputes the inputs) and `meter_correction_uncovered_days()`. Both are evaluation. The core must supply "is the governing evaluation still current?" and "uncovered days". It could write them as columns on a status record, or the view could read the core's latest recorded result.
  - The case-status contract (r7 3448–3449): the governing evaluation is the frozen one if frozen, else the latest. A **frozen** case whose evaluation is no longer current is **stale** and must be unfrozen and re-evaluated before delivery can post it (I4).
  - The view also reports a pending R-36 approval, `prior_test_failed`, `entered_out_of_order`, open holds and the forfeited total (J3).
  - Where a case can't be recomputed at all, r7 shows "cannot tell" (empty) rather than failing the whole surface.
- **`backbilling_forfeitures`** (J2) and **`meter_correction_open_holds`** (J1) are plain reads.

The design doc's §2 drop list doesn't mention `meter_correction_evaluation_current()`. It goes with the case-status change above.

---

## 15. Failed approaches: do not re-implement

Each of these was built or proposed, measured, and rejected. Most were caught by a battery case, a mutation or a race check.

| Approach | Why it failed | What replaced it | Evidence |
|---|---|---|---|
| **Fable's `voided_at` bound** for the meter-scope legs (round 5) | `voided_at` is the database clock, but the **caller picks the moment** of the void. Insert a deployment, then void, and the deployment reads as prior | The voided bill's **`first_issued_at`**, DB-stamped and write-once | FR-F1 fails under `voided_at`; HANDOFF |
| **Fable's lineage skip** (round 5): don't apply the units test to the replaced bill's own lineage | It re-admits a units rise laundered through a downward reissue: 50u $100 → 100u $80 → 100u $200 | "Usage may not rise" against every voided bill the correction doesn't replace | Q5; M81 |
| **Opus's `meters.location_id` legs** (round 5) | Redundant with the deployment legs, so a mutation removing them went uncaught. And `location_id` is a **label** the app writes: one UPDATE made another customer's meter "the customer's" (Fable) | Read deployments only, bounded by `first_issued_at` | M79 (label reinstated) is caught by Q3; HANDOFF |
| **Fable's `service_locations.updated_at` bound for U4** | Any address edit would refuse legitimate rebills | Open: state U4, or a DB-stamped `customer_recorded_at` | HANDOFF |
| **Round-1 trim**: record "forfeited" and issue the bill at the full delta | A guard that records its enforcement instead of performing it. R-32 also found the per-day trim has no fixed point ($31 → $18 → $10.45) | Whole-period forfeiture; the included set is what may post | r7 header 74–77; R-32 |
| **Per-day proration in the reissue gate** (proposed round 2) | A cheap new month dilutes an overcharge | Scope comparison, whole charges or shared meters | r7 1111–1112; residual R21 |
| **"More than EVERY matched voided bill"** (round 2) | One higher voided bill (a duplicate or a decoy) excused a rebill of its neighbour's days | "More than ANY" | O2; M70 |
| **Exact-period, same-location match** (round 1) | A one-day shift, a spanning bill, another premise or a consolidated bill re-billed voided days | Overlapping days by premise, shared meter, or (no premise) customer | bM8; M59 |
| **Whole-bill comparison across different scopes** (round 1) | A consolidated bill carrying the voided meter at the same price was refused, and one with no lines and no premise got through | Compare at the scope matched | N2, N3 |
| **Meter scope at the same premise** (round 2) | The extra rode on another meter's line or a meterless line | The same premise compares whole charges; meterless money counts as unattributed | O1 |
| **Meter scope keyed on "another premise" on the header** (round 3) | The header is the caller's choice; naming the customer's other premise re-opened the leak | Meter scope only for a bill with **no** premise | P1; M72 |
| **Units test read only against the replaced bill** (round 3) | A correction addressed to another premise increased against that premise's voided bill with other units | Test every voided bill it exceeds | P4; M75 |
| **Units equality against non-replaced bills** (round 4) | It refused misread-down-then-reprice | "May not rise" | Q4; M83 |
| **"A meter at the voided premise" read from a deployment overlapping the new period only** (round 4) | A backdated removal, a meter onboarded today, or an inactive meter escaped | "Ever deployed there, unless a removal on record before the voided bill went out" | Q1, Q2 |
| **Reading removals of a no-premise voided bill's meters raw** (round 5) | One backdated removal of the shared meter emptied the voided bill's premises (S4) | Honour a removal only if on record before `first_issued_at` | Q7; M84 |
| **`sum()` alone in the units tests** (through round 5) | A sum skips unknown usage, so a $300 line of unknown usage matched | Also count unknown-usage lines | Q8; M85, M86 |
| **Fencing on the cited test's own `recorded_at`** (round 1) | Re-point the case at a fresh identical copy of the test and the fence moves later | Earliest point on record: walk the chain back, and take any defective test within reach | FR-A |
| **Not stamping removals; comparing only the row's creation time** (through round 1) | A removal is a later write on an old row. Pulling the fast meter after the test with a backdated date made the stretch a "gap" | `removal_recorded_at`, DB-stamped | N1; FR-D; M64, M65 |
| **`<=` for app-recorded removals against the fence** (round 2) | A removal written in the test's own transaction ties on `now()` | Strictly before for app-stamped removals | O3; M71 |
| **Honouring an uncorroborated deployment start for refunds** (first draft) | It is the onboarding date on every migrated meter, so it ended refunds at go-live | Corroboration (§4.3) | F7c; M29 |
| **Any predecessor corroborates** (round 1) | A meter removed years ago corroborated every later onboarding date | The predecessor must have served into the window | bM6; M56 |
| **Refusing an adverse correction when no prior test exists** (round-1 draft) | Wrong on the merits: under-collects with no regulatory basis | The months term governs alone, behind the R-36 gate | R-35 refinement 5; F1 |
| **R-22/R-27 override with free text, then the three reason codes** (`no_read_history`, `meter_replaced`, `records_predate_acquisition`) | They decline a duty (v)(I) doesn't let the utility decline. Two were misclassified; the third was almost always false | No favourable override; the computed bound, meter-scoped targeting and two validated hold codes | R-37 |
| **Tenant-editable cap rows** (round-1 draft) | A tenant could uncap its own six-month `meter_error` row | Platform-held law; the tenant's shorter limit is separate | C1, C2; M07 |
| **R-36 gate stated as cutover + 6 months** (-12 round 1) | At month ends it isn't the inverse of anchor − 6 months, so it lapsed while a migrated date still set the window | Anchor − months, the same arithmetic as the window | §9.1 |
| **Direction fence after the status branches** (round 1) | `SET status='open', direction='customer_owes'` flipped a refund into a charge | Fence first; a status change carries nothing else | bM1, bM2; M50, M51 |
| **Withdrawal keyed on "a correction exists" or on the case's direction** (round 1) | A fast test "corrected" faster satisfied it; a hand-flipped direction escaped | Read the head of the test's chain | bM3; M52 |
| **Completed holds counting as cover and blocking re-holds** (round 1) | If the completing bills are voided, the days need holding again | Completed covers nothing and doesn't exclude | bM7; M57, M58 |
| **FOR SHARE handshake taken after the meter lock** (round 1) | "Lock a case, then record a test on its meter" deadlocked | Cases before the meter, on every path | FR-E; residual R15 |
| **Treating "Texas-only launch" as licence to hardcode Texas law** | It went into CHECK lists and trigger branches, and a second state became a redesign | Per-state, dated, platform rule rows | HANDOFF; audit |
| **Open-ended adversarial review against the app role** | Six rounds on one function, each finding a narrower path | A stopping rule (proposed, unconfirmed): block easy single-step mistakes, and write deliberate multi-step manipulation up as a known limit | HANDOFF |

---

## 16. Code-versus-ruling disagreements and open points

**Disagreements (code and ruling differ):**
- **D1.** The (v)(II) non-registering anchor. R-19 and R-20 say "from discovery"; r7 uses the discovering test's date with basis `test_date` (§2.4).
- **D3.** R-36's gate. The ruling covers adverse corrections on `attested_none`/`unknown` meters with no cause qualifier. r7 gates adverse `meter_error` only (residual R18). r7 also gates "no test at all" including `undeclared`, which is broader than the text (§9.1).
- **D5.** Zero on adverse periods. r7 refuses a zero amount on **adverse** test-anchored periods too. (v)(I) lets the utility forgo a correction to its own disadvantage, and (v)(II) is permissive. r7 allows forgoing only by withdrawing the case or through the tenant limit, not period by period. No ruling requires refusing an adverse zero (§6.2).
- **D6.** The (v)(II) determination basis. R-25 and R-23 require the evidence to record which (v)(II) basis was used; r7 doesn't (§6.5). Partial on R-36's marker propagation too.

**Design gaps the core needs filled (not disagreements):**
- **D2.** A rule attribute for **qualifying test outcomes**. **Resolved 2026-09-28:** `backbilling_rules.qualifying_test_outcomes` (Texas: `meter_error` {fast, slow}; `non_registering_meter` {non_registering}); battery C13, C14.
- **D4.** Whether `straddle_treatment` also governs the tenant-limit and claimed-start edges (§6.3).
- **D7.** The reissue gate resolves no rule today (§12.3). With the core it must, and it should record `enforce months`.
- **D8.** `delivery_path` has no value for `estimation_catchup`'s "ordinary next bill", nor for `unbilled_service`'s "new charge". Both are OQ-1.
- **D9.** `deployment_start` needs the corroboration rule for the favourable direction. That is an engineering reading still before Kyle (OQ-1 brief).
- **D10.** The kept view `meter_correction_case_status` depends on two dropped functions (§14.2). **Resolved 2026-09-28:** the view was rewritten without them; the fingerprint check and uncovered days are the core's surface.

**Still open elsewhere:**
- OQ-1: delivery per cause.
- Design §5: city-level rules; which date picks the rule row.
- U4 and U5.
- Counsel bundle: R-28's (4)(E)(vi) closing clause; R-29's anchor; R-30's four ambiguous read codes; who tampered; the R-39 additions' enforceability; successor liability.
- R-32's revisit trigger (interval data).
- CCK-15 (early promotion).

---

## 17. Index: dropped object → section

Line numbers are r7 (`570d437`).

| Dropped object | r7 lines | Section(s) |
|---|---|---|
| `enforce_meter_correction_case()`: UPDATE fences, status transitions | 1700–1792 | §11.1, §11.4 |
| — the test finding keeps its cause; the cause-change reason | 1801–1815 | §3.1, §3.2 |
| — INSERT fences | 1817–1830 | §2.4, §2.8 |
| — discovering-test checks (same meter, not superseded, same-day opposite) | 1833–1865 | §2.2 |
| — test-anchored derivation (outcome, anchor, direction, readings) | 1867–1905 | §2.3, §2.4, §2.5 |
| — discovery-cause checks | 1906–1919 | §2.6 |
| — the tamper gate | 1921–1973 | §3.3, §3.4 |
| `meter_correction_cases_shape_check` | 1523–1529 | §2.4, §2.6 |
| `meter_correction_cases_tamper_check` | 1542–1550 | §3.3 |
| `meter_correction_cases_cause_check` (five causes) | 1515–1516 | §2.1 |
| `meter_correction_billed_periods()` | 2103–2132 | §5.1 |
| `meter_correction_evidence_fence()` | 2147–2169 | §7 |
| `meter_correction_inputs()` | 2178–2336 | §4, §5.1, §6.1, §8 |
| `enforce_meter_correction_evaluation()` | 2418–2541 | §6.2, §8.1, §11.2 (open-only) |
| `meter_correction_evaluation_after()` | 2659–2727 | §6.3 |
| `enforce_period_evidence_written_by_evaluation()` | 2626–2639 | §6.3 (evidence is now written by the core; stays append-only) |
| Evidence `forfeit_check` (forfeit whole) | 2603–2609 | §6.3 |
| `backbilling_customer_class()` | 842–882 | §13.1 |
| `backbilling_resolve_cap()` | 887–919 | §13.2, §13.3 |
| `enforce_meter_correction_approval()` | 2782–2841 | §9.2 |
| `enforce_meter_correction_hold()` | 2991–3135 | §10 |
| `meter_correction_range_billed()`, `…_range_fully_billed()` | 2966–2989 | §5.2, §10.1, §10.4 |
| `meter_correction_uncovered_days()` | 3199–3258 | §11.3 |
| `meter_correction_freeze_check()` | 3263–3314 | §11.2 |
| `meter_correction_evaluation_current()` (not in design §2; follows from it) | 3393–3413 | §14.2 |
| `enforce_backbilling_gate_issue()` | 1059–1286 | §12.1–§12.3 |
| `backbilling_invoice_charge()` | 974–986 | §12.2 |
| `backbilling_units_match()` | 997–1020 | §12.4 |
| `backbilling_units_not_above()` | 1031–1054 | §12.4 |
| `correction_run_targets_backbill_cause_check` (`rate_misapplication` only) | 964–969 | §12.3 (becomes a foreign key to causes; the path comes from `delivery_path`) |
| `seed_backbilling_cap_defaults()` and its every-tenant DO block | 766–834 | §1.1 |
| `backbilling_cap_rules` (replaced by platform tables) | 685–759 | §1, §1.1, §13.2 |
| View `meter_fast_findings_without_case` | 3506–3520 | §14.1 |
| -12 `meter_governing_test()` (landed; not dropped, but evaluation) | -12: 1544–1618 | §4.2, §9.1 |
| Header rationale, round-by-round folds | 1–273 | §15 |
| §15 residuals R1–R21 | 3550–3745 | cited inline; R1 §3.5; R2 §6.2; R3 §12.3; R4 §13.2; R5 §13.3; R6 §4.3/§7.4; R7 §9.2; R8 §6.4; R9 §12.2; R10 §12.4; R11 §6.4; R12 §8.3; R13 §10.4; R14 §14.2; R15 §11.2/§11.5; R16 §7.4; R18 §9.1; R19 §13.1; R20/R20a §5.1/§12.2; R21 §12.5 |
