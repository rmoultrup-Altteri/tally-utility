#!/usr/bin/env bash
# The whole check suite, as CI runs it (rule-terms v2 §5; inventory L3).
#
#   tests/ci.sh            use the running tally-pg container (local)
#   tests/ci.sh --build    build the image from postgres/Dockerfile, start a
#                          fresh tally-pg from it, wait for its init (CI)
#
# It never writes the `tally` database: every check runs on a clone of it.
# Patches drafted but not yet mirrored into tu.sql (PENDING) are strict-
# applied to the clone (search_path='' and function-body checking on, twice:
# a patch must re-apply cleanly); once a patch is mirrored, its marker table
# exists in `tally` and it is skipped.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
export LAWC_PYTHON="${LAWC_PYTHON:-$ROOT/tools/law/.venv/bin/python}"

# patch file : a table it creates (its marker)
PENDING=(
)
BASE=ci_base

if [ "${1:-}" = "--build" ]; then
  docker build -q -t tally-postgres -f postgres/Dockerfile . >/dev/null || { echo "SETUP FAIL: image build"; exit 2; }
  docker rm -f tally-pg >/dev/null 2>&1 || true
  docker run -d --name tally-pg -e POSTGRES_PASSWORD=tally tally-postgres >/dev/null || { echo "SETUP FAIL: container"; exit 2; }
  # A probe before this line hits the temporary init server (tu.sql is still
  # loading); the line means the real server is starting.
  for _ in $(seq 1 300); do
    docker logs tally-pg 2>&1 | grep -q "PostgreSQL init process complete" && break
    sleep 1
  done
  for _ in $(seq 1 60); do docker exec tally-pg pg_isready -U tally -d tally >/dev/null 2>&1 && break; sleep 1; done
  if docker logs tally-pg 2>&1 | grep -q "ERROR:"; then
    echo "SETUP FAIL: tu.sql raised errors during init:"; docker logs tally-pg 2>&1 | grep -m5 "ERROR:"; exit 2
  fi
fi

q()  { docker exec -i tally-pg psql -U tally -d "$1" -v ON_ERROR_STOP=1 -q -At "${@:2}"; }
clone() {  # $1 new db, $2 template
  docker exec tally-pg psql -U tally -d postgres -qc "DROP DATABASE IF EXISTS $1" -qc "CREATE DATABASE $1 TEMPLATE $2" >/dev/null 2>&1 || return 1
  # CREATE DATABASE … TEMPLATE does not copy the database ACL: the app role
  # would hold TEMP again and the trigger-depth fences would be open.
  q "$1" -c "REVOKE TEMP ON DATABASE $1 FROM PUBLIC" -c "REVOKE TEMP ON DATABASE $1 FROM tally_app" >/dev/null
  if q "$1" -c "SELECT 1 FROM pg_roles WHERE rolname = 'tally_core'" | grep -q 1; then
    q "$1" -c "REVOKE TEMP ON DATABASE $1 FROM tally_core" >/dev/null
  fi
}

results=()
fail=0
step() {  # $1 label, rest: the command
  local label=$1; shift
  if out=$("$@" 2>&1); then
    results+=("PASS  $label")
  else
    results+=("FAIL  $label"); fail=1
    echo "---- $label"; echo "$out" | tail -25
  fi
}

clone "$BASE" tally || { echo "SETUP FAIL: clone"; exit 2; }
for entry in ${PENDING[@]+"${PENDING[@]}"}; do
  patch=${entry%%:*}; marker=${entry##*:}
  if [ "$(q tally -c "SELECT to_regclass('public.$marker') IS NULL")" = "t" ]; then
    docker cp "$patch" tally-pg:/tmp/pending.sql
    for pass in 1 2; do
      step "strict apply $(basename "$patch") (pass $pass)" \
        docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg \
        psql -U tally -d "$BASE" -v ON_ERROR_STOP=1 -q -o /dev/null -f /tmp/pending.sql
    done
  fi
done

battery() {  # $1 file
  docker cp "$1" tally-pg:/tmp/battery.sql && q "$BASE" -o /dev/null -f /tmp/battery.sql
}
for n in 09 10 11 12 13 14 16; do
  step "battery v5.4.2-$n" battery "tests/v5.4.2-$n/battery-$n.sql"
done
step "battery v5.4.2-17" tests/v5.4.2-17/run-battery-17.sh "$BASE"
step "isolation v5.4.2-17" tests/v5.4.2-17/isolation-17.sh "$BASE" ci_iso17
step "races v5.4.2-17" tests/v5.4.2-17/races/rule-close-17.sh "$BASE" ci_race17
step "law files v5.4.2-17" tests/v5.4.2-17/lawfiles-17.sh "$BASE" ci_law17
clone ci_r16 "$BASE" && step "races v5.4.2-16" tests/v5.4.2-16/races/place-close-16.sh ci_r16
clone ci_e13 "$BASE" && step "evidence txn v5.4.2-13" tests/v5.4.2-13/evidence-txn-13.sh ci_e13
step "races v5.4.2-12" tests/v5.4.2-12/races/pointer-mutex-12.sh
step "tenant isolation invariants" q "$BASE" -c "SELECT public.assert_tenant_isolation_invariants()"
step "core role invariants" q "$BASE" -c "SELECT public.assert_core_role_invariants()"
step "rule table invariants" q "$BASE" -c "SELECT public.assert_rule_table_invariants()"

printf '%s\n' "${results[@]}"
echo "ci: $([ $fail -eq 0 ] && echo 'all pass' || echo 'FAILURES')"
exit $fail
