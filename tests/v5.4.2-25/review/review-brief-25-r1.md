# Review brief: v5.4.2-25 r1 — disputes, and the dispute rule family

**Date:** 2026-11-07. **Kind:** patch review, round 1.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's files.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-25/review/patch-25-frozen-r1.sql` | `6fe776110440022976c6405947b9be5f` |
| `tests/v5.4.2-25/review/battery-25-frozen-r1.sql` | `58a94b366974e9689aeb537f419be325` |
| `tests/v5.4.2-25/review/disputes-25-frozen-r1.sh` | `5f019c70483af460e240b18a910b29c1` |
| `tests/v5.4.2-25/review/mutations-25-frozen-r1.py` | `8a7f860acf66a02595cd2a5e2982fa83` |
| `tests/v5.4.2-25/review/terms-25-frozen-r1.py` | `83d1484349ef8c3ad654eb40f2264eb6` |
| `tests/v5.4.2-25/review/migration-25-frozen-r1.py` | `55d80759b4066f5a037acc3bd104be20` |

The live copies (`sql/v5.4.2-25-disputes.sql` and `tests/v5.4.2-25/`) are identical today.

## Background

-25 was drafted on 2026-10-18 and has not been reviewed. It is the first part of wave 3 (disputes, collections). The base is `tally` (`sql/tu.sql`): -23 (cash), -27, -28 and -29 are mirrored. In `tests/ci.sh`, -25 applies first of the pending patches, before -26, -30 and -24.

What it is for:
- **CI-074:** a disputed amount is sheltered from collection while the dispute runs, by the rule that governs it.
- **CI-054 (the dispute side):** no late fee on a disputed amount.

The rulings, in `gas-billing-memory/application/`:
- **Ryan, 2026-10-18** (wave-3 Q1): dispute policies are rule-terms rows, one law table and one tariff table.
- **K-07:** a city's rules are per utility, with no default.
- **K-CCK:** fail toward protection.
- **K-A2:** the §7.45(6)(D)(ii) shelter.
- **R-05:** add-only.

The design is `application/wave3-build-2026-10-18/v5.4.2-25-design.md`. Its "Built" section lists what the build settled by rule. The inventory is `source-inventory-wave3.md` (D, Q1), and the law sources are in `sources/law-sources.md`. Residuals R1–R7 are in the patch header. -17's rule-terms template is the base for both rule tables (read `sql/PATCH-LESSONS.md`, `rule-table-fixture-notes` and `rule-table-keys-are-text-codes`).

Since the draft, Kyle's answers of 2026-11-03 and 11-05 (GBM `kyle-decisions-2026-11-03-scenario-batch-1.md`, `-11-05-scenario-batch-2.md`) say no penalty is assessed while a bill's dispute is open. Check that -25's record carries what the core needs for that.

## Drafting calls to check in particular

- **Never looser than the law** (L6). A tariff is compared with the law row in force when it is written: subjects, shelter, must-pay, end, stages, blocks and duties. `within_days` is compared only against its own kind. Is any comparison a way to write a looser tariff?
- **The determination's checks** (D4a–D4n). The law row is in force for the utility, class and received date. The tariff is the utility's own and in force. A delegation shelters only under a tariff. "No terms" only when none is in force. The outcome shapes, component, blocks and amounts. One live row per dispute; none after the resolution. Is any check narrower than its claim?
- **The status move** (R7): a SECURITY DEFINER trigger moves the dispute's status from its resolution or withdrawal event. Can it be reached any other way?
- **The readers.** Each takes both coordinates. The shelter ends on its last day, inclusive, or at the resolution. With no lines, the reading is pro rata. Are the boundaries right on both sides?
- **The meaning changes** T1 (`pending_dispute`) and T2 (the six reading columns dropped; status `disputed` needs an open dispute), and the precondition that names a row.
- **Locks.** A dispute's advisory lock first, then the cited rule rows shared. A reading's move takes every naming dispute's lock in id order. READ COMMITTED. Deadlock and retry.
- **Tenancy.** Every key between tenant tables carries `tenant_id` (R-12, board 2026-11-05). RLS, grants.

## Results so far (reproduce them)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`. The second run is skipped by its marker, the table `disputes`.
- **`battery-25.sql`:** 201 checks, one transaction, rolled back.
- **`races/disputes-25.sh`:** DR1–DR9, 12 results.
- **`terms-25.py`:** the law documents and fixtures, 0 failures.
- **`migration-25.py`:** P0–P4.
- **`mutations-25.py`:** 110 of 110 caught, each at its named check as the first failure.
- **`tests/ci.sh`:** 62 steps, all pass, with -25, -26, -30 and -24 pending.

## What to answer

1. **Does the patch implement the design, the rulings and Kyle's later answers on disputes?** Name any requirement missed or half-done.
2. **Is there a path around any new rule?** Consider:
   - a tariff looser than the law;
   - a determination citing the wrong row, tenant, class or date;
   - a second live determination;
   - a determination or amount after the resolution;
   - a status moved without its event;
   - a reading marked disputed with no dispute, or left disputed after it;
   - a line amount past its charge, or summing wrong.

   Try each role, isolation level and statement shape (multi-row, writable CTE, COPY), and a superuser history load.
3. **-17's and -23's properties.** Do the rule template's checks still hold for both tables? Does T2's re-created reading function differ from its predecessor beyond the change?
4. **Concurrency.** Is the lock order followed everywhere? Is any check a read without the lock that orders it?
5. **The invariants.** Do the invariant functions -25 adds or extends catch what they claim?
6. **The tests.** Is any check weaker than its label? Does any mutation pass for the wrong reason? What is missing?
7. **Residuals R1–R7.** Is any of them actually blocking?

## How to probe

**Opus and Fable** may query the running `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv25opus`, Fable `rv25fable`):
1. `CREATE DATABASE <name> TEMPLATE tally`.
2. Revoke TEMP on the clone from PUBLIC, `tally_app` and `tally_core` right after creating it.
3. `docker cp` the frozen patch into the container, then apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim must be a probe file in `tests/v5.4.2-25/review/codex-r1-probes/`. Each probe runs as the owner, on a fresh clone with frozen r1 applied, ends in ROLLBACK, and prints SQLSTATE and message for each caught error with RAISE NOTICE (a COPY probe must print its own error). The author will run the probes.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role.
- Do not run `mutations-25.py`; it uses a fixed database name. Do not run `tests/ci.sh`.
- Run `disputes-25.sh` only against your own clone; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.

**Output:** `tests/v5.4.2-25/review/<you>-r1.md` (opus, fable, codex): verdict "ready" or "not yet"; items B (blocking), S (should fix), N (note), each marked executed or predicted, with the evidence.
