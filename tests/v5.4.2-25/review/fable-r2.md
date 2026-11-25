# v5.4.2-25 r2 — Fable's review (disputes, the platform default, the status-move role)

**Date:** 2026-11-25. **Reviewer:** Fable (claude-fable-5-2). **Verdict: ready** — no blocking item. Two should-fix items (S1, S2), both executed; S1 is a plan item built by half and a header claim that fails under two overlapping commits. Fix them before the mirror or name them as residuals; neither moves money.

**Frozen files:** the ten md5s and the brief's own md5 match. Reviewed only those copies; read my own `fable-r1.md`; did not read `opus-*` or `codex-*`.

**Reproduced on `rv25fable`** (clone of `tally`, TEMP revoked from PUBLIC, `tally_app`, `tally_core`; frozen patch applied strictly, `search_path=''`, `check_function_bodies=on`):
- strict apply succeeded; the second run said "already applied (disputes exists); nothing to do";
- `battery-25-frozen-r2.sql`: 271 PASS, 0 FAIL, rolled back;
- `disputes-25-frozen-r2.sh rv25fable`: DR1–DR12, 16 PASS;
- `terms-25.py` (live copy, md5 equal to the frozen one) under `tools/law/.venv`: 0 failures;
- the default's seed lines in the patch equal the frozen `.seed.sql`; the yaml's sha256 equals the patch's `source:` line.

Not run, per the brief: `mutations-25.py`, `migration-25.py`, `ci.sh`. No role created, dropped or altered. The clone and its files in the container were dropped at the end. Probes ran as `tally_app` under `app.user_id` on the battery's fixtures inside the battery's rolled-back transaction, except the two-session probe (S1), which used committed fixtures on the race script's tenant.

---

## B — blocking

None.

---

## S — should fix

### S1. The "reading leaves disputed when its last dispute closes" check reads other disputes with no lock — executed (with a delay added to hold the window open)

Plan item 6 says the release happens "under the same locks (every naming dispute's, in id order)". As built, `enforce_dispute_reading_released` is a deferred check at commit that reads `disputes.status` of the other disputes naming the reading and takes no lock; the closing event took only its own dispute's lock. Two disputes naming one reading, closed by two transactions whose commits overlap: each check sees the other dispute still open, both pass.

```
fixture: reading R status disputed; disputes DA, DB name it, both open
control (in turn, another reading): close DC, commit; close DD, commit
   -> second refused 23514 [T2c]                     (right)
race:  A: BEGIN; withdraw DA; <deferred 3 s delay>; COMMIT
       B (1 s later): BEGIN; withdraw DB; <deferred 3 s delay>; COMMIT
   -> both committed; R = disputed; disputes = withdrawn, withdrawn
```

