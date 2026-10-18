Verdict: **not yet** — v5.4.2-23, review round 2.

**Evidence convention.** **Executed** means hash verification, source inspection, textual comparison, or writing/checking the probe files. **Predicted** means a database outcome inferred from source, not executed by me. All database findings and closure assessments below are predicted; the named probes are for the author to run. I ran no Docker, psql, CI, races, or mutation runner. I did not read `opus-r2.md` or `fable-r2.md`. No production/test implementation was changed.

**Executed — frozen inputs.** Before substantive review, all six MD5s matched:

| File | MD5 |
|---|---|
| patch-23-frozen-r2.sql | c3524ee9a6dfce08e33bcf324dd52a33 |
| battery-23-frozen-r2.sql | 813e06b8019d8d375cdcef752abaa3fd |
| cash-23-frozen-r2.sh | 0affa40a74f18000abdd9faabc994cc3 |
| mutations-23-frozen-r2.py | 46b0a55386c776f68e978f59656b496d |
| older-tests-23-frozen-r2.diff | c2f3d72f924d5178375e4a4fc58804b8 |
| patch-23-r1-to-r2.diff | f8fcfe820634527f72cec54933852b5b |

Read the r2 plan first, then the frozen implementation, tests and changes, all three round-1 reviews, the design/inventory/DECISION-LOG in tally-utility/application, and the specified Kyle rulings in gas-billing-memory/application. The 1,000-entry bound and -23/-24 split remain accepted decisions. Line references below are to the frozen r2 patch unless stated otherwise.

## Blocking items

**B1 — predicted: pending refunds do not prevent a bounce, contrary to the stated K2 contract.**

At 535–545 the payment bounce-row guard checks applications and live credits only. At 1436–1446 the status guard does the same. Neither checks pending refunds. Post 100, create a pending refund of 30, insert an NSF of 100 against the posting entry, then move the payment to nsf naming that NSF. Both writes are predicted to succeed; the refund remains pending. A pending refund has no ledger entry, so X2 cannot incidentally prevent this.

Probe: [01-pending-refund-bounce.sql](codex-r2-probes/01-pending-refund-bounce.sql). Safe behavior under the declared K2 answer is refusal until the pending refund is voided, with the check and refund creation/cancellation sharing the source lock. Test both the ledger act without a status move and the move. Posted refunds are a different case and must not be indiscriminately prohibited: the brief says they stand after the bounce.

This is **not K1-A** and does not require Kyle to choose a new rule. The patch header expressly says it implements cancel-first now. The older-tests diff preserves the counterexample: -19 creates P-4 pending against P-2 and then admits P-2's NSF/P5c. That fixture must cancel P-4 or explicitly test refusal, rather than certify the opposite behavior.

**B2 — predicted: the payment-arrival and bounce exemptions trust a refund reference without proving a refund posting.**

At 535–536, any new ledger row referencing a payment that refunds the source bypasses the bounce guard. There is no check of the new row's type, amount, standing refund status, or unique posting identity. At 1848–1853, `cash_arrival_stands` exempts the entire subtree of a directly attached row with that reference, again without proving its type or amount.

Concrete path: post 100, apply 50, and reserve a pending refund of **1**. Insert an **adjustment of +100**, under the posting entry, with `reference_type='refund'` and `reference_id` naming that refund. X2 permits exactly 100. The bounce guard skips it; arrival still reports true. Another application is admitted despite the posting entry having remainder zero. This is add-only ordinary application-role SQL, not a disabled guard or history load.

Two additional paths in the same probe:

- The posting transition accepts `reference_type IN ('payment','refund')` even for an ordinary positive payment, whereas root recognition at 532 requires `reference_type='payment'`. Post a positive payment using the accepted `refund` discriminator, apply it, then reverse the posting entry. The bounce guard does not recognize the source.
- Even with the correct `refund` ledger type and amount, two +30 rows may reference the same -30 refund under a -100 posting. The tree has only 40 left, but the payment position counts one refund and says 70 remains. There is no unique posting binding to make the exemption safe.

Probe: [02-refund-exemption-and-root.sql](codex-r2-probes/02-refund-exemption-and-root.sql). Bind the exemption to the actual, unique, amount-matched refund act, and make posting acceptance and source recognition use the same identity rules. Match the source being refunded to the posting tree. Merely adding `transaction_type='refund'` leaves duplicate posting and wrong-source paths.

