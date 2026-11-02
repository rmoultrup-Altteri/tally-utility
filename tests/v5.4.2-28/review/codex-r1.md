# Codex — v5.4.2-28, review round 1

Verdict: **not yet**.

**Executed — source review only.** Checked the four hashes immediately after reading the brief, before reviewing patch content. All match:

| Frozen artifact | MD5 |
|---|---|
| patch | `54271dccc92c10057625be74c85c0b33` |
| battery | `93b6aa3dc354f5af28811be055264232` |
| mutations | `c2eb5a80bf073330897bbd9ad6d0a2c0` |
| older-tests diff | `4cb633eaf9cddde75bf0388f8c41401a` |

Read the four Ryan rulings, Kyle K-02/K-03/K-06 context, the three parity rows and CI-101 update, PATCH-LESSONS index and relevant sections, frozen artifacts, and targeted schema definitions. Did not read `opus-r1.md` or `fable-r1.md`. No database execution, Docker, psql, CI, race scripts or mutation runner. The author's reported passes are not my measurements.

All database outcomes below are **predicted**. Probe files are supplied, not executed. Each starts a transaction, runs on an owner-connected fresh clone with frozen r1 applied, and ends in `ROLLBACK`. Role switches exercise ordinary application/core privileges without altering roles. Caught errors print both SQLSTATE and message. An unexpected setup or prerequisite failure invalidates the dependent result; an “accepted” notice alone is not a passing regression assertion.

## Blocking items

### B1 — **Predicted:** a dependency can be closed without a reason

Frozen patch lines 367–370, `rate_item_dependencies_close_consistent_check`:

```sql
(recorded_until IS NOT NULL) AND (closed_type IS NOT NULL)
AND (closed_reason ~ '[[:alnum:]]') AND (recorded_until >= recorded_at)
```

There is no `closed_reason IS NOT NULL` or `coalesce(..., false)`. For a closing row with a NULL reason, the open alternative is false and the closing alternative is NULL. A CHECK accepts NULL. The shared row guard excludes the closing fields from its immutable-content comparison and stamps the close time; the following dependency guard stamps the closer but does not require a reason.

Concrete path as `tally_app`: insert an ordinary dependency, then `UPDATE ... SET recorded_until = now(), closed_type = 'retracted'`, leaving `closed_reason` NULL. Expected: accepted, removed from the open graph, and permanently closed with no explanation. The deferred successor guard does not require a successor for retraction.

This weakens -21: its final guard explicitly rejected `NEW.retired_reason IS NULL` (`tu.sql` around 39543), and its pair CHECK required a reason with a retirement. The prior A-1 schedule-item pattern also expressly tests reason presence. The new blank-reason battery case does not cover NULL.

**Probe:** [01-dependency-close.sql](codex-r1-probes/01-dependency-close.sql), `B1 NULL close reason`, followed by stored stamps/reason and blank-reason control. Expected vulnerable observation: accepted, `missing_reason = true`, author/closer stamped correctly.

**Fix:** explicitly require a non-NULL alphanumeric close reason in the closing alternative. Add separate omitted/NULL, blank and punctuation-only cases for retraction and supersession.

### B2 — **Predicted:** changing children does not preserve the parent’s checked zone

Frozen patch lines 134–164 read the invoice and children without a shared row-version mutex or a child-write guard. Existing `enforce_invoice_surcharge_lines_and_bases` (`tu.sql` 19531 onward) checks the invoice being issued, not a parent of an edited child. The invoice immutability guard (`tu.sql` 38574 onward) permits edits to a draft child even when its parent is issued. No parent-membership enforcement was added here.

Concrete sequential path, stronger than a timing-only concern:

1. Parent P has one draft Austin child. At the battery's June boundary the customer is not yet a state agency in Central time.
2. Insert P's non-zero fee, snapshot P, issue P, and flush all deferred checks.
3. Change the draft child's location to El Paso, without updating P or its line.
4. Flush all checks again. Expected: child edit accepted, P remains issued with its fee, but an explicit `assert_surcharge_line` now rejects that same fee because the Mountain boundary classifies the customer as a state agency.

An additional live child can likewise turn a previously agreed zone into two zones. Updates of membership/location, child insertion/deletion and voiding must be considered together, including old and new parents on reparenting.

