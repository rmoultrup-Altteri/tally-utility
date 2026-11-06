# v5.4.2-30 r3 — Fable's review

**Date:** 2026-11-06. **Reviewer:** Fable (Claude Fable 5.1), independent; `opus-r3.md` and `codex-r3.md` not read; my own `fable-r1.md` and `fable-r2.md` read.
**Frozen files:** all seven md5s match the brief (executed, `md5 -q`).
**Scratch:** `rv30fable` cloned from `tally`, TEMP revoked from PUBLIC / tally_app / tally_core, the frozen r3 patch strict-applied twice (search_path empty, function bodies checked): both clean, the second a no-op ending in the patch's "invariants hold" notice (executed). `rv30fablerace` for the race test and the three hand-applied race mutations (recreated per run). Both dropped at the end (executed, `pg_database` empty of `rv30fable%`). PATCH-LESSONS read: the index, count-guards-need-lock-handshake, lock-order-as-a-rule, race-barriers-clear-stat-snapshot, checks-narrower-than-their-claim, reviewer-fixes-need-measuring.

## Verdict: ready

My round-2 blocking item is closed by the fix the plan chose, and I measured it in the shapes the brief asks about: the overlapping writer that began first is refused whether it had touched the premise or not, a re-spelling after the other's change records nothing and leaves the premise and its history agreeing, a change to a different premise is unaffected, and a repeatable-read writer is refused by PostgreSQL itself before the recorder runs. The other round-2 items are closed as the plan says. The race test's five legs pass on my clone with the second session seen waiting, and each race-only mutation (N52–N54) fails first at its named leg for the reason the leg states. One should-fix, small: the exclusive-group refusal counts rows, not places, so the same county recorded twice over overlapping transactions is refused as "two places". Nothing blocks.

## Answers to the brief

