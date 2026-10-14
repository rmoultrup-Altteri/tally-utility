# Codex review r1 — v5.4.2-19

**Verdict: not yet.** Five blocking findings below. This is a source-only review: none of the SQL reproductions, application passes, battery assertions, or concurrent schedules below was executed. Docker was not used. Only this report was written.

## Artifact identity and verification limits

All three supplied MD5 values match:

| Artifact | Observed MD5 | Result |
|---|---|---|
| `tests/v5.4.2-19/review/patch-19-frozen-r1.sql` | `63157e6e3343e62d4e547c31e6c02e14` | Match; 897 lines |
| `tests/v5.4.2-19/review/battery-19-frozen-r1.sql` | `f4f321db406e717074fc54a05e596371` | Match |
| `tests/v5.4.2-19/races/cycle-19.sh` | `3ab9a3e34e1f8a15a5548d8fd6b9ccbf` | Match |

The working files selected by CI, `sql/v5.4.2-19-hardening-batch-1.sql` and `tests/v5.4.2-19/battery-19.sql`, also have the respective frozen hashes. Static counting finds 74 refusal calls and 30 explicit success notices, consistent with 104 checks; that is not 104 executed passes. `bash -n` accepted `tests/ci.sh` and the race script.

Read, not run: strict application with empty search_path and body checking; transactional rollback on failure; second application through the psql gate; RLS/role behavior; the battery; the race sessions; actual table emptiness. The deployment premise that these tables are empty is accepted from the request, not independently measured. The authority documents were read, especially the named parity rows and wave 1. R1–R10 are treated as intentional residuals, not demands to implement later waves.

References below use `patch` for `tests/v5.4.2-19/review/patch-19-frozen-r1.sql`, `battery` for `tests/v5.4.2-19/review/battery-19-frozen-r1.sql`, and `schema` for `sql/tu.sql`. All reproduction outcomes are **predicted from source**, not observed database results.

## Blocking

### B1 — A read born locked bypasses both lock stamping and the new freeze premise

**Evidence:** patch:254, patch:290–303, patch:315; schema:8532, schema:12042, schema:17201–17255, schema:17330.

The replacement workflow function remains attached only to `BEFORE UPDATE`. Its required lock flag/run and DB timestamp logic also runs only when the validation status changes. The existing exception gate explicitly admits INSERT into `locked`, but does not enforce those lock metadata requirements. The dry-run lock guard is UPDATE-only too.

As `tally_app`, using valid tenant/meter fixtures, insert a new non-estimated reading on a fresh date with `validation_status='locked'`, `billing_period_locked=false`, and `locked_at='2020-01-01Z'`; omit the billing-run pointer. No shown guard rejects that shape or replaces that timestamp. Then UPDATE only `reading_value` or `consumption`: Block 2 does not run because OLD.billing_period_locked is false; Block 3 checks pointers, not values; the exception gate's frozen list does not include either value. Thus a row represented as locked can remain writable. Even inserting with the flag true and a valid run still preserves a caller-supplied lock time.

**Fix:** cover born-locked INSERTs as well as transitions, require consistent flag/run metadata, and stamp the lock time there. Either explicitly forbid application INSERT into consumed states, or validate those INSERTs fully. Add isolated tests for born-locked false flag, missing run, forged timestamp, and a valid born-locked row. Preserve the intended superuser history-load exception.

### B2 — `days_in_period` is still editable after consumption

**Evidence:** patch:219–220, patch:315–339; schema:3493; battery:99–138.

The column comparison misses `meter_readings.days_in_period`, although the population function treats it as a derived period fact. Dates, values, and consumption are frozen while their stored period length can be rewritten, including on the evidence reused by a correction run. There is no other UPDATE guard for this column in the schema.

Source reproduction using the battery's R1/R6 read, while locked or void-released:

```sql
UPDATE public.meter_readings
SET days_in_period = 999
WHERE id = '00000000-0000-4000-8000-000000001911';
```

This is predicted to succeed as `tally_app`. No rule evaluation is needed to prevent it: add the stored period length to the write-once comparison. Test it on both locked and void-released rows, with a legitimate pre-consumption edit as the positive boundary. The header's broad billing-value freeze is not complete without this field.

