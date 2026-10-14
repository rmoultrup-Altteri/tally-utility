# Codex review r2 — v5.4.2-19

**Verdict: ready, on source review. No blocking findings.** All twelve blocking entries across the three round-1 reviews are closed in the r2 source, with the scope qualifications below. There are test-isolation and documentation issues to fix. This is not an independent runtime certification.

Docker was unavailable and was not used. I did not connect to any database, run SQL, execute the battery/races/CI, or mutation-test a guard. I wrote only this report. The claimed strict application twice, 146/146 checks, C1–C7, 25 CI steps, and C5 failure against the conditional r1 supersession write are **supplied results, read rather than reproduced**. Table emptiness is the accepted deployment premise, not something I measured.

References: `patch` = `tests/v5.4.2-19/review/patch-19-frozen-r2.sql`; `battery` = `tests/v5.4.2-19/review/battery-19-frozen-r2.sql`; `schema` = `sql/tu.sql`; `race` = `tests/v5.4.2-19/races/cycle-19.sh`. Line references below use those frozen files. Any predicted SQL outcome is static reasoning, not an observed result.

## Artifact identity and checks actually performed

| Artifact | Observed MD5 | Result |
|---|---|---|
| patch | `7e7416abdf7161bdd1b7eff2621de2dd` | Matches; 1,409 lines |
| battery | `8fab48539eb6c64263bd95d4deb1a731` | Matches |
| race | `91f2817513fc9079fb04648b37f03446` | Matches |
| `tests/ci.sh` | `a5e640c0a0ae45e04a0e21fc04e9bc51` | Matches |

