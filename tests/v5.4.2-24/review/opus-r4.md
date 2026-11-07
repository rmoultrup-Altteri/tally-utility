# Opus review — v5.4.2-24 r4 (unmatched cash and agency pledges)

**Date:** 2026-11-07. **Reviewer:** Opus. **Brief:** `review-brief-24-r4.md` (md5 `d8c1885c9ef22a13f1334822634ee8d0`, which matches its `.md5`). I read the r2, r3 and r4 plans and my own r3 review. I read no other reviewer's file.

**Verdict: ready.** No blocking item. Round 3's blocker is closed. The misposted share now nets each reversal's own tree, so it matches -23's tree. Every tree shape I built gave the right amount: a reversal re-entered, a reversal undone before a bounce, a bounce that was itself undone, and a mixed three-level tree. After the move to `reversed`, the tree can't change. The other three round-3 fixes hold as well. One should-fix item is about a test and a message. The new below-zero refusal is reached by a real shape: a misposting return dated before the payment's own date. Round 3 accepted that shape, and the receipt then read 200 held on a receipt of 100. The plan says no path to a negative position is known, and the battery has no case of its own for it. Everything else is a note.

## Hashes and reproduction (executed)

- **Hashes.** The six frozen md5s match the brief: patch `8acade88…`, battery `414ff52a…`, races `88c9c30b…`, mutations `21e01cf8…`, ci diff `c343828b…`, r3-to-r4 diff `7a333752…`.
- **Clone and apply.** I made the clone `rv24opus` (`TEMPLATE tally`) and revoked TEMP from PUBLIC, `tally_app` and `tally_core`. The strict apply (`search_path=`, `check_function_bodies=on`) returned rc 0, and the tail's invariants passed. The second run printed `NOTICE: v5.4.2-24: already applied (suspense_receipts exists); nothing to do` and returned rc 0.
- **Battery.** `battery-24-frozen-r4.sql`: 256 PASS, 0 FAIL, rc 0.
- **Races.** `suspense-24-frozen-r4.sh rv24opus`: 24 PASS, 0 FAIL, rc 0 (SU1–SU12).
- **Not run.** I did not run `ci.sh` or the mutation runner. I did not apply -25, -26 or -30: r4 changes only -24's own functions, so I relied on the author's `ci.sh` result for the ordering beside them (predicted).
- **Restrictions kept.** I created, dropped or altered no role, and I did not touch `tally`. The clone is dropped, and `/tmp/rv24opus` is removed from the container.
- **How the probes ran.** Each probe used battery lines 1–179 (the helpers and fixtures) as a prefix. My helpers (`try`, `led`, `rev`) were created as the owner and granted to `tally_app`. The probe then ran under `SET ROLE tally_app` at READ COMMITTED, unless it is marked as a superuser load. Each probe was one transaction, rolled back. The scripts were scratch files and are not in the repo.

## Round-3, round-2 and round-1 findings: are they closed?

