# Fable review — v5.4.2-24 r5 (unmatched cash and agency pledges)

**Date:** 2026-11-07. **Reviewer:** Fable (claude-fable-5-1). **Brief:** `review-brief-24-r5.md` (md5 `c3a8e09c…`, matched).

**Frozen hashes checked, all matched:** patch `0670e335…`, battery `190f9278…`, races `88c9c30b…`, mutations `55d66cf4…`, ci diff `c343828b…`, r4-to-r5 `cee33443…`.

**Verdict: ready.** My round-4 blocker is closed as proposed: the misposted share is now the net of the posting entry's whole tree with every nsf row, and everything beneath one, left out, walked down by the reversal link alone with the plan pinned, bounded by 0 and the payment. Opus's round-4 should-fix (a return dated before its payment) is closed. Every earlier finding still is. No blocking item. Two should-fix items, both small: a stale function comment, and one tree shape the tests do not cover (the one where the payment bound is the only rule that holds).

**Scratch database:** `rv24fable` (TEMPLATE `tally`; TEMP revoked from PUBLIC, `tally_app`, `tally_core`; frozen r5 patch applied strictly twice; the battery; the races; my probes spliced into the battery after P9b12 and rolled back with it; dropped at the end). I did not run `ci.sh` or `mutations-24.py`; created, dropped or altered no role; read no `opus-*` or `codex-*` file. Two `crystaldba/postgres-mcp` containers were running at my start; I did not touch them.

## Reproduced (executed)

