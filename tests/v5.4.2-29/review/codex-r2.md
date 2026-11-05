# Codex — v5.4.2-29, round 2

Verdict: **not yet**.

This is my first review of this patch. **Executed** means a source inspection or file-only check actually performed; **predicted** means database behavior inferred from source, awaiting the author's probes. No database test was executed. I did not run docker, psql, ci.sh, reapply-29.sh, or the mutation runner, and did not read opus-r1.md or fable-r1.md.

## B1 — predicted: the Texas state lookup breaks historical replay after state succession

Location: `patch-29-frozen-r2.sql:105–109`, especially `p.effective_to IS NULL` at line 106.

The county and fact lookups now ask which row was in force on 1900-01-01, but the state lookup still asks for an **open** state that began by that date. A later close and successor of Texas leaves the old state in force on 1900, with the original counties still correctly parented to that historical ID. The old state fails the open predicate; its successor fails `effective_from <= c_from`. The patch therefore refuses before reaching its historical county checks.

Concrete path: on the post-patch scratch clone, close the Texas hierarchy's facts, close children before their parent, then insert state/child/fact successors from 2027. Use the ordinary triggers throughout. Reapply frozen r2. Predicted result: SQLSTATE `P0001`, message `v5.4.2-29 precondition: no open Texas state place in force from 1900-01-01`. None of the 1900 county identities, names, parents, or zones has changed. This is the state-successor case the brief explicitly asks to check. It contradicts the header's “everything is judged as of 1900” rule and leaves a hole in the replay-after-successors fix. It is a deployment/replay failure, not a claim of incorrect initial county data.

Probe: [02-state-successor.sql](codex-r2-probes/02-state-successor.sql). It distinguishes setup failures from the target refusal, prints SQLSTATE and message, compares complete place/fact fingerprints, and includes a control changing only the state selection to historical range containment. The control is predicted to accept without changing stored rows. Setup does not bypass any guard. If the clone has tenant citations that prevent the legal closes, the probe stops as SETUP FAILURE rather than reporting B1 as reproduced.

Fix: select the Texas state in force on `c_from`, using the same range predicate as the counties; retain historical parent comparison against that ID. Update the precondition wording and add the state-successor regression. A closed parent should still prevent genuinely new open children through the existing containment guard; a complete historical replay should not require such an insert.

Schema evidence inspected: `sql/tu.sql:26335–26429` (parent containment, close dependencies, close/successor discipline), `26287–26289` (identity exclusion), `27295–27300` (state succession after closing profiles). This is not a newly introduced regression from r1; it is an incompletely removed “open” assumption in the r2 remedy.

## S1 — executed source finding; database outcome predicted: N14/N15 still need an acceptance assertion

Location: `mutations-29-frozen-r2.sh:34–36,100–105`; `reapply-29-frozen-r2.sh:38–41`.

The RE branch extracts only the first `FAIL Pn` label. P1/P2 produce that label both when a bad load is accepted and when it refuses for an unexpected reason. Consequently, the runner does not itself establish the new N14/N15 claim that removing both comparisons **admits** the load. A malformed SQL mutation that errors at P1 can also look like a successful N14 catch. The brief records a manual exit-0 check for N14; that is useful author evidence, but not a durable assertion in this runner, and I did not reproduce it.

The actual r2 edits are logically targeted: N14 removes both name comparisons and N15 both zone comparisons. I predict the intended admission, not an actual wrong-reason catch for these two supplied mutants. [03-refusals-and-mutations.sql](codex-r2-probes/03-refusals-and-mutations.sql) directly requires acceptance of both, and separately requires postcondition refusal with only the diagnostic comparison removed.

Should fix: encode an acceptance-required outcome for these mutations, or preserve/check the underlying apply status in P1/P2. Keep N6–N8/N12 explicitly described as diagnostic/message coverage. N17 likewise tests the custom refusal rather than proving that the overlap guard would otherwise admit the row; its present label correctly says “not refused by the load.”

## S2 — executed source finding: the second CI marker read can still skip silently

Location: `tests/ci.sh:168`, also visible in `older-tests-29-r1-to-r2.diff`.

The first pending-marker read at lines 112–113 now validates `t|f`, closing the initial-loop failure case. The later load-rules gate independently calls `q tally` again and compares its stdout directly to `t`. A failed second call or any unexpected output makes that condition false and skips the reapply test without recording a failed step. Thus the fix is narrower than the claim that a marker error always stops the run.

Should fix: preserve the validated -29 pending result for both decisions, or give the second read the same status/value validation. This is a shell-control-flow finding; CI was only read, not run. No database behavior is asserted here.

## S3 — executed source finding; database outcome predicted: make P8 prove a no-op

Location: `reapply-29-frozen-r2.sh:84–109`.

