Verdict: **not yet** — v5.4.2-23, review round 1.

**Evidence convention:** **executed** means local hash verification, source reading, or textual comparison only. **Predicted** means database behavior inferred from source, with an author-run probe supplied below. I ran no database commands, Docker, CI, race script, or mutation runner. I did not read either other reviewer's files. All SQL line references below refer to `patch-23-frozen-r1.sql` unless a different file is named.

**N1 — executed: frozen inputs and authority.** All five MD5s matched before substantive review:

| Frozen file | Verified MD5 |
|---|---|
| patch-23-frozen-r1.sql | bf3b0967108fd0b8b5f91fca698fa750 |
| battery-23-frozen-r1.sql | 7d5b575d23e16f5bb384a4a0ab152313 |
| cash-23-frozen-r1.sh | 92e5424766121b8362dfdc21dc2dc9d5 |
| mutations-23-frozen-r1.py | 76de756ce7c9c57cb1d46ed6b5b6e0d2 |
| older-tests-23-frozen-r1.diff | 9a513066de9b060a6e71ac3266075c90 |

Read the design, inventory/triage and DECISION-LOG under tally-utility/application, and the October 15 and July 10 Kyle decisions under gas-billing-memory/application. U and L belong to -24. The 1,000-entry bound is an explicit decision, not a defect to solve by lowering it. I am not deciding restriction versus floor.

**B1 — predicted: credit donation/escheat spending is omitted from the cap and position (A3, M1, M3).**

`cash_source_draws` (1568–1583) enumerates applications, overpayment credits, and pending/posted refund payments only. Neither donation ledger entries nor escheat remittances participate. The credit position (1036–1057) has the same omission. The status guard (1349–1377) checks the existence of a donation/escheat cause, but does not require the donation amount to consume exactly the remainder or include it in the shared cap.

Concrete path: issue a 100 goodwill credit; record a 100 donation referencing it; refund another 100 from that still-active credit; then move the credit to donated, naming the donation. Predicted result: both disbursements are admitted and the terminal status is admitted. A second case names a donation of only 1 to end a credit whose derived remainder remains 100. These are ordinary writes, without disabled guards. The design explicitly includes donation/escheat among the three destinations of credit money and requires nothing left on donation; the comment saying the remainder “left with its status move” does not implement those requirements.

Probe: [01-donation-cap.sql](codex-r1-probes/01-donation-cap.sql). Expected safe behavior is refusal of the second draw and refusal of the mismatched terminal donation. Include donation/remittance records and their corrections in one dated, recorded, source-locked accounting of draws; validate the actual terminal cause against that accounting.

**B2 — predicted: the source lock does not protect source eligibility in both directions; status updates also lack an isolation pin (A3, M3).**

In `enforce_invoice_application`, payment/credit status is copied and validated before `check_cash_source` acquires the source lock (1668–1773). `enforce_cash_draw` likewise computes `v_ok` before that lock (1835–1864). The post-lock check rereads the amount and draws, but never revalidates status. The payment and credit UPDATE guards take advisory locks, but neither refuses REPEATABLE READ/SERIALIZABLE.

Two distinct schedules:

1. READ COMMITTED: A changes an unapplied payment to nsf and holds its source lock uncommitted. B starts afterward, reads the old posted version, and blocks acquiring that source lock. A commits. B resumes, checks only the numerical cap, and admits an application from the now-nsf payment. A status-only UPDATE does not change the FK key, so the referencing key-share lock is not the necessary handshake. The same pre-lock validation pattern exists for refunds and overpayment credits.
2. REPEATABLE READ: A establishes its snapshot while the payment is posted and unapplied. B applies 10 and commits. A changes the payment to nsf using an already-existing valid cause. The advisory lock cannot refresh A's snapshot, and B did not update the payment row, so the guard's application sum can remain zero. Predicted result: the UPDATE succeeds despite the committed application.

