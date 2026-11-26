# Opus review: v5.4.2-25 r4 (disputes, round-3 findings fixed)

**Date:** 2026-11-25. **Reviewer:** Opus. **Round:** 4.
**Verdict: not yet.** Nothing is blocking. One should-fix item remains:

- **S1.** The combined record takes a section from the law *whole* whenever the tariff is looser anywhere in that section. For the stages section this drops review stages and deadlines that only the tariff gives. In the probe, the tariff's appeal to the city council, admitted by r4's own rule N9i, cannot be recorded once the law tightens [D5b]. The subjects section loses what the tariff alone admits in the same way.

The fix is local to `dispute_terms_combined`. No seeded law row triggers it today. All three of my round-3 findings are closed.

## Hashes

All ten frozen files match the brief:

| File | md5 starts |
|---|---|
| patch | `dc738d92…` |
| battery | `557604c3…` |
| races | `cd393cfd…` |
| mutations | `3243d0b5…` |
| terms | `83d14843…` |
| migration | `55d80759…` |
| fill-manifest | `33802a5b…` |
| law file | `deb66829…` |
| seed | `3832a44f…` |
| diff | `9102047a…` |

The brief's own md5 matches its `.md5` (`ce97b1e2…`). The live copies are identical to the frozen ones.

## What I ran

I used two scratch clones of `tally`: `rv25opus` for the battery and probes, and `rv25opus_race` for the races. TEMP was revoked from PUBLIC, `tally_app` and `tally_core` on both. Both clones were dropped at the end and the container files removed.

- **Strict apply, twice, on each clone:** clean. The second run prints "already applied; nothing to do". Reproduced.
- **battery-25 (frozen r4):** 296 PASS, 0 FAIL, rc 0. Reproduced.
- **races (frozen r4), on the race clone:** 26 PASS, rc 0 (DR1 to DR15, including DR13c, DR14, DR15 and DR15b). Reproduced.
- **Invariants on the patched clone:** `assert_seal_role_invariants()`, `assert_dispute_guard_invariants()` and `assert_rule_table_invariants()` all pass.
- **Probes:**
  - `dispute_tariff_compare` and `dispute_terms_combined` called directly on hand-built documents, rolled back.
  - One battery prefix (lines 1 to 1421, through D8j) plus my statements on the real path, rolled back.
  - One two-session schedule as `tally_app` on the race clone's committed fixtures.
- **Not run:** `mutations-25.py` and `ci.sh`, which the brief forbids.

## My round-3 findings: closed?

| Round 3 | What it was | Round 4 | How I know |
|---|---|---|---|
| S1 | A tightened law dropped everything the tariff added | **Closed for blocks, duties, shelter end and must-pay; half-done for stages and subjects** (S1 below) | D8e, D8f, D8g, D8k and D8j pass. The tariff is now always cited where it is in force [D4q], and the record is checked against the combination. |
| S2 | The reading lock was FOR UPDATE | **Closed** | It is now `FOR NO KEY UPDATE` (`enforce_dispute_reading_released`). DR14 is the foreign-key shape: it passes, and M153 (back to FOR UPDATE) is caught by DR14. DR13 and DR13c still serialise two closes of one reading. |
| S3 | A tariff stage could sit between two law stages | **Closed** | The matcher is now `j = v_li`: the law's stage at place *i* must be the tariff's stage at place *i*. N9g and N9h are refused; N9i and N9j are admitted. |
| N1 | Deadlocks the header did not name | **Mostly closed** | The header and the function comment name two deadlocks. A third shape exists (N1 below). |
| N2 | A stage after the law's final stage | **Not changed, with a reason; I agree** | N2 below. |
| N6 | M145 could not tell the two lock strengths apart | **Closed** | M153 and DR14. |

---

## S — should fix

### S1. The combination replaces a whole section with the law's, so the record loses stages and subjects the tariff alone gives (executed)

**What happens.**
- `dispute_terms_combined` asks the comparator which sections the tariff is looser in, and replaces each of those sections whole with the law's (`jsonb_set(v_doc, ARRAY[v_section], v_law -> v_section)`).
- Only blocks and duties are merged, as the union of both documents.
- For a section that holds one value (shelter end, must-pay, shelter earned), "the law's where looser" is the right choice.
- For the stages and subjects sections, it is not. One finding anywhere in the section discards every part of it that the tariff gives beyond the law.
- The event guard checks a stage event against this combined document (`enforce_dispute_event`, the `stage_entered`/`decided` branch). So a stage the tariff gives and the law does not becomes unrecordable.

