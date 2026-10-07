-- ============================================================================
-- A COMMITTED fixture for isolation-17.sh and races/rule-close-17.sh: a small
-- ZZ law kind (zz_iso), a law table with a citing table, one tenant and one
-- investor-owned profile. Load once into a scratch clone of a -17 build.
-- ============================================================================
\set ON_ERROR_STOP 1
BEGIN;
INSERT INTO public.tenants (id, name, slug) VALUES ('00000000-0000-4000-8000-0000000017f1', 'Iso Gasco', 'iso17');
INSERT INTO public.users (id, tenant_id, display_name, email, role)
VALUES ('00000000-0000-4000-8000-0000000017f2', '00000000-0000-4000-8000-0000000017f1', 'Iso op', 'op@iso17.test', 'operator');
INSERT INTO public.places (kind_code, state_code, place_code, name, effective_from, source_note)
SELECT 'state', 'ZZ', 'ZZ', 'Zedland', DATE '1900-01-01', 'fixture' WHERE NOT EXISTS (SELECT 1 FROM public.places WHERE place_code = 'ZZ');
INSERT INTO public.rule_term_schemas (terms_kind, terms_version, rule_role, json_schema, introduced_on, description, source_note)
VALUES ('zz_iso', 1, 'law', '{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "oneOf": [
    {"type": "object", "additionalProperties": false, "required": ["governs", "citation", "cap"],
     "properties": {"governs": {"type": "string", "const": "law"}, "citation": {"type": "string", "pattern": "[A-Za-z0-9]"}, "cap": {"type": "number", "minimum": 0}}},
    {"type": "object", "additionalProperties": false, "required": ["governs", "citation"],
     "properties": {"governs": {"type": "string", "const": "delegated_to_utility"}, "citation": {"type": "string", "pattern": "[A-Za-z0-9]"}}}
  ]}', DATE '2026-10-07', 'isolation fixture', 'fixture');
INSERT INTO public.rule_term_schemas (terms_kind, terms_version, rule_role, json_schema, introduced_on, description, source_note)
SELECT 'zz_iso', 2, 'law', json_schema, DATE '2026-10-07', 'isolation fixture v2', 'fixture' FROM public.rule_term_schemas WHERE terms_kind = 'zz_iso';
INSERT INTO public.rule_term_schemas (terms_kind, terms_version, rule_role, json_schema, introduced_on, description, source_note)
SELECT 'zz_iso', 3, 'law', json_schema, DATE '2026-10-07', 'isolation fixture v3', 'fixture' FROM public.rule_term_schemas WHERE terms_kind = 'zz_iso' AND terms_version = 1;
CREATE TABLE public.zz_iso_rules (
  id uuid DEFAULT public.uuid_generate_v4() PRIMARY KEY,
  state_code text NOT NULL, service_type text NOT NULL,
  owner_types text[], system_kinds text[], commission_jurisdiction boolean,
  owner_span int4multirange NOT NULL DEFAULT '{[0,)}', system_span int4multirange NOT NULL DEFAULT '{[0,)}',
  jurisdiction_span int4range NOT NULL DEFAULT '[0,2)',
  customer_class text NOT NULL, effective_from date NOT NULL, effective_to date, source_note text NOT NULL,
  terms_kind text NOT NULL, terms_version integer NOT NULL, terms_source text NOT NULL, terms jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), recorded_txid bigint, closed_at timestamptz, closed_by text);
CREATE TABLE public.zz_iso_charges (
  id uuid DEFAULT public.uuid_generate_v4() PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES public.tenants(id),
  rule_id uuid NOT NULL REFERENCES public.zz_iso_rules(id), charged_on date NOT NULL);
ALTER TABLE public.zz_iso_charges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.zz_iso_charges FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON public.zz_iso_charges USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
CREATE FUNCTION public.zz_iso_cites() RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public.rule_row_cite('public.zz_iso_rules', NEW.rule_id, NEW.charged_on);
  RETURN NEW;
END $$;
CREATE TRIGGER zz_iso_cites BEFORE INSERT ON public.zz_iso_charges FOR EACH ROW EXECUTE FUNCTION public.zz_iso_cites();
CREATE FUNCTION public.zz_iso_floor(p_id uuid) RETURNS date LANGUAGE sql STABLE SET search_path = public, pg_temp AS
  $$ SELECT max(charged_on) FROM public.zz_iso_charges WHERE rule_id = p_id $$;
SELECT public.rule_table_register('public.zz_iso_rules', 'law', 'zz_iso', '{customer_class}', '{}', 'public.zz_iso_floor(uuid)');
INSERT INTO public.zz_iso_rules (id, state_code, service_type, customer_class, effective_from, source_note, terms_kind, terms_version, terms_source)
VALUES ('00000000-0000-4000-8000-0000000017f9', 'ZZ', 'gas', 'residential', DATE '2000-01-01', 'iso law row', 'zz_iso', 1,
        '{"governs": "law", "citation": "ZZ 1", "cap": 50}');
INSERT INTO public.zz_iso_rules (id, state_code, service_type, customer_class, effective_from, source_note, terms_kind, terms_version, terms_source)
VALUES ('00000000-0000-4000-8000-0000000017fa', 'ZZ', 'gas', 'commercial', DATE '2000-01-01', 'iso law row 2', 'zz_iso', 1,
        '{"governs": "law", "citation": "ZZ 2", "cap": 500}');
-- A core-written table, for X6.
INSERT INTO public.rule_term_schemas (terms_kind, terms_version, rule_role, json_schema, introduced_on, description, source_note)
VALUES ('zz_iso_inputs', 1, 'inputs', '{"$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object", "additionalProperties": false,
  "required": ["n"], "properties": {"n": {"type": "integer"}}}', DATE '2026-10-07', 'isolation fixture inputs', 'fixture');
INSERT INTO public.rule_term_schemas (terms_kind, terms_version, rule_role, json_schema, introduced_on, description, source_note)
SELECT 'zz_iso_inputs', v, 'inputs', json_schema, DATE '2026-10-07', 'isolation fixture inputs v' || v, 'fixture'
  FROM public.rule_term_schemas, generate_series(2, 3) v WHERE terms_kind = 'zz_iso_inputs' AND terms_version = 1 ORDER BY v;
CREATE TABLE public.zz_iso_calcs (
  id uuid DEFAULT public.uuid_generate_v4() PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES public.tenants(id),
  inputs jsonb NOT NULL, inputs_kind text NOT NULL, inputs_version integer NOT NULL,
  inputs_fingerprint text NOT NULL, calculated_by text NOT NULL);
ALTER TABLE public.zz_iso_calcs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.zz_iso_calcs FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON public.zz_iso_calcs USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
GRANT SELECT, INSERT ON public.zz_iso_calcs TO tally_core;
CREATE TRIGGER zz_iso_calcs_inputs BEFORE INSERT ON public.zz_iso_calcs FOR EACH ROW EXECUTE FUNCTION public.stamp_core_inputs();
COMMIT;
