# v5.4.2-30 r3 — Opus review

**Date:** 2026-11-06. **Reviewer:** Opus. **Verdict: ready** (no blocking item; two should-fix items, both wording or tests, no change to what the schema refuses).

All seven frozen md5s match the brief, and the live patch is byte-identical to the frozen r3 copy (**executed**).

Strict apply on a fresh clone of `tally` (`rv30opus`, TEMP revoked from PUBLIC, `tally_app` and `tally_core`): clean, twice (**executed**). The battery: 112 PASS, then "all checks passed" (**executed**). The frozen race test on a second clone (`rv30opusrace`): R1–R5 all PASS (**executed**). I did not run `mutations-30.sh`, `preconditions-30.sh` or `ci.sh`, which the brief restricts. I did run three mutations by hand on my own clones (below). Both clones are dropped.

PATCH-LESSONS sections read: temporal-helper-no-live-fallback, date-from-snapshot-knowledge-from-now, count-guards-need-lock-handshake, lock-order-as-a-rule, race-barriers-clear-stat-snapshot, checks-narrower-than-their-claim, every-branch-and-stated-default-tested.

---

## 1. My round-2 findings, item by item

- **B1 (two overlapping state corrections left the history on the losing state): closed** (**executed**, two sessions). R3 is my round-2 repro, and it passes. I also ran three orders the race test does not cover, on `rv30opusrace`:
  - **No lock wait.** B begins. A begins later, changes the state and commits. Only then does B update, so B never waits on a lock. B is refused with 40001 ("began after this one"). The check is keyed on the stamp, not on having waited, so this order is covered too.
  - **A re-spelling.** B begins, A changes the state to TX and commits, and B then writes `tx`. B commits and records nothing. That is right: the normalised state did not change.
  - **Insert, then update.** B begins. A inserts a new premise (TX) and commits. B then changes that premise to NM, and B is refused with 40001. Without the refusal, B's row would sort below the insert's row and the history would end on TX. A retry is recorded, last.
  - Two changes inside one transaction share one stamp, and the `seq` tie-break orders them (M8c; mutation N51).
  - Every writer of the state is an UPDATE of `service_locations`. No function in `tu.sql` updates it (**executed**, grep). A direct insert into the history is fenced, so no writer escapes the premise's row lock.
  - The recorder is VOLATILE (plpgsql's default), so its EXISTS check takes a fresh snapshot and sees the row the other writer committed while this one waited. Marked STABLE, it would use the statement's snapshot and miss that row. R3 would catch that (**predicted**).
- **S1 (a past read gave two cities of one exclusive group): closed** (**executed**). My round-2 two-session repro now refuses with 21000 ("within two places of one exclusive group"). The read at `now()` answers the successor city alone.
- **S2 (the levy and close lock handshake had no test): closed.** R1 and R2 are the two races I ran. I applied N52 by hand (the shared lock replaced by `NULL;`) on a fresh race clone and ran the frozen race test (**executed**):
  - R1 fails at "never seen waiting", which is the right reason.
  - The damage is real as well: the clone ends with a levy on R30-A while R30-A is closed at 2026-06-01, so the levy outlived its place.
  - R5 also fails. The runner records only the first failing leg, R1, which is the leg the mutation names.
- **N1 (a successor row was not locked by a levy insert that was already waiting): closed by S3's re-read.** R5 is that path. A residual remains, much narrower (N1 below).
- **N2–N7:** N2 is now in the gaps report's comment. N5 is M8c. N7 (L7) is restated, but it still overclaims; see S1 below.

---

## Blocking

None.

---

## Should fix

### S1. L7 and the header promise more than the stamps give. A rebill at a bill's own instant can silently answer different places from the bill, when a writer was in flight at that instant

L7 now ends "A read refuses, never mis-answers". The four-argument read's comment says "A rebill reads the jurisdictions the original bill saw". Both hold only for writers that had already finished when the bill's transaction began. Every stamp is the writing transaction's start (`now()`), not its commit. So "as known at t" really means "begun by t". Two repros, each with one ordinary writer and one bill (**executed**, `rv30opusrace`, as `tally_app`):

1. **A writer that straddles the bill.** W begins at 36.731 and inserts a district membership, but commits only at about 38.7. A bill computed live at 38.451 does not see the district, because W has not committed. The rebill at 38.451, run later, does see it (`created_at` 36.731 ≤ 38.451). Result: live `{A, C, D1, D2, E, TX}`, rebill `{A, C, D1, D2, D4, E, TX}`. Nothing raises.
2. **A void stamped before the row it voids.** V begins at 57.850. C inserts a district membership at 58.392 and commits. V then voids that row by key, and the void is stamped 57.850, which is earlier than the row's own creation. A bill computed live at 59.019, before V commits, saw the district. The rebill at 59.019 does not see it, because the void is "known" from 57.850. A close (`closed_at`) behaves the same way, and so do levies and places, all through the template's close.

Neither case is new in -30. AC-15 and AC-18 already have a new bill pass the writing transaction's `now()` and a replay pass the original run's instant, so every as-of lookup since v5.4.1 has this property. The window is the time a writer stays open. What is new in -30 is the explicit claim that these reads never mis-answer.

The answer is permanent for that instant. The refusals L7 does describe (two levy rows, two places of one group) are also permanent for any bill whose instant falls in the window, not only "for those seconds" while it is open. Such a bill can never be rebilled at its own instant.

**Fix (wording and the board; no schema change in -30):**
- Restate L7: as-known reads are stable for an instant only once every transaction that began by that instant has finished. Before that, a replay can differ from the live read: it can add a row whose writer straddled the instant, or drop a row whose close or void began before the row did. A bill whose instant falls in such a window may also be refused permanently at that instant.
- Narrow the comment on the four-argument read in the same way.
- Extend the board's template-stamps item. This is a silent mis-answer, not only a refusal, and `clock_timestamp()` alone does not close the straddle case: the statement time is still before the commit.
- The permanent remedy is the core's. Either compute a bill at an instant that every writer begun by then has finished, or record on the bill which levies and places it used (L5's bill line, money stream), and treat that record, not a replay, as what the bill saw.

