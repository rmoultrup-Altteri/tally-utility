# Opus review: v5.4.2-25 r3 (disputes, round-2 findings fixed)

**Date:** 2026-11-25. **Reviewer:** Opus. **Round:** 3.
**Verdict: not yet.** Nothing is blocking. Two should-fix items remain:
- **S1:** when the law tightens in one respect, D4r now drops every protection the tariff added in other respects.
- **S2:** the new reading lock is stronger than it needs to be (FOR UPDATE). It stalls a close behind any writer that references the reading, and it adds a deadlock outside the one the header admits.

A third should-fix item (S3: a stage inserted between two law stages) has no live law row that triggers it today. Each fix is a few lines.

## Hashes

All ten frozen files match the brief: patch `9d2d3ed7…`, battery `18fde97b…`, races `0c13f909…`, mutations `99dbb3b5…`, terms `83d14843…`, migration `55d80759…`, fill-manifest `2fe45983…`, law file `deb66829…`, seed `3832a44f…`, diff `fd6232e4…`. The brief's own md5 matches its `.md5` (`cbd40812…`).

## What I ran (scratch `rv25opus`, TEMP revoked from PUBLIC, tally_app and tally_core; dropped at the end, container files removed)

- **Strict apply, twice:** clean. The second run prints "already applied". Reproduced.
- **battery-25 (frozen r3):** 286 PASS, rc 0. Reproduced.
- **races (frozen r3), on my clone:** DR1–DR13, 18 PASS. Reproduced.
- **Invariants:** `assert_seal_role_invariants()`, `assert_dispute_guard_invariants()` and `assert_rule_table_invariants()` pass on the patched clone. r3 does not touch the carried seal body. I diffed it in r2: four intended edits only.
- **Sequence pin (item 5):** in a rolled-back transaction, `GRANT UPDATE ON SEQUENCE dispute_record_seq TO tally_app`. The guard invariant then raises and names the sequence's ACL line. A column DEFAULT on `dispute_amount_lines.record_seq` is not caught, but the BEFORE trigger overwrites the value, so this is harmless.
- **Probes:**
  - the comparator called directly;
  - three two-session schedules on committed fixtures;
  - one battery prefix (lines 1–1336) plus my statement, rolled back, on a fresh re-clone (the races' committed rows break D7p2, as in r2);
  - I also tried one variant of the release check (FOR NO KEY UPDATE) on my clone, to measure the fix suggested in S2.
- Not run: `mutations-25.py`, `ci.sh` (the brief forbids both).

## My round-2 findings: closed?

| r2 | What | r3 | How I know |
|---|---|---|---|
| S1 | The law tightens after the tariff, and D4q forced the looser tariff | **Closed, but over-corrects** (S1 below) | D8e/D8f pass. The law row cited is the one compared, under `rule_law_row_cite`'s shared lock, before the comparison. |
| S2 | Two closes of one reading's disputes leave it disputed | **Closed** | DR13 passes. At READ COMMITTED (enforced by `dispute_lock` on every event), the second check waits on the reading, re-reads and refuses. Lock strength: S2 below. |
| N1 | Header lock order | Closed | Items 2 and 3 name the default and the reading. |
| N2 | A reading-only dispute under "from issue" | Closed as a residual | R5 says so. |
| N3 | A line after the withdrawal, same transaction | **Closed** | `record_seq` on lines, stamped in an ENABLE ALWAYS BEFORE trigger (the caller's value is overwritten). The AFTER trigger judges by the amount's dispute. D8c/D8d pass. Lines must be in the amount's transaction (D2f), and that transaction holds the dispute's lock, so no concurrent close can interleave. |
| N4 | Stages compared by decider only | **Closed, with one gap** (S3) | P1.1 and P1.5 below are refused as they should be. |
| N5 | State, service and system are the caller's | Plan corrected | Bound by the service profile. Agreed. |
| N6 | "Issue" = bill date | Closed | R5's text. |
| N7–N10 | | Unchanged as noted | No change needed. |

Codex B1 (a row given the event's id): the id exclusion is gone. Ids from other tables can no longer exempt a row, and an event never compares with itself, because the comparison is strict `<`. D8a/D8b pass.

---

## S — should fix

### S1. D4r replaces the whole tariff with the law when the law tightens in one respect, so the record drops the tariff's other protections (executed)

**What happens.** The comparator returns a non-empty list if the tariff is looser in *any* dimension. D4r then requires the law row alone, and D4h, D4p and D4s check the record against the law's document only. So when the law tightens in one respect (for example, it adds a block), the record loses everything the utility's own tariff gave beyond the law.

**Evidence (the battery's own D8 fixture, executed).**
- T2's tariff (`tdoc()`) blocks `notice_issue, disconnect_order, disconnect_execute, late_fee`. Its shelter ends at the **resolution**, and its must-pay is `undisputed_charges`.
- The stricter law adds `credit_reporting`. Its shelter ends at the **earlier of resolution and 60 days**.
- D8f: the only admitted record is the law alone. Its shelter ends **2026-08-08**, and its blocks are the law's four, without `notice_issue`.
- My probe: the same law-alone record, with the union of blocks (the law's four plus `notice_issue`), is REFUSED 23514 [D4h].

So the customer's shelter, which the utility's own policy holds until the dispute is resolved, is recorded as ending on day 60. The pre-disconnection notice block is gone as well. The law change only asked for one more block. This is the r2 S1 harm, now in the other direction: the record is narrower than a document that binds the utility.

**Fix (fail toward protection; no money question).** When D4r applies, the record should be no looser than either document. The smallest change:
- cite both (the row already carries `rule_id` and `tariff_id`);
- check blocks against the **union** of both documents' blocks;
- take the shelter's end from the later of the two (a tariff ending at resolution ends no sooner than earlier-of-resolution-and-days, which the comparator already orders);
- take must-pay from the one that asks less, where comparable;
- refuse any pair that is not comparable.

If merging is felt to be the core's job, the minimum is:
- D4h admits the union of blocks under D4r;
- D4p/D4s accept the tariff's end when it is later.

Tests: D8f with the union admitted, and with the law's blocks alone refused.

### S2. The reading lock is FOR UPDATE: it waits on every writer that references the reading, and it adds a deadlock beyond "close against the reading's move" (executed)

**What happens.**
- `FOR UPDATE` conflicts with `FOR KEY SHARE`. That is the lock every foreign-key insert takes on the row it references.
- Twelve constraints reference `meter_readings`, including `invoice_line_items`, `billing_run_meters`, `meter_photos`, `read_cycle_meters`, `read_validation_exceptions`, `disputes.reading_id` and a replacement reading's `replaces_read_id`.
- So a dispute close's commit now waits for any open transaction that has inserted such a row, for example a billing run writing line items for that reading.
- The only conflict the check needs is with another close (it takes the same lock) and with the reading's move (an UPDATE, so `FOR NO KEY UPDATE`). `FOR NO KEY UPDATE` gives exactly those two, and does not conflict with key-share.

**Probes (two sessions, as tally_app, committed fixtures):**
- **P3, stall.** S1 inserts a `meter_photos` row for reading R3 and holds for 4 s. S2 withdraws a dispute of R3 (a sibling stays open) and commits. `pg_stat_activity` shows S2's `COMMIT` waiting on `transactionid`, blocked by S1. S2 commits only when S1 does (23:43:36.551, three milliseconds after S1).
- **P4, deadlock.** S1 inserts a photo of R3, then records an amount on dispute B6. S2 withdraws B6 (the last open dispute), moves R3 to `active` in the same transaction (the correct flow), and commits.
  - Result: **40P01**. S1 waits on B6's advisory lock, and S2's commit-time FOR UPDATE waits on S1's key-share.
  - This is not "a close against the reading's own move". S1 never moves the reading.
- **Measured fix.** I replaced `FOR UPDATE` with `FOR NO KEY UPDATE` in my clone only:
  - P4 again: no deadlock. S2 commits, and S1's amount is then refused [D2e], which is correct.
  - DR13's schedule again: the second close still waits on the reading and is refused [T2c]. The serialisation is kept.

**Fix.**
- Change `FOR UPDATE` to `FOR NO KEY UPDATE` in `enforce_dispute_reading_released`, and say so in rule 3 of the header.
- Add a race: a key-share holder on the reading, and a close that does not wait on it.

### S3. A tariff may insert a stage between two law stages, which moves the next stage's "from the prior decision" anchor (executed against the comparator; no live law row is affected)

**What happens.**
- The new matcher lets other tariff stages sit between matched law stages.
- A stage filed "within N days of the prior decision" counts from the stage before it in the document (L2c fixes that meaning).
- If the tariff inserts a stage with no decision deadline in front of such a stage, the law's next stage may never open.

**Evidence (`dispute_tariff_compare` called directly, 7.45's row with its stages replaced):**

| | Law stages | Tariff stages | Result |
|---|---|---|---|
| P1.1 | 7.45 | regulator decides in 3650 days | problem (correct) |
| P1.5 | 7.45 | regulator before the designated employee | problem (correct) |
| P1.7 | regulator, file `none` | file within 3650 days of issue | problem (correct) |
| P1.6 | file 30 days from issue, decide `none` | file `none`, decide 5 days | `{}` (correct) |
| **P1.3** | designated employee decides in 10 days; regulator filed within 30 days of the prior decision, decides in 15 | the same, plus a `governing_body` stage between them (file `none`, decide `none`) | **`{}`, admitted** |
| P1.2 | 7.45 as it is (regulator filed `none`) | a `governing_body` stage between (1 day to file, no decision deadline) | `{}` |

- In P1.3 the regulator's 30 days run from the governing body's decision, which has no deadline. Under the law they run from the utility's 10-day decision.
- In P1.2, harm depends on whether the core treats 7.45's regulator as reachable out of order. Today no law row files a stage from the prior decision (only the CPS tariff example does), so nothing live is affected.

**Fix (never looser).** When a law stage after the first files from `prior_decision`, require its match to be the tariff stage directly after the previous match (`j = v_pos + 1`). Add one test per side and a mutation.

---

## N — notes

- **N1. Two closes on two readings, in opposite order, deadlock (executed, P2).**
  - X withdraws a dispute of R1 (constraints IMMEDIATE), then one of R2. Y withdraws a dispute of R2, then one of R1.
  - Y gets **40P01** while locking R1's tuple. X commits. Both readings stay disputed under their open siblings, which is correct.
  - Without IMMEDIATE, the same happens only when the two commits run their deferred checks together.
  - The header's "Writers retry 40P01" covers it. But the function comment says "a close against the reading's own move can deadlock", as if that were the only case. Rule 3 should say the readings are not locked in id order.
- **N2. The law's `final` stage is not compared (executed, P1.4).** A tariff whose regulator stage is not final, followed by a utility `executive` stage after it, returns `{}`. A utility review after the regulator's final decision is probably the core's to read as void, but the comparator calls it "no looser". One line in the comment, or require that the law's final stage maps to the tariff's last stage.
- **N3. D4r/D4q read the tariff in force without its lock when it is not cited.** That tariff's terms are immutable. A concurrent close only makes a D4q refusal stale (fail closed, retried), and a concurrent back-dated tariff is R6. Not a defect.
- **N4. Lines and statement shapes.**
  - `record_seq` is stamped in BEFORE triggers in production order, and the guard runs AFTER ROW, ENABLE ALWAYS. So a multi-row insert, a writable CTE, COPY and a superuser in replica mode are all judged by the order the rows were produced.
  - A line produced before the withdrawal in one statement is "before", which is right.
  - I found no shape that records an amount, line, determination or event after a resolution (predicted from the code; D5r, D5r2 and D8a–D8d executed by the battery).
- **N5. Template and seals.**
  - -17's close floor and citation locks still order every citation in r3 (the D4r comparison runs after `rule_law_row_cite`).
  - -23's seal invariant passes, and r3 leaves its carried body unchanged.
- **N6. Tests.**
  - M145 (the lock removed) cannot tell FOR UPDATE from FOR NO KEY UPDATE. That is correct: both serialise the two closes. The S2 race above would pin the weaker one.
  - D8f's label ("the law alone is admitted, with the law's blocks") asserts the behaviour S1 questions. If S1 is accepted, D8f changes.
- **N7. Residuals R1–R8.** None is blocking. S1 is not a residual, because the database refuses the more protective record.
