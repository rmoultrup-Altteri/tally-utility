-- ============================================================================
-- THE ZZ FIXTURE AREA — a fictional state's law, written as an area migration
-- on the rule-terms convention (v5.4.2-17) would write it: three kinds (law,
-- tariff, core inputs) from the schema files beside this one, their facets, a
-- scoped vocabulary, a law table, a tariff table, a citing record table and a
-- core-written table, the area's hooks, and the registrations.
--
-- Included by tests/v5.4.2-17/battery-17.sql (inside its rolled-back
-- transaction) and by tools/law's CI (committed into a scratch database).
-- psql only: the schema files are read with backticks from /tmp/law, where
-- the runners copy law/. No BEGIN/COMMIT of its own — the caller's
-- transaction; the facets must share their schemas' transaction.
-- ============================================================================
\set zz_fee_schema `cat /tmp/law/fixtures/zz/zz_fee.v1.schema.json`
\set zz_tariff_schema `cat /tmp/law/fixtures/zz/zz_fee_tariff.v1.schema.json`
\set zz_inputs_schema `cat /tmp/law/fixtures/zz/zz_charge_inputs.v1.schema.json`

-- The area's waiver-class vocabulary, scoped by state and service.
CREATE TABLE public.zz_waiver_classes (
  state_code text NOT NULL, service_type text NOT NULL, class_code text NOT NULL,
  PRIMARY KEY (state_code, service_type, class_code));
INSERT INTO public.zz_waiver_classes VALUES ('ZZ', 'gas', 'senior'), ('ZZ', 'gas', 'medical'), ('TX', 'gas', 'tx_only');

INSERT INTO public.rule_term_schemas (terms_kind, terms_version, rule_role, json_schema, introduced_on, description, source_note) VALUES
  ('zz_fee', 1, 'law', :'zz_fee_schema', DATE '2026-10-07', 'ZZ connection fee (fixture)', 'law/fixtures/zz/zz_fee.v1.schema.json'),
  ('zz_fee_tariff', 1, 'tariff', :'zz_tariff_schema', DATE '2026-10-07', 'ZZ connection fee, a utility''s tariff (fixture)', 'law/fixtures/zz/zz_fee_tariff.v1.schema.json'),
  ('zz_charge_inputs', 1, 'inputs', :'zz_inputs_schema', DATE '2026-10-07', 'What the core read for a ZZ charge (fixture)', 'law/fixtures/zz/zz_charge_inputs.v1.schema.json');

INSERT INTO public.rule_term_facets (terms_kind, terms_version, facet_name, facet_type, json_path, vocabulary_table, vocabulary_column, vocabulary_scope, description) VALUES
  ('zz_fee', 1, 'fee_strategy', 'text', '$.fee.strategy', NULL, NULL, NULL, 'The fee strategy'),
  ('zz_fee', 1, 'fee_cap', 'number', '$.fee.cap', NULL, NULL, NULL, 'The statutory cap a tariff is compared with'),
  ('zz_fee', 1, 'has_fee', 'present', '$.fee', NULL, NULL, NULL, 'Whether the law sets a fee (false when delegated)'),
  ('zz_fee', 1, 'component_ids', 'text[]', 'strict $.**.id', NULL, NULL, NULL, 'Every component id, for citations'),
  ('zz_fee', 1, 'waiver_classes', 'text[]', '$.waivers[*].class', 'public.zz_waiver_classes', 'class_code',
   '{"state_code": "state_code", "service_type": "service_type"}', 'The waiver classes the law names');
INSERT INTO public.rule_term_facets (terms_kind, terms_version, facet_name, facet_type, json_path, description) VALUES
  ('zz_fee_tariff', 1, 'tariff_amount', 'number', '$.fee.amount', 'The tariff fee'),
  ('zz_fee_tariff', 1, 'component_ids', 'text[]', 'strict $.**.id', 'Every component id');