I said in round 2 that L7 would hold as stated with my fixes. That was wrong: I had looked only at two writers on one key, not at a writer and a reader.

### S2. Two filters of the new exclusive-group check are untested, and dropping either one refuses legitimate premises

The check repeats the main read's filters and adds `m.relation = 'within' AND m.exclusivity_group IS NOT NULL`. No battery fixture gives one premise two `outside` rows of one group, or two stacking districts. I applied each mutation by hand on `rv30opus` and `rv30opusrace` (**executed**):
- **`relation = 'within'` dropped:** the battery still passes 112 of 112. The probe premise, which is within R30-C and outside R30-A and R30-E, now gets 21000 at `now()`.
- **`exclusivity_group IS NOT NULL` dropped:** the battery still passes 112 of 112. The same premise, within districts D1, D2 and D4 (group NULL), gets 21000.

With the frozen patch, the same read answers `R30-A/outside, R30-C/within, R30-D1/within, R30-D2/within, R30-D4/within, R30-E/outside, TX/within` (**executed**). So the check is correct as written, and the brief's question ("does it refuse a `known_outside` row or a group of NULL?") is answered no.

Fix: add one fixture, M12c. Give a premise two stacking districts, plus an `outside` row in the group of its `within` city, and read it at `now()`: answered, not refused. Add the two mutations, each caught at M12c.

The other filters stay in step. M12b catches a dropped void leg (**predicted**), and every other filter is the main read's, character for character, apart from the `place_kinds` join. That join is total, because of the foreign key.

---

## Notes

**N1. A residual of the re-read: the coverage is measured in a third snapshot** (**predicted**, not reproduced: the window is the microseconds between two statements).
- The re-read compares the code's rows to the locked set. The coverage `range_agg` that follows reads the code's rows again.
- A successor committed between those two statements is counted in the coverage but holds none of this insert's locks. A dissolution of it could then pass beside the levy. It needs a succession and then, at once, a dissolution of the new row.
- Fix in one clause, the next time this function is opened: `AND p.id = ANY (v_locked)` on the coverage read. The locked rows cannot be closed under the shared lock, and the fresh snapshot still sees a close that committed before the lock was taken (R2).

**N2. The re-read cannot loop, and it does not refuse an ordinary insert** (**executed**, battery L and Q; **read**).
- Both arrays are sorted by id.
- No rows gives `{}` against `{}`, and then the coverage message.
- A transaction's own new successor row is locked by its own loop, since a shared advisory lock does not conflict with the same session's exclusive one.
- A 40001 is returned to the caller once per concurrent change of that code's rows.

**N3. The recorder refuses for as long as the server clock is stepped back** (**predicted**). The check is `recorded_at > now()`. After an NTP step backwards, every change to a premise last changed within the step is refused until the clock passes that row's stamp. That is a refusal, not a mis-record, so it is acceptable. It deserves a line in the 40001 contract.

**N4. The backfill stamps a premise's `created_at`, which is settable** (**predicted**). A premise imported with a future `created_at` would be "not yet recorded" until that time. Every change to its state would also be refused 40001 until then. Nothing is live, and C6 plants a past `created_at`. `least(l.created_at, now())` in the backfill would remove the case at no cost.

**N5. The coverage check's role requirement breaks no earlier writer** (**read**). Every UPDATE of `places` is a close, and `enforce_place` already requires superuser or BYPASSRLS for it. The new check only stops a role from being switched between the close and the commit, which is what C5 does.

**N6. The race test** (**executed** and **read**).
- Each two-session leg samples the named session waiting on a `Lock` event before the first session commits:
  - R1 waits on the advisory lock, and so does R2.
  - R3 waits on the premise's row lock, and R5 on the advisory lock of the row it found.
- R3 checks the SQLSTATE, the message and that the history and the premise agree (`OK/OK`).
- `RACE:<leg>` takes the first failing leg, which matches each mutation's own leg (N52 is R1 above, executed; N53 is R5 and N54 is R3, both predicted from the timelines).
- Cosmetic: a leg that fails `seen` prints FAIL twice (see N52 above). The sampling is fixed at one second after B starts. Under load that can flake to a false FAIL, never to a false PASS. PATCH-LESSONS' `pg_stat_clear_snapshot()` point does not apply, because each sample is its own psql session.

**N7. L1–L6 do not block. L7 is S1.**

Probe scripts (scratch, not repo files): `p1.sh` (recorder orders), `p2.sh` (two places of one group, and districts with `outside` rows), `p3.sh` (a void stamped before its row), `p4.sh` (a writer straddling a bill), in `/private/tmp/claude-501/-Users-ryanscomputer-code-tally-utility-rates/52858181-4398-43e0-9d0e-3c7e0e855989/scratchpad/`.
