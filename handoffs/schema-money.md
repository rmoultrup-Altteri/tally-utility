Folder: `~/code/tally-utility`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: schema stream "money" — cash, disputes, collections, enrollments, notices

**Generated**: 2026-11-27
**Branch**: `main`, pushed (this wrap-up's commit).
**Status**: **-24** mirrored 2026-11-24. **-25** (disputes) mirrored 2026-11-27 (commit 894eecf; Opus, Fable and Codex ready on r9). **-26** (collections decisions) is next: drafted and tested, never reviewed.

## Goal

Close this stream's half of the open invariants, in order (Ryan, 2026-11-02):
1. -23, -27, -24, -25: done (mirrored).
2. **-26** (collections decisions): first review.
3. Enrollments.
4. Notices.
5. New rule types.

## Waiting on others

- **Kyle, K-17:** which of a bill's charges its own credit line reduces. Sent by Ryan 2026-11-27 (`application/kyle-brief-2026-11-22-credit-line.md`). No netting patch until he answers.
- **Kyle, K-14 (scenarios sends):** three departures of the dispute rulings from CI-054 and CI-074: a penalty on an amount under dispute at a Brenham-style city; the 60-day end; notices not blocked.
- **Kyle, K-19 (scenarios):** the sixth batch, on unmatched cash and pledges (roadmap decisions).
- **Counsel:** whether *Memphis Light v. Craft* (1978) reaches a Texas city's customers (a city's due-process duty before disconnection; -25 R3 leaves it to the core).
- Nothing waits on Ryan.

## Resume Instructions

1. `git pull --ff-only`; fetch GBM; read the board.
2. **-26:** `sql/v5.4.2-26-*.sql` and its tests under `tests/v5.4.2-26/`; design in `application/wave3-build-2026-10-18/`. It was written before -24 and -25 changed (its conditions `agency_pledge`, `aged_suspense` and the dispute blocks read their rows), so:
   - re-run its battery alone on the current `tally` (which now carries -24 and -25); expect failures where it still reads `pending_dispute` as protective or the old `meter_readings.dispute_*` columns;
   - read `sql/PATCH-LESSONS.md`'s index before touching it;
   - fix tests first, then the patch; then mutations (`tests/v5.4.2-26/mutations-26.py`; it needs a base built from before -26), ci.sh;
   - freeze r1 as for -25 (below) and review with all three. Codex has not seen -26.
3. At -26's mirror, update AC-10, and re-grade CI-067, CI-069 and the collections rows.

## In flight at wrap-up (check first)

Nothing is running. Two leftover postgres-mcp containers were running at the mirror (pre-existing; offered to Ryan to stop, no answer): check `docker ps -q --filter ancestor=crystaldba/postgres-mcp | wc -l` before CI.

## How a round is frozen and reviewed

