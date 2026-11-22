# Codex review — scenarios round 4 — 2026-11-22

Reviewed SCN-0081–0098, the changed SCN-0033, SCN-0024 and SCN-0053, and the cast's penalty rows. **Two must-fix findings and eight should-add findings** follow, ordered by importance within each rank. These are scenario findings, not requests to change the schema.

## Evidence and limits

Read the brief, README and cast, the specified Kyle rulings, relevant canonical invariants and original outlines, their supersession audit, dated parity updates, application contracts, decision-log entries, cash patch headers/residuals, selected implementation definitions in the append-only `sql/tu.sql`, and relevant existing battery cases. References below to `GBM/` mean `/Users/ryanscomputer/code/gas-billing-memory/application/`. Battery references are source inspection, **not newly executed results**.

The attempted read-only database query (`docker exec tally-pg psql -U tally -d tally -Atc ...`) failed with `permission denied while trying to connect to the docker API at unix:///Users/ryanscomputer/.docker/run/docker.sock`. Consequently, no live catalog or runtime behavior was verified. No batteries, migrations, database writes or commits were run. No other report in this review directory was opened. Only this report was written.

## Findings

### 1. Must fix — SCN-0086(c): the reopened second bill disappears from the stated balance

**Problem.** The credit has paid $34.17 of another bill, but after undoing that application the Then says “then as (a).” Part (a) asserts a total of $65.83 owed. The second bill is still a charge; undoing an application does not reverse it. Its amount and remaining balance are not specified, so this branch has no reproducible account balance.

**Evidence.** `scenarios/cash.md:134–140`; the same file's ledger/application convention at line 6. Even if the second bill was exactly $34.17 and fully paid by this credit, the final ledger is $65.83 + $34.17 − $100.00 + $100.00 = **$100.00 owed**, not $65.83. If it was larger, the balance is larger still.

**Fix.** Give the other bill an invented amount, issue date and payment history. State the two reopened bill balances and their combined account balance. Limit “as (a)” to the November bill and the exhausted credit, rather than the account total.

### 2. Must fix — SCN-0095: CI-057 does not establish the asserted post-deadline penalty exemption

**Problem.** The scenario asserts that a penalty caused by failure to act on a notice in time “is not charged,” and asks Kyle only whether it is suppressed or charged and reversed. That treats entitlement to the exemption as already ruled. The cited invariant does not settle that proposition.

**Evidence.** `scenarios/cash.md:314`. `GBM/canonical-invariants.md:1011–1026` (CI-057) requires timely correction and preservation of the old account. Its related-invariant text says NOC-driven failed drafts must not produce late fees **before the utility has had reasonable opportunity to act**. That is a different temporal condition from a failure caused by missing the deadline. AC-36 (`application/APPLICATION-CONTRACTS.md:345–349`) establishes replacement/deactivation and core responsibility for choosing the account, not this penalty remedy.

**Fix.** Mark the proposed post-deadline exemption as the stream's reading and expand the Open to ask whether the customer is exempt in that case, as well as how any existing charge is corrected. Add distinct dates for notice receipt, the subsequent failed draft and penalty assessment. Preserve the already-supported protection while there has not yet been reasonable opportunity to act.

### 3. Should add — SCN-0088: cover return of a refund after the *repaying* credit was escheated

**Gap.** Part (b) returns a refund after repayment from an active credit; part (c) returns a refund whose own source credit was escheated. Neither exercises the distinct -27 case where the credit that repaid the shortfall was subsequently escheated. Reopening that old credit would violate the ruling even though the account total might look correct.

**Evidence.** `scenarios/cash.md:164–176`; `application/APPLICATION-CONTRACTS.md:394–400`; `application/DECISION-LOG.md:110–116`. `tests/v5.4.2-27/battery-27.sql:632–709` covers E1–E9: undo, returned refund and new credit together; missing/undersized carry refused; carry posts no ledger entry. The mirrored commit guard is `enforce_shortfall_undo_carried` at `sql/tu.sql:48886`.

**Fix.** Extend (b): the $20 repayment credit has ended through escheat before the $30 refund returns. Undo the repayment and create a new $20 credit naming that undo, atomically with the return. Assert the old credit stays closed, no extra money is posted for the carry, and omitting the new credit is refused. Supply explicit invented dates and dormancy facts.

