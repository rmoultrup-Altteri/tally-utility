# Opus review: v5.4.2-24 r10 (unmatched cash and agency pledges)

**Date:** 2026-11-22. **Reviewer:** Opus. **Brief:** `review-brief-24-r10.md`, md5 `2c1baad89f2410260629edbf17621471`, which matches its `.md5`. I read the r10 plan, the r9-to-r10 diff and my own r9 review. I read no Fable or Codex file.

**Verdict: not yet.** Nothing is blocking. The reader itself is right: two randomized runs found no date or recorded instant where it counts money twice or loses it, apart from S2's coded payments. Five should-fix items:
- **S1 (executed; new in r10):** a payment ended `nsf` when no nsf row under it still stands gives its whole amount back to the receipt, bank's code notwithstanding. The same tree ended `reversed` with the same code gives nothing back.
- **S2 (executed):** the reader drops a coded payment at recorded instants before its status move, when nobody could have known the code.
- **S3 (executed):** the proposed limit L7 loses money off every list, and one condition closes it.
- **S4 (executed):** a receipt's payment whose posting row is undone while it is still `pending` can never end and never give its money back.
- **S5 (executed, tests):** 13 wrong versions (two of them boundaries) pass every behaviour check; only the body hash catches them.

## Hashes and reproduction (executed)

- All six frozen md5s match.
- Clone `rv24opus` from `TEMPLATE tally`, TEMP revoked from PUBLIC, `tally_app` and `tally_core`. Strict apply clean; the second run says "already applied (suspense_receipts exists); nothing to do".
- Battery: 309 PASS, 0 FAIL, rc 0. Races: 24 PASS, rc 0.
- Not run: `ci.sh` and `mutations-24.py` (not allowed), and -25, -26, -30 beside -24. For those I rely on the author.
- The clone is dropped.

## 1. Round 9's findings

| Finding | State | Evidence |
|---|---|---|
| Codex B1, Opus S1, Fable S1: the reader at past coordinates | **closed**, but for S2's coded payments | F1, F2 below. |
| Opus S2: a partly misposted payment strands its share | **closed for the shapes named** (Q1, Q2, Q3); the rule opens S1 | P15 to P16b pass; P6, RA to RC below. |
| Opus S3, Codex S1, Fable: tests | **partly**: S4b and S4c are sound; S5 | Mutants below. |
| r8 and earlier | **still closed** | r10 adds one refusal, loosens one guard, adds a status to the order check and one reader function. Battery and races pass. |

