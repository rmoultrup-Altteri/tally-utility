# Review brief: v5.4.2-30 r2 — tax rows keyed to places, and the taxability fixes

**Date:** 2026-11-06. **Kind:** patch review, round 2.
**Reviewers:** Opus, Fable and Codex, independently. Do not read the other reviewers' round-2 files. You may read your own round-1 file.
**Stream:** rates (`~/code/tally-utility-rates`). Read the repo at that path.

## Frozen files

Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-30/review/patch-30-frozen-r2.sql` | `c771e574448d28118899b75f5b209936` |
| `tests/v5.4.2-30/review/battery-30-frozen-r2.sql` | `99988d012eb98f35384b009c4a46e715` |
| `tests/v5.4.2-30/review/mutations-30-frozen-r2.sh` | `ae4db22ac437bea544afade7db1bcc5a` |
| `tests/v5.4.2-30/review/preconditions-30-frozen-r2.sh` | `b4a7ca5a79a59a03491256d97cad0646` |
| `tests/v5.4.2-30/review/older-tests-30-frozen-r1.diff` | `bfaa7b62019e5ef4d68883b627e1fad1` (unchanged since r1) |
| `tests/v5.4.2-30/review/r1-to-r2.diff` | `a4e00abf34814105d6ba716f48ce306a` |

The live copies (`sql/v5.4.2-30-tax-levies-and-taxability.sql`, `tests/v5.4.2-30/`) are identical to these today. `r1-to-r2.diff` is the whole change since round 1 (patch, battery, mutations, preconditions).

## What changed, and why

The round-1 brief (`review-brief-30-r1.md`) describes the patch. The fix list, with each finding's source and the rule that settled it: `application/rates-build-2026-11-05/v5.4.2-30-r2-plan.md`. The calls are in the DECISION-LOG entry of 2026-11-06 (rates, -30 r1). In short:

1. **A premise's state is recorded on change** (round 1: Opus B1, Codex B2). New table `service_location_state_history`: written by the database at a premise's insert and at each change of its normalised state (`z_record_service_location_state`), refused to the app (`a_enforce_state_history_written_by_db`, the -07 depth fence), append-only, backfilled at each premise's `created_at`. `premise_places_as_of` reads the state as known at the instant and refuses a premise not yet recorded then.
2. **A place is never closed from under a levy** (Codex B1, Opus S2, Fable S1). A deferred constraint trigger on `places` (`z_check_place_levy_coverage`, ALWAYS) checks at commit that every levy of the closed row's kind, state and code is still covered by that code's rows, so a close and its successor row may come in one transaction. The levy's insert check now takes each of the code's rows' locks shared, under READ COMMITTED, before measuring coverage (VOLATILE).
3. The late-penalty guards fire always (Opus S1). The fact-kind repair refuses only while the kind is still a fraction (Opus S3, Fable S3, Codex S1). Exemption services must each be a service, never `all` (Fable S2); the precondition counts such rows. The reference report also lists a place that publishes a rate and has no levy (Fable S6). The exemption column's comment is re-issued (Opus S4). The published rate's description states its range and that it is stored as published (Codex S4, Fable N1).
4. Tests: L fragments name the schema's own reason; P4 is refused for one reason; C0–C4 (place close), L22/L23 (coverage across rows and a gap), Q1b (as `tally_app`), M3 from the premise's own stamp (no wall-clock age), M6–M11 (the state correction, the history's rules, a place's end as known), G5 (no-levy report), E2c–E2e, P7. `preconditions-30.sh` gains C2b, C5 (re-apply after a percent fact) and C6 (backfill). New mutations N4b–N4d, N28b, N34–N46.
5. New known limits: **L6** (an instant before a premise's state was recorded cannot be read; legacy rebills use their own record) and **L7** (the template's now() stamps: two writers on one key can make a read raise "2 rows" for seconds; the template's, on the board).

## Drafting calls to check in particular

- **Recording the state, not refusing its change.** Opus offered the smaller fix: refuse a state change while any membership exists, voided ones included. The author recorded the state instead. A premise with no memberships still reads its state's tax, and the smaller fix would refuse a correction of a mistyped state. Is the history complete? Consider every path that writes `service_locations.state`, a premise's tenant, the backfill's use of today's state, and RLS on the history for a platform administrator and for `tally_core`.
- **The deferred coverage check.** Is commit-time checking sound with the shared/exclusive place locks (a levy insert racing a close, a close racing a successor insert)? Can `SET CONSTRAINTS … DEFERRED` or a session setting skip it? It is ALWAYS, and deferred to commit at the latest.
- **The second leg of `tax_levy_reference_gaps`.** It reads memberships as they stand now and premises' current states. Is that the right "now" for a report?
- **Stamps with `now()`** in the history (as memberships and places), and the order by `recorded_at, seq` within one transaction.

## Results so far (reproduce them)

- **Strict apply, twice:** clean.
- **`battery-30.sql`:** 107 PASS on `tally` + -30 r2.
- **`preconditions-30.sh`:** 8 of 8 (C0–C6 with C2b).
- **`mutations-30.sh`:** 50 of 50, each at its named check.
- **`tests/ci.sh`:** 58 of 58 (-30 pending after the money stream's -25, -26, -27 r3).

## What to answer

1. Is each round-1 finding of yours closed? Say so item by item.
2. Does any round-2 change open a new path (roles, RLS, the as-of instants, the deferred check, the locks, a re-apply)?
3. Does the history or the coverage trigger break anything earlier patches had right (every write to `service_locations` and `places`)?
4. The tests: is any claim narrower than its check, or any mutation caught for the wrong reason?
5. Do L1–L7 block?

## How to probe

As in round 1. **Opus and Fable** clone into their own scratch database (Opus `rv30opus`, Fable `rv30fable`): `CREATE DATABASE <name> TEMPLATE tally`, revoke TEMP on it from PUBLIC, `tally_app` and `tally_core` right after, then strict-apply the frozen r2 patch:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

**Codex reviews source only.** Probe files go in `tests/v5.4.2-30/review/codex-r2-probes/` (owner, a fresh clone of `tally` with frozen r2 applied, ending in ROLLBACK, RAISE NOTICE with the SQLSTATE and message of each caught error). The author runs them and appends the output.

**Restrictions (everyone):** do not create, drop or alter any role; do not run `mutations-30.sh`, `preconditions-30.sh` or `tests/ci.sh`; never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes); drop your clone when done.

## Output

Write your full review to `tests/v5.4.2-30/review/<reviewer>-r2.md`: a verdict ("ready" or "not yet"); blocking items (B1…) with the concrete path or repro; should-fix items (S1…); notes (N1…). Mark each claim **executed** or **predicted**. If you cannot write the file, send the review to main as several messages, each under 3 KB. Your final message gives the verdict, the blocking items in one line each, and the file path.