1. **Each round-2 finding of mine, item by item.**
   - **B1** (two overlapping state corrections leave the history out of order): closed. `record_service_location_state()` refuses with 40001 when the premise already has a row stamped after the writer's `now()`. Executed on `rv30fable` with two sessions (P1a–P1d below) and by the frozen race test's R3/R4 (executed, both pass, B seen waiting). The plan's reason for keeping `now()` over my `clock_timestamp()` is right: a correction and the membership voids it needs (-16) must share one instant so a read sees both or neither; P2e below executes that (a void and the new county in one transaction: at `now()` the new county only, a second earlier neither is known).
   - **S1** (the coverage check runs as whoever holds the session at commit): closed. `check_place_levy_coverage()` requires superuser or BYPASSRLS and raises 42501 otherwise. Executed on the real path, not only C5's `SET CONSTRAINTS IMMEDIATE`: owner closes a city, `SET ROLE tally_app`, `COMMIT` → 42501 with -30's message, the place stays open (P3a, P3e); `SET ROLE tally_core` before the commit of a succession that would pass → also 42501 (P3c). The owner's close with a levy is still refused 23001 (P3b).
   - **S2** (the `seq` tie-break untested): closed. M8c (TX then NM in one transaction, read at `now()` answers NM) and mutation N51 (`seq` ascending) — predicted from the diff; M8c ran in my battery run (executed, 'all checks passed').
   - **S3** (the gaps report's second leg counts every premise ever): closed as a stated choice in the function's comment, which is what I asked for.
   - **N1** (the READ COMMITTED assert never speaks): unchanged; harmless.
2. **Does a round-3 change open a new path?** None found. The recorder's refusal fires only on an UPDATE that changes the normalised state, and only when a row stamped later exists; an INSERT has no earlier rows (the premise is invisible to any other transaction until commit). Under `tally_app` the EXISTS runs under the history's row-level policy, which has the same shape as `service_locations`' (both `is_platform_admin() OR tenant_id = get_user_tenant_id()`), so a writer that can update the premise can see its history rows; a writer that could not would also fail the history INSERT's WITH CHECK, never slipping a row through. The exclusive-group refusal is invoker-rights like the main read; at `now()` it can never fire against a live-consistent premise because -16's exclusion constraint (premise, group, axis, dates; within, unvoided) forbids exactly what it counts, and its place filters only narrow further; the two callers in `tu.sql` (the time-zone and regulatory lookups at `now()`) are unaffected. The re-read after locking cannot loop (one re-read, no retry inside), and with no rows of the code `v_locked` and `v_now` are both empty and the ordinary "none" refusal follows (P4, executed: 23514, not 40001). Retries: only the earlier-begun writer is refused, so two overlapping writers never both retry.
3. **Does anything break earlier writes to `service_locations` and `places`?** No path found. `service_locations`: the only new refusal is the 40001 on a state change by an earlier-begun transaction (P1a: an "import" transaction that never touched the premise is refused once another session changed it after the import began; its retry records in order). Inside one transaction nothing changes (stamps equal, never greater). `places`: the role requirement at commit only adds a refusal for a session that changed role between the close and its commit; the close itself already required superuser or BYPASSRLS (`enforce_place()`), so no legitimate migration is caught. `enforce_place()` is untouched.
4. **Tests narrower than their claim; a mutation caught for the wrong reason?**
   - The race legs prove what they say: every two-session leg checks `pg_stat_activity` for session B in a `Lock` wait before A commits (one sample per leg in a fresh connection, so no stale-snapshot issue). Executed: R1–R5 pass on my clone.
   - `RACE:<leg>` catches for the right reason (executed by hand-applying each mutation to a fresh clone and running the frozen race test): **N52** (no shared lock) fails first at R1 with "the second session was never seen waiting" — the close no longer waits; **N53** (re-read dropped) passes R1–R4 and fails at R5 with the levy accepted (no 40001); **N54** (the recorder's refusal off) passes R1–R2 and fails at R3 with B recorded and `history/premise: OK/NM` — exactly the B1 shape. `grep -m1 '^FAIL R'` takes the first leg, as the runner needs.
   - C5's check (`SET CONSTRAINTS IMMEDIATE` after `set_config('role', 'tally_app')` in a DO block) is the same code path as a COMMIT under the role; I executed the COMMIT path too (P3a, P3e) and it gives the same SQLSTATE and message. Not narrower.
   - M12 reads a second before `now()` with a planted `created_at` a day old and the first county voided at `now()`: the two memberships are both known and live at that instant, which is the ambiguity Opus described; M12b at `now()` answers the second only. M13 plants a future-stamped row as the superuser (the only writer the depth fence admits), so the refusal is exercised without a second session; R3 covers the real one.
   - Nothing caught for the wrong reason that I could find; N15–N17 now anchor on the main read's comment lines so the main read's filter alone is mutated (the exclusive check repeats them), which is the right anchoring.
5. **Do L1–L7 block?** No. L7's restatement is accurate for the levy table and the memberships, and its exclusion of the history is now true (B1's fix). L1–L6 unchanged from r2.

## Blocking

None.

## Should fix

### S1. The exclusive-group refusal counts rows, not places: the same county recorded twice is refused as "two places" — executed

`premise_places_as_of()`'s new check is `GROUP BY m.exclusivity_group HAVING count(*) > 1`. A utility that voids a county membership and re-records the same county with better evidence, in two overlapping transactions where the insert's transaction began before the void's (the insert waits on -16's exclusion until the void commits, then carries its own earlier `created_at`), leaves instants at which both rows are known and live. P2b (planted: the old row created two days ago and voided at `now()`, the new row of the **same** county created a day ago; read a second before `now()`): refused 21000 "within two places of one exclusive group". The premise is in one county; the answer is not ambiguous. It is the L7 window (seconds, in the past only), so it does not block; but the message is wrong for the case, and the main read would otherwise return the place twice. Fix: `HAVING count(DISTINCT m.place_id) > 1` in the check and `SELECT DISTINCT` (or a `DISTINCT ON (p.id)`) in the main read's first leg, or keep the refusal and say in the message that it is "two membership rows of one exclusive group". A battery check with the same-place plant either way.