-- The area's tables, as an area migration writes them (owner).
CREATE TABLE public.zz_fee_rules (
  id uuid DEFAULT public.uuid_generate_v4() PRIMARY KEY,
  state_code text NOT NULL, service_type text NOT NULL,
  owner_types text[], system_kinds text[], commission_jurisdiction boolean,
  owner_span int4multirange NOT NULL DEFAULT '{[0,)}', system_span int4multirange NOT NULL DEFAULT '{[0,)}',
  jurisdiction_span int4range NOT NULL DEFAULT '[0,2)',
  customer_class text NOT NULL,
  effective_from date NOT NULL, effective_to date,
  source_note text NOT NULL,
  terms_kind text NOT NULL, terms_version integer NOT NULL, terms_source text NOT NULL, terms jsonb NOT NULL,
  fee_strategy text, fee_cap numeric, has_fee boolean, component_ids text[], waiver_classes text[],
  created_at timestamptz NOT NULL DEFAULT now(), recorded_txid bigint, closed_at timestamptz, closed_by text);
CREATE TABLE public.zz_fee_tariffs (
  id uuid DEFAULT public.uuid_generate_v4() PRIMARY KEY,
  tenant_id uuid NOT NULL, state_code text NOT NULL, service_type text NOT NULL, system_kind text NOT NULL,
  customer_class text NOT NULL,
  effective_from date NOT NULL, effective_to date,
  tariff_reference text NOT NULL,
  terms_kind text NOT NULL, terms_version integer NOT NULL, terms_source text NOT NULL, terms jsonb NOT NULL,
  tariff_amount numeric, component_ids text[],
  created_at timestamptz NOT NULL DEFAULT now(), created_by uuid, recorded_txid bigint, closed_at timestamptz, closed_by uuid);
-- Records that cite them — the citing-record pattern an area copies
-- (inventory U4, F7; review r1): the record names the utility's profile key
-- and its own area key, cites THE law row for them (rule_law_row_cite), cites
-- the utility's tariff row only if it is the one in force for that key, names
-- the component that governed by its id, and is never edited.
CREATE TABLE public.zz_charges (
  id uuid DEFAULT public.uuid_generate_v4() PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES public.tenants(id),
  state_code text NOT NULL, service_type text NOT NULL, system_kind text NOT NULL, customer_class text NOT NULL,
  rule_id uuid NOT NULL REFERENCES public.zz_fee_rules(id),
  tariff_id uuid REFERENCES public.zz_fee_tariffs(id),
  fee_component text NOT NULL,
  charged_on date NOT NULL, amount numeric NOT NULL,
  UNIQUE (tenant_id, id));
ALTER TABLE public.zz_charges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.zz_charges FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON public.zz_charges USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
REVOKE UPDATE, DELETE, TRUNCATE ON public.zz_charges FROM tally_app;
GRANT SELECT ON public.zz_charges TO tally_core;
CREATE FUNCTION public.zz_charge_cites() RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE
  v_key jsonb := jsonb_build_object('customer_class', NEW.customer_class);
  v_components text[];
BEGIN
  PERFORM public.rule_law_row_cite('public.zz_fee_rules', NEW.rule_id, NEW.tenant_id, NEW.service_type, NEW.system_kind,
                                   NEW.state_code, v_key, NEW.charged_on);
  IF NEW.tariff_id IS NOT NULL THEN
    PERFORM public.rule_row_cite('public.zz_fee_tariffs', NEW.tariff_id, NEW.charged_on);
    IF NEW.tariff_id IS DISTINCT FROM public.rule_tariff_row_as_of('public.zz_fee_tariffs', NEW.tenant_id, NEW.service_type, NEW.system_kind,
                                                                   NEW.state_code, v_key, NEW.charged_on) THEN
      RAISE EXCEPTION 'zz: tariff row % is not this utility''s tariff for % on %', NEW.tariff_id, v_key, NEW.charged_on USING ERRCODE = 'check_violation';
    END IF;
    SELECT component_ids INTO v_components FROM public.zz_fee_tariffs WHERE id = NEW.tariff_id;
  ELSE
    SELECT component_ids INTO v_components FROM public.zz_fee_rules WHERE id = NEW.rule_id;
  END IF;
  -- F7: the part that governed, named by its id and checked against the facet.
  IF NOT coalesce(NEW.fee_component = ANY (v_components), false) THEN
    RAISE EXCEPTION 'zz: component % is not a component of the row that governed (%)', NEW.fee_component, v_components USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER zz_charge_cites BEFORE INSERT ON public.zz_charges FOR EACH ROW EXECUTE FUNCTION public.zz_charge_cites();
