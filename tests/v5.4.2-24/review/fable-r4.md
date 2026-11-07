# Fable review — v5.4.2-24 r4 (unmatched cash and agency pledges)

**Date:** 2026-11-07. **Reviewer:** Fable (claude-fable-5-1). **Brief:** `review-brief-24-r4.md` (md5 `d8c1885c…`, matched).

**Frozen hashes checked, all matched:** patch `8acade88…`, battery `414ff52a…`, races `88c9c30b…`, mutations `21e01cf8…`, ci diff `c343828b…`, r3-to-r4 `7a333752…`.

**Verdict: not yet.** Every round-3 finding is closed as written, and every earlier one still is. One item blocks, and it is the brief's own question ("an NSF row under a reversal, several levels deep"): the misposted share counts an nsf row that sits *inside* a misposting reversal's tree as misposted money. A reversal entered, undone, and then the bank's take-back keyed as a reversal of the undo (depth 3 under the posting entry) gives the receipt 100 back while the bank also took the 100 (B1). The patch's own rule, "what the bank took back (nsf rows) stays spent", holds only for nsf rows directly under the posting entry. No should-fix items.

**Scratch database:** `rv24fable` (TEMPLATE `tally`; TEMP revoked from PUBLIC, `tally_app`, `tally_core`; frozen r4 patch applied strictly twice; the battery; the races; probes on top of the battery's fixtures, rolled back; dropped at the end). I did not run `ci.sh` or `mutations-24.py`; created, dropped or altered no role; read no `opus-*` or `codex-*` file. Two `crystaldba/postgres-mcp` containers were running at my start; I did not touch them.

## Reproduced (executed)

- Strict apply (`search_path=''`, `check_function_bodies=on`): clean; the second run is skipped by the marker ("already applied (suspense_receipts exists)").
- `battery-24-frozen-r4.sql`: **256 PASS**, no FAIL (rolled back).
- `suspense-24-frozen-r4.sh rv24fable`: **24 PASS** (SU1–SU12b).
- `assert_suspense_pledge_guard_invariants()` on the clone after the battery and the races: clean (the r4 body hashes match the live functions).
- The `payments` trigger order is unchanged from r3 (`pg_trigger` by name: -23's `a_*` first, then `enforce_cash_draw`, …, `enforce_payment_suspense_cap`, `enforce_payment_suspense_pledge`, …).

## Round-3 findings — closed (executed)

- **The misposted share nets each reversal's own tree** (Opus B1, my B1): P14a (200 refused, 100 admitted), P14b (an undone reversal then the bank's take-back under the posting entry: nothing comes back), S4 at 250. My own extra shapes: a bank return undone while the payment was still posted, then a misposting reversal — 100 comes back, 100.01 refused (FC2/FC3 below); the undo of the bank return itself undone at depth 3 — -23 refuses the move to `reversed` naming a depth-3 row, so the payment is `nsf` and the return is refused (FD1–FD3). But see B1 for the one shape the netting gets wrong.
- **The cap refuses a date below zero** (my r3 proposal): I forced a −30 position (the disposition trigger disabled for one insert as the owner, rolled back) and called the cap directly: `23514 "… would come to -30.00, giving back more than was taken from the 100.00 the receipt holds"`. M15 is the mutation that meets it; no live path to a negative position found (every negative disposition is bounded by its own rule).
- **The order check's third branch excludes the row's own payment** (my S1): O4 (a payment loaded already voided, voided 04-04, recorded 04-03) admitted.
- **A NaN payment naming a pledge** (Opus S1): L7f refused by `payments_agency_pledge_check`; the invariant's exact-text list carries the new CHECK text.
- **P9b3 relabelled** (Opus S2): the label now says what it tests.

Rounds 1 and 2 (my B1, B2, S1, S2, N3–N8 of r1; my B1 and S1 of r2; the brief's list for the others): still closed, by the same battery checks as in my r2 and r3 reviews, all of which ran again here.

## B — blocking

### B1. An nsf row inside a misposting reversal's tree is counted as misposted money; the bank's take-back comes back to the receipt — **executed, as `tally_app`, no chosen times**

What it does: `enforce_suspense_disposition` sums `ledger_entry_remaining(x)` over the posting entry's *direct* non-nsf children x. `ledger_entry_remaining` is x's amount plus the net of everything under x, whatever its type. An nsf row under x's tree is therefore counted as if an operator had re-taken the money as misposted. -23 admits an nsf row anywhere a sign fits (`account_ledger_reversal_types_only_check` only requires that an nsf row names some entry), and the payment's move to `reversed` needs only a non-nsf direct child as its cause and the posting entry's tree netting to the entry.

Evidence (receipt 100, received 03-10; its payment 100 to C1, posted, entry E −100; all as `tally_app`, every `created_at` stamped by the database):

```
x: adjustment +100 reversing E (03-11, "misposted")                            admitted
y: adjustment −100 reversing x (03-12, "reversal entered in error")             admitted
n: nsf        +100 reversing y (03-13, "returned by the bank")                  admitted (FA1)
UPDATE payments SET status = 'reversed', status_cause_id = x                    admitted (FA2)
ledger_entry_remaining(E) = 0.00; ledger_entry_remaining(x) = 100.00; return_code NULL
misposting_returned −100 of the receipt, naming the payment, dated 03-13        ADMITTED (FA3)
suspense_receipt_position_as_of(receipt, 2026-12-31).held = 100.00
the customer's ledger under the payment nets 0.00
```

The customer has nothing; the bank took the 100 from the utility; the receipt reads 100 held and will fund another payment. Against the same posting entry, the identical three facts in the natural order (x +100, y −100 under x, n nsf +100 *under E*) give 0 back (P14b). The rule depends on where the operator attaches the bank's row, which is the label-not-the-act gap (`guard-the-act-not-the-label`). This shape is one notch less likely than r3's B1 (the bank's return must be keyed against the undo rather than the posting entry, as a "reverse the latest row" entry would do), but the money consequence is the same, the sequence is admitted to the app role with no chosen time, and the patch's comment states a rule it does not hold.

Fix (rule: -23's tree, read by the act): the misposted share is the sum of every row in the posting entry's tree **excluding each nsf row and everything beneath it** — walk down from E along `reverses_ledger_entry_id`, stop at an nsf row — bounded between 0 and the payment. Checked against the shapes in hand: P14a (x, y, z → 100), P14b (f4, f5, nsf f6 → 0), this probe (x, y, nsf n under y → 0, return refused), FC (nsf n under E, its undo m under n, x → x alone = 100, return admitted), the depth-3 shape (nsf n, m, k → 0). It also makes `least(v_pay.amount, …)` a true belt rather than a second rule. Battery: the probe above (return of 0.01 refused; the receipt holds 0) and FC (100 admitted, 100.01 refused). Mutation: the stop at nsf removed, named at the probe's check. A fail-closed alternative — refuse a misposting return while any nsf row anywhere in the tree has `ledger_entry_remaining <> 0` — also closes this probe, but would wrongly refuse a partial bank take-back beside a genuine misposting reversal; the walk is the right shape.

## S — should fix

None.

## N — notes

- **N1 (executed).** -23 admits an nsf row of −100 *directly under* a misposting reversal (a sign that means "the bank gave money"; FB1). Harmless here: it leaves the posting entry's tree at −100, so the payment cannot move to `reversed`, and -24 is never reached. If B1's walk is adopted, that row is excluded anyway.
- **N2 (executed).** After a return is recorded, the tree cannot be reshaped to lower the share: an undo under the reversal is a give-back to an ended payment (-23, `23001`, FE1); a second reversal would put the tree over its cap; a second return is the index (`suspense_receipt_dispositions_one_return_per_payment`, `23505`, FE2).
- **N3 (read).** `least(v_pay.amount, …)` does not bind on its own under -23's per-node cap (each direct child's remaining lies in 0..child, and the tree nets to the entry at `reversed`); the r4 plan says so and M106 exercises it via P14a. No mutation drops the bound alone; acceptable as a belt.
- **N4 (read).** Mutations M106–M108 mutate what they claim (the `sum(ledger_entry_remaining)` back to `sum(x.amount)`; the third branch's self-exclusion; the NaN clause with its pinned text) and name P14b, O4, L7f. No mutation covers B1's gap, which is why 109/109 passed with it open.
- **N5 (read).** Lock order: unchanged from r3. The misposted share is read under the receipt's lock only; a concurrent nsf insert at depth 3 does not race the return (the payment is already `reversed`, and an nsf row under y of a reversed payment is a take-back, which -23 admits regardless), so B1 needs no race leg — it is admitted serially.
- **N6 (read).** The invariant: `ledger_entry_remaining(uuid)` joined `c_app_exec` (-23 grants it to `tally_app`); the three body hashes changed in r4 match the live bodies (the invariant ran clean on my clone). Nothing narrower than its claim found.
- **N7.** Known limits L1–L6: none blocking.

## Answers to the brief's questions

1. **Round 3 and earlier.** Every finding of rounds 1–3 is closed as written. The patch implements the design and the rulings (CI-053, CI-056, the 11-07 refund rule within L5 and L6) except where B1 lets the bank's take-back come back to the receipt.
2. **Paths around a rule.** Found: B1 (a receipt's money released though the bank took it, as `tally_app`, no chosen times). Not found: out-of-bounds, cross-tenant or reason-less receipt payments; a database-made guess; a provider id twice; a pledge paid by another agency or customer or ended twice; an early lapse; a payment naming an error pledge; a misrouted refund in the traced origins; an agency brought back; an agreement edited (all by the r4 battery checks that re-ran here, as in my r2 and r3 reviews).
3. **-23 and -27.** -24 changes nothing they read; the new `payments` triggers still sort after -23's. B1 is -24 reading -23's tree by position rather than by type, not a change to -23.
4. **Concurrency.** Lock order followed; every cap and count read is under its lock and the pin; the races reproduce (24).
5. **Invariants.** Catches what it claims; N6.
6. **Tests.** Battery 256 and races 24 reproduced; no check weaker than its label among those traced (P9b3 now says what it tests). Missing: B1's nested-nsf shape and FC's undone-bank-return shape (N4).
7. **L1–L5.** None blocking (N7).
