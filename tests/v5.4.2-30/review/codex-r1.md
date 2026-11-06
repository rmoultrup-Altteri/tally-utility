# Codex — v5.4.2-30, round 1

Verdict: **not yet**.

Source-only review. **Executed** means a source inspection or hash check, never a database execution. **Predicted** means database behavior awaiting the author's probe output. No docker, psql, CI, precondition script, or mutation runner was run. Neither other review was read. All probes are in `codex-r1-probes/`, run independently as owner on fresh clones of `tally` with frozen r1 applied, and end in `ROLLBACK`. Caught errors print SQLSTATE and message with `RAISE NOTICE`. Follow the brief's clone TEMP revocations. No probe creates or alters roles.

## Blocking items

### B1 — predicted: closing a place can strand an approved levy

**Source:** frozen patch lines 284–295 (`tax_levy_insert_check`), 346–350 (`tax_levy_as_of`); `sql/v5.4.2-16-places-and-applicability.sql` lines 498–525 (`enforce_place`), also present in `sql/tu.sql` at the function beginning at line 26335.

Coverage is checked only when inserting the levy. The existing place-close guard enumerates memberships, utility profiles, facts, child places and jurisdictions, but not tax levies. The patch does not extend that guard. The levy lookup does not revalidate place coverage either.

Concrete path: insert an open county and an open levy for it; close the county at July 1 without a successor. The close is predicted to succeed with all guards enabled. The August lookup still returns the levy, although the place rows no longer cover its dates. This is a normal owner/platform close, not a disabled-trigger attack. It defeats the stated whole-range place condition after an initially valid insert.

**Probe:** `01-place-close-and-reused-code.sql`. Expected B1 notices: close accepted; August levy rows `1`; full coverage `false`.

**Fix:** make place maintenance preserve levy coverage as well as existing citations. Accommodate legitimate same-place succession, but require either continued coverage or closure of affected levies. The insertion and place-maintenance paths need a common serialization strategy. A lookup-only filter would hide the orphan rather than preserve the write invariant. Add a regression for the sequential close; L2 does not cover this path.

### B2 — predicted: a later state correction rewrites the historical premise result

**Source:** frozen patch lines 572–594; existing `enforce_service_location_state_vs_places`, -16 lines 885–899.

The four-argument lookup reads `service_locations.state` today, then uses it both to choose the historical state place and to filter historical memberships. The state-change guard ignores voided memberships. Consequently, voiding the old state's memberships and correcting the premise's state is permitted, but changes the answer for an instant before that void/correction.

Concrete path: a TX premise has a county membership known yesterday. Today void that membership and change the premise to NM. Reading yesterday should still recover TX and its county. The function instead selects NM and removes the TX county, even though its own void-time predicate correctly includes the membership as known yesterday. With no known destination state, the historical lookup can instead refuse; the probe uses a known NM state to show the wrong positive result.

**Probe:** `02-historical-premise-state.sql`. Expected same-coordinate output changes from `TX:48996,TX:TX` to `NM:NM`. Only fixture creation stamps are backdated, as in the frozen battery; tested void and state-change operations run with guards enabled.

**Fix:** give the state used by this lookup historical provenance, or enforce a state immutability rule that also protects historical/voided memberships. Include premises with only the automatic state membership when designing the fix. The new recorded-at API cannot promise the original jurisdictions while relying on mutable current state.

## Should-fix items

### S1 — predicted: re-application rejects legitimate post-patch percent facts

**Source:** frozen patch lines 533–539. `$repair30$` refuses any `sales_tax_rate` fact unconditionally. Unlike the version and agency preconditions, it does not distinguish first installation from an already repaired schema. Once a valid 6.25-percent reference fact is loaded, a rerun reports that the facts “are fractions,” even though the vocabulary already says percent.

**Probe:** `03-percent-facts-and-reapply.sql`, S1. It inserts a valid post-patch fact and executes the exact frozen repair precondition, predicting `P0001` with the fraction-precondition message. This isolates the rerun blocker; it does not claim a full second apply was executed.

Make the refusal conditional on actually changing the unit, and verify the already-repaired vocabulary before skipping the repair. Preserve refusal of genuine legacy fraction facts. “Strict apply, twice” on an empty database does not cover this lifecycle.

### S2 — predicted: M3 depends on the age of the source database

**Source:** frozen battery M3 and its setup comment. M3 assumes Texas was recorded less than three days ago and expects an error at `now() - interval '3 days'`. Cloning an older `tally` preserves its creation stamps. The same unchanged patch and battery can therefore fail once that assumption is false. M2 also uses a one-second offset relative to an unplanted state stamp.

**Probe:** `04-battery-time-assumption.sql` reports the TX rows covering the tested day that were known three days ago; a nonzero count contradicts M3's assumed setup. `00-battery-with-error-notices.sql` contains M3 itself.

Use an explicitly planted state creation stamp, or derive the before/after instants from the actual fixture stamps. Do not infer database age from wall-clock time.

### S3 — predicted: code continuity is assumed, not represented

**Source:** frozen patch's `range_agg` predicate; -16 `places_no_overlap` and place insertion rules. The key distinguishes kind, state and code, but has no persistent place identity or explicit successor relationship. Adjacent rows with the same code are treated as one continuous place regardless of their provenance.

**Probe:** the S3 portion of `01-place-close-and-reused-code.sql` adds a differently named county under the released code, then inserts a second utility's levy spanning both rows. Predicted: accepted. Different names alone do not prove different legal places; the important result is the absence of any continuity assertion the database could check.

