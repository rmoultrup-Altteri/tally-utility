# Codex independent review — v5.4.2-15 rewrite, round 1

**Verdict: not yet.** Four blocking findings: missing mapped-class law coverage, incomplete amount comparison, incomplete count-condition comparison, and an unusable tariff instalment schedule. The first three accept records under claims their guards do not establish; the fourth rejects an explicitly supported tariff feature.

Review method: source only, as requested. No Docker, database, migration, battery, mutation runner, or race test was executed. Database outcomes below are predictions from source, **not observed results**. Five self-contained probes accompany this report in `tests/v5.4.2-15/review/codex-r1-probes/`; each sets up disposable fixtures as the clone owner, exercises the relevant writes as `tally_app` with `SET LOCAL app.user_id`, reports expected and actual outcomes using `RAISE NOTICE 'PROBE NN: ...'`, and ends its sole transaction with `ROLLBACK`. Run each separately on a clone of the frozen patch using `psql -X -q -At -f <probe>`. Setup errors stop the script; target-write exceptions are reported, including SQLSTATE. No battery helper is required.

Both supplied MD5 hashes match:

- `tests/v5.4.2-15/review/patch-15r-frozen-r1.sql`: `988d73eff960db25d503cc2a39d10f3a`.
- `tests/v5.4.2-15/review/battery-15r-frozen-r1.sql`: `595ee401f0cfbc0d9c26f4013a155163`.

The two embedded `$schema$` texts match their committed schema files verbatim apart from surrounding whitespace, and as parsed JSON. Local JSON Schema validation passed for all 17 existing example/fixture documents and all 14 JSON documents embedded in the probes. This is a format check, not PostgreSQL validation or a legal-source verification.

For concise references below, **P** means `tests/v5.4.2-15/review/patch-15r-frozen-r1.sql`, **T** means `sql/v5.4.2-17-rule-terms-convention.sql`, and **B** means `tests/v5.4.2-15/review/battery-15r-frozen-r1.sql`. All line numbers refer to these exact files.

## Blocking

### B1 — An unrelated class supplies tariff coverage; absent rate law becomes “no floor”

**Locations:** P:3504, P:3407–3416; T:2180–2185, T:2216–2225, T:2246–2253; P:3620–3651.

The tariff registration deliberately shares no area-key column with the law table (`tariff_category` versus `customer_class,basis`). The template therefore builds its coverage multirange from **every** applicable law class and basis. `deposit_tariff_compare` subsequently filters rows to the category's mapped class, but never establishes coverage for that class. If that filter produces zero rows, the comparator returns an empty problem list. Existing residential/non-residential Texas law can thus supply “coverage” for a newly registered class that has no law at all. A partial date gap in the mapped class has the same structural problem.

The rate side has an analogous distinction missing: `v_seen` tracks a service profile, not a law row. The query already filters out everything except binding minimum-interest law, and returns NULL both for an explicit delegation/reference and for **no law for the selected class**. `enforce_deposit_interest_rate` then accepts the row because only a non-NULL floor is compared (P:3703–3708). The comment at P:3656 explicitly acknowledges “no law row” as a no-floor case; that conflicts with standing decision 2.

**Impact:** unknown law becomes permission at two write boundaries. This does not prove a deposit itself can bypass `rule_law_row_cite`; that later lookup remains a separate guard. It does disprove that the stored tariff/rate was accepted against known applicable law.

**Probe:** `01-unknown-class-coverage.sql`. Registers a synthetic Texas class with no law, maps an application-owned category to it, then attempts a tariff and a zero rate. Expected frozen result: both accepted. Desired result: missing-law refusal. The synthetic class is platform setup, not an application privilege escalation.

**Change:** establish coverage after mapping the category, for the relevant class and dates, before comparing content. For rates, distinguish explicit nonbinding law/delegation from a missing law determination. Do not infer coverage from another class or a surviving unrelated basis.

### B2 — “Months” comparison silently equates highest billing with average billing and ignores a monetary minimum

**Locations:** P:3418–3444; `law/deposit/deposit_tariff.v1.schema.json`:644–656; P:3866–3878, P:4022–4026; B:497–506, B:522.

`deposit_tariff_compare` reads only `amount.strategy` and `amount.months`. It never reads `amount.of` or `amount.minimum_amount`. The schema explicitly permits `highest` and a minimum monetary amount, so two highest months and two average months receive the same answer against the Texas one-sixth-annual cap. Likewise two average months with a minimum of 5,000 receive the same answer as two average months without a minimum.

Concrete counterexample: average monthly billing 100 and highest monthly billing 300 give an annual-fraction cap of 200, while two highest months demand 600. A 5,000 minimum is also above 200. The numeric month count being equal is not evidence that either tariff is no looser.

The comment that a deposit's recorded cap check protects this case is insufficient: the CHECK compares principal with the **recorded** cap, and the tariff-source branch only requires a tariff citation. It does not independently establish that the recorded cap conforms to law. That separation is intentional for core calculations (P:4991–4996); the fix belongs at the claimed tariff-comparison boundary, not in a new deposit-law evaluator.