**Probe:** [02-parent-zone.sql](codex-r1-probes/02-parent-zone.sql), B2 sequence. It attempts a complete snapshot/issuance and flushes **all** constraints as owner before changing the child. The expected explicit recheck error is `23514` with “was a state agency”; after appending the conflicting child, the lookup should report `21000`. If the issuance setup fails, do not count the subsequent steps as proof of an issued-parent bypass.

**Concurrency assessment, predicted; same probe demonstrates the missing invariant without racing:** neither a line/issuance reader nor a child writer implements a mutual parent handshake. At READ COMMITTED or REPEATABLE READ, an overlapping child change need not be visible to the read that admitted the fee. A parent FK is not validation of the zone predicate. SERIALIZABLE may abort particular overlapping schedules; it cannot repair the sequential legal sequence above. I have not executed or supplied a claim of a measured two-session race.

**Fix:** define and enforce when a parent's child set/premises become fixed, or revalidate affected parent fee lines on changes. Pair child writers with parent line/issuance checks using an agreed lock order and a row-version mutex so higher-isolation snapshots are covered. Locking only the currently selected children would still miss newly attached children. Include statement-end/deferred validation for multi-row and writable-CTE shapes.

### B3 — **Predicted:** a consolidated invoice with a premise bypasses child agreement and nesting refusal

Frozen patch line 134 selects the direct-premise branch solely from `location_id IS NOT NULL`. The schema's `invoices_check` (`tu.sql` 1687) only requires `location_id IS NOT NULL OR is_consolidated`; it does **not** require a consolidated parent to have a NULL premise. Neither the consolidated flag nor existence of children is checked before this return.

Concrete path: use the fixture parent with El Paso and Austin children, then give the parent the Austin location while keeping `is_consolidated = true`. Expected: `invoice_time_zone_as_of` returns Central without inspecting the disagreeing children, and a non-zero fee is admitted. This is a direct path around Ryan's “a consolidated parent uses its children's premises, which must agree.”

The nested-parent claim has the same gap. The `v_orphan` aggregate tests only a NULL child location. Give a consolidated child its own premise and the outer parent's check treats it as a leaf. Thus “a nested parent is always refused” is not established by Z5h's NULL-premise fixture.

**Probe:** [02-parent-zone.sql](codex-r1-probes/02-parent-zone.sql), B3 cases, including an actual fee insert on the mixed-child parent after setting its premise. No constraints are disabled.

**Fix:** validate the parent/leaf shape explicitly and select the helper branch from that validated shape. Reject nested parents independently of a NULL-location shortcut. If malformed combinations are to be prohibited globally, check existing data and include flags, links and location combinations in the migration tests.

## Should-fix items

### S1 — **Executed (source inspection):** the mutation runner succeeds on the wrong named check

`mutations-28-frozen-r1.sh:37` increments `caught` even when `$got != $2`, and never sets `fail` in that branch. Consequently the runner's success condition does not establish its header promise that each mutation fails at its named check. This is visible in shell source; I did not execute the runner.

Set failure on a mismatch, or explicitly enumerate acceptable alternate failures with their rationale. This does not contradict the author's account that the observed run hit all intended labels; it means later runs need not do so to exit successfully.

### S2 — **Predicted:** the tier check is not a complete tier-shape check

The new JSONPath deliberately filters to tiers where `.rate` exists. A tier missing `rate` is skipped. A rate under a different nested key is not the documented `.rate` and is likewise outside that path. The existing `rate_item_versions_tier_config_required_for_tiered` CHECK (`tu.sql:15407`) can evaluate to NULL for `{}` because `jsonb_typeof(tier_config -> 'tiers')` is NULL. Empty tiers also have no rate for the new path to examine.

**Probe:** [03-tier-shapes.sql](codex-r1-probes/03-tier-shapes.sql). Includes missing tiers/rate, empty tiers, a nested pricing object, explicit JSON null, string rates, arrays, negative rates and a long exact decimal tail. Expected: canonical numeric fifth decimals are refused; missing keys/empty collections can be accepted. Explicit JSON null is distinct from a missing member and is expected to be refused by the type predicate. Array outcomes are deliberately diagnostic, not claimed as measured bypasses.