**B3 — predicted: a credit's issuance is not singular, and its void can cancel only a stray issue row.**

`cash_arrival_stands` at 1858–1865 requires **an** issue row at minus the credit amount and no descendants under **any** issue row. It does not require exactly one issuance. `credit_issued` rows themselves are not amount-bound or unique by credit. The void cause at 1538–1543 requires only an issuing row referencing the credit with remainder zero; it never checks that issuing row's original amount against the credit.

A credit of 100 with issuing rows -100, -1, and another -100 passes arrival while all are untouched. Reverse only the -1 row and name that reversal to void the credit. With no draws, the move is predicted to succeed while both -100 issue rows still stand. The wrong-amount-only arrival case is refused, but adding one correct row makes malformed extra issuances acceptable.

Probe: [03-credit-arrival-identity.sql](codex-r2-probes/03-credit-arrival-identity.sql). Establish one amount/tenant/customer-bound issuing act for a non-overpayment credit and use that same act in arrival and void checks. Reject duplicate and wrong-amount issuance at the write, not just when a later draw happens.

**B4 — predicted: a legitimate credit refund cannot post under its credit issuance, but can post under unrelated money.**

X1 requires every `refund` ledger row to name an entry. Create a 100 goodwill credit and its -100 issuance, then a pending refund of 30. Posting +30 as a refund under that issuance reaches the credit bounce guard at 551–561. The pending refund already draws 30, so the guard rejects its own disbursement with 23001. Reversing the order does not solve it: inserting the refund ledger row first puts descendants under the issuance, so the subsequent refund payment fails arrival.

The same +30 refund posting under an unrelated -100 payment is predicted to succeed, and the refund's move to posted accepts it. That move checks the refund's type/reference/amount but not that its parent is the arrival of the credit it refunds. This is not a safe workaround: it consumes someone else's posting tree and can disable that unrelated source.

Probe: [04-credit-refund-posting.sql](codex-r2-probes/04-credit-refund-posting.sql). Define and enforce the posting path for both credit origins, including overpayment credits without their own issue row. Under current reversal semantics, a credit refund needs an appropriately bound exemption and coherent arrival accounting. Under K1-A, it can become an independent posting, but simply waiting for K1 leaves the current advertised credit-refund path incomplete. R10/R10b/R10c stop at a pending refund and a label change; they never post the disbursement.

**B5 — predicted: reversing a donation does not reverse its draw, and an undone donation still ends a credit.**

The donation leg of `cash_source_draws` (1820–1822) and `customer_credit_position_as_of` (1179–1182) sums the original donation rows, not their reversal trees. An adjustment of -100 under a +100 donation is a legal reversal type/sign/cap. Its root is a donation, so neither bounce-source branch recognizes the affected credit.

Issue 100, donate 100, then reverse that donation in full while the credit is active. The ledger donation remainder is zero, but the credit position still reports `given_up=100, remaining=0`. Moving the credit to donated by naming that fully reversed donation is predicted to succeed. The lost balance cannot be reapplied or refunded through the credit cap. The same omission also leaves a terminal donated credit unchanged when its donation is later reversed.

Probe: [05-donation-reversal.sql](codex-r2-probes/05-donation-reversal.sql). Include dated/recorded donation corrections in the draw accounting and source-lock handshake, and preserve terminal-source invariants when an outgoing act is undone. Checking only the original donation insert does not implement add-only corrections.

**B6 — predicted: an escheat remittance changes money inside a closed period without taking the close head.**

The new `escheatment_events` draw trigger (2176) calls `check_cash_source`, which takes only the source lock. There is no accounting-freeze trigger on that event table in the base or patch. The existing base stamp and append-only triggers do not take the head or check `event_date`. Unlike the corresponding donation, this money write does not follow the patch header's head-before-source rule.

Create a funded credit, set the tenant's closed-through date to March 31 using the same owner/tally_close fixture technique as battery F1, then insert an `escheated_to_state` event dated March 11. It is predicted to succeed and consume the credit inside the closed period. A donation on that date is refused by the freeze.

Probe: [06-escheat-freeze.sql](codex-r2-probes/06-escheat-freeze.sql). Freeze actual remittances by their defined UTC money day and take the head before the source. Include that trigger in the invariant and test the close/remittance handshake. This finding does not claim the existing ledger-only close snapshot directly reads escheat events; the defect is a newly monetary draw bypassing the explicitly universal freeze rule.