**Probe:** `02-tariff-amount-basis.sql`: four application writes. Expected: two average months accepted; two highest months accepted; two average months with minimum 5,000 accepted; three average months refused. The middle two expose the gap, with controls on both sides of the existing numeric boundary.

**Change:** require comparable bases and account for the minimum, or explicitly refuse/route an unprovable comparison. Do not certify these shapes as equivalent solely from the month number. The documented omission of fixed-amount comparisons (P:5024–5030) does not describe this silent loss of fields within a shape the comparator claims to compare.

### B3 — Count triggers can remove protections while passing the same-measure comparison

**Locations:** P:3453–3460; `law/deposit/deposit_tariff.v1.schema.json`:78–118; `tests/v5.4.2-15/mutations-15r.py`:91–94.

For count conditions, the comparator checks kind, event and window equality, then only whether `at_least` is smaller. It ignores `consecutive` and `exclude_disputed`. A tariff requiring two NSF events anywhere in twelve months passes against a law requiring two consecutive NSF events. A tariff counting disputed bills also passes against one excluding them. These are simple count conditions on precisely the same event/window, within the comparator's stated scope, not the expressly deferred combined-condition case.

**Probe:** `03-count-trigger-restrictions.sql`. A synthetic class has a count trigger with both restrictions true. As `tally_app`, write the identical trigger, one with only `consecutive=false`, one with only `exclude_disputed=false`, and a one-event threshold control. Expected: first three accepted, last refused. Desired: identical accepted and all three relaxations refused.

**Change:** include the protection flags in the partial order for comparable count conditions; where comparison cannot be established, make that explicit. Add independent negative cases for each flag and a positive equal/stricter boundary. Comparing an entire condition's meaning here is the existing comparator's job; evaluating a customer's history remains the core's.

### B4 — Deposits cannot use the instalment schedule stored in their tariff

**Locations:** P:4199–4213; P:4000–4005; `law/deposit/deposit_tariff.v1.schema.json`:30–36; `law/deposit/examples/deposit_tariff.iou_residential.yaml`:13–15.

`enforce_deposit_instalments_complete` obtains `v_doc_n` only from `deposit_rules` using `NEW.rule_id`. It never reads `NEW.tariff_id`. A delegated law document has no instalments, so its derived schedule length is zero. A valid two-part tariff schedule therefore cannot be used: the deposit plus one remaining instalment gives `v_n + 1 = 2`, which is compared with zero and refused when constraints run.

This affects the explicitly supported municipal tariff path, and also the committed investor-owned tariff example, which offers two instalments while the seeded Texas law has an empty schedule. It is a representational/write-path inconsistency, not a request to compute legal instalment entitlements in SQL.

**Probe:** `04-delegated-tariff-instalments.sql`. Creates a municipal profile, a valid two-part tariff, a deposit citing the delegation and tariff, and its one remaining instalment. Forces deferred constraints before rollback. Expected frozen result: refusal stating the law's schedule has zero instalments. Desired result: acceptance of the coherent tariff-backed schedule.

**Change:** record/resolve which cited document governs the schedule and validate completeness against it. Preserve the transaction-completeness and total-principal checks. Add a positive case using a tariff schedule under a delegation and one under law with no statutory schedule.

## Should-fix

### S1 — Duplicate guard kinds make comparison depend on array order

**Locations:** P:3463–3466, P:3342–3371, P:2983–3091; `law/deposit/deposit_tariff.v1.schema.json`:391; `law/deposit/deposit.v1.schema.json`:646.

The guard arrays permit two `payment_due_days` objects with different values. Neither area insert check enforces one guard of a kind. The comparator's non-STRICT `SELECT INTO` chooses one matching value, with no aggregation or ambiguity refusal. `[2 days, 1 day]` can therefore produce a different tariff comparison from `[1 day, 2 days]`. The template's component-ID uniqueness rule (T:878–888) does not address this: guard objects have no component ID.

**Probe:** `05-duplicate-payment-guards.sql`. Expected: a single two-day guard accepted, duplicate guards with two days first accepted, reversed order refused by the fewer-days comparison. The desired outcome for either duplicate arrangement is structural refusal, not choosing which contradictory value should govern.

Enforce uniqueness of guard kind in both law and tariff documents. This is a document-coherence check, independent of legal evaluation.

### S2 — The tests leave important advertised comparison branches unproved

**Locations:** B:497–537; `tests/v5.4.2-15/mutations-15r.py`:86–94; P:3430–3437, P:3448–3460.

The N block tests average-month caps, ratio thresholds and payment days. Its “highest with minimum” positive case is non-residential, where no cap applies (B:522). Its count example is a trigger the law does not name (B:516–518), so it cannot exercise the matched-count comparison. The listed comparator mutations M21–M28 do not mutate the matched-count threshold, equal-threshold strict/inclusive ratio distinction, or lesser/greater aggregation logic. This is a concrete guard the 110-mutation inventory misses: changing the comparison at P:3455 from `<` to `>` is not among the listed mutations.

