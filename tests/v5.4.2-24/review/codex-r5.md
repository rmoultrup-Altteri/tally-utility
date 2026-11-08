# Codex review — v5.4.2-24, round 5

**Verdict: not yet.** One blocking prediction remains: a misposting return can use the final tree balance on a date when that money still belongs to the original payment. The named round-4 changes are present, but they do not close this temporal variant.

## N1 — executed: identity and scope

Checked the brief's md5 first, together with all six frozen artifacts. Every value matches:

| Artifact | md5 |
|---|---|
| review-brief-24-r5.md | c3a8e09cb855f2bf9bc95311bb971e43 |
| patch-24-frozen-r5.sql | 0670e335b69594436e2135696f1b4f35 |
| battery-24-frozen-r5.sql | 190f92784e737ea9848b9bb7d7d3809c |
| suspense-24-frozen-r5.sh | 88c9c30b4bb11609a4f7f684673e2129 |
| mutations-24-frozen-r5.py | 55d66cf48e962866999c8dc81d6efcb1 |
| ci-24-frozen-r5.diff | c343828be614b5abf30a15944402ee0c |
| r4-to-r5.diff | cee334438830c4418859f32f88059525 |

Source only. No database connection, Docker, psql, CI, race script or mutation runner was executed. No `opus-*.md` or `fable-*.md` was read. The earlier findings below are identified from the authorized round plans and my own r1 review/probes. Authority: the tally-utility design, inventory and DECISION-LOG, plus GBM's canonical CI-053/CI-056 and the two specified workflow files. The DECISION-LOG expressly records Ryan accepting L5/L6 as limits.

A source-only check also verified all **28 embedded function-body md5s** against the frozen SQL bodies and counted **260 battery assertion call sites**. These are file checks, not database results. Strict double apply, 260 passing checks, 24 race results, 111 caught mutations and 62 passing CI steps remain the author's reported results.

All database outcomes below are **predicted**, with author-run probe files. Start each file as owner on its own fresh clone with frozen r5 applied and clone TEMP revoked from PUBLIC/app/core. Role switches use existing roles only. Each file ends in ROLLBACK; caught errors print SQLSTATE and message. Probe 02 catches COPY inside the server and prints COPY's own exception, without consulting psql LAST_ERROR_SQLSTATE.

## B1 — predicted: final-tree money can be released before the final reversal takes effect

**Evidence:** frozen patch lines 957–968 sum every non-NSF descendant without a transaction-date condition. Lines 976–989 require `disposed_on` to follow the payment date and the date of `status_cause_id`, but not the other tree rows whose net supplies the return. In -23's `enforce_payment_immutability`, the move to reversed accepts a non-NSF direct reversal of the posting entry when that entry's whole tree currently nets to zero. The selected reversal need not be the latest or still have an unreversed share. Frozen P14b itself selects an earlier reversal that was subsequently undone.

**Probe:** [01-return-date-tree.sql](codex-r5-probes/01-return-date-tree.sql). This uses ordinary tally_app writes at READ COMMITTED, with no trigger disabling or history-stamp override:

1. Receipt 100; original customer payment 100 on March 10.
2. Its posting entry has a +100 adjustment on March 11, a -100 undo beneath that adjustment on March 12, and another +100 direct reversal on March 13. This is P14a's tree.
3. Mark the payment reversed, naming the March 11 direct reversal instead of the March 13 row.
4. Return 100 to suspense dated March 11.
5. Read March 12 at current knowledge: predicted suspense held **100**, original payment received **100**.
6. Post another customer's payment of 100 from the receipt dated March 12: predicted accepted; the two customer payment positions then total **200 received on March 12** from the one receipt of 100.

The receipt cap sees 100 original payment, minus 100 disposition, plus 100 replacement payment. It therefore stays within its own 100 while -23 still sees the original payment's restored 100 on March 12. The final position on March 13 is not inflated; the error is the intermediate business-date position and its ability to fund a second dated posting. This matters to the promised every-date cap and historical reconciliation, not merely to an exception's wording.

The probe first asserts that the earlier status-cause selection is admitted, so an unexpected upstream refusal will be visible. It then asserts the predicted acceptance and double recognition. A savepoint removes that attempt and supplies the valid control: return on March 13, with zero suspense held on March 12 and 100 on March 13. Any unexpected caught error prints its actual SQLSTATE/message.

