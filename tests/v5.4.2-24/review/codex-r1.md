# Codex — v5.4.2-24, round 1

Verdict: **not yet**.

This is a SOURCE ONLY review. **No database result below is executed.** SQL outcomes are predictions for the author to test. I did not run docker, psql, CI, races, or the mutation runner, and did not read another reviewer's files. The probes are self-contained owner scripts for a fresh clone with frozen r1 applied; they end in ROLLBACK. Some switch locally to application/core roles to test those boundaries. Caught errors print SQLSTATE and message. The COPY probe catches the server's COPY exception itself, without using psql's LAST_ERROR_SQLSTATE.

## N1 — executed: freeze verification

Checked these before reviewing source; all match:

| File | Actual md5 |
|---|---|
| review-brief-24-r1.md | 1b3598dba62efb34e0be331cb32e6a0f |
| patch-24-frozen-r1.sql | eae62ab08914d6871f7688f329a13660 |
| battery-24-frozen-r1.sql | e2c82852c68e399021ea31a77773d1a8 |
| suspense-24-frozen-r1.sh | bb428ea60eb52ecb07a52921f1b23ca7 |
| mutations-24-frozen-r1.py | 2e5cd7660bed4aee12cc3bc77b8b1d4a |
| ci-24-frozen-r1.diff | c343828be614b5abf30a15944402ee0c |

The brief's value matches review-brief-24-r1.md5. Read the design, application/source-inventory-wave2's actual location under wave2-build-2026-10-15, application/DECISION-LOG, and GBM's canonical CI-053/056 and both named workflows. The ruling used here is Ryan's recorded 2026-11-07 decision; this is not an independent legal opinion.

## B1 — predicted: late-filled payment references bypass the new checks

**Evidence:** frozen patch lines 631–649 return from the UPDATE arm after checking the five new write-once fields and effective_date. Both provider checking and instrument comparison are below that return. In -23, enforce_payment_immutable's `c_once` explicitly permits NULL-to-value updates of provider_transaction_id, reference_number, check_number, check_date and check_bank_name.

Consequently an ordinary positive payment born without a provider id can later acquire the id of a suspense receipt. The payment-payment unique index has no receipt row to conflict with. Separately, a payment correctly copying a NULL instrument field from its receipt can later fill that field with its own value, leaving the immutable receipt and its payment inconsistent. A receipt-linked payment's provider id remains protected by the new CHECK; the provider exploit uses an ordinary payment.

**Probe:** [01-late-provider-and-instrument.sql](codex-r1-probes/01-late-provider-and-instrument.sql). Expected: both updates accepted; the join finds the duplicate provider transaction, and payment_bank differs from receipt_bank. Runs the attempted writes as tally_app.

**Fix:** run the provider check on first assignment as well as insert, with the isolation/lock discipline below. Recheck all receipt instrument fields on relevant updates, or freeze those fields from insert whenever suspense_receipt_id is set. Add regressions for each formerly NULL field.

## B2 — predicted: the cross-table provider check excludes a different row with the same UUID

**Evidence:** patch lines 605 and 608 use `id IS DISTINCT FROM p_self` on both tables. Receipt and payment primary keys occupy separate namespaces. A caller may supply the same UUID to both. Neither a table-local PK nor the payment-only provider unique index forbids that.

**Probe:** [02-cross-table-same-id.sql](codex-r1-probes/02-cross-table-same-id.sql), both insertion orders, as tally_app. Expected: two independently recorded positive amounts for the same tenant/source/provider transaction, sharing only their UUID. No race is required.

**Fix:** exclude self only in the same table, never in the opposite table. The boolean already identifies which table is being inserted. Add both orderings to the battery.

## B3 — predicted: a bank return recorded as `reversed` makes nonexistent cash spendable again

**Evidence:** check_suspense_receipt_cap, lines 558 onward, and suspense_receipt_position_as_of exclude every reversed payment. Existing payments_return_code_check explicitly permits a return code on reversed; -19 also documents a chargeback recorded as reversed. -23's status guard requires a non-NSF ledger reversal, not a proof that the reversal is exclusively a wrong-customer correction. No -24 guard narrows that vocabulary for receipt payments.

**Probe:** [03-reversed-bank-return.sql](codex-r1-probes/03-reversed-bank-return.sql). Receive 100, post all 100, record a bank-return adjustment and status reversed with R01, then post another customer's 100 from the same receipt. Expected: the return is accepted, held becomes 100, and the replacement payment is accepted. This is different from the battery's legitimate misposting correction followed by an NSF: its P9/P10 cases never cross reversed with a bank return.

