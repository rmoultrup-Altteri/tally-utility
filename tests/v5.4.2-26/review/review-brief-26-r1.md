# Review brief: v5.4.2-26 r1 — collections decisions and field verification

**Date:** 2026-11-27. **Kind:** patch review, round 1.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's files.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-26/review/patch-26-frozen-r1.sql` | `5d4dd3e54b26131a76e6cfbe68b3566f` |
| `tests/v5.4.2-26/review/battery-26-frozen-r1.sql` | `803c2aaf68585031259cbd824c4d3087` |
| `tests/v5.4.2-26/review/collections-26-frozen-r1.sh` | `e8b3e9aad3c269b5f852c9743e8360b1` |
| `tests/v5.4.2-26/review/mutations-26-frozen-r1.py` | `1342f5e7a20ae1982991154909f2186c` |
| `tests/v5.4.2-26/review/migration-26-frozen-r1.py` | `ccfd94a00976a35c4976394e6d058459` |

The live copies (`sql/v5.4.2-26-collections-decisions.sql` and `tests/v5.4.2-26/`) are identical today.

## Background

-26 was drafted on 2026-10-19 (Ryan: "go ahead with -26") and has never been reviewed. It is the second part of wave 3 (disputes, collections). The base is `tally` (`sql/tu.sql`), which now carries everything before it: -23 (cash), -27, -28, -29, -30 (tax), -24 (unmatched cash, agency pledges) and -25 (disputes, mirrored today). -26 is the only patch in `tests/ci.sh`'s PENDING list.

What it is for:
- **CI-067, CI-069:** a disconnection or other collections act happens only on a recorded decision that the act was allowed, naming every protection and bar the core found active, and every one it could not evaluate (which blocks: fail toward protection).
- **CI-071:** field verification before a disconnection is carried out: what the crew captured against what the database expected, and a supervisor's approval for a mismatch or for no photo evidence (D9-1).
- **CI-075:** a decision re-run on the same facts changes nothing (idempotent).
- **CI-070's link:** the act cites its decision.
- **Hardening:** a bill's dunning stage is moved only by the database from its dunning events; a bill's late fees are its late-fee charges (two old invoice columns go); `customers.do_not_disconnect` is written only from the enrollments.

