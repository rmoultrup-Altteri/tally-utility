# law/ — law content as files

Under the rule-terms convention (`application/rule-terms-convention-v2-2026-10-06.md`; built in `sql/v5.4.2-17-rule-terms-convention.sql`), each law row's content is a JSON document (`terms`) that a registered schema checks on every write. The content is authored here, as YAML files in git:
- reviewed as diffs;
- loaded by a reviewed migration;
- checked by CI on every push.

The format follows OpenFisca's parameter files (dated values, a citation per value, tests beside the law). We take the format only: there is no OpenFisca runtime.

```
law/
  <area>/                      one directory per law area (deposits, backbilling, …)
    <kind>.v<N>.schema.json    the JSON Schema of a kind's version, as registered
    <table>.yaml               the law rows of one table, for one state and service
    <table>.seed.sql           what tools/law/lawc.py emits from it (generated; committed)
  fixtures/zz/                 a FICTIONAL state's law: the convention's own fixture
```

## A law file

```yaml
table: public.zz_fee_rules         # the registered law table
kind: zz_fee                       # its kind …
version: 1                         # … and version (rule_term_schemas)
key: [customer_class]              # the table's own key columns
schema: zz_fee.v1.schema.json      # beside this file
rows:
  - name: residential_iou          # unique in the file; names the row in reviews and errors
    state_code: ZZ
    service_type: gas
    owner_types: [investor_owned, cooperative]   # or: any
    system_kinds: any                            # or: a list
    commission_jurisdiction: true                # true, false or any
    customer_class: residential                  # each key column
    effective_from: "2000-01-01"
    effective_to: "2030-01-01"                   # optional: only a law with a known end
    source_note: ZZ Code 1.1
    terms:                                       # the document; the schema decides its shape
      governs: law
      citation: ZZ Code 1.1
      fee: {strategy: flat, version: 1, id: f1, cap: 50, citation: ZZ Code 1.1(a)}
      waivers:
        - {id: w1, class: senior, effect: halve}
    scenarios:                                   # optional: the row's executable meaning
      - name: a senior pays half the capped fee
        inputs: {customer_class: residential, waiver_class: senior, tariff_fee: 40}
        expected: {fee: 20}
```

**Applicability is never omitted.** `owner_types`, `system_kinds` and `commission_jurisdiction` are always written: `any`, or what the law names. "Every owner type" is a statement about the law, so the file has to say it.

### What the loader refuses, and why

- **Every value is read as text, and the schema types it.**
  - `yes`, `1.10`, `2004-07-12` and `null` cannot silently become a boolean, a float, a date or nothing.
  - A boolean is `true` or `false`.
  - A number is digits with an optional sign and fraction: no exponent, no leading `+`.
- **Numbers are written canonically: `1.5`, not `1.50`; `2`, not `2.0`.** The database stores and hashes exactly what is written, and refuses a non-canonical number.
- **Duplicate keys, anchors and aliases, merge keys (`<<`) and explicit tags (even `!`) are refused.** Each hides or repeats content a reviewer reads once.
- **A null is refused anywhere in a document.** "Unknown" is a value the schema names, such as `unruled`, never an absence (v2 §3).
- **No control characters (newline, tab, …) in any string or key.** Validators disagree on how a pattern treats a trailing newline; nothing the law says needs one.
- **Nesting is at most 64 levels deep.**
- **JSON examples write numbers out in full, without exponents.** The database rewrites `1e2` as `100`, so the file would no longer say what is stored.

### A document

- **Strategies, not logic.** A decision point names a strategy and its version: `{"strategy": "flat", "version": 1, …}`. The core resolves `(decision point, strategy, version)` to code (v2 §4). There are no expressions, conditions or formulas in a document.
- **Component ids.** An `id` names a part a record can cite (`"id": "p1"`). It is unique within the document.
- **Citations per section.** A citation goes where the provision applies, not only at the root.
- **Delegated law.** Every law kind admits `{"governs": "delegated_to_utility", "citation": …}`: the law leaves the matter to the utility's own tariff. This is not the same as no law; with no law row, the database refuses (places finding 1).
- **Published values.** A value published on its own schedule is named, not copied: `{"source": "published", "name": "…"}`. The core reads it from `rule_parameter_values` on the date. An area that wants the database to check the names declares a `text[]` facet over those paths, with `rule_parameters` as its vocabulary.

