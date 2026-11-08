# Opus review — v5.4.2-24 r6 (unmatched cash and agency pledges)

**Date:** 2026-11-07. **Reviewer:** Opus. **Brief:** `review-brief-24-r6.md`. Its md5 is `5445398e46075576da4f0dd966c68d0f`, which matches `review-brief-24-r6.md5`. I read the r6 plan and my own r5 review. I read no other reviewer's file.

**Verdict: ready.** No blocking or should-fix items.

Both round-5 blockers are closed:
- A row typed nsf that gives money back is now counted in the misposted share (my r5 B1).
- A misposting return can no longer be dated before the last row under the posting entry (Codex r5 B1).

I looked for a date, or a recorded instant, on which one receipt's money counts twice. I found none. The reason is a chain of rules:
- The tree under a reversed payment is frozen, for every role, even with triggers set to replica.
- The return is dated on or after the tree's last row.
- The return is recorded after the payment's move to reversed, and that move is recorded after every row of the tree.

The plan's argument that the payment bound can't be reached is right.

## Hashes and reproduction (executed)

- **Hashes.** All six frozen md5s match the brief. The live patch, battery, race script and mutation runner have the same md5s as the frozen copies.
- **Clone.** I created `rv24opus` from `TEMPLATE tally` and revoked TEMP from PUBLIC, `tally_app` and `tally_core`.
- **Strict apply, twice.** I set `search_path=` and `check_function_bodies=on`, with `ON_ERROR_STOP`. The first run was clean, and the tail's invariants passed. The second run printed `already applied (suspense_receipts exists); nothing to do`.
- **Battery** (`battery-24-frozen-r6.sql`): 269 PASS, 0 FAIL, rc 0.
- **Races** (`suspense-24-frozen-r6.sh rv24opus`): 24 PASS, 0 FAIL, rc 0.
- **Not run.** I did not run `ci.sh` or the mutation runner, and I did not apply -25, -26 or -30. r6 changes only the body of `enforce_suspense_disposition`, so I relied on the author's `ci.sh` result (63 of 63) for the order beside them. That part is predicted.
- **Restrictions kept.** I created, altered and dropped no role. I did not touch `tally`. The clone is dropped, and my files in the container's `/tmp` are removed.
- **How the probes ran.** They used battery lines 1 to 621 as a prefix: the fixtures and checks through P14h4. Then they ran as `tally_app` at READ COMMITTED, and as the owner, which is a superuser. It was one transaction, rolled back.

## 1. Are round 5's findings closed, and every earlier one still?

| Finding | State | Evidence |
|---|---|---|
| r5 Opus B1: an undo typed nsf was left out of the share, so too much came back | **closed** | Both legs of the walk now leave out only `nsf` rows with `amount > 0`. P14e and P14e2 cover my shape B and give 50. P14f and P14f2 cover my Q4 and give 70. P14g covers Fable's FA and gives 100, not 200. All pass. Executed. |
| r5 Codex B1: a return dated before a later row under the posting entry counted one receipt twice | **closed** | A second walk, by the link alone, finds the latest `transaction_date` in the posting entry's tree, and a return dated earlier is refused. P14h to P14h4 pass. My own shape Q4 (below) is refused one day early and admitted on the last row's date. Executed. |
| r5 Fable S2: the payment bound | **argument right** | See item 3. Read, and the sign rule executed. |
| r5 Fable S1: the catalogue comment; Codex S1: test labels | **closed** | The comment now describes the misposting branch, the tenant check, the recorded order and the r6 date rule. The race header says "inserts a pending payment". The second G6 is now G6g. Read. |
| r4 and earlier | **still closed** | Only the misposting branch changed, and the battery and races pass. Executed. |

Every other path is unchanged since my r5 review, which found that the patch implements the design, CI-053, the record side of CI-056, and Ryan's 11-07 rule within limits L5 and L6. That finding stands.

### What a return can and can't do now (executed, as `tally_app`)