The rulings, in `gas-billing-memory/application/`: K-CCK (fail toward protection; CCK-7, the grain of a decision's subject), D9-1, D3A-1 (the field tool is external), R-38 attachment 2 (lifting a protection needs a supervisor and evidence), K-07 (no assumed defaults). The design is `application/wave3-build-2026-10-18/v5.4.2-26-design.md` (sections C, E, F, the lock order, "Tests as written" and "Built"); the inventory is `source-inventory-wave3.md` (E, F). Residuals R1–R5 are in the patch header. Read `sql/PATCH-LESSONS.md`'s index and the sections your questions touch.

## What changed around -26 since it was drafted

-26 was written a month ago, before most of what it now sits on. Its tests pass on today's base (results below), but check that its meaning still fits:

- **-25 as mirrored** (`sql/tu.sql`, the banner "MIRROR: PATCH v5.4.2-25"; AC-54 to AC-60): `pending_dispute` no longer protects an account; a dispute's effect is read from `dispute_shelter_as_of` / `dispute_line_shelter_as_of`; -25 has its own trigger on `customer_program_enrollments`, as has -24. -26's `dispute` condition, and `recompute_do_not_disconnect` beside those triggers.
- **-24 as mirrored** (AC-48 to AC-53): the conditions `agency_pledge` and `aged_suspense` are meant to read its rows.
- **-23 and -30:** a bill's money is per line (applications per line, a per-charge late-penalty base, `invoice_line_position_as_of`). -26 makes a late fee an `adhoc_charges` row citing its decision and drops `invoices.late_fee_assessed` and `late_fee_amount`. Does anything mirrored still read them, or assume one late fee per bill?
- **Ryan's rulings since** (`application/DECISION-LOG.md`):
  - 2026-11-22: on the full-amount penalty base, a city may take the penalty **every month** a bill stays unpaid (Pecan Flat does). Can -26 record a second and third late fee on one bill, and what does the dunning stage do then (a bill already past `late_fee_assessed` moved back to it)?
  - 2026-11-22: the silent-city dispute default stops the late fee, the disconnect order and the disconnection, not notices.
  - 2026-11-25: the cut-off checks' settings are required before go-live, and the database's fail-safe (an unevaluable check blocks) stays.
  - 2026-11-05: every link between two utility tables proves both rows are the same utility's (R-12): a two-column key with `tenant_id`.
  - 2026-11-05: a billing run reads every bill at one recorded instant (AC-47).
  - 2026-11-05 / 11-07: Tally staff act in a utility by impersonating it. Does the supervisor approval still mean what F3 says?
- **Kyle's answers** of 2026-11-03 and 11-05 (GBM `kyle-decisions-2026-11-03-scenario-batch-1.md`, `-11-05-scenario-batch-2.md`): a partial payment goes first to amounts that can ground a disconnection (SCN-0031); a meter-error correction can never ground one (F-1).
- **Lessons learned since** (PATCH-LESSONS): `triggers-run-as-every-writer`, `check-passes-null`, `early-return-branches-skip-fences`, `history-stamped-at-xact-start`, `as-of-now-is-not-committed`, `constraint-trigger-name-order`, `race-catch-names-its-damage`, `every-branch-and-stated-default-tested`. Each was found in a later patch; -26 never had them applied.

## Drafting calls to check in particular

- **The decision record** (C3–C5): the subject's shape per act; the bill issued; the location the customer's, a notice's the bill's own; the meter deployed there; the outcome's shape; the vocabulary; an execute decision for its own day; no future date (UTC, R1); one live decision per subject under the subject's advisory lock; a re-run on the same date and fingerprint refused. Is any check narrower than its claim?
- **Acts cite their decision** (A1–A9): exactly the gated acts, an eligible, live (where the act is the record itself), same-subject decision whose window covers the act's date; a log line needs its act's own record. Can an act happen with no decision, a blocked one, a superseded one, or another subject's?
- **The dunning stage** (E2): filled by the database from a fixed mapping; a direct write refused. Is the fence complete (every role, every path to `invoices.dunning_stage`)?
- **`do_not_disconnect`** (E4): a trigger-depth fence (R5). Does it hold with -24's and -25's enrollment triggers beside it?
- **Field visits and approvals** (F1–F4): the expected meter, the serial comparison (`upper(btrim(…))`), one execution per order and per decision, the approvals' kinds and the supervisor check, the order's status fence.
- **Locks** (header, "Lock order and isolation"): the subject's advisory lock, then the bill's or the order's row; READ COMMITTED; retry 40P01. Is any check a read without the lock that orders it?
- **Tenancy:** composite keys with `tenant_id` throughout (R-12); RLS; grants; the one tenant check kept (`collections_tenant_check`).
- **Migration:** the stop conditions, each naming its row.

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`. The second run is skipped by its marker, the table `collections_decisions`.
- **`battery-26.sql`:** 202 checks, one transaction, rolled back.
- **`races/collections-26.sh`:** CR1–CR8, 11 results.
- **`migration-26.py`:** P0–P7.
- **`mutations-26.py`:** 127 of 127 caught, each at its named check as the first failure (re-run 2026-11-27 on today's base).
- **`tests/ci.sh --build`:** 56 steps, all pass, with -26 pending (2026-11-27, at -25's mirror).

## What to answer

1. **Does the patch implement the design and the rulings, including those made since it was drafted (above)?** Name any requirement missed, half-done, or now wrong.
2. **Is there a path around any new rule?** Consider: an act with no decision, or citing a blocked, unevaluable, superseded, expired or other-subject decision; two live decisions; a stage moved without its event; `do_not_disconnect` set by hand; an execution without a match or evidence approval; an approval by a non-supervisor or reused. Try each role (tally_app, tally_core and the owner roles of earlier patches: tally_seal, tally_close, tally_void, tally_dispute), isolation level and statement shape (multi-row, writable CTE, COPY), and a superuser history load.
3. **Earlier patches' properties.** Do -23's, -24's and -25's invariant functions and fences still hold with -26 applied? Does any trigger -26 adds on a mirrored table refuse a path an earlier patch's role takes?
4. **Concurrency.** Is the lock order followed everywhere?
5. **The tests.** Is any check weaker than its label? Does any mutation pass for the wrong reason? What is missing?
6. **Residuals R1–R5.** Is any of them actually blocking?

## How to probe

**Opus and Fable** may query the running `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv26opus`, Fable `rv26fable`):
1. `CREATE DATABASE <name> TEMPLATE tally`.
2. Revoke TEMP on the clone from PUBLIC, `tally_app` and `tally_core` right after creating it.
3. `docker cp` the frozen patch into the container, then apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim must be a probe file in `tests/v5.4.2-26/review/codex-r1-probes/`. Each probe runs as the owner, on a fresh clone with frozen r1 applied, ends in ROLLBACK, and prints SQLSTATE and message for each caught error with RAISE NOTICE (a COPY probe must print its own error). The author will run the probes.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role.
- Do not run `mutations-26.py`; it uses fixed database names. Do not run `tests/ci.sh`.
- Run `collections-26.sh` only against your own clone; it commits rows.
- Never modify `tally`, the `ci_*` databases, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.

**Output:** `tests/v5.4.2-26/review/<you>-r1.md` (opus, fable, codex): verdict "ready" or "not yet"; items B (blocking), S (should fix), N (note), each marked executed or predicted, with the evidence.