**B7 — predicted: voiding an overpayment credit returns money to an already-refunded payment.**

The credit void now correctly stops drawing on its payment. However, `enforce_customer_credit_immutable` locks/checks only the credit, unlike refund cancellation, which also locks/checks its source. Post 100, hold 50 as an approved overpayment credit, refund the other 50, and move the payment to refunded with nothing left. Void the unused credit (the supported no-cause path). The void is predicted to succeed; the terminal refunded payment now has 50 remaining and cannot become posted again.

Probe: [07-void-credit-ended-payment.sql](codex-r2-probes/07-void-credit-ended-payment.sql). Apply the same parent-source handshake and ended-source protection used for refund cancellation. Also cover the race against the payment's move to refunded: checking the parent without taking its source lock would recreate round-1's concurrency error.

This is a remaining form of Opus B3/O4, opened by the otherwise-correct fix to Fable S1.

## Round-1 closure and the r2 plan

**Predicted throughout this table.** “Closed” means the particular round-1 path is addressed in source, not that I executed it or certify all adjacent paths. Probe 00 is the complete frozen battery with mandatory caught-error notices added; probes 01–12 extend it. The source-order catalog witness in probe 08 is not a runtime race reproduction.

| R2 plan item / round-1 finding | Disposition | Evidence and remaining work |
|---|---|---|
| §1: read eligibility after source lock — Opus B1, Fable B2, Codex B2 schedule 1 | **Closed** for the reported stale source read | `check_cash_source` acquires the lock in a separate statement before SELECT and eligibility/arrival/cap reads; callers no longer decide mutable source eligibility first. CR9/9b/10 address the reverse ordering. Probe 08 prints the installed function; 00 covers ordinary refusals. |
| §1: unknown/invisible source — Fable S5 | **Closed** | `NOT FOUND` raises 23503 after the source read. Probe 08 tests unknown and role reach; 00 covers tenant cases. |
| §1: status isolation — Codex B2 schedule 2 | **Closed** | Both move functions require READ COMMITTED before checking mutable facts. Probes 10/11 use an otherwise valid posting cause under RR/SERIALIZABLE. |
| §2: births — Opus B2/O1, Fable S3 | **Closed for app writes** | Pending default and ALWAYS birth trigger; explicit superuser history exception is documented. Probe 00 R1 and probe 08 history case. |
| §2: correct posting type — Codex B4 | **Closed for wrong transaction type; partly closed overall** | R2 rejects adjustment-as-posting. B2/B4 identify remaining discriminator and parent binding holes. |
| §2: full NSF/reversal — Opus B2/O3 | **Closed for a partial cause on a normal posting** | Remainder must be zero; 00 R3/R4. Pending-refund policy is still B1. |
| §2: refunded cause must stand — Fable S4 | **Closed for selecting a voided refund** | Both cause queries require pending/posted; cancellation locks the parent. Probe 00 R8e/R10d; CR13 source schedule. |
| §2: credit void's act | **Partly closed** | Whole-tree remainder is checked, but B3 allows a stray issuing row; B7 omits the overpayment credit's parent protection. |
| §2: remittance, not dormancy — Codex B4 | **Closed** | Event type is checked; 00 R12b. Monetary freeze remains B6. |
| §2: terminal donation amount — Codex B1 | **Partly closed** | A 1 donation with 14 left fails (00 R11e). Corrections invalidate the claimed cause without affecting the sum (B5). |
| §3: arrival on ledger — Opus B2/O2/O6 | **Partly closed** | Normal NSF/credit withdrawal blocks further draws (00 M3f3/R3b/R9; CR9b). B2/B3 leave accepted counterexamples. |
| §3: ledger-side bounce guard | **Partly closed** | Normal roots serialize against applications; B2 bypasses recognition/exemption, B4 blocks the legitimate credit refund. |
| §4: payment-naming credit must be overpayment — Fable B1 | **Closed** | CHECK, trigger WHEN, approval and draw all key on the payment link. Probe 00 R6/C1. |
| §4: voided overpayment credit frees payment — Fable S1 | **Partly closed** | It now frees the amount and historical reader code retains it before cancellation (00 R7 tests current release; 00 R17 tests the analogous refund history). B7 shows why the parent must be guarded too. |
| §4: donation/escheat in draw set — Codex B1, Fable S1 | **Partly closed** | Original draws are counted/capped; correction accounting and escheat freeze are B5/B6. |
| §5: refund cancellation at fixed recorded coordinates — Codex B3, Opus B3, Fable N2 | **Closed for the reported live-status replay hole** | Counted statuses precede terminal ones, and the latest transition stamp identifies exit time. Probe 00 R17. This does not repair B5's omitted ledger corrections. |
| §5: bill/line before issue — Codex B3 | **Closed** | Both date and first-issued recorded instant gate both readers; probe 00 R16–R16c. |
| §5: say the open-transaction caveat where read — Opus S1/Fable N2 | **Partly closed documentation** | Shared source comment and payment/credit function comments state it; line/invoice SQL COMMENTs omit it (S3). |
| §6: recorded order versus source and bill — Opus S3 | **Closed for the reported paths** | Separate source/bill checks split 40001 at now() from 23514 for chosen history time. Probe 00 R18/R18b. |
| §6: future reversals — Opus S2, Fable N11 | **Closed** | Reversal date cannot exceed CURRENT_DATE; probe 00 R5b. |
| §6: only reversal types name entries — Fable S7 | **Closed** | New CHECK excludes payment/charge/donation, preserving adjustment and nested write_off; probe 00 R5 and X. |
| §6: same-tenant approver — Opus S4 | **Closed** | Composite FK to users(id, tenant_id); probe 00 R6b. |
| §6: column grants — Codex S1, Opus S5, Fable N9 | **Closed for reported UPDATE grant hole** | `has_any_column_privilege`; probe 08. Other invariant limits are S2. |
| §6: default/policy/helper grants — Fable N9 | **Partly closed** | Expected default/policy present, forced RLS and excess PUBLIC/core EXECUTE checked. Missing app EXECUTE and extra permissive policies are not checked (S2). |
| §6: remove core tree-lock EXECUTE — Fable N5 | **Closed** | Grant now names app/void only; probe 08 baseline invariants. |
| §6: lock-order/head wording — Codex S3/N4, Fable N3 | **Partly closed** | Header now names invoice row, status row, tree/source order and approval exception. Escheat still contradicts head-first (B6); parent-credit cancellation is B7. |
| §7: direct invariant calls — Codex S2 | **Closed** | I1/I2 use PERFORM, no `OR true`. Probe 00. |
| §7: undo-of-undo, stale labels — Codex S4 | **Partly closed** | A2h is now a negative undo; -22 R10 and CR11 header corrected. CR11 emitted verdict remains stale (S1). |
| §7: credit-refund leg — Fable S6 | **Partly closed** | Cap and refunded-status tests added, actual posting absent (B4). |
| §7: rate class, restriction, other status branches — Fable S6, Codex S4 | **Closed for listed single-session omissions** | LC3, R14, R4/R4b, R10–R13 added; 00 carries them. |
| §7: multi-row/CTE/COPY — Fable S6 | **Partly closed** | R15/R15b cover INSERT/CTE. No COPY exists in frozen battery or race script; probe 09 supplies one. |
| §7: reverse races — Opus N8, Codex S4 | **Partly closed** | Payment/credit application reverse ordering and pins added. CR11 is application-versus-refund capacity, not terminal-status-first versus refund/overpayment creation. No B7 parent-credit void race. |
| Terminal-source undo/cancellation — Opus B3/O4 | **Partly closed** | Undo after refunded and refund void after refunded are refused (00 R8/R10d); credit cancellation and outgoing-ledger reversals remain B7/B5. |
| Pending refund at bounce — Opus B3/O5, Fable B3 | **Not closed** | B1. Posted-refund treatment remains subject to K1, separately below. |

