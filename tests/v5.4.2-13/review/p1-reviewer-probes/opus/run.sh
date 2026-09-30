#!/bin/sh
# usage: run.sh probe.sql  — runs fixtures + probe in one transaction on rv_b (probe ends with ROLLBACK)
D=$(cd "$(dirname "$0")" && pwd)
{ echo '\set ON_ERROR_STOP 1'; cat "$D/fixtures.sql"; grep -v '^\\i fixtures.sql' "$1" | grep -v '^\\set ON_ERROR_STOP'; } \
  | docker exec -i tally-pg psql -U tally -d rv_b -q -P pager=off 2>&1