### B3 — A positive replacement payment bypasses processor deduplication

**Evidence:** patch:496–501; schema:3840–3889, schema:3909, schema:10175, schema:10199, schema:13539–13585; battery:255–269.

Either non-NULL lineage pointer removes a row from `payments_provider_transaction_once`, regardless of amount, method, status, or the referenced payment's disposition. The base FKs only establish existence. `enforce_payment_immutable` freezes those pointers after intake; it does not validate their meaning on INSERT or the pending-to-posted write.

The NSF exclusion is especially problematic: schema:3909 describes `nsf_original_payment_id` as the pointer on a **replacement payment**, not merely a bookkeeping NSF reversal. Two deliveries of the same positive replacement transaction can both legitimately carry that pointer and both escape this index.

Source reproduction: after battery P5c, insert two distinct payment numbers with amount `20`, method `ach`, default status `posted`, valid effective fields, source `paymentus_webhook`, the same new provider transaction id `RETRY-TXN-1`, and `nsf_original_payment_id='00000000-0000-4000-8000-000000001962'`. Both are predicted to pass. The equivalent fake-refund escape is to add `refunds_payment_id` to an otherwise positive ACH posting; no check requires it to be a refund. P6b only exercises a legitimate negative refund and does not test the exclusion's opposite boundary.

**Fix:** include real replacement receipts in idempotency enforcement. Define and enforce the precise record kind eligible for any refund/return exception, and give repeat deliveries of those events an idempotency identity too. This is record integrity, not NACHA routing or arithmetic in a trigger. Add both repeated replacement receipt and positive-payment-with-refund-pointer negatives.

### B4 — Supersession of an already-inactive method lacks a row-version mutex

**Evidence:** patch:580, patch:617–621, patch:634–635; race script:90–92.

The predecessor is locked, but the AFTER trigger writes it only when `is_active OR is_default`. When both are already false, supersession creates no new predecessor row version. A REPEATABLE READ reactivation can retain a snapshot with no successor and pass the EXISTS guard after waiting for the predecessor lock. The unique successor index does not constrain reactivation.

Two-session source reproduction:

1. Commit an ordinary predecessor P with `is_active=false, is_default=false`.
2. B begins REPEATABLE READ and SELECTs P, establishing its snapshot.
3. A inserts successor S of P and holds its transaction open. The SELECT FOR UPDATE locks P, but the conditional AFTER UPDATE skips P.
4. B executes `UPDATE payment_methods SET is_active=true WHERE id=P`; it waits for A's lock.
5. A commits. B sees no successor in its old snapshot. P has not been updated by A, so there is no conflicting row version to force serialization failure. B can commit P active alongside S.

This does not require a hostile caller, a privileged role, or disabling a trigger. C3 covers two successors of an initially active predecessor, not reactivation or an inactive predecessor.

**Fix:** unconditionally write a predecessor version on supersession, including inactive/non-default predecessors, or explicitly refuse the unsupported isolation level. Keep lock order documented and add the above race with B observed waiting. Test READ COMMITTED and REPEATABLE READ reactivation as well as competing successors.

### B5 — The new recorded-time balance coordinate trusts caller-supplied ledger time

**Evidence:** patch:879–888; schema:1423, schema:106–130, schema:8504, schema:12012–12026, schema:13490–13503; battery:469–481.

`account_balance_as_of` correctly sums amounts, but its claim to return what was recorded by a coordinate depends on `account_ledger.created_at`. That column is an ordinary DEFAULT, not a server-enforced insertion stamp. The ledger insertion functions do not replace it. Append-only enforcement protects a fabricated timestamp after insertion; it does not make it true. The new log-stamping loop only covers the other three logs (patch:677).

As `tally_app`, insert a valid ledger charge today with `transaction_date='2026-01-31'`, amount 100, and `created_at='2026-02-01Z'`. A call with `p_on='2026-01-31'` and `p_recorded_at='2026-02-15Z'` now includes that newly inserted charge. The historical answer changes based on a fact the caller supplied. The B1 battery fixtures are deliberately inserted as owner with historical timestamps, so they do not distinguish trusted migration timestamps from untrusted application ones.

