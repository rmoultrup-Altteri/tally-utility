# Codex review — v5.4.2-24, round 6

**Verdict: not yet.** The two round-5 misposting examples are addressed, but a recorded-time variant remains: a return can precede the recording of the ledger reversal it spends. One blocking prediction (B1) and two should-fix predictions (S1–S2) follow. None is represented as an executed database result.

## N1 — executed: frozen identity and review scope

Checked the brief against its `.md5` first, then all six frozen files, before reviewing source. All matched:

| File | md5 |
|---|---|
| review-brief-24-r6.md | 5445398e46075576da4f0dd966c68d0f |
| patch-24-frozen-r6.sql | d25affc7995ee7ae3f586fc1569e7dc5 |
| battery-24-frozen-r6.sql | 9ea5569e4f4ae54443140deba2bddc66 |
| suspense-24-frozen-r6.sh | 55c631999a54b336848e18cb06c80331 |
| mutations-24-frozen-r6.py | b5a28245eb207b450bf7ea895a76bfae |
| ci-24-frozen-r6.diff | c343828be614b5abf30a15944402ee0c |
| r5-to-r6.diff | 01c0547cec70e8b9d528f75fdfd47842 |

Source only: no Docker, psql, CI, races or mutation runner executed. No `opus-*.md` or `fable-*.md` read. Earlier findings are identified through the authorized r2–r6 plans and my own r1/r5 reviews. Authority consulted: tally-utility's design, source inventory and DECISION-LOG; GBM's CI-053, CI-056 and the two specified workflows. Ryan's acceptance of L5/L6 is explicit in the 11-07 DECISION-LOG.

File checks verified all **28 embedded body md5s** against the frozen function bodies and counted **269 battery assertion call sites**. These are source checks, not successful database checks. The author's r5 probe logs contain 260 battery PASS notices and the seven PASS notices confirming my prior B1/control; they are historical author evidence, not r6 execution. Strict double apply, 269 checks, 24 race results, 113 mutation catches and 63 CI steps remain reported results, not reproduced here.

All r6 database predictions below have files in [codex-r6-probes](codex-r6-probes/). Run each as owner on its **own fresh clone with frozen r6 applied**, with clone TEMP revoked from PUBLIC/app/core as required by the brief. Existing-role switches are local; no cluster role is created, altered or dropped. Every file ends in ROLLBACK. Caught errors print SQLSTATE and message. Probe 02 catches COPY's server exception directly, not psql's LAST_ERROR_SQLSTATE.

## B1 — predicted: a misposting return can be recorded before its ledger evidence

**Evidence:** frozen patch `check_suspense_recorded_order`, lines 653–660, reads disposition timestamps, payment birth timestamps and void/reversal **status** timestamps. It does not read ledger timestamps. `enforce_suspense_disposition`, lines 991–1011, now walks the complete posting tree for its latest **business date**, but not its latest `created_at`.

The inherited `enforce_payment_immutable` does not establish the missing implication for every admitted history load. In `sql/v5.4.2-23-cash-reversals-positions-application.sql` (function name is the authoritative locator), its lineage-time check is conditional on `v_super AND NEW.status_recorded_at <> now()`. A status update that leaves its timestamp untouched stamps it at `now()` and skips that check. A superuser's ledger `created_at = clock_timestamp()` is preserved and is finite and already reached, yet later than transaction start. No trigger disabling is needed.

**Probe:** [01-recorded-tree-time.sql](codex-r6-probes/01-recorded-tree-time.sql).

1. As owner at READ COMMITTED, record receipt 100 and post customer C1's payment 100, dated March 10; their recorded timestamps are transaction start.
2. Insert its +100 misposting reversal, dated March 11, with `created_at = clock_timestamp()`.
3. Move the payment to reversed, naming that reversal, without overriding `status_recorded_at`. Predicted: admitted, stamped at transaction start, before the reversal's recording. The probe explicitly checks this prerequisite.
4. Insert a March-11 misposting return 100 with default `created_at = now()`. Predicted: admitted. Every r6 business-date bound is satisfied.
5. Read March 11 as known at transaction start. Predicted: **suspense holds 100 and C1's payment received 100**. The return is visible; its supporting ledger reversal is not.
6. Post C2's replacement payment 100, also recorded at transaction start. Predicted: admitted, and the two payment positions total **200 received at the same coordinates from receipt 100**. At current knowledge they total 100.

The positive control rolls back the early return/replacement and explicitly records the return at `clock_timestamp()`: predicted suspense held zero at the earlier instant and 100 at current knowledge. The probe logs caught errors and asserts the prerequisites; if an inherited guard refuses one, report that exact error and reassess this prediction.

This is historical double recognition, not a claim that the final current position contains 200. It is also not cured merely by waiting until the read coordinate is older than every open transaction: if these rows were committed, their stored timestamps would still have this ordering. The probe itself rolls everything back.

