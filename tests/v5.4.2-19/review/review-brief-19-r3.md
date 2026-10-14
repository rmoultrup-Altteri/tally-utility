# Review round 3: v5.4.2-19 — hardening batch 1 (close the holes in what is already built)

You are one of three independent reviewers (Opus, Fable, Codex). Round 2 verdicts: Codex ready, Opus ready, Fable not yet (one blocking item). This round checks the r3 fixes.

**Frozen artefacts** (repo `/Users/ryanscomputer/code/tally-utility`; check the hashes and say if they differ):
- patch `tests/v5.4.2-19/review/patch-19-frozen-r3.sql` — md5 `4ef0d4d078acd2b624d3527d2c06703d` (1,519 lines)
- battery `tests/v5.4.2-19/review/battery-19-frozen-r3.sql` — md5 `32ecc5a70c319650a2539a86dd69b93f` (159 checks)
- race script `tests/v5.4.2-19/races/cycle-19.sh` — md5 `91f2817513fc9079fb04648b37f03446` (C1–C7, unchanged since r2)
- CI `tests/ci.sh` — md5 `a5e640c0a0ae45e04a0e21fc04e9bc51` (unchanged since r2)
- round 2: `patch-19-frozen-r2.sql`, `battery-19-frozen-r2.sql`, and the reviews `opus-r2.md`, `fable-r2.md`, `codex-r2.md` in the same folder
- the live schema: `sql/tu.sql` (append-only; the patch is applied on top of it)

State at freeze: strict application twice (second run skipped by the gate), 159/159 battery checks, C1–C7, and the full CI suite (25 steps) pass. Mutation runs, each on a fresh clone: dropping `payments_provider_refund_once` fails P7c; dropping `a_enforce_payment_lineage` fails P9; restoring r1's type-partitioned file index fails J2c; replacing void_invoice()'s balance sum with 0 fails B5.

**What changed since r2** (header "Revision r3" paragraph, and R15–R18):
- **Fable B1 / Opus S4:** `payments_provider_refund_once`, one money-out row (amount < 0) per (tenant, source, processor id). A refund may share its original's id once; a further partial refund carries the processor's own refund id. Zero-amount rows are counted by neither index (R17).
- **Fable S2 / Opus PR3:** `enforce_payment_lineage`, where `refunds_payment_id` and `nsf_original_payment_id` must name a visible payment of the same tenant and customer.
- **Fable S1:** on a read with `billing_period_locked = false`, `locked_at`, `locked_by_billing_run_id` and `locked_by_invoice_id` change only with the move to locked, and `voided_from_invoice_id` never changes.
- **Opus S2:** a finished import job (complete, partial, failed, cancelled) also freezes `source_file_url`, `source_file_size_bytes` and the seven row counts.
- **Opus S3 / Fable S3 / Codex S2 (supersession):** decided as comment plus residual, not a guard. A processor can confirm a charge on the old account after the customer replaced it, so a payment citing an inactive method is a true record. Choosing the account is the core's job (R16). Challenge this if you think it is wrong.
- **Comments:** `account_ledger` table comment rewritten; header CI-055 and CI-118 text corrected; `voided_from_invoice_id` comment states that only the latest void is kept. Codex S3: the lock-order text now says headers before edges, with retry on deadlock or serialization failure.
- **Fable N8:** the three older meter-read triggers are ENABLE ALWAYS.
- **Residuals added:** R15 (a lock without a bill pointer strands the read; contract: the run sets both in one write), R16, R17 (dedup keyed on capture channel; zero amount; pending amount editable), R18 (status on a consumed read moves the next read's "previous"; field-reader confirmation and quality_flag frozen).
- **Battery:** new helper `pg_temp.refuses_at(label, sql, sqlstate, guard)`, which requires the named constraint or message fragment. New cases: RL1–4, Q4i, P7c–e, P9/P9b, J2c (isolated), J10/J10b, L7c (a different citation), B5.

**Standing rules** are as in round 2 (`review-brief-19-r2.md`).

## What to do
1. **Round-2 closure.** For every blocking and should-fix item in the three r2 reviews: closed / not closed / accepted as a residual, with the r3 line or a reproduction. Where r3 chose a residual over a guard, say whether you agree.
2. **New code.** The refund index, against legitimate flows: two partial refunds; a refund of an NSF'd payment; a reversal and a refund of one payment. The lineage trigger: UPDATE paths; the composite of `UPDATE OF` columns; RLS; superuser. The unconsumed-read lock-record fence: does any legitimate path in tu.sql write those columns on an unconsumed read (billing runs, gates, void_invoice and its older copies, correction flows)? Does it interact badly with Block 1's stamping? The import freeze: does any legitimate path update a finished job's counts or URL? Do the ENABLE ALWAYS changes affect anything?
3. **Tests.** Does each new case fail without its guard? Is anything true only by accident?
4. Verdict: **ready** / **not yet** (list blocking items). Separate findings: blocking, should-fix, note. Ground every claim in file:line or a reproduction.

## How to probe (Opus and Fable)
Never touch the `tally` or `postgres` databases or the repo files (except your own report file). Make your own clones, prefixed with your name:
```
docker exec tally-pg psql -U tally -d postgres -c "CREATE DATABASE <you>19 TEMPLATE tally"
docker exec tally-pg psql -U tally -d <you>19 -c "REVOKE TEMP ON DATABASE <you>19 FROM PUBLIC, tally_app, tally_core"
(echo "SET search_path = ''; SET check_function_bodies = on;"; cat tests/v5.4.2-19/review/patch-19-frozen-r3.sql) | docker exec -i tally-pg psql -U tally -d <you>19 -v ON_ERROR_STOP=1 -q -f -
docker cp tests/v5.4.2-19/review/battery-19-frozen-r3.sql tally-pg:/tmp/<you>b.sql && docker exec tally-pg psql -U tally -d <you>19 -v ON_ERROR_STOP=1 -q -f /tmp/<you>b.sql
```
`CREATE DATABASE … TEMPLATE` drops the database ACL, hence the REVOKE. Write probes as `tally_app` with `SET LOCAL app.user_id`. Drop your databases when done.

## Output
Write the full review to `OUTPUT_PATH`. Final reply SHORT (under 2,500 characters): verdict, blocking items (one line each with file:line), top should-fix.