Document and enforce a platform rule that codes are never reassigned across distinct places, or carry a stable identity/explicit continuity relationship. If the contemplated data source really reuses codes, elevate this to blocking: `range_agg` cannot distinguish reuse from succession. I am not asserting that a particular Comptroller code has been reused.

### S4 — predicted: reference-rate precision and endpoint differ from the design shorthand

**Source:** design §2.4 calls for at most four decimals; frozen patch only changes the reference kind's maximum and text. The inherited fact guard uses an exclusive maximum and does not check decimal precision. The older-test diff explicitly keeps the maximum open at 100, while the levy JSON schema allows 100.

**Probe:** `03-percent-facts-and-reapply.sql`, S4. Predicted: reference facts `6.25` and `6.25001` accepted; `100` rejected with `23514`. Each successful candidate is rolled back inside its exception block, so overlap cannot mask the next check.

Enforce the reference precision promised by §2.4, or explicitly narrow that requirement to levy rows. State the reference interval as `[0,100)` if intentional, rather than implying the same inclusive range as levies. This is not a practical 100-percent sales-tax scenario, but the contract and tests should agree.

## Notes and remaining review answers

### N1 — executed: all frozen hashes match

Checked before other review work:

| Frozen file | MD5 |
|---|---|
| patch | `9076fced7e04fc4f4fbc7eadce8b61c6` |
| battery | `f44fe54786b24633294d9877b1c826e1` |
| mutations | `db66f01041abd5849bdded08186cb0f5` |
| preconditions | `785186e33388dc98d1571f6d1571952e` |
| older-tests diff | `bfaa7b62019e5ef4d68883b627e1fad1` |

### N2 — predicted: ordinary guard paths are substantially covered, not independently proven

**Probe:** `00-battery-with-error-notices.sql` is the frozen battery with added SQLSTATE/message notices in its exception handlers. It preserves its transaction and rollback. It covers the ordinary levy shape, same-key overlap, immutability, tenant isolation, required arguments, close/successor historical reads, comparisons, required version answers, both sequential penalty-guard orders, exemption service matching, membership history and state-agency basis checks.

Source inspection found no additional concrete bypass in those tested paths. The new levy reader uses invoker rights and the registered tariff-table machinery; its creation/end predicates match the corresponding place/membership approach for those timestamps. The `end_as_known` distinction between a row born bounded and one closed later is deliberate. The fact repair restores its guard with `ENABLE ALWAYS` in the same patch transaction, with F1b checking the actual trigger mode. These are predictions to verify with probe 00, not a reproduction of the author's reported passes. B1 and B2 remain outside those fixtures.

### N3 — executed: test and mutation source review

`refuses_at` checks both SQLSTATE and guard/constraint identification, stronger than accepting any error. Q1–Q5 use `ok_q`; N14 intentionally lands at Q3 because seeing the successor too early can cause a cardinality error before Q4. F1b checks `tgenabled = 'A'`, so N5 targets the restoration mode rather than just trigger existence. The mutation script compares the observed label to the named label, including distinct apply/precondition cases. I found no concrete wrong-reason catch in the listed source mutations, but did not execute them or reproduce 33/33.

Important coverage gaps are place-close preservation, current-state dependence of historical reads, reapply after percent facts, code continuity, and reference precision. M1–M5 focus on membership changes; they do not exercise a place's close/successor history directly. The precondition fixtures deliberately bypass guards to plant legacy shapes: they test refusal messages, not a production remediation workflow. The precondition messages report counts, not the affected row IDs despite the header's “names the rows” wording.

The older-test diff explicitly supplies the four version answers, gas on exemption fixtures, and percent reference values. The PSF fixtures set the penalty-base answer false. It adds -30 to the CI apply/check lists. I found no unrelated behavior removal in that diff. This is source assessment, not a claim that earlier batteries still pass; their reported 58/58 remains author evidence.

### N4 — executed: L1–L5 scope assessment

None independently blocks this patch under the stated scope. L1 and the two-column base design are expressly settled by design §2.8. L2 is an acknowledged concurrency limitation, not evidence that the sequential B1 path is acceptable. L3 is a later data load, L4 is a separately scoped retirement, and L5 assigns bill-line enforcement to the money stream. Those limits should remain visible to the consuming application; this review does not certify the later data or billing implementation.

The two blockers concern guarantees this patch claims now: a levy retaining valid place coverage and the new historical premise lookup returning jurisdictions as known then.

## Author execution record

Pending. No database results are attached or claimed. Please append the output of each independent probe and distinguish setup errors from the predicted observation notices before resolving findings.

## Author execution record (2026-11-06, appended by the author)

Run as the owner on `rv30codex`, a fresh clone of `tally` (TEMP revoked) with frozen r1 strict-applied; `psql -X -q -At`, NOTICE lines kept. Full output: `codex-r1-probe-results.txt`. No setup errors.

- **00:** every caught error is the expected guard; the battery's closing notice printed.
- **01, B1 — confirmed:** "place close accepted with an open levy"; "August levy rows=1; full coverage=f".
- **01, S3 — confirmed:** a differently named county under the released code accepted; a levy spanning both rows accepted.
- **02, B2 — confirmed:** same date and recorded instant: before `TX:48996,TX:TX`, after `NM:NM`.
- **03, S4 — confirmed:** 6.25 and 6.25001 accepted as reference facts; 100 refused (23514).
- **03, S1 — confirmed:** the repair's precondition refuses (P0001, "facts exist; their values are fractions") once a valid percent fact exists.
- **04, S2 — confirmed as stated:** Texas rows known three days ago = 0 today; M3 relies on the build being under three days old.