**Fix:** order a misposting return's `created_at` after every ledger timestamp that supplies its share, including the full tree whose dates r6 now walks. Do not infer this from `status_recorded_at` alone. Follow the existing policy: an old transaction-start stamp retries with 40001; an explicitly chosen earlier stamp is refused with 23514. Preserve business-date checks and positive-NSF subtree pruning. Add a regression and mutation for the ledger-recording bound. Repairing the inherited status-time gap separately would also be useful, but -24's release needs an explicit trustworthy precondition.

**Prior finding relationship:** Codex r5 B1's exact March-11/12/13 business-date case is closed. The broad recorded-order guarantee behind Codex r1 B4 and r2 probe 03 is still incomplete in this distinct history-load shape.

## S1 — predicted: M74 now catches changed wording, not loss of the date protection

**Evidence:** frozen M74 replaces `IF v_rev_on IS NULL OR NEW.disposed_on < v_rev_on THEN` with false and names P9b2. P9b2 requires the message fragment `on or after its reversal`. Under r6, that same illegal return still reaches the complete-tree date guard and is refused with `last row under its posting entry`. The helper reports FAIL because the message differs; the runner recognizes that named first failure as a catch.

**Probe:** [07-redundant-reversal-date.sql](codex-r6-probes/07-redundant-reversal-date.sql). It demonstrates the original refusal, temporarily makes precisely M74's edit inside a savepoint, predicts the same SQLSTATE 23514 from the other guard, and checks the valid date still succeeds. It restores the function by rollback; it does not run the mutation runner.

For valid -23 data the named reversal belongs to the tree, so its date cannot exceed the tree maximum. Removing its separate date check does not admit P9b2's operation. This is analogous to the payment-bound equivalence correctly documented in the r6 plan. Keep the diagnostic test if its message is intentional, but classify M74 as diagnostic coverage/equivalent protection rather than an independent semantic kill. This does not allege that the reported runner output was fabricated; it explains why that output overstates independent behavioral coverage.

## S2 — predicted: the required-EXECUTE manifest can miss an absent inherited helper

**Evidence:** `c_app_exec` includes `cash_source_lock_key(text,uuid)` (frozen line 1657). The check at lines 1801–1803 uses `WHERE NOT has_function_privilege(..., to_regprocedure(...), 'EXECUTE')`. For an absent function the lookup and privilege result are NULL, so the row is not selected. Unlike the other listed helpers, **cash_source_lock_key is not in c_bodies**: it is inherited, not defined by -24.

The r6 plan's note that every `c_app_exec` entry is also body-pinned therefore does not cover this entry.

**Probe:** [08-missing-lock-helper.sql](codex-r6-probes/08-missing-lock-helper.sql). On the fresh clone, check the baseline invariant, drop this helper **without CASCADE** inside a savepoint, then call the -24 invariant. Predicted: it returns successfully despite the absent helper its writers require. If DROP encounters an unexpected dependency, the probe prints that error rather than removing dependents. Everything rolls back.

**Fix:** use `NOT coalesce(has_function_privilege(...), false)` or explicitly test `to_regprocedure(...) IS NULL`. An inherited helper need not have its body pinned here to require that it exists and is executable. This is an invariant-drift hole, not a demonstrated ordinary application bypass on an intact installation.

## N2 — predicted: closure of round-5 and earlier findings

Database coverage: [00-frozen-battery-coverage.sql](codex-r6-probes/00-frozen-battery-coverage.sql) is the frozen r6 battery with error logging added; [02](codex-r6-probes/02-statement-shapes-and-roles.sql), [03](codex-r6-probes/03-repeatable-read.sql), [04](codex-r6-probes/04-serializable.sql) and [05](codex-r6-probes/05-catalog-contract.sql) carry forward the supplementary role, statement-shape, isolation and catalog probes.

