# Codex review — v5.4.2-22 r1

**Verdict: not yet.** Source-only review; all database outcomes below are **predicted**, not executed. Four blocking paths need resolution. Probe filenames identify runnable evidence requests, not completed executions.

## Scope and verification

I verified the frozen files locally before reviewing their contents. All MD5s match the brief:

| Frozen file | MD5 |
|---|---|
| patch-22-frozen-r1.sql | `99acfac6675597e7d2de4d5a2c7a1254` |
| battery-22-frozen-r1.sql | `e6070dfdb509ff4ba1eded52eb33733a` |
| close-22-frozen-r1.sh | `73b157d2966a64a8a00fe537763716ea` |
| mutations-22-frozen-r1.py | `931d9091e15709121de6dd6b6947d47b` |

Reviewed those four copies, the relevant base definitions in `sql/tu.sql`, the wave-2 inventory and 2026-10-15 drafting decisions, and D-2/D-3/R-02 in the sibling `gas-billing-memory` repository. No other reviewers' reports were read. No Docker, database execution, mutation runner, or CI run was attempted. The author's strict-apply, CI, race and mutation results remain author-reported, not independently reproduced.

All probes are in `codex-r1-probes/`. Each is self-contained, requires an owner/superuser psql connection to a fresh clone with the frozen patch already applied, emits `RAISE NOTICE`, and ends in `ROLLBACK`. None needs commits or changes cluster roles. Run with `psql -U tally -d <clone> -f <file>`. Unexpected setup errors stop execution; caught errors are reported with SQLSTATE and message so an unrelated rejection cannot masquerade as the intended guard.

## Blocking items

### B1 — Snapshot aging is not reproducible after an aging-setting change

**Predicted; probe: `b1-aging-coordinate.sql`.** S1/S2, W2 and D-2/CI-110.

The close takes `clock_timestamp()` after the head lock and stores the bucket edges, but `receivables_aging_as_of()` subsequently resolves edges from mutable-in-the-append sense configuration history. `record_tenant_configuration_change()` omits `effective_from`, whose base default is transaction-start `now()` (`tu.sql:13006–13016`). The history lookup orders by `effective_from DESC, seq DESC` (patch section 6).

Concrete path: post a January 5 charge of 100; close January using `{30,60,90,120}`; update the tenant's edges to `{15,45}` in the same transaction; repeat aging at the returned close coordinate. The stored line is `0-30:100`; the recomputation is `16-45:100`. The update's transaction-start timestamp precedes the close coordinate, and its later sequence wins. No freeze or role bypass is needed. The probe uses `tally_app` with a tenant administrator.

There is also an independent route: the base permits direct `manual` configuration-history inserts with caller-chosen `effective_from`. The probe attempts one for this key at the close coordinate. Merely replacing the recorder's `now()` with `clock_timestamp()` does not close this route. An older concurrent configuration writer can also commit after the close without participating in the head handshake.

Fix the recorded-history contract for this key and coordinate the close with its writers, or define a snapshot-reproduction path that uses immutable captured configuration and revise the advertised generic-helper guarantee accordingly. The current promise that the generic aging function reproduces snapshot lines is false.

### B2 — Moving a pending payment between tenants bypasses the old tenant's freeze

**Predicted; probe: `b2-payment-tenant-move.sql`.** P2.

`enforce_accounting_freeze()` (patch section 4) checks both old and new dates against **NEW.tenant_id's** head only. The -21 payment immutability function permits tenant/customer/date changes while `OLD.status = 'pending'` (`tu.sql:39766` onward).

Create a pending January payment in tenant A; close A through January 31; as `tally_app` with a platform administrator, change its tenant and customer to tenant B, whose head is NULL, and its date to February 1. Both RLS sides are visible; the destination customer matches the destination tenant. The freeze is skipped because B has nothing closed, although the payment is being moved out of A's frozen interval. This is a date move, not the explicitly deferred status-only case R2.

