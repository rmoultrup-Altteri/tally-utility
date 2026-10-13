# Review round 1: v5.4.2-19 — hardening batch 1 (close the holes in what is already built)

You are one of three independent reviewers (separate models; you will not see each other's work).

**Frozen artefacts** (repo `/Users/ryanscomputer/code/tally-utility`; check the hashes and say if they differ):
- patch `tests/v5.4.2-19/review/patch-19-frozen-r1.sql` — md5 `63157e6e3343e62d4e547c31e6c02e14` (897 lines)
- battery `tests/v5.4.2-19/review/battery-19-frozen-r1.sql` — md5 `f4f321db406e717074fc54a05e596371` (104 checks)
- race script `tests/v5.4.2-19/races/cycle-19.sh` — md5 `3ab9a3e34e1f8a15a5548d8fd6b9ccbf` (C1–C4)
- why each item is here: `application/invariant-parity-measurement-2026-10-13.md` (the CI rows named in the patch header) and `application/step1-sequencing-2026-10-13.md` (wave 1)
- the live schema: `sql/tu.sql` (append-only; the patch is applied on top of it)
- also changed: `tests/v5.4.2-11/battery-11.sql` (its anomaly fixtures gained a dedup key) and `tests/ci.sh` (the patch is PENDING; battery-19 and the race run in CI)

**What it is.** About twenty small fixes on tables that are empty today, each closing a named gap from the parity measurement: meter reads (the database no longer computes usage with no rollover branch; a read a voided bill released is frozen like a locked one; the void carve-out is narrowed to void_invoice()'s exact write; the lock time is the database's), rates (tier-proration default restored; coverage order; WNA deadband columns; rider dependencies must form a DAG within one tenant, with a row-version mutex on the schedule header), payments (effective date and method; NACHA return code; one original payment per processor transaction), payment methods (account identity frozen; changes by supersession; notice-of-change fields), logs (dunning, escheatment and AI audit rows append-only with DB-stamped created_at; AI-created orders and charges cite their audit row), anomalies (dedup key required and immediately unique; identity and first detection write-once; recurrence only grows), ad-hoc approval capture write-once, invoice image hash, file imports (named and hashed; one live job per file content), attestation on active medical holds, and `account_balance_as_of`. Read the patch header first: it lists what changes, what is refused, and ten residuals (R1–R10) that are out of scope on purpose.

**Standing rules and decisions (challenge them, but know they are Ryan's):**
1. Nothing is live: the tables tightened are empty in every build from tu.sql. The patch fails rather than skip a non-conforming row.
2. Schema vs core: the schema represents and protects record integrity; the C# core evaluates (usage arithmetic, effective-date method choice, deadband in/out, NACHA windows). Do not ask for rule evaluation in triggers.
3. A guard must act, not record; a check narrower than the claim it certifies buys false confidence; test the boundary on both sides.
4. A fact a guard depends on must be written by the database, not an app-writable log.
5. A count/reach guard races concurrent writers: prefer a row-version mutex to a bare lock; state the lock order.
6. A CHECK whose leg can be NULL passes; coalesce the NULL leg (two such leaks were found and fixed before this freeze).
7. Row-level security hides other tenants' rows from tally_app; a "same tenant" check must be positive (visible AND of this tenant), never "no visible row of another tenant" (one such hole was found and fixed before this freeze).

## What to do
1. **Application.** Strict application (`search_path=''`, bodies checked), the `\if` re-run gate, one transaction, superuser under READ COMMITTED. Anything the patch replaces that something else depends on: the two rewritten functions (`populate_reading_calculations`, `enforce_reading_validation_workflow`) against every caller and every path in tu.sql that writes `meter_readings` (void_invoice and its older copies, correction runs, gates); dropped/re-added constraints; revoked grants vs any function or view that UPDATEs those logs.
2. **Reads.** Is every billing-relevant column of a consumed read frozen (compare the column list of `meter_readings` against Block 2)? Can a correction run still re-lock? Can the void carve-out still be abused (the GUC is caller-settable — what can a caller do with it now)? Does removing the consumption fill break anything that expected it?
3. **Rates.** The cycle check (recursion, the `d.id <> NEW.id` exclusion on UPDATE, the visibility/tenant test, the header bump against `enforce_reference_header` and `enforce_rate_schedule_lifecycle`, deadlocks with other header writers). The deadband constraints. The default.
4. **Payments and methods.** Every path a payment's status takes (pending, posted, nsf, reversed, refunded, voided) against the effective-date and return-code CHECKs; the partial unique index's exclusions (can a duplicate posting slip through as a "refund"?); the payment-method supersede chain (cycles, cross-customer, reactivation races, the AFTER trigger's UPDATE re-entering the BEFORE trigger, card expiry updates).
5. **Logs, anomalies, charges, invoices, imports, programs, balance.** Append-only coverage (UPDATE, DELETE, TRUNCATE, as owner and as tally_app/tally_core); created_at stamping and its superuser exemption; anomaly write-once list; the import uniqueness (status values that count as live; preview vs commit; a cancelled job revived); the attestation trigger on every path into `active`; `account_balance_as_of` coordinates and visibility.
6. **Tests.** Is each guard tested by a case only it can refuse? Missing negative cases? Boundaries on both sides? Anything the battery asserts that is false in a way the patch happens to satisfy? Does the race script prove what it says (is B really seen waiting)?
7. Verdict: **ready** / **not yet** (list blocking items). Separate findings: blocking, should-fix, note. Ground every claim in file:line or a reproduction.

## How to probe (Opus and Fable)
Never touch the `tally` or `postgres` databases or the repo files (except your own report file). Make your own clones, prefixed with your name:
```
docker exec tally-pg psql -U tally -d postgres -c "CREATE DATABASE <you>19 TEMPLATE tally"
docker exec tally-pg psql -U tally -d <you>19 -c "REVOKE TEMP ON DATABASE <you>19 FROM PUBLIC, tally_app, tally_core"
(echo "SET search_path = ''; SET check_function_bodies = on;"; cat tests/v5.4.2-19/review/patch-19-frozen-r1.sql) | docker exec -i tally-pg psql -U tally -d <you>19 -v ON_ERROR_STOP=1 -q -f -
docker cp tests/v5.4.2-19/review/battery-19-frozen-r1.sql tally-pg:/tmp/<you>b.sql && docker exec tally-pg psql -U tally -d <you>19 -v ON_ERROR_STOP=1 -q -f /tmp/<you>b.sql
```
`CREATE DATABASE … TEMPLATE` drops the database ACL, hence the REVOKE (tally_app must not hold TEMP). `tally` is the pre-19 base. Write probes as `tally_app` with `SET LOCAL app.user_id` where the guard is about the application; the battery's `pg_temp.refuses(label, sql, sqlstate)` helper shows how. For races, copy `tests/v5.4.2-19/races/cycle-19.sh` and run it against your own throwaway clone. Drop your databases when done.

## Output
Write the full review to `OUTPUT_PATH`. Final reply SHORT (under 2,500 characters): verdict, blocking items (one line each with file:line), top should-fix.
