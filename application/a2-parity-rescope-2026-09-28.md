# A-2 re-scoped to parity — design (2026-09-28)

**Decision (Ryan, 2026-09-28):** re-scope A-2 (`sql/v5.4.2-13-backbilling-caps.sql`, unmerged) to parity.
- **Parity** means the schema can *represent* the backbilling invariant (CI-008, CI-092) and its configurable parts, and it protects record integrity.
- **Rule evaluation** belongs to the C# calculation core, which isn't written yet. Evaluation here means computing the window, deciding forfeitures, deciding who must approve, and deciding which causes may be reissued.

Background: [texas-only-architecture-audit-2026-09-28.md](texas-only-architecture-audit-2026-09-28.md) §6.

**The test for every object in the patch:** does it *store or protect a record*, or does it *decide what the law requires*? The first stays. The second becomes scenario material for the core, so nothing Kyle ruled is lost.

---

## 1. Keep (stores or protects a record)

| Object (r7 section) | Why it stays | Change |
|---|---|---|
| `tenants.backbilling_adverse_limit_months` (§1) | The utility's own tariff limit: tariff data | None |
| `tenants.regulatory_class_mode` and its platform-only guard (§1) | How this utility's tariff draws "small commercial" is utility data. Who may change it is access control (Ryan, 2026-09-22) | Comment loses the §7.45 wording. The mode names stay Texas-shaped until the class resolver patch (CCK-4…13); stated as a residual |
| Supervisors: only a supervisor makes a supervisor (§2) | Access control on `users`, not law | None |
| Composite keys and the `jurisdiction_id` repair (§3) | Integrity: a premise can't point at another utility's city | Comment: rules no longer resolve through it |
| Deployment hardening: meter, location and install date fixed; removal written once; `created_at` stamped (§4) | Integrity of the history the core will read | None |
| `service_location_acquisitions`, append-only, stamped (§7) | A record | None |
| `meter_correction_cases` (§8) | The record of a finding about a meter | Cause becomes a foreign key to a causes table. The cause-coupled checks go (see §2). Evidence columns keep an internal-consistency check only |
| `meter_correction_case_events`, written by the database, append-only (§8) | Audit trail | None |
| `meter_correction_evaluations` and `meter_correction_period_evidence`, append-only (§9) | The record of what the core decided, and which rule row it used | Written by the core, not by a trigger. The rule reference points at the platform rule table. The "forfeit the whole amount" check (Kyle's R-32 as a CHECK) becomes "forfeited amount between zero and the correction" plus the rule's straddle treatment |
| `meter_correction_approvals`, append-only, stamped with the session user (§10) | The record that someone approved | Who must approve, and whether approval is needed, move to the core |
| `meter_correction_holds`, the no-overlap constraint, status and closure fields (§11) | The record of a hold | Eligibility (which causes and directions may hold) and the "range is billed" checks move to the core |
| A frozen case can't change; its frozen evaluation must be its own (§8/§12) | Integrity: *frozen* has to mean frozen | A small trigger replaces the 300-line case trigger's whole-row fence |
| A test that a frozen case cites can't be superseded (§13) | Integrity of the frozen record's references | None |
| The snapshot binding on `correction_run_targets.backbill_cause` (§6, from -10) | Integrity: a checked snapshot's inputs don't move | `backbill_cause` becomes a foreign key to causes, not `rate_misapplication` only |
| Views `meter_correction_case_status`, `backbilling_forfeitures`, `meter_correction_open_holds` (§14) | Plain reads over the records | Track the renamed columns |

## 2. Drop (decides what the law requires; becomes core scenarios)

| Object | What it decided | Ruling |
|---|---|---|
| `enforce_meter_correction_case()`, ~300 lines | cause from test outcome; direction from outcome; allowed cause changes; the tamper supervisor gate; the fast-meter "no withdrawal" duty | R-19, R-37, R-38, R-39 |
| Case `shape_check` and `tamper_check` | test-anchored causes; tampering needs evidence and approval | R-38, R-39 |
| `meter_correction_billed_periods`, `meter_correction_evidence_fence`, `meter_correction_inputs`, `enforce_meter_correction_evaluation`, `meter_correction_evaluation_after`, `enforce_period_evidence_written_by_evaluation` | the window, the periods, the forfeitures, the input fingerprint, the evidence fence (with its "6 months") | R-25, R-32, R-34…R-37 |
| `backbilling_customer_class()`, `backbilling_resolve_cap()` | customer to class; rule selection | CCK-14, R-26 |
| `enforce_meter_correction_approval` | the approver is a supervisor, and not the opener or evaluator | R-36 |
| `enforce_meter_correction_hold`, `meter_correction_range_billed`, `…_fully_billed` | hold eligibility; range checks | R-37(c) |
| `meter_correction_uncovered_days`, `meter_correction_freeze_check` | freezing needs full coverage and a matching fingerprint | R-37, R-38 |
| `enforce_backbilling_gate_issue`, `backbilling_invoice_charge`, `backbilling_units_match`, `backbilling_units_not_above` | the reissue gate: an upward rebill must be a rate misapplication with the same units | R-33, R-39 |
| `seed_backbilling_cap_defaults` and its every-tenant DO block | Texas rows per utility | R-20 |
| View `meter_fast_findings_without_case` | "a fast meter owes a refund", as a report | R-27, R-37 |

Each of these is written up as rules for the core in `a2-rules-for-the-core.md`, with its ruling and the r7 battery cases that pinned it. The 146-test battery, the 84 mutations and the concurrency tests stay in git history as the source for those scenarios.

## 3. Change: the rule table becomes platform-held law

`backbilling_cap_rules` (per utility, no dates) is replaced by the following.

**`backbilling_causes`** (platform vocabulary; no `tenant_id`; read-only to the app):
- `cause_code`, `description`.
- Seeded with the eight R-39 causes.
- The table names causes only. What a cause *does* in a given state lives on the rule row.

**`backbilling_customer_classes`** (platform vocabulary, per state):
- `(state_code, service_type, class_code)`, `description`, `source_note`.
- Texas gas seeds `protected` (residential and small commercial) and `unprotected`.
- Another state seeds its own classes.

**`backbilling_rules`** (platform law, the `meter_accuracy_thresholds` template):

| Column | Meaning |
|---|---|
| `state_code`, `service_type`, `customer_class`, `cause` | The key. The class is a foreign key to that state's classes; the cause is a foreign key to causes |
| `effective_from`, `effective_to` | No overlap per key (EXCLUDE) |
| `anchor_basis` | `test_date` / `discovery_date`, plus later kinds such as `notice_date` |
| `favourable_duty` | `mandatory` / `permitted`: must the utility refund back to the window? |
| `straddle_treatment` | `forfeit_whole` / `prorate_days` / `include_whole`, for a period that crosses the window edge |
| `delivery_path` | `adjustment` / `reissue` / `unruled`. Kyle's OQ-1 is still open, so most causes start as `unruled` |
| `requires_supervisor_evidence` | Does moving a case to this cause need evidence and a supervisor? (Texas: tampering) |
| `units_invariant` | Must a correction under this cause keep the original units? (Texas: rate misapplication) |
| `enforce_scope`, `enforce_months`, `enforce_condition` | What collection may pursue: `uncapped` / `months` / `never` / `conditional`. The condition comes from a general vocabulary (`read_beyond_utility_control`) |
| `source_note` | Required citation |

**`backbilling_rule_window_terms`** (child of a rule):
- `(rule_id, direction, term_kind, months)`, where direction is `adverse` or `favourable`.
- A window's start is the **latest** of its terms' dates. No terms means uncapped in that direction.
- `term_kind` comes from a general vocabulary:
  - `months_before_anchor`
  - `last_test_any_outcome`
  - `last_test_accurate`
  - `half_since_last_test`
  - `deployment_start`
  - `service_start`

**Texas gas seed** (R-20 amended by R-39): each Kyle row becomes a rule row with its terms and citations, effective 2004-07-12, the date -12's threshold row uses for the same rule text. Examples:
- `meter_error`, protected: adverse terms `months_before_anchor 6` + `last_test_any_outcome` + `deployment_start`; favourable terms the same; `favourable_duty = mandatory`; `straddle = forfeit_whole`; `enforce = never`.
- `rate_misapplication`: no adverse terms (uncapped); `units_invariant = true`; `delivery_path = reissue`; `enforce = months 6`.
- `tampering_bypass`: uncapped; `requires_supervisor_evidence = true`; `enforce = uncapped`.
- `unprotected` class: every cause uncapped.

**The ZZ check:** the battery seeds a fictional state `ZZ` with different rows. It must *store* a 12-month window, a refund-reach term, proration, and a customer class Texas lacks, without a schema change. That is parity's proof that nothing is Texas-only.

## 4. What the database still refuses

These are integrity only:
- rows from another utility;
- editing or deleting evaluations, evidence, approvals, events or acquisitions;
- changing a frozen case;
- a frozen case pointing at another case's evaluation;
- superseding a test that a frozen case cites;
- overlapping open holds;
- a rule row without a citation, or overlapping another for the same key;
- app writes to the law tables;
- a cause or class that doesn't exist;
- timestamps and actor ids supplied by the caller: they are stamped.

It no longer decides whether a correction is lawful. The core does, and the evaluation row records which rule row it used.

## 5. Open points

1. **City-level rules (Kyle's R-26):** a city with original rate authority overriding the state rule.
   - A platform law table can't point at `jurisdictions`, which is per utility.
   - **Recommend:** state-level rules now, and add `place_id` when the places table lands.
   - No Texas city override is seeded today, so nothing is lost meanwhile.
2. **Rule date:** which date picks the rule row — each period's start, the anchor, or the correction date? That's for Kyle. The schema can store the answer either way, because evidence records the rule row per period.
3. **Delivery (OQ-1)** stays open. `delivery_path = unruled` represents it honestly.

---

## 6. As built (2026-09-28)

`sql/v5.4.2-13-backbilling-caps.sql` has been rebuilt to this design: 2,150 lines, down from r7's 3,757. The r7 draft is commit `570d437`.

**Changes from the design above:**
- **`qualifying_test_outcomes`** is on `backbilling_rules`. A test-anchored rule names the test outcomes that make a finding its cause (R-39); a discovery rule names none. Found by the rules-for-the-core write-up (its D2).
- **Two small consistency checks:**
  - an evaluation's rule row must be a rule for the evaluated cause;
  - an evidence row's rule must be for that period's class and the evaluation's cause.
- **Evidence only in its evaluation's transaction:** `evaluations.recorded_txid` is stamped, and evidence inserts compare it to the current transaction.
- **`partly_forfeited`** is a disposition, so a state that prorates fits. Its dollars must be strictly between none and all.

**Verified on a clone of the -12 build:**
- Strict apply (`search_path = ''`, `check_function_bodies = on`) runs clean twice. The second run inserts nothing.
- `tests/v5.4.2-13/battery-13.sql`: 79 checks, all PASS. That includes group Z, the fictional state ZZ stored with no DDL.
- `evidence-txn-13.sh`: X1 PASS.
- `mutations-13.py`: 25 of 25 mutations caught.
  - One is caught when the patch's own tenant-isolation assertion refuses to apply.
  - One surfaces at H7 rather than H5, because other guards also refuse the edit it targets.
  - Two real defects were found and fixed while building: a NULL-leg hole in the evidence and hold-artifact CHECKs, and the law-history trigger reading `effective_to` on the terms table.
- Earlier batteries are unchanged: -09 28, -10 58, -11 41, -12 116.

**Not done:**
- Not mirrored into `tu.sql`.
- Not sent for review.
- Both wait on Ryan. The Kyle questions below may change seed rows but not the schema.

**For Kyle:**
- **Which date picks the rule row** (§5.2).
- **The unprotected class** (patch residual R9): r7 applied the fast-meter refund duty and the tamper gate to every class; the rows now follow R-20 (unprotected = outside §7.45).
- **The rules-for-the-core disagreements D1, D3, D5 and D6:**
  - D1: the non-registering anchor (discovery vs test date);
  - D3: the scope of R-36's gate;
  - D5: whether an adverse zero amount may be refused;
  - D6: recording the (v)(II) estimation basis.
