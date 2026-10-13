# Handoff: the deposits rewrite (-15) — patch written and frozen at round 5; Opus and Fable READY, Codex still to review

**Generated**: 2026-10-13
**Branch**: `main`. **-15 is mirrored**: `sql/tu.sql` 36,712 lines (md5 `95f79924acda06445b518db545365e61`), from the frozen r8 patch (md5 `2dc8f61cda3bc6958ca42737d317a629`). `tests/ci.sh --build` all pass.
**Status**: Landed. Only decision 1 is left for Ryan (below); everything else is optional follow-up.

## Goal
Rewrite the never-mirrored deposits draft `sql/v5.4.2-15-deposits-law-to-core.sql` onto the rule-terms convention (-17 template, -18 worked example): law is a document per (state, service, owner types, class, basis); the utility has its own categories and one tariff per category; every record cites the law row and, when one applied, the tariff row.

## Completed
- [x] Patch `sql/v5.4.2-15-deposits-law-to-core.sql` (~5,240 lines): vocabularies, kinds `deposit` v1 / `deposit_tariff` v1, `deposit_rules`, categories, `deposit_tariffs` + `deposit_tariff_compare`, rate floor, citing records, return-due record, 8 Texas rows + 8 city delegations, -06 law dropped, residuals R1-R12. Applies strictly (`search_path=''`, `check_function_bodies=on`) in one transaction; a re-run is skipped whole.
- [x] Tests: `tests/v5.4.2-15/battery-15r.sql` 334 checks (all pass, each block passes alone via `fail-first.py`); `mutations-15r.py` 166 mutations, all caught; `migration-15r.py`, `races/due-mutex-15.sh`, `evidence-txn-15.sh` pass.
- [x] Four review rounds folded in (r1-r4 reports in `tests/v5.4.2-15/review/`), then round 5 = Opus's one should-fix: `enforce_deposit` refuses a deposit with a category and no `tariff_id` when a tariff row is in force for that category on the posting date (patch 4150-4158; R53; M167). R10/R13 now use categories with no tariff (`nt`, `notariff`) so each is refused by its own guard alone. R7 wording says a months tariff under a highest-bills/seasonal cap is neither compared nor held and a stricter combined condition / longer notice is refused.
- [x] Round 5 frozen: patch md5 `fb44ecc041cb2f6004171dd3723962bb`, battery md5 `1c93db1658445380739edd198b0e3543`. **Opus READY, Fable READY** (both verified hashes, clean strict apply, 334/334, M167 caught at R53).

## Not Yet Done
- [ ] Ask Ryan decision 1 in one line, plain language: a deposit's own closed law row stays citable after its close ("grandfathered"). Not blocking.
- [ ] Optional, non-blocking, from the round-8 reports: extend V28b/c to terminal refunds/releases (Codex); a one-statement due row + citing notice + uncited `refunded` is refused where two statements are accepted, fails closed (Opus N1); a live due row beside an uncited notice in two statements is accepted, a cited due row may still be withdrawn, a zero refund can close a deposit with unpaid instalments (all the core's conventions).
- [ ] Carried over: backbilling tariff table; GitHub Actions version bump; verify Florida's official text (25-7.083) before loading any Florida row; the waiver-determination rewrite (residual R6) waits for a core that records determinations.

## Rounds 6-8 (2026-10-13), what each fixed
- r6: Codex r5 B1 — a later-dated instalment funded an earlier return; dated-principal timeline guard at the end of `enforce_deposit_event`; stale comments.
- r7: Opus r6 B1 — status checks lag inside a multi-row INSERT (AFTER ROW projection); refund state now read from events; refund not dated before its notice.
- r8: all three on r7 — the return-due BEFORE check lags too; new AFTER INSERT trigger `z_enforce_deposit_return_due_not_started`. Lesson: a BEFORE ROW check cannot see the other parts of a writable WITH; judge it after the statement.
- Reviewers: Codex has no Docker (read-only reviews); Opus/Fable run as named agents `opus-r6` / `fable-r6` (SendMessage); old agent ids are gone.

## Failed Approaches (Don't Repeat These)
- **`timeout` in shell probes**: macOS has none → `(eval):1: command not found: timeout`, exit 127, the run never starts → run the command directly, or poll a log file.
- **`until ! pgrep -f script` wait loops**: the loop matches itself → never ends → poll the run's output file (memory `monitor-pgrep-self-match`).
- **Skipping Codex because its quota ran out**: not allowed → memory `all-three-reviewers-before-mirror`: wait for it on the frozen revision, then ask Ryan to mirror.
- **Mutations shadowed by a second guard** (M43/M45, R10/R13 after the new tariff-citation guard): the mutated guard was not the first to refuse → give each check a fixture that only its guard can refuse (categories with no tariff).
- **Codex probe**: `codex exec` still prints `You've hit your usage limit … try again at Oct 13th, 2026 12:59 AM.` at 21:47 CDT Oct 12.

## Key Decisions
| Decision | Rationale |
|----------|-----------|
| Ryan's five (2026-10-12): customer type stays on the utility's own rate; one tariff per utility/state/service/category; v1 scope with 6 shapes refused; state rate is a floor; utility defines its own categories mapped to one law class | See memory `deposits-rewrite-decisions` |
| **Mine, unconfirmed:** a deposit's own closed law row stays citable after its close | A deposit decided under a row must keep citing it; Fable asks Ryan to confirm |
| **Mine:** a partial return needs no due row | The due record covers what is owed in full |
| **Mine:** no count-event vocabulary; triggers matched by condition leaves | Avoids a second vocabulary for the same thing |
| **Mine:** a non-superuser owner is refused, untested | Same as -18 |
| A deposit with no category may skip every tariff (Opus r5 note N1) | Which category an account belongs to is the core's call; the statutory cap still holds. If closed later: require a category when the utility defined one for that state/service/class |

## Current State
**Working**: patch applies strictly; 356/356; 175/175 mutations; migration, races, evidence-transaction checks.
**Broken**: nothing known.
**Uncommitted changes**: none after the wrap-up commit.

## Code Context
Run (from repo root; psql-only patch):
```
docker exec tally-pg psql -U tally -d postgres -c "CREATE DATABASE <you>15 TEMPLATE tally"
docker exec tally-pg psql -U tally -d <you>15 -c "REVOKE TEMP ON DATABASE <you>15 FROM PUBLIC, tally_app, tally_core"
(echo "SET search_path = ''; SET check_function_bodies = on;"; cat tests/v5.4.2-15/review/patch-15r-frozen-r5.sql) | docker exec -i tally-pg psql -U tally -d <you>15 -v ON_ERROR_STOP=1 -q -f -
```
`CREATE DATABASE … TEMPLATE` drops the ACL, hence the REVOKE. Never touch `tally` / `postgres`.
Codex: `PATH=~/.nvm/versions/node/v24.15.0/bin:$PATH codex exec -s workspace-write -C ~/code/tally-utility -o tests/v5.4.2-15/review/codex-r5.md -` with the brief on stdin.

## Resume Instructions
1. `git fetch` both repos (tally-utility, gas-billing-memory); read anything Kyle pushed first.
2. Ask Ryan decision 1 (one line).
3. Then ask what is next (the backbilling tariff table, or the core).

## Warnings
- Never edit the patch while reviewers test; one revision per round, hashes in every request.
- Nothing is live: the patch refuses to run over any non-legacy deposit, waiver determination or rate row. That is intentional.
- tu.sql is append-only; the mirror is done. A change to -15 is a new patch file.
- Explain codes (R53, M167, N1) in plain language when asking Ryan to decide anything.