Check and lock the old tenant's head as well when ownership changes, in deterministic order, or make tenant identity immutable from birth. Existing customer-credit immutability prevents the corresponding credit move; it does not protect pending payments.

### B3 — Accepted lineage cycles silently disappear from aging

**Predicted; probe: `b3-lineage-cycle.sql`.** W1 and S1/S2; R8 cannot justify losing current ledger balances.

The recursive `tree` in patch section 7 seeds only entries without an in-window same-customer parent. The base prevents self-reference and requires an existing same-tenant entry, but does not prevent a multi-entry cycle. A single multi-row INSERT can satisfy the immediate foreign key with mutually referencing rows.

The probe inserts adjustments A = +100 and B = -40, each naming the other, for one customer. Both are legal under -21/-22's deferred general reversal rules. Their ledger balance is +60, but neither is a tree root: `nets`, `debits` and aging omit them. Closing records +60 as the closing balance and no aging line for it. This is silent financial omission, not an infinite-recursion claim.

Either reject cyclic lineage at write time or detect uncovered entries during aging and fail explicitly. Do not let the close persist an aging total that silently omits accepted ledger debt. General sign/cap policy can still wait for -23.

### B4 — A future recorded timestamp on a history load makes close silently omit frozen money

**Predicted; probe: `b4-future-recorded-ledger.sql`.** S1/S2 and CR7b's complete-ledger reconciliation.

The base `stamp_log_created_at()` preserves a superuser's supplied `created_at` (`tu.sql:37335` onward). Insert a January charge of 100 with `created_at = clock_timestamp() + interval '1 day'`, then close January. Every snapshot query filters on `created_at <= v_at`, so the charge is omitted although it is already present and its transaction date becomes permanently frozen. The probe predicts closing balance/count zero against actual frozen-date ledger balance 100.

This does **not** show the same-coordinate ledger sum changing later: that filtered sum remains zero. It shows an incomplete close and failure of CR7b's second equality to the full dated ledger. As recorded time advances, later reports can include the previously omitted charge; a later period's opening can then disagree with the previous close.

Reject such timestamps for money loads, or refuse a close when already-present in-boundary rows lie beyond its recorded coordinate. Do not silently close past them. The brief explicitly includes owner history loads in this review's scope.

## Should-fix items

### S1 — Nonstandard array bounds bypass positive bucket validation

**Predicted; probe: `s1-array-bounds.sql`.** `aging_bucket_days_valid()` assumes a lower bound of one. `'[0:1]={-10,30}'::integer[]` has `p_days[1] = 30`, and its subscripts never satisfy `i > 1`; the negative edge is accepted. JSON history drops array bounds and returns `{-10,30}`, which can yield nonsensical bucket limits. Require a one-based array and validate every value, or normalize before validation. Also ensure the final predicate is never NULL for malformed arrays, since CHECK accepts NULL.

### S2 — GL recorded-time lookups can change retroactively within a transaction

**Predicted; probe: `s2-gl-recorded-coordinate.sql`.** The mapping trigger stamps both birth and closure with `now()`. Read an open mapping at wall-clock instant T; close it later in that transaction; repeat the lookup at T for a date beyond the effective end. The second lookup loses the mapping because its close stamp is the earlier transaction start. CR8 uses separate transactions and misses this case. Define the recorded-time convention consistently with the advertised instant-based API; wall-clock stamping addresses this intra-transaction case, but concurrent visibility still needs an explicit contract. This does not bypass G4's valid-date floor inside a closed period.

### S3 — Guard invariants validate trigger definitions, but only constraint names for recovery lineage

**Predicted; probe: `s3-invariant-check-definition.sql`.** Replacing `account_ledger_recovery_lineage_check` with a validated `CHECK (true)` passes `assert_periods_guard_invariants()`. The type-list check similarly requires only the presence of the `write_off_recovery` literal, not the exact accepted vocabulary. Tighten these checks if they are intended to defend the actual rules against drift. The function comment accurately disclaims function-body checking; do not describe it as validating those bodies. It also does not validate every new table CHECK/EXCLUDE constraint.

