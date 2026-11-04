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
| -23 | money | cash: reversals, positions, application, overpayment credits (round 8 reviewed 2026-11-02: Fable ready, Codex and Opus not yet; round 9 next) |
| -24 | money | unmatched cash, agency pledges (not drafted) |
| -25 | money | disputes (drafted, not reviewed) |
| -26 | money | collections decisions (drafted, not reviewed) |
| -27 | money | a credit applied to a bounced payment's shortfall (AC-44 netting; not drafted; next after -23, ahead of -24) |
| -29 | rates | every Texas county and its time zone, loaded once as shared place data (Ryan 2026-11-04; not drafted) |
| -28 | rates | small fixes: state-agency time zone (CI-010), dated rider order (CI-101), four-decimal rates (CI-109); r1 reviewed 2026-11-02 (not yet); r2 built and frozen 2026-11-04, in review; the meter test fee (CI-091) moved to its own patch after dated history |

**Next free: -30.**

## Mirror queue

1. -23 (money)
2. -25 (money)
3. -26 (money)
4. -28 (rates; r2 frozen 2026-11-04, in review)

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
- **rates → money (2026-11-02), Ryan's call (option 1, DECISION-LOG):** a consolidated (summary) bill should be fixed once it goes out: (1) a parent invoice may be issued only when every live child is already issued (or they issue together), and (2) no child may attach to (`parent_invoice_id` set to) a parent that is already issued. Today `enforce_invoice_immutable` freezes each issued bill's own `location_id` / `parent_invoice_id`, but a parent can go out over a draft child, that draft's premise can then change, and a new child can attach afterwards (-28 r1, Codex B2: the parent's issued pipeline-safety fee then fails its own check). Beyond the fee, it lets a sent summary's total drift from its members. -28 lists the gap as a known limit closed by your patch; no rates-side change.
- **rates → money (2026-11-04):** the -28 r2 reviewers (Opus executed it) found that an invoice of one utility can be attached as a child of another utility's consolidated parent: `parent_invoice_id` is a single-column key, which skips row-level security, and nothing on `invoices` checks the parent's tenant. `tally_app` signed in as the child's utility can do it. -28's zone lookup filters children by the parent's tenant, so every session reads the same zone (battery Z5q/Z5r). The attachment itself is yours (`invoices`), beside the summary-bill-fixed-at-issue rule; otherwise the cross-tenant link fix (CI-116) closes it at the end.
- **scenarios → rates (2026-11-02):** a city-owned system can make no backbilling correction today: -18's law rows bind investor-owned and cooperative utilities only, and a city's delegated row and tariff record wait on the backbilling tariff table (your carried-over item 7). Neither real city tariff modelled (Brenham, Stinnett) states a backbilling rule. `scenarios/backbilling.md` SCN-0019 is written against the ruling; Kyle's answer on what silent cities do decides what onboarding asks.
- **scenarios → money (2026-11-04), Kyle's answers of 2026-11-03** (GBM `application/kyle-decisions-2026-11-03-scenario-batch-1.md`; the scenarios now expect them). Yours to weigh: (1) a partial payment goes to amounts that can ground a disconnection first, a backbilled charge last (SCN-0031); (2) a correction carries an aging date apart from its posting date: what was owed keeps its age, an increase ages from the correction (SCN-0024); (3) a courtesy credit a void absorbed carries onto the correction, or is queued for review if it was given for the error itself (SCN-0004); (4) one deposit balance per account, topped up by a recorded event citing its trigger, not a second deposit; where §7.45 binds, a disconnection cannot trigger an additional deposit (SCN-0010); (5) **Kyle's flag 1:** the deposits build counts every late payment since the deposit was posted (rules DG4, case B15), but he reads §7.45(5)(F)(ii) as a rolling twelve months; (6) a credit left when a deposit-paid final bill is corrected down is a deposit refund, paid whatever its size (SCN-0029); (7) a keyed-low read may be rebilled with more usage, operator's choice recorded (SCN-0027 b).
- **scenarios → rates (2026-11-04), Kyle's answers of 2026-11-03.** Yours to weigh: (1) a rate change states its split method (by days, read date or cycle) when entered, no default; the gas cost factor is one locked figure per billing month, never split (SCN-0001); (2) where a city's ordinance is silent on backbilling, refunds have no limit and undercharges take a six-month platform default until the city records its own rule; this replaces the "unknown law is not permission" refusal for city systems (SCN-0019, SCN-0028; your backbilling tariff table); (3) the Texas law row that lets only a rate misapplication travel by reissue needs revisiting for a human keying error, which Kyle allows to add usage (SCN-0027 b); (4) forfeiting the straddling month applies to a utility's own limit too, as -18 already does (SCN-0016).
- **scenarios → money (2026-11-04), Ryan's call (option 4, DECISION-LOG; roadmap R-19):** the bill-line check in -21 (`invoice_line_arithmetic_gap`) refuses every city bill, because the city tariffs bill per Mcf or Ccf with no therm conversion. New rule for your next bill-line patch: (1) a gas line's unit is one of Ccf, Mcf (volume), therm, dekatherm, MMBtu (energy), stored as the utility writes it; (2) the gas conversion figures (meter factor, Ccf, therms, and the usage line's commodity rate) are required only on an energy-billed line; a volume-billed line carries quantity, unit and rate; (3) a multiplier is stored with the raw quantity it multiplied. Needed before the core build.
