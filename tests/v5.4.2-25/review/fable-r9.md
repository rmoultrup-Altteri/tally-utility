# v5.4.2-25 r9 — Fable's review (one paragraph of residual R10, diff only)

**Date:** 2026-11-27. **Reviewer:** Fable (claude-fable-5-2). **Verdict: ready.** Nothing blocking and nothing to fix. The round changes one comment paragraph in the patch header (residual R10) and nothing else: a database built from r9 has the same schema as one built from r8, to the line. Every clause of the new paragraph is true of the code and of the seeded law rows. Three notes, none asking for a change.

**Frozen files:** the ten md5s and the brief's own md5 match. `r8-to-r9.diff` (37 lines) is the true diff of the frozen r8 and r9 patches (regenerated and compared), and the live patch `sql/v5.4.2-25-disputes.sql` is byte-identical to frozen r9. The battery, races, mutation runner, terms and migration scripts, filler and both seed files are byte-identical to their r8 copies (`cmp`). Read: the brief, the r9 plan, the "Round 8 reviewed" section of the r8 plan, the diff, `dispute_terms_combined` in frozen r9 (lines 2745–2847), my own `fable-r8.md`. Did not read any `opus-*` or `codex-*` file.

**Reproduced** (clone `rv25fable` of `tally`, none left over; TEMP revoked from PUBLIC, `tally_app`, `tally_core`; `search_path=''`, `check_function_bodies=on`, `ON_ERROR_STOP=1`):
- frozen r9 applied with no error output; the second run said "already applied (disputes exists); nothing to do". (My wrapper did not capture psql's exit status for the applies; the evidence is no error line under ON_ERROR_STOP, the skip marker on the second run, and the complete schema in the dump below.)
- `battery-25-frozen-r9.sql` with my probes appended after D9u: psql exit 0, 351 PASS, 0 FAIL, "battery-25: all checks passed", rolled back.

Not run, per the brief: `mutations-25.py`, `tests/ci.sh`; also not run: the races, `terms-25.py`, `migration-25.py` (byte-identical to r8, and no function body changed, N1). No role created, dropped or altered. The clone and my files in the container are dropped; `tally`, `sql/tu.sql` and the repo are untouched (this file is my only write). No container started.

How the probes ran: appended to a copy of the frozen r9 battery after D9u, inside its one rolled-back transaction, as the owner, on its own fixtures (`combo`, `tdoc`, the seeded 7.45 document in `k25`). Stage lists below are id/decider/final.

---

## B — blocking

None.

## S — should fix

None.

---

## N — notes

### N1. Nothing outside the R10 paragraph changed — executed

Applied frozen r8 to a fresh clone, dumped it, dropped it, applied frozen r9 to a fresh clone and dumped that (`pg_dump --schema-only`, 59,351 lines each). The only differing lines are pg_dump's own random session token (lines 5 and 59350). So every function body, comment on an object, trigger, table, grant, policy and the manifest's hash lists are the same; the changed paragraph is a SQL comment in the header that never reaches the database. In the text, the diff has one hunk (header lines 172–192). The header's "Tests" line just below it (351 checks, 199 mutations) is unchanged and still right.

### N2. R10 is true in every clause — executed

Clause by clause.

**"at each of the law's places the combined stage takes the law's final flag, either way."** Every policy stage list of one to three stages over three deciders (final only on the last stage, which is all the document check allows) combined with every law stage list of one to three stages with any flags: 20,124 pairs. In all of them the law's stages come first, in the law's order, each with the law's decider and the law's flag. Failures: 0.

**"(a) Wherever the policy's stage at a law place is final and the law's is not, the policy's finality is replaced."** 1,479 of the pairs are this case; the flag came back false in every one.

**"Earlier than the law's last stage the law's later stages follow, so the customer keeps every appeal the law gives."** 450 of those 1,479 are before the law's last stage; none lost a later law stage. By reading, this cannot fail: the function's first loop walks the law's stage list and emits one stage per law stage, whatever the policy holds, so every law stage after any place is always in the record. Named cases:

```
one-stage policy [employee T] under the seeded 7.45 [employee F, regulator T]
   -> s1/designated_employee/false, s2/regulator/true
policy [employee F, regulator T] under law [employee F, regulator F, governing_body T]   (the shorter older policy)
   -> s1/…/false, s2/regulator/false, s3/governing_body/true
policy [employee T] under law [employee F, governing_body F, regulator F]                 (two law stages follow; the law's last not final)
   -> s1/…/false, s2/governing_body/false, s3/regulator/false
```

**The brief's question: a law stage that the policy's list displaces.** Holds there too. Where the policy's stage at a law place is of another decider, the law's stage is written there (its id marked `law:` if the policy uses that id) and the policy's stage moves after the law's last, keeping its own flag:

```
policy [employee F, regulator T] under law [employee F, governing_body F, regulator F]
   -> s1/…/false, law:s2/governing_body/false, s3/regulator/false, s2/regulator/true
policy [employee F, governing_body T (id s3)] under law [employee F, governing_body F, regulator T (id s3)]
   -> s1/…/false, s3/governing_body/false, law:s3/regulator/true
policy [regulator T] under law [employee F, regulator T]
   -> law:s1/designated_employee/false, s2/regulator/true, s1/regulator/true
```

In the first and third, the policy's final stage is not at a law place, so it is not direction (a): nothing of the policy's is replaced, every law stage is present, and the policy's stage follows as one more (a final-flagged stage after the law's last, which is direction (b)'s shape and the contract covers it). In the second it is direction (a) before the law's last, and the law's regulator follows.

**"(7.45's employee stage is such a place, as for a shorter older policy under a longer later law)."** True: 7.45's first stage is the employee's, not final, with the regulator after it. The first line above is that place; the second is the shorter-policy case.

**"at the law's last stage which protects more depends on the customer."** `policy [employee F, regulator T] under law [employee F, regulator F] -> s1/…/false, s2/regulator/false`. No stage follows, so the customer who won there loses the utility being bound and the one who lost gains nothing more in the record. Because a policy's final stage can only be its last, no policy stage ever follows a replaced one at the law's last place.

**"(b) Where the law's stage is final and the policy's own appeal follows, the appeal is kept after it."** Unchanged from r8. `policy [employee F, regulator F, governing_body T] under 7.45 -> s1/…/false, s2/regulator/true, s3/governing_body/true`.

**"Both rest on the core reading final as binding on the utility, never ending an appeal the combined record keeps (a contract at the mirror)."** Accurate, and "rest on" is the better word: it says what the two directions depend on without claiming the contract makes direction (a) at the last stage neutral (my round-8 N3).

**"No seeded law row has a last stage that is not final."** Queried on the clone after applying r9:

```
law      e70bd714…  2004-07-12  2 stages: s1/designated_employee/false, s2/regulator/true   last final = true
law      2c475b0f…  2004-07-12  0 stages
law      f64798a5…  2004-07-12  0 stages
law      3a101af3…  2004-07-12  0 stages
default  10331275…  2026-11-22  0 stages
default  16ad65a8…  2026-11-22  0 stages
```

One law row has stages and its last is final; the other three and both platform defaults have none. The round-8 sentence that Opus and Codex found false ("no stage that is not final where a policy's could be") is gone.

### N3. One reading of the 7.45 parenthesis — predicted, no change asked

"7.45's employee stage is such a place" is a statement about the function, and as that it is true (first line of N2). It is not a statement that a utility can file such a policy today: in round 8 I found a one-stage final policy refused under 7.45 as looser than the law, and refused before 7.45's start because no law is known then (four refusals, my r8 N2). So with today's seeded rows the place is reached only by calling the combining function directly, or by a law row written later. The paragraph does not claim otherwise, and the plan chose this wording deliberately; I note it only so nobody reads the parenthesis as "this happens to a filed policy today".

### N4. My round-8 items

- **N3 (the contract settles direction (b) fully, and direction (a) at the last stage stays customer-dependent):** the new wording is consistent with it; still a point for the contract's wording at the mirror.
- **N7's two open contract sentences** are unchanged and still open until the application contract is written at the mirror, by design: (1) under an average-usage cap the customer pays the undisputed part plus the disputed part up to the average-usage amount; (2) `final` binds the utility and never ends an appeal the combined record keeps.
- Everything else in my round-8 review was closed there, and nothing it rested on changed (N1).

### N5. Housekeeping, not about the patch

The same two `crystaldba/postgres-mcp` containers as in round 8 were running (`pgmcp-41600-…`, `pgmcp-44623-…`). I did not start or stop them. `git status` shows three untracked files in `codex-r9-probes/`; they are not mine and I did not open them.
