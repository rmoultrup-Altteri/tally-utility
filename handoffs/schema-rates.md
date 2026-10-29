Folder: `~/code/tally-utility-rates`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: schema stream "rates" — tax, gas cost, zones, reads, dated history

**Generated**: 2026-10-29 (written from the money stream's folder; this stream has not run yet)
**Branch**: `main`. This clone was made 2026-10-29 at `56eec8c`; `git pull --ff-only` first.
**Status**: Not started. Waiting for Ryan to open the first session here.

## Goal

Close the rates half of the 56 open invariants, beside the money stream (`~/code/tally-utility`). Ryan decided on 2026-10-29 to run the schema as two streams on tables that don't overlap (DECISION-LOG 2026-10-29). Estimate about 23 likely working days for this stream.

## How this stream differs from working alone

- Read the board (`HANDOFF.md`) at session start and before every mirror: table ownership, the mirror queue, patch numbers, notes from the other stream.
- Claim a patch number on the board (commit and push the board edit) **before** creating the patch file. The next free number is on the board.
- Touch only this stream's tables (the board lists them). If a patch here needs a change to a money table, leave a note on the board for the money stream instead.
- Add a new patch to `tests/ci.sh`'s `PENDING` list only once its battery passes on its own, so a broken draft here never turns the money stream's CI red.
- `tests/ci.sh` holds a lock across all clones. If it says "waiting", another stream is running it.
- This clone has no `tools/law/.venv`; `ci.sh` uses the main checkout's. Mutation and battery runners that call it directly need `LAWC_PYTHON=~/code/tally-utility/tools/law/.venv/bin/python`.

## Not Yet Done (in order; each patch starts with a source inventory, as usual)

1. [ ] **Small fixes** (a good first patch to shake out the two-stream process):
   - CI-010: `customer_is_state_agency_as_of` hard-codes `America/Chicago`; call `premise_time_zone_as_of`;
   - CI-089: drop the prompt-pay discount rule type (K-06: no early-pay discounts);
   - CI-091: meter test fee driven by the test outcome, tolerance and fee as rule data (K-06);
   - CI-101: the rider dependency order is not effective-dated, and a retirement is transaction time only (-21 R3);
   - CI-109: rounding to the cent, half-up; rates and intermediates to four decimals (K-06).
2. [ ] **Tax jurisdictions, tax stacking, franchise fees** (CI-044, CI-045, the tax half of CI-001/004). Kyle 2026-10-14: a jurisdiction is a place. `franchise_fee_rules` keys on `city_name` and needs a place, a line-to-rule link and the remittance record. Sources: `application/kyle-brief-2026-10-13-tax-jurisdictions-and-gas-cost.md` and Kyle's answer in GBM.
3. [ ] **Gas-cost billing side** (CI-037 transport vs. sales, K-04: neutral terms plus a per-jurisdiction label table; CI-038 pipeline safety fee as a dated rule, no fixed Texas cap, confirm against 16 TAC §8.201). Also settle `pga_monthly_reconciliations.deferred_balance_after` (a column for a record the platform doesn't keep, CI-036).
4. [ ] **Heating-value and pressure zones and their factor tables** (CI-020, CI-026, the factor half of CI-001/004). K-02: tenant-defined zone sets per factor, effective-dated, assigned to a location or meter.
5. [ ] **Which meter a read belongs to, and replacement reads** (CI-027; CI-030, K-03: a replacement points to the one it replaces, which is marked superseded, with a required reason code), plus the old -05 meter-reading defect (`grep -n "\-05 defect" changelog-archive/2026-10.md`).
6. [ ] **Dated history** (wave 6: CI-087, CI-104, CI-120, CI-133, the meter-parameter half of CI-001/004). This changes what existing columns mean (a scalar becomes a dated history), so settle the shape before data exists. -26 (money) uses `meter_deployments`, so **this patch waits until -26 mirrors**, or coordinates through the board.
7. [ ] **Carried over (this stream's):** the backbilling tariff table.

Each item's open half is spelled out in `application/invariant-parity-measurement-2026-10-13.md` (`grep -n "^| CI-NNN "`, and the dated Update sections override the full table). Kyle's rulings K-02, K-03, K-04 and K-06 are in GBM `application/kyle-decisions-2026-10-15-waves-1-to-7-and-texas-first.md`.

## Not this stream's

- The cross-tenant link fix (CI-116) and Kyle's version check on every edited record (K-01) touch nearly every table. They run after both streams finish (the board).
- The reconnect technician check (CI-072) touches `service_orders`, which -26 changes: money stream.

## Warnings

- **Revoke TEMP after every TEMPLATE clone.**
- **Never edit the frozen review copies or tu.sql's mirrored bodies.**
- **Don't edit a patch or its tests while its mutation runner is running.**
- Before writing or reviewing patch code, read the index at the top of `sql/PATCH-LESSONS.md`.
