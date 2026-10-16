# Handoff: v5.4.2-22 mirrored into tu.sql — next is v5.4.2-23 (cash)

**Generated**: 2026-10-16, about 4 PM CDT
**Branch**: `main` in both repos.
- tally-utility is at `eef5122`, clean and pushed (the wrap-up commit follows).
- GBM `main` is at `bab1da5` (manifest Section BR). `Clippings/` there is untracked on purpose: never commit it.

**Status**: -22 is done. -23 is not started.

## Goal

Reach the C# core build. Ryan's gate, in order:
1. schema parity with CI-001…CI-135 (**we are here**: now 78 of 135);
2. scenarios and a test strategy;
3. a phase plan;
4. build.

Wave 2 is two patches. -22 (periods and reporting, additive) has landed. -23 (cash, meaning-changing) is next.

## Completed (this session)

- [x] **r5 frozen (`6d3d709`); round 5:** all three ready.
  - Codex's 18 probes were executed and appended to `codex-r5.md`. Its S1 (post-then-close deadlock) was reproduced in two sessions.
  - Ryan chose to **fix the should-fix items before the mirror** over the default (mirror r5).
- [x] **r6 (`e3393f2`):**
  - lock order rewritten;
  - a history row whose `created_at` was chosen (`<> now()`) and falls before a tree row is refused for good (23514), while a row stamped at its transaction's start keeps 40001;
  - messages ("non-finite or future time") and the function comment fixed;
  - battery R11b/R11c, R12i–R12o; races CR16–CR18; mutations M73–M79.
- [x] **Round 6:** Opus and Fable ready, with lock-order wording findings. Codex hit its usage limit (reset 4:01 PM). **Ryan waived Codex for r6–r9.**
- [x] **r7 (`7c887f2`):**
  - the lock order is stated as a rule over the close's four rows (head, period, closing user, tenant), not a list;
  - races CR19 and CR20;
  - battery **R5b**, so M71 (and M54) are caught at one check every run.
- [x] **r8 (`6176902`):** comments only. The rule counts indirect waits and promises no complete list; every writer retries 40P01. Round 7: both ready.
- [x] **r9 (`f75f90e`):** comments only. The round-8 notes were fixed at Ryan's request rather than carried into -23. Round 9: both ready, nothing to fix.
- [x] **Mirror (`eef5122`), on Ryan's approval:**
  - tu.sql is 42,310 lines; the body is byte-identical to patch lines 347–1999 (r9 md5 `d3422f3d…`);
  - `tests/ci.sh --build`: 33/33, zero init errors;
  - schema identical to the -21 build plus frozen r9;
  - catalog identity 11,580 lines, md5 `48d462f3…`;
  - PENDING is empty.
- [x] **DEPLOY-VERIFICATION** -22 entry, including the deploy-time audit query (it must return 0 on the real database).
- [x] **Parity:** update 2026-10-16. CI-048, CI-076 and CI-110 are REP+PROT: 54 REP+PROT, 24 REP, 45 PARTIAL, 11 GAP.
- [x] **GBM** manifest Section BR.
- [x] **DECISION-LOG** entry for 2026-10-16 (round 5): fix before the mirror, and the 23514 split.
- [x] **Memory:**
  - `race-barriers-clear-stat-snapshot.md` (new);
  - `v5422-periods-landed.md` (new);
  - the waiver added to `all-three-reviewers-before-mirror.md`.

## Not Yet Done

- [ ] **v5.4.2-23, cash:** requirements M (add-only money, R-05, CI-013), X (reversals, R-02, CI-017), A (payment application, R-06/K-05/D7-1, CI-049/050), C, U (unapplied cash, CI-053), L (agency pledges, CI-056). They are in `application/wave2-build-2026-10-15/source-inventory-wave2.md`.
  - -23 is meaning-changing: frame each shape by its migration cost (memory).
  - Restate the ledger's and the close's lock order in -22's form.
