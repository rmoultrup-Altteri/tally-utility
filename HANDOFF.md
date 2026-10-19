# Handoff: wave 3 drafted — v5.4.2-26 (collections decisions, field verification) built and tested; -23 r3 still waits on Kyle (K-10)

**Generated**: 2026-10-19, 12:22 CDT
**Branch**: `main` in both repos. tally-utility is at the wrap-up commit, pushed. GBM had no new commits; Kyle has not answered K-10.
**Status**:
- **-23** is blocked on Kyle (Ryan, 2026-10-18: "let's wait on Kyle"). Kyle pushes his answers to the repos.
- **-25** (disputes) and **-26** (collections) are drafted and fully tested. Neither is frozen or reviewed.

## Goal

Reach the C# core build. Ryan's gate, in order:
1. schema parity with CI-001…CI-135 (**we are here**: 78 of 135; re-graded only after a mirror);
2. scenarios and a test strategy;
3. a phase plan;
4. build.

Wave 2: -22 landed; -23 waits for its r3; -24 follows -23. Wave 3: -25 and -26 are both drafted.

## Completed (this session, 2026-10-19)

- [x] Ryan: "go ahead with -26" (chosen over freezing -25 early).
- [x] **Design** (`9870aea`, amended in `1f92514` and `cb9abed`): `application/wave3-build-2026-10-18/v5.4.2-26-design.md`.
  - **Sections:** C (the decision record), E (hardening), F (field verification), the lock order, and the "Tests as written" and "Built" records.
  - **Three corrections to the inventory**, each settled by a standing rule:
    - a notice's subject is its bill plus the service it threatens (Kyle's CCK-7 grain);
    - idempotency is checked against the live decision, not by a unique key (memory `append-only-vs-unique-deadlock`);
    - only the disconnect act is guarded on orders, not dispatch moves.
- [x] **Tests first** (`1f92514`), then **the patch** (`cb9abed`), `sql/v5.4.2-26-collections-decisions.sql`.
- [x] **CI wiring:** -26 is in PENDING; `PRE26=ci_pre26` is cloned before -26 applies. The battery, races and migration are steps.
- [x] **Results:**

  | Check | Result |
  |---|---|
  | battery-26 | 202 checks |
  | races/collections-26.sh | CR1–CR8, 11/11 |
  | migration-26.py | P0–P7, 22/22 |
  | mutations-26.py | 127/127 |
  | `tests/ci.sh` | all pass, 49 steps |
- [x] **Roadmap:** the phases summary mentions -26; the dashboard's `phases` dataset was refreshed. Dates are unchanged (likely ready-to-onboard 2027-06-16).
- [x] **Memory:** `v5426-collections-drafted`.

## Not Yet Done

- [ ] **Kyle's K-10, then the -23 r3 plan.** The merged round-2 findings are in `git show 90b325c:HANDOFF.md`, under "Not Yet Done". Fetch GBM first.
- [ ] **Review -25 and -26.**
  - Freeze each (a brief plus md5s, as `tests/v5.4.2-23/review/review-brief-23-r2.md`) and send to all three reviewers (Opus, Fable, Codex).
  - **Default order:** after -23 r3 settles, so the reviewers see them on the -23 they build on.
  - **Mirror order:** -23, then -25, then -26.
- [ ] **For the reviewers to weigh:**
  - -25's R7, the SECURITY DEFINER status move, against -20's NOLOGIN-owner pattern;
  - -26's residuals R1–R5: UTC act dates, rule citations waiting for wave 7, two dunning types that move no stage, the core deciding conditions, and the trigger-depth fences.
- [ ] **At -26's mirror:**
  - update APPLICATION-CONTRACTS: AC-10 still lists `dunning_stage` and `late_fee_*` as writable; AC-37 should say a gated dunning step cites its decision; add a new AC for decisions, visits and approvals;
  - DEPLOY-VERIFICATION, the parity re-grade and the GBM manifest, as for every mirror.
