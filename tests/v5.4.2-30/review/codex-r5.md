# Codex — v5.4.2-30, round 5, narrow

Verdict: **ready**. No blocking or should-fix item found in the frozen r5 delta. Round-4 S1 is closed for the named mutation catches. This is a source-review verdict, not certification of the reported database runs.

**Executed** means checksum verification, source inspection, shell syntax checking, or static probe checks. **Predicted** means database behavior handed to the author in `codex-r5-probes/00-battery-and-boundaries.sql`. No database, docker, psql, CI, preconditions, race test (including selftest), or mutation runner was executed. Neither other reviewer's round-5 file was read. The author execution record appended to `codex-r4.md` is attributed evidence, not my execution.

## Blocking items

None.

## Should-fix items

None.

## Notes

### N1 — executed: frozen inputs match

Checked immediately after reading the brief, before further repository inspection:

| File | MD5 |
|---|---|
| patch-30-frozen-r5.sql | `04c4c4dd15170acc72248c97212ba79f` |
| battery-30-frozen-r5.sql | `fc5f4fc5add5cb19104569d41153d695` |
| mutations-30-frozen-r5.sh | `5c5f933dce129bb354def60cd3e8b5f0` |
| preconditions-30-frozen-r5.sh | `58121a1e3fcce1a2aa35d06eb42c67db` |
| levy-30-frozen-r5.sh | `11c1e986005931447e03714be8427556` |
| older-tests-30-frozen-r1.diff | `bfaa7b62019e5ef4d68883b627e1fad1` |
| r4-to-r5.diff | `313be208fdd715c2538676341538cd7e` |

### N2 — executed source disposition: every round-4 item

- **S1 — closed.** Mutation keys now include the specific damage, SQLSTATE, or returned answer. The old timeout examples cannot match the damage keys; connection failures cannot match the R6/R7 answer keys. Details in N3.
- **N1 — renewed.** Checksums above replace the r4 checksums for this review.
- **N2 — retained.** The earlier B1 answer-identity resolution remains: agreeing repeats answer once; different place row, relation or distance refuses. No new source change reopens the prior closures. The author reports that the r4 battery and supplementary probe passed. The r5 handoff retains those boundary controls; their r5 outcomes are predicted.
- **N3 — resolved more directly.** The filters now select `v_live` once, and both checks and the returned membership rows use those IDs. The r4 qualification that only the two checks shared the CTE no longer applies. See N4.
- **N4 — closed within the narrow scope.** Named race catches now preserve their evidence; the wait claim is scoped to R1–R3/R5 and says ten samples instead of a hard wall-clock bound. TEMP revocations remain in the race-clone branch. No concurrency execution is claimed.
- **N5 — closed.** Design §2.5 and M6 no longer promise the original bill's observed answer. L7 expressly distinguishes silent replay changes, ambiguity refusals, and two stacking districts answered together. L1–L7 assessment is in N6.

### N3 — executed: race verdicts and mutation specificity

Sources: `levy-30-frozen-r5.sh:42–112,182–323`; `mutations-30-frozen-r5.sh:40–46,253–312`.

The seven race mutations now have distinct affirmative signatures:

| Mutation | Required bracket | Source evidence required by the leg |
|---|---|---|
| N52 | R1 `nowait:damage` | B succeeds; open levy and closed place read back |
| N53 | R5 `waited:23514` | B refuses with 23514 instead of the intended 40001 |
| N53b | R5 `waited:damage` | B succeeds; the levy is read back after the successor operation |
| N54 | R3 `waited:damage` | B succeeds; final history state differs from the premise state |
| N64 | R7 `read:outside,within` | successful read returns the contradictory answer |
| N65 | R6 `read:within,within` | successful read returns the duplicate answer |
| N73 | R8 `read:R30-D,R30-D2` | successful read returns both districts |

N53's relabelling is accurate: removing only the changed-row-set check leaves the locked-row coverage restriction. N53b removes both checks and has a separate damage key. No new concrete wrong-reason catch was found in these edits.

The extracted SQLSTATE is retained rather than collapsing all SQL errors to `waited` or `nowait`. A 57014 timeout remains a failing race experiment, but its bracket cannot satisfy any of these named catches. R6/R7 retain the read status and compare successful output exactly; unrelated read errors become BROKEN. The runner compares the full bracket, and BROKEN/SEQUENTIAL/SETUP remain non-matching results. The selftest source includes the prior timeout and lost-connection examples, absent damage, writer failure, duplicate/contradictory answers, and both psql SQL-error exit conventions. Shell syntax checks passed; I did not execute the selftest.

There is a minor diagnostic imperfection, not a remaining mutation false catch: R3 still does not retain the separate `LAST` query's exit status. If that query fails while B has the expected 40001 refusal, the leg can print `FAIL R3 [waited:40001]` instead of BROKEN. That does not match N54's `waited:damage`; if B succeeded, the damage predicate also requires a state/state-shaped unequal pair. No correctness credit is awarded by that failed read.

R8 checks writer statuses and the bill's transaction-start ordering on the successful-read path. Its scheduled sleeps are not themselves proof of ordering; the timestamp assertion is the proof required before accepting the successful answer. This is source inspection of the experiment, not a reproduced three-session result.

### N4 — executed source analysis; database outcomes predicted in probe 00: infinity and v_live

Sources: `patch-30-frozen-r5.sql:164–168,768–903`; bounded grep of `sql/tu.sql:27021–27062`; probe 00's battery M1–M15b, retained r4 controls, and R5 comparisons.

