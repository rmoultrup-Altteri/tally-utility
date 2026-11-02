Folder: `~/code/tally-utility-rates`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: schema stream "rates" — tax, gas cost, zones, reads, dated history

**Generated**: 2026-11-02 (end of this stream's first session)
**Branch**: `main`; `git pull --ff-only` first. Last rates commit at wrap-up: see `git log --oneline -3`.
**Status**: v5.4.2-28 round 1 reviewed (Opus not yet, Fable ready, Codex not yet). The round-2 fix list is written. **One Ryan decision remains before building round 2** (below).

## Goal

Close the rates half of the 56 open invariants, beside the money stream (`~/code/tally-utility`). About 23 likely working days for this stream (DECISION-LOG 2026-10-29).

## How this stream differs from working alone

- Read the board (`HANDOFF.md`) at session start and before every mirror: table ownership, the mirror queue, patch numbers, notes from the other stream.
- Claim a patch number on the board (commit and push the board edit) **before** creating the patch file. Next free: **-29**.
- Touch only this stream's tables. A needed change to a money table goes to the board as a note.
- A new patch joins `tests/ci.sh`'s `PENDING` list only once its battery passes on its own.
- `tests/ci.sh` holds a lock across all clones. If it says "waiting", another stream is running it.
- This clone has no `tools/law/.venv`; runners that call it directly need `LAWC_PYTHON=~/code/tally-utility/tools/law/.venv/bin/python`.

## Where -28 stands

`sql/v5.4.2-28-rates-small-fixes.sql`, three sections:
1. **The state-agency check's day boundary (CI-010):** the pipeline safety fee's state-agency exemption is judged at midnight in the bill's own zone (`invoice_time_zone_as_of`; a consolidated parent's live children must agree). `customer_is_state_agency_as_of` takes the zone as a third argument.
2. **Rider dependencies dated in place (CI-101):** `rate_item_dependencies` becomes bi-temporal, like `rate_schedule_items`. -21's retire becomes close-as-retracted. New read `rate_item_dependencies_as_of`.
3. **Four-decimal rates (CI-109):** CHECKs on `rate_item_versions.rate_value`, the tier rates in `tier_config`, and `rate_schedule_items.rate_override`.

Not in -28: the prompt-pay discount (CI-089) needs no SQL; it is a parity re-grade after the mirror. The meter test fee (CI-091) is its own patch after dated history (item 6).

Tests: `tests/v5.4.2-28/battery-28.sql` (77 PASS), `mutations-28.sh` (11/11, database `m28`), plus the ported -19/-21 batteries and races `cycle-19.sh`, `labels-21.sh`. Full `ci.sh` passes except battery -15 case V23, which is the money stream's (a fixed date that has passed; board note).

