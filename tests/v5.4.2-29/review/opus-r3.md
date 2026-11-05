# Opus review: v5.4.2-29 r3 (every Texas county and its time zone)

**Date:** 2026-11-05. **Reviewer:** Opus (round 1: ready; I had not seen r2 or r3). **Scratch databases:** `rv29opus3` (clone of `tally`, frozen r3 applied strictly) and `rv29opus3b` (clone of `tally`, no counties), each with TEMP revoked from PUBLIC, `tally_app` and `tally_core` right after creating it. Both dropped at the end. Every probe ran in a transaction that rolled back. I did not read `fable-r1.md`, `codex-r2.md` or the codex probe files. I did not run `reapply-29.sh`, `mutations-29.sh` or `tests/ci.sh`.

## Verdict: ready

No blocking items. Round 3's one patch change closes Codex's B1 and changes nothing else. Round 2's fixes close my round-1 findings. One should-fix: CI's "is -29 still pending" marker still counts the counties open today, the same identity the patch moved away from in r2 and r3. It matters only after the mirror. Five notes.

## Frozen files

All seven md5s match the brief. The live patch `sql/v5.4.2-29-texas-counties.sql` is byte-identical to `patch-29-frozen-r3.sql`. Battery and source check are unchanged from r2 (cmp). **executed**

## Results reproduced (executed)

- Strict apply twice on `rv29opus3`: "252 counties loaded, 2 already present", then "0 counties loaded, 254 already present". Both exit 0.
- `battery-29-frozen-r3.sql`: 22 PASS, "all checks passed".
- `source-check-29.sh` run against the frozen r3 patch: 5 of 5 PASS.
- The data is unchanged since r1: the r1→r2 and r2→r3 diffs touch no `('48…')` tuple. I checked the list against the Census file in r1.
- The citations: I fetched 49 CFR 71.6 and 71.8 from the eCFR versioner (2026-10-01). 71.6(a) says the Central zone runs "west of … § 71.5 and east of the boundary line … described in § 71.7". 71.8 says the Mountain zone is "west of the boundary line … described in § 71.7". So the r2 citation fix is right: Central facts cite 71.6(a) and 71.7(e), Mountain facts cite 71.7(e) and 71.8.

## 1. Does each fix close its finding?

### Round 3, B1: re-applying after Texas itself is replaced. Closed. **executed**

On the loaded `rv29opus3` I wrote my own succession (not the author's `SUCCEED_TX`). It closes every open fact of Texas's tree at 2027-01-01, closes every place deepest first, then adds successors top down with the facts copied over. That came to 256 places and 256 facts. Results:
- **Frozen r3:** "0 counties loaded, 254 already present". The digest of every `places` and `place_facts` row was identical before and after (`2c9081c5…` both times).
- **Frozen r2, same state:** refused, "no open Texas state place in force from 1900-01-01". So the probe really does reproduce the finding, and r3 fixes it.
- **Texas's tree closed at 2027 with no successors at all:** r3 re-applies as a no-op, digest unchanged.

The change is minimal. Only the state lookup and its message moved, and the header text says so. Only one Texas row can be in force on 1900-01-01, because `places_no_overlap` forbids two. Every county row in force that day must sit under a parent in force over its whole range, and that parent can only be the same Texas row. So the postcondition's `parent_place_id = v_tx` still holds after the state is succeeded.

### Round 3, P10b: a county inserted under a Texas that has closed since. Right refusal. **executed**

On `rv29opus3b` (no counties), after the same succession, r3 refuses at the first insert with -16's rule: "parent … is not a state of state TX in force over 1900-01-01..open". r2 refused earlier, at its own precondition. I also planted Travis from 1900 under the old Texas before the succession, so it was closed and succeeded along with the rest. The load accepted Travis as present and then refused the next county the same way.

This is the right outcome. Loading into that state would need two rows per county, one under each Texas. That is a correction migration's job, not this load's, and the patch never writes an open child under a closed parent. See N1 on the wording of the message.

### Round 2's fixes to my round-1 findings

**Re-applying after a later correction (my S1). Closed. executed**
Each case below re-applied as "0 loaded" with the row digest unchanged:
- Travis closed at 1950, with a successor from 1950 under another name, in Mountain.
- Culberson's zone fact ended at 1900-01-02, with Mountain from then on.

A county not on the list that was in force only from 1900 to 1950 is still refused ("48990 is not on the Census list"), so the closed list still guards the 1900 day.

**Mutations caught by the wording of the message (my S2). Closed by the runner.** N14 and N15 remove a comparison from both the loop and the postcondition, and the runner now requires the load to be admitted for them. N6–N8 and N12 change only the in-loop layer, and the runner now requires "refused otherwise" for them. That is the right pair of claims. **predicted** from reading the runner; the author ran it.

**The app-role case passed at the temp table (my S3). Closed.** P6 and P6b grant TEMP and expect "permission denied for table places". I reproduced the grant-then-role path for both roles. On a loaded base it is a read-only no-op; see N4. **executed**

The other r2 changes check out: the CI marker became one variable with a t/f check, L3 now names Farwell and Texline, L6 is new, and battery -16's comments now say the stand-ins are planted. Each matches what it says. **executed** (read)

## 2. Is the data right?

Yes, unchanged since r1 (see above). Culberson stays Central (L2). **executed**

## 3. Is there a path around a rule?

None found. **executed**
- Under REPEATABLE READ the load refuses.
- As `tally_app` or `tally_core` with TEMP granted, the load writes nothing. It is a no-op on a loaded base, and P6 covers an empty one.
- `time_zone` is not keyed (`place_fact_kinds.keyed = f`), so a county cannot carry two zone facts in force on 1900. The single-row `SELECT INTO` in the loop and the postcondition's `NOT EXISTS` cannot disagree.
- The load is one DO block, so it applies all or nothing.

## 4. Did round 3 break anything round 2 had right?

No. The battery, the source check and every r2 case shape are unchanged. Every refusal I re-ran (isolation, a county not on the list, a misnamed or rezoned county from r1) behaves as before. **executed**

## 5. The tests

### S1. CI's -29 marker still counts the counties open today, not the counties in force on 1900. **executed (the marker), predicted (the ci.sh consequence)**

`tests/ci.sh` line 41 says -29 is pending while `count(*) … effective_to IS NULL < 254`. The gate at line 170, which decides whether `reapply-29.sh` runs, stays in ci.sh after the mirror. Take a mirrored database and later close one county with no successor, which is P8's Loving case and a change the header names as legitimate. The marker then flips to true; I evaluated it after that close in `rv29opus3`. From then on ci.sh would run `reapply-29.sh` on clones of a `tally` that already holds the counties. P7 there expects "252 counties loaded" and would fail. If -29 is still in `PENDING`, ci.sh would also strict-apply it again, which is harmless because that is a no-op. A succession of Texas (B1's case) does not trip the marker, because its successors keep the count at 254.

