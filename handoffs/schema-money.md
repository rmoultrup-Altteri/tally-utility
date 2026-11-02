Folder: `~/code/tally-utility`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: schema stream "money" — cash, disputes, collections, enrollments, notices

**Generated**: 2026-11-02, evening
**Branch**: `main`, pushed (this wrap-up's commit).
**Status**: -23 round 8 is built, frozen and reviewed: **Fable ready, Codex not yet, Opus not yet.** Three blocking items, all confirmed or executed. The first thing for Ryan is the fix for Codex's B1 (below); it was put to him and not yet answered.

## Goal

Close this stream's half of the open invariants, in order (Ryan, 2026-11-02): **-23 → -27 → -24** → -25 and -26 (drafted; reviewed in -27's waits) → enrollments → notices → new rule types. One patch at a time. The rates stream (`~/code/tally-utility-rates`, -28) and the scenarios stream run beside it.

## Resume Instructions

1. `git pull --ff-only`; `git -C ../gas-billing-memory fetch` and check `HEAD..origin/main`. Read the board's notes for this stream.
2. **Put Codex's B1 fix to Ryan if he hasn't answered** (one decision, prose, recommendation):
   - *What breaks:* `check_cash_source`'s family cap (frozen r8 ~3318–3350) refuses any act while the payment and its credits are over the payment's amount from that act's date on, even an act that adds nothing. A family can be legitimately over (K-10: what was paid out stands). Codex's case (take-back 60, not Q5's 50): the bank returns an escheated credit's refund; Ryan's 10-21 rule requires the 20 be carried to a reissue; the family cap refuses the reissue (110 > 100) though a reissue moves no money out. So the return can't be recorded. **Confirmed** (`codex-r8-probes/01-negative-pool-reissue.author-run.txt`).
   - *Option 1 (recommended):* skip the family cap for the two internal moves, `p_purpose IN ('reissue', 'overpayment_credit')`; the family sum already excludes both. Every other check stays. Tests: Codex's 60 case in Q5, plus a one-cent external refund after the carry still refused; a mutation removing the skip.
   - *Option 2:* change the family cap for every act to refuse only an act that adds to the overdraw. More general; re-opens the cap every reviewer has worked over.
   - *Option 3 (rejected by Codex and me):* waive the reissue requirement in deficit; reverses Ryan's 10-21 rule.
3. **Merge the three r8 reviews into `application/wave2-build-2026-10-15/v5.4.2-23-r9-plan.md`.** Items so far:
   - **Codex B1** (above). Codex S1: Z6 proves a guarded endpoint on planted history, not a full-history 999th make. Codex S2: the patch header still states the old exact-cap promise somewhere.
   - **Opus B1 (executed, real sessions):** a refund's return is stamped at its transaction's start; one that began before a take-back and commits after it moves the take-back's share from a later reissue onto the overpayment credit, after the fact. If that reissue was escheated in between, it ends holding 10 of its own on a remitted credit. Fix direction: give every leaving move on a family (a refund going nsf/voided/reversed, a family credit's void) the recorded-order check a draw has (`check_cash_order`'s arrival-entry leg, under the payment's lock it already takes), so it retries (40001) after the take-back. R17 then says "retried, not stamped back". Tests: J as race CR27, the void variant, a mutation.
   - **Opus B2 = Fable S1 (tests only):** agree() no longer pins what a line can pay; two cap mutations (mA the payment's cap counts the credit's share twice; mB the overpayment credit's cap forgets its share) pass all 390 checks. Fix: agree() admits `least(own side, pool)` and refuses it plus a cent, for each active line (Fable has `agree_exact` in `/private/tmp/claude-501/-Users-ryanscomputer-code-tally-utility/d802ba0f-386f-46fd-bb25-7df86bade265/scratchpad/probe-r8.sql`; scratch, may be gone); add mA and mB as mutations.
   - **Fable S2:** the P-G shape (an active credit's reissue sized on its own 40) as a battery check; ids 34xx free. Fable's race FR1 is in the same scratchpad (`race-fable-r8.sh`).
   - **Opus S1** (a statement that makes a reissue and draws on it is sized against the reissue's own draws), **Opus S2** (the pins don't protect the 999-deep line under autovacuum's "pages present, 0 rows" statistics), **Opus S3** (comments): read them in `opus-r8.md`. Opus S2 is final: under autovacuum's "pages present, 0 rows" statistics, Z6 took 23 min 24 s (battery to Z6: 1,444 s against 23 s), mostly in the pinned `overpayment_family` (754 s) and `cash_source_draws` (329 s) and the unpinned `customer_credit_draws_as_of` (323 s). Not blocking (real lines are 1–3 deep); fix: vacuum right before each run, correct R21's "the depth no longer depends on the statistics", consider pinning `customer_credit_draws_as_of`.
   - Brief housekeeping (Fable): the battery runs with the default search_path; only the strict apply uses an empty one.
4. Build round 9 (tests first: each new check red on frozen r8), mutations, races, freeze, three reviewers as in round 8 (see "How round 8 was reviewed").
5. **Fix -15's expired test** (below) as a test-only commit; then `tests/ci.sh` should pass.

## How round 8 was reviewed (repeat for round 9)

- Freeze: copy the patch, battery, races and runner to `tests/v5.4.2-23/review/*-frozen-r9.*`, diff r8→r9, md5s into the brief (`review-brief-23-r8.md` is the template), `review-brief-23-r9.md5`, `codex-prompt-r9.md` (sed from r8). Board line → "round 9 frozen".
- Opus and Fable: Agent tool, `model: opus` / `model: fable`, `general-purpose`, named `opus-r9` / `fable-r9`; ask for the final report in several messages under 3 KB.
- Codex: `export PATH="$HOME/.nvm/versions/node/v24.15.0/bin:$PATH"; codex exec -s workspace-write -o tests/v5.4.2-23/review/codex-r9-final.txt "$(cat tests/v5.4.2-23/review/codex-prompt-r9.md)" < /dev/null` in the background. Took about 25 minutes.
- Codex's probes: run each on a fresh clone with the frozen patch strictly applied (the runner script pattern: clone `tally`, revoke TEMP, apply with `search_path=` and `check_function_bodies=on`, run as owner, drop). The 02/03 lock probes run as concurrent sessions on one clone in their documented order. Save outputs as `<probe>.author-run.txt`.

## Not Yet Done

- [ ] **-23 round 9** (above), then the mirror on Ryan's approval (board's pre-mirror check first).
- [ ] **-27**: a credit applied to a bounced payment's shortfall (AC-44's netting; claimed, not drafted). Additive: a new application target or table, a draw on the credit and a repayment on the payment, through -23's positions and caps. Also R24's closing act.
- [ ] **-24** (unmatched cash and agency pledges; CI-053, 056), after -27.
- [ ] **Review -25 and -26.** They passed CI on top of -23 r8 today (every -23/-25/-26 step). At -26's mirror, update APPLICATION-CONTRACTS: AC-10 still lists `dunning_stage` and `late_fee_*` as writable.
- [ ] **-15's battery V23 expired on 2026-11-02** (fails on plain `tally` too, not ours to blame on -23/-25/-26). The fixture writes a deposit-return due row dated 2026-11-01 whose evidence is c9's closure, which the fixture stamps with today's date; the closure must be on or before the due date. V16 (and the x1–x3 supersede rows) use the same fixed date and may now pass for the wrong reason. Fix in the test only (`tests/v5.4.2-15/battery-15r.sql`, ~1189 and 1233–1281): date the closure in the fixture rather than today, or move the dependent dates; never `tu.sql`. The deposits rewrite is this stream's.
- [ ] **Counsel question C-03** (roadmap): may a utility set off a debt against a credit before reporting it as unclaimed property, per state? Feeds AC-44's per-state rule.
- [ ] **Then:** enrollments (wave 4: CI-060, 065, 081 link, 082–085); the reconnect technician check (CI-072); notices (wave 5: CI-088, 093–097, 111, 135); new rule types (wave 7: CI-043, 054 late-fee rows, 079, 080, 081 law row, 105, 114).
- [ ] **Tell Kyle (not blocking):** ui-concepts still lists `refunded`; `do_not_disconnect` must become a protective enrollment; the four wave-3 law findings.
- [ ] **Carried over:** the reply to Kyle on where D-2 lives (his 10-14 question); -21 R9; the Florida 25-7.083 text; the waiver rewrite; the -15 r8 follow-ups.

## Key Decisions (this session and the one before; DECISION-LOG has the reasons)

| Decision | Where |
|---|---|
| Option A: a line never reads more than it can pay; not "pays exactly what it reads" (Ryan, 11-01) | DECISION-LOG 2026-11-01 (-23 r8) |
| Netting before an escheat report is a per-state rule; with no rule row, report in full (Ryan, 11-02) | DECISION-LOG 2026-11-02 (-23 r8); AC-44 |
| Netting is recorded as a new kind of application to the bounced payment's shortfall, built as -27; never a billed charge (K-10) (Ryan, 11-02) | same; AC-44; board |
| -27 goes next after -23, ahead of -24 (Ryan, 11-02) | same; board |
| A reissue is sized on the credit's own money (author's call in the r8 build, follows option A and 10-21) | r8 plan "As built" |

