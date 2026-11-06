Folder: `~/code/tally-utility-rates`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: schema stream "rates" — tax, gas cost, zones, reads, dated history

**Generated**: 2026-11-06, end of this stream's fourth session
**Branch**: `main`. Run `git pull --ff-only` first.
**Status**:
- **v5.4.2-30** (tax levies and taxability) is at **round 3, frozen and in review**. Opus and Fable both say **ready** on r3. **Codex has not yet reviewed r3**: its usage limit reset at 16:06 on 2026-11-06, and this session left a background job that starts it at 16:08 (see Resume Instructions, item 1).
- -30 is in `ci.sh` PENDING (after money's -27). CI: 59/59.
- Kyle answered the franchise-fee base (K-15, 2026-11-06), so -31 is unblocked.

## Goal

Close the rates half of the open invariants, beside the money stream (`~/code/tally-utility`). Parity stands at 85 of 135.

## How this stream differs from working alone

- **The board** (`HANDOFF.md`): read it at session start and before every mirror. Edit only this stream's lines.
- **Next free patch number:** -31. Claim a number on the board before creating its file.
- **`tests/ci.sh`:** one run at a time across clones (a lock). -30 is in PENDING; its battery, race test (`races v5.4.2-30`) and the seven older tests ported to it all run.
- **Law runners:** this clone has no `tools/law/.venv`. `ci.sh` finds the main checkout's venv by itself.

## Completed this session

- [x] **Seven older tests ported to -30's required answers** (batteries -09, -16, -20, -21, -23 (money's), -28, -29 and race labels-21); -30 added to `ci.sh` PENDING and the battery loop. Board note to money (2026-11-06) posted.
- [x] **New test tools:** `tests/v5.4.2-30/mutations-30.sh` (57 mutations; kinds: battery label, `PRE:` preconditions, `RACE:` race leg), `preconditions-30.sh` (C0–C6: the guards that fire only over existing data, the re-apply after a percent fact, the backfill), `races/levy-30.sh` (R1–R5).
- [x] **Round 1** frozen and reviewed by all three (Opus and Codex not yet, Fable ready). Codex's five probes run by the author; all predictions held.
- [x] **Round 2** (`application/rates-build-2026-11-05/v5.4.2-30-r2-plan.md`): a premise's state is recorded on change (`service_location_state_history`) and read as known; a place is never closed from under a levy (a deferred check at commit, so a succession passes); late-penalty guards ALWAYS; the repair re-applies after percent facts; exemption services checked; the gaps report lists a published rate with no levy. Opus and Fable reviewed it (both not yet, the same blocking item); Codex was rate-limited.
- [x] **Round 3** (`v5.4.2-30-r3-plan.md`): an overlapping state correction that began first is refused and retries (40001); the coverage check needs an all-tenants role; a past read within two places of one exclusive group refuses; a levy insert that waited re-reads the place's rows (40001). Opus and Fable: **ready**.
- [x] DECISION-LOG: 2026-11-06 (rates, -30 r1) and (rates, -30 r2), including Kyle's franchise answers. Design 2.4 narrowed. Board: -30's row, the new table, the template-stamps item (unassigned).
- [x] Roadmap: K-15 answered; dashboard's decision queue uploaded.

## Not Yet Done

