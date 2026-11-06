# Opus review: v5.4.2-27 r5 (narrow confirmation round)

**Verdict: ready.** No blocking or should-fix items. Three notes.

## Hashes and reproduction (executed)

- All five frozen md5s match the brief (patch 50e7b43d…, battery 52e862a8…, races bc7fbafff…, mutations 81d0f48a…, r4-to-r5.diff b91fa67f…). The brief's own md5 (b53bec21…) matches `review-brief-27-r5.md5`.
- Clone `rv27opus` (TEMPLATE tally; TEMP revoked from PUBLIC, tally_app, tally_core). The frozen r5 patch applied strictly twice. Run 1 gave rc=0. Run 2 was skipped by its marker ("already applied"), rc=0.
- `battery-27-frozen-r5.sql`: **146 PASS**, 0 FAIL, rc=0 (J2, E21, E21b, E21c among them).
- `shortfall-27-frozen-r5.sh rv27opus`: **21 PASS**, rc=0. SR11 passes on the 40001 fragment.
- Not run: mutations, ci.sh, and -23's battery and races. The r4-to-r5 diff changes only a comment in `cash_drawn_at` and one branch in `enforce_shortfall_application`, which is -27's own function. I touched no role. The clone has been dropped.
- Probes: the battery up to the X7 fixture (line 1084), then a `pg_temp.try` helper that prints ADMITTED or REFUSED with the SQLSTATE. All of it runs in the battery's single transaction, ending in ROLLBACK. The probe file is in my scratchpad, not the repo.

## 1. The 23514/40001 split (read; executed for the in-statement cases)

The new branch runs only when the stamp and the re-read disagree. Within one transaction, an escheat made in an **earlier statement** is visible to the BEFORE stamp. The stamp is then true and agrees with the re-read, so the branch is never reached. Probe P4: escheat 20 as its own statement, then the undo. Result: stamp = t, and the deferred check asks for the carry (23514 "carry it…"). The only in-transaction disagreement left is an escheat that runs after the stamp **inside the undo's own statement**, and that is exactly what the new message names. E21 shows it gets 23514.

Executed, CTE order: PostgreSQL runs unreferenced data-modifying CTEs last-written-first, so E21's text order (u, e, i) runs the insert first. That makes the undo-before-escheat order the one tested, as its label says. In other text orders, -23's existing guards refuse first. Probe P3 (i, e, u) is refused 23503 (status_cause_id not yet inserted). Probe P3b (i, u, e, escheating 20) is refused 23514 by the escheat's draw check. Every order fails closed, and none of them is told to retry.

Answers to the brief's two cases:
- **True for an escheat made by another transaction:** only if both transactions started at the same microsecond (`now()` is the transaction start). In that case a real race gets 23514 instead of 40001. It still fails closed. The app does not retry automatically, and a person resubmitting the undo gets the right result. Acceptable (N1).
- **False for one this transaction made:** a non-superuser's status time is always forced to `now()` (customer_credits guard, `NOT v_super OR … unchanged` → `now()`), so this case cannot arise for the app. A superuser who chooses an earlier `status_recorded_at` in the same one-statement shape still gets r4's 40001, which a retry cannot clear. Predicted, not executed: inside the battery's single transaction, the lineage rule refuses any chosen time before `now()`. That shape is a history load written as one writable CTE, which is negligible (N2).

## 2. `cash_drawn_at`'s comment (read; J2 executed)

The comment is accurate now. Both terms can be nonzero at a take-back's instant when the rows share its transaction. For the repaid term it says "when the repayment shares the bounce's transaction" (J1). For the source's own applications it says "when one follows a partial take-back of the source in its transaction" (J2). The false claim r4 made, that the second term nets to 0 at every take-back's instant, is gone. J2 builds exactly that case: a partial take-back of 20 under Q8's entry, Q8 still posted, then K8 repays 10, all in one transaction. It reads 10 at the take-back's instant. M64 (that term set to `false`) would read 0, so J2 is the check that catches it.

## 3. Tests' labels (executed)

- **E21:** `refuses_at` requires both the SQLSTATE (23514) and the fragment "write the undo in a statement of its own", so the 40001 path cannot pass it. M66 (`IF false`) turns it back into 40001, which E21 catches.
- **E21b / E21c:** the undo is sent with `gave_to_escheated = true` while G7 is active, then the escheat of all 50 follows, and the deferred carry check is forced IMMEDIATE and passes. E21c confirms the database stored false. Both match their labels.
- **SR11:** `PSQL` sets `-v VERBOSITY=verbose`, a special psql variable, so errors print as `ERROR:  40001: …`. The fragment `40001: .*was escheated while this undo waited` therefore checks the SQLSTATE as well. The r5 23514 message would not match it.

## Notes

**N1 (predicted). The 40001/23514 split assumes two transactions never start in the same microsecond.** If they do, a real cross-transaction race is refused 23514 ("write the undo in a statement of its own") rather than 40001. It fails closed, and only the error's wording and the retry hint are wrong. No change needed. Optionally, the r5 code comment could say "practically never shared", as my r4 S1 did.

**N2 (predicted). A superuser's chosen status time inside the one-statement shape still gets r4's 40001, which a retry cannot clear.** This only happens in a history load written as a single writable CTE. No change needed.

**N3 (executed). The ordering in E21 relies on how PostgreSQL schedules CTEs, not on the order they are written.** The insert runs first because the CTEs run last-written-first. If a future PostgreSQL changed that order, E21 would hit -23's guards (as P3 and P3b do) instead of the r5 branch, and it would fail with a different SQLSTATE or message rather than pass vacuously. No change needed. A one-line comment in the battery would help the next reader.
