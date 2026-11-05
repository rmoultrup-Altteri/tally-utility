Folder: `~/code/tally-utility`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: schema stream "money" — cash, disputes, collections, enrollments, notices

**Generated**: 2026-11-05, evening
**Branch**: `main`, pushed (this wrap-up's commit).
**Status**: -27 round 2 is reviewed: **Fable ready; Opus and Codex not yet**, with one blocking item each, both confirmed and both settled by rule. The round 3 plan is written. The last question put to Ryan was "Shall I build round 3?", and he has not answered it yet (he asked to wrap up instead).

## Goal

Close this stream's half of the open invariants, in order (Ryan, 2026-11-02):
1. -23 (**mirrored 2026-11-04**);
2. **-27** (now);
3. -24;
4. -25 and -26 (drafted; review them during -27's waits);
5. enrollments;
6. notices;
7. new rule types.

One patch at a time. The rates stream (`~/code/tally-utility-rates`) and the scenarios stream run beside this one.

## Resume Instructions

1. Run `git pull --ff-only`. Then `git -C ../gas-billing-memory fetch` and check `HEAD..origin/main`. Read the board's notes for this stream.
2. **If Ryan says go, build -27 round 3** from `application/wave2-build-2026-10-15/v5.4.2-27-r3-plan.md`. Tests come first: each new check must fail on frozen r2. The fixes:
   - **Opus B1, an undo dated in the future.** `check_shortfall_repaid`'s NULL path, for a move giving money back, must also read every row at its own date from `current_date` on. The repayment path already reads strictly from `p_from`, and the retroactive undo dating stays for dates before today. Opus's probe: undo dated 2099-12-31, refund return admitted, payment reads +30 to 2099. Probes are in `/private/tmp/claude-501/-Users-ryanscomputer-code-tally-utility/5e6b8bb5-06a7-4742-b166-ff5f4b04a6c3/scratchpad/opus27/`; this is scratch and may be gone, and `opus-r2.md` has the shape.
   - **Codex B1, a carry born ended.** A `shortfall_reissue` credit is born `active`, for every role including a superuser's history load. Put the check in `enforce_shortfall_reissue`. Add a regression (Codex's `codex-r2-probes/06-carry-history.sql`, whose author run is ACCEPTED on r2) and a mutation. Note that -23's `enforce_cash_birth` returns early for a superuser.
   - **Opus S1, the undo a carry names.** It must have been recorded at or after the old credit's `escheated_at`.
   - **Tests:**
     - `cash_source_draws`' carry leg gets a check and a mutation (Fable S1, Opus S2);
     - a carry off a credit that was never escheated;
     - the depth bound;
     - mixed lines in both directions (from Codex's probe 08);
     - an escheated credit's ordinary undo still refused;
     - a caller-level invoice-application undo on a repaid family (Codex S1);
     - C2 made a true partial undo (probe 09);
     - E7c's label narrowed, or the balance compared;
     - mutations for the escheated-source requirement, the depth check, the birth status, and `cash_drawn_at`'s shortfall and repaid terms.
   - **Notes:**
     - deadlines on the race helper's monitoring queries;
     - the header's "never holds money" should name R5;
     - `repaid` should print 0.00.
3. Re-run everything:
   - strict apply twice;
   - battery, races and all mutations: `python3 -u tests/v5.4.2-27/mutations-27.py`, about 25 minutes; `-u` or the log stays empty until the end;
   - -23's battery and races with -27 applied;
   - `tests/ci.sh`.

   Then freeze r3 and review it with all three ("How a round is reviewed").
4. **Codex's usage:** it hit its limit at the end of round 2. The reset given was 5:18 PM (2026-11-05). If it is limited again at r3, give Ryan the reset time.
5. **At -27's mirror** (Ryan's approval, the board's pre-mirror check first):
   - update APPLICATION-CONTRACTS AC-44 (it still says "claimed, not drafted");
   - re-grade parity;
   - write the DEPLOY-VERIFICATION entry;
   - move the oldest CHANGELOG entries to `changelog-archive/2026-11.md` so 10 stay live. The live file holds 11 after this session's entry.

## How a round is reviewed (repeat for r3)

- **Freeze.** Copy the patch, battery, races and runner to `tests/v5.4.2-27/review/*-frozen-r3.*` and write `r2-to-r3.diff`. The brief is `review-brief-27-r2.md` with `@@` placeholders filled by script. Write the md5 to `.md5`, and make `codex-prompt-r3.md` by sed from r2. Change the board line to "r3 frozen".
- **Opus and Fable.** Use the Agent tool, general-purpose, `model: opus` and `model: fable`, named `opus-r3` and `fable-r3`. Ask for a reply under 2 KB, with the detail in the file. Both have read their own r1 and r2 files.
- **Codex.** Run in the background: `export PATH="$HOME/.nvm/versions/node/v24.15.0/bin:$PATH"; codex exec -s workspace-write -o tests/v5.4.2-27/review/codex-r3-final.txt "$(cat tests/v5.4.2-27/review/codex-prompt-r3.md)" < /dev/null`. It takes about 25 minutes. Run its probes yourself, each on a fresh clone with the frozen patch applied strictly, and save `<probe>.author-run.txt`.

## Not Yet Done

- [ ] **-27 round 3** (above), then the mirror.
- [ ] **-23's `refund_reissue` may have Opus S1's mirror gap:** a reissue naming a refund that came back before the escheat. This is this stream's, as a later patch; check it before deciding.
- [ ] **-24** (unmatched cash, agency pledges; CI-053, 056), after -27.
- [ ] **Review -25 and -26.** At -26's mirror, update AC-10, which still lists `dunning_stage` and `late_fee_*` as writable.
- [ ] **Board notes to money** from scenarios (2026-11-04: Kyle's answers; the Mcf unit list loosening -21's check) and from R-12 (two-column tenant keys): read them on the board.
- [ ] **Counsel question C-03** (setoff before an escheat report, per state).
- [ ] **Then:** enrollments, the reconnect check (CI-072), notices, new rule types.
- [ ] **Tell Kyle (not blocking):** ui-concepts still lists `refunded`; `do_not_disconnect` should become a protective enrollment; the four wave-3 law findings.

## Key Decisions (DECISION-LOG has the reasons)

| Decision | Where |
|---|---|
| A refund that comes back after its shortfall was repaid waits until the repayment is undone (Ryan, 11-05, option 1) | DECISION-LOG 2026-11-05 (-27 design); roadmap R-23 |
| An undo of a repayment whose credit was since escheated carries the money into a new credit, origin `shortfall_reissue`, in the old credit's overpayment line (Ryan, 11-05, option 1) | DECISION-LOG 2026-11-05 (-27 r1); roadmap R-24 |
| By rule (r2): the return check reads from the first repayment, with an undo counted from the row it undoes. A bounced deposit and a refund are refused as targets. Each privilege is asked alone. | r2 plan |
| By rule (r3, planned): also strict from today on; a carry born active; a carry's undo recorded after the escheat | r3 plan |

## Failed Approaches (Don't Repeat These)

- **Checking a returned refund from the target's latest shortfall row (r1).** A later repayment hides an earlier one (Codex B1).
- **Counting an undo from its repayment's date with no strict check from today on (r2).** A future-dated undo slips through (Opus B1).
- **`SET CONSTRAINTS … IMMEDIATE` inside an admitted battery check without setting it back to `DEFERRED`.** It stays immediate for the rest of the battery's transaction.
- **Running `mutations-27.py` without `python3 -u` into a log.** Nothing shows until the end.
- **A "may be voided" check on a credit something already draws on.** -23 refuses that void for its own reason, so the mutation survives. Test the void before any draw.
- **Earlier failures (rewriting roadmap JSON with `json.dump`; editing the roadmap before pulling; Codex with `-s read-only`).** These are still in the CHANGELOG.

## Current State

- **-27 r2** (frozen md5s in `review-brief-27-r2.md`):
  - strict apply twice clean;
  - battery 116/116, races 16/16 (SR1–SR9), mutations 58/58;
  - -23's battery 409/409 and races 51/51 with r2 applied;
  - `ci.sh` 55/55 (-29's three pending-only steps are skipped now that its counties are loaded).
- **Reviews:** `tests/v5.4.2-27/review/{opus,fable,codex}-r2.md`. Codex's r2 probes are run, with outputs in `codex-r2-probes/*.author-run.txt`; every prediction held.
- **Plans and design:** r2 plan, r3 plan, design sections 8 and 9.
- **Docker:** review clones dropped. `ci_r27` is left by `ci.sh`, as its steps do.
- **Dashboard:** decisions R-23 and R-24 added; the P1 summary refreshed. Dates unchanged: ready to onboard 2027-06-09 likely.
- **Uncommitted changes:** none after this wrap-up's commit.

## Warnings

- Don't edit the patch or tests while a mutation run is going. Adding a check can change which check fails first for other mutations, so rerun them all.
- Revoke TEMP after every TEMPLATE clone. Never edit the frozen review copies or `tu.sql`'s mirrored bodies.
- The battery's ids are `00000000-0000-4000-8000-0000000027xx`. These are used: `10`–`5f` (r2), `61`–`9e`, `a1`–`ae`, `b1`/`b2` (users), `c1`–`c9` (customers), `d1`–`d4`, `e1`–`e8`, `f1`–`f6`. The races use the prefix `…0000000028`.