## A schema

A kind's schema is JSON Schema 2020-12, limited to the subset the database's validator enforces. Registration refuses anything outside it, so a schema can never claim a check that does not run:

| Where | Allowed |
|---|---|
| Anywhere | `title`, `description`, `$comment` |
| Root only | `$schema` (2020-12), `$id`, `$defs` |
| A reference | `{"$ref": "#/$defs/<name>"}` and nothing else; never a chain of references |
| A union | `{"oneOf": […]}` of object schemas, with exactly one property that every branch requires as a string `const` (the discriminator: `strategy`, `governs`) |
| `object` | `properties`, `required`, `additionalProperties: false` (required) |
| `array` | `items` (required), `minItems`, `maxItems`, `uniqueItems` |
| `string` | `const` or `enum`, `minLength`, `maxLength`, and `pattern` from two only: `[A-Za-z0-9]` (contains a letter or digit) and `^[a-z][a-z0-9_]*$` (a code) |
| `integer`, `number` | `minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum` |
| `boolean` | `const` |

**A law kind's root** is a `oneOf` on `governs`, and one branch is exactly:

```json
{"type": "object", "additionalProperties": false, "required": ["governs", "citation"],
 "properties": {"governs": {"type": "string", "const": "delegated_to_utility"},
                "citation": {"type": "string", "pattern": "[A-Za-z0-9]"},
                "note": {"type": "string", "pattern": "[A-Za-z0-9]"}}}
```

`note` is optional.

**Versions** (v2 §11):
- A version is registered once, numbered 1, 2, …, and never edited.
- A new version is for a breaking shape change only. Additive optional fields, with a defined meaning when absent, do not need one.
- A version is frozen (no new rows) rather than retired: rows that use it keep it forever, and the core keeps a reader for it.

## Seeding

```sh
python3 -m venv tools/law/.venv && tools/law/.venv/bin/pip install -r tools/law/requirements.txt
tools/law/.venv/bin/python tools/law/lawc.py check law/<area>/<table>.yaml
tools/law/.venv/bin/python tools/law/lawc.py emit  law/<area>/<table>.yaml -o law/<area>/<table>.seed.sql
```

The seed SQL calls `public.rule_row_seed()` once per row. Each call does one of three things:
- inserts the row, through the same trigger as any insert;
- finds the row unchanged and returns its id;
- **raises**, naming what differs, if a row with the same applicability, key and start already holds anything else.

A seed is never an upsert. A change in the law is a close and a new row, written as a new row in the file with the old row's `effective_to` set, and closed in the database by a reviewed migration.

## CI

`tests/ci.sh` (and `.github/workflows/ci.yml`) runs `tests/v5.4.2-17/lawfiles-17.sh` against a scratch database. It checks five things:
1. Every law file is valid.
2. The committed seed SQL is what the files emit today.
3. Seeding twice changes nothing; every stored document equals its file, and no seeded table holds a row without a file.
4. For every `<kind>.vN.schema.json` under `law/`, the file equals the schema registered for that version, and the database validator agrees with a standard JSON Schema validator (`jsonschema`, Draft 2020-12, plus the fixed rules) on its examples (`examples/<kind>*.yaml`) and on every single-edit mutation of each. A schema without examples fails.

   This shows agreement on that corpus; it is not a proof for every possible document (patch residual R7). The corpus includes edits at type, length and number edges, control characters, non-ASCII text and branch switches.
5. The strict loader refuses what it should.

Golden scenarios are checked for shape now. They run against the core once it exists.
