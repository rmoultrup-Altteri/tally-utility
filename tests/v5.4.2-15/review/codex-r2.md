# Codex independent review — v5.4.2-15 rewrite, round 2

**Verdict: not yet.** Three blocking findings: incomplete mapped-class tariff coverage, missing-law acceptance for categoryless rates, and instalment completeness bypass after an early constraint check.

Source-only review, as requested. I did not access Docker or execute PostgreSQL, the battery, migration tests, mutations or races. All database outcomes below are **predictions**, not observed results. The three self-contained probes in `codex-r2-probes/` exercise the findings as `tally_app` with `SET LOCAL app.user_id`, after owner-only fixture setup. Each has one transaction ending in `ROLLBACK`, no external helper dependency, and `RAISE NOTICE 'PROBE NN: ...'` expected/actual reporting. Run each separately as the clone owner with `psql -X -q -At -f <file>`. Setup errors stop execution; target refusals report SQLSTATE and message. An unexpected setup/permission refusal does not confirm the intended guard.

Local checks verified the probe transaction/role markers and parsed their embedded JSON. PostgreSQL execution remains untested; Python JSON Schema validation was unavailable because `jsonschema` is not installed.

Both frozen MD5 hashes match the brief:

- Patch: `edb410da0fffe721ac499e5607cc8a61`.
- Battery: `4512683f6e9c9847353481883a09d1b3`.

References: **P** = `tests/v5.4.2-15/review/patch-15r-frozen-r2.sql`; **B** = `tests/v5.4.2-15/review/battery-15r-frozen-r2.sql`; **T** = `sql/v5.4.2-17-rule-terms-convention.sql`; **M** = `tests/v5.4.2-15/mutations-15r.py`; **G** = `tests/v5.4.2-15/migration-15r.py`. Line numbers refer to those files.

## Blocking

### B1 — One matching law row still substitutes for coverage of the tariff's entire range

**Locations:** P:3446–3450; T:2180–2184, T:2204–2223, T:2247–2253.

Round-one B1 is only partially fixed. The new comparator refuses zero matching-class rows, but does not require their date ranges to cover the tariff. The template still assembles its coverage from all applicable classes because `tariff_category` and the law's area keys share no column. One matching-class row covering 2020 is enough for the comparator, while residential/non-residential Texas rows supply template coverage for 2021. A tariff spanning both years is consequently predicted to pass even though its mapped class has no law for the second year.

This is a missing-law acceptance at the tariff boundary, not a claim that a deposit can bypass its separate law citation checks. It was explicitly included as the partial-date-gap case in round-one B1 and remains unresolved.

**Probe:** `codex-r2-probes/01-partial-class-coverage.sql`. Registers a synthetic Texas class with law only on `[2020-01-01,2021-01-01)`. Predicted results: tariff wholly inside that interval accepted; tariff extending to 2022 accepted (**bug**); tariff wholly after the law's end refused. Desired: only the first accepted.

**Required change:** establish mapped-class coverage over every applicable profile segment, preserving the template's lock/read handshake. Do not simply union un-clipped law dates across different profile applicability segments. Add both partial-gap and wholly-absent controls.

### B2 — A rate for every category still treats absent law as no floor

**Locations:** P:3674–3677, P:3684–3702, P:3715–3720, P:3772–3776.

The broadened class enumeration fixes the ordering problem when classes have known minimum rates. However, the new missing-law check explicitly requires `p_category IS NOT NULL`. With a valid profile and a registered class but no applicable law, a named-category rate is refused while a categoryless rate skips that check. The minimum-rate loop finds nothing, `v_seen` is already true because a profile exists, and NULL is returned and accepted as no floor.

A categoryless rate reaches the same unknown class. Removing the category cannot turn an unknown floor into a known exemption. This is also inconsistent with the new comment that the rate must clear every class, including categories defined later (P:3674).