The remaining round-1 notes are addressed in N1–N4 and the residual table below: Opus N1–N3, Fable N1/N7/N8 and Codex N2/N3 concern the tree/seal/class checks; Opus N4/Fable N6/Codex N5 concern earlier tests; Opus N5–N7/Fable N4/N10/N12 concern intentional residuals and policy. They are not silently promoted into new requirements.

## Should-fix items

**S1 — executed source assessment: the test completion claims are broader than the frozen tests.**

There is no COPY statement in the frozen battery or race script, despite the plan claiming one. R15 and R15b cover VALUES/CTE only. Probe [09-copy.sql](codex-r2-probes/09-copy.sql) supplies an owner COPY overflow; it prints the native verbose COPY error rather than reading `LAST_ERROR_SQLSTATE`. Application-role COPY under RLS is a separate unsupported operation, not proof of the numerical cap.

R10b/R10c test a pending credit refund, not posting it. Add B1–B7, including duplicated ledger/refund identities, cancellation after an ended parent, and reversal of outgoing acts. Test refunds and overpayment credits on the status-first side of the lock handshake. CR12's existing missing-cause updates prove that the isolation pin is reached first, but otherwise valid move fixtures are stronger regressions (probes 10/11).

The -22 CR11 header was renamed, but its emitted verdict in `older-tests-23-frozen-r2.diff` still says “reached through its recovery”; the rows now directly name the write-off. Fix the actual label too. The -19 P-2/P-4 fixture is a substantive K2 counterexample (B1), not merely a label.

