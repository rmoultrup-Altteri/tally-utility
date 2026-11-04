# Opus review: v5.4.2-29 r1 (every Texas county and its time zone)

**Date:** 2026-11-04. **Reviewer:** Opus. **Scratch database:** `rv29opus` (clone of `tally`, TEMP revoked from PUBLIC, `tally_app` and `tally_core`; dropped at the end).

## Verdict: ready

There are no blocking items. The data is right against both sources, I checked independently. I found no way around the load's rules. The fixture moves keep what the older tests proved. Three should-fix items: one is about re-applying after a later correction, two are about what the tests actually prove.

## Frozen files

All seven md5s match the brief, and so do the live copies (`sql/v5.4.2-29-texas-counties.sql` and the four files in `tests/v5.4.2-29/`). **executed**

## Results reproduced

- Strict apply twice on `rv29opus` (`search_path=`, `check_function_bodies=on`): both clean. The first printed "252 counties loaded, 2 already present", the second "0 counties loaded, 254 already present". **executed**
- `battery-29.sql`: 22 PASS, "all checks passed". **executed**
- Battery -16 (97 PASS) and battery -28 (101 PASS), from the moved fixtures, both run on `tally` + -29. Battery -28 as it stood before the move fails on `places_no_overlap` at its Travis insert, so the move was needed. **executed**
- I did not run `reapply-29.sh`, `mutations-29.sh` or `ci.sh` (the brief forbids it). I reproduced several of their cases by hand in rolled-back transactions (below).

## 1. Is the data right?

**Yes.** **executed**

- **The Census file.** I fetched `https://www2.census.gov/geo/docs/reference/codes2020/cou/st48_tx_cou2020.txt` today. It is byte-identical to `application/places-sources/census-st48_tx_cou2020.txt` (md5 `e1ea7280…`). It has 254 rows, all TX/48, all class H1, all status A.
- **The patch's list.** I parsed every `('48nnn', 'name', 'zone')` tuple in the frozen patch with my own script, not `source-check-29.sh`. There are 254 tuples, no duplicates, and the set of codes equals the Census set. Every name equals the Census name, " County" suffix included (DeWitt is spelled as the Census spells it). No name needs quoting. Every code is odd, from 48001 to 48507.
- **The battery's hash (C1b).** I recomputed `5094ab8b28e6ad29990118f886535842` straight from the Census file, as code|name lines in code order. So C1b ties the loaded rows to the source itself, not to the patch's own list.
- **The zones.** I read 49 CFR 71.7 from eCFR (versioner, 2026-10-01). Paragraph (e) runs the Central/Mountain line "southerly along … the west boundary of the State of Texas to the southeast corner of the State of New Mexico; thence westerly along the Texas-New Mexico boundary to the east line of Hudspeth County, Tex.; thence southerly along the east line of Hudspeth County, Tex., to the boundary between the United States and Mexico". The only Texas land west of that line is Hudspeth and El Paso. The panhandle and the 32nd-parallel counties (Loving, Reeves, Culberson) are east of it. The patch has Mountain at exactly 48141 and 48229 and Central everywhere else. That is right.
- **Culberson (48109)** is Central in the patch and Central by law. See L2 below.

## 2. Is there a path around a rule?

None found. **executed** unless marked.

- **The application role** (`tally_app`), and `tally_core`, which has only SELECT on `places` and `place_facts`: refused. Note the reason in S3.
- **Isolation level.** Under SERIALIZABLE the patch refuses with "run under READ COMMITTED (got serializable)". REPEATABLE READ takes the same check.
- **A partly loaded state.** The patch is one DO block, so it applies all or nothing. Two sessions loading at once: the second blocks on the overlap constraint behind the first, then fails, with nothing partly written. **predicted**, from how a gist exclusion constraint behaves.
- **A future-dated county not on the list** (48509 from 2030): refused by the closed-list postcondition.
- **A county whose only row is closed** (48453 closed in 2000): refused, but by the raw `places_no_overlap` violation rather than the patch's own message (N3).
- **A re-apply after a correction:** refused. See S1.
- **A misnamed or wrongly zoned present county:** refused (reproduced P1 and P2 by hand).

## 3. Does anything earlier break?

No. **executed**

