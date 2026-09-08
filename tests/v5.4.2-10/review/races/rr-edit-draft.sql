SET app.user_id = '00000000-0000-4000-8000-00000000fb01';
SET ROLE tally_app;
BEGIN ISOLATION LEVEL REPEATABLE READ;
UPDATE public.invoices SET period_end = '2026-04-02', due_date = '2026-04-23' WHERE id = '00000000-0000-4000-8000-00000000f106';
SELECT 'RR: never-snapshotted draft edited under REPEATABLE READ: ' || count(*) FROM public.invoices WHERE id='00000000-0000-4000-8000-00000000f106' AND period_end='2026-04-02';
ROLLBACK;
