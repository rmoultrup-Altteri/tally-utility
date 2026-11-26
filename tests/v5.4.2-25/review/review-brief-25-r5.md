# Review brief: v5.4.2-25 r5 — disputes, round-4 findings fixed

**Date:** 2026-11-26. **Kind:** patch review, round 5.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's files for this round. Each of you may read your own round-4 review (`opus-r4.md`, `fable-r4.md`, `codex-r4.md`). **Codex:** review the whole patch again, not only the change.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-25/review/patch-25-frozen-r5.sql` | `138f6770f5bf2205a98ff28a3940f68b` |
| `tests/v5.4.2-25/review/battery-25-frozen-r5.sql` | `20b101e9a8deaeacde48f8b352639e34` |
| `tests/v5.4.2-25/review/disputes-25-frozen-r5.sh` | `a5ad8111c4506c1b27c8565ba513ad49` |
| `tests/v5.4.2-25/review/mutations-25-frozen-r5.py` | `5e4713574105fa5900af1201e9d13bad` |
| `tests/v5.4.2-25/review/terms-25-frozen-r5.py` | `83d1484349ef8c3ad654eb40f2264eb6` |
| `tests/v5.4.2-25/review/migration-25-frozen-r5.py` | `55d80759b4066f5a037acc3bd104be20` |
| `tests/v5.4.2-25/review/fill-manifest-25-frozen-r5.py` | `33802a5b696602534f9b1b521981fc5d` |
| `tests/v5.4.2-25/review/dispute_platform_defaults-frozen-r5.yaml` | `deb668299bc3bd44d1eb72a1aeb117d4` |
| `tests/v5.4.2-25/review/dispute_platform_defaults-frozen-r5.seed.sql` | `3832a44f5ae4c788a8451479390906ec` |
| `tests/v5.4.2-25/review/r4-to-r5.diff` | `f27103988ea36cbd005e540f3b67930f` |

The live copies are identical today. `r4-to-r5.diff` is the patch's change since round 4; terms, migration, the manifest filler, the law file and its seed are unchanged since r4.

## Background

The base is `tally` (`sql/tu.sql`), carrying -23, -24, -27, -28, -29 and -30. In `tests/ci.sh`, -25 applies first of the two pending patches, before -26.

Round 4: Codex not yet (one blocking), Opus not yet, Fable not yet; all three on one finding: the combined record replaced a whole section with the law's. The merged plan is `application/wave3-build-2026-10-18/v5.4.2-25-r5-plan.md`: **read all of it**, especially "As built", which records two refinements on the plan (a tariff stage at a place of another decider follows the law's last instead of being dropped; a colliding law stage id is written `law:` and the id instead of failing closed). **One item is Ryan's ruling** (DECISION-LOG, 2026-11-26): where a tariff and a later law cannot be ranked on a start, an end or a must-pay, the combined record keeps both; the core applies the one more protective for the customer; the database checks that the record fits one of them. The rest is settled by standing rule (never looser than the law; fail toward protection).

What r5 changes, in short:
1. **The combination merges inside sections**: subjects what either admits; stages the law's places with the tariff's stage kept where of the same decider (the wider filing window, the quicker decision), then the tariff's other stages.
2. **Looser and not comparable are told apart**: `dispute_tariff_compare_sections` returns each finding's section and verdict; `dispute_tariff_compare` is rebuilt on it. A term not comparable becomes `{"either": [tariff's, law's]}`; the guard admits a component or last day that fits either [D4g, D4t].
3. **Races DR16** (the close first, against the reading's move) **and DR17** (a note edit, then an amount, against a close), each with one 40P01 and a consistent end state.
4. Notes: the lock order as a rule; the combination's comment; the amount lines numbered; `v_pos` removed; residual R9.

## What to check in particular

- Each of your round-4 findings: fixed, with both sides tested? Codex: each of your probes (`codex-r4-probes/`, the author's runs beside them).
- **The merge.** Is the combined record ever looser than either document, in any section or within a list? Are the subjects' union rules right for each pair of kinds? Is the stage merge right when the tariff's stage at a place is of another decider, when ids collide, and for the `final` flag? Does the event guard admit every stage the combined document gives, and only those?
- **The verdicts.** Is every comparator finding classified right (looser only where the law's term protects more for every customer)? Is any pair called looser that depends on the customer?
- **The ruling's checks.** Does [D4g] / [D4t] admit exactly what fits one of the two terms? Can a record fit neither and pass, or fit one and be refused? Is anything else reading a section that may now be `{"either": ...}` (the reader, the event guard, the core's contract)?
- **The lock order rule.** Is any deadlock outside the rule as now stated?
- What round 4 asked, for the whole patch (Codex especially).

## Results so far (reproduce what you can)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`; the second run is skipped by its marker.
- **`battery-25.sql`:** 318 checks (296 + D9a–D9i), one transaction, rolled back.
- **`races/disputes-25.sh`:** DR1–DR17, 30 results. In three back-to-back runs the author saw DR16 and DR17 lose session A each time; one run had DR2 (unchanged since r1) miss its "B seen waiting" poll under load. Report any flake you see.
- **`terms-25.py`:** 0 failures (unchanged).
- **`mutations-25.py`:** 178 mutations; one full run caught 178 of 178, each at its named check.
- **`tests/ci.sh`:** the first r5 run failed one step, the -24 races (unmatched cash; mirrored, untouched by r5), which passed when re-run alone; a second full run is recorded in the plan.

## What to answer

1. Does r5 close every round-4 finding (read your own)? Name any half-done.
2. Is there a path around any new rule? Try each role, isolation level and statement shape, and a superuser history load.
3. Do -17's template and -23's seal properties still hold?
4. Concurrency: is the lock order followed everywhere, and is any check a read without the lock that orders it?
5. Do the invariants catch what they claim?
6. The tests: is any check weaker than its label; does any mutation pass for the wrong reason; what is missing?
7. Residuals R1–R9: is any of them actually blocking?

## How to probe

**Opus and Fable** may query `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv25opus`, Fable `rv25fable`; drop any left from round 4 first): `CREATE DATABASE <name> TEMPLATE tally`; revoke TEMP on it from PUBLIC, `tally_app` and `tally_core` at once; `docker cp` the frozen patch into the container and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

Run the race script on a clone of its own (the battery's fixtures and the races' committed rows collide on one clone).

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim is a probe file in `tests/v5.4.2-25/review/codex-r5-probes/`: run as the owner on a fresh clone with frozen r5 applied, ending in ROLLBACK, printing SQLSTATE and message for each caught error with RAISE NOTICE (a COPY probe prints its own error). A two-session claim is two files with the schedule written at the top. The author will run them.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role (`tally_dispute` exists already; do not touch it).
- Do not run `mutations-25.py` (fixed database name) or `tests/ci.sh`.
- Run `disputes-25.sh` only against your own clone, a separate one from the battery's; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.

**Output:** `tests/v5.4.2-25/review/<you>-r5.md` (opus, fable, codex): verdict "ready" or "not yet"; items B (blocking), S (should fix), N (note), each marked executed or predicted, with the evidence. Keep your final message short; the file is the review.
