# Review brief: v5.4.2-25 r3 — disputes, round-2 findings fixed

**Date:** 2026-11-25. **Kind:** patch review, round 3.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's files for this round. Each of you may read your own round-2 review (`opus-r2.md`, `fable-r2.md`, `codex-r2.md`). **Codex:** review the whole patch again, not only the change.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-25/review/patch-25-frozen-r3.sql` | `9d2d3ed70656f1931df9e50c9b7b5ee6` |
| `tests/v5.4.2-25/review/battery-25-frozen-r3.sql` | `18fde97b141515e1b17059df9a690c45` |
| `tests/v5.4.2-25/review/disputes-25-frozen-r3.sh` | `0c13f9099548d3ae24b14ec21074f987` |
| `tests/v5.4.2-25/review/mutations-25-frozen-r3.py` | `99dbb3b568a9fff40d209644470bd7ad` |
| `tests/v5.4.2-25/review/terms-25-frozen-r3.py` | `83d1484349ef8c3ad654eb40f2264eb6` |
| `tests/v5.4.2-25/review/migration-25-frozen-r3.py` | `55d80759b4066f5a037acc3bd104be20` |
| `tests/v5.4.2-25/review/fill-manifest-25-frozen-r3.py` | `2fe45983fc37c0973be9d420ae31ef20` |
| `tests/v5.4.2-25/review/dispute_platform_defaults-frozen-r3.yaml` | `deb668299bc3bd44d1eb72a1aeb117d4` |
| `tests/v5.4.2-25/review/dispute_platform_defaults-frozen-r3.seed.sql` | `3832a44f5ae4c788a8451479390906ec` |
| `tests/v5.4.2-25/review/r2-to-r3.diff` | `fd6232e47e5a76bc9dfa5540215bc570` |

The live copies are identical today. `r2-to-r3.diff` is the patch's change since round 2; terms, migration, the law file and its seed are unchanged since r2.

## Background

The base is `tally` (`sql/tu.sql`), carrying -23, -24, -27, -28, -29 and -30. In `tests/ci.sh`, -25 applies first of the two pending patches, before -26.

Round 2: Codex not yet (two blocking, two should-fix), Opus not yet (two should-fix), Fable ready (two should-fix). The merged plan is `application/wave3-build-2026-10-18/v5.4.2-25-r3-plan.md`: **read all of it**, including "As built" and "Not changed". Every item is settled by a standing rule (never looser than the law; fail toward protection). The earlier plan is `v5.4.2-25-r2-plan.md`; the design `v5.4.2-25-design.md`; rulings in `application/DECISION-LOG.md` and GBM `application/`.

What r3 changes, in short:
1. **Nothing after the resolution:** the row-id exclusion is gone (a row carrying a closing event's id escaped); amount lines are numbered (`record_seq`) and guarded through their amount's dispute.
2. **Two closes of one reading:** the commit-time release check locks the reading's row before it counts the open disputes (race DR13). A close against the reading's own move may deadlock; the loser retries (40P01).
3. **A law tightened after a tariff:** the tariff must be cited only while it compares no looser than the cited law row; a looser tariff is refused [D4r] and the law is cited alone.
4. **Stages:** the comparator matches the law's stages in order, with filing and decision windows compared toward the customer.
5. **The record sequence's grants** are pinned by the guard invariant.
6. **D4f** has a real foreign tariff (D4f2, the owner's view).
7. **Fable N3:** an end date under a policy ended by resolution is refused [D4s].

## What to check in particular

- Each of your round-2 findings: is it fixed, with both sides tested? Codex: each of your probes 00–06 (`codex-r2-probes/`, with the author's runs beside them).
- **The reading lock (item 2).** Is the lock order in the header followed everywhere, and is the deadlock it admits the only one? Is a reading lock taken where none was before a hazard (a lock against `meter_readings` writers outside -25)?
- **D4q/D4r.** Can a determination now cite the law alone where the tariff is no looser, or the tariff where it is looser? Is the comparison made against the law row actually cited, under its lock?
- **The stage comparator.** Is each `none` compared in the protective direction? Can a law stage be matched twice, or out of order?
- **Lines and the close guard.** Any statement shape (multi-row, writable CTE, COPY) that adds a line, amount, determination or event after a resolution?
- What round 2 asked, for the whole patch (Codex especially).

## Results so far (reproduce what you can)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`; the second run is skipped by its marker.
- **`battery-25.sql`:** 286 checks, one transaction, rolled back.
- **`races/disputes-25.sh`:** DR1–DR13, 18 results.
- **`terms-25.py`:** 0 failures. `lawc.py check`: valid; the default's seed is what its law file emits, embedded verbatim.
- **`mutations-25.py`:** 153 mutations; one full run caught 153 of 153, each at its named check.
- **`tests/ci.sh`:** 59 steps, all pass (2026-11-25, r3).

## What to answer

1. Does r3 close every round-2 finding (read your own)? Name any half-done.
2. Is there a path around any new rule? Try each role, isolation level and statement shape, and a superuser history load.
3. Do -17's template and -23's seal properties still hold?
4. Concurrency: is the lock order followed everywhere, and is any check a read without the lock that orders it?
5. Do the invariants catch what they claim?
6. The tests: is any check weaker than its label; does any mutation pass for the wrong reason; what is missing?
7. Residuals R1–R8: is any of them actually blocking?

## How to probe

**Opus and Fable** may query `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv25opus`, Fable `rv25fable`; drop any left from round 2 first): `CREATE DATABASE <name> TEMPLATE tally`; revoke TEMP on it from PUBLIC, `tally_app` and `tally_core` at once; `docker cp` the frozen patch into the container and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim is a probe file in `tests/v5.4.2-25/review/codex-r3-probes/`: run as the owner on a fresh clone with frozen r3 applied, ending in ROLLBACK, printing SQLSTATE and message for each caught error with RAISE NOTICE (a COPY probe prints its own error). A two-session claim is two files with the schedule written at the top. The author will run them.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role (`tally_dispute` exists already; do not touch it).
- Do not run `mutations-25.py` (fixed database name) or `tests/ci.sh`.
- Run `disputes-25.sh` only against your own clone; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.

**Output:** `tests/v5.4.2-25/review/<you>-r3.md` (opus, fable, codex): verdict "ready" or "not yet"; items B (blocking), S (should fix), N (note), each marked executed or predicted, with the evidence.