## Notes

- **N1** The recorder refuses an earlier-begun transaction for *any* premise another session changed after it began, whether or not the earlier one had touched the premise (P1a). That is right (its stamp would sort below the other's) and the cost is one retry of, say, an import; worth a sentence in the function comment so the retry is expected.
- **N2** A re-spelling after another session's change (P1b: B commits `NM`, the earlier-begun A then sets `nm`) returns early, records nothing, and leaves the live row `nm` with the history ending `NM`: consistent, no refusal needed.
- **N3** A repeatable-read overlapping writer is refused by PostgreSQL ("could not serialize access due to concurrent update", 40001, `GetTupleForTrigger`) before the recorder runs (P1d); the same SQLSTATE, so the app's retry covers both.
- **N4** The read-committed re-read in the levy insert takes one new snapshot after the locks; because the function is VOLATILE each statement sees what committed while it waited, which is what R2 (a close) and R5 (a successor) rely on. `v_locked` and `v_now` are both ordered by `id`, so the array compare is exact.
- **N5** `levy-30.sh`'s `seen()` prints its own FAIL line and the leg's `else` prints a second one for the same leg (visible in the N52 run). Cosmetic: the runner's `grep -m1` takes the first, and both name the same leg.
- **N6** `known outside` rows for two counties on the tax axis are answered, not refused (P2a: relation `outside` is excluded from the check); two districts (NULL group) with a county and a city are all answered (P2c); the regulatory axis is unaffected by a tax-axis plant (P2f).
- **N7** My P3a as first written ran the close as `tally_app` because `SET ROLE` outlives a COMMIT in the same psql session; the "permission denied for table places" that produced was my probe's error, not the patch's. P3a was rerun as the owner (above).

## Probes (all on `rv30fable` or `rv30fablerace`, both dropped)

| # | What | Result |
|---|---|---|
| P1a | A begins, never touches premise L; B changes L to NM and commits; A changes L to OK | A refused 40001 "began after this one"; history NM over TX; A's retry records OK last — **B1 closed** |
| P1b | B commits NM; earlier-begun A sets `nm` | A commits, nothing recorded, live `nm`, history ends NM |
| P1c | B changes premise L2; earlier-begun A changes premise L | both recorded, no refusal |
| P1d | A in REPEATABLE READ overlaps B | A refused 40001 by PostgreSQL's own concurrent-update check |
| P2a | known-outside rows for two counties | answered (48901 outside, 48903 outside, TX within) |
| P2b | the same county voided and re-recorded with overlapping stamps, read a second ago | refused 21000 "two places" — **S1** |
| P2c | two districts + county + city | all five answered |
| P2e | void county A and record county B in one transaction | at `now()` B only; a second earlier nothing known (both stamped `now()`) |
| P2f | regulatory axis after the tax-axis plant | TX only |
| P3a/P3e | owner closes a city (with / without a levy), `SET ROLE tally_app`, `COMMIT` | 42501 "sees them all"; place stays open — **S1 (r2) closed** |
| P3b | owner's close with a levy | 23001 at COMMIT naming the levy |
| P3c | succession as owner, `SET ROLE tally_core`, `COMMIT` | 42501 "sees them all" |
| P4 | levy on a code with no rows | 23514 "its rows: none", not 40001 |
| Race | frozen `levy-30.sh` on `rv30fablerace` | R1–R5 PASS |
| N52/N53/N54 | each race-only mutation hand-applied to a fresh clone, frozen race test run | first FAIL at R1 / R5 / R3 respectively, each for the leg's stated reason |
| Battery | frozen r3 battery on `rv30fable` | "battery-30: all checks passed", rolled back |