**Probe:** `codex-r2-probes/02-categoryless-unknown-law.sql`. Creates a fictional state, one class, a profile and an application-owned category, with no law rows. Predicted: named-category zero rate refused; categoryless zero rate accepted (**bug**). Desired: both refused for missing law. No published-rate fixture is needed, so a missing publication cannot mask this case.

**Required change:** establish applicable law for every class the rate reaches before aggregating minimum values. Keep explicit nonbinding/reference/delegated law distinct from missing law. Test an entirely lawless profile and a mixture of known and unknown classes.

### B3 — An extra instalment can be appended after the completeness check has fired

**Locations:** P:4244–4258, P:4288–4295, P:4302–4305; B:882–885, B:894–917.

The tariff fallback fixes the original two-part-schedule rejection. But completeness is queued only by **AFTER INSERT on deposits**. In the deposit's transaction, a writer can insert a valid deposit and schedule, run `SET CONSTRAINTS ALL IMMEDIATE`, then append another instalment. The child insert checks transaction identity, whether the deposit was taken in instalments, and date; it does not requeue or perform the aggregate check. The already-consumed parent trigger has no reason to run again.

Thus a 100 principal with 50 received and one 50 instalment can gain another 10 instalment: three parts totaling 110, against a two-part schedule and a principal of 100. This is record arithmetic, within the database's explicit contract, not a request to evaluate schedule fractions or legal eligibility in triggers. Event receipts remain separately bounded by principal (P:4886–4890); that does not repair the contradictory stored schedule.

**Probe:** `codex-r2-probes/03-instalments-after-check.sql`. The valid municipal/tariff pair must first pass the initial immediate check. It then attempts the extra child insert and forces constraints again. Predicted: extra insert accepted; final notices report three parts totaling 110 (**bug**). Desired: refusal, leaving two parts totaling 100.

**Required change:** schedule aggregate validation on child insertion as well as parent insertion, so every later mutation creates a check even after an earlier flush. Preserve deferred construction of a valid schedule and the prohibition on adding children in a later transaction. Add a regression for the exact `insert → flush → append → flush` sequence; the current helper always appends all children before its one flush.

## Should-fix

### S1 — Comparator and cap arithmetic branches still lack targeted evidence

**Locations:** P:3468–3473, P:3495–3496, P:4103–4109; B:519–567, B:707–726, B:1246–1256; M:86–94, M:207–238.

Round-one S2 is partly fixed: N19–N24 and M114–M118 now explicitly cover matched-count thresholds, flags, windows and incomparable conditions. The mutation inventory still does not target the equal-value strict/inclusive ratio distinction or lesser/greater aggregation. The new recorded-cap battery cases use the annual-fraction example; they do not independently exercise the fixed-amount and months branches of `v_stat`.

Add law/tariff pairs on both sides of these boundaries, including a mixed convertible/nonconvertible cap. Mutate the strict/inclusive clause and min/max selection independently. Test exact/elevated recorded caps for fixed and monthly parts, and law-schedule precedence over a differently sized tariff schedule (P:4289). This finding is about absent targeted cases in source; I did not run a mutation or observe a survivor. Top should-fix after the three blocking regressions.

### S2 — Migration preservation assertions still overstate what they prove

**Locations:** G:145–164, G:167–175, G:195, G:205–213, G:233; P:4308–4309.

Round-one S3's preservation issue remains: `now.get(k)` conflates an absent key with a surviving NULL value. The patch drops two columns, while P1b still claims every old column survives. Require key presence for retained fields and an explicit allowlist/disposition for removed fields; clarify handling of non-NULL old values. P1f still checks only nonzero exit status, not that the legacy-accrual guard caused the refusal. `untouched()` checks selected sentinels, so “exactly as it was” remains stronger than its assertion.

The rerun *implementation* is repaired by the outer psql conditional (P:64–68); do not carry forward the old claim that a DO-block RETURN leaves later DDL executing. G:209's limited data fingerprint is still weaker evidence than checking that a later function definition is preserved, but source now shows that DDL is skipped. These are source-level test limitations and require no database reproduction to establish.