**Fix:** distinguish a correction that keeps money in custody from a bank return/chargeback. Use the same classification in the cap and reader and preserve its recorded-time meaning. Merely testing return_code at insert is insufficient: the return and its code arrive later, and the code is write-once-after-NULL. If adding a return code changes a previously released share, guard that transition under the receipt lock or prohibit the inconsistent sequence.

## B4 — predicted: a history load can produce negative held cash at a recorded coordinate

**Evidence:** the cap checks money dates against all current dispositions; it does not enforce recorded order. The position reader filters each disposition and payment by created_at. Unlike -23's check_cash_order, neither receipt draw writer rejects a draw recorded before the release it consumes.

**Probe:** [04-recorded-order.sql](codex-r1-probes/04-recorded-order.sql), owner history load with no disabled triggers. Receipt 100 recorded March 2; return 100 recorded March 3; undo dated March 4 but recorded March 10; payment 100 dated/recorded March 5. Expected: insert accepted by the current cap, but the March 6 money/recorded position has to_payments=100, disposed=100, held=-100. After March 10 it has held=0. All chosen timestamps are finite and in the past.

**Fix:** carry the cash stream's recorded-order discipline onto receipt releases and subsequent draws, including payment void/reversal releases. Serialize the check with the same receipt lock. Cover transaction-start timestamps after lock waits as well as explicit history stamps. This blocks reliance on suspense_held_as_of as the reconciliation substitute promised by L4.

## B5 — predicted: provider writers are not pinned to READ COMMITTED

**Evidence:** check_provider_transaction_once, lines 595–613, takes an advisory lock and queries the other table but never calls suspense_require_read_committed. enforce_suspense_receipt does not call it either. A normal payment without suspense/pledge linkage reaches neither of the payment trigger's isolation checks. The inherited accounting-freeze function takes a close-head share lock but does not impose READ COMMITTED.

**Probes:** [05-provider-isolation.sql](codex-r1-probes/05-provider-isolation.sql) and [05b-provider-serializable.sql](codex-r1-probes/05b-provider-serializable.sql). Expected: ordinary provider receipt and payment inserts are accepted at each isolation level. These establish the missing pin; they do **not** reproduce a two-session duplicate. The RR probe records the follow-up stale-snapshot schedule for the author. An advisory lock does not refresh an RR transaction snapshot. SERIALIZABLE may abort an anomaly through SSI; I am not claiming it admits the same duplicate.

**Fix:** enforce READ COMMITTED within the provider checker whenever it checks positive money with an id, covering receipts, inserts and late assignment. Add a stale-snapshot cross-table race in both directions. SU7 tests only a payment already naming a suspense receipt and cannot establish the provider path's pin.

## B6 — predicted: the new clock fields admit invisible or unageable receipts

**Evidence:** the shared stamp_log_created_at preserves a superuser's supplied timestamp. -23 adds finite/past validation for payment history loads; -24 only attaches the stamp trigger to its seven new tables. Receipt received_on is checked against the latest current date but not for finiteness.

**Probe:** [08-nonfinite-and-future-clocks.sql](codex-r1-probes/08-nonfinite-and-future-clocks.sql). Expected: an owner can insert a receipt with created_at=infinity, its finite-coordinate reader returns no row, and a normal pending payment can consume it. Separately, tally_app can insert received_on=-infinity for a fresh tenant with no closed period; calculating age then errors. The first outcome silently hides retained cash, while the second leaves an immutable receipt the age reader cannot evaluate.

**Fix:** validate finite, already-reached recorded stamps for history loads and finite business dates on all new dated rows. Keep the application's database stamping. NOT NULL alone does not close these clock failures.

## S1 — predicted: the invariant audits existing FK shape, not required constraint existence

**Evidence:** assert_suspense_pledge_guard_invariants checks exact trigger definitions/enabling, policy shape and broad grants. Its FK query only visits constraints that still exist. It contains no manifest of required FKs, CHECK definitions or unique indexes. The setup-table UPDATE grant test rejects excess grants but does not require the permitted stamp-column grants to remain present.

**Probe:** [06-invariant-blind-spots.sql](codex-r1-probes/06-invariant-blind-spots.sql). Expected: the invariant still passes after removing payments_suspense_receipt_fkey, removing payments_suspense_resolution_check, or revoking the agency status UPDATE grant. Each mutation is inside a savepoint and is rolled back.

