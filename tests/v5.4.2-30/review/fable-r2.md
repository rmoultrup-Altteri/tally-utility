# v5.4.2-30 r2 — Fable's review

**Date:** 2026-11-06. **Reviewer:** Fable (Claude Fable 5.1), independent; `opus-r2.md` and `codex-r2.md` not read; my own `fable-r1.md` read.
**Frozen files:** all six md5s match the brief (executed, `md5 -q`).
**Scratch:** `rv30fable` cloned from `tally`, TEMP revoked from PUBLIC / tally_app / tally_core, the frozen r2 patch strict-applied twice (search_path empty, function bodies checked): both clean, the second a no-op ending in the patch's own "invariants hold" notice (executed). Dropped at the end. PATCH-LESSONS read: the depth-fence, trigger-depth, count-guard, temporal-helper, snapshot-knowledge, rule-table-key and checks-narrower sections.

## Verdict: not yet

One blocking item, found by executing the brief's own question about the `now()` stamps: two operators who change the same premise's state in overlapping transactions leave the history out of order, and every later read of that premise's places answers the wrong state, silently and for good. The fix is two lines in -30's own code. Everything else from round 1 is closed, the deferred coverage check is sound under both lock orders (executed), and the as-known reads answer what was known in every case I tried.

## Answers to the brief

1. **Each round-1 finding of mine, item by item.**
   - **S1** (a place closed from under a levy): closed. Section 2b's deferred ALWAYS trigger refuses a close with no successor (C1, C3; my P4b executed: a town with an open levy, `UPDATE places SET effective_to` refused at COMMIT with 23001), admits a close plus successor in one transaction (C2), and admits the close once the utility closed its levy (C4). The levy insert now takes the code's rows' locks shared and re-reads under READ COMMITTED; both races executed and sound (P7, below).
   - **S2** (exemption services unchecked): closed. `service_types <@` the seven services (E2c `{Gas}`, E2d `{all}`), precondition C2b, mutations N4c and N28b.
   - **S3** (the repair refuses a re-apply): closed. The raise is guarded by the kind still being a fraction; precondition C5 proves a re-apply after a percent fact; N4b mutates the guard.
   - **S4a** (L fragments): closed, each names the schema's reason. **S4b** (P4's fixture): closed; P4 is now an `initial` version of the fee item written before P3, refused for the penalty base alone. **S4c** (succession positive test): closed, L22 admits, L23 refuses, N37 mutates the coverage test. **S4d** (Q as `tally_app`): closed, Q1b.
   - **S5** (two writers on a levy key): recorded as L7, the template's. Accepted for the levy table, where the exclusion constraint makes the read raise. It does **not** cover the new history table, which has no exclusion and no "2 rows" refusal: there the same stamp mis-answers permanently. That is B1.
   - **S6** (a published rate with no levy): closed. The report's second leg, G5/G5b, N45.
   - **N1** (the range wording): closed in the kind's description. **N3** (G and `created_at` mutations): closed, N44–N46.