**Fix:** stamp the ledger's recorded coordinate on application INSERT (with an explicit superuser migration exception if required), or introduce a separate DB-written recorded column and use it. Add an application-role backdated/future-created_at probe plus a retained history-load positive test. This is independent of the intentionally deferred `running_balance` problem in R2.

## Should-fix

### S1 — CI can silently skip the new race suite after clone failure

**Evidence:** `tests/ci.sh:105`, `tests/ci.sh:112–114`.

`clone ci_r19 "$BASE" && step ...` does not set `fail` when the clone fails. With no `set -e`, the script proceeds to subsequent checks and can end with `ci: all pass`, without a race result. Route clone setup failure through `step` or fail explicitly. This is the top should-fix because it can turn missing runtime evidence into a green CI result.

### S2 — Tests need guard-specific failures and missing boundary cases

**Evidence:** battery:27–40, battery:168–176, battery:193–207, battery:340–361, battery:409–438; race script:43–78.

The refusal helper checks SQLSTATE only; another CHECK with 23514 can satisfy a test intended for a particular CHECK. Q3d is weaker still: any exception counts as a successful immutability refusal. Capture constraint name or a stable guard-specific message and pair every negative with the same otherwise-valid row succeeding after only the targeted defect changes.

Priority additions beyond B1–B5:

- The claimed 3-cycle test Q4c also has a direct A→C edge, so C→A forms a 2-cycle. Remove the shortcut to isolate recursion beyond one hop. The current test need not exercise the claimed depth.
- DAG UPDATE reversing a lone A→B edge to B→A must pass, proving exclusion of the old row; also cross-tenant schedule, self-edge, and a separate-schedule non-cycle.
- Zero and all-NULL deadband positives; each partial-column combination; unknown measure; equal and ascending coverage dates.
- Payment status matrix, especially pending→posted without effective fields, pending→NSF, reversed/refunded INSERTs, and terminal effective-date clearing; deduplication on UPDATE as well as INSERT.
- Card expiry UPDATE; cross-tenant supersession; predecessor chain/self-reference; all identity fields and method reactivation races.
- Log UPDATE/DELETE/TRUNCATE for all three tables as owner and both roles; retained owner timestamp and NULL owner timestamp. Current L4 samples only one operation per table and does not exercise TRUNCATE.
- Anomaly subject and created_at changes, zero recurrence, unchanged recurrence/timestamps, and the asymmetric date boundary.
- Cancelled import retry and revival into a conflicting live job; complete/partial job duplicates; preview→commit collision; all four file source types.
- Active enrollment program-type change, NULL receipt with a document, verifier without verification time, and verification exactly at receipt.
- Balance equality at both coordinates, NULL customer/date, and the application timestamp test in B5.

The race script does query `pg_stat_activity` for **B's** application name and Lock wait, so it is more than a sleep-only race. However it samples once, uses a reusable application name, does not verify `pg_blocking_pids(B)` contains A, and does not fail closed if the waiting query returns an error/empty value (the shell integer test can itself fail and execution continues). Prefer bounded polling, unique session names/PIDs, validated query results, and explicit A→B blocking evidence. These are robustness concerns; I did not observe any race passing or failing.

### S3 — State the rate lock order and retry contract

**Evidence:** patch:432; schema:14815.

The header bump is compatible with both existing header guards: it changes neither identity/version nor lifecycle status. It also creates a row version even if `now()` happens to equal the old value. The intended cycle serialization is sound on source inspection.

But dependency UPDATE already locks the dependency row before its BEFORE trigger bumps the header. A different writer can first bump/lock the header with `assert_reference_version`, then UPDATE that same edge: edge→header versus header→edge deadlocks. Multi-schedule transactions can likewise invert header order. PostgreSQL aborting a participant preserves integrity; it is not a cycle escape. Document a consistent caller order (headers in a deterministic order before edge writes) and whole-transaction retry on deadlock/serialization failure. The patch currently describes serialization without stating this operational lock order.

### S4 — Clarify remaining identity/immutability boundaries