Round 1 is frozen in `tests/v5.4.2-28/review/` (md5s in `review-brief-28-r1.md`). Reviews: `opus-r1.md`, `fable-r1.md`, `codex-r1.md` (Codex's probes and their output in `codex-r1-probes/`).

**The round-2 fix list:** `application/rates-build-2026-11-02/v5.4.2-28-r2-plan.md`. It is the summary of the three reviews; open a review file only for one finding's evidence. In short:
- **B1** the tier jsonpath does not survive dump and restore: use `@ * 10000 % 1 != 0`, re-anchor mutation N10, add a reparse test, and a PATCH-LESSONS lesson.
- **B2** a close without a reason passes: `closed_reason IS NOT NULL AND ...`.
- **B3** pick the zone branch from `is_consolidated`, not from having a premise; refuse a child that is itself consolidated.
- **B4** settled (below): known limit L6, no code.
- **S1** the cycle walk: `(d.recorded_until IS NULL OR d.recorded_until > NEW.recorded_at)` and a two-session race test.
- **S2** refuse NaN in the four-decimal checks.
- **S3** the tier check's comment states its scope.
- **S4** tests: D7c made real plus a header-bump mutation; the mutation runner fails on a mismatched check; mutations for the override CHECK, the `changed_by` stamp, Z5h and the trigger order; rename K3b; say what D3c and K-del prove.
- **Percentage rates** (settled, below): the refusal message on a `decimal`-unit rate says percentages are stored in percent; add a battery case.

## Ryan's decisions this session (all in DECISION-LOG, 2026-11-02)

- -28 scope: the time zone option 1, CI-091 moved out, dated dependencies option 1, four-decimal rates option 2.
- **A consolidated (summary) bill is fixed once it goes out** (option 1): every member bill is final at issue, and nothing attaches after. This is the money stream's rule; the board note is sent. -28 lists it as known limit L6.
- **Percentage rates are stored as a percent, to four decimals.** The app accepts fractions or percent as the clerk types them, converts, and shows the utility's preferred form (APPLICATION-CONTRACTS AC-45). -28's check is unchanged.

## Open: one Ryan decision (asked, not answered)

**Read the zone only when it can change the answer** (Opus S3; the plan's "For Ryan" item 3). Today the check reads the bill's time zone for every non-zero fee under an exempting rule. Only El Paso and Hudspeth counties have a zone loaded, so a fee anywhere else is refused until that county's zone is loaded (known limit L1).
- **Option 1:** keep it. Costs a data load of each served county's zone before the first bill.
- **Option 2 (recommended):** check the state-agency status at the earliest (UTC+14) and latest (UTC−12) possible midnight; if they agree, use that answer with no zone lookup. Read the zone, refusing if it is missing, only when they disagree. Load the county zones anyway as ordinary data.

The question put to Ryan: does it bother him that, under option 2, a missing zone surfaces only on the rare bill where it matters?

Ask it again in plain language (one decision per message), record the answer in the DECISION-LOG, then build round 2.

## Next steps

1. Get Ryan's answer on the zone read and record it.
2. Build round 2 from the plan. Don't edit the patch while its mutation runner runs.
   - Strict apply twice; the battery; the mutations; the races; a dump and restore of a clone (B1); the full `ci.sh` (one run at a time).
3. Freeze round 2 (`*-frozen-r2.*`, a new brief with md5s). Launch all three reviewers:
   - **Opus and Fable** as agents with their own scratch databases. They report in several messages, each under 3 KB.
   - **Codex:** `PATH=~/.nvm/versions/node/v24.15.0/bin:$PATH codex exec -s workspace-write -C <repo> -o <out> "<prompt>" < /dev/null`. Wait on its output file, not on `pgrep`. Codex writes probe files only; the author runs them.
4. After the reviews say ready and Ryan approves: mirror onto `tu.sql` (the board's mirror queue: -28 is 4th), re-grade CI-010, CI-089, CI-101, CI-109 in the parity measurement.
5. Then items 2–7 below.

## Not Yet Done (after -28)

2. [ ] **Tax jurisdictions, tax stacking, franchise fees** (CI-044, CI-045, the tax half of CI-001/004). Sources: `application/kyle-brief-2026-10-13-tax-jurisdictions-and-gas-cost.md` and Kyle's K-09 in GBM.
3. [ ] **Gas-cost billing side** (CI-037, K-04; CI-038 pipeline safety fee as a dated rule; `pga_monthly_reconciliations.deferred_balance_after`, CI-036).
4. [ ] **Heating-value and pressure zones and their factor tables** (CI-020, CI-026, K-02).
5. [ ] **Which meter a read belongs to, and replacement reads** (CI-027; CI-030, K-03), plus the old -05 meter-reading defect.
6. [ ] **Dated history** (CI-087, CI-104, CI-120, CI-133). Waits until -26 mirrors, or coordinates through the board. Then the **meter test fee** (CI-091, K-06).
7. [ ] **The backbilling tariff table.** The scenarios stream's board note: city-owned systems can make no backbilling correction until it exists.
8. [ ] Later rates patch: retire the `decimal` rate unit (AC-45).

## Not this stream's

- The cross-tenant link fix (CI-116) and the version check on every record (K-01) run after both streams.
- The reconnect technician check (CI-072): money stream.
- Freezing a summary bill's members at issue, the bill-line rates' four-decimal check, and the UTC day boundaries in deposits and period close: all money stream's (board notes).

## Warnings

- **Revoke TEMP after every TEMPLATE clone.** At most two mutation runs at once.
- **Never edit the frozen review copies or tu.sql's mirrored bodies.**
- **Don't edit a patch or its tests while its mutation runner is running.**
- Before writing or reviewing patch code, read the index at the top of `sql/PATCH-LESSONS.md`.
- Ryan wants plain language with no shorthand codes in what he reads, and one decision per message.
