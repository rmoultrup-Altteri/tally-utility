Folder: `~/code/tally-utility`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: schema stream "money" — cash, disputes, collections, enrollments, notices

**Generated**: 2026-10-29, night
**Branch**: `main`, pushed (`111cbf0` plus this wrap-up's commit).
**Status**: -23 round 7 is built and tested, not frozen. It waits on Kyle's answer (asked in Slack 2026-10-29 19:09 CDT, DM D0B0GRDQYLR): do a payment's credits net against each other, and is a credit's shortfall covered first by its sibling credits (our lean, built) or by the payment's own money? Ryan: round 7 is not frozen until he answers.

## Goal

Close this stream's half of the open invariants, in order: -23 → -24 → -25 → -26 → enrollments → notices → new rule types. Each patch here builds on the one before, so this stream runs one patch at a time. The rates stream (`~/code/tally-utility-rates`) and the scenarios stream (`~/code/tally-utility-scenarios`) run beside it.

## Resume Instructions

1. `git pull --ff-only`; `git -C ../gas-billing-memory fetch` and check `HEAD..origin/main`. Read the board's notes for this stream. Read the Kyle DM (Slack plugin: `slack_read_channel` D0B0GRDQYLR) for his answer.
2. When Kyle answers: record it in GBM `application/` with a line in `wiki-ingestion-pending.md` in the same edit (his answers by chat are ours to record), add a DECISION-LOG entry, and set K-11 to answered in `application/roadmap/decisions.json`.
   - **Sibling credits first (A):** nothing changes in the patch.
   - **Payment first (B):** change the netting order in `overpayment_absorbed_as_of` (the `IF p_cover` block, "r7 (Fable B1"): cover from the payment before the siblings. Then rerun the battery (Z1–Z3a will need new expected figures), the races, and the full mutation run (N212 and N194 touch the cover).
   - **No netting at all:** that reopens Fable/Opus/Codex B1; take it to Ryan.
3. Freeze round 7: frozen copies, `tests/v5.4.2-23/review/review-brief-23-r7.md` with md5s, `codex-prompt-r7.md`. The brief must list the known limit (below) and the plan's "As built" points. Then launch the three reviewers as in round 6:
   - **Opus and Fable:** Agent tool, `model: opus` / `model: fable`, writing `opus-r7.md` / `fable-r7.md`. Their final reports cut off around 4 KB: ask for several SendMessages under 3 KB.
   - **Codex:** `codex exec -s workspace-write -o tests/v5.4.2-23/review/codex-r7-final.txt "$(cat tests/v5.4.2-23/review/codex-prompt-r7.md)" < /dev/null`, under nvm v24.15.0 (prefix PATH). If rate-limited, give Ryan the reset time.
   - Run Codex's probes yourself on a fresh clone with frozen r7 applied. Probe 02 (the 1,000-reissue chain) took over 50 minutes on r6; r7 reads the shares once per reading, so time it but cancel past 30 minutes and say so.
4. Merge into `v5.4.2-23-r8-plan.md`, or if all three say ready, ask Ryan about the mirror (board's pre-mirror check first).

## Not Yet Done

- [ ] **Kyle's answer, then freeze and review round 7** (above).
- [ ] **-24** (unmatched cash and agency pledges; CI-053, 056), after -23.
- [ ] **Review -25 and -26** after -23 settles. Drafted and tested, not frozen; they passed CI on top of r6 (49/49), not yet rerun on r7. They mirror after -23, -25 first. At -26's mirror, update APPLICATION-CONTRACTS: AC-10 still lists `dunning_stage` and `late_fee_*` as writable.
- [ ] **`tests/ci.sh` on r7** has not been run (optional before the freeze; through its lock).
- [ ] **Then:** enrollments (wave 4: CI-060, 065, 081 link, 082–085); the reconnect technician check (CI-072); notices (wave 5: CI-088, 093–097, 111, 135); new rule types (wave 7: CI-043, 054 late-fee rows, 079, 080, 081 law row, 105, 114).
- [ ] **Tell Kyle (not blocking):** ui-concepts still lists `refunded`; `do_not_disconnect` must become a protective enrollment; the four wave-3 law findings.
- [ ] **Carried over:** the reply to Kyle on where D-2 lives (his 10-14 question, still unanswered); -21 R9; the Florida 25-7.083 text; the waiver rewrite; the -15 r8 follow-ups.

## -23 round 7: what was built

Plan: `application/wave2-build-2026-10-15/v5.4.2-23-r7-plan.md` (fix list, "Waiting on Kyle", "As built"). Calls: DECISION-LOG 2026-10-29 (-23 r7).
- **Credits cover each other's shortfall:** in `overpayment_absorbed_as_of`, a credit in deficit (the overpayment credit first) is covered by sibling credits holding money, the latest first, then by the payment.
- **Escheat on the credit's own money:** a credit is escheated only when its own side, without the cover, holds nothing positive.
- **A reissue carrying a share of a take-back can't be voided**; once the share is given back, it can. **Known limit (Ryan, 10-29, not put to Kyle):** a reissue made by mistake after a take-back stays, its money on that line until refunded or applied.
- **A reissue's void takes its payment's lock first** (the void/give-back deadlock; race CR25).
- **Reissue lines are at most 999 deep** (`reissue_line_bound()`); deeper is refused at the make, and every walk raises (22000) rather than returning NULL.

## Failed Approaches (Don't Repeat These)

- **Passing a voided reissue's share back to its credit:** needs the shares re-split at the void's instant through every reader and cap; refused instead.
- **Codex with `-s read-only`:** it cannot write its review or probes.
- **A reissue's share placed at the reading; caps reading the covered positions; one-instant fixtures for distinct-instant shapes** (round 6).
- **Running `tools/roadmap/schedule.py` in place for a what-if:** use a scratch copy.
- **Earlier -23 rounds:** the r5 plan's B2; a dynamic split; the shortfall placed at the take-back; `(created_at, id)` order within one transaction; W4 in one transaction; `for i in $ids` in zsh; `docker stop` on postgres-mcp containers (use `docker kill`).

## Key Decisions

| Decision | Rationale |
|---|---|
| Which credit covers a shortfall goes to Kyle; round 7 built on sibling-first, not frozen till he answers | DECISION-LOG 2026-10-29 (-23 r7) |
| Refuse a reissue's void while it carries a take-back's share; a known limit | same entry (Ryan) |
| -23 r6's calls | DECISION-LOG 2026-10-29 (-23 r6) |

## Current State

- **-23 r7 on fresh clones:** strict apply twice clean (the second skips, "already applied"); battery 372/372; races 39/39; mutations 218/218, files unchanged during the run. Two needed a rerun: N129 missed once on a timing miss in CR10 under load (caught alone at CR17); N203 was re-anchored from Y7b to Y7i, because the new cover makes Y7b read right even under the mutation.
- **Red runs against r6:** battery Z1–Z5d and Z6a–d fail; CR25 deadlocks.
- **Dashboard:** P1 text and K-11 (open) updated; dates unchanged (ready to onboard 2027-06-09 likely).
- **Uncommitted changes:** none after this wrap-up's commit.

## Warnings

- **Don't edit the patch or tests while `mutations-23.py` runs.** A selected rerun: `python3 tests/v5.4.2-23/mutations-23.py N129 N203`. There is no `timeout` command on this Mac.
- **CR10 can miss its "B waits" observation under the full mutation run's load.** If a mutation fails CR10 that way, rerun it alone before believing it.
- **Revoke TEMP after every TEMPLATE clone. Never edit the frozen review copies or tu.sql's mirrored bodies.**
- **Other streams share tally-pg.** Use the board's pre-mirror check; run `ci.sh` only through its lock.
- **7 postgres-mcp containers were running on 10-29.** Other sessions may own them; leave them alone.
