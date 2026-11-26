# Review brief: v5.4.2-25 r6 — disputes, round-5 findings fixed

**Date:** 2026-11-26. **Kind:** patch review, round 6.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's files for this round. Each of you may read your own round-5 review (`opus-r5.md`, `fable-r5.md`, `codex-r5.md`). **Codex:** review the whole patch again, not only the change.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-25/review/patch-25-frozen-r6.sql` | `2e98f5d5789c534924e154f456908aa8` |
| `tests/v5.4.2-25/review/battery-25-frozen-r6.sql` | `a5204e30bc67641effaef4c7c96e2108` |
| `tests/v5.4.2-25/review/disputes-25-frozen-r6.sh` | `ba77a03997a856bd00d90d3c0e7fcb88` |
| `tests/v5.4.2-25/review/mutations-25-frozen-r6.py` | `77d92d300ddaf8c553d7b2e67e9cbedc` |
| `tests/v5.4.2-25/review/terms-25-frozen-r6.py` | `83d1484349ef8c3ad654eb40f2264eb6` |
| `tests/v5.4.2-25/review/migration-25-frozen-r6.py` | `55d80759b4066f5a037acc3bd104be20` |
| `tests/v5.4.2-25/review/fill-manifest-25-frozen-r6.py` | `33802a5b696602534f9b1b521981fc5d` |
| `tests/v5.4.2-25/review/dispute_platform_defaults-frozen-r6.yaml` | `deb668299bc3bd44d1eb72a1aeb117d4` |
| `tests/v5.4.2-25/review/dispute_platform_defaults-frozen-r6.seed.sql` | `3832a44f5ae4c788a8451479390906ec` |
| `tests/v5.4.2-25/review/r5-to-r6.diff` | `7d40f73f7c1893ea5b3fe0740879f20d` |

The live copies are identical today. `r5-to-r6.diff` is the patch's change since round 5; terms, migration, the manifest filler, the law file and its seed are unchanged since r4.

## Background

The base is `tally` (`sql/tu.sql`), carrying -23, -24, -27, -28, -29 and -30. In `tests/ci.sh`, -25 applies first of the two pending patches, before -26.

Round 5: Fable ready; Opus not yet (two should-fix); Codex not yet (two blocking, one should-fix). The merged plan is `application/wave3-build-2026-10-18/v5.4.2-25-r6-plan.md`: **read all of it**, especially "As built". Ryan's ruling of 2026-11-26 (DECISION-LOG: where a tariff and a later law cannot be ranked on a start, end or must-pay, both are kept, the core applies the more protective, the database checks the record fits one) stands unchanged. Every r6 item is settled by standing rule (never looser than the law; fail toward protection).

What r6 changes, in short:
1. **The stages merge always runs** where the law governs, so the law's `final` flag reaches every combined record (Codex B1, Fable N6).
2. **Undisputed charges against a withholding cap compare as a fraction of 1**, both directions; against other strategies it still asks no more (Codex B2, Opus S1).
3. **Tests** for every looser branch and every merge part (Fable S1, Opus S2), boundary days 60 and 61 (Fable N9), the displaced stage on the real path (Fable N5); 15 new mutations.
4. **A `lacks` verdict** for the four list sections (Codex S1).
5. Notes: `any_time` the widest start (Opus N1, Fable N3); the lock rule widened to two disputes' locks (Opus N2, Fable N4); the end check fails closed on a kind it does not name (Opus N4); DR2's window stretched; contract lines (Opus N3).

## What to check in particular

- Each of your round-5 findings: fixed, with both sides tested? Codex: each of your probes (`codex-r5-probes/`, the author's runs beside them).
- **The always-run merge.** Does running it with no stage finding ever change anything but the `final` flag at the law's places (a policy no looser should otherwise come back as it is)? Is the law's `final: false` over a policy's `final: true` at a law place ever looser for a customer?
- **The withholding comparison.** Is every pair of undisputed charges, withholding caps, average caps, full bill and unruled ranked right, in both directions, at filing and in a combination? Anything still depending on the customer called looser, or the reverse?
- **The start ranking.** Is `any_time` truly no narrower than every other kind, including on a regulator complaint?
- **The fail-closed end check.** Can any valid document reach the new branch?
- **`lacks`.** Does anything read the verdict and treat `lacks` wrongly (the combination, `dispute_tariff_compare`, a test)?
- What earlier rounds asked, for the whole patch (Codex especially).

## Results so far (reproduce what you can)

- **Strict apply, twice:** `search_path = ''`, `check_function_bodies = on`; the second run is skipped by its marker.
- **`battery-25.sql`:** 342 checks (318 + D9j–D9s, D9g4, D9g5), one transaction, rolled back. Against frozen r5 it fails first at D9j.
- **`races/disputes-25.sh`:** DR1–DR17, 30 results; three back-to-back runs on fresh clones, 30 of 30 each.
- **`terms-25.py`:** unchanged.
- **`mutations-25.py`:** 193 mutations. One full run caught 192; M158 was caught at D9g, one check before its old name (the fail-closed end check now refuses a fitting day where it used to admit every day). It was retargeted to D9g and caught there when re-run alone.
- **`tests/ci.sh`:** 59 of 59 on the first run.

## What to answer

1. Does r6 close every round-5 finding (read your own)? Name any half-done.
2. Is there a path around any rule, new or old? Try each role, isolation level and statement shape, and a superuser history load.
3. Do -17's template and -23's seal properties still hold?
4. Concurrency: is the lock order followed everywhere, and is any check a read without the lock that orders it?
5. Do the invariants catch what they claim?
6. The tests: is any check weaker than its label; does any mutation pass for the wrong reason; what is missing?
7. Residuals R1–R9: is any of them actually blocking?

## How to probe

**Opus and Fable** may query `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv25opus`, Fable `rv25fable`; drop any left from round 5 first): `CREATE DATABASE <name> TEMPLATE tally`; revoke TEMP on it from PUBLIC, `tally_app` and `tally_core` at once; `docker cp` the frozen patch into the container and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

Run the race script on a clone of its own (the battery's fixtures and the races' committed rows collide on one clone).

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim is a probe file in `tests/v5.4.2-25/review/codex-r6-probes/`: run as the owner on a fresh clone with frozen r6 applied, ending in ROLLBACK, printing SQLSTATE and message for each caught error with RAISE NOTICE (a COPY probe prints its own error). A two-session claim is two files with the schedule written at the top. The author will run them.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role (`tally_dispute` exists already; do not touch it).
- Do not run `mutations-25.py` (fixed database name) or `tests/ci.sh`.
- Run `disputes-25.sh` only against your own clone, a separate one from the battery's; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.

**Output:** `tests/v5.4.2-25/review/<you>-r6.md` (opus, fable, codex): verdict "ready" or "not yet"; items B (blocking), S (should fix), N (note), each marked executed or predicted, with the evidence. Keep your final message short; the file is the review.
