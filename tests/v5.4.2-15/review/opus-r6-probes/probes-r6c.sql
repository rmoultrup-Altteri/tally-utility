SELECT pg_temp.mk('M4');
SELECT pg_temp.multi('M4', $v$('refunded'::text, 87.50::numeric, DATE '2026-02-01'), ('instalment_received', 87.50, DATE '2026-02-14')$v$,
  'MS4 one statement: refunded 1 Feb (87.50), then the 14 Feb instalment');
SELECT pg_temp.show('M4');
SELECT pg_temp.mk('M5');
SELECT pg_temp.multi('M5', $v$('refund_initiated'::text, 87.50::numeric, DATE '2026-02-01'), ('principal_returned', 50, DATE '2026-02-01')$v$,
  'MS5 one statement: refund notice for 87.50, then a partial return of 50 the same day');
SELECT pg_temp.show('M5');
SELECT pg_temp.mk('M6');
SELECT pg_temp.multi('M6', $v$('instalment_received'::text, 87.50::numeric, DATE '2026-02-14'), ('refund_initiated', 175, DATE '2026-02-01')$v$,
  'MS6 one statement, other order: instalment 14 Feb then refund notice 1 Feb (the guard sees the earlier row)');
SELECT pg_temp.mk('M7');
SELECT pg_temp.multi('M7', $v$('refunded'::text, 87.50::numeric, DATE '2026-02-01'), ('refunded', 87.50, DATE '2026-02-02')$v$,
  'MS7 one statement: two refunds of 87.50');
SELECT pg_temp.show('M7');