| Finding | State | Evidence |
|---|---|---|
| r3 Opus B1, Fable B1 (the misposted share) | **closed** | See "The misposted share" below. Executed. |
| r3 Opus S1 (a NaN payment naming a pledge) | closed | `payments_agency_pledge_check` gains `amount <> 'NaN'`, and its manifest line matches. Battery L7f passes. `'Infinity'` can't reach these columns, because `numeric(12,2)` refuses it ("cannot hold an infinite value"). Executed. |
| r3 Opus S2 (P9b3's label) | closed | Relabelled. P14a and P14b now test the tree. M106 is caught at P14b. Read (mutation not run). |
| r3 Fable (cap below zero) | closed, but see S1 | `WHERE w.o > v_amount OR w.o < 0`. Executed: Q5 below. |
| r3 Fable S1 (third branch self-exclusion) | closed | The third branch of `check_suspense_recorded_order` excludes its own payment. Battery O4 (a load born voided, voided after its insert) passes. The order check runs only when a payment or a disposition is inserted, so excluding the row's own void can't hide another row. Executed (battery) and read. |
| Round 2 (releases ordered, per-table self-exclusion, partial bounce, NaN, the invariant's reach, foreign keys off) | still closed | Unchanged code paths. Battery P13, O1g and I9* pass, and SU11 and SU12 pass. Executed. |
| Round 1, all | still closed | Unchanged. The battery and the races pass. Executed. |

The patch implements the design, CI-053, CI-056's record side, and Ryan's 11-07 rule within L5 and L6.

### The misposted share (executed)

The rule is: the sum over the posting entry's direct non-NSF children of `ledger_entry_remaining(child)`, clamped to the range 0 to the payment. Two facts from -23 make this exact:

- **The cap.** -23's per-ancestor cap (R-02) keeps every child's remainder between 0 and its own amount.
- **The move.** The move to `reversed` requires the posting entry's remainder to be 0.

So the non-NSF share plus the NSF share equals the payment, and each share has its own sub-trees netted. `account_ledger_payment_arrival_key` makes the posting entry unique per payment, so no second root can add to the sum. I ran each case as `tally_app` at READ COMMITTED:

| Case | Tree under the posting entry (−100) | Return allowed | Probe result |
|---|---|---|---|
| Q1 (r3 B1, shape 1) | adj +100, undone by −100; adj +100 again | 100 | 200 and 100.01 refused; 100 admitted; a second return refused (`…one_return_per_payment`); then 100.01 dated 03-13 from the receipt refused by the cap, 100 admitted |
| Q2 (r3 B1, shape 2) | adj +100 undone by −100; nsf +100 | 0 | move to `reversed` naming the undone adj admitted by -23; return of 0.01 refused ("0 of its 100.00") |
| Q3 (r3's fourth case) | nsf +100 undone by −100 (check cleared); adj +100 | 100 | 100.01 refused, 100 admitted |
| Q4 (three levels, mixed) | nsf +40 undone by −40; nsf +30; adj +70 with an nsf-typed −20 under it; adj +20 | 70 | remaining(e) = 0, remaining(adj 70) = 50; 70.01 refused, 70 admitted |

**Is the tree frozen after the move?** Executed. Each of these was refused once the payment was reversed:

- Q1g: a give-back row under the re-entry was refused with 23001 ("gives money back to payment …, which has ended").
- Q1i: the same row with no reference fields set was refused the same way, because -23 keys the rule on the tree's root.
- Q1h: a take-away row (+100 under the undo) was refused with 23514 by -23's per-ancestor cap ("would come to 200.00, outside 0 to 100.00").

So the share read at the disposition can't change afterwards. And because the disposition reads `status = 'reversed'`, the move must have committed first.

**Other ways of reaching `reversed`.** Executed:

- `tally_app` can't insert a payment already reversed. -23 refuses it ("is born reversed, naming none").
- A superuser history load can insert one (H1: admitted). But it has no posting entry, so its misposting return reads 0 and is refused (H1b: "0 of its 100.00"). This fails toward protection.
- A posting row can be written only for a pending payment, so a load must post and then reverse, and that goes through the netting above.

**Is the bound at the payment dead code?** The `least(v_pay.amount, …)` and `greatest(0, …)` clamps can't bind while -23's cap holds. They are defence in depth, and the plan says the bound is shown only by M106 (where it holds P14a). That is fine.

---

## B: blocking

None.

---

## S: should fix

### S1. The below-zero refusal is reached by a real shape. It has no battery case, and its message misleads the clerk (executed)

The r4 plan says: "no path to a negative position is known after item 1." There is one.

**The shape.** A payment made from a receipt has a `payment_date` (the day it was resolved). Its posting ledger entry may be dated earlier, for example on the day the money came, which is also the payment's `effective_date`. -23 ties the posting row's amount, kind and account to the payment, but not its date. A reversal can then be dated after the posting entry but before `payment_date`. A misposting return dated on or after that reversal passes the return's own date rule. But the receipt's cap counts the payment only from `payment_date`. So on the days in between, the return gives back money the cap doesn't yet count as spent.

**Probe Q5** (as `tally_app`):

- A receipt of 100 dated 03-01.
- Its payment to C1 dated 03-10 and effective 03-01.
- The posting entry dated 03-01.
- A reversal (adjustment +100) dated 03-06, then the move to `reversed`.
- A misposting return of 100 dated 03-06.

```
r4:  Q5a return dated 03-06 => REFUSED 23514 suspense receipt R24-24a5: on 2026-03-06 its payments and
     dispositions would come to -100.00, giving back more than was taken from the 100.00 the receipt holds
     Q5 held on 03-07 | 100.00          (the return dated 03-10 is admitted)
r3's cap (the r4 cap with "OR w.o < 0" removed, in the same rolled-back transaction):
     Q5a => ACCEPTED
     Q5 held on 03-07 | 200.00 | amount 100.00 ;  suspense_held_as_of(T1, 03-07) = 200.00
```

So r3 let the receipt read 200 held on a receipt of 100 from 03-06 to 03-09. That figure feeds CI-056's aged-suspense reporting and -26's `aged_suspense` condition. I found no way to actually spend the extra 100: a payment dated in the gap still meets the cap on 03-10. So this was an overstated reading, not an overspend, and r4 refuses it. That is why this item isn't blocking.

**What to fix:**

1. **A battery case.** Add Q5 as a battery case for the below-zero clause. Today the clause is shown only by mutation M15, which removes a different rule. This shape is the one that reaches the clause in normal use.
2. **A clearer refusal.** The clerk is told they are "giving back more than was taken", when the real problem is the date. Prefer one more line in the misposting-return branch: require `disposed_on >= greatest(v_rev_on, v_pay.payment_date)`, with a message naming the payment's date. Keep the below-zero clause in the cap as the backstop. A mutation that drops the new date clause would then be caught by Q5 at its own check, not at the cap.

---

## N: notes

- **N1 (executed). -23's and -27's properties.**
  - r4 adds one read of -23's `ledger_entry_remaining` (STABLE, security invoker, plan-pinned) inside -24's AFTER INSERT trigger on dispositions. It writes nothing of -23's.
  - The cap's new clause reads only -24's rows.
  - The trigger order on `payments` is unchanged from r3. The battery-23 port is unchanged, and the races pass.
  - Nothing in r4 changes what -23's positions, caps or recorded-order rules see.
- **N2 (read). -24's money rule now leans on a -23 body that no invariant pins.** `c_app_exec` now requires `tally_app`'s EXECUTE on `ledger_entry_remaining(uuid)`. -23's invariant pins its settings (`proconfig`, `tu.sql` lines 47015 and 47182), but no invariant pins its body or `ledger_tree_ids`' body by md5. -24's `c_bodies` covers only -24's own functions, which is what its comment claims. So the claim isn't narrower than the check. But a replaced `ledger_entry_remaining` would quietly change what a misposting return may give back. This belongs to -23's invariant (or a later invariants pass), not to -24.
- **N3 (read). Concurrency.**
  - The lock order is unchanged: payment, then receipt; a pledge on its own key.
  - The tree read in the misposting branch runs under the receipt's lock but not the tree's lock. That is sound, because the tree is frozen once the payment is reversed (Q1g, Q1h, Q1i).
  - No cap is read without the lock that orders it.
- **N4 (read). `c_app_exec`'s NULL leg is still there (r3 N3).** `has_function_privilege('tally_app', to_regprocedure('public.nope(uuid)'), 'EXECUTE')` returns NULL (executed), and `WHERE NOT NULL` drops it. The new entry `ledger_entry_remaining(uuid)` is not in `c_bodies`, so this entry is now covered only by -23's settings check (which fails on a missing function through `::regprocedure`). Nothing escapes today. `coalesce(…, false)` would still make the check say what it means.
- **N5 (judgement). Known limits.** L1 and L3 are fine. L2 fails toward protection. L4 is fine now that the share is netted and the cap refuses below zero. L5 and L6 stand by Ryan's 11-07 ruling. None blocks.
- **N6 (predicted; executed in r1). Statement shapes.** COPY, writable CTEs and multi-row inserts: the cap is still AFTER ROW under the receipt's lock, and the misposting rule is in the same AFTER ROW trigger, so nothing depends on statement shape. Not re-probed this round.
- **N7 (environment).** Two `crystaldba/postgres-mcp` containers (`pgmcp-67591-…`, `pgmcp-67190-…`, up 45 hours) were still running beside `tally-pg`. That is the leak the session-start check warns about. I left them alone.
