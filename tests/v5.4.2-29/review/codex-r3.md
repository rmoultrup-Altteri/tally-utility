# Codex — v5.4.2-29, round 3

Verdict: **ready** (source review). No blocking items. One non-blocking test-hardening item remains below.

**Executed** means source inspection or a file-only check performed by this reviewer. **Predicted** means database behavior specified in an accompanying probe, not executed here. The author's r2 results are prior evidence, not my execution. I did not run docker, psql, ci.sh, reapply-29.sh or the mutation runner; I did not read opus-r1.md or fable-r1.md.

## B items — none

**Executed source assessment:** round-2 B1 is addressed exactly at the faulty lookup. Frozen r3 lines 109–114 select Texas by range containment on 1900-01-01 and update the diagnostic. No other executable patch logic changed. The header now explains both complete historical replay and refusal of a new open child under a closed historical parent. There is no unrelated DDL, grant or data-list change.

**Predicted, probes 02 and 05:** after ordinary state/child/fact succession, replay accepts and preserves every places/place_facts column. Restoring the r2 lookup (N18) refuses at the state precondition. With the non-seeded counties absent before succession, the original patch instead reaches the parent containment rule and refuses with SQLSTATE 23514; it does not invent an open child spanning beyond its parent's lifetime. Both cases check complete row fingerprints. This closes the earlier replay defect without weakening the parent rule. Schema source inspected: `sql/tu.sql:26287` (identity exclusion), `26360` (parent containment), and the adjacent close/successor rules.

## S1 — executed source finding: P7 should reject unavailable fingerprints

Location: `reapply-29-frozen-r3.sh:100–105`.

The new P7 comparison requires only `"$d1" = "$d2"`. Neither `fp` assignment's exit status is checked, and two empty outputs compare equal. If both fingerprint commands fail without stdout while the apply/count commands succeed, P7 can print “no row changed” without a fingerprint. This is a shell-control-flow finding, not a database-result claim. It does not establish that the reported author run encountered this failure.

Use checked assignments (`d1=$(fp) || ...`, likewise d2) and require a nonempty digest, or use the existing `noop` helper, which rejects an empty before digest at line 63. Prefer checking command status for all three cases. This is non-blocking: P8/P10 already reject empty fingerprints, and the patch's change itself is narrowly correct. Probe 01 independently specifies the unchanged-replay assertion for the author.

## N1 — executed: integrity and file-only verification

All seven hashes were checked immediately after reading the brief, before patch inspection, and matched:

| Frozen file / source | MD5 |
|---|---|
| patch-29-frozen-r3.sql | a3030b836fce0eeb6609a2464a797362 |
| battery-29-frozen-r3.sql | c33a30571096b7254a227d38e46596d3 |
| reapply-29-frozen-r3.sh | e949fbc171ea4f814f179c55a01e4424 |
| source-check-29-frozen-r3.sh | efb33dd9c856e70e4c10ef893a8e4449 |
| mutations-29-frozen-r3.sh | 7cc5ae564b136f04803dd7a5fe521af6 |
| older-tests-29-r2-to-r3.diff | a2472b325a0a10655bb4cbf7036326a6 |
| census-st48_tx_cou2020.txt | e1ea7280eb41b680feb924b3bef2c411 |

Executed the authorized command:

```
tests/v5.4.2-29/source-check-29.sh tests/v5.4.2-29/review/patch-29-frozen-r3.sql
PASS S1
PASS S1b
PASS S2
PASS S2b
PASS S3
exit 0
```

The live checker equals the frozen r3 checker. The frozen r2/r3 batteries are identical. The patch list matches all 254 unique Census code/name pairs; only 48141 and 48229 are America/Denver and all other entries are America/Chicago. This is file-content verification, not proof of database contents. I did not re-download the Census source.

## N2 — executed: disposition of the r3 plan and test scope

| R3 item | Source disposition |
|---|---|
| B1 | Closed as described above; P10/P10b and N18 cover the two distinct historical-state paths. Runtime predictions are in probes 02/05. |
| S1 | Closed for the requested admission distinction: N14/N15 now require `RE:P1 [admitted]` / `RE:P2 [admitted]`. A mere unexpected refusal no longer satisfies those expectations. N9/N10 also require admission; N16/N18 require refusal. |
| S2 | Closed: the second CI marker read captures stderr and validates exactly `t` or `f` before branching, matching the first-read policy. Other outputs exit 2. CI was not run. |
| S3 | Substantially closed: P7/P8/P10 compare all columns of both tables using sorted JSON row digests. P8 now has a different successor zone/name and a county dissolved before today. P7's empty-output edge is S1 above. |

The mutation outcome parser includes suffix letters, so P10b labels are not truncated to P10. The diagnostic-only mutations still assert the broad category `[refused otherwise]`, not a particular SQLSTATE or fallback guard. That is narrower than independently proving the fallback guard's identity; it is not a new regression or an acceptance claim. Probes 03 explicitly require the postcondition for N6/N7 and successful execution for N14/N15. No source evidence indicates that the supplied N14/N15 are caught for a wrong reason. I did not execute any mutation.

P7 labels all of its failures `[changed]`, even apply failures; no current mutation requires a P7 classification, so this does not affect the newly requested N14/N15 distinction. Battery C checks retain their immediate-post-load scope; they are not claimed as invariants after corrections. The pending marker remains a deployment gate for the stipulated base, not a general validator of arbitrary corrected place histories.

