# Opus review: v5.4.2-24 r9 (unmatched cash and agency pledges)

**Date:** 2026-11-22. **Reviewer:** Opus. **Brief:** `review-brief-24-r9.md`, md5 `a4f09bb6e7cad8e2c4817c8c3d06a6aa`, which matches its `.md5`. I read the r9 plan, the design, the r8-to-r9 diff and my own r8 review. I read no Fable or Codex file.

**Verdict: not yet.** Nothing is blocking. There are three should-fix items:
- **S1 (executed):** the new reader is wrong at past dates. It lists money as due back while the customer's ledger or the receipt still holds it, and misses money that is already in neither.
- **S2 (executed):** a receipt's payment that was partly reversed as misposted can end where the misposted part can never come back, and the reader never shows it. A partly reversed payment still posted is also missing from the reader.
- **S3 (executed, tests):** 12 of 12 wrong versions of the reader that I tried pass every behaviour check; only the body hash catches them. The conservation sweep leaves the reader out.

## Hashes and reproduction (executed)

- All six frozen md5s match the brief.
- Clone `rv24opus` from `TEMPLATE tally`, TEMP revoked from PUBLIC, `tally_app` and `tally_core`. Strict apply (`search_path=`, `check_function_bodies=on`): the first run is clean; the second says "already applied (suspense_receipts exists); nothing to do".
- Battery: 282 PASS, 0 FAIL, rc 0. Races (`suspense-24-frozen-r9.sh rv24opus`): 24 PASS, 0 FAIL, rc 0.
- Not run: `ci.sh` and `mutations-24.py` (not allowed), and -25, -26 and -30 beside -24. For those I rely on the author's 63/63 and 119/119.
- Probes run after the battery's lines down to S8e (inclusive), each in one transaction that is rolled back; Q1 to Q6 write as `tally_app`. Clone dropped, container files removed. The SQL is in the appendix.

## 1. Round 8's findings, and the earlier ones

| Finding | State | Evidence |
|---|---|---|
| r8 Opus S1: money awaiting a return on no reader | **closed only for one shape** | A payment reversed in full by one row, dated on or after the payment, is listed correctly from that row's date until its return (S8, Q4; executed). Other shapes: S1 and S2 below. |
| r8 Opus S2, Fable N1: the "at most" comment | **closed** | The table comment, the guard's inline comment and design section 10 (round 3's list) now say exactly the share. Read. (The inline comment above the walk still opens "r3: at most what was reversed as misposted", as history.) |
| r8 Fable S1: refusals prove the share | **closed** | Six guard strings match "reversed as misposted (N of its M"; all pass. Executed (battery). |
| The moved walk is the same rule | **yes** | The body is the same CTE, with the same three planner settings on the function. `search_path` is pinned; NULL only for an unknown payment, which the guard has already refused. Read (diff), and P13 to P14h4 pass. |
| r7 and earlier | **still closed** | r9 changes one guard statement (the call), comments, and adds two functions. The battery, S4b and the races pass. Executed. |

Other parts of the brief's question on the reader:
- **Another tenant:** 0 rows for `tally_app` (Q5, executed).
- **NULL or infinite coordinates, or a NULL tenant:** raise 22004 (executed).
- **A payment with a return code:** left out; a code written later takes it off. See N1.
- **A voided payment:** cannot have a reversed status. Read.
- **Reversed and returned the same day:** both reads are `<=`, so it is never listed. Read.
- **As of now, for a payment reversed in full and never partly taken back:** receipts plus returns due count each dollar once (sweep; executed).

**Design and rulings; paths (2); -23 and -27 (3); concurrency (4); invariant (5); limits (7).** r9 adds no table, lock, trigger or write path, so my r5 to r8 answers stand for those. S2's first case is a path that loses money, which my earlier rounds missed. The invariant carries both new functions (body, attributes; the share in `tally_app`'s EXECUTE list), and I1 fails when either body changes (executed, S3). None of L1 to L6 blocks.

## B: blocking

None.

## S: should fix

**S1 (executed). The reader reads today's final share from one row's date, so it is wrong on earlier dates, both ways.**

`suspense_misposting_returns_due_as_of` takes the whole share at current knowledge and lists it from the date of the single row the payment's status names. That row may be any non-nsf reversal of the posting entry: the first of several, or the last. The date of the payment itself isn't read at all. I ran battery S4b's sum with the amounts due added, over the battery's own fixtures (Q-A):