**Evidence: stages, on the real path (executed).** I took the battery prefix through D8j and added a tariff written under 7.45 with three stages:
1. the designated employee, who decides within 10 days;
2. the regulator, who decides within 15 days;
3. the governing body (the city council), filed within 30 days of the prior decision and decided within 30. Admitted under N9i, since it comes after the law's last stage.

Then I applied the battery's stricter law (the regulator decides within 10 days), and recorded the combined determination (both documents' blocks, no last day). It was admitted. Then:

| | Result |
|---|---|
| Tariff stages | `["designated_employee", "regulator", "governing_body"]` |
| Combined stages | the law's two only. The designated employee has **no deadline** (the tariff's 10 days are gone), the regulator has 10 days, and there is **no governing-body stage**. |
| `stage_entered` s3 before `governing_body`, as `tally_app` | **refused 23514 [D5b]**: "stage s3 … is not a stage of the live determination's document" |
| `stage_entered` s1 before `designated_employee` | admitted |

So a customer's appeal to the city council can no longer be recorded once the law tightens one deadline. That appeal is in the city's own tariff, which still binds the city, and r4's new N9i admits it. The utility's own 10-day promise on its first decision is also gone from the record. This is the round-3 S1 harm again, inside one section: the record is narrower than a document that binds the utility.

**Evidence: subjects (executed on the function; core-facing).**
- The law excludes `identity_theft`. The tariff excludes `tamper_finding` and admits everything else.
- The comparator names `subjects` (the tariff does not admit `tamper_finding`), so the combined subjects are the law's.
- `identity_theft`, which the tariff admits, is then not admitted (`dispute_subjects_admitted(...) @> '{identity_theft}'` = false).
- The database checks no subject against the document. But `dispute_determination_terms` is the document the core reads as "the document a determination cites", so the core is handed the narrower list.

**Fix (fail toward protection; no money question).**
- **Stages:** for each of the law's places *i*, keep the tariff's stage *i* when the comparator matched it: same decider, the wider filing window and the shorter decision window of the two. Otherwise take the law's stage *i*. Then append the tariff's stages after the law's last; N9i already admits them. Keep stage ids unique, and keep the `final` flag on the last stage only (L2d).
- **Subjects:** the union. A subject is admitted if either document admits it, and excluded only if both exclude it.
- **Tests:**
  - a D8 variant with the tariff's third stage: its stage event admitted, and the employee's 10 days kept;
  - a subjects case;
  - a mutation back to whole-section replacement for each.

**Lighter alternative.** If merging inside a section is felt to be the core's job, then at minimum:
- append the tariff's stages after the law's last to the combined stages, so the event guard admits them;
- say in the function comment that stages and subjects are taken whole from the law, and that the tariff's additions in those sections are the core's to honour.

---

## N — notes

### N1. A third deadlock shape: any UPDATE of the reading, then a dispute's lock, against a close (executed)

**Schedule (race clone, as `tally_app`).**
- Setup: reading R (`…25fc`) is disputed, and I added a second open dispute X on it, so a close needs no move.
- Session A updates R's note (an edit, not a status move) and holds 3 s. Then it records an amount on X.
- Session B, starting 1 s after A, withdraws X and commits.

**Result.**
- B's commit-time `FOR NO KEY UPDATE` waits on A's row lock.
- A's amount waits on X's advisory lock.
- **A gets 40P01.** B commits.
- The end state is right: the reading is disputed, its other dispute (`…263e`) is open, and X is withdrawn.

