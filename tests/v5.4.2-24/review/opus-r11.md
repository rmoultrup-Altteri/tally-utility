# Opus review: v5.4.2-24 r11 (unmatched cash and agency pledges)

**Date:** 2026-11-24. **Reviewer:** Opus. **Brief:** `review-brief-24-r11.md`, md5 `4040b5b267aa9775c6aaaaa6074df157`, which matches its `.md5`. I read the r11 plan, the r10-to-r11 diff, my own r10 review and the -23 guards the new rules lean on (`enforce_payment_immutable` as rewritten by -23, `enforce_ledger_reversal`). I read no Fable or Codex file.

**Verdict: ready.** Nothing is blocking. Every round-10 finding is closed, and I found no path around the four ending rules or the ledger trigger. These are the shapes I ran: rows added or undone after the end, an undone cause row, a status moved from reversed to nsf or back, several statements in one transaction, writable CTEs in both orders, multi-row inserts, COPY as the owner, and a superuser load under the replica role. One should-fix item is a test gap that does not need another round:

- **S1 (executed):** a deposit made from a receipt behaves exactly like an ordinary payment under every rule (D1 to D4 below), but the battery still has no deposit fixture. Any mutant that drops `'deposit'` from one of the three new walks therefore passes the battery.

The notes (N1 to N4) are comments and label precision.

## Hashes and reproduction (executed)

- All six frozen md5s match (patch `5518d763…`, battery `83283377…`, races `360dea4d…`, mutations `46f7ef48…`, ci diff `ec30f743…`, r10-to-r11 `f428a197…`).
- Clone `rv24opus` from `TEMPLATE tally` (which carries -30). TEMP was revoked from PUBLIC, `tally_app` and `tally_core` right after creation. The strict apply (`search_path=''`, `check_function_bodies=on`) is clean; the second run says "already applied (suspense_receipts exists); nothing to do".
- `battery-24-frozen-r11.sql`: **335 PASS, 0 FAIL**, rc 0.
- `suspense-24-frozen-r11.sh rv24opus`: **29 PASS** (SU1 to SU15b), rc 0.
- `tests/v5.4.2-23/battery-23.sql` (the live file already carries the -24 port in the ci diff; `patch -R --dry-run` applies cleanly) on the clone with -24 in place: **409 PASS, 0 FAIL**. This includes X3 and X3c, where `void_invoice()` runs as `tally_void` and writes a `void_reversal` row under a charge with the new ledger trigger enabled.
- Not run: `ci.sh` and `mutations-24.py` (not allowed), and -25/-26 beside -24. For those I rely on the author's 61/61 and 161/161.
- The clone is dropped, and the container's temp files are removed.

## 1. Round 10's findings

| Finding | State | Evidence (executed unless marked) |
|---|---|---|
| Codex B1, Opus S1/S3: what the bank took was ambiguous at the end | **closed** | P17 to P19c, P21, P22 pass. My E2 (coded, naming an undone row: refused 23514; naming the whole row: admitted) and D2 (part nsf, coded reversed: refused; nsf: admitted, 60 listed, 60 returned, held 60). |
| Opus S2: a code hid the payment at earlier instants | **closed** | S8y passes. The reader's gate is `status_recorded_at <= p_recorded_at`, and a code can no longer be written after the move (E3b refused). So the move's recorded time is the code's time, and no undated case is left. |
| Opus S4: a pending receipt payment undone, stranded | **closed** | P20, P20b; D3 (deposit) refused; Q3d (multi-row) refused; COPY as owner refused; superuser under `session_replication_role = replica` refused (Q3f). Race RD below. |
| Fable S2: born ended | **closed** | O7, O7b, as owner (superuser). |
| Conservation (Fable S1, Codex S2, Opus N4) | **closed, label overclaims** | See N2: over 41 receipts and 92 days the only miss is a pending payment, which the formula leaves out. |
| Opus S5: tests | **closed but for a11** | P17 to P22, S8t to S8za. Deposit still missing (S1). |
| r9 and earlier | **still closed** | Battery 335 and races 29 pass. r11 touches only the end of a receipt's payment, the reader's code gate, the born-ended insert and the new ledger trigger. |

**Design and rulings:** r11 changes nothing in CI-053's resolution paths, CI-056's readers or `cash_money_agency`. My earlier answers stand. The new rules make CI-053 hold at the end of a receipt's payment: after the move, the receipt's money is in exactly one of three places (the bank, the receipt, the due list), and nothing can later move it.

## 2. Paths around the new rules (question 2, executed as `tally_app` unless marked)

The rules lean on three facts from -23, each executed:
- a status move happens at READ COMMITTED only, under the payment's advisory lock (`enforce_payment_immutable`, which sorts before `enforce_payment_suspense_pledge`);
- statuses are terminal (E1d: nsf to reversed refused, 23001; E2d: reversed to nsf refused, 23001);
- `return_code` is write-once once recorded, under -19 (E1e, E1f, E2c: 23001). So -24's new rule against adding a code to a payment already reversed only has to close the change from no code to a code.

