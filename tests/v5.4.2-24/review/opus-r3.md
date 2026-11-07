# Opus review — v5.4.2-24 r3 (unmatched cash and agency pledges)

**Date:** 2026-11-07. **Reviewer:** Opus. **Brief:** `review-brief-24-r3.md` (md5 `de2313fe8d200b9012063bf62626a51b`, matches its `.md5`). I read the r2 and r3 plans and my own r1 and r2 reviews, and no other reviewer's file.

**Verdict: not yet.** One blocking item. The new misposting-return limit (Codex r2 probe 01) adds up only the ledger rows directly under the payment's posting entry. -23 nets the whole tree of reversals, including a reversal that is itself undone. So a reversal entered, undone and entered again lets a 100 payment give 200 back to its receipt. A receipt of 100 then funded a new payment of 200. And a reversal entered and undone, followed by the bank taking all 100 back, still gave 100 back to suspense. Both ran as `tally_app` at READ COMMITTED with ordinary ledger rows. The fix also dropped r2's "at most the payment's amount" bound, which would have stopped the first case. One should-fix item: a NaN payment naming a pledge makes the pledge read `paid`. One should-fix item on the tests. Every other round-2 finding is closed, and every round-1 finding is still closed.

## Hashes and reproduction (executed)

- The six frozen md5s match the brief: patch `209260b5…`, battery `f7fab303…`, races `88c9c30b…`, mutations `a2892027…`, ci diff `c343828b…`, r2-to-r3 diff `4921c86e…`. The live patch, battery, races and mutations are identical to the frozen copies.
- Clone `rv24opus` (`TEMPLATE tally`; TEMP revoked from PUBLIC, `tally_app` and `tally_core`). Strict apply (`search_path=`, `check_function_bodies=on`): rc 0, and the tail's invariants passed. Second run: `NOTICE: v5.4.2-24: already applied (suspense_receipts exists); nothing to do`, rc 0.
- `battery-24-frozen-r3.sql`: 251 PASS, 0 FAIL, rc 0.
- `suspense-24-frozen-r3.sh rv24opus`: 24 PASS, 0 FAIL, rc 0 (SU1–SU12).
- I did not run `ci.sh` or the mutation runner. I created, dropped or altered no role and did not touch `tally`. The clone is dropped, and `/tmp/rv24opus-*` is removed from the container.
- Probes: the battery's helpers and fixtures (battery lines 1–177) as a prefix, then the probe, in one transaction that was rolled back. The probe scripts were scratch files and are not in the repo.

## Round-2 and round-1 findings: are they closed?