Read the r2/r3 plans, own r2 review including the author's appended results, r2-to-r3 patch/reapply/mutation diffs, older-test diffs, source notes, and the DECISION-LOG's 2026-11-04 -28 r2 ruling. The fixture replacements preserve the earlier test relationships and assertions and avoid the Census codes. R3 changes only the CI marker validation outside -29's own files. No r2 behavior was visibly removed beyond the defective open-Texas condition.

## N3 — executed source assessment: source authority and limits

The county list is right against the pinned Census source. I re-read the official eCFR provisions: [71.6(a)](https://www.ecfr.gov/current/title-49/subtitle-A/part-71/section-71.6) assigns the eastern side of the Central/Mountain boundary to Central; [71.7(e)](https://www.ecfr.gov/current/title-49/subtitle-A/part-71/section-71.7) describes the Texas line through Hudspeth's eastern boundary; [71.8](https://www.ecfr.gov/current/title-49/subtitle-A/part-71/section-71.8) defines the Mountain side. The county assignments, including Culberson as Central, agree with that line. The retrieved pages displayed currency through November 3 (71.6/71.7) and October 29 (71.8), 2026; this is not an independent retrieval of the patch's October 1 snapshot.

L1–L6 do not block this scoped county load:

- L1 leaves premise membership with the utility, expressly required by the DECISION-LOG ruling.
- L2 uses the legal county zone; billing custom does not change the cited boundary.
- L3 defers boundary municipalities. Section 71.7(g) makes that exception real; this patch is not a complete municipal zone map.
- L4 limits the inventory to counties.
- L5 uses 1900 as a modelling baseline. The 2020 Census and modern boundary text do not establish that every listed county existed with these facts in 1900.
- L6 preserves the older seeded citations. The patch source has no update path for those notes; replay preservation and new citations are specified in probe 01.

## N4 — predicted: database claims and author-run probes

Each linked file must run **as owner on its own fresh clone of tally with frozen r3 already applied**. All embed the exact r3 patch (embedded MD5 verified locally), end in ROLLBACK, and print SQLSTATE and message with RAISE NOTICE for caught errors. No probe has been executed by this reviewer.

| Probe | Predicted result / claim |
|---|---|
| [01 baseline and county corrections](codex-r3-probes/01-baseline-and-county-corrections.sql) | Correct baseline codes/names, ranges, parents, zones and new citations; complete no-op on replay, also after county/fact succession, dissolution and a new later county. |
| [02 state successor](codex-r3-probes/02-state-successor.sql) | All normal guards remain enabled for succession. R3 replay is a complete no-op; N18 refuses at the historical-state precondition, atomically. |
| [03 refusals and mutations](codex-r3-probes/03-refusals-and-mutations.sql) | Wrong name/zone, missing zone, later-only code and extra 1900 county refuse atomically; diagnostic removal still reaches the postcondition; dual-layer removal admits; app/core insert paths refuse at places despite TEMP permission; matching partial state completes. |
| [04 repeatable read](codex-r3-probes/04-isolation-repeatable-read.sql) | P0001 with the patch's READ COMMITTED diagnostic. |
| [04 serializable](codex-r3-probes/04-isolation-serializable.sql) | Same explicit isolation refusal. |
| [05 closed parent, partial load](codex-r3-probes/05-closed-parent-partial-load.sql) | After reconstructing the two-county seed and succeeding Texas, insertion under historical Texas refuses with 23514 at parent containment; every place/fact row remains unchanged. |

Probes 03/05 remove only non-seeded county fixtures with immutability triggers temporarily disabled, restore both triggers to ALWAYS before tested writes, and roll everything back. This is disposable-clone setup, not a production transition or privilege bypass. No role is created, dropped or altered. Probe 03's TEMP grants are transactional.

The as-of-1900 identity is the correct replay contract. Later correction/dissolution does not rewrite that baseline. A legitimate history whose only county row starts after 1900, or an extra county already present at that baseline, intentionally conflicts with the load and requires a separate migration decision; probe 03 specifies those refusals. A partially loaded historical state does not justify inventing children outside the selected parent's lifetime; probe 05 covers that boundary.

**Executed source assessment:** no new SECURITY DEFINER function, privilege grant or concurrency mechanism appears. Existing schema comments explicitly require serialized platform migrations (residual R9). I found no additional source-supported bypass within that contract. This is not an exhaustive race proof. Roles, isolation, partial-state and correction predictions are limited to the executable cases above.

I do not claim independent reproduction of the reported 22 battery passes, 12 reapply passes, 20 mutation catches or 54 CI steps. The author's r2 probe results support the prior diagnosis; r3 probe execution remains with the author. Only this review and the six r3 probe files were written; the existing codex-r3.log was left alone.

---

## Author's execution of the probes (2026-11-05)

Each probe run by the author as owner on its own fresh clone of `tally` (with -23 and -28; TEMP revoked from PUBLIC, tally_app, tally_core), frozen r3 applied strictly first (exit 0 each time), clone dropped afterwards. Raw output: `codex-r3-probes/results/`.

| Probe | Result |
|---|---|
| 01 baseline and county corrections | 7 PASS, no failure |
| 02 state successor | 4 PASS, no failure (r3 re-applies as a no-op after Texas is succeeded) |
| 03 refusals and mutations | 18 PASS, no failure |
| 04 repeatable read | 1 PASS |
| 04 serializable | 1 PASS |
| 05 closed parent, partial load | 2 PASS, no failure |

S1 (P7's digests unchecked) is test-only; folded after the other two r3 reviews.
