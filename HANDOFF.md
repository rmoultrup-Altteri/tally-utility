# Handoff: A-2 re-drafted as v5.4.2-13 (the meter correction case) — four review rounds folded, round 5 frozen, NOT landed

**Generated**: 2026-09-23 22:47 (end of session)
**Branch**: tally-utility `main` (pushed, `478fcab`) · gas-billing-memory `main` (pushed, `075d73c`)
**Status**: In progress. Round 5 is frozen at md5 `d0873150fb758cb2a490ed083c691d96` and **not yet sent to reviewers**. `tu.sql` is untouched: 23,452 lines through v5.4.2-12, md5 `2aa59147bfde61d86991f7f0a5c5d22a`.

## THE ONE THING TO CARRY FORWARD

**Send round 5 to Fable and Opus as a confirmation round.** In round 4 both reviewers said "not yet, narrowly". Each would call the patch **sound enough to mirror** with its gate siblings folded in, and all four are folded in r5.

The brief is written: `tests/v5.4.2-13/review/review-brief-13-round5.md`.

If both come back "sound enough to mirror", land it:
1. mirror into tu.sql;
2. rebuild and check catalog parity;
3. run the batteries on the build;
4. write the records.

The reviewer agents (`fable-r1`, `opus-r1`) are from this session. A new session must spawn fresh ones: `subagent_type: general-purpose`, `model: fable` and `model: opus`. Put this in each prompt: **"send the report to main as several messages under ~3 KB"**, because final results truncate at about 4 KB and they cannot write report files (memory `reviewer-reports-truncate`).

## Goal

A-2: enforce 16 TAC §7.45's backbilling limits on top of the meter test history (-12). This follows Kyle's R-32…R-39. **Ryan's design call (2026-09-23): a meter correction case record** (one per finding about one meter) carries metering corrections, because R-33 takes meter errors off void-and-reissue and R-37(b) makes the correction follow the meter. **Posting a case to a bill is -14** and waits on Kyle's **OQ-1**.

## Completed (this session)

- [x] **Kyle brief for OQ-1**: GBM `application/kyle-brief-2026-09-23-oq1-correction-delivery.md`. It asks, cause by cause, whether a correction is delivered as an adjustment or by void-and-reissue, plus two follow-ons. It also asks Kyle to confirm the **R-37(a) corroboration reading** (below). **Not yet sent to Kyle; Ryan decides.** Logged as ingestion Section BM.
- [x] **`sql/v5.4.2-13-backbilling-caps.sql`** re-drafted from scratch (3,619 lines):
  - tenant settings: `regulatory_class_mode`, platform-set; `backbilling_adverse_limit_months`, R-37(d);
  - supervisors (`session_is_supervisor()`; only a supervisor makes a `tenant_admin`);
  - deployment evidence guards, including `meter_deployments.removal_recorded_at`;
  - `backbilling_cap_rules` (8 causes, **platform-held**);
  - the narrowed reissue gate (`correction_run_targets.backbill_cause` admits `rate_misapplication` only; R-39 units test);
  - `service_location_acquisitions`;
  - `meter_correction_cases` with a trigger-written event log and the tamper gate;
  - evaluations and per-period evidence with an md5 fingerprint;
  - the R-36 approvals;
  - two-code holds;
  - the freeze;
  - the test-history couplings;
  - four views: status, forfeitures, open holds, and fast findings with no case;
  - residuals R1–R21.
