# Opus review: v5.4.2-25 r2 (disputes, the platform default, the status-move role)

**Date:** 2026-11-25. **Reviewer:** Opus. **Round:** 2.
**Verdict: not yet.** Nothing is blocking. Two should-fix items (S1, S2) are worth fixing before the freeze. Each is a few lines of code with a test.

## Hashes

All ten frozen files match the brief: patch `edf445bb…`, battery `50f48c07…`, races `9fb24be5…`, mutations `1a621326…`, terms `83d14843…`, migration `55d80759…`, fill-manifest `e0664cca…`, law file `deb66829…`, seed `3832a44f…`, diff `46289b5a…`. The brief's own md5 matches its `.md5` (`99615d09…`).

## What I ran

All of this was on scratch `rv25opus` (TEMPLATE tally; TEMP revoked from PUBLIC, tally_app and tally_core). I dropped it at the end and removed my files from the container.

- **Strict apply, twice:** the first run is clean and seeds the two defaults. The second prints "already applied" and does nothing. Reproduced.
- **battery-25 (frozen r2):** 271 PASS, rc 0. Reproduced.
- **races (frozen r2), on my clone:** DR1–DR12, 16 PASS. Reproduced.
  - The race script commits rows, so a battery run on the same clone afterwards fails D7p2. DR10/DR11 have cited the default for a dispute received 2026-11-23, so it cannot close on that day. That is correct behaviour, not a defect. I re-cloned before the probes.
- **Invariants on the patched clone:** `assert_seal_role_invariants()`, `assert_dispute_guard_invariants()` and `assert_rule_table_invariants()` all pass.
- **The carried seal body:** I diffed `pg_get_functiondef` on `tally` against the clone. The differences are tally_dispute in `c_owns`, its grant list plus a comment line, and the role loop. The rest of the tally_close line is byte-identical. Nothing of -23's is lost or loosened.
- **Probes:**
  - one probe file: the battery's lines 1–1247 (fixtures through D7), then my statements, ending in ROLLBACK;
  - one two-session race on committed fixtures (S2).
- Not run: `mutations-25.py` and `ci.sh` (the brief forbids both). I read `terms-25.py`, `migration-25.py` and `fill-manifest.py` but did not run them.

## Round-1 findings: closed?

| r1 | What | r2 | How I know |
|---|---|---|---|
| B1 | A record in the same statement as the resolution | **Closed** | An AFTER ROW trigger, ENABLE ALWAYS, on amounts, determinations and events judges by `record_seq` against the closing event. Battery D5r/D5r2 and the CTE shapes pass. The legitimate order is admitted. See N3 for lines. |
| S1 | Duties and stages not compared | **Closed** (narrower than I asked) | Duties are compared as a superset. Stages are compared by decider category only: a tariff's regulator stage may have a longer deadline than the law's (N4). |
| S2 | The law alone cited while the utility's tariff is in force | **Closed, but over-reaches** | D4q. When the law has tightened since the tariff was written, D4q forces the record onto the looser tariff (**S1 below**). |
| S3 | Amount uncapped | **Closed** | D2g (100.01 refused, 100 admitted). |
| S4 | Reading left `disputed` | **Closed in one transaction, open under two** | `zz_dispute_reading_released` holds a single transaction. Two concurrent closings both pass (**S2 below**). |
| S5 | Eleven single-column tenant links | **Closed** | All are two-column now. `dispute_tariffs (id, tenant_id)` is unique. The line key is tied through `invoice_id`, which is the dispute's bill. |
| S6 | Penalty rule | **Superseded** by item 9 (Ryan 2026-11-22), built as ruled | See below. |
| N1 | Replica-mode cross-tenant bill | **Closed** | The guard compares the bill's tenant and customer itself, and the reading's tenant. |
| N2 | Definer owned by the superuser | **Closed** | `tally_dispute` is NOLOGIN, has exactly 13 privileges, and is in the seal invariant. The update guard keys on `current_user = 'tally_dispute'`. |
| N3 | State, service and system are the caller's | **Not changed** | The plan's Notes say "The bill's are used". The code still uses `NEW.state_code`, `service_type` and `system_kind` (N5). |

