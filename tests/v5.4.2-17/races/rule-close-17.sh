#!/usr/bin/env bash
# v5.4.2-17: the two handshakes the convention adds, each in both orders.
#   RC1  A cites a law row (a charge on 2020-06-01) and holds; B's close of the
#       row on that date waits on the row's lock, then sees the citation and
#       is refused.
#   RC2  A closes a law row (to 2010) and holds; B's citation of it on 2020
#       waits, then re-reads the row and is refused: not in force.
#   RC3  A writes a row of schema version 2 and holds; B's freeze of version 2
#       waits, then succeeds; a row of version 2 written after is refused.
#   RC4  A freezes version 3 and holds; B's row of version 3 waits, then sees
#       the freeze and is refused.
#   RC5  A closes a law row (cap 50) and adds its stricter successor (cap 10)
#       and holds; B's tariff of 40 over both waits on the row it found, then
#       re-reads, finds the successor, and is refused as looser than the law
#       (review r1 B1, all three reviewers: the check read, then locked).
#   RC6  A writes a core record of inputs version 2 and holds; B's freeze of
#       version 2 waits, then succeeds; a core record of version 2 after it is
#       refused (review r2, Codex S4).
#   RC7  A freezes inputs version 3 and holds; B's core record of version 3
#       waits, then sees the freeze and is refused.
# Every leg checks that the second session was SEEN WAITING (pg_stat_activity,
# by application_name, wait_event_type Lock) before the first committed, and
# that session A itself succeeded, so no leg passes by running sequentially.
# Runs on its own scratch clone of a -17 database (it commits rows).
#   usage: races/rule-close-17.sh <db-with-17> [scratch-db]
set -uo pipefail
SRC="${1:?db with v5.4.2-17}"
DB="${2:-race17}"
HERE=$(cd "$(dirname "$0")/.." && pwd)
docker exec tally-pg psql -U tally -d postgres -qc "DROP DATABASE IF EXISTS $DB" -qc "CREATE DATABASE $DB TEMPLATE $SRC" >/dev/null 2>&1
docker exec tally-pg psql -U tally -d "$DB" -qc "REVOKE TEMP ON DATABASE $DB FROM PUBLIC" -qc "REVOKE TEMP ON DATABASE $DB FROM tally_app" >/dev/null
PSQL=(docker exec -i tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -q -At)
"${PSQL[@]}" < "$HERE/fixture-iso-17.sql" >/dev/null || { echo "SETUP FAIL: the fixture did not load"; exit 2; }
ROOT=$(cd "$HERE/../.." && pwd)
docker exec tally-pg rm -rf /tmp/law && docker cp "$ROOT/law" tally-pg:/tmp/law
printf 'BEGIN;\n\\i /tmp/law/fixtures/zz/fixture-zz.sql\nCOMMIT;\n' | "${PSQL[@]}" >/dev/null 2>&1 || { echo "SETUP FAIL: the ZZ area did not load"; exit 2; }
"${PSQL[@]}" >/dev/null <<SQL || { echo "SETUP FAIL: the RC5 rows did not load"; exit 2; }
BEGIN;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000017f2';
SET LOCAL ROLE tally_app;
INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction,
                                             effective_from, evidence_reference, evidence_date)
VALUES ('00000000-0000-4000-8000-0000000017f1', 'gas', 'distribution', 'ZZ', 'investor_owned', true, DATE '2000-01-01', 'Cert 1', DATE '2000-01-01');
COMMIT;
INSERT INTO public.zz_fee_rules (id, state_code, service_type, customer_class, effective_from, source_note, terms_kind, terms_version, terms_source)
VALUES ('00000000-0000-4000-8000-0000000017fb', 'ZZ', 'gas', 'residential', DATE '2000-01-01', 'cap 50', 'zz_fee', 1,
        '{"governs": "law", "citation": "ZZ 1", "fee": {"strategy": "flat", "version": 1, "id": "f1", "cap": 50, "citation": "ZZ 1"}, "waivers": []}');
