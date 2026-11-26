# v5.4.2-25 r4 — Fable's review (disputes, round-3 findings fixed)

**Date:** 2026-11-25. **Reviewer:** Fable (claude-fable-5-2). **Verdict: ready** — no blocking item. One should-fix (S1, executed): the new combined record keeps the more protective of the two documents section by section, and inside two sections (stages, subjects) that still drops something the utility's own policy gives. It never goes below the law. Fix it before the mirror, or name it as a residual and correct the comment that says the law "takes nothing the tariff gives".

**Frozen files:** the ten md5s and the brief's own md5 match. Reviewed only those copies; read my own `fable-r3.md`, the r4 plan in full and `r3-to-r4.diff` in full; did not read any `opus-*` or `codex-*` file. Read the PATCH-LESSONS index and the sections on count guards and lock handshakes, lock order as a rule, constraint-trigger name order, checks that name their own guard, and race catches.

**Reproduced** (clones of `tally`, TEMP revoked from PUBLIC, `tally_app`, `tally_core`; frozen patch applied strictly, `search_path=''`, `check_function_bodies=on`):
- strict apply succeeded on both clones; the second run said "already applied (disputes exists); nothing to do";
- `battery-25-frozen-r4.sql` on `rv25fable`: 296 PASS, 0 FAIL, rolled back;
- `disputes-25-frozen-r4.sh` on a separate clone (`rv25fable_race`): DR1–DR15, 26 PASS, rc 0;
- `terms-25.py` (live copy, md5 equal to the frozen one and to r3's): 0 failures;
- `assert_dispute_guard_invariants()` passes; the catalog's hashes of `enforce_dispute_reading_released` (`a04b43a9…`) and `dispute_terms_combined` (`29d12a2b…`) are the manifest's.

Not run, per the brief: `mutations-25.py`, `migration-25.py`, `ci.sh`. No role created, dropped or altered (probes used `SET ROLE` only). Both clones and my files in the container are dropped. `tally`, `sql/tu.sql` and the repo are untouched (this file is my only write).

How the probes ran: single-session probes were appended to a copy of the frozen battery before its final line, inside its one rolled-back transaction, on the battery's own "law tightens after the tariff" fixture (`tight_sql`), as the owner like the battery's D8 checks. Direct calls of the two pure functions used the seeded 16 TAC 7.45 row and the battery's tariff document. The two-session probe used committed rows on the race script's tenant in the race clone, as `tally_app` under `app.user_id`.

---

## B — blocking

None.

---

## S — should fix

### S1. The combined record replaces a whole section with the law's, so a tightened law still takes away what the utility's policy adds inside that section — executed

This is the other half of round 3's "a tightened law drops what the utility's policy added". r4 fixed it between sections (the policy's later shelter end and smaller must-pay survive; D8g, D8j). Inside a section it is unfixed for the two sections that are lists.

`dispute_terms_combined` takes each section the comparator names and overwrites the policy's section with the law's, whole. For blocks and duties it takes the union instead, which is right. For stages and subjects the whole-section swap loses the policy's extras:

```
PA  stages, through the tables (the battery's D8 fixture, with a policy that has 7.45's two stages
    and then its own governing-body appeal; the law then tightens the regulator from 15 days to 10)
      policy's stages:            designated_employee, regulator, governing_body
      comparator finding:         stages (the regulator's 15 days is slower than 10)
      combined document's stages: designated_employee, regulator          <- the appeal is gone
      determination citing policy + law:   admitted
      stage_entered s2 regulator:          admitted
      stage_entered s3 governing_body:     23514 "... is not a stage of the live determination's document ... [D5b]"

PC  stages, filing window (direct call): law stage 2 filed within 30 days of the prior decision, decided in 10;
    policy stage 2 has no filing deadline, decided in 15
      combined stage 2: file_within 30 days from prior_decision, decide_within 10 days
      (the customer gains the quicker decision and loses the open filing window the policy promised)

PB  subjects (direct call): law admits calculation + meter_accuracy; policy admits calculation + deposit
      combined subjects: listed [calculation, meter_accuracy]             <- deposit is gone
```

PA is the one that reaches a record: the customer appeals to the city council under the policy still in force, and the database refuses the event that says so. Before the law tightened, the same policy admitted that event. Nothing here goes below the law, so "never looser than the law" holds; what fails is "fail toward protection", and the function's comment ("a law that tightened after the tariff was written takes nothing the tariff gives") and the plan's item 2 ("every block either document gives") claim more than is built.

It needs a law that tightens after a policy with extras of its own was written; no seeded row is in that position.

**Settle by rule (fail toward protection), and measure the fix before folding it:**
- subjects: admit what either admits (the union of `dispute_subjects_admitted` of both), as blocks and duties already do;
- stages: the law's stages, each with the wider of the two filing windows and the quicker of the two decisions where the policy's stage at that place is of the same decider and comparable; then the policy's own stages after the law's last (what the comparator already admits after the law's last, N9i). Where the policy's stage at a place is of another decider, the law's stage alone.
- or keep the code and say so: a residual, the comment corrected, and a line in the application contracts that under a combined record the policy's own later stages are not recordable.

Either way add the case to the battery: D8j checks one replaced section (stages) on a fixture where the policy has no extra inside it, so M147 ("the law's sections never replace the tariff's looser ones") is caught there and nothing tests what a replacement loses.

---

## N — notes

- **N1. My round-3 findings (executed).** S1 (the reading lock too strong) is closed: `FOR NO KEY UPDATE`, the hash in the manifest changed with it, DR14 passes (two clerks each open and withdraw a dispute on one reading: the second waits, then commits, no 40P01), DR13 and DR13c still refuse the second close [T2c] at the forced check and at B's own COMMIT. I did not re-time the plain wait behind a billing run's key-share lock; it is the one-word change I measured in round 3 (0 s). S2 (a policy stage in front of the law's) is closed: the law's stages are the policy's first, in order, with nothing between (N9g, N9h refused; N9i, N9j admitted), which also closes the "prior decision" shift. N7's first half (the determination guard's comment) and N8 (the sequence's settings, H16b4) are closed. N7's second half is not taken: the table comment of `dispute_amount_lines` still does not say lines are numbered.
- **N2. A third deadlock, not one of the two the header names — executed.** The header says two deadlocks are admitted (a close against the reading's status move; two closes of two readings in opposite order) and "no other is known". Any transaction that edits the reading at all and then writes to one of its disputes is the same reverse order, not only a status move:
  ```
  A: BEGIN; withdraw dispute DX (names reading R); (3 s); COMMIT     -- at commit wants R FOR NO KEY UPDATE
  X (1 s later): BEGIN; UPDATE meter_readings SET notes = ... WHERE id = R;   -- holds R's row
                 record an amount on DX                                        -- waits for DX's lock (A holds it)
  -> A: ERROR deadlock detected (40P01), "while locking tuple ... meter_readings ... FOR NO KEY UPDATE"
     X committed; end state: reading active with the note, dispute open with the amount (consistent)
  ```
  "Writers retry 40P01" covers it. Word the header as the rule the lesson `lock-order-as-a-rule` asks for: a closing transaction takes the reading's row last; any transaction that updates a reading (any column) and then takes a lock of one of its disputes is in the reverse order and can deadlock with a close. Drop "no other is known".
- **N3. The deadlock schedule itself has no race leg.** The plan promised the close against the reading's move "in both orders". DR15 is the order that waits and is refused [T2c]; DR15b is two clerks each closing and moving. The order that deadlocks (A closes the only open dispute and holds, B moves the reading out) is not a leg. I ran it in round 3 on the stronger lock (both lose, end state disputed and open); the lighter lock still conflicts with the status UPDATE, so nothing changes. Add the leg with its end state, or drop "both orders" from the plan.
- **N4. The combined record otherwise does what it says — executed.** Every prefix the comparator can write (blocks, duties, stages, subjects, shelter_earned, shelter_ends, must_pay) is the document's own top-level key, so the split on the first colon names a real section; I ran a replacement through each of the five single sections and the union through both lists. A not-comparable pair falls to the law's section (a policy sheltering "within 20 days of issue" against the law's "before delinquency" gives the law's; a policy withholding cap against the law's average-usage cap gives the law's; a policy ending "through the regulator's close" against the law's day 60 gives the law's day 60). That is the floor, and the only choice a comparator that cannot rank them allows; say so in the comment, since the last one may read as a loss to the utility. A policy no looser in every respect comes back unchanged apart from its block and duty codes being sorted. A NULL section cannot arise: both schemas require every section the comparator names, and if one did, the result is NULL and [D4g] refuses the record. The law's sections carry the law's `citation` keys and ids into the combined document, so it validates against neither schema; nothing validates it, and the core reads it as data.
- **N5. Under a combined record the stage ids are the law's.** The event guard reads stages from `dispute_determination_terms`, so a stage event names the law's stage id whenever the stages section was replaced. The fixture's ids coincide (s1, s2 in both). An application contract line: the application takes a dispute's stages, must-pay component and blocks from `dispute_determination_terms` for the live determination, never from the policy row.
- **N6. The grant of `dispute_tariff_compare` to `tally_core` is safe — executed.** It is invoker-rights, STABLE, reads only the arguments and `dispute_subjects` (which the core already reads), and writes nothing; `tally_core` called the combination on the battery's documents. The guard invariant pins both functions' grants.
- **N7. The decision against Opus N2 (a policy stage after the law's final stage is admitted) is not wrong by a standing rule.** A stage after the law's last delays none of the law's stages and shortens no shelter; under a shelter that ends at resolution it lengthens it. What the law's final decision gave the customer cannot be taken back by a later policy stage, but that is the core's evaluation, not a comparison of documents. Write that sentence into the application contracts at the mirror.
- **N8. One consequence of "nothing between" — executed on the comparator.** A policy has no class, and is compared with every class's law row. If two classes of one state had different stage lists (say employee–regulator for one and employee–governing body–regulator for the other), no policy can satisfy both: 7.45's own stages got one finding, the other class's stages got one finding. The utility then has no policy and the law alone is cited, which fails toward the law. No seeded row is affected (the unprotected class has no stages). A sentence in the residuals is enough.
- **N9. Paths around the new rule.** With a policy in force, the law alone is refused [D4q] whatever the policy's looseness (D8f); the policy with only its own blocks is refused [D4h] (D8e); the law's last day under a combined document that ends at resolution is refused [D4s] (D8k). The guards are `ENABLE ALWAYS`, so the owner's load meets them too; a session that cannot see the policy row gets [D4f]. The reader returns recorded fields only, so it is unaffected by the combination. The combination is a function of two immutable rows, so a record checked today reads the same later — as long as `dispute_tariff_compare` itself is not changed by a later patch; a change to it re-reads every combined record, which is worth a line beside the function.
- **N10. Tests.** New checks have both sides (D8e/D8f/D8k against D8g; N9g/N9h against N9i/N9j; DR13c beside DR13). M153 (back to `FOR UPDATE`) is tied to DR14, which is the schedule that tells the two lock strengths apart. Missing: S1's cases; N3's leg; a check that the combination handles a replaced section other than stages (the code path is one generic line, so a note). `v_pos` in the comparator is now assigned and never read.
- **N11. -17's template and -23's seal.** Battery P and H checks pass. `r3-to-r4.diff` has no hunk inside `assert_seal_role_invariants`. The manifest hunks are all in the guard invariant: four changed function hashes, one new function (body, settings, grants), the comparator's grant, and the owner and sequence settings added to each table line.
- **N12. Residuals R1–R8.** None blocking.