**Evidence:** patch:720–729, patch:785, patch:814–816; schema:2127–2129, schema:2135, schema:14390–14392, schema:14447–14449.

- Anomalies freeze the canonical `entity_type/entity_id`, but `customer_id`, `meter_id`, `location_id`, and the separate `detected_at` remain editable. If these are authoritative subject/detection fields, add them; otherwise describe them explicitly as mutable context and stop claiming all subject/first-detection representations are sealed.
- Invoice hash is write-once even on draft/held invoices, whereas the existing URL/time guard returns early on those states. Thus a draft can change URL while retaining the old hash, but cannot regenerate an image with a different hash. Align the draft policy or document that previews must not occupy these delivery fields. The issued-invoice case is covered correctly.
- The import uniqueness key itself remains mutable. A completed job can be relabeled to a different hash/type/preview flag, or to failed/cancelled, freeing its old slot. The partial unique index does correctly refuse revival when another live row occupies the same key, but does not establish immutable history of committed file identity. Decide which edits are legitimate once rows have committed; this review does not ask the database to hash external files.

## Other source review results and intentional limits

### Application and dependencies

The gate is outside a single BEGIN/COMMIT pair (patch:181–185, patch:896–897). With psql and ON_ERROR_STOP as specified, a failed first run does not leave the new marker committed; a successful second run skips. This is a marker gate, not verification that an independently created marker denotes a complete patch. Under the stated controlled deployment premise that is acceptable.

Names in new DDL are qualified and replacement function search paths are pinned. The dropped dunning FK, anomaly UNIQUE, and import type CHECK exist in the base (`schema:5064` for anomaly uniqueness); no dependent object that requires the old anomaly deferrability was found. New CHECKs are validated, not NOT VALID. Functions enforcing newly introduced rules do not retrospectively validate existing rows: in particular the active-enrollment trigger would not make a pre-existing missing attestation fail application. That is compatible with the empty-table premise, but the header's fail-on-nonconforming-row claim should not be read as a universal migration validator.

`populate_reading_calculations` has one trigger caller, INSERT-only (`schema:8560`); the workflow function has one UPDATE trigger caller (`schema:8532`). Their signatures do not change, so replacing bodies preserves those dependencies. The void writes at schema:1229, :12647, :13837, and the final live definition at :14144 all write exactly the same three fields admitted by the new transition. Older copies are overwritten definitions, not additional live overloads. The location backfills at :12953/:12960 and validation backfills at :16943/:16951 occur before this appended patch. I found no later live SQL correction procedure that requires editing the newly frozen values; the allowed correction transition remains void_released→released_to_billing→locked (patch:280–281). R8 models that path, but does not execute a complete correction billing run.

No UPDATE of dunning_events/escheatment_events/ai_audit_log in a stored function or view definition was found in tu.sql. Revoking those writes therefore has no identified internal SQL caller regression. Application contracts must still adopt complete-at-insert logging, as R9 says.

### Reads and caller-settable void GUC

The GUC is still sufficient for a caller to release a locked read without voiding its invoice, and subsequently send it through the permitted re-lock path. The trigger establishes a write shape, not provenance that `void_invoice()` actually ran. Ordinary annotation changes can accompany that write; Block 3 does not compare the whole row. This is consistent with patch:242–245's explicit accident-fence contract, but not with an unqualified claim that only the function can release reads. B2 is a substantive remaining billing-field escape, not merely that documented trust boundary.

Consumption removal leaves previous-value/date/day filling in place. The base `usage_statistics` materialized view explicitly filters NULL consumption (`schema:4826`), so a writer that forgets the new core contract can silently omit reads from those aggregates. No source evidence shows the C# calculation path was exercised or updated here. That is an integration obligation under R9, not a request to put rollover evaluation back in a trigger or add the deferred sign policy.

### Rates

The recursive walk follows base→its bases and checks reachability of the proposed dependent, bounded by per-path visited nodes (patch:436–447). Excluding the same id works for ordinary UPDATE with stable id; membership is positively checked against visibility and tenant for schedule and both items. Header identity cannot change underneath it under `enforce_reference_header` (schema:14747). Deleting an edge cannot introduce a cycle; the intentional DELETE residual does not invalidate insertion serialization. The traversal enumerates paths, so dense DAGs may be expensive, but no scale-based blocker is asserted without measurement.

