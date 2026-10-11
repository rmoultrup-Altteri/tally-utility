#!/bin/bash
# Run battery-18 against a database that has v5.4.2-18 applied.
# usage: tests/v5.4.2-18/run-battery-18.sh [db]   (default: tally)
set -euo pipefail
DB=${1:-tally}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
F=/tmp/battery-18-$$.sql
docker cp "$ROOT/tests/v5.4.2-18/battery-18.sql" tally-pg:$F
trap 'docker exec tally-pg rm -f $F' EXIT
docker exec tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -q -f $F