- [x] **`tests/v5.4.2-13/battery-13.sql`: 137 PASS**, in groups A–P. Groups M–P each hold one discriminating check per review-round finding.
- [x] **`tests/v5.4.2-13/mutations-13.py`: 73 planted mutations, each caught at its named check.** Run it with `MUT_DIR=<dir> python3 tests/v5.4.2-13/mutations-13.py [M01 ...]`.
- [x] **`tests/v5.4.2-13/fence-and-race-13.sh`: A–E PASS.** These checks need separate transactions: the evidence fence, the acquisition fence, freeze-vs-supersession in both orders, the backdated removal, and the deadlock. Each check fails under its planted mutation. `PATCH13=<file>` runs it against another copy.
- [x] Regressions on the patched build stay at 09 **28**, 10 **58**, 11 **41**, 12 **116**.
- [x] **Four review rounds** (Fable + Opus, hash-frozen). The briefs and frozen copies r1–r5 are in `tests/v5.4.2-13/review/`. The round-1…round-4 dispositions are in the patch header and the round briefs.
- [x] Memory: `early-return-branches-skip-fences`, `reviewer-reports-truncate`.

## Not Yet Done

- [ ] **Round 5 review** (confirmation). Then land:
  1. mirror the patch BODY into tu.sql;
  2. `diff` it against the source;
  3. rebuild `tally-pg` from a fresh volume;
  4. hash-verify;
  5. check catalog parity against a patched clone;
  6. run every battery on the build, plus fence-and-race;
  7. write the records: DEPLOY-VERIFICATION, DECISION-LOG (the design decisions below), APPLICATION-CONTRACTS (AC-34?), and the GBM CI re-grades (A-2 register entry, CI-008);
  8. update the parity plan and the ingestion section;
  9. update both CHANGELOGs;
  10. commit and push both repos.