**S2 — predicted: the cash invariant's “alone” and policy claims are narrower than a complete privilege/policy contract.**

At 3171–3187, the policy test asserts that the expected permissive policy exists; it does not exclude additional permissive policies. The EXECUTE check rejects PUBLIC/core reach but does not require tally_app to retain EXECUTE. Probe [08-catalog-and-role-contract.sql](codex-r2-probes/08-catalog-and-role-contract.sql) separately adds a permissive `USING(true)` policy and revokes app EXECUTE, then calls the cash invariant. Both calls are predicted to pass. Other global invariants may catch some drift; this is about this function's stated coverage, not a claim that the entire invariant suite passes.

Pin the complete policy set and positive app grant, or narrow the documentation. Also pin the escheat stamp/freeze dependencies once B6 is fixed. This invariant explicitly does not compare function bodies; that limitation is correctly documented.

**S3 — executed: reconcile durable comments/design with r2.**

The design still says a payment born posted is not a move, every other ledger type may name an entry, an undo is always allowed, and approval writes take the head. R2 deliberately changes those statements. The r2 plan explains the corrections but the design should incorporate them. Likewise the patch's X1 introductory comment at 245 and tree-root helper comment still allow more parent-link types than the new CHECK does. The two bill-position SQL COMMENTs should include the open-transaction caveat, as the plan promised for each reader. These are documentation fixes, not new policy decisions.

## Notes and assessment

**N1 — executed source reasoning; predicted behavioral coverage in probes 00/09/10/11: the general tree cap remains structurally sound.**

For each visited descendant, `m` is the count of insertion-path ancestors above it. Expanding `j=1..m` includes exactly the ancestor/descendant pairs whose subtree totals change. Siblings contribute only to shared ancestors. The window's date peers net together; date monotonicity prevents a descendant predating its parent. The upward walk fails closed if its bound stops before the root. Immutable parent links give normal writers the same root. `ledger_tree_ids` uses deduplicating UNION, so it does not infinitely traverse a planted finite cycle. The 1,000 bound and plan settings remain, including the arrival helper's settings.

No new arithmetic flaw in X2 itself was identified. B2 is an eligibility/identity bypass around money that still fits X2's numerical cap. `void_invoice` retains invoice FOR UPDATE, head, then root lock before reading the remainder. The four tally_void ledger helper grants remain necessary for its invoker helper call graph. A textual comparison with the last base seal function found one replaced source line: the four helper grants were added to tally_void's expected list. No extra cash-table read grant was added to that role. Probe 00 exercises void and baseline invariants; 08 calls seal/period/cash assertions directly.

**N2 — executed source assessment; predicted database checks in probes 00/08/10/11: locking, roles, births and time.**

`check_cash_source` is volatile PL/pgSQL, with lock acquisition and the subsequent source read in separate statements. At READ COMMITTED that is the intended fresh-snapshot handshake; restriction fields read earlier are immutable. The numerical source/line/tree caps are behind their corresponding locks. The undo purpose intentionally skips arrival but still requires posted/active; its date is bounded by the original application's date. The caller purpose/date/created_at arguments match the listed six draw types.

That fixes the original stale eligibility read; it does not make omitted writers safe. B2 skips the source lock through its exemption, B6 omits the head, and B7 omits the affected parent lock. A retry cannot correct an accepted inconsistent state. The documented invoice/head/FK and multi-object lock inversions can still deadlock; no source proof of an irreducible deadlock was found. I did not reproduce any two-session schedule, and do not claim the author's CR results as executed here.

