# Handoff: wave 3 begun — v5.4.2-25 (disputes) drafted and tested; -23 r3 still waits on Kyle (K-10)

**Generated**: 2026-10-18, evening
**Branch**: `main` in both repos. tally-utility is at the wrap-up commit (after the -25 patch commit), pushed. GBM had no new commits at wrap-up: Kyle has not answered K-10 there.
**Status**:
- **-23** is blocked on Kyle. Ryan, 2026-10-18: "let's wait on Kyle"; r3 does not start before his answer.
- **-25** is drafted and fully tested. It is not frozen or reviewed.

## Goal

Reach the C# core build. Ryan's gate, in order:
1. schema parity with CI-001…CI-135 (**we are here**: 78 of 135; re-graded only after a mirror);
2. scenarios and a test strategy;
3. a phase plan;
4. build.

Wave 2 is -22 (landed) and -23 (cash; r3 waits on K-10); -24 follows -23. Wave 3 is -25 (disputes, drafted) and -26 (collections decisions, field verification).

## Completed (this session, 2026-10-18 evening)

- [x] **Wave-3 source inventory** (`9b9057e`):
  - `application/wave3-build-2026-10-18/source-inventory-wave3.md`, with sources under `sources/`;
  - -25/-26 split;
  - four items for Kyle, none blocking.
- [x] **Q1** (`e1ce387`): Ryan, "go with the rule entries". Dispute policies are rule-terms rows, with one law table and one tariff table.
- [x] **Design** (`e7a056f`): `application/wave3-build-2026-10-18/v5.4.2-25-design.md`. Its "Built" section records what the build settled and the test corrections.
- [x] **Tests first** (`bfe4f21`), then **the patch** (`sql/v5.4.2-25-disputes.sql`; Ryan: "go ahead with the patch"):
  - `law/dispute/` holds the schemas, `dispute_rules.yaml` and its seed, and the examples;
  - `law/fixtures/dispute-states/`.
- [x] **Results:**

  | Check | Result |
  |---|---|
  | battery-25 | 201/201 |
  | races DR1–DR9 | 12/12 |
  | terms-25 | 0 failures |
  | migration P0–P4 | pass |
  | mutations-25 | 110/110 |
  | `tests/ci.sh` | all pass, 44 steps |
- [x] **CI wiring:** -25 is in the PENDING list. The migration runs on `ci_pre25`, the base cloned just before -25 applies (CI drops it at the start of each run).
- [x] **battery-19 RW6** no longer writes `meter_readings.dispute_reason` (dropped by T2).
- [x] **Go-live dashboard data:**
  - wave 3 is in progress;
  - W3-Q1 is in the decision queue;
  - dates unchanged (likely ready-to-onboard is still 2027-06-16).

## Not Yet Done

- [ ] **Kyle's K-10 answer**, then the -23 r3 plan. The merged round-2 findings are in the previous handoff (`git show 90b325c:HANDOFF.md`, "Not Yet Done"), split into "either answer" and "depends on K1". Fetch GBM first.
- [ ] **-25 review:** freeze it (brief plus md5s, as `tests/v5.4.2-23/review/review-brief-23-r2.md`) and send it to all three reviewers (Opus, Fable, Codex).
  - **Default order:** after -23 r3 settles, so the reviewers see -25 on the -23 it builds on. Ryan may say sooner.
  - **Mirroring:** -25 mirrors only after -23.