| Finding | State | Evidence |
|---|---|---|
| r2 Opus B1, Fable B1, Codex probe 03 (releases not ordered) | closed | Every disposition calls `check_suspense_recorded_order`, and its union reads `status_recorded_at` of voided and reversed payments. Battery O1g (a chosen-time misposting return before the reversal) passes. SU11 (an undo begun before its original committed) and SU12 (a misposting return begun before the reversal committed) both get 40001, and their retries are admitted. Executed. |
| Codex r2 probe 02 (self-exclusion across tables) | closed | `NOT (NOT p_self_is_payment AND d.id = p_self)` and its mirror. Battery passes. Executed (battery) and read. |
| Codex r2 probe 01 (partly bounced payment returned whole) | **closed for the probe's shape; the fix opens B1** | See B1. |
| Codex r2 probe 07 (NaN) | closed on -24's own tables | The three amount CHECKs refuse NaN, and the battery passes. A NaN payment from a receipt is refused by the cap. A NaN payment naming a pledge is not refused: see S1. |
| r2 Opus S1, Fable S1, Codex probe 06 (the invariant's reach) | closed | `c_bodies` covers 28 functions, including the nine I named in r2. `c_attrs` covers volatility, security and settings. `c_notnull` covers 54 columns, and `c_app_exec` covers 11 functions. The battery's I-checks catch a replaced pin body, a changed attribute, a revoked EXECUTE and a dropped NOT NULL. Function owners are already pinned by -20's role invariant (`tu.sql` around line 39209). Executed (battery) and read. |
| r2 Opus N4 (a load with foreign keys off) | closed for dispositions and pledge events | Both guards now read the parent `AND x.tenant_id = NEW.tenant_id`. Candidates are still open: see N2. Read. |
| r2 Opus N1 (stale comments) | closed | The table comment, the position reader's comment and the header now describe r2 and r3. Read. |
| r2 Opus N2 (provider id at SERIALIZABLE) | closed as an application contract | Header line, to be recorded in APPLICATION-CONTRACTS at the mirror. Read. |
| Round 1, all | still closed | Unchanged code paths. The battery and races still pass. |

The patch implements the design, CI-053, CI-056's record side, and Ryan's 11-07 rule within L5 and L6, apart from B1.

---

## B — blocking

### B1. The misposting-return limit adds up only the direct reversals, so a reversal that was undone and entered again gives back twice, and a bounce after an undone reversal gives back money the bank took (executed)

r3 replaced r2's bound (`-NEW.amount > v_pay.amount`) with this:

```sql
SELECT coalesce(sum(x.amount), 0) INTO v_misposted
  FROM public.account_ledger e
  JOIN public.account_ledger x ON x.reverses_ledger_entry_id = e.id AND x.transaction_type <> 'nsf'
 WHERE e.reference_type = 'payment' AND e.reference_id = v_pay.id AND e.reverses_ledger_entry_id IS NULL
   AND e.transaction_type IN ('payment', 'deposit');
```

This reads one level of the tree. -23 lets a reversal row be reversed in turn: `account_ledger_reversal_types_only_check` admits `adjustment` at any depth. -23's `ledger_entry_remaining` then nets the whole tree (`ledger_tree_ids`, at any depth). That net is what -23's move to `reversed` reads (`remaining = 0`). So -23 and -24 disagree about how much was reversed.

**Q1: a reversal entered, undone and entered again (executed, as `tally_app`, READ COMMITTED).** The receipt is 100, and its payment of 100 to C1 is posted (posting entry e, −100). Then:
- A: an `adjustment` of +100 reverses e.
- B: an `adjustment` of −100 reverses A ("reversal entered in error").
- C: an `adjustment` of +100 reverses e again.

`ledger_entry_remaining(e) = 0.00`, and the move to `reversed` naming C is accepted. `v_misposted` = A + C = 200.

```
Q1e misposting return of 200 on a 100 payment => ACCEPTED
 Q1 position | amount 100.00 | to_payments 100.00 | disposed -200.00 | held 200.00
Q1f a new payment of 200 from the receipt of 100 => ACCEPTED
```

A receipt of 100 then paid 200 to C2. That is money the bank never received, put on a customer's ledger as paid, which is the exact thing CI-053 forbids. r2's bound would have stopped this, but r3 removed it.

**Q2: a reversal entered and undone, then the bank takes it all back (executed, same role and level).** The receipt is 100, and its payment of 100 is a check, so no return code is required. A reverses e by +100, B reverses A by −100, and an `nsf` row of +100 reverses e. Remaining is 0. The move to `reversed` naming A (non-nsf, reverses e) is accepted by -23. `v_misposted` = A = 100, because B is a grandchild and is not read.

```
Q2c misposting return of 100 (the bank took all 100) => ACCEPTED
 Q2 position | amount 100.00 | to_payments 100.00 | disposed -100.00 | held 100.00
```

The bank took the whole 100, yet the receipt holds 100 again. That is Codex r2 probe 01's defect (the bank's money given back), reached through a one-step-deeper tree.

**Why it blocks.** It is a path around the round's own new rule. It lets one receipt be spent twice, which is the first case the brief asks about, and the shapes are ordinary clerk corrections ("reversal entered in error"). Nothing later repairs it: -23 refuses further ledger rows on an ended payment, so the tree is fixed as it was at the move.

**Fix (measure it; lesson `reviewer-fixes-need-measuring`).** Measure over the same tree -23 measures. For example: what was misposted = the payment's amount less the net of every `nsf` row in `ledger_tree_ids(posting entry)` together with its own subtree, and never more than the payment's amount. Check it against these cases:
- Q1 gives 100.
- Q2 gives 0.
- Codex probe 01 gives 60.
- A bounce that was itself reversed (the check cleared after all), followed by a misposting reversal, gives 100.

