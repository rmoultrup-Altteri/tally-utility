# Opus review: v5.4.2-24 r8 (unmatched cash and agency pledges)

**Date:** 2026-11-07. **Reviewer:** Opus. **Brief:** `review-brief-24-r8.md`. Its md5 is `1c45869648fdf7ad4507e5a73d9b130a`, which matches `review-brief-24-r8.md5`. I read the r8 plan, the r7-to-r8 diff and my own r7 review. I read no Fable or Codex review file.

**Verdict: not yet.** Nothing is blocking. Both round-7 findings are closed. There are two should-fix items:
- **S1:** money reversed as "posted to the wrong customer" but not yet returned to its receipt shows up on no reader. It isn't held, it isn't on any ledger, it isn't on the aged list, and it can stay that way forever.
- **S2 (wording only):** the table comment on `suspense_receipt_dispositions` still says a misposting return gives back "at most" the share. Once mirrored, that wrong contract text needs a new patch to fix.

## Hashes and reproduction (executed)

- **Hashes.** All six frozen md5s match the brief.
- **Clone.** I created `rv24opus` from `TEMPLATE tally`, then revoked TEMP from PUBLIC, `tally_app` and `tally_core`.
- **Strict apply, twice.** I used `search_path=`, `check_function_bodies=on` and `ON_ERROR_STOP`. The first run was clean, tail invariants included. The second run printed "already applied (suspense_receipts exists); nothing to do".
- **Battery** (`battery-24-frozen-r8.sql`): 277 PASS, 0 FAIL, rc 0. P9b3b, P14b, P14c, P14e, P14f, P14i4 and S4b pass with the expected messages.
- **Races** (`suspense-24-frozen-r8.sh rv24opus`): 24 PASS, 0 FAIL, rc 0.
- **Not run.** I did not run `ci.sh` or the mutation runner, and I did not apply -25, -26 or -30. r8 changes one comparison, one message and a comment in `enforce_suspense_disposition`, so for the order beside those patches I rely on the author's `ci.sh` result (63 of 63). That part is predicted.
- **Restrictions kept.** I created, altered and dropped no role. I did not touch `tally`, and I edited no repo file except this one. Mutated function bodies were loaded only inside rolled-back transactions on my clone. The clone is dropped, and my files in the container's `/tmp` are removed.
- **Probe files** are in `/private/tmp/claude-501/-Users-ryanscomputer-code-tally-utility/d46f327b-5792-45cc-8b71-44f90b3162fa/scratchpad/opus8/`: `q1.sql`, `q2.sql`, `mut_a.sql`, `mut_b.sql`, `mut_c.sql` and their `.out` files. Each probe is the battery's lines 1 to 1122 (or 1 to 1116 for the mutants), then my statements, rolled back. Writes ran as `tally_app` at READ COMMITTED unless noted.

## 1. Are the round-7 findings closed, and the earlier ones still?

| Finding | State | Evidence |
|---|---|---|
| r7 Opus S1: a short misposting return stranded the rest | **closed** | `IF -NEW.amount <> v_misposted`. My r7 shape, re-run (q1, a receipt of 100 paid to C1 and reversed as misposted): returning 40 is refused (23514, "gives back exactly what payment … reversed as misposted (100.00 of its 100.00 …), not 40.00"). 100.01 is refused the same way, and 100 is admitted. A second return is refused (23505, the one-per-payment index). The receipt then holds 100, and paying it to the right customer, dated on or after the return, is admitted: held 0, on ledgers 100. Another 0.01 is refused by the cap. Executed. |
| r7 Opus S2: no test of the refusal of an earlier time chosen by the owner | **closed** | P14i4 passes, met at "before a row under its posting entry recorded at". Its time, `now() + (reversal's created_at - now())/2`, falls strictly between the transaction's start and the reversal, so it reaches the 23514 branch and not the 40001 retry. Mutant (a), with only that `RAISE` removed: 208 PASS, then the first failure is P14i4 "accepted". Mutant (b), M116 as written: the same, first failure P14i4. Executed. |
| r7 re-aimed checks (P14b, c, e, f) | **sound** | Each now offers the amount a known wrong rule would give: 100, 100, 100, 90. So each fails if the share rule drifts, not just if the comparison does. Mutant (c), with the rule turned to "at least": the first failure is P9b3. The 50.01 return was caught there by the cap's "giving back more than was taken" instead of the share message, so the cap still backs up an over-return. Executed. |
| r6 and earlier | **still closed** | r8 touches nothing else. The battery and races pass, my r7 table's evidence still applies to unchanged code, and S4b still passes. Executed (battery, races). |

**Does an exact return refuse any legitimate return, or strand money another way?**
- **A share of 0** (the bank took everything): every return is refused, since `amount <> 0` is a CHECK and the share is 0. That is right: nothing is owed back. Read, and P14b executed.
- **A share in fractions of a cent:** this can't happen. `account_ledger.amount`, `payments.amount` and the disposition's amount are all `numeric(12,2)`. Executed (catalog).
- **Can the share change after the return?** The tree is frozen once the payment is reversed. A reversed payment can't later be voided, by `tally_app` or by the owner (23001, -23's status rule; q1 QB7, QB8), so the cap can't lose the payment under the return. Executed.
- **Can the cap refuse an exact return?** No. A return only lowers the receipt's running total. On every date on or after the return, the payment it gives back is already counted, so the total can't go below zero. Read.
- **A share the clerk can't read:** the refusal message states it, but no reader does; see S1.
- **An overpayment credit already refunded to the wrong customer:** the whole share still comes back. I judged that right in r6 (N3): the true payer paid. The exact rule only removes the option of returning less, which that case didn't need either.

