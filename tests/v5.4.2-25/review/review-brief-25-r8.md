# Review brief: v5.4.2-25 r8 — round-7 wording, diff only

**Date:** 2026-11-27. **Kind:** patch review, round 8 (a short check of the change).
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's files for this round. Each of you may read your own round-7 review (`opus-r7.md`, `fable-r7.md`, `codex-r7.md`).

## Frozen files

Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-25/review/patch-25-frozen-r8.sql` | `8f430bce8324b17d0a96b86bd29da94a` |
| `tests/v5.4.2-25/review/battery-25-frozen-r8.sql` | `772c6a71dc7fef67220e318a87032cef` |
| `tests/v5.4.2-25/review/disputes-25-frozen-r8.sh` | `ba77a03997a856bd00d90d3c0e7fcb88` |
| `tests/v5.4.2-25/review/mutations-25-frozen-r8.py` | `68ee1252a020b63f67c522e05c120eeb` |
| `tests/v5.4.2-25/review/terms-25-frozen-r8.py` | `83d1484349ef8c3ad654eb40f2264eb6` |
| `tests/v5.4.2-25/review/migration-25-frozen-r8.py` | `55d80759b4066f5a037acc3bd104be20` |
| `tests/v5.4.2-25/review/fill-manifest-25-frozen-r8.py` | `33802a5b696602534f9b1b521981fc5d` |
| `tests/v5.4.2-25/review/dispute_platform_defaults-frozen-r8.yaml` | `deb668299bc3bd44d1eb72a1aeb117d4` |
| `tests/v5.4.2-25/review/dispute_platform_defaults-frozen-r8.seed.sql` | `3832a44f5ae4c788a8451479390906ec` |
| `tests/v5.4.2-25/review/r7-to-r8.diff` | `4b4514ef1ba4830ddf4b5687d18911ef` |
| `tests/v5.4.2-25/review/battery-r7-to-r8.diff` | `d014313ed8462aaf8b318e1fc0268726` |

The live copies are identical today. Only the patch and the battery changed since r7; the races, mutations, terms, migration, manifest filler, law file and seed are byte-identical to their r7 copies.

## Scope

**Review the diff only:** `r7-to-r8.diff` (46 lines) and `battery-r7-to-r8.diff` (13 lines). Round 7 found all three of you ready with nothing blocking; r8 answers only the leftover wording and one test. No function body changed (the manifest filler writes the same body lists as r7; check that if you can). The merged plan is `application/wave3-build-2026-10-18/v5.4.2-25-r8-plan.md`: read all of it (one page), and the "Round 7 reviewed" section of `v5.4.2-25-r7-plan.md`.

What r8 changes:
1. **Residual R10** (Codex S1, Fable N4) states both directions of the law's final flag: (a) a policy's final stage at any law place where the law's is not final is replaced, including earlier than the law's last stage (a shorter older policy under a longer later law); (b) a final law stage followed by the policy's own appeal keeps the appeal. Both rest on a core contract: `final` binds the utility and never ends an appeal the combined record keeps.
2. **Comments** (Opus N1, Fable N6): `dispute_tariff_compare`'s "narrower than no start" now "no start is wider than it"; the ambiguous "a law of either" names both strategies; the release function's deadlock clause now covers any write to the reading's row followed by one of its disputes' locks, as the header says.
3. **D9t4** (Opus N3, Codex N7) checks which two terms are kept, not only how many.

Not changed, by decision (plan "Not changed"): the always-true average-cap condition (Opus N2), D9u's synthetic stages (Codex N7).

## What to check

- Does each change say exactly what the code does? Is R10 now complete, or is there a third direction in which the law's final flag could disadvantage a customer?
- Does the release comment's clause now match the header's lock rule?
- Is D9t4 right: is `jsonb_build_array(avg('m1'), wcap(0.9,'m2'))` the combined record's `either` in that order, and would it fail if either term were dropped or swapped?
- Did anything outside comments and D9t4 change?
- Is any item from your round-7 review still open?

## Results so far (reproduce what you can)

- Strict apply, twice (`search_path = ''`, `check_function_bodies = on`); the second run skipped by its marker.
- `battery-25.sql`: 351 of 351.
- `mutations-25.py`: 199 of 199, each at its named check.
- `tests/ci.sh`: 59 of 59, first run.

## How to probe

**Opus and Fable** may query `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv25opus`, Fable `rv25fable`; drop any left from round 7 first): `CREATE DATABASE <name> TEMPLATE tally`; revoke TEMP on it from PUBLIC, `tally_app` and `tally_core` at once; `docker cp` the frozen patch into the container and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Any database claim is a probe file in `tests/v5.4.2-25/review/codex-r8-probes/`: run as the owner on a fresh clone with frozen r8 applied, ending in ROLLBACK, printing SQLSTATE and message for each caught error with RAISE NOTICE. The author will run them.

**Restrictions (everyone):** do not create, drop or alter any role; do not run `mutations-25.py` or `tests/ci.sh`; never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes); drop your clone when done.

**Output:** `tests/v5.4.2-25/review/<you>-r8.md` (opus, fable, codex): verdict "ready" or "not yet"; items B (blocking), S (should fix), N (note), each marked executed or predicted, with the evidence. Keep your final message short; the file is the review.
