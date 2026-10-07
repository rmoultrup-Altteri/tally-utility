#!/usr/bin/env python3
"""v5.4.2-17 — prove the -17 checks CATCH drift, not merely pass.

Each mutation alters a copy of the patch, applies it (strict: search_path ''
and function-body checking on) to a fresh clone of `tally` with TEMP revoked,
and runs the script that owns the named check:

  battery check (R V F T L U C A P I K G)  run-battery-17.sh
  X1-X5                                     isolation-17.sh
  RC1-RC4                                   races/rule-close-17.sh
  W1-W5                                     lawfiles-17.sh
  APPLY                                     the patch itself must refuse

CAUGHT only when the named check prints its own FAIL line ("FAIL T4a:",
"FAIL RC1:"): the battery stops at the first failing check, so a mutation an
EARLIER check catches is reported as missed here, and its named check is
wrong — fix the name, never loosen the rule.

    python3 tests/v5.4.2-17/mutations-17.py [M07 M12 ...]
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[2]
PATCH = ROOT / "sql/v5.4.2-17-rule-terms-convention.sql"
HERE = ROOT / "tests/v5.4.2-17"
DB = "m17"


def rep(old: str, new: str) -> Callable[[str], str]:
    def m(s: str) -> str:
        assert s.count(old) == 1, f"mutation anchor not unique/found ({s.count(old)}): {old[:90]!r}"
        return s.replace(old, new, 1)
    return m


def both(*fs: Callable[[str], str]) -> Callable[[str], str]:
    def m(s: str) -> str:
        for f in fs:
            s = f(s)
        return s
    return m


MUTATIONS = [
    # ---- the registry (section 4)
    ("M01", "a schema outside the subset registers", "R4a",
     rep("    v_err := public.rule_terms_schema_errors(NEW.json_schema);\n    IF cardinality(v_err) > 0 THEN",
         "    v_err := '{}';\n    IF cardinality(v_err) > 0 THEN")),
    ("M02", "format is a supported keyword", "R4a",
     rep("WHEN 'string'  THEN ARRAY['const', 'enum', 'minLength', 'maxLength', 'pattern']",
         "WHEN 'string'  THEN ARRAY['const', 'enum', 'minLength', 'maxLength', 'pattern', 'format']")),
    ("M03", "an object schema may be open", "R4b",
     rep("        IF NOT (p_node ? 'additionalProperties') OR p_node -> 'additionalProperties' <> 'false'::jsonb THEN",
         "        IF false THEN")),
    ("M04", "any pattern", "R4c",
     rep("        IF p_node ? 'pattern' AND (jsonb_typeof(p_node -> 'pattern') <> 'string' OR NOT (p_node ->> 'pattern') = ANY (c_patterns)) THEN",
         "        IF p_node ? 'pattern' AND jsonb_typeof(p_node -> 'pattern') <> 'string' THEN")),
    ("M05", "a $ref to nothing", "R4d",
     rep("            IF v_target IS NULL THEN\n                v_err := v_err || (p_path || ': $ref ' || (p_node ->> '$ref') || ' names no definition');\n            ELSIF",
         "            IF false THEN\n                NULL;\n            ELSIF")),
    ("M06", "a definition may be a reference", "R4e",
     rep("                IF jsonb_typeof(p_schema -> '$defs' -> v_k) = 'object' AND (p_schema -> '$defs' -> v_k) ? '$ref' THEN",
         "                IF false THEN")),
    ("M07", "a union with no discriminator", "R4f",
     rep("        IF v_disc IS NULL THEN\n            v_err := v_err || (p_path || ': a oneOf needs exactly one property",
         "        IF false THEN\n            v_err := v_err || (p_path || ': a oneOf needs exactly one property")),
    ("M08", "a union repeating a discriminator value", "R4g",
     rep("                 FROM jsonb_array_elements(p_node -> 'oneOf') b) <> jsonb_array_length(p_node -> 'oneOf') THEN",
         "                 FROM jsonb_array_elements(p_node -> 'oneOf') b) < 0 THEN")),
    ("M09", "any version number", "R2a",
     rep("    IF NEW.terms_version IS DISTINCT FROM coalesce(v_next, 1) THEN", "    IF false THEN")),
    ("M10", "a version may change the kind's role", "R2b",
     rep("    IF v_role IS NOT NULL AND v_role <> NEW.rule_role THEN", "    IF false THEN")),
    ("M11", "a law kind need not admit the delegated document", "R3b",
     rep("        IF NOT v_found THEN", "        IF false THEN")),
    ("M12", "governs may take any value", "R3a",
     rep("            IF NOT (v_branch #>> '{properties,governs,const}') = ANY (ARRAY['law', 'delegated_to_utility']) THEN",
         "            IF false THEN")),
    ("M13", "the application may register a schema", "R6a",
     rep("REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.rule_term_schemas FROM tally_app, tally_core;",
         "REVOKE UPDATE, DELETE, TRUNCATE ON public.rule_term_schemas FROM tally_app, tally_core;\nGRANT INSERT ON public.rule_term_schemas TO tally_app;")),
    ("M14", "a schema may be edited", "R7a",
     rep("        IF NOT (OLD.accepts_new_rows AND NOT NEW.accepts_new_rows)\n           OR (to_jsonb(NEW) - c_frozen_cols) IS DISTINCT FROM (to_jsonb(OLD) - c_frozen_cols) THEN",
         "        IF NOT (OLD.accepts_new_rows AND NOT NEW.accepts_new_rows) AND false THEN")),
    ("M15", "a schema may be deleted", "R7c",
     rep("    IF TG_OP = 'DELETE' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('term schema %s v%s is never deleted",
         "    IF TG_OP = 'DELETE' THEN\n        RETURN OLD;\n        RAISE EXCEPTION USING\n            MESSAGE = format('term schema %s v%s is never deleted")),
    ("M16", "the registry may be truncated", "R7d",
     rep("CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.rule_term_schemas\n    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_rule_registry_no_truncate();\nALTER TABLE public.rule_term_schemas ENABLE ALWAYS TRIGGER no_truncate;",
         "")),
    ("M17", "the hash is not of the schema", "R1",
     rep("    NEW.schema_hash := 'sha256:' || encode(sha256(convert_to(NEW.json_schema::text, 'UTF8')), 'hex');",
         "    NEW.schema_hash := 'sha256:' || encode(sha256(convert_to(NEW.description, 'UTF8')), 'hex');")),
    ("M18", "a frozen version may be thawed", "R8b",
     rep("        IF NOT (OLD.accepts_new_rows AND NOT NEW.accepts_new_rows)\n           OR (to_jsonb(NEW) - c_frozen_cols)",
         "        IF NOT (OLD.accepts_new_rows <> NEW.accepts_new_rows)\n           OR (to_jsonb(NEW) - c_frozen_cols)")),
    # ---- the validator (section 3)
    ("M19", "unknown keys pass", "V2",
     rep("            IF NOT coalesce(v_node -> 'properties', '{}'::jsonb) ? v_k THEN\n                v_err := v_err || (public.rule_terms_pointer(p_path, v_k) || ': unknown key');\n            ELSE",
         "            IF NOT coalesce(v_node -> 'properties', '{}'::jsonb) ? v_k THEN\n                NULL;\n            ELSE")),
    ("M20", "required keys may be missing", "V3",
     rep("            IF NOT p_doc ? v_k THEN\n                v_err := v_err || (public.rule_terms_pointer(p_path, v_k) || ': required');",
         "            IF false THEN\n                v_err := v_err || (public.rule_terms_pointer(p_path, v_k) || ': required');")),
    ("M21", "a null is only a type mismatch", "V4",
     rep("    IF p_doc IS NULL OR v_type = 'null' THEN\n        RETURN ARRAY[p_path || ': null is not allowed",
         "    IF p_doc IS NULL THEN\n        RETURN ARRAY[p_path || ': null is not allowed")),
    ("M22", "a number may be a string", "V5",
     rep("        IF v_type <> 'number' THEN\n            RETURN ARRAY[p_path || ': expected a number'];",
         "        IF v_type NOT IN ('number', 'string') THEN\n            RETURN ARRAY[p_path || ': expected a number'];")),
    ("M23", "an unknown strategy falls to the first branch", "V6",
     rep("        IF v_branch IS NULL THEN\n            RETURN ARRAY[public.rule_terms_pointer(p_path, v_disc) || ': \"' || v_value",
         "        IF v_branch IS NULL THEN\n            v_branch := v_node -> 'oneOf' -> 0;\n        END IF;\n        IF false THEN\n            RETURN ARRAY[public.rule_terms_pointer(p_path, v_disc) || ': \"' || v_value")),
    ("M24", "enum not enforced", "V9",
     rep("        IF v_node ? 'enum' AND NOT (v_node -> 'enum') ? v_value THEN", "        IF false THEN")),
    ("M25", "integer not enforced", "V10",
     rep("        IF v_node ->> 'type' = 'integer' AND v_n <> trunc(v_n) THEN", "        IF false THEN")),
    ("M26", "minimum not enforced", "V11",
     rep("        IF v_node ? 'minimum' AND v_n < (v_node ->> 'minimum')::numeric THEN", "        IF false THEN")),
    ("M27", "exclusiveMinimum is inclusive", "V11",
     rep("        IF v_node ? 'exclusiveMinimum' AND v_n <= (v_node ->> 'exclusiveMinimum')::numeric THEN",
         "        IF v_node ? 'exclusiveMinimum' AND v_n < (v_node ->> 'exclusiveMinimum')::numeric THEN")),
    ("M28", "minItems not enforced", "V12",
     rep("        IF v_node ? 'minItems' AND v_len < (v_node ->> 'minItems')::numeric THEN", "        IF false THEN")),
    ("M29", "uniqueItems not enforced", "V13",
     rep("        IF (v_node -> 'uniqueItems') = 'true'::jsonb\n           AND", "        IF false\n           AND")),
    ("M30", "pattern not enforced", "V14",
     rep("        IF v_node ? 'pattern' AND v_value !~ (v_node ->> 'pattern') THEN", "        IF false THEN")),
    ("M31", "numbers need not be canonical", "V16",
     rep("     WHERE jsonb_typeof(v) = 'number' AND NOT public.rule_terms_number_canonical(v);",
         "     WHERE jsonb_typeof(v) = 'number' AND false;")),
    ("M32", "component ids unique only within an array", "V15",
     rep("              FROM jsonb_path_query(p_doc, 'strict $.**.id') v\n             WHERE jsonb_typeof(v) = 'string'\n             GROUP BY",
         "              FROM jsonb_path_query(p_doc, 'strict $.**.waivers[*].id') v\n             WHERE jsonb_typeof(v) = 'string'\n             GROUP BY")),
    ("M33", "maxLength not enforced", "V19",
     rep("        IF v_node ? 'maxLength' AND char_length(v_value) > (v_node ->> 'maxLength')::numeric THEN", "        IF false THEN")),
    ("M34", "the parser lets duplicates through", "V21a",
     rep("    IF NOT (p_text IS JSON OBJECT WITH UNIQUE KEYS) THEN", "    IF false THEN")),
    ("M35", "a pointer does not escape /", "V20",
     rep("    SELECT p_path || '/' || replace(replace(p_key, '~', '~0'), '/', '~1')", "    SELECT p_path || '/' || replace(p_key, '~', '~0')")),
    ("M36", "the parser only checks the root", "V21b",
     rep("    IF NOT (p_text IS JSON OBJECT WITH UNIQUE KEYS) THEN",
         "    IF EXISTS (SELECT 1 FROM json_object_keys(p_text::json) k GROUP BY k HAVING count(*) > 1) THEN")),
    # ---- facets (section 4)
    ("M37", "a facet may be declared after its schema's transaction", "X1",
     rep("    IF v_txid IS DISTINCT FROM txid_current() THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('facet %s of %s v%s: facets are declared",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('facet %s of %s v%s: facets are declared")),
    ("M38", ".datetime() allowed", "F2b", rep("    IF NEW.json_path ~* 'datetime' THEN", "    IF false THEN")),
    ("M39", "a vocabulary need not be a table", "F2c",
     rep("        IF v_cls IS NULL OR NOT EXISTS (SELECT 1 FROM pg_class c WHERE c.oid = v_cls AND c.relkind IN ('r', 'p')) THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('facet %s: vocabulary %s is not a table",
         "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('facet %s: vocabulary %s is not a table")),
    ("M40", "present is always true", "F4", rep("            v_value := to_jsonb(v_n > 0);", "            v_value := to_jsonb(true);")),
    ("M41", "a single-valued facet takes the first of several matches", "F5",
     rep("            IF v_n > 1 THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('facet %s of %s v%s: path %s matched %s values",
         "            IF false THEN\n                RAISE EXCEPTION USING\n                    MESSAGE = format('facet %s of %s v%s: path %s matched %s values")),
    ("M42", "a writer-set facet is overwritten silently", "T6d",
     rep("        IF p_row -> v_k IS NOT NULL AND jsonb_typeof(p_row -> v_k) <> 'null' AND (p_row -> v_k) <> (v_facets -> v_k) THEN",
         "        IF false THEN")),
    ("M43", "vocabulary facets unchecked", "T6h",
     rep("        IF v_missing IS NOT NULL THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('%s: %s names %s, not in %s",
         "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('%s: %s names %s, not in %s")),
    ("M44", "a vocabulary's scope ignored", "T6i",
     rep("            v_scope := v_scope || format(' AND v.%I = %L', v_k, p_row ->> (f.vocabulary_scope ->> v_k));", "            NULL;")),
    ("M45", "a version may declare other facets than the table has", "T6k",
     rep("    IF NOT (v_declared @> p_cfg.facet_columns AND v_declared <@ p_cfg.facet_columns) THEN", "    IF false THEN")),
    # ---- the template (sections 5-6)
    ("M46", "an area key may be NULL", "T1b",
     rep("            v_err := v_err || public.rule_table_column_errors(p_table, v_c, 'text', true);",
         "            v_err := v_err || public.rule_table_column_errors(p_table, v_c, 'text', NULL);")),
    ("M47", "the law exclusion ignores the owner span", "T3a",
     rep("EXCLUDE USING gist (state_code WITH =, service_type WITH =, owner_span WITH &&, system_span WITH &&",
         "EXCLUDE USING gist (state_code WITH =, service_type WITH =, system_span WITH &&")),
    ("M48", "every row binds every owner type", "T3a",
     rep("    IF p_codes IS NULL THEN\n        RETURN int4multirange(int4range(0, NULL));\n    END IF;",
         "    RETURN int4multirange(int4range(0, NULL));")),
    ("M49", "terms set by the writer kept", "T6c",
     rep("    IF p_row -> 'terms' IS NOT NULL AND jsonb_typeof(p_row -> 'terms') <> 'null' AND (p_row -> 'terms') <> v_terms THEN",
         "    IF false THEN")),
    ("M50", "another kind's document accepted", "T6e",
     rep("    IF p_row ->> 'terms_kind' IS DISTINCT FROM p_cfg.terms_kind THEN", "    IF false THEN")),
    ("M51", "a frozen version accepted", "T6g", rep("    IF NOT v_schema.accepts_new_rows THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s v%s is frozen", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s v%s is frozen")),
    ("M52", "the area's insert check never called", "T6j",
     rep("    IF p_cfg.insert_check IS NOT NULL THEN", "    IF false THEN")),
    ("M53", "a close may carry an edit", "T7c",
     rep("    IF (v_old -> 'effective_to') = 'null'::jsonb AND (v_new -> 'effective_to') <> 'null'::jsonb\n       AND (v_new - c_close_cols) = (v_old - c_close_cols) THEN",
         "    IF (v_old -> 'effective_to') = 'null'::jsonb AND (v_new -> 'effective_to') <> 'null'::jsonb THEN")),
    ("M54", "a rule row may be deleted", "T7d",
     rep("    IF TG_OP = 'DELETE' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s rows are never deleted: records cite them",
         "    IF TG_OP = 'DELETE' THEN\n        RETURN OLD;\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s rows are never deleted: records cite them")),
    ("M55", "any role closes a law row", "T7f",
     rep("        IF v_cfg.rule_role = 'law' AND NOT coalesce(v_sees_all, false) THEN", "        IF false THEN")),
    ("M56", "a close is not stamped", "T8",
     rep("        v_set := jsonb_build_object('closed_at', now(),", "        v_set := jsonb_build_object('closed_at', NULL,")),
    ("M57", "a system kind of another service", "T5d",
     rep("             WHERE NOT EXISTS (SELECT 1 FROM public.utility_system_kinds k WHERE k.system_kind = s AND (p_row ->> 'service_type') = ANY (k.service_types));",
         "             WHERE NOT EXISTS (SELECT 1 FROM public.utility_system_kinds k WHERE k.system_kind = s);")),
    ("M58", "an empty owner set", "T5b",
     rep("    IF cardinality(p_codes) = 0 OR array_position(p_codes, NULL) IS NOT NULL", "    IF array_position(p_codes, NULL) IS NOT NULL")),
    ("M59", "a seed upserts over a different document", "T4e",
     rep("    IF cardinality(v_diff) > 0 THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s already holds this law row",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s already holds this law row")),
    ("M60", "a seed compares owner types in order", "T4d",
     rep("                       AND t.owner_span = public.rule_applicability_span(''owner_type'', $4)",
         "                       AND t.owner_types = $4")),
    ("M61", "registration takes any hook", "T1d",
     rep("    IF p_close_floor IS NOT NULL AND NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = p_close_floor", "    IF false AND NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = p_close_floor")),
    ("M62", "the application may register a table", "T1e",
     rep("REVOKE ALL ON FUNCTION public.rule_table_register(regclass, text, text, text[], text[], regprocedure, regprocedure, regclass, regprocedure, boolean)\n    FROM PUBLIC, tally_app, tally_core;\nREVOKE ALL ON FUNCTION public.assert_tenant_isolation_invariants() FROM tally_core;",
         "REVOKE ALL ON FUNCTION public.assert_tenant_isolation_invariants() FROM tally_core;")),
    # ---- lookups
    ("M63", "the law lookup ignores the owner", "L1",
     rep("    EXECUTE format('SELECT array_agg(t.id) FROM %s t WHERE t.state_code = $1 AND t.service_type = $2\n                      AND t.owner_span @> $3 AND t.system_span @> $4",
         "    EXECUTE format('SELECT array_agg(t.id) FROM %s t WHERE t.state_code = $1 AND t.service_type = $2\n                      AND $3 IS NOT NULL AND t.system_span @> $4")),
    ("M64", "no law is an empty answer", "L2a",
     rep("    IF v_ids IS NULL THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('no law in %s binds", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('no law in %s binds")),
    ("M65", "any key accepted", "L2d",
     rep("    IF NOT (v_keys @> p_cfg.area_key AND v_keys <@ p_cfg.area_key)\n       OR", "    IF false\n       OR")),
    # ---- tariffs
    ("M66", "the comparator never runs", "U2a",
     rep("    IF cardinality(v_problems) > 0 THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s: looser than the law", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s: looser than the law")),
    ("M67", "a tariff need not have a profile", "U3a",
     rep("    IF (datemultirange(v_range) - v_profiled) <> '{}'::datemultirange THEN", "    IF false THEN")),
    ("M68", "a tariff need not have law over its range", "U3b",
     rep("    IF (datemultirange(v_range) - v_lawed) <> '{}'::datemultirange THEN", "    IF false THEN")),
    ("M69", "any law row covers a tariff", "U3b",
     rep("            v_shared := v_shared || format(' AND t.%I = %L', v_c, p_row ->> v_c);", "            NULL;")),
    ("M70", "a tariff row keeps the writer's created_by", "U1",
     rep("        v_set := v_set || jsonb_build_object('created_by', v_user);", "        NULL;")),
    ("M71", "a tariff row may be deleted by its utility", "T2",
     rep("        EXECUTE format('REVOKE DELETE, TRUNCATE ON %s FROM tally_app', v_rel);\n        EXECUTE format('GRANT SELECT, INSERT, UPDATE ON %s TO tally_app', v_rel);",
         "        EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON %s TO tally_app', v_rel);")),
    # ---- citations and closes
    ("M72", "a citation need not be in force", "C2a",
     rep("    IF NOT v_in_force THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s row %s is not in force on %s", "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('%s row %s is not in force on %s")),
    ("M73", "the close floor is ignored", "C3a",
     rep("            IF v_floor IS NOT NULL AND (v_new ->> 'effective_to')::date <= v_floor THEN", "            IF false THEN")),
    ("M74", "a close takes no lock", "RC1",
     rep("        PERFORM pg_advisory_xact_lock(public.rule_row_lock_key(TG_RELID::regclass, OLD.id));\n        IF v_cfg.close_floor IS NOT NULL THEN",
         "        IF v_cfg.close_floor IS NOT NULL THEN")),
    ("M75", "a citation takes no lock", "RC2",
     rep("    PERFORM pg_advisory_xact_lock_shared(public.rule_row_lock_key(p_table, p_id));\n    EXECUTE format('SELECT daterange(t.effective_from",
         "    EXECUTE format('SELECT daterange(t.effective_from")),
    ("M76", "a freeze takes no lock", "RC4",
     rep("        PERFORM pg_advisory_xact_lock(public.rule_term_schema_lock_key(OLD.terms_kind, OLD.terms_version));\n        NEW.frozen_at := now();",
         "        NEW.frozen_at := now();")),
    ("M77", "a rule-row insert takes no schema lock", "RC3",
     rep("    PERFORM pg_advisory_xact_lock_shared(public.rule_term_schema_lock_key(p_cfg.terms_kind, (p_row ->> 'terms_version')::integer));",
         "")),
    ("M78", "a rule row written under REPEATABLE READ", "X2",
     rep("    PERFORM public.assert_rule_read_committed(format('writing a row of %s', TG_RELID::regclass));", "")),
    ("M79", "a citation under REPEATABLE READ", "X3",
     rep("    PERFORM public.assert_rule_read_committed(format('citing a row of %s', p_table));", "")),
    ("M80", "a close under SERIALIZABLE", "X4",
     rep("        PERFORM public.assert_rule_read_committed(format('closing a row of %s', TG_RELID::regclass));", "")),
    ("M81", "a freeze under REPEATABLE READ", "X5",
     rep("        PERFORM public.assert_rule_read_committed('freezing a term schema');", "")),
    # ---- adoption
    ("M82", "a second fill allowed", "A3a",
     rep("    IF v_cfg.adopts_legacy_rows AND (v_old -> 'terms') = 'null'::jsonb AND (v_new -> 'terms_source') <> 'null'::jsonb THEN",
         "    IF v_cfg.adopts_legacy_rows AND (v_new -> 'terms_source') <> 'null'::jsonb THEN")),
    ("M83", "a fill may change other columns", "A3b",
     rep("        IF (v_new - v_doc_cols) IS DISTINCT FROM (v_old - v_doc_cols) THEN", "        IF false THEN")),
    ("M84", "a fill may move the spans", "A3e",
     rep("        IF (v_set -> 'owner_span') IS DISTINCT FROM (v_old -> 'owner_span')", "        IF false")),
    ("M85", "any role adopts", "A3d",
     rep("        IF NOT coalesce(v_sees_all, false) THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('adopting %s row %s is a reviewed migration''s act",
         "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = format('adopting %s row %s is a reviewed migration''s act")),
    # ---- published values
    ("M86", "a value in any scope", "P3a",
     rep("    IF (NEW.state_code IS NOT NULL) <> ('state_code' = ANY (v_p.scoped_by))\n       OR (NEW.service_type IS NOT NULL) <> ('service_type' = ANY (v_p.scoped_by)) THEN",
         "    IF false THEN")),
    ("M87", "a value out of range", "P3b",
     rep("    IF (v_p.value_min IS NOT NULL AND NEW.value < v_p.value_min) OR (v_p.value_max IS NOT NULL AND NEW.value > v_p.value_max) THEN", "    IF false THEN")),
    ("M88", "NaN only caught as out of range", "P3c",
     rep("    IF NEW.value = 'NaN'::numeric THEN", "    IF false THEN")),
    ("M89", "a lookup in a broader scope", "P2a",
     rep("    IF (p_state_code IS NOT NULL) <> ('state_code' = ANY (v_p.scoped_by)) OR (p_service_type IS NOT NULL) <> ('service_type' = ANY (v_p.scoped_by)) THEN",
         "    IF false THEN")),
    ("M90", "a published value may be edited", "P3e",
     rep("        IF OLD.effective_to IS NOT NULL OR NEW.effective_to IS NULL\n           OR (to_jsonb(NEW) - c_close_cols) IS DISTINCT FROM (to_jsonb(OLD) - c_close_cols) THEN\n            RAISE EXCEPTION USING\n                MESSAGE = 'a published value is never edited",
         "        IF false THEN\n            RAISE EXCEPTION USING\n                MESSAGE = 'a published value is never edited")),
    # ---- core inputs
    ("M91", "the writer's fingerprint is kept", "I3a",
     rep("    IF v_row ->> 'inputs_fingerprint' IS NOT NULL AND v_row ->> 'inputs_fingerprint' <> v_fp THEN", "    IF false THEN")),
    ("M92", "inputs not validated", "I3b",
     rep("    v_err := public.rule_terms_errors(v_schema.json_schema, v_row -> 'inputs');", "    v_err := '{}';")),
    ("M93", "any kind is an inputs kind", "I3d",
     rep("     WHERE terms_kind = v_row ->> 'inputs_kind' AND terms_version = (v_row ->> 'inputs_version')::integer AND rule_role = 'inputs';",
         "     WHERE terms_kind = v_row ->> 'inputs_kind' AND terms_version = (v_row ->> 'inputs_version')::integer;")),
    ("M94", "the fingerprint is md5", "I1",
     rep("    v_fp := 'sha256:' || encode(sha256(convert_to((v_row -> 'inputs')::text, 'UTF8')), 'hex');",
         "    v_fp := 'sha256:' || md5((v_row -> 'inputs')::text);")),
    # ---- the core role and findings
    ("M95", "the application records findings", "K4a",
     rep("REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.rule_audit_findings FROM tally_app;\n",
         "REVOKE UPDATE, DELETE, TRUNCATE ON public.rule_audit_findings FROM tally_app;\nGRANT INSERT ON public.rule_audit_findings TO tally_app;\n")),
    ("M96", "a missed decision need not say what", "K4b",
     rep("    IF FOUND AND v_kind.expects_decision <> (NEW.expected_decision IS NOT NULL) THEN", "    IF false THEN")),
    ("M97", "a finding's subject in another tenant", "K4d",
     rep("    IF v_tenant IS DISTINCT FROM NEW.tenant_id THEN", "    IF false THEN")),
    ("M98", "a finding names an unregistered rule table", "K4f",
     rep("        SELECT * INTO v_cfg FROM public.rule_tables WHERE table_name = v_cls;\n        IF NOT FOUND THEN",
         "        SELECT * INTO v_cfg FROM public.rule_tables WHERE table_name = v_cls;\n        IF false THEN")),
    ("M99", "findings may be edited", "K5a",
     rep("    IF TG_OP <> 'INSERT' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = 'an audit finding is never edited or deleted",
         "    IF TG_OP = 'DELETE' THEN\n        RAISE EXCEPTION USING\n            MESSAGE = 'an audit finding is never edited or deleted")),
    ("M100", "a finding's kind and version are the writer's", "K3",
     rep("        NEW.terms_kind := v_rule ->> 'terms_kind';\n        NEW.terms_version := (v_rule ->> 'terms_version')::integer;", "        NULL;")),
    ("M101", "the core holds TEMP", "K1",
     rep("    EXECUTE format('REVOKE TEMP ON DATABASE %I FROM tally_core', current_database());",
         "    EXECUTE format('GRANT TEMP ON DATABASE %I TO tally_core', current_database());")),
    ("M102", "the core reads materialized views", "APPLY",
     rep("              WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v') LOOP\n        EXECUTE format('GRANT SELECT ON %s TO tally_core', r.t);",
         "              WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v', 'm') LOOP\n        EXECUTE format('GRANT SELECT ON %s TO tally_core', r.t);")),
    ("M103", "findings have an open policy", "APPLY",
     rep("CREATE POLICY tenant_isolation ON public.rule_audit_findings USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));",
         "CREATE POLICY tenant_isolation ON public.rule_audit_findings USING (true);")),
    ("M104", "a tariff table's policy is open", "U5b",
     rep("        EXECUTE format('CREATE POLICY tenant_isolation ON %s USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())))', v_rel);",
         "        EXECUTE format('CREATE POLICY tenant_isolation ON %s USING (true)', v_rel);")),
]


def sh(cmd: list[str], inp: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, input=inp, capture_output=True, text=True)


def runner(check: str) -> list[str]:
    if check.startswith("X"):
        return [str(HERE / "isolation-17.sh"), DB, "m17iso"]
    if re.fullmatch(r"RC[1-4]", check):
        return [str(HERE / "races/rule-close-17.sh"), DB, "m17race"]
    if check.startswith("W"):
        return [str(HERE / "lawfiles-17.sh"), DB, "m17law"]
    return [str(HERE / "run-battery-17.sh"), DB]


def main() -> int:
    base = PATCH.read_text()
    only = set(sys.argv[1:])
    missed = ran = 0
    for mid, what, check, mut in MUTATIONS:
        if only and mid not in only:
            continue
        ran += 1
        try:
            patched = mut(base)
        except AssertionError as exc:
            print(f"{mid} ANCHOR-ERROR: {exc}")
            missed += 1
            continue
        for q in (f"DROP DATABASE IF EXISTS {DB}", f"CREATE DATABASE {DB} TEMPLATE tally"):
            sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", q])
        # A TEMPLATE clone does not copy the database ACL: revoke TEMP again.
        sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", DB, "-qc", f"REVOKE TEMP ON DATABASE {DB} FROM PUBLIC, tally_app"])
        a = sh(["docker", "exec", "-i", "tally-pg", "psql", "-U", "tally", "-d", DB, "-v", "ON_ERROR_STOP=1", "-q", "-1", "-f", "-"],
               "SET search_path = ''; SET check_function_bodies = on;\n" + patched)
        if a.returncode:
            last = a.stderr.strip().splitlines()[-1] if a.stderr.strip() else "?"
            if check == "APPLY":
                print(f"{mid} caught at apply: {what} ({last[:90]})")
            else:
                print(f"{mid} APPLY-ERROR ({what}): {last[:140]}")
                missed += 1
            continue
        if check == "APPLY":
            print(f"{mid} MISSED (applied cleanly): {what}")
            missed += 1
            continue
        out = sh(runner(check))
        text = out.stdout + out.stderr
        first = next((l for l in text.splitlines() if "FAIL" in l or "ERROR" in l), "")
        first = re.sub(r"^psql:[^:]+:\d+: ", "", first)[:120]
        if re.search(rf"FAIL {re.escape(check)}[a-z]?[:\s]", text):
            print(f"{mid} caught at {check}: {what}")
        else:
            print(f"{mid} MISSED ({check}): {what}  [first: {first}]")
            missed += 1
    print(f"{ran - missed}/{ran} caught")
    sh(["docker", "exec", "tally-pg", "psql", "-U", "tally", "-d", "postgres", "-qc", f"DROP DATABASE IF EXISTS {DB}"])
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main())
