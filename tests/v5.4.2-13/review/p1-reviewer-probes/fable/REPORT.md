# Review P1 — v5.4.2-13 parity re-scope (Fable)

Patch `sql/v5.4.2-13-backbilling-caps.sql`, md5 `07ced77c92311ae73ffd3f19623ca4f9` (verified). Database `rv_a` in `tally-pg` (PostgreSQL 16.14). Frozen battery run on `rv_a` as a baseline: **79 PASS, 0 FAIL**. Every probe below ran inside one transaction that was rolled back; nothing in `rv_a` was changed.

Repro files (this directory):
- `00-fixtures.sql` — the battery's own fixture block (battery-13.sql lines 28–137), copied verbatim.
- `10-probes.sql`, `11-probes-redo.sql` — the probes. `run-probes.sql` / `run-probes-redo.sql` = fixtures + probes + `ROLLBACK`.
- Run: `docker exec -i tally-pg psql -U tally -d rv_a -v ON_ERROR_STOP=1 -q -f - < run-probes.sql 2>&1 | grep OBSERVED`
- Captured output: `probes-output.txt`, `probes-redo-output.txt`.

## Verdict: **not yet** — one blocker, small fix

**Blocking:** F-1 (Q2, HIGH). A law row that an evaluation already cites can have its *window* changed after the fact: the history trigger fences UPDATE and DELETE on `backbilling_rule_window_terms` but not INSERT, so a new term can be added to an in-force, cited rule row. That contradicts design §4 / residual R7 ("a law row is never edited — for the owner too") and the claim evaluations rest on ("rule rows never change, so this citation stays true"). The fix is a few lines.

Recommended in the same revision: F-2, F-3 (Q2, MEDIUM). Everything else is LOW or a Q1 design note Ryan can accept as stated.

**Texas-literal check: clean.** Every `TX` / cause-name literal is in the section 5 seed DO block (data) or an error message. No trigger branch or CHECK keys on a state, cause or service name. The CHECK-bound vocabularies (`anchor_basis`, `enforce_condition`, `term_kind`, straddle, delivery) are general, not Texan — but see F-Q1-1.

---

## Findings — Q2 PROTECT

### F-1 · HIGH · Q2 · A cited law row's window can still change (term INSERT is unfenced)
- **Where:** `sql/v5.4.2-13-backbilling-caps.sql:703-738` (`enforce_backbilling_law_history`, BEFORE UPDATE OR DELETE only); terms table `:666-690`.
- **Repro:** `10-probes.sql` P1, P1b (owner session).
- **Observed:**
  ```
  P1  OBSERVED: owner added a window term to a CITED rule row (terms 6 -> 7); the evaluation's rule_id now names a different window
  P1b OBSERVED: an uncapped direction of an in-force rule became capped by a later INSERT (rate_misapplication adverse: 0 -> 1 terms)
  ```
  P1 adds `favourable/last_test_accurate` to the TX protected `meter_error` row while an evaluation cites it. P1b adds a 6-month adverse term to `rate_misapplication`, turning a direction the law leaves uncapped into a capped one under the *same* `rule_id`. No new row, no close, no citation change: every evaluation and evidence row naming that id now names a different law.
- **Why it matters:** parity rests on "the evaluation records which rule row it used" being a stable fact. The window is the rule's most consequential attribute and lives in the child table, which is append-open. Writer is the owner (tally_app is revoked), so the exposure is a platform migration or admin fix — exactly the path R7 says must go through close-and-replace.
- **Suggested fix:** fence term INSERTs to the rule row's own creation. No DDL: BEFORE INSERT on terms, `IF (SELECT created_at FROM backbilling_rules WHERE id = NEW.rule_id) <> now() THEN RAISE restrict_violation`. `now()` is constant within a transaction and `created_at` defaults to it, so a rule and its terms written together pass and anything later is refused. If a stamped txid is preferred (mirroring `evaluations.recorded_txid`), add `recorded_txid` to `backbilling_rules`. Battery: term INSERT on an existing rule → refused.

### F-2 · MEDIUM · Q2 · Closing a law row has no floor and no stamp
- **Where:** `:713-721` (close branch); `:632-633` (`range_check` requires only `effective_to > effective_from`).
- **Repro:** `10-probes.sql` P2, P2b.
- **Observed:**
  ```
  P2  OBSERVED: the TX meter_error row (cited by an evaluation for 2026 periods) was closed effective 2005-01-01; the table has no closed_at / closed_by
  P2b OBSERVED: a successor row with favourable_duty=permitted now covers 2026 while the frozen-able evaluation cites the closed mandatory row
  ```
