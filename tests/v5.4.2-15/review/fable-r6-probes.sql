-- Fable r6 probes, spliced in before I16 (deposit D: posted 87.50 on 15 Jan, return 87.50 on 1 Feb, instalment 87.50 on 14 Feb).
CREATE FUNCTION pg_temp.fd() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT id FROM public.deposits WHERE customer_id = '00000000-0000-4000-8000-0000000015c1' AND received_at_posting = 87.50 LIMIT 1 $$;
CREATE FUNCTION pg_temp.held_min(p uuid) RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT min(public.deposit_principal_in_force(p, e.effective_on)) FROM public.deposit_events e WHERE e.deposit_id = p $$;

-- F1 ties on one day: a receipt and debits on the same day; the day's net must stay >= 0
SAVEPOINT f1;
SELECT pg_temp.does_as('F1a: a return of 0.01 on 14 Feb, the day the second instalment arrives, is funded by it (same day counts)', :'t1',
  pg_temp.ev_sql(pg_temp.fd(), 'principal_returned', 0.01, DATE '2026-02-14'));
SELECT pg_temp.does_as('F1b: an application of 87.49 on 14 Feb takes the rest of that day''s money', :'t1',
  pg_temp.ev_sql(pg_temp.fd(), 'applied_to_balance', 87.49, DATE '2026-02-14'));
SELECT pg_temp.ok('F1c: held on 14 Feb is now exactly 0', public.deposit_principal_in_force(pg_temp.fd(), DATE '2026-02-14') = 0);
SELECT pg_temp.ok('F1d: status projected partial_applied? (remainder 0 -> applied)', (SELECT status FROM public.deposits WHERE id = pg_temp.fd()) = 'applied');
SELECT pg_temp.refuses('F1e: one more cent on 14 Feb is refused by the per-type remainder check (remainder 0)',
  pg_temp.ev_sql(pg_temp.fd(), 'applied_to_balance', 0.01, DATE '2026-02-14'), '23514', 'applied_to_balance must be', 'tally_app', :'u1');
SELECT pg_temp.refuses('F1f: a backdated application of 0.01 on 10 Feb is refused by the per-type check first (remainder 0; the guard sits last by design)',
  pg_temp.ev_sql(pg_temp.fd(), 'applied_to_balance', 0.01, DATE '2026-02-10'), '23514', 'applied_to_balance must be', 'tally_app', :'u1');
SELECT pg_temp.does_as('F1g: the zero refund notice on 14 Feb closes a fully applied deposit', :'t1',
  pg_temp.ev_sql(pg_temp.fd(), 'refund_initiated', 0, DATE '2026-02-14'));
SELECT pg_temp.ok('F1h: never negative on any recorded day', pg_temp.held_min(pg_temp.fd()) >= 0);
ROLLBACK TO SAVEPOINT f1;

-- F2 debit dated before posting
SELECT pg_temp.refuses('F2: an application dated 14 Jan, before posting, is refused before the guard runs',
  pg_temp.ev_sql(pg_temp.fd(), 'applied_to_balance', 1, DATE '2026-01-14'), '23514', 'precedes posted_on', 'tally_app', :'u1');
SELECT pg_temp.refuses('F2b: a release dated 14 Jan likewise',
  pg_temp.ev_sql(pg_temp.fd(), 'refunded', 87.50, DATE '2026-01-14'), '23514', 'precedes posted_on', 'tally_app', :'u1');

-- F3 refund-type events against a later debit (not just a later receipt), and a refund notice dated after its refund
SAVEPOINT f3;
SELECT pg_temp.refuses('F3a: a refund of the remainder dated 20 Jan precedes the 1 Feb return and the 14 Feb receipt',
  pg_temp.ev_sql(pg_temp.fd(), 'refunded', 87.50, DATE '2026-01-20'), '23514', 'precedes a receipt', 'tally_app', :'u1');
