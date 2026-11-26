# Review brief: v5.4.2-25 r4 — disputes, round-3 findings fixed

**Date:** 2026-11-25. **Kind:** patch review, round 4.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's files for this round. Each of you may read your own round-3 review (`opus-r3.md`, `fable-r3.md`, `codex-r3.md`). **Codex:** review the whole patch again, not only the change.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-25/review/patch-25-frozen-r4.sql` | `dc738d922cf27c9847347a507c055475` |
| `tests/v5.4.2-25/review/battery-25-frozen-r4.sql` | `557604c32211183f4ac5e07fb8f7b351` |
| `tests/v5.4.2-25/review/disputes-25-frozen-r4.sh` | `cd393cfdb86854f449c42e8c43e5901c` |
| `tests/v5.4.2-25/review/mutations-25-frozen-r4.py` | `3243d0b52ea7742348d1bbcc74358dd4` |
| `tests/v5.4.2-25/review/terms-25-frozen-r4.py` | `83d1484349ef8c3ad654eb40f2264eb6` |
| `tests/v5.4.2-25/review/migration-25-frozen-r4.py` | `55d80759b4066f5a037acc3bd104be20` |
| `tests/v5.4.2-25/review/fill-manifest-25-frozen-r4.py` | `33802a5b696602534f9b1b521981fc5d` |
| `tests/v5.4.2-25/review/dispute_platform_defaults-frozen-r4.yaml` | `deb668299bc3bd44d1eb72a1aeb117d4` |
| `tests/v5.4.2-25/review/dispute_platform_defaults-frozen-r4.seed.sql` | `3832a44f5ae4c788a8451479390906ec` |
| `tests/v5.4.2-25/review/r3-to-r4.diff` | `9102047af72d253fa022cd837432ba0c` |

The live copies are identical today. `r3-to-r4.diff` is the patch's change since round 3; terms, migration, the law file and its seed are unchanged since r2.

## Background

The base is `tally` (`sql/tu.sql`), carrying -23, -24, -27, -28, -29 and -30. In `tests/ci.sh`, -25 applies first of the two pending patches, before -26.

Round 3: Codex not yet, Opus not yet, Fable ready; none blocking. The merged plan is `application/wave3-build-2026-10-18/v5.4.2-25-r4-plan.md`: **read all of it**, especially "As built", which records one change from the plan (item 3: a policy stage after the law's last is admitted, final or not, with the reason). Every item is settled by a standing rule (never looser than the law; fail toward protection; not comparable is refused). The earlier plans are `v5.4.2-25-r3-plan.md` and `-r2-plan.md`; the design `v5.4.2-25-design.md`; rulings in `application/DECISION-LOG.md` and GBM `application/`.

What r4 changes, in short:
1. **The reading lock** is `FOR NO KEY UPDATE` (all three, round 3): it no longer conflicts with the key-share lock of a row that references the reading. The header names the two deadlocks admitted. Races DR13c, DR14, DR15, DR15b.
2. **A tariff looser in part than the law** (Opus S1): cited with the law, and the record checked against the two combined (`dispute_terms_combined`: each section the tariff's where no looser, the law's where looser; both documents' blocks and duties). The law alone is never cited while a policy is in force [D4q].
3. **Stages** (Opus S3, Fable S2): the law's stages are the tariff's first, in order, with nothing between. A stage of the tariff's own only after the law's last.
4. **D4f** has a real hidden tariff, and separate tests for another state, service and system (Codex S2).
5. Notes: comments, the owner and the record sequence's settings pinned.

## What to check in particular

- Each of your round-3 findings: fixed, with both sides tested? Codex: each of your probes (`codex-r3-probes/`, the author's runs beside them).
- **The combined record.** Is the combination ever looser than either document for any section? Does it rely on the comparator's message prefixes correctly, for every section the comparator can name? Is `dispute_tariff_compare` granted to `tally_core` safe? Is the stage check of events right under the combined document?
- **The decision against Opus N2** (a stage after the law's final one is admitted). Is it wrong by a standing rule?
- **The lighter lock.** Does it still serialise everything r3 needed? Is any deadlock beyond the two named?
- What round 3 asked, for the whole patch (Codex especially).

## Results so far (reproduce what you can)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`; the second run is skipped by its marker.
- **`battery-25.sql`:** 296 checks, one transaction, rolled back.
- **`races/disputes-25.sh`:** DR1–DR15, 26 results.
- **`terms-25.py`:** 0 failures (unchanged since r2).
- **`mutations-25.py`:** 161 mutations; one full run caught 161 of 161, each at its named check.
- **`tests/ci.sh`:** 59 steps, all pass (2026-11-25, r4).

## What to answer

1. Does r4 close every round-3 finding (read your own)? Name any half-done.
2. Is there a path around any new rule? Try each role, isolation level and statement shape, and a superuser history load.
3. Do -17's template and -23's seal properties still hold?
4. Concurrency: is the lock order followed everywhere, and is any check a read without the lock that orders it?
5. Do the invariants catch what they claim?
6. The tests: is any check weaker than its label; does any mutation pass for the wrong reason; what is missing?
7. Residuals R1–R8: is any of them actually blocking?

## How to probe

**Opus and Fable** may query `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv25opus`, Fable `rv25fable`; drop any left from round 3 first): `CREATE DATABASE <name> TEMPLATE tally`; revoke TEMP on it from PUBLIC, `tally_app` and `tally_core` at once; `docker cp` the frozen patch into the container and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim is a probe file in `tests/v5.4.2-25/review/codex-r4-probes/`: run as the owner on a fresh clone with frozen r4 applied, ending in ROLLBACK, printing SQLSTATE and message for each caught error with RAISE NOTICE (a COPY probe prints its own error). A two-session claim is two files with the schedule written at the top. The author will run them.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role (`tally_dispute` exists already; do not touch it).
- Do not run `mutations-25.py` (fixed database name) or `tests/ci.sh`.
- Run `disputes-25.sh` only against your own clone, a separate one from the battery's; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.

**Output:** `tests/v5.4.2-25/review/<you>-r4.md` (opus, fable, codex): verdict "ready" or "not yet"; items B (blocking), S (should fix), N (note), each marked executed or predicted, with the evidence.