Probes: run [05-race-fixtures.sql](codex-r1-probes/05-race-fixtures.sql) on a fresh clone, then [06-rc-status-A.sql](codex-r1-probes/06-rc-status-A.sql) and [07-rc-draw-B.sql](codex-r1-probes/07-rc-draw-B.sql) as directed. On a separate fresh clone, run 05 then [08-rr-status-A.sql](codex-r1-probes/08-rr-status-A.sql) and [09-rr-draw-B.sql](codex-r1-probes/09-rr-draw-B.sql). Safe outcomes are a rejection/retry, not an accepted inconsistent pair.

Acquire the source lock before the final eligibility read, then read at READ COMMITTED; put an equivalent isolation requirement on terminal status changes. CR3 tests only the opposite ordering—application first, status second—and therefore does not cover schedule 1.

**B3 — predicted: fixed as-of coordinates do not identify a reproducible position (M1; R2 is blocking).**

The payment and credit readers filter refund creation time/date, then consult the refund's *current* status (1023, 1049). Insert a pending refund of 40 against a payment of 100, read its position, void that pending refund legally, and reread at exactly the same money date and recorded instant. Predicted remainder changes from 60 to 100. The credit-source reader behaves the same way. This changes money, not merely a descriptive lifecycle label, so -22's live customer-status residual is not an adequate precedent.

The line reader also takes `l.amount` from the live line without checking whether the bill/line existed at either coordinate (1068–1074). The invoice reader aggregates those live lines (1092–1096). An issued March bill is therefore returned with its amounts for coordinates in January 2000, before the bill existed. Requiring non-NULL coordinates does not make those amounts historical.

Probe: [02-historical-positions.sql](codex-r1-probes/02-historical-positions.sql), which prints both refund-source cases and the pre-existence line/invoice reads. Represent refund cancellation with dated/recorded evidence that can be evaluated at the requested coordinates; gate the billed artifact by its existence/issuance coordinates and define any draft-reading semantics explicitly.

**B4 — predicted: a status cause may exist without being the act the status claims (M3/Q1(a)).**

The payment posting branch (1232–1235) checks reference identity and amount but omits `transaction_type`. A pending payment of 100 can become posted by citing an `adjustment` of -100; the design specifically requires the payment posting entry, or deposit posting for a deposit. This does not challenge the expressly permitted birth of a payment already posted—it is a bypass of the new transition rule.

Likewise the credit escheated branch (1349–1350) accepts any `escheatment_events` row naming the credit. A `dormancy_flag` with no remittance is sufficient to end the credit as escheated. A row about the credit is not necessarily the row that caused its money to leave.

Probe: [03-status-cause.sql](codex-r1-probes/03-status-cause.sql). Require the matching posting type/designation, and the actual remittance event type for escheatment. Audit the other cause branches to distinguish the posting/issuing entry from arbitrary entries merely sharing its reference.

**S1 — predicted: the cash privilege invariant misses column-level UPDATE grants.**

The final privilege check uses `has_table_privilege` only (2820–2821). `GRANT UPDATE(reason) ON invoice_applications TO tally_app` gives the role an UPDATE privilege while that test still reports no table UPDATE. The append-only trigger remains a separate defense, so this is an invariant-coverage problem rather than a demonstrated data mutation bypass. Probe: [04-catalog-contract.sql](codex-r1-probes/04-catalog-contract.sql). Check column privileges as well as table privileges, consistent with the invariant's claim.

**S2 — predicted: battery I1/I2 can succeed without invoking any invariant function.**

`battery-23-frozen-r1.sql:685–690` uses `assert_*() IS NULL OR true`. The constant true permits simplification of the expression without calling the function. Probe 04 disables a claimed trigger, evaluates the I1 expression, and then invokes the invariant directly with the error printed. Call each invariant directly with SELECT/PERFORM and report success afterward. The patch tail and CI's direct calls are separate checks; this finding does not claim those calls are skipped.

**S3 — executed (source), predicted (catalog): the documented head-lock rule is not followed on approvals or status-only updates.**