The literal R-12 assertion about *every existing key* is true but weaker than proving tenancy linkage survives drift. The COMMENT's broad “every ... guard” and “keeps ... its grants” can easily be read more strongly than the checks. Add required-constraint/index definitions and positive stamp-grant checks, or explicitly narrow the advertised guarantee. The existing mutations exercise a narrowed FK and a widened grant, not deletion or missing required grants.

## S2 — executed (source inspection only): tests overstate some labels and mutation coverage

- P3b says “and who” but supplies suspense_resolved_by and tests a blank reason. Add an independent missing-user test.
- P4c tests the battery's post() helper choosing a later effective date; it is not a standalone assertion that the database supplies a posting date. Keep the helper path, but name it precisely.
- A4/A5b/L6d demonstrate application privilege denials, not the owner trigger paths. Probe 07 includes owner term edits, agency resurrection and receipt edits.
- M56 is described as allowing an agency refund to the customer, but replacing only `IF v_agency IS NOT NULL` with false still falls through to the customer's-money exception. Its catch at G1 measures the changed error message, not acceptance of a forbidden refund. Replace the mutation with removal of the actual agency mismatch refusal, retaining valid control cases.
- The runner does check the first reported failure rather than accepting arbitrary later failures. I found no basis to assert that its reported 71/71 was fabricated or that every mutation is semantic coverage. I did not run it.
- Frozen race SU3's prose says “posts”; apay() inserts a pending payment only. That is sufficient for the non-voided-payment vs recorded_in_error rule, but does not exercise posting/status-update concurrency. SU6 is sequential historical reading, not reversal racing a fresh receipt draw. No multi-receipt lock-order race, COPY case, cross-table equal-id case, late provider assignment or recorded-order history load appears in the frozen suite.

[00-frozen-battery-coverage.sql](codex-r1-probes/00-frozen-battery-coverage.sql) reproduces the frozen battery as an author-run probe with SQLSTATE/message logging added to catches. [07-statement-shapes-and-roles.sql](codex-r1-probes/07-statement-shapes-and-roles.sql) adds multi-row, writable CTE, server COPY, core privilege and owner-trigger probes. No pass count from either is claimed.

## N2 — predicted: requirement and bypass coverage outside the blockers

The following are source conclusions awaiting the linked probes, not database certifications.

| Requirement / attack | Source assessment and probe |
|---|---|
| Unidentified money retained, candidates never automatically applied | Tables are separate from the customer ledger; no candidate-to-payment writer is introduced. Probe 00 U/C. U1–U3 are substantially implemented, subject to B1–B6. |
| Receipt cap at every business date | For a fixed set of included payments/dispositions, cumulative sums change only on their row dates, so those boundaries suffice. Pending is already counted. Forward status moves do not increase this current-state sum: posted-to-NSF leaves it unchanged; void/reverse reduces it. B3 concerns what a release means; B4 concerns the separate recorded coordinate. Probe 00 P/X, probes 03/04/07. |
| Dates, reason, tenant and instrument on resolution | Insert checks and composite FKs cover the ordinary routes; effective-date updates are checked. -23 freezes payment_date from insert. Probe 00 P/T/D and probe 07; late nullable instrument enrichment is B1. |
| Duplicate provider transaction | Positive-money checker plus payment-only unique index is the intended division. Refund ids intentionally occupy the outgoing-money namespace; skipping negative refunds is not itself a second incoming receipt. B1/B2/B5 prevent certification of incoming uniqueness. Probes 01/02/05/05b. |
| Wrong agency/customer, two pledge endings, premature lapse, payment after recorded_in_error | BEFORE guards, one-event uniqueness and immutable linkage express these rules; UTC-12 is the conservative lapse boundary. Probe 00 L. No invented pledge cap: excess agency money remains accepted. |
| Pledge agreement/state precedence | Stored agreement/pay_by and reader CASE implement the as-built precedence: void, paid, effective event, no_agreement, overdue, open. Probe 00 A/L. Pledge created_at is the recording clock; this does not prove a delayed human intake's actual arrival time. |
| Agency refund recipient | Explicit overpayment and refund_reissue paths are covered by probe 00 G. The new helper also has a shortfall_reissue branch in source; that branch lacks a dedicated frozen battery/mutation test and needs one. No claim of a tested shortfall-reissue chain here. |
| Agency shortfall money laundering / refund of a refund | Probe 09 attempts repayment of a customer's NSF shortfall, then refund of that target, and refund of an existing negative refund. Predicted refusals follow existing source status/amount requirements. Repayment is not by itself a newly positive refundable payment. |
| Transfer or another credit origin holding agency money | cash_money_agency defaults unsupported origins to NULL. Probe 09 exposes that for a transfer credit, but does not demonstrate a typed agency-to-transfer money movement. There is no justified claim here that an arbitrary origin_notes/source_reference string proves a particular agency funded a credit. Typed provenance must be extended if those workflows carry agency money. |
| Agency brought back / agreement edited | App ACLs plus owner trigger logic prohibit these updates; probe 00 A/L and probe 07. |
| CI-056, settings, no guessed defaults | Service-level history and aged/open readers provide inputs; the operator queue, reporting and disconnect execution remain core/rule work. Probe 00 S/L. The aged reader raises for missing service level but deliberately returns NULL past_retention for missing retention; this is narrower than design 2.4's generic “readers ... raise while unset.” Document that NULL must be treated as unknown, never false. |