At positive infinity, the new predicates reduce to the old current-read predicates: created-at comparisons admit recorded rows, no non-NULL void stamp is greater than infinity, and `end_as_known` uses the stored end even for an infinite close stamp. The state lookup takes the latest history row by recorded_at/seq. Its recorder and backfill are unchanged in r5; the existing same-transaction ordering and overlapping-writer refusal remain relevant to agreement with the live premise state. I found no new path in this delta that refuses committed, consistent data accepted by -16. This does not extend to owner-corrupted history or bypassed constraints.

`v_live` carries membership IDs, not copied row values. That is sufficient in this implementation: the function remains STABLE and invoker-rights; its ordinary reads use the calling statement's snapshot and the same RLS context. All earlier membership selection filters are present in the single selection: premise, axis, creation, void, membership date range, place creation/date range, and state. The checks and result then select the same IDs. The result still joins place kinds for specificity. No SECURITY DEFINER or policy bypass was added. Empty membership sets become an empty array; the separately selected state remains the state branch.

**Predicted / probe 00:** the frozen r5 battery and retained r4 distance/successor controls pass. The supplementary test checks `end_as_known` at infinity against NULL, finite, future and infinite close stamps. It compares all eight output columns as multisets against a temporary copy of the original -16 reader, for the first fixture tenant's premises, both axes, and four dates including the successor boundary. It includes the battery's future-stamped void/state cases and wrong-state/not-yet-effective place controls. Another-tenant access through the three-argument form is refused. These are planted-state and single-session controls, not a concurrency proof.

### N5 — executed source analysis; database controls predicted in probe 00: callers and test scope

The direct `premise_places_as_of` call sites found in `tu.sql` are in `premise_time_zone_as_of`: its regulatory/tax candidate reads and regulatory-axis state-uniformity read (`27088–27090`, `27120`). I did not find a second independently named regulatory caller of this function in the supplied schema. Thus the brief's “two callers” should not be read as an inventory of two distinct functions. Both axes receive the intended current-read restoration. The time-zone fact reads, specificity selection, disagreement refusal and state-uniformity rule are unchanged.

`tax_levy_reference_gaps` (`patch:477–523`) does not call this reader. It directly reads current place/fact ranges, memberships and premise state; no r5 edit changes it. Its report semantics are therefore not widened by the infinity wrapper. Probe 00 retains G1–G5b and compares time-zone outcomes with a temporary copy of the old consumer wired to the old reader. Expected time-zone refusals are compared by SQLSTATE and message, with every caught error printed.

M12h separates axes; M12i/j independently exercise kind as part of answer identity and exclusive-group place identity. M14/M14b cover place creation, state and date filters; N69–N71 remove those separately. M15 is explicitly a planted timestamp experiment, and M15b retains the finite-instant answer. R8 supplies the real-session counterpart in the author's harness. N72 and N73 exercise the same wrapper mutation by different experiments. I found no added assertion weaker than the named regression it claims to detect. M4's old label “as known now” is imprecise under the new API wording, but its fixture and assertion remain appropriate; M15/M15b disambiguate the behavior.

The apply/battery/precondition/race/mutation/CI totals and timing figures in the brief remain **author-reported**, not reproduced or independently certified here.

### N6 — executed scope assessment: L1–L7 do not block

- **L1:** staging and approval remain application work; the reference report is not approval.
- **L2:** the accepted cross-table penalty concurrency limitation remains; r5 does not claim to close it.
- **L3:** reference-data loading remains the later data patch.
- **L4:** legacy-column retirement remains separate work.
- **L5:** bill evidence, line bases and one-off defaults remain the money stream's work.
- **L6:** pre-go-live evidence policy and unavailable-history refusal remain accepted. Probe 00 retains the history refusal controls; backfill is not reconstructed history.
- **L7:** the restatement covers both a replay changing with writer visibility and a permanently ambiguous historical coordinate, including stacking districts that return together without an error. Recorded bill evidence identifies what was used, not whether that answer was correct. The plain reader no longer imposes the caller's transaction-start timestamp as its recorded coordinate. “Committed” here is subject to the SQL snapshot and normal visibility of the transaction's own writes; it is not a promise to see commits outside that snapshot. The state-row-as-found qualification is explicit in the function comment. No replay guarantee is revived by §2.5 or M6.

## Probe handoff — predicted, not executed

`codex-r5-probes/00-battery-and-boundaries.sql` is standalone: frozen r5 battery, notices added to all caught-error handlers, retained r4 supplementary controls, then the infinity / -16 equivalence / time-zone / tenant-isolation checks described above. Expected result: all assertions pass. Temporary baseline functions are copied from bounded schema grep, not an alternate reconstruction of the old algorithm.

Run as owner, with ON_ERROR_STOP, on a fresh clone of `tally` with frozen r5 applied and TEMP revoked from PUBLIC, tally_app and tally_core. No role is created or altered. Owner-only fixture edits are labelled and their guards restored. The file ends in ROLLBACK. Static checks confirmed the final rollback, baseline function definitions and caught-error instrumentation; SQL was not parsed or executed by a database here.

**Author execution record: pending.** Record setup failures separately from assertion failures. No database outcome in this review is marked executed by Codex.

---

## Author execution record (2026-11-22)

Fresh clone of `tally` (TEMP revoked), frozen r5 strict-applied (clean). `00-battery-and-boundaries.sql` run as owner with ON_ERROR_STOP: exit 0, `battery-30: all checks passed`, then `codex-r5: all battery and supplementary checks passed`. Every predicted control held, including the column-by-column equivalence of the three-argument read with -16's reader (both axes, four dates), the time-zone equivalence, `end_as_known` at infinity, and the other-tenant refusal. No setup failure.
