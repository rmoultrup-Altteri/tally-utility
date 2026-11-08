# Opus review — v5.4.2-24 r7 (unmatched cash and agency pledges)

**Date:** 2026-11-07. **Reviewer:** Opus. **Brief:** `review-brief-24-r7.md`. Its md5 is `e70288b521b4fa1d593caa1963e4391c`, which matches `review-brief-24-r7.md5`. I read the r7 plan, the r6-to-r7 diff and my own r6 review. I read no Fable or Codex review file.

**Verdict: not yet.** Nothing blocking. Two should-fix items:
- **S1:** a misposting return may give back less than what was misposted, and the rest can never be given back. The money is then held nowhere.
- **S2 (test only):** no test covers the half of the new recorded-time rule that refuses a time the owner chooses. With that half removed, every behaviour check still passes, and one receipt's money counts twice at a past instant.

Every round-6 finding is closed, and every earlier one still is. I found no date, and no pair of date and instant, at which one receipt's money counts twice in the patch as frozen.

## Hashes and reproduction (executed)

- **Hashes.** All six frozen md5s match the brief. The live patch, battery, race script and mutation runner have the same md5s as the frozen copies.
- **Clone.** I created `rv24opus` from `TEMPLATE tally` and revoked TEMP from PUBLIC, `tally_app` and `tally_core`.
- **Strict apply, twice.** `search_path=`, `check_function_bodies=on`, `ON_ERROR_STOP`. The first run was clean, including the tail's invariants. The second run printed `already applied (suspense_receipts exists); nothing to do`.
- **Battery** (`battery-24-frozen-r7.sql`): 275 PASS, 0 FAIL, rc 0. P9b2, P14i0 to P14i3, S4b and I9d2 pass with the messages the plan names.
- **Races** (`suspense-24-frozen-r7.sh rv24opus`): 24 PASS, 0 FAIL, rc 0.
- **Not run.** I did not run `ci.sh` or the mutation runner, and I did not apply -25, -26 or -30. r7 changes only the body of `enforce_suspense_disposition` and one line of the invariant. So I relied on the author's `ci.sh` result (63 of 63) for the order beside them. That part is predicted.
- **Restrictions kept.** I created, altered and dropped no role. I did not touch `tally`. I edited no repo file except this one. The clone is dropped, and my files in the container's `/tmp` are removed. Mutated function bodies were loaded only inside rolled-back transactions on my own clone.
- **How the probes ran.** They used a prefix of the battery: lines 1 to 1113, or lines 1 to 1388 for Q-M2. Then they ran as the owner (a superuser) or as `tally_app` at READ COMMITTED, in one transaction, rolled back. The probe files are in my scratchpad: `/private/tmp/claude-501/-Users-ryanscomputer-code-tally-utility/d46f327b-5792-45cc-8b71-44f90b3162fa/scratchpad/opus7/` (`q1.sql`, `q2.sql`, `q3.sql` and their `.out` files).

## 1. Is every round-6 finding closed, and every earlier one still?

| Finding | State | Evidence |
|---|---|---|
| r6 Codex B1: a misposting return recorded before the ledger row that gives the money back, so one receipt counted twice at that instant | **closed** | The walk now also takes the latest `created_at` in the posting entry's tree. A return stamped at its transaction's start retries (P14i, 40001). A return the owner stamps 1 microsecond before the reversal was recorded is refused (my QA, 23514: "money comes back only after what gives it back is known"). A return stamped at exactly the reversal's time is admitted (QA2). A second customer's payment stamped before that return is refused by the receipt's recorded order (QA3, 23514). Executed. |
| r6 Codex S1: the separate reversal-date check was redundant | **closed** | The check and its variable are gone. P9b2 now meets the tree-date message. The argument is right: the reversal the payment names is a row of the tree, so its date is at most the tree's last date. Read and executed. |
| r6 Codex S2: the invariant skipped a missing helper | **closed** | `coalesce(…, false)`. I9d2 drops `cash_source_lock_key(text, uuid)`, and the invariant names it ("tally_app has lost EXECUTE on a function its writes' guards call: cash_source_lock_key(…)"). Executed. |
| r6 Fable S1: no general check that a receipt's money is never in two places | **closed, with a limit** | S4b passes. It has teeth: with M113 loaded (the recorded-time rule off) and a return stamped at the transaction's start, S4b fails (my Q-M1). But it only checks one direction; see S1 and N2. Executed. |
| r5 and earlier | **still closed** | Only the misposting branch changed, and the battery and races pass. My r6 tree-freeze probes (Q1 to Q1c) ran against code r7 does not touch. Executed (battery and races). |