- **Why it matters:** "closed, never edited" is meant to keep "what was in force on date D" true forever. A retroactive close plus a successor rewrites that answer for dates already evaluated, and nothing records when or by whom the close happened. It is the edit R7 forbids, in two statements.
- **Suggested fix:** (a) in the close branch, refuse when any evaluation or evidence row cites `OLD.id` for a date on/after `NEW.effective_to` (`v.anchor_date >= NEW.effective_to`, `p.period_start >= NEW.effective_to`); (b) add `closed_at`/`closed_by`, stamped by the trigger and excluded from the "nothing else changes" comparison. Battery: close-before-cited-date → refused; stamps set.

### F-3 · MEDIUM · Q2 · A case or evaluation can cite another meter's test or deployment
- **Where:** cases FKs `:1048-1053`, trigger `:1125-1249`; evaluations FKs `:1454-1457`, trigger `:1487-1510`. All `(id, tenant_id)` composites — tenant-safe, meter-blind.
- **Repro:** `10-probes.sql` P3, P3b, P3c (tally_app, tenant 1).
- **Observed:**
  ```
  P3  OBSERVED: case … on meter M-DISC opened citing a discovering test of meter M-SLOW
  P3b OBSERVED: evaluation … of the M-FAST case records governing_test of M-SLOW and deployment of M-PRED
  P3c OBSERVED: the case on M-DISC cites M-OLD's deployment removal as its tamper evidence
  ```