1. [ ] **Codex's r3 review.** Check `tests/v5.4.2-30/review/codex-r3.md`. If missing, the background job died with the session: run it (Resume Instructions, item 1). Run its probes on a clone with frozen r3 applied and append the output to its file, as for r1 (`codex-r1-probe-results.txt` shows the shape).
2. [ ] **Round 4, short**, folding the r3 should-fix items (all three reviewers' together). From Opus and Fable so far:
   - **Fable S1:** the exclusive-group refusal counts membership rows, not places. The same county voided and re-recorded by overlapping transactions is refused as "two places". Count `DISTINCT m.place_id` (and keep the main read from returning a place twice).
   - **Opus S1:** L7 and `premise_places_as_of`'s comment overclaim ("refuse, never mis-answer"; "a rebill sees what the bill saw"). Stamps are the writer's transaction start, so a writer in flight at the bill's instant can make a rebill answer different places. Restate L7 and narrow the comment. Widen the board's stamps item: `clock_timestamp()` does not cover a writer straddling the instant. The lasting remedy is the core's (a bill line records its levies and places, as L5 already gives money; or the core reads at an instant every writer begun by then has finished). Opus said this is not new: every as-of read in the schema works this way.
   - **Opus S2:** the two-places check's `relation = 'within'` and `exclusivity_group IS NOT NULL` filters are untested. Add a fixture (a premise outside two cities, or in two stacking districts) and two mutations.
   - Opus notes (non-blocking): a sub-millisecond residual in the levy's coverage read (a one-clause fix, in `opus-r3.md`); the recorder refuses while the server clock is stepped back; the backfill trusts a settable `created_at`.
   - Fable notes: `levy-30.sh`'s `seen()` prints a FAIL line twice (cosmetic).
   These are settled by rule (wording, tests, and a narrowing that refuses less). Then a narrow review of r4, and ask Ryan about the mirror.
3. [ ] **Before the mirror:** re-run -30's battery and races on the current `tally` (the money stream mirrors -25, -26, -27 first; -27 reached r5 on 2026-11-06, not yet run with -30 r3). Follow the board's pre-mirror check.
4. [ ] **-31 franchise fees** (Kyle 2026-11-06, GBM `application/kyle-decisions-2026-11-06-franchise-fee-base.md`):
   - The base is one of two values, no default: "gas sales" or "all billed lines" (never taxes or the fee itself).
   - A rider's exclusion leaves it out of the rule's base.
   - No per-charge flag: a city may have several franchise rules, each covering a required list of customer classes. No two rules may cover one class over overlapping dates; this replaces `UNIQUE (tenant_id, city_name, effective_date)`.
   - Keyed to the city as a place; rate in percent.
   - No 2% cap check that assumes §182.025 governs city-owned systems (§182.026(a)).
   - Design: `tax-design.md` section 3.
5. [ ] -32 (Texas cities and districts, with the Comptroller's rates as reference facts), then the carried-over items:
   - the gas-cost billing side;
   - zones and factor tables;
   - read ownership and replacement reads (Kyle batch 2, answer 15);
   - dated history and the meter test fee;
   - the backbilling tariff table (Kyle batch 2, answers 10–14);
   - retiring the `decimal` rate unit;
   - retiring the old customer exempt columns.

## Failed Approaches (Don't Repeat These)

- **A place-close check at the close itself (BEFORE UPDATE):** it refuses every succession. A code's rows never overlap, so the successor row can only be inserted after the close. The check runs at commit (deferred constraint trigger).
- **Stamping the state history with `clock_timestamp()`** (Fable's r2 suggestion): a correction's row then post-dates the membership voids in its own transaction, and a read between them sees the old state without its places. Keep `now()` and refuse the overlapping writer.
- **`ALTER TABLE places …` after a place close in the same battery transaction:** "pending trigger events" (the deferred check). Plant place stamps before any close.
- **A tie-break test that ends where it began** (TX → NM → TX): both orders give TX. End on a different state.
- **A test fragment like `empty`** that the new wording also contains ("non-empty"): match the old phrase itself.
- **Reading after `COMMIT` in the same psql session that did `SET ROLE tally_app`:** the role persists without `app.user_id` (22P02). Read in a new session.
- Carried over: a uuid as a rule-template key (keys are text); editing a vocabulary row directly; non-canonical JSON numbers (`1.0`); expecting "as known before the build" to read empty.

## Key Decisions (DECISION-LOG 2026-11-06)

| Decision | Rationale |
|---|---|
| A premise's state recorded on change, not its change refused | A premise with no memberships still reads its state's tax; a clerk's typo is corrected, not refused |
| Overlapping state corrections: the earlier-begun writer retries (40001) | One transaction, one instant; the database's own "changed since you read it" pattern |
| Place-close coverage checked at commit, under an all-tenants role | A succession needs close-then-insert; the check counts every tenant's levies |
| A levy insert that waited re-reads the place's rows (40001) | -16's rule: a row committed while a writer waited is never trusted unlocked |
| Codex on every round unless Ryan waives it | Standing rule; r2 went to r3 for Codex because of its usage limit |

## Current State

**Working:** `tally` holds -23, -28 and -29. -30 r3 applies strictly twice. Battery 112/112, preconditions 8/8, races 5/5, mutations 57/57, `ci.sh` 59/59 (with -30 pending after money's -25, -26, -27 r4).

**Uncommitted changes:** none after the wrap-up commit. Codex's r3 output, if it lands later, goes to `tests/v5.4.2-30/review/codex-r3*` (uncommitted until the next session).

## Code Context (r3 additions to r0)

```sql
public.service_location_state_history (tenant_id, service_location_id, state, recorded_at now(), seq identity)
  -- written by z_record_service_location_state (AFTER INSERT OR UPDATE OF state on service_locations, ALWAYS);
  -- refused to the app (a_enforce_state_history_written_by_db, depth fence); append_only; backfilled at created_at;
  -- an UPDATE is refused 40001 when the premise has a row stamped after now()
premise_places_as_of(loc, on, axis, recorded_at)   -- state from the history (latest recorded_at, seq by then);
  -- refuses P0002 "not yet recorded"; refuses 21000 when two within places of one exclusivity group answer
public.check_place_levy_coverage()  -- z_check_place_levy_coverage: DEFERRABLE INITIALLY DEFERRED, AFTER UPDATE OF effective_to
  -- on places, ALWAYS; needs superuser/BYPASSRLS; every levy of the code still covered by its rows
tax_levy_insert_check   -- VOLATILE; READ COMMITTED; share-locks each row of the code, re-reads them (40001 if new), then coverage
tax_levy_reference_gaps -- second leg: a place reached by the utility's premises, publishing a rate, with no levy (levy_id NULL)
```

## Resume Instructions

1. **Codex on r3.** If `tests/v5.4.2-30/review/codex-r3.md` does not exist, run:
   `PATH=~/.nvm/versions/node/v24.15.0/bin:$PATH codex exec -s workspace-write -C ~/code/tally-utility-rates -o tests/v5.4.2-30/review/codex-r3-final.txt "$(cat tests/v5.4.2-30/review/codex-prompt-r3.md)" < /dev/null > tests/v5.4.2-30/review/codex-r3.log 2>&1`
   (in the background; it takes about 10 minutes; watch for "usage limit" in the log). Then run its probes from `codex-r3-probes/` on a fresh clone of `tally` with `patch-30-frozen-r3.sql` strict-applied, and append the results to `codex-r3.md`.
2. Fold all three reviewers' r3 should-fix items into r4 (Not Yet Done, item 2). Write `v5.4.2-30-r4-plan.md`; tests first; re-run the battery, preconditions, races, mutations and `ci.sh`; freeze r4 and run a narrow review with all three.
3. Ask Ryan about the mirror once all three say ready (one question; re-test on the current `tally` first, item 3).
4. Then -31.

## Warnings

- Revoke TEMP after every TEMPLATE clone. At most two mutation runs at once. The mutation runner drops `m30`, `m30p` and `r30m` when it ends: don't use those names for your own scratch work.
- Never edit the frozen review copies or `tu.sql`'s mirrored bodies.
- -30's battery -23 port means money's battery -23 passes only with -30 applied. Run it through `ci.sh` until -30 is mirrored (board note of 2026-11-06).
- Kyle's batch 2 answer 3b (late-charge tax depends on the tariff's form) and the penalty engine are the money stream's.
- Before writing or reviewing patch code, read the index at the top of `sql/PATCH-LESSONS.md`.
- Ryan wants plain language with no shorthand codes in what he reads, and one decision per message.