**Design and rulings.** The design and the rulings stand as in my r7 review: CI-053's hold-and-resolve, the record side of CI-056, and Ryan's 11-07 rule (agency money refunded to the agency) within L5 and L6. S1 is a gap in CI-056's fail-loud surface.

## 2 to 5. Paths around the rules, -23 and -27, concurrency, the invariant

r8 changed no table, trigger order, lock or reader. It changed one comparison, its message, the function's comment and that function's body pin in the invariant. The tail invariants pass with the new pin. My r5 to r7 answers on receipts spent twice, dates, tenants, provider transactions, pledges, agencies, agreements, lock order and trigger order beside -23 apply unchanged. The battery and races that hold them pass. Executed (battery, races, apply); the reasoning is read.

## B: blocking

None.

## S: should fix

**S1 (executed). Money waiting on a misposting return appears on no reader, for as long as no one files the return.**

When a payment made from a receipt is reversed with no return code, its money leaves the customer's ledger. It comes back to the receipt only when a clerk files a misposting return. That is the r2 design: -23 also lets a bank's take-back be entered as a plain reversal, so the database can't tell the two apart. Until the return is filed:
- the receipt shows nothing held, because the payment still counts against it;
- the payment shows nothing received;
- `suspense_receipts_aged_as_of` doesn't list it;
- `suspense_held_as_of`, the figure L4 says reconciles the subledger to the bank, is short by the whole amount.

Probe q2 (tally_app): receipt of 100 on 03-20, paid to C1, reversed as misposted on 03-21, service level 10 days. Read on 10-31, 224 days later: held 0.00, on customers' ledgers 0.00, on the aged list 0 times. After the return is filed it appears on the list (1).

What this does to the money: 100 of real cash sits on no customer's account, isn't counted as held, and isn't flagged past the service level. CI-053 says unmatched money is held and never dropped, and CI-056 says it fails loud past the service level. Here it is dropped from every view, silently. r8 made sure the money can always come back, but nothing prompts anyone to bring it back. A bank take-back entered as a reversal sits in the same blind spot, and that case also needs someone to look and decide.

**Fix (rule: CI-056, fail loud; additive):** the cheapest options are these.
- (a) A STABLE reader, for example `suspense_returns_awaiting_as_of(tenant, on, recorded)`. It lists each payment made from a receipt that is reversed with no return code and has no misposting return, with its share and its days since the reversal against the service level.
- (b) Move the share walk into a helper, say `suspense_misposted_share(payment)`. Both the trigger and the reader would call it, so the C# core never re-implements the walk, and a clerk can read the exact amount the rule demands.

The other option is to record this as a known limit (L7) and make it the core's job. That puts the "fail loud" duty in code that doesn't exist yet. Under the standing rule that the design is permanent, I recommend the reader. The ruling text needn't change. The reader could also feed -26's `aged_suspense` condition, which is the author's call.

**S2 (read). The table comment states the old rule.**

`COMMENT ON TABLE public.suspense_receipt_dispositions` (patch line 449) still says a misposting return gives back "at most what non-NSF rows reversed of it, dated on or after the reversal". That is wrong in three ways now:
- it is exactly the share (r7);
- an nsf row that gives money back is counted (r5, r6);
- the return is dated on or after every row under the posting entry, and recorded no earlier than all of them (r6).

The function's comment is right. The table comment is what an application developer reads first. A developer who believes "at most" would build a partial-return screen, and that screen is now refused on every partial amount. Once mirrored into `tu.sql`, the text can be corrected only by a later patch.

**Fix:** reword the table comment to match the function's: "exactly the net of the posting entry's tree, with every nsf row that takes money, and what is beneath it, left out; dated on or after, and recorded no earlier than, every row of that tree; once; never undone". No test is needed.

## N: notes

- **N1 (executed). M116 removes more than its label says.** It inserts `RETURN NULL;` before the `RAISE`, which also skips the receipt cap after it. It is still caught at P14i4 as the first failure, and so is the narrower mutant that removes only the `RAISE` (mutant a). So the check is sound. A narrower M116 (`RAISE` replaced by `NULL;`) would test exactly what it names. Optional.
- **N2 (executed). Paying the right customer must be dated on or after the return.** In q1, paying the returned 100 to the right customer with payment date 03-20 (the receipt's date) is refused: "on 2026-03-20 … would come to 200.00". On that date the money wasn't back yet. Dated 03-21, with effective date 03-20, it is admitted, so the right customer is still credited as of when they paid. That is correct. The application and the core should default the payment date to the return's date. Worth a line in the application contracts.
- **N3 (read). The design document stops at round 4** (section 11). Rounds 5 to 8 live only in the plans. Its round-3 section still says "at most what non-NSF rows reversed", which is accurate as history. A one-paragraph "as of r8" summary would save the next reader from walking five plans. Optional.
- **N4 (read). My r7 notes stand.** First, the 40001 "retry" message misleads a history load that would fail the same way on retry. Second, S4b catches money counted in two places but not money that is in none of them. S1 is the second kind, and S4b can't see it.
