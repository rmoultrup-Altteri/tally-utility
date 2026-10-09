-- ============================================================================
-- PATCH v5.4.2-17 — the rule-terms convention, written once: a registry of
--                    term schemas, a validator, a law- and tariff-table
--                    template, published values, the core's role, audit
--                    findings, and the core-inputs fingerprint
-- ============================================================================
-- Authority:   Ryan, 2026-10-06: rule-terms convention v2 ADOPTED (application/
--              rule-terms-convention-v2-2026-10-06.md), §12 step 2. Ryan,
--              2026-10-07: the step-2 defaults (inventory §4) — -13's rows are
--              adopted in place; law-file tooling in Python; CI as a GitHub
--              Actions workflow.
-- Spec:        application/rule-terms-step2-source-inventory-2026-10-07.md —
--              every requirement V1-V10, F1-F7, T1-T7, U1-U5, P1-P4, C1-C4,
--              L1-L4 classed Step 2 is held here or in law/ and tools/law/,
--              or is a stated residual (section 11).
--
-- REVIEW ROUND 1 (frozen bf006d2a; Opus, Fable, Codex: all "not yet"; record:
--   tests/v5.4.2-17/review/review-findings-17-r1.md). Folded: the tariff
--   check locks, then re-reads its law rows until stable (B1, all three); a
--   core record runs only under READ COMMITTED (all three); adoption needs
--   the area's insert check, where a document is compared with the old
--   columns (Codex); facet columns are never template or key columns and
--   are of their facet's type; a table holding rows registers only as
--   adopting (Fable); no control character in a document, nesting at most
--   64 (all three: Python's "$" before a newline); a strategy fixes its
--   version (Fable); a law row's state is a known state; rule_law_row_cite
--   ties a citation to the citing utility's law (all three); dispositions of
--   audit findings and a unit vocabulary (all three); the expected-decision
--   pair's NULL escape closed (Codex); seeds refuse unknown columns and keep
--   defaults (Fable, Opus); facet paths refuse .double(); a close that
--   rewrites a number's scale is an edit; tally_core's attributes, TEMP and
--   column grants asserted (Codex, Opus); residuals R9-R17.
-- REVIEW ROUND 2 (frozen 89691580; Opus and Fable "ready", Codex "not yet";
--   record: tests/v5.4.2-17/review/review-findings-17-r2.md). Folded: a
--   facet column's type is paired with its facet's (all three); a union
--   branch is not a document level, so depth agrees with the reference check
--   (Fable, Codex); an adopting table names an adoption check, run only when
--   a document is filled — never on later inserts (Fable) — and holds no
--   filled document at registration (Codex); a re-seed compares every column
--   it names (Opus); a strategy's version is a range, so strategies version
--   independently of documents (Opus); a freeze compares text, so the hash
--   keeps meaning the stored schema (Codex); the core's invariants are a
--   reusable assertion CI runs, covering CREATE on any schema (Codex).
-- REVIEW ROUND 3 (frozen 74c730ed; Opus and Fable "ready"; Codex could not
--   run (usage limit); record: tests/v5.4.2-17/review/review-findings-17-r3.md).
--   Folded: tally_core is a member of no role (Opus S1); a seed names the
--   whole envelope and no id (Opus N1); strategy version bounds are
--   integers (Fable note).
-- REVIEW ROUND 4 (frozen ad7045b9; Codex "not yet"; Opus and Fable reviewed r3;
--   record: tests/v5.4.2-17/review/review-findings-17-r4.md). Folded: a law
--   kind's delegated branch is exactly the standard document, so it can be
--   satisfied (Codex B1); the version rule covers every object schema with a
--   "strategy" property, not only a union's branches (Codex B2); a seed types
--   its applicability before matching it (Codex S1); lawc refuses a lone
--   surrogate in a key (Codex S2); the adoption wording names the adoption
--   check (Codex S3).
--
-- ----------------------------------------------------------------------------
-- What changes
-- ----------------------------------------------------------------------------
--   * tally_core, the calculation core's role (v2 §8; C1): reads what
--     tally_app reads, writes only what a table grants it — in this patch,
--     audit findings. It defines no code (no TEMP, no CREATE) and is not a
--     member of tally_app nor tally_app of it. Tenant isolation is the
--     existing tenant_isolation policy, which names no role.
--   * A REGISTRY OF TERM SCHEMAS (V1): one row per (kind, version), holding a
--     JSON Schema (2020-12) document, its hash, the kind's role (law, tariff,
--     or the inputs of a core record) and whether it still accepts new rows.
--     Never edited except that one-way freeze; never deleted. A schema may
--     use only the keywords the validator enforces (V9).
--   * A VALIDATOR, rule_terms_errors(schema, document): one IMMUTABLE
--     interpreter of that subset (V3, V4) — closed objects, required keys, no
--     nulls, types, enumerations, bounds, array sizes and uniqueness, $ref
--     into $defs, and oneOf as a union selected by a const discriminator
--     ("strategy", "governs") — plus three fixed rules: component ids
--     ("id") unique in a document, numbers written canonically (no trailing
--     fractional zeros, so equal values hash equal), and no nulls. Duplicate
--     keys cannot survive a cast to jsonb, so a document enters as TEXT and
--     rule_terms_parse() refuses duplicates at any depth first (U2).
--   * FACETS (F1-F3, F7): per (kind, version), typed values derived from a
--     document by a JSON path — text, text[], integer, number, boolean,
--     present —
--     written by the row's insert trigger, never by the writer; a facet may
--     name a vocabulary table its codes must exist in, scoped by the row's
--     own columns (a waiver class of the row's state and service).
--   * THE LAW- AND TARIFF-TABLE TEMPLATE (T1-T6, U1, U3, U4):
--     rule_table_register() takes an area's table — the template columns
--     plus the area's own key and facet columns — and gives it the shared
--     parts: the no-overlap exclusion, the kind CHECK and registry key, the
--     insert, history and no-truncate triggers, the grants, and for a tariff
--     table the tenant policy. Law rows key on state, service, the owner
--     types, system kinds and commission-jurisdiction status they bind (each
--     NULL = every one), so one row can bind a set of owner types; spans of
--     integer ranges make the exclusion catch "every owner type" against
--     "municipal" (v2 §9; -16 R1). Tariff rows key on tenant, state,
--     service and the system they govern. A row's document is validated and
--     its facets derived on insert; the row is never edited after, except a
--     stamped close above its floor and — for a table registered as having
--     pre-convention rows — the one-time filling of an empty document (T6).
--     A law kind always admits the document "the law leaves this to the
--     utility" (V8), distinct from no law at all.
--   * One serialisation between a citation and a close (T4): a citing record
--     takes a rule row's lock shared and re-reads the row; a close takes it
--     exclusive and then reads its floor — both under READ COMMITTED. A
--     record citing law calls rule_law_row_cite, which also requires the row
--     to be THE law row in force for the citing utility (U4).
--   * Lookups that refuse rather than guess (T3): the law row in force for a
--     utility's profile, key and date; the utility's tariff row, if any.
--   * "Stricter, never looser" (U3): a tariff row is checked, on insert,
--     against every law row in force over its range for its utility, by the
--     area's comparator; a part of its range with no law known is refused.
--   * PUBLISHED VALUES (P1, P3): rule_parameters names a value published on
--     its own schedule (a commission's annual deposit rate, a Treasury
--     yield) with its unit, range and scope dimensions; rule_parameter_values
--     dates each published value with its own citation.
--   * AUDIT FINDINGS (C3): what the core's audit passes find — a missed
--     decision, a record that disagrees with its rule, a tariff looser than
--     a later law, a published value the utility's differs from — written
--     only by tally_core, append-only, per tenant; and what a person did
--     about each (acknowledged, corrected, dismissed), append-only too.
--   * THE CORE-INPUTS FINGERPRINT (C4): a trigger a core-written table
--     attaches; it validates the record's inputs against their registered
--     schema and stamps sha256 of the stored document. The writer cannot
--     choose the fingerprint, only confirm it.
--
--   Not here: any area's kinds, schemas, facets or tables. The -13
--   migration and the -15 rewrite (v2 §12 step 4) register their own. This
--   patch ships the machinery; the battery proves it on a fictional state's
--   law (ZZ), created and rolled back inside the test.
--
-- ----------------------------------------------------------------------------
-- What the database refuses
-- ----------------------------------------------------------------------------
--   Term schemas: any write by tally_app or tally_core; a schema using a
--   keyword the validator does not enforce, an unwhitelisted pattern, a
--   $ref to a missing or chained definition, a oneOf without exactly one
--   const discriminator, an object schema not closed; a law kind with no
--   "delegated_to_utility" document of the standard shape; a version not
--   the next for its kind, or a role other than the kind's; an edit other
--   than a stamped freeze; delete; truncate.
--   Facets: any write by tally_app or tally_core; a facet declared outside
--   its schema's transaction; a JSON path that does not parse or uses
--   .datetime(); a vocabulary that is not a table and column, or a scope
--   naming a column it lacks; edit; delete; truncate.
--   Registration: a table holding rows unless it adopts them; an adopting
--   table without an adoption check (the old-columns equality lives there, run once); a
--   facet column that is a template or key column, or not of a facet type.
--   Documents (every kind): a control character in any string or key; a
--   strategy (a union branch or alone) that does not fix its "version"; a law
--   kind whose delegated branch is not exactly the standard document.
--   Rule rows (any registered table): a document that is not JSON, has a
--   duplicate key, fails its schema, or disagrees with a document the
--   writer also set; a kind other than the table's; a version that does
--   not exist or is frozen; facets the writer set that the document does
--   not give; a facet code not in its vocabulary for the row's scope; an
--   owner type, system kind or state not known (a state is a state place),
--   or a system kind not of
--   the row's service; overlap with a row of the same key; an insert or a
--   close outside READ COMMITTED; any edit but a stamped close (above its
--   floor; for law, by a role that sees every tenant) or the one-time fill
--   of an empty document; delete; truncate. A tariff row: another tenant's;
--   a utility with no profile, or no law known, over part of its range; a
--   comparator's finding that it is looser than the law.
--   Seeds (rule_row_seed): a law row already stored for the same state,
--   service, owner/system/jurisdiction sets, key and start with a different
--   document, end, citation, kind or version — never an upsert, never a
--   silent skip; any seed by tally_app or tally_core.
--   Published values: any write by tally_app or tally_core; a value outside
--   its parameter's range, NaN, or scoped other than its parameter says;
--   overlap; any edit but a stamped close; delete; truncate.
--   Dispositions: any write but an INSERT by tally_app; one with no user;
--   one of another tenant's finding; edit; delete; truncate.
--   Audit findings: any write but an INSERT by tally_core (or a migration);
--   a subject or rule row that does not exist in the finding's tenant; a
--   missed decision without what was expected and by when (or the reverse);
--   a coverage that ends before it starts; edit; delete; truncate.
--   Core inputs: a write outside READ COMMITTED; inputs not valid for their
--   registered inputs schema (component ids exempt); a
--   fingerprint the writer supplied that is not the stored document's; a
--   blank calculated_by.
--
-- PRECONDITION. None: the patch adds a role, tables and functions, and
--   changes no existing row or object.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. tally_core — the calculation core's role (v2 §8; inventory C1)
-- ----------------------------------------------------------------------------
-- NOLOGIN, as tally_app is: a login role for the core service is granted
-- membership. It reads every table tally_app reads (SELECT; row-level
-- security applies — the tenant_isolation policy names no role) and writes
-- only where a table grants it INSERT. The core sets app.user_id like any
-- session; which user a core session acts as is the area's (residual R1).

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tally_core') THEN
        CREATE ROLE tally_core NOLOGIN;
    END IF;
END
$$;
COMMENT ON ROLE tally_core IS
    'The calculation core''s role (v5.4.2-17; rule-terms v2 §8). Reads what tally_app reads; writes only the records a table grants it (core-only records: decisions, accruals, due rows, audit findings), which tally_app cannot. NOLOGIN: grant membership to the core service''s LOGIN user. Never a member of tally_app, nor tally_app of it. Defines no code: no TEMP, no CREATE.';

GRANT USAGE ON SCHEMA public TO tally_core;
-- SELECT on every table and (invoker-rights) view; never a materialized view,
-- which row-level security does not reach. No default privileges: a table
-- added later is granted to the core by the patch that adds it, so the core
-- reads nothing it was not given (EXECUTE likewise; section 10).
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT c.oid::regclass AS t
               FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
              WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v') LOOP
        EXECUTE format('GRANT SELECT ON %s TO tally_core', r.t);
    END LOOP;
END
$$;

-- No code of its own: the trigger-depth fences (tu.sql 18690) hold only while
-- no application role can define a function or a temp table.
DO $$
BEGIN
    EXECUTE format('REVOKE TEMP ON DATABASE %I FROM tally_core', current_database());
    EXECUTE format('REVOKE CREATE ON DATABASE %I FROM tally_core', current_database());
    REVOKE CREATE ON SCHEMA public FROM tally_core;
END
$$;
-- A pre-existing tally_core keeps its attributes through IF NOT EXISTS, and
-- membership could join it to tally_app: the tail's
-- assert_core_role_invariants() refuses both (review r1, Codex S1).


-- ----------------------------------------------------------------------------
-- 2. Shared helpers
-- ----------------------------------------------------------------------------

-- Every rule-row insert, citation and close runs under READ COMMITTED: the
-- lock handshake makes each side wait for the other's commit, and only READ
-- COMMITTED then reads what was committed (the v5.4.2-16 pattern).
CREATE OR REPLACE FUNCTION public.assert_rule_read_committed(p_what text) RETURNS void
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s runs only under READ COMMITTED — under %s it would read a rule row or schema from a snapshot taken before a close or freeze it waited for (v5.4.2-17)', p_what, current_setting('transaction_isolation')),
            ERRCODE = 'invalid_transaction_state';
    END IF;
END;
$$;
COMMENT ON FUNCTION public.assert_rule_read_committed(text) IS
    'v5.4.2-17. Refuses (invalid_transaction_state, never a retryable code) outside READ COMMITTED: rule-row inserts, citations and closes, and schema freezes, wait on each other''s locks, and only READ COMMITTED then reads what the other committed.';

-- The advisory-lock key for a rule row: a citing record takes it shared, a
-- close exclusive. tally_app cannot row-lock a platform row it may not update.
CREATE OR REPLACE FUNCTION public.rule_row_lock_key(p_table regclass, p_id uuid) RETURNS bigint
    LANGUAGE sql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT hashtextextended('rule_row/' || p_table::oid::text || '/' || p_id::text, 0)
$$;
COMMENT ON FUNCTION public.rule_row_lock_key(regclass, uuid) IS
    'v5.4.2-17 (inventory T4). The advisory-lock key for a row of a registered rule table: a citing record takes it shared (rule_row_cite), a close takes it exclusive.';

-- The key a schema version's freeze takes exclusive and a rule-row insert of
-- that version takes shared.
CREATE OR REPLACE FUNCTION public.rule_term_schema_lock_key(p_kind text, p_version integer) RETURNS bigint
    LANGUAGE sql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT hashtextextended('rule_term_schema/' || p_kind || '/' || p_version::text, 0)
$$;
COMMENT ON FUNCTION public.rule_term_schema_lock_key(text, integer) IS
    'v5.4.2-17. The advisory-lock key for a term schema version: a freeze takes it exclusive, an insert of a row of that version shared.';

-- A JSON Pointer step (RFC 6901): ~ and / escaped.
CREATE OR REPLACE FUNCTION public.rule_terms_pointer(p_path text, p_key text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT p_path || '/' || replace(replace(p_key, '~', '~0'), '/', '~1')
$$;

-- True for a JSON number written canonically: as PostgreSQL's numeric with
-- its trailing fractional zeros removed would print it. 1.50 and 1.0 are
-- refused, 1.5 and 1 accepted, so two documents that mean the same numbers
-- serialise, and hash, the same — and a JSON Schema validator that reads
-- 1.0 as a non-integer cannot disagree with this one.
CREATE OR REPLACE FUNCTION public.rule_terms_number_canonical(p_value jsonb) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT p_value::text = trim_scale((p_value #>> '{}')::numeric)::text
$$;


-- ----------------------------------------------------------------------------
-- 3. The validator — one IMMUTABLE interpreter of a JSON Schema subset
-- ----------------------------------------------------------------------------
-- Why an interpreter and not a function generated per version (v2 §5's
-- wording): the same guarantee — a check on every write that cannot drift,
-- because the registry row it reads is never edited — reviewed once instead
-- of once per version. rule_terms_schema_errors() refuses, at registration,
-- any keyword this interpreter does not enforce, so a schema cannot claim a
-- check that never runs; the CI cross-check (tools/law) runs a standard
-- 2020-12 validator over the same documents and requires the two to agree.
--
-- The subset:
--   annotations, anywhere:  title, description, $comment (strings)
--   root only:              $schema (2020-12, required), $id, $defs
--   a reference:            {"$ref": "#/$defs/<name>"} and annotations only;
--                           the target exists and is not itself a $ref
--   a union:                {"oneOf": [...]} and annotations only; at least
--                           two branches, each an object schema (inline or a
--                           $ref to one); exactly one property every branch
--                           requires with a string const — the discriminator
--                           — with a different value in each branch
--   every other schema has a "type", one of:
--     object   properties, required (names in properties, no repeats),
--              additionalProperties — required, and false
--     array    items (required), minItems, maxItems, uniqueItems
--     string   const | enum (not both), minLength, maxLength, pattern (one
--              of the whitelisted patterns, which mean the same in ECMA-262,
--              Python and PostgreSQL regular expressions)
--     integer, number   minimum, maximum, exclusiveMinimum, exclusiveMaximum
--     boolean  const
--   "null" is not a type: no document may hold a null anywhere.

CREATE OR REPLACE FUNCTION public.rule_terms_resolve(p_root jsonb, p_node jsonb) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT CASE WHEN p_node ? '$ref' THEN p_root #> ARRAY['$defs', substr(p_node ->> '$ref', 9)] ELSE p_node END
$$;
COMMENT ON FUNCTION public.rule_terms_resolve(jsonb, jsonb) IS
    'v5.4.2-17. A schema node with a $ref ("#/$defs/<name>") resolved to its definition; any other node as it is.';

-- The discriminator of a oneOf: the one property every branch requires with
-- a string const. NULL when there is none or more than one.
CREATE OR REPLACE FUNCTION public.rule_terms_discriminator(p_root jsonb, p_union jsonb) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_branches jsonb := p_union -> 'oneOf';
    v_names text[];
BEGIN
    IF jsonb_typeof(v_branches) IS DISTINCT FROM 'array' OR jsonb_array_length(v_branches) = 0 THEN
        RETURN NULL;
    END IF;
    SELECT array_agg(k ORDER BY k) INTO v_names
      FROM (SELECT k
              FROM jsonb_array_elements(v_branches) b,
                   LATERAL (SELECT public.rule_terms_resolve(p_root, b) AS s) r,
                   LATERAL jsonb_object_keys(CASE WHEN jsonb_typeof(r.s -> 'properties') = 'object' THEN r.s -> 'properties' ELSE '{}'::jsonb END) k
             WHERE jsonb_typeof(r.s #> ARRAY['properties', k, 'const']) = 'string'
               AND jsonb_typeof(r.s -> 'required') = 'array'
               AND (r.s -> 'required') ? k
             GROUP BY k
            HAVING count(*) = jsonb_array_length(v_branches)) x;
    IF cardinality(v_names) = 1 THEN
        RETURN v_names[1];
    END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.rule_terms_discriminator(jsonb, jsonb) IS
    'v5.4.2-17. The discriminator of a oneOf union: the single property every branch requires with a string const. NULL when no property, or more than one, qualifies — rule_terms_schema_errors refuses such a union.';

-- A non-negative integer keyword value.
CREATE OR REPLACE FUNCTION public.rule_terms_is_count(p_value jsonb) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT jsonb_typeof(p_value) = 'number'
       AND (p_value #>> '{}')::numeric = trunc((p_value #>> '{}')::numeric)
       AND (p_value #>> '{}')::numeric >= 0
$$;

CREATE OR REPLACE FUNCTION public.rule_terms_schema_node_errors(p_root jsonb, p_node jsonb, p_path text, p_is_root boolean)
    RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    c_annotations CONSTANT text[] := ARRAY['title', 'description', '$comment'];
    c_root_only   CONSTANT text[] := ARRAY['$schema', '$id', '$defs'];
    c_types       CONSTANT text[] := ARRAY['object', 'array', 'string', 'integer', 'number', 'boolean'];
    -- Patterns whose meaning is the same in ECMA-262 (JSON Schema), Python re
    -- (the CI cross-check) and PostgreSQL ARE: "contains an ASCII letter or
    -- digit" (memory: blank checks whitelist alnum) and "a code".
    c_patterns    CONSTANT text[] := ARRAY['[A-Za-z0-9]', '^[a-z][a-z0-9_]*$'];
    v_err      text[] := '{}';
    v_allowed  text[];
    v_type     text;
    v_kw       text;
    v_k        text;
    v_b        jsonb;
    v_target   jsonb;
    v_i        integer;
    v_disc     text;
BEGIN
    IF jsonb_typeof(p_node) IS DISTINCT FROM 'object' THEN
        RETURN ARRAY[p_path || ': a schema must be an object'];
    END IF;
    FOREACH v_kw IN ARRAY c_annotations LOOP
        IF p_node ? v_kw AND jsonb_typeof(p_node -> v_kw) <> 'string' THEN
            v_err := v_err || (p_path || ': ' || v_kw || ' must be a string');
        END IF;
    END LOOP;

    IF p_node ? '$ref' THEN
        v_allowed := c_annotations || ARRAY['$ref'];
    ELSIF p_node ? 'oneOf' THEN
        v_allowed := c_annotations || ARRAY['oneOf'];
    ELSE
        v_type := CASE WHEN jsonb_typeof(p_node -> 'type') = 'string' THEN p_node ->> 'type' END;
        IF v_type IS NULL OR NOT v_type = ANY (c_types) THEN
            v_err := v_err || (p_path || ': "type" is required and must be one of object, array, string, integer, number, boolean');
        END IF;
        v_allowed := c_annotations || ARRAY['type'] || CASE v_type
            WHEN 'object'  THEN ARRAY['properties', 'required', 'additionalProperties']
            WHEN 'array'   THEN ARRAY['items', 'minItems', 'maxItems', 'uniqueItems']
            WHEN 'string'  THEN ARRAY['const', 'enum', 'minLength', 'maxLength', 'pattern']
            WHEN 'integer' THEN ARRAY['minimum', 'maximum', 'exclusiveMinimum', 'exclusiveMaximum']
            WHEN 'number'  THEN ARRAY['minimum', 'maximum', 'exclusiveMinimum', 'exclusiveMaximum']
            WHEN 'boolean' THEN ARRAY['const']
            ELSE ARRAY[]::text[] END;
    END IF;
    IF p_is_root THEN
        v_allowed := v_allowed || c_root_only;
    END IF;
    FOR v_kw IN SELECT k FROM jsonb_object_keys(p_node) k ORDER BY k LOOP
        IF NOT v_kw = ANY (v_allowed) THEN
            v_err := v_err || (p_path || ': keyword "' || v_kw || '" is not supported here — the validator would not enforce it');
        END IF;
    END LOOP;

    -- A reference.
    IF p_node ? '$ref' THEN
        IF jsonb_typeof(p_node -> '$ref') <> 'string' OR (p_node ->> '$ref') !~ '^#/\$defs/[A-Za-z0-9_]+$' THEN
            v_err := v_err || (p_path || ': $ref must be "#/$defs/<name>"');
        ELSE
            v_target := p_root #> ARRAY['$defs', substr(p_node ->> '$ref', 9)];
            IF v_target IS NULL THEN
                v_err := v_err || (p_path || ': $ref ' || (p_node ->> '$ref') || ' names no definition');
            ELSIF jsonb_typeof(v_target) = 'object' AND v_target ? '$ref' THEN
                v_err := v_err || (p_path || ': $ref ' || (p_node ->> '$ref') || ' names another reference — chains are refused');
            END IF;
        END IF;
        RETURN v_err;
    END IF;

    -- A union.
    IF p_node ? 'oneOf' THEN
        IF jsonb_typeof(p_node -> 'oneOf') <> 'array' OR jsonb_array_length(p_node -> 'oneOf') < 2 THEN
            RETURN v_err || (p_path || ': oneOf must be an array of at least two schemas');
        END IF;
        v_i := 0;
        FOR v_b IN SELECT e FROM jsonb_array_elements(p_node -> 'oneOf') e LOOP
            IF jsonb_typeof(v_b) = 'object' AND v_b ? '$ref' THEN
                v_err := v_err || public.rule_terms_schema_node_errors(p_root, v_b, p_path || '/oneOf/' || v_i, false);
                v_target := public.rule_terms_resolve(p_root, v_b);
            ELSE
                v_err := v_err || public.rule_terms_schema_node_errors(p_root, v_b, p_path || '/oneOf/' || v_i, false);
                v_target := v_b;
            END IF;
            IF v_target IS NOT NULL AND (jsonb_typeof(v_target) <> 'object' OR v_target ->> 'type' IS DISTINCT FROM 'object') THEN
                v_err := v_err || (p_path || '/oneOf/' || v_i || ': a union branch must be an object schema');
            END IF;
            v_i := v_i + 1;
        END LOOP;
        v_disc := public.rule_terms_discriminator(p_root, p_node);
        IF v_disc IS NULL THEN
            v_err := v_err || (p_path || ': a oneOf needs exactly one property that every branch requires with a string const');
        ELSIF (SELECT count(DISTINCT public.rule_terms_resolve(p_root, b) #>> ARRAY['properties', v_disc, 'const'])
                 FROM jsonb_array_elements(p_node -> 'oneOf') b) <> jsonb_array_length(p_node -> 'oneOf') THEN
            v_err := v_err || (p_path || ': the oneOf branches repeat a value of "' || v_disc || '"');
        END IF;
        RETURN v_err;
    END IF;

    -- A typed schema.
    CASE v_type
    WHEN 'object' THEN
        IF NOT (p_node ? 'additionalProperties') OR p_node -> 'additionalProperties' <> 'false'::jsonb THEN
            v_err := v_err || (p_path || ': an object schema must set "additionalProperties": false — unknown keys are refused');
        END IF;
        IF p_node ? 'properties' THEN
            IF jsonb_typeof(p_node -> 'properties') <> 'object' THEN
                v_err := v_err || (p_path || ': properties must be an object');
            ELSE
                FOR v_k IN SELECT k FROM jsonb_object_keys(p_node -> 'properties') k ORDER BY k LOOP
                    v_err := v_err || public.rule_terms_schema_node_errors(p_root, p_node -> 'properties' -> v_k,
                                          public.rule_terms_pointer(p_path || '/properties', v_k), false);
                END LOOP;
            END IF;
        END IF;
        IF p_node ? 'required' THEN
            IF jsonb_typeof(p_node -> 'required') <> 'array'
               OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_node -> 'required') e WHERE jsonb_typeof(e) <> 'string') THEN
                v_err := v_err || (p_path || ': required must be an array of property names');
            ELSIF (SELECT count(DISTINCT e) FROM jsonb_array_elements(p_node -> 'required') e) <> jsonb_array_length(p_node -> 'required') THEN
                v_err := v_err || (p_path || ': required repeats a name');
            ELSE
                FOR v_k IN SELECT e FROM jsonb_array_elements_text(p_node -> 'required') e LOOP
                    IF NOT coalesce(p_node -> 'properties', '{}'::jsonb) ? v_k THEN
                        v_err := v_err || (p_path || ': required names "' || v_k || '", which properties does not define');
                    END IF;
                END LOOP;
            END IF;
        END IF;
        -- A strategy names its version (inventory V5; review r1, Fable). Any
        -- object schema with a "strategy" property — a branch of a union, or
        -- a lone strategy with nothing to choose between (review r4, Codex
        -- B2) — requires "version", a bounded integer (1 <= minimum <=
        -- maximum), so a row says which frozen behaviour it was written for.
        -- A range, not one value (review r2, Opus): a strategy's v2 joins the
        -- range in the same terms version, as v2 §11 versions strategies
        -- independently of documents.
        IF jsonb_typeof(p_node -> 'properties') = 'object' AND (p_node -> 'properties') ? 'strategy' THEN
            v_target := public.rule_terms_resolve(p_root, p_node #> '{properties,version}');
            IF NOT (coalesce(p_node -> 'required', '[]'::jsonb) ? 'version')
               OR v_target ->> 'type' IS DISTINCT FROM 'integer'
               OR jsonb_typeof(v_target -> 'minimum') IS DISTINCT FROM 'number'
               OR jsonb_typeof(v_target -> 'maximum') IS DISTINCT FROM 'number'
               OR (v_target ->> 'minimum')::numeric <> trunc((v_target ->> 'minimum')::numeric)
               OR (v_target ->> 'maximum')::numeric <> trunc((v_target ->> 'maximum')::numeric)
               OR (v_target ->> 'minimum')::numeric < 1
               OR (v_target ->> 'minimum')::numeric > (v_target ->> 'maximum')::numeric THEN
                v_err := v_err || (p_path || ': strategy "' || coalesce(public.rule_terms_resolve(p_root, p_node #> '{properties,strategy}') ->> 'const', '?')
                                   || '" must require "version", an integer with 1 <= minimum <= maximum');
            END IF;
        END IF;
    WHEN 'array' THEN
        IF NOT p_node ? 'items' THEN
            v_err := v_err || (p_path || ': an array schema must define items');
        ELSE
            v_err := v_err || public.rule_terms_schema_node_errors(p_root, p_node -> 'items', p_path || '/items', false);
        END IF;
        FOREACH v_kw IN ARRAY ARRAY['minItems', 'maxItems'] LOOP
            IF p_node ? v_kw AND NOT public.rule_terms_is_count(p_node -> v_kw) THEN
                v_err := v_err || (p_path || ': ' || v_kw || ' must be a non-negative integer');
            END IF;
        END LOOP;
        IF p_node ? 'minItems' AND p_node ? 'maxItems' AND public.rule_terms_is_count(p_node -> 'minItems')
           AND public.rule_terms_is_count(p_node -> 'maxItems')
           AND (p_node ->> 'minItems')::numeric > (p_node ->> 'maxItems')::numeric THEN
            v_err := v_err || (p_path || ': minItems exceeds maxItems');
        END IF;
        IF p_node ? 'uniqueItems' AND jsonb_typeof(p_node -> 'uniqueItems') <> 'boolean' THEN
            v_err := v_err || (p_path || ': uniqueItems must be a boolean');
        END IF;
    WHEN 'string' THEN
        IF p_node ? 'const' AND p_node ? 'enum' THEN
            v_err := v_err || (p_path || ': const and enum together');
        END IF;
        IF p_node ? 'const' AND jsonb_typeof(p_node -> 'const') <> 'string' THEN
            v_err := v_err || (p_path || ': a string const must be a string');
        END IF;
        IF p_node ? 'enum' AND (jsonb_typeof(p_node -> 'enum') <> 'array' OR jsonb_array_length(p_node -> 'enum') = 0
               OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_node -> 'enum') e WHERE jsonb_typeof(e) <> 'string')
               OR (SELECT count(DISTINCT e) FROM jsonb_array_elements(p_node -> 'enum') e) <> jsonb_array_length(p_node -> 'enum')) THEN
            v_err := v_err || (p_path || ': enum must be a non-empty array of distinct strings');
        END IF;
        FOREACH v_kw IN ARRAY ARRAY['minLength', 'maxLength'] LOOP
            IF p_node ? v_kw AND NOT public.rule_terms_is_count(p_node -> v_kw) THEN
                v_err := v_err || (p_path || ': ' || v_kw || ' must be a non-negative integer');
            END IF;
        END LOOP;
        IF p_node ? 'pattern' AND (jsonb_typeof(p_node -> 'pattern') <> 'string' OR NOT (p_node ->> 'pattern') = ANY (c_patterns)) THEN
            v_err := v_err || (p_path || ': pattern must be one of ' || array_to_string(c_patterns, ', ') || ' — others may mean different things to different validators');
        END IF;
    WHEN 'integer', 'number' THEN
        FOREACH v_kw IN ARRAY ARRAY['minimum', 'maximum', 'exclusiveMinimum', 'exclusiveMaximum'] LOOP
            IF p_node ? v_kw AND jsonb_typeof(p_node -> v_kw) <> 'number' THEN
                v_err := v_err || (p_path || ': ' || v_kw || ' must be a number');
            END IF;
        END LOOP;
    WHEN 'boolean' THEN
        IF p_node ? 'const' AND jsonb_typeof(p_node -> 'const') <> 'boolean' THEN
            v_err := v_err || (p_path || ': a boolean const must be a boolean');
        END IF;
    ELSE
        NULL;
    END CASE;
    RETURN v_err;
END;
$$;
COMMENT ON FUNCTION public.rule_terms_schema_node_errors(jsonb, jsonb, text, boolean) IS
    'v5.4.2-17 (inventory V9). The reasons a schema node is outside the subset rule_terms_errors enforces, recursively; empty when it is inside. Called by rule_terms_schema_errors.';

CREATE OR REPLACE FUNCTION public.rule_terms_schema_errors(p_schema jsonb) RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_err text[] := '{}';
    v_k   text;
BEGIN
    IF jsonb_typeof(p_schema) IS DISTINCT FROM 'object' THEN
        RETURN ARRAY[': a schema must be a JSON object'];
    END IF;
    IF p_schema ->> '$schema' IS DISTINCT FROM 'https://json-schema.org/draft/2020-12/schema' THEN
        v_err := v_err || ': "$schema" must be "https://json-schema.org/draft/2020-12/schema"'::text;
    END IF;
    IF p_schema ? '$id' AND jsonb_typeof(p_schema -> '$id') <> 'string' THEN
        v_err := v_err || ': "$id" must be a string'::text;
    END IF;
    IF p_schema ? '$ref' THEN
        v_err := v_err || ': the root may not be a reference'::text;
    END IF;
    IF NOT (p_schema ? 'oneOf') AND p_schema ->> 'type' IS DISTINCT FROM 'object' THEN
        v_err := v_err || ': the root must be an object schema or a oneOf of object schemas'::text;
    END IF;
    IF p_schema ? '$defs' THEN
        IF jsonb_typeof(p_schema -> '$defs') <> 'object' THEN
            v_err := v_err || ': "$defs" must be an object'::text;
        ELSE
            FOR v_k IN SELECT k FROM jsonb_object_keys(p_schema -> '$defs') k ORDER BY k LOOP
                IF v_k !~ '^[A-Za-z0-9_]+$' THEN
                    v_err := v_err || (public.rule_terms_pointer('/$defs', v_k) || ': a definition name is letters, digits and _');
                END IF;
                IF jsonb_typeof(p_schema -> '$defs' -> v_k) = 'object' AND (p_schema -> '$defs' -> v_k) ? '$ref' THEN
                    v_err := v_err || (public.rule_terms_pointer('/$defs', v_k) || ': a definition may not be a reference');
                ELSE
                    v_err := v_err || public.rule_terms_schema_node_errors(p_schema, p_schema -> '$defs' -> v_k,
                                          public.rule_terms_pointer('/$defs', v_k), false);
                END IF;
            END LOOP;
        END IF;
    END IF;
    RETURN v_err || public.rule_terms_schema_node_errors(p_schema, p_schema, '', true);
END;
$$;
COMMENT ON FUNCTION public.rule_terms_schema_errors(jsonb) IS
    'v5.4.2-17 (inventory V9). The reasons a JSON Schema is outside the subset the validator enforces (see rule_terms_schema_node_errors), each prefixed by its JSON Pointer; empty when the schema is inside it. A term schema is registered only when this is empty.';

CREATE OR REPLACE FUNCTION public.rule_terms_node_errors(p_root jsonb, p_node jsonb, p_doc jsonb, p_path text, p_depth integer)
    RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    c_max_depth CONSTANT integer := 64;
    v_node   jsonb := public.rule_terms_resolve(p_root, p_node);
    v_err    text[] := '{}';
    v_disc   text;
    v_value  text;
    v_branch jsonb;
    v_k      text;
    v_e      jsonb;
    v_i      integer;
    v_n      numeric;
    v_len    integer;
    v_type   text := jsonb_typeof(p_doc);
BEGIN
    IF p_depth > c_max_depth THEN
        RETURN ARRAY[p_path || ': nested more than ' || c_max_depth || ' levels deep'];
    END IF;
    IF p_doc IS NULL OR v_type = 'null' THEN
        RETURN ARRAY[p_path || ': null is not allowed — say what the law says, or "unruled"'];
    END IF;

    IF v_node ? 'oneOf' THEN
        IF v_type <> 'object' THEN
            RETURN ARRAY[p_path || ': expected an object'];
        END IF;
        v_disc := public.rule_terms_discriminator(p_root, v_node);
        IF NOT p_doc ? v_disc THEN
            RETURN ARRAY[public.rule_terms_pointer(p_path, v_disc) || ': required'];
        END IF;
        IF jsonb_typeof(p_doc -> v_disc) <> 'string' THEN
            RETURN ARRAY[public.rule_terms_pointer(p_path, v_disc) || ': expected a string'];
        END IF;
        v_value := p_doc ->> v_disc;
        SELECT b INTO v_branch
          FROM jsonb_array_elements(v_node -> 'oneOf') b
         WHERE public.rule_terms_resolve(p_root, b) #>> ARRAY['properties', v_disc, 'const'] = v_value;
        IF v_branch IS NULL THEN
            RETURN ARRAY[public.rule_terms_pointer(p_path, v_disc) || ': "' || v_value || '" is not one of '
                         || (SELECT string_agg(public.rule_terms_resolve(p_root, b) #>> ARRAY['properties', v_disc, 'const'], ', ' ORDER BY 1)
                               FROM jsonb_array_elements(v_node -> 'oneOf') b)];
        END IF;
        -- The same document node, so the same depth (review r2, Fable, Codex):
        -- depth counts document levels, as the reference check does. A branch
        -- is an object schema, so this cannot recurse without descending.
        RETURN public.rule_terms_node_errors(p_root, v_branch, p_doc, p_path, p_depth);
    END IF;

    CASE v_node ->> 'type'
    WHEN 'object' THEN
        IF v_type <> 'object' THEN
            RETURN ARRAY[p_path || ': expected an object'];
        END IF;
        FOR v_k IN SELECT e FROM jsonb_array_elements_text(coalesce(v_node -> 'required', '[]'::jsonb)) e ORDER BY e LOOP
            IF NOT p_doc ? v_k THEN
                v_err := v_err || (public.rule_terms_pointer(p_path, v_k) || ': required');
            END IF;
        END LOOP;
        FOR v_k IN SELECT k FROM jsonb_object_keys(p_doc) k ORDER BY k LOOP
            IF NOT coalesce(v_node -> 'properties', '{}'::jsonb) ? v_k THEN
                v_err := v_err || (public.rule_terms_pointer(p_path, v_k) || ': unknown key');
            ELSE
                v_err := v_err || public.rule_terms_node_errors(p_root, v_node -> 'properties' -> v_k, p_doc -> v_k,
                                                                public.rule_terms_pointer(p_path, v_k), p_depth + 1);
            END IF;
        END LOOP;
    WHEN 'array' THEN
        IF v_type <> 'array' THEN
            RETURN ARRAY[p_path || ': expected an array'];
        END IF;
        v_len := jsonb_array_length(p_doc);
        IF v_node ? 'minItems' AND v_len < (v_node ->> 'minItems')::numeric THEN
            v_err := v_err || (p_path || ': at least ' || (v_node ->> 'minItems') || ' items');
        END IF;
        IF v_node ? 'maxItems' AND v_len > (v_node ->> 'maxItems')::numeric THEN
            v_err := v_err || (p_path || ': at most ' || (v_node ->> 'maxItems') || ' items');
        END IF;
        IF (v_node -> 'uniqueItems') = 'true'::jsonb
           AND (SELECT count(DISTINCT e) FROM jsonb_array_elements(p_doc) e) <> v_len THEN
            v_err := v_err || (p_path || ': items must be unique');
        END IF;
        v_i := 0;
        FOR v_e IN SELECT e FROM jsonb_array_elements(p_doc) e LOOP
            v_err := v_err || public.rule_terms_node_errors(p_root, v_node -> 'items', v_e, p_path || '/' || v_i, p_depth + 1);
            v_i := v_i + 1;
        END LOOP;
    WHEN 'string' THEN
        IF v_type <> 'string' THEN
            RETURN ARRAY[p_path || ': expected a string'];
        END IF;
        v_value := p_doc #>> '{}';
        IF v_node ? 'const' AND v_value IS DISTINCT FROM v_node ->> 'const' THEN
            v_err := v_err || (p_path || ': must be "' || (v_node ->> 'const') || '"');
        END IF;
        IF v_node ? 'enum' AND NOT (v_node -> 'enum') ? v_value THEN
            v_err := v_err || (p_path || ': "' || v_value || '" is not one of '
                               || (SELECT string_agg(e, ', ' ORDER BY e) FROM jsonb_array_elements_text(v_node -> 'enum') e));
        END IF;
        IF v_node ? 'minLength' AND char_length(v_value) < (v_node ->> 'minLength')::numeric THEN
            v_err := v_err || (p_path || ': at least ' || (v_node ->> 'minLength') || ' characters');
        END IF;
        IF v_node ? 'maxLength' AND char_length(v_value) > (v_node ->> 'maxLength')::numeric THEN
            v_err := v_err || (p_path || ': at most ' || (v_node ->> 'maxLength') || ' characters');
        END IF;
        IF v_node ? 'pattern' AND v_value !~ (v_node ->> 'pattern') THEN
            v_err := v_err || (p_path || ': does not match ' || (v_node ->> 'pattern'));
        END IF;
    WHEN 'integer', 'number' THEN
        IF v_type <> 'number' THEN
            RETURN ARRAY[p_path || ': expected a number'];
        END IF;
        v_n := (p_doc #>> '{}')::numeric;
        IF v_node ->> 'type' = 'integer' AND v_n <> trunc(v_n) THEN
            v_err := v_err || (p_path || ': expected an integer');
        END IF;
        IF v_node ? 'minimum' AND v_n < (v_node ->> 'minimum')::numeric THEN
            v_err := v_err || (p_path || ': must be at least ' || (v_node ->> 'minimum'));
        END IF;
        IF v_node ? 'maximum' AND v_n > (v_node ->> 'maximum')::numeric THEN
            v_err := v_err || (p_path || ': must be at most ' || (v_node ->> 'maximum'));
        END IF;
        IF v_node ? 'exclusiveMinimum' AND v_n <= (v_node ->> 'exclusiveMinimum')::numeric THEN
            v_err := v_err || (p_path || ': must be greater than ' || (v_node ->> 'exclusiveMinimum'));
        END IF;
        IF v_node ? 'exclusiveMaximum' AND v_n >= (v_node ->> 'exclusiveMaximum')::numeric THEN
            v_err := v_err || (p_path || ': must be less than ' || (v_node ->> 'exclusiveMaximum'));
        END IF;
    WHEN 'boolean' THEN
        IF v_type <> 'boolean' THEN
            RETURN ARRAY[p_path || ': expected a boolean'];
        END IF;
        IF v_node ? 'const' AND p_doc <> v_node -> 'const' THEN
            v_err := v_err || (p_path || ': must be ' || (v_node ->> 'const'));
        END IF;
    ELSE
        -- Unreachable for a registered schema (rule_terms_schema_errors).
        RETURN ARRAY[p_path || ': the schema node has no type the validator knows'];
    END CASE;
    RETURN v_err;
END;
$$;
COMMENT ON FUNCTION public.rule_terms_node_errors(jsonb, jsonb, jsonb, text, integer) IS
    'v5.4.2-17. The reasons a document node fails its schema node, recursively, each prefixed by its JSON Pointer. Called by rule_terms_errors; assumes a schema rule_terms_schema_errors accepted.';

CREATE OR REPLACE FUNCTION public.rule_terms_errors(p_schema jsonb, p_doc jsonb, p_component_ids boolean DEFAULT true) RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_err text[];
    v_dup text;
    v_bad text;
BEGIN
    IF p_schema IS NULL OR p_doc IS NULL THEN
        RETURN ARRAY[': a schema and a document are both required'];
    END IF;
    v_err := public.rule_terms_node_errors(p_schema, p_schema, p_doc, '', 0);
    -- Fixed rule: numbers canonical (see rule_terms_number_canonical).
    SELECT string_agg(DISTINCT v::text, ', ') INTO v_bad
      FROM jsonb_path_query(p_doc, 'strict $.**') v
     WHERE jsonb_typeof(v) = 'number' AND NOT public.rule_terms_number_canonical(v);
    IF v_bad IS NOT NULL THEN
        v_err := v_err || (': numbers must be written canonically, without trailing fractional zeros: ' || v_bad);
    END IF;
    -- Fixed rule: no control character (U+0001-U+001F, U+007F) in any string
    -- or key (review r1, all three): a newline is where Python's "$" and
    -- PostgreSQL's part company, and nothing the law says needs one.
    SELECT string_agg(DISTINCT to_jsonb(v #>> '{}')::text, ', ') INTO v_bad
      FROM (SELECT v FROM jsonb_path_query(p_doc, 'strict $.**') v WHERE jsonb_typeof(v) = 'string'
            UNION ALL
            SELECT to_jsonb(k) FROM jsonb_path_query(p_doc, 'strict $.** ? (@.type() == "object").keyvalue().key') k(k)) x(v)
     WHERE (v #>> '{}') ~ ('[' || chr(1) || '-' || chr(31) || chr(127) || ']');
    IF v_bad IS NOT NULL THEN
        v_err := v_err || (': strings and keys hold no control characters (newline, tab, …): ' || v_bad);
    END IF;
    IF NOT p_component_ids THEN
        RETURN v_err;
    END IF;
    -- Fixed rule: component ids unique within the document (v2 §3: a record
    -- names the part that governed by its id, never by its position).
    -- Inputs documents are exempt: an "id" there is whatever the core read.
    SELECT string_agg(DISTINCT i, ', ' ORDER BY i) INTO v_dup
      FROM (SELECT v #>> '{}' AS i
              FROM jsonb_path_query(p_doc, 'strict $.**.id') v
             WHERE jsonb_typeof(v) = 'string'
             GROUP BY v #>> '{}'
            HAVING count(*) > 1) d;
    IF v_dup IS NOT NULL THEN
        v_err := v_err || (': component ids must be unique in a document: ' || v_dup || ' repeated');
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_path_query(p_doc, 'strict $.**.id') v WHERE jsonb_typeof(v) <> 'string') THEN
        v_err := v_err || ': a component id ("id") must be a string'::text;
    END IF;
    RETURN v_err;
END;
$$;
COMMENT ON FUNCTION public.rule_terms_errors(jsonb, jsonb, boolean) IS
    'v5.4.2-17 (rule-terms v2 §5; inventory V3-V5). The reasons a document fails a registered schema, each prefixed by its JSON Pointer ("" is the root); empty when it is valid. IMMUTABLE and pure: the schema is an argument, and a registered schema is never edited. Also enforces fixed rules: no nulls anywhere; numbers written canonically; no control characters in a string or key; nesting at most 64 deep; and, unless p_component_ids is false (an inputs document), component ids ("id") unique strings.';

-- A document as written, to jsonb — refusing duplicate keys at any depth
-- first, which a cast to jsonb would silently resolve to the last (v2 §5;
-- inventory U2). Every rule row, law or tariff, enters through this.
CREATE OR REPLACE FUNCTION public.rule_terms_parse(p_text text) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_doc jsonb;
BEGIN
    IF p_text IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'a rule document is required, as JSON text (v5.4.2-17)',
            ERRCODE = 'not_null_violation';
    END IF;
    BEGIN
        v_doc := p_text::jsonb;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION USING
            MESSAGE = format('a rule document must be JSON that PostgreSQL can store: %s (v5.4.2-17)', SQLERRM),
            ERRCODE = 'invalid_text_representation';
    END;
    IF jsonb_typeof(v_doc) <> 'object' THEN
        RAISE EXCEPTION USING
            MESSAGE = 'a rule document must be a JSON object (v5.4.2-17)',
            ERRCODE = 'invalid_text_representation';
    END IF;
    IF NOT (p_text IS JSON OBJECT WITH UNIQUE KEYS) THEN
        RAISE EXCEPTION USING
            MESSAGE = 'a rule document repeats a key in one of its objects — as jsonb only the last would survive, silently (v5.4.2-17)',
            ERRCODE = 'duplicate_json_object_key_value';
    END IF;
    RETURN v_doc;
END;
$$;
COMMENT ON FUNCTION public.rule_terms_parse(text) IS
    'v5.4.2-17 (inventory U2). JSON text to jsonb, refusing anything but an object and any object (at any depth, inside arrays too) that repeats a key. Every rule row''s document enters through its terms_source column and this function.';


-- ----------------------------------------------------------------------------
-- 4. The registry: term schemas and their facets (inventory V1, V8, F1-F3)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.rule_term_schemas (
    terms_kind        text NOT NULL,
    terms_version     integer NOT NULL,
    rule_role         text NOT NULL,
    json_schema       jsonb NOT NULL,
    schema_hash       text NOT NULL,
    accepts_new_rows  boolean DEFAULT true NOT NULL,
    introduced_on     date NOT NULL,
    description       text NOT NULL,
    source_note       text NOT NULL,
    created_at        timestamp with time zone DEFAULT now() NOT NULL,
    recorded_txid     bigint DEFAULT txid_current() NOT NULL,
    frozen_at         timestamp with time zone,
    frozen_by         text,
    CONSTRAINT rule_term_schemas_pkey PRIMARY KEY (terms_kind, terms_version),
    CONSTRAINT rule_term_schemas_kind_check CHECK ((terms_kind ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT rule_term_schemas_version_check CHECK ((terms_version >= 1)),
    -- law: a law row's content; tariff: a utility's own rule row; inputs:
    -- what the core read for a record it wrote (C4).
    CONSTRAINT rule_term_schemas_role_check CHECK ((rule_role = ANY (ARRAY['law'::text, 'tariff'::text, 'inputs'::text]))),
    CONSTRAINT rule_term_schemas_hash_check CHECK ((schema_hash ~ '^sha256:[0-9a-f]{64}$'::text)),
    CONSTRAINT rule_term_schemas_frozen_check
        CHECK (((accepts_new_rows AND (frozen_at IS NULL) AND (frozen_by IS NULL))
             OR ((NOT accepts_new_rows) AND (frozen_at IS NOT NULL) AND (frozen_by ~ '[[:alnum:]]'::text)))),
    CONSTRAINT rule_term_schemas_text_check CHECK (((description ~ '[[:alnum:]]'::text) AND (source_note ~ '[[:alnum:]]'::text)))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.rule_term_schemas FROM tally_app, tally_core;
GRANT SELECT ON public.rule_term_schemas TO tally_app, tally_core;
COMMENT ON TABLE public.rule_term_schemas IS
    'v5.4.2-17 (rule-terms v2 §5, §11; inventory V1, V8, V9). One row per (kind, version) of a rule document: the JSON Schema (2020-12, in the subset rule_terms_errors enforces) every document of it must satisfy, its hash (stamped), and its role — law (a law row''s content), tariff (a utility''s own rule row), or inputs (what the core read for a record it wrote). A law kind''s root is a oneOf on "governs" that always admits {"governs": "delegated_to_utility", "citation": …}: the law leaves the matter to the utility, which is not the same as no law (v2 §3, places inventory finding 1). Versions of a kind are numbered 1, 2, … and share a role; a new version is for a breaking change only (v2 §11). Never edited — the one change is a stamped, one-way freeze (accepts_new_rows false), after which no new row may use the version; rows already using it keep it forever. Never deleted. Written only by reviewed platform migrations; the CI cross-check (tools/law) runs a standard validator over the same schema.';

CREATE OR REPLACE FUNCTION public.enforce_rule_term_schema() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    c_frozen_cols CONSTANT text[] := ARRAY['accepts_new_rows', 'frozen_at', 'frozen_by'];
    v_err      text[];
    v_role     text;
    v_next     integer;
    v_branch   jsonb;
    v_found    boolean := false;
    v_core     jsonb;
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('term schema %s v%s is never deleted: rows may use it forever (v5.4.2-17)', OLD.terms_kind, OLD.terms_version),
            ERRCODE = 'restrict_violation';
    END IF;

    IF TG_OP = 'UPDATE' THEN
        -- The one edit: a freeze, once.
        -- Compared as text (review r2, Codex S3): 0 and 0.0 are equal jsonb but
        -- not the text the hash was taken over.
        IF NOT (OLD.accepts_new_rows AND NOT NEW.accepts_new_rows)
           OR (to_jsonb(NEW) - c_frozen_cols)::text IS DISTINCT FROM (to_jsonb(OLD) - c_frozen_cols)::text THEN
            RAISE EXCEPTION USING
                MESSAGE = format('term schema %s v%s is never edited; the one change is a freeze (accepts_new_rows true to false) (v5.4.2-17)', OLD.terms_kind, OLD.terms_version),
                ERRCODE = 'restrict_violation';
        END IF;
        PERFORM public.assert_rule_read_committed('freezing a term schema');
        PERFORM pg_advisory_xact_lock(public.rule_term_schema_lock_key(OLD.terms_kind, OLD.terms_version));
        NEW.frozen_at := now();
        NEW.frozen_by := session_user;
        RETURN NEW;
    END IF;

    -- INSERT.
    v_err := public.rule_terms_schema_errors(NEW.json_schema);
    IF cardinality(v_err) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('term schema %s v%s is outside the subset the validator enforces: %s (v5.4.2-17)',
                             NEW.terms_kind, NEW.terms_version, array_to_string(v_err[1:10], '; ')),
            ERRCODE = 'check_violation';
    END IF;
    SELECT max(terms_version) + 1, min(rule_role) INTO v_next, v_role
      FROM public.rule_term_schemas WHERE terms_kind = NEW.terms_kind;
    IF NEW.terms_version IS DISTINCT FROM coalesce(v_next, 1) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('term schema %s: the next version is %s, not %s (v5.4.2-17)', NEW.terms_kind, coalesce(v_next, 1), NEW.terms_version),
            ERRCODE = 'check_violation';
    END IF;
    IF v_role IS NOT NULL AND v_role <> NEW.rule_role THEN
        RAISE EXCEPTION USING
            MESSAGE = format('term schema %s is a %s kind; a version cannot change its role to %s (v5.4.2-17)', NEW.terms_kind, v_role, NEW.rule_role),
            ERRCODE = 'check_violation';
    END IF;
    -- A law kind admits "the law leaves this to the utility" (inventory V8):
    -- the root is a oneOf discriminated by "governs", and one branch is
    -- exactly {governs: "delegated_to_utility", citation} (a note optional).
    IF NEW.rule_role = 'law' THEN
        IF NOT (NEW.json_schema ? 'oneOf') OR public.rule_terms_discriminator(NEW.json_schema, NEW.json_schema) IS DISTINCT FROM 'governs' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('law kind %s: the root must be a oneOf discriminated by "governs" (v5.4.2-17)', NEW.terms_kind),
                ERRCODE = 'check_violation';
        END IF;
        FOR v_branch IN SELECT public.rule_terms_resolve(NEW.json_schema, b) FROM jsonb_array_elements(NEW.json_schema -> 'oneOf') b LOOP
            IF NOT (v_branch #>> '{properties,governs,const}') = ANY (ARRAY['law', 'delegated_to_utility']) THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('law kind %s: "governs" is "law" or "delegated_to_utility", not "%s" (v5.4.2-17)', NEW.terms_kind, v_branch #>> '{properties,governs,const}'),
                    ERRCODE = 'check_violation';
            END IF;
            IF v_branch #>> '{properties,governs,const}' = 'delegated_to_utility' THEN
                -- Exactly the standard document (review r4, Codex B1), so the
                -- branch can be satisfied: any other constraint on "governs"
                -- or "citation" (a maxLength of 1, say), a required "note",
                -- or an extra keyword could leave no document that validates.
                -- Annotations (title, description, $comment) do not change
                -- what validates.
                v_core := v_branch - 'title' - 'description' - '$comment';
                v_found := coalesce(
                           (v_core - 'required' - 'properties') = '{"type": "object", "additionalProperties": false}'::jsonb
                       AND (v_core -> 'required') @> '["citation", "governs"]'::jsonb
                       AND jsonb_array_length(v_core -> 'required') = 2
                       AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_core -> 'properties') k) <@ ARRAY['citation', 'governs', 'note']
                       AND (v_core #> '{properties,governs}') - 'title' - 'description' - '$comment'
                           = '{"type": "string", "const": "delegated_to_utility"}'::jsonb
                       AND (v_core #> '{properties,citation}') - 'title' - 'description' - '$comment'
                           = '{"type": "string", "pattern": "[A-Za-z0-9]"}'::jsonb
                       AND (NOT (v_core -> 'properties') ? 'note'
                            OR (v_core #> '{properties,note}') - 'title' - 'description' - '$comment'
                               = '{"type": "string", "pattern": "[A-Za-z0-9]"}'::jsonb), false);
            END IF;
        END LOOP;
        IF NOT v_found THEN
            RAISE EXCEPTION USING
                MESSAGE = format('law kind %s must admit {"governs": "delegated_to_utility", "citation": "…"} — the law leaving a matter to the utility is not the same as no law (v5.4.2-17)', NEW.terms_kind),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    NEW.schema_hash := 'sha256:' || encode(sha256(convert_to(NEW.json_schema::text, 'UTF8')), 'hex');
    NEW.accepts_new_rows := true;
    NEW.frozen_at := NULL;
    NEW.frozen_by := NULL;
    NEW.created_at := now();
    NEW.recorded_txid := txid_current();
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_rule_term_schema() IS
    'v5.4.2-17. BEFORE INSERT OR UPDATE OR DELETE on rule_term_schemas (ENABLE ALWAYS): a schema in the validator''s subset, the next version of its kind, the kind''s role, and for a law kind the delegated_to_utility document; the hash and stamps set here. The only edit is a freeze, once, under READ COMMITTED and the version''s lock. No delete.';

DROP TRIGGER IF EXISTS rule_term_schema_guard ON public.rule_term_schemas;
CREATE TRIGGER rule_term_schema_guard BEFORE INSERT OR UPDATE OR DELETE ON public.rule_term_schemas
    FOR EACH ROW EXECUTE FUNCTION public.enforce_rule_term_schema();
ALTER TABLE public.rule_term_schemas ENABLE ALWAYS TRIGGER rule_term_schema_guard;

CREATE OR REPLACE FUNCTION public.enforce_rule_registry_no_truncate() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    RAISE EXCEPTION USING
        MESSAGE = format('%s is never truncated: rule rows and records depend on it (v5.4.2-17)', TG_TABLE_NAME),
        ERRCODE = 'restrict_violation';
END;
$$;
DROP TRIGGER IF EXISTS no_truncate ON public.rule_term_schemas;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.rule_term_schemas
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_rule_registry_no_truncate();
ALTER TABLE public.rule_term_schemas ENABLE ALWAYS TRIGGER no_truncate;


CREATE TABLE IF NOT EXISTS public.rule_term_facets (
    terms_kind          text NOT NULL,
    terms_version       integer NOT NULL,
    facet_name          text NOT NULL,
    facet_type          text NOT NULL,
    json_path           text NOT NULL,
    vocabulary_table    text,
    vocabulary_column   text,
    vocabulary_scope    jsonb,
    description         text NOT NULL,
    created_at          timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT rule_term_facets_pkey PRIMARY KEY (terms_kind, terms_version, facet_name),
    CONSTRAINT rule_term_facets_schema_fkey FOREIGN KEY (terms_kind, terms_version)
        REFERENCES public.rule_term_schemas(terms_kind, terms_version),
    CONSTRAINT rule_term_facets_name_check CHECK ((facet_name ~ '^[a-z][a-z0-9_]*$'::text)),
    -- present: whether the path matches anything; text[]: every string it
    -- matches, distinct and sorted; text, integer, number, boolean: at most
    -- one (a number is what a tariff is compared with the law on: a cap, a
    -- ratio).
    CONSTRAINT rule_term_facets_type_check
        CHECK ((facet_type = ANY (ARRAY['text'::text, 'text[]'::text, 'integer'::text, 'number'::text, 'boolean'::text, 'present'::text]))),
    CONSTRAINT rule_term_facets_vocabulary_check
        CHECK ((((vocabulary_table IS NULL) AND (vocabulary_column IS NULL) AND (vocabulary_scope IS NULL))
             OR ((vocabulary_table IS NOT NULL) AND (vocabulary_column IS NOT NULL)
                 AND (facet_type = ANY (ARRAY['text'::text, 'text[]'::text]))
                 AND ((vocabulary_scope IS NULL) OR (jsonb_typeof(vocabulary_scope) = 'object'::text))))),
    CONSTRAINT rule_term_facets_text_check CHECK (((description ~ '[[:alnum:]]'::text) AND (json_path ~ '[[:alnum:]$]'::text)))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.rule_term_facets FROM tally_app, tally_core;
GRANT SELECT ON public.rule_term_facets TO tally_app, tally_core;
COMMENT ON TABLE public.rule_term_facets IS
    'v5.4.2-17 (rule-terms v2 §7; inventory F1-F3). The typed facets of a (kind, version): each a value the insert trigger derives from the document by a SQL/JSON path, into the rule table''s column of the same name, that no writer sets. Types: present (the path matches anything), text[] (every string it matches, distinct, sorted), text, integer, number, boolean (at most one match). A text or text[] facet may name a vocabulary table and code column its every code must exist in, scoped by vocabulary_scope ({"vocabulary column": "rule row column"}) — a waiver class of the row''s own state and service. Ordinary constraints and guards read facets, never the document. Declared in the schema row''s own transaction; never edited or deleted.';

CREATE OR REPLACE FUNCTION public.enforce_rule_term_facet() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_txid  bigint;
    v_path  jsonpath;
    v_cls   regclass;
    v_k     text;
BEGIN
    IF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('facet %s of %s v%s is never edited or deleted (v5.4.2-17)', OLD.facet_name, OLD.terms_kind, OLD.terms_version),
            ERRCODE = 'restrict_violation';
    END IF;
    SELECT recorded_txid INTO v_txid FROM public.rule_term_schemas
     WHERE terms_kind = NEW.terms_kind AND terms_version = NEW.terms_version;
    IF v_txid IS DISTINCT FROM txid_current() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('facet %s of %s v%s: facets are declared in their schema''s own transaction — a facet added later would be missing from rows already written (v5.4.2-17)', NEW.facet_name, NEW.terms_kind, NEW.terms_version),
            ERRCODE = 'check_violation';
    END IF;
    BEGIN
        v_path := NEW.json_path::jsonpath;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION USING
            MESSAGE = format('facet %s: %s is not a SQL/JSON path (v5.4.2-17)', NEW.facet_name, NEW.json_path),
            ERRCODE = 'check_violation';
    END;
    IF NEW.json_path ~* 'datetime' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('facet %s: a path may not use .datetime() — its result depends on the session''s time zone (v5.4.2-17)', NEW.facet_name),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.json_path ~* 'double' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('facet %s: a path may not use .double() — it rounds an exact number (v5.4.2-17)', NEW.facet_name),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.vocabulary_table IS NOT NULL THEN
        v_cls := to_regclass(NEW.vocabulary_table);
        IF v_cls IS NULL OR NOT EXISTS (SELECT 1 FROM pg_class c WHERE c.oid = v_cls AND c.relkind IN ('r', 'p')) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('facet %s: vocabulary %s is not a table (v5.4.2-17)', NEW.facet_name, NEW.vocabulary_table),
                ERRCODE = 'check_violation';
        END IF;
        NEW.vocabulary_table := v_cls::text;
        IF NOT EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = v_cls AND a.attname = NEW.vocabulary_column AND NOT a.attisdropped AND a.attnum > 0) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('facet %s: vocabulary %s has no column %s (v5.4.2-17)', NEW.facet_name, NEW.vocabulary_table, NEW.vocabulary_column),
                ERRCODE = 'check_violation';
        END IF;
        FOR v_k IN SELECT k FROM jsonb_object_keys(coalesce(NEW.vocabulary_scope, '{}'::jsonb)) k LOOP
            IF jsonb_typeof(NEW.vocabulary_scope -> v_k) <> 'string'
               OR NOT EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = v_cls AND a.attname = v_k AND NOT a.attisdropped AND a.attnum > 0) THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('facet %s: scope %s must map a column of %s to a rule-row column name (v5.4.2-17)', NEW.facet_name, v_k, NEW.vocabulary_table),
                    ERRCODE = 'check_violation';
            END IF;
        END LOOP;
    END IF;
    NEW.created_at := now();
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS rule_term_facet_guard ON public.rule_term_facets;
CREATE TRIGGER rule_term_facet_guard BEFORE INSERT OR UPDATE OR DELETE ON public.rule_term_facets
    FOR EACH ROW EXECUTE FUNCTION public.enforce_rule_term_facet();
ALTER TABLE public.rule_term_facets ENABLE ALWAYS TRIGGER rule_term_facet_guard;
DROP TRIGGER IF EXISTS no_truncate ON public.rule_term_facets;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.rule_term_facets
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_rule_registry_no_truncate();
ALTER TABLE public.rule_term_facets ENABLE ALWAYS TRIGGER no_truncate;

-- A document's facets, as a jsonb object {facet_name: value}.
CREATE OR REPLACE FUNCTION public.rule_terms_facets(p_kind text, p_version integer, p_terms jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    f        public.rule_term_facets%ROWTYPE;
    v_out    jsonb := '{}'::jsonb;
    v_m      jsonb;
    v_n      integer;
    v_value  jsonb;
BEGIN
    FOR f IN SELECT * FROM public.rule_term_facets
              WHERE terms_kind = p_kind AND terms_version = p_version ORDER BY facet_name LOOP
        v_m := jsonb_path_query_array(p_terms, f.json_path::jsonpath);
        v_n := jsonb_array_length(v_m);
        IF f.facet_type = 'present' THEN
            v_value := to_jsonb(v_n > 0);
        ELSIF f.facet_type = 'text[]' THEN
            IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE jsonb_typeof(e) <> 'string') THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('facet %s of %s v%s: path %s matched a value that is not a string (v5.4.2-17)', f.facet_name, p_kind, p_version, f.json_path),
                    ERRCODE = 'data_exception';
            END IF;
            v_value := coalesce((SELECT jsonb_agg(DISTINCT e ORDER BY e) FROM jsonb_array_elements(v_m) e), '[]'::jsonb);
        ELSE
            IF v_n > 1 THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('facet %s of %s v%s: path %s matched %s values; a %s facet takes at most one (v5.4.2-17)', f.facet_name, p_kind, p_version, f.json_path, v_n, f.facet_type),
                    ERRCODE = 'data_exception';
            END IF;
            v_value := CASE WHEN v_n = 1 THEN v_m -> 0 ELSE 'null'::jsonb END;
            IF v_n = 1 AND NOT (
                   (f.facet_type = 'text' AND jsonb_typeof(v_value) = 'string')
                OR (f.facet_type = 'boolean' AND jsonb_typeof(v_value) = 'boolean')
                OR (f.facet_type = 'number' AND jsonb_typeof(v_value) = 'number')
                OR (f.facet_type = 'integer' AND jsonb_typeof(v_value) = 'number'
                    AND (v_value #>> '{}')::numeric = trunc((v_value #>> '{}')::numeric))) THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('facet %s of %s v%s: path %s matched %s, not a %s (v5.4.2-17)', f.facet_name, p_kind, p_version, f.json_path, v_value, f.facet_type),
                    ERRCODE = 'data_exception';
            END IF;
        END IF;
        v_out := v_out || jsonb_build_object(f.facet_name, v_value);
    END LOOP;
    RETURN v_out;
END;
$$;
COMMENT ON FUNCTION public.rule_terms_facets(text, integer, jsonb) IS
    'v5.4.2-17 (inventory F1-F2). A document''s declared facets as {facet_name: value}. A path matching the wrong type or too many values raises — a schema and its facets that disagree are a registration defect, not data.';


-- ----------------------------------------------------------------------------
-- 5. Applicability spans (v2 §9; -16 R1; inventory T2)
-- ----------------------------------------------------------------------------
-- A law row binds a set of owner types, system kinds and commission-
-- jurisdiction statuses, each NULL for "every one". The exclusion must catch
-- "every owner type" against "municipal" for the same key and dates, which
-- = on text cannot. Each code therefore has an ordinal, a set becomes a
-- multirange of [ordinal, ordinal+1) and "every" becomes [0, ∞); the
-- exclusion tests overlap (&&). Ordinals are platform-held and never change;
-- "every" includes owner types and system kinds added later, which is what
-- a law that names none means.

CREATE TABLE IF NOT EXISTS public.rule_applicability_ordinals (
    dimension    text NOT NULL,
    code         text NOT NULL,
    ordinal      integer NOT NULL,
    created_at   timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT rule_applicability_ordinals_pkey PRIMARY KEY (dimension, code),
    CONSTRAINT rule_applicability_ordinals_ordinal_key UNIQUE (dimension, ordinal),
    CONSTRAINT rule_applicability_ordinals_dimension_check
        CHECK ((dimension = ANY (ARRAY['owner_type'::text, 'system_kind'::text]))),
    CONSTRAINT rule_applicability_ordinals_ordinal_check CHECK ((ordinal >= 0))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.rule_applicability_ordinals FROM tally_app, tally_core;
GRANT SELECT ON public.rule_applicability_ordinals TO tally_app, tally_core;
COMMENT ON TABLE public.rule_applicability_ordinals IS
    'v5.4.2-17 (inventory T2). A fixed ordinal for each owner type and system kind, so a law row''s set of them is a multirange and the no-overlap exclusion can compare sets — including "every one" (NULL) against a single one. A code must exist in its vocabulary (utility_owner_types, utility_system_kinds). Platform-held; never edited or deleted. A new owner type or system kind adds its ordinal in the same migration.';

CREATE OR REPLACE FUNCTION public.enforce_rule_applicability_ordinal() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('the %s ordinal of %s is never edited or deleted: law rows'' spans are built on it (v5.4.2-17)', OLD.dimension, OLD.code),
            ERRCODE = 'restrict_violation';
    END IF;
    IF (NEW.dimension = 'owner_type' AND NOT EXISTS (SELECT 1 FROM public.utility_owner_types WHERE owner_type = NEW.code))
       OR (NEW.dimension = 'system_kind' AND NOT EXISTS (SELECT 1 FROM public.utility_system_kinds WHERE system_kind = NEW.code)) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s %s is not in its vocabulary (v5.4.2-17)', NEW.dimension, NEW.code),
            ERRCODE = 'foreign_key_violation';
    END IF;
    NEW.created_at := now();
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS rule_applicability_ordinal_guard ON public.rule_applicability_ordinals;
CREATE TRIGGER rule_applicability_ordinal_guard BEFORE INSERT OR UPDATE OR DELETE ON public.rule_applicability_ordinals
    FOR EACH ROW EXECUTE FUNCTION public.enforce_rule_applicability_ordinal();
ALTER TABLE public.rule_applicability_ordinals ENABLE ALWAYS TRIGGER rule_applicability_ordinal_guard;
DROP TRIGGER IF EXISTS no_truncate ON public.rule_applicability_ordinals;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.rule_applicability_ordinals
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_rule_registry_no_truncate();
ALTER TABLE public.rule_applicability_ordinals ENABLE ALWAYS TRIGGER no_truncate;

-- Seed: every owner type and system kind -16 knows, in code order.
INSERT INTO public.rule_applicability_ordinals (dimension, code, ordinal)
SELECT 'owner_type', o.owner_type, (row_number() OVER (ORDER BY o.owner_type))::integer - 1
  FROM public.utility_owner_types o
 WHERE NOT EXISTS (SELECT 1 FROM public.rule_applicability_ordinals x WHERE x.dimension = 'owner_type')
 ORDER BY o.owner_type;
INSERT INTO public.rule_applicability_ordinals (dimension, code, ordinal)
SELECT 'system_kind', s.system_kind, (row_number() OVER (ORDER BY s.system_kind))::integer - 1
  FROM public.utility_system_kinds s
 WHERE NOT EXISTS (SELECT 1 FROM public.rule_applicability_ordinals x WHERE x.dimension = 'system_kind')
 ORDER BY s.system_kind;

-- A set of codes (NULL = every one) as a multirange of their ordinals.
-- Refuses an empty set, a repeated code and a code with no ordinal.
CREATE OR REPLACE FUNCTION public.rule_applicability_span(p_dimension text, p_codes text[]) RETURNS int4multirange
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_span    int4multirange;
    v_missing text;
BEGIN
    IF p_codes IS NULL THEN
        RETURN int4multirange(int4range(0, NULL));
    END IF;
    IF cardinality(p_codes) = 0 OR array_position(p_codes, NULL) IS NOT NULL
       OR (SELECT count(DISTINCT c) FROM unnest(p_codes) c) <> cardinality(p_codes) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('a set of %s codes is NULL (every one) or non-empty, without blanks or repeats: %s (v5.4.2-17)', p_dimension, p_codes),
            ERRCODE = 'check_violation';
    END IF;
    SELECT string_agg(c, ', ' ORDER BY c) INTO v_missing
      FROM unnest(p_codes) c
     WHERE NOT EXISTS (SELECT 1 FROM public.rule_applicability_ordinals o WHERE o.dimension = p_dimension AND o.code = c);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s %s: not a known code with an ordinal (v5.4.2-17)', p_dimension, v_missing),
            ERRCODE = 'foreign_key_violation';
    END IF;
    SELECT range_agg(int4range(o.ordinal, o.ordinal + 1)) INTO v_span
      FROM public.rule_applicability_ordinals o
     WHERE o.dimension = p_dimension AND o.code = ANY (p_codes);
    RETURN v_span;
END;
$$;
COMMENT ON FUNCTION public.rule_applicability_span(text, text[]) IS
    'v5.4.2-17 (inventory T2). The multirange of a set of owner types or system kinds (NULL = every one: [0, ∞)). Refuses an empty set, blanks, repeats and unknown codes.';

-- One code's ordinal, as the point a span must contain.
CREATE OR REPLACE FUNCTION public.rule_applicability_ordinal(p_dimension text, p_code text) RETURNS integer
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v integer;
BEGIN
    SELECT ordinal INTO v FROM public.rule_applicability_ordinals WHERE dimension = p_dimension AND code = p_code;
    IF v IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s %s has no ordinal (v5.4.2-17)', p_dimension, p_code),
            ERRCODE = 'no_data_found';
    END IF;
    RETURN v;
END;
$$;

-- Commission jurisdiction: false [0,1), true [1,2), NULL (either) [0,2).
CREATE OR REPLACE FUNCTION public.rule_jurisdiction_span(p_commission_jurisdiction boolean) RETURNS int4range
    LANGUAGE sql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT CASE p_commission_jurisdiction WHEN false THEN int4range(0, 1) WHEN true THEN int4range(1, 2) ELSE int4range(0, 2) END
$$;


-- ----------------------------------------------------------------------------
-- 6. The law- and tariff-table template (inventory T1-T6, U1, U3, U4)
-- ----------------------------------------------------------------------------
-- An area writes CREATE TABLE with the template columns below plus its own
-- key columns (NOT NULL) and facet columns, then calls rule_table_register().
-- Registration adds the shared parts, so no area re-implements them.
--
--   every rule table:  id uuid PK; state_code text; service_type text;
--                      effective_from date; effective_to date (NULL);
--                      terms_kind text; terms_version integer;
--                      terms_source text; terms jsonb; created_at
--                      timestamptz; recorded_txid bigint; closed_at
--                      timestamptz (NULL)
--   a law table adds:  owner_types text[]; system_kinds text[];
--                      commission_jurisdiction boolean — each NULL for
--                      every one; owner_span int4multirange; system_span
--                      int4multirange; jurisdiction_span int4range (written
--                      by the trigger); source_note text; closed_by text
--   a tariff table:    tenant_id uuid; system_kind text; tariff_reference
--                      text; created_by uuid; closed_by uuid
--
-- The document is written as JSON TEXT into terms_source; the insert trigger
-- parses it (refusing duplicate keys), validates it, and writes terms, the
-- facets and the spans. A writer cannot choose any of them.

CREATE TABLE IF NOT EXISTS public.rule_tables (
    table_name          regclass NOT NULL,
    rule_role           text NOT NULL,
    terms_kind          text NOT NULL,
    area_key            text[] NOT NULL,
    facet_columns       text[] NOT NULL,
    close_floor         regprocedure,
    insert_check        regprocedure,
    law_table           regclass,
    compare_function    regprocedure,
    adopts_legacy_rows  boolean NOT NULL,
    adoption_check      regprocedure,
    created_at          timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT rule_tables_pkey PRIMARY KEY (table_name),
    CONSTRAINT rule_tables_adoption_check CHECK ((adopts_legacy_rows = (adoption_check IS NOT NULL))),
    CONSTRAINT rule_tables_role_check CHECK ((rule_role = ANY (ARRAY['law'::text, 'tariff'::text]))),
    CONSTRAINT rule_tables_tariff_check
        CHECK ((((rule_role = 'law'::text) AND (law_table IS NULL) AND (compare_function IS NULL))
             OR ((rule_role = 'tariff'::text) AND ((law_table IS NULL) = (compare_function IS NULL)) AND (NOT adopts_legacy_rows)))),
    CONSTRAINT rule_tables_arrays_check
        CHECK (((array_position(area_key, NULL) IS NULL) AND (array_position(facet_columns, NULL) IS NULL)))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.rule_tables FROM tally_app, tally_core;
GRANT SELECT ON public.rule_tables TO tally_app, tally_core;
COMMENT ON TABLE public.rule_tables IS
    'v5.4.2-17 (inventory T1, U1). Every table on the rule-terms template: its role (law: platform-held, migration-written; tariff: the utility''s own rule rows, tenant-owned), the kind of document it holds, its own key columns, its facet columns, and its hooks — close_floor(uuid) RETURNS date (the latest date a citing record needs the row in force; a close must end after it), insert_check(jsonb) (an area predicate over the new row, raising), for a tariff table the law table and compare(tariff jsonb, law_rows jsonb) RETURNS text[] (the reasons the tariff is looser than the law), and for a table with pre-convention rows adoption_check(jsonb) (run only when an empty document is filled: it compares the document with the row''s old columns, and raises). Written only by rule_table_register(); never edited or deleted.';

CREATE OR REPLACE FUNCTION public.enforce_rule_table_registry() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('the registration of %s is never edited or deleted: its triggers read it (v5.4.2-17)', OLD.table_name),
            ERRCODE = 'restrict_violation';
    END IF;
    NEW.created_at := now();
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS rule_table_registry_guard ON public.rule_tables;
CREATE TRIGGER rule_table_registry_guard BEFORE INSERT OR UPDATE OR DELETE ON public.rule_tables
    FOR EACH ROW EXECUTE FUNCTION public.enforce_rule_table_registry();
ALTER TABLE public.rule_tables ENABLE ALWAYS TRIGGER rule_table_registry_guard;
DROP TRIGGER IF EXISTS no_truncate ON public.rule_tables;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.rule_tables
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_rule_registry_no_truncate();
ALTER TABLE public.rule_tables ENABLE ALWAYS TRIGGER no_truncate;

-- The column a template requires: its type and whether it may be NULL.
CREATE OR REPLACE FUNCTION public.rule_table_column_errors(p_table regclass, p_column text, p_type text, p_not_null boolean)
    RETURNS text[]
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_type     text;
    v_notnull  boolean;
BEGIN
    SELECT format_type(a.atttypid, a.atttypmod), a.attnotnull INTO v_type, v_notnull
      FROM pg_attribute a
     WHERE a.attrelid = p_table AND a.attname = p_column AND a.attnum > 0 AND NOT a.attisdropped;
    IF NOT FOUND THEN
        RETURN ARRAY[format('%s has no column %s (%s)', p_table, p_column, p_type)];
    END IF;
    IF v_type <> p_type THEN
        RETURN ARRAY[format('%s.%s is %s, not %s', p_table, p_column, v_type, p_type)];
    END IF;
    IF p_not_null IS NOT NULL AND v_notnull <> p_not_null THEN
        RETURN ARRAY[format('%s.%s must %s', p_table, p_column, CASE WHEN p_not_null THEN 'be NOT NULL' ELSE 'allow NULL' END)];
    END IF;
    RETURN '{}';
END;
$$;

-- The facet columns of a table whose types do not store a version's facets
-- exactly (review r2, all three: a text[] facet in a text column was stored
-- as JSON text).
CREATE OR REPLACE FUNCTION public.rule_facet_column_errors(p_table regclass, p_kind text, p_version integer) RETURNS text[]
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT coalesce(array_agg(format('facet %s is %s but %s.%s is %s', f.facet_name, f.facet_type, p_table, f.facet_name,
                                     coalesce(format_type(a.atttypid, a.atttypmod), 'missing')) ORDER BY f.facet_name), '{}')
      FROM public.rule_term_facets f
      LEFT JOIN pg_attribute a ON a.attrelid = p_table AND a.attname = f.facet_name AND a.attnum > 0 AND NOT a.attisdropped
     WHERE f.terms_kind = p_kind AND f.terms_version = p_version
       AND coalesce(format_type(a.atttypid, a.atttypmod), 'missing') <> ALL (CASE f.facet_type
               WHEN 'text' THEN ARRAY['text'] WHEN 'text[]' THEN ARRAY['text[]']
               WHEN 'integer' THEN ARRAY['integer', 'bigint'] WHEN 'number' THEN ARRAY['numeric']
               ELSE ARRAY['boolean'] END)
$$;

CREATE OR REPLACE FUNCTION public.rule_table_register(
        p_table             regclass,
        p_role              text,
        p_terms_kind        text,
        p_area_key          text[],
        p_facet_columns     text[],
        p_close_floor       regprocedure DEFAULT NULL,
        p_insert_check      regprocedure DEFAULT NULL,
        p_law_table         regclass DEFAULT NULL,
        p_compare_function  regprocedure DEFAULT NULL,
        p_adoption_check    regprocedure DEFAULT NULL)
    RETURNS void
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_err      text[] := '{}';
    v_rel      text := p_table::text;
    v_name     text;
    v_c        text;
    v_kind_role text;
    v_key_excl text := '';
    v_adopts   boolean := p_adoption_check IS NOT NULL;
    v_doc_nn   boolean := p_adoption_check IS NULL;
    v_type     text;
    v_has_rows boolean;
    v_i        integer;
    c_template_cols CONSTANT text[] := ARRAY['id', 'state_code', 'service_type', 'effective_from', 'effective_to', 'terms_kind', 'terms_version',
        'terms_source', 'terms', 'created_at', 'recorded_txid', 'closed_at', 'closed_by', 'owner_types', 'system_kinds',
        'commission_jurisdiction', 'owner_span', 'system_span', 'jurisdiction_span', 'source_note', 'tenant_id', 'system_kind',
        'tariff_reference', 'created_by'];
BEGIN
    SELECT c.relname INTO v_name FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE c.oid = p_table AND n.nspname = 'public' AND c.relkind = 'r';
    IF v_name IS NULL THEN
        RAISE EXCEPTION USING MESSAGE = format('%s is not an ordinary table in public (v5.4.2-17)', p_table), ERRCODE = 'invalid_parameter_value';
    END IF;
    IF p_role IS DISTINCT FROM 'law' AND p_role IS DISTINCT FROM 'tariff' THEN
        RAISE EXCEPTION USING MESSAGE = format('a rule table is law or tariff, not %s (v5.4.2-17)', p_role), ERRCODE = 'invalid_parameter_value';
    END IF;
    IF EXISTS (SELECT 1 FROM public.rule_tables WHERE table_name = p_table) THEN
        RAISE EXCEPTION USING MESSAGE = format('%s is already registered (v5.4.2-17)', p_table), ERRCODE = 'unique_violation';
    END IF;
    SELECT min(rule_role) INTO v_kind_role FROM public.rule_term_schemas WHERE terms_kind = p_terms_kind;
    IF v_kind_role IS DISTINCT FROM p_role THEN
        RAISE EXCEPTION USING
            MESSAGE = format('kind %s is %s, so a %s table cannot hold it (v5.4.2-17)', p_terms_kind, coalesce(v_kind_role || ' kind', 'not registered'), p_role),
            ERRCODE = 'invalid_parameter_value';
    END IF;
    IF v_adopts AND p_role <> 'law' THEN
        RAISE EXCEPTION USING MESSAGE = 'only a law table can hold pre-convention rows (v5.4.2-17)', ERRCODE = 'invalid_parameter_value';
    END IF;
    IF p_area_key IS NULL OR p_facet_columns IS NULL OR array_position(p_area_key, NULL) IS NOT NULL OR array_position(p_facet_columns, NULL) IS NOT NULL THEN
        RAISE EXCEPTION USING MESSAGE = 'area key and facet columns are arrays without NULLs (empty allowed) (v5.4.2-17)', ERRCODE = 'invalid_parameter_value';
    END IF;

    -- The template columns.
    v_err := v_err
        || public.rule_table_column_errors(p_table, 'id', 'uuid', true)
        || public.rule_table_column_errors(p_table, 'state_code', 'text', true)
        || public.rule_table_column_errors(p_table, 'service_type', 'text', true)
        || public.rule_table_column_errors(p_table, 'effective_from', 'date', true)
        || public.rule_table_column_errors(p_table, 'effective_to', 'date', false)
        || public.rule_table_column_errors(p_table, 'terms_kind', 'text', v_doc_nn)
        || public.rule_table_column_errors(p_table, 'terms_version', 'integer', v_doc_nn)
        || public.rule_table_column_errors(p_table, 'terms_source', 'text', v_doc_nn)
        || public.rule_table_column_errors(p_table, 'terms', 'jsonb', v_doc_nn)
        || public.rule_table_column_errors(p_table, 'created_at', 'timestamp with time zone', true)
        || public.rule_table_column_errors(p_table, 'recorded_txid', 'bigint', NULL)
        || public.rule_table_column_errors(p_table, 'closed_at', 'timestamp with time zone', false);
    IF p_role = 'law' THEN
        v_err := v_err
            || public.rule_table_column_errors(p_table, 'owner_types', 'text[]', false)
            || public.rule_table_column_errors(p_table, 'system_kinds', 'text[]', false)
            || public.rule_table_column_errors(p_table, 'commission_jurisdiction', 'boolean', false)
            || public.rule_table_column_errors(p_table, 'owner_span', 'int4multirange', true)
            || public.rule_table_column_errors(p_table, 'system_span', 'int4multirange', true)
            || public.rule_table_column_errors(p_table, 'jurisdiction_span', 'int4range', true)
            || public.rule_table_column_errors(p_table, 'source_note', 'text', true)
            || public.rule_table_column_errors(p_table, 'closed_by', 'text', false);
    ELSE
        v_err := v_err
            || public.rule_table_column_errors(p_table, 'tenant_id', 'uuid', true)
            || public.rule_table_column_errors(p_table, 'system_kind', 'text', true)
            || public.rule_table_column_errors(p_table, 'tariff_reference', 'text', true)
            || public.rule_table_column_errors(p_table, 'created_by', 'uuid', false)
            || public.rule_table_column_errors(p_table, 'closed_by', 'uuid', false);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid = p_table AND i.indisprimary
                     AND i.indnkeyatts = 1 AND i.indkey[0] = (SELECT attnum FROM pg_attribute WHERE attrelid = p_table AND attname = 'id')) THEN
        v_err := v_err || format('%s: id must be the primary key', p_table);
    END IF;
    -- The area key: NOT NULL text columns (= in the exclusion never matches a
    -- NULL, so a NULL key would escape it), none a template column.
    FOREACH v_c IN ARRAY p_area_key LOOP
        IF v_c = ANY (ARRAY['id', 'state_code', 'service_type', 'tenant_id', 'system_kind', 'owner_types', 'system_kinds', 'commission_jurisdiction']) THEN
            v_err := v_err || format('%s: %s is a template column, not an area key', p_table, v_c);
        ELSE
            v_err := v_err || public.rule_table_column_errors(p_table, v_c, 'text', true);
        END IF;
        v_key_excl := v_key_excl || format(', %I WITH =', v_c);
    END LOOP;
    -- Facet columns (review r1, Codex B4, Opus S3): never a template or key
    -- column — a facet would overwrite it with the document's value.
    FOREACH v_c IN ARRAY p_facet_columns LOOP
        IF v_c = ANY (c_template_cols) OR v_c = ANY (p_area_key) THEN
            v_err := v_err || format('%s: %s is a template or key column, never a facet', p_table, v_c);
        ELSE
            SELECT format_type(a.atttypid, a.atttypmod) INTO v_type
              FROM pg_attribute a WHERE a.attrelid = p_table AND a.attname = v_c AND a.attnum > 0 AND NOT a.attisdropped;
            IF v_type IS NULL THEN
                v_err := v_err || format('%s has no facet column %s', p_table, v_c);
            END IF;
            -- Its type is checked against its facet's (rule_facet_column_errors,
            -- below and at every row write).
        END IF;
    END LOOP;
    -- A table registered without pre-convention rows holds none: rows already
    -- there were never validated (review r1, Fable S5).
    IF NOT v_adopts THEN
        EXECUTE format('SELECT EXISTS (SELECT 1 FROM %s)', v_rel) INTO v_has_rows;
        IF v_has_rows THEN
            v_err := v_err || format('%s already holds rows: register it as adopting pre-convention rows, or register it empty', p_table);
        END IF;
    END IF;
    -- Adoption must prove the document says what the old columns said
    -- (inventory §4 A; review r1, Codex B1): an adopting table names an
    -- adoption check, run only when an empty document is filled — the whole
    -- row, old typed columns included — never on later inserts (review r2,
    -- Fable F2: a permanent insert check comparing with legacy columns
    -- refused every new row). Its rows are pre-convention: every document
    -- empty (review r2, Codex B3: a prefilled document would never be
    -- validated or compared).
    IF v_adopts THEN
        IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = p_adoption_check
                         AND p.prorettype = 'void'::regtype AND p.proargtypes = '3802'::oidvector) THEN
            v_err := v_err || format('adoption check %s must be (jsonb) RETURNS void', p_adoption_check);
        END IF;
        IF EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = p_table AND a.attname = 'terms' AND NOT a.attisdropped) THEN
            EXECUTE format('SELECT EXISTS (SELECT 1 FROM %s WHERE terms IS NOT NULL OR terms_source IS NOT NULL OR terms_kind IS NOT NULL OR terms_version IS NOT NULL)', v_rel)
               INTO v_has_rows;
            IF v_has_rows THEN
                v_err := v_err || format('%s holds rows whose document is already filled: an adopting table''s documents are all empty, and each is filled through adoption', p_table);
            END IF;
        END IF;
    END IF;
    -- Facet columns of the type each declared facet stores (review r2, all
    -- three): text text, text[] text[], integer integer or bigint, number
    -- numeric, boolean and present boolean — for every version of the kind
    -- registered now; rule_row_prepare checks a later version at its first row.
    FOR v_i IN SELECT terms_version FROM public.rule_term_schemas WHERE terms_kind = p_terms_kind ORDER BY terms_version LOOP
        v_err := v_err || public.rule_facet_column_errors(p_table, p_terms_kind, v_i);
    END LOOP;
    -- Hooks: their signatures.
    IF p_close_floor IS NOT NULL AND NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = p_close_floor
            AND p.prorettype = 'date'::regtype AND p.proargtypes = '2950'::oidvector) THEN
        v_err := v_err || format('close floor %s must be (uuid) RETURNS date', p_close_floor);
    END IF;
    IF p_insert_check IS NOT NULL AND NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = p_insert_check
            AND p.prorettype = 'void'::regtype AND p.proargtypes = '3802'::oidvector) THEN
        v_err := v_err || format('insert check %s must be (jsonb) RETURNS void', p_insert_check);
    END IF;
    IF p_role = 'tariff' AND (p_law_table IS NULL) <> (p_compare_function IS NULL) THEN
        v_err := v_err || 'a tariff table names both a law table and a comparator, or neither'::text;
    END IF;
    IF p_law_table IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.rule_tables WHERE table_name = p_law_table AND rule_role = 'law') THEN
        v_err := v_err || format('%s is not a registered law table', p_law_table);
    END IF;
    IF p_compare_function IS NOT NULL AND NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = p_compare_function
            AND p.prorettype = 'text[]'::regtype AND p.proargtypes = '3802 3802'::oidvector) THEN
        v_err := v_err || format('comparator %s must be (jsonb, jsonb) RETURNS text[]', p_compare_function);
    END IF;
    IF cardinality(v_err) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s does not fit the rule-table template: %s (v5.4.2-17)', p_table, array_to_string(v_err, '; ')),
            ERRCODE = 'invalid_table_definition';
    END IF;

    -- The shared parts.
    EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I CHECK (terms_kind = %L)', v_rel, v_name || '_rule_kind_check', p_terms_kind);
    EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I FOREIGN KEY (terms_kind, terms_version) REFERENCES public.rule_term_schemas(terms_kind, terms_version)',
                   v_rel, v_name || '_rule_schema_fkey');
    EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I CHECK ((effective_to IS NULL) OR (effective_to > effective_from))', v_rel, v_name || '_rule_range_check');
    EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I CHECK (state_code ~ %L)', v_rel, v_name || '_rule_state_check', '^[A-Z]{2}$');
    EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I CHECK (service_type = ANY (ARRAY[''water'', ''sewer'', ''electric'', ''gas'', ''stormwater'', ''trash'', ''reclaimed_water'']))',
                   v_rel, v_name || '_rule_service_check');
    IF v_adopts THEN
        EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I CHECK (((terms_kind IS NULL) AND (terms_version IS NULL) AND (terms_source IS NULL) AND (terms IS NULL)) OR ((terms_kind IS NOT NULL) AND (terms_version IS NOT NULL) AND (terms_source IS NOT NULL) AND (terms IS NOT NULL)))',
                       v_rel, v_name || '_rule_document_check');
    END IF;
    IF p_role = 'law' THEN
        EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I CHECK (source_note ~ %L)', v_rel, v_name || '_rule_source_check', '[[:alnum:]]');
        EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I EXCLUDE USING gist (state_code WITH =, service_type WITH =, owner_span WITH &&, system_span WITH &&, jurisdiction_span WITH &&%s, daterange(effective_from, effective_to, ''[)'') WITH &&)',
                       v_rel, v_name || '_rule_no_overlap', v_key_excl);
        EXECUTE format('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON %s FROM tally_app, tally_core', v_rel);
        EXECUTE format('GRANT SELECT ON %s TO tally_app, tally_core', v_rel);
    ELSE
        EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I CHECK (tariff_reference ~ %L)', v_rel, v_name || '_rule_reference_check', '[[:alnum:]]');
        EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I FOREIGN KEY (tenant_id) REFERENCES public.tenants(id)', v_rel, v_name || '_rule_tenant_fkey');
        EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I FOREIGN KEY (system_kind) REFERENCES public.utility_system_kinds(system_kind)', v_rel, v_name || '_rule_system_fkey');
        EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I FOREIGN KEY (created_by) REFERENCES public.users(id)', v_rel, v_name || '_rule_created_by_fkey');
        EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I FOREIGN KEY (closed_by) REFERENCES public.users(id)', v_rel, v_name || '_rule_closed_by_fkey');
        EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I EXCLUDE USING gist (tenant_id WITH =, state_code WITH =, service_type WITH =, system_kind WITH =%s, daterange(effective_from, effective_to, ''[)'') WITH &&)',
                       v_rel, v_name || '_rule_no_overlap', v_key_excl);
        EXECUTE format('CREATE INDEX %I ON %s USING btree (tenant_id)', 'idx_' || v_name || '_rule_tenant', v_rel);
        EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', v_rel);
        EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY', v_rel);
        EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON %s', v_rel);
        EXECUTE format('CREATE POLICY tenant_isolation ON %s USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())))', v_rel);
        EXECUTE format('REVOKE DELETE, TRUNCATE ON %s FROM tally_app', v_rel);
        EXECUTE format('GRANT SELECT, INSERT, UPDATE ON %s TO tally_app', v_rel);
        EXECUTE format('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON %s FROM tally_core', v_rel);
        EXECUTE format('GRANT SELECT ON %s TO tally_core', v_rel);
    END IF;
    EXECUTE format('CREATE TRIGGER rule_row_insert BEFORE INSERT ON %s FOR EACH ROW EXECUTE FUNCTION public.enforce_rule_row_insert()', v_rel);
    EXECUTE format('CREATE TRIGGER rule_row_history BEFORE UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION public.enforce_rule_row_history()', v_rel);
    EXECUTE format('CREATE TRIGGER rule_row_no_truncate BEFORE TRUNCATE ON %s FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_rule_registry_no_truncate()', v_rel);
    EXECUTE format('ALTER TABLE %s ENABLE ALWAYS TRIGGER rule_row_insert', v_rel);
    EXECUTE format('ALTER TABLE %s ENABLE ALWAYS TRIGGER rule_row_history', v_rel);
    EXECUTE format('ALTER TABLE %s ENABLE ALWAYS TRIGGER rule_row_no_truncate', v_rel);

    INSERT INTO public.rule_tables (table_name, rule_role, terms_kind, area_key, facet_columns, close_floor, insert_check,
                                    law_table, compare_function, adopts_legacy_rows, adoption_check)
    VALUES (p_table, p_role, p_terms_kind, p_area_key, p_facet_columns, p_close_floor, p_insert_check,
            p_law_table, p_compare_function, v_adopts, p_adoption_check);
END;
$$;
COMMENT ON FUNCTION public.rule_table_register(regclass, text, text, text[], text[], regprocedure, regprocedure, regclass, regprocedure, regprocedure) IS
    'v5.4.2-17 (inventory T1, U1). Puts an area''s table on the rule-terms template: checks its template, key and facet columns and its hooks'' signatures, then adds the kind CHECK, the registry foreign key, the range, state and service CHECKs, the no-overlap exclusion (law: state, service, owner/system/jurisdiction spans, the area key, dates; tariff: tenant, state, service, system kind, the area key, dates), the insert / history / no-truncate triggers (ENABLE ALWAYS), the grants (law: read-only for tally_app and tally_core; tariff: tally_app inserts and closes, under the canonical tenant policy, FORCE RLS), and records it in rule_tables. Migration-only.';

-- The registration of the table a trigger fires on.
CREATE OR REPLACE FUNCTION public.rule_table_config(p_table regclass) RETURNS public.rule_tables
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v public.rule_tables%ROWTYPE;
BEGIN
    SELECT * INTO v FROM public.rule_tables WHERE table_name = p_table;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s is not a registered rule table (v5.4.2-17)', p_table),
            ERRCODE = 'invalid_table_definition';
    END IF;
    RETURN v;
END;
$$;

-- The document, facets, spans and stamps a new (or adopted) rule row gets,
-- from what the writer sent. p_row is the row as written, as jsonb; returns
-- the columns to overwrite.
CREATE OR REPLACE FUNCTION public.rule_row_prepare(p_cfg public.rule_tables, p_row jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_schema   public.rule_term_schemas%ROWTYPE;
    v_terms    jsonb;
    v_err      text[];
    v_facets   jsonb;
    v_declared text[];
    v_out      jsonb;
    f          public.rule_term_facets%ROWTYPE;
    v_codes    text[];
    v_scope    text := '';
    v_k        text;
    v_missing  text;
    v_sys      text;
BEGIN
    v_terms := public.rule_terms_parse(p_row ->> 'terms_source');
    IF p_row ->> 'terms_kind' IS DISTINCT FROM p_cfg.terms_kind THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s holds %s documents, not %s (v5.4.2-17)', p_cfg.table_name, p_cfg.terms_kind, coalesce(p_row ->> 'terms_kind', 'none')),
            ERRCODE = 'check_violation';
    END IF;
    IF p_row -> 'terms' IS NOT NULL AND jsonb_typeof(p_row -> 'terms') <> 'null' AND (p_row -> 'terms') <> v_terms THEN
        RAISE EXCEPTION USING
            MESSAGE = 'terms is derived from terms_source; the writer set a different document in both (v5.4.2-17)',
            ERRCODE = 'check_violation';
    END IF;
    -- The version's lock, shared: a freeze waits for this row, and this row,
    -- once a freeze commits, sees it.
    PERFORM pg_advisory_xact_lock_shared(public.rule_term_schema_lock_key(p_cfg.terms_kind, (p_row ->> 'terms_version')::integer));
    SELECT * INTO v_schema FROM public.rule_term_schemas
     WHERE terms_kind = p_cfg.terms_kind AND terms_version = (p_row ->> 'terms_version')::integer;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s v%s is not a registered term schema (v5.4.2-17)', p_cfg.terms_kind, p_row ->> 'terms_version'),
            ERRCODE = 'foreign_key_violation';
    END IF;
    IF NOT v_schema.accepts_new_rows THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s v%s is frozen: new rows use a later version (v5.4.2-17)', v_schema.terms_kind, v_schema.terms_version),
            ERRCODE = 'check_violation';
    END IF;
    v_err := public.rule_terms_errors(v_schema.json_schema, v_terms);
    IF cardinality(v_err) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: the document is not a valid %s v%s: %s (v5.4.2-17)', p_cfg.table_name, v_schema.terms_kind, v_schema.terms_version,
                             array_to_string(v_err[1:10], '; ') || CASE WHEN cardinality(v_err) > 10 THEN format('; and %s more', cardinality(v_err) - 10) ELSE '' END),
            ERRCODE = 'check_violation';
    END IF;

    -- Facets: the declared set must be the table's facet columns, exactly.
    SELECT coalesce(array_agg(facet_name ORDER BY facet_name), '{}') INTO v_declared
      FROM public.rule_term_facets WHERE terms_kind = v_schema.terms_kind AND terms_version = v_schema.terms_version;
    IF NOT (v_declared @> p_cfg.facet_columns AND v_declared <@ p_cfg.facet_columns) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s v%s declares facets %s but %s has facet columns %s (v5.4.2-17)', v_schema.terms_kind, v_schema.terms_version,
                             v_declared, p_cfg.table_name, p_cfg.facet_columns),
            ERRCODE = 'invalid_table_definition';
    END IF;
    v_err := public.rule_facet_column_errors(p_cfg.table_name, v_schema.terms_kind, v_schema.terms_version);
    IF cardinality(v_err) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: %s (v5.4.2-17)', p_cfg.table_name, array_to_string(v_err, '; ')),
            ERRCODE = 'invalid_table_definition';
    END IF;
    v_facets := public.rule_terms_facets(v_schema.terms_kind, v_schema.terms_version, v_terms);
    FOR v_k IN SELECT k FROM jsonb_object_keys(v_facets) k LOOP
        IF p_row -> v_k IS NOT NULL AND jsonb_typeof(p_row -> v_k) <> 'null' AND (p_row -> v_k) <> (v_facets -> v_k) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s.%s is a facet, derived from the document (%s); the writer set %s (v5.4.2-17)', p_cfg.table_name, v_k, v_facets -> v_k, p_row -> v_k),
                ERRCODE = 'check_violation';
        END IF;
    END LOOP;
    -- Vocabulary facets: every code exists, scoped by the row's own columns.
    FOR f IN SELECT * FROM public.rule_term_facets
              WHERE terms_kind = v_schema.terms_kind AND terms_version = v_schema.terms_version AND vocabulary_table IS NOT NULL
              ORDER BY facet_name LOOP
        v_codes := CASE WHEN f.facet_type = 'text[]' THEN ARRAY(SELECT jsonb_array_elements_text(v_facets -> f.facet_name))
                        WHEN v_facets ->> f.facet_name IS NULL THEN '{}'::text[]
                        ELSE ARRAY[v_facets ->> f.facet_name] END;
        v_scope := '';
        FOR v_k IN SELECT k FROM jsonb_object_keys(coalesce(f.vocabulary_scope, '{}'::jsonb)) k ORDER BY k LOOP
            IF NOT p_row ? (f.vocabulary_scope ->> v_k) THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('facet %s scopes its vocabulary by %s, which %s does not have (v5.4.2-17)', f.facet_name, f.vocabulary_scope ->> v_k, p_cfg.table_name),
                    ERRCODE = 'invalid_table_definition';
            END IF;
            v_scope := v_scope || format(' AND v.%I = %L', v_k, p_row ->> (f.vocabulary_scope ->> v_k));
        END LOOP;
        EXECUTE format('SELECT string_agg(c, '', '' ORDER BY c) FROM unnest($1) c WHERE NOT EXISTS (SELECT 1 FROM %s v WHERE v.%I = c%s)',
                       f.vocabulary_table, f.vocabulary_column, v_scope)
           INTO v_missing USING v_codes;
        IF v_missing IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: %s names %s, not in %s for this row''s scope — a misspelled code would silently reach no one (v5.4.2-17)',
                                 p_cfg.table_name, f.facet_name, v_missing, f.vocabulary_table),
                ERRCODE = 'foreign_key_violation';
        END IF;
    END LOOP;

    v_out := jsonb_build_object('terms', v_terms) || v_facets;

    -- The state is a known state (review r1, Codex S5, Fable S10): a state
    -- place of its code, as v5.4.2-16 records states.
    IF NOT EXISTS (SELECT 1 FROM public.places pl WHERE pl.kind_code = 'state' AND pl.place_code = p_row ->> 'state_code') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: %s is not a known state (no state place of that code) (v5.4.2-17)', p_cfg.table_name, p_row ->> 'state_code'),
            ERRCODE = 'foreign_key_violation';
    END IF;

    -- Applicability.
    IF p_cfg.rule_role = 'law' THEN
        IF jsonb_typeof(p_row -> 'system_kinds') = 'array' THEN
            SELECT string_agg(s, ', ' ORDER BY s) INTO v_sys
              FROM jsonb_array_elements_text(p_row -> 'system_kinds') s
             WHERE NOT EXISTS (SELECT 1 FROM public.utility_system_kinds k WHERE k.system_kind = s AND (p_row ->> 'service_type') = ANY (k.service_types));
            IF v_sys IS NOT NULL THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('%s: system kind %s is not a kind of %s system (v5.4.2-17)', p_cfg.table_name, v_sys, p_row ->> 'service_type'),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
        v_out := v_out || jsonb_build_object(
            'owner_span', public.rule_applicability_span('owner_type',
                              CASE WHEN jsonb_typeof(p_row -> 'owner_types') = 'array' THEN ARRAY(SELECT jsonb_array_elements_text(p_row -> 'owner_types')) END),
            'system_span', public.rule_applicability_span('system_kind',
                              CASE WHEN jsonb_typeof(p_row -> 'system_kinds') = 'array' THEN ARRAY(SELECT jsonb_array_elements_text(p_row -> 'system_kinds')) END),
            'jurisdiction_span', public.rule_jurisdiction_span((p_row ->> 'commission_jurisdiction')::boolean));
    ELSE
        IF NOT EXISTS (SELECT 1 FROM public.utility_system_kinds k WHERE k.system_kind = p_row ->> 'system_kind' AND (p_row ->> 'service_type') = ANY (k.service_types)) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: system kind %s is not a kind of %s system (v5.4.2-17)', p_cfg.table_name, p_row ->> 'system_kind', p_row ->> 'service_type'),
                ERRCODE = 'check_violation';
        END IF;
    END IF;

    IF p_cfg.insert_check IS NOT NULL THEN
        EXECUTE format('SELECT %s($1)', p_cfg.insert_check::regproc) USING (p_row || v_out);
    END IF;
    RETURN v_out;
END;
$$;
COMMENT ON FUNCTION public.rule_row_prepare(public.rule_tables, jsonb) IS
    'v5.4.2-17 (inventory V1-V5, F1-F3, T2, U2). For a new or adopted rule row: the document parsed from terms_source (duplicates refused) and validated against its registered, unfrozen schema; the declared facets derived (and any the writer set compared); vocabulary facets checked in scope; for a law row the owner, system and jurisdiction spans; the area''s insert check. Returns the columns the trigger writes.';

CREATE OR REPLACE FUNCTION public.enforce_rule_row_insert() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_cfg   public.rule_tables%ROWTYPE := public.rule_table_config(TG_RELID::regclass);
    v_row   jsonb;
    v_set   jsonb;
    v_user  uuid;
BEGIN
    PERFORM public.assert_rule_read_committed(format('writing a row of %s', TG_RELID::regclass));
    v_row := to_jsonb(NEW);
    v_set := public.rule_row_prepare(v_cfg, v_row);
    v_set := v_set || jsonb_build_object('created_at', now(), 'recorded_txid', txid_current(), 'closed_at', NULL, 'closed_by', NULL);
    IF v_cfg.rule_role = 'tariff' THEN
        v_user := nullif(current_setting('app.user_id', true), '')::uuid;
        v_set := v_set || jsonb_build_object('created_by', v_user);
        NEW := jsonb_populate_record(NEW, v_set);
        PERFORM public.rule_tariff_check(v_cfg, to_jsonb(NEW));
        RETURN NEW;
    END IF;
    RETURN jsonb_populate_record(NEW, v_set);
END;
$$;
COMMENT ON FUNCTION public.enforce_rule_row_insert() IS
    'v5.4.2-17 (inventory T1, U1, U3). BEFORE INSERT on every registered rule table (ENABLE ALWAYS): under READ COMMITTED, rule_row_prepare() writes the document, facets and spans; the stamps are set here (created_by from app.user_id on a tariff row); a tariff row is then checked against the law (rule_tariff_check).';

-- A tariff row against the law (inventory U3): the utility has a profile, and
-- the law has a row, for every day of the tariff's range; the comparator
-- finds nothing looser in any law row in force over it. Each law row's lock
-- is taken shared, so a close of it waits.
CREATE OR REPLACE FUNCTION public.rule_tariff_check(p_cfg public.rule_tables, p_row jsonb) RETURNS void
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    c_max_reads CONSTANT integer := 5;
    v_range    daterange := daterange((p_row ->> 'effective_from')::date, (p_row ->> 'effective_to')::date, '[)');
    v_profiled datemultirange;
    v_lawed    datemultirange;
    v_rows     jsonb;
    v_ids      uuid[];
    v_locked   uuid[] := '{}';
    v_new      uuid[];
    v_stable   boolean := false;
    v_law_cfg  public.rule_tables%ROWTYPE;
    v_shared   text := '';
    v_c        text;
    v_id       uuid;
    p          public.utility_service_profiles%ROWTYPE;
    v_prange   daterange;
    l          record;
    v_problems text[];
BEGIN
    IF p_cfg.law_table IS NULL THEN
        RETURN;
    END IF;
    -- The law rows that speak to this tariff: those whose key agrees on every
    -- key column the two tables share (a residential tariff is measured
    -- against residential law, and only residential law covers it).
    v_law_cfg := public.rule_table_config(p_cfg.law_table);
    FOREACH v_c IN ARRAY p_cfg.area_key LOOP
        IF v_c = ANY (v_law_cfg.area_key) THEN
            v_shared := v_shared || format(' AND t.%I = %L', v_c, p_row ->> v_c);
        END IF;
    END LOOP;
    -- Lock, then read (review r1 B1, all three reviewers): read the law rows,
    -- take the lock of every row not yet held, and read again — each read a
    -- fresh READ COMMITTED snapshot — until a read finds no row whose lock
    -- was not already held before it began. That last read is then current:
    -- a close of any row it saw either committed before it (and is seen) or
    -- waits for this transaction; a successor committed while a lock was
    -- awaited is found by the re-read. Coverage and the comparison use only
    -- that last read.
    FOR v_try IN 1 .. c_max_reads LOOP
        v_profiled := '{}';
        v_lawed := '{}';
        v_rows := '[]'::jsonb;
        v_ids := '{}';
        FOR p IN SELECT * FROM public.utility_service_profiles u
                  WHERE u.tenant_id = (p_row ->> 'tenant_id')::uuid AND u.service_type = p_row ->> 'service_type'
                    AND u.system_kind = p_row ->> 'system_kind' AND u.state_code = p_row ->> 'state_code'
                    AND u.voided_at IS NULL AND daterange(u.effective_from, u.effective_to, '[)') && v_range LOOP
            v_prange := daterange(p.effective_from, p.effective_to, '[)') * v_range;
            v_profiled := v_profiled + datemultirange(v_prange);
            FOR l IN EXECUTE format(
                    'SELECT t.id, to_jsonb(t) AS j, daterange(t.effective_from, t.effective_to, ''[)'') AS r FROM %s t
                      WHERE t.state_code = $1 AND t.service_type = $2
                        AND t.owner_span @> $3 AND t.system_span @> $4 AND t.jurisdiction_span @> $5
                        AND daterange(t.effective_from, t.effective_to, ''[)'') && $6%s
                      ORDER BY t.effective_from, t.id', p_cfg.law_table, v_shared)
                  USING p.state_code, p.service_type,
                        public.rule_applicability_ordinal('owner_type', p.owner_type),
                        public.rule_applicability_ordinal('system_kind', p.system_kind),
                        CASE WHEN p.commission_jurisdiction THEN 1 ELSE 0 END,
                        v_prange LOOP
                v_lawed := v_lawed + datemultirange(l.r * v_prange);
                v_rows := v_rows || jsonb_build_array(l.j);
                v_ids := v_ids || l.id;
            END LOOP;
        END LOOP;
        SELECT coalesce(array_agg(DISTINCT x ORDER BY x), '{}') INTO v_new FROM unnest(v_ids) x WHERE NOT x = ANY (v_locked);
        IF cardinality(v_new) = 0 THEN
            v_stable := true;
            EXIT;
        END IF;
        FOREACH v_id IN ARRAY v_new LOOP
            PERFORM pg_advisory_xact_lock_shared(public.rule_row_lock_key(p_cfg.law_table, v_id));
        END LOOP;
        v_locked := v_locked || v_new;
    END LOOP;
    IF NOT v_stable THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: the law rows for this tariff kept changing while it waited for them (%s reads); write it again (v5.4.2-17)', p_cfg.table_name, c_max_reads),
            ERRCODE = 'lock_not_available';
    END IF;
    IF (datemultirange(v_range) - v_profiled) <> '{}'::datemultirange THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: the utility has no profile for %s (%s) in %s over %s — who owns it decides which law applies (v5.4.2-17)',
                             p_cfg.table_name, p_row ->> 'service_type', p_row ->> 'system_kind', p_row ->> 'state_code', datemultirange(v_range) - v_profiled),
            ERRCODE = 'no_data_found';
    END IF;
    IF (datemultirange(v_range) - v_lawed) <> '{}'::datemultirange THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: no law is known in %s for this utility over %s — a tariff is measured against the law, and unknown law is not permission (v5.4.2-17)',
                             p_cfg.table_name, p_cfg.law_table, datemultirange(v_range) - v_lawed),
            ERRCODE = 'no_data_found';
    END IF;
    EXECUTE format('SELECT %s($1, $2)', p_cfg.compare_function::regproc) INTO v_problems USING p_row, v_rows;
    IF cardinality(v_problems) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: looser than the law: %s (v5.4.2-17)', p_cfg.table_name, array_to_string(v_problems, '; ')),
            ERRCODE = 'check_violation';
    END IF;
END;
$$;
COMMENT ON FUNCTION public.rule_tariff_check(public.rule_tables, jsonb) IS
    'v5.4.2-17 (inventory U3). A new tariff row against its law table: refuses when any day of its range has no utility profile, or no law row binding that profile''s owner type, system kind and jurisdiction status and agreeing with the tariff on every key column the two tables share; otherwise passes every such law row to the area''s comparator, and refuses on any reason it returns. Lock, then read: every row''s lock is taken shared and the rows are read again until a read finds no row it had not locked first (review r1 B1), so a close or a successor committed while it waited is seen; the comparison uses only that read. A "delegated_to_utility" law row is passed too; the comparator finds nothing to compare in it. A LATER law change that makes the tariff looser is a core audit finding (tariff_looser_than_law), never a refusal of the law.';

CREATE OR REPLACE FUNCTION public.enforce_rule_row_history() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_cfg        public.rule_tables%ROWTYPE := public.rule_table_config(TG_RELID::regclass);
    c_close_cols CONSTANT text[] := ARRAY['effective_to', 'closed_at', 'closed_by'];
    v_new        jsonb := to_jsonb(NEW);
    v_old        jsonb := to_jsonb(OLD);
    v_doc_cols   text[];
    v_floor      date;
    v_set        jsonb;
    v_sees_all   boolean;
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s rows are never deleted: records cite them, and the law in force on a past date must stay answerable (v5.4.2-17)', TG_RELID::regclass),
            ERRCODE = 'restrict_violation';
    END IF;
    SELECT r.rolsuper OR r.rolbypassrls INTO v_sees_all FROM pg_roles r WHERE r.rolname = current_user;

    -- A close: effective_to set once, nothing else, above the floor.
    IF (v_old -> 'effective_to') = 'null'::jsonb AND (v_new -> 'effective_to') <> 'null'::jsonb
       AND (v_new - c_close_cols)::text = (v_old - c_close_cols)::text THEN
        PERFORM public.assert_rule_read_committed(format('closing a row of %s', TG_RELID::regclass));
        IF v_cfg.rule_role = 'law' AND NOT coalesce(v_sees_all, false) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('a law row of %s is closed only by a role that sees every tenant: the floor counts every tenant''s citations (v5.4.2-17)', TG_RELID::regclass),
                ERRCODE = 'insufficient_privilege';
        END IF;
        PERFORM pg_advisory_xact_lock(public.rule_row_lock_key(TG_RELID::regclass, OLD.id));
        IF v_cfg.close_floor IS NOT NULL THEN
            EXECUTE format('SELECT %s($1)', v_cfg.close_floor::regproc) INTO v_floor USING OLD.id;
            IF v_floor IS NOT NULL AND (v_new ->> 'effective_to')::date <= v_floor THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('%s row %s cannot close on %s: a citing record needs it in force on %s (v5.4.2-17)',
                                     TG_RELID::regclass, OLD.id, v_new ->> 'effective_to', v_floor),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
        v_set := jsonb_build_object('closed_at', now(),
                                    'closed_by', CASE WHEN v_cfg.rule_role = 'law' THEN to_jsonb(session_user::text)
                                                      ELSE to_jsonb(nullif(current_setting('app.user_id', true), '')) END);
        RETURN jsonb_populate_record(NEW, v_set);
    END IF;

    -- The one-time fill of a pre-convention row's empty document (inventory
    -- T6): the document columns and facets only, by a migration; the row's
    -- key, dates and identity are untouched, and the document is validated
    -- exactly as an insert's.
    IF v_cfg.adopts_legacy_rows AND (v_old -> 'terms') = 'null'::jsonb AND (v_new -> 'terms_source') <> 'null'::jsonb THEN
        v_doc_cols := ARRAY['terms_kind', 'terms_version', 'terms_source', 'terms'] || v_cfg.facet_columns;
        IF (v_new - v_doc_cols) IS DISTINCT FROM (v_old - v_doc_cols) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('adopting %s row %s into the convention changes only its document and facets (v5.4.2-17)', TG_RELID::regclass, OLD.id),
                ERRCODE = 'restrict_violation';
        END IF;
        IF NOT coalesce(v_sees_all, false) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('adopting %s row %s is a reviewed migration''s act (v5.4.2-17)', TG_RELID::regclass, OLD.id),
                ERRCODE = 'insufficient_privilege';
        END IF;
        PERFORM public.assert_rule_read_committed(format('adopting a row of %s', TG_RELID::regclass));
        PERFORM pg_advisory_xact_lock(public.rule_row_lock_key(TG_RELID::regclass, OLD.id));
        v_set := public.rule_row_prepare(v_cfg, v_new);
        IF v_cfg.adoption_check IS NOT NULL THEN
            EXECUTE format('SELECT %s($1)', v_cfg.adoption_check::regproc) USING (v_new || v_set);
        END IF;
        -- Adoption never moves the row's applicability: its spans as stored
        -- must be what its owner types, system kinds and jurisdiction say.
        IF (v_set -> 'owner_span') IS DISTINCT FROM (v_old -> 'owner_span')
           OR (v_set -> 'system_span') IS DISTINCT FROM (v_old -> 'system_span')
           OR (v_set -> 'jurisdiction_span') IS DISTINCT FROM (v_old -> 'jurisdiction_span') THEN
            RAISE EXCEPTION USING
                MESSAGE = format('adopting %s row %s: its stored spans do not match its owner types, system kinds and jurisdiction — fix the spans first (v5.4.2-17)', TG_RELID::regclass, OLD.id),
                ERRCODE = 'check_violation';
        END IF;
        RETURN jsonb_populate_record(NEW, v_set);
    END IF;

    RAISE EXCEPTION USING
        MESSAGE = format('%s rows are never edited: a change in the law is a close and a new row; the only edit is a stamped close (v5.4.2-17)', TG_RELID::regclass),
        ERRCODE = 'restrict_violation';
END;
$$;
COMMENT ON FUNCTION public.enforce_rule_row_history() IS
    'v5.4.2-17 (inventory T1, T4, T6). BEFORE UPDATE OR DELETE on every registered rule table (ENABLE ALWAYS). No delete. One edit: a close — effective_to set once and nothing else, under READ COMMITTED, with the row''s lock taken exclusive before the floor is read, never on or before the area''s close floor; a law row only by a role that sees every tenant; closed_at and closed_by stamped. For a table registered with pre-convention rows, also the one-time fill of an empty document by a migration, validated as an insert''s, nothing else changed.';

-- A citing record takes the rule row's lock shared and re-reads the row
-- (inventory T4). Called by an area's guard on its citing records.
CREATE OR REPLACE FUNCTION public.rule_row_cite(p_table regclass, p_id uuid, p_on date) RETURNS void
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_cfg      public.rule_tables%ROWTYPE := public.rule_table_config(p_table);
    v_in_force boolean;
BEGIN
    IF p_id IS NULL OR p_on IS NULL THEN
        RAISE EXCEPTION USING MESSAGE = 'rule_row_cite: a row and a date are required (v5.4.2-17)', ERRCODE = 'invalid_parameter_value';
    END IF;
    PERFORM public.assert_rule_read_committed(format('citing a row of %s', p_table));
    PERFORM pg_advisory_xact_lock_shared(public.rule_row_lock_key(p_table, p_id));
    EXECUTE format('SELECT daterange(t.effective_from, t.effective_to, ''[)'') @> $2 FROM %s t WHERE t.id = $1', v_cfg.table_name)
       INTO v_in_force USING p_id, p_on;
    IF v_in_force IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s has no row %s (or it is not visible) (v5.4.2-17)', p_table, p_id),
            ERRCODE = 'foreign_key_violation';
    END IF;
    IF NOT v_in_force THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s row %s is not in force on %s (v5.4.2-17)', p_table, p_id, p_on),
            ERRCODE = 'check_violation';
    END IF;
END;
$$;
COMMENT ON FUNCTION public.rule_row_cite(regclass, uuid, date) IS
    'v5.4.2-17 (inventory T4). The citing side of the close handshake: under READ COMMITTED, takes the rule row''s lock shared — held to commit, so a close waits — then re-reads the row and refuses unless it exists, is visible and is in force on the date. A close that committed first is seen; one that comes later must clear the citation in its floor.';

-- The law row in force (inventory T3): from the utility's profile on the
-- date, the area key and the date. Refuses when there is no profile, or no
-- law row — unknown law is not permission, and never falls back.
CREATE OR REPLACE FUNCTION public.rule_law_row_as_of(p_table regclass, p_tenant_id uuid, p_service_type text, p_system_kind text,
                                                     p_state_code text, p_key jsonb, p_on date)
    RETURNS uuid
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_cfg     public.rule_tables%ROWTYPE := public.rule_table_config(p_table);
    v_profile public.utility_service_profiles%ROWTYPE;
    v_where   text := '';
    v_c       text;
    v_ids     uuid[];
BEGIN
    IF v_cfg.rule_role <> 'law' THEN
        RAISE EXCEPTION USING MESSAGE = format('%s is not a law table (v5.4.2-17)', p_table), ERRCODE = 'invalid_parameter_value';
    END IF;
    PERFORM public.rule_key_check(v_cfg, p_key);
    v_profile := public.utility_service_profile_as_of(p_tenant_id, p_service_type, p_system_kind, p_state_code, p_on);
    FOREACH v_c IN ARRAY v_cfg.area_key LOOP
        v_where := v_where || format(' AND t.%I = %L', v_c, p_key ->> v_c);
    END LOOP;
    EXECUTE format('SELECT array_agg(t.id) FROM %s t WHERE t.state_code = $1 AND t.service_type = $2
                      AND t.owner_span @> $3 AND t.system_span @> $4 AND t.jurisdiction_span @> $5
                      AND daterange(t.effective_from, t.effective_to, ''[)'') @> $6%s', p_table, v_where)
       INTO v_ids
      USING p_state_code, p_service_type,
            public.rule_applicability_ordinal('owner_type', v_profile.owner_type),
            public.rule_applicability_ordinal('system_kind', v_profile.system_kind),
            CASE WHEN v_profile.commission_jurisdiction THEN 1 ELSE 0 END, p_on;
    IF v_ids IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('no law in %s binds a %s %s utility (%s, %s jurisdiction) in %s for %s on %s — unknown law is not permission (v5.4.2-17)',
                             p_table, v_profile.owner_type, p_service_type, p_system_kind,
                             CASE WHEN v_profile.commission_jurisdiction THEN 'under the commission''s' ELSE 'outside the commission''s' END,
                             p_state_code, p_key, p_on),
            ERRCODE = 'no_data_found';
    END IF;
    IF cardinality(v_ids) > 1 THEN
        -- Unreachable while the exclusion holds.
        RAISE EXCEPTION USING
            MESSAGE = format('%s: %s law rows match %s on %s (v5.4.2-17)', p_table, cardinality(v_ids), p_key, p_on),
            ERRCODE = 'cardinality_violation';
    END IF;
    RETURN v_ids[1];
END;
$$;
COMMENT ON FUNCTION public.rule_law_row_as_of(regclass, uuid, text, text, text, jsonb, date) IS
    'v5.4.2-17 (inventory T3). The id of the law row in force: the utility''s profile on the date (utility_service_profile_as_of — refuses when none) gives its owner type, system kind and jurisdiction status; the row must bind all three, match the state, service and every area-key column (p_key names exactly the table''s area key), and be in force on the date. Refuses (no_data_found) when no law row matches: unknown law is never permission and never falls back to a broader row. Does not lock; a citing record calls rule_row_cite.';

-- A record's citation of the law (inventory U4; review r1, all three): the
-- cited row must be THE law row in force for the citing utility's profile,
-- key and date — not merely a row in force — and is then locked as any
-- citation is. A city-owned system cannot cite the investor-owned row.
CREATE OR REPLACE FUNCTION public.rule_law_row_cite(p_table regclass, p_id uuid, p_tenant_id uuid, p_service_type text, p_system_kind text,
                                                    p_state_code text, p_key jsonb, p_on date)
    RETURNS void
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_expected uuid;
BEGIN
    PERFORM public.rule_row_cite(p_table, p_id, p_on);
    -- Resolved after the cited row's lock is held, so a close in flight has
    -- either committed (and is seen) or waits.
    v_expected := public.rule_law_row_as_of(p_table, p_tenant_id, p_service_type, p_system_kind, p_state_code, p_key, p_on);
    IF v_expected IS DISTINCT FROM p_id THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s row %s is not the law for this utility on %s: its law row is %s (v5.4.2-17)', p_table, p_id, p_on, v_expected),
            ERRCODE = 'check_violation';
    END IF;
END;
$$;
COMMENT ON FUNCTION public.rule_law_row_cite(regclass, uuid, uuid, text, text, text, jsonb, date) IS
    'v5.4.2-17 (inventory U4, T3, T4; review r1). The citing side for a law row: rule_row_cite (lock shared, re-read, in force on the date), then the row must be the one rule_law_row_as_of resolves for the citing utility''s profile, key and date. An area''s guard on its citing records calls this, not rule_row_cite, for law rows.';

-- The utility's own tariff row in force, or NULL when it has none.
CREATE OR REPLACE FUNCTION public.rule_tariff_row_as_of(p_table regclass, p_tenant_id uuid, p_service_type text, p_system_kind text,
                                                        p_state_code text, p_key jsonb, p_on date)
    RETURNS uuid
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_cfg   public.rule_tables%ROWTYPE := public.rule_table_config(p_table);
    v_where text := '';
    v_c     text;
    v_ids   uuid[];
BEGIN
    IF v_cfg.rule_role <> 'tariff' THEN
        RAISE EXCEPTION USING MESSAGE = format('%s is not a tariff table (v5.4.2-17)', p_table), ERRCODE = 'invalid_parameter_value';
    END IF;
    IF p_tenant_id IS NULL OR p_service_type IS NULL OR p_system_kind IS NULL OR p_state_code IS NULL OR p_on IS NULL THEN
        RAISE EXCEPTION USING MESSAGE = 'rule_tariff_row_as_of: tenant, service, system kind, state and date are all required (v5.4.2-17)', ERRCODE = 'invalid_parameter_value';
    END IF;
    PERFORM public.rule_key_check(v_cfg, p_key);
    FOREACH v_c IN ARRAY v_cfg.area_key LOOP
        v_where := v_where || format(' AND t.%I = %L', v_c, p_key ->> v_c);
    END LOOP;
    EXECUTE format('SELECT array_agg(t.id) FROM %s t WHERE t.tenant_id = $1 AND t.service_type = $2 AND t.system_kind = $3
                      AND t.state_code = $4 AND daterange(t.effective_from, t.effective_to, ''[)'') @> $5%s', p_table, v_where)
       INTO v_ids USING p_tenant_id, p_service_type, p_system_kind, p_state_code, p_on;
    IF cardinality(v_ids) > 1 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: %s tariff rows match %s on %s (v5.4.2-17)', p_table, cardinality(v_ids), p_key, p_on),
            ERRCODE = 'cardinality_violation';
    END IF;
    RETURN v_ids[1];
END;
$$;
COMMENT ON FUNCTION public.rule_tariff_row_as_of(regclass, uuid, text, text, text, jsonb, date) IS
    'v5.4.2-17 (inventory U4). The id of the utility''s own tariff row in force for its system, state, service, area key and date — or NULL when it has none, which is ordinary: a record always cites the law row in force and cites a tariff row only when one applied. Under a "delegated_to_utility" law row, it is the core that refuses a decision with no tariff row (no policy recorded). Invoker rights: RLS applies.';

-- Seeding a law row from a law file (inventory T5; v2 §5 "seeds are
-- idempotent and strict"): the row is inserted unless a row of the same
-- applicability, key and start already exists; then it must be the same row —
-- the same document, end, citation — or the seed raises. Never an upsert:
-- a law row's content is never edited, and a re-run seed that silently kept
-- old law (the -13 and -15 seeds' skip-on-key) is what this replaces.
CREATE OR REPLACE FUNCTION public.rule_row_seed(p_table regclass, p_row jsonb) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_cfg      public.rule_tables%ROWTYPE := public.rule_table_config(p_table);
    v_where    text := '';
    v_c        text;
    v_existing jsonb;
    v_terms    jsonb;
    v_diff     text[] := '{}';
    v_id       uuid;
    v_unknown  text;
    v_cols     text;
BEGIN
    IF v_cfg.rule_role <> 'law' THEN
        RAISE EXCEPTION USING MESSAGE = format('%s is not a law table: a utility''s own rows are not seeded (v5.4.2-17)', p_table), ERRCODE = 'invalid_parameter_value';
    END IF;
    -- The whole envelope, and no id (review r3, Opus N1): a seed is compared
    -- on every column it names, so it names them all; the row's id is the
    -- database's.
    IF jsonb_typeof(p_row) IS DISTINCT FROM 'object' OR p_row ? 'id'
       OR NOT p_row ?& ARRAY['state_code', 'service_type', 'owner_types', 'system_kinds', 'commission_jurisdiction',
                             'effective_from', 'effective_to', 'source_note', 'terms_kind', 'terms_version', 'terms_source'] THEN
        RAISE EXCEPTION USING
            MESSAGE = 'rule_row_seed: a row names the whole envelope — state_code, service_type, owner_types, system_kinds, commission_jurisdiction, effective_from, effective_to, source_note, terms_kind, terms_version, terms_source — and no id (v5.4.2-17)',
            ERRCODE = 'invalid_parameter_value';
    END IF;
    -- Applicability is typed before it is matched (review r4, Codex S1): a
    -- scalar or an object where a set belongs would otherwise read as NULL —
    -- "every one" — and match a row that applies to everything.
    IF jsonb_typeof(p_row -> 'owner_types') NOT IN ('null', 'array')
       OR jsonb_typeof(p_row -> 'system_kinds') NOT IN ('null', 'array')
       OR jsonb_typeof(p_row -> 'commission_jurisdiction') NOT IN ('null', 'boolean')
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_row -> 'owner_types') = 'array' THEN p_row -> 'owner_types' ELSE '[]'::jsonb END) e
                   WHERE jsonb_typeof(e) <> 'string')
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_row -> 'system_kinds') = 'array' THEN p_row -> 'system_kinds' ELSE '[]'::jsonb END) e
                   WHERE jsonb_typeof(e) <> 'string') THEN
        RAISE EXCEPTION USING
            MESSAGE = 'rule_row_seed: owner_types and system_kinds are null (every one) or an array of strings, and commission_jurisdiction is null or a boolean (v5.4.2-17)',
            ERRCODE = 'invalid_parameter_value';
    END IF;
    PERFORM public.rule_key_check(v_cfg, (SELECT coalesce(jsonb_object_agg(k, p_row -> k), '{}'::jsonb) FROM unnest(v_cfg.area_key) k));
    -- Every key a column (review r1, Fable S4): a misspelt "effective_too"
    -- would otherwise be dropped and the row stored open-ended.
    SELECT string_agg(k, ', ' ORDER BY k) INTO v_unknown
      FROM jsonb_object_keys(p_row) k
     WHERE NOT EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = p_table AND a.attname = k AND a.attnum > 0 AND NOT a.attisdropped);
    IF v_unknown IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('rule_row_seed: %s has no column %s (v5.4.2-17)', p_table, v_unknown),
            ERRCODE = 'undefined_column';
    END IF;
    SELECT string_agg(quote_ident(k), ', ' ORDER BY k) INTO v_cols FROM jsonb_object_keys(p_row) k;
    FOREACH v_c IN ARRAY v_cfg.area_key LOOP
        v_where := v_where || format(' AND t.%I = %L', v_c, p_row ->> v_c);
    END LOOP;
    -- Applicability compared as sets: the order a file lists owner types in
    -- is not a difference.
    EXECUTE format('SELECT to_jsonb(t) FROM %s t
                     WHERE t.state_code = $1 AND t.service_type = $2 AND t.effective_from = $3
                       AND t.owner_span = public.rule_applicability_span(''owner_type'', $4)
                       AND t.system_span = public.rule_applicability_span(''system_kind'', $5)
                       AND t.jurisdiction_span = public.rule_jurisdiction_span($6)%s', p_table, v_where)
       INTO v_existing
      USING p_row ->> 'state_code', p_row ->> 'service_type', (p_row ->> 'effective_from')::date,
            CASE WHEN jsonb_typeof(p_row -> 'owner_types') = 'array' THEN ARRAY(SELECT jsonb_array_elements_text(p_row -> 'owner_types')) END,
            CASE WHEN jsonb_typeof(p_row -> 'system_kinds') = 'array' THEN ARRAY(SELECT jsonb_array_elements_text(p_row -> 'system_kinds')) END,
            (p_row ->> 'commission_jurisdiction')::boolean;
    IF v_existing IS NULL THEN
        -- Only the columns the seed names: the rest keep their defaults, and
        -- the trigger writes the document, facets, spans and stamps.
        EXECUTE format('INSERT INTO %s (%s) SELECT %s FROM jsonb_populate_record(NULL::%s, $1) RETURNING id',
                       p_table, v_cols, v_cols, p_table)
           INTO v_id USING p_row;
        RETURN v_id;
    END IF;
    v_terms := public.rule_terms_parse(p_row ->> 'terms_source');
    IF (v_existing -> 'terms') IS DISTINCT FROM v_terms THEN
        v_diff := v_diff || 'terms'::text;
    END IF;
    -- Every column the seed names is compared, not only the document (review
    -- r2, Opus S2); applicability was matched as sets above, and the
    -- document is compared parsed. Values are compared as jsonb, so 50.0 is
    -- the stored 50: a seed restates the law, and a number's scale in it is
    -- not the law (unlike a close or a freeze, compared as text: an edit).
    FOR v_c IN SELECT k FROM jsonb_object_keys(p_row) k
                WHERE k <> ALL (ARRAY['id', 'terms_source', 'owner_types', 'system_kinds', 'commission_jurisdiction'])
                ORDER BY k LOOP
        IF (v_existing -> v_c) IS DISTINCT FROM (p_row -> v_c) THEN
            v_diff := v_diff || v_c;
        END IF;
    END LOOP;
    IF NOT p_row ? 'effective_to' AND (v_existing -> 'effective_to') <> 'null'::jsonb THEN
        v_diff := v_diff || 'effective_to'::text;
    END IF;
    IF cardinality(v_diff) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s already holds this law row (%s from %s) with a different %s: a law row is never edited — a change in the law is a close and a new row (v5.4.2-17)',
                             p_table, v_existing ->> 'id', p_row ->> 'effective_from', array_to_string(v_diff, ', ')),
            ERRCODE = 'unique_violation';
    END IF;
    RETURN (v_existing ->> 'id')::uuid;
