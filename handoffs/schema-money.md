Folder: `~/code/tally-utility`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: schema stream "money" — cash, disputes, collections, enrollments, notices

**Generated**: 2026-11-07, late evening (about 21:50)
**Branch**: `main`, pushed (this wrap-up's commit).
**Status**: two patches in review. **-24** (unmatched cash, agency pledges): r8 reviewed (Fable ready, Opus not yet on two should-fix items, Codex not run), and **r9 is built but not frozen**. **-25** (disputes): r2 built, not frozen, held on Ryan's dispute ruling.

## Goal

Close this stream's half of the open invariants, in order (Ryan, 2026-11-02):
1. -23 and -27: done (mirrored).
2. **-24** (in review).
3. **-25 and -26** (-25 r2 built; -26 not yet reviewed).
4. Enrollments.
5. Notices.
6. New rule types.

## In flight at wrap-up (check first)

- **CI, then -24's full mutation run** (background, started about 21:40 on the r9 working copy). The logs are in the session scratchpad, which will be gone. If the result isn't in the repo, re-run both: `bash tests/ci.sh` (63 steps expected), then `python3 -u tests/v5.4.2-24/mutations-24.py` (119 expected). The eight mutations touching r9's changes were run alone and all were caught at their checks.

## Waiting on Ryan

1. **Codex for -24.** Codex hit its usage limit on round 7 (it never started) and resets at **12:15 AM on 2026-11-08**. Ryan hasn't said whether to wait for it or waive it for these rounds (memory `all-three-reviewers-before-mirror`). Codex reviewed r5 and r6 and found the blocker both times; Opus and Fable have not seen a blocker since r6.
2. **The dispute ruling (-25 r2 item 9).** Two of Ryan's rulings disagree:
   - **Money's (AC-46, DECISION-LOG 2026-11-07 money -25):** a platform rule for every customer, covering the whole bill, until resolution or withdrawal.
   - **Scenarios' (four entries):** a city's own rule wins; only a city with no rule gets a default; the default covers the disputed amount only; it ends at the earlier of resolution and 60 days after issue.

   The scenarios stream asks Ryan and leaves a board note. Whichever yields gets a dated correction in DECISION-LOG and AC-46. If scenarios' version stands, -25 needs a platform default dispute row for a city with no dispute tariff (a schema change) before r2 freezes.

## Resume Instructions

1. `git pull --ff-only`, fetch GBM, read the board's notes (scenarios → money for the ruling).
2. **-24 r9:** confirm CI 63/63 and mutations 119/119 (above). Then freeze r9 as rounds r6–r8 were frozen (below). Write the brief from `review-brief-24-r8.md`, using `application/wave2-build-2026-10-15/v5.4.2-24-r9-plan.md` for "what changed". Review with Opus and Fable, plus Codex if Ryan says wait. Run every Codex probe on a fresh clone with the frozen patch applied, and save `<probe>.author-run.txt`. Its predictions have held every round.
3. **-25:** after the dispute ruling, finish r2 (`application/wave3-build-2026-10-18/v5.4.2-25-r2-plan.md`). Then run `tests/v5.4.2-25/fill-manifest.py` after any change, the battery, the races (add a same-statement race and a reading-move race), ci.sh and the mutations (126/126 today). Freeze, and review with all three. Codex has not yet reviewed -25.
4. **-26** after -25: re-test, freeze r1, review.

## How a round is frozen and reviewed (-24 r6–r8)

1. Run `python3 tests/v5.4.2-24/fill-manifest.py` after any change to a pinned object. A new function needs a hand-added `c_bodies` entry with 32 zeros as its md5; the script fills it. Then the battery (through ci.sh), the mutations, and ci.sh.
2. Copy the patch, battery, races and mutations to `review/*-frozen-rN.*`. Copy the ci diff from the previous round (unchanged since r1). Write `r(N-1)-to-rN.diff`.
3. Write the brief with `@` placeholders, then fill the md5s by sed, and write its `.md5`. Make the Codex prompt by sed from the last one, and create the `codex-rN-probes/` folder.
4. Commit and push, then launch the reviewers:
   - **Opus and Fable:** run as agents (general-purpose, `model: opus` or `fable`), told to review only the frozen copies and to reply in under 2 KB. Ask Fable to put any test SQL in its file.
   - **Codex:** `export PATH="$HOME/.nvm/versions/node/v24.15.0/bin:$PATH"; codex exec -s workspace-write -o <final> "$(cat <prompt>)" < /dev/null`. A one-line `codex exec -s read-only --skip-git-repo-check "Reply ok"` shows whether it is limited, and until when.

## Not Yet Done

- [ ] -24 r9: freeze and review (above). Current: battery 282, races 24, mutations 119.
- [ ] -25 r2 (above). Current: battery 222, races 12, mutations 126.
- [ ] -26: not reviewed. At its mirror, update AC-10.
- [ ] **For later money patches:**
  - -23's `payments`, `customer_credits` and `account_ledger` accept NaN amounts (-24 r3 note);
  - -23's helper bodies are unpinned by any invariant (Opus -24 r4 note);
  - -23's move to reversed checks the lineage's recorded time only for a superuser's hand-set status time (Codex -24 r6 B1; -24 no longer relies on it);
  - the two -23 escheat gaps (refund_reissue order; a returned refund of an escheated credit).
- [ ] **At -24's mirror:**
  - an application contract that a payment carrying a provider transaction id is written at READ COMMITTED;
  - another, that a reconciliation adds `suspense_misposting_returns_due_as_of`'s money in transit to `suspense_held_as_of`;
  - operator guidance (Opus r5 N1, r6 notes): a reversal filed under a bank take-back's undo holds the money until it is filed again, and a misposted payment whose credit was already refunded leaves the wrong customer owing the refund;
  - -24's known limits L1–L6 in its header;
  - DEPLOY-VERIFICATION;
  - the parity re-grade of CI-053 and CI-056.
- [ ] **At -25's mirror:** a contract that a reading's move into or out of disputed is written at READ COMMITTED (Fable r1 N).
- [ ] Counsel question C-03; tell Kyle the three items from 11-06's handoff.

## Key Decisions (DECISION-LOG has the reasons; review rounds settled by rule in the plans)

| Decision | Where |
|---|---|
| A refund of an agency's money goes to the agency, for every agency | DECISION-LOG 2026-11-07 (-24 design) |
| Agency money in a deposit or an untyped credit stays known limits L5 and L6 | DECISION-LOG 2026-11-07 (-24 r1) |
| No late penalty while a bill's dispute is open: a platform rule (AC-46) — **held, conflicts with scenarios' version** | DECISION-LOG 2026-11-07 (-25 r1); board |
| A misposting return: exactly the misposted share, dated on or after every row under the posting entry, recorded no earlier than every row of it; a reader lists one still due | plans r6–r9 |

## Failed Approaches (Don't Repeat These)

- **Trusting a status label for where money is** (r1): record the act (`misposting_returned`).
- **Ledger-tree rules a reviewer broke** (r3–r5): summing only direct reversals; netting each reversal's tree with nsf rows inside counted; leaving out every row typed nsf. What holds: walk the whole tree, leaving out only nsf rows that take money (amount > 0) and what is beneath them, bounded by the payment.
- **Checking a release only by business date** (r6): a history load can record a supporting row after the release's transaction began. Order by recorded time too.
- **"At most" for a once-only, never-undone release** (r7): a short one strands the rest. Make it exact, and re-aim the checks that refused share + 0.01 (PATCH-LESSONS `check-names-its-own-guard`).
- **Self-exclusion by id across two tables; an AFTER-trigger status read; a constraint trigger that sorts too early; a writable CTE whose insert doesn't read the CTE; changing a pinned object without fill-manifest.**
- **Editing the battery while ci.sh or a mutation run is going** (this session, caught before the mutations began). Both read the live test files.

## Current State

- `tu.sql` unchanged today (49,090 lines; -23, -27, -28 and -29 mirrored).
- `tests/ci.sh` PENDING: -25, -26, -30, -24. ci.sh 63/63 on r8 (and on every r6–r8 freeze). One run failed in -19's race C6 ("session B was never seen waiting on a lock"): a timing check, which passed three runs alone and every full run since.
- The -24 r9 working copy (patch, battery, mutations, plan) is committed but not frozen.
- Docker: the scratch clones are dropped. `m24` is the mutation runner's own (it is replaced each run). Leave the two postgres-mcp containers; they belong to the desktop app.

## Warnings

- Don't edit a patch or its tests while ci.sh or a mutation run is going.
- Revoke TEMP after every TEMPLATE clone. Never edit frozen review copies or bodies mirrored into `tu.sql`.
- Before a mirror or `ci.sh --build`, check that no other stream is mid-run.
- -24's battery ids are `…0000000a24xx` (free two-hex ids are few now: check before choosing); the race ids are `…0000000b24xx`.
