# Review: v5.4.2-29 r1 — every Texas county and its time zone (Fable)

**Date:** 2026-11-04. **Reviewer:** Fable (claude-fable-5-1), independent; opus-r1.md and codex-r1.md not read.
**Scratch database:** `rv29fable` (clone of `tally`, TEMP revoked from PUBLIC, tally_app, tally_core right after creation; dropped at the end).
**Frozen hashes:** all seven md5s in the brief match (**executed**); the five live copies are byte-identical to the frozen ones (**executed**); the frozen `older-tests-29-frozen-r1.diff` equals `git diff fdd17a8^ fdd17a8` over `tests/ci.sh`, `battery-16.sql`, `place-close-16.sh`, `battery-28.sql` ignoring the `index` lines (**executed**).

## Verdict: **ready**

No blocking item. Three should-fix items, two of them wording in stored data and comments that is cheaper to correct before the rows and the fixture comments are frozen into `tu.sql` and the batteries. The data is exactly the two sources; every rule of the load refused on every path I tried; the moved fixtures still prove what their checks claim.

## 1. Is the data right?

**Executed.** I fetched the Census file from `https://www2.census.gov/geo/docs/reference/codes2020/cou/st48_tx_cou2020.txt` today: md5 `e1ea7280eb41b680feb924b3bef2c411`, byte-identical to `application/places-sources/census-st48_tx_cou2020.txt`. 254 rows, every one state TX / STATEFP 48, class H1, status A. Every code is odd, 48001..48507, with no odd number in that range absent — so "Texas county codes are odd" (the header's reason the even fixture codes can never be real) holds for the whole list. My own parse of the patch's VALUES list (independent of `source-check-29.sh`): 254 rows, 254 distinct codes, every code/name pair identical to the Census file's, no name with anything but letters, spaces and periods (DeWitt, La Salle, McCulloch, Deaf Smith, Jeff Davis, Jim Hogg, Jim Wells, Tom Green, Red River, San Augustine and friends all as the Census spells them). The battery's C1b hash of `code|name` lines, `5094ab8b28e6ad29990118f886535842`, reproduces from the Census file.

**Executed.** 49 CFR 71.7(e), fetched from the eCFR versioner API for 2026-10-01: "...westerly along the Texas-New Mexico boundary to the east line of Hudspeth County, Tex.; thence southerly along the east line of Hudspeth County, Tex., to the boundary between the United States and Mexico." 71.6(a): the Central zone is "east of the boundary line between the central and mountain standard time zones described in § 71.7". West of Hudspeth's east line lie exactly Hudspeth and El Paso. So Mountain at 48141 and 48229 and Central everywhere else, Culberson (48109) included, is the law as written. 71.7(g) (municipalities on the line are Mountain) is correctly left to a later city load (L3).

**Executed.** Strict apply on `rv29fable` twice: `252 counties loaded, 2 already present`, then `0 counties loaded, 254 already present`; afterwards 254 open counties, all from 1900-01-01, 252 facts `America/Chicago`, 2 `America/Denver`, no `p29_counties` left behind. `battery-29` 22/22 PASS on the clone. `source-check-29.sh` 5/5 against the frozen patch.

## 2. Is there a path around a rule?

All **executed** on `rv29fable` unless marked, each probe in a transaction rolled back.

- **Roles.** tally_app: `permission denied for table places` on insert and on close (C6b, C6c). tally_core running the patch: refused at the very first step, `permission denied to create temporary tables` (TEMP revoked), and tally_core inserting a place fact directly: `permission denied for table place_facts`. Grants on `places`/`place_facts` are SELECT only for both app roles (catalog checked).
- **Isolation.** The guard reads `transaction_isolation` before anything else; the brief's P5 covers it. Nothing in the patch takes a lock that would need it beyond -16's own rule.
- **Partly loaded state.** The whole load is one `DO` block: a refusal anywhere (loop or postcondition) rolls the lot back, so a partly loaded database cannot exist after a failed run. Two owners loading at once (**predicted**): the second's INSERT of the same (county, TX, code, [1900,∞)) waits on the first's exclusion-index entry and then fails `23P01`; its DO rolls back whole.
- **A present county that disagrees.** Misnamed, wrong zone, no zone: refused (the brief's P1–P3). I added: a county whose only open zone fact is dated 1950 (name and zone agree, so the loop passes) is refused by the postcondition's `from 1900` leg; a county whose zone fact is closed in the future (2030) reads as "0 open zone fact(s), zone none" and is refused. Both are the right direction.
- **A re-apply after a correction.** See S1: it refuses, which is safe, but the header's "Re-applying is a no-op" does not say so.
- **Dates.** A membership from 1890 against a loaded county is refused by -16's range rule exactly as before. No Texas place or fact is dated before 1900 (the state itself is from 1900), so nothing earlier can interact.
- **The lookup after the load.** A premise in Culberson (regulatory) and Hudspeth (tax) is refused as a disagreement (`cardinality_violation`), not tie-broken — -16's behaviour unchanged, now reachable with real counties.

## 3. Does the patch or the fixture move break anything earlier?

**Executed (read every use).** The moved fixtures:

- `battery-16` `travis` → 48990 (with a Central fact): used as the owner of a municipal system that must be refused (P2b: a county cannot own a municipal system — kind, not code), as the county of the padded `' tx '` premise (L7d), as the zoned county under an unzoned city (T3b, the city level falls through), on both axes of one premise (U2a), and beside `bastrop` → 48994 on the other axis (U2b, two counties agreeing). None of these depends on the code being Travis's.
- `battery-16` `harris` → 48992 (no fact): the peer county that carries no zone beside El Paso (T3a): the proof is that a zoneless peer refuses, which a planted county proves better than real Harris, which -29 now zones. The comment on line 1044 still reads "Harris County, no zone loaded" (S3).
- `place-close-16` P9/P10 → 48996/48998: R16 races two counties for one premise and axis; the exclusivity group is the county kind's, not the code's. Intact.
- `battery-28` Travis → 48990 "Battery County 28 (Central)": the Austin premise reads Central (Z5b), the parent/child consolidated cases (Z6i) and the fee-stands cases need only a Central county. Intact; the comment was updated.
- `battery-16` line 183 plants `48999` under a city to be refused (A5c) — never inserted, so no collision. `battery-25` line 151 plants `48925` ("Battery County 25", odd but above 48507): not a real code, no collision with the load, but it does not follow the new even-code convention the board note asks of future fixtures (N6).

The brief reports every older battery and race passing in `ci.sh` on the moved fixtures; I did not run `ci.sh` (restricted) and take that as reported.

Nothing in -16's or -28's functions assumed only two counties: `premise_time_zone_as_of` and `invoice_time_zone_as_of` read whatever facts exist; the -28 fee check calls the bill-level lookup. The seeded El Paso and Hudspeth rows are untouched (C4 checks the -16 source_note text).

## 4. The tests: claims vs checks

- `battery-29` C1–C6c and Z1–Z2e: each claim matches its check. Z's fixture arithmetic is right: 2026-07-01 05:30 UTC is 00:30 CDT on July 1 (after the end of June 30 in Central) and 23:30 MDT on June 30 (before it in Mountain), so Houston and Van Horn admit the fee and El Paso refuses it for the same customer.
- C2b counts *all* time_zone facts of a county (`<> 1`), not only open ones — stricter than the patch, which requires exactly one *open* fact. On a base that ever carries a closed historical zone fact for a county, C2b fails while the patch passes. None exists today; noted (N4).
- `mutations-29`: 15 named catches. Three are caught at the named place but by a guard other than the one mutated: N13 (present counties reloaded) is caught because the reload of seeded El Paso hits `places_no_overlap` before anything else (the script's own comment says so); N6 and N12 (the loop's name comparison removed or skipped) are caught because P1's planted "Travis Co." is then refused by the postcondition's "missing, misnamed..." leg, and P1 fails on the message text it expects. The mutations are caught, and the load does not accept bad data under any of them; what the run does not prove is that the loop's own name/zone comparison is load-bearing beyond its clearer message. Acceptable (N5).
- `reapply-29` P1–P7: each label matches its check; P7 asserts both notices and the 254/254 count.
- The frozen copy `source-check-29-frozen-r1.sh` resolves `ROOT` two directories up from its own location, so run from `review/` it looks for `tests/application/places-sources/...` and fails at open. The live copy (identical text, in `tests/v5.4.2-29/`) resolves correctly; I ran that against the frozen patch. Not a patch defect (N7).
- `tests/ci.sh` `?` marker: `${entry%%:*}` / `${entry##*:}` split safely because the SQL condition has no colon; `${marker#\?}` strips the literal `?`; the condition is evaluated against `tally` like every other marker, so after the mirror and a rebuild the entry simply stops matching. On my loaded clone the condition reads `f`. The "load rules" step is gated on the same condition, so `reapply-29.sh` runs only while a pre-29 base exists; the comment says what to do after the mirror.

## 5. Do L1–L5 block?

No. L1 (a premise still needs its county recorded) is -16's design and the lookup refuses, never assumes (Z1d, Z2e). L2 (Culberson legal, not local): nothing in the schema is hurt; the only reader is the state-agency midnight, and a utility that bills on Van Horn local time has no setting for that today — a note for the rates stream, not this patch. L3/L4 are later loads. L5: the postcondition pins 1900 (see S1 for the consequence on re-apply).

## Should-fix

**S1. "Re-applying is a no-op" holds only while no county has ever been corrected. Executed.** After a legitimate correction — Travis closed 2026-01-01 with a successor of the same name and zone from 2026-01-01 — the loop accepts the successor (name and zone agree) but the postcondition refuses: `county 48453 (Travis County) is missing, misnamed, misparented or not in force from 1900; ... does not carry exactly one open time_zone fact of America/Chicago from 1900`. After a dissolution (closed, no successor) the loop finds no open row and re-inserts from 1900, which fails on `places_no_overlap` with a raw 23P01 and no patch message. Both refusals are safe, and in this repo the patch applies once (a correction is its own later patch, and a fresh build runs them in order), so this is not a correctness defect. But the header's rule 3 and the brief's "re-apply is a no-op" overstate it. Fix: state it as a known limit (L6: the postcondition pins the 1900 dating; after any county correction the load is not re-runnable and is not meant to be), or relax the postcondition for rows the loop found present (accept an open row of the right name, parent and zone whatever its `effective_from`). I recommend the header fix: the strict postcondition is the stronger guard for the one application that matters.

**S2. The fact citation in 252 stored rows names 71.7(e) for a statement 71.6(a) makes.** `'49 CFR 71.7(e): Texas east of the east line of Hudspeth County is Central time'` — 71.7(e) describes the line; that the east side is Central is 71.6(a) ("east of the boundary line ... described in § 71.7"), and that the west side is Mountain is 71.8. The substance is right; the pointer is one section off. `source_note` is never edited after insert, so this is the round to write `'49 CFR 71.6(a), 71.7(e): ...'` (and the Mountain branch `'49 CFR 71.7(e), 71.8: ...'`). C5 checks only for the substring `49 CFR 71.7(e)`, so it keeps passing either way.

**S3. Fixture comments in `battery-16` still name the real counties.** Line 1044 "El Paso County (Mountain) for rates; Harris County, no zone loaded, for tax" now describes a planted county 48992; the labels `travis`, `harris`, `bastrop` are fine as labels but the comment misleads a reader into thinking real Harris is unzoned. One-line comment edits; the proofs are intact (section 3).

## Notes

- **N1.** The whole load is atomic: a partly loaded database is impossible after a refusal. Executed by every refusing probe (nothing persisted; each probe also rolled back).
- **N2.** The loop's present-county check and the postcondition overlap on name; the loop adds the clear "already present as X" message and the zone-count detail. Keep both.
- **N3.** `TRUNCATE p29_counties` after `CREATE TEMP TABLE IF NOT EXISTS` makes two applies in one transaction safe; `ON COMMIT DROP` leaves nothing (checked: no `p29_counties` relation after the run).
- **N4.** C2b is stricter than the patch (counts all facts, not open ones); harmless today, would need loosening if a county's zone fact were ever closed and superseded.
- **N5.** Mutations N6, N12, N13 are caught by neighbouring guards (see section 4); none lets bad data through.
- **N6.** `battery-25` plants county `48925` — not real, no collision, but not even either. The board's note to new fixtures should be read as "not on the Census list"; the even convention is -29's own.
- **N7.** The frozen `source-check-29-frozen-r1.sh` cannot be run from `review/` (ROOT resolution); run the live copy with the frozen patch as its argument.
- **N8.** Two `postgres-mcp` containers were running when I started (`docker ps --filter ancestor=crystaldba/postgres-mcp` → 2); not mine, not touched; reported for the leak watch.
- **N9.** The eCFR enhanced-renderer URL returns 404; the versioner API (`/api/versioner/v1/full/2026-10-01/title-49.xml?section=71.7`) returns the section. Worth a line in `application/places-sources/our-sources.md` for the next loader.

## Clean-up

`rv29fable` dropped. No repo file touched but this one.
