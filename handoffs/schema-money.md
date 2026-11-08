Folder: `~/code/tally-utility`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: schema stream "money" — cash, disputes, collections, enrollments, notices

**Generated**: 2026-11-07, evening
**Branch**: `main`, pushed (this wrap-up's commit).
**Status**: two patches in review. **-24** (unmatched cash, agency pledges): r5 reviewed (Opus not yet, Fable ready), and r6 is built but not frozen, waiting for Codex's r5 review. **-25** (disputes): r1 reviewed (both not yet), and r2 is built but not frozen. **Three background jobs may still be running at the start of next session** (see "In flight").

## Goal

Close this stream's half of the open invariants, in order (Ryan, 2026-11-02):
1. -23 and -27: done (mirrored).
2. **-24** (in review).
3. **-25 and -26** (-25 in review; -26 not yet reviewed).
4. Enrollments.
5. Notices.
6. New rule types.

## In flight at wrap-up (check first)

- **Codex's -24 r5 review** (background job). It starts at 19:15, after the usage reset, and writes `tests/v5.4.2-24/review/codex-r5.md` and `codex-r5-probes/`. Run every probe on a fresh clone with frozen r5 applied, and save `<probe>.author-run.txt`. Its predictions have held every round.
- **CI, then two mutation runs in parallel** (background job, started about 18:15). The logs are in the session scratchpad, which will be gone: re-run them if no result is in the repo.
  - `bash tests/ci.sh`;
  - `python3 -u tests/v5.4.2-24/mutations-24.py` (112 expected);
  - `python3 -u tests/v5.4.2-25/mutations-25.py` (125 expected).

## Resume Instructions

1. Run `git pull --ff-only`, then fetch GBM. Read the board's notes, especially **scenarios → money (2026-11-07)**: four notes on disputes.
2. **Disputes, Ryan's call (held).** Two of Ryan's rulings on Kyle's no-penalty-while-disputed rule disagree:
   - **Money's (AC-46, DECISION-LOG 2026-11-07 money -25):** a platform rule for every customer, covering the whole bill, until resolution or withdrawal.
   - **Scenarios' (four entries):** a city's own rule wins; only a city with no rule gets a default; the default covers the disputed amount only; it ends at the earlier of resolution and 60 days after issue.

   The scenarios stream asks Ryan and leaves a board note. Whichever yields gets a dated correction in DECISION-LOG and AC-46. If scenarios' version stands, -25 needs a platform default dispute row for a city with no dispute tariff, which is a schema change, before -25 r2 freezes (r2 plan item 9).
3. **-24:** fold Codex's r5 findings into r6 (`application/wave2-build-2026-10-15/`; write `v5.4.2-24-r6-plan.md` with Opus r5 B1, Fable r5 S1 and S2, and Codex's). Then run `fill-manifest.py`, the battery, ci.sh and the mutations, freeze r6, and review it with all three.
4. **-25:** after the dispute ruling, finish r2 (`application/wave3-build-2026-10-18/v5.4.2-25-r2-plan.md`). Then run `tests/v5.4.2-25/fill-manifest.py` after any change, the battery, the races (add a same-statement race and a reading-move race), ci.sh and the mutations. Freeze r2, and review it with all three; Codex has not yet reviewed -25.
5. **-26** after -25: re-test, freeze r1, review.

## How a round is reviewed

As -24's rounds were:
1. **Freeze.** Copy the patch, battery, races and mutations to `review/*-frozen-rN.*`, with `r(N-1)-to-rN.diff`. Write the brief (models: `tests/v5.4.2-24/review/review-brief-24-r5.md`, `tests/v5.4.2-25/review/review-brief-25-r1.md`) and its `.md5`, and make the Codex prompt by sed.
2. **Opus and Fable:** run as agents (general-purpose, `model: opus` or `fable`), asked for a reply under 2 KB.
3. **Codex:** in the background, `export PATH="$HOME/.nvm/versions/node/v24.15.0/bin:$PATH"; codex exec -s workspace-write -o <final> "$(cat <prompt>)" < /dev/null`.
   - It hit its usage limit after about 160k tokens on -24 r2, and the reset is about 3 hours. If it is limited, give Ryan the reset time.
   - Starting it at a time works: `until [ "$(date +%H%M)" -ge HHMM ]; do sleep 60; done; codex exec …`.
   - Cancel a queued Codex run when the other two have already found a blocker in that round.