- The fixture moves use 48990–48998. They are even, so they can never be real Texas codes. Batteries -16 and -28 address their fixtures by key (`pg_temp.id('travis')`, `b28.k`), never by code, so every older case still runs on the same shape. Battery -16's zone-less tax-axis county (formerly Harris 48201, now 48992) still proves "one place with a zone and one without is refused". Battery -28's Central stand-in (48990) still proves the Central path, and -29's Z2 now proves it on real Harris.
- Other fixtures that are not real codes stay as they are and do not collide: 48925 (battery -25, rolled back) and 48999 (battery -16, a county under a city, which is meant to be refused). Both are above 48507.
- The pending money patches (-23, -25, -26) apply before -29 in `PENDING`, and none of them writes `places`.
- No older test counts Texas counties.

## 4. The tests

### S1. "Re-applying is a no-op" holds only until the first correction migration. **executed**

In `rv29opus`, with the load committed, I made each change below in a transaction, re-applied the patch, and rolled back:

| Later change (close + successor, as `places` requires) | Re-apply of -29 |
|---|---|
| R1: Culberson's zone fact closed at 2027-01-01, same zone again from 2027 | refuses: "does not carry exactly one open time_zone fact … from 1900" |
| R2: Culberson moved to Mountain from 2027 (a change in the law) | refuses: "already present … zone America/Denver" |
| R3: Culberson's zone fact given a future end date, no successor yet | refuses: "0 open zone fact(s), zone none" (the fact is still in force today) |
| R4: Culberson's place closed at 2027, successor from 2027 | refuses: "missing, misnamed, misparented or not in force from 1900" |
| R5: a new Texas county loaded later (48509 from 2027) | refuses: "not on the Census list" |

The header says "re-applying is a no-op". DEPLOY-VERIFICATION records re-application "over the build" as part of the mirror check, and the DECISION-LOG records re-applies "after committed post-patch rows". But -29 judges the rows that are open today (`effective_to IS NULL`), not the state it created. So the first ordinary correction to any county, which is exactly the close-plus-successor path the patch itself names, makes its body in `tu.sql` refuse if it is ever run again. -16's own seed survives this, because it skips any code that has a row at all.

It is not blocking: today `tu.sql` only builds empty databases, and ci.sh stops re-applying -29 once it is mirrored. But the claim is narrower than it reads, and the fix is cheap. Judge everything as of `c_from` instead of "open":
- a code is present when any row of it is in force on 1900-01-01;
- compare that row's name, and the zone fact in force on 1900-01-01;
- the postcondition becomes: every Texas county in force on 1900-01-01 is on the list, and each one's 1900 fact has the list's zone.

That survives R1–R5 and still refuses everything P1–P4 test. If it is not adopted, the header should say "a no-op until a later migration corrects a county", and a later county migration's author needs to know.

### S2. The mutations behind the per-county compare are caught by the wording of the message, not by a change in what happens. **executed**

I applied mutation N6 (name not compared), N12 (always CONTINUE) and N7 (zone not compared) to fresh clones carrying the planted P1/P2 rows. Each load **still refuses**, now through the postcondition: N6 and N12 with "county 48453 (Travis County) is missing, misnamed…", N7 with "does not carry exactly one open time_zone fact of America/Chicago". `mutations-29.sh` counts them as caught only because `reapply-29.sh` greps for the in-loop message.

The reverse is untested. No mutation removes the postcondition's second leg (name, parent, from 1900) or the zone-value half of the third, and each is masked by the in-loop compare. So the two layers each hide the other's mutations. The run proves which message appears, not that either layer is needed. Mutations N8 and N13 have the same shape: N13 is "caught at P1" because the load dies on El Paso's overlap before reaching Travis.

Suggested fix: state in the mutation script that the in-loop compare is the diagnostic layer and the postcondition is the guard. Then add two mutations that disable a postcondition leg together with its in-loop twin, expecting the load to be admitted and battery C1b or C3 to catch it. Alternatively, make the reapply cases check only the refusal (the exit code plus "v5.4.2-29"), with the message as a separate softer check.

### S3. Case P6 ("as tally_app the load refuses") passes because tally_app cannot create a temp table, not because it cannot write `places`. **executed**