### 4. Should add — SCN-0087: a fresh payment can repay the shortfall, and that source's later bounce must wait

**Gap.** Only credit-funded netting is exercised. A customer can pay the remaining off-bill debt with a new payment. That payment must not become an overpayment credit or an invented bill charge. Its own bounce is blocked while the shortfall application stands.

**Evidence.** `scenarios/cash.md:149–157`; `sql/v5.4.2-27-shortfall-applications.sql:24–34,89–101`; `tests/v5.4.2-27/battery-27.sql:192–198` (K7). The mirrored guards on ledger take-back and payment status are described at `sql/tu.sql:48771,48795` and cover `account_ledger` and `payments`, including the ordinary application writer.

**Fix.** After the $20 netting, have BB-02 pay the remaining $10. Record that payment against the shortfall, assert zero account balance and no bill charge. Attempt its bounce before undoing the repayment: refused. Undo and bounce: the $10 shortfall reopens. Also exercise a source with enough money to isolate the target cap: the current $20 source cannot independently prove the claimed $30 target cap, because a $30.01 attempt already exceeds the source.

### 5. Should add — SCN-0083/0085: exercise Kyle's configurable return-window hold

**Gap.** The scenarios test the hard cap and a pending refund blocking a bounce, but never the separate utility policy that holds or warns on refunds during a payment's return window. An implementation could omit that policy and pass this family.

**Evidence.** `GBM/kyle-decisions-2026-10-21-refund-then-bounce.md`, answer 3 and final “What this changes” bullet; `sql/v5.4.2-23-cash-reversals-positions-application.sql:339–342` (R14). This is a utility-configurable policy, off by default, and explicitly absent from the schema.

**Fix.** Add invented utility settings and dates for: default off, hold on before expiry, permitted after expiry, and warning-only if supported by the chosen policy. Attribute the decision to the core and label storage/enforcement as not built. Keep this separate from cancellation of a refund already pending, which SCN-0085(b) covers.

### 6. Should add — SCN-0095/0098: distinguish the customer's timely date from when money becomes drawable

**Gap.** The effective-date examples establish on-time versus late, but do not prove that an early customer date cannot fund a refund or application before settlement. All ordinary draws here happen after arrival.

**Evidence.** `scenarios/cash.md:304–313,355–362`; supersession audit `application/scenarios-source-inventory-2026-11-02/audit-invariant-docs-p-to-w.md:30`; `tests/v5.4.2-23/battery-23.sql:1515–1524` (V10/V10a: payment dated March 10, settled March 12; refund dated March 11 refused, March 12 admitted). The latest mirrored `check_cash_source` begins at `sql/tu.sql:48334`; its contract at line 48572 includes arrival and date caps.

**Fix.** Add a payment sent by its due date but settling later. Assert timely treatment for the late-fee calculation, while a draw dated before settlement is refused and the same draw on/after settlement is admitted. Specify both dates and the method, rather than allowing a test to use one date for both purposes.

### 7. Should add — SCN-0085/0096: partial reversals and their separate remaining caps

**Gap.** SCN-0085 states “less earlier reversals” but exercises none. SCN-0096 describes full reversal/re-entry as the correction rule. The existing schema and battery also support a partial correction; the scenarios should distinguish that supported branch from the full replacement workflow, or explicitly resolve whether the core intends to offer a narrower workflow.

**Evidence.** `scenarios/cash.md:105,121–123,321–330`; Kyle R-02 in `GBM/kyle-decisions-2026-10-15-waves-1-to-7-and-texas-first.md:15`; `tests/v5.4.2-23/battery-23.sql:1166–1182` (S3: $50 receipt, $5 correction, $45 refund admitted, $45.01 refused). The supersession audit's reversal-family A4 explicitly preserves partial second reversals (`application/scenarios-source-inventory-2026-11-02/audit-invariant-docs-p-to-w.md:169`).

**Fix.** Add a $50 payment with $5 already reversed. Assert the refund cap is $45 before refunds, and the remaining take-back cap is $45 irrespective of a later refund. Exercise a legal partial second reversal and an over-cap attempt. Describe SCN-0096's full replacement as its chosen workflow rather than evidence that every correction must use that shape.

