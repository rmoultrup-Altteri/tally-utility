# Review: v5.4.2-29 r3 — every Texas county and its time zone (Fable)

**Date:** 2026-11-05. **Reviewer:** Fable (claude-fable-5-1), independent; opus-r1.md, codex-r2.md, the codex probe files and codex-r3.log not read. Inputs: `review-brief-29-r3.md`, my `fable-r1.md`, the r2 and r3 plans, the frozen r1/r2/r3 files (diffed pairwise), `sql/PATCH-LESSONS.md` (index; template-clone-drops-acl, strict-apply-before-mirror, checks-narrower-than-their-claim, every-branch-and-stated-default-tested).
**Scratch databases:** `rv29fable3` (clone of `tally`, loaded) and `rv29fable3b` (clone, not loaded), TEMP revoked from PUBLIC, tally_app and tally_core right after creation; both dropped at the end. Every probe ran in one psql session ending in ROLLBACK; nothing persisted.
**Frozen hashes:** all seven md5s in the brief match (**executed**). The live `sql/v5.4.2-29-texas-counties.sql`, `reapply-29.sh`, `mutations-29.sh`, `battery-29.sql` and `source-check-29.sh` are byte-identical to the r3 frozen copies (`cmp`, **executed**). `older-tests-29-r2-to-r3.diff` equals `git diff HEAD~1 -- tests/ci.sh` (**executed**).

## Verdict: **ready**

No blocking item. No should-fix item. The one patch change in round 3 (Texas looked up as the row in force on 1900-01-01) closes Codex's B1 exactly and nothing else: I reproduced the r2 refusal and the r3 no-op on the same succeeded state, in my own database. The round-2 changes (which I had not seen) close my r1 S1, S2 and S3 as the plan says. The data is unchanged from r1 and still exactly the two sources. Every rule refused on every path I tried, including the paths the as-of-1900 identity opens.

## 1. Round 3's fix (B1) and the round-2 fixes