**Fix:** make release availability respect the tree's business-date history, not just its final net and one cause row. A conservative implementation can require the return to follow all relevant tree dates. A more permissive one must prove the returned share is available at the disposition date **and every later tree boundary**; checking only the net at March 11 would still miss the March 12 undo. Preserve the NSF-subtree exclusion and the amount bounds. Add a regression with the early cause, intervening undo and later reversal, plus a targeted mutation.

This is a new temporal variant of the earlier misposting findings, not a claim that r5 still counts the specific NSF subtree from round 4.

## S1 — executed: remaining test labels and coverage should be tightened

Source inspection only:

- The frozen race header still calls SU3/SU3b “posts,” but `apay()` inserts a pending payment. This tests insertion versus recorded_in_error, not posting versus lapse/withdrawal. That part of **Codex r1 S2 remains open**.
- A4/A5b/L6d still test application ACL refusals, not owner trigger behavior. Their labels are reasonable as application assertions, but do not establish the all-role guarantee. Probe 02 separately exercises owner edits and resurrection.
- P14a–d test final balances after their tree histories; they do not compare the intermediate tree dates against disposition/replacement-payment dates. Probe 01 supplies the missing case behind B1.
- `G6` is used twice: the shortfall-reissue trace and the goodwill-refund refusal. Give each a unique id before attaching a mutation to either; the runner identifies checks by label.
- The shortfall trace now has behavioral coverage (G6/G6a/G6b), but no dedicated mutation of its branch appears in the frozen mutation list. The 1,000-step agency-lineage bound remains expressly untested. Neither omission alone is a blocker.

The runner's first-failure matching is materially stronger than “any failure means caught.” M56 now removes the actual mismatch refusal, resolving the earlier wrong-reason objection. M98/M106/M109 target the top-level NSF filter, descent and nested NSF filter respectively; M110 removes the new payment-date rule. I found no new source basis for alleging an incorrectly credited mutation result. I did not execute any mutation.

## N2 — predicted: closure of earlier findings

Database evidence for these closure predictions is [00-frozen-battery-coverage.sql](codex-r5-probes/00-frozen-battery-coverage.sql), a copy of the frozen r5 battery with SQLSTATE/message logging added to its catches, supplemented by probes 02–05. The original r2 probes are not represented as r5 execution evidence.

| Finding | Round-5 assessment / probe coverage |
|---|---|
| r4 Fable B1: NSF below a reversal's undo | Specific shape closed: recursive descent excludes NSF at both entry and recursive steps, pruning descendants too. 00 P14c; bank-return undo followed by a separate reversal is 00 P14d. B1 above is separate. |
| r4 Opus S1: return before payment date | Closed: explicit payment-date refusal, with both boundary sides in 00 P9b11/P9b12. |
| Codex r1 B1: late provider id / instrument drift | Closed in source: UPDATE checks first provider assignment and receipt instrument equality. 00 U8h/P5e; isolation probes 03/04 include late assignment. |
| Codex r1 B2: equal ids across tables | Closed: provider self-exclusion is table-specific. 00 U8f and companion checks. |
| Codex r1 B3: reversed label releases bank money | Exact original bypass closed: explicit return, code guard, amount calculation, once-only index, late-code refusal. 00 P9/P12/P13/P14. Temporal correctness remains blocked by B1 above. |
| Codex r1 B4: recorded order | Original draw-before-release case closed: payment/disposition order checks include dispositions, payments and terminal recorded times. 00 O1 family. |
| Codex r1 B5: provider snapshot isolation | Closed: common provider checker requires READ COMMITTED, including late assignment. 03 REPEATABLE READ and 04 SERIALIZABLE predict 25000. |
| Codex r1 B6: invisible/nonfinite clocks | Closed for the reported cases: seven-table recorded-at guard plus finite date CHECKs. 00 O2 family. |
| Codex r1 S1: invariant existence/grant/body holes | Closed for the reported holes: required manifests, validated constraints, valid unique indexes, stamp grants and body hashes. 00 I8/I9; 05 catalog controls. |
| Codex r1 S2 | Missing-user case and misleading P4c label corrected; M56 corrected. Race “posts” wording remains as S1 above. |
| Codex r2 probe 01: mixed bank return and misposting | Closed for 40 bank / 60 misposted: 00 P13/P13b/P13c. |
| Codex r2 probe 02: recorded-order equal id | Closed: exclusion per table, 00 O1e. |
| Codex r2 probe 03; r2 reviewers' B1: unordered releases | Closed for reported undo/reversal recorded-time cases: every disposition is ordered; reversal status_recorded_at included. 00 O1f/O1g. |
| Codex r2 probe 06; r2 S1: invariant scope | Required attributes, helper EXECUTE and NOT NULL now present; 00 I9. Scope qualifications below still apply. |
| Codex r2 probe 07: NaN | Receipt/disposition/pledge and pledge-payment checks now refuse it. 00 U3b/X5b/L6e/L7f. This does not claim -23's general money NaN issue is fixed. |
| r3 B1: reversal undone and re-entered | Final-balance variant closed: full pruned-tree net, bounded by payment. 00 P14a/P14b. B1 above exposes the date variant. |
| r3 should-fixes: below-zero cap, own-void exclusion, NaN pledge payment, P9b3 label | Corresponding source clauses and revised label present; 00 O4/L7f/P9b3 and cap cases. Lower-bound and upper-bound defenses remain partly exercised through mutations, as the plan discloses. |