### S4 — W3's write-off aging threshold setting is missing

**Predicted, source finding.** The inventory explicitly says the schema records the tenant setting for the aging threshold that triggers write-off. The patch records reporting bucket boundaries, not a distinct write-off threshold; the source search found no defined threshold setting in the base either. Arbitrary JSON settings capacity is not a defined policy contract. Add the setting/history contract and check, or explicitly move that requirement out of -22. Do not substitute the last aging bucket edge without a ruling that they mean the same thing.

### S5 — Several test labels and coverage claims are broader than their checks

**Predicted, source finding.** CR7 checks later ledger postings, not later configuration writes or loaded future timestamps. CR8 checks separate-transaction mapping changes only. W13 is a useful cross-customer test, but there is no multi-hop chain, cyclic lineage, or reversal-before-original window test. CR3 exercises REPEATABLE READ, not SERIALIZABLE; CR4 also pins only REPEATABLE READ in its test inputs. I4's label promises the canonical policy, but its own query checks only the two RLS flags; I5 separately calls the tenant-isolation invariant. The race header's “every race leg” blocking observation is broader than CR3's sleep-based orchestration.

The mutation runner is meaningfully stronger than “any failure counts”: it requires the named first failure (or expected apply-error phrase). I found no specific mutation demonstrated to pass for an unrelated reason. Its regex permits letter-suffixed checks when the expected label has no suffix, so attribution is not strictly exact. Mutation success proves the selected perturbations are detected, not the missing cases above. The supplied probes request execution of concrete suspected gaps rather than rerunning that fixed-database-name runner.

## Notes and answers to the remaining brief questions

### N1 — The ordinary head handshake and statement shapes

**Predicted; probe: `n1-statement-shapes.sql` for the listed single-session cases.** For separate transactions at READ COMMITTED, a writer holding FOR SHARE keeps the closer's FOR UPDATE waiting; the volatile close's subsequent SQL statements can see the committed writer. A writer that has not reached the head when the close commits reads the advanced head and is rejected. REPEATABLE READ and SERIALIZABLE writers with older snapshots should fail serialization when locking the changed head. READ UNCOMMITTED has PostgreSQL's READ COMMITTED behavior. No separate-session isolation execution was performed or is claimed here.

The recovery and period-insert checks are volatile and restricted to READ COMMITTED, with transaction advisory locks. Ordinary multi-row inserts should see earlier rows for their cap/chain checks. The probe requests contiguous multi-row periods, an over-cap multi-row recovery, a writable ledger CTE consumed before calling close, and a write after one's own close. These are regression evidence requests, not newly asserted bypasses. Existing `void_invoice` inserts its reversal through the ledger freeze as `tally_void`; there is no new definer exemption. B2 is the concrete head-selection hole found.

### N2 — Period, head, snapshot and GL write protection

**Predicted, source finding.** Apart from the identified data/coordinate defects, I found no ordinary-role path to reopen, edit, delete, truncate, or create a closed period; forge or edit a snapshot; or move the head backward. Period insertion serializes the append-only chain, EXCLUDE backs overlap protection, and close checks the next boundary and UTC-12 end. The first-ever period intentionally has no predecessor. `now()` in the ended-everywhere check can conservatively delay a long transaction's close, not allow an early one.

GL specificity counts the charge pair as one dimension, plus class and the two places. NULL wildcards, highest-specificity tie rejection, and no-match NULL match the drafting call. INSERT and closure lock the same head and disallow an effective start/end on or before closed-through. Ending a mapping strictly after the boundary leaves its closed-period dates covered, even before/after the close is known in recorded time. No ordinary-role in-place account/key edit path was found. G2's export refusal remains a core responsibility, as the inventory explicitly states.

