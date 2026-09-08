-- Runs on a PRE-patch clone (fable2). Seed violating rows as owner, then apply p09.
INSERT INTO public.tenants (id, name, slug) VALUES ('a0000000-0000-0000-0000-00000000000a','Fable Gas','fable-gas');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('a1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-00000000000a','Fable Admin','fa@example.com','tenant_admin');
INSERT INTO public.customers (id, tenant_id, customer_number) VALUES ('a2000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-00000000000a','CUST-001');
-- current ACTIVE assertion without evidence (the blocker)
INSERT INTO public.customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, status, verified_by, verified_at, effective_start, effective_end)
VALUES ('e0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000001','government','active','a1000000-0000-0000-0000-000000000001',now(),'2026-01-01','2027-01-01');
-- current EXPIRED assertion without evidence (NOTICE only)
INSERT INTO public.customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, status, verified_by, verified_at, effective_start, effective_end)
VALUES ('e0000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-000000000001','non_profit','expired','a1000000-0000-0000-0000-000000000001',now(),'2024-01-01','2025-01-01');