Nothing trips this today: no Texas county has dissolved since 1931 (L5). But it is the same "open today" identity that r2 and r3 removed from the patch, and the fix is one line. Count the counties in force on 1900-01-01 instead (`daterange(effective_from, effective_to, '[)') @> DATE '1900-01-01'`). That version stays false after the same close; I evaluated it as well.

### Is any claim narrower than its check?

No.
- The digests in P7, P8 and P10 cover every column of every `places` and `place_facts` row, stamps included. An empty digest fails, because of the `-z` guard.
- P8's successors now differ from what they replace, so a re-apply that wrote would show.
- P10b greps for -16's own parent message, so it tells "refused by the parent rule" apart from r2's precondition.
- The runner's `grep -m1 '^FAIL P… [how]'` only sees FAIL lines that carry a tag. Every FAIL line in `reapply-29.sh` carries one, and SETUP FAIL lines do not start with "FAIL".

## 6. Do L1–L6 block?

No, for the same reasons as in r1. L6 (El Paso and Hudspeth keep -16's source notes) records what my r1 N1 asked for. L3 now names the border towns.

## Notes

- **N1.** P10b's refusal comes from -16 ("parent … is not a state … in force over 1900-01-01..open"), not from the load, so it does not say that the load needs the 1900 Texas to be still open in order to insert. That state can only arise on a pre-29 base where Texas has already been succeeded, which `tu.sql` never builds. The message is acceptable as it is. An optional line in the precondition would be friendlier: refuse when a county must be inserted and `v_tx` is closed. **executed**
- **N2.** Judging "already present" as of 1900 means a re-apply checks nothing about the counties today. In my probe, Culberson rezoned to Mountain from 1900-01-02 re-applies as a no-op. That is the intended design (I proposed it in r1): a correction belongs to its own reviewed migration. The header says what was in force on 1900-01-01 does not change, which is accurate. **executed**
- **N3.** P7's failure line always says `[changed]`, even when an apply refused. No mutation names P7, so this does not mislead the runner today. It would be worth distinguishing if one ever does. **predicted** (read)
- **N4.** With TEMP granted, `tally_app` and `tally_core` can run the patch on a loaded base to a successful no-op, because the run is read-only. That is harmless, and the real write refusal is covered by P6, P6b and battery C6b/C6c. **executed**
- **N5.** Two `crystaldba/postgres-mcp` containers were running when I started. I am flagging them for the board's container-leak rule; I did not touch them.

Clones `rv29opus3` and `rv29opus3b` dropped; my temp files in the container removed.
