#!/usr/bin/env python3
"""Deposit rule-terms v1: the document-format tests (v5.4.2-15 rewrite).

Written BEFORE law/deposit/deposit.v1.schema.json exists, so it fails first:
  T0  the schema file exists
  T1  the validator accepts the schema (rule_terms_schema_errors is empty)
  T2  every example and fixture document is valid, and the database validator
      and a standard JSON Schema 2020-12 validator agree on each of them and
      on every single-edit mutation of them (lawc crosscheck)
  T3  every must-refuse document is rejected by BOTH validators, the database
      one with the stated reason
The must-refuse cases include one natural-looking document for each shape
v1 leaves out on purpose (application/deposits-terms-v1-design-2026-10-12.md,
section 4: recalculation, bill-anchored instalments, a sum cap with an add-on,
guarantor caps, municipal funds), so an out-of-scope rule is refused in plain
words, never silently dropped.

The functions called are pure, so this runs against any database that has
v5.4.2-17 (the live `tally` by default; LAWC_DB overrides the name).

usage: tools/law/.venv/bin/python tests/v5.4.2-15/terms-15.py
"""
from __future__ import annotations

import copy
import sys
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "law"))
import lawc  # noqa: E402

SCHEMA = ROOT / "law" / "deposit" / "deposit.v1.schema.json"
VALID_DOCS = sorted((ROOT / "law" / "deposit" / "examples").glob("*.yaml")) + \
             sorted((ROOT / "law" / "fixtures" / "deposit-states").glob("*.yaml"))

COMMON_RETURN = {"instruments": ["cash"], "conditions": [], "minimum_amount": {"kind": "none"},
                 "deadline": {"kind": "none"}, "hold_while": [], "vests": "unruled"}
BASE = {
    "governs": "law", "citation": "16 TAC 7.45",
    "cap": {"strategy": "parts", "version": 1, "combinator": "single", "scope": "per_deposit",
            "parts": [{"id": "c1", "kind": "fraction_of_annual_billing", "divisor": 6}]},
    "triggers": [],
    "waivers": [{"id": "w1", "waiver_class": "age_65_no_balance", "applies_to": {"kind": "any_trigger"},
                 "effect": {"kind": "excuse"}, "also_releases_held": False, "disqualified_by": {"kind": "none"}}],
    "interest": {"strategy": "bearing", "version": 1, "instruments": ["cash"],
                 "rate": {"kind": "published", "name": "tx_deposit_interest_rate", "binding": "minimum", "by_hold": []},
                 "method": {"kind": "simple"}, "day_count": "actual_365",
                 "hold": {"kind": "minimum", "days": 30, "retroactive": True},
                 "credit": {"kind": "at_refund"}, "stops_on": ["refund"], "forfeited_on": [],
                 "penalty": {"kind": "none"}, "rounding": {"kind": "none"}},
    "return": [{"id": "r1", "when": {"reason": "account_closed"}, **COMMON_RETURN}],
    "instalments": [{"id": "i1", "fraction": Decimal("0.5"), "days_after": 0}, {"id": "i2", "fraction": Decimal("0.5"), "days_after": 30}],
}


def edit(fn):
    d = copy.deepcopy(BASE)
    fn(d)
    return d


def drop(path):
    def f(d):
        node = d
        for k in path[:-1]:
            node = node[k]
        del node[path[-1]]
    return f


def setv(path, value):
    def f(d):
        node = d
        for k in path[:-1]:
            node = node[k]
        node[path[-1]] = value
    return f


