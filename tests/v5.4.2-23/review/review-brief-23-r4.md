# Review brief: v5.4.2-23 r4 — cash: round 3's findings, the overpayment credit's bounce, refund_reissue

**Date:** 2026-10-21. **Kind:** patch review, round 4.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's round-4 files. You may read every earlier review in this folder (`*-r1.md` to `*-r3.md`, `codex-r*-probes/`): r4 answers round 3.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-23/review/patch-23-frozen-r4.sql` | `e4c343f57dc767770dde8d746e9bee3c` |
| `tests/v5.4.2-23/review/battery-23-frozen-r4.sql` | `4c8f04ddc0fdf1c872b226acf12aa4cc` |
| `tests/v5.4.2-23/review/cash-23-frozen-r4.sh` | `26c88beead259f132fed05732dedc5eb` |
| `tests/v5.4.2-23/review/mutations-23-frozen-r4.py` | `c3f6b89826442a0d61d728546f5b1e33` |
| `tests/v5.4.2-23/review/older-tests-23-frozen-r4.diff` | `be99c2f963ab9f2177c9f059a4de7e5c` |
| `tests/v5.4.2-23/review/patch-23-r3-to-r4.diff` | `26c563b64c89ac678d7d7dc09b706a33` |

Today the live copies are identical to the frozen ones. Review the frozen copies. `older-tests-23-frozen-r4.diff` is every change -23 made to earlier tests, against the -22 mirror commit `eef5122` (r4 adds none). `patch-23-r3-to-r4.diff` is for orientation; review the whole patch.

## What changed since round 3

All three reviewers said "not yet". `application/wave2-build-2026-10-15/v5.4.2-23-r4-plan.md` is the merged list. `application/DECISION-LOG.md` (2026-10-21, r4) gives the calls and the reasons, including two places where the fix differs from a reviewer's suggestion. One new ruling:
- **Ryan, 2026-10-21 (option 1):** a refund of a credit that comes back after the credit was escheated goes into a new credit (origin `refund_reissue`, `customer_credits.reissues_refund_id`), in the same transaction, checked at commit (`enforce_escheated_credit_settled`).

In short:
1. **The overpayment credit's bounce** (K-10 through the credit). The bounce waits only while the credit is applied or has a refund pending. What the credit paid out stands; what it held goes with the payment: its `issued` and its cap read the payment's posting entry. A payment holds one live overpayment credit. Locks: payment, then credit.
2. **Nothing comes back to an escheated credit.** Escheat waits while a refund is pending; a donation is not undone onto it; a returned refund is reissued.
3. **A donation's correction** is a capped draw when it takes money again, and an undo when it gives it back.
4. **Arrival rows** only for a payment still pending or a credit still active, under its lock. A source's money counts from its arrival entry's date (not by forcing that date to the payment's: ACH settles later).
5. **The cap** is checked from the new row's date on. **Recorded order** covers rows under the arrival entry.
6. **Rows giving money back** are not held up, but nothing is given back to an ended source. **A credit never issued** is voided naming nothing.

## Drafting calls to check in particular

- **The overpayment credit model.** Take-backs come first out of what the credit holds. Is any position, cap or status move inconsistent with that? Kyle's example through the credit, in full and in part: does every reader agree on what the customer owes?
- **One live overpayment credit per payment.** Does anything legitimate need two?
- **`refund_reissue`.** Is every way a refund of an escheated credit can come back forced through it, at commit? Can a reissue be created, voided or drawn on to move money that should not move? Is the commit-time check reachable around (a refund of a credit that is escheated later in the same transaction, a superuser path)?
- **The arrival-date cap.** The arrival entry counts from its date; draws are refused before it. Does any reader still treat money as present before that date?
- **The lock order.** Payment before its credit, a credit before its reissue, the arrival row's source lock. Any cycle with another writer?
- **Give-back rows.** Is "nothing back to an ended source" complete (payment, credit, donation trees)?

## Results so far (reproduce them)

- **Strict apply, twice:** as before.
- **`tests/ci.sh`:** passes in full with -23, -25 and -26 pending (49 steps).
- **`battery-23.sql`:** 252 checks. The V section is new (round 3's findings and the reissue); C1k now checks one live credit per payment and C1k2 the overpayment cap. Every V check failed against r3 before the fix: `tests/v5.4.2-23/red-r4-against-r3.txt` (V7i, V15, V15b and V16 were added after it, with their guards).
- **`races/cash-23.sh`:** CR1–CR19, 29 results. New: CR18 and CR18b (an overpayment credit's draw against its payment's bounce, both orders), CR19 (a posting row against the payment's void).
- **`mutations-23.py`:** 170 of 170 caught, each at its named check as the first failure. N141–N170 are new.

## What to answer

1. **Does r4 close each round-3 finding it claims to close?** Item by item.
2. **Does r4 apply the rulings faithfully** (K-10, Ryan's status decision, Ryan's reissue decision)?
3. **Did r4 open anything new?** A guard refusing a legitimate act; a lock-order cycle; a moved check; a role or superuser path.
4. **Is there still a path around any rule?** Every role, isolation level and statement shape.
5. **Concurrency.** Every cap behind its lock; every money-freeing move taking the lock the next draw waits on.
6. **The invariants and the tests.** Any claim narrower than its check; any mutation passing for the wrong reason; anything missing.
7. **Residuals R1–R16.** Is any of them blocking?

## How to probe

**Opus and Fable** may query the running `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv23opus`, Fable `rv23fable`):
1. `CREATE DATABASE <name> TEMPLATE tally`.
2. Revoke TEMP on the clone from PUBLIC, `tally_app` and `tally_core` right after creating it.
3. `docker cp` the frozen patch into the container and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

-25 and -26 are not needed for this review.

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim must be a probe file in `tests/v5.4.2-23/review/codex-r4-probes/`. Each probe runs as the owner on a fresh clone with frozen r4 applied, ends in ROLLBACK, and prints SQLSTATE and message for each caught error with RAISE NOTICE. The author will run the probes.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role.
- Do not run `mutations-23.py`; it uses the fixed name `m23`.
- Run `cash-23.sh` only against your own clone; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.

## Output

Write your full review to `tests/v5.4.2-23/review/<reviewer>-r4.md` (`opus`, `fable` or `codex`). It should contain:
- a verdict: "ready" or "not yet";
- the round-3 findings, each marked closed, partly closed or not closed;
- blocking items (B1…), each with the concrete path or repro;
- should-fix items (S1…);
- notes (N1…).

Mark each claim as **executed** or **predicted**. Your final message, under 2 KB, gives the verdict, the blocking items in one line each, and the file path. If you cannot write the file, send the review to main as several messages, each under 3 KB.
