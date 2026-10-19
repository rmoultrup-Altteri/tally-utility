#!/usr/bin/env python3
"""Dispute rule-terms v1: the document-format tests (v5.4.2-25).

Written BEFORE law/dispute/dispute.v1.schema.json and dispute_tariff.v1.schema.json
exist, so it fails first:
  T0  the schema file exists
  T1  the validator accepts the schema (rule_terms_schema_errors is empty)
  T2  every example and fixture document is valid, and the database validator
      and a standard JSON Schema 2020-12 validator agree on each of them and
      on every single-edit mutation of them (lawc crosscheck)
  T3  every must-refuse document is rejected by BOTH validators, the database
      one with the stated reason
The must-refuse cases include the shapes v1 leaves out on purpose
(application/wave3-build-2026-10-18/v5.4.2-25-design.md and the inventory's
residuals): a conditional late-fee block (PA 56.22(c), estimated bills only),
a must-pay amount with no strategy, and logic in place of a strategy.

The functions called are pure, so this runs against any database that has
v5.4.2-17 (the live `tally` by default; LAWC_DB overrides the name).

usage: tools/law/.venv/bin/python tests/v5.4.2-25/terms-25.py
"""
from __future__ import annotations

import copy
import sys
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "law"))
import lawc  # noqa: E402

SCHEMA = ROOT / "law" / "dispute" / "dispute.v1.schema.json"
TARIFF_SCHEMA = ROOT / "law" / "dispute" / "dispute_tariff.v1.schema.json"
EXAMPLES = ROOT / "law" / "dispute" / "examples"
VALID_DOCS = sorted(EXAMPLES.glob("dispute.*.yaml")) + sorted((ROOT / "law" / "fixtures" / "dispute-states" / "examples").glob("*.yaml"))
TARIFF_DOCS = sorted(EXAMPLES.glob("dispute_tariff.*.yaml"))