- [ ] **Kyle:** send the OQ-1 brief. It carries the R-37(a) corroboration question. Also: R-36 applies only to adverse `meter_error` (R18), which needs his confirmation. Still open with him from before: R13 (can a wrong-dated test be corrected?), the counsel bundle, the customer-type default widening, and the A-8 brief.
- [ ] **-14 (delivery):** after OQ-1, it posts a frozen case. **It must re-derive the fingerprint and refuse a stale frozen case (R15).** It must also carry `enforceable_scope` onto the posted charge (F-1), and add R-38 attachment 3 (supplemental adjustment, protection re-determination).
- [ ] Everything in the old handoff's Workstreams A and B is unchanged:
  - the UI direction call;
  - the 229-link tenant-blind FK remediation (now also `invoice_line_items.meter_id` and `meter_deployments`' own links, R20);
  - A-8, A-10, Wave 4;
  - the invariant-register and feature-list re-grades;
  - scenarios (zero written);
  - wiki ingestion (Sections A–BM queued).

## Failed Approaches (Don't Repeat These)

Every one of these was found by review and is pinned by a battery check and a mutation.

- **Honouring R-37(a)'s "start of the meter's deployments" literally.** `sync_meter_deployments()` creates every meter's first deployment from `meters.start_date`, which defaults to `CURRENT_DATE`. So on a migrated meter the "start" is the **onboarding date**, and every fast-meter refund would end at go-live. The fix: a start shortens a refund only if **corroborated**, meaning another meter served that premise into the window and came out on or before this one went in.
- **Fencing derived columns in the fall-through of a guard whose status branches `RETURN NEW` early.** Freeze, unfreeze and withdraw skipped the fence, so a fast case could be turned into a charge in one statement. Put the fences first, and make a status change carry nothing, by whole-row jsonb comparison.
- **Keying withdrawal on the case's direction, or on "some correction exists".** A fast test corrected to an *even faster* reading freed the case. Read the head of the supersession chain.
- **Leaving the discovering test's supersession out of the fingerprint.** The case froze on a test already corrected to accurate. Also: a supersession check with no lock lost a race to a freeze in flight.
- **Fencing deployment evidence on the discovering test's `recorded_at`.** The caller picks the test, and a same-date copy gets a fresh recorded_at. The fence is the moment the fault was **first** on record.
- **Fencing only a deployment's `created_at`.** A removal is a later write, dated by the caller, and it flows through `meters.status` → sync. Stamp `removal_recorded_at`, and use strict `<` for application-stamped removals, because one transaction has one `now()`.
- **Believing a "no closed-row insert" rule stops fabrication.** A history can be built entirely through `meters` (insert with an old start_date, then inactivate with a removal_date). That route is only caught if it happens after the finding; before the finding it is residual R6.
- **Counting a completed hold as coverage.** Its bills can be voided later. Completed holds cover nothing and are excluded from the no-overlap constraint.
- **Any `0.00` in a fast refund.** Refused on any period whose usage is known and non-zero, or unknown.
- **The reissue gate, five wrong versions:**
  1. matching the exact period at the same location;
  2. comparing whole totals across bills of different scope;
  3. per-meter scope at the same premise (the extra rides on another meter's line, or a line with no meter);
  4. "more than EVERY matched voided bill" (a decoy or a mis-keyed duplicate excuses the rebill);
  5. per-meter scope keyed on the header's premise.

  **Rejected: per-day proration.** A cheap new month dilutes an overcharge. **Rejected: Opus's covering-bill rule.** A same-period duplicate covers the period and still excuses the rebill.
- **Round-1 lock order** (meter, then cases) deadlocked "lock a case, then record a test". The trigger is now named `a0_…` so it fires before -12's meter lock.
- **Harness traps:**
  - `git add` with a path already `git rm`'d fails the whole add. Commit `c949190` contains only a deletion; `ce462da` holds the files.
  - A DO block that raises rolls back its own fixture inserts, so put fixtures outside it.
  - `now()` is constant within a battery transaction, so ordering-by-time checks need separate transactions.
  - A mutation can stay green because a *redundant* guard catches it. Then you need a check that exercises the guard alone, or a mutation that breaks both guards.

## Key Decisions (for DECISION-LOG at landing)

| Decision | Rationale |
|---|---|
| Meter correction case as its own record (Ryan) | R-33 takes meter errors off void-and-reissue; R-37(b) is meter-scoped; R-38 doesn't depend on OQ-1 |
| Posting deferred to -14 | OQ-1 decides which object delivers each cause |
| The DB derives cause eligibility, anchor, basis and direction from the discovering test | R-39: the outcome decides the cause. A caller-chosen anchor or direction moves the window |
| A test finding keeps its cause (meter_error/non_registering may become only tampering) | Relabelling a fast meter drops the mandatory refund |
| Cap table platform-held | The draft let a tenant uncap its own six-month row |
| `regulatory_class_mode` platform-set; `backbilling_adverse_limit_months` tenant-set, adverse only | Leaving the default removes protection; the limit can only shorten a charge (R-37(d)) |
| Void-and-reissue admits `rate_misapplication` only, with the R-39 units test against every exceeded voided bill | Narrow first; units are the mechanical definition of "correct units, wrong price" |
| Corroborated service start for refunds (put to Kyle) | Otherwise every refund ends at onboarding |
| R-36 gate enforced for adverse `meter_error` only; approver ≠ opener ≠ evaluator; approval bound to one evaluation | Weak prior-test provenance only moves a (v)(I) window |
| Freeze = latest evaluation + fingerprint match + approval + zero uncovered days | One comparison instead of a list that can drift |
| Reissue gate: overlap by premise, shared meter, or (no premise) customer; whole charge unless the new bill has no premise; "more than ANY" is an increase | See Failed Approaches. Costs are in R21 |
| unbilled_service and estimation_catchup not accepted as case causes; R-30 read classification dropped | No billing-period unit (OQ-1); no path uses them yet |

## Current State

**Working**: the r5 patch applies cleanly and idempotently twice under strict settings (`search_path=''`, `check_function_bodies=on`) on a clone of `tally`. The rest of the checks, with their numbers, are listed under Completed.
**Deployed**: `tally-pg`'s `tally` DB is still the -12 build. The patch exists only in `sql/`, and scratch clones were dropped.
**Uncommitted changes**: none; everything is pushed.

## Code Context

```sql
-- the case: caller supplies meter_id, cause, discovering_test_id (test causes)
--   or anchor_date + claimed_from (discovery causes); the DB derives the rest
INSERT INTO meter_correction_cases (tenant_id, meter_id, cause, discovering_test_id) ...;
-- evaluate: caller supplies ONLY {invoice_id: amount}, exactly the billed periods found
INSERT INTO meter_correction_evaluations (tenant_id, case_id, submitted_amounts) ...;
meter_correction_billed_periods(tenant, meter, from, before) -> the period set
meter_correction_inputs(case_id) -> jsonb   -- the fingerprinted document
meter_correction_evidence_fence(case_id) -> timestamptz
meter_correction_uncovered_days(evaluation_id) -> int
UPDATE meter_correction_cases SET status = 'frozen' | 'open' | 'withdrawn' (+ withdrawn_reason)
-- the gate: enforce_backbilling_gate_issue() BEFORE UPDATE OF status ON invoices
```

**Scratch sources:** the patch was assembled as `cat p1 p2 p3 p4` in the session scratchpad. That scratchpad is gone in a new session, so **edit `sql/v5.4.2-13-backbilling-caps.sql` directly** from now on.

## Resume Instructions

1. `git fetch` both repos and read GBM for any Kyle answer to OQ-1 (memory `fetch-gbm-before-orienting`).
   - If OQ-1 is answered, the landing plan still holds; -14 comes after.
2. Re-verify r5 before sending:
   ```sh
   md5 -q sql/v5.4.2-13-backbilling-caps.sql   # expect d0873150fb758cb2a490ed083c691d96
   docker exec tally-pg psql -U tally -d tally -c "CREATE DATABASE s13 TEMPLATE tally"
   docker cp sql/v5.4.2-13-backbilling-caps.sql tally-pg:/tmp/p13.sql
   docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d s13 -v ON_ERROR_STOP=1 -q -f /tmp/p13.sql   # twice
   ```
   Then clone `s13` and run battery-13 in the clone; expect **137 PASS**. Then `sh tests/v5.4.2-13/fence-and-race-13.sh`; expect **A–E PASS**.
3. Spawn two reviewers (Fable, Opus) with `review-brief-13-round5.md` and the chunked-report instruction. They must check the md5s at the start and again before reporting.
4. If both say "sound enough to mirror", land it by the loop in Not Yet Done. If either finds something:
   - fold it into one revision;
   - add a battery check that exercises the guard alone;
   - add a mutation;
   - freeze r6 and send it.

## Warnings

- **tu.sql is APPEND-ONLY.** Mirror the patch BODY only and `diff` it afterwards. Its header comment is stale; fix it, if at all, with this mirror.
- **Only database `tally` exists.** Clone it with `TEMPLATE tally`. Two clones can't be created from it at the same instant. There is no host port, so use `docker exec` and `-U tally`.
- **Batteries run on clones that HOLD TEMP**, which the deployed DB revokes.
- **Fixture traps for -13 and later:**
  - An issued invoice needs a calculation snapshot, checked by a deferred constraint trigger at commit. Build bills as a draft, then lines, then `snap`, then status (see `pg_temp.bill` in battery-13).
  - Issued line items are immutable.
  - Every meter created `active` with a `location_id` auto-creates deployment #1 at `start_date`, which defaults to today.
  - The application cannot insert a deployment that is already removed.
  - A correction must sit on a `run_type = correction` run, with one live correction per bill lineage.
- **Trigger order is load-bearing.** `a0_enforce_test_supersession_vs_frozen_case` must sort before any `meter_tests` trigger that locks the meter row (R15).
- **Do not draft -14** before OQ-1. Texas-only launch scope. Never `git add -A` in GBM. Log GBM canonical changes in `application/wiki-ingestion-pending.md`.
- **Unchanged Workstream A (UI):** `ui-concepts/`, `pnpm dev` on port 4182. Run `pnpm check:fixtures` after any fixture edit. It is waiting on Ryan's direction call.