P8 changes the row identities/ranges but retains the same county name and zone value; its final assertion is successful exit plus the patch's own “0 counties loaded” notice. It does not compare the data before and after replay. That is narrower than an independent proof that corrections were preserved without any write.

Should fix: include a genuinely different successor name/zone and compare complete relevant rows before and after. Also cover a county closed before today without a successor. [01-baseline-and-county-corrections.sql](codex-r2-probes/01-baseline-and-county-corrections.sql) supplies all three, plus a new later county. Predicted: frozen r2 leaves every place/fact column unchanged in those county-only cases.

## N1 — executed: frozen integrity and source data

All eight MD5s were checked **before** reviewing the patch, and all matched:

| File | Verified MD5 |
|---|---|
| patch-29-frozen-r2.sql | 0d0f118056684d942417493a46f6b43d |
| battery-29-frozen-r2.sql | c33a30571096b7254a227d38e46596d3 |
| reapply-29-frozen-r2.sh | 521fc0d02ca0c884dceaa30b81bc3a98 |
| source-check-29-frozen-r2.sh | efb33dd9c856e70e4c10ef893a8e4449 |
| mutations-29-frozen-r2.sh | c560c150ec066ed896c9bfc0c026875b |
| older-tests-29-frozen-r1.diff | e3deb2d46247209bd18f82a4350acbcc |
| older-tests-29-r1-to-r2.diff | cca76dd90e3ad57384062a4b84bbbbc5 |
| census-st48_tx_cou2020.txt | e1ea7280eb41b680feb924b3bef2c411 |

Executed the one authorized runner:

```text
tests/v5.4.2-29/source-check-29.sh tests/v5.4.2-29/review/patch-29-frozen-r2.sql
PASS S1
PASS S1b
PASS S2
PASS S2b
PASS S3
exit 0
```

The live source checker is byte-identical to its frozen r2 copy. Its parser compares all 254 unique FIPS/name pairs to the pinned Census file; the patch list matches, including spelling/capitalization. Mountain entries are exactly 48141 and 48229; every other entry is America/Chicago. This verifies file content, not a database load. I did not independently re-download the Census file.