| Probe | Result |
|---|---|
| E1: plain 100, its undo, nsf 100; ended nsf (share 0) | admitted |
| E1b: after the end, a re-take of 100 under the undo | refused 23514 (the tree's cap: would net 200) |
| E1c: after the end, the nsf row undone | refused 23001 ("gives money back to payment … which has ended") |
| E2: plain A 100, A undone, plain C 100; reversed R01 naming A | refused 23514 ("only where the row it names takes back the whole") |
| E2b: the same naming C | admitted; due none, held 0 (the bank's) |
| E2e/E2f: after it, C undone, or a re-take under A's undo | refused 23001 / 23514 |
| E3/E3b: ended reversed with no code (40 nsf, 60 plain), then the code in a second statement of the same transaction | end admitted; code refused 23514; 60 stays listed |
| E4: one statement: `UPDATE … nsf` main, CTE inserts an undo of the bounce plus a plain re-take under it | refused 23001 (the CTE's rows land after the move, so the undo gives money back to an ended payment) |
| E4b: the CTE order reversed | refused 23514 (`is not typed nsf`) |
| E4d: CTE inserts the plain 60 and the main UPDATE ends coded naming it | refused 23503 (-23's cause check does not see the CTE's row) |
| E4e: the UPDATE in the CTE, the 60 inserted in the main statement | refused 23514 (the code rule sees the row) |
| COPY (owner) of an undo under a pending receipt payment's entry | refused 23514. As `tally_app`, COPY FROM is refused outright by RLS ("COPY FROM not supported with row-level security"). |

The tree is frozen at the end: a give-back is refused once the payment has ended, and a take-back hits the cap, since the entry has nothing left. So the order of moves offers no way round. A row cannot be added after the end, and a row cannot be undone after it. The cause row is checked by its remaining amount, so naming an undone row fails. Every way of splitting the work across statements was refused at one of these points.

**Earlier subjects in the brief's list** (a receipt spent twice, out-of-bounds dates, other tenants, the provider transaction, pledges, refunds, agencies, agreements): r11 changes none of their code. I re-ran the battery and races against them and did not re-probe them by hand.

## 3. The new trigger on `account_ledger` (question 3)

**Writers.** These are the INSERT grants on `account_ledger` in the clone: `tally` (owner, superuser, BYPASSRLS), `tally_app` and `tally_void`. `tally_core`, `tally_close` and `tally_seal` have SELECT only. The only function body in `public` that inserts into `account_ledger` is `void_invoice()`: SECURITY DEFINER, owned by `tally_void`, executable by `tally_app` and `tally_void`. Every copy of it in `tu.sql` (lines 1289 to 43634) writes a `void_reversal` row of `reference_type 'invoice_void'` under the bill's charge entry. -25 and -26 insert no ledger rows. The other SECURITY DEFINER functions (`get_user_tenant_id`, `is_platform_admin`, `assert_reference_version`, `reference_version_receipt_held`, `close_accounting_period`) do not write the ledger.

| Writer | Can the trigger refuse a legitimate write? | Can it fail for lack of a grant? |
|---|---|---|
| `tally_void` via `void_invoice()` | No. The parent is a charge, so the trigger returns after reading `account_ledger` alone (SELECT is granted). **Executed:** battery-23 X3/X3c pass with the trigger on. | No: it never reaches `payments`. |
| `tally_app`, ordinary payments | No. **Executed:** Q3a (a plain 100 reversal of a payment not from a receipt, then reversed) is admitted; P22 is admitted; battery-23's whole cash section (409) passes. | No. SELECT on `payments` is granted. The trigger calls no function, so its own EXECUTE grants do not matter: a trigger function is checked for EXECUTE only at CREATE TRIGGER. |
| `tally_app`, receipt payments | Only a row under a pending payment's posting entry, which -23 already forbids at the move (`ledger_tree_ids = 0`). **Executed:** the race RD below. | No. |
| owner or superuser load | Same as above. A load writes the posting row, then the move, then the reversal rows, as -23 requires. | No. |

**`ENABLE ALWAYS` and a replica load.** Under `session_replication_role = replica` the trigger fires: Q3f refused, as wanted. The two other replica paths are predicted, not executed:
- A logical-replication apply runs in commit order, so the subscriber reads the same `payments` state the primary had. If `payments` is not replicated, `EXISTS` is false and the row is admitted: no false refusal.
- A plain dump restore: with `--disable-triggers` nothing fires. Without it, either `payments` is empty or it holds final statuses, so the trigger never refuses data that was valid on the primary.

**Multi-row inserts and order.** This is an AFTER ROW trigger, run at the end of the statement for each row. It reads only the parent entry and the payment's status, so the order of rows does not matter. Q3c (an nsf row and a plain row in one INSERT under a posted payment) was admitted; Q3d (a posting entry and its undo in one INSERT, payment pending) was refused. AFTER triggers fire in name order: `enforce_ledger_lineage_acyclic`, `enforce_ledger_reversal` (-23, takes the tree's lock and then the payment's), `enforce_ledger_shortfall_source` (-27), `enforce_ledger_suspense_posted`, `enforce_shortfall_reissue_rows`. So -24's read runs under -23's payment lock.

**Race RD (executed, committed fixtures, two sessions).** A moves a pending receipt payment to posted and holds. B inserts a take-back under the posting entry. B waits on A's advisory lock (`pg_stat_activity`: Lock/advisory, blocked by A's pid), and after A commits it is admitted at 01:36:20.215. B is not falsely refused: the trigger's query takes a fresh snapshot at READ COMMITTED (forced by -23 for reversal rows) and sees `posted`.

## 4. -23's and -27's properties; concurrency (questions 3 and 4 of "What to answer")

- -24 adds refusals only. No reader of -23's or -27's positions, caps or recorded order changes. The ending checks read the tree (`suspense_misposted_share`, `suspense_untyped_take_back`, `ledger_entry_remaining`) under the payment's lock, which -23 takes before them in name order, at READ COMMITTED. SU13 to SU15b and RD pass.
- r11 drops r10's receipt lock and READ COMMITTED pin on a code change. That is safe: a code on a payment that is already reversed is now refused, and the only code still written without a move (no code to a code on an nsf payment) changes no reader. The reader's gate applies to reversed payments only, and the misposting return of a bounced payment is admitted with or without the code (P15h).
- No new cap is read without its lock.

## 5. The invariants

`assert_suspense_pledge_guard_invariants()` carries the new trigger's definition with `tgenabled = 'A'`, both new functions' attributes and body hashes, and `tally_app`'s EXECUTE on `suspense_untyped_take_back` and on -23's `ledger_entry_remaining`. I1 to I9e pass. Each claim I checked matches its check.

## B: blocking

None.

## S: should fix

**S1 (executed; brief question 1). A deposit made from a receipt behaves exactly like an ordinary payment, and nothing tests it.**
- D1: a deposit payment from receipt Ra1. Its posting entry is typed `deposit`. A plain 100 reversal lists it as "100.00 since 2026-03-11"; ended reversed with R01 naming the whole row, it is admitted and the list says none.
- D2: 40 nsf plus 60 plain. Coded reversed is refused 23514. Ended nsf, it is listed as 60, the return of 60 is admitted, and the receipt holds 60.
- D3: a pending deposit's entry undone: refused 23514 by the new trigger.
- D4: an untyped row under a bounce: the move to nsf is refused 23514.

No rule behaves differently for a deposit. Not blocking. But a mutant that drops `'deposit'` from `transaction_type IN ('payment', 'deposit')` in `suspense_untyped_take_back`, `enforce_ledger_suspense_posted` or the two share walks would pass every behaviour check. (Predicted: I ran no mutations; the battery has no `is_deposit` row from a receipt.) The fix is D1 to D3 above as battery checks, about ten lines, and needs no review round. Out of -24's scope, for the deposit patch (predicted, not executed: a `deposits` row needs -15's rule fixtures): a misposted deposit returned to its receipt leaves any `deposits` row recorded on the payment to -15's own reversal rules. The same is true of any reversed deposit payment, not only one made from a receipt.

## N: notes

**N1 (read). The lock order is load-bearing and stated nowhere.** Both new checks depend on a -23 trigger whose name sorts first and takes the payment's lock:
- `enforce_payment_immutable` before `enforce_payment_suspense_pledge`, for the ending checks;
- `enforce_ledger_reversal` before `enforce_ledger_suspense_posted`, for the ledger trigger.

The invariant pins both trigger definitions, so a rename would be caught. Still, say so in the two comments (I asked for this in r10 too).

**N2 (executed). S4c's label is wider than its check.** It says "every receipt of T1, every day". Its window is 2026-03-10 to 03-20, and it runs at line 1378, before the history-load receipts (O section, S8y's coded payment) exist. 10 of the 41 T1 receipts are dated after 03-20 (for example R8, 03-21), so it never reads them. I re-ran S4c's exact sum at the end of the battery over every T1 receipt from 03-01 to 05-31. The one miss is R10 (`R24-000b`), from 04-05 on: its 100 went to the payment P24-O1c, which is still `pending`. The receipt reader puts that 100 under `to_payments`, but S4c's formula counts only `received`, which is 0 while a payment is pending. With that receipt left out, nothing fails. Fix: widen the series and move S4c to the end, or add the pending payments' amounts to the sum.

**N3 (executed). A receipt's payment left pending is on no list.** RD-2's position is to_payments 100, held 0; the returns-due list is empty. A pending payment can still be posted or voided, so the money is not stranded as it was in r10 S4. But no reader ages it against the service level. This belongs with -23's pending lifecycle, not -24. If it is wanted, it is a later reader.

**N4 (executed).** A payment made from a receipt and then returned is spent again only at a date on or after the return (my first try, dated on the receipt's day, was refused by the cap: "on 2026-03-10 … 200.00"). That is the cap working as designed, but worth one line in the application contract: the new payment's `payment_date` is not before the misposting return.

## Limits L1 to L6

r11 changes none of them, and none is blocking.
