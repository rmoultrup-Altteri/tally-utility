#!/bin/bash
# Run battery-15r against a database that has the rewritten v5.4.2-15 applied.
# usage: tests/v5.4.2-15/run-battery-15r.sh [db]   (default: tally)
set -euo pipefail
DB=${1:-tally}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
docker cp "$ROOT/tests/v5.4.2-15/battery-15r.sql" tally-pg:/tmp/battery-15r.sql
docker exec tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -q -o /dev/null -f /tmp/battery-15r.sql