CREATE FUNCTION public.zz_fee_floor(p_id uuid) RETURNS date LANGUAGE sql STABLE SET search_path = public, pg_temp AS
  $$ SELECT max(charged_on) FROM public.zz_charges WHERE rule_id = p_id $$;
CREATE FUNCTION public.zz_tariff_floor(p_id uuid) RETURNS date LANGUAGE sql STABLE SET search_path = public, pg_temp AS
  $$ SELECT max(charged_on) FROM public.zz_charges WHERE tariff_id = p_id $$;
-- An area predicate over a new row: waivers reach residential customers only.
CREATE FUNCTION public.zz_fee_insert_check(p_row jsonb) RETURNS void LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF p_row ->> 'customer_class' <> 'residential' AND jsonb_array_length(p_row -> 'waiver_classes') > 0 THEN
    RAISE EXCEPTION 'zz: a waiver reaches residential customers only' USING ERRCODE = 'check_violation';
  END IF;
END $$;
-- The comparator: a tariff fee above any applicable law row's cap is looser.
CREATE FUNCTION public.zz_fee_compare(p_tariff jsonb, p_law jsonb) RETURNS text[] LANGUAGE sql STABLE SET search_path = public, pg_temp AS $$
  SELECT coalesce(array_agg(format('fee %s above the cap %s of %s', p_tariff ->> 'tariff_amount', l ->> 'fee_cap', l ->> 'source_note') ORDER BY l ->> 'id'), '{}')
    FROM jsonb_array_elements(p_law) l
   WHERE l -> 'terms' ->> 'governs' = 'law' AND l ->> 'customer_class' = p_tariff ->> 'customer_class'
     AND (p_tariff ->> 'tariff_amount')::numeric > (l ->> 'fee_cap')::numeric
$$;

-- The core's record of what it read for a charge.
CREATE TABLE public.zz_charge_calcs (
  id uuid DEFAULT public.uuid_generate_v4() PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES public.tenants(id),
  charge_id uuid NOT NULL,
  FOREIGN KEY (tenant_id, charge_id) REFERENCES public.zz_charges(tenant_id, id),
  inputs jsonb NOT NULL, inputs_kind text NOT NULL, inputs_version integer NOT NULL,
  inputs_fingerprint text NOT NULL, calculated_by text NOT NULL);
ALTER TABLE public.zz_charge_calcs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.zz_charge_calcs FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON public.zz_charge_calcs USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
REVOKE INSERT, UPDATE, DELETE ON public.zz_charge_calcs FROM tally_app;
GRANT SELECT, INSERT ON public.zz_charge_calcs TO tally_core;
CREATE TRIGGER zz_charge_calcs_inputs BEFORE INSERT ON public.zz_charge_calcs FOR EACH ROW EXECUTE FUNCTION public.stamp_core_inputs();

-- The registrations.
SELECT public.rule_table_register('public.zz_fee_rules', 'law', 'zz_fee', '{customer_class}',
                                  '{fee_strategy,fee_cap,has_fee,component_ids,waiver_classes}',
                                  'public.zz_fee_floor(uuid)', 'public.zz_fee_insert_check(jsonb)');
SELECT public.rule_table_register('public.zz_fee_tariffs', 'tariff', 'zz_fee_tariff', '{customer_class}',
                                  '{tariff_amount,component_ids}', 'public.zz_tariff_floor(uuid)', NULL,
                                  'public.zz_fee_rules', 'public.zz_fee_compare(jsonb,jsonb)');
