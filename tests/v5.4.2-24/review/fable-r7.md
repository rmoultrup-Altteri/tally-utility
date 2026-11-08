# Fable review — v5.4.2-24 r7 (unmatched cash and agency pledges)

**Date:** 2026-11-07. **Reviewer:** Fable (claude-fable-5-1). **Brief:** `review-brief-24-r7.md` (md5 `e70288b5…`, matched its `.md5`).

**Frozen hashes checked, all matched:** patch `b82ca100…`, battery `f910a8ba…`, races `55c63199…`, mutations `d89f7cb5…`, ci diff `c343828b…`, r6-to-r7 `e1e99c48…`. I reviewed the frozen copies only (the live copies were being edited while I worked).

**Verdict: ready.** Round 6's blocker and both should-fix items are closed, and my own round-6 should-fix (the conservation sweep) is in as S4b and has teeth: I forced the exact round-6 shape past the guard in my clone and the sweep flagged it, and nothing else. Every earlier finding still holds. No blocking item, nothing to fix; notes only.

**Scratch database:** `rv24fable` (TEMPLATE `tally`; TEMP revoked from PUBLIC, `tally_app`, `tally_core`; frozen r7 patch applied strictly twice; the battery; the races; my probes spliced into a copy of the battery and rolled back with it; dropped at the end, confirmed gone). I did not run `ci.sh` or `mutations-24.py`; created, dropped or altered no role; read no `opus-*` or `codex-*` review file (I listed the `codex-r6-probes/*.author-run.txt` names only). Two `crystaldba/postgres-mcp` containers were running at my start; I did not touch them.

## Reproduced (executed)