**Item 9 (the platform default) against Ryan's rulings of 2026-11-22:**
- The content is as ruled: any subject; before delinquency; must-pay is the undisputed charges; the shelter ends at the earlier of resolution and 60 days from issue; the late fee and both disconnection steps are blocked; no stages and no duties. It applies to both classes.
- It is a law-template table of its own, so the delegation document is not loosened.
- It is cited only under a delegation with no tariff (D7k, D7o).
- When a default is in force, the default in force must be cited (D7b, D7b3), and "no terms" is refused (D7b, D4n).
- When none is in force, naming one is refused (D7a).
- A city's own tariff replaces the default from its date (D7k). A dispute already determined keeps the default it cited (D7m).
- The close floor holds (D7p and the DR10 race).
- The comparator does not read the default (I checked: `rule_tariff_insert` passes only `p_cfg.law_table` rows).

I found no place where a determination can cite a default it should not, fail to cite one it must, cite the wrong class's or a closed one, or cite one beside a tariff. The lookup is followed by `rule_law_row_cite` under the dispute's lock.

The three calls settled by rule while building all agree with standing rules:
- the default is in force from the ruling's date;
- a dispute received on the due date counts as before delinquency (R8);
- a back-dated policy over a determined dispute is admitted (R6).

---

## S — should fix

### S1. When the law tightens after a tariff was written, D4q forces the record onto the looser tariff (executed)

**What happens.** D4q (r2, for my r1 S2) says: where the law governs and a tariff of the utility is in force, the determination cites the tariff. D4h then requires the recorded blocks to equal the tariff's. The template admits a stricter later law over an existing tariff on purpose ("a later change in the law that makes a tariff looser is a core audit finding, never a refusal of the law"). After such a change, the record can no longer show the law's protection.

**Probe** (T2, investor-owned):
1. Tariff `ac` (`tdoc()`, from 2026-01-01) is written while 16 TAC 7.45 is in force.
2. As the owner, the 7.45 protected row is closed on 2026-06-01, and a row from 2026-06-01 is added that also blocks `credit_reporting`. Both are admitted.
3. A dispute is received 2026-06-10 on a bill dated 2026-06-01, with an amount of 40.

| | Determination | Result |
|---|---|---|
| Q1a | the new law row alone, its four blocks, ends 2026-07-30 | REFUSED 23514 [D4q]: "the utility has its own dispute policy in force on 2026-06-10, never narrower than the law — cite it" |
| Q1b | the tariff, with the law's `credit_reporting` added to the tariff's blocks | REFUSED 23514 [D4h] |
| Q1c | the tariff with its own blocks (no `credit_reporting`) | **ADMITTED** |

So the only record the database accepts says credit reporting is not stopped, while the law in force on the received date stops it. D4q's own message ("never narrower than the law") is false in this case. This is the same harm as r1 S2 (a recorded shelter narrower than the rule that binds), now arising from the fix.

**Fix (suggested).** Apply D4q only when the tariff is no looser than the cited law row on the received date. The comparator already exists:

```sql
cardinality(public.dispute_tariff_compare(<tariff>.terms_as_row, jsonb_build_array(r.terms))) = 0
```

(called with the shapes it already takes). When the tariff is looser, admit the law alone; that tariff is the core's audit finding. Test: Q1a admitted, and Q1-style tariff-cited determinations both ways.

### S2. Two disputes of one reading closing at once leave the reading `disputed` with no open dispute (executed)

**What happens.** `enforce_dispute_reading_released` runs at commit. It reads "is any other dispute naming the reading still open?" without taking a lock. Closing dispute A takes only A's lock, and closing B only B's. Each session sees the other's dispute as still open (not yet committed). Both pass, and both commit. The header's lock rule ("a reading's move … takes the lock of every dispute naming the reading") binds the move, but not this check. The plan's item 6 said "under the same locks (every naming dispute's, in id order)".

**Probe** (committed fixtures on my clone):
- reading R has two open reading-only disputes, A and B, and is marked `disputed`;
- session 1 withdraws A, runs `SET CONSTRAINTS zz_dispute_reading_released IMMEDIATE` (passes, 21:10:55.66), then holds 4 s;
- session 2 withdraws B, runs the same (passes, 21:10:56.65), and commits;
- session 1 commits.

Afterwards R is `disputed` and its disputes are `withdrawn, withdrawn`.

