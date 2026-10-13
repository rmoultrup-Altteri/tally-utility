# Codex independent review — v5.4.2-15 rewrite, round 3

**Verdict: not yet.** Three blocking findings remain: class coverage is not clipped to profile applicability; renamed count triggers can still escape comparison by changing units; and the tariff-cap guard can be bypassed by omitting the cap or its source.

This is a **source-only review**. I did not access Docker, execute PostgreSQL, or run the battery, migration, mutations, fail-first or race suites. Every database outcome below is a **prediction**, not an observed result. Six self-contained probes accompany the report in `tests/v5.4.2-15/review/codex-r3-probes/`. Each runs in one READ COMMITTED transaction ending in ROLLBACK, creates its fixtures as the clone owner, then exercises application writes as `tally_app` with `SET LOCAL app.user_id`. No battery helper is required. Run each separately on the frozen-patch clone with `psql -X -q -At -f <file>`. Notices state expected and actual outcomes, including SQLSTATE/message on refusal. An unrelated fixture, permission or constraint error does **not** confirm the intended refusal; check the positive controls too.

Both frozen MD5 hashes match:

- Patch: `0a13969608d7360dff2ae468a90b86d4`.
- Battery: `0f6ae2ce52c38492ec3fc31ce09b0593`.

Local inspection also found both embedded `$schema$` texts equal to their JSON files, excluding each file's trailing newline. All probe JSON documents parse. Transaction, rollback and role markers were checked. PostgreSQL parsing/execution and JSON Schema validation were unavailable locally. The mutation inventory contains 154 entries; I did not verify the reported 154 kills.

Reference abbreviations below are exact file:line references:

- **P**: `tests/v5.4.2-15/review/patch-15r-frozen-r3.sql`
- **B**: `tests/v5.4.2-15/review/battery-15r-frozen-r3.sql`
- **T**: `sql/v5.4.2-17-rule-terms-convention.sql`
- **M**: `tests/v5.4.2-15/mutations-15r.py`
- **G**: `tests/v5.4.2-15/migration-15r.py`

## Blocking

### B1 — The new class-coverage union counts dates when the selected law does not bind the utility

**Locations:** P:3454–3459; T:2198–2223, T:2247–2253. Regression coverage: B:763–765; M:258.

The comparator now unions the mapped class's law dates, which addresses the previous single-profile partial-gap example. However, it unions the **full effective range** of every law row in `p_law`. The template selected each row because it overlaps at least one applicable utility profile, but appends the original JSON row to `v_rows` (T:2222). Only the template's all-class coverage calculation is clipped to the applicable profile segment (T:2221). The comparator's new class-specific calculation discards that distinction.

Example: the utility is investor-owned during 2020 and cooperative during 2021. A synthetic class has a law row effective throughout 2020–2021 but binding **only investor-owned** utilities. Other Texas classes have cooperative law. A tariff for the synthetic class spanning both years is predicted to pass: other classes supply the template's 2021 coverage, and the synthetic class's investor-owned law supplies the comparator's full two-year range. That class has no applicable law in the cooperative year.

This is the profile-clipping qualification explicitly raised in round-two B1, not a demand to evaluate law in the database. It concerns the tariff's own missing-law admission check; it does not establish a bypass of a deposit's separate law citation lookup.

**Probe:** `01-profile-clipped-coverage.sql`. Expected on frozen r3: before the transition ACCEPTED; entirely after it REFUSED for missing class law; spanning it ACCEPTED (**bug**). Desired: the spanning tariff also refuses. `04-partial-class-coverage.sql` separately rechecks the old single-profile case: covered ACCEPTED, partially uncovered REFUSED, wholly uncovered REFUSED.

**Required fix:** compute mapped-class coverage as the union of `law range ∩ applicable profile range ∩ tariff range`, retaining owner/system/jurisdiction matching and the template's lock/read handshake. Pass clipped applicability spans to the area check, or establish equivalent class-specific coverage within that handshake. Add a profile-transition regression; merely mutating `range_agg` to full coverage does not test clipping.

### B2 — Changing a count trigger's code and window unit makes it disappear from comparison

**Locations:** P:3503–3509, P:3517–3550; B:582–584, B:760–762; M:249–250.

The new matching predicate includes window-unit equality in `v_samemeasure`. Thus, for a count of the **same event**, changing both the trigger code and `window.unit` makes both match flags false. `CONTINUE` skips the threshold, disputed/consecutive protections, payment days and all other guards. The existing incomparable-condition refusal is never reached.

A law counting at least three `late_payment` events within twelve months, with consecutive/disputed protections and two days to pay, can therefore be met by a tariff under another registered code counting one `late_payment` within twelve bills with no protections. The units cannot be compared without further information. The correct conservative result is the same refusal already used for a same-code unit mismatch, rather than treating the event as wholly unregulated. This is not a request to convert bills to months or evaluate customer history.

