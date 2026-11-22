# v5.4.2-30 r4 — Fable's review

**Date:** 2026-11-22. **Reviewer:** Fable (Claude Fable 5.2), independent; `opus-r4.md` and `codex-r4.md` not read; my own `fable-r3.md`, the r4 plan and `r3-to-r4.diff` read.
**Frozen files:** all seven md5s match the brief (executed).
**Scratch:** `rv30fable` and `rv30fablerace`, each cloned from `tally`, TEMP revoked from PUBLIC / tally_app / tally_core, the frozen r4 patch strict-applied (search_path empty, function bodies checked); on `rv30fable` twice, the second a no-op ending in "invariants hold" (executed). The race clone was recreated for each hand-applied mutation. Both dropped at the end (executed: no `rv30fable%` database remains). No role created or altered; `mutations-30.sh`, `preconditions-30.sh` and `ci.sh` not run; no repo file touched but this one.
**PATCH-LESSONS read:** the index; template-clone-drops-acl, temporal-helper-no-live-fallback, history-stamped-at-xact-start, count-guards-need-lock-handshake, race-barriers-clear-stat-snapshot, checks-narrower-than-their-claim, every-branch-and-stated-default-tested, check-names-its-own-guard, reviewer-fixes-need-measuring.

## Verdict: ready

My round-3 should-fix is closed: the same county recorded twice is now answered once, and the cases that really are ambiguous (one place both within and outside, at two distances, or through two of its rows; two places of one exclusive group) refuse. I could not make the read answer a place twice, answer contradictory records, or refuse a premise whose records are consistent and settled. The race test's new verdicts say what happened, and the three mutations I applied by hand through it each fail at the named leg for the stated reason. One should-fix, about tests only: four of the filters in the check's copy of "which records count" can be removed with the whole battery still passing, and one of those removals refuses every premise that has a different county on its two axes. Nothing blocks.

## Answers to the brief

**1. Is each round-3 finding of mine closed?**

- **S1 (the same county recorded twice refused as "two places"): closed — executed.** Probe PA: a county membership voided now and the same county recorded again by a (planted) transaction a day old, read a second ago: `48881/within TX/within`, once. The exclusive-group check counts places (kind and code), and the main read is `DISTINCT`. Battery M12d holds the same shape for a county and a district; mutations N57, N58 and N62 take away each of the three parts.
- **N1 (say in the recorder's comment that a long import is refused once): closed — read.** The comment now says it is refused whether or not it had touched the premise.
- **N5 (the race test printed two FAIL lines for one leg): closed — executed.** One line per leg in every run below.
- N2, N3, N4, N6, N7 were observations; nothing to close.

**2. Does a round-4 change open a new path or break what was right?** None found.

- *Agreeing repeats answer once.* Everything the caller reads is in what makes an answer: the read returns the place's id, kind, state, code, name and specificity (all fixed by the place row's id) and the relation and distance; the check compares id, relation and distance. Two records that agree in those three give identical output rows, so `DISTINCT` drops nothing a caller could see. Distances compare as numbers, not as text (PE: 2.5, 2.50 and 2.500 recorded three times, two voided now: one row, executed; the column is `numeric(8,3)` anyway). A missing distance against a stated one is a disagreement and refuses (PC, executed): `count(DISTINCT (id, rel, miles))` counts a row holding a NULL and treats two NULLs as alike, which is the behaviour wanted.
- *Can the check refuse a live-consistent premise at `now()`?* Not once the writers have finished: with every stamp in the past, the check's set is exactly what -16's two exclusion constraints already forbid (one unvoided row per place and axis on a date; one within place per exclusive group), and a place has one row in force on a date. Executed for the legitimate shapes: a county on the regulatory axis and another on the tax axis (PB: each axis answers its own), a known-outside city beside a limited-purpose area of the same group and two stacking districts (M12c). It **can** refuse at `now()` inside a transaction that began between two overlapping writers (three real sessions, executed: the reader's first read answers `within`; after the later-begun writer voided and the earlier-begun one recorded `outside`, its second read at its own `now()` is refused 21000; a new transaction answers `outside`). That is L7(b) seen from an open transaction; r3 would have answered both. It reaches the time-zone and regulatory lookups too, since they read at `now()`. Right behaviour; see N1.
- *Kind and code as the place's identity.* Nothing legitimate refused that I could find. Two rows of one place both in force on one date as known at an instant needs the successor recorded before the predecessor's close was (M12g): the two rows differ in id and name, which the caller reads, so refusing is consistent with the rule. A state takes no membership (PF: 23514 from -16), so the state row added at the end cannot repeat.
- *The two checks and the main read.* Today the filters are word for word the same (read), and the function is STABLE, so both statements run on the caller's one snapshot and cannot see different rows. Whether they *stay* in step is the should-fix below.
- *The levy's coverage read* (`p.id = ANY (v_locked)`): correct; after the re-read `v_locked` is every row of the code, each held shared, so the third read can only lose a row committed since, which is the intent.
- *The backfill* (`least(created_at, now())`): executed on a fresh clone with a premise dated 2999 planted before the patch: its history row is in the past, and a later state change is recorded after it (`TX,NM`) instead of being refused for ever.
- *Cost:* 2000 reads of a premise with two agreeing records in 231 ms on a shared machine (about 0.12 ms each). No concern.

**3. Tests: a claim narrower than its check, or a mutation caught for the wrong reason?**

- The new battery checks prove what they say (120 PASS on my clone, executed), and each new battery mutation's stated reason matches the check it names (read: N55–N62; N55 and N56 fail M12c because the outside city or the two districts are counted; N61 leaves M12d and M12e intact and lets M12g's two rows through).
- Through the race test, by hand on fresh clones (executed): **N52** → `FAIL R1 [nowait]`, session B's close exit 0, and afterwards one open levy on the city with the city closed at 2026-06-01: the damage the label claims, not a side effect. (R2 then prints BROKEN and R5 FAIL; the runner takes the first line.) **N64** → `FAIL R7 [read]: outside,within`. **N65** → `FAIL R6 [read]: within,within`. N62's mutation, which the runner checks only in the battery, also fails R6 with the 21000 refusal, so the agreeing case is held by two real sessions as well.
- A broken or in-order leg cannot be read as a catch: BROKEN and SEQUENTIAL lines never match the runner's `RACE:<leg>:<how>` (read, and seen in the N52 run's R2). One narrowness in `[nowait]`, see N2.
- **Narrower than its claim:** the check's own filters, S1.