## Failed Approaches (Don't Repeat These)

- **Narrowing agree() without a direct cap check:** N207 (and Opus's mA/mB) then pass the battery. Every per-side cap needs a check that refuses its figure plus a cent.
- **Rewriting the roadmap JSON with `json.dump(indent=1)`:** reformats the whole file. phases.json is `indent=2`; decisions.json is one object per line.
- **Editing the roadmap before pulling at wrap-up:** the rates stream wraps up the same day; pull first, then edit.
- **Codex with `-s read-only`; a voided reissue's share passed back to its credit; caps reading the covered positions; one-instant fixtures for distinct-instant shapes; `docker stop` on postgres-mcp containers (use `docker rm -f`/`kill`).**

## Current State

- **-23 r8** (frozen md5s in `review-brief-23-r8.md`): strict apply twice clean; battery 390/390 (22–45 s after VACUUM); races 40/40 (CR26 new); mutations 225/225 (43 min; N207 retargeted to the new Y7j2, N223 to Z4a after the first run missed them). Red vs r7: `tests/v5.4.2-23/red-r8-against-r7.txt`.
- **Reviews:** `tests/v5.4.2-23/review/{opus,fable,codex}-r8.md`, Codex's probes and the author runs in `codex-r8-probes/`.
- **CI** (`tests/ci.sh`, -23 r8 + -25 + -26 pending): every step passes except `battery v5.4.2-15` (V23, the expired date above).
- **Docker:** 7 leaked postgres-mcp containers from 10-27 removed; 2 live (wrapper processes alive) left.
- **Dashboard:** P1 text and C-03 updated; dates unchanged (ready to onboard 2027-06-09 likely). -27 isn't in the duration estimate yet.
- **Uncommitted changes:** none after this wrap-up's commit.

## Warnings

- **Don't edit the patch or tests while `mutations-23.py` runs.** A selected rerun: `python3 tests/v5.4.2-23/mutations-23.py N207 N223`. Adding a check can change which check fails first for other mutations: rerun all after adding one.
- **CR10 can miss its "B waits" observation under the mutation run's load.** Rerun that mutation alone before believing it.
- **Revoke TEMP after every TEMPLATE clone. Never edit the frozen review copies or tu.sql's mirrored bodies.**
- **Other streams share tally-pg.** `ci.sh` only through its lock; the pre-mirror check before a mirror.