Restore `-NEW.amount <= v_pay.amount` as a separate bound either way. A narrower alternative is to refuse a misposting return when anything in the tree sits more than one level below the posting entry, so it fails toward protection. Tests: Q1 and Q2 in the battery. Add a mutation that drops the tree walk (back to direct children), and one that drops the restored payment-amount bound.

---

## S — should fix

### S1. A NaN payment naming a pledge makes the pledge read `paid` (executed)

`payments_agency_pledge_check` is -24's own CHECK on `payments`. It requires `amount > 0`, which NaN passes (lesson `check-passes-null`). As `tally_app`: an agency, a pledge of 100, an agency payment of `'NaN'` naming it, and then posting it are all accepted.

```
 agency_pledge_position_as_of => amount 100.00 | paid NaN | outstanding NaN | state paid
```

`x.paid >= l.amount` is true for NaN. So the pledge -26's `agency_pledge` condition reads is "paid", and that condition stops protecting the pledged portion. -23's general NaN gap is rightly left to a later money patch. But this CHECK is -24's, and r3 fixed the identical clause on -24's three tables. **Fix:** `AND amount <> 'NaN'::numeric` in `payments_agency_pledge_check`, its manifest entry, a battery case and a constraint mutation. For symmetry, consider the same clause in `payments_suspense_resolution_check`. The cap already refuses a NaN payment from a receipt, but only at the AFTER trigger.

### S2. A test is weaker than its label, and the removed bound went unnoticed (read, then executed via Q1)

P9b3 is labelled "it gives back at most the payment". It refuses 50.01 on a 50 payment, but only because the direct sum is also 50. Nothing in the battery or the mutations distinguishes "at most the payment" from "at most what was reversed as misposted", so removing the payment-amount bound passed 251 checks and 106 mutations. The P13 case (40 nsf + 60 misposted) has only one level. Add Q1 and Q2 from B1, and pin P9b3 to the bound its label names (lesson `checks-narrower-than-their-claim`).

---

## N — notes

- **N1 (executed). -23's and -27's properties.** r3 changes only -24's functions. The new tenant clauses and the wider order union read -23's rows and write none of them. `enforce_payment_suspense_cap` still fires AFTER INSERT under the receipt's lock, after -23's triggers, and only reads. The battery-23 port and the races pass. Nothing in r3 changes what -23's positions, caps or recorded-order rules see. The B1 disagreement is between -24's limit and -23's tree, not a change to -23.
- **N2 (read; predicted). Candidates with foreign keys off.** `suspense_receipt_candidates` has no guard trigger, so a superuser load under `session_replication_role = replica` can write a candidate of another tenant's receipt. A candidate is a hint and moves no money, and RLS hides it from the other tenant, so this is harmless. One sentence in the header ("a history load runs with foreign keys on") would cover it with the other tables.
- **N3 (read). `c_app_exec` has a NULL leg.** `has_function_privilege('tally_app', to_regprocedure(...), 'EXECUTE')` is NULL for a missing function, and `NOT NULL` filters it out. Every listed function except `cash_source_lock_key` is also in `c_bodies`, which reports a missing one. `cash_source_lock_key` is -23's and pinned by -23's invariant. So nothing escapes today, but `coalesce(..., false)` would make the check say what it means.
- **N4 (read). Concurrency.** The new tenant reads come after the advisory lock in both guards, so the lock order is unchanged: payment, then receipt; pledge on its own key. The misposting limit's ledger read runs under the receipt's lock. -23 refuses new ledger rows on an ended payment, so the tree cannot change under it. No cap is read without the lock that orders it.
- **N5 (judgement). Known limits.** L1 and L3 are fine. L2 fails toward protection. L4 is fine once B1 is fixed (B1 overstates `suspense_held_as_of`). L5 and L6 stand by Ryan's 11-07 ruling. None is blocking.
- **N6 (predicted; executed in r1). COPY, writable CTEs and multi-row inserts.** The cap's statement shape is unchanged since r1 (AFTER ROW, under the receipt's lock), so I did not re-probe it. B1 does not depend on statement shape.
- **N7 (environment).** Two `crystaldba/postgres-mcp` containers (`pgmcp-67591-…`, `pgmcp-67190-…`, up 44 hours) were running beside `tally-pg` during this review. I left them alone, but they are the leak the session-start check warns about.
