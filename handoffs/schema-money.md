Folder: `~/code/tally-utility`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: schema stream "money" — cash, disputes, collections, enrollments, notices

**Generated**: 2026-10-29, evening
**Branch**: `main`, pushed (`00b39b1` plus this wrap-up's commit).
**Status**: -23 round 6 is built, tested and frozen. Next: launch the three reviewers on it (Ryan, 2026-10-29: "launch the reviewers in the new one").

## Goal

Close this stream's half of the open invariants, in order: -23 → -24 → -25 → -26 → enrollments → notices → new rule types. Each patch here builds on the one before, so this stream runs one patch at a time. The rates stream (`~/code/tally-utility-rates`) and the scenarios stream (`~/code/tally-utility-scenarios`) run beside it; neither has opened a session yet.

## Resume Instructions

1. `git pull --ff-only`; `git -C ../gas-billing-memory fetch` and check `HEAD..origin/main`. Read the board's notes for this stream.
2. Check the frozen md5s match `tests/v5.4.2-23/review/review-brief-23-r6.md` (the brief's own md5 is in `review-brief-23-r6.md5`).
3. Launch the three reviewers, independently, in the background:
   - **Opus and Fable:** Agent tool, `model: opus` / `model: fable`, told to read and follow `tests/v5.4.2-23/review/review-brief-23-r6.md` and write `opus-r6.md` / `fable-r6.md`. Their final reports cut off around 4 KB, so ask for several SendMessages under 3 KB each (memory).
   - **Codex:** `codex exec -s read-only -o tests/v5.4.2-23/review/codex-r6-final.txt "$(cat tests/v5.4.2-23/review/codex-prompt-r6.md)" < /dev/null`. It works only under nvm v24.15.0 (prefix PATH; memory "codex reviewer node path"). If it is rate-limited, give Ryan the reset time and let him wait or waive.
   - Then run Codex's probes yourself on a fresh clone with the frozen r6 applied.
4. Merge the three into `application/wave2-build-2026-10-15/v5.4.2-23-r7-plan.md`, or, if all three say ready, ask Ryan about the mirror. Before mirroring, follow the board's pre-mirror check.

## Not Yet Done

- [ ] **-23 r6 reviews** (above).
- [ ] **-24** (unmatched cash and agency pledges; CI-053, 056), after -23. Claim nothing on the board: -24's number is already this stream's.
- [ ] **Review -25 and -26** after -23 settles. Both are drafted and tested, not frozen, and pass CI on top of r6 (49/49). They mirror after -23, -25 first. At -26's mirror, update APPLICATION-CONTRACTS: AC-10 still lists `dunning_stage` and `late_fee_*` as writable.
- [ ] **Then:**
  - enrollments (wave 4: CI-060, 065, 081 link, 082–085);
  - the reconnect technician check (CI-072);
  - notices (wave 5: CI-088, 093–097, 111, 135);
  - new rule types (wave 7: CI-043, 054 late-fee rows, 079, 080, 081 law row, 105, 114).
- [ ] **Tell Kyle (not blocking):**
  - ui-concepts still lists `refunded`;
  - `do_not_disconnect` must become a protective enrollment;
  - the four wave-3 law findings.
- [ ] **Carried over (this stream's):**
  - the reply to Kyle on D-2's location;
  - -21 R9;
  - the Florida 25-7.083 text;
  - the waiver rewrite;
  - the -15 r8 follow-ups.

## -23 r6: what to know before reading the reviews

- **Shares are fixed when a take-back is recorded; the cover is applied at the reading.** `overpayment_shares` gives each credit of the family (the overpayment credit and its reissues) a share per row under the payment's posting entry, by what each held at that row's instant: the overpayment credit first, then each reissue in recorded order. A give-back restores the latest share first. `overpayment_absorbed_as_of` covers an existing deficit between the payment and the family at the reading. The caps read each side as recorded, and the pool cap holds the total. agree() in the battery checks that each position equals what its cap admits and that the positions add up to the ledger.
- **One instant floats (R17).** Shapes that need distinct instants are history loads at chosen times (`pg_temp.h*()` in the battery's Y section).
- **The As-built list** is at the end of the r6 plan; the calls are in DECISION-LOG 2026-10-29 (-23 r6).

## Failed Approaches (Don't Repeat These)

- **A reissue's share placed at the reading:** its own draw shrank its share, so its cap never applied (Y7j).
- **Caps reading the covered positions:** one side could draw the other's money.
- **One-instant fixtures for distinct-instant shapes:** the agree() probe itself moves a share.
- **Running `tools/roadmap/schedule.py` in place for a what-if:** use a scratch copy. When P2 does not wait on P1, P3 must depend on both.
- **Earlier -23 rounds:**
  - the r5 plan's B2: 60 out of 50;
  - a dynamic split;
  - the shortfall placed at the take-back;
  - `(created_at, id)` order within one transaction;
  - W4 in one transaction;
  - `for i in $ids` in zsh;
  - `docker stop` on postgres-mcp containers: use `docker kill`.

## Key Decisions

| Decision | Rationale |
|---|---|
| -23 r6's calls (shares as recorded, cover at the reading, own-side caps, credit-first attribution, no reissue-void lock) | DECISION-LOG 2026-10-29 (-23 r6) |
| Two schema streams, per-stream handoffs, clones; scenarios beside the schema | DECISION-LOG 2026-10-29 |

## Current State

- **-23 r6 on a fresh clone:**
  - strict apply twice, clean;
  - battery 344/344;
  - races 38/38;
  - mutations 210/210, with the files checked unchanged during the run.
- **`tests/ci.sh`:** 49/49 with -23 r6, -25 and -26 pending.
- **Speed (R21):** with 2 reissues and 4 rows, a position reads in 2–4 ms and a draw takes about 5 ms; with 10 reissues and 50 rows, 10–25 ms and 20–100 ms.
- **Uncommitted changes:** none after this wrap-up's commit.

## Warnings

- **Don't edit the patch or tests while `mutations-23.py` runs:** the runner re-reads the battery and races for every mutation.
- **Revoke TEMP after every TEMPLATE clone.**
- **Never edit the frozen review copies or tu.sql's mirrored bodies.**
- **Other streams now share tally-pg.** Use the board's pre-mirror check, and run `ci.sh` only through its lock.
- **7 postgres-mcp containers were running on 10-29** (about 70 MB each). Other sessions may own them; check before killing any.
