-- A FAIL or false only_own_subject_visible proves core/app audit privileges or cross-tenant subject enforcement is broken.

\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF current_database() NOT LIKE 'codex%' THEN
  RAISE EXCEPTION 'Run only on an operator-created codex-prefixed clone of frozen r6';
 END IF;END $$;
SET LOCAL search_path = public, pg_temp;
SET LOCAL statement_timeout = '30s';
CREATE FUNCTION pg_temp.expect(label text, command text, state text, phrase text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE actual_state text; message text;
BEGIN
 BEGIN
  EXECUTE command;
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE, message = MESSAGE_TEXT;
 END;
 IF actual_state IS DISTINCT FROM state OR (state IS NOT NULL AND position(phrase in message)=0) THEN
  RAISE EXCEPTION 'FAIL %: expected % / %, got % / %',label,state,phrase,actual_state,message;
 END IF;
 RAISE NOTICE 'PASS % (state %, message %)',label,coalesce(actual_state,'success'),coalesce(message,'none');
END $$;
INSERT INTO public.tenants(id,name,slug) VALUES
 ('c0de0000-0000-4000-8000-000000000001','Codex A','codex-r6-a'),
 ('c0de0000-0000-4000-8000-000000000002','Codex B','codex-r6-b');
INSERT INTO public.users(id,tenant_id,display_name,email,role) VALUES
 ('c0de0000-0000-4000-8000-000000000011','c0de0000-0000-4000-8000-000000000001','Codex A','a@codex-r6.test','operator'),
 ('c0de0000-0000-4000-8000-000000000012','c0de0000-0000-4000-8000-000000000002','Codex B','b@codex-r6.test','operator');
CREATE TABLE public.codex_subject(id uuid PRIMARY KEY,tenant_id uuid NOT NULL REFERENCES public.tenants(id));
ALTER TABLE public.codex_subject ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.codex_subject FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON public.codex_subject USING(public.is_platform_admin() OR tenant_id=public.get_user_tenant_id());
GRANT SELECT ON public.codex_subject TO tally_app,tally_core;
INSERT INTO public.codex_subject VALUES
 ('c0de0000-0000-4000-8000-000000000021','c0de0000-0000-4000-8000-000000000001'),
 ('c0de0000-0000-4000-8000-000000000022','c0de0000-0000-4000-8000-000000000002');
SET LOCAL app.user_id='c0de0000-0000-4000-8000-000000000011';
SELECT pg_temp.expect('core own subject accepted', $q$
 SET LOCAL ROLE tally_core;
 INSERT INTO public.rule_audit_findings(tenant_id,finding_kind,subject_table,subject_id,core_release,coverage_from,coverage_to,detail)
 VALUES('c0de0000-0000-4000-8000-000000000001','record_disagrees_with_rule','public.codex_subject','c0de0000-0000-4000-8000-000000000021','codex r6','2020-01-01','2020-01-02','{}');
 RESET ROLE;
$q$,NULL,NULL);
SELECT pg_temp.expect('core cannot cite invisible subject', $q$
 SET LOCAL ROLE tally_core;
 INSERT INTO public.rule_audit_findings(tenant_id,finding_kind,subject_table,subject_id,core_release,coverage_from,coverage_to,detail)
 VALUES('c0de0000-0000-4000-8000-000000000001','record_disagrees_with_rule','public.codex_subject','c0de0000-0000-4000-8000-000000000022','codex r6','2020-01-01','2020-01-02','{}');
 RESET ROLE;
$q$,'23503','or it is not visible');
SELECT pg_temp.expect('app cannot write findings', $q$
 SET LOCAL ROLE tally_app;
 INSERT INTO public.rule_audit_findings(tenant_id,finding_kind,subject_table,subject_id,core_release,coverage_from,coverage_to,detail)
 VALUES('c0de0000-0000-4000-8000-000000000001','record_disagrees_with_rule','public.codex_subject','c0de0000-0000-4000-8000-000000000021','codex r6','2020-01-01','2020-01-02','{}');
 RESET ROLE;
$q$,'42501','permission denied');
SET LOCAL ROLE tally_core;
SELECT current_user, count(*)=1 AS only_own_subject_visible FROM public.codex_subject;
RESET ROLE;

ROLLBACK;
