#!/bin/bash
# Run battery-17 against a database that has v5.4.2-17 applied.
# usage: tests/v5.4.2-17/run-battery-17.sh [db]   (default: tally)
set -euo pipefail
DB=${1:-tally}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
docker exec tally-pg rm -rf /tmp/law
docker cp "$ROOT/law" tally-pg:/tmp/law
docker cp "$ROOT/tests/v5.4.2-17/battery-17.sql" tally-pg:/tmp/battery-17.sql
docker exec tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -q -o /dev/null -f /tmp/battery-17.sql
