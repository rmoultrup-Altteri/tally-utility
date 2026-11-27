# Review brief: v5.4.2-25 r7 — disputes, round-6 findings fixed

**Date:** 2026-11-26. **Kind:** patch review, round 7.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's files for this round. Each of you may read your own round-6 review (`opus-r6.md`, `fable-r6.md`, `codex-r6.md`). **Codex:** review the whole patch again, not only the change.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-25/review/patch-25-frozen-r7.sql` | `a2646d043c09bca6beb3606623977ad4` |
| `tests/v5.4.2-25/review/battery-25-frozen-r7.sql` | `3255b77046b53f183b90b359df61edcf` |
| `tests/v5.4.2-25/review/disputes-25-frozen-r7.sh` | `ba77a03997a856bd00d90d3c0e7fcb88` |
| `tests/v5.4.2-25/review/mutations-25-frozen-r7.py` | `68ee1252a020b63f67c522e05c120eeb` |
| `tests/v5.4.2-25/review/terms-25-frozen-r7.py` | `83d1484349ef8c3ad654eb40f2264eb6` |
| `tests/v5.4.2-25/review/migration-25-frozen-r7.py` | `55d80759b4066f5a037acc3bd104be20` |
| `tests/v5.4.2-25/review/fill-manifest-25-frozen-r7.py` | `33802a5b696602534f9b1b521981fc5d` |
| `tests/v5.4.2-25/review/dispute_platform_defaults-frozen-r7.yaml` | `deb668299bc3bd44d1eb72a1aeb117d4` |
| `tests/v5.4.2-25/review/dispute_platform_defaults-frozen-r7.seed.sql` | `3832a44f5ae4c788a8451479390906ec` |
| `tests/v5.4.2-25/review/r6-to-r7.diff` | `8a597274f2b2f05c06d98fcdcd05c348` |

The live copies are identical today. `r6-to-r7.diff` is the patch's change since round 6 (125 lines). The races, terms, migration, the manifest filler, the law file and its seed are unchanged since r6.

## Background

The base is `tally` (`sql/tu.sql`), carrying -23, -24, -27, -28, -29 and -30. In `tests/ci.sh`, -25 applies first of the two pending patches, before -26.

Round 6: Opus ready; Codex ready (two should-fix); Fable not yet (one should-fix in the comparator, one in the tests). The merged plan is `application/wave3-build-2026-10-18/v5.4.2-25-r7-plan.md`: **read all of it**, especially "As built" and "Tests (r7)". Ryan's ruling of 2026-11-26 (DECISION-LOG) stands unchanged. Every r7 item is settled by standing rule (never looser than the law; fail toward protection; the comparator's stated ordering applied consistently).

What r7 changes, in short:
1. **A withholding cap of 1 or more ranks against an average-usage cap as undisputed charges does**, both directions; below 1 stays not comparable (Fable S1). N5c flips to admitted.
2. **Prose:** `dispute_tariff_compare`'s comment rewritten whole; the sections comment; the release function's comment states the header's lock rule; design L6 (Codex S1, Opus N3, Fable N8).
3. **Assertions that accept NULL** fixed in D8j, D9a; D9j compares the whole stage list (Codex S2).
4. **The unruled end on the real path:** D4y2, D4y3 under 7.45(1) (Opus N1, Fable S2).
5. Notes: the law's final flag pinned either way (D9u) and residual R10; the `any_time` premise; the fail-closed branch's comment; D9s's label.

## What to check in particular

- Each of your round-6 findings: fixed, with both sides tested? Codex: each of your probes (`codex-r6-probes/`, the author's runs beside them).
- **The must-pay ordering, whole.** Take every pair of unruled, full_bill, undisputed_charges, withhold_cap (below, at and above 1) and average_usage_cap (equal and unequal figures), both directions. Is each verdict right: looser only where the law's term protects more for every customer, not comparable where it depends on the customer? Is the ordering now consistent (no pair A ≤ B, B ≤ C with A against C refused or reversed)?
- **The premise.** Is "a withholding of at least the disputed amount asks no more than an average-usage cap" true for every customer under 7.45(6)(D)? Is any customer worse off?
- **R10.** Is the residual stated rightly, and is it the only direction in which the law's final flag can disadvantage a customer?
- **The new tests.** Is any check weaker than its label (NULL, a wrong fixture, a check that passes for another reason)?
- What earlier rounds asked, for the whole patch (Codex especially).

## Results so far (reproduce what you can)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`; the second run is skipped by its marker.
- **`battery-25.sql`:** 351 checks (342 + N5d, N5e, D9t–D9t4, D9u, D4y2, D4y3; N5c flipped), one transaction, rolled back. Against frozen r6 it fails first at N5c.
- **`races/disputes-25.sh`:** unchanged; 30 of 30 inside `ci.sh`.
- **`mutations-25.py`:** 199 mutations (193 + M188–M193; M157 re-anchored). One full run caught 198 at their named checks; M17 was caught at N5c, one check before its old name (N5c now admits a policy, and M17's comparator refuses it against the unprotected row's unruled start). It was retargeted and caught there when re-run alone.
- **`tests/ci.sh`:** 59 of 59 on the first run.

## What to answer

1. Does r7 close every round-6 finding (read your own)? Name any half-done.
2. Is there a path around any rule, new or old? Try each role, isolation level and statement shape, and a superuser history load.
3. Do -17's template and -23's seal properties still hold?
4. Concurrency: is the lock order followed everywhere, and is any check a read without the lock that orders it?
5. Do the invariants catch what they claim?
6. The tests: is any check weaker than its label; does any mutation pass for the wrong reason; what is missing?
7. Residuals R1–R10: is any of them actually blocking?

## How to probe

**Opus and Fable** may query `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv25opus`, Fable `rv25fable`; drop any left from round 6 first): `CREATE DATABASE <name> TEMPLATE tally`; revoke TEMP on it from PUBLIC, `tally_app` and `tally_core` at once; `docker cp` the frozen patch into the container and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

Run the race script on a clone of its own (the battery's fixtures and the races' committed rows collide on one clone).

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim is a probe file in `tests/v5.4.2-25/review/codex-r7-probes/`: run as the owner on a fresh clone with frozen r7 applied, ending in ROLLBACK, printing SQLSTATE and message for each caught error with RAISE NOTICE (a COPY probe prints its own error). A two-session claim is two files with the schedule written at the top. The author will run them.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role (`tally_dispute` exists already; do not touch it).
- Do not run `mutations-25.py` (fixed database name) or `tests/ci.sh`.
- Run `disputes-25.sh` only against your own clone, a separate one from the battery's; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.

**Output:** `tests/v5.4.2-25/review/<you>-r7.md` (opus, fable, codex): verdict "ready" or "not yet"; items B (blocking), S (should fix), N (note), each marked executed or predicted, with the evidence. Keep your final message short; the file is the review.