### 8. Should add — SCN-0094(d): make refundable funds an explicit precondition

**Gap.** The Then promises that changing the second refund's processor number makes it accepted. The Given does not say whether the $65.83 payment has paid the reference November bill. If it has, no money is available for even the first $10 refund. If it has not, the refunds can fit. A test must currently choose the prerequisite itself, and could mistake a cap refusal for successful duplicate protection.

**Evidence.** `scenarios/cash.md:8,286–294`; the source cap described by the latest `check_cash_source` contract at `sql/tu.sql:48572` counts applications and refunds together. AC-35 (`application/APPLICATION-CONTRACTS.md:333–343`) makes processor uniqueness an additional condition, not permission to exceed the source's available money.

**Fix.** State that (d) is an independent branch with the payment posted and at least $15 unapplied, no credit holding that money and no other refunds. Assert the first refund succeeds, the repeated identifier is refused for identity duplication, and a distinct identifier succeeds within the remaining cap. Alternatively release an explicitly specified application first.

### 9. Should add — SCN-0096/0097: pin the application undo and reapplication steps

**Gap.** Both scenarios accept a reversal of a posted payment without saying whether the payment is applied. A correctly allocated bill payment cannot simply be reversed. SCN-0097 additionally needs its undo dated in the open period; SCN-0096 needs the replacement applied so the bill is paid as well as the account ledger summing to zero.

**Evidence.** `scenarios/cash.md:323–330,339–346`, compared with the explicit prerequisite in SCN-0084 at line 93. `sql/v5.4.2-23-cash-reversals-positions-application.sql:343–351` (R15) blocks taking back a payment's posting entry while applications remain, including partial take-backs. Application dates are frozen by the close (`sql/tu.sql:45347`).

**Fix.** Specify that the original payment was applied; assert refusal before undo, then the successful sequence. In SCN-0096, undo $56.83 and apply the new $65.83 with its true customer date. In SCN-0097, undo in December before the December bounce and retain November's closed view. If intentionally testing an unapplied payment instead, say so explicitly and add the normal applied branch.

### 10. Should add — SCN-0094: test confirmation only after processor acceptance

**Gap.** The Rule includes “a confirmation is sent only after the processor accepts,” but no When/Then tests rejection, timeout or delayed acceptance. The current successful redelivery cases could pass even if the app confirms before receiving acceptance.

**Evidence.** `scenarios/cash.md:284–295`; CI-055 in `GBM/canonical-invariants.md:979–989` explicitly includes premature confirmation among its failure modes. The dated parity table distinguishes this application responsibility from processor-key uniqueness (`application/invariant-parity-measurement-2026-10-13.md:332`, read with its October 15 update).

**Fix.** Add acceptance delayed, declined and indeterminate variants. Assert no success confirmation before acceptance; on eventual accepted redelivery, one posting and the appropriate confirmation. Label this as app behavior rather than a built database guard.

## Checks with no additional finding

- SCN-0033's corrected components recompute to **$52.61** and **$79.06**. The lower correction's penalty plus tax is **$5.26**, giving **$57.87**. The higher correction carries **$13.23**, including **$13.10** tariff-priced principal and **$0.13** tax; its December 4 balance remains **$72.42**. These agree with Ryan's November 22 matched-line ruling.
- SCN-0024's changed bullet follows Kyle's next-regular-bill age/due-date ruling and identifies the moved line's aging as a stream reading. Its existing Status correctly warns that separate aging dates are not built.
- SCN-0053's recurring full-amount penalty is **$21.58**, excluding the earlier **$9.50** penalty; the once-only alternative is **$12.08**. The cast agrees with the November 22 choice. The source tariff does not itself establish monthly recurrence, and the cast appropriately marks that selection invented.
- Cash table arithmetic checks out apart from finding 1's omitted bill. The November 16 bill is 29 days old on December 15. Counting November 16 as day 1 makes January 14 day 60. December 8 is the sixth weekday after November 30 in the stated banking-day example.
- The already-marked Opens concerning mailed overpayments, combined deposit/bill receipts, allocation-floor conflicts, and the legal effective date are not reported as newly discovered defects. The unresolved dispute-policy conflicts are explicitly exposed in SCN-0033 and today's decision log; this review does not replace Ryan's rulings with the older invariant wording.
