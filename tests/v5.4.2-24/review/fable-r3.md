# Fable review — v5.4.2-24 r3 (unmatched cash and agency pledges)

**Date:** 2026-11-07. **Reviewer:** Fable (claude-fable-5-1). **Brief:** `review-brief-24-r3.md` (md5 `de2313fe…`, matched).

**Frozen hashes checked, all matched:** patch `209260b5…`, battery `f7fab303…`, races `88c9c30b…`, mutations `a2892027…`, ci diff `c343828b…`, r2-to-r3 `4921c86e…`.

**Verdict: not yet.** Every round-2 finding is closed, and every round-1 finding still is. One new item is blocking, opened by round 2's fix 3: the misposting return now gives back "what the non-NSF rows reversing the posting entry came to", read as a plain sum of the entry's direct children, and the payment bound that r2 had was dropped. A reversal, its re-reversal and a second reversal under one posting entry (all admitted by -23 while the payment is posted) make that sum 200 of a 100 payment; the return of 200 is admitted, the receipt reads 200 held of 100, and a second payment of 200 is drawn from it — 100 of money became 300 of payments (B1). One should-fix: a superuser history load that inserts a receipt's payment already voided, with the void's stamp after the insert's, is refused by the payment's own order check, because the status branch of the union does not exclude the row itself (S1).

**Scratch database:** `rv24fable` (TEMPLATE `tally`; TEMP revoked from PUBLIC, `tally_app`, `tally_core`; frozen r3 patch applied strictly twice, the battery, the races, then a committed copy of the battery for fixtures; dropped at the end). I did not run `ci.sh` or `mutations-24.py`; created, dropped or altered no role; read no `opus-*` or `codex-*` file. Two `crystaldba/postgres-mcp` containers were running at my start; I did not touch them.

## Reproduced (executed)

- Strict apply (`search_path=''`, `check_function_bodies=on`): clean; the second run is skipped by the marker.
- `battery-24-frozen-r3.sql`: **251 PASS**, no FAIL (rolled back; a second run with COMMIT in place of ROLLBACK, also 251, left the fixtures).
- `suspense-24-frozen-r3.sh rv24fable`: **24 PASS** (SU1–SU12b), every B leg seen blocked by A.
- `assert_suspense_pledge_guard_invariants()` on the clone after the battery and races: clean.

## Round-2 findings — closed (executed through the battery and races)

- Releases ordered (my B1, Opus B1, Codex probe 03): O1f (an undo before its original, 23514), O1g/O1h (a return before and after the reversal's stamp), SU11 and SU12/SU12b live (40001, retry admitted). The union reads `status_recorded_at` of voided and reversed payments.
- Self-exclusion per table (Codex probe 02): O1e.
- Misposting return capped at the non-NSF reversal (Codex probe 01): P13/P13b/P13c, S4 at 150. (But see B1: the cap is wider than it should be.)
- NaN refused (Codex probe 07): U3b, X5b, L6e.
- The invariant's reach (my S1, Opus S1, Codex probe 06): I9 (a helper's body), I9b (volatility), I9c (`search_path` reset), I9d (helper EXECUTE), I9e (NOT NULL). My own extra: an *added* setting on a pinned function (`SET statement_timeout`) is caught too (F4b, executed).
- Foreign keys off (Opus N): O3b, O3c.
- Stale comments: corrected in the table comment and the reader's comment. The header states the READ COMMITTED application contract.