SELECT pg_temp.refuses('F3b: … dated 1 Feb (the return''s own day) it still precedes the 14 Feb receipt',
  pg_temp.ev_sql(pg_temp.fd(), 'refunded', 87.50, DATE '2026-02-01'), '23514', 'precedes a receipt', 'tally_app', :'u1');
SELECT pg_temp.does_as('F3c: the refund notice on 1 Mar', :'t1', pg_temp.ev_sql(pg_temp.fd(), 'refund_initiated', 87.50, DATE '2026-03-01'));
SELECT pg_temp.refuses('F3d: once pending, a backdated instalment is refused (status), not by the guard',
  pg_temp.ev_sql(pg_temp.fd(), 'instalment_received', 1, DATE '2026-02-20'), '23514', 'refund is pending', 'tally_app', :'u1');
SELECT pg_temp.does_as('F3e: OBSERVATION — the refund itself may be dated 20 Feb, before its own notice of 1 Mar (not the new guard''s scope)', :'t1',
  pg_temp.ev_sql(pg_temp.fd(), 'refunded', 87.50, DATE '2026-02-20'));
ROLLBACK TO SAVEPOINT f3;

-- F4 several receipts: a three-instalment deposit for c1 (20% at posting, 40% + 40%); late receipt and the status projection
SAVEPOINT f4;
SELECT pg_temp.run(pg_temp.cat_sql(:'t1', 'inst3', 'residential'), 'tally_app', :'u1');
SELECT pg_temp.run(pg_temp.tar_sql(:'t1', 'inst3', pg_temp.tdoc('{"amount": {"strategy": "fixed", "version": 1, "amount": 175},
   "instalments": [{"id": "i1", "fraction": 0.2, "days_after": 0}, {"id": "i2", "fraction": 0.4, "days_after": 30}, {"id": "i3", "fraction": 0.4, "days_after": 60}]}')), 'tally_app', :'u1');
SELECT pg_temp.does_as('F4a: a second deposit for the customer, 35 at posting, 70 due 14 Feb, 70 due 16 Mar', :'t1',
  pg_temp.dw_sql(jsonb_build_object('tenant', :'t1', 'customer', :'c1', 'rule', pg_temp.law('residential', 'credit_evaluation', 'municipal'), 'category', 'inst3',
     'tariff', pg_temp.tar(:'t1', 'inst3'), 'principal', '175.00', 'cap', '175.00', 'cap_source', 'tariff', 'cap_component', null, 'cap_basis', null, 'received', '35.00'),
     '{70.00,70.00}', '{2026-02-14,2026-03-16}'));
CREATE FUNCTION pg_temp.fe() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT id FROM public.deposits WHERE customer_id = '00000000-0000-4000-8000-0000000015c1' AND received_at_posting = 35.00 LIMIT 1 $$;
SELECT pg_temp.does_as('F4b: the 16 Mar instalment is recorded first (out of order)', :'t1', pg_temp.ev_sql(pg_temp.fe(), 'instalment_received', 70, DATE '2026-03-16'));
SELECT pg_temp.refuses('F4c: an application of 36 on 20 Jan: only 35 held that day (the 70 of 16 Mar does not reach back)',
  pg_temp.ev_sql(pg_temp.fe(), 'applied_to_balance', 36, DATE '2026-01-20'), '23514', 'negative principal', 'tally_app', :'u1');
SELECT pg_temp.does_as('F4d: an application of 35 on 20 Jan empties the day', :'t1', pg_temp.ev_sql(pg_temp.fe(), 'applied_to_balance', 35, DATE '2026-01-20'));
SELECT pg_temp.ok('F4e: status is partial_applied (remainder 70, undated), not applied', (SELECT status FROM public.deposits WHERE id = pg_temp.fe()) = 'partial_applied');
SELECT pg_temp.does_as('F4f: the 14 Feb instalment arrives late in the record', :'t1', pg_temp.ev_sql(pg_temp.fe(), 'instalment_received', 70, DATE '2026-02-14'));
SELECT pg_temp.refuses('F4g: a return of 71 on 1 Mar: 70 held (14 Feb money), 140 only from 16 Mar',
  pg_temp.ev_sql(pg_temp.fe(), 'principal_returned', 71, DATE '2026-03-01'), '23514', 'negative principal', 'tally_app', :'u1');
SELECT pg_temp.does_as('F4h: a return of 70 on 1 Mar', :'t1', pg_temp.ev_sql(pg_temp.fe(), 'principal_returned', 70, DATE '2026-03-01'));
SELECT pg_temp.refuses('F4i: a backdated application of 0.01 on 20 Feb would unfund the 1 Mar return',
  pg_temp.ev_sql(pg_temp.fe(), 'applied_to_balance', 0.01, DATE '2026-02-20'), '23514', 'negative principal', 'tally_app', :'u1');
SELECT pg_temp.refuses('F4j: a refund of the remainder 70 dated 1 Mar precedes the 16 Mar receipt already recorded',
  pg_temp.ev_sql(pg_temp.fe(), 'refund_initiated', 70, DATE '2026-03-01'), '23514', 'precedes a receipt', 'tally_app', :'u1');
SELECT pg_temp.does_as('F4k: dated 16 Mar it is accepted', :'t1', pg_temp.ev_sql(pg_temp.fe(), 'refund_initiated', 70, DATE '2026-03-16'));
SELECT pg_temp.ok('F4l: exhausted_on is NULL (applications and returns reached 105, below the principal)', (SELECT exhausted_on FROM public.deposit_balance(pg_temp.fe())) IS NULL);
SELECT pg_temp.ok('F4m: never negative on any recorded day', pg_temp.held_min(pg_temp.fe()) >= 0);
ROLLBACK TO SAVEPOINT f4;

-- F5 applied while instalments are still to come, then the late receipt flips the projection; then a zero refund closes it with instalments unpaid (OBSERVATION)
CREATE FUNCTION pg_temp.ff() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT id FROM public.deposits WHERE customer_id = '00000000-0000-4000-8000-0000000015c1' AND received_at_posting = 35.00 LIMIT 1 $$;
SAVEPOINT f5;
SELECT pg_temp.run(pg_temp.cat_sql(:'t1', 'inst3', 'residential'), 'tally_app', :'u1');
SELECT pg_temp.run(pg_temp.tar_sql(:'t1', 'inst3', pg_temp.tdoc('{"amount": {"strategy": "fixed", "version": 1, "amount": 175},
   "instalments": [{"id": "i1", "fraction": 0.2, "days_after": 0}, {"id": "i2", "fraction": 0.4, "days_after": 30}, {"id": "i3", "fraction": 0.4, "days_after": 60}]}')), 'tally_app', :'u1');
SELECT pg_temp.does_as('F5a: the same three-instalment deposit', :'t1',
  pg_temp.dw_sql(jsonb_build_object('tenant', :'t1', 'customer', :'c1', 'rule', pg_temp.law('residential', 'credit_evaluation', 'municipal'), 'category', 'inst3',
     'tariff', pg_temp.tar(:'t1', 'inst3'), 'principal', '175.00', 'cap', '175.00', 'cap_source', 'tariff', 'cap_component', null, 'cap_basis', null, 'received', '35.00'),
     '{70.00,70.00}', '{2026-02-14,2026-03-16}'));
SELECT pg_temp.does_as('F5b: apply the 35 on 20 Jan with 140 still to come', :'t1', pg_temp.ev_sql(pg_temp.ff(), 'applied_to_balance', 35, DATE '2026-01-20'));
SELECT pg_temp.ok('F5c: status applied (remainder 0 today)', (SELECT status FROM public.deposits WHERE id = pg_temp.ff()) = 'applied');
SELECT pg_temp.does_as('F5d: the 14 Feb instalment arrives', :'t1', pg_temp.ev_sql(pg_temp.ff(), 'instalment_received', 70, DATE '2026-02-14'));
SELECT pg_temp.ok('F5e: status back to partial_applied', (SELECT status FROM public.deposits WHERE id = pg_temp.ff()) = 'partial_applied');
SELECT pg_temp.refuses('F5f: a release/refund of 70 dated 1 Feb precedes the 14 Feb receipt',
  pg_temp.ev_sql(pg_temp.ff(), 'refunded', 70, DATE '2026-02-01'), '23514', 'precedes a receipt', 'tally_app', :'u1');
ROLLBACK TO SAVEPOINT f5;
SAVEPOINT f5b;
SELECT pg_temp.run(pg_temp.cat_sql(:'t1', 'inst3', 'residential'), 'tally_app', :'u1');
SELECT pg_temp.run(pg_temp.tar_sql(:'t1', 'inst3', pg_temp.tdoc('{"amount": {"strategy": "fixed", "version": 1, "amount": 175},
   "instalments": [{"id": "i1", "fraction": 0.2, "days_after": 0}, {"id": "i2", "fraction": 0.4, "days_after": 30}, {"id": "i3", "fraction": 0.4, "days_after": 60}]}')), 'tally_app', :'u1');
SELECT pg_temp.does_as('F5g: the same deposit again', :'t1',
  pg_temp.dw_sql(jsonb_build_object('tenant', :'t1', 'customer', :'c1', 'rule', pg_temp.law('residential', 'credit_evaluation', 'municipal'), 'category', 'inst3',
     'tariff', pg_temp.tar(:'t1', 'inst3'), 'principal', '175.00', 'cap', '175.00', 'cap_source', 'tariff', 'cap_component', null, 'cap_basis', null, 'received', '35.00'),
     '{70.00,70.00}', '{2026-02-14,2026-03-16}'));
SELECT pg_temp.does_as('F5h: apply the 35 on 20 Jan', :'t1', pg_temp.ev_sql(pg_temp.ff(), 'applied_to_balance', 35, DATE '2026-01-20'));
SELECT pg_temp.does_as('F5i: OBSERVATION — a zero refund on 20 Jan closes the deposit with two instalments (140) scheduled and unpaid', :'t1',
  pg_temp.ev_sql(pg_temp.ff(), 'refunded', 0, DATE '2026-01-20'));
SELECT pg_temp.ok('F5j: status refunded', (SELECT status FROM public.deposits WHERE id = pg_temp.ff()) = 'refunded');
ROLLBACK TO SAVEPOINT f5b;

-- F6 the record is append-only for tally_app: no re-dating an event to sidestep the guard
SELECT pg_temp.refuses('F6: tally_app cannot re-date a recorded event (no UPDATE grant at all)',
  format('UPDATE public.deposit_events SET effective_on = DATE ''2026-03-01'' WHERE deposit_id = %L AND event_type = ''principal_returned''', pg_temp.fd()), '42501', NULL, 'tally_app', :'u1');
SELECT pg_temp.refuses('F6b: … nor delete one (no DELETE grant)',
  format('DELETE FROM public.deposit_events WHERE deposit_id = %L AND event_type = ''principal_returned''', pg_temp.fd()), '42501', NULL, 'tally_app', :'u1');
-- F7 a refund dated after every receipt but before an application already recorded (the lead's widening of Codex's rule)
SAVEPOINT f7;
SELECT pg_temp.does_as('F7a: an application of 10 on 1 Mar (87.50 held from 14 Feb)', :'t1', pg_temp.ev_sql(pg_temp.fd(), 'applied_to_balance', 10, DATE '2026-03-01'));
SELECT pg_temp.refuses('F7b: a refund notice of the remainder 77.50 dated 20 Feb — after the last receipt, before the 1 Mar application — is refused',
  pg_temp.ev_sql(pg_temp.fd(), 'refund_initiated', 77.50, DATE '2026-02-20'), '23514', 'precedes a receipt', 'tally_app', :'u1');
SELECT pg_temp.does_as('F7c: dated 1 Mar it is accepted', :'t1', pg_temp.ev_sql(pg_temp.fd(), 'refund_initiated', 77.50, DATE '2026-03-01'));
ROLLBACK TO SAVEPOINT f7;
