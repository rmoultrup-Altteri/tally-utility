# v5.4.2-25 r3 — Fable's review (disputes, round-2 findings fixed)

**Date:** 2026-11-25. **Reviewer:** Fable (claude-fable-5-2). **Verdict: ready** — no blocking item. Two should-fix items (S1, S2), both executed. S1 is a one-word change to the new reading lock that removes a deadlock and a wait I measured; S2 is a gap in the new stage comparison that reaches the harm round 2's item 4 set out to stop, by a different shape. Fix them before the mirror or name them as residuals; neither moves money or leaves a wrong record.

**Frozen files:** the ten md5s and the brief's own md5 match. Reviewed only those copies; read my own `fable-r2.md` and the r3 plan in full; did not read any `opus-*` or `codex-*` file. Read the PATCH-LESSONS index and the sections on count guards and lock handshakes, lock order as a rule, checks that lag inside one statement, and race catches.

**Reproduced on `rv25fable`** (clone of `tally`, TEMP revoked from PUBLIC, `tally_app`, `tally_core`; frozen patch applied strictly, `search_path=''`, `check_function_bodies=on`):
- strict apply succeeded; the second run said "already applied (disputes exists); nothing to do";
- `battery-25-frozen-r3.sql`: 286 PASS, 0 FAIL, rolled back;
- `disputes-25-frozen-r3.sh rv25fable`: DR1–DR13, 18 PASS (run twice, on two fresh clones);
- `terms-25.py` (live copy, md5 equal to the frozen one): 0 failures;
- `assert_dispute_guard_invariants()` passes on the applied clone; the function hash of the release check in the manifest (`22bc5bdb…`) is what the catalog holds.

Not run, per the brief: `mutations-25.py`, `migration-25.py`, `ci.sh`. No role created, dropped or altered. The clone and its files in the container are dropped. `tally`, `sql/tu.sql` and the repo are untouched (this file is my only write).

How the probes ran: single-session probes were appended to a copy of the frozen battery before its final line, inside its one rolled-back transaction, on the battery's own fixtures, as `tally_app` under `app.user_id` unless marked "owner". Two-session probes used committed rows on the race script's tenant in my clone. Where a probe held a commit open, it did so with a scratch deferred trigger in my clone (a three-second sleep queued after the release check), as in round 2.

---

## B — blocking

None.

---

## S — should fix

### S1. The new reading lock is stronger than it needs to be: it deadlocks with, and waits behind, anything that merely references the reading — executed, and the weaker lock measured

The commit-time release check takes the reading's row `FOR UPDATE`. That mode conflicts with the `FOR KEY SHARE` lock every foreign-key insert takes on the reading. Twelve foreign keys point at `meter_readings` (`disputes`, `invoice_line_items`, `billing_run_meters`, `adhoc_charges`, `meter_photos`, `read_cycle_meters`, `read_validation_exceptions` ×2, `meters`, and three self-references). So a transaction that has inserted any row naming the reading, and is still open, now stands in the way of a dispute's close.

Two things follow, both run on the frozen patch:

```
P2 (deadlock; the closer loses)
  reading R disputed; disputes D3, D4 open
  A: BEGIN; withdraw D3; (3 s); COMMIT
  X (1 s later): BEGIN; open a new dispute naming R   -- KEY SHARE on R
                 record an amount on D3                -- waits for D3's lock (A holds it)
  A's COMMIT: the release check wants R FOR UPDATE     -- waits for X
  -> A: ERROR deadlock detected (40P01); X committed; D3 still open with the new amount

P5 (plain wait)
  A: BEGIN; open a new dispute naming R; (6 s); COMMIT
  B (1 s later): BEGIN; withdraw D10; COMMIT
  -> B's COMMIT took 5 s (it waited for A to end)
```

P5 is the one that matters in practice: a billing run that has inserted `billing_run_meters` or `invoice_line_items` rows for the reading holds that key-share lock until the run's transaction ends, and a clerk's close of a dispute on that reading will not commit until then. Before r3 the close took no lock on `meter_readings` at all.

**Fix, measured:** `FOR NO KEY UPDATE` in place of `FOR UPDATE`. It still conflicts with itself and with every plain `UPDATE` of the reading, so it serialises exactly what r3 needs, and it does not conflict with key-share. I replaced the one word in my clone's function and re-ran:

```
P1 two closes of one reading, real commit path   -> second waits, then refused [T2c]; reading stays disputed under the open dispute  (same as frozen)
P2 as above                                      -> no deadlock: A commits; X's amount refused [D2e] (the right answer)
P5 as above                                      -> B commits at once (0 s)
P6 a close against the reading's own move        -> still deadlocks (40P01), end state consistent  (same as frozen)
```

The manifest hash of `enforce_dispute_reading_released` and the header's item 3 ("FOR UPDATE") change with it. Lesson `count-guards-need-lock-handshake` rule 2 is this family (do not take a lock stronger than the conflict you need on a row other writers touch routinely).

### S2. A tariff may put a stage of its own, with no deadline, in front of a stage the law gives the customer — executed

Round 2's item 4 was "a tariff can stretch the regulator's 15 days to 3,650". r3 compares each law stage with the tariff stage that matches it, in order — correct as far as it goes (see N3). But "other tariff stages may sit between", and nothing is asked of them. Direct calls to `dispute_tariff_compare` with the seeded 16 TAC 7.45 row (designated employee, then the regulator within 15 days):

```
C2  tariff: employee, MANAGER (no decision deadline), regulator 15 days              -> admitted
C3  tariff: employee, GOVERNING BODY (3,650 days to decide), regulator 15 days        -> admitted
C4  tariff: EXECUTIVE (file within 1 day of receipt) first, then employee, regulator  -> admitted
C9  law's regulator stage filed "30 days from the prior decision"; tariff keeps that
    wording but the prior decision is now a no-deadline manager's                     -> admitted
```

If the core reads stages as a sequence (each reached after the one before it), C2/C3 delay the regulator indefinitely and C4 puts a one-day filing gate in front of the law's whole process; C9 silently changes what "prior decision" means. The battery's N9g pins the admitted side with a 30-day manager stage, so "between" is deliberate; the unbounded case is not tested and not stated.

**Settle by rule (never looser; not comparable is refused):** either (a) the comparator refuses a tariff-only stage placed before a matched law stage unless it cannot delay it — simplest: tariff-only stages are admitted only after the law's last stage is matched — or (b) keep the comparator and write the other half down: a residual and an application contract that the core never makes a stage the law gives wait on, or be forfeited by, a tariff-only stage. (b) costs nothing in the schema; (a) would refuse N9g's fixture, so measure it. Either way add the unbounded case to the battery (C2 and C4 are one line each).

---

## N — notes