The delay was a scratch deferred trigger in my clone, queued after the closing event, so the commit check ran and the commit followed three seconds later. Without it the window is the time between the deferred check and the commit becoming visible: short, and longer for a transaction with other deferred work after the event. The damage is a reading left `disputed` with no open dispute (the header's T2 claim); a later plain update can move it out, so nothing is lost for good.

**Fix (measure it):** a closing event of a dispute that names a reading takes the lock of every dispute naming that reading, in id order (as `enforce_reading_dispute_status` does), in the BEFORE guard; then the second close waits for the first commit and its commit check sees it. Say where that falls in the header's lock rule (writers retry 40P01). Add a race leg (two closes of two disputes of one reading) and a mutation. If left, name it as a residual and correct the header.

### S2. The order "nothing after the resolution" rests on is a sequence whose grants nothing pins — executed

Round 1's blocker is fixed by `record_seq` order (`enforce_dispute_nothing_after_close`). `tally_app` holds USAGE on `dispute_record_seq` (nextval only). No invariant lists the sequence (my r1 S4 named it; `assert_dispute_guard_invariants` has tables, columns, functions, no sequence).

```
A1 GRANT UPDATE ON SEQUENCE dispute_record_seq TO tally_app; all nine tail invariants  -> pass
A2 with that grant, as tally_app, one statement:
     WITH r AS (INSERT resolved event RETURNING 1)
     INSERT INTO dispute_amounts ... FROM r WHERE setval('public.dispute_record_seq', 1) > 0
                                                                                        -> ACCEPTED (an amount after the resolution)
A3 the same statement without the grant   -> 42501 permission denied for sequence
A4 the same statement without setval      -> 23514 [D2e]
```

Not open today (A3). But a stray grant reopens round 1's blocker and CI stays green. **Fix:** pin the sequence's ACL in the invariant (one line beside `c_tables`), with a battery check and a mutation.

---

## N — notes

- **N1. Round-1 findings (executed unless marked).** B1 closed: multi-row insert, writable CTE (A4, battery D5r, D5r2, D4k2, D2m2) and a superuser COPY of a resolution plus an escalation (23514 [D5f]) are all refused; COPY as `tally_app` is refused by PostgreSQL itself ("COPY FROM not supported with row-level security"). S1 (counted end) closed for the counted kind, both sides tested (D4p, D4p2, D7c, D7f). S2 (duties, stages) closed as the plan words it (N9a, N9b; stages compared by decider only, deadlines not). S3 (owner role) closed. S4 (invariant) closed except the sequence (S2 above). S5 (two-column keys) closed on the five record tables (catalog); `dispute_tariffs.created_by`/`closed_by → users(id)` are the template's own and stay single-column.
- **N2. Three note dispositions the plan states are not in the patch.** (a) "D4a's service and state: the bill's are used" — `enforce_dispute_determination` still takes state, service and system from the row and checks them against the profile only (by reading; no effect while only Texas gas rows exist). (b) "The opened event is re-ordered by being written first" — executed: a dispute and its first amount in one statement give the amount `record_seq` 6 and the opened event 7, as in round 1. Harmless. (c) "A sheltered determination with nothing sheltered: a test pins it" — no battery check does. Correct the plan or build them.
- **N3. An end date under a document that ends only at resolution is unchecked — executed.** T3's own tariff (`shelter_ends.kind = resolution`): a sheltered determination with `shelter_ends_on` = the received day is accepted, so the reader stops the shelter the next day while the dispute is open. The brief scopes item 3 to the counted kind; this is the under-claim side. One line would require NULL for `resolution` and `through_regulator_close`.
- **N4. A reading-only dispute under a counted document can only be recorded "not sheltered" — executed.** At the silent city, a dispute naming a reading and no bill: sheltered with an end is refused [D4p] ("an unknown day"), sheltered with no end [D4p], "no terms" [D7b]; "not sheltered" citing the default is accepted. The same holds under 16 TAC 7.45. Defensible (60 days from issue needs a bill), but residual R5 ("its shelter is read from its determinations") is then empty for every seeded document; say so in R5.
- **N5. The default's citation rule — executed.** No path found to cite it where it should not be, miss it where it must be, cite the other class's, a closed one, or one beside a tariff: battery D7a–D7p2, plus: with the protected default closed from November 23, a November 23 dispute citing it is refused [D7a] and "no terms" is admitted; the November 22 dispute still cites the closed row. "Not sheltered" under the default is admitted. The lookup is read before the lock and `rule_law_row_cite` re-resolves under it, so a close in flight is seen (DR10). The negative legs (no tariff, no default in force) take no lock: a back-dated tariff is residual R6 (DR11); a back-dated default row is the platform's own act and R6 should name it too.
- **N6. The default's table and the template (by reading and battery P1–P15b).** The -17 template is keyed by table, not by kind: registration, the exclusion, `rule_law_row_as_of`, `rule_law_row_cite`, the trigger invariant and the tariff's coverage check (which reads `law_table = dispute_rules` only) treat a second law table of the kind `dispute` correctly. Nothing resolves "the law table of a kind".
- **N7. The status-move role — executed.** Grants exact (seal invariant, H18–H18c). Refused [D1g]: the superuser moving a resolved dispute back to open; `SET ROLE tally_dispute` doing the same, re-typing the status, or resolving an open dispute with no event. As `tally_dispute`: insert an event 42501; read `subject` 42501. `tally_app` direct update 42501. Born-resolved insert is [D1h] with no superuser carve-out. RLS on the move is right (fail closed, as the void). A history load as the superuser sets `app.user_id` to a user of the dispute's own tenant (admitted); another tenant's user is refused earlier, by the `created_by` key (23503, not a message that says why); unset is DR12; replica mode still fires every guard (a second event after the resolution refused [D5f]). Write this as the application contract at the mirror.
- **N8. The carried seal invariant — executed (diff).** -25's `assert_seal_role_invariants` against the last body in `tu.sql` (line 46687, -23; no later patch re-issues it): four edits only — the owned-function list, the grants list, the role loop, the comment. Nothing of -23's is lost.
- **N9. An unlisted trigger passes the invariant — executed.** A new BEFORE UPDATE trigger on `disputes` sorting after `b_enforce_dispute_update` passes `assert_dispute_guard_invariants` and the seal invariant. -24's invariant has the same shape (listed triggers must exist; extras unseen), so this is the family's residual, not -25's.
- **N10. Calls settled by rule while building.** None wrong by a standing rule. Two to tell Ryan in a line at the mirror, since each decides a late fee on one boundary: (a) his ruling says "raised before the bill's due date"; the stored term `before_delinquency` admits a dispute received on the due date (the 2026-11-07 entry does say the default mirrors 7.45, so the reading is fair); (b) the default binds by received date from 2026-11-22, so a dispute received earlier and still open stays "no terms". Nothing is live, so (b) has no case today.
- **N11. Header.** The lock rule names the law row's and the tariff's locks, not the default's (law row, then default; all shared, no cycle). The Tests line says 270 checks and 140 mutations; the brief says 271 and 141.
- **N12. Residuals R1–R8.** None blocking. R5 see N4; R6 see N5; R7 see N7.
- **N13. Tests.** New checks are tagged and both sides of each new boundary are pinned (November 21/22 for the default's first day, January 18/19 for day 60, November 22/23 for the close floor, November 24 for the city's own policy). Missing: S1's race, S2's sequence, N3's shape, a closed default cited (N5), a history load's resolution under another tenant's user (N7). M48's miss (a race barrier not seen under load) could not be re-run here; DR1 passed on my run.