**Design and rulings.** Nothing outside the misposting branch changed. My r5 and r6 findings stand: the patch implements the design, CI-053's hold-and-resolve rule, the record side of CI-056, and Ryan's 11-07 rule (a refund of an agency's money goes to the agency) within limits L5 and L6. The one exception is S1, which falls short of CI-053's "never dropped".

### Why no instant counts the money twice now (read, pieces executed)

A read at instant X counts the receipt's share as given back only if the return's `created_at` is at or before X. The new rule makes the return's `created_at` at or after every row of the posting entry's tree, so those rows are visible at X too. The payment's `received` at X therefore already shows the reversal. The tree can't grow after the move to reversed (my r6 Q1 to Q1c: -23's guard is ENABLE ALWAYS). The return is also dated on or after the tree's last row. So at any date on which the return counts, the payment's `received` is at its final net. The receipt's recorded order (QA3) keeps any later spend of the returned money after the return.

## 2. Paths around the new rules

The r7 change adds one comparison in the AFTER INSERT trigger, under the receipt's lock, in the same walk as r6's. Multi-row inserts, writable CTEs and COPY fire the same row trigger, so I predict no change for those shapes (r1 probed them). Roles: `tally_app` can't choose `created_at` in a way that reaches the 23514 leg; the stamp is the database's. The owner can (QA). Every other path in the brief's list runs through code unchanged since r5, covered by my r1 to r6 probes and by the passing battery and races.

## 3. -23's and -27's properties

-24 still re-issues no -23 or -27 function. The new walk only reads `account_ledger`, so trigger order beside -23's doesn't matter for it. Read.

## 4. Concurrency

The tree walk runs without the payment's lock. That is sound for the same reason as r6: the tree is frozen once the payment is reversed, and the return requires a committed `reversed`. In READ COMMITTED each query in the trigger takes a fresh snapshot, so a tree row committed by a later transaction is seen and the 40001 leg fires. SU12 and SU12b cover the race. Executed (races).

## 5. The invariants

I9d2 closes the missing-function leg. `enforce_suspense_disposition`'s pinned md5 was updated, and the strict apply's tail passes. Executed.

## 6. The tests

See S2. P14i3's label matches its check: at the transaction's start instant the receipt holds 0, and at `clock_timestamp()` it holds 100. S4b's sum is right as an upper bound. What the receipt still holds already nets every disposition, returns included. Adding what the payments still have on the ledger, and the dispositions other than returns, gives at most the receipt exactly when no money is in two places. A refund paid from a payment still counts in `received`, so S4b errs toward flagging, never toward missing a double count. Executed and read.

## 7. Known limits L1–L5

Unchanged since r6; none is blocking. Read.

## B: blocking

None.

## S: should fix

**S1 (executed). A misposting return may give back less than what was misposted, and the rest is then lost for good.**

What it does to the money: a clerk records the return of a reversed payment and types 40 instead of 100. The database admits it, because a return may be *at most* the misposted share. After that:
- a second return is refused (the one-return-per-payment index);
- the return can't be undone (an undo may not name a misposting return);
- the payment is reversed for good.

So 60 of money the utility really received is held nowhere: not on the receipt, not on any customer's ledger, not refunded. CI-053 says unmatched money is "held, never dropped". The battery's S4b doesn't notice, because it only checks that money is never in two places, not that it is somewhere.

Probe Q1 (`tally_app`, READ COMMITTED): receipt R of 100 on 03-20. A payment of 100 from it to C1, posted, then reversed as misposted on 03-21 (`unpost`).
- QB1, return 40: **admitted**.
- QB2, return the other 60: refused, 23505 `suspense_receipt_dispositions_one_return_per_payment`.
- QB3, undo the 40 return: refused, 23514 "an undo names a disposition … that is not itself an undo".
- QB4, pay 100 from R to the right customer: refused, 23514 cap ("would come to 200.00").
- QB5: R holds 40.00. The payment's `received` is 0.00, and its ledger tree nets to 0.00. The other 60 is nowhere.
- QC: S4b, re-run over this state, passes.

There's no case for returning less than the share. The move to reversed requires the posting entry's tree to net to zero, and the share is exactly what came off the ledger less what the bank took. So the right return is always the whole share.

**Fix (rule: money is held, never dropped):** require `-NEW.amount = v_misposted`, refusing both more and less. The message should name the share. The alternative, letting several returns of one payment add up to the share, needs a cumulative cap and a change to the index. It is more code for no use I can see. Tests: a battery check that 40 of 100 is refused and 100 is admitted, and a mutation back to `>`. I haven't checked that every existing return in the battery and races gives back its full share. Any that gives less will need re-aiming. If the author wants a two-way net, S4b could also say that the receipt's amount, less what the bank or a state took, equals the sum. That needs the bank's take under each payment, so it's optional; see N2.

**S2 (executed). No test covers the 23514 leg of the new recorded-time rule (a time the owner chooses).**

The new rule has two outcomes:
- a return stamped at its own transaction's start retries (40001), tested by P14i;
- a return given an earlier chosen time is refused (23514).

No battery check, race or mutation reaches the second outcome. `grep` finds the message "money comes back only after what gives it back is known" nowhere in the battery, races or mutations. M113 turns off the whole rule and is met at P14i, on the first outcome.

What it does to the money if that refusal is lost: a history load records the return 1 microsecond after the payment's status stamp, before the reversal was recorded. That is the r6 Codex B1 shape again: at that instant one receipt's 100 counts as both on C1's ledger and held.

Probe Q-M2: I loaded `enforce_suspense_disposition` with only the 23514 `RAISE` replaced by `NULL`, then ran battery lines 21 to 1388 (U to T).
- 255 of 255 behaviour checks pass.
- The chosen-time return (`now() + 1µs`, before the reversal's `clock_timestamp()`) is admitted.
- S4b, appended after it, fails. So the double count is real, and only my added shape exposes it.

In a raw run the body-md5 pin would catch the edit. The mutation runner's `refill()` recomputes the pins, so a mutation of this leg would be reported MISSED.

**Fix (test only):** add P14i4 as the owner, in P14i's shape: a return with `created_at` between `now()` and the reversal's `created_at`, expected 23514 "money comes back only after". Add a mutation that removes that `RAISE` (or turns the `= now()` test into `true`), named at P14i4.

## N: notes

- **N1 (read).** In an owner's history load where the reversal is in the same transaction, the 40001 message says "retry", but retrying the same script fails the same way. The load must stamp the return explicitly, as P14i2 does. This is the same as `check_suspense_recorded_order`'s existing message. A word in the message ("or stamp it after that row") would help a loader. Optional.
- **N2 (read).** S4b sweeps only T1's receipts, and it is an upper bound by design: it catches money in two places, not money missing. S1 is the missing-money shape it can't see. A lower bound would need the bank's take under each payment and any unreturned misposted share, which the readers don't expose today. Optional after S1's fix, which removes the one way I found to lose money.
- **N3 (executed).** The new comparison treats equal stamps as known together. A return at exactly the reversal's `created_at` is admitted (QA2). That is consistent with every reader's `created_at <= p_recorded_at`.
- **N4 (read).** My r6 notes stand unchanged (P14g's label; a future-dated ledger row holds the return until that date; a misposted payment whose overpayment credit was refunded).
