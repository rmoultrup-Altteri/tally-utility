# Codex — v5.4.2-30, round 4, narrow

Verdict: **ready** for the SQL patch. No blocking item found. The race harness still has the should-fix below; this verdict does **not** certify “69 mutations caught for the right reason.”

**Executed** means checksum verification, source inspection, or the isolated shell classification demonstration described below. **Predicted** means database behavior submitted for author execution. No database, docker, psql, race script, mutation runner, preconditions script or CI was run. I did not read `opus-r4.md` or `fable-r4.md`. The author’s round-3 execution record is attributed evidence, not my execution.

## Blocking items

None.

## Should-fix items

### S1 — executed: round-3 S1 is only partly closed; broken experiments can still satisfy all five race mutation keys

Sources: `levy-30-frozen-r4.sh:102–112,145–146,187–189`; `mutations-30-frozen-r4.sh:46` and N52–N54/N64–N65.

The improvements are real: A failures become BROKEN; B connection/command failures are distinguished in `verdict()`; a correct result without an observed wait becomes SEQUENTIAL; R1/R2 pin SQLSTATE and message; the runner retains the reason suffix. The original two examples of A failing and a correct sequential leg no longer count as catches.

But `verdict()` treats **any** B exit 3 containing `ERROR:` as a semantic result. If its error differs from the expected refusal, the only remaining discriminator is whether a wait was sampled. The new R6/R7 final read is weaker: its exit status is discarded altogether. Any output failing the expected grep becomes `FAIL R6/R7 [read]`, including a failed connection. R3 likewise does not classify failure of the separate `LAST` query before folding it into the semantic verdict.

I executed only the extracted `verdict()` / `refused()` shell definitions with literal inputs, followed by the runner's sed transformation. With `AST=0`, `BST=3`, and `OUT='ERROR:  57014: canceling statement due to statement timeout'`, the output mapped as follows:

| Literal input setting | Accepted mutation key |
|---|---|
| R1, WAITED=0 | `RACE:R1:nowait` (N52) |
| R3, WAITED=1 | `RACE:R3:waited` (N54) |
| R5, WAITED=1 | `RACE:R5:waited` (N53) |

For R6/R7 I executed their final grep/echo branch with literal `OUT='psql: error: connection to server was lost'`. It produced `RACE:R6:read` and `RACE:R7:read`, exactly N65 and N64. These are shell classification reproductions, **not** database timeout or connection-failure experiments. No claim is made that the reported author run encountered them.

Fix: retain each read's exit status and classify infrastructure/unrelated errors as BROKEN. Give mutation catches explicit semantic signatures: successful conflicting write plus verified resulting state for N52; the intended accepted write/result for N53/N54; successful duplicate result for N65; successful contradictory result for N64. A wrong SQLSTATE can fail the unmutated test without being accepted as the named mutation's intended damage. Test the classifier with literal output/status fixtures independently of database races.

**N52 specifically:** removing the shared advisory lock is the source mutation named by the test. `nowait` alone does not demonstrate its intended damage. At present the key requires neither B success nor a persisted conflicting close. The timeout demonstration above satisfies it without either. Keep its intentional no-wait exception, but require affirmative evidence of the conflicting write.

This remains a test-evidence defect, not a demonstrated production bypass, so I retain its round-3 should-fix severity.

## Notes and required answers

### N1 — executed: frozen inputs match

Checked before all other repository review work, immediately after reading the brief:

| File | MD5 |
|---|---|
| patch-30-frozen-r4.sql | `16658c7afe086c4bbd4b3935e19ff20a` |
| battery-30-frozen-r4.sql | `3619b5610bbf250256a6eeffefc020a6` |
| mutations-30-frozen-r4.sh | `c9c31f007194d4a5fb994e757970c162` |
| preconditions-30-frozen-r4.sh | `58121a1e3fcce1a2aa35d06eb42c67db` |
| levy-30-frozen-r4.sh | `cd922967e469a06c85875f954fb0d72a` |
| older-tests-30-frozen-r1.diff | `bfaa7b62019e5ef4d68883b627e1fad1` |
| r3-to-r4.diff | `e0b3c948703bf650318d2ffddc8d0ab8` |

### N2 — executed source disposition; database outcomes predicted: round-3 findings, individually

- **B1: closed in source under the November 22 decision.** The reader now checks distinct `(place row ID, relation, distance)` per `(kind, code)` and deduplicates agreeing output. Exclusive groups count distinct places. I accept the decision to answer agreeing repeats once; my r3 objection to bare DISTINCT was about conflicting answers, which now have an explicit refusal. Probe 00 carries M12d–M12g and their current-read controls: agreeing county/district repeats answer once; opposite relations, different distances and ambiguous successor rows refuse with 21000.
- **S1: partly closed, still should-fix.** See S1 above. The original examples are fixed, but broader broken-experiment classifications remain and the new read legs introduce a connection-error case.
- **N1 (frozen inputs):** renewed in N1 above.
- **N2 (earlier findings):** no r4 source change reopens the recorded closures. Those remain source dispositions supported by the author's r3 probe record. No new second-apply or historical execution is claimed here. Probe 00 retains the battery's coverage, state-history, percent, required-answer and guard checks.
- **N3 (source paths/write guards):** no new blocker found in the narrow delta. The recorder's r4 edit is commentary; the coverage query adds `p.id = ANY (v_locked)`; backfill now uses `least(l.created_at, now())`. These are inspected source changes, not executed concurrency or migration results.
- **N4 (test scope/TEMP):** the RACE clone branch now contains all three prescribed TEMP revocations. M12c and N55/N56 add the outside/group-NULL cases. N57–N62 separately target agreeing repeats and each answer component; N64/N65 target the new race reads, subject to S1. The locked-row coverage clause explicitly has no mutation; no inter-statement execution proof is claimed.
- **N5 (limits):** L7 has been materially narrowed; assessment below. L1–L6 retain their agreed scope.