The inventory's L1 names a program_types link and payment inheritance of pledge restriction, while the built design uses agency.program_kind, an optional toward_invoice_id and the existing payment restriction fields. Section 8 should explicitly reconcile that scope change. A typed pledge amount/date and agency identity are present; automatic restriction inheritance is not specified by the built payment trigger. This is a design/inventory reconciliation request, not a claim of a proven wrongful application.

## N3 — predicted: interaction with -23/-27 and concurrency limits

No existing function is re-issued by this patch. That limits regression surface but does not establish semantic isolation: the new receipt release logic interprets -23's status vocabulary, and the new refund classifier follows -23/-27 lineage. B1 and B3 are concrete consequences of that composition.

Trigger ordering matters. The inherited freeze/birth/stamp and payment immutability checks precede the new payment BEFORE guard by name; the receipt cap is AFTER INSERT and can inspect the statement's complete rows. The pending-payment cap tests in probe 07 distinguish a final-state check from a row-at-a-time projected balance. A NULL effective date may remain pending; posting must still satisfy inherited required-effective-date constraints and the new receipt bound (probe 00 P4c).

The receipt and disposition cap call sites take the receipt advisory lock first. The cap helper itself is callable without that lock, but a standalone read-only call cannot authorize or persist a draw; its caller must not be mistaken for a locked write API. Pledge-payment insertion and event insertion share the pledge lock. Agreement/pledge insertion and agency retirement share the agency lock. These are the intended handshakes reflected by the frozen SU tests; none was executed here.

The design's early sections say receipt/pledge before payment, whereas section 8 and the brief describe the actual payment-then-receipt order. Use the as-built order and correct the earlier prose. Locks across multiple rows/receipts follow statement/transaction acquisition order, not a global sorted set. This is not a proof of deadlock freedom; the documented 40P01/40001 retry contract remains necessary. A caller's whole transaction can span several sources, so reviewing one trigger is not enough to waive retries. B5 is an actual missing isolation precondition, separate from that retry requirement. No claim of an executed deadlock or concurrent duplicate is made.

## N4 — predicted: known limits and readiness scope

- **L1:** reasonable intake boundary. Candidate evidence cannot protect a customer absent from intake's candidate set. Not a reason to block this record patch.
- **L2:** acceptable staged rule/core work only if launch continues to fail toward protection for an unevaluable condition. This review does not certify -26's runtime integration; probe 00 establishes only reader inputs.
- **L3:** reasonable application matching scope. Not a blocker for recording an unmatched batch line.
- **L4:** a separate snapshot line can remain deferred for this additive patch, but the replacement reader must be trustworthy. B4/B6 make the current workaround insufficient. Probe 00 S4 is only an ordinary total; probes 04/08 expose the problematic coordinates.
- **L5:** explicitly outside the refund-payment guard. It does not justify claiming Ryan's agency-refund rule is universally database-enforced. The design assigns deposit payee routing to the core, so I do not make the known omission a separate schema-patch blocker; agency deposit-return launch needs that core route or the deposits follow-up. I did not simulate a deposit disbursement and do not assert an executed mispayment.

The patch implements much of the intended record substrate, but cannot be marked ready while cross-table idempotency, custody after bank returns, and historical visibility have the predicted bypasses above. Have the author run the probes and report actual SQLSTATE/messages, then fix confirmed blockers and add targeted regression/mutation coverage. Strict double apply, the 188-check result, all 12 race results and 71/71 mutations remain the author's reported results, not reproduced evidence from this review.
