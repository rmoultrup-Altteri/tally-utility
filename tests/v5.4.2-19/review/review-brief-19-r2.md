# Review round 2: v5.4.2-19 — hardening batch 1 (close the holes in what is already built)

You are one of three independent reviewers (separate models; you will not see each other's work until this round — now you may).

**Frozen artefacts** (repo `/Users/ryanscomputer/code/tally-utility`; check the hashes and say if they differ):
- patch `tests/v5.4.2-19/review/patch-19-frozen-r2.sql` — md5 `7e7416abdf7161bdd1b7eff2621de2dd` (1,409 lines)
- battery `tests/v5.4.2-19/review/battery-19-frozen-r2.sql` — md5 `8fab48539eb6c64263bd95d4deb1a731` (146 checks)
- race script `tests/v5.4.2-19/races/cycle-19.sh` — md5 `91f2817513fc9079fb04648b37f03446` (C1–C7)
- CI `tests/ci.sh` — md5 `a5e640c0a0ae45e04a0e21fc04e9bc51` (clone failures now fail: `cstep`)
- round 1: the r1 freeze (`patch-19-frozen-r1.sql`, `battery-19-frozen-r1.sql`) and the three reviews `opus-r1.md`, `fable-r1.md`, `codex-r1.md` in the same folder
- why each item is here: `application/invariant-parity-measurement-2026-10-13.md` and `application/step1-sequencing-2026-10-13.md` (wave 1); Ryan's call on the running balance: top entry of `application/DECISION-LOG.md`
- the live schema: `sql/tu.sql` (append-only; the patch is applied on top of it)

State at freeze: strict application twice (second run skipped by the gate), 146/146 battery checks, C1–C7, and the full CI suite (25 steps) pass. C5 was shown to FAIL against r1's conditional supersession write (a superseded card committed active), so it catches the bug it is for.

**What changed since r1.** Read the header's "Revision r2" paragraph first. In short:
- Reads: an application INSERT carries no lock record (born unconsumed); a consumed read (locked or void_released) freezes every column except a named follow-up whitelist; lock pointers move only by void_invoice()'s exact write or a correction run's re-lock; the lock flag is set only with the move to locked.
- Payments: one receipt per processor transaction keys on money in (`amount > 0`), not on lineage labels; a row citing `refunds_payment_id` must be a negative refund.
- AI citations bind the tenant (composite FK) and are write-once. The ledger's `created_at` is the database's.
- Imports: file identity write-once; finished statuses final; one live commit per file whatever its type.
- Rider cycle walk is a linear set walk with a stated lock order. Invoice image and hash: frozen together once issued, change together on a draft. Anomalies freeze subject and detection fields. A superseded method cannot be made default, and (Codex B4) supersession always rewrites the predecessor, even an inactive one.
- **Ryan's decision (CI-019):** `account_ledger.running_balance` is dropped with its trigger; `void_invoice()` now returns the summed ledger balance (section 8).
- New residuals R11–R14; R2 is closed.

**Standing rules and decisions (challenge them, but know they are Ryan's):**
1. Nothing is live: the tables tightened are empty in every build from tu.sql.
2. Schema vs core: the schema represents and protects record integrity; the C# core evaluates. Do not ask for rule evaluation in triggers.
3. A guard must act, not record; a check narrower than its claim buys false confidence; test the boundary on both sides.
4. A fact a guard depends on must be written by the database, not an app-writable log.
5. A count/reach guard races concurrent writers: prefer a row-version mutex to a bare lock; state the lock order.
6. A CHECK whose leg can be NULL passes; coalesce the NULL leg.
7. A "same tenant" check must be positive (visible AND of this tenant).

## What to do
1. **Round-1 closure.** For every blocking item in all three r1 reviews (yours and the other two), say closed / not closed, with the r2 line or a reproduction. Where r2 chose a different fix from the one proposed, judge the fix, not the proposal.
2. **New code.** The born-unconsumed INSERT trigger; the Block 2 whitelist (`jsonb_each(to_jsonb(OLD))` — compare it to every `meter_readings` column, and check nothing legitimate after consumption is now refused, e.g. void_invoice(), the correction re-lock, the follow-up workflow); the payments refund CHECK and index predicate; the AI composite FKs and write-once trigger; the import job record trigger; the unconditional supersession write.
3. **Section 8 (running balance).** The rewritten `void_invoice()` against the last live definition in tu.sql: is it otherwise identical (SECURITY DEFINER, search_path, grants, owner, every other behaviour)? Does anything else in tu.sql (function, view, materialized view, index, grant, comment) still reference `running_balance`? Is the dropped trigger's function used anywhere else?
4. **Tests.** Does each new case fail without its guard? Is anything asserted true only by accident? Does the race script prove B was blocked by A?
5. Verdict: **ready** / **not yet** (list blocking items). Separate findings: blocking, should-fix, note. Ground every claim in file:line or a reproduction.

## How to probe (Opus and Fable)
Never touch the `tally` or `postgres` databases or the repo files (except your own report file). Make your own clones, prefixed with your name:
```
docker exec tally-pg psql -U tally -d postgres -c "CREATE DATABASE <you>19 TEMPLATE tally"
docker exec tally-pg psql -U tally -d <you>19 -c "REVOKE TEMP ON DATABASE <you>19 FROM PUBLIC, tally_app, tally_core"
(echo "SET search_path = ''; SET check_function_bodies = on;"; cat tests/v5.4.2-19/review/patch-19-frozen-r2.sql) | docker exec -i tally-pg psql -U tally -d <you>19 -v ON_ERROR_STOP=1 -q -f -
docker cp tests/v5.4.2-19/review/battery-19-frozen-r2.sql tally-pg:/tmp/<you>b.sql && docker exec tally-pg psql -U tally -d <you>19 -v ON_ERROR_STOP=1 -q -f /tmp/<you>b.sql
```
`CREATE DATABASE … TEMPLATE` drops the database ACL, hence the REVOKE. `tally` is the pre-19 base. Write probes as `tally_app` with `SET LOCAL app.user_id`; the battery's `pg_temp.refuses(label, sql, sqlstate)` helper shows how. For races, run `tests/v5.4.2-19/races/cycle-19.sh` against your own throwaway clone with the patch applied. Drop your databases when done.

## Output
Write the full review to `OUTPUT_PATH`. Final reply SHORT (under 2,500 characters): verdict, blocking items (one line each with file:line), top should-fix.