- [ ] **Carried over:**
  - the reply to Kyle on D-2's location;
  - the -05 defect (`meters_last_validated_actual_reading_id_fkey`);
  - -21 R9;
  - the R-03 scoping (CI-014's remaining DELETE grants);
  - `pga_monthly_reconciliations.deferred_balance_after`;
  - the backbilling tariff table;
  - the GitHub Actions bump;
  - the Florida 25-7.083 text;
  - the waiver-determination rewrite;
  - low-confidence measurement rows;
  - the -15 r8 follow-ups;
  - gate steps 2–4.
- [ ] **Go-live roadmap dashboard:** refresh it at wrap-up per memory. It was not refreshed this session.

## Failed Approaches (Don't Repeat These)

- **Barrier loops polling `pg_stat_activity` without `pg_stat_clear_snapshot()`.** The view is snapshotted once per transaction, so CR15 and CR17 timed out ("barrier: race22_b_done never seen"). CR16 and CR18 passed only because the signal arrived before the first read. Clear the snapshot on every poll.
- **A deadlock list presented as complete.** Each of rounds 5–8 found a missing shape: the users row, write-then-close, the period row, a third party, and the single statement with edges and slug. State the rule (rows in order; holding a later one and waiting for an earlier one, directly or indirectly), give examples, and say that every writer retries 40P01.
- **A named mutation catch that depends on same-date row order.** M71 was caught at R10f in one run and at R12h in the next, because a ROWS frame orders ties arbitrarily. Use a fixture where no order passes (R5b: +150 and −50 on one date against 100). A mutation caught earlier for a valid reason gets its expected check renamed (M54 → R5b), never a looser runner.
- **Editing the battery while `mutations-22.py` runs.** The runner reads the live file on every mutation, and a bad quote (`adjustment's` inside a SQL literal) would have broken every mutation that ran after it. Edit between runs only.
- **R12i as proof that a retry succeeds.** In one transaction the later row is the transaction's own, so the retry meets it again. Only CR15, with two transactions, shows a retry succeed.
- **"email" listed as a unique users column.** It isn't. Check `pg_index` before naming key columns: users has id, tenant_id and cognito_sub; tenants has id and slug.
- **Earlier sessions' failures still hold:** link-only recursive joins with pinned plans; VACUUM before plan-sensitive tests; `query_canceled` escapes `WHEN OTHERS`; psql's `LAST_ERROR_SQLSTATE` after COPY; and the rest (see the CHANGELOG).

## Key Decisions

| Decision | Rationale |
|---|---|
| Fix the should-fix items and the notes before the mirror (r6, then r9) | Ryan's call, twice: tu.sql's mirrored text is never edited, so a wrong sentence there stays until -23 corrects it |
| Codex waived for r6–r9 | Ryan: "let's not wait for codex on this". Codex said ready on r5; after r5 only one small code change and wording followed |
| A chosen-time history row before a tree row gets 23514, not 40001 | A retry cannot change a chosen time; 40001 would spin a retry loop to its cap |
| The own-transaction 40001 case (owner only) is stated in R12, not coded | Telling "its own" apart needs subtransaction-aware xmin tests; the owner is the only one who can reach it |
| The lock order is a rule, not a list; writers retry 40P01 | Lists proved incomplete four times; no deadlock ever admitted a row or lost data |
| Mirror r9 exactly as frozen | Those are the bytes both reviewers passed |

## Current State

**Working:**
- tu.sql through -22;
- the rebuilt `tally-pg` container (fresh from tu.sql);
- `tests/ci.sh`: 33/33;
- -22: battery 167, races CR1–CR20 (30 PASS), mutations 79/79.

**Broken:** nothing known.
**Uncommitted changes:** only this wrap-up (HANDOFF.md, CHANGELOG.md). **Scratch DBs:** none.

## Code Context

```sql
-- the close's rows, in order (r7 rule): head FOR UPDATE; period FOR UPDATE;
--   closing user's users row FOR KEY SHARE (closed_by); tenant row FOR KEY SHARE (snapshot lines, only if lines are written)
-- enforce_write_off_recovery (AFTER INSERT, WHEN reverses_ledger_entry_id IS NOT NULL OR transaction_type = 'write_off'):
--   23514 "recorded at a non-finite or future time" | 23514 "a time chosen for it" (created_at <> now(), before a tree row)
--   40001 "retry it" (stamped at its start, before a tree row) | 23514 "on <date> the rows netted" (cap) | 25000 non-READ COMMITTED
-- deploy-time audit (DEPLOY-VERIFICATION -22): must return 0
SELECT count(*) FROM public.account_ledger l
 WHERE (l.transaction_type IN ('write_off','write_off_recovery') OR l.reverses_ledger_entry_id IS NOT NULL)
   AND (NOT isfinite(l.created_at) OR l.created_at > clock_timestamp());
```

```bash
# race barriers (tests/v5.4.2-22/races/close-22.sh): signal / await_app / await_blocked
# DO loop: PERFORM pg_stat_clear_snapshot(); EXIT WHEN EXISTS (... application_name = '<step>') ...
```

## Resume Instructions

1. `git pull --ff-only` in both repos, and check GBM for Kyle's pushes.
   - Expected: tally-utility at the wrap-up commit after `eef5122`; GBM at `bab1da5` or later.
2. `bash tests/ci.sh`.
   - Expected: `ci: all pass`, 33 steps.
   - If the container is missing: `bash tests/ci.sh --build` (it recreates `tally-pg` from tu.sql).
3. Start -23:
   - read the source inventory's M, X, A, C, U, L sections and the "-22 as drafted" mapping;
   - draft per memory "source inventory first, triage by rule";
   - raise only real conflicts with Ryan, one decision per message, in plain language, with a default.
4. Refresh the go-live roadmap dashboard (memory `go-live-roadmap-dashboard`) at the next wrap-up.

## Warnings

- **Never edit tu.sql's mirrored bodies or the frozen review copies.** Corrections go in the next patch's header.
- **Revoke TEMP from PUBLIC, `tally_app` and `tally_core` after every `CREATE DATABASE … TEMPLATE`.**
- **Roles are cluster-wide;** reviewers must not touch roles.
- **`tests/ci.sh --build` deletes the container.**
- **Never `git add -A` in gas-billing-memory.**
- **Commits go straight to main.** `git pull --rebase` before pushing.
- **Background reviewers' final messages repeat as idle notifications.** Don't act on a second copy.
- **Ask Ryan one decision per message, in plain language, with a default.** He picked "fix it now" over the default twice this session: offer it as a real option.
