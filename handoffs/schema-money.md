Folder: `~/code/tally-utility`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: schema stream "money" — cash, disputes, collections, enrollments, notices

**Generated**: 2026-10-29
**Branch**: `main`, pushed.
**Status**: -23 round 6 waits on Ryan's go. The concurrency plan is half-agreed (see "Plan decisions so far"); the workstream decision is next and is asked from this folder.

## Goal

Close this stream's half of the open invariants, in order: -23 → -24 → -25 → -26 → enrollments → notices → new rule types. Each patch here builds on the one before, so this stream is strictly one patch at a time. The rates stream (`~/code/tally-utility-rates`) runs beside it on tables this one doesn't touch.

## Plan decisions so far (2026-10-29, Ryan)

- The schema estimate is 7 / 12 / 20½ weeks from 10-14 (was 3 / 5 / 8). The count of what's left: about 15 patches after -23, 24 / 47 / 91 working days in one stream. `phases.json` is not yet updated; that waits for the workstream decision.
- The schema runs as two streams (this one and rates), about 24 and 23 likely days, then the two all-table patches at the end. Parity about mid-December instead of late January.
- Per-stream handoffs, a shared board (`HANDOFF.md`), one clone per stream identified by its folder name, memory linked, a CI lock. Clones, not worktrees (Ryan: "clones seem easier").
- The what-if runs are in this session's scratchpad. To repeat one, copy `tools/roadmap/schedule.py` and `application/roadmap/phases.json` into a scratch tree (`<scratch>/tools/roadmap/`, `<scratch>/application/roadmap/`) and edit the copy. When P2 stops waiting on P1, P3 must depend on **both** P1 and P2 finishing (the first what-ifs forgot this).

## Not Yet Done

- [ ] **The workstream decision** (next, one decision per message): with two schema streams, Ryan's third session slot goes to scenarios (P2) or the platform (P4). That needs the gate question too: may scenarios start before the schema is at parity? Steps 3 and 4 stay in order. Then update `phases.json` (P1's weeks [7, 12, 20.5] and basis; `depends`; `as_of` to the day), run the scheduler, refresh the dashboard, record in DECISION-LOG, and write `handoffs/<third>.md` for `~/code/tally-utility-scenarios`.
- [ ] **-23 r6** (on Ryan's go): follow `application/wave2-build-2026-10-15/v5.4.2-23-r6-plan.md`.
  - **B1:** recorded-order legs under a payment's posting entry. **B2:** the shortfall's side decided at read time. **B3:** lineage order within one instant.
  - **B4:** `status_recorded_at` write-once. **B5:** a reissue stays in its payment's lineage.
  - **S1:** the refund deadlock. **S2:** the escheated give-back refused only as far as the credit would read positive. **S3:** no future `created_at` for superusers.
  - **S4:** tests and mutations. **S5:** comments.
  - Then freeze, run the three reviewers and merge.
- [ ] **-24** (unmatched cash and agency pledges; CI-053, 056), after -23.
- [ ] **Review -25 and -26** after -23 settles. Both are drafted and tested, not frozen; they mirror after -23, -25 first. At -26's mirror, update APPLICATION-CONTRACTS: AC-10 still lists `dunning_stage` and `late_fee_*` as writable.
- [ ] **Then:** enrollments (wave 4: CI-060, 065, 081 link, 082–085), the reconnect technician check (CI-072, it touches `service_orders`), notices (wave 5: CI-088, 093–097, 111, 135), new rule types (wave 7: CI-043, 054 late-fee rows, 079, 080, 081 law row, 105, 114).
- [ ] **Tell Kyle (not blocking):** ui-concepts still lists `refunded`; `do_not_disconnect` must become a protective enrollment; the four wave-3 law findings.
- [ ] **Carried over (this stream's):** the reply to Kyle on D-2's location; -21 R9; the Florida 25-7.083 text; the waiver rewrite; the -15 r8 follow-ups.

## Failed Approaches (Don't Repeat These)

- **Running `tools/roadmap/schedule.py` in place for a what-if:** it overwrites the dashboard's sources. Use a scratch copy.
- **Treating the scheduler's dates as capacity-aware:** it gives every phase full effort however many run at once.
- **-23:**
  - the r5 plan's B2, "the credit absorbs a take-back up to its amount": 60 out of 50;
  - a dynamic split: positions drift from the caps;
  - the shortfall placed at the take-back: 40 / −10 readable while only 30 can be drawn;
  - `(created_at, id)` order within one transaction: uuid ties;
  - W4 in one transaction: a shared `now()`;
  - `for i in $ids` in zsh: use `while read`;
  - `docker stop` on postgres-mcp containers ("404 page not found"): use `docker kill`.

## Key Decisions

| Decision | Rationale |
|---|---|
| -23: K-10 decides B2 as built; a cap on the payment and its credit together; reissue = `least(refund, what is left)` | See DECISION-LOG 2026-10-28 |
| Two schema streams, per-stream handoffs, clones | See DECISION-LOG 2026-10-29 |

## Current State

- -23 r5 on a fresh clone: battery 293/293, races 33/33, mutations 190/190. r5's findings are listed in the r6 plan.
- `tests/ci.sh` 49/49 before the lock; re-run after it (see the board).

## Warnings

- **Don't edit the patch or tests while `mutations-23.py` runs.**
- **Revoke TEMP after every TEMPLATE clone.**
- **Never edit the frozen review copies or tu.sql's mirrored bodies.**
- **7 postgres-mcp containers were running on 10-29** (about 70 MB each). Other sessions may own them; check before killing any.