### N3 — Seal comparison and least privilege

**Predicted, source finding.** A source diff against the final -21 `assert_seal_role_invariants()` preserves the old checks and adds the third owner/function/grant list, the two head privileges for `tally_void`, and snapshot/head/status reachability checks. It does not remove an old seal guard. `tally_close` is created NOLOGIN without bypass or role-management powers; the invariant rejects existing roles with those powers, memberships in either direction, unexpected ownership, grants/default grants, or code-creation privileges. Its sole owned function is the pinned SECURITY DEFINER close. Fresh runtime catalog state has not been inspected.

`session_is_supervisor()` reads exactly `users.id`, `users.role`, and `users.tenant_id` (`tu.sql:23621`); those three column grants are sufficient and appropriately narrow. The two identity/RLS helpers are separately executable. `tally_void` needs an UPDATE privilege on some head column to take FOR SHARE; `updated_at` is sufficient and its trigger rejects actual unauthorized updates. Table SELECT is sufficient, but not literally the smallest possible read grant: the freeze only reads `tenant_id` and `closed_through`, not `updated_at`. This extra timestamp visibility is not a blocking write capability. The close's other SELECT lists are likewise explicit, not all column-minimized.

### N4 — Snapshot arithmetic and aging semantics

**Predicted, source finding.** Opening is before period_start; activity is inclusive of both period endpoints; closing is opening plus activity. Entry count is in-period activity count, not cumulative ledger count. Activity lines group by type; aging includes prior outstanding balances and separates credit balances. Unbilled revenue plus basis is properly supplied because the schema cannot derive the core's estimate. Other figures are computed. B1/B3/B4 qualify correctness and reconciliation.

For an acyclic same-customer forest, transitive netting is internally consistent. A parent outside either as-of window, or belonging to another customer, makes the visible reversal its own root. Thus a reversal dated before its original contributes independently until the original enters the window. Newest-first positive-root allocation leaves older debt paid first. Its filter `cum - net < balance` and `least(net, balance - (cum - net))` cannot produce a negative open part for such a forest; positive-root totals cover a positive overall balance. Cycles break the coverage premise (B3).

Both aging helpers are invoker-rights functions with explicit required coordinates and no live-setting fallback. Explicit tenant filtering remains in place for a platform administrator who can see all tenants. A tenant user cannot see another tenant's configuration or ledger and receives the stated no-data error. Status comes from historical events, and last location from the latest located ledger entry, as drafted; customer number is read live, so the whole presentation row is not an immutable customer-identity snapshot.

### N5 — Residuals R1–R9

**Predicted, source assessment.** R1/R2 and R3 are acceptable staged scope when stated accurately: non-ledger event/status coupling and per-bill allocation wait for -23; a status move is not presently guaranteed to write its own ledger row merely because the header describes that intended workflow. R4 is a reasonable transaction-time status choice. R5 is an explicit approximation until occupancy exists. R6 duplicates vocabularies and needs maintenance; R7's lookup-time tie failure is deterministic and deliberate. R9's pre-deployment no-history error is preferable to invented configuration.

R8 is acceptable for deferring general sign and cap enforcement, but it is **not** acceptable as a reason for B3's silent aging omission. None of the other stated residuals authorizes B1, B2, or B4. The patch substantially implements the intended P/S/G/W shape; those four correctness gaps and the W3 setting omission prevent calling the current implementation complete.

## Probe outputs (run by the author on a clone with the frozen r1 patch, 2026-10-15)

