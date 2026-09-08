INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at) VALUES
  ('00000000-0000-4000-8000-0000000fa641', '00000000-0000-4000-8000-0000000fa001', 'FA-RUN-DL', '2026-03', '2026-03-01', '2026-03-31', 'regular', 'in_progress', now());
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa541', 'FA-DL-1', '00000000-0000-4000-8000-0000000fa641', 'regular', NULL, '2026-03-01', '2026-03-31');
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa542', 'FA-DL-2', '00000000-0000-4000-8000-0000000fa641', 'regular', NULL, '2026-03-01', '2026-03-31');