Deadband all-or-none checks use `IS NULL` booleans and do not suffer the nullable CHECK leg leak. Zero is allowed; the two vocabulary constraints and nonnegative value act independently. Bitemporal whole-row comparison covers the new columns. Coverage order deliberately allows either endpoint NULL. The tier default is restored without changing already-explicit false values.

### Payments and methods

The effective-date pair and required-status checks operate with NOT NULL base status. Pending and intake-voided can omit both; posted/nsf/reversed/refunded require both. Existing terminal-state and no-return-to-pending enforcement prevents unfreezing by status cycling (schema:13544–13557). A posted payment can acquire R01 with its NSF transition; ACH NSF cannot omit a code; a non-NULL code is thereafter write-once. Code-bearing NSF/reversed rows are terminal, so a legitimate later status transition is not newly stranded by the code CHECK. R10 intentionally leaves reversed ACH without a required code.

Supersession uses a composite tenant FK, a positive visible predecessor lookup, same-customer comparison, unique successor, and immutable identity/link fields. Requiring an existing predecessor plus freezing that edge prevents normal chain cycles; the self CHECK covers self-reference. The AFTER deactivation re-enters BEFORE but changes only allowed fields and never activates, so that recursion terminates. Card expiry fields remain mutable as intended. B4 is the missing concurrency case, not a general claim that the AFTER trigger recurses indefinitely.

### Logs, charges, programs, imports, and balance

The three logs already belong to the no-hard-delete/no-truncate protected set (`schema:13261–13287`), upgraded to ALWAYS by the later loop (`schema:14474–14500`). Patch UPDATE/DELETE append-only triggers and revocations complete that coverage, including ordinary owner statements; table owners/superusers could explicitly alter/disable protections, which is outside the application threat model. Timestamp triggers are invoker-rights and preserve only superuser-supplied history timestamps. tally_core starts with SELECT on existing tables, not blanket operational write rights (`schema:27358–27372`); the patch does not grant it log mutation.

AI audit CHECKs require a non-NULL FK for the stated AI flags/source. They do not establish that the cited row is the correct action or tenant; the broad tenant-FK retrofit is separately sequenced in the authority document. Do not present these checks as semantic validation of the AI decision.

Anomaly recurrence/last-detection columns are NOT NULL in the base, so the new comparisons cannot pass through NULL. Immediate UNIQUE closes deferred deduplication. The existing rate-correction anomaly writer already supplies a dedup key (`schema:15130`); battery-11's four anomaly fixture sites now supply distinct keys (`tests/v5.4.2-11/battery-11.sql:422`, :432, :441, :450), preserving those domain probes.

Approval capture checks freeze both fields even while pending. Attestation runs for every enrollment INSERT/UPDATE, including a change into active and a change of program type while active; the verification-pair CHECK handles both NULL directions and requires receipt before verification. Platform program types are not application-writable. These are representation checks, not evaluation of eligibility, renewal windows, or protection expiry.

Import status/is_dry_run/type/tenant are NOT NULL. The new live index includes pending, inspecting, awaiting_mapping_approval, validating, validated, awaiting_error_review, importing, complete, and partial; only failed/cancelled are exempt. Preview and commit have separate slots. A failed/cancelled row changed back into a conflicting live slot must satisfy the index again. The old filename-based idempotency UNIQUE remains, so retry may need a fresh caller key even when the content slot is freed; J4 supplies one.

The balance helper is invoker-rights, requires all coordinates, checks customer visibility, returns zero for a visible customer with no eligible rows, and uses inclusive date/time bounds. It does not depend on row order or running_balance. Those are good properties; B5 prevents treating its recorded-time coordinate as trusted history yet.

## Required closeout

Resolve B1–B5, add isolated tests for each, and execute strict application twice, the revised full battery/compatibility batteries, and the expanded races in an authorized throwaway database. This reviewer has supplied source findings, not database execution evidence.