The app gets birth/status/time guards; tally_core is a reader and cannot directly invoke the cap or write cash. tally_void is reached through its sealed function. Owner fixture role switches in probes do not create or alter cluster roles. Superuser history loads deliberately bypass birth restrictions and may retain chosen transition timestamps, including terminal births without causes. The source even permits changing `status_recorded_at` alone as superuser, without a finite/monotone constraint. Probe 08 makes that exception visible. Thus reproducibility assumes a valid history load, not resistance to an owner rewriting history. This is explicitly outside ordinary app protection; I do not classify the stated superuser exception itself as a blocker.

The R2 status-time formula works for ordinary supported trajectories because counted refund states pending/posted precede all uncounted terminal states; there is no later counted reentry. Bill lines are immutable after first issue and now gated at both coordinates. Original donation/escheat draws are present once each; donations cannot themselves name an entry, so that particular double classification is excluded. Missing outgoing corrections are B5, not a claim that the original donation row is counted twice.

**N3 — executed source assessment: tests, mutations and earlier-test changes.**

The cash invariant contains 32 trigger definition strings and the named constraints, approval index, absent counters, five configured walks, column UPDATE checks, default/policy/EXECUTE checks. Its definition/ALWAYS/validation checks are explicit. Probe 08 tests selected catalog drift; 00 carries the behavioral battery. I do not certify strict apply twice, 168 checks, CI, or 110/110 mutations from this source-only review.

The mutation runner anchors replacements uniquely and checks the first reported FAIL/ERROR/FATAL/PANIC against its named behavioral test. APPLY mutations instead search the apply stderr for the named phrase. A “caught” mutation can mean a different refusal message rather than an admitted bad write. For example, N60 broadens pending eligibility, but `cash_arrival_stands` independently requires posted: C1m2 can fail on the expected message while the credit is still refused. The same source structure also retains an independent active-status condition for credits. Probe [13-redundant-eligibility-mutation.sql](codex-r2-probes/13-redundant-eligibility-mutation.sql) demonstrates the N60 prediction through a local transactional function alteration; it does not invoke the mutation runner. That measures attribution/diagnostic drift, not necessarily loss of the underlying safety outcome. Distinguish those from mutations which actually admit an invalid act; the number alone establishes no completeness.

Earlier-test changes generally follow explicit new rules: required line class; removal of counters; posting/issuance fixtures; approval-specific origins; immutable identity replacing parent-move races; cross-customer/sign/date refusals; safe history timestamps; and owner-planted trees for downstream boundary checks. The -19 balance adjustment is arithmetically consistent with adding -10 and -20 posting entries and a net-zero -20/+20 posting/NSF pair. -21's 2161 issuance and 2181 posting are necessary for refund reservations. The reduced full-chain depth test and planted prefixes remain the approved performance tradeoff, not equivalent full-chain coverage. Exceptions: the K2 fixture remains wrong (B1), and CR11's emitted label remains wrong (S1). No unrelated loosening was identified.

**N4 — executed residual disposition, with predicted behavior covered by the referenced probes.**

| Residual / carried note | Assessment |
|---|---|
| R1 depth 1,000 | Accepted explicit Ryan decision; no request to lower it. |
| R2 status-time replay | Original refund-cancellation replay hole closed in normal role paths. B5/B7 are separate remaining money/state defects; “R2 closed” does not make the whole position/correction model complete. |
| R3 paid/partial app lifecycle | Accepted documented label separate from derived position. |
| R4 void leaves applications | Accepted core undo/rebill responsibility; bill reader now says so. |
| R5 repeated charge-type list | Maintenance obligation, nonblocking. |
| R6 source-less class | Accepted core responsibility; sourced class checking is covered by LC1/LC3. |
| R7 allocation/floor/notification | Accepted scope. Both restriction and floor-over-restriction have explicit representation; no decision on which wins. |
| R8 earlier-test rewrites | Mostly justified; B1 and S1 must be corrected, not excused by this residual. |
| R9 tariff service/system match | Explicit delegation to core, nonblocking in this patch. |
| R10 multiple deposit-refund credits | Accepted -15 boundary. A credit cannot now evade payment approval by claiming deposit_refund while naming a payment; deposit_id is a distinct route. |
| R11 long statement locks | Accepted operational timeout requirement; no timing measurements reproduced here. |
| Floor after its target is paid (Fable N4) | Remains Kyle's policy question; no added open-target requirement invented here. |
| payer_class default customer (Fable N10) | No new allocation-tariff default is introduced by that intake classification. |

