# v5.4.2-30 r5 — Fable's review (narrow)

**Date:** 2026-11-22. **Reviewer:** Fable (Claude Fable 5.2), independent; `opus-r5.md` and `codex-r5.md` not read; my own `fable-r4.md`, the r5 plan and `r4-to-r5.diff` read.
**Frozen files:** all seven md5s match the brief (executed).
**Scratch:** `rv30fable` and `rv30fablerace`, each cloned from `tally`, TEMP revoked from PUBLIC / tally_app / tally_core, the frozen r5 patch strict-applied (search_path empty, function bodies checked); on `rv30fable` twice, the second a no-op ending in "invariants hold" (executed). The race clone was recreated for each hand-applied mutation. Both dropped at the end (executed: no `rv30fable%` database remains). No role created or altered; `mutations-30.sh`, `preconditions-30.sh` and `ci.sh` not run; no repo file touched but this one. Every function I changed on `rv30fable` was restored from the frozen patch before the drop (function md5 equal to the base, executed).
**PATCH-LESSONS read:** the index; temporal-helper-no-live-fallback, history-stamped-at-xact-start, checks-narrower-than-their-claim, every-branch-and-stated-default-tested, check-names-its-own-guard, reviewer-fixes-need-measuring.

## Verdict: ready

The one change to what a read answers is right. The plain (three-argument) read now gives the earlier patch's answer on everything I could throw at it: 13,920 reads over randomly planted premises, places and memberships (stamps in the past, at now, a microsecond ahead, an hour ahead and at `infinity`; voids, closes, successor rows, other-state places, changed and unknown premise states), compared row for row and refusal for refusal with -16's original function installed beside it: no difference, and no 21000 refusal from the plain read. The same data read at `now()` (round 4's reading) differed from -16 in more than half the reads, so the comparison can see the fault it is looking for. My round-4 should-fix is closed by construction: the records that count are picked in one query, and each of its filters, removed, now fails a named check. The three race mutations I applied by hand each fail at the named leg with the named bracket. Nothing blocks, and I have no should-fix; notes only.

## Answers to the brief

**1. Is each round-4 finding of mine closed?**

- **S1 (four filters of the refusals' copy of "which records count" untested; the axis one, removed, refused every premise with a different county on each axis): closed — executed.** There is now one query (`v_live`); the refusals and the answer both read `m.id = ANY (v_live)`. On `rv30fable` I removed each of the four filters from that one query and ran the frozen battery: the axis → fails **M12h** (the read raised 21000, the very refusal I reported); the place's state, the place in force on the date, the place recorded by the instant → each fails **M14**. I also re-widened each reader separately to "all the premise's memberships" (the answer alone, then the refusals alone): both fail at M1. So neither half can drift back unnoticed.
- **N1 (a transaction begun between two overlapping writers was refused at its own `now()`, and so were the time-zone lookups inside it): closed for the plain form — executed.** Three real sessions as `tally_app`: a reader begun after the earlier-begun writer (which records a new county and the district again as outside) and before the later-begun one (which voids the old county and the district). First reads: El Paso County and the district within, zone `America/Denver`. After both commit, still in the same transaction: the plain read answers Travis County and the district outside; `premise_time_zone_as_of` answers `America/Chicago`; the four-argument form at `now()` refuses (21000, "more than one answer for one place"), as L7(b) now says it will; the four-argument form at `infinity` answers as the plain one. The four-argument comment now says "at now() a new transaction answers".
- **N2 (`[nowait]` covered both a commit and an unrelated refusal): closed — executed and read.** The bracket now carries what was proved: `damage`, a SQLSTATE, or the answer. The runner matches the whole bracket.
- **N3 (L7(a)'s list of ways two reads differ read as complete and was not): closed — read.** (a) now names the kinds of write (a row, a close, a void, a change of the premise's state) and the one condition (begun by the instant, committed or not when each read ran), which covers the case I said was missing.
- **N4 (two filters caught only by an unlabelled fixture error):** nothing was owed; no change needed.

**2. Does any round-5 change open a new path, or break what earlier rounds had right?** None found.

- *`infinity`, comparison by comparison (read, then executed by the random comparison above).* Membership recorded by then: `created_at <= infinity` is always true, including a stamp of `infinity` itself, so a row stamped ahead of the reader counts as -16 counted it. Not voided by then: `voided_at > infinity` is never true, so any void excludes the row, as -16's `voided_at IS NULL` did. End as known: `closed_at > infinity` is never true, so the end is the row's own end date, as -16 read it. Places likewise. The premise's state: the latest history row, which equals the premise's own state as long as the recorder's order holds (its 40001 refusal, R3; no other trigger on the premise table rewrites the state — checked in the catalogue). An unknown state (`ZZ`) refuses P0002 in both.
- *Can the plain read refuse committed, consistent data?* No path found. Its two 21000 refusals need two unvoided rows of one place on one date and axis, or two unvoided "within" rows of one exclusive group; -16's two exclusion constraints forbid exactly those among committed rows, and `places_no_overlap` gives a code one row in force on a date. An exclusion constraint cannot be passed while the conflicting row's writer is still open, so no snapshot holds both. Executed: 0 refusals of this kind in 13,920 plain reads, against 298 for the same reads at `now()`.
- *The callers.* The only functions in the database that call the read are the read's own two forms and `premise_time_zone_as_of` (catalogue search, executed). The time-zone lookup already read place facts as committed; it now reads places the same way, so its two halves agree again (in r4 they did not). `tax_levy_reference_gaps` never calls the read: it reads the tables directly, as committed, and its text is unchanged since r4 (the diff does not touch it). No change besides the intended one.
- *`v_live`.* The function is STABLE, so its three statements run on the caller's one snapshot; the ids picked are the ids read. Under RLS the second and third statements read memberships by id through the same policy as the first (executed as `tally_app`: own premise answered; with no user set the premise is refused P0002, nothing leaks). Nothing the old main read filtered is now unfiltered: the old filters were moved, not dropped (diff read; the six single-reader mutants above confirm it).
- *Cost.* 3000 reads over seven dates, one premise with a county and a district: 227 and 214 ms plain, 205 and 198 ms four-argument (about 0.07 ms a read; shared machine). No concern.

**3. The tests: a claim narrower than its check, or a mutation caught for the wrong reason?**

- Battery: 127 PASS, "all checks passed" (executed). Race selftest passes; R1–R8 PASS (executed, and R1–R8 again in each mutant run below with only the named leg failing).
- By hand through the frozen race test, each on a fresh clone (executed): **N73** (plain read at `now()`) → `FAIL R8 [read:R30-D,R30-D2]`, every other leg PASS. **N53** (the re-read guard off) → `FAIL R5 [waited:23514]`, the levy told its city is not in force over its dates: the relabel is accurate, it changes only how the writer is refused. **N53b** (both guards off) → `FAIL R5 [waited:damage]`, session B committed. The plan's correction of r4's "not testable" is right.
- Can a broken leg read as a catch? Not that I can construct (read). A session that fails for its own reasons, a commit with no damage read back, an error with no SQLSTATE and an unrelated read error all print BROKEN; the selftest holds each of those on literal outputs. R8 prints BROKEN unless the bill's own transaction start is proved to lie between the two writers' stamps, so a slow machine cannot turn it into a PASS or a FAIL.
- Two narrownesses, neither blocking: N1 and N2 below.

**4. Do L1–L7 block?** No. L7 as restated does not overclaim: it says a read at an instant is settled only once every transaction begun by then has finished, that two reads at one instant can differ silently, that a read can refuse or answer a row beside its replacement, that a read at `now()` is such a read, and that the plain form is outside both. The last is what I measured. One thing it leaves unsaid is in N3.

## Blocking

None.

## Should fix

None.

## Notes

- **N1 The plain form's four "as known" comparisons are held by one check of one of them.** M15 and R8 both test a *void* stamped after the reader began. A membership *recorded* by a later-begun writer, a close stamped later, and a state change stamped later are not tested for the plain form. Today that is enough, because the instant is one argument and N72 turns all four at once (and the random comparison above shows all four right). It would stop being enough only if the plain form stopped being a one-line call of the other. Nothing owed.
- **N2 For R5 (and R2), "damage read back" is the same fact as "session B committed".** The damage query asks whether an open levy on the city exists, which B's clean exit already says. For R1 and R3 the damage is a separate fact (an open levy on a closed city; a history that ends on a state the premise is not in). Honest as labelled — the bracket never claims more — but the R5 bracket proves the commit, not that the levy rests on a row it never locked. That cannot be read from the data, since the successor row does cover the levy. Nothing owed.
- **N3 What the plain form does not promise.** "As committed when the statement runs" is right under READ COMMITTED; in a REPEATABLE READ transaction it is as committed when that transaction's snapshot was taken. And a correction made in two transactions (void in one, record again in another) is read half-done between their commits: the premise has no district for that moment. Both are -16's behaviour, not r5's, and neither is an L7 matter; one clause in the plain form's comment would save a later reader the question.
- **N4 Wording.** A missing or invisible premise read through the plain form (and so through the time-zone lookup) is now refused with "was not yet recorded at infinity" (executed). The SQLSTATE is -16's (P0002); only the message changed. And M4's label still says the three-argument form "reads as known now"; since r5 it reads what is committed. Neither changes a result.
- **N5 Environment, not the patch.** Two `crystaldba/postgres-mcp` containers were running in Docker for the whole of this review. I left them alone; they are the leak the session-start check is for.

## Probes (all on `rv30fable` or `rv30fablerace`, both dropped)

| # | What | Result |
|---|---|---|
| Apply | frozen r5, strict, twice | clean; second a no-op |
| Battery | frozen r5 battery | 127 PASS, "all checks passed" |
| Race | frozen `levy-30-frozen-r5.sh`: selftest, then the run | selftest "all pass"; R1–R8 PASS |
| Equivalence | -16's original read installed as a second function in a rolled-back transaction; 80 premises (TX, NM, changed once or twice, a few set to an unknown state), about 135 planted place rows and 4,500 planted memberships per run with random stamps (3 days ago, 400 days ago, 1 s ago, now, +1 µs, +1 h, `infinity`), voids and closes, the exclusion constraints left on; every premise × 29 dates × 2 axes; three seeds | 13,920 reads: plain form differs from -16 in **0**; plain form 21000 refusals **0**; P0002 348, identical in both. The same reads at `now()`: differ in 7,433, refuse 21000 in 298 |
| Callers | catalogue search for functions whose body names the read | the two forms and `premise_time_zone_as_of` only |
| State triggers | triggers on the premise table that could change the state unrecorded | none |
| C1–C4 | each of the four r4-untested filters removed from the single picking query, battery run | axis → M12h (21000); place's state, in force, recorded-by → M14 |
| C5, C6 | the answer alone, then the refusals alone, made to read all the premise's memberships | both fail at M1 |
| C7 | `voided_at >` made `>=` in the picking query | fails at M1 |
| Restore | frozen patch re-applied to `rv30fable` | function md5 equal to the base |
| N73 / N53 / N53b | hand-applied to a fresh race clone, frozen race test | `FAIL R8 [read:R30-D,R30-D2]` / `FAIL R5 [waited:23514]` / `FAIL R5 [waited:damage]`; all other legs PASS each time |
| 3-session | reader (as `tally_app`) begun between an earlier-begun re-record (new county; district outside) and a later-begun void (old county; district within) | first: old county, district within, `America/Denver`; later, same transaction: plain read new county and district outside, zone `America/Chicago`; four-argument at `now()` refused 21000; four-argument at `infinity` as the plain read — **r4 N1 closed** |
| RLS | plain read as `tally_app` with no user set | refused P0002 |
| Time | 3000 reads over seven dates, each form, twice | plain 227 and 214 ms; four-argument 205 and 198 ms |