4. **The invariant manifests.** -24's and -25's invariants pin exact lists generated from a build: run `python3 tests/v5.4.2-2N/fill-manifest.py` after any change to a listed object. Each mutation runner re-fills or skips the body pins: -24's `refill()` and `unpin()`, and -25 drops the tail invariant call for a behavioural mutation.

## Not Yet Done

- [ ] -24 r6 (above). Current: battery 265, races 24, mutations 112.
- [ ] -25 r2 (above). Current: battery 221, races 12, mutations 125.
- [ ] -26: not reviewed. At its mirror, update AC-10.
- [ ] **For later money patches:**
  - -23's `payments`, `customer_credits` and `account_ledger` accept NaN amounts (-24 r3 note);
  - -23's helper bodies (`ledger_entry_remaining` and others) are unpinned by any invariant (Opus -24 r4 note);
  - the two -23 escheat gaps (refund_reissue order; a returned refund of an escheated credit).
- [ ] **At -24's mirror:**
  - an application contract that a payment carrying a provider transaction id is written at READ COMMITTED;
  - -24's known limits L1–L6 in its header;
  - DEPLOY-VERIFICATION;
  - the parity re-grade of CI-053 and CI-056.
- [ ] **At -25's mirror:** a contract that a reading's move into or out of disputed is written at READ COMMITTED (Fable r1 N).
- [ ] Counsel question C-03; tell Kyle the three items from 11-06's handoff.

## Key Decisions (DECISION-LOG has the reasons)

| Decision | Where |
|---|---|
| A refund of an agency's money goes to the agency, for every agency | DECISION-LOG 2026-11-07 (-24 design) |
| Agency money in a deposit or an untyped credit stays known limits L5 and L6 | DECISION-LOG 2026-11-07 (-24 r1) |
| No late penalty while a bill's dispute is open: a platform rule (AC-46) — **held, conflicts with scenarios' version** | DECISION-LOG 2026-11-07 (-25 r1); board |
| -24's review rounds settled by rule (plans r2–r5) | `application/wave2-build-2026-10-15/v5.4.2-24-r*-plan.md` |

## Failed Approaches (Don't Repeat These)

- **Trusting a status label for where money is** (r1): "reversed" was taken to mean misposted, but -23 lets a bank's take-back be reversed. Record the act (`misposting_returned`).
- **Summing only the direct reversals under a posting entry** (r3), **netting each reversal's tree with nsf rows inside counted** (r4), and **leaving out every row typed nsf** (r5). Each was a ledger-tree shape a reviewer broke. What holds: walk the whole tree, leaving out only nsf rows that take money (amount > 0) and what is beneath them, bounded by the payment.
- **Self-exclusion by id across two tables** (r1 provider check, r2 order check): exclude a row only within its own table.
- **Checking "nothing after the resolution" from a status an AFTER trigger writes** (-25 r1): judge from the events, AFTER INSERT.
- **A deferred check named so it sorts before the trigger it reads**, when the constraints are immediate (PATCH-LESSONS `constraint-trigger-name-order`).
- **A writable CTE whose main insert does not read the CTE** runs first, so it tests the wrong order. Make the row read the CTE (`FROM r`).
- **Changing a manifest-pinned object without re-running fill-manifest.**

## Current State

- `tu.sql` unchanged today (49,090 lines; -23, -27, -28 and -29 mirrored).
- `tests/ci.sh` PENDING: -25, -26, -30, -24. ci.sh 62/62 at the last full run (-24 r5 base). New steps: battery 24, races 24, the invariants of 24 and 25.
- Battery -23 now needs -24 applied, as well as -30 (an agency fixture). Run it through ci.sh.
- Docker: the clones `p24`, `p25` and `r24` may remain; drop them. Two postgres-mcp containers belong to the desktop app; leave them.
- Uncommitted changes: none after this wrap-up's commit.

## Warnings

- Don't edit a patch or its tests while a mutation run is going.
- Revoke TEMP after every TEMPLATE clone. Never edit frozen review copies or bodies mirrored into `tu.sql`.
- Before a mirror or `ci.sh --build`, check that no other stream is mid-run.
- -24's battery ids are `…0000000a24xx`; the race ids are `…0000000b24xx`.