The r2 statement-shape and isolation probes were coverage probes, not additional confirmed blockers. Their updated r5 counterparts are [02](codex-r5-probes/02-statement-shapes-and-roles.sql), [03](codex-r5-probes/03-repeatable-read.sql) and [04](codex-r5-probes/04-serializable.sql).

## N3 — predicted: design, rulings and bypass matrix

These are source conclusions awaiting the indicated probes, not universal impossibility proofs.

| Requirement / attempted bypass | Assessment and probe |
|---|---|
| Receipt spent twice | Ordinary payment/disposition overdraw is guarded by the receipt cap; B1 defeats temporal composition with the ledger. 00 P/X; 01; 02 multi-row/CTE/COPY. |
| Payment dated/effective out of bounds, wrong tenant, missing reason/operator | New insert/update checks plus inherited payment immutability and composite keys address the stated routes. 00 P3/P4/P5/T/O3. |
| Guessed application | Candidates are evidence; no new writer chooses a customer from them. 00 C and U1b. Resolution requires explicit customer, reason and operator. |
| Provider transaction twice | Incoming namespace spans receipts and payments; own-table payment uniqueness remains inherited. Refund ids are a separate outgoing namespace. 00 U8; 03/04. |
| Pledge paid by another agency/customer or ended twice | Identity check, immutable link and one-event unique constraint. 00 L7/L8/L11–L14. |
| Premature lapse / recorded-in-error pledge paid | Date/pay-by checks and payment/event checks. 00 L10/L12/L14; 02 adds both dependent writable-CTE directions. |
| Pledge overpaid | Intentionally accepted; excess real money belongs to the payment, not an invented pledge cap. 00 L12. |
| Agreement/pay-by chosen by caller | Refused; database selects the latest unwithdrawn effective agreement under agency lock and stores its result. 00 A/L1–L4. |
| Pledge state precedence | void, paid, effective event, no_agreement, overdue, open. Reader uses received money, not pending amounts. 00 L8–L15. |
| Agency refund to customer or another agency; customer money to agency | Typed source paths are checked, including overpayment and both reissues. 00 G1–G7. L5/L6 remain outside that guarantee. |
| Agency brought back / agreement terms edited | App ACLs and owner guards are distinct defenses. 00 A/L17; 02 owner cases. |
| Cross-tenant / history-load paths | Composite keys, FORCE RLS and ALWAYS triggers cover ordinary roles; explicit tenant checks cover the reported FK-off load cases. 00 T/O3, 02 roles. This is not a claim that arbitrary superuser disabling of guards is prevented. |

The record-side design substantially implements CI-053 and CI-056, subject to B1. Typed pledges and suspense readers provide the core's inputs; operator queues, reporting, jurisdictional protection and disconnection decisions are not built by this patch. `past_retention = NULL` when unset is now explicitly documented as unknown. The inventory's original `program_types` formulation became `program_kind` and agreement terms in the design; the bill restriction is now enforced by equality rather than automatically filled by the database (00 L18).

## N4 — predicted: interaction with -23/-27, concurrency and invariants

