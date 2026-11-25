# Review brief: v5.4.2-25 r2 — disputes, with the platform default and the status-move role

**Date:** 2026-11-25. **Kind:** patch review, round 2.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's files for this round. Opus and Fable may read their own round-1 reviews (`opus-r1.md`, `fable-r1.md`). **Codex has not reviewed -25 before:** review the whole patch, not only the change.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-25/review/patch-25-frozen-r2.sql` | `edf445bbdae2e1246f1f4ccd38464da5` |
| `tests/v5.4.2-25/review/battery-25-frozen-r2.sql` | `50f48c07e45fb95905f365075e5df862` |
| `tests/v5.4.2-25/review/disputes-25-frozen-r2.sh` | `9fb24be54e778203d23023c7fe8570f9` |
| `tests/v5.4.2-25/review/mutations-25-frozen-r2.py` | `1a6213269fc9e8b38afb8d871721771a` |
| `tests/v5.4.2-25/review/terms-25-frozen-r2.py` | `83d1484349ef8c3ad654eb40f2264eb6` |
| `tests/v5.4.2-25/review/migration-25-frozen-r2.py` | `55d80759b4066f5a037acc3bd104be20` |
| `tests/v5.4.2-25/review/fill-manifest-25-frozen-r2.py` | `e0664cca97f532fa4e62ae33e5824190` |
| `tests/v5.4.2-25/review/dispute_platform_defaults-frozen-r2.yaml` | `deb668299bc3bd44d1eb72a1aeb117d4` |
| `tests/v5.4.2-25/review/dispute_platform_defaults-frozen-r2.seed.sql` | `3832a44f5ae4c788a8451479390906ec` |
| `tests/v5.4.2-25/review/r1-to-r2.diff` | `46289b5a1048074a4c2d33a5a5641108` |

The live copies are identical today. `r1-to-r2.diff` is the patch's change since round 1.

## Background

The base is `tally` (`sql/tu.sql`), which now carries -23 (cash), -24 (unmatched cash and pledges, mirrored 2026-11-24), -27, -28, -29 and -30. In `tests/ci.sh`, -25 applies first of the two pending patches, before -26.

Round 1: Opus and Fable both said not yet, with the same blocker. The merged plan is `application/wave3-build-2026-10-18/v5.4.2-25-r2-plan.md`: items 1–8 are settled by standing rule; item 9 is Ryan's ruling of 2026-11-22. **Read its sections "Item 9 design", "Item 9 as built" and "Item 8's status-move role".** The original design is `v5.4.2-25-design.md`; the rulings are in `application/DECISION-LOG.md` (the 2026-11-22 entries tagged money, -25, and the scenarios entries of that day) and GBM `application/`.

What -25 is for: CI-074 (a disputed amount is sheltered from collection while the dispute runs, by the rule that governs it) and CI-054's dispute side (no late fee on a disputed amount).

What r2 changes, in short:
1. **Items 1–7** (round-1 findings): "nothing after the resolution" judged from the events in one statement; never-looser compares duties and stages; a counted shelter end is required and capped; a determination cites the utility's tariff where the law governs; an amount is capped at the bill's positive charges; a reading leaves `disputed` when its last dispute closes; two-column tenant keys.
2. **Item 8:** `assert_dispute_guard_invariants()`, exact lists generated from a build (`fill-manifest.py`); and the status move owned by a new role, `tally_dispute` (the seal pattern, `sql/PATCH-LESSONS.md` `seal-pattern-owner-roles`). -25 carries `assert_seal_role_invariants()` forward from -23 with that role added; its body differs from `tu.sql`'s only by four edits.
3. **Item 9, the platform default** (Ryan 2026-11-22): `dispute_platform_defaults`, a law-template table holding the platform's default for a city-owned system with no dispute policy of its own (law file `law/dispute/dispute_platform_defaults.yaml`). A determination under a delegation with no tariff in force cites the default in force for the profile, class and received date (`platform_default_id`); "no terms" only when neither is in force; a city's own tariff replaces it from the tariff's date.

## What to check in particular

- **The default's citation rule** (D4d, D4e, D7a, D7b, D7k, D4n). Can a determination cite a default where it should not, fail to cite it where it must, cite the wrong class's or a closed one, or cite it beside a tariff? Is the lookup under the right lock? Does the close floor hold a cited default open?
- **The default's table.** Its insert check (governs law, no unruled section, the documents' own checks, the class). Does the template treat a second law table of the kind `dispute` correctly (registration, the no-overlap exclusion, `rule_law_row_as_of`, `rule_law_row_cite`, the template's invariant)? The comparator does not read it, on purpose: a city's own policy may be narrower than the default.
- **The calls settled by rule while building** (plan, "Item 9 as built"): the default in force from 2026-11-22; a dispute received on the due date counts as before delinquency (residual R8); a back-dated policy over a determined dispute admitted (residual R6, races DR11). Is any of them wrong by a standing rule?
- **The status-move role.** Its grants are exact. Can the move be made, or a status written, any other way? RLS applies to the move (races DR12): is that right, and what must a history load do?
- **The carried seal invariant.** Is anything of -23's lost or loosened?
- **Items 1–8** as round 1 asked: is each fixed, both sides of each boundary tested?

## Results so far (reproduce what you can)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`; the second run is skipped by its marker.
- **`battery-25.sql`:** 271 checks, one transaction, rolled back.
- **`races/disputes-25.sh`:** DR1–DR12, 16 results.
- **`terms-25.py`:** 0 failures. `lawc.py check` on every law file: valid; the default's seed is what its law file emits, embedded verbatim.
- **`mutations-25.py`:** 141 mutations; one full run caught 140, the one miss (M48) a race timing flake in an earlier race check (DR1 not seen waiting under load), caught at its own check when run alone.
- **`tests/ci.sh`:** 59 steps, all pass (2026-11-25, r2, on `tally` carrying -24 and -30; -25 and -26 pending).

## What to answer

1. Does r2 close every round-1 finding (Opus and Fable: read your own), and does item 9 implement Ryan's rulings of 2026-11-22? Name any requirement missed or half-done.
2. Is there a path around any new rule? Try each role, isolation level and statement shape (multi-row, writable CTE, COPY), and a superuser history load.
3. Do -17's template and -23's seal properties still hold?
4. Concurrency: is the lock order followed everywhere, and is any check a read without the lock that orders it?
5. Do the invariants catch what they claim?
6. The tests: is any check weaker than its label; does any mutation pass for the wrong reason; what is missing?
7. Residuals R1–R8: is any of them actually blocking?

## How to probe

**Opus and Fable** may query `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv25opus`, Fable `rv25fable`): `CREATE DATABASE <name> TEMPLATE tally`; revoke TEMP on it from PUBLIC, `tally_app` and `tally_core` at once; `docker cp` the frozen patch into the container and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim is a probe file in `tests/v5.4.2-25/review/codex-r2-probes/`: run as the owner on a fresh clone with frozen r2 applied, ending in ROLLBACK, printing SQLSTATE and message for each caught error with RAISE NOTICE (a COPY probe prints its own error). The author will run them.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role (`tally_dispute` exists already; do not touch it).
- Do not run `mutations-25.py` (fixed database name) or `tests/ci.sh`.
- Run `disputes-25.sh` only against your own clone; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.

**Output:** `tests/v5.4.2-25/review/<you>-r2.md` (opus, fable, codex): verdict "ready" or "not yet"; items B (blocking), S (should fix), N (note), each marked executed or predicted, with the evidence.