Add dedicated law/tariff pairs and independent refusal/acceptance cases for those branches, plus probes 01–05 as regressions. Document tests cover shape, not table-hook behavior. I did not execute a new mutation and do not claim an observed survivor; the coverage gap above is from the test source.

### S3 — Migration preservation and “nothing to do” assertions are narrower than their labels

**Locations:** `tests/v5.4.2-15/migration-15r.py`:141–156, 162–168, 198–206; P:79–81, P:4222–4223.

`unchanged()` uses `now.get(k)`, so a removed column and a surviving NULL column compare equal. The patch drops `refund_eligibility_on` and `cap_basis_annual_billing`; the fixture leaves them NULL. Thus P1b's “every column it had” assertion does not prove column preservation. Require key presence, and explicitly specify which obsolete columns may be removed and how any non-NULL legacy values are handled.

P1f merely checks nonzero exit status and supplies no law/rate IDs; it cannot by itself prove that the intended legacy-accrual guard caused the refusal. P2 fingerprints four old tables plus `deposit_rules`, not tariffs, registries, grants or schema objects. The patch's early `RETURN` exits only its initial DO block; the rest of the patch still contains DDL. P3–P5's `untouched()` checks a small set of sentinels, not an exact before/after database snapshot.

These are source-level limitations in what the tests prove, not claims that a database run failed. Tighten the labels or assertions, include guard-specific error checks, and distinguish data idempotence from a true skipped rerun.

## Notes and reviewed boundaries

- **Migration/template:** P:62 and P:5050 bracket the patch in one transaction; P:74–91 checks prerequisites and existing business rows. Law and tariff registration use the template hooks at P:3140 and P:3501; the Texas rows go through `rule_row_seed` in P:3174–3230. The precondition itself contains no explicit all-tenant visibility assertion. The migration runner always uses the owner connection (`migration-15r.py`:63–78), so it does not prove behavior for a non-superuser owner under forced RLS. That remains an unverified deployment boundary, not a claimed reproduction of data loss. The template explicitly requires superuser/BYPASSRLS visibility for law closes (T:2283–2293).
- **Law hooks:** P:2995–3034 checks cap cardinality/kind ordering and instalment sums/order; P:3037–3087 checks trigger/reason uniqueness, waiver references, disqualifiers and published-name registration/by-hold order. Global component-ID uniqueness is already in T:878–888; I did not misclassify its absence in the area hooks as a defect. Non-Texas fixtures are schema examples, not seeded law; acceptance by a JSON validator is not proof their external vocabulary/parameter references are registered.
- **Tenant and tariff history:** P:3343–3347 performs the pre-RLS tenant check with invoker rights; there is no SECURITY DEFINER elevation in that hook. Category edits/deletes are explicitly refused (P:3277–3284). Template history permits only a stamped close and uses a tariff close floor (P:3317–3326; T:2285–2309). These are relevant defenses against remapping, overlapping successors and other-tenant writes; the coverage defect B1 occurs even for an authorized utility writing its own category.
- **Floors:** The fixed minimum, maximum of main/by-hold published values, reference-rate omission and profile owner/system/jurisdiction predicates are explicit at P:3620–3644. Published values are read on the supplied date at P:3575–3586. Rate writes require READ COMMITTED and take the exclusive tenant/state/service lock before reading settled accruals (P:3675–3703); accruals take that key shared (P:4831–4833). Those source checks do not replace a race run. Which preexisting rate an accrual chooses is deliberately left to the core (P:4809–4812).
- **Citations and close floor:** P:2953–2960 includes deposits, event period ends/effective dates, and due dates. P:3771–3782 explicitly permits the deposit's original law after closure; P:3801–3806 takes its shared lock without requiring it still be in force. Successor citations go through the template at both endpoints. I treated grandfathering as the stated decision, not as a range-bypass defect. Closing-role visibility is supplied by T:2289–2293; the area function is invoker-rights.
- **Due/events:** Due insertion and withdrawal both lock and write a deposit-row version (P:4388–4395, P:4575–4577); event projection also writes that row (P:4944–4956). Evidence requires the due transaction, the cited component/reason/instrument, correct customer and date range (P:4491–4550). The owed view is security-invoker (P:4614). I found no additional source-backed blocking defect in these paths, but did not execute the concurrency or tenant-isolation scripts.
- **Compatibility and scope:** The old view/functions are explicitly dropped at P:4965–4970. `sql/tu.sql`:18021, 18043, 18284, 18315 and its old event body at 18482 still represent the pre-patch consumers; that is consistent with reviewing an unmirrored migration, not evidence that the patch has been integrated into the bootstrap. Core-only writers and waiver-determination redesign are expressly deferred at P:5015–5022. Cap recomputation, waiver eligibility, interest calculation and evidence completeness are core responsibilities (P:4991–4996, P:5032–5036); no finding asks to move them into deposit/event triggers.

**Disposition:** resolve B1–B4 and run the supplied probes on the frozen clone before accepting this round. S1 is the top additional structural fix; S2 and S3 should strengthen the evidence accompanying the next review. No repository file outside this report and its probe directory was modified by this review.