Executed source verification of the legal citations: read the local Texas source excerpt and the official eCFR text. Central is east of the §71.7 boundary under [49 CFR 71.6(a)](https://www.ecfr.gov/current/title-49/subtitle-A/part-71/section-71.6); [71.7(e)](https://www.ecfr.gov/current/title-49/subtitle-A/part-71/section-71.7) describes the Texas boundary along Hudspeth's east line; [71.8](https://www.ecfr.gov/current/title-49/subtitle-A/part-71/section-71.8) defines the Mountain side. The county-level assignments, including Culberson as Central, agree with that boundary. The displayed eCFR pages were current through 2026-11-03 (71.6/71.7) and 2026-10-29 (71.8); I did not retrieve a separate 2026-10-01 snapshot. Section 71.7(g)'s municipal exception is real; particular city limits were not verified.

## N2 — executed source assessment of each r2 fix

| Plan item | Assessment |
|---|---|
| S1, as of 1900 | County/fact lookup and postcondition consistently changed to date containment; later-only codes get the explicit refusal. County behavior is predicted in probes 01/03. State selection remains the B1 gap. |
| S2, citations | Closed in source: new Central notes cite 71.6(a) and 71.7(e), Mountain branch adds 71.8, C5 checks the new Central wording and value. |
| S3, diagnostic vs guard | The distinction and dual-layer mutants are present; S1 above asks for durable acceptance evidence, not another change to the patch comparisons. |
| S4, app/core role case | TEMP is explicitly granted and both role cases demand “permission denied for table places.” Predicted reproduction in probe 03. |
| S5, fixture comments | Closed: -16 explains all three stand-ins and corrects the L13 comment. |
| CI marker note | Single expression is implemented; first read is validated; second-read limitation is S2 above. |
| L3/L6/source note additions | Present and within the plan; no unrelated schema or grant change in the patch. |

Read the r2 plan, relevant DECISION-LOG entry, source notes, frozen patch/battery/reapply/mutation files, their r1-to-r2 differences, both older-test diffs, and targeted schema excerpts. No r1 reviewer report was used. The code/name list did not change between r1 and r2. The round-1 fixture moves replace only fixture identities/names, preserve the same test relationships and assertions, and use codes outside the pinned Census set. No older proof was visibly deleted or weakened by those diffs. That is a source assessment, not a passing execution of those older suites.

## N3 — predicted: refusal, partial-state, role and isolation behavior

Probes are the executable specifications for these database predictions:

| Probe | Prediction |
|---|---|
| 01-baseline-and-county-corrections.sql | On the stipulated fresh applied clone: 254 correct county rows with matching facts/citations; a second apply changes no place/fact column; later county/fact corrections, dissolution and a new later code preserve replay. |
| 02-state-successor.sql | The state-successor case refuses as B1; the historical-state control accepts as a no-op. |
| 03-refusals-and-mutations.sql | Wrong name, wrong zone, missing zone, later-only code and an extra 1900 county refuse; late refusal rolls back earlier inserts; matching partial data completes; app/core insert paths fail at places; N14/N15 actually admit. |
| 04-isolation-repeatable-read.sql | Refuses with P0001 and the READ COMMITTED diagnostic. |
| 04-isolation-serializable.sql | Same refusal under SERIALIZABLE. |

All five files run as the owner on a fresh clone with frozen r2 already applied and end in ROLLBACK. All caught errors print SQLSTATE and message through RAISE NOTICE. Each embeds the exact frozen patch, whose embedded MD5 was checked locally. Probe 03 explicitly reconstructs a pre-load fixture by removing only the non-seeded Texas counties/facts with their immutability triggers temporarily disabled; it restores both triggers to ALWAYS **before** any tested write. This is test setup on the disposable clone, not an asserted production transition or permission bypass. No roles are created, dropped or altered. The role test's database TEMP grants are transactional.

The source has no newly introduced SECURITY DEFINER function or privilege grant. Role protection relies on existing table permissions, rather than an explicit owner-name test. Platform place/fact writes are serialized by the existing deployment discipline (`tu.sql` residual R9); the patch does not add concurrency coordination. I found no source-supported application-role bypass. That is not a claim that I executed a race test or exhaustively proved every possible owner-session setup.

The historical closed list is appropriate for replay: it must not reject a new county effective only after 1900. Conversely a code whose only row begins in 1950 is intentionally refused instead of guessed/backdated. An unfamiliar county already in force on 1900 is also intentionally refused. These can be legitimate input histories, but they conflict with this reviewed baseline and need their own migration decision; refusal is safer than silently rewriting them.

## N4 — executed source assessment: limits and regression scope

L1–L6 do not independently block this county-only data patch:

- L1 keeps premise membership as utility data, matching the 2026-11-04 DECISION-LOG ruling.
- L2 chooses the legal county zone; local billing practice is not evidence for changing that legal fact.
- L3 acknowledges the boundary-municipality exception. Do not present the county load as a complete city-level legal map; city limits and their zone facts remain later work.
- L4 explicitly limits this load to counties.
- L5 makes 1900 a modelling baseline, not a historically accurate claim that all 2020 counties existed then. The Census list and current boundary provisions do not establish historical county/time-zone facts for every intervening year.
- L6 explicitly preserves the seeded rows' older citations; new rows receive the improved provenance. Probe 01 checks the new citations; I did not execute a before/after seeded-row audit against an unpatched database.

The r2 historical rule deliberately stops policing current rows during replay. That is the requested correction, not an unintended weakening of a current-data validation contract. Battery C1/C2/C2b/C3 still describe the immediate post-load baseline and are not general invariants after successors; the plan explicitly retains that scope. The database-level baseline checks in probe 01 remain unexecuted.

No new r1 regression was identified from the reviewed diffs. B1 is the remaining replay assumption; S1–S3 concern strength/completeness of verification. I did not reproduce the reported 22 battery passes, 10 reapply passes, 19 mutation catches, or the CI results, and make no independent database claim about the reported unrelated -15 V23 failure.

Only this review and the five probe files were written. The existing untracked codex-r2.log was left alone.

---

## Author's execution of the probes (2026-11-05)

Run by the author as owner, each on its own fresh clone of `tally` (carries -23 and -28; TEMP revoked from PUBLIC, tally_app, tally_core), frozen r2 applied first (exit 0 every time), clone dropped afterwards. Raw output: `codex-r2-probes/results/`.

| Probe | Result |
|---|---|
| 01 baseline and county corrections | all PASS: baseline codes/names, ranges/parents/zones, 252 citations; unchanged replay is a no-op on every column; county corrections, dissolution and a new later county replay as a no-op, preserved byte-for-byte |
| 02 state successor | **B1 reproduced**: setup passed with every guard enabled; frozen r2 refuses `P0001 v5.4.2-29 precondition: no open Texas state place in force from 1900-01-01`; places and facts unchanged; the control (historical state lookup) accepts as a no-op |
| 03 refusals and mutations | all PASS: wrong name, wrong zone, missing zone, later-only code and closed-list guard refuse atomically; N6/N7 with the diagnostic removed refuse at the postcondition; **N14 and N15 are actually admitted** (251 loaded); app and core roles refused `42501 permission denied for table places`; matching partial load completes at 254 |
| 04 repeatable read | PASS: refused, `run under READ COMMITTED (got repeatable read)` |
| 04 serializable | PASS: refused, `run under READ COMMITTED (got serializable)` |

S2 confirmed by reading: `tests/ci.sh:168` re-reads `P29_PENDING` without the `t|f` validation at 112–113.

Disposition: B1 is a patch change (round 3). S1, S2, S3 are test-only and are folded in the same round.