- [ ] **Tell Kyle (not blocking):** `ui-concepts/components/accounts/AccountDetail.tsx` edits `do_not_disconnect` as a checkbox. After -26 that is refused; the screen must enroll the customer in a protective program instead.
- [ ] **Four law findings for Kyle** (wave-3 inventory, "For Kyle"): the day-26 elderly bar, the forecast high, closed days, *Craft*. Ryan decides when to send them.
- [ ] **Carried over:**
  - the reply to Kyle on D-2's location;
  - the -05 defect (`meters_last_validated_actual_reading_id_fkey`);
  - -21 R9;
  - the R-03 scoping;
  - `pga_monthly_reconciliations.deferred_balance_after`;
  - the backbilling tariff table;
  - the GitHub Actions bump;
  - the Florida 25-7.083 text;
  - the waiver-determination rewrite;
  - low-confidence measurement rows;
  - the -15 r8 follow-ups;
  - gate steps 2–4.

## Failed Approaches (Don't Repeat These)

- **A unique key on (act, subject, date, fingerprint) for idempotency.** It wedges: when facts go A, then B, then back to A on the same day, the decision restoring A can never be written. Compare against the live decision only ([C5]).
- **Requiring a dunning log line to cite the live decision.** `late_fee_applied`, `shutoff_scheduled` and `disconnected` log an act that has its own record. If the next day's sweep writes a newer decision first, an honest log is refused. The act's own record (charge, order, executed visit) is checked live; the log needs that record and its date in the window ([A8]).
- **`array_agg(... ORDER BY code)` against a literal list.** The default collation ignores `_`, so `aged_suspense` sorts before `agency_pledge`. Sort with `COLLATE "C"`.
- **An invoice with no `location_id`.** `invoices_check` requires `is_consolidated = true`.
- **A test of a composite FK that a guard check beats first.** Build the fixture so the guard's own checks pass and only the key can refuse (A5b, A5g).
- **Guard pieces that are always beaten** (they can't be mutation-tested, so remove them): tenant checks where row security answers first (decisions, approvals); a "no successor" filter on the latest-recorded live decision; a blocked-but-empty test; an `outcome = 'executed'` filter the CHECK already guarantees.
- **Mutating `ENABLE ALWAYS`.** The owner's battery runs as origin, so nothing distinguishes it. It isn't mutated.
- **Earlier failures still hold:**
  - document-order comparisons of rule facets;
  - `deferred()` as one tenant's operator;
  - plain TRUNCATE of a referenced table;
  - untested exempt branches;
  - `pg_stat_clear_snapshot()` in race polls;
  - never edit the patch or tests during a mutation run;
  - `codex exec` needs `< /dev/null`.

## Key Decisions

| Decision | Rationale |
|---|---|
| Go ahead with -26 before reviewing -25 (Ryan) | -26 is independent of K-10; reviewing -25 now risks a second pass after -23 changes |
| Decisions written by tally_app with `calculated_by` | Same as `dispute_determinations` and `deposit_return_due` |
| Unevaluable blocks; only eligible authorizes | Fail toward protection (K-CCK, R-26, R-30); a design rule, not law |
| An eligible execute decision holds for its own day only | EWE is daily; GBM rank 0 refuses relying on an older evaluation |
| A disconnect is checked at order and again at execution | CI-067's "every disconnect path consults it" |
| `dunning_stage` and `do_not_disconnect` are written by the database, with depth fences | Guards must act; a projection nobody can type in |
| `late_fee_assessed` and `late_fee_amount` dropped | Wave 2 M1: derive, do not store (no reader existed) |
| Overrides: the database stamps the supervisor; a mismatch approval binds the captured values | D9-1, R-38 attachment 2; guard the act, not the label |
| Rule citations wait for wave 7 | No collections rule table exists; adding a cite table later is additive |
| Wait for Kyle before -23 r3 (Ryan, carried) | Under K1 = A, the refund exemption and three blockers are deleted, not fixed |

## Current State

**Working:**
- tu.sql through -22;
- -23 r2, -25 and -26 pending in CI;
- `tests/ci.sh` all pass (49 steps).

**Broken (known):** -23 r2's round-2 findings (unchanged).

**Uncommitted changes:** none after the wrap-up commit.

**Scratch DBs** in tally-pg (throwaway; drop them freely):
- `p25` (tally + -23 r2 + -25; the base for `fresh26.sh`);
- `s26` and `r26` (+ -26);
- `ci_pre26` (left by CI; the mutation base);
- older `q25`, `r25`, `ci_pre25`.

## Code Context

```sql
-- the decision (tally_app writes, with calculated_by); one live per (tenant, act, customer, invoice, location, meter)
collections_decisions (act ∈ notice|late_fee|disconnect_order|disconnect_execute|collections_referral,
  invoice_id, location_id, meter_id, evaluation_date, outcome ∈ eligible|blocked|unevaluable,
  active_conditions text[], unevaluable_conditions text[], governing_condition, valid_until,
  supersedes_id, inputs, inputs_fingerprint, calculated_by)
public.collections_live_decision(tenant, act, customer, invoice, location, meter) -> collections_decisions
public.collections_act_check(decision, act, invoice, location, meter, on date, live bool, what) -> collections_decisions
-- acts: dunning_events / adhoc_charges / service_orders .collections_decision_id; service_order_field_visits; _approvals
-- lock order: subject advisory lock (READ COMMITTED, 25000) -> bill row FOR NO KEY UPDATE (dunning) | order row FOR SHARE (visit)
-- every refusal the patch raises carries its tag, e.g. [C3f], [A8], [F2b]
```

```bash
S=<scratchpad>/fresh26.sh <db>   # recreate if gone: clone p25 -> <db>, REVOKE TEMP, strict-apply -26
bash tests/v5.4.2-26/races/collections-26.sh <throwaway db>
python3 tests/v5.4.2-26/migration-26.py <pre-26 base>         # ci_pre26 after a CI run
M26_BASE=ci_pre26 python3 tests/v5.4.2-26/mutations-26.py [--anchors] [M01 ...]   # ~30 min for 127
```

## Resume Instructions

1. Run `git pull --ff-only` here and `git fetch` in `../gas-billing-memory`. Look for Kyle's K-10 there; Kyle pushes his answers to the repos.
2. Run `bash tests/ci.sh`.
   - Expected: all pass, 49 steps.
   - The -17 RC5 race can flake under load; rerun it alone.
   - If `tally-pg` is missing: `bash tests/ci.sh --build`.
3. **If Kyle has answered:** write `application/wave2-build-2026-10-15/v5.4.2-23-r3-plan.md`, implement it with the refund-posting tests first, re-run CI and the mutations, then freeze r3 for all three reviewers.
4. **If not:** ask Ryan whether to freeze -25 and -26 for review now or keep going (-24 waits for -23; wave 4 is next in the sequencing). Do not start -23 r3.

## Warnings

- **Never edit** the frozen review copies (`tests/v5.4.2-*/review/*-frozen-*`) or tu.sql's mirrored bodies.
- **Revoke TEMP from PUBLIC, `tally_app` and `tally_core` after every `CREATE DATABASE … TEMPLATE`.** -26's depth fences depend on it.
- **Don't edit the patch or tests while a mutation runner runs.**
- **The -26 battery uses dates relative to today** for order decisions (`pg_temp.today()`). Other acts use fixed past dates; decisions can't be future-dated ([C3j]).
- **-25 embeds law files verbatim:** re-emit with `lawc.py emit` after editing `law/dispute/*`.
- **Codex:**
  - only under nvm v24.15.0;
  - run it as `codex exec -s workspace-write -C <repo> -o <final.txt> "$(cat prompt)" < /dev/null`.
