#!/usr/bin/env bash
# The law-file checks (inventory L1-L3, V10) on a scratch clone of a -17
# database with the ZZ fixture area committed:
#   W1  every law file lints, types and validates (lawc check)
#   W2  the committed seed SQL is what the law files emit today (no drift)
#   W3  seeding twice changes nothing the second time, and every stored row's
#       document equals its file's; no row in a seeded table lacks a file
#   W4  the database validator and a standard JSON Schema 2020-12 validator
#       agree on every example document and every single-edit mutation of it
#   W5  the strict YAML loader refuses duplicate keys, anchors (so aliases,
#       which need one),
#       merge keys, tags, and non-canonical numbers
# usage: tests/v5.4.2-17/lawfiles-17.sh <db-with-17> [scratch-db]
set -uo pipefail
SRC="${1:?db with v5.4.2-17}"
DB="${2:-law17}"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PY="${LAWC_PYTHON:-$ROOT/tools/law/.venv/bin/python}"
LAWC=("$PY" "$ROOT/tools/law/lawc.py")
export LAWC_DB="$DB"
fail=0
docker exec tally-pg psql -U tally -d postgres -qc "DROP DATABASE IF EXISTS $DB" -qc "CREATE DATABASE $DB TEMPLATE $SRC" >/dev/null 2>&1
docker exec tally-pg psql -U tally -d "$DB" -qc "REVOKE TEMP ON DATABASE $DB FROM PUBLIC" -qc "REVOKE TEMP ON DATABASE $DB FROM tally_app" >/dev/null
docker exec tally-pg rm -rf /tmp/law && docker cp "$ROOT/law" tally-pg:/tmp/law
printf 'BEGIN;\n\\i /tmp/law/fixtures/zz/fixture-zz.sql\nCOMMIT;\n' \
  | docker exec -i tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -q -o /dev/null 2>/dev/null \
  || { echo "SETUP FAIL: the ZZ fixture area did not load"; exit 2; }

LAWFILES=()
while IFS= read -r f; do LAWFILES+=("$f"); done < <(find "$ROOT/law" -name '*.yaml' -not -path '*/examples/*' | sort)

if "${LAWC[@]}" check "${LAWFILES[@]}"; then echo "PASS W1: every law file is valid"; else echo "FAIL W1"; fail=1; fi

drift=0
for f in "${LAWFILES[@]}"; do
  seed="${f%.yaml}.seed.sql"
  if ! diff -q <("${LAWC[@]}" emit "$f") "$seed" >/dev/null 2>&1; then echo "  drift: $seed is not what $f emits"; drift=1; fi
done
if [ $drift -eq 0 ]; then echo "PASS W2: the committed seed SQL matches its law files"; else echo "FAIL W2"; fail=1; fi

if "${LAWC[@]}" roundtrip "${LAWFILES[@]}"; then echo "PASS W3: seeded, re-seeded unchanged, every row equals its file"; else echo "FAIL W3"; fail=1; fi

EX="$ROOT/law/fixtures/zz/examples"
SCH="$ROOT/law/fixtures/zz"
w4=0
"${LAWC[@]}" crosscheck "$SCH/zz_fee.v1.schema.json" "$EX/zz_fee.flat.yaml" "$EX/zz_fee.greater_of.yaml" "$EX/zz_fee.delegated.yaml" || w4=1
"${LAWC[@]}" crosscheck "$SCH/zz_fee_tariff.v1.schema.json" "$EX/zz_fee_tariff.yaml" || w4=1
"${LAWC[@]}" crosscheck "$SCH/zz_charge_inputs.v1.schema.json" "$EX/zz_charge_inputs.yaml" || w4=1
if [ $w4 -eq 0 ]; then echo "PASS W4: the database validator agrees with the reference validator"; else echo "FAIL W4"; fail=1; fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
w5=0
bad() {  # $1 label, $2 expected phrase, $3 YAML body (a law file)
  printf '%s\n' "$3" > "$TMP/bad.yaml"
  cp "$SCH/zz_fee_tariff.v1.schema.json" "$TMP/"
  out=$("${LAWC[@]}" check "$TMP/bad.yaml" 2>&1)
  if grep -qF "$2" <<<"$out"; then :; else echo "  W5 $1: expected \"$2\", got: $out"; w5=1; fi
}
HEAD='table: public.zz_fee_rules
kind: zz_fee
version: 1
key: [customer_class]
schema: zz_fee_tariff.v1.schema.json'
bad dup "repeats the key" "$HEAD
rows: []
rows: []"
bad anchor "anchors (&r) are refused" "$HEAD
rows: &r []"
bad merge "merge keys" "$HEAD
rows:
  - <<: {name: x}"
bad tag "explicit tags" "$HEAD
rows: !!seq []"
bad number "non-canonical number" "$HEAD
rows:
  - name: r
    state_code: ZZ
    service_type: gas
    owner_types: any
    system_kinds: any
    commission_jurisdiction: any
    customer_class: residential
    effective_from: \"2000-01-01\"
    source_note: x
    terms: {fee: {strategy: flat, version: 1, id: t1, amount: 1.50}}"
bad omitted "never omitted" "$HEAD
rows:
  - name: r
    state_code: ZZ
    service_type: gas
    owner_types: [investor_owned]
    system_kinds: any
    commission_jurisdiction: yes
    customer_class: residential
    effective_from: \"2000-01-01\"
    source_note: x
    terms: {fee: {strategy: flat, version: 1, id: t1, amount: 1}}"
if [ $w5 -eq 0 ]; then echo "PASS W5: the loader refuses duplicate keys, anchors, merge keys, tags, non-canonical numbers and a yes for true"; else echo "FAIL W5"; fail=1; fi

echo "lawfiles-17: $([ $fail -eq 0 ] && echo 'all pass' || echo 'FAILURES')"
exit $fail