**What the header should say.** The header says the reading's own move "(an UPDATE of its status)" and two closes in opposite order are the two deadlocks admitted, and "No other is known". But any transaction that updates the reading's row, for any column (a clerk's note edit, a billing run locking the reading), and then takes one of its disputes' locks deadlocks against a close the same way.

That is harmless: the loser retries. But PATCH-LESSONS `lock-order-as-a-rule` asks for the rule, not a list of shapes. Suggested wording for rule 3: "a transaction that writes the reading's row before a lock of one of its disputes takes them in the reverse of a close's order, and can deadlock with it; writers retry 40P01".

### N2. The decision against my round-3 N2 (a stage after the law's final one) is right by the standing rules (predicted from the code)

- A stage after the law's last delays none of the law's stages.
- The database checks no outcome against a stage decision, so a later utility stage opens no record path that was not already open.
- A shelter that ends at resolution only lasts longer. Ends of "the earlier of resolution and N days", and ends at the regulator's close, are unaffected.

So no protection is lost, and "never looser" is not breached. One thing to carry into the application contracts at the mirror: under N9i a tariff may mark the regulator's stage `final: false`. The core must still treat the law's final decision as binding on the utility whatever stage follows.

S1 is the other side of the same decision: having admitted such a stage, the combined record should keep it.

### N3. The combined record relies on the comparator's message prefixes correctly (executed and read)

- Every finding the comparator writes begins with a section name and a colon: `blocks`, `duties`, `stages`, `subjects`, `shelter_earned`, `shelter_ends`, `must_pay`. Each is the document's own JSON key, and the law row's citation text comes after the colon.
- Every section is required in both schemas, so `v_law -> v_section` is never NULL. If a future message lost its prefix, `jsonb_set` would add a stray key (harmless). A NULL section would null the whole document, and D4g would then refuse (fail closed).
- A section ruled `unruled` in the law is never named, so the tariff's stays. That is right.
- Single-valued sections behave correctly in my direct calls:
  - a shelter-earned or must-pay pair that cannot be compared takes the law's, the floor;
  - shelter end "resolution" in the tariff against "earlier of resolution and 60 days" in the law keeps the tariff's (D8j).
- The comparator checks shelter end by days only, not by what the count starts from. That is fine, because the schema fixes the start to the bill's issue date for both documents.

### N4. Granting `dispute_tariff_compare` to `tally_core` is safe (read)

It is STABLE with invoker rights. It reads only the arguments and `dispute_subjects`, which `tally_core` can already read, and writes nothing. `dispute_terms_combined` has the same rights. The guard invariant pins both ACLs.

### N5. The combined record can change after it is recorded, if the subject list grows (predicted)

`dispute_subjects_admitted` with kind `any` reads the live `dispute_subjects` list. A new platform subject code can make the comparator newly name `subjects` for a tariff that lists codes, so a later event check recomputes a different subjects section. The stages, blocks, ends and must-pay a record is checked against do not depend on that list, so no check changes. Worth one line in the function comment.

### N6. Tests (read)

- **No test where the law's single-valued section wins.**
  - D8j covers the stages replaced and the tariff's shelter end and must-pay kept.
  - No check has the law's shelter end replacing the tariff's (for example, a tariff that ends at 30 days under a law of 60, then D4p at day 60) or the law's must-pay replacing the tariff's.
  - A mutation that replaced only a fixed list of sections, say `stages` alone, would survive M147 and D8j.
  - Add one D8 case for each of the shelter end and must-pay.
- **D8j's label asserts the behaviour S1 questions** (the law's stages taken whole). If S1 is accepted, D8j changes.
- **DR14 pins the weaker lock, as round 3 asked.** DR13c now closes on the real COMMIT.
- **D4f is now a real hidden tariff** (T3's, invisible to T1 under row security). D4f3, D4f4 and D4f5 test another state, service and system, each with its own mutation (M65c, M65d, M65e). Codex's round-2 point is closed.

### N7. Paths around the rules, the template and the seals (read; the battery and invariants executed)

- **The policy-in-force rule [D4q]** is simpler now. Where the law governs and a policy is in force on the received date, no tariff cited is refused. A tariff cited must be the utility's own for that state, service and system [D4f], in force [D4c] and cited under `rule_row_cite`.
  - I found no role, isolation level or statement shape that cites the law alone while a policy is in force.
  - At REPEATABLE READ, `dispute_lock` refuses (25000), as before.
  - A superuser history load runs the same ENABLE ALWAYS guards.
- **-17's template (the close floor and the citation locks):** still orders every citation. Both documents the combination reads are cited before it is computed.
- **-23's seals:** the invariant passes, and r4 does not touch the carried body.

### N8. The residuals R1–R8 (read)

r4 does not change them, and none is blocking. S1 is not a residual: the database refuses a stage event that a binding document gives.