- Strict apply (`search_path=''`, `check_function_bodies=on`): clean; the second run is skipped by the marker ("already applied (suspense_receipts exists)").
- `battery-24-frozen-r5.sql`: **260 PASS**, 0 FAIL (rolled back).
- `suspense-24-frozen-r5.sh rv24fable`: **24 PASS** (SU1–SU12b).
- `assert_suspense_pledge_guard_invariants()` on the clone after the battery and the races: clean (the r5 body hash and the new `enable_*` attributes of `enforce_suspense_disposition` match the live function).
- Trigger order on `payments` is unchanged from r4 (`pg_trigger` by name: -23's `a_*` first, then `enforce_cash_draw`, …, `enforce_payment_suspense_cap`, `enforce_payment_suspense_pledge`, …). On `account_ledger`, -22's `enforce_ledger_lineage_acyclic` and -23's `enforce_ledger_reversal` are `ENABLE ALWAYS` (`tgenabled = 'A'`), so a replica-mode history load cannot write a cycle past them either.

## Round-4 findings — closed (executed)

- **My B1 (an nsf row inside a reversal's tree counted as misposted money).** P14c is my exact shape (reversal, its undo, the bank's take-back filed under the undo): the return of 0.01 is refused; P14d (the bank's take-back undone, then a reversal beside it): 100 comes back; S4 at 450. My extra shapes below (FA–FD) all come out right or fail closed.
- **Opus S1 (a return dated before its payment).** P9b11 refused with the message naming the payment's date; P9b12 (dated on the payment's date) admitted.

Rounds 1–3 (my r1 B1, B2, S1, S2; my r2 B1, S1; my r3 B1, S1; the brief's list for the others): still closed by the same battery checks, all of which ran again here.

## Probes on the r5 walk (executed, as `tally_app` unless said, every `created_at` stamped by the database)

- **FA — an nsf of negative sign under a misposting reversal, then a second reversal.** E −100; x +100 under E (misposted); n nsf −100 under x (-23 admits it: FA1); x2 +100 under E; the payment moves to `reversed` naming x (FA2). The non-nsf sum is 200; `least(v_pay.amount, …)` brings it to 100: 100.01 refused (FA3), 100 admitted (FA4); the receipt then holds 100 and the customer's rows under the payment net 0. Right by the money (the negative "nsf" is a give-back under a take-away, not a bank return), but here the payment bound is the only rule that holds — see S2.
- **FB — a misposting reversal attached under the undo of a bank take-back (depth 3).** E; n nsf +100 under E; m −100 under n; x +100 under m. -23 refuses the move to `reversed` naming x (`23503`, FB1): the cause is a direct child. The payment stays `posted`, so no return (FB2). Fail-closed; the walk would read 0 for it.
- **FC — the bank's take-back, its undo, a second take-back under the undo, and a misposting reversal beside.** E; n nsf +100; m −100 under n; n2 nsf +100 under m. The tree nets 100 (the bank has it), so a misposting reversal beside it is over the posting entry's cap (-23, FC1). The walk reads 0 (FC2, as the owner).
- **FD — the bound.** A 999-link alternating chain (+100, −100, …) under the posting entry, built one row at a time as `tally_app` (1 min 46 s for the 999 inserts: -23's per-insert walks, not -24's). The 1000th link is refused by -22's lineage rule (FD1). The payment moves to `reversed` naming link 1 (FD2). Over that tree the return of 100.01 is refused and 100 admitted (FD3, FD4) in **20 ms** each. So the walk is bounded the way -23's are: by the lineage rule at insert (acyclic, ≤ 1000), with no bound of its own — the same posture as `ledger_tree_ids`.
- **FE — the plan.** `EXPLAIN` of the walk as `tally_app` with the three `enable_*` off (the function's setting), after `VACUUM ANALYZE` of a near-empty ledger (reltuples 6, the lesson's "planner believes empty" case): index scan on `account_ledger_payment_arrival_key` for the posting entry, index scans on `idx_account_ledger_reverses` for both steps, nested loops, no sequential scan or hash join. (Without the setting, the recursive step is a hash join over a sequential scan — the pin is doing its work.)

## S — should fix

### S1. `COMMENT ON FUNCTION enforce_suspense_disposition()` says nothing about misposting returns — **read**

The catalogue comment (patch line 1007) describes the date bounds, the undo rules and the cap, and stops. The function's largest branch — a misposting return names a payment of the receipt, `reversed` with no return code; at most the net of the posting entry's tree with the nsf subtrees left out, bounded by the payment; dated on or after the payment and its reversal; once — is not mentioned. The header comment (lines 34–40) is right; the catalogue is what a later session reads. One sentence; no behaviour change, no hash change to the pinned body (the comment is not part of `prosrc`).

### S2. No test holds the payment bound alone — **executed (FA)**

The r5 plan's own note on M106 says P14a "is held by the bound at the payment", but every battery shape nets to at most the payment before the bound is applied, so a mutation dropping `least(v_pay.amount, …)` would pass 260/260 and 111/111. FA is the shape where the bound is the only rule: a negative-signed nsf row under a reversal (which -23 admits, my r4 N1) beside a second reversal; the non-nsf sum is 200 and the return of 100.01 is refused by the bound alone. Add FA as a battery check (100.01 refused, 100 admitted) and a mutation replacing `least(v_pay.amount, greatest(0, …))` with `greatest(0, …)`, named at it. Small; the rule already holds.

## N — notes

- **N1 (executed).** The fail-closed shapes: a misposting reversal attached beneath an nsf row (FB) reads 0, and -23 independently refuses the payment's move to `reversed` naming it, so no return is reachable. A tree where the walk reads less than the money says (an operator who keys the misposting under the bank's undone take-back) is held, not released; the fix is a reversal keyed under the posting entry, which -23 admits. The gap closes toward the receipt, never away from it.
- **N2 (read).** After a return is recorded the tree is fixed, as the r5 comment claims: a negative row anywhere under the posting entry is a give-back to an ended payment (-23, `23001`); a positive row anywhere puts the posting entry's tree, already at the payment, over its cap (-23, `23514`). So a return can never be left standing against a tree that later shrinks.
- **N3 (read).** Mutations M98, M106, M109 and M110 mutate what they claim (the top-level nsf filter; the descent; the below-top nsf filter; the date rule) and name P13, P14b, P14c and P9b11, each of which fails for that reason alone. `ledger_entry_remaining(uuid)` has correctly left `c_app_exec`: -24 no longer calls it.
- **N4 (read).** The function-level `SET enable_seqscan/hashjoin/mergejoin = off` also governs `check_suspense_recorded_order` and `check_suspense_receipt_cap` when called from this trigger. Both read by `suspense_receipt_id`, indexed on `payments` (`idx_payments_suspense_receipt`) and on dispositions (`idx_suspense_dispositions_receipt`), so they lose nothing; `enforce_ledger_reversal` in -23 carries the same setting over a larger body.
- **N5 (read).** Lock order unchanged from r3: the receipt's advisory lock, then the payment is read; the misposted share is read under the receipt's lock, and the payment is already `reversed` (its tree fixed, N2), so no concurrent ledger write can change the share between the read and the insert. No race leg needed.
- **N6 (read).** The invariant's exact lists carry the r5 body hash and the new attribute string; I9b (attributes) and the body-hash check are exercised by the battery. Nothing narrower than its claim found.
- **N7.** Known limits L1–L6: none blocking.
- **N8 (executed, mine).** When my probes are spliced in, S4 reads 650 rather than 450 (FA and FD each give 100 back); that is my fixtures, not a finding.

## Answers to the brief's questions

1. **Round 4 and earlier.** My r4 B1 and Opus's r4 S1 are closed; every finding of rounds 1–3 still is. The patch implements the design and the rulings (CI-053, CI-056, the 11-07 refund rule within L5 and L6).
2. **Paths around a rule.** None found. The shapes the brief names for the walk (an nsf at any depth, a reversal under an nsf row, a bank's take-back undone and then reversed, several levels deep) come out right (P14b, P14c, P14d, FA, FC) or fail closed (FB). The rest of the list is held by the r4 battery checks that re-ran here, as in my r2–r4 reviews.
3. **-23 and -27.** -24 reads -23's tree by type and link only and calls none of -23's helpers now; it changes nothing -23 or -27 reads; the new `payments` triggers still sort after -23's.
4. **Concurrency.** Lock order followed (N5); the races reproduce (24).
5. **Invariants.** Catch what they claim (N6).
6. **Tests.** Battery 260 and races 24 reproduced; no check weaker than its label among those traced; mutations re-anchored correctly (N3). Missing: the shape where the payment bound alone holds (S2).
7. **L1–L5.** None blocking (N7).