**Probe:** `02-renamed-count-unit.sql`. Four independent categories vary code and unit: equivalent renamed count ACCEPTED (control); same code/different unit REFUSED as incomparable; different code/same unit with weakened terms REFUSED; different code/different unit with the same weakened terms ACCEPTED (**bug**). Desired: the last refuses as incomparable. Both codes are already registered; the fixture deliberately uses the implementation's stated rule that code spelling does not define what a trigger measures.

**Required fix:** distinguish matching the event from being able to compare its window. Match count triggers by event irrespective of code/unit; require compatible units before numeric comparison, and otherwise refuse as incomparable. Keep guard checks for every matched law trigger. N27 proves the renamed-ratio case only; it cannot establish the count-unit boundary. Deferring a count-event vocabulary does not require leaving this hole.

### B3 — A municipal deposit can bypass the new tariff bound by omitting the cap or its source

**Locations:** P:3966–3976, P:4115–4134, P:4167–4195. Claimed bound: P:5229–5233. Tests: B:1332–1351.

The new bound runs only under `IF NEW.cap_source = 'tariff'`. Two omissions escape it under the municipal delegation:

1. A deposit cites a fixed-100 tariff but records principal 999, cap 999 and **NULL cap_source**. The cap-source CHECK evaluates to NULL, not FALSE: its tariff branch is `cap_amount IS NOT NULL AND cap_source = 'tariff'`. The statutory branch does not rescue the check. The procedural `IF` also does not run for NULL. Principal equals the supplied cap, so the principal/cap check adds no tariff bound.
2. With principal 999 and **all cap fields NULL**, the cap-source CHECK explicitly accepts the empty shape. Only a law document with `cap.strategy = parts` mandates recording a cap. A delegation requires the tariff citation, but not the fixed tariff's cap, so the new arithmetic guard is again skipped.

These are omissions of facts the database says it holds coherent, not disagreements over how the core computes billing. In both cases the tariff is actually cited and has an unambiguous fixed amount. R35 now tests only a fully populated tariff-source record, leaving the guard optional for the same municipal path.

**Probe:** `03-omitted-tariff-cap.sql`. Under the same fixed-100 tariff: principal/cap 100 with tariff source ACCEPTED; 999 with explicit tariff source REFUSED; 999 with NULL source ACCEPTED (**bug**); principal 999 with all cap fields omitted ACCEPTED (**bug**). Desired: only the exact control accepts.

**Required fix:** make the nonempty cap shape require a non-NULL, valid source, rather than relying on nullable equality inside CHECK. Where the cited municipal policy specifies a fixed or computable monthly amount, require the corresponding recorded cap/basis and enforce its bound independently of an optional source label. Preserve the explicitly documented core scope for case-by-case amounts and minimum amounts.

## Should-fix

### S1 — Arithmetic boundary coverage remains incomplete, including the new seasonal branch

**Locations:** P:3480–3485, P:3512–3513, P:4005–4017; B:531–548, B:640, B:1356–1367; M:86–95, M:241–258.

Round-two S1 is partly addressed: R40/R41 and M140 exercise the recorded lesser-of minimum; R42/R43 and M141 exercise highest-bills arithmetic. They do not test the comparator's lesser/greater aggregation, which is a different code path. The frozen battery still has no `greater_than` ratio boundary, no `greater_of` comparator case and no `seasonal_average` case. The mutation list does not independently target the strict/inclusive clause, comparator min/max selection or seasonal multiplication.

Add exact/just-over recorded seasonal caps; equal-threshold strict-versus-inclusive ratio comparisons in both directions; lesser/greater comparisons with convertible parts and a mixed convertible/nonconvertible cap. Retain the new B1–B3 probe cases as regressions, with refusal reasons and positive controls. This is a source-level coverage finding, **not** a claim that I ran a mutant and observed it survive.

### S2 — Function documentation contradicts the new guards

**Locations:** P:3418–3420, P:3559–3560, P:3753–3754, versus P:3546–3550 and P:3710–3725.

The comparator's leading comment and stored function comment still list “other guards” as not compared, although all non-payment law guards must now be carried identically. The stored rate-floor comment still lists “no law row” as a NULL/no-floor outcome, although the new missing-class check raises. Update these alongside R7 so callers do not infer obsolete permissions or exceptions. No database probe is needed to establish these textual contradictions.

## Notes and disposition of the round-two findings

