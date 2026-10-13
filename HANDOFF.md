# Handoff: core-build gate step 1 — schema parity measured; finance gate resolved; Kyle brief ready to post

**Generated**: 2026-10-13 14:04
**Branch**: `main`, pushed, tree clean after this commit.
**Status**: In Progress. Deposits (-15) is mirrored and closed. The step-1 measurement exists; the next job is to price and sequence the open items while Kyle answers a brief.

## Goal

Reach the C#-core build. Ryan's gate (2026-10-13), no date, in order: (1) schema at parity with the invariants (CI-001…CI-135) and scenarios; (2) finish the scenarios and devise a testing strategy from them; (3) plan the build phases; (4) execute. We are in step 1.

## Completed

- [x] **-15 deposits landed and mirrored**: `sql/tu.sql` 36,712 lines, md5 `95f79924acda06445b518db545365e61`, from the frozen r8 patch (md5 `2dc8f61cda3bc6958ca42737d317a629`). Rounds r6–r8 this session: Codex B1 (a later instalment funded an earlier return → dated-principal timeline guard), Opus B1 (status checks lag in a multi-row INSERT → refund state read from events), all three on r7 (due-row check lags in a writable WITH → AFTER INSERT trigger `z_enforce_deposit_return_due_not_started`). Battery 356, mutations 175/175, `tests/ci.sh --build` all pass, catalog identity (11,020 lines) equal to the patched clone. AC-24/25 rewritten; `sql/DEPLOY-VERIFICATION.md` has the -15 entry. Commit `d71c857`.
- [x] **Decision 1 confirmed by Ryan**: a deposit's own closed law row stays citable after its close (patch residual R4).
- [x] **Per-invariant parity measurement**: `application/invariant-parity-measurement-2026-10-13.md`. 135 CIs vs the current schema: REP+PROT 34, REP 21, PARTIAL 61, GAP 12, BLOCKED 7. Done for step 1 = 55; open = 80. Seven read-only Sonnet agents; 629 evidence names matched to the live catalog; classifications not independently re-reviewed (conf: 65 high, 69 med, 1 low).
- [x] **Finance gate resolved**: Ryan accepted Kyle's D-2 for the receivables/reporting side. Released: accounting periods + close snapshot, GL code mapping, AR aging, bad-debt recovery type, revenue distribution matrix, finance parts of disputes/bankruptcy. **Carve-out**: gas-cost side (gas_purchases, per-class deferred PGA ledger, carrying cost, annual true-up; CI-033, 036) stays fenced for Kyle. Logged in `application/DECISION-LOG.md` (`d3ba0be`).
- [x] **Kyle brief written and marked READY TO SEND**: `application/kyle-brief-2026-10-13-tax-jurisdictions-and-gas-cost.md` (7 questions: 5 tax/A-8, 2 gas-cost). Ryan has the Slack text; he must attach/link the file (the repo is private).

## Not Yet Done

- [ ] **Ryan posts the Kyle brief** (Slack text was given; the file path is above). Then fold Kyle's answers when they arrive.
- [ ] **Price and sequence the 80 open items** from the measurement document (no size estimate exists yet). The 12 GAPs and the PARTIALs whose missing piece is a typed column, a transition record or an append-only guard are buildable with no ruling.
- [ ] Buildable now (finance gate released): `accounting_periods` + close snapshot (A4), GL code mapping as tenant config (A6), AR aging view (A7), bad-debt recovery posting type citing its write-off (CI-076), revenue distribution matrix as config (A-10, CI-048), disputes table (A-15 non-finance, CI-074).
- [ ] Hardening patch Ryan has not yet decided: stop `populate_reading_calculations` default-filling negative consumption on rollover (CI-022); the `void_released` guard hole in `enforce_reading_validation_workflow` (CI-025/030/031); `prorate_tier_breakpoints` default regressed to false (CI-108).
- [ ] Person-decisions still open (grouped in the measurement doc): Kyle — A-8 tax jurisdictions, Q-1 concurrent assertions, zone model for BTU/pressure/rate, reading-supersede pair, transport/sales vocabulary and PSF cap figure, Q-5 earmarking, rounding, city-owned gas protections. Ryan — seal `version` bumps (A-23), reversal rows carrying predecessor, enrollment transition record, `service_locations.customer_id` nullable vs occupancy table, composite tenant-bound FKs, extend rule-terms to estimation/late fees/program exclusions.
- [ ] Review the low/medium-confidence rows of the measurement before a decision rests on them. Unread trigger bodies: premise-place membership guard, tax-exemption lifecycle, surcharge-line freeze (agent C); CI-119 not traced to the end (agent F).
- [ ] Carried over: backbilling tariff table; GitHub Actions version bump; verify Florida's official text (25-7.083) before loading any Florida row; waiver-determination rewrite (residual R6) waits for a core that records determinations; optional -15 follow-ups listed in the round-8 reports (`tests/v5.4.2-15/review/*r8*.md`).
- [ ] Step 2 onward (scenarios, testing strategy, phase plan, build) has not started. `CONTEXT.md` still says no application code and no test scenarios exist.

## Failed Approaches (Don't Repeat These)

