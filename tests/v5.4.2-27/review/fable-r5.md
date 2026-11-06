# Fable review — v5.4.2-27 r5 (narrow confirmation round)

**Verdict: ready.** The four changes from r4 do what the plan says, the corrected comment is accurate for both terms, and the new checks test what their labels say. No blocking item, no should-fix; three notes, none asking for a change before the mirror.

Frozen hashes checked first (`md5 -q`): all five match the brief, and the brief matches `review-brief-27-r5.md5`. Clone `rv27fable` (TEMPLATE tally; TEMP revoked from PUBLIC, tally_app, tally_core; `has_database_privilege` = f for both); frozen r5 applied strictly (`search_path=''`, `check_function_bodies=on`) twice: the second run printed "already applied (shortfall_applications exists); nothing to do". Server zone Etc/UTC, run at 2026-11-06 18:20 UTC. Clone dropped at the end.

## Reproduced

| What | Result |
|---|---|
| strict apply, twice | first applies, second skipped by its marker |
| `battery-27-frozen-r5.sql` | 146 PASS, 0 FAIL, rolled back; J1, J2, E21 (23514, "write the undo in a statement of its own"), E21b, E21c all PASS |
| `shortfall-27-frozen-r5.sh rv27fable` | 21 PASS, exit 0; SR11 passes with its new `40001: .*was escheated while this undo waited` label, SR11a admitted |
| M64 and M66 `rep()` anchors | each exactly one occurrence in the frozen r5 patch; M64 names J2, M66 names E21 (read, not run) |
| `assert_shortfall_guard_invariants()` | passes in the battery's tail and at the end of my probe transaction |

## The r4-to-r5 changes, one by one

1. **`cash_drawn_at`'s comment** (Codex r4 S1) — executed. The comment now says both terms can be non-zero at a take-back's instant when the row shares the take-back's transaction: the repaid term (J1, r4) and the source's own applications term (J2: a partial take-back of 20 under Q8's posting entry, then K8 repays 10 in the same transaction; `cash_drawn_at('credit', K8, take-back's created_at)` reads 10). Accurate; the old "(R15 holds the take-back while they are applied)" reasoning, which was only true across transactions, is gone.
2. **23514 vs 40001 in the re-read** (Opus r4 S1) — executed. Both reads are under the credit's lock (`check_cash_source` took it just before). The split keys on `status_recorded_at = now()`: that stamp is set to `now()` by -23's `enforce_customer_credit_immutable` for every non-superuser move, so it equals this transaction's `now()` exactly when this transaction made the move.
   - Same statement (E21's shape, unreferenced CTEs: the undo's INSERT runs before the UPDATE, the AFTER trigger at the statement's end sees the escheat): 23514, as the app (E21) and as the owner (my P4a); nothing of the statement remains (P4b); the same undo as a statement of its own is then admitted (P4c), so the message's remedy is right.
   - An escheat by this transaction in an **earlier** statement, then the undo: the stamp reads its own transaction's write, no mismatch, admitted and stamped true, the carry stands (P2a–c). So "= now()" never fires on a legitimate same-transaction order.
   - One statement with the undo selecting from the escheat's RETURNING (escheat first; my r4 P2b): still admitted, stamped true (P3a–b). The 23514 reaches only the shape that cannot be told apart.
   - The undo first, then the escheat, as separate statements (E21b): admitted, the app's sent `true` replaced by `false` (E21c, my r4 N1 closed).
3. **SR11's label checks the SQLSTATE** (Codex r4 S2) — executed; the race gives `40001:` in the verbose error and passes.
4. **E21c** (my r4 N1) — executed; the sent value is replaced, pinned.
5. **Headers**: the race script names the id collision with -23's battery (my r4 N3); the patch header carries the r5 line and counts 146/21/74.

## Findings

No B. No S.

### N1 (predicted) — the two edges of the `= now()` test are both acceptable

- *Another transaction's escheat with the same `now()`*: two transactions would have to start in the same microsecond (`transaction_timestamp` resolution) and the escheat still commit between the stamp and the re-read. The lost race would then say 23514 "write the undo in a statement of its own" instead of 40001. Nothing wrong is recorded; the undo is already its own statement, so the next attempt is admitted. Vanishingly rare, and harmless when it happens.
- *A superuser's chosen status time in the one-statement shape*: `status_recorded_at <> now()`, so the refusal is 40001 "retry it", and the retry fails the same way. Only a superuser doing a history load who also puts the undo in the escheat's statement; the refusal is still right, only the remedy in the message is off. Not worth a third branch.

### N2 (predicted) — comment wording, `cash_drawn_at`

"a partial take-back of the source": for a credit source (J2's case) the take-back is under the credit's payment's posting entry, not of the credit itself. The reading "a take-back of the money the source holds" is what is meant, and the J2 pointer makes it findable. Cosmetic; no change asked before the mirror.

### N3 (executed) — a -23 ordering matter met while probing, not -27's

An escheat whose event row and status move are in the same writable CTE as the undo is refused by -23's `check_cash_source` ("a row drawing on credit … (escheated) for escheat"), since the event's AFTER trigger runs at the statement's end and sees the credit already escheated. Recording the event in an earlier statement (as the battery's E1 does) avoids it. Unchanged by -27; noted only so nobody reads it as an r5 regression.

## Probe file

`/private/tmp/claude-501/-Users-ryanscomputer-code-tally-utility/1dff16d9-6dfb-40ad-a60b-fd9517b382c2/scratchpad/probe-r5-fable.sql` — P2–P4 above, one transaction rolled back, built on the battery's helpers and fixtures (its lines 24–145); ids under `…29d0`–`…29ff`. Runs with `docker exec tally-pg psql -U tally -d <clone> -v ON_ERROR_STOP=1 -q -f`.
