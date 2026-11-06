# Review brief: v5.4.2-30 r3 — tax rows keyed to places, and the taxability fixes

**Date:** 2026-11-06. **Kind:** patch review, round 3.
**Reviewers:** Opus, Fable and Codex, independently. Do not read the other reviewers' round-3 files. You may read your own earlier files. Codex did not review round 2 (usage limit); Codex reviews the whole patch at r3, with its round-1 file as its starting point.
**Stream:** rates (`~/code/tally-utility-rates`). Read the repo at that path.

## Frozen files

Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-30/review/patch-30-frozen-r3.sql` | `a90c82cb685eecc2578d87b29ef322b0` |
| `tests/v5.4.2-30/review/battery-30-frozen-r3.sql` | `5b77be6f0cc757ee9dde1fb85e3a99b5` |
| `tests/v5.4.2-30/review/mutations-30-frozen-r3.sh` | `a5db1e2fdb7e91b2b5b26fedf6275964` |
| `tests/v5.4.2-30/review/preconditions-30-frozen-r3.sh` | `b4a7ca5a79a59a03491256d97cad0646` (unchanged since r2) |
| `tests/v5.4.2-30/review/levy-30-frozen-r3.sh` | `9202e6a96f8d34889de8b20d9eb8f38f` (new: the race test) |
| `tests/v5.4.2-30/review/older-tests-30-frozen-r1.diff` | `bfaa7b62019e5ef4d68883b627e1fad1` (unchanged since r1) |
| `tests/v5.4.2-30/review/r2-to-r3.diff` | `1bd33e4e28f80792eb72280885ec4834` |

The live copies (`sql/v5.4.2-30-tax-levies-and-taxability.sql`, `tests/v5.4.2-30/`, `tests/v5.4.2-30/races/levy-30.sh`) are identical to these today. `r2-to-r3.diff` is the change since round 2, including the one line that adds the race test to `tests/ci.sh`. The earlier changes: `r1-to-r2.diff`.

## What changed, and why

The round-1 brief describes the patch (`review-brief-30-r1.md`); the round-2 brief, round 2's changes (`review-brief-30-r2.md`). The round-3 fix list, with each finding's source and the rule that settled it: `application/rates-build-2026-11-05/v5.4.2-30-r3-plan.md`. The calls: DECISION-LOG, 2026-11-06 (rates, -30 r2). In short:

1. **Two overlapping corrections of a premise's state** (round 2: Opus B1, Fable B1). The recorder refuses with 40001 (retry) when the premise already has a history row stamped after its own transaction began. Stamps stay `now()`, so a correction and the memberships voided with it carry one instant. Fable's `clock_timestamp()` alternative was not taken; the plan says why.
2. **The coverage check's role** (Fable S1): it requires a role that sees every tenant, as the close does.
3. **Two places of one exclusive group** (Opus S1): `premise_places_as_of` refuses (21000) when, as known at the instant, a premise is within two places of one group.
4. **A levy insert that waited** (Opus's note): after locking the code's rows it re-reads them and refuses (40001) if one was committed meanwhile (-16's rule, its race R19).
5. Tests: C5, M8c (two changes in one transaction), M12/M12b, M13; the race test `levy-30.sh` (R1–R5: the lock handshake both ways, overlapping corrections and a control, the re-read), run by `ci.sh`; the mutation runner gains `RACE:<leg>` (N52–N54) beside N48–N51. L7 restated.

## Drafting calls to check in particular

- **The recorder's refusal.** Is "a row stamped after my start" the right test in every order (insert, then update; two updates; an update and a re-spelling; the backfill's rows)? Can an overlapping writer still be recorded out of order, for example one that is not blocked by the premise's row lock?
- **The exclusive-group refusal**, which repeats the main read's filters. Do the two stay in step? Does it refuse anything legitimate, such as a `known_outside` row or a group of NULL?
- **The re-read after locking.** Can it loop, or refuse an ordinary insert with no concurrent change?
- **The race test.** Does each leg prove what it says, with the second session seen waiting? Does `RACE:<leg>` in the runner catch for the right reason?

## Results so far (reproduce them)

- **Strict apply, twice:** clean.
- **`battery-30.sql`:** 112 PASS on `tally` + -30 r3.
- **`preconditions-30.sh`:** 8 of 8.
- **`levy-30.sh`:** R1–R5 pass (each second session seen waiting).
- **`mutations-30.sh`:** 57 of 57, each at its named check (3 through the race test).
- **`tests/ci.sh`:** 59 of 59 (-30 pending after the money stream's -25, -26, -27).

## What to answer

1. Is each earlier finding of yours closed? Say so item by item.
2. Does any round-3 change open a new path (roles, RLS, the as-of instants, retries, the locks, a re-apply)?
3. Does anything break what earlier patches had right (every write to `service_locations` and `places`)?
4. The tests: is any claim narrower than its check, or any mutation caught for the wrong reason?
5. Do L1–L7 block?

## How to probe

As before. **Opus and Fable** clone into their own scratch database (Opus `rv30opus`, Fable `rv30fable`): `CREATE DATABASE <name> TEMPLATE tally`, revoke TEMP on it from PUBLIC, `tally_app` and `tally_core` right after, then strict-apply the frozen r3 patch:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

You may run the frozen race test against your own clone (`levy-30-frozen-r3.sh <your clone>`; it commits rows, so use a clone you drop).

**Codex reviews source only.** Probe files go in `tests/v5.4.2-30/review/codex-r3-probes/` (owner, a fresh clone of `tally` with frozen r3 applied, ending in ROLLBACK, RAISE NOTICE with the SQLSTATE and message of each caught error). The author runs them and appends the output. A two-session probe is a shell script in the same folder in the race test's shape; say so in your review.

**Restrictions (everyone):** do not create, drop or alter any role; do not run `mutations-30.sh`, `preconditions-30.sh` or `tests/ci.sh`; never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes); drop your clone when done.

## Output

Write your full review to `tests/v5.4.2-30/review/<reviewer>-r3.md`: a verdict ("ready" or "not yet"); blocking items (B1…) with the concrete path or repro; should-fix items (S1…); notes (N1…). Mark each claim **executed** or **predicted**. If you cannot write the file, send the review to main as several messages, each under 3 KB. Your final message gives the verdict, the blocking items in one line each, and the file path.