NONE = {"kind": "none"}
BASE = {
    "governs": "law", "citation": "16 TAC 7.45(6)(D)",
    "subjects": {"kind": "any", "excluded": [], "citation": "16 TAC 7.45(6)(D)(i)"},
    "shelter_earned": {"kind": "before_delinquency", "citation": "16 TAC 7.45(6)(D)(i)"},
    "must_pay": {"strategy": "average_usage_cap", "version": 1, "id": "m1", "history_years": 2,
                 "no_history": "similar_customers", "citation": "16 TAC 7.45(6)(D)(ii)"},
    "shelter_ends": {"kind": "earlier_of_resolution_and_days", "days": 60, "from": "issue", "citation": "16 TAC 7.45(6)(D)(ii)"},
    "stages": [
        {"id": "s1", "decider": "designated_employee", "file_within": NONE, "decide_within": NONE, "final": False, "citation": "x"},
        {"id": "s2", "decider": "regulator", "file_within": NONE, "decide_within": {"kind": "days", "days": 15}, "final": True, "citation": "y"},
    ],
    "blocks": {"codes": ["disconnect_order", "disconnect_execute", "late_fee"], "citation": "16 TAC 7.45(6)(D)(ii)"},
    "duties": {"codes": ["investigate", "report_result"], "citation": "16 TAC 7.45(6)(D)(i)"},
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
    ("out: a late-fee block conditional on an estimated bill (PA 56.22(c))",
        setv(["blocks", "conditions"], [{"block": "late_fee", "only_if": "estimated_bill"}]), "/blocks/conditions: unknown key"),
    ("out: a must-pay expression in place of a strategy", setv(["must_pay"], {"formula": "disputed - average"}), "/must_pay/strategy: required"),
    ("out: a shelter that ends on a formula", setv(["shelter_ends"], {"kind": "expression", "text": "min(a,b)"}), "/shelter_ends/kind"),
    # the document is closed and explicit
    ("an unknown top-level key", setv(["extra"], 1), "/extra: unknown key"),
    ("a missing must_pay", drop(["must_pay"]), "/must_pay: required"),
    ("a missing blocks section (absent is never none)", drop(["blocks"]), "/blocks: required"),
    ("a missing stages list", drop(["stages"]), "/stages: required"),
    ("a null anywhere", setv(["shelter_ends", "days"], None), "null is not allowed"),
    ("a section with no citation", drop(["shelter_earned", "citation"]), "/shelter_earned/citation: required"),
    # vocabulary in the shape
    ("a subjects kind that does not exist", setv(["subjects", "kind"], "some"), "/subjects/kind"),
    ("a listed subjects section with no codes", setv(["subjects"], {"kind": "listed", "excluded": [], "citation": "x"}), "/subjects/codes: required"),
    ("a shelter_earned kind that does not exist", setv(["shelter_earned", "kind"], "before_due_date"), "/shelter_earned/kind"),
    ("a within_days shelter with no day count", setv(["shelter_earned"], {"kind": "within_days", "from": "receipt", "citation": "x"}), "/shelter_earned/days: required"),
    ("a within_days shelter counted from an unknown anchor", setv(["shelter_earned"], {"kind": "within_days", "days": 21, "from": "due", "citation": "x"}), "/shelter_earned/from"),
    ("a must_pay strategy that does not exist", setv(["must_pay", "strategy"], "half_bill"), "/must_pay/strategy"),
    ("an average cap with no history years", drop(["must_pay", "history_years"]), "/must_pay/history_years: required"),
    ("an average cap with an unknown no-history basis", setv(["must_pay", "no_history"], "zero"), "/must_pay/no_history"),
    ("a full bill with a stray figure", setv(["must_pay"], {"strategy": "full_bill", "version": 1, "id": "m1", "history_years": 2, "citation": "x"}), "/must_pay/history_years: unknown key"),
    ("a withhold cap with no fraction", setv(["must_pay"], {"strategy": "withhold_cap", "version": 1, "id": "m1", "citation": "x"}), "/must_pay/fraction: required"),
    ("a must_pay with no id (the determination cites it)", drop(["must_pay", "id"]), "/must_pay/id: required"),
    ("a days-capped end with no days", drop(["shelter_ends", "days"]), "/shelter_ends/days: required"),
    ("a days-capped end from receipt (v1: from issue only)", setv(["shelter_ends", "from"], "receipt"), "/shelter_ends/from"),
    ("a stage decider that does not exist", setv(["stages", 0, "decider"], "clerk"), "/stages/0/decider"),
    ("a stage that does not say whether it is final", drop(["stages", 0, "final"]), "/stages/0/final: required"),
    ("a filing deadline with no anchor", setv(["stages", 1, "file_within"], {"kind": "days", "days": 30}), "/stages/1/file_within/from: required"),
    ("a decision deadline with a stray anchor", setv(["stages", 1, "decide_within"], {"kind": "days", "days": 90, "from": "issue"}), "/stages/1/decide_within/from: unknown key"),
    ("a blocks list given as a bare list", setv(["blocks"], ["late_fee"]), "/blocks"),
    ("a delegated document with law fields", lambda d: (d.clear(), d.update({"governs": "delegated_to_utility", "citation": "x", "stages": []})), "/stages: unknown key"),
    # ids
    ("a repeated stage id", setv(["stages", 1, "id"], "s1"), "component ids must be unique"),
    ("a stage id equal to the must_pay id", setv(["stages", 0, "id"], "m1"), "component ids must be unique"),
]
TARIFF_BASE = {
    "citation": "CPS Energy Customer Terms and Conditions IV.4",
    "subjects": {"kind": "any", "excluded": ["deposit"]},
    "shelter_earned": {"kind": "any_time"},
    "must_pay": {"strategy": "undisputed_charges", "version": 1, "id": "m1"},
    "shelter_ends": {"kind": "resolution"},
    "stages": [
        {"id": "s1", "decider": "manager", "file_within": NONE, "decide_within": NONE, "final": False},
        {"id": "s2", "decider": "executive", "file_within": {"kind": "days", "days": 30, "from": "prior_decision"},
         "decide_within": {"kind": "days", "days": 90}, "final": True},
    ],
    "blocks": {"codes": ["disconnect_order", "disconnect_execute"]},
    "duties": {"codes": ["investigate"]},
}
TARIFF_REFUSE = [
    ("tariff: a governs key (a tariff is the utility's policy, not law)", setv(["governs"], "law"), "/governs: unknown key"),
    ("tariff: a delegation (only law delegates)", lambda d: (d.clear(), d.update({"governs": "delegated_to_utility", "citation": "x"})), "unknown key"),
    ("tariff: a missing citation", drop(["citation"]), "/citation: required"),
    ("tariff: a missing must_pay (K-07: no assumed default)", drop(["must_pay"]), "/must_pay: required"),
    ("tariff: an unruled must_pay (a utility's own policy says what it asks)", setv(["must_pay"], {"strategy": "unruled", "version": 1, "id": "m1"}), "/must_pay/strategy"),
    ("tariff: an unruled shelter start", setv(["shelter_earned"], {"kind": "unruled"}), "/shelter_earned/kind"),
    ("tariff: an unruled shelter end", setv(["shelter_ends"], {"kind": "unruled"}), "/shelter_ends/kind"),
    ("tariff: a stage decider that does not exist", setv(["stages", 0, "decider"], "clerk"), "/stages/0/decider"),
    ("tariff: a missing blocks section", drop(["blocks"]), "/blocks: required"),
    ("tariff: a repeated component id", setv(["stages", 1, "id"], "s1"), "component ids must be unique"),
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


def check_kind(res: Result, label: str, schema_path: Path, docs_paths: list[Path], base: dict, refuse: list, number_case) -> None:
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
    before_text, after_text = number_case
    text = lawc.dumps(base).replace(before_text, after_text, 1)
    assert after_text in text, "the non-canonical number case did not change the document"
    if any("canonically" in l for l in sql_errors(schema, text)):
        res.ok(f"{label} T3", "a non-canonical number: refused (written canonically)")
    else:
        res.bad(f"{label} T3", "a non-canonical number was not refused")


def main() -> int:
    res = Result()
    check_kind(res, "law", SCHEMA, VALID_DOCS, BASE, REFUSE, ('"days":60', '"days":60.0'))
    check_kind(res, "tariff", TARIFF_SCHEMA, TARIFF_DOCS, TARIFF_BASE, TARIFF_REFUSE, ('"days":30', '"days":30.0'))
    # the governmental fixture's 1.1 must survive typing as a canonical number
    gov = ROOT / "law" / "fixtures" / "dispute-states" / "examples" / "tx_governmental.yaml"
    if SCHEMA.exists():
        schema = lawc.load_json(SCHEMA)
        d = lawc.typed(schema, schema, lawc.load_yaml(gov), "")
        if d["must_pay"]["fraction"] == Decimal("1.1"):
            res.ok("law T2b", "the withholding fraction 1.1 is typed as the number 1.1")
        else:
            res.bad("law T2b", f"the withholding fraction typed as {d['must_pay']['fraction']!r}")
    print(f"{res.fails} failure(s)")
    return 1 if res.fails else 0


if __name__ == "__main__":
    sys.exit(main())