**Composition.** The frozen patch does not re-issue an existing cash/shortfall function. It adds nullable payment fields and guards; -23/-27 continue deriving their own positions from the same ledger and lineage. This does not imply semantic isolation: probe 01 demonstrates the predicted mismatch between -24's release and -23's date-sensitive received figure. Probe 00 G6 covers the shortfall-reissue trace, and [05-catalog-contract.sql](codex-r5-probes/05-catalog-contract.sql) invokes all four relevant invariant functions without changing them.

**Trigger order matters.** Stamping, inherited freeze/birth/immutability checks and the new BEFORE payment guard compose by trigger name; receipt-cap enforcement is AFTER INSERT, so it can inspect all inserted rows. Probe 05 prints the actual payment and ledger trigger ordering; 00 P4c and 02 multi-row/CTE/COPY exercise the behavioral distinctions. The CI diff ports -23's agency fixture by supplying agency_id and adds -24 after the stated pending patches; I did not run either battery through CI.

**Locks.** Both receipt-cap write call sites acquire the receipt advisory lock before the order/cap reads. The provider checker takes its namespace lock and pins isolation itself. Pledge insertion and agreement writes share the agency lock with retirement; payment insertion and pledge events share the pledge lock. The standalone cap helper is read-only and does not itself lock: calling it alone must not be treated as authorization to write. Probe 00 covers ordinary guarded paths, 02 statement shapes, 03/04 isolation pins. Frozen SU1–SU12 provide source coverage for the documented cross-session handshakes, not results reproduced here.

The blanket phrase “lock between payments and events” needs its scope understood: the new pledge lock is on payment INSERT, not every later posting/status update. Pending insertion already prevents recorded_in_error; late payments are expressly allowed after lapse/withdrawal, and the reader lets paid outrank those events. I do not infer a new blocking race from this allowed state model. I also do not certify all status-transition interleavings from SU3.

The stated head → inherited cash locks → receipt/pledge order describes individual paths, not a globally sorted transaction-wide acquisition order. Multi-row/CTE operations and caller-composed transactions can acquire several source locks; 40P01 and 40001 retries remain mandatory. No claim of deadlock freedom or executed contention testing is made.

**Tree bounds.** The new downward CTE has no explicit depth counter. Its normal-data bound comes from -22's ALWAYS lineage guard rejecting loops and paths beyond 1,000 entries, retained alongside -23's reversal guards. Probe 05 exposes that inherited trigger/function contract. This bounds depth, not total width or execution time; the three planner settings are present and included in the attribute manifest. I did not benchmark a deep tree. A corrupted database with lineage validation disabled is outside this prediction.

**Invariant reach.** It now tests required trigger definitions/enabling, exact sole RLS policy and FORCE flags, table/column grants, validated constraint definitions, valid unique-index definitions, 28 body hashes, function volatility/security/settings, required NOT NULL and app helper EXECUTE grants. Probe 00 I1–I9 tests the listed drift cases; probe 05 checks the installed combination. These are required-item manifests, not equality checks for every possible extra schema object, and do not prove data semantics: a pinned body can still contain B1. Inherited helper bodies and every reader ACL are not independently pinned by this -24 function. Its wording should be read at the actual enumerated scope; I found no new blocker in that scope.

## N5 — predicted: known limits and completion conditions

- **L1:** candidate quality remains intake's responsibility; the schema cannot protect an account absent from the candidate set. No separate blocker. Probe 00 C/S tests the supplied candidates, not matching quality.
- **L2:** statutory pledge protection and its operational enforcement remain staged core/rule work. No separate blocker for this record patch; 00 L/S proves inputs only, not a working disconnect pause.
- **L3:** batch matching remains core work. No separate blocker for storing an unmatched item; 00 U/A covers those records, not an import route.
- **L4:** the missing close-snapshot line is a stated follow-up, but its replacement held reader must reconcile at the chosen dates. Probe 01 is a concrete reason that prerequisite is not yet satisfied.
- **L5/L6:** accepted by Ryan in the 11-07 DECISION-LOG. Deposit returns and untyped credit origins are not certified as database-routed agency refunds. The rule still applies to the core. These accepted limits are not new blockers; probe 00 G supports only the typed paths actually claimed here.

Have the author run probe 01 first and preserve its notices, then the other five probes on fresh clones. If the predicted B1 acceptance and March-12 figures hold, fix the temporal release rule and add the regression/mutation before marking ready. If an upstream guard refuses the prerequisite, report its exact SQLSTATE/message and reassess B1 against that evidence. No database result in this review has been presented as executed.
