# Opus review: v5.4.2-24 r13 (tests only, confirmation)

**Date:** 2026-11-24. **Reviewer:** Opus. **Brief:** `review-brief-24-r13.md`, md5 `e6448acd982799d2d96993f650f682e7`, which matches its `.md5`. I read the r13 plan, `r12-to-r13.diff` and my own r12 review. I read no Fable or Codex file.

**Verdict: ready.** The new S4c term is right for both of my r12 shapes and for every other shape I tried. P25 and P25b each make r12's term fail on their own. The re-pointed mutations each fail first at the check they now name. The helper change leaves every fixture's number as it was.

- **B:** none.
- **S:** none.
- **N1 (executed):** the battery has two checks labelled each of D1, D2, D3, D4 and D4b (the deposit fixtures and the closed-period section). This was already so in r12; r13 did not add it. The runner matches the first failure by label, so a mutation named D2 would also count as caught if it slipped past the deposit D2 and then tripped the closed-period D2. It does not happen today: M171 fails at the deposit D2 (its text is "its misposted 60 is the share"). Renaming one set (say, the closed-period ones to F1 to F4b) would remove the ambiguity. No change needed for this round.
- **N2 (executed, environment):** running the battery back to back on one clone without a `VACUUM` in between made S4b take over five minutes (I cancelled it). After `VACUUM ANALYZE` it took 83 to 104 s for the whole battery. `ci.sh` and the mutation runner already vacuum before each run, so this is only a hazard for hand runs.

## Hashes and reproduction (executed)

- All six frozen md5s match the brief: patch `37630681…`, battery `0ec62ea3…`, races `360dea4d…`, mutations `d4b925f7…`, ci diff `ec30f743…`, r12-to-r13 `9bbb3fc9…`. The frozen r12 patch has the same md5 as r13. The live patch, battery, mutation runner and race script are byte-identical to the frozen r13 copies (`cmp`).
- Clone `rv24opus` from `TEMPLATE tally`, TEMP revoked from PUBLIC, `tally_app` and `tally_core` right after creation. Strict apply (`search_path=''`, `check_function_bodies=on`): rc 0. Second apply: "already applied (suspense_receipts exists); nothing to do", rc 0.
- `battery-24-frozen-r13.sql`: **355 PASS, 0 FAIL**, rc 0. D2, D2b, D2c, P25, P25b and S4c all pass.
- I did not run the races, `ci.sh` or `mutations-24.py`. The patch and the race script have not changed since r12. For the mutations, see question 3.
- The clone is dropped (`pg_database` count 0), and the container's `/tmp/opus-*` files are removed. No repo file was changed except this one.

## 1. Is S4c's new term right in every shape? (executed)

The new term counts a receipt's payment that is not voided and is dated by day d, when the payment has no posting entry (`payment` or `deposit`, not a reversal row) dated on or before d. It no longer reads the status. My r12 shapes:

- **A pending payment with its posting entry (P25):** from the entry's date, the ledger reader counts the 100 and the new term counts 0. The total is 100, not 200.
- **A posted payment whose entry is dated after its payment date (P25b):** on the days before the entry, the new term counts the 100 and the ledger reader counts 0. The total is 100, not 0.

Other shapes. Each was a probe block inserted just before S4c in a scratch copy of the frozen battery, run as the owner, dated in April (after the battery's closed period), with the receipt's readers printed for 04-09 to 04-16:

| Probe | Shape | What -23/-24 did | S4c |
|---|---|---|---|
| Q1 | a pending payment with its entry, then voided | refused, 23001 "is on the ledger: it is reversed, not voided" | passes (355) |
| Q2 | a posted payment, then voided | refused, 23001 "cannot move from posted to voided" | passes |
| Q3 | posted, the entry undone on 04-12, then a second posting entry | the undo is admitted; the second entry is refused (23505, `account_ledger_payment_arrival_key`) | passes; ledger 100 to 04-11, then 0, with the misposted share carrying it |
| Q3b | a pending payment's entry undone while it is still pending | refused, 23514 "is moved to posted before its posting entry is undone" | passes |
| Q4 | a deposit whose entry is dated two days after its payment | admitted | passes; ledger 0 on 04-10 and 04-11, 100 from 04-12; the new term carries the gap |
| Q5 | a posting entry dated before its payment date (entry 04-11, payment 04-12) | admitted | passes; the receipt holds 100 until 04-12 and the payment reader shows no row before its payment date, so neither counts twice |
| Q6 | a 60 payment from a 100 receipt, its entry dated three days late, then bounced | admitted | passes; 40 held throughout, and the 60 moves from the pending term to the ledger to the bank's part |

A voided payment can never carry a posting entry (Q1, Q2), so dropping voided payments at every date matches the receipt reader, which also gives a voided payment's money back at every date. One payment has at most one posting entry (Q3), so the NOT EXISTS test cannot be satisfied by a later re-posting. The term never counts a payment twice and never drops one in any shape I could build.

## 2. Do P25 and P25b test what they claim? (executed)

Both fixtures set up the exact shapes from my r12 Q5b and Q5c. Their own checks read the patch's readers (the receipt holds 0; the ledger has the 100 from the entry's date only), and both pass. S4c is their real oracle. I put r12's term back into a scratch copy of the frozen battery (a one-line diff, checked against `battery-24-frozen-r12.sql`) and ran it four ways:

| Copy | Result |
|---|---|
| r12 term, both fixtures | 354 PASS, then **FAIL S4c** |
| r12 term, P25 only | 353 PASS, then **FAIL S4c** |
| r12 term, P25b only | 353 PASS, then **FAIL S4c** |
| r12 term, neither fixture | **353 PASS**, rc 0 |

Each fixture is enough on its own to catch r12's term, and without them r12's term passes. That is the gap they close.

## 3. Do the re-pointed mutations name the right check? (executed)

I loaded the frozen mutation list read-only and applied each of the five mutations to the frozen patch. For each one I made a fresh `rv24opus`, revoked TEMP, applied strictly, ran `VACUUM`, ran the frozen battery, and took the first failure using the runner's rule:

| Mutation | Defect | Named | First failure |
|---|---|---|---|
| M118 | the returns-due reader lists a payment with no share | D2c | D2c (the reader lists it on 03-10 owing 0) |
| M138 | the share at a date is the final share | D2c | D2c |
| M129 | the reader lists only a reversed payment | D2b | D2b (the deposit payment is still posted) |
| M175 | the dated share walks no deposit | D2b | D2b |
| M171 | the undated share walks no deposit | D2 | D2 "its misposted 60 is the share" (the deposit D2, not the closed-period D2; see N1) |

Each one breaks exactly the fact its check now states. In each case the check before it passes: M118 and M138 pass D2 and D2b; M129 and M175 pass D2.

## 4. Does the helper change alter a fixture's number? (executed and static)

`rcpt()`, `fromr()`, `pledge()` and `apay()` keep four hex digits when the id starts with `00000000-0000-4000-8000-0000000`, which covers every `k()` id (`…0000000a24xx`), every `n()` id (`…0000000c25xx`) and the tenant constants. Every other id uses twelve. Every call passes `k()`, `n()` or `gen_random_uuid()`. So every fixture number is unchanged. The one check that rebuilds a number by hand, U6 at line 227 (`'R24-' || right(pg_temp.k('01')::text, 4)`), still matches the helper's four digits for `k('01')`. A random id's number is now `P24-` plus twelve hex digits, which cannot equal any four-digit fixture number. The one random `rcpt()` (D1, closed period) is refused before its check number matters. The full battery passes 355 with the change.