2. **Does a round-2 change open a new path?** Yes, two. B1 (the history's `now()` stamps under two writers). S1: the deferred check runs with whatever role the session holds at COMMIT, and a session that closes a place as the owner, then `SET ROLE tally_app`, then commits, runs the check under row-level security and sees no levy (executed, P4). Roles and RLS on the history are otherwise right: `tally_core` reads it only with an operator's `app.user_id` of the premise's tenant (P5, executed, three cases), a platform administrator's state change records a history row carrying the premise's tenant (P6, executed), the app's direct insert is refused at depth 1 (M10) and its own premise insert records at depth 2 (M10c). The isolation pin on the levy insert is already enforced by -17's template (P3, executed: 25000 from -17's message before -30's assert is reached); -30's assert is belt and braces.
3. **Does the history or the coverage trigger break anything earlier?** No path found. The recorder is an AFTER trigger named `z_`, after -16's state guard; it records only a change of the normalised state (M8b). The history's two FKs are NO ACTION, as the memberships' are, so a tenant delete (cascading onto premises) is already refused through memberships before the history is reached; nothing new. `enforce_place()` is not re-issued; the new trigger is additive and fires only on `effective_to`. The battery, preconditions, mutations and `ci.sh` counts in the brief are consistent with what I ran on the clone.
4. **Tests narrower than their claim; a mutation caught for the wrong reason?** Two gaps, both in the history. (a) No test makes two state changes in one transaction, so the `seq` tie-break is untested, and no mutation drops `, h.seq DESC` alone (N39 reverses the whole ORDER BY). I executed it (P2): TX→NM→OK in one transaction, the read at `now()` answers OK, so the tie-break works; it still needs a check and a mutation. (b) Nothing tests two sessions on one premise (B1). N36 lands on C0, a catalog assertion, rather than on C2's behaviour; acceptable since C2 would also fail, but C0 is the first check in the section so the runner stops there. Nothing else caught for the wrong reason.
5. **Do L1–L7 block?** No. L6 is right: a backfilled stamp at `created_at` precedes any bill of the premise. L7 is right for the levy table and the template; it must not be read as covering the history (B1).

## Blocking

### B1. Two writers on one premise leave the state history out of order, and every later read answers the wrong state — executed

`record_service_location_state()` stamps `recorded_at = now()`, the transaction's start, and `premise_places_as_of()` picks the latest row by `recorded_at DESC, seq DESC`. A premise's `UPDATE` takes the row lock, so two sessions changing the same premise serialise in row order, and `seq` follows that order; `now()` does not.

Repro on `rv30fable` (two psql sessions, owner, premise in TX with no memberships):
- Session A: `BEGIN` at 18:01:19.49, `pg_sleep(4)`, `UPDATE service_locations SET state = 'OK'`, `COMMIT`.
- Session B, 1.5 s later: `BEGIN` at 18:01:21.03, `UPDATE … SET state = 'NM'`, `COMMIT` (B commits first; A's update then waits for B's row lock, re-reads, and commits last).
- Result: `service_locations.state` = **OK**. History ordered as the reader orders it: `NM 18:01:21.03 seq 3`, `OK 18:01:19.49 seq 4`, `TX seq 1`. `premise_places_as_of(premise, today, 'tax', now())` returns state **NM**.

The live row says Oklahoma; every read as known now, and at every future instant, says New Mexico. It is not the L7 shape: nothing raises, the window never closes, and the mis-read then filters the memberships by `p.state_code = v_state`, so the premise's places on the tax axis are wrong for every bill from then on. -16's guard does not help (the premise had no memberships, which is the case the r2 plan itself gives for recording rather than refusing). It needs two operators with overlapping transactions on one premise where the first to begin commits last; a long-running import transaction beside a clerk's correction is enough.

**Fix (in -30's own code; no template change):** stamp the history with `clock_timestamp()` (the waiter's insert happens after the first writer's commit, so its stamp is later), and pick the latest row by `seq DESC` alone within `recorded_at <= p_recorded_at` (`seq` is the write order under the premise's row lock). Keep the index. M8's `max(recorded_at) = now()` and M10d's `recorded_at = now()` then become `>= now()` (or `BETWEEN now() AND clock_timestamp()`). Add a race test (the -27 races harness has the shape) and a mutation that puts `now()` back; a single-session battery cannot catch this one. The header's L7 should then say the history is stamped on write, not at transaction start, and why.

## Should-fix

### S1. The deferred coverage check runs as whatever role holds the session at COMMIT — executed

A constraint trigger fires at commit under the session's role then, not the role that issued the UPDATE. `enforce_place()` requires superuser or BYPASSRLS in the BEFORE trigger, but `check_place_levy_coverage()` reads `tax_levies` with invoker rights under FORCE RLS. Executed (P4): owner inserts a levy for tenant T on city C; `BEGIN; UPDATE places SET effective_to = '2027-01-01' WHERE id = C; SET ROLE tally_app; COMMIT;` — admitted; the place is closed at 2027-01-01 and the levy is still open past it. The same close without the role switch is refused (P4b). The closer is a platform migration, so the path is a mistake rather than an attack, but it is the one way round section 2b. Fix: repeat `enforce_place()`'s `rolsuper OR rolbypassrls` check at the top of `check_place_levy_coverage()` and raise `insufficient_privilege` otherwise; a battery check that the trigger refuses under `SET ROLE tally_app` at commit; a mutation.

### S2. The `seq` tie-break has no test and no mutation — executed (works)

P2: two state changes in one transaction (TX→NM→OK), `premise_places_as_of(…, now())` answers OK, history `TX/2, NM/5, OK/6`. Add the check after M8 (d2 changed twice in the battery's one transaction) and a mutation dropping `, h.seq DESC` (or, after B1's fix, reversing `seq DESC`). Under B1's fix this test is the one that pins the order within a transaction.

### S3. `tax_levy_reference_gaps()`'s second leg: the state leg counts every premise of the tenant, ever — predicted

The second leg's state clause is `EXISTS (service_locations l WHERE l.tenant_id = p_tenant_id AND upper(btrim(l.state)) = p.state_code)`: a premise that was in that state once, is now inactive, or was moved out of it still makes the state "a place the utility's premises are in" on `p_on`. Reading memberships and states as they stand now is right for a report (the knowledge-from-now lesson), and a false positive here is one row naming a state the utility has no levy for, so it does not block. If the row is unwelcome, use the premise's state as of now from the history (the latest row), which excludes nothing more; the real narrowing would be "a premise with service on `p_on`", which this table does not know. State the choice in the function comment either way.

## Notes

- **N1** The levy insert's new READ COMMITTED assert never speaks: -17's `rule_row_prepare` refuses REPEATABLE READ first with its own message (P3, executed, 25000). Harmless; the comment could say -17 already holds the line.
- **N2** The history's FKs are NO ACTION like the memberships', so a tenant delete that cascades onto `service_locations` fails at the history as it already fails at memberships; no new shape.
- **N3** `tally_core` reads the history through the same policy as memberships: no `app.user_id` refuses "not found", an operator's id of the premise's tenant answers, another tenant's refuses (P5, executed). Consistent with -16.
- **N4** The lock handshake in section 2b is sound in both orders (P7, executed): close first and held, the levy insert waits on the shared lock, re-reads the closed row and is refused ("its rows: {[2000-01-01,2027-01-01)}"); levy first and held, the close waits at the exclusive lock, proceeds, and is refused at COMMIT naming the levy. No deadlock: the insert takes shared locks in `id` order and the close takes one exclusive.
- **N5** `SET CONSTRAINTS … IMMEDIATE` only makes the check earlier; `DEFERRED` cannot skip it; `session_replication_role = replica` does not skip an ALWAYS trigger (C0 asserts `tgenabled = 'A'`). Only the owner's `DISABLE TRIGGER` could, out of scope.
- **N6** The backfill at `created_at` with today's state is the best record available and is stated as such; L6 covers the instant before it.
- **N7** P4's fixture now has exactly one reason to be refused (an `initial` version of the fee item, written before P3's valid one), closing my r1 S4b.

## Probes (all on `rv30fable`, dropped; P2/P3/P6 rolled back, the rest committed on the clone only)

| # | What | Result |
|---|---|---|
| P1 | two sessions change one premise's state; the first-begun commits last | live state OK; history ordered NM over OK; `premise_places_as_of(…, now())` answers NM — **B1** |
| P2 | two changes in one transaction, read at `now()` | OK (the `seq` tie-break works) |
| P3 | levy insert under REPEATABLE READ | refused 25000 by -17's template check |
| P4 | close a place, `SET ROLE tally_app`, COMMIT, with a levy on it | admitted; levy left open — **S1** |
| P4b | the same close without the role switch | refused 23001 at COMMIT, naming the levy |
| P5 | `tally_core` reads: no user / operator of the tenant / other tenant | refused / TX / refused |
| P6 | a platform administrator changes a premise's state as `tally_app` | recorded, carrying the premise's tenant |
| P7 | levy insert vs close, both orders | both serialise and refuse correctly |