- **Why it matters:** the case is "the record of one finding about one meter"; its discovering test, tamper evidence, and its evaluation's governing test and bounding deployment are the record's own references. A wrong-id app bug (the brief's bar) leaves a record inconsistent in the same way the kept "evidence is one kind with its reference" CHECK guards against. -12 already applies this rule to supersession (`tu.sql:22823`, "may supersede only a test of the same meter"). Not law: no window or duty is computed.
- **Suggested fix:** case trigger: when `discovering_test_id` / `evidence_deployment_id` is set, require its `meter_id = NEW.meter_id`. Evaluation trigger: `governing_test_id` and `deployment_id` must be of the case's meter. Four lookups. Battery: each → `check_violation`.

### F-4 · LOW · Q2 · A freeze compares only cause and anchor_date, not the other case inputs
- **Where:** `:1199-1208`. **Repro:** P4. **Observed:** `case_fast (direction now customer_owes) froze on ev1 (direction customer_owed); only cause and anchor_date are compared`.
- The core's fingerprint check (rules §11.2 #3) is the real guard, by design. But the evaluation row also carries `anchor_basis`, `direction`, `claimed_from`; comparing them costs nothing and closes the flip-then-freeze app bug. Extend `v_eval`.

### F-5 · LOW · Q2 · "Frozen" fences the case row only; evaluations and holds still append to a frozen case
- **Where:** evaluations `:1487-1510`, holds `:1839-1878` never read case status. **Repro:** P6. **Observed:** `on the FROZEN case_fast a new evaluation … and a new hold … were accepted (status still frozen)`.
- Design §4 says "changing a frozen case" = the row, so this may be accepted as stated. Flagged because a hold opened after the freeze changes what the frozen evaluation's coverage meant (residual R15 already leans on delivery re-deriving the fingerprint). If unwanted: refuse hold INSERT (optionally evaluations/approvals) when the case is not `open`. Whether a hold is *allowed* stays the core's.

### F-6 · LOW · Q2 · A withdrawal can carry other changes into the terminal record
- **Where:** `:1190-1247` — whole-row fence exists for freeze/unfreeze, not for `open → withdrawn`. **Repro:** P10. **Observed:** `withdrawal statement also moved anchor_date to 1999-01-01 and direction to customer_owes; the row is now terminal`.
- Fix: same `to_jsonb(NEW) - cols` comparison on the withdraw path with `cols = {status, withdrawn_reason, notes, updated_at}` (rules §11.1 says this for r7).

### F-7 · LOW · Q2 · The two vocabulary law tables have no history guard
- **Where:** `backbilling_causes` `:505-515`, `backbilling_customer_classes` `:535-552` — REVOKE for tally_app only, no trigger. **Repro:** P8, P8b (owner). **Observed:** `owner rewrote description/source_note on a class row and a cause row`; `an unreferenced class row can be deleted by the owner`.
- `source_note` on a class row is the citation for which customers the state protects. Referenced rows can't be deleted (FK) but their text can be rewritten silently. Attach `enforce_backbilling_law_history` (its close branch is keyed on `TG_TABLE_NAME = 'backbilling_rules'`, so on these tables it refuses every UPDATE/DELETE) to both.

### Checked, not findings
- `updated_at` on a case INSERT is caller-settable (P12). Cosmetic; `set_updated_at` corrects it on first update.
- Approval with no session user (P7): under `tally_app`, RLS's `get_user_tenant_id()` raises `22P02` on an unset/empty `app.user_id` before the approval trigger runs, so an anonymous approval is impossible on the app path. The owner path accepts `approved_by = NULL` — out of scope.
- The 79 battery checks cover the rest of design §4 on `rv_a` (tenant isolation K3/K4/K5, append-only tables, frozen-case fence, frozen-eval same-case FK, superseding a cited test, overlapping open holds, uncited/overlapping/edited law rows, app writes to law tables, unknown cause/class, stamps). I re-ran it rather than re-deriving them.

---

## Findings — Q1 STORE

### F-Q1-1 · MEDIUM · Q1 · The statutory shape that does not fit as rows: a window anchored on notice (or any anchor/condition outside the CHECK lists)
- **Where:** `:600-601` (`anchor_basis` ∈ {test_date, discovery_date}), `:629-631` (`enforce_condition` ∈ {read_beyond_utility_control}); mirrored on cases `:1054-1062` and evaluations `:1458-1459`.
- **Repro:** P21, P21b. **Observed:** `anchor_basis=notice_date refused 23514 … backbilling_rules_anchor_basis_check`; `enforce_condition=customer_denied_access refused 23514 … backbilling_rules_enforce_condition_check`.
- **Why it matters:** design §3 itself lists `anchor_basis` as "`test_date` / `discovery_date`, plus later kinds such as `notice_date`". A second state whose window runs from the utility's written notice to the customer, or whose enforceability turns on a condition other than the Texas read classification, is DDL, not rows. The design accepts this trade for `term_kind` explicitly ("a CHECK change and a core change together"); it does not say so for these two, and Q1's test is "rows alone".
- **Suggested fix:** either state the same acceptance for `anchor_basis` and `enforce_condition` in the comments and design §3 (the core must implement any new anchor anyway, so DDL-plus-core may be the honest answer), or move them to two tiny platform vocabulary tables with FKs so a new state is rows. Either is fine; the current text over-promises.

### F-Q1-2 · MEDIUM · Q1 · Interest on refunds has no rule attribute and no evidence column
- **Where:** `backbilling_rules` `:572-639`; `meter_correction_period_evidence` `:1559-1617`.
- **Repro:** P23 (catalogue check). **Observed:** `backbilling_rules has no column for: {refund_interest_required, interest_rate_basis, …}`; `meter_correction_period_evidence has no column for: {interest_amount, estimation_basis}`.
- **Why it matters:** a number of state consumer rules attach interest to the refund of an over-collection (the shape, not a citation, is the point). That is a per-state rule parameter (required? at what basis?) and a per-period output (the interest computed). Neither has a home: `correction_amount` is the caller's principal, `inputs` is inputs, and evidence has no free-form column. Texas needs neither, so nothing is lost today; it is a plausible second-state shape that needs DDL. (`estimation_basis` is D6, known.)
- **Suggested fix:** if non-Texas refunds may land before the next schema round, add `refund_interest` (`none`/`simple`/`per_tariff`) on rules and nullable `interest_amount` on evidence now; otherwise record it as a Q1 residual beside R2/R3.

### F-Q1-3 · LOW · Q1 · Window terms are whole months only
- **Where:** `:687-689`. **Repro:** `11-probes-redo.sql` P22/P22b. **Observed:** `months=0 refused` (correct); columns `id, rule_id, direction, term_kind, months, created_at`.
- A state that states its window in days or billing periods cannot be stored exactly. Whether a target state does is for Kyle. Fix if wanted: `unit` (`months`/`days`/`billing_periods`) beside a `count`.

### F-Q1-4 · LOW · Q1 · Delivery-side statutory parameters (notice, repayment terms) are not on the rule row
- **Repro:** P23. Many state rules require written notice before backbilling and a repayment period at least as long as the backbilled span. Per-state law, but delivery (-14) territory; noted so -14 puts them on `backbilling_rules` rather than in code.

### Q1 attributes confirmed present (no finding)
Walking `a2-rules-for-the-core.md` §1 and §2–§14 against the tables: every named rule parameter (`anchor_basis`, `qualifying_test_outcomes`, `favourable_duty`, both straddles, `delivery_path`, `requires_supervisor_evidence`, `units_invariant`, `enforce_scope/months/condition`, per-direction window terms incl. `deployment_start` and `half_since_last_test`) is a column; every evaluation output named in §6.1, §8, §9 (rule row, windows, governing test + basis + out-of-order flag, deployment bound, tenant limit, approval_required, inputs + fingerprint, core version, per-period class/rule/window/direction/amount/disposition/reason/days/forfeited) is a column; `partly_forfeited` lets a prorating state fit; ZZ (battery Z1–Z3) stores as rows. The R-36 "which gate" is a boolean (`approval_required`) — enough while there is one gate.
