# tests/ — review batteries and reviewer artefacts, one directory per patch

Every `sql/v5.4.x-NN-*.sql` patch is verified by a **battery**: a single psql
script that runs inside one transaction, writes end-to-end as `tally_app`
(`SET LOCAL app.user_id = …; SET ROLE tally_app`), asserts every guard in the
patch header with `PASS Fn` notices, and ends in `ROLLBACK`. Negative cases
live inside `DO … EXCEPTION` blocks so the transaction survives them.

Until 2026-09-08 batteries lived only in the session scratchpad and were lost
when the session's temp directory was cleared — the -07 and -08 batteries
(161 and 173 checks) are gone. From -09 on they are committed here.

## Layout

```
tests/
  v5.4.2-09/
    battery-09.sql          # the regression battery (28 checks, all PASS on the -09 build)
    review/
      review-brief-09.md    # the brief handed to both reviewers (round-1 hash frozen)
      seed.sql              # minimal reviewer fixture (two tenants, three users, three customers)
      precond-seed.sql      # pre-patch rows that make the deploy precondition refuse
      repros/               # reviewer and author repros, one finding each (round 1–3)
      attacks/              # author probes run against the frozen patch
```

## Running a battery

The container `tally-pg` runs WITHOUT a host port (127.0.0.1:5432 belongs to
another project). Always go through `docker exec`. Run against a throwaway
clone so the `tally` database stays virgin:

```sh
docker cp tests/v5.4.2-09/battery-09.sql tally-pg:/tmp/battery-09.sql
docker exec tally-pg psql -U tally -d tally -qtA -c "CREATE DATABASE bat TEMPLATE tally"
docker exec tally-pg psql -U tally -d bat -v ON_ERROR_STOP=1 -f /tmp/battery-09.sql 2>&1 \
  | grep -E 'PASS|FAIL|ERROR'
docker exec tally-pg psql -U tally -d tally -qtA -c "DROP DATABASE bat"
```

Expect one `PASS` line per check and no `ERROR`. A battery is green only under
`-v ON_ERROR_STOP=1`; without it a failed positive case scrolls past.

## Conventions the batteries depend on

- `SET CONSTRAINTS ALL IMMEDIATE` at the top so deferred gates fire at the
  statement, not at the (never reached) commit. Close-then-insert successions
  wrap `SET CONSTRAINTS ALL DEFERRED; …; SET CONSTRAINTS ALL IMMEDIATE` inside
  a single `EXECUTE`.
- `now()` is constant inside the transaction: transaction-time ordering cannot
  be tested in one battery. Races are verified by hand in two sessions and
  recorded in `sql/DEPLOY-VERIFICATION.md`.
- An expected-error `DO` block must not contain its own setup; a setup failure
  would be mistaken for the expected refusal.
- Fixture minimums per table are recorded in the review brief of the patch
  that introduced them; superuser writes the fixtures, `tally_app` writes the
  cases under test.

## Review workflow (per patch)

Fresh-load scratch → strict apply ×2 (`search_path=''`,
`check_function_bodies=on`) → battery → pre-seeded precondition check →
brief with `wc -l` + `md5 -q` → **freeze the file, launch both reviewers**
→ fold findings into one revision → next round on the new hash → mirror into
`tu.sql` after the last banner → fresh rebuild + catalog parity → battery
green on the build. Every reviewer repro that found a hole belongs in
`review/repros/`; if it was folded into the battery, say so in its header.
