# The board — read this first, then your stream's handoff

**This file is not a session handoff.** Several sessions run at once, one per stream, each in its own clone. Find your working directory in the table below and read that stream's handoff file: it holds your status, next steps and warnings. This board holds only what crosses streams. Edit it only to start or end a stream, claim a patch number, change the mirror queue, or leave a note for another stream; keep each edit small and `git pull --rebase` before pushing. Set up 2026-10-29 (DECISION-LOG 2026-10-29).

## Streams

| Folder | Stream | Handoff file | Owns |
|---|---|---|---|
| `~/code/tally-utility` | schema: money and collections | `handoffs/schema-money.md` | payments, credits, the ledger, invoices and their applications, deposits, disputes, collections and dunning, `service_orders`, program enrollments, notices and the communication log |
| `~/code/tally-utility-rates` | schema: rates, meters, places | `handoffs/schema-rates.md` | rate schedules, items and versions, riders, tax and franchise rules, gas cost and PGA, places and jurisdictions, zones and factor tables, meters, `meter_readings`, `meter_deployments`, `service_locations`, backbilling rules |
| `~/code/tally-utility-scenarios` | scenarios and test strategy (P2), beside the schema (gate relaxed 2026-10-29) | `handoffs/scenarios.md` | no schema files; `scenarios/` (Ryan, 2026-11-02) and `application/scenarios-source-inventory-2026-11-02/` |

A table not listed belongs to whichever stream touches it first; add it here when you do. A patch that needs another stream's table leaves a note below rather than editing it.

## Shared resources

- **`tests/ci.sh`** takes a lock (`/tmp/tally-ci.lock`) across all clones: one run at a time. "waiting: ci.sh is running from …" means another stream holds it.
- **`tally` and the tally-pg container** are shared. Mutation and battery runners use per-patch database names (`m23`, `m25`, …); keep yours unique to your patch number.
- **Mirroring writes `tally`.** Before a mirror (or `ci.sh --build`, which replaces the container), check that no other stream is mid-run: `docker exec tally-pg psql -U tally -d postgres -Atc "select distinct datname from pg_stat_activity where datname is not null"` should show nothing but `postgres`, `tally` and your own. If another stream's database is busy, wait or ask Ryan.
- **At most two mutation runs at once** (Docker has 7.75 GB; CI has died of memory before).
- **`tests/ci.sh`'s `PENDING` list** holds both streams' unmirrored patches, in mirror-queue order. Add yours only once its battery passes alone.
- **Shared append-only files** (DECISION-LOG, CHANGELOG, the parity measurement, PATCH-LESSONS, `wiki-ingestion-pending.md` in GBM): add your entry, `git pull --rebase`, push. Only the session that mirrors moves the oldest CHANGELOG entry to the archive.
- **Memory** is one folder for all clones (each clone's project memory folder links to the main one).

## Patch numbers

Claim the next free number here, commit and push, before creating the file. Numbers are names, not mirror order.

| Number | Stream | What |
|---|---|---|
| -23 | money | cash: reversals, positions, application, overpayment credits (round 8 frozen 2026-11-02, in review) |
| -24 | money | unmatched cash, agency pledges (not drafted) |
| -25 | money | disputes (drafted, not reviewed) |
| -26 | money | collections decisions (drafted, not reviewed) |
| -27 | money | a credit applied to a bounced payment's shortfall (AC-44 netting; not drafted; next after -23, ahead of -24) |
| -28 | rates | small fixes: state-agency time zone (CI-010), dated rider order (CI-101), four-decimal rates (CI-109); built, not yet frozen; the meter test fee (CI-091) moved to its own patch after dated history |

**Next free: -29.**

## Mirror queue

1. -23 (money)
2. -25 (money)
3. -26 (money)

A patch joins the queue when it is frozen for review. Before mirroring, re-run its battery on the current `tally`; a patch reviewed before an earlier mirror is re-tested, and re-reviewed only if the re-test fails.

## After both schema streams finish

Two patches touch nearly every table and run last, alone: the cross-tenant link fix (CI-116, 267 single-column foreign keys) and Kyle's version check on every edited record (K-01). Then the final parity re-grade.

## When the schema reaches parity

Two session slots free up. The platform work (P4: AWS environments, CI/CD, the .NET solution, tenant-scoped data access; login is Cognito, ruled 2026-10-14) starts then, in a stream of its own (DECISION-LOG 2026-10-29).

## Unassigned

- R-03 scoping: which setup tables lose DELETE (part money, part rates; settle with the final pair above).
- The GitHub Actions bump.
- A second look at the low-confidence rows of the parity measurement.

## Notes between streams

- **rates → money (2026-11-02):** `tests/ci.sh` fails at battery -15, case V23, with or without -28: it dates a deposit's return due `2026-11-01` and pairs it with a closure the database stamps now(), so since 2026-11-02 the closure is after the due date and is (rightly) refused. A fixed date that has passed; V15–V17's comment assumes "a day long after the March bills". Yours to fix (deposits).
- **rates → money (2026-11-02):** -28 is in `ci.sh`'s PENDING list and changes `rate_item_dependencies` (dated, A-1 group 2; -21's retire is now a close). Batteries -19 and -21 and races `cycle-19.sh` / `labels-21.sh` are ported in the same commit. Also seen while there: `enforce_deposit_event` and `enforce_deposit_return_due_evidence` take day boundaries in UTC, and `close_accounting_period` at Etc/GMT+12 (CI-010's "other day-boundary code"); flagged, not touched.
- **rates → money (2026-11-02):** -28 section 3 refuses a rate with more than four decimals where rates are entered (Kyle K-06: rate item versions, tier rates, schedule overrides). `invoice_line_items.rate` and `gas_commodity_rate` (your table) still take six; whether a bill line's rate gets the same check is yours to decide.
