Folder: `~/code/tally-utility`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: schema stream "money" — cash, disputes, collections, enrollments, notices

**Generated**: 2026-11-27, late (after -26 r3 was built)
**Branch**: `main`, pushed (this wrap-up's commit).
**Status**: -24 and -25 mirrored. **-26** (collections decisions): rounds 1 and 2 reviewed (all three "not yet" both times); **r3 built and pushed (54f7bd8), not frozen**. Ryan has not yet said "freeze r3".

## Goal

Close this stream's half of the open invariants, in order (Ryan, 2026-11-02):
1. -23, -27, -24, -25: done (mirrored).
2. **-26** (collections decisions): r3 to freeze and review.
3. Enrollments.
4. Notices.
5. New rule types.

## Waiting on others

- **Kyle:** K-14 and K-19 (scenario batches 3 and 6, sent by Ryan 2026-11-26); **K-17** (a bill's credit line: which charge it reduces), sent by Ryan 2026-11-27 (`application/kyle-brief-2026-11-22-credit-line.md`). No netting patch until K-17 is answered.
- **Counsel:** whether *Memphis Light v. Craft* (1978) reaches a Texas city's customers.
- Nothing waits on Ryan except the go-ahead to freeze -26 r3.

## Resume Instructions

1. `git pull --ff-only`; fetch GBM; read the board.
2. **On Ryan's "freeze r3":** follow "How a round is frozen" below, with `tests/v5.4.2-26/review/review-brief-26-r2.md` as the model. Frozen files this time: patch, battery-26, races, mutations, migration, fill-manifest, **battery-21 and battery-22** (both now need -26). Diffs r2→r3 for the patch, battery-26 and battery-22 (`git diff d4695ff HEAD -- tests/v5.4.2-22/battery-22.sql`). The brief asks whether each round-2 item is fixed (plan `application/wave3-build-2026-10-18/v5.4.2-26-r3-plan.md`, items 1–11) and what r3 may have broken. Point the reviewers at:
   - judging an execution as of its arrival (`collections_act_check`'s `p_at`, `collections_cover_blocks`; R8);
   - the new trigger on `account_ledger` (`a_enforce_late_fee_ledger`; tally_void writes the ledger);
   - the split rule for closed bills (item 7, settled by rule; the reviewers disagreed);
   - the void-bill rule, narrowed from draft-and-void (the r3 plan says why);
   - the invariant's wider lists, and the race classifier.
3. Review with all three; run Codex's probes on fresh clones of frozen r3 with a bash script (copy, clone `tally`, revoke TEMP, strict-apply, run, save `.author-run.txt`).
4. At -26's mirror: update AC-10; contracts for R1 (an execute decision is written on the utility's local day, after that day's weather check), R8 (an execution is judged as of its arrival), and a notice's waiting period counting from the later of its date and the day it was recorded (Fable r2 N9); DEPLOY-VERIFICATION's history-load order (program types, customers with do_not_disconnect false, then enrollments; approvals load only under an active tenant_admin); re-grade CI-067, CI-069, CI-070, CI-071, CI-075.

## In flight at wrap-up (check first)

Nothing is running. The round-1 and round-2 reviewer agents are idle and need nothing. Last full results on r3 (all on the pushed files): battery-26 288, races 19 (CR1–CR11b), migration P0–P7b, mutations 177/177 (classifier self-test 10/10), battery-21 143 and battery-22 170 with -26, `ci.sh` 56/56.

## How a round is frozen and reviewed

1. After any change to a function body or a pinned object, run `python3 tests/v5.4.2-26/fill-manifest.py` (it refills `assert_collections_guard_invariants()`'s lists), then the battery, races, migration, mutations, ci.sh. A stale manifest makes the patch refuse to apply, which is the point.
2. Copy the frozen files to `tests/v5.4.2-26/review/*-frozen-rN.*`; write the diffs.
3. Write the brief and its `.md5`, the Codex prompt (edit by hand: a global sed also rewrites the earlier round's file names), and `codex-rN-probes/`.
4. Commit and push, then launch Opus and Fable (general-purpose agents, `model: opus` / `fable`, each writing its own review file) and Codex (`export PATH="$HOME/.nvm/versions/node/v24.15.0/bin:$PATH"; codex exec -s workspace-write -o <final> "$(cat <prompt>)" < /dev/null`).
5. Read every shell command in a Codex probe before running it.

## Not Yet Done

- [ ] -26 r3: freeze and review (above). Then mirror on Ryan's approval.
- [ ] **For later money patches** (unchanged): a bill's credit line (K-17); one charge part due later (Ryan 2026-11-22); a split check for a deposit and a bill (SCN-0091 c); a pledge's received day and the credit-netting timing setting (board 2026-11-25); a penalty on the ledger with no bill line (SCN-0092); a credit to the state posts no ledger row (SCN-0088 c); -27 R3's settling record (SCN-0101 b); a posting undone while its payment is pending (non-receipt payments); NaN amounts and unpinned helpers in -23; the two -23 escheat gaps.
- [ ] The late fee's grace, rate, cap and exempt programs still have no data home (CI-054).
- [ ] R-38's supervisor rule on ending a protective enrollment (Opus r1 N3): a later patch on the enrollment table.

## Key Decisions (this session; DECISION-LOG has the older ones)

| Decision | Where |
|---|---|
| -25 mirrored after r9 | DECISION-LOG 2026-11-27 |
| -26: escalation steps move a bill's stage only forward; a repeat monthly late fee leaves it where it is (settled by rule; Ryan may overrule) | r2 plan item 6 |
| -26: from a payment plan any escalation step moves the bill; a resolved or written-off bill reopens only on a gated step (settled by rule between Opus and Fable) | r3 plan item 7 |
| -26: an execution is judged as of the crew's arrival, so a late sync is recorded even if the core blocked afterwards | r3 plan item 1, R8 |
| -26: the approver is an active tenant_admin of the order's own utility; Tally staff act through its Tally User | r2 plan item 5 |
| -26: `penalty` charges are late penalties; other penalties take another type | r2 plan item 7 |

## Failed Approaches (Don't Repeat These)

- **"Decision recorded before the act" without judging the act as of that moment** (-26 r2): a late-synced execution could then cite no decision at all. Bound the arrival below AND read liveness as of the arrival.
- **A lock key that includes an optional narrowing part** (-26 r1): a location-wide block and a meter's eligible decision stood side by side. Key the lock on the broad part (PATCH-LESSONS `optional-key-splits-a-subject`).
- **A status update whose guard reads other rows, without the READ COMMITTED pin** (-26 r1; PATCH-LESSONS `every-guard-reading-other-rows-pins-isolation`).
- **Reading the previous stage from the bill's projection in a BEFORE trigger**: an AFTER trigger moves it, so a multi-row insert chains wrongly. Read the events.
- **Refusing collection steps on draft bills**: battery-19 logs one. Void bills only.
- **A runner rule that "never seen waiting" is not a catch, without the race naming its damage**: it hid real lock-removal damage. The race prints FAIL only with damage, else BROKEN.
- **Putting the "self-check holds" test before newer named checks**: every body mutation is then caught by it first. It runs last.
- **Running a probe script with `$P` as a command under zsh**: use bash.

## Current State

- `tally` carries -25. `ci.sh` PENDING: -26 only.
- Counts after -25: 163 tables, 125 policies, 612 triggers, 680 functions (DEPLOY-VERIFICATION). Parity 88 of 135.
- The two leftover postgres-mcp containers were stopped on Ryan's say-so (2026-11-27).

## Warnings

- Don't edit a patch or its tests while ci.sh or a mutation run is going. ci.sh drops and rebuilds `ci_pre26`, which the mutation runner and migration test clone from: run them one at a time.
- Revoke TEMP after every TEMPLATE clone. Never edit frozen review copies or bodies mirrored into `tu.sql`.
- Before a mirror or `ci.sh --build`, check that no other stream is mid-run.