Round 1 (my B1, B2, S1, S2, N3–N8; the brief's list for the others): still closed, by the same battery checks as in my r2 review, all of which ran again here.

## B — blocking

### B1. A re-reversal under the posting entry inflates the misposting return; a 100 receipt funds 300 of payments — **executed, as `tally_app`, no chosen times**

What it does: `enforce_suspense_disposition` now bounds a misposting return by `v_misposted`, the sum of the rows that directly reverse the payment's posting entry and are not NSF. A reversal's own reversal (money given back to the customer because the first reversal was wrong) is a grandchild of the posting entry: it is not subtracted, and -23 admits it while the payment is still posted (only a give-back to an *ended* payment is refused, `tu.sql:43293`). -23's R-02 cap bounds the *net* of the tree between 0 and the entry, so two +100 reversals with a −100 between them are fine for -23. The r2 bound `-NEW.amount > v_pay.amount` was removed rather than kept beside the new one, and the receipt cap only refuses a date where payments plus dispositions *exceed* the receipt, never one where they fall below zero, so an over-release is invisible to it.

Evidence (receipt `R24-24f1` 100, received 04-02; its payment `P24-24f2` 100 to C1, posted, entry E −100; all as `tally_app`):

```
x: adjustment +100 reversing E (04-03, "misposted")               admitted
y: adjustment −100 reversing x (04-04, "reversal was wrong")       admitted
z: adjustment +100 reversing E (04-05, "misposted after all")      admitted
ledger_entry_remaining(E) = 0.00;  UPDATE payments SET status = 'reversed', status_cause_id = z   admitted
customer's ledger under the payment nets 0.00 (all 100 taken back once)
misposting_returned −200 of P24-24f2 to R24-24f1, dated 04-05:    ADMITTED
suspense_receipt_position_as_of(R, 2026-12-31, now):  amount 100 | to_payments 100 | disposed −200 | held 200
a second payment of 200 from the receipt to C2, dated 04-05:       ADMITTED (cap: 300 − 200 = 100 on 04-05)
held after: 0.00; live payments naming the receipt: 300.00
```

Control (same fixture shape without the re-reversal, x only): a return of 101 is refused by the new message, `at most what payment … reversed as misposted (100.00 of its 100.00 …)` (F1g, 23514). So P13 is right as far as it reaches; the gap is the netting.

What is wrong at the end: 100 of money arrived; 300 stands as payments on two customers' ledgers (100 taken back from C1 again by x and z, but y gave 100 of it back, so C1 keeps 0 and C2 keeps 200 — C2 was paid 200 out of 100). CI-053: money is never applied beyond what was received.

Fix (rule: guard the act, measure the fix). Measured on the fixture above: the net of each non-NSF child's subtree gives 100, the r3 sum 200.

```sql
WITH RECURSIVE down(id, amount) AS (
    SELECT x.id, x.amount FROM public.account_ledger x
     WHERE x.reverses_ledger_entry_id = e.id AND x.transaction_type <> 'nsf'   -- e: the posting entry
    UNION ALL
    SELECT y.id, y.amount FROM down d JOIN public.account_ledger y ON y.reverses_ledger_entry_id = d.id)
SELECT coalesce(sum(amount), 0) ...            -- 100 on the fixture; r3's query gives 200
```

(With -23's walk settings: seqscan, hashjoin, mergejoin off, lesson `recursive-walks-join-on-link-alone`; or `ledger_tree_ids` per child.) Keep `least(…, v_pay.amount)` as a second bound. And, as the belt that catches *any* over-release path, let `check_suspense_receipt_cap` refuse a date where payments plus dispositions fall below 0 as well as one where they exceed the receipt (`w.o < 0 OR w.o > v_amount`): the receipt's holding is then bounded on both sides by the cap, not only by each release's own arithmetic. Battery: the x/y/z case (return of 200 refused, 100 admitted, held 100), and the variant x +100, y −100, z +60 (60 admitted, 61 refused: the customer still holds 40). Mutations: the netting dropped; the lower bound dropped.

## S — should fix

### S1. A superuser load of a receipt's payment inserted already voided is refused by its own order check — **executed**

What it does: the third branch of `check_suspense_recorded_order`'s union (`status_recorded_at` of voided and reversed payments) has no self-exclusion. A superuser history load that inserts a receipt's payment with `status = 'voided'` and `status_recorded_at` an hour after its `created_at` (the normal shape of a void that followed its payment; -23 admitted the row) reaches -24's AFTER trigger and is refused:

```
INSERT payments (… suspense_receipt_id = R24-00fc, created_at '2026-04-02 12:00', status 'voided', status_recorded_at '2026-04-03 12:00')
ERROR 23514: a payment from a receipt on receipt … is recorded at 2026-04-02 12:00, before a row of the receipt already recorded at 2026-04-03 12:00
```

The row it is "before" is itself. Fix: `AND NOT (p_self_is_payment AND p.id = p_self)` on the third branch, as on the second. Battery: the insert above admitted. Mutation: the clause dropped, named at that check. (A live void is a later UPDATE and never meets this; only a load that brings the ended payment in whole does.)

## N — notes

- **N1 (executed).** A payment recorded (superuser chosen time) an hour before its receipt's `created_at` is still admitted (F2; my r2 N2). No holding figure is wrong at the instant between (the reader returns no row before the receipt exists), so this stays a note. `r.created_at` could join the union when B1's fix is made.
- **N2 (read).** Lock order: the disposition trigger reads `payments` and `account_ledger` under the receipt's lock only, taking no -23 lock, so no cycle through -23; the return-code UPDATE takes -23's `a_*` locks before the receipt's (trigger name order). The B1 shape has no race leg: the re-reversal needs the payment posted and the return needs it reversed, and the status move holds the payment's lock.
- **N3 (read).** The invariant: `c_attrs` compares `provolatile | prosecdef | proconfig` exactly, so an added or removed setting and a changed volatility are both caught (F4b, I9b, I9c); `c_app_exec` with a missing function yields NULL and is silent there, but the body list names the function first. `c_notnull` reads `pg_attribute`, right for PG 16. Nothing narrower than its claim found.
- **N4 (read).** Mutations: M95–M106 each name the first-failing check (M95 O1f, M96 O1g, M97 O1e, M98 P13, M99 U3b, M100 O3b, M101 O3c, M102 I9b, M103 I9e, M104 I9d; M105 relies on race SU7, which the runner runs). M98 removes the NSF filter, not the netting: no mutation covers B1's gap, which is why 106/106 passed with it open.
- **N5 (read).** The r3 plan's fix 3 was taken literally ("at most what the non-NSF rows reversing the payment's posting entry came to") and the r2 payment bound dropped with it; lesson `reviewer-fixes-need-measuring` applies to the author's reading of the fix list as much as to our proposals.
- **N6.** Known limits L1–L6: none blocking.

## Answers to the brief's questions

1. **Rounds 1 and 2.** Every finding of both rounds is closed. The patch implements the design and the rulings (CI-053, CI-056, the 11-07 refund rule within L5 and L6) except where B1 lets a receipt's holding exceed the receipt.
2. **Paths around a rule.** Found: B1 (a receipt spent three times over, as `tally_app`, no chosen times, after a correction sequence -23 admits). Not found: out-of-bounds, cross-tenant or reason-less receipt payments (incl. foreign keys off, O3b/O3c); a database-made guess; a provider id twice; a pledge paid by another agency or customer or ended twice; an early lapse; a payment naming an error pledge; a misrouted refund in the traced origins; an agency brought back; an agreement edited.
3. **-23 and -27.** -24 changes nothing they read; the new `payments` triggers still sort after -23's on both sides. B1 is -24 misreading -23's tree, not a change to -23.
4. **Concurrency.** Lock order followed; every cap and count read is under its lock and the pin; the releases are now ordered (SU11, SU12).
5. **Invariants.** Catches what it claims; N3.
6. **Tests.** Battery 251 and races 24 reproduced; no check weaker than its label among those traced. Missing: B1's netting and lower-bound checks, S1's load shape (N4).
7. **L1–L5.** None blocking (N6).
