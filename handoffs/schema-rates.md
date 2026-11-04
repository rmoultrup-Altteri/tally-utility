Folder: `~/code/tally-utility-rates`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: schema stream "rates" — tax, gas cost, zones, reads, dated history

**Generated**: 2026-11-04 (end of this stream's second session)
**Branch**: `main`; `git pull --ff-only` first. Last rates commit at wrap-up: see `git log --oneline -3`.
**Status**: v5.4.2-28 is **mirrored**. v5.4.2-29 round 2 is **frozen**: Opus and Fable said ready on round 1, and Codex has not reviewed it. **One Ryan decision is open** (below).

## Goal

Close the rates half of the open invariants, beside the money stream (`~/code/tally-utility`). Parity now stands at 85 of 135 after money's -23 mirror (81 after -28). About 23 working days for this stream from 2026-10-29 (DECISION-LOG 2026-10-29).

## How this stream differs from working alone

- **The board** (`HANDOFF.md`): read it at session start and before every mirror. It holds table ownership, the mirror queue (now -25, -26), patch numbers and notes from the other streams.
- **Claiming a patch:** claim its number on the board (commit and push the board edit) **before** creating the patch file. Next free: **-30**.
- **Tables:** touch only this stream's. A needed change to a money table goes to the board as a note.
- **`tests/ci.sh`:** a new patch joins its `PENDING` list only once its battery passes on its own. The script holds a lock across all clones; if it says "waiting", another stream is running it. A data patch can be pending by an SQL condition: a `?` marker, as -29's `P29_PENDING`.
- **Law runners:** this clone has no `tools/law/.venv`. Runners that call it need `LAWC_PYTHON=~/code/tally-utility/tools/law/.venv/bin/python`.

## Where -29 stands

`sql/v5.4.2-29-texas-counties.sql` is data only.
- **What it loads:** the 252 Texas counties that -16 did not seed. Each gets a `places` row (the Census FIPS code and name, parent Texas, from 1900-01-01) and one `time_zone` fact. El Paso and Hudspeth are Mountain (seeded by -16, checked, not reloaded); every other county is Central. Culberson is Central by law (known limit L2).
- **Its sources:** `application/places-sources/census-st48_tx_cou2020.txt` and 49 CFR 71.6(a), 71.7(e) and 71.8.
- **Its rules:**
  - A county already present on 1900-01-01 must match; otherwise the whole load refuses.
  - Afterwards, the counties in force on 1900-01-01 are exactly the list.
  - Re-applying is a no-op, even after later corrections.
- **Tests** (round 2):
  - `tests/v5.4.2-29/battery-29.sql`: 22 PASS.
  - `reapply-29.sh`: 10/10, database `r29re`. It runs in CI only while -29 is pending.
  - `source-check-29.sh`: 5/5, no database.
  - `mutations-29.sh`: 19/19, databases `m29` and `r29re`.
  - `ci.sh` on `tally` with -23: 53 pass; only battery -15 V23 fails (the money stream's).
- **Older tests changed:** batteries -16 and -28 and race place-close-16 no longer plant real county codes. They use even codes 48990–48998; real Texas codes are odd. The board says a new fixture must not use a real code.
- **Review:**
  - Round 1 is frozen in `tests/v5.4.2-29/review/`, with `opus-r1.md` and `fable-r1.md`. Codex hit its usage limit (`codex-r1-usage-limit.log`).
  - Round 2 is frozen beside it: `review-brief-29-r2.md` with its md5, and `codex-prompt-r2.md`, ready to run.
  - The fix list is `application/rates-build-2026-11-04/v5.4.2-29-r2-plan.md`.

## Open: one Ryan decision (asked, not answered)

**Codex on -29.** The rule is three reviewers before a mirror, unless Ryan waives one (he waived Codex for -19). Codex's usage limit reset at 18:56 CST on 2026-11-04.
- **Option 1 (recommended):** run Codex on round 2. Nothing is blocked on -29, and Codex has found what the other two missed before.
- **Option 2:** mirror on Opus's and Fable's reviews. It is a small data load whose data is checked mechanically against the Census file.

## Next steps

1. **Get Ryan's answer on Codex.** If he wants it, run it:
   - `PATH=~/.nvm/versions/node/v24.15.0/bin:$PATH codex exec -s workspace-write -C ~/code/tally-utility-rates -o tests/v5.4.2-29/review/codex-r2-final.txt "$(cat tests/v5.4.2-29/review/codex-prompt-r2.md)" < /dev/null > tests/v5.4.2-29/review/codex-r2.log 2>&1` in the background.
   - Wait on its output file, not on `pgrep`.
   - Run its probes on a fresh clone of `tally` with frozen r2 applied, and append the results to `codex-r2.md`.
2. **Fold in findings.** Test-only additions don't change the patch. A patch change means round 3.
3. **On Ryan's approval, mirror -29.**
   - **Pre-mirror check (the board):** first check `ci.sh` is quiet and no other stream is running the database. Revoke TEMP after every clone.
   - **Append and build:** append the patch body to `tu.sql` with the mirror banner, then `ci.sh --build`. The schema must equal `tally` plus the frozen patch. Also check the init md5 and that TEMP is off for every role.
   - **Re-apply:** re-applying over the build must be a no-op.
   - **CI:** take -29 out of `PENDING`. `reapply-29.sh` then stops running in CI (it needs a pre-29 base).
   - **Records:** DEPLOY-VERIFICATION, the DECISION-LOG, and the board (mirrored; a note to money that `tally` now holds every county). Add a GBM `wiki-ingestion-pending.md` section.
   - **Parity:** no invariant row changes, but CI-010's "what is left" loses its data clause. Note it in an Update section.
4. Then items 2–8 below.

## Not Yet Done

2. [ ] **Tax jurisdictions, tax stacking, franchise fees** (CI-044, CI-045, the tax half of CI-001/004). Sources: `application/kyle-brief-2026-10-13-tax-jurisdictions-and-gas-cost.md` and Kyle's K-09 in GBM. Cities and tax jurisdictions are later place loads. Settle there the 49 CFR 71.7(g) question: towns on the Texas–New Mexico line (Farwell, Texline) may be Mountain by law (-29 L3).
3. [ ] **Gas-cost billing side** (CI-037, K-04; CI-038 pipeline safety fee as a dated rule; `pga_monthly_reconciliations.deferred_balance_after`, CI-036). Kyle 2026-11-03: the gas cost factor is one locked figure per billing month, never split.
4. [ ] **Heating-value and pressure zones and their factor tables** (CI-020, CI-026, K-02).
5. [ ] **Which meter a read belongs to, and replacement reads** (CI-027; CI-030, K-03), plus the old -05 meter-reading defect. Kyle 2026-11-03: a human keying error may add usage, so the Texas law row that lets only a rate misapplication travel by reissue needs revisiting (SCN-0027 b).
6. [ ] **Dated history** (CI-087, CI-104, CI-120, CI-133). Waits until -26 mirrors, or coordinates through the board. Then the **meter test fee** (CI-091, K-06). Kyle 2026-11-03: a rate change states its split method (by days, read date or cycle) when entered, with no default.
7. [ ] **The backbilling tariff table.** Kyle 2026-11-03: where a city's ordinance is silent, refunds have no limit and undercharges take a six-month platform default until the city records its own rule (SCN-0019, SCN-0028). This replaces "unknown law is not permission" for city systems.
8. [ ] Later rates patch: retire the `decimal` rate unit (AC-45).

## Not this stream's

- The cross-tenant link fix (CI-116) and the version check on every record (K-01) run after both streams.
- The reconnect technician check (CI-072).
- These are the money stream's (all with board notes):
  - freezing a summary bill's members at issue;
  - an invoice attached under another utility's summary bill;
  - the four-decimal check on bill-line rates;
  - the UTC day boundaries in deposits and period close.

## Warnings

- **Revoke TEMP after every TEMPLATE clone.** At most two mutation runs at once.
- **Never edit the frozen review copies or tu.sql's mirrored bodies.**
- **Don't edit a patch or its tests while its mutation runner is running.**
- **Before a rebuild, wait for other streams' runs to go quiet.** The money stream rebuilt `tally-pg` at 14:26 CST on 2026-11-04 (for -23).
- Before writing or reviewing patch code, read the index at the top of `sql/PATCH-LESSONS.md`.
- Ryan wants plain language with no shorthand codes in what he reads, and one decision per message.