`SET CONSTRAINTS … IMMEDIATE` widens the window between the check and the commit. Without it, the window is the instant both COMMITs run their deferred triggers together, which is rare but real. An application that sets constraints immediate (as the battery does) opens it fully.

**Damage.** This is r1 S4's damage again: the next reading on that meter skips R (`populate_reading_calculations` takes `active` readings only), and nothing lists R.

**Fix.** In the deferred check, first lock R (`SELECT … FROM meter_readings WHERE id = v_reading FOR UPDATE`), or every dispute naming R in id order (`dispute_lock`), and then read. At READ COMMITTED, the second check waits for the first to commit, re-reads, and refuses. Add a race (DR13) and a mutation that removes the lock.

---

## N — notes

- **N1. Lock order header (read).** The rule lists "the cited law row's lock, then the cited tariff row's … 3. nothing else". r2 adds the platform default's shared lock (`rule_law_row_cite` on `dispute_platform_defaults`), taken after those, and S2 would add the reading's. No cycle is possible today, because a close takes only its own row's lock. The header should name both locks.
- **N2. A reading-only dispute cannot be recorded as sheltered under a document whose end counts from the bill's issue (executed, Q2).**
  - At T3 under the default, a reading-only dispute received 2026-11-23 has an amount of 40.
  - "sheltered … ends 2027-01-21" is REFUSED [D4p] ("ends it by an unknown day"); "not_sheltered" is ADMITTED.
  - The same holds under 7.45. So the core must record `not_sheltered` for a dispute the rule would shelter once a bill exists.
  - Since R5 says a reading-only dispute's shelter is read from its determinations, either say in R5 that such a dispute has no recordable shelter until its bill, or let D4p accept a NULL end when there is no bill.
- **N3. A line can be added to an amount after its dispute is closed, in the same transaction (executed, Q3).** In one statement batch: dispute → amount 60 → withdrawn → line 60. All of it is ADMITTED, and the commit-time sum check passes. `enforce_dispute_amount_line` checks "the amount's own transaction" [D2f] but not "nothing after the close", and the new AFTER trigger does not cover `dispute_amount_lines`. The amount itself was written before the close, so this changes only which lines were disputed, not the figure. Cheap to add the same trigger on lines (judging by the amount's `record_seq`).
- **N4. Stages are compared by decider only.** A tariff whose regulator stage allows 30 days to decide passes against the law's 15. The plan chose this on purpose ("deadlines … not compared"). It is recorded here so the brief's "compares stages" is read that narrowly.
- **N5. D4a still uses the caller's state, service and system (read).** The plan's Notes say "D4a's service and state are the caller's, not the bill's. The bill's are used." The code (D4a, D4e, D4q, D7) still passes `NEW.state_code`, `NEW.service_type` and `NEW.system_kind`. This is harmless while one family exists. Either build it or correct the plan line.
- **N6. "60 days from issue" anchors on `invoices.invoice_date`, not `first_issued_at` (read).** Where a bill is dated before it is sent, the cap ends earlier than the document's words, which is away from protection. The battery's own bills differ by eight months (dated March 1, issued "a day ago"), so the choice is visible. Worth one sentence in the header saying the bill date is the issue date.
- **N7. The guard invariant checks listed triggers but not unlisted ones on the -25 tables (read).** An extra BEFORE trigger sorting after `b_enforce_*` could rewrite NEW after the guard has checked it. Policies and column grants are checked both ways; triggers only one way. -24's model is the same, so this is not new to -25.
- **N8. The status move and history loads (executed, DR12).** RLS applies to tally_dispute, and the move raises when it finds no row, so a load without `app.user_id` fails loudly rather than leaving the status open. That is right. The application contract should say a superuser history load sets `app.user_id` to a user of the dispute's tenant for every closing event. A superuser can `SET ROLE tally_dispute` and update the status directly, but the event-match guard still holds, and the superuser is trusted.
- **N9. Mutations (read).** The move's event leg as tally_dispute has no mutation, as the plan says. Its body is pinned by md5 in the guard invariant, so that is acceptable.
- **N10. Residuals R1–R8.** None is blocking. R6 now covers the default as well (DR11): fine. R8 is fine. S1 above is close to R6 (a later fact changes what the record should say), but unlike R6 the database actively refuses the correct record, so it is not a residual.