END;
$$;
COMMENT ON FUNCTION public.rule_row_seed(regclass, jsonb) IS
    'v5.4.2-17 (rule-terms v2 §5; inventory T5). A reviewed migration''s seed of one law row (as tools/law emits it): inserted when no row of the same state, service, owner/system/jurisdiction sets, area key and start exists; otherwise the existing row''s id when it is the same row (document, end, citation, kind, version), and an error (unique_violation) naming what differs when it is not. Never an upsert. Migration-only.';

-- p_key names exactly the table's area-key columns, each a non-blank string.
CREATE OR REPLACE FUNCTION public.rule_key_check(p_cfg public.rule_tables, p_key jsonb) RETURNS void
    LANGUAGE plpgsql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_keys text[];
BEGIN
    IF jsonb_typeof(p_key) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION USING MESSAGE = format('the key of %s is a JSON object of %s (v5.4.2-17)', p_cfg.table_name, p_cfg.area_key), ERRCODE = 'invalid_parameter_value';
    END IF;
    SELECT coalesce(array_agg(k ORDER BY k), '{}') INTO v_keys FROM jsonb_object_keys(p_key) k;
    IF NOT (v_keys @> p_cfg.area_key AND v_keys <@ p_cfg.area_key)
       OR EXISTS (SELECT 1 FROM jsonb_each(p_key) e WHERE jsonb_typeof(e.value) <> 'string' OR (e.value #>> '{}') !~ '[[:alnum:]]') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('the key of %s names exactly %s, each a non-blank string; got %s (v5.4.2-17)', p_cfg.table_name, p_cfg.area_key, p_key),
            ERRCODE = 'invalid_parameter_value';
    END IF;
END;
$$;


-- ----------------------------------------------------------------------------
-- 7. Published values (v2 §6; inventory P1, P3)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enforce_rule_vocabulary_immutable() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s rows are never edited or deleted: rows and records cite them (v5.4.2-17)', TG_TABLE_NAME),
            ERRCODE = 'restrict_violation';
    END IF;
    NEW.created_at := now();
    RETURN NEW;
END;
$$;

CREATE TABLE IF NOT EXISTS public.rule_units (
    unit          text NOT NULL,
    description   text NOT NULL,
    created_at    timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT rule_units_pkey PRIMARY KEY (unit),
    CONSTRAINT rule_units_code_check CHECK ((unit ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT rule_units_text_check CHECK ((description ~ '[[:alnum:]]'::text))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.rule_units FROM tally_app, tally_core;
GRANT SELECT ON public.rule_units TO tally_app, tally_core;
COMMENT ON TABLE public.rule_units IS
    'v5.4.2-17 (inventory P1; review r1, all three). The units a published value is stated in — what one unit of value means, so a 2.87% rate is 0.0287 in annual_rate_fraction and never 2.87 by mistake. Platform-held; never edited or deleted; a new unit is a row.';
DROP TRIGGER IF EXISTS rule_unit_guard ON public.rule_units;
CREATE TRIGGER rule_unit_guard BEFORE INSERT OR UPDATE OR DELETE ON public.rule_units
    FOR EACH ROW EXECUTE FUNCTION public.enforce_rule_vocabulary_immutable();
ALTER TABLE public.rule_units ENABLE ALWAYS TRIGGER rule_unit_guard;
DROP TRIGGER IF EXISTS no_truncate ON public.rule_units;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.rule_units
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_rule_registry_no_truncate();
ALTER TABLE public.rule_units ENABLE ALWAYS TRIGGER no_truncate;
INSERT INTO public.rule_units (unit, description)
SELECT v.u, v.d
  FROM (VALUES
    ('annual_rate_fraction', 'A yearly rate as a fraction: 0.0287 is 2.87% a year (Texas Utilities Code 183.003''s deposit rate; Treasury yields).'),
    ('usd', 'United States dollars (an indexed dollar threshold, rule-terms v2 §6).')
  ) AS v(u, d)
 WHERE NOT EXISTS (SELECT 1 FROM public.rule_units x WHERE x.unit = v.u);

CREATE TABLE IF NOT EXISTS public.rule_parameters (
    parameter_name  text NOT NULL,
    unit            text NOT NULL,
    scoped_by       text[] NOT NULL,
    value_min       numeric,
    value_max       numeric,
    description     text NOT NULL,
    source_note     text NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT rule_parameters_pkey PRIMARY KEY (parameter_name),
    CONSTRAINT rule_parameters_unit_fkey FOREIGN KEY (unit) REFERENCES public.rule_units(unit),
    CONSTRAINT rule_parameters_name_check CHECK ((parameter_name ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT rule_parameters_unit_check CHECK ((unit ~ '^[a-z][a-z0-9_]*$'::text)),
    -- The dimensions a published value is scoped by: national (none), a
    -- state, a state's service.
    CONSTRAINT rule_parameters_scope_check
        CHECK ((scoped_by IN (ARRAY[]::text[], ARRAY['state_code'::text], ARRAY['state_code'::text, 'service_type'::text]))),
    -- value_min <= v <= value_max, either open; NaN never a bound.
    CONSTRAINT rule_parameters_range_check
        CHECK ((((value_min IS NULL) OR (value_min <> 'NaN'::numeric)) AND ((value_max IS NULL) OR (value_max <> 'NaN'::numeric))
            AND ((value_min IS NULL) OR (value_max IS NULL) OR (value_min <= value_max)))),
    CONSTRAINT rule_parameters_text_check CHECK (((description ~ '[[:alnum:]]'::text) AND (source_note ~ '[[:alnum:]]'::text)))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.rule_parameters FROM tally_app, tally_core;
GRANT SELECT ON public.rule_parameters TO tally_app, tally_core;
COMMENT ON TABLE public.rule_parameters IS
    'v5.4.2-17 (rule-terms v2 §6; inventory P1). A value the law refers to by name but that is published on its own schedule — a commission''s annual deposit interest rate, a Treasury yield, an indexed threshold — with its unit (the name says what it is: annual_rate_fraction, not "rate"), its allowed range, and the dimensions its values are scoped by (none: national; state; state and service). A law document refers to it as {"source": "published", "name": …}; the core reads the value in force on the date. Platform-held; never edited or deleted. The utility''s own applied value stays its own tenant row (R-D1).';

DROP TRIGGER IF EXISTS rule_parameter_guard ON public.rule_parameters;
CREATE TRIGGER rule_parameter_guard BEFORE INSERT OR UPDATE OR DELETE ON public.rule_parameters
    FOR EACH ROW EXECUTE FUNCTION public.enforce_rule_vocabulary_immutable();
ALTER TABLE public.rule_parameters ENABLE ALWAYS TRIGGER rule_parameter_guard;
DROP TRIGGER IF EXISTS no_truncate ON public.rule_parameters;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.rule_parameters
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_rule_registry_no_truncate();
ALTER TABLE public.rule_parameters ENABLE ALWAYS TRIGGER no_truncate;

CREATE TABLE IF NOT EXISTS public.rule_parameter_values (
    id              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    parameter_name  text NOT NULL,
    state_code      text,
    service_type    text,
    effective_from  date NOT NULL,
    effective_to    date,
    value           numeric NOT NULL,
    source_note     text NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    closed_at       timestamp with time zone,
    closed_by       text,
    CONSTRAINT rule_parameter_values_pkey PRIMARY KEY (id),
    CONSTRAINT rule_parameter_values_parameter_fkey FOREIGN KEY (parameter_name) REFERENCES public.rule_parameters(parameter_name),
    CONSTRAINT rule_parameter_values_state_check CHECK (((state_code IS NULL) OR (state_code ~ '^[A-Z]{2}$'::text))),
    CONSTRAINT rule_parameter_values_service_check
        CHECK (((service_type IS NULL) OR (service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text])))),
    CONSTRAINT rule_parameter_values_range_check CHECK (((effective_to IS NULL) OR (effective_to > effective_from))),
    CONSTRAINT rule_parameter_values_value_check CHECK ((value <> 'NaN'::numeric)),
    CONSTRAINT rule_parameter_values_source_check CHECK ((source_note ~ '[[:alnum:]]'::text)),
    -- Scope columns are all set or all NULL per parameter (the trigger), so
    -- coalescing a NULL to '' compares like with like.
    CONSTRAINT rule_parameter_values_no_overlap
        EXCLUDE USING gist (parameter_name WITH =, (COALESCE(state_code, ''::text)) WITH =, (COALESCE(service_type, ''::text)) WITH =,
                            daterange(effective_from, effective_to, '[)'::text) WITH &&)
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.rule_parameter_values FROM tally_app, tally_core;
GRANT SELECT ON public.rule_parameter_values TO tally_app, tally_core;
COMMENT ON TABLE public.rule_parameter_values IS
    'v5.4.2-17 (rule-terms v2 §6; inventory P1). Each published value of a rule parameter, dated, in its parameter''s scope (state and service set exactly as the parameter''s scoped_by says), within its range, never NaN, with its own citation — the publication it came from. A new publication is a new dated value, not a new law row. Never edited except a stamped close (by a role that sees every tenant); never deleted. Nothing cites a value yet: a record that will (an area that adopts a statutory rate) brings the close floor with it (residual R4).';

CREATE OR REPLACE FUNCTION public.enforce_rule_parameter_value() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    c_close_cols CONSTANT text[] := ARRAY['effective_to', 'closed_at', 'closed_by'];
    v_p        public.rule_parameters%ROWTYPE;
    v_sees_all boolean;
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING
            MESSAGE = 'a published value is never deleted: the value in force on a past date must stay answerable (v5.4.2-17)',
            ERRCODE = 'restrict_violation';
    END IF;
    IF TG_OP = 'UPDATE' THEN
        IF OLD.effective_to IS NOT NULL OR NEW.effective_to IS NULL
           OR (to_jsonb(NEW) - c_close_cols) IS DISTINCT FROM (to_jsonb(OLD) - c_close_cols) THEN
            RAISE EXCEPTION USING
                MESSAGE = 'a published value is never edited; the only edit is a stamped close — a new publication is a new value (v5.4.2-17)',
                ERRCODE = 'restrict_violation';
        END IF;
        SELECT r.rolsuper OR r.rolbypassrls INTO v_sees_all FROM pg_roles r WHERE r.rolname = current_user;
        IF NOT coalesce(v_sees_all, false) THEN
            RAISE EXCEPTION USING MESSAGE = 'a published value is closed by a reviewed platform migration (v5.4.2-17)', ERRCODE = 'insufficient_privilege';
        END IF;
        NEW.closed_at := now();
        NEW.closed_by := session_user;
        RETURN NEW;
    END IF;
    SELECT * INTO v_p FROM public.rule_parameters WHERE parameter_name = NEW.parameter_name;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING MESSAGE = format('%s is not a published parameter (v5.4.2-17)', NEW.parameter_name), ERRCODE = 'foreign_key_violation';
    END IF;
    IF (NEW.state_code IS NOT NULL) <> ('state_code' = ANY (v_p.scoped_by))
       OR (NEW.service_type IS NOT NULL) <> ('service_type' = ANY (v_p.scoped_by)) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s is scoped by %s: a value names exactly those (v5.4.2-17)', NEW.parameter_name, CASE WHEN cardinality(v_p.scoped_by) = 0 THEN 'nothing (national)' ELSE array_to_string(v_p.scoped_by, ' and ') END),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.value = 'NaN'::numeric THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: NaN is not a published value (v5.4.2-17)', NEW.parameter_name),
            ERRCODE = 'check_violation';
    END IF;
    IF (v_p.value_min IS NOT NULL AND NEW.value < v_p.value_min) OR (v_p.value_max IS NOT NULL AND NEW.value > v_p.value_max) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: %s is outside [%s, %s] %s (v5.4.2-17)', NEW.parameter_name, NEW.value, coalesce(v_p.value_min::text, '-∞'), coalesce(v_p.value_max::text, '∞'), v_p.unit),
            ERRCODE = 'check_violation';
    END IF;
    NEW.created_at := now();
    NEW.closed_at := NULL;
    NEW.closed_by := NULL;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS rule_parameter_value_guard ON public.rule_parameter_values;
CREATE TRIGGER rule_parameter_value_guard BEFORE INSERT OR UPDATE OR DELETE ON public.rule_parameter_values
    FOR EACH ROW EXECUTE FUNCTION public.enforce_rule_parameter_value();
ALTER TABLE public.rule_parameter_values ENABLE ALWAYS TRIGGER rule_parameter_value_guard;
DROP TRIGGER IF EXISTS no_truncate ON public.rule_parameter_values;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.rule_parameter_values
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_rule_registry_no_truncate();
ALTER TABLE public.rule_parameter_values ENABLE ALWAYS TRIGGER no_truncate;

CREATE OR REPLACE FUNCTION public.rule_parameter_value_as_of(p_name text, p_state_code text, p_service_type text, p_on date)
    RETURNS public.rule_parameter_values
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_p public.rule_parameters%ROWTYPE;
    v   public.rule_parameter_values%ROWTYPE;
BEGIN
    SELECT * INTO v_p FROM public.rule_parameters WHERE parameter_name = p_name;
    IF NOT FOUND OR p_on IS NULL THEN
        RAISE EXCEPTION USING MESSAGE = format('rule_parameter_value_as_of: %s is not a published parameter, or no date was given (v5.4.2-17)', p_name), ERRCODE = 'invalid_parameter_value';
    END IF;
    IF (p_state_code IS NOT NULL) <> ('state_code' = ANY (v_p.scoped_by)) OR (p_service_type IS NOT NULL) <> ('service_type' = ANY (v_p.scoped_by)) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s is scoped by %s: name exactly those, nothing broader or narrower (v5.4.2-17)', p_name, CASE WHEN cardinality(v_p.scoped_by) = 0 THEN 'nothing (national)' ELSE array_to_string(v_p.scoped_by, ' and ') END),
            ERRCODE = 'invalid_parameter_value';
    END IF;
    SELECT * INTO v FROM public.rule_parameter_values x
     WHERE x.parameter_name = p_name AND x.state_code IS NOT DISTINCT FROM p_state_code AND x.service_type IS NOT DISTINCT FROM p_service_type
       AND daterange(x.effective_from, x.effective_to, '[)') @> p_on;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('no published %s is recorded for %s on %s (v5.4.2-17)', p_name, concat_ws('/', p_state_code, p_service_type), p_on),
            ERRCODE = 'no_data_found';
    END IF;
    RETURN v;
END;
$$;
COMMENT ON FUNCTION public.rule_parameter_value_as_of(text, text, text, date) IS
    'v5.4.2-17 (inventory P1, P3). The published value of a parameter in force on a date, in exactly the scope its parameter is published in. Refuses a scope broader or narrower than the parameter''s, and refuses when none is recorded — never falls back to another scope or the latest value.';


-- ----------------------------------------------------------------------------
-- 8. The core-inputs fingerprint (v2 §8; inventory C4)
-- ----------------------------------------------------------------------------
-- A core-written table carries inputs jsonb, inputs_kind text,
-- inputs_version integer, inputs_fingerprint text and calculated_by text, and
-- attaches this as a BEFORE INSERT trigger. The inputs are validated against
-- their registered inputs schema; the fingerprint is the database's.

CREATE OR REPLACE FUNCTION public.stamp_core_inputs() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_row    jsonb := to_jsonb(NEW);
    v_schema public.rule_term_schemas%ROWTYPE;
    v_err    text[];
    v_fp     text;
BEGIN
    IF NOT (v_row ? 'inputs' AND v_row ? 'inputs_kind' AND v_row ? 'inputs_version' AND v_row ? 'inputs_fingerprint' AND v_row ? 'calculated_by') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s lacks the core-inputs columns (inputs, inputs_kind, inputs_version, inputs_fingerprint, calculated_by) (v5.4.2-17)', TG_RELID::regclass),
            ERRCODE = 'invalid_table_definition';
    END IF;
    IF coalesce(v_row ->> 'calculated_by', '') !~ '[[:alnum:]]' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: calculated_by names the core release that computed the record (v5.4.2-17)', TG_RELID::regclass),
            ERRCODE = 'check_violation';
    END IF;
    PERFORM public.assert_rule_read_committed(format('writing a core record of %s', TG_RELID::regclass));
    PERFORM pg_advisory_xact_lock_shared(public.rule_term_schema_lock_key(v_row ->> 'inputs_kind', (v_row ->> 'inputs_version')::integer));
    SELECT * INTO v_schema FROM public.rule_term_schemas
     WHERE terms_kind = v_row ->> 'inputs_kind' AND terms_version = (v_row ->> 'inputs_version')::integer AND rule_role = 'inputs';
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: %s v%s is not a registered inputs schema (v5.4.2-17)', TG_RELID::regclass, v_row ->> 'inputs_kind', v_row ->> 'inputs_version'),
            ERRCODE = 'foreign_key_violation';
    END IF;
    IF NOT v_schema.accepts_new_rows THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: inputs schema %s v%s is frozen (v5.4.2-17)', TG_RELID::regclass, v_schema.terms_kind, v_schema.terms_version),
            ERRCODE = 'check_violation';
    END IF;
    v_err := public.rule_terms_errors(v_schema.json_schema, v_row -> 'inputs', false);
    IF cardinality(v_err) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: inputs are not a valid %s v%s: %s (v5.4.2-17)', TG_RELID::regclass, v_schema.terms_kind, v_schema.terms_version, array_to_string(v_err[1:10], '; ')),
            ERRCODE = 'check_violation';
    END IF;
    v_fp := 'sha256:' || encode(sha256(convert_to((v_row -> 'inputs')::text, 'UTF8')), 'hex');
    IF v_row ->> 'inputs_fingerprint' IS NOT NULL AND v_row ->> 'inputs_fingerprint' <> v_fp THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: the writer''s fingerprint %s is not the stored inputs'' %s — the core and the database disagree on the inputs (v5.4.2-17)',
                             TG_RELID::regclass, v_row ->> 'inputs_fingerprint', v_fp),
            ERRCODE = 'check_violation';
    END IF;
    RETURN jsonb_populate_record(NEW, jsonb_build_object('inputs_fingerprint', v_fp));
END;
$$;
COMMENT ON FUNCTION public.stamp_core_inputs() IS
    'v5.4.2-17 (rule-terms v2 §8; inventory C4). BEFORE INSERT on a core-written table: its inputs validated against their registered inputs schema (role inputs, unfrozen) — so numbers are canonical and the same inputs always hash the same — and inputs_fingerprint set to sha256 of the stored jsonb text, "sha256:<hex>". The writer may send the fingerprint it computed, as a cross-check; a different one is refused. calculated_by must name the core release.';


-- ----------------------------------------------------------------------------
-- 9. Audit findings (v2 §8; inventory C3)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.rule_audit_finding_kinds (
    kind_code          text NOT NULL,
    expects_decision   boolean NOT NULL,
    description        text NOT NULL,
    source_note        text NOT NULL,
    created_at         timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT rule_audit_finding_kinds_pkey PRIMARY KEY (kind_code),
    CONSTRAINT rule_audit_finding_kinds_code_check CHECK ((kind_code ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT rule_audit_finding_kinds_text_check CHECK (((description ~ '[[:alnum:]]'::text) AND (source_note ~ '[[:alnum:]]'::text)))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.rule_audit_finding_kinds FROM tally_app, tally_core;
GRANT SELECT ON public.rule_audit_finding_kinds TO tally_app, tally_core;
COMMENT ON TABLE public.rule_audit_finding_kinds IS
    'v5.4.2-17 (inventory C3). What a core audit pass can find. expects_decision: a finding of this kind names the decision that should have been recorded and the date it was due by (a missed decision). Platform-held; an area adds its own kinds.';

DROP TRIGGER IF EXISTS rule_audit_finding_kind_guard ON public.rule_audit_finding_kinds;
CREATE TRIGGER rule_audit_finding_kind_guard BEFORE INSERT OR UPDATE OR DELETE ON public.rule_audit_finding_kinds
    FOR EACH ROW EXECUTE FUNCTION public.enforce_rule_vocabulary_immutable();
ALTER TABLE public.rule_audit_finding_kinds ENABLE ALWAYS TRIGGER rule_audit_finding_kind_guard;
DROP TRIGGER IF EXISTS no_truncate ON public.rule_audit_finding_kinds;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.rule_audit_finding_kinds
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_rule_registry_no_truncate();
ALTER TABLE public.rule_audit_finding_kinds ENABLE ALWAYS TRIGGER no_truncate;

INSERT INTO public.rule_audit_finding_kinds (kind_code, expects_decision, description, source_note)
SELECT v.k, v.e, v.d, v.s
  FROM (VALUES
    ('missed_decision', true,
     'A decision the law required was never recorded by the date it was due: a return that should have fallen due, an accrual not made.',
     'Rule-terms v2 §8: a SQL view cannot see omissions; the core''s audits find them (-15 residual R6).'),
    ('record_disagrees_with_rule', false,
     'A recorded decision disagrees with what its cited rule, evaluated by this core release, says.',
     'Rule-terms v2 §8: the discrepancy views become core audit passes, not a second interpreter of the law.'),
    ('tariff_looser_than_law', false,
     'A utility''s tariff row is looser than a law row that came into force after it was written.',
     'Inventory U3: the law row records the law; it is never refused to protect a tariff.'),
    ('published_value_differs', false,
     'The utility''s applied value differs from the published value in force (a deposit interest rate).',
     'v5.4.2-15 deposit_interest_rate_discrepancies, replaced by a core audit pass (inventory C3).')
  ) AS v(k, e, d, s)
 WHERE NOT EXISTS (SELECT 1 FROM public.rule_audit_finding_kinds x WHERE x.kind_code = v.k);

CREATE TABLE IF NOT EXISTS public.rule_audit_findings (
    id                  uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id           uuid NOT NULL,
    finding_kind        text NOT NULL,
    subject_table       text NOT NULL,
    subject_id          uuid NOT NULL,
    rule_table          text,
    rule_row_id         uuid,
    terms_kind          text,
    terms_version       integer,
    core_release        text NOT NULL,
    coverage_from       date NOT NULL,
    coverage_to         date NOT NULL,
    expected_decision   text,
    expected_by         date,
    detail              jsonb NOT NULL,
    found_at            timestamp with time zone DEFAULT now() NOT NULL,
    recorded_txid       bigint DEFAULT txid_current() NOT NULL,
    CONSTRAINT rule_audit_findings_pkey PRIMARY KEY (id),
    CONSTRAINT rule_audit_findings_tenant_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT rule_audit_findings_kind_fkey FOREIGN KEY (finding_kind) REFERENCES public.rule_audit_finding_kinds(kind_code),
    CONSTRAINT rule_audit_findings_schema_fkey FOREIGN KEY (terms_kind, terms_version) REFERENCES public.rule_term_schemas(terms_kind, terms_version),
    CONSTRAINT rule_audit_findings_rule_check
        CHECK ((((rule_table IS NULL) AND (rule_row_id IS NULL)) OR ((rule_table IS NOT NULL) AND (rule_row_id IS NOT NULL)))),
    CONSTRAINT rule_audit_findings_coverage_check CHECK ((coverage_to >= coverage_from)),
    CONSTRAINT rule_audit_findings_expected_check
        CHECK ((((expected_decision IS NULL) = (expected_by IS NULL)) AND ((expected_decision IS NULL) OR (expected_decision ~ '^[a-z][a-z0-9_]*$'::text)))),
    CONSTRAINT rule_audit_findings_release_check CHECK ((core_release ~ '[[:alnum:]]'::text)),
    CONSTRAINT rule_audit_findings_detail_check CHECK ((jsonb_typeof(detail) = 'object'::text)),
    CONSTRAINT rule_audit_findings_tenant_id_key UNIQUE (tenant_id, id)
);
CREATE INDEX IF NOT EXISTS idx_rule_audit_findings_tenant ON public.rule_audit_findings USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_rule_audit_findings_subject ON public.rule_audit_findings USING btree (subject_table, subject_id);
ALTER TABLE public.rule_audit_findings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rule_audit_findings FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.rule_audit_findings;
CREATE POLICY tenant_isolation ON public.rule_audit_findings USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.rule_audit_findings FROM tally_app;
REVOKE UPDATE, DELETE, TRUNCATE ON public.rule_audit_findings FROM tally_core;
GRANT SELECT ON public.rule_audit_findings TO tally_app;
GRANT SELECT, INSERT ON public.rule_audit_findings TO tally_core;
COMMENT ON TABLE public.rule_audit_findings IS
    'v5.4.2-17 (rule-terms v2 §8; inventory C3). What a core audit pass found, per tenant: the kind; the subject record (a table of the tenant''s and a row of it in this tenant); the rule row it judged by, if any, with that row''s kind and version stamped from the row; the core release; the span the pass examined (coverage); for a missed decision, the decision expected and the date it was due by; detail (an object). found_at and recorded_txid stamped. Written only by tally_core (or a migration); append-only — never edited or deleted. What a person did about a finding is a row of rule_audit_finding_dispositions.';

CREATE OR REPLACE FUNCTION public.enforce_rule_audit_finding() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_kind     public.rule_audit_finding_kinds%ROWTYPE;
    v_cls      regclass;
    v_tenant   uuid;
    v_rule     jsonb;
    v_cfg      public.rule_tables%ROWTYPE;
BEGIN
    IF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION USING
            MESSAGE = 'an audit finding is never edited or deleted (v5.4.2-17)',
            ERRCODE = 'restrict_violation';
    END IF;
    SELECT * INTO v_kind FROM public.rule_audit_finding_kinds WHERE kind_code = NEW.finding_kind;
    IF FOUND AND (v_kind.expects_decision <> (NEW.expected_decision IS NOT NULL) OR v_kind.expects_decision <> (NEW.expected_by IS NOT NULL)) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('a %s finding %s the decision expected and the date it was due by (v5.4.2-17)', NEW.finding_kind,
                             CASE WHEN v_kind.expects_decision THEN 'names' ELSE 'does not name' END),
            ERRCODE = 'check_violation';
    END IF;
    -- The subject: a row of a tenant table, in this finding's tenant.
    v_cls := to_regclass(NEW.subject_table);
    IF v_cls IS NULL OR NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                                     WHERE c.oid = v_cls AND n.nspname = 'public' AND c.relkind IN ('r', 'p'))
       OR NOT EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = v_cls AND a.attname = 'tenant_id' AND NOT a.attisdropped)
       OR NOT EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = v_cls AND a.attname = 'id' AND NOT a.attisdropped) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('audit finding: %s is not a tenant table with an id (v5.4.2-17)', NEW.subject_table),
            ERRCODE = 'foreign_key_violation';
    END IF;
    NEW.subject_table := v_cls::text;
    EXECUTE format('SELECT t.tenant_id FROM %s t WHERE t.id = $1', v_cls) INTO v_tenant USING NEW.subject_id;
    IF v_tenant IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION USING
            MESSAGE = format('audit finding: %s has no row %s in tenant %s (or it is not visible) (v5.4.2-17)', NEW.subject_table, NEW.subject_id, NEW.tenant_id),
            ERRCODE = 'foreign_key_violation';
    END IF;
    -- The rule row: of a registered rule table; a tariff row of this tenant.
    IF NEW.rule_table IS NOT NULL THEN
        v_cls := to_regclass(NEW.rule_table);
        SELECT * INTO v_cfg FROM public.rule_tables WHERE table_name = v_cls;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING
                MESSAGE = format('audit finding: %s is not a registered rule table (v5.4.2-17)', NEW.rule_table),
                ERRCODE = 'foreign_key_violation';
        END IF;
        NEW.rule_table := v_cls::text;
        EXECUTE format('SELECT to_jsonb(t) FROM %s t WHERE t.id = $1', v_cls) INTO v_rule USING NEW.rule_row_id;
        IF v_rule IS NULL OR (v_cfg.rule_role = 'tariff' AND (v_rule ->> 'tenant_id')::uuid IS DISTINCT FROM NEW.tenant_id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('audit finding: %s has no row %s for tenant %s (v5.4.2-17)', NEW.rule_table, NEW.rule_row_id, NEW.tenant_id),
                ERRCODE = 'foreign_key_violation';
        END IF;
        NEW.terms_kind := v_rule ->> 'terms_kind';
        NEW.terms_version := (v_rule ->> 'terms_version')::integer;
    ELSE
        NEW.terms_kind := NULL;
        NEW.terms_version := NULL;
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_path_query(NEW.detail, 'strict $.**') v WHERE jsonb_typeof(v) = 'null') THEN
        RAISE EXCEPTION USING MESSAGE = 'audit finding: detail holds no nulls — say what was found (v5.4.2-17)', ERRCODE = 'check_violation';
    END IF;
    NEW.found_at := now();
    NEW.recorded_txid := txid_current();
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_rule_audit_finding() IS
    'v5.4.2-17 (inventory C3). BEFORE INSERT OR UPDATE OR DELETE on rule_audit_findings (ENABLE ALWAYS): no edit, no delete; a missed decision names what and by when, other kinds do not; the subject is a row of a public tenant table in this finding''s tenant; the rule row is a row of a registered rule table (a tariff row of this tenant), and its kind and version are stamped from it; detail holds no nulls; found_at and recorded_txid stamped. Who may insert is the grants: tally_core, not tally_app.';

DROP TRIGGER IF EXISTS rule_audit_finding_guard ON public.rule_audit_findings;
CREATE TRIGGER rule_audit_finding_guard BEFORE INSERT OR UPDATE OR DELETE ON public.rule_audit_findings
    FOR EACH ROW EXECUTE FUNCTION public.enforce_rule_audit_finding();
ALTER TABLE public.rule_audit_findings ENABLE ALWAYS TRIGGER rule_audit_finding_guard;
DROP TRIGGER IF EXISTS no_truncate ON public.rule_audit_findings;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.rule_audit_findings
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_rule_registry_no_truncate();
ALTER TABLE public.rule_audit_findings ENABLE ALWAYS TRIGGER no_truncate;


-- What a person did about a finding (inventory C3; review r1, all three):
-- append-only rows, so a finding's history is every disposition in order.
CREATE TABLE IF NOT EXISTS public.rule_audit_disposition_kinds (
    kind_code     text NOT NULL,
    description   text NOT NULL,
    created_at    timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT rule_audit_disposition_kinds_pkey PRIMARY KEY (kind_code),
    CONSTRAINT rule_audit_disposition_kinds_code_check CHECK ((kind_code ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT rule_audit_disposition_kinds_text_check CHECK ((description ~ '[[:alnum:]]'::text))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.rule_audit_disposition_kinds FROM tally_app, tally_core;
GRANT SELECT ON public.rule_audit_disposition_kinds TO tally_app, tally_core;
COMMENT ON TABLE public.rule_audit_disposition_kinds IS
    'v5.4.2-17 (inventory C3). What a person can record about an audit finding. Platform-held; never edited or deleted; an area adds its own.';
DROP TRIGGER IF EXISTS rule_audit_disposition_kind_guard ON public.rule_audit_disposition_kinds;
CREATE TRIGGER rule_audit_disposition_kind_guard BEFORE INSERT OR UPDATE OR DELETE ON public.rule_audit_disposition_kinds
    FOR EACH ROW EXECUTE FUNCTION public.enforce_rule_vocabulary_immutable();
ALTER TABLE public.rule_audit_disposition_kinds ENABLE ALWAYS TRIGGER rule_audit_disposition_kind_guard;
DROP TRIGGER IF EXISTS no_truncate ON public.rule_audit_disposition_kinds;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.rule_audit_disposition_kinds
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_rule_registry_no_truncate();
ALTER TABLE public.rule_audit_disposition_kinds ENABLE ALWAYS TRIGGER no_truncate;
INSERT INTO public.rule_audit_disposition_kinds (kind_code, description)
SELECT v.k, v.d
  FROM (VALUES
    ('acknowledged', 'Seen; what will be done is in the note.'),
    ('corrected', 'The record was corrected; the note says how (the correction is its own record).'),
    ('dismissed', 'The finding was wrong or does not apply; the note says why.')
  ) AS v(k, d)
 WHERE NOT EXISTS (SELECT 1 FROM public.rule_audit_disposition_kinds x WHERE x.kind_code = v.k);

CREATE TABLE IF NOT EXISTS public.rule_audit_finding_dispositions (
    id              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id       uuid NOT NULL,
    finding_id      uuid NOT NULL,
    disposition     text NOT NULL,
    note            text NOT NULL,
    decided_by      uuid,
    decided_at      timestamp with time zone DEFAULT now() NOT NULL,
    recorded_txid   bigint DEFAULT txid_current() NOT NULL,
    CONSTRAINT rule_audit_finding_dispositions_pkey PRIMARY KEY (id),
    CONSTRAINT rule_audit_finding_dispositions_finding_fkey FOREIGN KEY (tenant_id, finding_id)
        REFERENCES public.rule_audit_findings(tenant_id, id),
    CONSTRAINT rule_audit_finding_dispositions_kind_fkey FOREIGN KEY (disposition) REFERENCES public.rule_audit_disposition_kinds(kind_code),
    CONSTRAINT rule_audit_finding_dispositions_user_fkey FOREIGN KEY (decided_by) REFERENCES public.users(id),
    CONSTRAINT rule_audit_finding_dispositions_note_check CHECK ((note ~ '[[:alnum:]]'::text))
);
CREATE INDEX IF NOT EXISTS idx_rule_audit_finding_dispositions_tenant ON public.rule_audit_finding_dispositions USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_rule_audit_finding_dispositions_finding ON public.rule_audit_finding_dispositions USING btree (finding_id);
ALTER TABLE public.rule_audit_finding_dispositions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rule_audit_finding_dispositions FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.rule_audit_finding_dispositions;
CREATE POLICY tenant_isolation ON public.rule_audit_finding_dispositions USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
REVOKE UPDATE, DELETE, TRUNCATE ON public.rule_audit_finding_dispositions FROM tally_app;
GRANT SELECT, INSERT ON public.rule_audit_finding_dispositions TO tally_app;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.rule_audit_finding_dispositions FROM tally_core;
GRANT SELECT ON public.rule_audit_finding_dispositions TO tally_core;
COMMENT ON TABLE public.rule_audit_finding_dispositions IS
    'v5.4.2-17 (inventory C3; review r1, all three). What a person did about an audit finding — acknowledged, corrected, dismissed — with a note, in the finding''s tenant; decided_by is the session''s user and decided_at the time, both stamped. Written by tally_app (people act on findings; the core records them); append-only — never edited or deleted. Which kinds an area allows, and who may record them, is the area''s.';

CREATE OR REPLACE FUNCTION public.enforce_rule_audit_finding_disposition() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION USING
            MESSAGE = 'a finding''s disposition is never edited or deleted: record another (v5.4.2-17)',
            ERRCODE = 'restrict_violation';
    END IF;
    NEW.decided_by := nullif(current_setting('app.user_id', true), '')::uuid;
    IF NEW.decided_by IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'a finding''s disposition is a person''s act: app.user_id names who (v5.4.2-17)',
            ERRCODE = 'not_null_violation';
    END IF;
    NEW.decided_at := now();
    NEW.recorded_txid := txid_current();
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS rule_audit_finding_disposition_guard ON public.rule_audit_finding_dispositions;
CREATE TRIGGER rule_audit_finding_disposition_guard BEFORE INSERT OR UPDATE OR DELETE ON public.rule_audit_finding_dispositions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_rule_audit_finding_disposition();
ALTER TABLE public.rule_audit_finding_dispositions ENABLE ALWAYS TRIGGER rule_audit_finding_disposition_guard;
DROP TRIGGER IF EXISTS no_truncate ON public.rule_audit_finding_dispositions;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.rule_audit_finding_dispositions
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_rule_registry_no_truncate();
ALTER TABLE public.rule_audit_finding_dispositions ENABLE ALWAYS TRIGGER no_truncate;


-- ----------------------------------------------------------------------------
-- 10. The tail (AC-32)
-- ----------------------------------------------------------------------------
-- EXECUTE for the core: every invoker-rights function in public, now that
-- this patch's own exist (tu.sql revokes PUBLIC's EXECUTE on new functions,
-- -11 5b), except registration and seeding, which are a migration's acts.
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT p.oid::regprocedure AS f
               FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND NOT p.prosecdef AND p.prokind IN ('f', 'p') LOOP
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO tally_core', r.f);
    END LOOP;
END
$$;
GRANT EXECUTE ON FUNCTION public.get_user_tenant_id() TO tally_core;
GRANT EXECUTE ON FUNCTION public.is_platform_admin() TO tally_core;
REVOKE ALL ON FUNCTION public.rule_table_register(regclass, text, text, text[], text[], regprocedure, regprocedure, regclass, regprocedure, regprocedure)
    FROM PUBLIC, tally_app, tally_core;
REVOKE ALL ON FUNCTION public.assert_tenant_isolation_invariants() FROM tally_core;
REVOKE ALL ON FUNCTION public.rule_row_seed(regclass, jsonb) FROM PUBLIC, tally_app, tally_core;

-- The core's invariants, as a reusable assertion (review r2, Codex S2): the
-- tail runs it now, and CI runs it last on every build (tests/ci.sh), so a
-- later patch that hands the core more than it should is caught then, not
-- only when this patch applies.
CREATE OR REPLACE FUNCTION public.assert_core_role_invariants() RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_bad text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tally_core') THEN
        RAISE EXCEPTION USING MESSAGE = 'tally_core does not exist (v5.4.2-17)', ERRCODE = 'invalid_grant_operation';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tally_core'
                  AND (rolsuper OR rolbypassrls OR rolcreaterole OR rolcreatedb OR rolcanlogin OR rolreplication)) THEN
        RAISE EXCEPTION USING
            MESSAGE = 'tally_core is NOLOGIN and holds no SUPERUSER, BYPASSRLS, CREATEROLE, CREATEDB or REPLICATION — a login user is granted membership (v5.4.2-17)',
            ERRCODE = 'invalid_grant_operation';
    END IF;
    IF pg_has_role('tally_core', 'tally_app', 'MEMBER') OR pg_has_role('tally_app', 'tally_core', 'MEMBER') THEN
        RAISE EXCEPTION USING
            MESSAGE = 'tally_core and tally_app are members of each other (v5.4.2-17)',
            ERRCODE = 'invalid_grant_operation';
    END IF;
    -- A member of no role at all (review r3, Opus S1): membership of a role
    -- with BYPASSRLS or SUPERUSER would let the core SET ROLE past every
    -- tenant policy. Its login users are members of it, never the reverse.
    SELECT string_agg(m.roleid::regrole::text, ', ' ORDER BY 1) INTO v_bad
      FROM pg_auth_members m WHERE m.member = 'tally_core'::regrole;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tally_core is a member of %s: it belongs to no role (v5.4.2-17)', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
    -- No materialized view (row-level security does not reach one), column
    -- grants included (has_any_column_privilege, as AC-32 reads tally_app).
    SELECT string_agg(n.nspname || '.' || c.relname, ', ' ORDER BY 1) INTO v_bad
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE c.relkind = 'm' AND n.nspname NOT IN ('pg_catalog', 'information_schema')
       AND has_any_column_privilege('tally_core', c.oid, 'SELECT');
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tally_core reaches materialized views %s, which row-level security does not reach (v5.4.2-17)', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_default_acl d, aclexplode(d.defaclacl) a WHERE a.grantee = 'tally_core'::regrole) THEN
        RAISE EXCEPTION USING
            MESSAGE = 'tally_core holds a default privilege: its grants are explicit (v5.4.2-17 R8)',
            ERRCODE = 'invalid_grant_operation';
    END IF;
    -- No code of its own (the trigger-depth fences): no TEMP, no CREATE on the
    -- database, and no CREATE on any schema — through PUBLIC as well as
    -- directly. A TEMPLATE clone drops the database ACL; revoke TEMP from
    -- PUBLIC after cloning.
    SELECT string_agg(n.nspname, ', ' ORDER BY 1) INTO v_bad
      FROM pg_namespace n
     WHERE n.nspname NOT LIKE 'pg\_%' AND n.nspname <> 'information_schema'
       AND has_schema_privilege('tally_core', n.oid, 'CREATE');
    IF has_database_privilege('tally_core', current_database(), 'TEMP') OR has_database_privilege('tally_core', current_database(), 'CREATE')
       OR v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tally_core can define code (TEMP, CREATE on the database, or CREATE on schema %s) — after a TEMPLATE clone, revoke TEMP from PUBLIC (v5.4.2-17)', coalesce(v_bad, 'none')),
            ERRCODE = 'invalid_grant_operation';
    END IF;
END;
$$;
COMMENT ON FUNCTION public.assert_core_role_invariants() IS
    'v5.4.2-17 (inventory C1; review r1-r2). Raises unless tally_core still holds no dangerous attribute (NOLOGIN; no SUPERUSER, BYPASSRLS, CREATEROLE, CREATEDB, REPLICATION), is not a member of tally_app nor tally_app of it, reaches no materialized view (column grants included), holds no default privilege, and can define no code (no TEMP; no CREATE on the database or any schema). Run in this patch''s tail and last in CI, as assert_tenant_isolation_invariants() is. Invoker rights; owner-only.';
REVOKE ALL ON FUNCTION public.assert_core_role_invariants() FROM PUBLIC, tally_app, tally_core;
DO $$
BEGIN
    PERFORM public.assert_core_role_invariants();
END
$$;

DO $$
BEGIN
    PERFORM public.assert_tenant_isolation_invariants();
    RAISE NOTICE 'v5.4.2-17: verified via assert_tenant_isolation_invariants() — rule_audit_findings is FORCE RLS under the canonical policy; every function added here is invoker; tally_core reads, writes only audit findings, and defines no code.';
END;
$$;


-- ----------------------------------------------------------------------------
-- 11. Residuals
-- ----------------------------------------------------------------------------
-- R1. WHICH USER A CORE SESSION IS. tally_core sets app.user_id like any
--     session, and the tenant policy keys on that user's tenant. Whether the
--     core acts as a per-tenant service user, or as the user whose action
--     triggered it, is decided with the first core-written area (it decides
--     what evaluated_by means on -13's evaluations; inventory C2).
-- R2. CORRECTION LINEAGE. A rule row wrong from its first day is repaired by
--     a reviewed migration; the lineage that separates legal validity from
--     recorded revision, and re-evaluates the records the row touched, is
--     designed when the first repair is needed (v2 §11; -15 R4; -13 R7;
--     inventory T7).
-- R3. AN AREA KEY HAS NO "EVERY VALUE". Owner type, system kind and
--     jurisdiction status take sets and NULL (every one); an area's own key
--     columns are NOT NULL and compared with =, so a law that applies to
--     every customer class is a row per class, or the area keeps class out
--     of its key. The -15 rewrite decides for deposits (inventory U5).
-- R4. PUBLISHED VALUES HAVE NO CLOSE FLOOR. Nothing cites one yet; the first
--     area whose records do (a statutory rate a record applies) adds the
--     floor and the citation handshake, as rule_row_cite does for rows.
-- R5. A TARIFF'S PROFILE COVERAGE IS READ, NOT LOCKED. rule_tariff_check
--     locks the law rows it compares against, not the utility's profiles; a
--     profile closed or voided concurrently can leave a tariff over days no
--     profile covers. The tariff is still compared with the law under the
--     profile it was written for; a core audit finds a tariff with no
--     profile.
-- R6. THE LAW ROW A TARIFF IS COMPARED WITH IS THE ONE IN FORCE WHEN IT IS
--     WRITTEN. A law row inserted later over the tariff's range is not
--     compared at its insert (the law is never refused to protect a tariff,
--     inventory U3); the core's audit records tariff_looser_than_law.
-- R7. THE INTERPRETER IS ONE IMPLEMENTATION OF A SUBSET. Agreement with a
--     standard JSON Schema validator is proved by the CI cross-check over
--     the fixture documents (tools/law), not by construction; a schema
--     feature outside the subset is refused at registration, never ignored.
-- R8. THE CORE'S GRANTS ARE EXPLICIT. tally_core holds no default
--     privileges, so a table or function a later patch adds is invisible to
--     the core until that patch grants it (SELECT, EXECUTE, and INSERT on a
--     core-only record). It fails closed — a forgotten grant is a refusal,
--     not a leak — and it keeps materialized views, which row-level security
--     does not reach, away from the core by construction.
-- R9. A TABLE'S FACETS ARE FIXED. A version's declared facets must equal
--     its table's facet columns, and the registration is never edited, so a
--     later version cannot add a facet to an existing table. A new facet is a
--     new table (or a later, sanctioned extension that appends the column and
--     fills it once, as adoption fills a document) — designed when an area
--     first needs it (review r1, Opus S4).
-- R10. PUBLISHED VALUES ARE NOT SCOPED BY CUSTOMER CLASS. The inventory's P1
--     named class from -15's deposit_interest_rate_law, but no source
--     publishes a class-specific value (Utilities Code §183.003 publishes one
--     rate per year); by the stopping rule, a class dimension waits for a
--     source that needs it, and would then be a typed column with the class
--     vocabulary of its area (review r1, all three).
-- R11. GOLDEN SCENARIOS ARE SHAPE-CHECKED, NOT SCHEMA-CHECKED. A scenario's
--     inputs and expected outputs are the core's decision-point types, which
--     do not exist yet; tools/law checks each is a non-empty mapping. When
--     the core exists its types give the schemas (v2 §5) and lawc validates
--     scenarios against them (review r1, Codex B8).
-- R12. A TARIFF TABLE MAY NAME NO LAW TABLE. Registration lets a tariff table
--     name both a law table and a comparator, or neither — a utility's own
--     rule that no law speaks to (a fee schedule the law leaves untouched).
--     Such a table is not checked against any law; an area that has law must
--     name it (review r1, Codex S2).
-- R13. A FINDING'S SUBJECT IS CHECKED WHEN THE FINDING IS WRITTEN. It names a
--     row of a tenant table, without a foreign key (the table varies); the
--     records the core audits are append-only by their areas' design, so the
--     reference stays good, but nothing here enforces that (review r1, Codex S4).
-- R14. THE -13 ADOPTION SEQUENCE. backbilling_rules must (1) gain the template
--     columns, the applicability set to what §7.45 binds, before (2) it is
--     registered as adopting; (3) its own history trigger
--     (enforce_backbilling_rule_history, which refuses every update but a
--     close) is dropped in the same migration; and (4) its adoption check
--     (p_adoption_check, run once, when the empty document is filled — not
--     the permanent insert check, which every later row passes through)
--     compares each document — window terms included — with the row's old
--     columns. Steps 1 and 3 are the migration's, reviewed with it (review
--     r1, Fable S11, Codex).
-- R15. THE FINGERPRINT IS OVER POSTGRESQL'S jsonb TEXT. sha256 of the stored
--     inputs' text form: keys ordered by length, then bytes; ", " and ": "
--     separators; numbers canonical (enforced). A core that sends its own
--     fingerprint to confirm must reproduce that form (a test vector belongs
--     with the core's first inputs kind); one that does not, reads the
--     stamped value back (review r1, Opus N2).
-- R16. THE AREA DECIDES WHICH LAW ROWS A TARIFF SPEAKS TO BEYOND SHARED KEYS.
--     The tariff check filters law rows on the key columns the two tables
--     share by name. A tariff keyed on the utility's own vocabulary (a city's
--     own classes) must not share that column name with the law table; the
--     comparator then chooses the law rows itself, and coverage is over all
--     of them (review r1, Opus S9, Codex).
-- R17. A CLOSE UNDER A TARIFF IS ALLOWED. A law table's close floor counts
--     the area's citing records, not tariff rows; a law row closed under a
--     tariff that was measured against it leaves the tariff to the core's
--     audit, like a later law (R6) (review r1, Fable).
-- R18. A TARIFF CHECK MAY GIVE UP OR DEADLOCK, NEVER PASS STALE. It re-reads
--     its law rows at most five times (55P03 when they keep changing); a
--     close of two law rows taken in another order than the tariff's
--     ordered locks can deadlock, and PostgreSQL aborts one side (40P01).
--     Either is a retry, never a stale acceptance. The state check accepts a
--     state place of that code at any date: states do not come and go
--     inside the dates the law covers (review r2, Opus notes).
-- ============================================================================
-- END PATCH v5.4.2-17
-- ============================================================================