SQL

T=00000000-0000-4000-8000-0000000017f1
U=00000000-0000-4000-8000-0000000017f2
ROW1=00000000-0000-4000-8000-0000000017f9
ROW2=00000000-0000-4000-8000-0000000017fa
fail=0
A_OUT=$(mktemp); B_OUT=$(mktemp); trap 'rm -f "$A_OUT" "$B_OUT"' EXIT

waiting() {
docker exec -i tally-pg psql -U tally -d "$DB" -At -c "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND application_name = 'race17_b' AND wait_event_type = 'Lock'"
}
two() {  # $1 A's SQL (held 3s), $2 B's SQL (starts 1s later)
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
BEGIN;
$1
SELECT pg_sleep(3);
COMMIT;
SQL
APID=$!
sleep 1
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL &
SET application_name = 'race17_b';
$2
SQL
sleep 1
WAITED=$(waiting)
wait $APID; AST=$?
wait
OUT=$(cat "$B_OUT")
}
seen() {
if [ "${AST:-0}" -ne 0 ]; then echo "FAIL $1: session A itself failed: $(cat "$A_OUT")"; fail=1; return 1; fi
if [ "${WAITED:-0}" -lt 1 ]; then echo "FAIL $1: the second session was never seen waiting (sequential, not a race)"; fail=1; return 1; fi
}
APP="SET LOCAL app.user_id = '$U'; SET LOCAL ROLE tally_app;"

two "$APP INSERT INTO public.zz_iso_charges (tenant_id, rule_id, charged_on) VALUES ('$T', '$ROW1', DATE '2020-06-01');" \
    "UPDATE public.zz_iso_rules SET effective_to = DATE '2020-06-01' WHERE id = '$ROW1';"
if seen RC1 && grep -q "needs it in force on 2020-06-01" <<<"$OUT"; then
  echo "PASS RC1: a close waits for a citation in flight, then sees it and is refused"
else echo "FAIL RC1: the close said: $OUT"; fail=1; fi

two "UPDATE public.zz_iso_rules SET effective_to = DATE '2010-01-01' WHERE id = '$ROW2';" \
    "BEGIN; $APP INSERT INTO public.zz_iso_charges (tenant_id, rule_id, charged_on) VALUES ('$T', '$ROW2', DATE '2020-01-01'); COMMIT;"
if seen RC2 && grep -q "is not in force on 2020-01-01" <<<"$OUT"; then
  echo "PASS RC2: a citation waits for a close in flight, then re-reads the row and is refused"
else echo "FAIL RC2: the citation said: $OUT"; fail=1; fi

two "INSERT INTO public.zz_iso_rules (state_code, service_type, customer_class, effective_from, source_note, terms_kind, terms_version, terms_source)
     VALUES ('ZZ', 'gas', 'r3', DATE '2000-01-01', 'r3', 'zz_iso', 2, '{\"governs\": \"law\", \"citation\": \"ZZ 3\", \"cap\": 5}');" \
    "UPDATE public.rule_term_schemas SET accepts_new_rows = false WHERE terms_kind = 'zz_iso' AND terms_version = 2;"
AFTER=$("${PSQL[@]}" 2>&1 <<SQL
INSERT INTO public.zz_iso_rules (state_code, service_type, customer_class, effective_from, source_note, terms_kind, terms_version, terms_source)
VALUES ('ZZ', 'gas', 'r3b', DATE '2000-01-01', 'r3b', 'zz_iso', 2, '{"governs": "law", "citation": "ZZ 3", "cap": 5}');
SQL
)
if seen RC3 && ! grep -q ERROR <<<"$OUT" && grep -q "is frozen" <<<"$AFTER"; then
  echo "PASS RC3: a freeze waits for a row of its version in flight, then holds against the next"
else echo "FAIL RC3: the freeze said: $OUT; the next row said: $AFTER"; fail=1; fi