This is a should-fix rather than a separate rounding blocker: absent or misplaced rates already violate the documented JSON shape, and I found no consumer that treats the alternate nested key as a supported tariff rate. Do not describe the constraint as proving every tier *has* a numeric rate. Either enforce the documented shape or state that presence/shape remains outside this precision check. Keep the long-tail case to test exact JSON numeric precision independently of the six-decimal scalar columns.

### S3 — **Executed (source inspection); runtime consequence predicted:** D7c does not isolate the close mutex

The battery backdates the schedule at lines 289–292, before D2d and several later successful inserts. Each insert contains the same header bump. D7c then checks `updated_at = now()` after the close. That equality cannot distinguish a close that touched the header from one that did not: earlier inserts already supplied it.

The ported -21 K5 test is better: its backdate is immediately before the close. Retain that coverage and move -28's backdate to immediately before D7, or add an independent close-only mutex test. The mutation set tests removal of the closer stamp, not removal of the closing UPDATE.

Database inspection support: [01-dependency-close.sql](codex-r1-probes/01-dependency-close.sql) exercises closes and [04-reapply-and-catalog.sql](codex-r1-probes/04-reapply-and-catalog.sql) prints the applicable triggers/privileges. Neither is represented as a measured concurrency test.

## Notes and required review answers

### N1 — **Executed (source inspection):** scope follows the three rulings; implementation has the blockers above

The patch implements the requested bill-zone argument, in-place dependency dating and entry-time precision CHECKs. It leaves CI-091 out as directed. I found no unrelated policy expansion in the replacement surcharge function: a source diff against the final prepatch definition changes only the zone variable and exemption branch. The previous rule-row SHARE lock, tax/base exclusion, service mutex and positive-only cap code are retained verbatim. This is a textual comparison, not a claim that their runtime regressions were rerun.

### N2 — **Predicted:** dependency architecture is otherwise consistent with the stated model

The row guard sorts before the dependency guard. `recorded_at NOT NULL` prevents its draft-edit branch from becoming an escape. It excludes only close fields from the immutable-content comparison, then the dependency guard stamps `closed_by`; insert stamping replaces caller-supplied `changed_by`. A later edit of the author is content mutation; a closer with no close fails consistency. The trusted `app.user_id` boundary remains AC-43's existing application contract, not authenticated identity manufactured by this patch.

The predecessor check compares tenant and all three link keys and requires a superseded predecessor. Closed rows are excluded from the cycle walk; inclusive ranges agree with the exclusion and the as-of reader. A successor for the same link therefore does not traverse its closed predecessor. Deferred successor enforcement and no-delete guards remain attached. Probe 01 includes stamps, immutable fields, owner/application deletion, endpoint overlap, multi-row cycle, missing successor and an actual same-link successor; probe 04 prints trigger order and ALWAYS status.

The schedule UPDATE mutex is retained on both insertion and close. The source's lock-order caveat is appropriate: acquire headers in schedule-id order before dependency rows, and retry the whole transaction after deadlock/serialization failure. A direct close can acquire its dependency row first and deadlock with a header-first writer; this is not a new promise of deadlock freedom. I make no claim of having reproduced the all-isolation races. Existing ported race outcomes require the author's execution.

### N3 — **Executed (source inspection), with predicted catalog checks:** signature and version contracts

The final prepatch two-argument call sites found in schema source belong to the successive definitions of `assert_surcharge_line`; the frozen patch replaces the final body. Searches found no active application-contract call requiring the dropped signature. Historical patch text and prose mentions are not live callers. Probe 02 prints the remaining function bodies mentioning the helper and checks `to_regprocedure` for the old signature; this is the required live confirmation, not supplied evidence of its result.

AC-42 explicitly excludes schedule composition from reference-version tokens and allows `updated_at`-only header writes. Thus adding the dependency guard does not itself require a new version receipt. Probe 04 checks role privileges for that mutex; probe 03 obtains normal version receipts before rate-version inserts. `tally_core` is intended to read these entities; probe 01 tests the new read and a denied write. Owner and application behavior are not inferred from a core grant alone.

### N4 — **Predicted:** reapply and precondition are conservative, not a data migration

The first-run `retired_at` marker plus existing rows raises before the destructive section-2 DDL; the enclosing transaction is intended to roll back earlier section-1 work too. Refusing undated legacy rows is the declared precondition and is acceptable. It does not implement a populated-table conversion, and its “date them by hand” hint still requires an actual migration plan.

