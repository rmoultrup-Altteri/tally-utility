# v5.4.2-30 r5 — Opus review

**Date:** 2026-11-22. **Reviewer:** Opus. **Verdict: ready**, with no blocking item. S1 (the words of known limit L7) should be fixed before the mirror; it changes no code.

All seven frozen md5s match the brief, and the live copies are byte-identical to the frozen ones (**executed**, first; the patch again at the end).

- Two fresh clones of `tally` (`rv30opus`, `rv30opusrace`), TEMP revoked from PUBLIC, `tally_app` and `tally_core`. Frozen r5 strict-applied twice on each: no error (**executed**).
- Battery -30: 127 PASS, "all checks passed". Battery -16 passes too. Race selftest passes. Frozen race test: R1–R8 PASS, exit 0 (all **executed**).
- Not run, as the brief restricts: `mutations-30.sh`, `preconditions-30.sh`, `ci.sh`. `fable-r5.md` and `codex-r5.md` not read.
- Both clones are dropped.

---

## 1. My round-4 findings

- **S1(i), the plain read answering a voided row: closed in the code** (**executed**: R8 and M15 pass; with `now()` put back, R8 prints `[read:R30-D,R30-D2]`; section 4's comparison).
- **S1(ii), the refusal at `now()`: closed for the plain read**, including the writer reading its own premise after recording (**executed**, section 4).
- **S1(iii), L7's words: partly closed.** (a) is now right. My own round-4 remedy wording was ambiguous, the patch carries it, and one new clause is false: S1 below.
- **S2 (N53's damage): closed.** N53 gives `R5 [waited:23514]`, with no levy on R30-C. N53b gives `R5 [waited:damage]`, with a levy on it. The own-rows clause alone removed still passes R1–R8, which fits: either guard alone stops the levy (**executed**).
- **S3 (a broken leg read as a catch): closed.** My round-4 experiment repeated on frozen r5 (an unrelated 42501 in R1's B; the read function renamed away): `FAIL R1 [nowait:42501]`, which no mutation names, then `BROKEN` at R6, R7 and R8 (**executed**).
- **S4 (the kind half of a place's identity): closed.** Grouping by code alone fails M12i; counting by code alone fails M12j (**executed**).
- **N1, N2: closed** in the function's comment (**read**).

## 2. Blocking

None.

## 3. Should fix

### S1. L7 says the answer at an instant is "settled" once its writers finish, and offers that as a remedy. The settled answer can be a set of places that was never true

Executed on `rv30opusrace` (three sessions; a premise in district D1 by mistake, should be D2; districts stack, so nothing refuses). A begins; the bill's instant; B begins, voids D1, commits; A records D2, commits.

| four-argument read at the instant | answer |
|---|---|
| made at the instant itself | `OP-D1, TX` |
| after B committed, A still open | `OP-D1, TX` |
| **after every transaction begun by the instant has finished** (0 open, checked) | **`OP-D1, OP-D2, TX`** |
| the plain read, then | `OP-D2, TX` |

So, in L7 as restated:
1. **"or it is computed at an instant every writer begun by then has finished" is not a cure as most will read it.** A core that takes an instant, waits for its writers and then reads follows this sentence and bills both districts. In this case an immediate read was better than the waited one. The cure is an instant at which no writer is *open*: every transaction begun by the instant had already committed or aborted at the instant. I wrote this remedy in round 4 ("Only the second remedy covers this"); in the waiting reading it was wrong.
2. **"So a read at an instant is settled only once every transaction that began by then has finished: (a)… (b)…"** introduces (b) as something that ends. (a) ends. (b) begins when the last writer finishes and never ends. r4 said "and for that instant for good"; r5 dropped it.
3. **"the instant never had one answer" is false.** It had one, D1, and a read made then gave it (first row).

The same point needs a clause in the four-argument form's comment: it says only "settled". The refusals it names do not cover two stacking districts.

Why it does not block: the code is unchanged from r4 here, the window needs two overlapping corrections of one premise, and the first remedy (the bill records what it used) still holds. But it tells the core, in the schema's own words, to do the thing that double-taxes.

**Fix (words only):**
- (a) keep.
- (b) end with: "…, where a successor's writer began before its predecessor's close or void. This outlasts the writers: once they finish, every later read at that instant refuses or answers both, though a read made at the instant answered one."
- Remedy: "or it is computed at an instant when no transaction begun earlier was still open (waiting for them afterwards does not help)".
- Comment of the four-argument form: after "settled … finished", add "settled is not the same as right: a row and its replacement can both be known then".
- If the board's stamps item or the DECISION-LOG repeats the remedy, fix it there too (not checked).

## 4. The brief's questions

**`infinity` against -16's read: no difference found.** Every comparison collapses to -16's condition (**read**):
- `created_at <= infinity` is always true.
- `voided_at > infinity` is never true, which leaves `voided_at IS NULL`.
- `end_as_known` gives the end date itself.
- The history's last row is the premise's state, because the recorder refuses any order that would end elsewhere. `seq` has cache 1.
- Neither exclusion constraint is deferrable, so the two refusals cannot fire on committed data.
- Grants and RLS policies on the history match those on `service_locations` for `tally_app` and `tally_core`.

I also compared them (**executed**). -16's function was installed beside r5's in a second schema, then 12 clients ran for 90 s:
- 8/12 of the transactions were `tally_app` writers: random membership inserts, closes, voids and state flips TX/NM with odd spelling, in one transaction after a random pause.
- 2/12 were owner place successions, and 2/12 readers begun 0.1 s before.
- After each operation, inside the same transaction, both functions were read for 3 premises, 4 dates and 2 axes in one statement, errors compared by SQLSTATE.

| | |
|---|---|
| reads compared | 132,912 |
| plain r5 differs from -16 | **0** |
| the read at `now()` (r4's plain form) differs from -16 | 1,684 |
| writes that took effect | 603 inserts, 626 closes, 1,125 voids, 478 state changes, 657 successions |

The third line shows the probe could see a difference. It covers `infinity` and `v_live` (same rows in checks and answer, under RLS, with committed writes landing around the statement).

**The callers.** The only function in the catalogue that calls the plain read is `premise_time_zone_as_of` (three calls). There is no separate regulatory lookup: the second call site is inside it, on the regulatory axis (catalogue search **executed**). It gets -16's answers back (**predicted**: its body is unchanged and the read is equivalent). `tax_levy_reference_gaps` does not call the read and is unchanged in r5.

**`v_live`.** The rows are picked under one snapshot (STABLE), and the two later statements re-read them by id under the same RLS. The old main read's filters are all in the pick; `place_kinds` is joined through a foreign key. Single-filter mutations of the pick, against batteries -30 and -16 (**executed**):

| removed or weakened | first failure |
|---|---|
| premise; void; membership range | M1 |
| membership recorded by; void "as known"; membership end "as known" | M2 |
| place end "as known" | M11 |
| axis | M12h |
| place recorded by; place range; place's state | M14, each |
| `v_live` ignored in the checks, or in the answer | M1 |
| the state's history "as known" | M3 |
| plain read at `now()`, or at `clock_timestamp()` | M15 |

Every filter of the pick now has a check. `array_agg` without `coalesce` passes, and is equivalent (`= ANY (NULL)` selects nothing). Two filters of the state's *own* place row are still uncaught: N1.

**The race verdicts.** Seven RACE mutations applied by hand to fresh clones (**executed**), the levies and places then read from the tables (N54: the test's own read-back, and R4):

| | first non-PASS line | damage seen |
|---|---|---|
| N52 | `R1 [nowait:damage]` | R30-A ends 2026-06-01 under an open levy |
| N53 | `R5 [waited:23514]` | none (refused) |
| N53b | `R5 [waited:damage]` | a levy on R30-C, its successor row never locked |
| N54 | `R3 [waited:damage]` | the history's end differs from the premise's state |
| N64 | `R7 [read:outside,within]` | the answer itself |
| N65 | `R6 [read:within,within]` | the answer itself |
| N73 | `R8 [read:R30-D,R30-D2]` | the answer itself |

Each names its own damage. I found no broken leg that prints a named bracket. Sixteen edits to the verdict code, each run through the selftest (**executed**): eleven caught; the other five are N3.

**L1–L7.** L1–L6 do not block. L7 is S1. It does not block.

## 5. Notes

**N1. Two filters of the state's own place row are untested** (**executed**): `p.created_at <= p_recorded_at` removed, and its `end_as_known` replaced by the raw end, both pass batteries -30 and -16. Neither is new in r5. The comment now claims "places likewise", and says the state row is "taken as found". A state row loaded after the instant is an ordinary event while states are being loaded. One check (a state place recorded after the instant: P0002) would hold the first.

**N2. (a) says "silently", and (b) lists only 21000.** A write open at the instant can also turn an answer into a P0002 refusal, or back. Round 4's case was a premise's state changed to one whose place was recorded later; a premise inserted by an open writer is another. Half a clause: "or one of them can refuse (P0002)".

**N3. What the selftest does not hold** (**executed** as edits that still pass):
- The run's exit status: dropping `fail=1` from the SEQUENTIAL, FAIL or read-FAIL branch passes, because the verdicts are evaluated in a subshell. With such a slip `ci.sh` would pass a failing leg. The code is right today.
- Reading exit 2 as a result passes, and is equivalent: psql's exit-2 text has no `ERROR:  nnnnn`, so it is BROKEN either way.

**N4. Two brackets are looser than they look** (**predicted**):
- N53's `R5:waited:23514` would be met by any other CHECK failure of B's levy after the wait. R2 passing first with the message "in force over the whole" makes that remote.
- R3 with B refused correctly and the `LAST` query failing prints `FAIL R3 [waited:40001]`, where BROKEN is meant. No mutation names it.

**N5. Read cost** (**executed**, `tally_app`, 40,000 premises with 4 places each, 160,000 memberships, 3000 reads, three runs, noisy machine): -16 2.15–2.38 s, r4 0.55–0.60 s, r5 1.09–1.19 s. So r5 is twice r4 with four places, and still half of -16. It does not grow with the table: the plans are primary-key index scans. The extra is re-planning: the array parameter makes the planner choose a custom plan each call. With `plan_cache_mode = force_generic_plan` r5 reads in 0.68–0.70 s. If it ever matters, that is one function-level SET; I would not change it now.

**N6. A bill using both reads mixes two coordinates** (**read**). The plain read is what is committed; `tax_levy_as_of` has only the instant form. A bill reading plain places and levies at `now()` can see a place recorded after its own start and not the levy recorded beside it. It is the core's choice (the four-argument form exists for this); worth a clause at L5 or L7 when the core's contract is written.

**N7. Wording.** A refusal through the plain form says "not yet recorded at infinity" / "as known at infinity". The `sample()` comment still says "within 1.5s", which the header rightly no longer does. M4's label still says "as known now". The plan's "time zone, regulatory" lookups are one function.

**N8.** The preconditions test, the older-tests diff and the CI timing were not re-examined (unchanged, or restricted).

Probe scripts (scratch, not repo files): `eq.sql`, `w.sql`, `p.sql`, `r.sql` (the comparison), `sweep.py` (filters), `rm5.py` (race mutations), `st.py` (selftest edits), `p3.sh` (S1), `perf.sql`, `t.sql` (cost), in `/private/tmp/claude-501/-Users-ryanscomputer-code-tally-utility-rates/690a7128-f07b-44e6-8980-a85eead718c4/scratchpad/opusr5/`.

---

## r6 (words only)

Read only, no database work: the md5 of `patch-30-frozen-r6.sql` (`978f1cdf07ae36fb286b2a575a5eb7c5`, the live patch identical), `r5-to-r6.diff`, the board's stamps item, and the DECISION-LOG correction. My own diff of the r5 and r6 patches shows header comments and the one function COMMENT only. The `pg_dump` comparison is the author's and was not repeated.

**S1: closed. N2: closed.** L7, the function's comment, the board and the log now say the same thing: the settled answer can be one that was never true, waiting does not cure it, and the instant must be one with no earlier-begun transaction still open.

No sentence needs changing before the mirror. Three nits, optional:
- L7 (b) "every later read at that instant refuses or answers both" (my wording) is too strong in one case: a place recorded again *alike* answers once (race R6). "can refuse or answer both" would be exact. The log's "answers both (or refuses)" has the same exception.
- The log's correction says "that instant" without naming it: an instant between the two writers' starts.
- The board's "for those seconds" describes which instants refuse, not for how long. Such an instant refuses for good.