# (name, mutation, text the database validator must report)
REFUSE = [
    # the shapes v1 leaves out on purpose
    ("out: periodic recalculation", setv(["recalculation"], {"every_years": 3, "tolerance": Decimal("0.25")}), "/recalculation: unknown key"),
    ("out: a sum cap", setv(["cap", "combinator"], "sum"), "/cap/combinator"),
    ("out: a cap add-on", setv(["cap", "add_on"], {"kind": "equipment_damage"}), "/cap/add_on: unknown key"),
    ("out: a bill-anchored instalment", setv(["instalments", 0, "anchor"], "next_bill"), "/instalments/0/anchor: unknown key"),
    ("out: a guarantor cap", setv(["guarantor_cap"], {"days": 60}), "/guarantor_cap: unknown key"),
    ("out: a municipal deposit fund", setv(["fund"], {"separate_account": True}), "/fund: unknown key"),
    # the document is closed and explicit
    ("an unknown top-level key", setv(["extra"], 1), "/extra: unknown key"),
    ("a missing cap", drop(["cap"]), "/cap: required"),
    ("a null anywhere", setv(["interest", "hold", "days"], None), "null is not allowed"),
    ("a trigger list left out", drop(["triggers"]), "/triggers: required"),
    ("a return rule with no vests", drop(["return", 0, "vests"]), "/return/0/vests: required"),
    ("interest with no credit", drop(["interest", "credit"]), "/interest/credit: required"),
    # decision 4: a rate must say whether it binds
    ("a rate that does not say whether it binds", drop(["interest", "rate", "binding"]), "/interest/rate/binding: required"),
    ("a binding that is not minimum or reference", setv(["interest", "rate", "binding"], "maximum"), "/interest/rate/binding"),
    # unions say exactly what each branch needs
    ("a minimum hold without retroactive", drop(["interest", "hold", "retroactive"]), "/interest/hold/retroactive: required"),
    ("a reduce effect with a stray day count", setv(["waivers", 0, "effect"], {"kind": "reduce", "fraction": Decimal("0.5"), "days": 3}), "/waivers/0/effect/days: unknown key"),
    ("a reduce effect with no fraction", setv(["waivers", 0, "effect"], {"kind": "reduce"}), "/waivers/0/effect/fraction: required"),
    ("a condition that does not exist", setv(["triggers"], [{"id": "t1", "trigger_code": "x", "guards": [],
        "condition": {"kind": "xor_of", "of": []}}]), "/triggers/0/condition/kind"),
    ("an all_of with one child", setv(["triggers"], [{"id": "t1", "trigger_code": "x", "guards": [],
        "condition": {"kind": "all_of", "of": [{"kind": "ratio", "measure": "usage_to_estimate", "op": "at_least", "value": 2}]}}]), "at least 2 items"),
    ("a cap part with the wrong figure", setv(["cap", "parts", 0], {"id": "c1", "kind": "fraction_of_annual_billing", "months": 2}), "unknown key"),
    ("a delegated document with law fields", lambda d: (d.clear(), d.update({"governs": "delegated_to_utility", "citation": "x", "cap": {}})), "/cap: unknown key"),
    # ids and numbers
    ("a repeated component id", setv(["instalments", 1, "id"], "i1"), "component ids must be unique"),
]
NON_CANONICAL = ("a non-canonical number", '{"governs":"law"}', None)


def sql_errors(schema: dict, doc_text: str, ids: bool = True) -> list[str]:
    out = lawc.run_sql(
        f"SELECT unnest(public.rule_terms_errors({lawc.sql_literal(lawc.dumps(schema))}::jsonb, "
        f"{lawc.sql_literal(doc_text)}::jsonb, {'true' if ids else 'false'}));\n")
    return [l for l in out.splitlines() if l.strip()]


def main() -> int:
    fails = 0

    def ok(tag: str, msg: str) -> None:
        print(f"PASS {tag}: {msg}")

    def bad(tag: str, msg: str) -> None:
        nonlocal fails
        fails += 1
        print(f"FAIL {tag}: {msg}")

    if not SCHEMA.exists():
        bad("T0", f"{SCHEMA.relative_to(ROOT)} does not exist (expected until the schema is written)")
        print(f"{fails} failure(s)")
        return 1
    ok("T0", "the schema file exists")
    schema = lawc.load_json(SCHEMA)

    errs = lawc.run_sql(f"SELECT array_to_string(public.rule_terms_schema_errors({lawc.sql_literal(lawc.dumps(schema))}::jsonb), E'\\n');\n").strip()
    if errs:
        bad("T1", f"the validator refuses the schema:\n{errs}")
        print(f"{fails} failure(s)")
        return 1
    ok("T1", "the validator accepts the schema")

    docs = []
    for p in VALID_DOCS:
        d = lawc.typed(schema, schema, lawc.load_yaml(p), "") if p.suffix == ".yaml" else lawc.load_json(p)
        problems = lawc.reference_errors(schema, d)
        if problems:
            bad("T2", f"{p.relative_to(ROOT)} is not valid: {problems[:3]}")
        docs.append(d)
    if not fails:
        if lawc.crosscheck(SCHEMA, docs) == 0:
            ok("T2", f"{len(docs)} example and fixture documents valid; both validators agree on all of them and their mutations")
        else:
            bad("T2", "the database validator and the standard validator disagree")

    for name, fn, expect in REFUSE:
        doc = edit(fn)
        text = lawc.dumps(doc)
        ref = lawc.reference_errors(schema, doc)
        db = sql_errors(schema, text)
        if not ref:
            bad("T3", f"{name}: the standard validator ACCEPTED it")
        elif not db:
            bad("T3", f"{name}: the database validator ACCEPTED it")
        elif not any(expect in line for line in db):
            bad("T3", f"{name}: refused, but not for {expect!r}: {db[:2]}")
        else:
            ok("T3", f"{name}: refused ({expect})")

    # the numbers rule is the database's own (a standard validator does not know it)
    text = lawc.dumps(BASE).replace('"fraction":0.5', '"fraction":0.50', 1)
    assert '"fraction":0.50' in text, "the non-canonical number case did not change the document"
    db = sql_errors(schema, text)
    if any("canonically" in l for l in db):
        ok("T3", "a non-canonical number: refused (written canonically)")
    else:
        bad("T3", f"a non-canonical number was not refused: {db[:2]}")

    print(f"{fails} failure(s)")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