1. Run the patch's `fill-manifest.py` after any change to a pinned object; then the battery, mutations, ci.sh.
2. Copy the patch, battery, races, mutations, terms, migration, fill-manifest and law yaml/seed to `tests/v5.4.2-NN/review/*-frozen-rN.*`; write `r(N-1)-to-rN.diff`.
3. Write the brief and its `.md5`, the Codex prompt (edit references by hand, not a global sed: it rewrites the earlier round's file names too), and `codex-rN-probes/`.
4. Commit and push, then launch:
   - **Opus and Fable:** agents (general-purpose, `model: opus` / `fable`), frozen copies only, each writes its review to a file.
   - **Codex:** `export PATH="$HOME/.nvm/versions/node/v24.15.0/bin:$PATH"; codex exec -s workspace-write -o <final> "$(cat <prompt>)" < /dev/null`.
5. Read any shell command in a Codex probe **before** running it. Run each probe on a fresh clone with the frozen patch, from a **bash** script (zsh will not run `$P` as a command), and save `<probe>.author-run.txt`.

## Mirror procedure (as done for -24 and -25)

Before: counts, `pg_dump --schema-only` with and without privileges, `catalog-identity.sql`, on a clone with the frozen patch. Append a blank line, a 4-line banner and the patch body to `tu.sql`; take the patch out of PENDING; `tests/ci.sh --build` (check no other stream is mid-run first); compare dumps and catalog (0 lines); TEMP off for every app role. Records: DEPLOY-VERIFICATION, APPLICATION-CONTRACTS, the parity update, DECISION-LOG, board, GBM section, roadmap `parity.json`. Errors in the container log after "init process complete" are the tests' expected refusals.

## Not Yet Done

- [ ] -26: first review (above).
- [ ] Opus's r9 wording note N1 on -25 (optional; mirrored text cannot change, so only in a later patch's header).
- [ ] **For later money patches:**
  - **a bill's credit line** (K-17): `invoice_line_position_as_of` counts positive lines only and the cap is per line, so a paid bill reads open by the credit; a courtesy posted as a ledger reversal (SCN-0004) looks the same; say what happens when a credit exceeds the lines it can reduce;
  - **one charge, part of it due later** (Ryan 2026-11-22, board);
  - **a split check** for a deposit and a bill: one payment per processor transaction refuses the second (SCN-0091 c);
  - a pledge's received day (Ryan 2026-11-25, board: one column); the credit-netting timing setting (board);
  - a penalty on the ledger with no bill line takes no application (SCN-0092); nothing posts a ledger row when a credit goes to the state (SCN-0088 c); a customer's direction has no basis of its own; -27 R3 has no settling record (SCN-0101 b);
  - a posting undone while its payment is pending, for payments not from a receipt;
  - NaN amounts in -23's tables; -23's helper bodies unpinned; the two -23 escheat gaps.
- [ ] The late fee's grace, rate, cap and exempt programs still have no data home (CI-054).

## Key Decisions (DECISION-LOG has the reasons)

| Decision | Where |
|---|---|
| A city's own dispute rule wins; the default protects the disputed amount only, until resolution or 60 days from issue (issue day = day 1) | DECISION-LOG 2026-11-22; AC-46 |
| Dispute terms that cannot be ranked are both kept; the core applies the more protective per customer | DECISION-LOG 2026-11-26; AC-58 |
| `final` binds the utility and never ends an appeal the combined record keeps; a law row with a non-final last stage comes back to Ryan | -25 R10; AC-60 |
| -25 mirrored after r9 with R10's wording fixed in the patch | DECISION-LOG 2026-11-27 |

## Failed Approaches (Don't Repeat These)

- **A global sed to bump round numbers in the Codex prompt**: rewrites the previous round's file references too.
- **Running the probe runner under zsh**: `$P` as a command fails; use bash.
- **`set -e` in a pre-mirror script with greps that may match nothing**: exits early.
- **A default inside a delegation document** (-25): `enforce_rule_term_schema` holds a delegation to `governs`, `citation`, `note` → its own table.
- **A trigger on `account_ledger` that joins `payments`**: `void_invoice()` runs as `tally_void`, which may not read it; only ci.sh showed it.
- **Comparing two aggregates to test an order**: PostgreSQL 16 sorts the input for both → `WITH ORDINALITY`.
- **Editing tests or pulling while ci.sh or a mutation run reads them**: use a separate worktree.

## Current State

- `tally` carries -25 (container replaced at the mirror; all scratch databases gone, including `mutations-25.py`'s base `m25base`: re-running that suite needs a copy built from before -25). `ci.sh` PENDING: -26 only. `ci.sh --build` 56/56.
- Counts: 163 tables, 9 views, 4 matviews, 125 policies, 124 FORCE-RLS, 593 FKs, 719 CHECKs, 31 EXCLUDE, 612 triggers, 680 functions, 837 indexes.
- Parity 88 of 135 (REP+PROT 62, REP 26, PARTIAL 38, GAP 8).

## Warnings

- Don't edit a patch or its tests while ci.sh or a mutation run is going.
- Revoke TEMP after every TEMPLATE clone. Never edit frozen review copies or bodies mirrored into `tu.sql`.
- Before a mirror or `ci.sh --build`, check that no other stream is mid-run.