| Receipt | Date | Receipt holds | On the customer's ledger | Listed as due | Receipt's amount |
|---|---|---|---|---|---|
| R20 (…15): payment dated 03-15, reversed 03-11 | 03-11 to 03-14 | 100 | 0 | **100** | 100 |
| R23 (…18): reversal 03-11, undone 03-12, again 03-13; status names the first | 03-12 | 0 | 100 | **100** | 100 |
| R24 (…7a): the same shape, returned 03-13 | 03-12 | 0 | 100 | **100** | 100 |

That is 200 counted against a receipt of 100 on six receipt-dates. The other way: R16 (…10: reversal 03-11, undone 03-12, again 03-13; status names the last) has 100 in none of them on 03-11. R22 (…17) and R21 (…16) are also short on the dates between their reversals and the row the status names.

The brief says a reconciliation adds the two figures, and the comment says "the money is then on no customer's account and not yet on the receipt". On these dates neither holds. A month-end read back later, which is what a date coordinate is for, would be overstated or understated. Adding the due amount to S4b unchanged fails on the frozen patch at all instants (executed).

**Fix, executed on the clone:** read the share as of the coordinates. Make the walk keep only rows with `transaction_date <= p_on AND created_at <= p_recorded_at`, and list a payment only when `payment_date <= p_on AND created_at <= p_recorded_at`. With that (appendix, FIX), the sweep shows 0 rows counted twice, S4b with the due amount passes at every date and recorded instant, and the rows still short are exactly what the bank took (R4, R9, R11's 40, R17, R18, R19 on 03-11 only, R21's 50, R22's 40). The guard can call the same function at its own date, or keep the un-dated one. `reversed_on` should be the date of the latest counted row, or the first date the amount was continuously due; say which. The comment's last sentence ("read at current knowledge") then goes.

**S2 (executed). A partly misposted payment can end where its misposted part is lost for good, and it is on no list.**

The patch models a payment partly taken back by the bank and partly reversed as misposted (P13, P14e, P14f). P13 works only because the clerk ends it `reversed` with no code. Two other ordinary endings, both as `tally_app`:
- **Q1.** Receipt 100, paid to C1. 60 is reversed as misposted on 03-11; the bank takes the other 40 on 03-12 (an nsf row). The clerk moves the payment to `nsf`, naming the nsf row: -23 admits it, since nothing is left. `suspense_misposted_share` says 60. The return is refused ("is nsf"), `nsf` to `reversed` is refused (terminal), and paying 60 to the right customer is refused (160 against 100). Read on 10-31: held 0, on the ledger 0, due none, aged 0.
- **Q2.** The same, ended `reversed` with the bank's code R01 for the 40. The return is refused ("with return code R01"). The same 60 is lost. The code is write-once.

So 60 of real cash is on no account, no receipt and no list, with no row that can bring it back. That is CI-053's "never dropped", and the same class of loss as r7's short return. A partial bank take-back is rare, but the rules were built for it.

- **Q3, recoverable but unseen.** One check for two customers is posted to C1, and 60 is reversed; the payment stays `posted` with 40. Held 0, received 40, due none, on 10-31 (234 days). Reversing the other 40 and starting again recovers it, but nothing tells anyone to. This is the likeliest case of the three.

**Fix (rule: CI-053, CI-056):** (a) the reader lists by the share, not the status (S1's fix already does this; keep returned ones out, as now); (b) the return is admitted for a payment wholly undone, `nsf` or `reversed`, whose share is above 0; a return code bars it only when the tree holds no nsf row that takes money, because then the code describes the whole reversal. The alternative is to refuse the move to `nsf`, and the code, on a receipt's payment with a share above 0 whose tree has an nsf row; that forces P13's ending. Option (b) leaves the operator able to record what happened, so I recommend it. Either needs a check for each of Q1 to Q3. If (b), the order check's status list (`voided`, `reversed`) should gain `nsf`. The fixed reader and (b) must agree on the code rule. (S1's fix is executed; (b) is predicted.)

**S3 (executed, tests). The reader's behaviour is barely tested.** I put each wrong reader into the battery ahead of its checks. All 12 pass S8 to S8e and everything up to I1 (262 PASS), where only the body hash catches them: no `return_code IS NULL`; no `status_recorded_at <=`; no `created_at <=` on the return; no `disposed_on <=`; no tenant; no `status = 'reversed'`; `>=` for `>` in past_service_level; age always 0; the level read now instead of at the instant; raising while the level is unset; coordinates not required; the order reversed. M117 removes the whole "not returned" test, so it does not show that either date on it matters. The hash proves the body is unchanged, not that it is right, and S1 is a body that was pinned wrong. **Fix:** add the amount due to S4b's sum (that alone fails on S1 and covers the dates and instants); then add checks for a code (P12's P19 not listed), the tenant, the level's boundary (day 10 no, day 11 yes), NULL while unset, a NULL coordinate, and a read before the return's date and instant, with mutations for each.

## N: notes

- **N1 (executed, Q4).** A return code written later removes a payment from the list at earlier recorded instants too (1 row at t0 before the code, 0 at the same t0 after it). `return_code` has no recorded time of its own. A superuser or auditor re-reading an old instant gets a different answer. Say so in the comment.
- **N2 (read).** A bounced check entered as a plain reversal has no way off the list: the code must be `R` and two digits (a NACHA code), the status is terminal, and the only other exit is the return, which would put money on the receipt the bank has taken back. Lockbox checks are the typical receipt. The comment should say the list includes these and that a bank's take-back is recorded as nsf.
- **N3 (read).** The age runs from the reversal, while the receipt's clock runs from `received_on` (design 2.4). Money 200 days old and reversed yesterday reads as 1 day, not past; the day it is returned it reads as past on the aged list. I suggested the reversal date in r8; consider adding `received_on` as a column so the core can choose.
- **N4 (read).** Money due back does not put its receipt's candidates on the aged list, so `aged_suspense` protects no one while it waits. `receipt_id` lets the core join the candidates; worth a line in the comment or L1.
- **N5 (read).** My r8 N1 to N3 stand (M116 is wider than its label; default the new payment's date to the return's; the design's narrative stops at round 4).

## Appendix: the SQL

Each runs after battery-24-frozen-r9.sql lines 1 to 1171 (through S8e).

### Q-A (S1: the sweep)
```sql
RESET ROLE;
-- every T1 receipt, date, instant: held + on ledger + left + due vs the receipt
CREATE TEMP VIEW sweep AS
    WITH ds AS (
      SELECT received_on AS d FROM public.suspense_receipts WHERE tenant_id = pg_temp.t1()
      UNION SELECT payment_date FROM public.payments WHERE tenant_id = pg_temp.t1()
      UNION SELECT disposed_on FROM public.suspense_receipt_dispositions WHERE tenant_id = pg_temp.t1()
      UNION SELECT transaction_date FROM public.account_ledger WHERE tenant_id = pg_temp.t1()
    ), ats AS (SELECT clock_timestamp() AS at)
    SELECT r.id, r.receipt_number, r.amount, ds.d, h.held, l.on_ledger, o.left_it, u.due
      FROM public.suspense_receipts r CROSS JOIN ds CROSS JOIN ats
      CROSS JOIN LATERAL (SELECT coalesce((SELECT x.held FROM public.suspense_receipt_position_as_of(r.id, ds.d, ats.at) x), 0) AS held) h
      CROSS JOIN LATERAL (SELECT coalesce(sum(y.received), 0) AS on_ledger
                            FROM public.payments p CROSS JOIN LATERAL public.payment_position_as_of(p.id, ds.d, ats.at) y
                           WHERE p.suspense_receipt_id = r.id) l
      CROSS JOIN LATERAL (SELECT coalesce(sum(x.amount), 0) AS left_it
                            FROM public.suspense_receipt_dispositions x
                           WHERE x.suspense_receipt_id = r.id AND x.kind <> 'misposting_returned'
                             AND x.disposed_on <= ds.d AND x.created_at <= ats.at) o
      CROSS JOIN LATERAL (SELECT coalesce(sum(x.owed), 0) AS due
                            FROM public.suspense_misposting_returns_due_as_of(pg_temp.t1(), ds.d, ats.at) x WHERE x.receipt_id = r.id) u
     WHERE r.tenant_id = pg_temp.t1() AND r.received_on <= ds.d;
\echo '--- A: counted twice (held + ledger + left + due > receipt)'
SELECT receipt_number, d, amount, held, on_ledger, left_it, due FROM sweep WHERE held+on_ledger+left_it+due > amount ORDER BY 1,2;
\echo '--- B: in none of them, though the bank took nothing (R23, R20, R16, R24, R4...): list short rows, with due=0'
SELECT receipt_number, min(d), max(d), count(*), min(held+on_ledger+left_it+due), amount FROM sweep WHERE held+on_ledger+left_it+due < amount GROUP BY 1, amount ORDER BY 1;
ROLLBACK;
```
### S4b with the due amount (S1, S3)
```sql
SELECT pg_temp.ok('S4b conservation: no receipt''s money counts twice at any date and recorded instant (Fable r6 S1)',
  NOT EXISTS (
    WITH ds AS (
      SELECT received_on AS d FROM public.suspense_receipts WHERE tenant_id = pg_temp.t1()
      UNION SELECT payment_date FROM public.payments WHERE tenant_id = pg_temp.t1()
      UNION SELECT disposed_on FROM public.suspense_receipt_dispositions WHERE tenant_id = pg_temp.t1()
      UNION SELECT transaction_date FROM public.account_ledger WHERE tenant_id = pg_temp.t1()
    ), ats AS (
      SELECT created_at AS at FROM public.suspense_receipts WHERE tenant_id = pg_temp.t1()
      UNION SELECT created_at FROM public.payments WHERE tenant_id = pg_temp.t1()
      UNION SELECT status_recorded_at FROM public.payments WHERE tenant_id = pg_temp.t1() AND status_recorded_at IS NOT NULL
      UNION SELECT created_at FROM public.suspense_receipt_dispositions WHERE tenant_id = pg_temp.t1()
      UNION SELECT created_at FROM public.account_ledger WHERE tenant_id = pg_temp.t1()
      UNION SELECT clock_timestamp()
    )
    SELECT 1
      FROM public.suspense_receipts r CROSS JOIN ds CROSS JOIN ats
      CROSS JOIN LATERAL (SELECT coalesce((SELECT x.held FROM public.suspense_receipt_position_as_of(r.id, ds.d, ats.at) x), 0) AS held) h
      CROSS JOIN LATERAL (SELECT coalesce(sum(y.received), 0) AS on_ledger
                            FROM public.payments p CROSS JOIN LATERAL public.payment_position_as_of(p.id, ds.d, ats.at) y
                           WHERE p.suspense_receipt_id = r.id) l
      CROSS JOIN LATERAL (SELECT coalesce(sum(x.amount), 0) AS left_it
                            FROM public.suspense_receipt_dispositions x
                           WHERE x.suspense_receipt_id = r.id AND x.kind <> 'misposting_returned'
                             AND x.disposed_on <= ds.d AND x.created_at <= ats.at) o
      CROSS JOIN LATERAL (SELECT coalesce(sum(x.owed), 0) AS due FROM public.suspense_misposting_returns_due_as_of(pg_temp.t1(), ds.d, ats.at) x WHERE x.receipt_id = r.id) u
     WHERE r.tenant_id = pg_temp.t1() AND r.received_on <= ds.d AND r.created_at <= ats.at
       AND h.held + l.on_ledger + o.left_it + u.due > r.amount));
ROLLBACK;
```
### FIX (run before Q-A and S4b; 0 rows counted twice, PASS)
```sql
RESET ROLE;
CREATE FUNCTION public.suspense_misposted_share_as_of(p_payment_id uuid, p_on date, p_recorded_at timestamptz) RETURNS numeric
 LANGUAGE sql STABLE SET search_path = public, pg_temp AS $$
 WITH RECURSIVE e AS (
   SELECT l.id FROM public.account_ledger l WHERE l.reference_type='payment' AND l.reference_id=p_payment_id AND l.reverses_ledger_entry_id IS NULL
      AND l.transaction_type IN ('payment','deposit') AND l.transaction_date <= p_on AND l.created_at <= p_recorded_at
 ), down(id, amount) AS (
   SELECT l.id,l.amount FROM e JOIN public.account_ledger l ON l.reverses_ledger_entry_id=e.id AND NOT (l.transaction_type='nsf' AND l.amount>0) AND l.transaction_date<=p_on AND l.created_at<=p_recorded_at
   UNION ALL
   SELECT l.id,l.amount FROM down d JOIN public.account_ledger l ON l.reverses_ledger_entry_id=d.id AND NOT (l.transaction_type='nsf' AND l.amount>0) AND l.transaction_date<=p_on AND l.created_at<=p_recorded_at
 ) SELECT least((SELECT amount FROM public.payments WHERE id=p_payment_id), greatest(0, coalesce(sum(amount),0))) FROM down $$;
CREATE OR REPLACE FUNCTION public.suspense_misposting_returns_due_as_of(p_tenant_id uuid, p_on date, p_recorded_at timestamp with time zone)
    RETURNS TABLE (payment_id uuid, receipt_id uuid, customer_id uuid, owed numeric, reversed_on date, age_days integer,
                   service_level_days integer, past_service_level boolean)
    LANGUAGE sql STABLE SET search_path = public, pg_temp AS $$
 SELECT p.id, p.suspense_receipt_id, p.customer_id, s.owed::numeric(12,2), NULL::date, NULL::int, NULL::int, NULL::boolean
  FROM public.payments p CROSS JOIN LATERAL (SELECT public.suspense_misposted_share_as_of(p.id,p_on,p_recorded_at) AS owed) s
 WHERE p.tenant_id=p_tenant_id AND p.suspense_receipt_id IS NOT NULL AND p.payment_date<=p_on AND p.created_at<=p_recorded_at
   AND (p.return_code IS NULL OR p.status='nsf') AND s.owed>0
   AND NOT EXISTS (SELECT 1 FROM public.suspense_receipt_dispositions d WHERE d.returned_payment_id=p.id AND d.disposed_on<=p_on AND d.created_at<=p_recorded_at) $$;
```
### Q1 to Q6 (S2, N1)
```sql
RESET ROLE;
CREATE FUNCTION pg_temp.lg(p_id uuid, p_pay uuid, p_rev uuid, p_type text, p_amt numeric, p_on date, p_c uuid) RETURNS void LANGUAGE sql AS $$
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id, reversal_reason)
VALUES (p_id, pg_temp.t1(), p_c, p_on, p_type, 'q2', p_amt, 'payment', p_pay, p_rev, CASE WHEN p_type='nsf' THEN NULL ELSE 'misposted' END) $$;
CREATE FUNCTION pg_temp.try(l text, q text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN EXECUTE q; RAISE NOTICE '%: admitted', l; EXCEPTION WHEN OTHERS THEN RAISE NOTICE '%: % %', l, SQLSTATE, SQLERRM; END $$;
CREATE FUNCTION pg_temp.st(l text, p_r uuid, p_pay uuid, p_on date) RETURNS void LANGUAGE plpgsql AS $$
BEGIN RAISE NOTICE '% on %: status %, held %, received %, share %, due rows %, aged %', l, p_on, (SELECT status||coalesce(' '||return_code,'') FROM public.payments WHERE id=p_pay),
 (SELECT held FROM public.suspense_receipt_position_as_of(p_r,p_on,clock_timestamp())), (SELECT received FROM public.payment_position_as_of(p_pay,p_on,clock_timestamp())),
 public.suspense_misposted_share(p_pay), (SELECT coalesce(string_agg(owed::text||' from '||reversed_on||' past '||past_service_level,','),'none') FROM public.suspense_misposting_returns_due_as_of(pg_temp.t1(),p_on,clock_timestamp()) WHERE payment_id=p_pay),
 (SELECT count(*) FROM public.suspense_receipts_aged_as_of(pg_temp.t1(),p_on,clock_timestamp()) WHERE receipt_id=p_r); END $$;
GRANT EXECUTE ON FUNCTION pg_temp.lg(uuid,uuid,uuid,text,numeric,date,uuid), pg_temp.try(text,text), pg_temp.st(text,uuid,uuid,date) TO tally_app;
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000a24b1', true) \g /dev/null
-- Q1: 60 reversed as misposted 03-11, bank takes 40 03-12 (nsf), the clerk ends it nsf
SELECT pg_temp.rcpt(('00000000-0000-4000-8000-0000000b09c0'::uuid),100,DATE '2026-03-10'), pg_temp.fromr(('00000000-0000-4000-8000-0000000b09c1'::uuid),('00000000-0000-4000-8000-0000000b09c2'::uuid),('00000000-0000-4000-8000-0000000b09c0'::uuid),:c1,100) \g /dev/null
SELECT pg_temp.lg(gen_random_uuid(),('00000000-0000-4000-8000-0000000b09c1'::uuid),('00000000-0000-4000-8000-0000000b09c2'::uuid),'adjustment',60,DATE '2026-03-11',:c1) \g /dev/null
SELECT pg_temp.st('Q1 partial, still posted',('00000000-0000-4000-8000-0000000b09c0'::uuid),('00000000-0000-4000-8000-0000000b09c1'::uuid),DATE '2026-03-11') \g /dev/null
SELECT pg_temp.try('Q1 return while posted', $q$SELECT pg_temp.mret(NULL,('00000000-0000-4000-8000-0000000b09c0'::uuid),('00000000-0000-4000-8000-0000000b09c1'::uuid),60,DATE '2026-03-11')$q$) \g /dev/null
SELECT pg_temp.lg(('00000000-0000-4000-8000-0000000b09c3'::uuid),('00000000-0000-4000-8000-0000000b09c1'::uuid),('00000000-0000-4000-8000-0000000b09c2'::uuid),'nsf',40,DATE '2026-03-12',:c1) \g /dev/null
SELECT pg_temp.try('Q1 move to nsf', $q$UPDATE public.payments SET status='nsf', nsf_date=DATE '2026-03-12', status_cause_id=('00000000-0000-4000-8000-0000000b09c3'::uuid) WHERE id=('00000000-0000-4000-8000-0000000b09c1'::uuid)$q$) \g /dev/null
SELECT pg_temp.st('Q1 nsf',('00000000-0000-4000-8000-0000000b09c0'::uuid),('00000000-0000-4000-8000-0000000b09c1'::uuid),DATE '2026-10-31') \g /dev/null
SELECT pg_temp.try('Q1 return after nsf', $q$SELECT pg_temp.mret(NULL,('00000000-0000-4000-8000-0000000b09c0'::uuid),('00000000-0000-4000-8000-0000000b09c1'::uuid),60,DATE '2026-03-12')$q$) \g /dev/null
SELECT pg_temp.try('Q1 nsf to reversed', $q$UPDATE public.payments SET status='reversed', status_cause_id=(SELECT id FROM public.account_ledger WHERE reverses_ledger_entry_id=('00000000-0000-4000-8000-0000000b09c2'::uuid) AND amount=60) WHERE id=('00000000-0000-4000-8000-0000000b09c1'::uuid)$q$) \g /dev/null
SELECT pg_temp.try('Q1 pay the right customer 60', $q$SELECT pg_temp.fromr(gen_random_uuid(),gen_random_uuid(),('00000000-0000-4000-8000-0000000b09c0'::uuid),'00000000-0000-4000-8000-0000000a24c2',60,true,NULL,DATE '2026-03-13')$q$) \g /dev/null
-- Q2: same, ended reversed, with the bank's return code for the 40
SELECT pg_temp.rcpt(('00000000-0000-4000-8000-0000000b09c4'::uuid),100,DATE '2026-03-10'), pg_temp.fromr(('00000000-0000-4000-8000-0000000b09c5'::uuid),('00000000-0000-4000-8000-0000000b09c6'::uuid),('00000000-0000-4000-8000-0000000b09c4'::uuid),:c1,100) \g /dev/null
SELECT pg_temp.lg(gen_random_uuid(),('00000000-0000-4000-8000-0000000b09c5'::uuid),('00000000-0000-4000-8000-0000000b09c6'::uuid),'nsf',40,DATE '2026-03-11',:c1), pg_temp.lg(('00000000-0000-4000-8000-0000000b09c7'::uuid),('00000000-0000-4000-8000-0000000b09c5'::uuid),('00000000-0000-4000-8000-0000000b09c6'::uuid),'adjustment',60,DATE '2026-03-12',:c1) \g /dev/null
SELECT pg_temp.try('Q2 reversed with R01', $q$UPDATE public.payments SET status='reversed', reversed_at=now(), reversed_by=pg_temp.op(), reversed_reason='m', return_code='R01', status_cause_id=('00000000-0000-4000-8000-0000000b09c7'::uuid) WHERE id=('00000000-0000-4000-8000-0000000b09c5'::uuid)$q$) \g /dev/null
SELECT pg_temp.st('Q2',('00000000-0000-4000-8000-0000000b09c4'::uuid),('00000000-0000-4000-8000-0000000b09c5'::uuid),DATE '2026-10-31') \g /dev/null
SELECT pg_temp.try('Q2 return', $q$SELECT pg_temp.mret(NULL,('00000000-0000-4000-8000-0000000b09c4'::uuid),('00000000-0000-4000-8000-0000000b09c5'::uuid),60,DATE '2026-03-12')$q$) \g /dev/null
-- Q3: a partial misposting, posted, never ended
SELECT pg_temp.rcpt(('00000000-0000-4000-8000-0000000b09c8'::uuid),100,DATE '2026-03-10'), pg_temp.fromr(('00000000-0000-4000-8000-0000000b09e1'::uuid),('00000000-0000-4000-8000-0000000b09e2'::uuid),('00000000-0000-4000-8000-0000000b09c8'::uuid),:c1,100) \g /dev/null
SELECT pg_temp.lg(gen_random_uuid(),('00000000-0000-4000-8000-0000000b09e1'::uuid),('00000000-0000-4000-8000-0000000b09e2'::uuid),'adjustment',60,DATE '2026-03-11',:c1) \g /dev/null
SELECT pg_temp.st('Q3',('00000000-0000-4000-8000-0000000b09c8'::uuid),('00000000-0000-4000-8000-0000000b09e1'::uuid),DATE '2026-10-31') \g /dev/null
-- Q4: an ordinary full return reversed as plain; a return code written later takes it off the list, also at earlier instants
SELECT pg_temp.rcpt(('00000000-0000-4000-8000-0000000b09e4'::uuid),100,DATE '2026-03-10'), pg_temp.fromr(('00000000-0000-4000-8000-0000000b09e5'::uuid),('00000000-0000-4000-8000-0000000b09e6'::uuid),('00000000-0000-4000-8000-0000000b09e4'::uuid),:c1,100) \g /dev/null
SELECT pg_temp.unpost(('00000000-0000-4000-8000-0000000b09e5'::uuid),('00000000-0000-4000-8000-0000000b09e6'::uuid),DATE '2026-03-11') \g /dev/null
SELECT clock_timestamp() AS t0 \gset
SELECT pg_temp.st('Q4 before code',('00000000-0000-4000-8000-0000000b09e4'::uuid),('00000000-0000-4000-8000-0000000b09e5'::uuid),DATE '2026-10-31') \g /dev/null
SELECT count(*) AS due_at_t0 FROM public.suspense_misposting_returns_due_as_of(pg_temp.t1(),DATE '2026-10-31',:'t0') WHERE payment_id=('00000000-0000-4000-8000-0000000b09e5'::uuid);
SELECT pg_temp.try('Q4 code later', $q$UPDATE public.payments SET return_code='R10' WHERE id=('00000000-0000-4000-8000-0000000b09e5'::uuid)$q$) \g /dev/null
SELECT count(*) AS due_at_t0_read_after_the_code FROM public.suspense_misposting_returns_due_as_of(pg_temp.t1(),DATE '2026-10-31',:'t0') WHERE payment_id=('00000000-0000-4000-8000-0000000b09e5'::uuid);
-- Q5: tenancy and null coordinates
SELECT count(*) AS t2_rows FROM public.suspense_misposting_returns_due_as_of(pg_temp.t2(),DATE '2026-10-31',clock_timestamp());
SELECT pg_temp.try('Q5 null tenant', $q$SELECT * FROM public.suspense_misposting_returns_due_as_of(NULL,DATE '2026-10-31',clock_timestamp())$q$) \g /dev/null
SELECT pg_temp.try('Q5 null date', $q$SELECT * FROM public.suspense_misposting_returns_due_as_of(pg_temp.t1(),NULL,clock_timestamp())$q$) \g /dev/null
SELECT pg_temp.try('Q5 inf', $q$SELECT * FROM public.suspense_misposting_returns_due_as_of(pg_temp.t1(),'infinity',clock_timestamp())$q$) \g /dev/null
-- Q6 level unset: before the setting
SELECT payment_id, owed, service_level_days, past_service_level FROM public.suspense_misposting_returns_due_as_of(pg_temp.t1(),DATE '2026-03-31',clock_timestamp()) LIMIT 5;
ROLLBACK;
```
Output:
```
 Q1 partial, still posted on 2026-03-11: status posted, held 0.00, received 40.00, share 60.00, due rows none, aged 0
 Q1 return while posted: 23514 payment P24-09c1 is posted: only a payment reversed as posted to the wrong customer gives its money back to the receipt; a bank's take-back keeps it spent (v5.4.2-24)
 Q1 move to nsf: admitted
 Q1 nsf on 2026-10-31: status nsf, held 0.00, received 0.00, share 60.00, due rows none, aged 0
 Q1 return after nsf: 23514 payment P24-09c1 is nsf: only a payment reversed as posted to the wrong customer gives its money back to the receipt; a bank's take-back keeps it spent (v5.4.2-24)
 Q1 nsf to reversed: 23001 payment P24-09c1 cannot move from nsf to reversed (CI-013; v5.4.2-23): pending moves to posted or voided, posted to nsf or reversed, and the rest are terminal — post a new payment (a refund is read from the position, not a status)
 Q1 pay the right customer 60: 23514 suspense receipt R24-09c0: on 2026-03-13 its payments and dispositions would come to 160.00, more than the 100.00 the receipt holds (CI-053, v5.4.2-24)
 Q2 reversed with R01: admitted
 Q2 on 2026-10-31: status reversed R01, held 0.00, received 0.00, share 60.00, due rows none, aged 0
 Q2 return: 23514 payment P24-09c5 is reversed with return code R01: only a payment reversed as posted to the wrong customer gives its money back to the receipt; a bank's take-back keeps it spent (v5.4.2-24)
 Q3 on 2026-10-31: status posted, held 0.00, received 40.00, share 60.00, due rows none, aged 0
 Q4 before code on 2026-10-31: status reversed, held 0.00, received 0.00, share 100.00, due rows 100.00 from 2026-03-11 past true, aged 0
 due_at_t0 
-----------
         1
(1 row)

 Q4 code later: admitted
 due_at_t0_read_after_the_code 
-------------------------------
                             0
(1 row)

 t2_rows 
---------
       0
(1 row)

 Q5 null tenant: 22004 suspense_service_level_days_as_of: tenant and a finite instant are both given; never default to now (v5.4.2-24)
 Q5 null date: 22004 suspense_misposting_returns_due_as_of: a position is read at a finite money date and recorded instant, both given (on , recorded 2026-11-22 22:10:05.28269+00) (v5.4.2-23)
 Q5 inf: 22004 suspense_misposting_returns_due_as_of: a position is read at a finite money date and recorded instant, both given (on infinity, recorded 2026-11-22 22:10:05.282899+00) (v5.4.2-23)
              payment_id              |  owed  | service_level_days | past_service_level 
--------------------------------------+--------+--------------------+--------------------
 00000000-0000-4000-8000-0000000a24b3 | 100.00 |                 10 | t
(1 row)

```
### S3: the mutants (each function body placed after the battery's BEGIN)
```python
import subprocess,re
P=open('/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-24/review/patch-24-frozen-r9.sql').read()
B='/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-24/review/battery-24-frozen-r9.sql'
i=P.index('CREATE OR REPLACE FUNCTION public.suspense_misposting_returns_due_as_of'); j=P.index('$$;',P.index('AS $$',i))+3
fn=P[i:j]
i2=P.index('CREATE OR REPLACE FUNCTION public.suspense_misposted_share'); j2=P.index('$$;',P.index('AS $$',i2))+3
sh=P[i2:j2]
M=[('return_code dropped',fn.replace(' AND p.return_code IS NULL','')),
('status_recorded_at dropped',fn.replace(' AND p.status_recorded_at <= p_recorded_at','')),
('d.created_at dropped',fn.replace(' AND d.created_at <= p_recorded_at','')),
('d.disposed_on dropped',fn.replace(' AND d.disposed_on <= p_on','')),
('tenant dropped',fn.replace('p.tenant_id = p_tenant_id AND ','')),
('> to >= in past_service_level',fn.replace('(p_on - l.transaction_date) > v_level','(p_on - l.transaction_date) >= v_level')),
('age wrong',fn.replace('(p_on - l.transaction_date)::integer','0')),
('level as of clock',fn.replace('suspense_service_level_days_as_of(p_tenant_id, p_recorded_at)','suspense_service_level_days_as_of(p_tenant_id, clock_timestamp())')),
('raises while unset',fn.replace('    RETURN QUERY',"    IF v_level IS NULL THEN RAISE EXCEPTION 'x'; END IF;\n    RETURN QUERY")),
('coordinates not required',re.sub(r"    PERFORM public.cash_coordinates_required\([^;]*;\n",'',fn)),
('reversed status dropped',fn.replace("p.status = 'reversed' AND ",'')),
('order reversed',fn.replace('ORDER BY l.transaction_date','ORDER BY l.transaction_date DESC')),
]
import sys
b=open(B).read()
for n,f in M:
    assert f!=fn,n
    k=b.index('SAVEPOINT') if False else None
    # run the battery with the mutated function created first (invariant pins removed from consideration: stop at the I section's hash check last)
    sql=b.replace('BEGIN;\n','BEGIN;\n'+f+'\n',1)
    r=subprocess.run(['docker','exec','-i','tally-pg','psql','-U','tally','-d','rv24opus','-v','ON_ERROR_STOP=1','-q'],input=sql,capture_output=True,text=True)
    e=[l for l in r.stderr.splitlines() if 'ERROR' in l]
    print(n,'| PASS',r.stderr.count('PASS'),'|',(e or ['none'])[0][:230])
```
