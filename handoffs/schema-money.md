Folder: `~/code/tally-utility`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: schema stream "money" — cash, disputes, collections, enrollments, notices

**Generated**: 2026-11-22, evening (about 18:50)
**Branch**: `main`, pushed (this wrap-up's commit).
**Status**: **-24** (unmatched cash, agency pledges): rounds 9 and 10 reviewed, **r11 built, not frozen**. **-25** (disputes): r2 built, not frozen; Ryan's dispute rulings are in, and the default table they need is designed, not built.

## Goal

Close this stream's half of the open invariants, in order (Ryan, 2026-11-02):
1. -23 and -27: done (mirrored).
2. **-24** (r11 to freeze).
3. **-25 and -26** (-25 r2 needs the default table; -26 not yet reviewed).
4. Enrollments.
5. Notices.
6. New rule types.

## Waiting on others

- **Kyle, K-17:** which of a bill's charges its own credit line reduces. Slack draft in Kyle's DM (Ryan sends). No netting patch until he answers. When K-17 was drafted, Slack reported no draft already attached, and K-14 was not among the DM's sent messages; scenarios was told (board).
- **Kyle, K-14 (scenarios sends):** three departures of the dispute rulings from CI-054 and CI-074: a penalty on an amount under dispute at a Brenham-style city; the 60-day end; notices not blocked.
- **Counsel:** whether *Memphis Light v. Craft* (1978) reaches a Texas city's customers.
- Nothing is waiting on Ryan except sending the drafts.

## Resume Instructions

1. `git pull --ff-only`; fetch GBM; read the board.
2. **-24 r11:** plan `application/wave2-build-2026-10-15/v5.4.2-24-r11-plan.md`. Its last CI ran while rates was mirroring -30 (61/61, because -30's steps are gone from `ci.sh`), so it is not proof on the new base.
   - Run `bash tests/ci.sh` on the pulled tree. Expect 61 steps, all pass.
   - Run `python3 -u tests/v5.4.2-24/mutations-24.py`. Expect 161 of 161.
   - Freeze as below, with `review-brief-24-r10.md` as the model and the r11 plan for "what changed". Review with Opus, Fable and Codex (all available on 11-22).
   - Put to the reviewers: a receipt's payment that is a **deposit** has no test; whether ending rules 1–4 in the plan can be got round; the new trigger on `account_ledger` (every role that writes it).
3. **-25 r2:** build the silent-city default as its own table, `dispute_platform_defaults` (design: `application/wave3-build-2026-10-18/v5.4.2-25-r2-plan.md`, "Item 9 design"). Tests first. Re-run everything on the base with -30 mirrored. Then freeze and review with all three; Codex has not seen -25.
4. **-26** after -25.

## In flight at wrap-up (check first)

Nothing is running. Last full results on r11: mutations 161 of 161 (160 in the run; M98 alone after its setup step became check P10a); battery 335; ci.sh 61/61 on the changing base, before P10a.

## How a round is frozen and reviewed (-24)

1. Run `python3 tests/v5.4.2-24/fill-manifest.py` after any change to a pinned object. A new function needs a hand-added `c_bodies` entry with 32 zeros, and (if a guard calls it as the app) a `c_app_exec` entry; a new trigger needs a `c_triggers` entry. Then the battery, mutations, ci.sh.
2. Copy the patch, battery, races and mutations to `review/*-frozen-rN.*`, the ci diff from the round before, and write `r(N-1)-to-rN.diff`.
3. Write the brief and its `.md5`, the Codex prompt (sed from the last), and `codex-rN-probes/`.
4. Commit and push, then launch:
   - **Opus and Fable:** agents (general-purpose, `model: opus` / `fable`), frozen copies only, reply under 2 KB.
   - **Codex:** `export PATH="$HOME/.nvm/versions/node/v24.15.0/bin:$PATH"; codex exec -s workspace-write -o <final> "$(cat <prompt>)" < /dev/null`.
5. Read any shell command in a Codex probe **before** running it (`COPY … FROM PROGRAM`). Run each probe on a fresh clone with the frozen patch, and save `<probe>.author-run.txt`.

Scratch helper from this session, worth rebuilding: clone `tally`, revoke TEMP from PUBLIC, tally_app and tally_core, strict-apply the working patch, run the battery, print the first FAIL.

## Not Yet Done

- [ ] -24 r11: CI on the new base, freeze, review. Battery 335, races 29.
- [ ] -25 r2: the default table (above). Battery 222, races 12, mutations 126.
- [ ] -26: not reviewed. At its mirror, update AC-10.
- [ ] **For later money patches:**
  - **a bill's credit line** (K-17): `invoice_line_position_as_of` counts positive lines only, and the cap is per line, so a paid bill reads open by the credit and takes that much again. Read, not run by money; scenarios confirmed a like case. A courtesy posted as a ledger reversal (SCN-0004) looks to have the same gap. The design must also say what happens when a credit exceeds the lines it can reduce;
  - **one charge, part of it due later** (Ryan 2026-11-22, board: the record scenarios asks for, read by the penalty rule and the aging);
  - **a split check** for a deposit and a bill: one payment per processor transaction (-19's index) refuses the second (SCN-0091 c);
  - a penalty on the ledger with no bill line takes no application (SCN-0092); nothing posts a ledger row when a credit goes to the state (SCN-0088 c); a customer's direction has no basis of its own (Kyle 11-05, 16); -27 R3 has no settling record (SCN-0101 b);
  - a posting undone while its payment is pending, for payments not from a receipt (-23's; -24 r11 refuses it for a receipt's);
  - NaN amounts in -23's tables; -23's helper bodies unpinned; the two -23 escheat gaps.
- [ ] **At -24's mirror:** contracts for READ COMMITTED on provider ids, for a reconciliation adding `suspense_misposting_returns_due_as_of` to `suspense_held_as_of`, and for the history loader (a receipt loads in recorded order; its payments are loaded pending and moved); operator guidance (a take-back learned after a payment ended reversed: return it to the receipt, then `bank_returned` there with its code; a misposting whose credit was refunded leaves the wrong customer owing); limits L1–L6; DEPLOY-VERIFICATION; the parity re-grade of CI-053 and CI-056.
- [ ] **At -25's mirror:** a contract that a reading's move into or out of disputed is written at READ COMMITTED.
- [ ] Counsel question C-03; tell Kyle the three items from 11-06's handoff.

## Key Decisions (DECISION-LOG 2026-11-22 has the reasons)

| Decision | Where |
|---|---|
| Of the two dispute rulings of 11-07, the scenarios version stands: a city's own rule wins; the disputed amount only; until resolution or 60 days from issue (issue day = day 1) | DECISION-LOG; AC-46 rewritten |
| The silent-city default reaches every customer class, and blocks the late fee and both disconnection steps; stages and duties empty | DECISION-LOG; -25 r2 plan |
| Day 60 unresolved: the disputed amount takes the next bill's due date (scenarios) | DECISION-LOG; AC-46 |
| -24: what the bank took must be unambiguous when a receipt's payment ends (by rule; r11 plan item 1) | r11 plan |

## Failed Approaches (Don't Repeat These)

- **A default inside a delegation document** (-25): `enforce_rule_term_schema` (-17) holds a delegation to exactly `governs`, `citation`, `note` → its own table instead.
- **A final figure in a reader with coordinates** (-24 r9): the share was taken as known now → compute at the coordinates, and add every new place money can be to the conservation sweep, both ways.
- **Allowing a coded return where the tree has an nsf row** (Opus r9's rule): returns money the bank took in two pieces. **Refusing a code only on a part-bounced tree** (r10): still ambiguous for two plain reversals and for an undone bounce. → r11's ending rules.
- **Recording every bank return on a receipt's payment as nsf** (planned, dropped): `nsf` is counted against a customer; an unauthorized debit (R10) is not a bounce.
- **A trigger on `account_ledger` that joins `payments`** (r11's first form): `void_invoice()` runs as `tally_void`, which may not read it; every void was refused. -24's own tests stayed green; only ci.sh showed it.
- **Comparing two aggregates to test an order**: PostgreSQL 16 sorts the input for both → `WITH ORDINALITY`.
- **Editing tests or pulling while ci.sh or a mutation run reads them**: use a separate worktree.

## Current State

- `tally` carries -30 (rates mirrored it on 11-22 and replaced the container). `ci.sh` PENDING: -25, -26, -24.
- **Two ci.sh races failed once on 11-22** (-20 RC3, -26 CR8b: "session B was never seen waiting on a lock"), under load; each passed three times alone and in every later full run. Cause not established.

## Warnings

- Don't edit a patch or its tests while ci.sh or a mutation run is going.
- Revoke TEMP after every TEMPLATE clone. Never edit frozen review copies or bodies mirrored into `tu.sql`.
- Before a mirror or `ci.sh --build`, check that no other stream is mid-run.
- -24's battery ids: `…0000000a24xx` (few free) and `…0000000c25xx`; race ids `…0000000b24xx`.
