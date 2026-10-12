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
TARIFF_SCHEMA = ROOT / "law" / "deposit" / "deposit_tariff.v1.schema.json"
EXAMPLES = ROOT / "law" / "deposit" / "examples"
VALID_DOCS = sorted(EXAMPLES.glob("deposit.*.yaml")) + sorted((ROOT / "law" / "fixtures" / "deposit-states").glob("*.yaml"))
TARIFF_DOCS = sorted(EXAMPLES.glob("deposit_tariff.*.yaml"))

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


def edit(fn, base=None):
    d = copy.deepcopy(BASE if base is None else base)
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
TARIFF_BASE = {
    "citation": "Gas tariff, deposits",
    "amount": {"strategy": "months_of_billing", "version": 1, "months": 1, "of": "average", "minimum_amount": {"kind": "none"}},
    "triggers": [], "waivers": [
        {"id": "w1", "ground": "military_deployment", "applies_to": {"kind": "any_trigger"}, "effect": {"kind": "excuse"},
         "also_releases_held": False, "disqualified_by": {"kind": "none"}}],
    "instalments": [{"id": "i1", "fraction": Decimal("0.5"), "days_after": 0}, {"id": "i2", "fraction": Decimal("0.5"), "days_after": 30}],
}
TARIFF_REFUSE = [
    ("tariff: a law-style cap section", setv(["cap"], {"strategy": "none", "version": 1}), "/cap: unknown key"),
    ("tariff: a missing amount", drop(["amount"]), "/amount: required"),
    ("tariff: a fixed amount with no figure", setv(["amount"], {"strategy": "fixed", "version": 1}), "/amount/amount: required"),
    ("tariff: a fixed amount of zero", setv(["amount"], {"strategy": "fixed", "version": 1, "amount": 0}), "/amount/amount"),
    ("tariff: an amount strategy that does not exist", setv(["amount"], {"strategy": "sliding", "version": 1}), "/amount/strategy"),
    ("tariff: months of billing with no basis", setv(["amount"], {"strategy": "months_of_billing", "version": 1, "months": 2,
        "minimum_amount": {"kind": "none"}}), "/amount/of: required"),
    ("tariff: months of billing on a basis that is not average or highest", setv(["amount"], {"strategy": "months_of_billing", "version": 1,
        "months": 2, "of": "median", "minimum_amount": {"kind": "none"}}), "/amount/of"),
    ("tariff: a case-by-case amount with a stray figure", setv(["amount"], {"strategy": "case_by_case", "version": 1, "amount": 100}), "/amount/amount: unknown key"),
    ("tariff: a waiver named by a law class (the tariff names its own ground)", setv(["waivers", 0, "waiver_class"], "age_65_no_balance"), "/waivers/0/waiver_class: unknown key"),
    ("tariff: a waiver with no ground", drop(["waivers", 0, "ground"]), "/waivers/0/ground: required"),
    ("tariff: a recalculation section (out of version 1)", setv(["recalculation"], {"every_years": 3}), "/recalculation: unknown key"),
    ("tariff: instalments tied to bills", setv(["instalments", 0, "anchor"], "next_bill"), "/instalments/0/anchor: unknown key"),
    ("tariff: a repeated component id", setv(["instalments", 1, "id"], "i1"), "component ids must be unique"),
]


def sql_errors(schema: dict, doc_text: str, ids: bool = True) -> list[str]:
    out = lawc.run_sql(
        f"SELECT unnest(public.rule_terms_errors({lawc.sql_literal(lawc.dumps(schema))}::jsonb, "
        f"{lawc.sql_literal(doc_text)}::jsonb, {'true' if ids else 'false'}));\n")
    return [l for l in out.splitlines() if l.strip()]


class Result:
    def __init__(self) -> None:
        self.fails = 0

    def ok(self, tag: str, msg: str) -> None:
        print(f"PASS {tag}: {msg}")

    def bad(self, tag: str, msg: str) -> None:
        self.fails += 1
        print(f"FAIL {tag}: {msg}")


def check_kind(res: Result, label: str, schema_path: Path, docs_paths: list[Path], base: dict, refuse: list) -> None:
    if not schema_path.exists():
        res.bad(f"{label} T0", f"{schema_path.relative_to(ROOT)} does not exist (expected until the schema is written)")
        return
    res.ok(f"{label} T0", "the schema file exists")
    schema = lawc.load_json(schema_path)
    errs = lawc.run_sql(f"SELECT array_to_string(public.rule_terms_schema_errors({lawc.sql_literal(lawc.dumps(schema))}::jsonb), E'\\n');\n").strip()
    if errs:
        res.bad(f"{label} T1", f"the validator refuses the schema:\n{errs}")
        return
    res.ok(f"{label} T1", "the validator accepts the schema")

    docs, before = [], res.fails
    for p in docs_paths:
        d = lawc.typed(schema, schema, lawc.load_yaml(p), "")
        problems = lawc.reference_errors(schema, d)
        if problems:
            res.bad(f"{label} T2", f"{p.relative_to(ROOT)} is not valid: {problems[:3]}")
        docs.append(d)
    if res.fails == before:
        if lawc.crosscheck(schema_path, docs) == 0:
            res.ok(f"{label} T2", f"{len(docs)} documents valid; both validators agree on all of them and their mutations")
        else:
            res.bad(f"{label} T2", "the database validator and the standard validator disagree")

    for name, fn, expect in refuse:
        doc = edit(fn, base)
        ref = lawc.reference_errors(schema, doc)
        db = sql_errors(schema, lawc.dumps(doc))
        if not ref:
            res.bad(f"{label} T3", f"{name}: the standard validator ACCEPTED it")
        elif not db:
            res.bad(f"{label} T3", f"{name}: the database validator ACCEPTED it")
        elif not any(expect in line for line in db):
            res.bad(f"{label} T3", f"{name}: refused, but not for {expect!r}: {db[:2]}")
        else:
            res.ok(f"{label} T3", f"{name}: refused ({expect})")

    # the numbers rule is the database's own (a standard validator does not know it)
    text = lawc.dumps(base).replace('"fraction":0.5', '"fraction":0.50', 1)
    assert '"fraction":0.50' in text, "the non-canonical number case did not change the document"
    if any("canonically" in l for l in sql_errors(schema, text)):
        res.ok(f"{label} T3", "a non-canonical number: refused (written canonically)")
    else:
        res.bad(f"{label} T3", "a non-canonical number was not refused")


def main() -> int:
    res = Result()
    check_kind(res, "law", SCHEMA, VALID_DOCS, BASE, REFUSE)
    check_kind(res, "tariff", TARIFF_SCHEMA, TARIFF_DOCS, TARIFF_BASE, TARIFF_REFUSE)
    print(f"{res.fails} failure(s)")
    return 1 if res.fails else 0


if __name__ == "__main__":
    sys.exit(main())