## Notes: disposition of the reported fixes and decisions

| Area | Round-two source assessment |
|---|---|
| Rate-floor ordering | P:3674–3677 enumerates every registered class rather than current category mappings. F17–F19 at B:698–702 and M123–M124 at M:221–224 address the reported ordering and named-category cases. Missing-law handling remains B2 above. |
| Amount comparison | P:3475–3483 now refuses highest-bill and minimum-amount tariffs where an average-month bound was derived. P:3452–3454 refuses amounts against an unruled initial cap. This addresses round-one B2's lost fields within the stated comparable shape. Fixed/nonconvertible comparisons remain expressly limited at P:3415–3417. |
| Count comparison | P:3500–3518 compares threshold, window length, consecutive and disputed flags; different incomparable conditions produce a problem. Equal combined conditions are permitted by JSON equality. This addresses round-one B3 within the documented scope. |
| Duplicate guards / excess return | P:3065–3073 and P:3383–3387 contain the new structural refusals. Round-one S1's order-dependent duplicate guards are addressed on both document sides. |
| Recorded statutory cap | P:4077–4117 requires a tariff citation for a tariff source and records the statutory component/basis whenever the cited document caps the deposit. Fraction, monthly and fixed values feed the new upper-bound comparison. The guard no longer depends on the cap being labeled statutory. Choosing the governing part and establishing real-world billing inputs remain core responsibilities, not newly claimed database proofs. |
| Instalment fallback | P:4289–4291 chooses a nonempty law schedule, otherwise the cited tariff schedule. Round-one B4's lookup defect is addressed; aggregate integrity still has B3 above. P:4301's function comment should be updated: it still describes only a law schedule. |
| Migration precondition | P:85–97 explicitly requires superuser **or BYPASSRLS**, and counts existing interest accruals alongside deposits, waivers and rates. G:215–233 adds real-data rerun and accrual precondition cases. The brief's “refuses a non-superuser owner” is too broad: a non-superuser with BYPASSRLS passes this particular role check; ordinary non-bypass owners are refused. No claim here that the entire migration was tested under either role. |
| Rerun | P:64–68 and P:5151 implement a psql-level skip around the patch. Its marker is the existence of both tables, not verification of registration/version. Treat this as a completed-install rerun guard, not a repair mechanism for an arbitrary preexisting partial schema. |
| Grandfathering | P:3841–3844 expressly allows the deposit's own law after closure, with a shared citation lock at P:3868–3872. Successor citations still require the applicable span. This is consistent with the supplied grandfathering decision; no new blocker on that interpretation. |
| Voluntary partial return | The optional due-row checks start at P:4836. The stated decision at P:5104–5106 is consistent with permitting a voluntary return without a due determination. It does not establish that a statutory obligation was evaluated or settled. When a due row is cited, the existing identity/live/date/amount checks remain at P:4837–4865. I do not elevate this policy choice into a blocking schema defect. |
| Deferred scope | Count event vocabulary and the AC-24/25 rewrite remain deferred, as the brief says. P:5141–5145 explicitly ties those contract updates to the mirror commit. Neither justifies treating this unmirrored patch as already integrated. |

The diff leaves the cited-record locking, close-floor union (P:2961–2966), tenant checks (P:3361–3373), rate lock/settled-accrual check (P:3743–3770), and event chronology guards unchanged apart from the stated fixes. I found no additional source-backed blocker in those paths during this round. The existing race and cross-transaction scripts remain runtime evidence for the maintainer to execute; this review does not certify concurrency from a single-transaction probe.

**Disposition:** resolve B1–B3, run the three supplied probes on the frozen clone to confirm the predictions, and retain their positive controls as regressions. Only this report and `codex-r2-probes/` were changed in the repository.
