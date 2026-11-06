Folder: `~/code/tally-utility`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: schema stream "money" — cash, disputes, collections, enrollments, notices

**Generated**: 2026-11-06, afternoon
**Branch**: `main`, pushed (this wrap-up's commit).
**Status**: **-27 is mirrored** into `tu.sql` (2026-11-06, Ryan's approval). Nothing of this stream is in flight. The next patch is -24.

## Goal

Close this stream's half of the open invariants, in order (Ryan, 2026-11-02):
1. -23 (mirrored 2026-11-04);
2. -27 (**mirrored 2026-11-06**);
3. **-24** (next);
4. -25 and -26 (drafted; review them during -24's waits);
5. enrollments;
6. notices;
7. new rule types.

One patch at a time. The rates stream (`~/code/tally-utility-rates`) and the scenarios stream run beside this one.

## Resume Instructions

1. Run `git pull --ff-only`. Then `git -C ../gas-billing-memory fetch` and check `HEAD..origin/main`. Read the board's notes for this stream.
2. **Start -24** (unmatched cash and agency pledges; CI-053, CI-056). It is claimed on the board but not drafted. Begin with a source inventory and a design, the way -27's was done (`application/wave2-build-2026-10-15/v5.4.2-27-design.md` is the model). Settle findings by standing rule. Ask Ryan only what changes where money ends up, or what conflicts with a ruling (memory: policy vs bookkeeping questions). Tests come first.
3. **While -24 waits on reviews, review -25 and -26.** First re-test both on the current `tally`, which now carries -27, -28 and -29: strict apply, then each battery. ci.sh already applies them over the build (56/56 pass). At -26's mirror, update AC-10, which still lists `dunning_stage` and `late_fee_*` as writable.
4. **Codex:** it hit its usage limit on 2026-11-06 (reset 16:06 that day). If it is limited at a review, give Ryan the reset time and let him wait or waive.

## How a round is reviewed (as -27's)

- **Freeze.** Copy the patch, battery, races and runner to `tests/v5.4.2-NN/review/*-frozen-rN.*`; write `r(N-1)-to-rN.diff`; write the brief with `@@` placeholders, filled by script with the md5s and results; write the brief's md5 to `.md5`; make `codex-prompt-rN.md` by sed from the last one. Set the board line to "rN frozen".
- **Opus and Fable:** the Agent tool, general-purpose, `model: opus` / `model: fable`, named `opus-rN` / `fable-rN`. Ask for a reply under 2 KB, with the detail in the file.
- **Codex:** run it in the background: `export PATH="$HOME/.nvm/versions/node/v24.15.0/bin:$PATH"; codex exec -s workspace-write -o <final.txt> "$(cat <prompt>)" < /dev/null`. It takes about 15–25 minutes. Then run its probes yourself, each on a fresh clone with the frozen patch applied strictly, and save `<probe>.author-run.txt`. Its predictions have been right every time; run them before believing any "always" claim of your own.

## Not Yet Done

- [ ] **-24** (above).
- [ ] **Review -25 and -26** (above).
- [ ] **Two -23 gaps, for a later money patch.** All three -27 reviewers say they do not block -27:
  - `refund_reissue` can name a refund that came back before its credit's escheat. Opus suggests -27's pattern: the database records, when the refund leaves, whether its credit was already escheated.
  - No commit check carries a returned refund of an escheated credit (Fable r3 N8).
- [ ] **Board notes to money:** from scenarios (Kyle's answers of 11-03 and 11-05; the Mcf unit list loosening -21's check) and from R-12 (two-column tenant keys). Read them on the board.
- [ ] **Counsel question C-03** (setoff before an escheat report, per state).
- [ ] **Then:** enrollments, the reconnect check (CI-072), notices, new rule types.
- [ ] **Tell Kyle (not blocking):**
  - ui-concepts still lists `refunded`;
  - `do_not_disconnect` should become a protective enrollment;
  - the four wave-3 law findings.
- [ ] **Roadmap housekeeping:** `decisions.json` has two R-23 and two R-24 entries (a P1 pair from this stream, a P2 pair from scenarios). Renumber one pair in coordination with the scenarios stream.

## Key Decisions (DECISION-LOG has the reasons)

| Decision | Where |
|---|---|
| An undo of a shortfall repayment is dated no later than today (UTC+14), or the row it undoes where later; -23's R-02 rule | DECISION-LOG 2026-11-06 (-27 r3) |
| The database records whether an undo gave money to an escheated credit (`gave_to_escheated`); a carry names only such an undo. Built as option 2 although Ryan approved option 1 (option 1's cost was larger than stated) | DECISION-LOG 2026-11-06 (-27 r3) |
| A short round 5 before the mirror; Codex waived for it; -27 mirrored ahead of -25 and -26 | DECISION-LOG 2026-11-06 (-27) |
| Ask Ryan only about where money ends up or conflicts with rulings; settle stamps, labels and orderings by rule even when a reviewer says "Ryan's call" | memory `policy-vs-bookkeeping-questions` |

## Failed Approaches (Don't Repeat These)

- **A second reading "from today on" in the return check (r3).** It ran only when money left the family, so an undo dated in the future, recorded on its own, was admitted. Its window also read only dates that some row falls on.
- **Saying a reader term "always reads 0".** Rows written in a take-back's own transaction share its `now()` and count at its instant. Codex disproved this twice, in r3 and r4.
- **Comparing two `now()` stamps to order events in one transaction** (`<` and `<=` both fail one way or the other). Record the fact as the row is written instead.
- **Running -23's battery on a clone with -27 alone.** After the rates stream's port, it needs -30 applied after -27.
- **Earlier failures** are in the CHANGELOG, including `SET CONSTRAINTS IMMEDIATE` left on in a battery, mutations run without `python3 -u`, and Codex run with `-s read-only`.

## Current State

- **`tu.sql`:** 49,090 lines, md5 `26ea77de6d842fcca59b8c85a018d6f7`. It carries -23, -27, -28 and -29. DEPLOY-VERIFICATION has the -27 entry, with deployment queries.
- **`tests/ci.sh` PENDING:** -25, -26 and -30. `ci.sh --build` passed 56/56 after the mirror.
- **The -27 record:** `tests/v5.4.2-27/review/`, five rounds with every brief, frozen copy, review and Codex probe author-run; plans r2–r5.
- **Parity:** 85 of 135 (update 2026-11-06, no class change). AC-44 is updated.
- **Roadmap:** P1 at 85 of 135; R-25 and R-26 answered; the dashboard is refreshed. Ready to onboard 2027-06-09 likely (unchanged).
- **Docker:** the container was rebuilt by `ci.sh --build`. Only `ci.sh`'s own `ci_*` databases and `tally` remain. Two small postgres-mcp containers belong to the desktop app and should be left alone.
- **Uncommitted changes:** none after this wrap-up's commit.

## Warnings

- Don't edit a patch or its tests while a mutation run is going.
- Revoke TEMP after every TEMPLATE clone. Never edit frozen review copies, or the bodies already mirrored into `tu.sql`.
- Before a mirror or `ci.sh --build`, check that no other stream is mid-run (the board's query). `--build` replaces the container.
- When updating the roadmap dashboard, read the dataset's current file first. Another stream may have uploaded a newer one that isn't pushed to git yet (it happened today: K-15). Merge, don't overwrite.
- -27's battery ids are `…0000000027xx` and `…0000000029xx`, and its races use `…0000000028xx`. Those race ids collide with -23's battery, so run -23's battery on a clone the race script has not touched.
