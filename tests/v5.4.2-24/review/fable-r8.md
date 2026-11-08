# Fable review — v5.4.2-24 r8 (unmatched cash and agency pledges)

**Date:** 2026-11-07. **Reviewer:** Fable (claude-fable-5-1). **Brief:** `review-brief-24-r8.md` (md5 `1c45869648fdf7ad4507e5a73d9b130a`, matched its `.md5`).

**Frozen hashes checked, all matched:** patch `be4cc5c2…`, battery `973fa32b…`, races `55c63199…` (unchanged from r6), mutations `f30c5fc1…`, ci diff `c343828b…` (unchanged from r1), r7-to-r8 `8093d493…`. I reviewed the frozen copies only.

**Verdict: ready.** Both round-7 should-fix items are closed and I executed each one's test and each one's mutation by hand. Every earlier finding still holds (the whole battery re-ran here). The one change to the rule since round 7, a misposting return must give back exactly the misposted share rather than anything up to it, refuses no legitimate return and strands no money that I could construct. No blocking item. One should-fix on test strength (a free tightening of six checks' guard strings, SQL below) and notes.

**Scratch database:** `rv24fable` (TEMPLATE `tally`; TEMP revoked from PUBLIC, `tally_app`, `tally_core` right after creation; frozen r8 patch applied strictly twice; the battery; my probes spliced into a copy of the battery and rolled back with it; the two new mutations applied by hand to the clone's function and reverted; the races; dropped at the end, confirmed gone). I did not run `ci.sh` or `mutations-24.py`; created, dropped or altered no role; read no `opus-*` or `codex-*` review file. Two `crystaldba/postgres-mcp` containers were running at my start; I did not touch them.

## Reproduced (executed)

- Strict apply (`search_path=''`, `check_function_bodies=on`): clean; the second run is skipped by its marker ("already applied (suspense_receipts exists)").
- `battery-24-frozen-r8.sql`: **277 PASS**, 0 FAIL (rolled back). P9b3b, P14i4 and the re-aimed P14b, P14c, P14e, P14f all pass with the "exactly what payment" message.
- `suspense-24-frozen-r8.sh rv24fable`: **24 PASS** (SU1–SU12b).
- `assert_suspense_pledge_guard_invariants()` on the clone after the battery and the races: clean. The live body of `enforce_suspense_disposition` hashes to `8eb423ac1f404a942d69ac7e41de3eed`, the value the frozen invariant pins (the only pin that changed from r7).
- Trigger order on `payments` unchanged from r7: -23's `a_*` first, then `enforce_cash_draw`, `enforce_escheated_credit_settled`, `enforce_payment_effective_date`, `enforce_payment_immutable`, `enforce_payment_suspense_cap`, `enforce_payment_suspense_pledge`, `enforce_shortfall_source_moves`; all `ENABLE ALWAYS` except `set_updated_at`.
- Column types on the clone: `payments.amount`, `account_ledger.amount`, `suspense_receipts.amount`, `suspense_receipt_dispositions.amount` are all `numeric(12,2)`. This matters for the exact rule (below).

## Round-7 findings — closed (executed)

- **Opus r7 S1 — a short misposting return stranded the rest.** What it did to the money: a clerk who returned 40 of a misposted 100 could never return the other 60 (one return per payment, never undone), so 60 sat on no customer's account, not on the receipt, and was never refunded; CI-053 says held, never dropped. The rule is now `-NEW.amount <> v_misposted` → refused, with the share and the payment's amount in the message. Executed: P9b3b (49.99 of a 50 share refused), P9b3 (50.01 refused), P13 and P13b (100 refused, 60 admitted where the bank took 40), P14a/P14a2, P14e/P14e2, P14f/P14f2 all re-ran. **M115 by hand:** I replaced the clone's function body with the mutation (`<>` back to `>`), ran the battery, and the first failure was `FAIL P9b3b … accepted`; then restored the body (pin `8eb423ac…` again, invariants clean). So the mutation is caught at the check the runner names, for the right reason.

  The brief's question — does an exact return refuse a legitimate return or strand money another way:
  - *A share of 0* (P14b: a reversal undone, then the bank took the 100; P14c: the bank's take-back filed under the undo). No return is possible, since a disposition's amount is non-zero by CHECK. Is anything stranded? No: my **FP5/FP5b** assert the receipt holds 0 in both shapes, and the payment is not voided so the receipt's cap counts it as spent. The money went to the bank; the ledger says so; nothing is on no account.
  - *A share the clerk can't read:* the refusal says "(0 of its 100.00" or "(60.00 of its 100.00", so the clerk is told the exact figure to key. And because every amount column is `numeric(12,2)`, the share (a sum of two-decimal rows, capped at a two-decimal payment) is always a figure a `numeric(12,2)` return can equal exactly; there is no rounding gap that could make every return refused. (Checked: `33.33::numeric(12,2) = least(33.33, greatest(0, 33.330))` is true; `0 = 0.00` is true.)
  - *The share changing after the return:* **FP1 (executed)**. After P13b's exact return of 60, I tried to grow payment 1a's tree three ways: an undo of the bank's take-back (nsf −40 under it), a second reversal (+40 under the posting entry), and an undo of the misposting reversal (−60 under it). -23 refused all three: the give-backs with 23001 "gives money back to payment …, which has ended: post a new payment (CI-013)", the take-back with 23514 "the rows netted against it would come to 140.00, outside 0 to 100.00". FP1d: the tree still has two rows and the receipt still holds 60. So the share a return matched is the share forever; the money cannot be double-counted or stranded by a later tree row.

- **Opus r7 S2 — the chosen-earlier-time refusal untested.** The recorded-order rule has two halves: a return stamped at the transaction's start that meets a tree row recorded later retries (40001), and a time the owner chose that is earlier than a tree row is refused (23514). Only the first had a check. P14i4 now inserts a return stamped at the midpoint between the transaction's start and the reversal's `clock_timestamp()` stamp and expects 23514 "before a row under its posting entry recorded at". Executed: passes. **M116 by hand:** a `RETURN NULL;` before that RAISE (the mutation's exact text), battery run, first failure `FAIL P14i4 … accepted`; body restored. **FP3 (executed):** the gap between the transaction's start and 9d's recorded instant in the battery is about 1.28 s, so the midpoint is far from either edge; the check is not timing-fragile (it would need a gap under 2 µs to collapse onto the 40001 branch).

Rounds 1–6 (my r1 B1, B2, S1, S2; r2 B1, S1; r3 B1, S1; r4 B1; r5 S1, S2; r6 S1 = S4b; and the brief's list for Opus's and Codex's) are still closed by the same battery checks, all of which ran again here; S4b's conservation sweep is in the 277.

## S — should fix

- **S1 (executed). Six refusal checks prove "not this amount", not "this share".** With an exact rule, a `refuses_at` that offers the wrong amount passes whenever the computed share differs from that amount, whatever the share is. P14b and P14c (share 0, offered 100) have no admitting partner, since a 0 return cannot exist, so today they prove only "share ≠ 100": a wrong rule that computed 40 or 60 in those shapes would pass them. P9b3/P9b3b, P13, P14e and P14f have admitting partners (or the 0.01-over check), so they are pinned; still, the refusal message carries the share, and the guard string can pin it for free. I ran all six with the tighter guards and they pass:

```sql
-- the guard text pins the share the database computed; otherwise unchanged
SELECT pg_temp.refuses_at('P9b3b …', $q$SELECT pg_temp.mret(NULL, pg_temp.k('04'), pg_temp.k('14'), 49.99, DATE '2026-03-05')$q$,
  '23514', 'reversed as misposted (50.00 of its 50.00');
SELECT pg_temp.refuses_at('P13 …',   $q$SELECT pg_temp.mret(NULL, pg_temp.k('0c'), pg_temp.k('1a'), 100, DATE '2026-03-12')$q$,
  '23514', 'reversed as misposted (60.00 of its 100.00');
SELECT pg_temp.refuses_at('P14b …',  $q$SELECT pg_temp.mret(NULL, pg_temp.k('11'), pg_temp.k('1d'), 100, DATE '2026-03-13')$q$,
  '23514', 'reversed as misposted (0 of its 100.00');
SELECT pg_temp.refuses_at('P14c …',  $q$SELECT pg_temp.mret(NULL, pg_temp.k('13'), pg_temp.k('1e'), 100, DATE '2026-03-13')$q$,
  '23514', 'reversed as misposted (0 of its 100.00');
SELECT pg_temp.refuses_at('P14e …',  $q$SELECT pg_temp.mret(NULL, pg_temp.k('16'), pg_temp.k('d1'), 100, DATE '2026-03-14')$q$,
  '23514', 'reversed as misposted (50.00 of its 100.00');
SELECT pg_temp.refuses_at('P14f …',  $q$SELECT pg_temp.mret(NULL, pg_temp.k('17'), pg_temp.k('d7'), 90, DATE '2026-03-16')$q$,
  '23514', 'reversed as misposted (70.00 of its 100.00');
```

  Note the share prints as `0` (not `0.00`) when the tree nets to nothing, because `greatest(0, 0.00)` returns the first argument; the guard above matches what the message actually says. Mutations M106, M109, M111 and M115 would then be caught by the share in the message as well as by the amount, and a future wrong share in the two share-0 shapes would be caught at all. Not blocking: the rule is right, and the mutations the author aimed at are caught today.

## N — notes

- **N1 (read).** The table comment on `suspense_receipt_dispositions` (patch line 449) still says a misposting return is "at most what non-NSF rows reversed of it", and the inline comment at line 952 says "at most what was reversed as misposted"; the function comment and the header were updated to "exactly". The design's section 2.3 bullet ("a misposting return gives back at most what non-NSF rows reversed", line 202) likewise. Wording only; nothing pins table comments.
- **N2 (read).** `least(v_pay.amount, …)` in the share is now belt-and-braces: FP1b shows -23 refuses a tree that nets above the posting entry, so the sum can't exceed the payment. Harmless.
- **N3 (read).** The exact rule reads the tree under the receipt's advisory lock, after the payment is `reversed` (terminal in -23: `tu.sql` line 13544), and FP1 shows the tree can't grow afterwards, so there is no window in which the share a clerk was told differs from the share the trigger checks, except the one SU12 covers (the reversal not yet committed → 40001, retry admitted).
- **N4 (read).** My r7 notes N1–N9 stand (the 40001 message's wording; the ordinary flow costs the clerk nothing because reversal and return both default to `now()`; a tree row's stamp is never in the future; S4b checks over-counting only).
- **N5.** Known limits L1–L6: none blocking, as before.

## Answers to the brief's questions

1. **Round 7 and earlier.** Opus r7 S1 closed (P9b3b, re-aimed P14b/c/e/f, M115 caught at P9b3b by hand; FP1 and FP5 show the exact rule strands nothing). Opus r7 S2 closed (P14i4, M116 caught at P14i4 by hand; FP3 shows the check's margin). Rounds 1–6 still closed. The patch implements the design and the rulings (CI-053, CI-056, Ryan's 11-07 refund rule within L5 and L6).
2. **Paths around a rule.** None found. The exact return cannot be followed by a tree change (FP1); a share of 0 leaves no money unaccounted (FP5). The rest of the brief's list is held by the rounds 1–7 checks that re-ran here, and by the races.
3. **-23 and -27.** -24 still reads -23's tree by type, sign and link alone and calls none of -23's helpers; r8 changes only a comparison operator. Nothing -23 or -27 reads changes. The `payments` trigger order is unchanged.
4. **Concurrency.** Lock order unchanged; the races reproduce (24).
5. **Invariants.** Clean on the clone after battery and races; the body pin is the only pin that moved and matches.
6. **Tests.** Battery 277 and races 24 reproduced; both new mutations caught at their named checks by hand. S1 above is the one weakness I would tighten: six refusals could pin the share through the message.
7. **L1–L6.** None blocking.