The working patch and battery selected by CI also match the respective frozen hashes. Static counting finds 112 refusal calls and 34 explicit success notices (excluding the refusal helper's generic notice), consistent with 146 checks. `bash -n tests/ci.sh tests/v5.4.2-19/races/cycle-19.sh` passed; that checks shell syntax only.

I read the Revision r2 paragraph first, the r1 frozen patch/battery changes, all three r1 reviews, the relevant parity rows, wave 1 in `application/step1-sequencing-2026-10-13.md:15`, and Ryan's running-balance decision in `application/DECISION-LOG.md:9`. I extracted and diffed the last live `void_invoice()` body against r2 and inventoried all 94 live `meter_readings` columns from the source.

## Round-1 blocking closure

Each review's identifiers are retained, including duplicate findings.

| R1 item | Status | R2 evidence and judgment |
|---|---|---|
| Codex B1 — born-locked INSERT | **Closed** | `patch:412–435` rejects application INSERTs with consumed status, true flag, lock time, either lock pointer or void provenance. Refusing birth with a lock is a sound alternative to stamping one. Superuser history loading remains explicit. |
| Codex B2 — editable days_in_period | **Closed** | `patch:355–368` freezes every non-whitelisted column; `days_in_period` is not exempt. Applies after void release as well. `battery:128` targets this field. |
| Codex B3 — positive replacement/refund dedupe escape | **Closed** | `patch:585–590` checks refund shape and indexes every positive amount, irrespective of either lineage pointer. Positive NSF replacements now count. `battery:336–349` targets both escapes. |
| Codex B4 — inactive predecessor lacks a row version | **Closed** | `patch:717–718` unconditionally UPDATEs the predecessor, including false/false rows. That removes the old-snapshot/no-write escape. `race:113–118` supplies RR/RC reactivation cases and the final inactive-state check. |
| Codex B5 — caller-written ledger recorded time | **Closed** | `patch:747–748,829–832` stamps application ledger INSERTs. `battery:454–460` supplies an explicitly backdated value and checks its replacement; `battery:611–612` checks the helper's recorded-time boundary. |
| Opus B1 — born-locked/void-released INSERT | **Closed** | Same INSERT guard, `patch:420–425`; no reliance on the unrelated meter-pointer FK refusal. |
| Opus B2 — void-released lock pointers editable | **Closed** | `patch:380–395` protects all consumed states. The re-lock exception is limited to released_to_billing→locked; void provenance cannot change on that transition. `battery:161–179` covers pointer refusals and a valid re-lock retaining provenance. |
| Opus B3 — payment labels evade once-only rule | **Closed** | `patch:587–590`: the positive amount determines participation, not the label. It is unnecessary to invent an NSF-negative-row exclusion because replacement receipts should participate. |
| Opus B4 — foreign-tenant AI citation and removable provenance | **Closed for its required structural fix** | Composite FKs at `patch:791–797`, write-once flag/citation at `patch:801–824`. `battery:437–452` covers foreign citations and provenance edits. Same-tenant action-to-record semantic matching is still not established; the optional action-type restriction proposed in r1 was not implemented. See notes. |
| Opus B5 — import completion/identity can free slot | **Closed** | `patch:981–993` freezes file identity and every finished status, including complete/partial. `patch:968–970` counts committing jobs across types. `battery:556–568` tests identity, finality and a duplicate after completion. |
| Fable B1 — processor receipt bypass | **Closed** | `patch:585–590`; same money-in fix as Codex B3/Opus B3. |
| Fable B2 — import key mutable | **Closed** | `patch:981–990` includes tenant, initiator, source/import types, name/hash, dry-run flag, caller key, id and creation time. This is stronger than freezing only hash and preview flag. |

Related r1 should-fixes also addressed: lock flag (`patch:340`), raw/period/read-validation fields (`patch:355`), ledger stamp (`patch:829`), anomaly subject/detection (`patch:850–865`), superseded default (`patch:697`), draft image pair (`patch:932`), preview exclusion and cross-type commits (`patch:968`), set-based graph walk (`patch:509`), SQLSTATE-specific Q3d (`battery:209`), genuine 3-hop Q4c and old-edge exclusion positive (`battery:239–248`), and CI clone failure (`tests/ci.sh:56–60,114`). The lock-order improvement is partial; see S3.

## Blocking

None identified within the stated wave-1 scope and accepted residuals. Source closure should not be read as a claim that I ran the concurrency or privilege checks.

## Should-fix

### S1 — Isolate the cross-type import test; add a behavioral balance-return assertion

**`battery:546–548`; `schema:12325–12333,5344`.** J2c uses the same filename/hash/commit flag as J2. The pre-existing INSERT trigger derives the same `feb.csv:h-feb:commit` idempotency key, which is already unique per tenant. Consequently J2c can still report PASS with the new file-wide unique index removed, or with r1's type-partitioned index restored. It does not prove cross-type protection.

Give J2c a distinct explicit idempotency key (and preferably a different filename), assert `CONSTRAINT_NAME = 'import_jobs_file_once'`, and retain the same hash with `import_type='lockbox'`. A mutation restoring `import_type` to the file index must then make this refusal test fail. This is a test defect; the r2 index itself has the correct key.

**`battery:617–624`; `patch:1365–1368`.** B4 proves absence of a column/function/name reference, not that `void_invoice()` returns the correct sum. Replacing the new query with `SELECT 0 INTO v_new_running_bal` would leave B4 passing. Seed an unrelated prior customer ledger balance plus an invoice charge, call the function as `tally_app`, and assert `credit_balance` equals the remaining sum including its reversal. Include another customer's rows. Existing CI battery-11 calls the function (`tests/v5.4.2-11/battery-11.sql:273`) but checks callability/voiding, not this arithmetic. The new sum is correct by inspection; its new behavior deserves a direct regression assertion.

Other isolation limitations are itemized in the test audit below. Checking SQLSTATE is useful, but not sufficient whenever two relevant guards share it.

### S2 — Replace the surviving ledger comment and stale patch descriptions

**`schema:13725–13726`; `patch:1400–1402`.** The live table COMMENT still says `running_balance is computed on INSERT by compute_ledger_running_balance()`. Dropping the column and function does not remove a comment attached to `account_ledger`. Append a replacement COMMENT in this patch describing summed balances. This is the one surviving live catalog comment I found referring to the removed machinery; it is not an executable dependency.

Also update `patch:73–76` (still describes lineage exclusions), `patch:105–110` (still describes type/preview-partitioned file uniqueness), and `patch:723` (“a draft can no longer use the replaced account”). The payment-method trigger deactivates the row; it does not reject a payment citing an inactive method. The same issue was raised in Opus r1. State that the core excludes inactive methods when selecting an account.

### S3 — Finish the dependency lock-order contract

**`patch:494–503`; `schema:14815` (`assert_reference_version`).** Ascending schedule-id order addresses multi-schedule inversion, but not the edge→header versus header→edge inversion described in Codex r1 S3. An UPDATE acquires its dependency row before its BEFORE trigger bumps the header. Another transaction can acquire that header first through a reference-version write and then try to update the edge.

Document that callers acquire/write the relevant header mutexes in ascending id order **before** dependency-row writes, and retry the whole transaction after deadlock/serialization failure. A deadlock abort preserves the graph invariant; this is an operational contract issue, not a demonstrated cycle escape.

## New-code audit

### Reads: birth, complete column inventory, and allowed workflows

`schema:3482–3590` defines 93 columns; `schema:12893` adds `location_id`, giving 94. No other live column additions to this table were found. All 21 whitelist names are real columns. `jsonb_each(to_jsonb(OLD))` plus `IS DISTINCT FROM` (`patch:355–368`) compares all other fields, including SQL NULL changes, and new columns will be frozen automatically.

The complete partition is:

| Treatment | Columns |
|---|---|
| 16 follow-up fields | `notes`, `tamper_investigated`, `tamper_investigation_notes`, `dispute_reason`, `dispute_raised_by`, `dispute_raised_at`, `dispute_resolved_by`, `dispute_resolved_at`, `dispute_resolution_notes`, `status`, `requires_followup`, `followup_priority`, `followup_notes`, `assigned_to_user_id`, `replaced_by_reading_id`, `triggers_correction_workflow` |
| 5 fields governed by Blocks 1/3 | `validation_status`, `locked_at`, `locked_by_billing_run_id`, `locked_by_invoice_id`, `voided_from_invoice_id` |
| Frozen identity/measurement | `id`, `tenant_id`, `meter_id`, `location_id`, `register_type`, `register_label`, `reading_date`, `reading_value`, `previous_value`, `previous_reading_date`, `consumption`, `consumption_unit`, `days_in_period`, `read_method`, `read_by`, `data_collector_user_id`, `read_sequence_number`, `actual_read_order`, `reading_timestamp`, `raw_read_value` |
| Frozen collection evidence | `gps_latitude`, `gps_longitude`, `gps_accuracy_rating`, `gps_changed_latitude`, `gps_changed_longitude`, `endpoint_id`, `changed_endpoint_id`, `endpoint_type_received`, `extended_endpoint_type_received`, `endpoint_read_datetime`, `access_status`, `access_notes`, `skip_code`, `force_complete_reason_code`, `trouble_code_1`, `trouble_code_2`, `trouble_message`, `read_condition`, `amr_read_status`, `tamper_count_1`, `tamper_count_2`, `tamper_count_1_changed_flag`, `tamper_count_2_changed_flag` |
| Frozen classification/calculation | `is_estimated`, `estimation_reason`, `quality_flag`, `replaces_reading_id`, `gas_meter_factor`, `gas_pressure_corrected_volume`, `gas_btu_factor`, `gas_therms`, `reading_purpose`, `is_service_transition`, `transition_outgoing_customer_id`, `transition_incoming_customer_id`, `billing_cycle_id`, `auto_approved`, `validated_by`, `validated_at`, `billing_period_locked`, `consumption_prior_period`, `consumption_same_period_last_year`, `consumption_pct_vs_typical` |
| Frozen remaining provenance | `import_job_id`, `vendor_reference`, `attempted_count`, `source_system`, `entered_by`, `created_at`, `confirmed_by_field_reader_at`, `confirmed_by_field_reader_id`, `read_cycle_meter_id`, `replaces_read_id` |

The birth guard runs before the existing population/exception triggers by trigger-name order (`patch:433`; `schema:8560,12948,17330`). NOT NULL on status/flag prevents a NULL escape (`schema:3549,3554`). Application reads may be born in a permitted pre-consumption state; this guard does not pretend to repair the pre-existing actual-read born-approved FK issue noted by the r1 reviewers.

For ordinary application rows, the birth prohibition plus transition checks establish the lock-flag premise: a false flag can become true only with status locked (`patch:340`), and entering locked requires a run and true flag and stamps the time (`patch:320–331`). The normal state machine prevents an ordinary false-flag row from already being locked. Superuser history loads intentionally sit outside the birth guarantee.

`void_invoice()` changes exactly status and two pointers (`patch:1201–1207`); Blocks 1/3 admit it without touching any frozen column. A correction passes void_released→released_to_billing→locked (`patch:310,381–394`): its run and time may change, a bill may fill the cleared pointer, and prior void provenance stays. A subsequent legitimate void records the bill then held. A re-lock need not supply a bill pointer; that is the existing run-level-lock contract, not a new r2 regression.

Follow-up assignment, tamper investigation, dispute opening/resolution, follow-up priority/notes, original-row replacement marking and correction flags remain editable. There is no `updated_at` on `meter_readings`, hence no automatic timestamp UPDATE conflicting with the whitelist. The later exception trigger retains `validated_at` and does not re-count an ordinary correction re-entry (`schema:17205–17331`). The earlier location/validation backfills (`schema:12953,12960,16943,16951`) run before this append-only patch.

I found no in-schema follow-up writer requiring one of the newly frozen columns. This is narrower than proving every future application workflow compatible. In particular, field-reader confirmation and `quality_flag` now must be finalized before consumption; their comments describe confirmation of the extracted value (`schema:3628,3635`), not a guaranteed post-billing operation. Preserve that ordering in R9's application contract, and add positives for assignment, dispute resolution, tamper investigation and replacement marking; RW6 currently samples only part of the whitelist.

### Payments, AI provenance, imports, and supersession

The refund CHECK cannot pass via a nullable payment-method/amount leg: both base columns are NOT NULL (`schema:3845–3846`). A citing row must be negative and method refund (`patch:587`); negative non-refunds with the pointer are also rejected. Every positive receipt with a provider id enters the index, including pending/voided and NSF replacements. The source and tenant key columns are NOT NULL (`schema:3841,3850`). Updates moving pending rows into the indexed shape are checked too. Once posted, the existing identity guard freezes amount/source/provider id/lineage (`schema:13561–13584`). Idempotency for negative refund deliveries remains outside the stated “one receipt/money in” rule; do not describe the index as enforcing all outbound-event idempotency.

Both AI composite FKs bind the action record's non-null tenant to the cited log's tenant (`patch:791–797`). They work for the owner as well as under RLS; a foreign hidden row cannot pass through FK existence alone. The UPDATE trigger freezes both provenance fields even from NULL/false (`patch:806`); the required-citation CHECKs prevent clearing a required citation on INSERT. Human rows remain possible and operational edits need not change their creation provenance. The log itself is append-only.

The import index (`patch:968`) counts every non-dry-run, nonfailed/noncancelled row with a hash, across import types and source types. Non-null status/dry-run/source columns (`schema:3093,3102,3104`) keep the predicate definite. Preview retries need a fresh caller idempotency key because the older independent idempotency constraint remains; J3 does that explicitly (`battery:552–554`). Failed/cancelled jobs cannot revive; a retry is a new job. Complete/partial jobs cannot free their slot by status, preview, hash, tenant or type edits. Before completion, cancellation may still release the slot; R13 correctly assigns partially committed imports the `partial` status and calls out the remaining core obligation.

Unconditional supersession writes the predecessor even if neither boolean changes (`patch:714–718`). The existing BEFORE trigger admits that deactivation; the UPDATE creates a row version rather than only a lock. A waiting RR reactivation must then serialize-fail; an RC writer rechecks with the successor visible. The same reasoning covers attempts to make the predecessor default (`patch:697–701`). The unique successor constraint still handles competing successors. These are source conclusions, not races I ran.

### Other changed guards

The graph walk now deduplicates by node (`patch:509–519`), eliminating path-count explosion. This is a reachable-set walk; “linear” describes its graph model, not a measured guarantee about a particular SQL query plan. It retains positive visible-and-same-tenant membership checks and the header row-version mutex. Excluding the edited row is necessary and preserved.

Invoice URL/hash pairing is definite on NULL and format (`patch:909–912`). Issued non-null delivery fields cannot change; a previously absent image can be recorded together. Draft/held rows can set/clear both or change both, but not change just one non-null value (`patch:923–937`). This requires a new URL when bytes change, consistent with the stated policy. No post-issuance return to draft can unlock the image because the base invoice guard prohibits that (`schema:14415`). Anomalies now freeze both canonical and denormalized subject/detection fields (`patch:850–865`), while resolution and increasing recurrence remain available.

## Section 8: exact comparison and dependency inventory

The last base definition starts at `schema:14039` and ends at `schema:14337`; earlier copies at 1126, 12543 and 13733 are overwritten versions of the same signature. An extracted-body text diff shows **one hunk only**: the old `SELECT running_balance ... WHERE id = v_ledger_entry_id` at `schema:14305–14307` is replaced by the commented tenant-and-customer SUM at `patch:1362–1368`.

The replacement keeps the five parameters/defaults, JSONB return type, PL/pgSQL, SECURITY DEFINER and pinned `public, pg_temp` search path (`patch:1094–1099`). No other body behavior changed: invoice validation, cross-tenant check, reason validation, duplicate warning, read release, both charge dispositions, original-charge lookup, reversal INSERT, void metadata, event payload, carve-out reset and returned keys are identical. The variable precision also remains `DECIMAL(12,2)` (`patch:1109`). Existing behavior, including existing limitations, was preserved rather than newly validated by execution.

CREATE OR REPLACE of the same function preserves its ownership and ACL; there is no DROP/CREATE or owner/grant edit in section 8. The source build creates objects as `tally` (`postgres/Dockerfile:50`), and the base explicitly revokes PUBLIC and grants tally_app EXECUTE (`schema:21499,21509`). The later bulk core-function grant excludes SECURITY DEFINER functions (`schema:30320`). I did not inspect a live catalog to verify owner/ACLs after application.

A full-source search for `running_balance` and `compute_ledger_running_balance` found:

| Reference | Disposition after r2 |
|---|---|
| `schema:106–137` function and function comment | Dropped at `patch:1401`; no other caller found |
| `schema:1418` ledger column | Dropped at `patch:1402` |
| `schema:8504` sole trigger using the function | Dropped first at `patch:1400` |
| `schema:1368,12808,13998` earlier void bodies | Already overwritten by the last live base definition |
| `schema:14305` final live reader | Replaced by section 8 |
| `schema:13726` ledger table comment | **Survives and is stale**, S2 |

No remaining function, view, materialized view, index or column-specific grant referencing the removed column was found. Broad table grants survive the column drop without referring to it individually. No other trigger/function invocation of `compute_ledger_running_balance()` was found. The drops use no CASCADE, appropriately failing if an unexpected catalog dependency exists; I did not run that check.

The new `credit_balance` is the visible statement's sum, including this transaction's reversal, for the invoice's tenant and customer. It is not a transaction-commit snapshot of other concurrent writers, and does not claim to be. The recorded-coordinate helper uses database transaction time (`patch:747–748,1069–1073`), not commit time; long-lived transactions can therefore become visible later with an earlier recorded coordinate. This is a semantic limit of the documented `created_at` coordinate, independent of the closed caller-forged timestamp bug.

## Test and race audit

The answer to “does each new case fail without its guard?” is **not uniformly yes**. The following is a static removal analysis, not an executed mutation suite.

| New/changed cases | What their source establishes, and removal caveats |
|---|---|
| RB1–RB4 (`battery:75–86`) | Exercise four birth shapes. RB2–RB4 should accept absent the birth guard. RB1 absent it may hit the pre-existing actual-read FK error instead; its different SQLSTATE would still fail the test, but use an estimated fixture to demonstrate the intended old acceptance cleanly. Isolated INSERT pointer/void-origin cases are still missing. |
| RF1 (`battery:90`) | Pending→true flag isolates the new UPDATE check; absent it the row should be accepted. R1 remains the positive boundary. |
| RW1–RW5/RW6 (`battery:128–135`) | New fields are targeted and a follow-up edit passes. RW3 uses invalid `estimation_reason='x'`; removing the freeze produces a different-state enum failure, not a valid writable row. Use valid `other` for a clean counterexample. Add equivalent period-field and full follow-up positives after void release. |
| RV1–RV6/R8 (`battery:161–179`) | Isolate the formerly open pointers, including erasure during release; R8 checks both re-lock and retained provenance. Missing Block 3 allows these formerly legal writes. |
| Q3d/Q4c/Q4h (`battery:209,239–248`) | Q3d now requires 23001. Q4c now really needs traversal beyond a direct reverse edge; Q4h checks old-edge exclusion. Removing cycle detection lets Q4c through; removing old-edge exclusion rejects Q4h. |
| Q5 (`battery:254–278`) | Exercises a deep reachable set and requires a refusal within one second. Removing the cycle guard reaches explicit FAIL. The handler still accepts any check_violation; a guard-specific message would be stronger. The one-second threshold and r1 timeout/performance outcome were not measured here. |
| P7/P7b/P8 (`battery:336–349`) | P7 has two defenses: absent the refund CHECK, the positive index yields 23505 rather than expected 23514, so the test fails. P7b catches restoring the old lineage exclusion. P8 isolates the sign requirement without a provider id. Add a negative amount with non-refund method to isolate the method leg. P6b supplies the legitimate negative-refund positive. |
| M9 (`battery:397`) | Targets the newly added default refusal on a known superseded row. Unconditional predecessor versioning needs C5, not this sequential check. |
| L6/L6b/L7/L7b/L7c/L8 (`battery:437–460`) | Valid foreign audit ids isolate tenant binding; service-order creation provenance tests isolate write-once. L7c without the freeze falls through to the required-citation CHECK (different state), so use a different valid same-tenant audit id to prove retargeting refusal too. L8 directly distinguishes caller time from DB time. |
| N4/N4b (`battery:495–496`) | Customer and detection changes are otherwise valid and exercise the enlarged frozen set. Other added subject/detection fields are not individually exercised. |
| I2/I4/I3/I5/I6 (`battery:523–526,645–646`) | Draft one-sided changes, paired positive, and issued hash-only negative cover the new behavior. I6 still passes if the new image trigger is absent because the old invoice guard independently freezes URL (`schema:14447`). I5 is the isolating issued-hash test. Add clearing both on a draft and first setting the pair on an issued image-less invoice. |
| J2c/J6–J9/J3 (`battery:546–568`) | J2c has the false-positive defect in S1. J6/J6b/J6c and J7/J8 are otherwise-valid identity/finality edits; the INSERT-only idempotency-key trigger does not regenerate the key on J6b's UPDATE. J9 has a fresh key, so it isolates file uniqueness after completion. J3 proves that previews no longer occupy the file index, given a fresh caller key. Add partial/cancelled final-state boundaries. |
| B4 (`battery:617–624`) | Catalog/text absence check; does not establish the returned sum. S1. B1 plus L8 tests the separate as-of helper and application timestamp boundary. |

The existing `pg_temp.refuses` helper (`battery:29–41`) checks SQLSTATE but not constraint/message identity. Positive notices following UPDATEs often prove only lack of error, not row count or final values; known inserted fixtures make them reasonable here, but direct field assertions would better pin workflow regressions. R1/R6/R8 already use value assertions.

**The race script now does prove that B was blocked by A, if it reports PASS.** `race:53–60` polls `pg_blocking_pids(B)` and requires A's backend pid in that list, with both sessions in the selected database. Invalid/empty/error output never becomes success. `race:83–95` requires the observation, A's successful completion, and the expected SQLSTATE/message from B. That is materially stronger than r1's generic Lock-wait sample.

C5 starts B while A holds an uncommitted supersession (`race:65–83,113–114`). B's RR UPDATE snapshot predates A's commit even without a separate preliminary SELECT. The inactive predecessor is committed in setup (`race:48–50`). With r1's conditional write restored, A has only locked it, leaving no row-version conflict; B can miss the successor in its snapshot. The test then lacks the expected serialization error and C7 also sees the bad active state. This explains the supplied mutation result; I did not reproduce it.

C6 checks RC refusal, C7 checks both predecessors remain inactive, and C4 checks one half of each graph cycle persisted (`race:115–121`). Fixed sleeps/startup delays can cause false failures on a slow host, but missing overlap cannot produce a PASS because the blocker relationship is required. Reused application names are adequate in the stated single-run throwaway clone; unique session identifiers would improve concurrent harness reuse.

CI's `cstep` now records clone failure and sets `fail=1` (`tests/ci.sh:56–60`), and the r19 race uses it (`:114`). The final exit returns that failure (`:123`). This closes Codex r1 S1 by inspection. I did not simulate clone failure or execute the 25-step suite.

## Notes and accepted boundaries

- R11–R14 are explicit at `patch:185–198`; none was silently mistaken for a completed safeguard. AI same-tenant citation is not proof that the cited audit action actually created this order/charge; even a same-tenant unrelated action can be cited. The optional r1 action-type restriction alone would not prove that relationship either. Broader AI edge tenant binding remains R11.
- The caller-settable void GUC still authorizes the exact pointer-release shape without proving the function ran (`patch:272–279`). Follow-up annotations may accompany it because they are explicitly whitelisted. “Exact write” is exact for the protected lock metadata, not whole-row equality with the function's UPDATE. That is R14's accepted accident fence.
- R13 means file bytes/hash normalization and correct `partial` versus `cancelled` disposition remain intake/core obligations (`patch:191–193`). The database guarantees uniqueness of the stored hash and finality of the stored completion state, not physical file equivalence or proof of already-committed imported rows.
- The old workflow trigger remains origin-enabled, while new guards are ENABLE ALWAYS (`schema:8532`; `patch:435`). Normal application roles cannot set replication bypass. Aligning it is reasonable hygiene, not a new application bypass.
- The precondition prose at `patch:201–204` overstates retrospective validation for active medical holds: the new enrollment trigger (`patch:1025–1044`) validates writes, not pre-existing active rows. Under the accepted empty-table build premise this does not block application; avoid presenting it as a general populated-database migration guarantee.

**Final assessment:** ready within the requested scope, with all r1 blocking entries structurally closed. Top follow-up is S1: make J2c fail when cross-type uniqueness is removed, and assert the new `void_invoice().credit_balance` behavior directly. Runtime claims remain supplied evidence, not checks performed by this reviewer.