### N3 — executed source inspection; database outcomes predicted: the new reader's answer identity and filters

Source: `patch-30-frozen-r4.sql:794–884`.

The two checks share one `live` CTE. Their membership/premise, axis, creation, void, membership effective range, place creation/effective range and state filters match the final membership SELECT. The final SELECT additionally joins `place_kinds` to obtain specificity; the schema declares the place-kind foreign key and the kind primary key. The CTE is shared by the two checks, **not** by the final RETURN QUERY; the plan's “read once” should be understood accordingly. The function remains declared STABLE.

The returned membership-specific fields are relation and distance. All other returned fields come from the selected place ID and its kind. Evidence references and membership IDs are not output fields. I found no caller-visible field omitted from the agreement comparison that can vary between two records pointing to that same place row in this read. Distinct place row IDs remain disagreement even if their relation and distance agree; this preserves the caller's returned row identity.

Grouping by kind/code within the already filtered state follows the declared successor convention. It does not merge different kinds. Current effective ranges still select which successor applies on a date. The new check is not an unconditional ban on having successive rows.

**Predicted, probe 00:** M12d handles agreeing repeats with NULL distance; M12e/f/g handle relation/distance/row disagreement; M12b/e2/f2/g2 and M12c exercise current consistent sets. Supplementary controls check NULL versus numeric distance (refusal), equal non-NULL outside distances (one answer), two NULL outside distances (one answer), and the dates immediately before/on succession (the appropriate single row).

For a fresh settled current read, I found no new false refusal path in these cases. That is not a promise about `now()` in a long-running transaction: the transaction-start recorded coordinate remains subject to L7. Nor is this a claim that every concurrency schedule was tested.

### N4 — executed: test claims and mutation specificity

The M12 additions assert concrete arrays, relations, distances or row IDs, and refusals name both SQLSTATE and the intended guard. N55/N56 target independent exclusive-group filters. N57 and N62 distinguish erroneous group counting from erroneous answer counting; N58 targets output DISTINCT; N59/N59b, N60 and N61 target omission of the refusal or its respective components. The named single-session checks match those source mutations. I found no additional concrete wrong-reason catch in these additions; S1 prevents certification of the race catches.

R6/R7 verify writer success and a persisted timestamp ordering before their final read. They do not sample a lock wait: their experiment is transaction-lifetime overlap with the void committed before replacement. That is appropriate to this case, but contradicts the header's blanket “Every two-session leg” wait claim. Scope that sentence to R1–R3/R5. Also, the sampling loop has ten external queries plus sleeps; “up to 1.5s” is not a hard wall-clock bound.

The brief's apply/battery/precondition/race/mutation/CI totals remain **author-reported**, not reproduced here. The reported -22 timing failure has no established cause in the supplied evidence; I do not attribute it to load or to this patch.

### N5 — executed scope assessment: L1–L7 do not block this narrow review

- **L1:** application staging/approval remains its assigned work.
- **L2:** the cross-table penalty concurrency limitation remains an expressly accepted scope boundary, not fixed by r4.
- **L3:** reference data loading remains the later data patch.
- **L4:** retirement of the legacy columns remains separate work.
- **L5:** bill-line evidence and base enforcement remain the money stream's work; this patch does not claim to implement them.
- **L6:** the accepted pre-go-live evidence policy remains. Probe 00 retains the refusal tests for unavailable recorded state. Backfill is an approximation, not recovered state history.
- **L7:** the new text discloses silent differences between an original live read and a later replay, and distinguishes them from ambiguity refusals. It no longer promises “never mis-answers” relative to what the bill actually saw. Its remedy relies on bill evidence/settled writers and is not newly supplied by r4. This meets the November 22 decision; it does not independently block.

One stale description remains: `tax-design.md` §2.5 says a rebill must see the jurisdictions the original bill saw, and battery M6 labels its result “as a bill then saw them.” The newer decision and function comment control this review. Align those descriptions so they do not revive the old replay guarantee.

## Probe handoff — predicted, not executed

`codex-r4-probes/00-battery-and-boundaries.sql` contains the frozen r4 battery with a SQLSTATE/message RAISE NOTICE added to **every** caught-error handler, followed by the supplemental distance and succession controls described above. Original battery assertions are retained. Expected result: all assertions pass.

Run as owner, independently on a fresh clone of `tally` with frozen r4 applied and TEMP revoked from PUBLIC, tally_app and tally_core, using ON_ERROR_STOP. It creates/alters no role and ends in ROLLBACK. Owner-only fixture edits are explicitly labelled and guards are restored before the supplementary reads. This is a planted-state probe, not a two-session race reproduction.

**Author execution record: pending.** No database outcome in this review is marked executed by Codex. Append actual probe output and distinguish setup failures from assertion failures.

---

## Author execution record (2026-11-22)

Fresh clone of `tally` (TEMP revoked), frozen r4 strict-applied (clean). `00-battery-and-boundaries.sql` run as owner with ON_ERROR_STOP: exit 0, `battery-30: all checks passed`, then `codex-r4: all battery and supplementary checks passed`. Every predicted supplementary control held (NULL against 4 miles refused; agreeing 4-mile and agreeing NULL distances answered once; the successor boundary on both days). The probe's setup and assertions all passed; no setup failure.