- [ ] **-25 known gaps** (in the design's "Built" section, and as residuals R1–R7 in the patch header):
  - no race test exercises the reading-status move's dispute locks;
  - Gov't Code 2251 has no governmental class (R1);
  - the status move is a SECURITY DEFINER trigger function owned by the migration role (R7). Reviewers should weigh it against the NOLOGIN-owner pattern of -20.
- [ ] **-26:** collections decisions and field verification (inventory sections E and F).
- [ ] **Four items for Kyle** (inventory, "For Kyle"), none blocking:
  - the day-26 elderly bar;
  - the extreme-weather forecast is the high;
  - closed days are the utility's staffed days;
  - *Craft* due process for cities.

  Ryan decides when to send them.
- [ ] **After -23 mirrors:**
  - re-grade the parity measurement;
  - add a GBM manifest section;
  - add a DEPLOY-VERIFICATION entry;
  - update memory.
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

- **Expecting document order from a rule table.** The -17 template stores owner types and every text[] facet distinct and sorted. Compare sorted values (K3, K5, U2 were wrong).
- **Running `pg_temp.deferred()` as one tenant's operator** while other tenants' fixtures still have checks pending. `SET CONSTRAINTS ALL IMMEDIATE` fires every pending deferred trigger as the current role, and RLS hides the other tenants' rows. Flush the fixtures' checks as the owner first.
- **Testing a no-truncate guard with a plain TRUNCATE on a referenced table.** PostgreSQL refuses it (0A000) before any trigger runs. Use CASCADE, so only the guard can refuse.
- **Guard pieces another check always beats** (a tenant check where RLS answers, depth fences next to an event-match check, an early return before a CHECK). They can't be mutation-tested; remove them.
- **A mutation's named check must be the first failure.** When another test rightly catches it first, rename it (DR7b, DR3, R3). When nothing catches it, add a test (N8). Never loosen the runner.
- **Earlier failures still hold:**
  - the refund exemption keyed on `reference_id` (-23);
  - an untested exempt path;
  - a header default with no code behind it;
  - `pg_stat_clear_snapshot()` in barrier polls;
  - never edit tests during a mutation run;
  - `codex exec` with the prompt as an argument needs `< /dev/null`.

## Key Decisions

| Decision | Rationale |
|---|---|
| Dispute policies are rule entries (Ryan, wave-3 Q1) | One law table and one tariff table; the comparator keeps a utility's policy no looser than the law |
| Determinations are written by tally_app with `calculated_by` | The nearest decision record, `deposit_return_due` |
| The database writes the opened event and moves the status | Guards must act: the status cannot disagree with the events |
| `shelter_ends_on` is the last sheltered day, inclusive | TX gas: April 29 for a March 1 bill (day 60 counting the issue day) |
| `within_days` compares only with its own kind, same anchor | Fail toward protection; a window against "before delinquency" depends on the due date |
| No lines means pro rata over the bill's positive lines | Stated in the reader's `basis`; cumulative rounding keeps the parts exact |
| Wait for Kyle before -23 r3 (Ryan, carried) | Under K1 = A the refund exemption and three blockers are deleted, not fixed |

## Current State

**Working:**
- tu.sql through -22;
- -23 r2 and -25 pending;
- `tests/ci.sh` all pass (44 steps);
- -25: battery 201, races 12/12, terms 0 failures, migration pass, mutations 110/110.

**Broken (known):** -23 r2's round-2 findings (unchanged; repros in `tests/v5.4.2-23/review/`).

**Uncommitted changes:** none after the wrap-up commit.

**Scratch DBs** in tally-pg (throwaway; drop them freely): `q25` (tally + -23 r2), `p25` and `r25` (+ -25), `ci_pre25` (left by CI; the mutation runner's default base).

## Code Context

```sql
-- the reader the core and collections read (both coordinates required, 22004 otherwise)
public.dispute_shelter_as_of(p_invoice_id uuid, p_on date, p_recorded_at timestamptz)
  RETURNS TABLE (dispute_id, determination_id, outcome, sheltered_amount, must_pay_amount, shelter_ends_on, blocks text[])
public.dispute_line_shelter_as_of(p_line_id uuid, p_on date, p_recorded_at timestamptz)
  RETURNS TABLE (dispute_id, determination_id, sheltered_amount, basis)   -- basis 'lines' | 'pro_rata'
-- lock order: the dispute's advisory lock (dispute_lock: RC only, 25000) -> cited law row (shared) -> cited tariff row (shared)
-- every refusal the patch raises carries its tag, e.g. [D4h]; the battery matches on it
```

```bash
S=<scratchpad>/fresh.sh          # recreate if gone: clone q25 -> <db>, REVOKE TEMP, strict-apply -25
bash tests/v5.4.2-25/races/disputes-25.sh <throwaway db>
python3 tests/v5.4.2-25/migration-25.py <pre-25 base>          # ci_pre25 after a CI run
M25_BASE=ci_pre25 python3 tests/v5.4.2-25/mutations-25.py [--anchors] [M01 ...]   # ~25 min for 110
tools/law/.venv/bin/python tests/v5.4.2-25/terms-25.py
```

## Resume Instructions

1. `git pull --ff-only` in tally-utility, and `git fetch` in `../gas-billing-memory`. Look for Kyle's K-10 answer there; ask Ryan about Slack.
2. `bash tests/ci.sh`.
   - Expected: all pass. The -17 RC5 race can flake under load: rerun it alone (`tests/v5.4.2-17/races/rule-close-17.sh ci_base <scratch>`).
   - If `tally-pg` is missing: `bash tests/ci.sh --build`.
3. **If Kyle has answered:** write `application/wave2-build-2026-10-15/v5.4.2-23-r3-plan.md`, implement it with the refund-posting tests first, re-run CI and the mutations, then freeze r3 for all three reviewers.
4. **If not:** ask Ryan whether to freeze -25 for review now or start the -26 inventory work (sections E and F). Do not start -23 r3.

## Warnings

- **Never edit the frozen review copies** (`tests/v5.4.2-*/review/*-frozen-*`) or tu.sql's mirrored bodies.
- **Revoke TEMP from PUBLIC, `tally_app` and `tally_core` after every `CREATE DATABASE … TEMPLATE`.**
- **Don't edit the patch or tests while a mutation runner runs.** It re-reads them for every mutation.
- **The -25 patch embeds** `law/dispute/*.schema.json` and `dispute_rules.seed.sql` verbatim. Edit the files, re-emit with `lawc.py emit`, and re-embed; lawfiles W2/W4 check it. The tariff schema is derived from the law schema: `python3 tools/law/derive_dispute_tariff_schema.py law/dispute/dispute.v1.schema.json law/dispute/dispute_tariff.v1.schema.json`.
- **Codex:**
  - only under nvm v24.15.0;
  - run it as `codex exec -s workspace-write -C <repo> -o <final.txt> "$(cat prompt)" < /dev/null`.