On an already-dated table the marker is absent, so the row-count precondition is skipped. Probe 04 embeds the exact frozen body with only the outer BEGIN/COMMIT removed, reapplies twice with a dependency row under empty search_path/body checks, and reports retained rows. It then adds the legacy marker transactionally to exercise the refusal predicate (`55000` expected); this last part is a predicate test, not a reconstruction of a full legacy database. The probe's outer transaction rolls back every DDL change. No strict-apply success is claimed until it is run.

### N5 — **Executed (test-source review):** coverage is useful but narrower than the headline

The frozen battery pins the important Central/Mountain boundary and expected guard messages, tests inclusive overlap and a conservative dated-cycle refusal, and checks real scalar/tier precision boundaries. The older-tests diff largely preserves its prior dependency semantics: retire becomes retraction, creation gains an effective date, and duplicate-open detection changes from uniqueness to exclusion. The -21 closer/header test retains its original intent. Comments about retirement are historical terminology, not another live API.

Missing from the provided battery: B1's NULL close, B2's child changes after validation/issuance, B3's malformed parent shapes, S2's shape matrix, and a close-only mutex check in D7c. There is also no new parent/child race. The supplied probes address the concrete source findings but do not replace a real race suite. The -15 V23 date failure is excluded from this review as instructed.

### N6 — **Predicted/accepted design assessment:** L1–L5 are not independently blocking

- **L1:** refusing unloaded counties is the explicit “never assume” ruling. Probe 02 tests a missing-county lookup and a zero fee on that premise.
- **L2:** the conservative overlap walk can refuse a graph with no common-day cycle. This is explicitly approved; probe 01 includes that construction. No demand for an exact temporal walk in this patch.
- **L3:** one-transaction `now()` tests do not demonstrate replay across separate commit times. Probe 01 preserves that limitation; do not promote its before/now reads into proof of multi-transaction history.
- **L4:** invoice-line rates, annual deposit percentages and retired history are excluded by the stated scope. This is not a claim of complete platform rounding enforcement. Probe 03 covers the three entry points actually changed.
- **L5:** earliest-history fallback is intentionally retained, not introduced here. Probe 02 includes the pre-history call alongside the boundary calls. Its business tradeoff is accepted for this review.

B1–B3 are additional enforcement gaps, not rediscoveries of these accepted limits.

## Probe results — executed by the author (2026-11-02)

Each probe ran as the owner on a fresh clone of `tally` with frozen r1 strict-applied (`psql -X -q -At`, NOTICE kept). Full output: `codex-r1-probes/OUTPUT-r1.txt`.

- **01-dependency-close.sql — B1 confirmed.** "B1 NULL close reason: accepted (SQLSTATE 00000)"; the row is closed with no reason, author and closer stamped. Controls as predicted: blank reason 23514, closed row immutable 23001, inclusive-endpoint cycle and same-link overlap refused 23514, missing successor 23000, app delete 42501, owner delete 23001, core write 42501; L2's conservative refusal reproduced.
- **02-parent-zone.sql — B2 and B3 confirmed.** B2: the parent's fee was accepted with Austin as sole child, the parent snapshotted, issued and every constraint flushed; the draft child's premise was then moved to El Paso and accepted, all constraints flushed again and accepted; an explicit recheck of the issued fee now refuses (23514, "was a state agency ... midnight America/Denver"); appending a conflicting live child to the issued parent was accepted, after which the lookup refuses (21000). B3: a consolidated parent given its own premise was accepted, its mixed-zone children ignored, and a non-zero fee accepted; a nested parent with a premise likewise read as a leaf. Old two-argument signature: absent.
- **03-tier-shapes.sql — S2 as predicted.** Five decimals, negative five decimals, numeric string, JSON null, array, nested array and the long exact tail refused (23514); a missing `rate`, missing `tiers`, `{"tiers": []}` and a rate nested under `pricing` accepted. Scalar and override boundaries as the battery.
- **04-reapply-and-catalog.sql — N4 as predicted.** Strict re-apply twice with a dated dependency row: accepted, rows kept; the legacy-marker precondition raises 55000; triggers in name order, all ENABLE ALWAYS.