The design says approval writes take the close head FOR SHARE. The approval table receives stamp, append-only and no-truncate triggers but no head-taking guard. Payment/credit freeze triggers fire only on INSERT or UPDATE OF date/tenant; status-only updates go straight to the source advisory lock. Neither rewritten status function explicitly takes the head. Probe 04 prints the relevant trigger definitions. Reconcile these omissions with the stated rule and include the guards in the invariants. Approval alone does not spend money, so I have not promoted its missing handshake into an additional cap blocker. The status-isolation consequence is already B2.

**S4 — executed: some tests do less than their labels, and important dimensions are absent.**

- A2h supplies a *positive* undo. Its expected failure is the sign CHECK, so it does not test the trigger's “cannot undo an undo” branch. Add a negative undo naming an undo, with all shape constraints otherwise satisfied.
- The older -22 R10 now expects an opposite-sign failure but keeps a label describing ancestor-cap coverage. The rewritten -22 CR11 posts siblings directly under the write-off while its result label still says “reached through its recovery.” Rename them and retain a legal nested race elsewhere.
- R10g changes from 301 inserted entries to 200; R11b/c plant the long prefix with guards disabled. This reduces full-chain construction/performance coverage, but is explicitly explained by the accepted quadratic/cubic cost and supplemented by guarded boundary appends and R11e. It is not evidence of unchanged old coverage, nor a reason to lower the approved bound.
- The new battery lacks a rate-item-version line-class negative case, donation/escheat cap cases, refund cancellation replay, the reverse ordering of CR3, and non-READ-COMMITTED terminal moves. Add these to the maintained checks and mutation targets.

**N2 — executed source analysis; predicted database outcomes: the reversal algorithm is structurally sound.**

For a row on the downward walk, `m` is the count of insertion-path ancestors above it. While following the path it increases once per edge; after divergence it remains fixed. Thus expanding `j=1..m` includes exactly the same (ancestor, descendant) pairs as walking each path ancestor's subtree independently. The ancestor itself is excluded. Siblings contribute to their common ancestors but not to the other sibling's subtree. The window's default RANGE frame groups same-date peers, matching the specified date netting. Earlier-dated children are rejected separately. An insertion on a different branch changes only the ancestors of that insertion; its own trigger checks those ancestors.

The root comes from immutable parent links, the cap's upward walk fails closed, and the void explicitly takes the root lock before reading the remainder and inserting its reversal. I found no source path giving two normal writers different roots for the same tree. All five relevant walk/helper functions have the pinned planner settings in source. `ledger_tree_ids` has no explicit depth predicate, but uses UNION over IDs, so even a corrupted finite cycle terminates by deduplication; the normal lineage gate supplies the 1,000-entry bound. This is not an unbounded UNION ALL traversal.

Author probes: [10-frozen-battery-coverage.sql](codex-r1-probes/10-frozen-battery-coverage.sql), [11-copy-and-cte.sql](codex-r1-probes/11-copy-and-cte.sql), [12-reversal-branches.sql](codex-r1-probes/12-reversal-branches.sql). These cover existing X checks, aggregate statement caps, same-date peers and sibling/ancestor separation; they are not runtime results from this review.

**N3 — executed: seal comparison and invariant inventory.**

A textual comparison of `assert_seal_role_invariants()` against -22 found exactly one changed source line: the `tally_void` grant array gains the four named ledger helpers. Those are needed by the invoker-rights call graph: void → root/key/remaining, remaining → tree_ids; reversal enforcement also calls the key helper. I found no extra definer or data-write grant in that change. Probe 04 calls the seal invariant directly; probe 10 exercises the void as tally_app.

Counted 28 trigger-definition strings and 34 constraint-definition strings in the cash invariant. Its loops check exact catalog renderings, ALWAYS enablement, and constraint validation; it also pins the approval index text, absent counters and four helper/walk configurations. It explicitly does not compare guard function bodies. The column-grant hole is S1. The five-column approval FK, the non-NULL source condition and unique approval index address the nullable-FK and reuse cases in source. Probe 10 carries the C1 checks and the existing shape, write-once, restriction, tariff and class checks.