With TEMP revoked, which is how every clone and `reapply-29.sh` run, `SET ROLE tally_app` fails at `CREATE TEMP TABLE`: "permission denied to create temporary tables in database". The fragment "permission denied" matches it. With TEMP granted, the refusal is the one the case means: "permission denied for table places". The real protection is there, and battery C6b and C6c test it directly. But P6 is narrower than its label. Grep for "for table places" and grant TEMP to tally_app inside P6's own clone, or drop P6 as a duplicate of C6b. `tally_core` behaves the same as tally_app.

### The rest of the battery

C1–C6 and Z1–Z2e check what their labels say. Z2d proves the exemption actually reads the loaded county (it refuses for a state agency in Houston), so Z2 cannot pass just because the check never runs.

## 5. Do the known limits (L1–L5) block?

None of them blocks.

- **L1 (each premise still needs its county recorded).** This is the decision's own stated split: the platform holds the counties, the utility records which county each premise is in. Z1d and Z2e test it.
- **L2 (Culberson stores the legal zone, Central).** The zone feeds the state-agency fee's end-of-period boundary, which is a legal determination, so the legal zone is the right thing to store. Nothing in the schema reads the zone for display. The header says "that is its own setting" for a utility that bills on local time, but no such setting exists yet. That is a forward reference, not a gap this patch opens. **executed** grep of the zone's readers: only `premise_time_zone_as_of` and its -28 callers.
- **L3 (49 CFR 71.7(g): towns on the line are Mountain; cities not loaded).** This is not only hypothetical. The Texas–New Mexico boundary is itself the zone line, and towns sit on it, for example Farwell (Parmer County), which adjoins Texico, NM. Read literally, (g) could put such a town in Mountain while its county stays Central. Since cities are not loaded, no premise can reach a wrong answer through -29. I'd name the candidate towns in L3 so the city load meets them. **predicted**: I did not verify any town's limits against the line.
- **L4 (counties only).** Out of scope by design.
- **L5 (everything dated from 1900-01-01).** A membership dated before 1900 is refused by -16's containment rule, as it already was for El Paso. No fact or bill reads before 1900. **executed**: nothing in `tally` is dated before 1900.

## Drafting calls (the brief's list)

- **Refuse, not overwrite.** Right. Places are platform-only rows, never edited, and a silent overwrite would rewrite history. A difference is a migration-author error that should stop the load. The only gap is S1: a correction made after the load.
- **The closed-list postcondition.** No legitimate row trips it in any path that runs it today: the pending patches write no places, test fixtures are rolled back, and `tally` is never written. A future county or a correction would trip it, but only on a re-apply (S1).
- **Culberson.** See L2; it does not block.
- **Dates.** See L5; no interaction.
- **The fixture moves.** Sound; see section 3.
- **CI.** The `?` marker works for this condition, but see N4.

## Notes

- **N1.** El Paso and Hudspeth keep -16's source note "Texas county (FIPS n)." while the other 252 cite the Census file. The provenance differs on two rows. It is acceptable (fixing it would take a close and successor), but worth a line in the header. **executed** (C4 asserts it).
- **N2.** The patch's temp table is `CREATE TEMP TABLE IF NOT EXISTS … ON COMMIT DROP` with the `p29_counties` name unqualified. Under `search_path=` it resolves to pg_temp first, which is intended. A same-named temp table already in the session would be reused, but only the session running the migration can make one. Not a path.
- **N3.** If a list code's only row is closed, or is open with a future end date, the patch's "present" lookup misses it. The insert then dies on `places_no_overlap` instead of the patch's "does not overwrite" message. It still refuses, just with a less helpful message. The S1 fix covers it.
- **N4.** `ci.sh`'s `?` marker treats any output other than `t` as "mirrored", so a condition that errors (a typo, a renamed table) silently skips the strict apply. The table-name markers cannot error that way. The same condition is also written a second time, in the gate for `reapply-29.sh`, so the two copies can drift apart. Suggested fix: treat an error as a setup failure, and keep the condition in one variable. **predicted**: read from the script.
- **N5.** After the mirror, the load rules (P1–P7) lose CI coverage until a pre-29 base is restored. This is stated in ci.sh and matches -25 and -26.
- **N6.** Two `crystaldba/postgres-mcp` containers were running when I started. That is noted for the board's container-leak rule; I did not touch them.

Clone `rv29opus` dropped at the end of the review.