| Probe | What it tries | Result |
|---|---|---|
| Q1 | After P14h3's return (03-13) on payment 7b, record an undo (−100) of the second reversal, dated 03-14. This would give the payment its 100 back while the receipt holds the same 100. | Refused 23001, by -23: "gives money back to payment …, which has ended: post a new payment" |
| Q1n | The same, typed nsf | Refused 23001, the same guard |
| Q1b | Q1 as the owner (a superuser) | Refused 23001 |
| Q1c | Q1 as the owner with `session_replication_role = replica` | Refused 23001 (-23's guard is ENABLE ALWAYS) |
| Q3 | A negative nsf row directly under the posting entry | Refused 23514 by -23's sign rule (R-02) |
| Q4 | Receipt 100 and its payment to C1. The bank takes 40 (03-11). Misposted 60 (03-12). The bank's take-back is undone (−40, 03-20). Misposted the remaining 40 (03-21). | Before 03-21 the move to reversed is refused, because 40 is still on the ledger. After it: a return dated 03-20 is refused ("the last row under its posting entry (2026-03-21)"); 100.01 on 03-21 is refused; 100 on 03-21 is admitted. |
| Q4, by date | Receipt held, then the payment's received | 03-11: 0 and 60. 03-12: 0 and 0. 03-20: 0 and 40. 03-21: 100 and 0. No date counts the money twice. |
| Q5 | A second return of the same payment | Refused 23505 (`suspense_receipt_dispositions_one_return_per_payment`) |

Q4 also shows the share is right when the bank first takes money back and then pays after all. The bank's subtree nets to 0, so the whole 100 comes back. That is the money that really arrived.

### Recorded instants (read; pieces executed)

The new rule covers money dates. For a read at an earlier recorded instant, the order comes from four rules that link together:
- **The return is recorded after the move to reversed.** `check_suspense_recorded_order` reads the payment's `status_recorded_at` once it is reversed. This was executed in r3.
- **The move to reversed is recorded after every row of the tree.** For a chosen time, -23's `cash_lineage_recorded` includes `ledger_tree_ids` of the arrival entry. For an app-path time, the row lock and `now()` give the same order.
- **The tree is frozen once the payment is reversed** (Q1 to Q1c).
- **Any recorded instant that shows the return also shows the whole tree.** That follows from the first three, so the payment's received is at its final net at every money date on or after the return.

So I found no recorded instant at which the receipt holds the share while the payment still counts it.

## 2. Paths around the new rules

The r6 change is confined to the misposting branch. Each of the brief's other paths (a receipt spent twice, payments out of bounds, guessed applications, a provider transaction recorded twice, pledges, lapses, agency refunds, agreements) runs through code unchanged since r5. My r1 to r5 probes cover them, and the r6 battery and races still pass. Statement shapes (multi-row, writable CTE, COPY) were probed in r1. The new code runs in the same AFTER ROW trigger, under the same receipt lock, so I predict no change there. A multi-row VALUES insert into the ledger (Q4's three rows in one statement) behaved as row-by-row.

## 3. -23's and -27's properties; the payment bound

- **The bound argument is right.** -23 records the posting entry at exactly minus the payment's amount. It keeps every entry's tree net between 0 and its own amount, by sign, on every date. The walk drops only subtrees rooted at a positive nsf row, each of which nets between 0 and its amount, at any depth. So what the walk sums is at most the posting tree's total, which is at most the payment. `least(v_pay.amount, …)` is then an unreachable guard. Recording it as an equivalent mutation, not a missing test, is the right call.
- **The first-leg `amount > 0` condition is unreachable for the same reason** (Q3): no negative row can sit directly under the posting entry. That is why M111 mutates only the second leg. This is consistent with the plan. Executed.
- -24 still re-issues no -23 or -27 function. The two new walks only read the ledger, so the order of the triggers beside -23's doesn't matter for them. Read.

## 4. Concurrency

The new date walk reads the tree without the payment's lock. That is sound, because the tree can't change once the payment is reversed (Q1 to Q1c), and a status never moves back from reversed. The cap and the order check still run under the receipt's lock, as before. Read and executed.

## 5. The invariants

`c_bodies` pins the new body md5 (`eac03f6e…`), and the tail ran clean on the strict apply. Nothing else in `assert_suspense_pledge_guard_invariants()` changed. Executed.

## 6. The tests

- M111 removes the undo-counting condition on the second leg, which P14e's shape needs, so it is named at P14e. M112 turns off the date rule, named at P14h. Both target exactly the r6 change. I did not run them (the runner is reserved).
- See N1 for P14g.

## 7. Known limits L1–L5

None blocks. L4 (what the misposted share counts) is now settled by the r6 walk.

---

## B: blocking

None.

## S: should fix

None.

## N: notes

- **N1 (read). P14g checks only the refusal.** Its label says "100 comes back, not 200", but it only refuses 100.01. It never admits 100. P14e2 and P14f2 do admit their amounts. An admits-100 check would make P14g say all of what its label claims. It is cosmetic: the walk's sum for FA is pinned by the refusal together with P14e and P14f.
- **N2 (predicted). A row dated in the future under the tree holds the return until that date.** The return is dated on or after the tree's last row, and no later than today (UTC+14). If -23 admits a ledger row dated ahead, the misposted money stays in the payment, not in suspense, until that day comes. That fails toward keeping the money spent, and the date passes by itself. No change.
- **N3 (predicted). A misposted payment whose overpayment credit was already refunded.** -23 lets such a payment be reversed when the refund is posted ("what the credit paid out stands"). The customer then owes the refund (K-10). The receipt gets the payment's whole misposted share back, because the true payer did pay it. So the receipt's 100 can credit the right customer 100 while the wrong customer owes the 30 the utility refunded in error. I think that is the right outcome: the payer doesn't bear the utility's mistake, and the 30 is the utility's to recover. It matches K-10's rule for bank returns. Worth a sentence in the operator guidance, not the schema.
- **N4 (carried).** My r5 notes N1 (a misposting reversal filed under the undo of a bank's take-back holds the money until it is filed again) and N5 (`c_app_exec` drops a missing function silently; `coalesce(…, false)`) stand. The plan records both.
- **N5 (environment).** The two `crystaldba/postgres-mcp` containers are still running beside `tally-pg`. I left them alone.