**N4 — executed source assessment; predicted remaining database checks: requirements and concurrency.**

X1–X4 have no additional source blocker identified. M2/M4's counter/designation removal and immutable money fields are present; effective-date/return-code protection also depends on the retained -19 guard. M1 and M3 have B1–B4. A1/A2 and A4–A6 have their specified shapes; A3 has B1/B2. C1 has its approval identity/amount/reuse checks and draw cap, subject to B2's eligibility race; C2 removes the retired choice.

Both restriction and floor-over-restriction are represented: the first names the restricted target; the second requires an outside regulated line and an unregulated positive target. Operator override is explicit with user/reason. The tariff checks cover own utility and completeness, use rule_row_cite for the effective date, and compute the close floor from the latest citing application's date. Undos do not erase that historical citation. The line-class trigger has the same issue/void/previously-issued/snapshot gating as the arithmetic trigger and reads the rate version at snapshot valid_at under now(), as that established convention does. These observations do not certify the absent rate-version negative test noted in S4.

The numerical application/source caps acquire advisory locks; they are not bare unlocked counts. The defect is what is validated outside those locks and which isolation levels can enter the other side. Multi-object transactions can acquire equal-rank locks in opposite orders; PostgreSQL deadlock retry is the stated policy. I found no source proof of an inherently unresolvable deadlock, but retries cannot fix B2's accepted stale decision. The complete documented order should also acknowledge the pre-existing invoice row lock taken by void_invoice before the head, as well as UPDATE row locks on status changes.

Probe [13-serializable.sql](codex-r1-probes/13-serializable.sql) checks the draw/reversal pins; [14-role-reach.sql](codex-r1-probes/14-role-reach.sql) checks core reading versus writing and app immutability. Probe 10 covers app tenant isolation, tally_void via its definer, and the owner/tally_close fixture paths. Superuser history-time checks are included there. No role was created, dropped or altered by this review.

**N5 — executed: tests, mutations and residuals disposition.**

The mutation runner checks the first FAIL/ERROR/FATAL/PANIC line against the named test, and its replacements assert unique anchors. I found no specific additional wrong-first-failure attribution from source; I cannot independently certify the reported 71/71, strict apply twice, 107 checks or 38 CI steps. I did not run them. Structural mutations applied before the tail are tested by direct invariant calls, independent of S2.

The older-test changes generally follow the new rules: line class is supplied; counters disappear; overpayment-only fixtures become adjustments where origin is irrelevant; immutable identity/lineage refusals replace obsolete move races; illegal cross-customer/same-sign/backdated/future reversal fixtures are rewritten or deliberately planted for a distinct downstream defense. The performance-coverage reduction and stale labels are specifically called out in S4 rather than described as equivalent coverage.

Residual assessment: R1 is accepted by explicit decision; **R2 is blocking (B3)**; R3 is an explicitly retained app-written lifecycle label; R4's existing applications on void are a documented core undo/rebill responsibility; R5 is a maintenance duplication; R6 delegates source-less classification to the core; R7 delegates allocation and notification policy, including the unresolved restriction/floor choice; R8 describes rule-driven test changes with the qualifications in S4. None of R3–R8 excuses B1/B2/B4.

**N6 — executed: probe delivery and limits.**

Every probe is under `codex-r1-probes/`, starts from owner access on a fresh clone with frozen r1 already applied, and ends in ROLLBACK. Single-session probes roll back their fixtures. The concurrency probes necessarily commit scratch fixtures (05) and the competing transaction (06 or 09) so the other session can observe it; use a separate disposable clone for each schedule and discard it afterward. They finish with an empty rolled-back transaction. No probe creates/alters cluster roles. Caught errors print SQLSTATE and message with RAISE NOTICE. The COPY probe prints its own verbose server error and does not use LAST_ERROR_SQLSTATE. Probe 10 is the frozen battery copied into the allowed probe directory with full caught-error notices; it remains unexecuted.