- **Reading events in a BEFORE ROW trigger to fix the due-row status lag**: Opus's first suggestion → a diagnostic trigger saw 0 events in one ordering, because which part of a writable `WITH` runs first is not fixed → judge cross-table facts in an AFTER INSERT row trigger (fires after every part of the statement). Memory `projection-checks-lag-in-one-statement`.
- **Unescaped apostrophe in a battery label** (`'… deposit's …'` inside a SQL string literal) → syntax error at the run's end that looked like a PASS count of 255 → check the run tail, not only the count.
- **`sed -i` on macOS without `''` in a `&&` chain** → failure left `$DB` unset and later commands ran against nothing → use `sed -i ''` and check each step.
- **Resuming the old Opus/Fable agent ids** → "No transcript found" → start fresh named agents (`opus-r6`, `fable-r6`) and message them by name.
- **Codex review with Docker**: the Codex CLI has no Docker access (permission denied on the socket) → its reviews are source-only; say what it could only read.
- **`timeout` in macOS shell probes**: no such command (exit 127). **`until ! pgrep -f script`**: matches itself. Poll a log file.
- **Asserting Texas tax facts in the Kyle brief** (state-level residential-gas exemption, combined-rate ceiling) → unverified in the repo → removed; the brief says each place carries a "taxes residential gas" fact.

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Mirror -15 without the patch's psql re-run gate and BEGIN/COMMIT | tu.sql is applied once to an empty database; the body is byte-identical to patch lines 73–5398 |
| "Pending" refund = a `refund_initiated` event exists (no cancel in this ledger) | Lets the guards read events instead of the lagging projection |
| Refund-date rule covers applications and returns, not only receipts | A whole-remainder return must not precede a later application either |
| Accept D-2 for the receivables/reporting side; hold the gas-cost side for Kyle | D-2 is silent on what the utility pays suppliers; "not a GL" is not shown to cover it |
| Measure parity per invariant against the live catalog, with REP (core evaluates) not counted as a gap | "Schema represents, core evaluates"; gives step 1 a finite list |
| Kyle brief: preferences stated as input only; other Kyle items listed as queued, not asked | Keeps the ask short; matches earlier briefs |
| New work lives in tally-utility `application/`, not gas-billing-memory | gas-billing-memory has an uncommitted `wiki-ingestion-pending.md` and a log-every-change rule |

## Current State

**Working**: -15 landed; `tests/ci.sh --build` passes (batteries 09–18, isolation, races, evidence, invariants); the `tally-pg` container is the fresh -15 build (leftover `ci_*` clone databases are normal).
**Broken**: nothing known. The parity table in gas-billing-memory (`application/schema-parity-plan.md`) is stale (2026-09-23) and the invariant register's grades are v5.2.1-era; neither was edited.
**Uncommitted changes**: None in tally-utility. gas-billing-memory has an uncommitted `application/wiki-ingestion-pending.md` and untracked `Clippings/` that predate this session; not touched.

## Code Context

Run the full suite (rebuilds `tally-pg`, destroys its databases):
```
tests/ci.sh --build
```
Clone for patch work (CREATE DATABASE … TEMPLATE drops the ACL, so revoke TEMP after every clone):
```
docker exec tally-pg psql -U tally -d postgres -c "CREATE DATABASE x TEMPLATE tally"
docker exec tally-pg psql -U tally -d x -c "REVOKE TEMP ON DATABASE x FROM PUBLIC, tally_app, tally_core"
(echo "SET search_path = ''; SET check_function_bodies = on;"; cat sql/<patch>.sql) | docker exec -i tally-pg psql -U tally -d x -v ON_ERROR_STOP=1 -q -f -
```
Codex: `PATH=~/.nvm/versions/node/v24.15.0/bin:$PATH codex exec -s workspace-write -C ~/code/tally-utility -o <out.md> - < brief.md`. Named reviewer agents: message `opus-r6` / `fable-r6` (SendMessage).
Never write test data to the `tally` or `postgres` databases; tu.sql is append-only (a change is a new patch file).

## Resume Instructions

1. `git fetch` both repos (tally-utility, gas-billing-memory); read anything Kyle pushed first (his rulings land on gas-billing-memory main).
   - Expected: tally-utility up to date at the wrap-up commit or later.
2. Ask Ryan whether the Kyle brief was posted and whether Kyle has answered; if so, fold the answers (new kyle-decisions file, update `application/DECISION-LOG.md`, the measurement doc's BLOCKED rows).
3. Price and sequence the 80 open items: open `application/invariant-parity-measurement-2026-10-13.md`, rate each PARTIAL/GAP small/medium/large with the migration-cost framing (schema vs core-only, additive vs meaning-changing), and propose an order. Raise decisions with Ryan one at a time in plain language, no codes.
   - Expected: a short sequenced list; the finance-released builds and the plain GAPs first.
4. Before relying on a measured call, re-verify the medium/low-confidence rows that matter against `sql/tu.sql` and the live catalog.

## Warnings

- Ryan wants one decision per message in plain language; spell out any code (CI-nnn, A-nn, R-nn) wherever he is asked to decide. Commit and push straight to main in tally-utility; do not branch or ask.
- Never edit a patch while reviewers test it; one revision per round, hashes in every request; all three reviewers (Opus, Fable, Codex) before a mirror.
- Do not build the gas-cost tables (gas purchases, deferred PGA ledger, carrying cost, true-up) until Kyle rules.
- The measurement is agent judgment backed by catalog name checks; it is not a re-review. Treat REP+PROT as "agent verified the objects exist", not as a proof of enforcement.
- Don't edit the invariant register from the measurement document; the list of stale entries is in it for a deliberate pass.
