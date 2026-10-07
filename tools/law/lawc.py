#!/usr/bin/env python3
"""lawc — law files on the rule-terms convention (v5.4.2-17).

Law content is authored as YAML files in git and loaded by a reviewed
migration (rule-terms v2 §6). This tool reads those files strictly, types
every value from its registered JSON Schema, writes the seed SQL a
migration runs, and runs the CI checks (inventory L1-L3, V10):

  lawc.py check   FILE...            lint, type and validate law files
  lawc.py emit    FILE... [-o OUT]   the seed SQL (public.rule_row_seed calls)
  lawc.py crosscheck SCHEMA DOC...   the database validator and a standard
                                     JSON Schema 2020-12 validator must agree
                                     on every document and on a mutation
                                     corpus generated from them
  lawc.py roundtrip FILE...          seed into the database (twice: the second
                                     run must change nothing), then compare
                                     every stored row with its file

The database commands run psql through LAWC_PSQL (default:
"docker exec -i tally-pg psql -U tally -d tally"); set LAWC_DB to change
only the database name.

Strictness, and why:
  * Every YAML scalar is read as a string (no implicit typing), so "yes",
    "1.10", "2004-07-12" and "null" cannot silently become a boolean, a
    float, a date or a null; the schema says what each value is.
  * Duplicate keys, anchors, aliases, merge keys and explicit tags are
    refused: each hides or repeats content a reviewer reads once.
  * Numbers are exact (Decimal) and must be WRITTEN canonically in the file
    (no trailing fractional zeros: 1.5, not 1.50), as the database
    requires, so the file shows exactly what is stored and a value hashes
    the same wherever it is serialised.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any, Iterator

import yaml
from jsonschema import Draft202012Validator

REPO = Path(__file__).resolve().parents[2]
JSON_SCHEMA_2020_12 = "https://json-schema.org/draft/2020-12/schema"
NUMBER_RE = re.compile(r"-?(0|[1-9][0-9]*)(\.[0-9]+)?")
DATE_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")
CODE_RE = re.compile(r"[a-z][a-z0-9_]*")
ENVELOPE_KEYS = {"name", "state_code", "service_type", "owner_types", "system_kinds",
                 "commission_jurisdiction", "effective_from", "effective_to", "source_note",
                 "terms", "scenarios"}
FILE_KEYS = {"table", "kind", "version", "key", "schema", "rows"}


class LawError(Exception):
    """A law file, schema or document the convention refuses."""


# ---------------------------------------------------------------------------
# Strict YAML
# ---------------------------------------------------------------------------

class StrictLoader(yaml.BaseLoader):
    """BaseLoader (every scalar a string) that refuses duplicate keys,
    anchors, aliases, merge keys and explicit tags."""

    def compose_node(self, parent, index):  # noqa: D401 — PyYAML hook
        if self.check_event(yaml.AliasEvent):
            event = self.peek_event()
            raise LawError(f"line {event.start_mark.line + 1}: aliases (*{event.anchor}) are refused — write the content out")
        event = self.peek_event()
        anchor = getattr(event, "anchor", None)
        if anchor is not None:
            raise LawError(f"line {event.start_mark.line + 1}: anchors (&{anchor}) are refused — write the content out")
        tag = getattr(event, "tag", None)
        if tag is not None:
            raise LawError(f"line {event.start_mark.line + 1}: explicit tags ({tag}) are refused — the schema types values")
        return super().compose_node(parent, index)

    def construct_mapping(self, node, deep=False):
        seen: dict[str, int] = {}
        for key_node, _ in node.value:
            key = self.construct_scalar(key_node) if isinstance(key_node, yaml.ScalarNode) else None
            if key is None:
                raise LawError(f"line {key_node.start_mark.line + 1}: a mapping key must be a plain string")
            if key == "<<":
                raise LawError(f"line {key_node.start_mark.line + 1}: merge keys (<<) are refused")
            if key in seen:
                raise LawError(f"line {key_node.start_mark.line + 1}: key {key!r} repeats the key on line {seen[key]}")
            seen[key] = key_node.start_mark.line + 1
        return super().construct_mapping(node, deep=True)


def load_yaml(path: Path) -> Any:
    try:
        with path.open(encoding="utf-8") as fh:
            return yaml.load(fh, Loader=StrictLoader)  # noqa: S506 — StrictLoader is a BaseLoader
    except LawError as exc:
        raise LawError(f"{path}: {exc}") from None
    except yaml.YAMLError as exc:
        raise LawError(f"{path}: not YAML: {exc}") from None


def load_json(path: Path) -> Any:
    """JSON with exact numbers, refusing duplicate keys."""
    def pairs(items):
        out = {}
        for k, v in items:
            if k in out:
                raise LawError(f"{path}: key {k!r} repeats in one object")
            out[k] = v
        return out
    def number(text: str) -> Decimal:
        # PostgreSQL rewrites 1e2 as 100 on the way in, which would make the
        # file and the stored document differ; write numbers out in full.
        if "e" in text or "E" in text:
            raise LawError(f"{path}: {text} — write numbers without an exponent")
        return Decimal(text)
    with path.open(encoding="utf-8") as fh:
        return json.load(fh, parse_float=number, parse_int=number, object_pairs_hook=pairs)


# ---------------------------------------------------------------------------
# Canonical JSON
# ---------------------------------------------------------------------------

class RawNumber(str):
    """A number to write exactly as given — the cross-check's non-canonical
    mutations (1.50) use it; nothing a law file loads ever is one."""


def canonical_number(d: Decimal) -> str:
    if d.is_nan() or d.is_infinite():
        raise LawError(f"{d} is not a JSON number")
    # format(…, "f") writes the exact value, whatever the Decimal context's
    # precision (normalize() would round past 28 digits; review r1, Codex).
    text = format(d, "f")
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    if text in ("-0", ""):
        text = "0"
    return text


def dumps(value: Any) -> str:
    """Canonical JSON text: keys sorted, no insignificant space, numbers
    canonical. (Key order is irrelevant to jsonb; sorting makes files and
    seeds diff cleanly.)"""
    if isinstance(value, RawNumber):
        return str(value)
    if value is True:
        return "true"
    if value is False:
        return "false"
    if value is None:
        return "null"
    if isinstance(value, Decimal):
        return canonical_number(value)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "[" + ",".join(dumps(v) for v in value) + "]"
    if isinstance(value, dict):
        return "{" + ",".join(json.dumps(k, ensure_ascii=False) + ":" + dumps(value[k]) for k in sorted(value)) + "}"
    raise LawError(f"cannot serialise {type(value).__name__}")


# ---------------------------------------------------------------------------
# Schemas: the subset, the discriminator, typing a document
# ---------------------------------------------------------------------------

def resolve(root: dict, node: dict) -> dict:
    ref = node.get("$ref") if isinstance(node, dict) else None
    if ref is None:
        return node
    if not ref.startswith("#/$defs/"):
        raise LawError(f"$ref {ref} is outside the subset")
    return root["$defs"][ref[len("#/$defs/"):]]


def discriminator(root: dict, union: dict) -> str:
    """The one property every branch requires with a string const — the same
    rule as public.rule_terms_discriminator."""
    branches = [resolve(root, b) for b in union["oneOf"]]
    names = None
    for b in branches:
        props = b.get("properties", {})
        here = {k for k, v in props.items()
                if isinstance(v, dict) and isinstance(v.get("const"), str) and k in b.get("required", [])}
        names = here if names is None else names & here
    if not names or len(names) != 1:
        raise LawError("a oneOf needs exactly one const discriminator")
    return next(iter(names))


def typed(root: dict, node: dict, value: Any, path: str) -> Any:
    """A YAML document (every scalar a string) typed by its schema. Values the
    schema cannot type are left as they are, for the validator to report."""
    node = resolve(root, node)
    if "oneOf" in node:
        if not isinstance(value, dict):
            return value
        key = discriminator(root, node)
        for b in node["oneOf"]:
            rb = resolve(root, b)
            if isinstance(value.get(key), str) and rb["properties"][key]["const"] == value[key]:
                return typed(root, rb, value, path)
        return value
    kind = node.get("type")
    if kind == "object" and isinstance(value, dict):
        props = node.get("properties", {})
        return {k: (typed(root, props[k], v, f"{path}/{k}") if k in props else v) for k, v in value.items()}
    if kind == "array" and isinstance(value, list):
        return [typed(root, node["items"], v, f"{path}/{i}") for i, v in enumerate(value)]
    if kind in ("integer", "number") and isinstance(value, str):
        if not NUMBER_RE.fullmatch(value):
            raise LawError(f"{path}: {value!r} is not a number as written (digits, an optional sign and fraction; no exponent)")
        return Decimal(value)
    if kind == "boolean" and isinstance(value, str):
        if value not in ("true", "false"):
            raise LawError(f"{path}: {value!r} is not true or false")
        return value == "true"
    return value


def for_validator(value: Any) -> Any:
    """Decimals as the reference validator needs them: integral ones as int
    (jsonschema's "integer" does not accept a Decimal)."""
    if isinstance(value, RawNumber):
        d = Decimal(str(value))
        return int(d) if d == d.to_integral_value() and "." not in value else d
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral_value() else value
    if isinstance(value, list):
        return [for_validator(v) for v in value]
    if isinstance(value, dict):
        return {k: for_validator(v) for k, v in value.items()}
    return value


CONTROL = re.compile("[\x00-\x1f\x7f]")
SURROGATE = re.compile("[\ud800-\udfff]")
MAX_DEPTH = 64


def fixed_rule_errors(doc: Any, component_ids: bool = True) -> list[str]:
    """The validator's fixed rules, as rule_terms_errors applies them: no
    nulls, numbers canonical, no control characters in strings or keys,
    nesting at most 64 deep, and (unless an inputs document) component ids
    unique strings."""
    errs: list[str] = []
    ids: dict[str, int] = {}

    def walk(v: Any, path: str, depth: int = 0) -> None:
        if depth > MAX_DEPTH:
            errs.append(f"{path}: nested too deeply")
            return
        if isinstance(v, str) and not isinstance(v, RawNumber) and CONTROL.search(v):
            errs.append(f"{path}: control character")
        if isinstance(v, str) and SURROGATE.search(v):
            # PostgreSQL cannot store a lone surrogate (nor NUL, above): the
            # document would fail before the validator saw it (review r2, Codex).
            errs.append(f"{path}: a lone surrogate PostgreSQL cannot store")
        if v is None:
            errs.append(f"{path}: null")
        elif isinstance(v, RawNumber):
            if str(v) != canonical_number(Decimal(str(v))):
                errs.append(f"{path}: non-canonical number {v}")
        elif isinstance(v, Decimal):
            if str(v) != canonical_number(v):
                errs.append(f"{path}: non-canonical number {v}")
        elif isinstance(v, list):
            for i, e in enumerate(v):
                walk(e, f"{path}/{i}", depth + 1)
        elif isinstance(v, dict):
            for k, e in v.items():
                if CONTROL.search(k):
                    errs.append(f"{path}: control character in key {k!r}")
                if k == "id" and component_ids:
                    if isinstance(e, str):
                        ids[e] = ids.get(e, 0) + 1
                    else:
                        errs.append(f"{path}/id: a component id must be a string")
                walk(e, f"{path}/{k}", depth + 1)

    walk(doc, "")
    errs += [f": component id {i} repeated" for i, n in sorted(ids.items()) if n > 1]
    return errs


def reference_errors(schema: dict, doc: Any, component_ids: bool = True) -> list[str]:
    validator = Draft202012Validator(schema)
    errs = [f"/{'/'.join(str(p) for p in e.absolute_path)}: {e.message}" for e in validator.iter_errors(for_validator(doc))]
    return errs + fixed_rule_errors(doc, component_ids)


# ---------------------------------------------------------------------------
# Law files
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class LawRow:
    file: Path
    name: str
    table: str
    kind: str
    version: int
    seed: dict  # the row as rule_row_seed takes it
    terms: Any
    scenarios: list


def set_or_any(value: Any, what: str, where: str) -> list[str] | None:
    if value == "any":
        return None
    if isinstance(value, list) and value and all(isinstance(v, str) and CODE_RE.fullmatch(v) for v in value):
        if len(set(value)) != len(value):
            raise LawError(f"{where}: {what} repeats a code")
        return sorted(value)
    raise LawError(f"{where}: {what} is \"any\" or a non-empty list of codes — never omitted")


def read_law_file(path: Path) -> list[LawRow]:
    data = load_yaml(path)
    if not isinstance(data, dict) or set(data) - FILE_KEYS or not {"table", "kind", "version", "key", "schema", "rows"} <= set(data):
        raise LawError(f"{path}: a law file has exactly table, kind, version, key, schema and rows")
    if not re.fullmatch(r"public\.[a-z][a-z0-9_]*", data["table"]):
        raise LawError(f"{path}: table must be public.<name>")
    if not CODE_RE.fullmatch(data["kind"]) or not re.fullmatch(r"[1-9][0-9]*", data["version"]):
        raise LawError(f"{path}: kind is a code and version a positive integer")
    key = data["key"]
    if not isinstance(key, list) or not all(isinstance(k, str) and CODE_RE.fullmatch(k) for k in key):
        raise LawError(f"{path}: key lists the table's area-key columns")
    schema_path = (path.parent / data["schema"]).resolve()
    schema = load_json(schema_path)
    Draft202012Validator.check_schema(for_validator(schema))
    if schema.get("$schema") != JSON_SCHEMA_2020_12:
        raise LawError(f"{schema_path}: $schema must be {JSON_SCHEMA_2020_12}")
    rows = data["rows"]
    if not isinstance(rows, list) or not rows:
        raise LawError(f"{path}: rows is a non-empty list")
    out: list[LawRow] = []
    names: set[str] = set()
    for i, row in enumerate(rows):
        where = f"{path} rows[{i}]"
        if not isinstance(row, dict):
            raise LawError(f"{where}: a row is a mapping")
        unknown = set(row) - ENVELOPE_KEYS - set(key)
        missing = (ENVELOPE_KEYS - {"effective_to", "scenarios"} | set(key)) - set(row)
        if unknown or missing:
            raise LawError(f"{where}: unknown {sorted(unknown)}, missing {sorted(missing)}")
        name = row["name"]
        if not CODE_RE.fullmatch(name) or name in names:
            raise LawError(f"{where}: name is a code, unique in its file")
        names.add(name)
        for col in ("effective_from", "effective_to"):
            if col in row and not DATE_RE.fullmatch(row[col]):
                raise LawError(f"{where}: {col} is YYYY-MM-DD")
        juris = row["commission_jurisdiction"]
        if juris not in ("true", "false", "any"):
            raise LawError(f"{where}: commission_jurisdiction is true, false or any — never omitted")
        terms = typed(schema, schema, row["terms"], "")
        errs = reference_errors(schema, terms)
        if errs:
            raise LawError(f"{where} ({name}): the document is not a valid {data['kind']} v{data['version']}: " + "; ".join(errs[:10]))
        seed = {
            "state_code": row["state_code"],
            "service_type": row["service_type"],
            "owner_types": set_or_any(row["owner_types"], "owner_types", where),
            "system_kinds": set_or_any(row["system_kinds"], "system_kinds", where),
            "commission_jurisdiction": None if juris == "any" else juris == "true",
            "effective_from": row["effective_from"],
            "effective_to": row.get("effective_to"),
            "source_note": row["source_note"],
            "terms_kind": data["kind"],
            "terms_version": int(data["version"]),
            "terms_source": dumps(terms),
        }
        for k in key:
            seed[k] = row[k]
        scenarios = row.get("scenarios", [])
        for j, sc in enumerate(scenarios if isinstance(scenarios, list) else [None]):
            if not (isinstance(sc, dict) and set(sc) == {"name", "inputs", "expected"} and isinstance(sc["name"], str)
                    and re.search(r"[A-Za-z0-9]", sc["name"]) and isinstance(sc["inputs"], dict) and sc["inputs"]
                    and isinstance(sc["expected"], dict) and sc["expected"]):
                raise LawError(f"{where} scenarios[{j}]: a scenario is {{name, inputs, expected}}, each non-empty")
        out.append(LawRow(path, name, data["table"], data["kind"], int(data["version"]), seed, terms, scenarios))
    return out


def emit(rows: list[LawRow]) -> str:
    lines = ["-- Generated by tools/law/lawc.py emit — do not edit; edit the law file and re-emit.",
             "-- Each call inserts its law row, or finds it unchanged, or raises (public.rule_row_seed, v5.4.2-17)."]
    for path in sorted({r.file for r in rows}):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        lines.append(f"-- source: {path.resolve().relative_to(REPO)} sha256 {digest}")
    for r in rows:
        body = dumps({k: v for k, v in r.seed.items()})
        tag = "$law$"
        if tag in body:
            raise LawError(f"{r.file} {r.name}: the row contains {tag}")
        lines.append(f"SELECT public.rule_row_seed('{r.table}', {tag}{body}{tag}::jsonb);  -- {r.name}")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# The database
# ---------------------------------------------------------------------------

def psql_cmd() -> list[str]:
    if "LAWC_PSQL" in os.environ:
        return shlex.split(os.environ["LAWC_PSQL"])
    return ["docker", "exec", "-i", "tally-pg", "psql", "-U", "tally", "-d", os.environ.get("LAWC_DB", "tally")]


def run_sql(sql: str) -> str:
    proc = subprocess.run(psql_cmd() + ["-v", "ON_ERROR_STOP=1", "-q", "-At", "-X"],
                          input=sql, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise LawError(f"psql failed: {proc.stderr.strip()}")
    return proc.stdout


def sql_literal(text: str) -> str:
    return "'" + text.replace("'", "''") + "'"


# ---------------------------------------------------------------------------
# The cross-check (inventory V10; v5.4.2-17 residual R7)
# ---------------------------------------------------------------------------

def schema_consts(schema: Any) -> set[str]:
    """Every string const in a schema: the discriminator values of its unions."""
    found: set[str] = set()

    def walk(n: Any) -> None:
        if isinstance(n, dict):
            if isinstance(n.get("const"), str):
                found.add(n["const"])
            for v in n.values():
                walk(v)
        elif isinstance(n, list):
            for v in n:
                walk(v)
    walk(schema)
    return found


def mutations(doc: Any, schema: Any = None) -> Iterator[tuple[str, Any]]:
    """Single-edit variants of a valid document: every key removed, an
    unknown key added, every value replaced by values of other types and at
    the edges, every array emptied, its first item repeated, numbers written
    non-canonically."""
    replacements = [None, "x", "", "f1\n", "a\tb", "é", "x" * 201, RawNumber("0"), RawNumber("-1"), RawNumber("1.5"),
                    RawNumber("1.50"), RawNumber("10000"), RawNumber("12345678901234567890123456789.5"), True, [], {}]

    def paths(v: Any, path: tuple) -> Iterator[tuple]:
        yield path
        if isinstance(v, dict):
            for k in v:
                yield from paths(v[k], path + (k,))
        elif isinstance(v, list):
            for i, e in enumerate(v):
                yield from paths(e, path + (i,))

    def get(v, path):
        for p in path:
            v = v[p]
        return v

    consts = schema_consts(schema) if schema is not None else set()
    for path in paths(doc, ()):
        target = get(doc, path)
        label = "/" + "/".join(map(str, path))
        if path:
            parent = get(doc, path[:-1])
            if isinstance(parent, dict):
                m = copy.deepcopy(doc)
                del get(m, path[:-1])[path[-1]]
                yield f"remove {label}", m
            for r in replacements:
                m = copy.deepcopy(doc)
                get(m, path[:-1])[path[-1]] = copy.deepcopy(r)
                yield f"{label} := {dumps(r)}", m
            # A discriminator switched to another branch's value: the document
            # now claims a strategy whose parameters it does not carry.
            if isinstance(target, str) and target in consts:
                for other in sorted(consts - {target}):
                    m = copy.deepcopy(doc)
                    get(m, path[:-1])[path[-1]] = other
                    yield f"{label} := {other!r}", m
            if isinstance(target, Decimal):
                for delta in (Decimal("0.01"), Decimal("-0.01")):
                    m = copy.deepcopy(doc)
                    get(m, path[:-1])[path[-1]] = target + delta
                    yield f"{label} {delta:+}", m
        if isinstance(target, dict):
            m = copy.deepcopy(doc)
            get(m, path)["zz_unknown"] = "x"
            yield f"{label} + unknown key", m
        if isinstance(target, list) and target:
            m = copy.deepcopy(doc)
            get(m, path).append(copy.deepcopy(target[0]))
            yield f"{label} + repeat of its first item", m


def crosscheck(schema_path: Path, docs: list[Any], component_ids: bool = True) -> int:
    schema = load_json(schema_path)
    cases: list[tuple[str, Any]] = []
    for i, d in enumerate(docs):
        cases.append((f"doc {i}", d))
        cases += [(f"doc {i}: {label}", m) for label, m in mutations(d, schema)]
    ref = [not reference_errors(schema, d, component_ids) for _, d in cases]
    values = ",\n".join(f"({i}, {sql_literal(dumps(d))}::jsonb)" for i, (_, d) in enumerate(cases))
    flag = "true" if component_ids else "false"
    out = run_sql(f"SELECT c.i, cardinality(public.rule_terms_errors({sql_literal(dumps(schema))}::jsonb, c.d, {flag})) = 0\n"
                  f"  FROM (VALUES {values}) AS c(i, d) ORDER BY c.i;\n")
    db = {int(i): v == "t" for i, v in (line.split("|") for line in out.split())}
    disagree = [(cases[i][0], ref[i], db.get(i)) for i in range(len(cases)) if ref[i] != db.get(i)]
    valid = sum(ref)
    print(f"crosscheck {schema_path.name}: {len(cases)} documents ({valid} valid, {len(cases) - valid} invalid); {len(disagree)} disagreement(s)")
    for label, r, d in disagree[:20]:
        print(f"  DISAGREE {label}: reference {'valid' if r else 'invalid'}, database {'valid' if d else 'invalid'}")
    return 1 if disagree else 0


# ---------------------------------------------------------------------------
# Round trip
# ---------------------------------------------------------------------------

def roundtrip(rows: list[LawRow]) -> int:
    seed = emit(rows)
    first = run_sql("BEGIN;\n" + seed + "COMMIT;\n").split()
    second = run_sql("BEGIN;\n" + seed + "COMMIT;\n").split()
    if first != second or len(first) != len(rows):
        print(f"roundtrip: the second seed changed something ({first} then {second})")
        return 1
    failures = 0
    for r, row_id in zip(rows, first):
        stored = run_sql(f"SELECT terms::text FROM {r.table} WHERE id = {sql_literal(row_id)};").strip()
        same = run_sql(f"SELECT {sql_literal(stored)}::jsonb = {sql_literal(r.seed['terms_source'])}::jsonb;").strip()
        if same != "t":
            print(f"roundtrip: {r.file.name} {r.name}: stored terms differ from the file")
            failures += 1
    for table in sorted({r.table for r in rows}):
        ids = run_sql(f"SELECT id FROM {table} ORDER BY id;").split()
        extra = sorted(set(ids) - set(first))
        if extra:
            print(f"roundtrip: {table} holds rows no law file names: {extra}")
            failures += 1
    print(f"roundtrip: {len(rows)} row(s); seeded, re-seeded unchanged; {failures} failure(s)")
    return 1 if failures else 0


# ---------------------------------------------------------------------------

def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="lawc.py", description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("check", "emit", "roundtrip"):
        p = sub.add_parser(name)
        p.add_argument("files", nargs="+", type=Path)
        if name == "emit":
            p.add_argument("-o", "--out", type=Path)
    p = sub.add_parser("crosscheck")
    p.add_argument("--inputs", action="store_true", help="an inputs schema: component ids are not unique-checked")
    p.add_argument("schema", type=Path)
    p.add_argument("docs", nargs="+", type=Path, help="JSON or YAML documents valid for the schema")
    args = ap.parse_args(argv)
    try:
        if args.cmd == "crosscheck":
            schema = load_json(args.schema)
            docs = [typed(schema, schema, load_yaml(d), "") if d.suffix in (".yaml", ".yml") else load_json(d) for d in args.docs]
            for d, path in zip(docs, args.docs):
                errs = reference_errors(schema, d, component_ids=not args.inputs)
                if errs:
                    raise LawError(f"{path}: a crosscheck seed document must be valid: {errs[:5]}")
            return crosscheck(args.schema, docs, component_ids=not args.inputs)
        rows = [r for f in args.files for r in read_law_file(f)]
        if args.cmd == "check":
            print(f"check: {len(rows)} row(s) in {len(args.files)} file(s) valid")
            return 0
        if args.cmd == "emit":
            text = emit(rows)
            if args.out:
                args.out.write_text(text, encoding="utf-8")
            else:
                sys.stdout.write(text)
            return 0
        return roundtrip(rows)
    except LawError as exc:
        print(f"lawc: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