- Strict apply (`search_path=''`, `check_function_bodies=on`): clean; the second run is skipped by its marker ("already applied (suspense_receipts exists)").
- `battery-24-frozen-r7.sql`: **275 PASS**, 0 FAIL (rolled back).
- `suspense-24-frozen-r7.sh rv24fable`: **24 PASS** (SU1–SU12b).
- `assert_suspense_pledge_guard_invariants()` on the clone after the battery and the races: clean. The live body of `enforce_suspense_disposition` hashes to `885503e246bf54139455c377d3688cee`, the value the frozen invariant pins (the only pin that changed from r6).
- Trigger order on `payments` is unchanged from r6 (-23's `a_*` first; `enforce_payment_suspense_cap` and `enforce_payment_suspense_pledge` sort after `enforce_cash_draw`); all `ENABLE ALWAYS` except `set_updated_at`.

## Round-6 findings — closed (executed unless marked)

- **Codex r6 B1 — a misposting return recorded before the ledger row that gives its money back.** What it did to the money: in a database owner's history load, a read at the transaction's start instant saw the receipt holding its 100 again (the return) while the wrong customer's payment still held the same 100 (its reversal was stamped later), so one cheque counted as 200 at that instant and a second customer's payment from the receipt was admitted as of then. The fix reads `max(created_at)` over the same tree walk as the dates and refuses a return stamped earlier than it (40001 when the stamp is the transaction's start, 23514 when it was chosen). I checked the reasoning against -23's reader, not only the plan: `payment_draws_as_of` computes what a payment still holds from the posting entry's tree filtered by `transaction_date <= d AND created_at <= at`. Since the return is now dated on or after every tree row (r6) and recorded no earlier than every tree row (r7), at every date-and-instant pair where the return is visible, every tree row is visible too, so the payment's side already shows the money gone when the receipt's side shows it back. P14i0 (the shape holds), P14i (40001), P14i2 (admitted at a later instant), P14i3 (positions at both instants) all re-ran here. My probes: **FP2** a return stamped one microsecond before the reversal's recorded instant, a chosen time later than the transaction's start, is refused 23514 with "money comes back only after what gives it back is known" (FP2b confirms the stamp was past the start, so this rule and not the recorded-order helper decided). **FP3** a return stamped at exactly the reversal's recorded instant is admitted (the rule is "no earlier than"), and FP3b shows the positions agree on both sides at that instant: receipt 100 and payment 0; one microsecond earlier, receipt 0 and payment 100. Never both 100.
- **Codex r6 S1 — the separate reversal-date check removed.** The reversal the payment names is a row of the tree, so the tree-date rule always refused first. P9b2 now expects the tree-date message (re-ran). M74 is gone; M112 is named at P9b2. Predicted: with the tree-date rule removed, P9b2's return (dated 03-04, payment dated 03-03, reversal 03-05) is refused by nothing else, so P9b2 is the first check to fail, as the runner expects.
- **Codex r6 S2 — the invariant passed over a missing helper.** `has_function_privilege` returns NULL for a function that does not exist and the filter dropped the row; now `coalesce(…, false)`. I9d2 (drop -23's `cash_source_lock_key`, invariants raise 0LP01 naming it) re-ran. The body-pin, attribute and NOT NULL sections already used NOT EXISTS, so a missing pinned object was always reported there; only the EXECUTE list had the gap.
- **My r6 S1 — a conservation sweep.** S4b is my FH sweep widened to recorded instants: for every receipt of the tenant, every date anything is dated on, and every instant anything was recorded at, what the receipt holds plus what its payments still hold on the ledger plus what left to a sender, a bank or a state never exceeds the receipt. The instant set is right: the payment side's `received` steps only at ledger rows' `created_at`, the receipt side at receipts', payments', dispositions' `created_at` and payments' `status_recorded_at`, and all of these are sampled. **FP1 (teeth, executed):** in a savepoint I built the round-6 shape, disabled `enforce_suspense_disposition` on the clone's table, inserted the return stamped at the transaction's start, re-enabled the trigger, and ran S4b's query: it flagged that receipt and only that receipt, at every date from the reversal's date on and at every sampled instant from the transaction's start up to (not at) the reversal's recorded instant, each cell showing receipt 100 + payment 100 against a receipt of 100. FP1c: FP3's correctly stamped receipt is never flagged. So the net catches the class, not only the instance.

Rounds 1–5 (my r1 B1, B2, S1, S2; r2 B1, S1; r3 B1, S1; r4 B1; r5 S1, S2; the brief's list for the others): still closed by the same battery checks, all of which ran again here.

## Probe SQL (executed; spliced into a copy of the battery, FP2 after P14i, FP1 and FP3 in a savepoint after P14i3 and rolled back so S4 stays 770)

```sql
-- FP2: a chosen time between the start and the reversal's recorded instant.
SELECT pg_temp.refuses_at('FP2 ...',
  $q$INSERT INTO public.suspense_receipt_dispositions (tenant_id, suspense_receipt_id, kind, amount, disposed_on, reason, recorded_by, returned_payment_id, created_at)
     VALUES (pg_temp.t1(), pg_temp.k('9a'), 'misposting_returned', -100, DATE '2026-03-11', 'posted to the wrong customer', pg_temp.op(), pg_temp.k('9b'),
             (SELECT l.created_at - interval '1 microsecond' FROM public.account_ledger l WHERE l.id = pg_temp.k('9d')))$q$,
  '23514', 'money comes back only after what gives it back is known');

-- FP3: fixture c6 (receipt 100, 03-10), payment c7 posted c8, reversal c9 at clock_timestamp(), payment reversed;
-- a return stamped at c9's created_at exactly is admitted; positions at c9.created_at and 1 us before as stated above.

-- FP1: fixture a3/a4/a5/a6 as above; then
ALTER TABLE public.suspense_receipt_dispositions DISABLE TRIGGER enforce_suspense_disposition;
INSERT INTO public.suspense_receipt_dispositions (id, tenant_id, suspense_receipt_id, kind, amount, disposed_on, reason, recorded_by, returned_payment_id, created_at)
VALUES (pg_temp.k('a7'), pg_temp.t1(), pg_temp.k('a3'), 'misposting_returned', -100, DATE '2026-03-11', 'posted to the wrong customer', pg_temp.op(), pg_temp.k('a4'), now());
ALTER TABLE public.suspense_receipt_dispositions ENABLE ALWAYS TRIGGER enforce_suspense_disposition;
-- S4b's query, selecting the offending cells into a temp table; assert every hit is receipt a3, d >= 03-11,
-- now() <= at < a6.created_at, held = 100, on_ledger = 100; and no hit on c6.
```

## N — notes

- **N1 (read).** The 40001 branch's message says the tree row "was recorded after this transaction began"; in the history-load shape it was recorded by this same transaction, stamped with `clock_timestamp()`. The advice is still right: a retry in a new transaction starts after that instant and is admitted (P14i2 shows the admit at a later stamp). Wording only.
- **N2 (read).** In the ordinary flow, a reversal and its return both default to `now()`, so a return recorded in the same transaction as the reversal meets `created_at = v_tree_recorded`, not `<`, and is admitted: the new rule costs the clerk nothing (P14h3's shape). Only a stamp chosen earlier than a tree row's is refused.
- **N3 (read).** A tree row's `created_at` can never be in the future (-23's `enforce_ledger_reversal` refuses it), so a row visible with a stamp later than our `now()` was truly recorded after our start, and the retry is never a loop.
- **N4 (read).** Once the payment is `reversed`, no row can join its tree (-23 refuses give-backs because the payment has ended and take-backs because the tree is already at its cap; my r6 FG). So `v_tree_recorded`, like `v_tree_last`, is fixed when the return is checked, and the lock order is unchanged: the receipt's lock, then the payment and its tree are read.
- **N5 (executed, FP1 cells).** The sweep flags the doubled money at every sampled instant between the start and the reversal's recorded instant, not only at the start: the instants other fixtures recorded at `clock_timestamp()` in between fall into the window too. That is the sweep working as designed (positions are step functions; it samples every step).
- **N6 (read).** S4b checks over-counting only (`> r.amount`), which is its label ("counts twice"). Money that left a receipt through a bank's take-back of a payment is in neither term and reads as an under-count, allowed by design. S4b also inherits -23's reading that a payment holds nothing before its `payment_date` even when its posting entry is dated earlier (my r6 N4); not -24's property.
- **N7 (predicted).** M113 is named at P14i rightly: with the recorded-instant rule removed, `check_suspense_recorded_order` does not read ledger rows (it reads the receipt's dispositions and payments, and a reversed payment's `status_recorded_at`, which equals the start stamp here), so the return is admitted and P14i is the first check to fail. M114 at I9d2: the body-pin list does not carry `cash_source_lock_key`, so with the coalesce removed the invariant passes and I9d2 is the first to fail. Both anchors occur once in the frozen patch.
- **N8 (read).** The invariant's other EXECUTE checks (`has_function_privilege(text, text, text)` on the three helpers that must not be callable by `public` or `tally_core`) raise 42883 if a helper is dropped, rather than listing it under 0LP01. Loud either way.
- **N9.** Known limits L1–L6: none blocking, as in r6. L4 (no suspense line in the period close) still has `suspense_held_as_of` as its reconciling figure.

## Answers to the brief's questions

1. **Round 6 and earlier.** Codex r6 B1 closed (P14i–P14i3, my FP2 and FP3, and the reasoning against -23's reader above); Codex r6 S1 and S2 closed (P9b2, I9d2); my r6 S1 closed (S4b, teeth shown by FP1). Rounds 1–5 still closed. The patch implements the design and the rulings (CI-053, CI-056, the 11-07 refund rule within L5 and L6).
2. **Paths around a rule.** None found. A receipt spent twice at any date or recorded instant: S4b over every fixture (and FP1 shows it would have caught round 6's shape). The rest of the brief's list is held by the rounds 1–6 checks that re-ran here; the roles, isolation levels and statement shapes were Codex's probes 02–04 in rounds 5 and 6, whose author runs exist.
3. **-23 and -27.** -24 still reads -23's tree by type, sign and link alone and calls none of -23's helpers; the r7 change adds a read of `created_at` on the same rows. Nothing -23 or -27 reads changes. The `payments` trigger order is unchanged.
4. **Concurrency.** Lock order unchanged (N4). The races reproduce (24).
5. **Invariants.** Catch what they claim; the EXECUTE gap is closed (I9d2).
6. **Tests.** Battery 275 and races 24 reproduced; checks traced match their labels; mutations re-anchored correctly (N7). Nothing missing that I would hold the mirror for.
7. **L1–L6.** None blocking (N9).