- **N1. My round-2 findings (executed).** S1 (two closes of one reading) is closed on the real commit path, not only under `SET CONSTRAINTS IMMEDIATE`: with the commit held open, the second close waits on the reading, then is refused [T2c]; the reading stays disputed under the open dispute (P1). S2 (the sequence's grants) is closed: `GRANT SELECT … TO tally_core`, `REVOKE USAGE … FROM tally_app` and a change of owner each fail the guard invariant (0LP01), beside the battery's `GRANT UPDATE` (H16b3). N3 (an end date under a policy ended by resolution) is closed [D4s], D8h. N2 and N4 are corrected in the plan and in residual R5 as the plan says. N11's header lines are corrected (counts 286 / 18 / 153; the default's lock named).
- **N2. The deadlock the header admits is not the only one — executed.** The function's comment names one (a close against the reading's own move). Two more exist: S1's, and this one, which no lock mode removes: two transactions each closing one dispute of each of two readings, in opposite order, take the two readings' locks at commit in opposite order (P3: one got 40P01, the other committed, both readings stayed disputed under their open disputes — consistent). "Writers retry 40P01" covers it. Say it in the header as a rule: the reading's row is the last lock a closing transaction takes, in the order its closing events were written; and the reading's move takes the reading's row *before* the disputes' locks (the reverse of items 1 and 3 — the header's numbered order does not say so; only the function comment does).
- **N3. The close against the reading's own move, both orders — executed (frozen function).** A closes the only open dispute and holds, B moves the reading out: A is the deadlock victim and B is then refused [T2] (the dispute is open again) — both lose, end state disputed/open, a retry of the proper flow works. A moves the reading into disputed and holds, B closes the only open dispute: B waits, then is refused [T2c]. Two clerks each closing the dispute and moving the reading out in one transaction: the second is refused [D5f], end state active/withdrawn. No schedule left a reading disputed with no open dispute. The plan's item 2 promised "both orders of close against the reading's own move" as tests; only DR13 (two closes) was built. Add the first schedule as a race leg, or drop the promise from the plan.
- **N4. The stage comparator otherwise does what it says — executed.** A law stage cannot be matched twice (two law stages of one decider against one tariff stage: refused) or out of order (N9f). Each `none` is compared toward the customer: tariff filing `none` is the widest, tariff decision `none` never satisfies a law deadline, law decision `none` asks nothing. Days compare only from the same anchor (30 from receipt against 30 from the prior decision: refused); 29 against 30 filing days refused, 30 admitted; 16 against 15 decision days refused. `final` is not compared (a tariff that makes the law's last stage non-final and adds a governing-body stage after it is admitted — more review, not less).
- **N5. The tariff-versus-law rule [D4q]/[D4r] — executed, as `tally_app`.** The battery's D8e/D8f run as the owner; the same holds for the application. After the law tightens: citing the now-looser tariff is refused [D4r], also as "not sheltered"; the law alone is admitted with the law's four blocks to day 60 (August 8) and refused on day 61 [D4p] or with the tariff's blocks [D4h]. Once the utility writes a tariff no looser than the new law: the law alone is refused [D4q], the new tariff is admitted, the closed one is refused [D4c]; and a new tariff still lacking the law's block cannot be written at all. The comparison is against the cited law row, read after its citation lock; a cited tariff is re-read after its own. I found no way to cite the law alone where the tariff is no looser, or the tariff where it is looser. One consequence to know, not a defect: the insert check compares a tariff with every class's law row, the citation compares it with the cited class's row only, so after a tightening of one class the other class's disputes go on citing the tariff.
- **N6. Nothing after the resolution: statement shapes — executed.** All refused: amount, withdrawal and line in one statement in either join order ([D2e], from the line or from the amount, whichever ran after the event); amount, withdrawal, then a multi-row line insert; a line carrying `record_seq` 0 (overwritten); the owner in replica mode; the owner's COPY of a line, and of an escalation, after the withdrawal; a withdrawal with a superseding determination in one statement [D4k]. The control (amount, line, then withdrawal) is admitted. A line takes no dispute lock of its own, and needs none: it must be in its amount row's transaction [D2f], which holds the lock.
- **N7. Two stale texts (by reading).** The COMMENT on `enforce_dispute_determination` still describes r2's [D4q] and names neither [D4r] nor [D4s]. The table comment of `dispute_amount_lines` does not mention that lines are numbered.
- **N8. The sequence's own settings are not pinned — executed.** `ALTER SEQUENCE dispute_record_seq MAXVALUE 100000 CYCLE` passes the guard invariant. Only the owner can do it, and the default never wraps, so this is a note; `pg_sequence.seqcycle = false` would be one more line.
- **N9. Tests.** New checks are tagged, and each new boundary has both sides (D8c/D8d, D8e/D8f, N9c–N9g, day 60/61 by my Q2/Q2b). M152 fails for the right reason: the invariant is driven by its list, so with the line removed the stray grant passes and H16b3 reports "accepted". DR13 exercises the check through `SET CONSTRAINTS … IMMEDIATE`, not at COMMIT; P1 shows the commit path behaves the same. A race mutation is counted caught on any line beginning "FAIL DR13", which is also what "session A itself failed" prints — the family's standing weakness (lesson `race-catch-names-its-damage`), not new. Missing: S2's unbounded stage; N3's close-against-move leg; S1's schedule if the lock mode changes.
- **N10. -17's template and -23's seal.** Battery P1–P15b and H16–H18c pass. `r2-to-r3.diff` has no hunk inside `assert_seal_role_invariants`, so the carried seal invariant is the one I diffed against `tu.sql` in round 2 (four intended edits). The three manifest hunks are all in the guard invariant: one trigger, five function hashes, the sequence.
- **N11. Residuals R1–R8.** None blocking. R5's new wording matches what I executed in round 2 (N4).
- **N12. For whoever reproduces.** The battery is not re-runnable on a clone after the race script has run there (D7p2 fails: DR10 leaves a committed citation of the default on November 23). Battery first, or a fresh clone each. Unrelated to -25: two `crystaldba/postgres-mcp` containers are running on this machine (up 42 hours and 3 days).
