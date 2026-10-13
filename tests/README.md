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
  ci.sh                     # EVERY check, as .github/workflows/ci.yml runs it (--build: image from postgres/Dockerfile,
                            #   fresh tally-pg). Clones `tally`; strict-applies (twice) patches not yet mirrored;
                            #   batteries -09..-14, -15, -16, -17, -18; -18's and -15's migrations (while `tally` is pre-18 / pre-15); -17's isolation, races and law files; -15, -16 and -12 races;
                            #   -15's and -13's evidence scripts; the tenant-isolation invariants. Never writes `tally`.
  v5.4.2-18/                # backbilling at the rule-terms convention: the 16 Texas rows adopted in place (landed 2026-10-10; r6 frozen, mirrored)
    battery-18.sql          # 108 checks, groups S M K D O H X L G, on the migrated table: the kind and its facet; the
                            #   registration; the sixteen documents against expectations typed from the -13 seed; the
                            #   document gate; overlap and applicability; history and the close floor over planted
                            #   citations; the area's insert check; lookups; neighbours (a ZZ state's rows only prove the gate)
    run-battery-18.sh       # runs battery-18 against <db> that has -18 applied
    migration-18.py         # P1-P11 on clones of a PRE-18 base: the patch on the real data (documents built apart from the
                            #   patch; identity unchanged), twice, with extra legacy rows, three aborts that leave the table
                            #   untouched, and the adoption check on its own (23 single-key differences refused)
    mutations-18.py        # 107 mutations, each caught at its named check (battery, F13 of battery-13, P-labels, or the
                            #   patch's own refusal); needs a PRE-18 base (a database built from the -17 tu.sql: `tally` is post-18 now)
  v5.4.2-17/                # the rule-terms convention written once (DRAFT r6, 2026-10-09; round 5: Opus, Fable and Codex all ready; their should-fixes folded in r6)
    battery-17.sql          # 247 checks, groups R V F T L U C A P I K G, on a fictional state's law (ZZ) from
                            #   law/fixtures/zz/ (fixture-zz.sql); every refusal must carry its own guard's phrase
    run-battery-17.sh       # copies law/ into the container, then runs the battery against <db>
    isolation-17.sh         # X1-X6: a facet after its schema's transaction; rows, citations, closes, freezes
                            #   and core records outside READ COMMITTED (fixture-iso-17.sql, committed into a scratch clone)
    races/rule-close-17.sh  # RC1-RC7: a close against a citation, a freeze against a row or a core record, each
                            #   in both orders; a tariff against a close and successor in flight; the second session seen waiting
    lawfiles-17.sh          # W1-W5: law files valid; seed SQL not drifted; seed twice + round trip; the database
                            #   validator agrees with jsonschema on 899 documents; the strict loader's refusals
    mutations-17.py         # 165 mutations, each caught at its named check (battery, X, R, W or APPLY); clones
                            #   `tally` (the -16 build) and revokes TEMP on every clone
  v5.4.2-15/                # deposits at the rule-terms convention: the deposit law leaves the database (landed 2026-10-13; r8 frozen, mirrored)
    battery-15r.sql         # 356 checks: the kinds and their schemas, the law table and its Texas rows, categories and
                            #   tariffs against the law, the rate floor, deposits citing law and tariff rows, instalments,
                            #   money not leaving before it arrived, refund state from the events (multi-row statements),
                            #   accruals, partial returns, the return-due record and its evidence, tenancy
    run-battery-15r.sh      # runs battery-15r against <db> that has -15 applied
    fail-first.py           # runs each `rN:begin` block of the battery alone: a block fails on the previous build, passes on this
    migration-15r.py        # P0-P6 on clones of a PRE-15 base (the -18 build): strict apply, carried legacy deposits unchanged,
                            #   twice, a real deposit / waiver / rate / accrual stops it untouched, the -06 law gone
    mutations-15r.py        # 175 mutations, each caught at its named check; needs a PRE-15 base (a database built from the -18 tu.sql)
    terms-15.py             # the document schemas against their examples and fixtures
    evidence-txn-15.sh      # X1-X2: return-due evidence and an instalment schedule only in their own transaction (two transactions)
    races/due-mutex-15.sh   # R1-R10: one live due row, a due row vs a refund, a refund vs a withdrawal, a rate backdated during
                            #   an accrual, law and tariff closes racing citing deposits, rates only under READ COMMITTED
    review/                 # briefs r1-r8, the frozen patch and battery of each round, one report per reviewer per round, probes
  NOTE (2026-10-02): CREATE DATABASE … TEMPLATE does not copy the database ACL — tally_app regains TEMP on a
  clone. Revoke it after cloning (REVOKE TEMP ON DATABASE x FROM PUBLIC, tally_app) or the depth fences are open.
  v5.4.2-14/                # meter_governing_test() without R-36's gate (the core's now), LANDED 2026-09-30
    battery-14.sql          # 6 checks: no gate column, no month count in the body, exact grants, still
                            #   answers as tally_app, comments name the core, AC-32
    mutations-14.py         # 4 mutations; needs a -13 BASE (tu.sql ab3ce7ae…, 25,930 lines)
    parity/catalog-identity.sql  # the -13 identity query plus every comment (function, table, column)
  v5.4.2-12/                # the meter test history (CI-091), LANDED 2026-09-23
    battery-12.sql          # 116 checks, groups A-K; every guard has a planted mutation that fails it.
                            #   Restated 2026-09-30 for -14: F1/F3/F4/F5/F7/F10 assert weak_provenance and
                            #   the governing test instead of supervisor_gate (passes with or without -14)
    isolation-check-12.sql  # 3 checks: a cutover change is refused outside READ COMMITTED
                            #   (cannot live in the battery, which is one READ COMMITTED transaction)
    races/pointer-mutex-12.sh   # two sessions: the pointer's row-version mutex (R1); applies -12 only to a
                                #   base without it (-12 cannot re-apply over a -14 build)
    review/                 # five rounds: review-brief-12{,-round2..5}.md and the frozen patch
                            #   and battery for each round (patch-12-frozen-r1..r5.sql)
  v5.4.2-13/                # A-2 at PARITY (re-scoped 2026-09-28), LANDED 2026-09-30. The schema stores per-state
                            #   backbilling law and the correction records; the C# core evaluates the law.
    battery-13.sql          # 99 checks, groups A-K + Z (a fictional state ZZ stored with no DDL)
    evidence-txn-13.sh      # X1: evidence only in its evaluation's transaction (two committed transactions)
    mutations-13.py         # 45 mutations, each must be caught at its named check. Needs a -12 BASE
                            #   (tu.sql 2aa59147…, 23,452 lines): on the mirrored build CREATE TABLE IF NOT
                            #   EXISTS keeps the real tables, so table-definition mutations do not take.
    parity/                 # catalog-counts.sql and catalog-identity.sql: run on the patched clone and the
                            #   fresh build and diff (the identity list must match line for line)
    r7/                     # the r7 draft's battery (146), mutations (84) and fence-and-race script —
                            #   they tested law in triggers; now scenario material for the core
                            #   (application/a2-rules-for-the-core.md). Run only against the r7 patch (570d437).
    review/                 # r7's review rounds 1-6 (frozen patches and batteries); parity round P1: brief,
                            #   frozen patch and battery, findings and dispositions, both reviewers' probes
  v5.4.2-11/
    battery-11.sql          # 41 checks; TWO tenants throughout (every headline check is cross-tenant).
                            #   Group G is unusual and deliberate: it proves the tenant-isolation
                            #   assertion CATCHES drift rather than merely passing — G2-G9 each create
                            #   a leaky object and require a raise, G10a proves a cross-tenant WRITE
                            #   really lands before G10b requires the raise, G11 guards a false positive.
    probe-pre-11.sql        # the 11 discriminating checks under SAVEPOINTs, to run against an UNPATCHED
                            #   build: every line must read PRE-PATCH HOLE there and "as expected" here
    review/
      review-brief-11.md          # round 1 (hash frozen)
      review-brief-11-round2.md   # round 2 — every round-1 finding and its disposition
      review-brief-11-round3.md   # round 3 — confirmation, scoped to section 7 and R5
                                  # (the patch went five rounds; rounds 4 and 5 have no committed
                                  #  brief — their hashes and outcomes are in sql/DEPLOY-VERIFICATION.md)
  v5.4.2-10/
    battery-10.sql          # 58 checks; review/ holds five frozen revisions, five briefs, per-round reviewer repros, races/ (two-session scripts + outputs)
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