| Finding / changed area | Source assessment for r3 |
|---|---|
| Codex B1 / Fable S1: class date coverage | The zero/partial-date gap check is now present at P:3454–3459; N18/N30/N31 at B:763–767 cover absence, lapse and an inside-range positive case. Probe 04 supplies the previous reproduction with updated expectations. **Incomplete across profile transitions: B1 above.** |
| Codex B2 / Opus S3: categoryless missing law | P:3698–3725 enumerates all registered classes and checks each for applicable law without the former named-category gate. F19/F20 at B:732–736 and M154 at M:257 target it. Probe 05 predicts both named and categoryless lawless rates now refuse. I found no remaining source defect in that particular fix. |
| Codex B3: instalments after a flush | P:4354–4405 extracts the aggregate check and queues it on both parent and child INSERT. M139 at M:241 targets the child path; I6 at B:1321–1324 constructs the early-flush case. Probe 06 predicts the valid two-part 100 schedule passes, the later extra 10 refuses, and two parts totaling 100 remain. Its control records the tariff cap explicitly so it is independent of B3 above. |
| Opus B1: choosing the larger lesser-of part | P:4152–4165 includes the named part plus fixed/same-kind computable parts in a minimum. R40/R41 at B:1356–1361 and M140 at M:242 specifically target the recorded fixed-plus-annual example. The one-basis limitation is stated at P:5227–5229. Do not read this as proof of every part on a different billing basis. No additional blocker asserted for that documented limit. |
| Fable S2: highest/seasonal figures | P:4005–4017 defines highest-bills as the recorded total and seasonal as recorded average times multiple; P:4152 calls it. Highest-bills has R42/R43 and M141. Seasonal still needs S1's targeted tests. |
| Opus B2: renamed usage trigger | P:3505–3515 compares equal ratio measures regardless of code. N27 at B:582–584 and M147 at M:249 target that exact correction. The remaining count matching issue is B2 above. |
| Fable S4: omitted law guards | P:3546–3550 requires exact JSON membership for each non-payment guard. N28 at B:760–762 and M148 at M:250 target an omitted service-age guard. This is conservative structural comparison; see S2 for stale comments. |
| Fable B1 / Opus S1: municipal cap | P:4170–4194 clears unsupported cap components, requires the monthly basis on the explicit tariff-source path and calculates fixed/monthly limits. R35–R39 at B:1332–1351 and M142–M145 at M:244–247 target these branches. **Still bypassable through omission: B3 above.** R44 at B:1368–1370 and M146 at M:248 target statutory source with no law cap. |
| Opus S2: missing targeted mutations | M150–M153 at M:252–256 target successor span equality, the close floor's event branch, tariff instalment fractions and received-instalment bounds. M149 at M:251 targets fractional counts. A20/A22 (B:1018–1024), N29 (B:585–586), I7 (B:1325–1326), R45/R46 (B:1371–1376) provide the associated cases. This verifies their presence and target in source, not the claimed kills. |
| Codex S2: migration preservation / refusal reason | G:163–168 now distinguishes a missing retained column from a surviving NULL and permits the named dropped columns only when their old values were NULL. G:212 now requires the legacy-accrual refusal phrase. The earlier specific defects are addressed. G:151/G:200 still describe every old column as retained, G:172–179 checks selected abort sentinels, and G:214–218 fingerprints selected data rather than all schema objects: these labels should be narrowed, but are not new blocking migration defects. |

The original duplicate-guard fix remains in both insert checks (P:3073–3079 and P:3386–3391); the highest-bill/minimum-amount comparator refusals remain at P:3487–3494. The law-first, tariff-fallback instalment selection remains at P:4369–4372. These are source dispositions of earlier findings, not a new runtime certification.

Migration/template review: the psql skip encloses the transaction (P:67–72 and P:5256–5258); preconditions count non-legacy deposits, waivers, rates and accruals after an explicit superuser/BYPASSRLS test (P:88–105). Law registration and Texas seeding still use the template (P:3160–3168, P:3240–3263). The new round-three changes do not replace the cited-record mutex (P:4904–4905), shared citation locks (P:3898–3902), identity freeze (P:4237–4259) or tenant policies (for example P:4484–4488). I found no additional source-backed blocker in those unchanged paths. Strict installation, rerun behavior, concurrency and non-superuser deployment were not executed by this review. In particular, “non-superuser refused” is too broad: the explicit role predicate also permits BYPASSRLS; it does not prove that such a role has every privilege required to install the patch.

The two policy decisions remain explicit: the deposit's own law row is a separate citable branch from an in-range successor (P:3871–3874); due-row validation is conditional on a citation (P:4935–4965), and voluntary partial-return arithmetic is separate (P:5071–5079). I found no new supplied evidence that resolves Ryan's intent differently from the prior round's interpretation, so I am not creating an approval blocker for either. These statements describe the source branches only. Count-event vocabulary and AC-24/25 mirror work remain deferred; B2 can be fixed without settling the broader vocabulary.

**Disposition:** resolve B1–B3, run the six probes on the frozen clone to confirm or disprove these predictions, then add the demonstrated boundaries to the battery and mutation suite. This review writes only this report and `codex-r3-probes/`; it makes no patch or test-suite edits.