**4. Do L1–L7 block?** No. L7 as restated no longer overclaims: it says a replay can differ silently, that the instant stays that way for good, and that the remedy is the bill's own record. One wording gap, N3.

## Blocking

None.

## Should fix

### S1. Four filters of the check's copy of "which records count" are untested; one, removed, refuses every premise with different counties on its two axes — executed

The function decides which membership records count twice: once in the set the two refusals read, once in the main read. The existing mutations N15–N17 are anchored on the main read on purpose. I removed each filter from the check's copy alone, re-created the function on `rv30fable`, and ran the frozen battery:

| Removed from the check's set only | Battery |
|---|---|
| the axis (`m.axis = p_axis`) | **all 120 pass** |
| the premise's state (`p.state_code = v_state`) | **all 120 pass** |
| the place in force on the date | **all 120 pass** |
| the place recorded by the instant (`p.created_at <=`) | **all 120 pass** |
| not voided by the instant | fails M12b |
| the membership recorded by the instant | fails (unlabelled, an early fixture read) |
| the membership in force on the date | fails (unlabelled) |
| membership end / place end "as known" (`end_as_known`) | fails M12g |

With the axis filter gone, a premise in one county on the regulatory axis and another on the tax axis (which -16 allows, and the time-zone lookup's comment expects) is refused on both axes at `now()` as "within two places of one exclusive group" (PB under the mutant, executed; answered correctly under the frozen function). So a later edit that lets the two copies drift would refuse legitimate premises on every read, and no test would say so.

Fix, either: (a) four battery checks and mutations — a premise with different counties on the two axes; a membership of a place of another state; of a place not yet in force on the date; of a place recorded after the instant — each answered, not refused; or (b) read the records once and make both the refusals and the answer from that one set, so there is nothing to keep in step. (b) is the lasting one but changes the function's shape, so measure it before folding it in; (a) is enough for this round.

## Notes

- **N1** A transaction that began between two overlapping writers can be refused at its own `now()` (three sessions, executed, above), and so can the time-zone and regulatory lookups called inside it. A retry in a new transaction answers. Worth one clause in the three-argument form's comment ("a caller in a long transaction retries on 21000"), since that form is described only as "as known now".
- **N2** `FAIL <leg> [nowait]` means "wrong result, no wait seen". It covers session B committing unhindered (N52, the damage) and also session B being refused at once with a different error (predicted from `verdict()`: exit 3 with an ERROR and no wait takes the same branch). The line prints what B said, but the runner matches only `R1:nowait`. Harmless for N52 as run; if it matters, print `[nowait, accepted]` when B's exit is 0.
- **N3** L7(a) lists two ways a replay differs ("adds a row whose writer was still open at the instant, or drops one whose close or void began before the row was recorded"). The commoner drop is the mirror of the first: a row whose close or void was begun by the instant but not yet committed. The sentence before it ("stable only once every transaction that began by then has finished") already covers it; the list reads as complete and is not.
- **N4** The battery failures for two of the removed filters above are unlabelled errors from an earlier fixture read rather than a named check. They are caught, so nothing is owed; if S1(a) is taken, the new checks would name them.

## Probes (all on `rv30fable` or `rv30fablerace`, both dropped)

| # | What | Result |
|---|---|---|
| Apply | frozen r4, strict, twice | clean; second a no-op |
| Battery | frozen r4 battery | 120 PASS, "all checks passed" |
| Race | frozen `levy-30-frozen-r4.sh` | R1–R7 PASS |
| PA | the same county voided now and recorded again a day ago; read 1 s ago, and now | once, both times — **r3 S1 closed** |
| PB | county X regulatory, county Y tax | each axis answers its own county |
| PC | outside a city with no distance (voided now), outside at 4 miles a day ago; 1 s ago | refused 21000 "more than one answer"; now: 4.000 only |
| PD | county X voided now, county Y a day ago; 1 s ago | refused 21000 "two places of one exclusive group"; now: Y only |
| PE | one district outside at 2.5, 2.50, 2.500 (two voided now); 1 s ago | one row |
| PF | a membership of the state itself | refused by -16 (23514) |
| Time | 2000 reads, two agreeing records | 231 ms |
| 3-session | reader begun between an earlier-begun re-record (outside) and a later-begun void, reading at `now()` | first read `within`; second refused 21000; new transaction `outside` |
| C1–C9 | each filter removed from the check's set alone, battery run | four pass all 120 (S1); five fail |
| PB + mutant | the axis filter removed from the check's set | both axes refused 21000; restored function answers (function md5 equal to the race clone's afterwards) |
| N52 / N64 / N65 | hand-applied to a fresh race clone, frozen race test | `FAIL R1 [nowait]` with the levy and the closed city both committed / `FAIL R7 [read]: outside,within` / `FAIL R6 [read]: within,within` |
| N62 via race | agreeing repeats refused | `FAIL R6 [read]`: 21000 |
| Backfill | a premise dated 2999 planted before the patch | history row in the past; a later change records after it |
