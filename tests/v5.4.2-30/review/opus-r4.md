# v5.4.2-30 r4 — Opus review

**Date:** 2026-11-22. **Reviewer:** Opus. **Verdict: ready**, with no blocking item. S1 (the words of known limit L7) and S2 (one mutation's claim) should be fixed before the mirror. Neither changes what the schema refuses.

All seven frozen md5s match the brief. The live patch is byte-identical to the frozen copy (**executed**, checked first and again at the end).

- Two fresh clones of `tally` (`rv30opus`, `rv30opusrace`), TEMP revoked from PUBLIC, `tally_app` and `tally_core`. Frozen r4 strict-applied twice on each: no error (**executed**).
- Battery: 120 PASS, "all checks passed" (**executed**). Frozen race test: R1–R7 PASS, exit 0 (**executed**).
- Not run, as the brief restricts: `mutations-30.sh`, `preconditions-30.sh`, `ci.sh`. I did not read `fable-r4.md` or `codex-r4.md`.
- By hand: 18 single-filter mutations of the read against battery -30 (nine of them also against battery -16), and N52, N53, N54, N64, N65 plus two of my own through the frozen race test.
- Both clones are dropped.

---

## 1. My round-3 findings

- **S1 (L7 and the read's comment overclaimed): partly closed.** The comment on the four-argument read is now right. L7's first sentence is right. Its part (a) and its remedy are not yet: S1 below. Part of the fault is the wording I proposed.
- **S2 (two untested filters of the group check): closed.** M12c is the fixture I asked for. N55 and N56 are its mutations (**read**; M12c passes, **executed**).
- **N1 (the coverage read's third snapshot): closed in the code.** But it changed what mutation N53 proves: S2 below.
- **N3 (clock stepped back): closed**, in the recorder's comment.
- **N4 (a future `created_at` in the backfill): closed** by `least()` and C6b (**read**).
- **N6 (cosmetics of the race test): closed.**
- N2, N5, N7 needed nothing.

## 2. Blocking

None.

## 3. Should fix

### S1. L7 still overclaims: the read at `now()` can itself answer a set of places that was never true, where -16 answered correctly; and (a) leaves out the commonest difference

**(i) The live read is not the reference (executed, `rv30opusrace`, as `tally_app`, three sessions).** A premise is recorded in district D1 by mistake, and should be in D2.
1. A begins.
2. A billing transaction begins.
3. B voids the D1 row and commits.
4. A records D2 and commits.
5. The billing transaction, still open, reads with the three-argument form (`now()`).

| | the billing transaction | a new transaction |
|---|---|---|
| -30 r4 | **D1 and D2, both within, no error** | D2 |
| `tally` without -30 (-16's read) | D2 | D2 |

Both corrections were committed before the read, and no committed state ever held both rows. D1's void is stamped after the billing transaction began (so D1 counts as live), and D2's row is stamped before it. Districts stack, so the group check has nothing to refuse.
- L7(a) speaks only of "a replay" differing "from a live read made then". Here the live read is the wrong one, and a replay at that instant repeats it.
- L7's first remedy, that the bill records what it used, would record two district taxes as what the bill saw.
- Only the second remedy covers this: a bill computed at an instant that every writer begun by then has finished.
- It is a regression from -16's read. It has been there since r1, when the three-argument form became the four-argument form at `now()`.

**(ii) The same order on one place refuses at `now()` (executed).** The first record said outside at an unknown distance; the second says outside at 4 miles. The billing transaction gets 21000, and a new transaction answers `outside / 4.000`. The writer itself can meet it too: A began, B voided the row and committed, and A re-records the place and reads its own premise at `now()`, which refuses (**executed**). So the answer to "can the check refuse a live-consistent premise at `now()`?" is yes, in a transaction begun inside the window. The refusal is right (better than r3's two answers), but it is not only "a past read", which is how the plan titles it. A new transaction is the retry.

**(iii) (a) names too few cases.** It says a replay "drops one whose close or void began before the row was recorded". The ordinary case is a row recorded long before. Each was **executed** with one ordinary writer and one bill:

| the writer open at the bill's instant | live read | replay at the same instant |
|---|---|---|
| voids an old district row | `OP-D1, TX` | `TX` |
| closes an old district row | `OP-D1, TX` | `TX` |
| changes the premise's state to NM | `TX` | refused, P0002 (NM's place is not known there) |

In the first case the row was recorded at 22:14:01.2, the void was stamped 22:14:04.4, and the bill ran at 22:14:05.7. The row predates the void, so (a) as worded says this cannot happen. The third is a refusal that (b) does not list.

**Why it does not block.** (i) needs three overlapping transactions on one premise, and every case is in the family L7's first sentence states. The permanent cure is already assigned to the core.

**Fix (wording, plus the board's stamps item, which repeats the narrow form):**
- (a) becomes: a read at such an instant can silently differ from one made earlier or later at the same instant. It depends on whether a write whose transaction began by the instant (a row, a close, a void, or a change of the premise's state) had committed when the read ran.
- Add (c): the read at `now()` is such a read. In a transaction begun between the two writers, it can answer both the voided row and its replacement (two stacking districts), or refuse with 21000. A new transaction answers.
- Remedy: the bill's record is what the bill *used*, not proof that it was right. Only an instant every writer has finished settles the answer.
- The three-argument form's comment says "as known now". Say "as known when the transaction began".

A schema alternative, not measured and not recommended for -30: have the three-argument form refuse when a membership or place it answers was closed or voided after `now()`. That would refuse a long billing run on every ordinary correction made during it.

### S2. Mutation N53 no longer does the damage its label names. The own-rows clause took that over, and that clause is testable after all

N53 removes `v_now <> v_locked` and is labelled "a place row committed while the levy waited trusted unlocked". Race test on clones (**executed**):

| mutation | R5 | damage |
|---|---|---|
| N53 alone | FAIL [waited]: B **refused**, 23514 "in force over the whole" | none: no levy on R30-C |
| own-rows clause alone removed | PASS | none |
| both removed | FAIL [waited]: B exit 0 | a levy on R30-C whose successor row was never locked |

So since r4 the two guards back each other up. The re-read now decides only *how* the writer is refused (40001, retry, against a misleading 23514). Its mutation is caught for the wrong SQLSTATE, not for the damage. The statement "no mutation removes the own-rows clause: the window is between two statements" is also no longer accurate: with the re-read gone, R5's window reaches it.

Fix: relabel N53 ("the writer told its place is not in force, not to retry"), and add N53b with EXTRA removing both, at `RACE:R5:waited`.

### S3. A broken leg can still be read as a catch

`verdict` calls a leg BROKEN only when A fails, when psql exits other than 0 or 3, or when B exits 3 with no ERROR. Any *other* SQL error of B's is FAIL. The R6/R7 read (and R4's) has no status check at all. On a clone with frozen r4 **unmutated** (**executed**):
- An unrelated trigger makes R1's B fail with 42501. Output: `FAIL R1 [nowait]: … (exit 3): ERROR: 42501`. By the runner's `sed`, that is N52's named catch.
- The function renamed away (42883) gives `FAIL R6 [read]: ERROR: 42883` (N65's catch), and the same at R7 (the leg and reason N64 names). A dropped connection in that read would print the same (**predicted**).

The recorded catches are sound. I ran all five, and four do their damage:
- **N52:** R1 exit 0, no wait. R30-A ends 2026-06-01 under a live levy, so `R1:nowait` is the damage it claims.
- **N54:** R3 exit 0.
- **N64:** R7 reads `outside,within`.
- **N65:** R6 reads `within,within`.
- N53 is S2, and it shows why the gap matters: a refusal was read as a catch.

A sequential leg cannot be read as a catch:
- Right but never seen waiting prints SEQUENTIAL.
- In the reverse order, A itself is refused in R1 and R2, which is BROKEN.
- R5 reversed would print `[nowait]`, which N53 does not name (**predicted**).

Fix: print the outcome in the reason, as `nowait:committed`, `waited:committed` or `waited:<SQLSTATE>`, and have each RACE mutation name it. For R6, R7 and R4, any ERROR other than the leg's own expected SQLSTATE is BROKEN.

### S4. The kind half of "one place is its kind and code" is untested

Mutations by hand (**executed**) against batteries -30 and -16:
- `GROUP BY l.kind, l.code` reduced to `l.code`: both batteries pass.
- `count(DISTINCT (l.kind, l.code))` reduced to `l.code`: both pass.

Neither is idle. City, limited-purpose and extraterritorial codes share one pattern, and the batteries' city codes are names. A premise within a limited-purpose area and outside the city of the same code is an ordinary premise. Frozen r4 answers it correctly: `municipality OP-CITY outside, limited_purpose_area OP-CITY within` (**executed**). With the first mutation it would be refused at `now()` (**predicted**).

Fix: give M12c's limited-purpose area its city's code (or add one that has it), and add the two mutations. For the second, the check is two within places of one group and one code, of different kinds, as known a moment ago: refused as two places.

---

## 4. The brief's other questions

- **Do agreeing repeats mislead?** No (**read**). An answer is the id, relation and distance. Code, name and specificity follow from the id. The group is the kind's and is not returned. Evidence and dates are not returned either. Distances are `numeric(8,3)`, so equal values are one value. NULL is distinct from 4 in the composite count: 21000 (**executed**).
- **Is anything legitimate refused by the kind-and-code identity?** Not outside the window. `places_no_overlap` holds one row per kind, state and code on a date, and `no_repeat` holds one live membership per place. The check's `state_code = v_state` supplies the state.
- **Do the two checks and the main read stay in step?** Yes, as written; I compared them line by line. Mutating each filter of the check alone (**executed**):
  - Caught in battery -30: the premise, created, void (dropped, and NULL-only), membership range and end, and place end legs. The axis leg is caught in battery -16 only.
  - Uncaught by both batteries: `p.created_at`, the place range as a whole, and `p.state_code`. They are the read's stated defence in depth. The main read's `p.created_at` and `p.state_code` are equally uncaught, and that is not new.
- **L1–L6 do not block. L7 is S1.**
- **Does a round-4 change open a new path?** The only new path is refusals inside L7's window, where r3 answered twice. The own-rows clause cannot refuse an ordinary levy (the battery's L group and R1–R5 pass, **executed**).

## 5. Notes

**N1. The state's own row is outside the "more than one answer" rule** (**predicted**). `SELECT p.id INTO v_state_place` takes any one row if two successive rows of a state are both known at the instant, and returns it silently. The levy read keys on kind and code, so no rate changes; the returned `place_id` could. The comment says the read refuses "one with more than one answer for one place", so the state is an unstated exception. One clause of comment is enough: a state's succession is the platform's, and rare.

**N2. The two 21000s are not retryable classes**, yet at `now()` the remedy is to retry in a new transaction (S1 ii). Say so in the read's comment or the 40001 contract.

**N3.** C5 of the preconditions, the older-tests diff and the timing check of battery -22 were not re-examined (unchanged, or restricted).

Probe scripts (scratch, not repo files): `mut.py`, `mut2.py` (filters), `rm.py`, `rm2.py` (race mutations), `p1.sh` (one writer and one bill; the writer's own read; same code in two kinds), `p2.sh` (three sessions), in `/private/tmp/claude-501/-Users-ryanscomputer-code-tally-utility-rates/690a7128-f07b-44e6-8980-a85eead718c4/scratchpad/`.