Only this review and these probe files were written. SQL execution and confirmation of the predicted outcomes remain with the author.

---

## Author-run probe results (2026-10-17, Claude)

Run on fresh clones of `tally` with frozen r1 strict-applied twice (search_path '', check_function_bodies on; TEMP revoked). `psql -X -q -At`, NOTICE lines kept. Race probes: each `\prompt` replaced by `SELECT pg_sleep(6)`, B launched 2 s after A; pg_stat_activity confirmed B waiting on the advisory lock (RC) before A committed. Clones cx1, cxrc, cxrr dropped.

| Item | Result |
|---|---|
| B1 donation cap | **confirmed**: refund after a full donation accepted; terminal donation after the double draw accepted; a 1.00 donation ends a credit with 100 left |
| B3 positions | **confirmed**: voiding a pending refund moves a fixed-coordinate payment position 60 → 100 and a credit position 60 → 100; line and bill amounts are returned for coordinates before the bill existed |
| B4 status cause | **confirmed**: an adjustment accepted as a payment's posting entry; a dormancy flag accepted as the escheatment cause |
| B2 schedule 1 (RC) | **confirmed**: payment ends nsf with 10.00 applied |
| B2 schedule 2 (RR) | **confirmed**: RR transaction moves the payment to nsf over a committed 10.00 application |
| S1 column grant | **confirmed**: `has_table_privilege` false after GRANT UPDATE(reason); invariant passes |
| S2 I1 expression | **confirmed**: expression true with a guard disabled; the direct call raises 0LP01 |
| 10 battery copy | 107 PASS, 0 FAIL |
| 11 COPY/CTE, 12 branches, 13 serializable, 14 role reach | all refused or admitted as the probe expects (N2/N4 hold) |

Raw output: single-session probes and race transcripts are reproduced below.

