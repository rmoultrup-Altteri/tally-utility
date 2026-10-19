#!/usr/bin/env python3
"""Derive law/dispute/dispute_tariff.v1.schema.json from dispute.v1.schema.json (v5.4.2-25): the same sections,
less the per-section citations, the unruled branches and the governs key.

    python3 tools/law/derive_dispute_tariff_schema.py law/dispute/dispute.v1.schema.json law/dispute/dispute_tariff.v1.schema.json
"""
import json, sys, copy
law = json.load(open(sys.argv[1]))
d = copy.deepcopy(law["$defs"])
for k in ["earned_unruled", "pay_unruled", "ends_unruled", "delegated", "law"]:
    d.pop(k)
for u in ["shelter_earned", "must_pay", "shelter_ends"]:
    d[u]["oneOf"] = [b for b in d[u]["oneOf"] if not b["$ref"].endswith("_unruled")]
for k, v in d.items():
    if v.get("type") == "object" and "citation" in v.get("properties", {}):
        v["properties"].pop("citation")
        v["required"] = [r for r in v["required"] if r != "citation"]
root = copy.deepcopy(law["$defs"]["law"])
root["properties"].pop("governs")
root["required"] = [r for r in root["required"] if r != "governs"]
out = {
  "$schema": law["$schema"],
  "$id": "https://tally-utility/law/dispute/dispute_tariff.v1.schema.json",
  "title": "Dispute tariff, version 1",
  "description": "A utility's own dispute policy, from its tariff, confirmed at setup (K-07: no assumed default): the same sections as the dispute law, so the two compare like with like. A tariff is the utility's policy, not law: it carries one citation (the tariff provision), no governs key, and no unruled section — a utility's own policy says what it does. Measured against the law in force when written (never looser).",
  "type": "object",
  "additionalProperties": False,
  "required": root["required"],
  "properties": root["properties"],
  "$defs": d,
}
json.dump(out, open(sys.argv[2], "w"), indent=2, ensure_ascii=False)
open(sys.argv[2], "a").write("\n")