**B1 — executed.** The diff r2→r3 is two lines of code (the Texas lookup, now `daterange(effective_from, effective_to, '[)') @> c_from`) plus the message and the header paragraph; nothing else moved (diffed the frozen pair). On `rv29fable3` (loaded) I closed Texas and its whole tree at 2027-01-01 and added successors from 2027 (256 rows closed and succeeded, the shape of reapply P10, the ordinary rules on):
- r3 re-applies: `0 counties loaded, 254 already present`; the digest of every `places` and `place_facts` row (the same query as the runner's `fp()`) is identical before and after (`9091c8d6…` both times). **F1.**
- frozen r2 on the same state: `v5.4.2-29 precondition: no open Texas state place in force from 1900-01-01`. The finding is real and the fix closes it. **F2.**
- a further correction after the succession (the Harris successor closed 2028 and replaced under the new Texas), then r3: no-op, digest unchanged. **F3.**
- Texas and every child closed at 2027 with **no** successor, then r3: no-op, digest unchanged, zero open Texas places afterwards. The header's "closes one without a successor" holds for the whole state, not only a county. **F4.**
- on `rv29fable3b` (unloaded), Texas succeeded first, then r3: refused by -16's parent rule (`parent … is not a state of state TX in force over 1900-01-01..open — v5.4.2-16`), at the first county insert, from inside the DO block, so nothing is loaded; frozen r2 on the same state refuses at its precondition instead. **F5, F5b.** This is P10b's claim; it is the right refusal: a county from 1900 can only sit under the Texas in force over `[1900, open)`, and that row is closed. A load that knew how to split the county across the two Texas rows would be inventing data; refusing is correct. (The message is -16's raw one with a UUID; see N3.)

**"The row in force on 1900-01-01" as the identity of "already present" — executed where marked.** It is the right identity: the load writes rows dated 1900, so the only rows it can be asked to agree with are those in force on that date; everything later is a later migration's data, which the load must neither read as a mismatch nor touch. Checked:
- a county closed before today (Loving in P8; all 254 in F4): no-op.
- a county whose 1900 row was closed and succeeded (P8; F6 with a 1950 successor of the same name): the loop takes the 1900 row, compares name and the zone fact in force on 1900, and skips. F6 on the unloaded base, with three counties planted correctly and one of them succeeded at 1950: `249 loaded, 5 already present`, 255 county rows after (254 + the closed 1900 Harris).
- a Texas state row closed and succeeded: F1–F5 above.
- a listed code whose only row begins after 1900 (P9): refused by the load's own message, not the overlap rule. Right under -16 R2 (counties from 1900); a 1950-only row is contrary to R2, and refusing is safer than backdating under it.
- what the identity does **not** see (**F7**, executed): a 1900 row named right and closed 1950, with a misnamed successor from 1950 (`Harrys Kounty`). The load is admitted (251 loaded, 3 present) and leaves the misnamed row alone. That is the design: the load's claim is the state on 1900-01-01, and a later row is a later migration's responsibility. Not a defect; recorded as N2 so the next reader does not expect more.

**Can a legitimate row trip "refuse, not overwrite" or the closed list?** No path found. Leg 1 of the postcondition (a county in force on 1900 off the list) can only be tripped by a county row dated to cover 1900 whose code is not one of the 254; Texas has had no county abolished after 1899 (Buchel and Foley 1897, Encinal 1899 — **predicted**, from general knowledge, not a source in the repo), so a correct historical load could never plant one. Legs 2 and 3 are tripped only by a 1900 row that disagrees with the Census list — a mistake, and the right outcome is the refusal.

**Round-2 fixes (my first sight; the plan's S1–S5) — executed as marked.** S1 (as-of-1900) closes my r1 S1 and more than my proposed header note, with every refusal kept (P1–P4, P9 still refuse: F6/F7 show the loop and the postcondition on the 1900 row; the battery's C-checks pass on the loaded base). S2: the stored notes now read `49 CFR 71.6(a), 71.7(e): …` on the 252 Central facts (F12: 252 rows match, 0 Mountain rows from -29, El Paso and Hudspeth keep -16's `Texas county (FIPS n).` and -16's citation text, nothing closed). Battery C5 now requires the 71.6(a) substring and the Central value. S3/S4/S5 are as the plan describes (read the r1→r2 battery and ci.sh diffs and the frozen r3 runners).

## 2. Is the data right?

Unchanged since r1 and re-checked where cheap (**executed**): the Census file's md5 is the brief's and the r1 one; `source-check-29.sh` 5/5 against the frozen r3 patch; after the strict apply, 254 counties all from 1900-01-01, 252 `America/Chicago` and 2 `America/Denver`, Culberson Central, Mountain exactly at 48141 and 48229 (F12). The VALUES list is byte-identical between r1, r2 and r3 (the diffs touch no data line). My r1 reading of 71.6(a)/71.7(e)/71.8 stands; the r2 citation matches it.

## 3. Is there a path around a rule?

All **executed** unless marked.
- **Roles (F9).** tally_app inserting into `places` and into `place_facts`: `permission denied for table …`; tally_core inserting into `places`: the same; tally_core creating the patch's temp table on my clone: `permission denied to create temporary tables`. Catalog: both roles hold SELECT only on the two tables. Reapply P6/P6b grant TEMP deliberately so the refusal lands at `places`, which is the stronger proof.
- **Isolation (F8).** Under REPEATABLE READ the load refuses at its first statement.
- **Partly loaded state (F6).** The load completes what is missing and skips what is present and agreeing. The whole load is one DO block; every refusal above rolled the lot back (F5 left nothing: the error came from inside the block).
- **Two Texas rows in force on 1900 (F11).** Impossible: `places_no_overlap` is keyed on (kind, state, code, range), so the r3 lookup finds at most one row and `SELECT … INTO` cannot pick an arbitrary one. The same key makes "the county row in force on 1900" unique, and `place_facts_no_overlap` makes "the zone fact in force on 1900" unique.
- **Re-apply after a correction.** F1, F3, F4, P8, P10 (all no-op). The in-loop `SELECT … INTO v_zone` sets `v_zone` to NULL when no fact is in force on 1900 (PL/pgSQL assigns NULL on zero rows), so a stale value from the previous county cannot leak into the comparison; P3 proves the NULL branch refuses.
- **Concurrency (predicted, unchanged from r1).** Two owners loading at once: the second's inserts block on the first's exclusion entries and fail `23P01`; its block rolls back whole.

## 4. Did round 3 break anything round 2 had right?

No. The only patch change is the Texas lookup; the county lookup, the zone lookup, the `v_nrows` refusal, the postcondition and the list checks are byte-identical r2→r3. The strict apply twice, the battery (22/22) and the source check (5/5) all pass on r3. The r2 cases (P8, P9) are unchanged in the r3 runner.

## 5. The tests: claims vs checks

- **reapply-29 (r3).** `refused()` yields `[admitted]` only on exit 0 and `[refused otherwise]` only on a non-zero exit without the fragment; `noop()` yields `[refused]` on a non-zero exit and `[changed]` when the notice is missing, the before-digest is empty or the digests differ. The digest covers every column of every `places` and `place_facts` row (`to_jsonb(row)`), ordered by text, so a re-apply that wrote, closed or stamped anything shows. **F10 (executed):** one permitted close of Culberson's fact moves the digest (`e63b32…` → `5c544d…`). P8's successors differ in zone and name from what they replace, so a re-apply that re-inserted or compared the wrong row would both change the digest and (for the name) refuse; P10's state is the one I reproduced in F1. P10b's fragment is -16's message, which is the only text that proves the refusal came from the parent rule and not the load.
- **mutations-29 (r3).** N18's anchor (the r3 lookup's two lines) is unique in r3; under it the old Texas is closed, the new one starts in 2027, `v_tx` is NULL and P10 fails `[refused]` — F2 is this mutation run by hand (frozen r2 is r3 with N18 applied, plus the message). The runner now compares `RE:<case> [<how>]`, so a mutation that refused for the wrong reason or applied when it should refuse is a `WRONG CHECK`, not a catch. I did not run the runner (shared database names); the author's 20/20 is taken as reported.
- **ci.sh (S2).** The second read of `P29_PENDING` is taken with `2>&1` and gated `t|f` else `SETUP FAIL … exit 2`, exactly like the pending-list read above it. The condition is one variable, so the two reads cannot drift apart. The marker counts *open* Texas counties `< 254`; after a hypothetical county close on the live base the marker would read pending again and `reapply-29.sh` would run against an already-loaded `tally` (its cases clone `tally` and expect the load to insert) — that is the comment's "restore a pre-29 base" situation, and cannot happen before the mirror (predicted; N4).
- **battery-29.** Unchanged since r2; its C-checks describe the state just after the load, which is the only state the battery sees in `ci.sh`. C2b still counts every zone fact (my r1 N4); harmless today.

## 6. Do L1–L6 block?

No. L1–L5 as in r1. L6 (El Paso and Hudspeth keep -16's notes) is the right call: a note is never edited (F10's first attempt proved -16 refuses it), and a close-and-successor to change provenance text would be churn; the header carries the provenance.

## Notes

- **N1 (executed).** F1–F5 are the B1 story end to end: r2 refuses after a state succession on a loaded base; r3 is a no-op there; on an unloaded base both refuse, r3 by the parent rule, r2 by its own precondition.
- **N2 (executed, F7).** The as-of-1900 identity never examines a county's later rows. A misnamed successor dated after 1900 is admitted untouched. Intended; stated here so nobody reads "already present must match" as "every row of that code must match".
- **N3 (executed, F5).** P10b's refusal is -16's raw message with the parent's UUID. A load-level precondition ("the Texas in force on 1900 has closed; counties from 1900 cannot be inserted under it") would read better, but the state cannot arise in this repo's apply order (no patch before -29 replaces Texas), and the plan chose to let the parent rule speak. Not a should-fix.
- **N4 (predicted).** `P29_PENDING` keys on open counties. Any later patch that closes a Texas county before -29 is mirrored would turn the marker back to pending; after the mirror the entry is removed as the comment says. Nothing to do now.
- **N5 (executed).** Two `postgres-mcp` containers were running when I started (`docker ps --filter ancestor=crystaldba/postgres-mcp` → 2); not mine, not touched; reported for the leak watch, as in r1.
- **N6 (predicted).** The header's L5 ("No Texas county has been created or renamed since 1931") and my leg-1 reasoning (no county abolished after 1899) are general knowledge, not a repo source. They matter only for the historical correctness of dating everything from 1900, which -16 R2 already decided.

## Clean-up

`rv29fable3` and `rv29fable3b` dropped. No repo file touched but this one. Probe scripts live in my scratchpad, not the repo.
