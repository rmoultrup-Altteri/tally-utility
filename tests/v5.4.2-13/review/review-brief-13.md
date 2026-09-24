# Review brief — v5.4.2-13, A-2 backbilling caps re-drafted to Kyle R-32…R-39 (round 1, frozen)

| Artefact | Lines | md5 |
|---|---|---|
| `sql/v5.4.2-13-backbilling-caps.sql` (= `review/patch-13-frozen-r1.sql`) | 3113 | `a00683c5fcb5ee03208d35c60ba0e8a4` |
| `tests/v5.4.2-13/battery-13.sql` (= `review/battery-13-frozen-r1.sql`) | 1188 | `c861df94345b61dc48c8d043290c5fae` |

The patch is **frozen** for this round. Review the frozen copy. If you believe
the file changed under you, stop and say so. **Do not edit any file in the
repo.** Write repros to your own scratch space and put them in your report.

(`review/patch-12-frozen-r*.sql`, `battery-12-frozen-r*.sql` and
`review-brief-12.md` in this directory are the SUPERSEDED round-1 draft, from
before Kyle's R-32…R-39. Read them only for history.)

## What this patch is

16 TAC §7.45 limits how far back a Texas gas utility may correct a bill, and
for a meter found more than 2% FAST it makes the refund back to that limit a
duty. This patch builds the limits, and the object that carries a metering
correction, on top of the meter test history (v5.4.2-12, landed).

There is no application code; `sql/tu.sql` (through v5.4.2-12) is the only
artefact, so every rule is a constraint, trigger or function. The app
connects as `tally_app` (non-owner, RLS forced, no TEMP/CREATE in the deployed
DB).

**Authority.** Read these before judging:
- `gas-billing-memory/application/kyle-decisions-2026-09-22-a2-straddle-and-meter-test-anchor.md`,
  in particular §1 (the MAX() arithmetic), R-32 (a straddling period is
  forfeited whole), R-33 (meter errors are adjustments, not void-and-reissue),
  R-34 (the governing test), R-35 r5 (no test means the six-month cap, not a
  refusal) and R-36 (the transitional supervisor gate).
- `gas-billing-memory/application/kyle-decisions-2026-09-23-a2-override-and-cause-freeze.md`:
  R-37 (no override in the favourable direction, the computed deployment
  bound, meter-scoped targeting, the two-code hold, the adverse tenant limit),
  R-38 (the freeze and supersession, the tamper gate), R-39 (the eight
  causes), and OQ-1 (open).
- The -12 contract: `sql/v5.4.2-12-meter-test-history.sql`'s header and
  `meter_governing_test()`.

**Ryan's design call (2026-09-23).** R-33 takes meter errors off
`correction_run_targets` (the void-and-reissue path), and R-37(b) makes a
correction follow the METER, not an account. So a metering correction gets
its own record, `meter_correction_cases`. **Posting a case to a bill is NOT
in this patch.** Kyle's OQ-1 decides which object delivers each cause, and his
record puts that ruling ahead of the delivery DDL. A frozen case charges
nobody. v5.4.2-14 posts.

## What lands (patch sections)

1. `tenants.regulatory_class_mode` (PLATFORM-set) and
   `tenants.backbilling_adverse_limit_months` (R-37(d), tenant-set). Both are
   logged. The known-key CHECK on `tenant_configuration_history` is widened.
2. Supervisors: `session_is_supervisor()`; only a supervisor may grant
   `tenant_admin` (extends -12's section 1b).
3. `UNIQUE (id, tenant_id)` on `jurisdictions` and `meter_deployments`; the
   `service_locations.jurisdiction_id` FK is repaired to tenant-composite.
4. `meter_deployments` guard: meter, location, install date and created_at
   are immutable for tally_app; removal is write-once; created_at is stamped.
5. `backbilling_cap_rules`: 8 causes, **platform-held** (tally_app cannot
   write it), seeded for TX gas, both classes. Plus the resolvers.
6. The void-and-reissue path narrowed. `correction_run_targets.backbill_cause`
   admits `rate_misapplication` only. The issuance gate refuses an upward
   rebill unless it is a correction on a target recording that cause, over
   the same period, **with the same usage quantities per meter**. The
   -10 target freeze gains `backbill_cause`.
7. `service_location_acquisitions` (R-37(c)'s predecessor date, per premise).
8. `meter_correction_cases` plus its trigger-written event log. The cause,
   anchor and direction are derived from the discovering test for
   meter_error and non_registering_meter. There is a tamper gate. Cases move
   open ⇄ frozen, or to withdrawn.
9. `meter_correction_inputs()` builds the full input document.
   `meter_correction_evaluations` stores the caller's per-period amounts,
   with everything else derived plus an md5 fingerprint.
   `meter_correction_period_evidence` holds per-period rows: included or
   forfeited.
10. `meter_correction_approvals`: R-36 approval of ONE evaluation, by a
    supervisor who is neither the opener nor the evaluator.
11. `meter_correction_holds`: two codes, database-validated, closable only
    as ruled.
12. The freeze. It checks the fingerprint (all inputs unchanged), the R-36
    approval, and zero uncovered in-window days on a fast meter.
13. `meter_tests` coupling: a test a FROZEN case rests on cannot be
    superseded.
14. Views `meter_correction_case_status`, `backbilling_forfeitures` and
    `meter_correction_open_holds` (security_invoker).
15. Residuals R1–R17. **Read them. They are what I already know.**
16. AC-32 tail.

## Verification already done (re-run it; do not take my word)

- Strict apply ×2 (`search_path=''`, `check_function_bodies=on`) on a fresh
  `TEMPLATE tally` clone: clean and idempotent, and AC-32 passes.
- `battery-13.sql`: **116 PASS**, zero failures. Two tenants throughout.
- Regressions on the patched clone: battery-09 **28**, -10 **58**, -11 **41**,
  -12 **116**, each at its recorded count.
- **49 planted mutations** (`tests/v5.4.2-13/mutations-13.py`). Each breaks
  one guard. Every one is caught at the check written for it. Seven are
  caught first by a backstop constraint at that check (M03 in fixtures, M09,
  M22, M27, M30, M45, M46). Six mutations were initially NOT caught
  discriminatingly (M19, M25, M33, M35, M39, plus M46's harness miss). The
  battery was sharpened until they were.

```sh
docker exec tally-pg psql -U tally -d tally -c "CREATE DATABASE r13x TEMPLATE tally"   # pick your own name
docker cp tests/v5.4.2-13/review/patch-13-frozen-r1.sql tally-pg:/tmp/r13x.sql
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg \
  psql -U tally -d r13x -v ON_ERROR_STOP=1 -q -f /tmp/r13x.sql
docker cp tests/v5.4.2-13/review/battery-13-frozen-r1.sql tally-pg:/tmp/b13x.sql
docker exec tally-pg psql -U tally -d r13x -v ON_ERROR_STOP=1 -f /tmp/b13x.sql 2>&1 | grep -E 'PASS|FAIL|ERROR'
```

`tally-pg` has NO host port. Use `docker exec` only, and connect as
`-U tally` (there is no `postgres` role). Only database `tally` exists:
clone it, never write to it, and drop your clone when done. Two clones
cannot be created from `tally` at the same instant, so retry if you see
"source database is being accessed". To act as the app:
`SET LOCAL app.user_id = '<users.id>'; SET ROLE tally_app;`. A tally_app
session may call `set_config('app.user_id', …)`; that is the RLS model's
premise (-12 R16), not a finding. Clones HOLD TEMP for tally_app and the
deployed DB does not, so "tally_app can create a temp function" is not a
finding either.

## Defects found and fixed before freezing (the shapes I most want you hunting)

1. **A tenant could uncap its own statutory row.** The round-1 draft's cap
   table was tenant-writable. It is now platform-held.
2. **The service-start bound would have ended every fast-meter refund at
   go-live.** `sync_meter_deployments()` creates every meter's first
   deployment from `meters.start_date`, which defaults to CURRENT_DATE, so
   on a migrated meter "the start of its deployments" (R-37(a)) is its
   ONBOARDING date. The bound now shortens a REFUND only when corroborated:
   another meter served that premise and came out on or before this one
   went in. A CHARGE may still be shortened by any recorded start. The
   under-reach day count likewise never excuses days before the first
   recorded deployment. **This is an engineering reading of Kyle's ruling
   (residual R6), and I want it attacked from both sides.** Can
   corroboration be manufactured? Does it wrongly refuse a real bound?
4. **A fast finding could be relabelled out of its duty.** Changing a fast
   meter_error case to billing_constant_error dropped the window and the
   under-reach check while the test still stood. A test-decided cause now
   moves only to tampering_bypass, which is gated (battery E20, mutation
   M49). What remains is residual R17: a fast meter found tampered.
3. **The tenant settings history refused every tenant INSERT.** Its
   known-key CHECK did not know the two new keys. The strict apply did not
   catch this; the regression batteries did.

## Where I most want an adversarial read

1. **Anything the caller supplies that decides the window or the result.**
   The caller supplies the cause, the discovering test, for discovery causes
   the anchor and claimed_from, and the per-period amounts. Can any of them
   lengthen an adverse window, shorten a favourable one, avoid the R-36
   gate, or move a period from forfeited to included? Consider in
   particular:
   - picking which of two same-day tests discovers;
   - a discovery cause's anchor feeding the tenant limit;
   - changing the cause between evaluate and freeze, since the fingerprint
     includes the cause;
   - `claimed_from` on tampering (uncapped).
2. **The fingerprint.** `meter_correction_inputs()` is the whole contract
   between evaluation and freeze. Is anything the evidence depends on
   missing from it? Candidates: the discovering test's supersession, the
   evaluation-level cap row vs per-period rows, a customer's type under
   explicit_class, an invoice's `usage_quantity` (billed_units is included;
   is the line meter_id?), holds (deliberately excluded; is that right?).
   Can two different worlds hash the same?
3. **Under-reach (R-37).** Can a FAST meter's case freeze with an in-window
   refund stretch neither corrected nor held? Routes to try:
   - deployment gaps;
   - invoices that are issued but void, or `credit_memo` / `duplicate`
     (excluded from the period set: is that right?);
   - a hold opened then completed;
   - a re-evaluation that shortens the window after a hold;
   - withdrawal paths (withdrawal is refused while the discovering test
     stands);
   - a cause change away from meter_error and back;
   - changing the cause so the case stops being "fast" at all. Fixed for
     the discovery causes (defect 4); tampering remains (R17). Is there
     another route? For example, a second case on the same meter, or a
     withdrawal after a cosmetic supersession of the test.
4. **The reissue gate.** Does the units test close R-33 for upward rebills?
   Try:
   - a units-preserving meter correction (a fast meter's rebill at the same
     units but a higher price?);
   - moving usage between meters on one bill;
   - lines with NULL usage;
   - consolidated bills.
   The downward direction is ungated (R3); is that acceptable?
5. **The holds.** Can either code be satisfied falsely? Consider:
   - the cutover moving (platform-set, but -12 lets it move within bounds);
   - an acquisition row entered after the finding (it is write-once but
     not time-fenced against the test: a finding?);
   - a hold range spanning two deployments at two premises;
   - completion by a bill loaded for another customer.
6. **R-36.** The gate is required only for an ADVERSE meter_error. Is that
   right against R-36's text ("an adverse correction anchored on
   migrated_date_only provenance, or raised on a meter flagged attested_none
   or unknown")? Check non_registering_meter too. Is the separation of
   duties (approver ≠ opener ≠ evaluator) sound against a two-person
   collusion-free reading, and does anything let the operator re-evaluate
   AFTER approval and still freeze?
7. **Concurrency.** Evaluation, approval, hold and freeze all lock the case
   row. Two-session repros of:
   - a freeze racing a hold completion;
   - a freeze racing an approval (REPEATABLE READ too);
   - an evaluation racing a cause change;
   - the -12 test insert (which locks the meter row) racing a freeze.
   R15 states what is not locked. Is that set complete?
8. **Tenancy.** Every new FK is composite. Hunt for a tenant-blind link, an
   RLS gap in the views, and a cross-tenant read through
   `meter_correction_inputs()` (invoker) or the status view.
9. **The case guard's state machine.** Enumerate the transitions: open,
   frozen, withdrawn, each with a cause change and with column edits in the
   same statement. Is any path able to change a frozen case's substance,
   un-withdraw, or stamp its own `frozen_evaluation_id`?

## Rules of engagement

- Severity CRITICAL / HIGH / MEDIUM / LOW, each with a reproduction I can run.
- For every finding, separate the **finding** from your **proposed fix**, and
  say whether you measured the fix.
- "Fine but undocumented" is LOW; name the line.
- **Out of scope by ruling or by design:**
  - posting a case, and anything that needs the delivery object (OQ-1, R1);
  - F-1 carried onto a posted charge (R8);
  - deriving the amount from the test error (R2, not ruled);
  - estimation_catchup, unbilled_service and the R-30 read classification
    (R11);
  - the CCK volumetric resolver.

  A finding that these are missing is not news. A finding that this patch's
  FACTS for them are wrong is.
- Do not propose deriving a test date from `install_date`,
  `test_interval_months` or `next_test_due_date` (R-31 / R-35 r3). A
  deployment start may BOUND a window; it is never a test date.
- End with a one-line verdict: **"sound enough to mirror"** or **"not yet"**,
  and why.