| Finding | Assessment and coverage |
|---|---|
| r5 Opus B1, negative NSF undo excluded | Exact case closed: both recursive legs prune only positive NSF rows and their descendants. 00 P14e/e2/f/f2/g. |
| r5 Codex B1, return before later tree date | Exact case closed: complete-tree maximum includes NSF and posting entry. 00 P14h–h4. B1 above is the recorded-coordinate variant. |
| r5 Fable S1, catalog comment | Corrected in source, including tenant, recorded order, misposting amount and date checks. |
| r5 Fable S2, unreachable payment bound | The r6 argument is sound for valid finite -23 trees: all descendants net to at most the payment; each omitted positive-NSF subtree has a nonnegative total, so pruning cannot raise that sum. The upper clamp is defensive. 00 P14a–g supplies examples, not a universal proof. |
| r5 Codex S1, race header and duplicate G6 | Both corrected. A4/A5b/L6d remain app-ACL tests; 02 separately probes owner guards. Shortfall trace has G6/G6a/G6b behavioral coverage, still no dedicated branch mutation; the 1,000-step trace bound remains disclosed as untested. |
| r1 Codex B1/B2/B5, provider late assignment, instrument drift, cross-table equal id, isolation pin | Original routes closed in source. 00 U8/P5e; 03/04 include late provider assignment at RR/SERIALIZABLE. |
| r1 Codex B3, reversed bank money released by label | Original route closed: explicit disposition, return-code checks, once-only index and pruned-tree amount. 00 P9/P12/P13/P14. |
| r1 Codex B4; r2 probe 02/03, recorded ordering and equal-id exclusion | Original scenarios closed, including releases and table-specific exclusion: 00 O1 family. B1 shows the remaining ledger-time gap. |
| r1 Codex B6 and r2 NaN findings | Finite reached timestamps, finite dates and new monetary NaN checks are present. 00 O2/U3b/X5b/L6e/L7f. No claim that -23's general NaN issue is repaired. |
| r1/r2 invariant findings | Original missing constraints/indexes/grants/bodies/attributes/NOT NULL addressed: 00 I8/I9 and 05. S2 is a distinct NULL lookup hole. |
| r1 Codex S2, missing-user case/P4c/M56 | Corrected. M56 removes the actual agency mismatch refusal. Current mutation qualification is S1 above. |
| r2 mixed bank return/misposting; r3 B1 tree netting; r4 B1 nested NSF | Original cases covered by 00 P13/P14a–d; pruning and netting remain present. |
| r3 should-fixes, r4 return-before-payment | Lower cap, own-void exclusion, NaN pledge payment and labels remain; explicit payment-date check retained. 00 O4/L7f/P9b3/P9b11/P9b12. |
| Settings, tenant checks with FKs off, bill restriction, retired-name reuse | Earlier fixes remain in source and 00 S/O3/L18/A coverage. |

I found no reintroduction of the earlier concrete examples. That is narrower than saying all possible temporal histories are safe.

## N3 — predicted: design, rulings and bypass coverage

| Requirement / attempt | Source assessment and author probe |
|---|---|
| Receipt spent twice | Payment/disposition cap checks cumulative changes at each row date under receipt lock; ordinary overspend refused. 00 P/X, 02 multi-row/CTE/COPY. Historical composition still fails as B1 predicts. |
| Wrong date/effective date, tenant, missing reason/operator, instrument drift | Insert/update checks, inherited immutability and composite keys cover the specified cases. 00 P3/P4/P5/T/O3. |
| Guessed application | No new writer chooses a customer from candidates. Resolution names customer, reason and operator. 00 U/C. This does not verify the truth of an operator's identification. |
| Provider transaction twice | Shared incoming namespace lock plus own-table unique indexes; table-specific self exclusion and late assignment check. 00 U8, 03/04. |
| Wrong agency/customer paying pledge; ended twice | Identity checks, immutable linkage and one-event uniqueness. 00 L7/L8/L11–L14; 02 tests dependent writable CTEs in both orders. |
| Early lapse or payment naming recorded-in-error pledge | Pay-by/date checks and payment/event handshake. 00 L10/L12/L14, 02. |
| Agency overpayment | Intentionally accepted; no invented pledge cap. 00 L12. |
| Caller chooses agreement/pay-by | Database chooses agreement under agency lock and stores computed terms; direct supplied terms refused. 00 A/L1–L4. |
| Pledge reader precedence | void, paid, effective event, no_agreement, overdue, open. 00 L8–L15. |
| Agency refund to customer/wrong agency; customer money to agency | Typed payment, overpayment-credit and both reissue paths checked. 00 G1–G7. L5/L6 explicitly limit this guarantee. |
| Agency resurrected; agreement edited | App ACL and owner triggers are separate protections. 00 A/L17; 02 owner controls. |
| History load / roles | 00 O/T includes finite clocks and tenant checks with ordinary FKs off; 02 app/core/owner and COPY; 03/04 higher-isolation refusals; B1 owner history path. Arbitrary disabling of ALWAYS guards is not covered. |

The patch supplies the intended CI-053/CI-056 **record side**, subject to B1. It retains unidentified money, stores explicit resolution evidence, supplies typed pledges and aged/open readers, and does not allocate candidates automatically. Operator queues, reporting, statutory protection and disconnect execution remain core/rule work. Missing service level raises; missing retention is explicitly unknown (`past_retention = NULL`), not false (00 S).

The inventory's program_types formulation is implemented through agency `program_kind`, agreement terms and explicit equality of the pledge's target bill with the payment restriction (00 L18), rather than automatic field inheritance. Ryan's 11-07 refund rule is enforced on the typed paths specified by the design, with L5/L6 accepted separately; this review does not expand that to universal database enforcement.

## N4 — predicted: -23/-27 composition, locks and invariants