```
##### 01-donation-cap.sql
psql:/tmp/cx.sql:59: NOTICE:  B1 refund after full donation: SQLSTATE=00000 accepted
psql:/tmp/cx.sql:61: NOTICE:  B1 terminal donation after double draw: SQLSTATE=00000 accepted
00000000-0000-4000-8000-00000000cd03|2026-03-06|100.00|2026-10-18 01:16:49.310664+00
100.00|0|100.00|0.00
psql:/tmp/cx.sql:69: NOTICE:  B1 donation amount unrelated to remainder: SQLSTATE=00000 accepted
100.00|0|0|100.00
##### 02-historical-positions.sql
before refund void|100.00|0|0|40.00|60.00
psql:/tmp/cx.sql:59: NOTICE:  B3 pending refund void: SQLSTATE=00000 accepted
after refund void|100.00|0|0|0|100.00
line before bill date/recording|60.00|0|60.00
bill before bill date/recording|90.00|0|100.00
credit before|100.00|0|40.00|60.00
psql:/tmp/cx.sql:71: NOTICE:  B3 credit refund void: SQLSTATE=00000 accepted
credit after|100.00|0|0|100.00
##### 03-status-cause.sql
psql:/tmp/cx.sql:57: NOTICE:  B4 adjustment used as posting entry: SQLSTATE=00000 accepted
posted|00000000-0000-4000-8000-00000000cd02
psql:/tmp/cx.sql:66: NOTICE:  B4 dormancy flag used as escheatment cause: SQLSTATE=00000 accepted
##### 04-catalog-contract.sql
psql:/tmp/cx.sql:54: NOTICE:  cash invariants baseline: SQLSTATE=00000 accepted
psql:/tmp/cx.sql:55: NOTICE:  seal invariants baseline: SQLSTATE=00000 accepted
psql:/tmp/cx.sql:56: NOTICE:  period invariants baseline: SQLSTATE=00000 accepted
customer_credit_approvals|CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.customer_credit_approvals FOR EACH ROW EXECUTE FUNCTION stamp_log_created_at()
customer_credit_approvals|CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON public.customer_credit_approvals FOR EACH ROW EXECUTE FUNCTION enforce_append_only()
customer_credit_approvals|CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.customer_credit_approvals FOR EACH STATEMENT EXECUTE FUNCTION enforce_no_hard_delete()
customer_credits|CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT OR UPDATE OF issued_date, tenant_id ON public.customer_credits FOR EACH ROW EXECUTE FUNCTION enforce_accounting_freeze('issued_date')
customer_credits|CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.customer_credits FOR EACH ROW EXECUTE FUNCTION stamp_log_created_at()
customer_credits|CREATE TRIGGER enforce_cash_draw AFTER INSERT ON public.customer_credits FOR EACH ROW WHEN ((new.origin_type = 'overpayment'::text)) EXECUTE FUNCTION enforce_cash_draw()
customer_credits|CREATE TRIGGER enforce_customer_credit_deposit_lineage BEFORE INSERT OR UPDATE OF origin_type, deposit_id ON public.customer_credits FOR EACH ROW EXECUTE FUNCTION enforce_customer_credit_deposit_lineage()
customer_credits|CREATE TRIGGER enforce_customer_credit_immutable BEFORE UPDATE ON public.customer_credits FOR EACH ROW EXECUTE FUNCTION enforce_customer_credit_immutable()
customer_credits|CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.customer_credits FOR EACH ROW EXECUTE FUNCTION enforce_no_hard_delete()
customer_credits|CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.customer_credits FOR EACH STATEMENT EXECUTE FUNCTION enforce_no_hard_delete()
customer_credits|CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.customer_credits FOR EACH ROW EXECUTE FUNCTION update_updated_at()
payments|CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT OR UPDATE OF payment_date, tenant_id ON public.payments FOR EACH ROW EXECUTE FUNCTION enforce_accounting_freeze('payment_date')
payments|CREATE TRIGGER a_enforce_payment_lineage BEFORE INSERT OR UPDATE OF refunds_payment_id, nsf_original_payment_id, customer_id, tenant_id ON public.payments FOR EACH ROW EXECUTE FUNCTION enforce_payment_lineage()
payments|CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.payments FOR EACH ROW EXECUTE FUNCTION stamp_log_created_at()
payments|CREATE TRIGGER enforce_cash_draw AFTER INSERT ON public.payments FOR EACH ROW WHEN (((new.refunds_payment_id IS NOT NULL) OR (new.refunds_customer_credit_id IS NOT NULL))) EXECUTE FUNCTION enforce_cash_draw()
payments|CREATE TRIGGER enforce_payment_effective_date BEFORE UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION enforce_payment_effective_date()
payments|CREATE TRIGGER enforce_payment_immutable BEFORE UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION enforce_payment_immutable()
payments|CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.payments FOR EACH ROW EXECUTE FUNCTION enforce_no_hard_delete()
payments|CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.payments FOR EACH STATEMENT EXECUTE FUNCTION enforce_no_hard_delete()
payments|CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION update_updated_at()
t|f
psql:/tmp/cx.sql:63: NOTICE:  S1 invariant after column grant: SQLSTATE=00000 accepted
t
psql:/tmp/cx.sql:70: NOTICE:  S2 direct invocation detects disabled trigger: SQLSTATE=0LP01 message=a v5.4.2-23 guard is missing, changed, or not ENABLE ALWAYS:
  CREATE TRIGGER enforce_invoice_application AFTER INSERT ON public.invoice_applications FOR EACH ROW EXECUTE FUNCTION enforce_invoice_application()
##### 10-frozen-battery-coverage.sql: 107 PASS, 0 FAIL (output elided)
##### 11-copy-and-cte.sql
psql:/tmp/cx.sql:60: NOTICE:  00000: N multirow cap, aggregate 120 of 100: SQLSTATE=23514 message=entry 00000000-0000-4000-8000-00000000cd01 (charge, 100.00): on 2026-03-02 the rows netted against it would come to -120.00, outside 0 to -100.00 — reversals of an entry total at most the entry, with the opposite sign (R-02 cap, v5.4.2-23)
LOCATION:  exec_stmt_raise, pl_exec.c:3897
psql:/tmp/cx.sql:66: NOTICE:  00000: N writable CTE cap, aggregate 120 of 100: SQLSTATE=23514 message=entry 00000000-0000-4000-8000-00000000cd01 (charge, 100.00): on 2026-03-02 the rows netted against it would come to -120.00, outside 0 to -100.00 — reversals of an entry total at most the entry, with the opposite sign (R-02 cap, v5.4.2-23)
LOCATION:  exec_stmt_raise, pl_exec.c:3897
psql:/tmp/cx.sql:74: ERROR:  23514: entry 00000000-0000-4000-8000-00000000cd01 (charge, 100.00): on 2026-03-02 the rows netted against it would come to -120.00, outside 0 to -100.00 — reversals of an entry total at most the entry, with the opposite sign (R-02 cap, v5.4.2-23)
CONTEXT:  PL/pgSQL function enforce_ledger_reversal() line 144 at RAISE
LOCATION:  exec_stmt_raise, pl_exec.c:3897
100.00
##### 12-reversal-branches.sql
psql:/tmp/cx.sql:61: NOTICE:  branch B over-undo: root would be legal, B would not: SQLSTATE=23514 message=entry 00000000-0000-4000-8000-00000000cd03 (adjustment, -40.00): on 2026-03-04 the rows netted against it would come to 41.00, outside 0 to 40.00 — reversals of an entry total at most the entry, with the opposite sign (R-02 cap, v5.4.2-23)
psql:/tmp/cx.sql:64: NOTICE:  root cap includes sibling B when posting under A: SQLSTATE=23514 message=entry 00000000-0000-4000-8000-00000000cd01 (charge, 100.00): on 2026-03-02 the rows netted against it would come to -101.00, outside 0 to -100.00 — reversals of an entry total at most the entry, with the opposite sign (R-02 cap, v5.4.2-23)
psql:/tmp/cx.sql:69: NOTICE:  same-date peers net together despite row order: SQLSTATE=00000 accepted
0.00
##### 13-serializable.sql
psql:/tmp/cx.sql:58: NOTICE:  serializable refund must be refused at 25000: SQLSTATE=25000 message=a row drawing on payment 00000000-0000-4000-8000-00000000cd01 is written at READ COMMITTED (this transaction is serializable): its cap must see every row committed while it waited (R-06, v5.4.2-23)
psql:/tmp/cx.sql:63: NOTICE:  serializable reversal must be refused at 25000: SQLSTATE=25000 message=a reversal is posted at READ COMMITTED (this transaction is serializable): its cap must see every row committed while it waited (R-02, v5.4.2-23)
##### 14-role-reach.sql
psql:/tmp/cx.sql:59: NOTICE:  core read position: SQLSTATE=00000 accepted
psql:/tmp/cx.sql:60: NOTICE:  core cannot write money: SQLSTATE=42501 message=permission denied for table payments
psql:/tmp/cx.sql:63: NOTICE:  app cannot rewrite amount: SQLSTATE=23001 message=payment CDX-pay: amount is written once, at insert or when first recorded (R-05, CI-013; v5.4.2-23) — reverse the payment and post a new one
##### rc-A
psql:/tmp/race-06.sql:10: NOTICE:  B2 RC status: SQLSTATE=00000 accepted

##### rc-B
psql:/tmp/race-07.sql:11: NOTICE:  B2 draw after source ends: SQLSTATE=00000 accepted
nsf|10.00
##### rr-A
posted

psql:/tmp/race-08.sql:12: NOTICE:  B2 RR terminal status after concurrent application: SQLSTATE=00000 accepted
nsf
##### rr-B
psql:/tmp/race-09.sql:11: NOTICE:  B2 concurrent draw: SQLSTATE=00000 accepted
```