two "UPDATE public.rule_term_schemas SET accepts_new_rows = false WHERE terms_kind = 'zz_iso' AND terms_version = 3;" \
    "INSERT INTO public.zz_iso_rules (state_code, service_type, customer_class, effective_from, source_note, terms_kind, terms_version, terms_source)
     VALUES ('ZZ', 'gas', 'r4', DATE '2000-01-01', 'r4', 'zz_iso', 3, '{\"governs\": \"law\", \"citation\": \"ZZ 4\", \"cap\": 5}');"
if seen RC4 && grep -q "is frozen" <<<"$OUT"; then
  echo "PASS RC4: a row waits for a freeze of its version in flight, then sees it and is refused"
else echo "FAIL RC4: the row said: $OUT"; fail=1; fi

two "UPDATE public.zz_fee_rules SET effective_to = DATE '2025-01-01' WHERE id = '00000000-0000-4000-8000-0000000017fb';
     INSERT INTO public.zz_fee_rules (state_code, service_type, customer_class, effective_from, source_note, terms_kind, terms_version, terms_source)
     VALUES ('ZZ', 'gas', 'residential', DATE '2025-01-01', 'cap 10', 'zz_fee', 1,
             '{\"governs\": \"law\", \"citation\": \"ZZ 2\", \"fee\": {\"strategy\": \"flat\", \"version\": 1, \"id\": \"f1\", \"cap\": 10, \"citation\": \"ZZ 2\"}, \"waivers\": []}');" \
    "BEGIN; $APP INSERT INTO public.zz_fee_tariffs (tenant_id, state_code, service_type, system_kind, customer_class, effective_from, tariff_reference, terms_kind, terms_version, terms_source)
     VALUES ('$T', 'ZZ', 'gas', 'distribution', 'residential', DATE '2020-01-01', 'Ord 1', 'zz_fee_tariff', 1, '{\"fee\": {\"strategy\": \"flat\", \"version\": 1, \"id\": \"t1\", \"amount\": 40}}'); COMMIT;"
if seen RC5 && grep -q "fee 40 above the cap 10 of cap 10" <<<"$OUT"; then
  echo "PASS RC5: a tariff waits for a close and a stricter successor in flight, then re-reads and is refused against the successor"
else echo "FAIL RC5: the tariff said: $OUT"; fail=1; fi

CORE="SET LOCAL app.user_id = '$U'; SET LOCAL ROLE tally_core;"
CALC="INSERT INTO public.zz_iso_calcs (tenant_id, inputs, inputs_kind, inputs_version, calculated_by) VALUES ('$T', '{\"n\": 1}', 'zz_iso_inputs',"
two "$CORE $CALC 2, 'core x');" \
    "UPDATE public.rule_term_schemas SET accepts_new_rows = false WHERE terms_kind = 'zz_iso_inputs' AND terms_version = 2;"
AFTER=$(printf '%s\n' "BEGIN; $CORE $CALC 2, 'core x'); COMMIT;" | "${PSQL[@]}" 2>&1)
if seen RC6 && ! grep -q ERROR <<<"$OUT" && grep -q "is frozen" <<<"$AFTER"; then
  echo "PASS RC6: a freeze of an inputs version waits for a core record of it in flight, then holds against the next"
else echo "FAIL RC6: the freeze said: $OUT; the next record said: $AFTER"; fail=1; fi

two "UPDATE public.rule_term_schemas SET accepts_new_rows = false WHERE terms_kind = 'zz_iso_inputs' AND terms_version = 3;" \
    "BEGIN; $CORE $CALC 3, 'core x'); COMMIT;"
if seen RC7 && grep -q "is frozen" <<<"$OUT"; then
  echo "PASS RC7: a core record waits for a freeze of its inputs version in flight, then sees it and is refused"
else echo "FAIL RC7: the record said: $OUT"; fail=1; fi

echo "rule-close-17: $([ $fail -eq 0 ] && echo 'all legs pass' || echo 'FAILURES')"
exit $fail