**The reader (F1, F2; executed).**
- F1: 500 random payments, 1,385 random rows (nsf and adjustment, any depth, undos of undos, redeposits, payment dates up to three days after the posting row), each payment ended and some returned. At 47 dates each (23,500 points): 0 above the receipt; `due_since` equal to a brute-force first day of the unbroken run at every point; every shortfall equal to what the nsf rows hold; the final share equals the as-of share at the end for all 500.
- F2: 150 payments with rows recorded an hour apart (owner's chosen times), read at 13 instants by 24 dates (46,800 points): 0 over, 0 unequal (held + on the account + due + net of the nsf rows = the receipt), `due_since` 0 wrong.
- Pruning: no row is visible before its parent (dates and recorded times go down the tree in order under -23), so a pruned subtree is whole at every coordinate. Read; consistent with F1 and F2.

**S4c's seven receipts: not picked to pass (executed).** Over all 25 of the battery's T1 receipts then present, three differ from S4c's formula. Two (…14, …17) differ only because it adds nsf rows gross, without their undos. With the nsf rows net of what is under them, 24 of 25 are equal at every date, and the one left is R9, the whole take-back recorded as reversed R10. So S4c can run over every receipt but R9, with no list.

**The nsf return: lock order and races (executed; not in SU1 to SU12).**
- RA: A inserts a plain reversal of 60 (40 is already nsf) and holds; B ends the payment reversed with R01, naming A's row. B waits, then is refused ("60.00 was reversed otherwise"). The check reads the share safely only because `enforce_payment_immutable` sorts before `enforce_payment_suspense_pledge` and takes the payment's lock first; say so in the comment.
- RB: A moves the payment to nsf and holds; B's return is refused at once ("is posted"). B does not wait, because the move takes no receipt lock. Safe.
- RC: A returns 60 and holds; B writes R01 on the bounced payment, waits, and is admitted: nsf, R01, held 60.
- The nsf row, the nsf move and the return in one writable CTE: admitted, held 60 (P6). Give-backs after the nsf end: 23001. Further take-backs: 23514 (P7). `tally_app`.
- No path takes the receipt's lock and then a payment's within one statement; a transaction that returns first and then touches the ledger can deadlock (40P01), as before.

**Design, rulings, -23 and -27 (3), invariant (5), limits L1 to L6 (7):** r10 adds no table, trigger or lock, so my earlier answers stand. The invariant carries the new function in its attribute and body lists. None of L1 to L6 blocks.

## B: blocking

None.

## S: should fix

**S1 (executed, P2, `tally_app`). A bounce with nothing bounced gives the whole payment back.** Receipt 100, paid to C1. An nsf row takes 100 (03-11); the check is presented again, so the nsf row is undone (03-12); the bank takes it again and the clerk enters that as an adjustment of 100 (03-13), then ends the payment `nsf` with R01, naming the first nsf row. -23 admits it (an nsf row directly under the posting entry, and nothing left). Share 100, **listed as due 100**, return of 100 **admitted**, held 100, and 100 **paid to C2**: the receipt's money is spent twice, once by the bank. r9 refused this return. The same tree ended `reversed` with R01 (P2b) is admitted, not listed and not returned, so the same evidence is read two opposite ways.

The other reading is possible (redeposited, then really misposted, then closed as nsf), so barring the return would strand the money. **Fix (the author's own rule: leave neither reading open), executed on the clone:** refuse the move to `nsf` of a receipt's payment whose share is the whole amount, because then no nsf row under it stands. The clerk ends it `reversed`, with a code (the bank's) or without (misposted). With it P2 is refused and the battery passes up to I1's body hash.

**S2 (executed, P3). A code written with the status move takes the payment off the list at instants before the move.** Plain reversal recorded 04-04, read at recorded 04-05: "100.00 since 2026-04-03". Then the move to `reversed` with R01, recorded 04-10. The same read at 04-05 now says none, with held 0 and received 0. So one recorded instant has two answers, and at 04-05 the money is nowhere. The comment's limit ("a return code has no recorded time of its own") covers a code written after the move. This one's time is known: a code cannot exist before its payment has ended (`payments_return_code_check`), so not before `status_recorded_at`. r9's filter had `status_recorded_at`; r10 dropped it. **Fix, executed:** `AND NOT (p.status = 'reversed' AND p.return_code IS NOT NULL AND p.status_recorded_at <= p_recorded_at)`. The read at 04-05 then keeps its answer. The limit that remains is the interval between the move and a later code.

**S3 (executed, P4, P2c). L7 is not acceptable, and there is a rule.** 60 reversed as misposted and 40 as the bank's, both plain, ended `reversed` R01: listed 100 before the move, then none; the return is refused, paying 60 to C2 is refused, held 0. 60 is on no account, receipt or list, and nothing can bring it back: the class the plan treated as blocking in r9. P2c reaches the same loss with nsf rows in the tree (40 nsf, undone, then 60 and 40 plain): share is the whole, so r10's check passes it. The database cannot tell the rows apart, but it need not. A code on `reversed` describes the row the status names, so **admit it only where that row stands for the whole payment**: in r10's condition, `v_share > 0 AND (v_share < NEW.amount OR ledger_entry_remaining(NEW.status_cause_id) < NEW.amount)`. **Executed:** P4 and P2c are refused, P12a (one whole reversal, R10) and P2b are admitted, and the battery passes up to I1. Nothing is lost by the refusal: end without the code, return the whole, and record the bank's part as `bank_returned` from the receipt with its code. The message should say that, rather than "as nsf rows". A later code (P16b's path) reads the same row.

**S4 (executed, P1, `tally_app`). A receipt's payment undone before its move to posted is stranded for good.** The posting row (-100) is written for a pending payment and a reversal (+100) under it, both admitted; the payment is never moved. Then: `posted` is refused (something is under the entry), `voided` is refused (it is on the ledger), `reversed` is refused (pending), the return is refused ("is pending"), and paying C2 is refused (200 against 100). r10's reader lists 100 forever, which is at least loud, with no row that clears it. -23 says the row and the move are written together, but nothing holds it, and for a receipt's money the result is CI-053's. Admitting the return is not the fix (a pending payment's tree still takes give-backs). **Fix, executed:** an AFTER INSERT trigger on `account_ledger` refusing a row under the posting entry of a receipt's payment still pending (appendix). The payment is then still postable, and reversed afterwards in the ordinary way; the battery passes up to I1. If a ledger trigger is not wanted in -24, state it as L7 and carry it to -23's owner.

**S5 (executed, tests). Thirteen wrong versions pass every behaviour check** (each put into the battery after BEGIN; all first fail at I1's body hash). As in r9, the hash shows the body is unchanged, not that it is right.

| | Wrong version | What would show it |
|---|---|---|
| a3 | an undo or deeper row counts before it is recorded | a read at an instant between a reversal and its undo |
| a9 | `since` before the payment's own date | 20 on 03-15: since 03-15 |
| a10 | `since` is the latest row, not the first of the run | two partial reversals on two dates: since the first |
| a11 | a deposit's entry is not read | a receipt's payment with `is_deposit`, reversed |
| a12 | an nsf row under an undo is counted as misposted (the reader; P14 covers only the guard) | P14e's tree read by the reader |
| a14 | `since` nets the dates backwards | a partial undo, then more |
| a15, a16 | the payment's own date, or instant, excluded (boundary) | reversed on the payment's date, read that day |
| r3 | any return of the receipt hides every payment of it | two payments of one receipt, one returned |
| r6 | `customer_id` not returned | one check of the column |
| g2 | `reversed` with a code refused where the share is 0 | nsf takes it all, ended reversed with a code: admitted (the rule r10 states) |
| g4 | the code check reaches payments not from a receipt | a plain payment, part nsf and part reversed, coded: admitted |
| x2 | a pending payment gives its money back | P1's return (or S4's refusal) |

Also g5 (the receipt's lock dropped from the code check) passes the battery, as expected of one transaction; I did not run the races on it (RC would show it). Caught, as intended: a4, a7, a8, a13, r1, r2, r4, r5, r7, g1, g3, x1. Equivalent under -23: a1, a2 (the entry's filters), a5 (the bound), and a6 in the reader (not when the share function is read directly). r8 (the order of ties) is untested and trivial.

## The three questions put to me

1. **L7:** not acceptable; there is a rule (S3).
2. **Inserts:** `tally_app` cannot do it. Inserted `reversed` with R01 or `nsf`: 23514 (born pending); pending to `reversed`: 23001 (P5, executed). As owner, a payment born `reversed` (with a code or without) and no rows uses up its receipt, has share 0, is on no list, and its return is refused (P9, executed). That does not matter for r10's check, but it is a load that loses a receipt's money silently. A refusal at insert of a receipt's payment born `reversed` or `nsf`, for every role, costs one line (born voided is tested at O4 and must stay). Note, not a condition.
3. **A code without a time:** acceptable after the status move, not before it (S2). Between the move and a later code the old instant changes its answer; that residue is fine as a stated limit.

## N: notes

- **N1 (executed, P8).** The order check now reads a bounce's recorded time for every row on the receipt, so a history load of a 200 receipt (P1 bounced, recorded 04-10; P2 recorded 04-05) is refused if P1's bounce is loaded before P2. r9 admitted it. It is the same rule as for reversals, and loading in recorded order passes; say so in the loader's contract.
- **N2 (read).** Stale words: the header says reversed takes a code "only where the bank took all of it" (until S3, it does not); `suspense_misposted_share`'s comment and the guard's "only a payment reversed as posted to the wrong customer" omit the bounced case; the comment on `enforce_payment_suspense_pledge` lacks r10's refusal.
- **N3 (read).** The reader calls the plpgsql share once for every payment ever made from a receipt, returned or not. At about 565 payments it took 46 ms (executed), so it is linear, about 0.1 ms each. Testing the return first would keep it to the open ones.
- **N4 (read).** S4c should net the nsf rows and drop its list (above). RA to RC are worth adding to the races.
- **N5 (read).** `posted` payments are listed as due the moment a reversal is recorded, including between a bank take-back entered plain and its coded end. Stated; fine.

## Appendix: the SQL

P probes: battery-24-frozen-r10.sql lines 1 to 1313, then the block. F1 and F2 the same. The fix runs put `FIX` (below) after the battery's BEGIN.

### P1, P2, P2b, P2c, P4, P5, P6, P7
```sql
\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
RESET ROLE;
CREATE FUNCTION pg_temp.try(p_label text, p_sql text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RAISE NOTICE '%: admitted', p_label;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE '%: % %', p_label, SQLSTATE, left(SQLERRM,230); END $$;
CREATE FUNCTION pg_temp.st(p uuid, r uuid) RETURNS text LANGUAGE sql AS $$
 SELECT format('status %s code %s share %s held %s due(12-31) %s aged-listed %s', p.status, coalesce(p.return_code,'-'), public.suspense_misposted_share(p.id), pg_temp.held(r), pg_temp.due(p.id, DATE '2026-12-31'),
  EXISTS (SELECT 1 FROM public.suspense_receipts_aged_as_of(pg_temp.t1(), DATE '2026-12-31', clock_timestamp()) a WHERE a.receipt_id=r)) FROM public.payments p WHERE p.id=$1 $$;
GRANT EXECUTE ON FUNCTION pg_temp.try(text,text), pg_temp.st(uuid,uuid) TO tally_app; SET ROLE tally_app;
SELECT current_user;
\echo === P1 posting row written, reversed before the move to posted (tally_app)
SELECT pg_temp.rcpt(pg_temp.n('c1'), 100, DATE '2026-03-10');
SELECT pg_temp.fromr(pg_temp.n('51'), NULL, pg_temp.n('c1'), :c1, 100, false);
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id)
 VALUES (pg_temp.n('61'), pg_temp.t1(), :c1, DATE '2026-03-10','payment','x',-100,'payment',pg_temp.n('51'));
SELECT pg_temp.try('P1 reverse while pending', $q$SELECT pg_temp.rev(pg_temp.n('71'), pg_temp.n('51'), pg_temp.n('61'), 'adjustment', 100, DATE '2026-03-11')$q$);
SELECT pg_temp.st(pg_temp.n('51'), pg_temp.n('c1'));
SELECT pg_temp.try('P1 post', $q$UPDATE public.payments SET status='posted', status_cause_id=pg_temp.n('61') WHERE id=pg_temp.n('51')$q$);
SELECT pg_temp.try('P1 void', $q$UPDATE public.payments SET status='voided' WHERE id=pg_temp.n('51')$q$);
SELECT pg_temp.try('P1 reversed', $q$UPDATE public.payments SET status='reversed', reversed_at=now(), reversed_by=pg_temp.op(), reversed_reason='m', status_cause_id=pg_temp.n('71') WHERE id=pg_temp.n('51')$q$);
SELECT pg_temp.try('P1 return', $q$SELECT pg_temp.mret(NULL, pg_temp.n('c1'), pg_temp.n('51'), 100, DATE '2026-03-12')$q$);
SELECT pg_temp.try('P1 pay to C2', $q$SELECT pg_temp.fromr(pg_temp.n('52'), pg_temp.n('62'), pg_temp.n('c1'), '00000000-0000-4000-8000-0000000a24c2', 100)$q$);
\echo === P2 nsf row undone (redeposit), the bank takes it again entered as an adjustment, ended nsf naming the undone row, R01
SELECT pg_temp.rcpt(pg_temp.n('c2'), 100, DATE '2026-03-10');
SELECT pg_temp.fromr(pg_temp.n('53'), pg_temp.n('63'), pg_temp.n('c2'), :c1, 100);
SELECT pg_temp.rev(pg_temp.n('73'), pg_temp.n('53'), pg_temp.n('63'), 'nsf', 100, DATE '2026-03-11');
SELECT pg_temp.rev(pg_temp.n('74'), pg_temp.n('53'), pg_temp.n('73'), 'adjustment', -100, DATE '2026-03-12');
SELECT pg_temp.rev(pg_temp.n('75'), pg_temp.n('53'), pg_temp.n('63'), 'adjustment', 100, DATE '2026-03-13');
SELECT pg_temp.try('P2 nsf naming the undone row, R01', $q$UPDATE public.payments SET status='nsf', nsf_date=DATE '2026-03-13', return_code='R01', status_cause_id=pg_temp.n('73') WHERE id=pg_temp.n('53')$q$);
SELECT pg_temp.st(pg_temp.n('53'), pg_temp.n('c2'));
SELECT pg_temp.try('P2 return 100', $q$SELECT pg_temp.mret(NULL, pg_temp.n('c2'), pg_temp.n('53'), 100, DATE '2026-03-13')$q$);
SELECT pg_temp.st(pg_temp.n('53'), pg_temp.n('c2'));
SELECT pg_temp.try('P2 pay to C2', $q$SELECT pg_temp.fromr(pg_temp.n('54'), pg_temp.n('64'), pg_temp.n('c2'), '00000000-0000-4000-8000-0000000a24c2', 100, true, NULL, DATE '2026-03-14')$q$);
\echo === P2b same tree, ended reversed with R01
SELECT pg_temp.rcpt(pg_temp.n('c3'), 100, DATE '2026-03-10');
SELECT pg_temp.fromr(pg_temp.n('55'), pg_temp.n('65'), pg_temp.n('c3'), :c1, 100);
SELECT pg_temp.rev(pg_temp.n('76'), pg_temp.n('55'), pg_temp.n('65'), 'nsf', 100, DATE '2026-03-11');
SELECT pg_temp.rev(pg_temp.n('77'), pg_temp.n('55'), pg_temp.n('76'), 'adjustment', -100, DATE '2026-03-12');
SELECT pg_temp.rev(pg_temp.n('78'), pg_temp.n('55'), pg_temp.n('65'), 'adjustment', 100, DATE '2026-03-13');
SELECT pg_temp.try('P2b reversed R01', $q$UPDATE public.payments SET status='reversed', reversed_at=now(), reversed_by=pg_temp.op(), reversed_reason='b', return_code='R01', status_cause_id=pg_temp.n('78') WHERE id=pg_temp.n('55')$q$);
SELECT pg_temp.st(pg_temp.n('55'), pg_temp.n('c3'));
\echo === P2c 40 nsf undone, then 60 misposted + 40 adjustment under the undo; various
SELECT pg_temp.rcpt(pg_temp.n('c4'), 100, DATE '2026-03-10');
SELECT pg_temp.fromr(pg_temp.n('56'), pg_temp.n('66'), pg_temp.n('c4'), :c1, 100);
SELECT pg_temp.rev(pg_temp.n('79'), pg_temp.n('56'), pg_temp.n('66'), 'nsf', 40, DATE '2026-03-11');
SELECT pg_temp.rev(pg_temp.n('7a'), pg_temp.n('56'), pg_temp.n('79'), 'nsf', -40, DATE '2026-03-12');
SELECT pg_temp.rev(pg_temp.n('7b'), pg_temp.n('56'), pg_temp.n('66'), 'adjustment', 60, DATE '2026-03-13');
SELECT pg_temp.rev(pg_temp.n('7c'), pg_temp.n('56'), pg_temp.n('66'), 'adjustment', 40, DATE '2026-03-13');
SELECT pg_temp.try('P2c reversed R01: 60 misposted is lost (L7 shape with nsf rows in the tree)', $q$UPDATE public.payments SET status='reversed', reversed_at=now(), reversed_by=pg_temp.op(), reversed_reason='b', return_code='R01', status_cause_id=pg_temp.n('7c') WHERE id=pg_temp.n('56')$q$);
SELECT pg_temp.st(pg_temp.n('56'), pg_temp.n('c4'));
\echo === P4 L7
SELECT pg_temp.rcpt(pg_temp.n('c5'), 100, DATE '2026-03-10');
SELECT pg_temp.fromr(pg_temp.n('57'), pg_temp.n('67'), pg_temp.n('c5'), :c1, 100);
SELECT pg_temp.rev(pg_temp.n('7d'), pg_temp.n('57'), pg_temp.n('67'), 'adjustment', 60, DATE '2026-03-11');
SELECT pg_temp.rev(pg_temp.n('7e'), pg_temp.n('57'), pg_temp.n('67'), 'adjustment', 40, DATE '2026-03-12');
SELECT pg_temp.try('P4 before the end', $q$SELECT 1$q$); SELECT pg_temp.st(pg_temp.n('57'), pg_temp.n('c5'));
SELECT pg_temp.try('P4 reversed R01', $q$UPDATE public.payments SET status='reversed', reversed_at=now(), reversed_by=pg_temp.op(), reversed_reason='b', return_code='R01', status_cause_id=pg_temp.n('7e') WHERE id=pg_temp.n('57')$q$);
SELECT pg_temp.st(pg_temp.n('57'), pg_temp.n('c5'));
SELECT pg_temp.try('P4 return 60', $q$SELECT pg_temp.mret(NULL, pg_temp.n('c5'), pg_temp.n('57'), 60, DATE '2026-03-12')$q$);
SELECT pg_temp.try('P4 pay 60 to C2', $q$SELECT pg_temp.fromr(pg_temp.n('58'), pg_temp.n('68'), pg_temp.n('c5'), '00000000-0000-4000-8000-0000000a24c2', 60)$q$);
\echo === P4b L7, the code written a day later on a payment already ended and LISTED
\echo === P5 inserts as tally_app
SELECT pg_temp.rcpt(pg_temp.n('c6'), 100, DATE '2026-03-10');
SELECT pg_temp.try('P5 app inserts reversed', $q$INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, effective_date, effective_date_method, amount, payment_method, channel, source_system, check_number, suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by, status, return_code)
 SELECT pg_temp.n('59'), pg_temp.t1(), 'PX', '00000000-0000-4000-8000-0000000a24c1', DATE '2026-03-10', DATE '2026-03-10','lockbox_receipt',100,'check',channel,source_system,check_number,id,'x',pg_temp.op(),'reversed','R01' FROM public.suspense_receipts WHERE id=pg_temp.n('c6')$q$);
SELECT pg_temp.try('P5 app inserts nsf', $q$INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, effective_date, effective_date_method, amount, payment_method, channel, source_system, check_number, suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by, status)
 SELECT pg_temp.n('59'), pg_temp.t1(), 'PX', '00000000-0000-4000-8000-0000000a24c1', DATE '2026-03-10', DATE '2026-03-10','lockbox_receipt',100,'check',channel,source_system,check_number,id,'x',pg_temp.op(),'nsf' FROM public.suspense_receipts WHERE id=pg_temp.n('c6')$q$);
SELECT pg_temp.try('P5 app updates pending to reversed R01', $q$SELECT pg_temp.fromr(pg_temp.n('5a'), NULL, pg_temp.n('c6'), '00000000-0000-4000-8000-0000000a24c1', 100, false); UPDATE public.payments SET status='reversed', return_code='R01' WHERE id=pg_temp.n('5a')$q$);
\echo === P6 the mixed end written in one CTE as app; multi-row update
SELECT pg_temp.rcpt(pg_temp.n('c7'), 100, DATE '2026-03-10');
SELECT pg_temp.fromr(pg_temp.n('5b'), pg_temp.n('6b'), pg_temp.n('c7'), :c1, 100);
SELECT pg_temp.rev(pg_temp.n('80'), pg_temp.n('5b'), pg_temp.n('6b'), 'adjustment', 60, DATE '2026-03-11');
SELECT pg_temp.try('P6 nsf rows and nsf end with return in one statement', $q$WITH x AS (INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id) VALUES (pg_temp.n('81'), pg_temp.t1(), '00000000-0000-4000-8000-0000000a24c1', DATE '2026-03-12','nsf','b',40,'payment',pg_temp.n('5b'),pg_temp.n('6b')) RETURNING id), u AS (UPDATE public.payments SET status='nsf', nsf_date=DATE '2026-03-12', status_cause_id=(SELECT id FROM x) WHERE id=pg_temp.n('5b') RETURNING id)
 INSERT INTO public.suspense_receipt_dispositions (tenant_id, suspense_receipt_id, kind, amount, disposed_on, reason, recorded_by, returned_payment_id) SELECT pg_temp.t1(), pg_temp.n('c7'), 'misposting_returned', -60, DATE '2026-03-12','m', pg_temp.op(), id FROM u$q$);
SELECT pg_temp.st(pg_temp.n('5b'), pg_temp.n('c7'));
\echo === P7 redeposit after nsf end refused; further takeback
SELECT pg_temp.try('P7 redeposit after nsf end', $q$SELECT pg_temp.rev(NULL, pg_temp.n('11'), pg_temp.n('41'), 'adjustment', -40, DATE '2026-03-13')$q$);
SELECT pg_temp.try('P7 takeback under nsf', $q$SELECT pg_temp.rev(NULL, pg_temp.n('11'), pg_temp.n('21'), 'adjustment', 1, DATE '2026-03-13')$q$);
ROLLBACK;
```

### P3, P8, P9
```sql
\set ON_ERROR_ROLLBACK on
\set ON_ERROR_STOP 0
RESET ROLE;
\echo === P3 reversal recorded 04-04, status+code R01 recorded together 04-10 (owner's history)
INSERT INTO public.suspense_receipts (id, tenant_id, receipt_number, amount, received_on, channel, source_system, check_number, recorded_by, created_at)
VALUES (pg_temp.n('d1'), pg_temp.t1(), 'R24-25d1', 100, DATE '2026-04-02', 'mail', 'internal', 'CHK-25d1', pg_temp.op(), '2026-04-02 12:00+00');
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, effective_date, effective_date_method, amount, payment_method, channel, source_system, check_number,
                             suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by, created_at)
VALUES (pg_temp.n('91'), pg_temp.t1(), 'P24-2591', :c1, DATE '2026-04-02', DATE '2026-04-02', 'lockbox_receipt', 100, 'check', 'mail', 'internal', 'CHK-25d1',
        pg_temp.n('d1'), 'identified', pg_temp.op(), '2026-04-03 12:00+00');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, created_at)
VALUES (pg_temp.n('92'), pg_temp.t1(), :c1, DATE '2026-04-02', 'payment', 'posted', -100, 'payment', pg_temp.n('91'), '2026-04-03 12:00+00');
UPDATE public.payments SET status = 'posted', status_cause_id = pg_temp.n('92'), status_recorded_at = '2026-04-03 12:00+00' WHERE id = pg_temp.n('91');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id, reversal_reason, created_at)
VALUES (pg_temp.n('93'), pg_temp.t1(), :c1, DATE '2026-04-03', 'adjustment', 'r', 100, 'payment', pg_temp.n('91'), pg_temp.n('92'), 'r', '2026-04-04 12:00+00');
SELECT 'before the move, read at 04-05: ' || pg_temp.due(pg_temp.n('91'), DATE '2026-04-30', '2026-04-05 12:00+00');
UPDATE public.payments SET status = 'reversed', reversed_at=now(), reversed_by=pg_temp.op(), reversed_reason='r', return_code='R01', status_cause_id = pg_temp.n('93'), status_recorded_at = '2026-04-10 12:00+00' WHERE id = pg_temp.n('91');
SELECT 'after the move, read at 04-05: ' || pg_temp.due(pg_temp.n('91'), DATE '2026-04-30', '2026-04-05 12:00+00'), 'held ' || (SELECT held FROM public.suspense_receipt_position_as_of(pg_temp.n('d1'), DATE '2026-04-30', '2026-04-05 12:00+00')), 'received ' || (SELECT received FROM public.payment_position_as_of(pg_temp.n('91'), DATE '2026-04-30', '2026-04-05 12:00+00'));
\echo === P8 a second payment recorded between, loaded after a bounce (r10 order check, nsf added)
INSERT INTO public.suspense_receipts (id, tenant_id, receipt_number, amount, received_on, channel, source_system, check_number, recorded_by, created_at)
VALUES (pg_temp.n('d2'), pg_temp.t1(), 'R24-25d2', 200, DATE '2026-04-02', 'mail', 'internal', 'CHK-25d2', pg_temp.op(), '2026-04-02 12:00+00');
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, effective_date, effective_date_method, amount, payment_method, channel, source_system, check_number,
                             suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by, created_at)
VALUES (pg_temp.n('94'), pg_temp.t1(), 'P24-2594', :c1, DATE '2026-04-02', DATE '2026-04-02', 'lockbox_receipt', 100, 'check', 'mail', 'internal', 'CHK-25d2',
        pg_temp.n('d2'), 'identified', pg_temp.op(), '2026-04-03 12:00+00');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, created_at)
VALUES (pg_temp.n('95'), pg_temp.t1(), :c1, DATE '2026-04-02', 'payment', 'posted', -100, 'payment', pg_temp.n('94'), '2026-04-03 12:00+00');
UPDATE public.payments SET status = 'posted', status_cause_id = pg_temp.n('95'), status_recorded_at = '2026-04-03 12:00+00' WHERE id = pg_temp.n('94');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id, created_at)
VALUES (pg_temp.n('96'), pg_temp.t1(), :c1, DATE '2026-04-03', 'nsf', 'b', 100, 'payment', pg_temp.n('94'), pg_temp.n('95'), '2026-04-04 12:00+00');
UPDATE public.payments SET status = 'nsf', nsf_date='2026-04-03', status_cause_id = pg_temp.n('96'), status_recorded_at = '2026-04-10 12:00+00' WHERE id = pg_temp.n('94');
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, effective_date, effective_date_method, amount, payment_method, channel, source_system, check_number,
                             suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by, created_at)
VALUES (pg_temp.n('97'), pg_temp.t1(), 'P24-2597', :c1, DATE '2026-04-02', DATE '2026-04-02', 'lockbox_receipt', 100, 'check', 'mail', 'internal', 'CHK-25d2',
        pg_temp.n('d2'), 'identified', pg_temp.op(), '2026-04-05 12:00+00');
\echo === P9 owner inserts already nsf / reversed with code
SELECT pg_temp.rcpt(pg_temp.n('d3'), 100, DATE '2026-03-10');
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, effective_date, effective_date_method, amount, payment_method, channel, source_system, check_number, suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by, status, return_code)
 SELECT pg_temp.n('98'), pg_temp.t1(), 'P24-2598', :c1, DATE '2026-03-10', DATE '2026-03-10','lockbox_receipt',100,'check',channel,source_system,check_number,id,'x',pg_temp.op(),'reversed','R01' FROM public.suspense_receipts WHERE id=pg_temp.n('d3');
SELECT 'owner-inserted reversed R01: held ' || pg_temp.held(pg_temp.n('d3')), pg_temp.due(pg_temp.n('98'), DATE '2026-12-31');
SELECT pg_temp.mret(NULL, pg_temp.n('d3'), pg_temp.n('98'), 100, DATE '2026-03-12');
\echo === P9b owner inserts pending, posting+reversals rows, then UPDATE pending->? ; insert row with status reversed AFTER ledger? (posting needs the payment)
SELECT pg_temp.rcpt(pg_temp.n('d4'), 100, DATE '2026-03-10');
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, effective_date, effective_date_method, amount, payment_method, channel, source_system, check_number, suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by, status)
 SELECT pg_temp.n('99'), pg_temp.t1(), 'P24-2599', :c1, DATE '2026-03-10', DATE '2026-03-10','lockbox_receipt',100,'check',channel,source_system,check_number,id,'x',pg_temp.op(),'reversed' FROM public.suspense_receipts WHERE id=pg_temp.n('d4');
SELECT 'owner-inserted reversed no code: held ' || pg_temp.held(pg_temp.n('d4')), pg_temp.due(pg_temp.n('99'), DATE '2026-12-31'), public.suspense_misposted_share(pg_temp.n('99'));
SELECT pg_temp.mret(NULL, pg_temp.n('d4'), pg_temp.n('99'), 100, DATE '2026-03-12');
ROLLBACK;
```

### F1
```sql
RESET ROLE;
CREATE TEMP TABLE fz(id uuid, r uuid, pd date); 
DO $$
DECLARE i int; j int; r uuid; p uuid; e uuid; par record; amt numeric; ok int:=0; bad int:=0; pd date; ended int:=0; ret int:=0; n record;
BEGIN
 PERFORM setseed(0.4242);
 FOR i IN 1..500 LOOP
  r:=gen_random_uuid(); p:=gen_random_uuid(); e:=gen_random_uuid(); pd := DATE '2026-03-10' + (random()*3)::int;
  INSERT INTO public.suspense_receipts (id, tenant_id, receipt_number, amount, received_on, channel, source_system, check_number, recorded_by)
   VALUES (r, pg_temp.t1(), 'FZ-'||i, 100, DATE '2026-03-10', 'lockbox','bank_lockbox','FZ'||i, pg_temp.op());
  INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, effective_date, effective_date_method, amount, payment_method, channel, source_system, check_number, suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by)
   VALUES (p, pg_temp.t1(), 'FZP-'||i, '00000000-0000-4000-8000-0000000a24c1', pd, DATE '2026-03-10','lockbox_receipt',100,'check','lockbox','bank_lockbox','FZ'||i, r,'x',pg_temp.op());
  INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id)
   VALUES (e, pg_temp.t1(), '00000000-0000-4000-8000-0000000a24c1', CASE WHEN random()<0.7 THEN pd ELSE DATE '2026-03-10' END,'payment','x',-100,'payment',p);
  UPDATE public.payments SET status='posted', status_cause_id=e WHERE id=p;
  INSERT INTO fz VALUES (p,r,pd);
  FOR j IN 1..(2+random()*10)::int LOOP
   SELECT l.* INTO par FROM public.account_ledger l WHERE l.reference_id=p AND l.reference_type='payment' ORDER BY (l.id=e)::int*random()*1.5 + random() DESC LIMIT 1;
   amt := (ARRAY[20,40,60,100])[1+floor(random()*4)::int];
   BEGIN
    PERFORM pg_temp.rev(NULL, p, par.id, CASE WHEN random()<0.35 THEN 'nsf' ELSE 'adjustment' END, CASE WHEN par.amount<0 THEN amt ELSE -amt END, par.transaction_date + (random()*2)::int);
    ok:=ok+1;
   EXCEPTION WHEN OTHERS THEN bad:=bad+1; END;
  END LOOP;
  -- end it where nothing is left
  IF public.ledger_entry_remaining(e)=0 THEN
   SELECT l.* INTO n FROM public.account_ledger l WHERE l.reverses_ledger_entry_id=e ORDER BY random() LIMIT 1;
   IF n.transaction_type='nsf' THEN UPDATE public.payments SET status='nsf', nsf_date='2026-03-20', status_cause_id=n.id WHERE id=p;
   ELSE UPDATE public.payments SET status='reversed', reversed_at=now(), reversed_by=pg_temp.op(), reversed_reason='m', status_cause_id=n.id WHERE id=p; END IF;
   ended:=ended+1;
   IF random()<0.6 AND public.suspense_misposted_share(p)>0 THEN
     INSERT INTO public.suspense_receipt_dispositions (tenant_id, suspense_receipt_id, kind, amount, disposed_on, reason, recorded_by, returned_payment_id) VALUES (pg_temp.t1(), r,'misposting_returned', -public.suspense_misposted_share(p), DATE '2026-04-20','m',pg_temp.op(),p); ret:=ret+1;
   END IF;
  END IF;
 END LOOP;
 RAISE NOTICE 'rows ok % refused % ended % returned %', ok,bad,ended,ret;
END $$;
CREATE TEMP TABLE sw AS SELECT f.id, f.r, f.pd, g.d::date d, h.held, l.received, coalesce(s.share,0) share, s.since,
  coalesce((SELECT sum(x.owed) FROM public.suspense_misposting_returns_due_as_of(pg_temp.t1(), g.d::date, clock_timestamp()) x WHERE false),0) z,
  -- bank: the net of every nsf row that takes money with its subtree (outermost)
  (WITH RECURSIVE a AS (SELECT l.id, l.amount FROM public.account_ledger e JOIN public.account_ledger l ON l.reverses_ledger_entry_id=e.id WHERE e.reference_id=f.id AND e.reverses_ledger_entry_id IS NULL AND l.transaction_date<=g.d
        UNION ALL SELECT l.id,l.amount FROM a JOIN public.account_ledger l ON l.reverses_ledger_entry_id=a.id WHERE l.transaction_date<=g.d) SELECT coalesce(sum(amount),0) FROM a) net_full
 FROM fz f CROSS JOIN generate_series(DATE '2026-03-10', DATE '2026-04-25','1 day') g(d)
 CROSS JOIN LATERAL (SELECT held FROM public.suspense_receipt_position_as_of(f.r,g.d::date,clock_timestamp())) h
 LEFT JOIN LATERAL (SELECT received FROM public.payment_position_as_of(f.id,g.d::date,clock_timestamp())) l ON true
 LEFT JOIN LATERAL public.suspense_misposted_share_as_of(f.id,g.d::date,clock_timestamp()) s ON true;
CREATE TEMP TABLE due AS SELECT g.d::date d, x.* FROM generate_series(DATE '2026-03-10', DATE '2026-04-25','1 day') g(d) CROSS JOIN LATERAL public.suspense_misposting_returns_due_as_of(pg_temp.t1(), g.d::date, clock_timestamp()) x WHERE x.payment_id IN (SELECT id FROM fz);
\echo --- over: held+received+due > 100
SELECT count(*), count(distinct s.id) FROM sw s LEFT JOIN due u ON u.payment_id=s.id AND u.d=s.d WHERE s.held+coalesce(s.received,0)+coalesce(u.owed,0) > 100;
SELECT s.d, s.pd, s.held, s.received, s.share, u.owed, s.net_full, s.id FROM sw s LEFT JOIN due u ON u.payment_id=s.id AND u.d=s.d WHERE s.held+coalesce(s.received,0)+coalesce(u.owed,0) > 100 ORDER BY s.id,s.d LIMIT 8;
\echo --- since wrong: since <> brute force (first day of the unbroken run of share>0)
SELECT count(*) FROM sw s WHERE share>0 AND since <> (SELECT min(y.d) FROM sw y WHERE y.id=s.id AND y.d<=s.d AND NOT EXISTS (SELECT 1 FROM sw z WHERE z.id=s.id AND z.d BETWEEN y.d AND s.d AND z.share=0));
\echo --- short, by whether share < net_full (an nsf takes) 
SELECT (s.net_full - s.share) = (100-(s.held+coalesce(s.received,0)+coalesce(u.owed,0))) AS equals_bank, count(*) FROM sw s LEFT JOIN due u ON u.payment_id=s.id AND u.d=s.d WHERE s.held+coalesce(s.received,0)+coalesce(u.owed,0) < 100 GROUP BY 1;
SELECT s.d, s.pd, s.held, s.received, s.share, u.owed, s.net_full, s.id FROM sw s LEFT JOIN due u ON u.payment_id=s.id AND u.d=s.d WHERE s.held+coalesce(s.received,0)+coalesce(u.owed,0) < 100 AND (s.net_full - s.share) <> (100-(s.held+coalesce(s.received,0)+coalesce(u.owed,0))) ORDER BY s.id,s.d LIMIT 8;
\echo --- final share vs as-of at the end
SELECT count(*) FROM fz f WHERE public.suspense_misposted_share(f.id) <> (SELECT share FROM public.suspense_misposted_share_as_of(f.id, DATE '2026-12-31', clock_timestamp()));
\echo --- nsf-ended with share = 100; reversed with share 0; ended, share differs from gross plain reversals
SELECT p.status, public.suspense_misposted_share(p.id) share, count(*) FROM fz f JOIN public.payments p ON p.id=f.id GROUP BY 1,2 ORDER BY 1,2;
\timing on
SELECT count(*) FROM public.suspense_misposting_returns_due_as_of(pg_temp.t1(), DATE '2026-12-31', clock_timestamp());
\timing off
ROLLBACK;
```

### F2
```sql
RESET ROLE;
CREATE TEMP TABLE fz(id uuid, r uuid, n int);
DO $$
DECLARE i int; j int; r uuid; p uuid; e uuid; par record; amt numeric; t timestamptz; v_id uuid; n record; ended int:=0; ret int:=0; ok int:=0;
BEGIN
 PERFORM setseed(0.77);
 FOR i IN 1..150 LOOP
  r:=gen_random_uuid(); p:=gen_random_uuid(); e:=gen_random_uuid(); t:='2026-04-01 00:00+00';
  INSERT INTO public.suspense_receipts (id, tenant_id, receipt_number, amount, received_on, channel, source_system, check_number, recorded_by, created_at)
   VALUES (r, pg_temp.t1(), 'FZ-'||i, 100, DATE '2026-03-10', 'lockbox','bank_lockbox','FZ'||i, pg_temp.op(), t);
  INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, effective_date, effective_date_method, amount, payment_method, channel, source_system, check_number, suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by, created_at)
   VALUES (p, pg_temp.t1(), 'FZP-'||i, '00000000-0000-4000-8000-0000000a24c1', DATE '2026-03-10', DATE '2026-03-10','lockbox_receipt',100,'check','lockbox','bank_lockbox','FZ'||i, r,'x',pg_temp.op(), t);
  INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, created_at)
   VALUES (e, pg_temp.t1(), '00000000-0000-4000-8000-0000000a24c1', DATE '2026-03-10','payment','x',-100,'payment',p,t);
  UPDATE public.payments SET status='posted', status_cause_id=e, status_recorded_at=t WHERE id=p;
  INSERT INTO fz VALUES (p,r,i);
  FOR j IN 1..9 LOOP
   t := t + interval '1 hour';
   SELECT l.* INTO par FROM public.account_ledger l WHERE l.reference_id=p AND l.reference_type='payment' ORDER BY (l.id=e)::int*random()*1.5 + random() DESC LIMIT 1;
   amt := (ARRAY[20,40,60,100])[1+floor(random()*4)::int];
   BEGIN
    INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id, reversal_reason, created_at)
    VALUES (pg_temp.t1(), '00000000-0000-4000-8000-0000000a24c1', par.transaction_date + (random()*2)::int, CASE WHEN random()<0.35 THEN 'nsf' ELSE 'adjustment' END, 'f', CASE WHEN par.amount<0 THEN amt ELSE -amt END, 'payment', p, par.id, 'f', t);
    ok:=ok+1;
   EXCEPTION WHEN OTHERS THEN NULL; END;
  END LOOP;
  t := t + interval '1 hour';
  IF public.ledger_entry_remaining(e)=0 THEN
   SELECT l.* INTO n FROM public.account_ledger l WHERE l.reverses_ledger_entry_id=e ORDER BY random() LIMIT 1;
   IF n.transaction_type='nsf' THEN UPDATE public.payments SET status='nsf', nsf_date='2026-03-20', status_cause_id=n.id, status_recorded_at=t WHERE id=p;
   ELSE UPDATE public.payments SET status='reversed', reversed_at=now(), reversed_by=pg_temp.op(), reversed_reason='m', status_cause_id=n.id, status_recorded_at=t WHERE id=p; END IF;
   ended:=ended+1;
   IF public.suspense_misposted_share(p)>0 THEN
     INSERT INTO public.suspense_receipt_dispositions (tenant_id, suspense_receipt_id, kind, amount, disposed_on, reason, recorded_by, returned_payment_id, created_at) VALUES (pg_temp.t1(), r,'misposting_returned', -public.suspense_misposted_share(p), DATE '2026-04-01','m',pg_temp.op(),p, t+interval '1 hour'); ret:=ret+1;
   END IF;
  END IF;
 END LOOP;
 RAISE NOTICE 'rows ok % ended % returned %', ok,ended,ret;
END $$;
CREATE TEMP TABLE at AS SELECT TIMESTAMPTZ '2026-04-01 00:30+00' + k*interval '1 hour' a FROM generate_series(0,12) k;
CREATE TEMP TABLE due AS SELECT g.d::date d, at.a, x.payment_id, x.owed, x.due_since FROM at, generate_series(DATE '2026-03-10', DATE '2026-04-02','1 day') g(d) CROSS JOIN LATERAL public.suspense_misposting_returns_due_as_of(pg_temp.t1(), g.d::date, at.a) x WHERE x.payment_id IN (SELECT id FROM fz);
CREATE TEMP TABLE sw AS SELECT f.id, g.d::date d, at.a, h.held, l.received, coalesce(u.owed,0) owed, u.due_since,
 (WITH RECURSIVE t AS (SELECT l.id, l.amount, (l.transaction_type='nsf' AND l.amount>0) k FROM public.account_ledger e JOIN public.account_ledger l ON l.reverses_ledger_entry_id=e.id WHERE e.reference_id=f.id AND e.reverses_ledger_entry_id IS NULL AND l.transaction_date<=g.d AND l.created_at<=at.a
        UNION ALL SELECT l.id,l.amount, t.k OR (l.transaction_type='nsf' AND l.amount>0) FROM t JOIN public.account_ledger l ON l.reverses_ledger_entry_id=t.id WHERE l.transaction_date<=g.d AND l.created_at<=at.a) SELECT coalesce(sum(amount) FILTER (WHERE k),0) FROM t) bank
 FROM fz f CROSS JOIN at CROSS JOIN generate_series(DATE '2026-03-10', DATE '2026-04-02','1 day') g(d)
 CROSS JOIN LATERAL (SELECT held FROM public.suspense_receipt_position_as_of(f.r,g.d::date,at.a)) h
 LEFT JOIN LATERAL (SELECT received FROM public.payment_position_as_of(f.id,g.d::date,at.a)) l ON true
 LEFT JOIN due u ON u.payment_id=f.id AND u.d=g.d::date AND u.a=at.a;
\echo --- fuzz2
SELECT count(*), count(*) FILTER (WHERE held+received+owed>100) AS n_over, count(*) FILTER (WHERE held+received+owed+bank<>100) AS n_unequal FROM sw;
SELECT count(*) FROM sw s WHERE owed>0 AND due_since <> (SELECT min(y.d) FROM sw y WHERE y.id=s.id AND y.a=s.a AND y.d<=s.d AND NOT EXISTS (SELECT 1 FROM sw z WHERE z.id=s.id AND z.a=s.a AND z.d BETWEEN y.d AND s.d AND z.owed=0));
SELECT * FROM sw WHERE held+received+owed+bank<>100 ORDER BY id,a,d LIMIT 6;
ROLLBACK;
```

### S4c over every receipt, the nsf rows net
```sql
RESET ROLE;
\echo --- s4c all
SELECT r.receipt_number, min(g.d)::date, max(g.d)::date, min(t.total), max(t.total), r.amount FROM public.suspense_receipts r
      CROSS JOIN generate_series(DATE '2026-03-01', DATE '2026-04-30', '1 day') g(d)
      CROSS JOIN LATERAL (SELECT coalesce((SELECT x.held FROM public.suspense_receipt_position_as_of(r.id, g.d::date, clock_timestamp()) x), 0)
             + coalesce((SELECT sum(y.received) FROM public.payments p CROSS JOIN LATERAL public.payment_position_as_of(p.id, g.d::date, clock_timestamp()) y WHERE p.suspense_receipt_id = r.id), 0)
             + coalesce((SELECT sum(x.amount) FROM public.suspense_receipt_dispositions x WHERE x.suspense_receipt_id = r.id AND x.kind <> 'misposting_returned' AND x.disposed_on <= g.d), 0)
             + coalesce((SELECT sum(z.owed) FROM public.suspense_misposting_returns_due_as_of(pg_temp.t1(), g.d::date, clock_timestamp()) z WHERE z.receipt_id = r.id), 0)
             + coalesce((WITH RECURSIVE t AS (SELECT l.id, l.amount, (l.transaction_type='nsf' AND l.amount>0) k FROM public.payments p JOIN public.account_ledger e ON e.reference_type='payment' AND e.reference_id=p.id AND e.reverses_ledger_entry_id IS NULL JOIN public.account_ledger l ON l.reverses_ledger_entry_id=e.id WHERE p.suspense_receipt_id=r.id AND l.transaction_date<=g.d
        UNION ALL SELECT l.id,l.amount, t.k OR (l.transaction_type='nsf' AND l.amount>0) FROM t JOIN public.account_ledger l ON l.reverses_ledger_entry_id=t.id WHERE l.transaction_date<=g.d) SELECT sum(amount) FILTER (WHERE k) FROM t),0) AS total) t
     WHERE r.tenant_id=pg_temp.t1() AND r.received_on <= g.d AND t.total <> r.amount GROUP BY 1,6 ORDER BY 1;
SELECT count(*) FROM public.suspense_receipts WHERE tenant_id=pg_temp.t1();
ROLLBACK;
```

### The mutants (function, text replaced, replacement)
```python
M=[
('a1 entry not date-filtered',A,"           AND l.transaction_date <= p_on AND l.created_at <= p_recorded_at\n    ), down","           AND l.created_at <= p_recorded_at\n    ), down"),
('a2 entry not instant-filtered',A,"           AND l.transaction_date <= p_on AND l.created_at <= p_recorded_at\n    ), down","           AND l.transaction_date <= p_on\n    ), down"),
('a3 deeper rows not instant-filtered',A,w+"    ), days"," WHERE l.transaction_date <= p_on\n    ), days"),
('a4 first rows not date-filtered',A,w+"        UNION"," WHERE l.created_at <= p_recorded_at\n        UNION"),
('a5 least(payment) dropped',A,"least(p.amount, greatest(0, coalesce((SELECT sum(d.amount) FROM down d), 0)))","greatest(0, coalesce((SELECT sum(d.amount) FROM down d), 0))"),
('a6 greatest(0) dropped',A,"least(p.amount, greatest(0, coalesce((SELECT sum(d.amount) FROM down d), 0)))","least(p.amount, coalesce((SELECT sum(d.amount) FROM down d), 0))"),
('a7 since: net < 0',A,"z.net <= 0","z.net < 0"),
('a8 since: >= restart',A,"y.dated > coalesce","y.dated >= coalesce"),
('a9 since not floored at payment_date',A,"greatest(p.payment_date,","greatest(DATE '-infinity',"),
('a10 since: max',A,"SELECT min(y.dated)","SELECT max(y.dated)"),
('a11 deposits out',A,"l.transaction_type IN ('payment', 'deposit')","l.transaction_type = 'payment'"),
('a12 deep nsf counted',A,"l.reverses_ledger_entry_id = d.id AND NOT (l.transaction_type = 'nsf' AND l.amount > 0)","l.reverses_ledger_entry_id = d.id"),
('a13 deep nsf giving back left out',A,"l.reverses_ledger_entry_id = d.id AND NOT (l.transaction_type = 'nsf' AND l.amount > 0)","l.reverses_ledger_entry_id = d.id AND l.transaction_type <> 'nsf'"),
('a14 since net by row order not date',A,"sum(sum(d.amount)) OVER (ORDER BY d.dated)","sum(sum(d.amount)) OVER (ORDER BY d.dated DESC)"),
('a15 payment date <',A,"x.payment_date <= p_on","x.payment_date < p_on"),
('a16 created_at <',A,"x.created_at <= p_recorded_at","x.created_at < p_recorded_at"),
('r1 return date <',R,"d.disposed_on <= p_on","d.disposed_on < p_on"),
('r2 return instant <',R,"d.created_at <= p_recorded_at","d.created_at < p_recorded_at"),
('r3 any return of the receipt hides',R,"d.returned_payment_id = p.id AND d.disposed_on","d.suspense_receipt_id = p.suspense_receipt_id AND d.kind = 'misposting_returned' AND d.disposed_on"),
('r4 coded nsf hidden',R,"NOT (p.status = 'reversed' AND p.return_code IS NOT NULL)","p.return_code IS NULL"),
('r5 posted hidden',R,"NOT (p.status = 'reversed' AND p.return_code IS NOT NULL)","NOT (p.status = 'reversed' AND p.return_code IS NOT NULL) AND p.status <> 'posted'"),
('r6 customer wrong',R,"p.customer_id, s.share","NULL::uuid, s.share"),
('r7 pending listed only',R,"NOT (p.status = 'reversed' AND p.return_code IS NOT NULL)","NOT (p.status = 'reversed' AND p.return_code IS NOT NULL) AND p.status <> 'nsf'"),
('r8 tie order',R,"ORDER BY s.since, p.id","ORDER BY s.since, p.id DESC"),
('g1 share <=',G,"v_share < NEW.amount","v_share <= NEW.amount"),
('g2 share >=0',G,"v_share > 0 AND","v_share >= 0 AND"),
('g3 code check all statuses',G,"NEW.status = 'reversed' AND NEW.return_code IS NOT NULL","NEW.return_code IS NOT NULL"),
('g4 code check on no-receipt pay off/any',G,"IF NEW.suspense_receipt_id IS NOT NULL AND NEW.status = 'reversed'","IF NEW.status = 'reversed'"),
('g5 lock dropped',G,"PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('suspense_receipt', NEW.suspense_receipt_id));\n                IF NEW.status","IF NEW.status"),
('x1 coded reversed returns when part',X,"(v_pay.status = 'reversed' AND v_pay.return_code IS NULL)","(v_pay.status = 'reversed')"),
('x2 pending returns',X,"v_pay.status = 'nsf' OR","v_pay.status IN ('nsf','pending') OR"),
]
```

### FIX (built from the frozen bodies by these replacements)
```python
g=fn('enforce_payment_suspense_pledge')
a="IF v_share > 0 AND v_share < NEW.amount THEN"
assert a in g
g=g.replace(a,"IF v_share > 0 AND (v_share < NEW.amount OR public.ledger_entry_remaining(NEW.status_cause_id) < NEW.amount) THEN")
h="        -- r10 (Opus r9 S2): reversed with a bank's return code says"
assert h in g
g=g.replace(h,"""        IF NEW.suspense_receipt_id IS NOT NULL AND NEW.status = 'nsf' AND OLD.status <> 'nsf'
           AND public.suspense_misposted_share(NEW.id) = NEW.amount THEN
            RAISE EXCEPTION USING MESSAGE = format('payment %s: no nsf row under its posting entry stands, so it did not bounce', NEW.payment_number), ERRCODE = 'check_violation';
        END IF;
"""+h)
r=fn('suspense_misposting_returns_due_as_of')
b="NOT (p.status = 'reversed' AND p.return_code IS NOT NULL)"
assert b in r
r=r.replace(b,"NOT (p.status = 'reversed' AND p.return_code IS NOT NULL AND p.status_recorded_at <= p_recorded_at)")
t="""CREATE FUNCTION public.enforce_ledger_suspense_posted() RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
 IF EXISTS (SELECT 1 FROM public.account_ledger l JOIN public.payments p ON p.id = l.reference_id
     WHERE l.id = NEW.reverses_ledger_entry_id AND l.reference_type = 'payment' AND l.transaction_type IN ('payment','deposit') AND l.reverses_ledger_entry_id IS NULL
       AND p.suspense_receipt_id IS NOT NULL AND p.status = 'pending') THEN
  RAISE EXCEPTION USING MESSAGE = 'a receipt''s payment is moved to posted before its posting entry is undone', ERRCODE = 'check_violation';
 END IF; RETURN NULL; END $$;
CREATE TRIGGER enforce_ledger_suspense_posted AFTER INSERT ON public.account_ledger FOR EACH ROW WHEN (NEW.reverses_ledger_entry_id IS NOT NULL) EXECUTE FUNCTION public.enforce_ledger_suspense_posted();
"""
```

### RA, RB, RC (two sessions; the fixtures committed on the clone after battery lines 1 to 184)
```sql
SELECT pg_temp.rcpt(pg_temp.n('e1'), 100, DATE '2026-03-10'); SELECT pg_temp.fromr(pg_temp.n('a1'), pg_temp.n('b1'), pg_temp.n('e1'), :c1, 100);
SELECT pg_temp.rev(pg_temp.n('41'), pg_temp.n('a1'), pg_temp.n('b1'), 'nsf', 40, DATE '2026-03-11');
SELECT pg_temp.rcpt(pg_temp.n('e2'), 100, DATE '2026-03-10'); SELECT pg_temp.fromr(pg_temp.n('a2'), pg_temp.n('b2'), pg_temp.n('e2'), :c1, 100);
SELECT pg_temp.rev(pg_temp.n('51'), pg_temp.n('a2'), pg_temp.n('b2'), 'adjustment', 60, DATE '2026-03-11');
SELECT pg_temp.rev(pg_temp.n('52'), pg_temp.n('a2'), pg_temp.n('b2'), 'nsf', 40, DATE '2026-03-11');
COMMIT;
-- pg_temp.n(x) below stands for the literal uuid 00000000-0000-4000-8000-0000000c25<x>; t1, c1, op as in the battery
-- RA session A
BEGIN; INSERT INTO account_ledger (id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reference_type,reference_id,reverses_ledger_entry_id,reversal_reason)
 VALUES (n('61'),t1,c1,'2026-03-12','adjustment','m',60,'payment',n('a1'),n('b1'),'m'); SELECT pg_sleep(4); COMMIT;
-- RA session B, 1.5 s later
UPDATE payments SET status='reversed', reversed_at=now(), reversed_by=op, reversed_reason='m', return_code='R01', status_cause_id=n('61') WHERE id=n('a1');
-- RB session A
BEGIN; UPDATE payments SET status='nsf', nsf_date='2026-03-11', status_cause_id=n('52') WHERE id=n('a2'); SELECT pg_sleep(3); COMMIT;
-- RB session B, 1 s later (and RC session A, in BEGIN .. pg_sleep(3) .. COMMIT)
INSERT INTO suspense_receipt_dispositions (tenant_id,suspense_receipt_id,kind,amount,disposed_on,reason,recorded_by,returned_payment_id) VALUES (t1,n('e2'),'misposting_returned',-60,'2026-03-12','m',op,n('a2'));
-- RC session B, 1 s later
UPDATE payments SET return_code='R01' WHERE id=n('a2');
```