### b1-aging-coordinate.sql
```
NOTICE:  OBSERVED B1 before=[{"amount": 100.00, "balance": 100.00, "customer_id": "232e7408-11f0-4c06-923d-995c128d02f6", "bucket_index": 0, "bucket_to_days": 30, "customer_number": "CX-1", "customer_status": "active", "bucket_from_days": 0, "last_location_id": null}] after=[{"amount": 100.00, "balance": 100.00, "customer_id": "232e7408-11f0-4c06-923d-995c128d02f6", "bucket_index": 1, "bucket_to_days": 45, "customer_number": "CX-1", "customer_status": "active", "bucket_from_days": 16, "last_location_id": null}] changed=t
NOTICE:  OBSERVED B1 snapshot edges={30,60,90,120}; as-of edges={15,45}
NOTICE:  OBSERVED B1 manual backdate accepted; same-coordinate edges now={10,20}
```

### b2-payment-tenant-move.sql
```
c33b14e5-4384-4b69-a298-a5e493b276fe
NOTICE:  OBSERVED B2 accepted move from closed-through 2020-01-31 to open tenant; row={"id":"27ec0398-be96-4b91-b6c5-ce4a29bfdbff","tenant_id":"77069eb2-8924-474e-a6fb-811031d88ee0","payment_number":"CX-P","customer_id":"d2e9ff78-b023-47ee-a25c-6d688d51dd71","payment_date":"2020-02-01","amount":10.00,"payment_method":"check","payment_method_id":null,"channel":"walk_in","source_system":"internal","reference_number":null,"provider_transaction_id":null,"provider_authorization_code":null,"check_number":null,"check_date":null,"check_bank_name":null,"status":"pending","applied_amount":0.00,"unapplied_amount":0.00,"is_deposit":false,"deposit_status":null,"nsf_date":null,"nsf_reason":null,"nsf_fee_charge_id":null,"nsf_original_payment_id":null,"refunds_payment_id":null,"refund_reason":null,"reversed_at":null,"reversed_by":null,"reversed_reason":null,"notes":null,"received_by":null,"metadata":{},"created_at":"2026-10-16T02:14:27.319584+00:00","updated_at":"2026-10-16T02:14:27.319584+00:00","effective_date":null,"effective_date_method":null,"return_code":null,"refunds_customer_credit_id":null}
```

### b3-lineage-cycle.sql
```
NOTICE:  OBSERVED B3 ledger=60.00 aging rows=0 aging sum=<NULL>
NOTICE:  OBSERVED B3 snapshot closing=60.00 aging lines=0
```

### b4-future-recorded-ledger.sql
```
NOTICE:  OBSERVED B4 snapshot closing=0.00 entry count=0; actual frozen-date ledger=100.00; future timestamp=2026-10-17 02:14:27.502261+00
```

### n1-statement-shapes.sql
```
NOTICE:  OBSERVED N1 contiguous periods in multi-row statement=3
NOTICE:  OBSERVED N1 recovery statement refused: 23514 write-off eb805bc9-91f4-41f6-b534-d55f2d020360: recoveries of 60.00 would exceed the 50.00 written off (R-02 cap, v5.4.2-22)
NOTICE:  OBSERVED N1 cap SQLSTATE=23514 surviving recovery count=0
NOTICE:  OBSERVED N1 CTE close at=2026-10-16 02:14:27.58682+00 snapshot closing=75.00 ledger=75.00
NOTICE:  OBSERVED N1 after-close write refused: 23514 account_ledger: dated 2020-01-07, on or before 2020-01-31, the end of the tenant's last closed accounting period — a closed period is frozen; post the correction into an open period (D-2, v5.4.2-22)
```

### s1-array-bounds.sql
```
NOTICE:  OBSERVED S1 validator=t for [0:1]={-10,30}
NOTICE:  OBSERVED S1 accepted invalid edges; history reader normalizes to {-10,30}
```

### s2-gl-recorded-coordinate.sql
```
NOTICE:  OBSERVED S2 at=2026-10-16 02:14:27.774779+00 before=55cb68a6-c1fb-4976-a178-171d13d51775 after=<NULL> close stamp=2026-10-16 02:14:27.767301+00
```

### s3-invariant-check-definition.sql
```
NOTICE:  OBSERVED S3 invariant accepted a vacuous recovery lineage CHECK
```