**Composition probes:** [06-composition-controls.sql](codex-r6-probes/06-composition-controls.sql), plus 00 G and 05. No existing cash or shortfall function is re-issued by -24. Nevertheless, its releases depend on their semantics; B1 is a concrete reason additive DDL does not establish temporal isolation.

Probe 06 predicts that an ordinary held overpayment credit loses its remaining money when its payment is fully reversed, while suspense gets the share back. It also prints the posted-refund case: the refund remains spent and -23 retains a negative payment position/shortfall. I do not label gross refund-plus-reallocation figures as creation of money while ignoring that explicit debt. Its third control covers the `deposit` posting-entry branch and zero remaining received amount after reversal. It **does not** certify a separate -15 deposit record, its balance or its disbursement; L5 remains outside the certified routing scope. No blanket assertion that every deposit lifecycle conserves across -24 is made.

Trigger order matters: inherited stamping, birth/freeze and immutability guards compose by trigger name with the new BEFORE payment guard; the receipt cap is AFTER INSERT and sees the statement's completed inserts. Probe 05 prints installed payment/ledger trigger order; 00 and 02 exercise behavioral cases. The CI diff supplies agency_id to -23's fixtures and applies -24 after the stated pending patches; it was inspected, not run.

Both receipt-cap write call sites take the receipt lock before cap/order reads. The cap helper itself is read-only and does not acquire that lock; a direct helper call is not a write authorization. Provider checking pins READ COMMITTED internally and takes the provider namespace lock. Pledge insertion/agreement changes serialize with retirement through the agency lock. Pledge payment INSERT and event INSERT share the pledge lock. Source evidence is the corresponding functions; 00/02/03/04 exercise their single-session paths and pins. Frozen SU1–SU12 are reviewed cross-session test schedules, not races reproduced here.

The pledge lock is not added to every subsequent payment status update. A pending payment already bars recorded_in_error; late actual payments after withdrawal/lapse are accepted, and paid outranks the event. SU3 is correctly described as pending insertion, not posting-versus-lapse concurrency. I found no separate cap read on an authorized receipt writer lacking its receipt lock. B1 is insufficient temporal evidence, not a missing receipt mutex.

The documented tenant-head → inherited cash locks → receipt/pledge order is a path rule, not global ordering of every lock across an arbitrary multi-row transaction. Deadlocks remain possible and 40P01/40001 retries remain part of the contract. No deadlock-free or exhaustive concurrency certification is claimed. The recursive walk relies on inherited ALWAYS lineage/sign/tree-cap guards; its bound is depth, not total width or runtime (05 catalog evidence). The payment upper-bound equivalence assumes these guards remain intact.

The invariant checks required trigger definitions/enabling, sole tenant policy/FORCE RLS, grants, validated constraint definitions, valid unique indexes, 28 body hashes, function attributes, required NOT NULL and app helper EXECUTE. 00 I/05 cover intended checks; 08 covers S2. These are enumerated required-item checks, not equality of every possible schema object or a proof of correct money semantics. Inherited helper bodies are not all pinned here. S2 narrows the advertised required-EXECUTE guarantee; B1 demonstrates that a matching body hash can still preserve a semantic defect.

## N5 — predicted: test sufficiency and known limits

New P14e–g/M111 target negative-NSF undo handling; P14h–h4/M112 target the prior business-date case. Those are relevant regressions. They do not vary ledger recording time independently of terminal status recording time, which is the missing axis in B1. The runner does require the named first failure and refills body hashes so deliberate behavior edits reach tests; S1 shows why message-sensitive checks still need interpretation.

Additional disclosed gaps remain nonblocking by themselves: a dedicated shortfall-reissue trace mutation, the 1,000-step trace test, and full deposit-lifecycle composition. Existing source tests and the probes distinguish app privilege refusals from owner triggers, and COPY from ordinary INSERT.

Known limits are not independently blocking for this scoped record patch:

- **L1:** candidate quality remains intake's; 00 C/S tests supplied candidates, not matching correctness.
- **L2:** statutory/core enforcement remains staged. 00 L/S tests reader inputs, not a working disconnect pause.
- **L3:** batch matching remains core work. No import integration is certified.
- **L4:** a snapshot line is deferred, but its replacement held reader must reconcile at both coordinates. B1 blocks that prerequisite for the demonstrated history shape.
- **L5/L6:** explicitly accepted by Ryan; deposit payees and untyped credit origins are not universally database-routed. 00 G and 06 establish only the narrower typed/payment paths described above.

Run probe 01 first, then 07/08 and the remaining probes independently. Confirm or disprove the exact prerequisite and double-recognition notices before changing the patch. Close B1 and add the regression/mutation; clarify M74's coverage and make missing required helpers fail the invariant. No r6 database pass or failure is claimed as executed in this review.
