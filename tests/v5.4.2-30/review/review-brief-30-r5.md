# Review brief: v5.4.2-30 r5 — tax rows keyed to places, and the taxability fixes

**Date:** 2026-11-22. **Kind:** patch review, round 5, narrow.
**Reviewers:** Opus, Fable and Codex, independently. Do not read the other reviewers' round-5 files. You may read every round-4 file.
**Stream:** rates (`~/code/tally-utility-rates`). Read the repo at that path.

## Frozen files

Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-30/review/patch-30-frozen-r5.sql` | `04c4c4dd15170acc72248c97212ba79f` |
| `tests/v5.4.2-30/review/battery-30-frozen-r5.sql` | `fc5f4fc5add5cb19104569d41153d695` |
| `tests/v5.4.2-30/review/mutations-30-frozen-r5.sh` | `5c5f933dce129bb354def60cd3e8b5f0` |
| `tests/v5.4.2-30/review/preconditions-30-frozen-r5.sh` | `58121a1e3fcce1a2aa35d06eb42c67db` |
| `tests/v5.4.2-30/review/levy-30-frozen-r5.sh` | `11c1e986005931447e03714be8427556` |
| `tests/v5.4.2-30/review/older-tests-30-frozen-r1.diff` | `bfaa7b62019e5ef4d68883b627e1fad1` |
| `tests/v5.4.2-30/review/r4-to-r5.diff` | `313be208fdd715c2538676341538cd7e` |

The live copies are identical to these today. `r4-to-r5.diff` is the change since round 4.

## What changed, and why

Round 4: all three ready. The round-5 fix list, with each finding's source and the rule that settled it: `application/rates-build-2026-11-05/v5.4.2-30-r5-plan.md`. In short:

1. **The plain (three-argument) `premise_places_as_of` reads at `infinity`**, what is committed, as -16's did (Opus S1). The only change to what a read answers.
2. **The records that count are picked once** (`v_live`); the refusals and the answer read those rows (Fable S1).
3. **L7, the comments, design 2.5** restated (Opus S1 iii, Fable N3, Codex N5).
4. **Tests:** M12h-M12j, M14-M15b; race R8; mutations N53 relabelled, N53b, N66-N73; race verdicts name the damage read back, the SQLSTATE or the answer, with a selftest (Codex S1, Opus S2-S4, Fable N2).

## Drafting calls to check in particular

- **`infinity`.** Does every as-known comparison (memberships, places, `end_as_known`, the state history) give -16's answer there? Is there a state where the plain read now differs from -16's, or refuses committed, consistent data?
- **The two callers in `tu.sql`** (time zone, regulatory lookups) and `tax_levy_reference_gaps`: any change besides the one intended?
- **`v_live`.** Same rows in the checks and the answer, under RLS and within one statement's snapshot? Does anything the old main read filtered no longer get filtered?
- **The race verdicts.** Can a broken leg still be read as a catch? Does each RACE mutation's bracket show its own damage?
- **L7 as restated.** Does it still overclaim, or omit a case?

## Results so far (reproduce them)

- **Strict apply, twice:** clean.
- **`battery-30.sql`:** 127 PASS on `tally` + -30 r5 (on r4, M15 fails: Opus S1).
- **`preconditions-30.sh`:** 9 of 9.
- **`levy-30.sh`:** selftest passes; R1–R8 pass.
- **`mutations-30.sh`:** 78 of 78, each at its named check (7 through the race test).
- **`tests/ci.sh`:** 63 of 63, with money's -25, -26 and -24 pending beside -30.
- **Read cost** (3000 reads, two runs each, one premise with one district): r5 360 and 386 ms, r4 295 and 306 ms.

## What to answer

1. Is each round-4 finding of yours closed? Say so item by item.
2. Does any round-5 change open a new path, or break what earlier rounds had right?
3. The tests: is any claim narrower than its check, or any mutation caught for the wrong reason?
4. Do L1–L7 block?

## How to probe

**Opus and Fable** clone into their own scratch database (Opus `rv30opus`, Fable `rv30fable`; race clones `rv30opusrace`, `rv30fablerace`): `CREATE DATABASE <name> TEMPLATE tally`, revoke TEMP on it from PUBLIC, `tally_app` and `tally_core` right after, then strict-apply the frozen r5 patch:

```
docker exec -i -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q < <patch>
```

You may run `levy-30-frozen-r5.sh <your race clone>` (it commits rows). A few mutations may be applied by hand on your own clones.

**Codex reviews source only.** Probe files go in `tests/v5.4.2-30/review/codex-r5-probes/` (owner, a fresh clone of `tally` with frozen r5 applied, ending in ROLLBACK, RAISE NOTICE with the SQLSTATE and message of each caught error). The author runs them. A two-session probe is a shell script in the same folder in the race test's shape.

**Restrictions (everyone):** do not create, drop or alter any role; do not run `mutations-30.sh`, `preconditions-30.sh` or `tests/ci.sh`; never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes); drop your clones when done.

## Output

Write your full review to `tests/v5.4.2-30/review/<reviewer>-r5.md`: a verdict ("ready" or "not yet"); blocking items (B1…) with the concrete path or repro; should-fix items (S1…); notes (N1…). Mark each claim **executed** or **predicted**. Your final message gives the verdict, the blocking items in one line each, and the file path, under 3 KB.
