# Review brief: v5.4.2-30 r4 — tax rows keyed to places, and the taxability fixes

**Date:** 2026-11-22. **Kind:** patch review, round 4, narrow.
**Reviewers:** Opus, Fable and Codex, independently. Do not read the other reviewers' round-4 files. You may read every round-3 file.
**Stream:** rates (`~/code/tally-utility-rates`). Read the repo at that path.

## Frozen files

Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-30/review/patch-30-frozen-r4.sql` | `16658c7afe086c4bbd4b3935e19ff20a` |
| `tests/v5.4.2-30/review/battery-30-frozen-r4.sql` | `3619b5610bbf250256a6eeffefc020a6` |
| `tests/v5.4.2-30/review/mutations-30-frozen-r4.sh` | `c9c31f007194d4a5fb994e757970c162` |
| `tests/v5.4.2-30/review/preconditions-30-frozen-r4.sh` | `58121a1e3fcce1a2aa35d06eb42c67db` |
| `tests/v5.4.2-30/review/levy-30-frozen-r4.sh` | `cd922967e469a06c85875f954fb0d72a` |
| `tests/v5.4.2-30/review/older-tests-30-frozen-r1.diff` | `bfaa7b62019e5ef4d68883b627e1fad1` |
| `tests/v5.4.2-30/review/r3-to-r4.diff` | `e0b3c948703bf650318d2ffddc8d0ab8` |

The live copies are identical to these today. `r3-to-r4.diff` is the change since round 3.

## What changed, and why

The fix list, with each finding's source and the rule that settled it: `application/rates-build-2026-11-05/v5.4.2-30-r4-plan.md`. The calls: DECISION-LOG, 2026-11-22 (rates, -30 r3). In short:

1. **The past read of a premise's places** (Codex B1, Fable S1): one live set; more than one row, relation or distance for one place (kind and code) refuses (21000); two places of one exclusive group refuses; the same place recorded twice alike is answered once (`DISTINCT`).
2. **L7 and the read's comment** restated (Opus S1). Wording only.
3. **Tests for two untested filters** (Opus S2).
4. **The race test and the mutation runner say why a leg failed** (Codex S1); the race clone revokes TEMP (Codex N4). Two new race legs, R6 and R7.
5. Small: the levy's coverage counts only rows it locked (Opus N1); the backfill takes `least(created_at, now())` (Opus N4); the recorder's comment (Fable N1, Opus N3).

## Drafting calls to check in particular

- **Agreeing repeats answer once, disagreeing ones refuse.** Can a case where the two records agree still mislead (is anything the caller reads left out of what makes an answer)? Can the check refuse a live-consistent premise at `now()`?
- **The place's identity in the check is its kind and code**, within the premise's state; a successor row is the same place (-16). Is anything legitimate refused?
- **The two checks and the main read** repeat the same filters. Do they stay in step?
- **The race test's verdicts.** Can a broken or sequential leg still be read as a catch? Is N52's `R1:nowait` the damage it claims?
- **L7 as restated.** Does it still overclaim?

## Results so far (reproduce them)

- **Strict apply, twice:** clean.
- **`battery-30.sql`:** 120 PASS on `tally` + -30 r4.
- **`preconditions-30.sh`:** 9 of 9.
- **`levy-30.sh`:** R1–R7 pass.
- **`mutations-30.sh`:** 69 of 69, each at its named check (5 through the race test).
- **`tests/ci.sh`:** 63 of 63 (with money's -25, -26 and -24 pending beside -30). The first run failed one timing check of battery -22 (R11d: 1.34 s against 1 s). Timed four times each on `tally`, with -30, with -25/-26/-24, and with all four: about 0.3 s everywhere. The cause was not established; the machine's load average was about 12 shortly after that run. The second run passed.

## What to answer

1. Is each round-3 finding of yours closed? Say so item by item.
2. Does any round-4 change open a new path, or break what earlier rounds had right?
3. The tests: is any claim narrower than its check, or any mutation caught for the wrong reason?
4. Do L1–L7 block?

## How to probe

**Opus and Fable** clone into their own scratch database (Opus `rv30opus`, Fable `rv30fable`; race clones `rv30opusrace`, `rv30fablerace`): `CREATE DATABASE <name> TEMPLATE tally`, revoke TEMP on it from PUBLIC, `tally_app` and `tally_core` right after, then strict-apply the frozen r4 patch:

```
docker exec -i -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q < <patch>
```

You may run `levy-30-frozen-r4.sh <your race clone>` (it commits rows). A few mutations may be applied by hand on your own clones.

**Codex reviews source only.** Probe files go in `tests/v5.4.2-30/review/codex-r4-probes/` (owner, a fresh clone of `tally` with frozen r4 applied, ending in ROLLBACK, RAISE NOTICE with the SQLSTATE and message of each caught error). The author runs them. A two-session probe is a shell script in the same folder in the race test's shape.

**Restrictions (everyone):** do not create, drop or alter any role; do not run `mutations-30.sh`, `preconditions-30.sh` or `tests/ci.sh`; never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes); drop your clones when done.

## Output

Write your full review to `tests/v5.4.2-30/review/<reviewer>-r4.md`: a verdict ("ready" or "not yet"); blocking items (B1…) with the concrete path or repro; should-fix items (S1…); notes (N1…). Mark each claim **executed** or **predicted**. Your final message gives the verdict, the blocking items in one line each, and the file path, under 3 KB.