## K1-A and K2

**K1-A1 — predicted, conditional; not counted against current reversal semantics.** Probe [12-k1-current-contract.sql](codex-r2-probes/12-k1-current-contract.sql) records the present contract: -50 posting, +30 posted refund, then +50 NSF is refused by X2; +20 NSF fits. The remaining-only NSF needs a separate +30 recovery charge under option B to represent the bank/customer economics. This is the known question for Kyle, not a newly discovered X2 defect.

If Kyle chooses **A, its own movement**, changes extend beyond deleting `refund` from X1's required-parent list:

- Remove it from the permitted reversal-type list too, if refunds must never reverse an entry; bind a refund posting to its refund payment/source without a parent link, at the correct signed amount, once only.
- Remove the payment-refund subtree exclusion from `cash_arrival_stands` and the own-refund exemption from the bounce guard. The payment arrival then concerns actual undo entries only. The credit-refund route in B4 must become a valid independent posting too.
- Keep refunds in `cash_source_draws` and the positions: independent cash out still spends the source. Keep pending/posted status history and cancellation handling. Posted refunds must survive a source bounce; pending refunds need the separately chosen K2 action.
- Allow the full +50 NSF against -50, leave +30 refund standing, and verify customer ledger balance +30. Removing only the X1 requirement while leaving refund rows permitted under the old tree would keep two incompatible posting conventions.
- Audit refund reversals/cancellations after posting, status cause validation, duplicate posting, source/date/customer binding, lock order and the terminal-source protections. K1-A does not solve B3/B5/B6/B7 by itself.

**K1-A2 — executed test inventory / predicted changed assertions; conditional.** Update the two exact X1 constraint strings in `assert_cash_guard_invariants`, associated APPLY mutations (including N77's shape expectation), the refund arm of `pg_temp.post`, and add positive posted-refund fixtures to battery R8/R10 instead of stopping at reservations. Replace the probe-12 full-bounce refusal with admission and the +30 account-balance expectation. Add a race between independent refund posting/cancellation and the full NSF, plus negative tests that a refund cannot retain a reversal parent. Re-anchor tests/mutations targeting arrival/exemption code when it is removed. Existing CR8/CR11 capacity races still apply to refund reservations; they do not become tests of the newly independent ledger posting. Rework -19's P-2/P-4 scenario to obey K2, regardless of K1.

**K2 — predicted.** The declared current answer is cancel-first, but B1 shows it is not implemented. If Kyle chooses automatic cancellation, the bounce must atomically cancel pending refunds with explicit status stamps and compatible source/refund lock order. An already-posted refund must remain standing. Pending-refund creation and pending-to-posted movement must serialize with that cancellation so neither can slip past the bounce. Preserve historical position coordinates and record the cancellation act; do not implement it by making the draw reader ignore refunds whenever their source has bounced.

## Probe delivery

**Executed: files written and statically inspected only.** Every `.sql` probe begins an owner transaction on an author-prepared fresh clone with frozen r2 applied and ends in ROLLBACK. Tested ordinary writes switch to tally_app; owner-only catalog/history/close-head fixtures are labeled. Caught errors print SQLSTATE and full message using RAISE NOTICE. COPY prints its native verbose error directly. None creates/drops/alters a role or commits fixtures.

- `00-frozen-battery-coverage.sql`: frozen regression coverage with caught-error notices added.
- `01`–`07`: the seven blocking paths, independently runnable.
- `08-catalog-and-role-contract.sql`: invariant, role, source-order and owner-history witnesses.
- `09-copy.sql`: COPY aggregate overflow, native error output.
- `10-repeatable-read.sql`, `11-serializable.sql`: isolation pins with valid posting cause.
- `12-k1-current-contract.sql`: current refund-tree/bounce behavior for the K1 discussion.
- `13-redundant-eligibility-mutation.sql`: N60 still refuses the bad write through the independent arrival check.

No author-run result is implied by a probe's presence. “ACCEPTED SQLSTATE=00000” in an attempt means the attempted statement was admitted, not that the behavior is correct; compare it with the predicted/safe outcomes above.
