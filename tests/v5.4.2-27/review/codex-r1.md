# Codex — v5.4.2-27 r1

Verdict: **not yet**.

Source-only review, 2026-11-05. **Executed** means a filesystem checksum, source comparison or source inspection, never a database execution. All database outcomes below are **predicted** and have author-run probes. I ran no docker, psql, CI, race or mutation commands, and read no `opus-*.md` or `fable-*.md` files.

**N1 — executed: freeze verified before review.** All hashes match:

| File | MD5 |
| --- | --- |
| review-brief-27-r1.md | 702e7455edd45a6a60f503b30aae5ffe |
| patch-27-frozen-r1.sql | f1fbdf157f53fd098b989ec155d654ce |
| battery-27-frozen-r1.sql | 5db82bc75a30e5aba615e3e2b6bcbe21 |
| shortfall-27-frozen-r1.sh | babf6406acec78d53d9e1cfb2018d684 |
| mutations-27-frozen-r1.py | c8be8e11cc39e1524ac9775c60d811c0 |
| ci-27-frozen-r1.diff | bb7f2e5fe83202c41fcca2aaebd31196 |

The brief hash matches `review-brief-27-r1.md5`. Authority read: the two specified Kyle rulings in gas-billing-memory, the -27 design including section 8, tally-utility DECISION-LOG's relevant entries, APPLICATION-CONTRACTS AC-44, and the wave-2 source inventory. The later rulings and design control where that older inventory differs.

**B1 — predicted: an unrelated later repayment moves the return-check boundary past an outstanding earlier repayment.**

Evidence: frozen patch lines 475–503, called with NULL at the refund's departure in `enforce_shortfall_source_moves`. `max(applied_on)` includes positive repayments, not just corrective undos. Consequently, the exception intended to permit an undo followed by a refund return also skips earlier dates when there was **no undo at all**.

Author-run reproduction: [01-latest-date-hole.sql](codex-r1-probes/01-latest-date-hole.sql). Fresh clone, frozen r1 applied, owner session, normal triggers, one rolled-back transaction:

1. Payment P receives 50 dated March 10. It refunds 10 dated March 11 and 30 dated March 18; both refunds are posted before P's bounce is recorded.
2. P bounces, dated March 12. Its deficit is 10 through March 17, then 40.
3. A goodwill credit pays 20 of the shortfall dated March 18, then another 10 dated March 13. These repayments individually fit the deficit at every date from their respective dates onward.
4. The March 11 refund of 10 comes back, dated March 19. No shortfall application is undone.

Predicted result: the return is accepted. At the current recorded instant, P's position for March 13–17 is **+10**, on a payment that has ended. From March 18 onward it is zero: the remaining refund is 30 and the repayments total 30. The return check starts at March 18 and misses the earlier excess. The probe prints these positions, the zero undo-row count, and the error from explicitly invoking the cap from March 13 (predicted 23514).

This is not merely S4's documented interval between a repayment and its corrective undo: there is no corrective undo. It violates the header's first-repayment promise and section 6's requirement to undo netting that would leave the ended payment positive. Section 8's generalized latest-row boundary is too broad. H2 tests a back-dated repayment at insertion; it does not test a later return invalidating that already accepted repayment.

Fix the boundary/validation so an unrelated later positive repayment cannot hide an earlier outstanding repayment. Preserve the specifically authorized undo-and-return workflow; blindly changing `max` to `min` breaks the existing S4 expectation, as M17 already demonstrates in its intended test design. Add this sequence as a regression, including a family-credit refund variant and a later partial undo that does not undo the affected earlier repayment. Resolve the intended treatment of historical intervals explicitly rather than using the latest arbitrary row as evidence of correction.

**S1 — predicted: the invariant checks less privilege state than its comment promises.**

Evidence: frozen patch lines 996–1001. `NOT has_table_privilege(..., 'SELECT, INSERT')` does not independently require both privileges. The core branch checks forbidden writes but never requires SELECT, and omits REFERENCES/TRIGGER from the forbidden privileges despite “tally_core only read it.”

Author-run reproduction: [02-invariant-privileges.sql](codex-r1-probes/02-invariant-privileges.sql). In separate savepoints, revoke app INSERT, revoke core SELECT, and grant core REFERENCES. Predicted: `assert_shortfall_guard_invariants()` accepts each. The probe reports each result and rolls back every grant change. This is an invariant-coverage defect, not a claim that the frozen patch initially grants those wrong privileges.

Require SELECT and INSERT separately, require core SELECT, and check the full forbidden table/column privilege set consistent with the stated contract. Add corresponding invariant mutations. Existing trigger-definition, validated-constraint, policy and FORCE-RLS comparisons are substantially more exact; the comment also correctly disclaims checking function bodies.

**S2 — executed (source inspection only): the recorded-order race helper has an unbounded wait and does not check B's exit before waiting for A.**

Evidence: frozen race script lines 168–190. A's loop has no deadline and exits only on observing B's transient `race27_b_done` application name. B sets that name only after its statements and COMMIT; its command status is not checked before `wait $APID`. The outer startup poll also proceeds when it exhausts its attempts. This is visible harness control flow, not an executed race result.

Give both handshakes explicit deadlines, check B's status, and terminate/reap A on failure. A durable completion handshake would also avoid depending on observing B's two-second marker. The mutation runner invokes this helper for SR checks, so bounded failure reporting matters to both tools.

**N2 — executed: the six reissued functions differ from the base only in the intended additions.**

I extracted the last definitions in `sql/tu.sql` and diffed each against frozen r1. `cash_source_draws` adds source and target shortfall legs; the two draw readers add the source sums and payment `repaid`; the cover adds `d.repaid` to the payment's own part; the payment position appends `repaid` and adds it to remaining; `check_cash_source` adds the two purposes, the within-family exemption and the post-undo target check. No unrelated executable-body change appeared. `payment_draws_as_of` also changes its return signature, as well as the publicly highlighted `payment_position_as_of` change.

The table is additive and has no ledger-posting trigger. Basis/undo checks, typed source choice, composite tenant/customer keys, the freeze, forced RLS and SELECT/INSERT app grants are present in the source. This matches the storage approach Ryan chose and Kyle's prohibition on inventing a billed charge. Section 8 explicitly settles counting source netting in `applied` instead of adding `netted`. B1 prevents signing off the target cap.

**N3 — predicted: behavioral coverage and source-path assessment, subject to author execution.**

[03-baseline.sql](codex-r1-probes/03-baseline.sql) is the frozen battery copied into the permitted probe directory, with caught errors additionally printed as full SQLSTATE/message notices. It is not evidence of a fresh pass. It covers the following predictions already embodied in the frozen checks:

- K: ordinary source/target positions; source caps; payment take-backs; undo amount, source and date; ended/pending/deposit sources; target status; customer/tenant keys; app RLS and append-only access; credit-entry withdrawal; escheat; chosen recorded times.
- S/U: refund departure and donation undo affecting a repaid target; the authorized corrective undo workflow.
- F: family cover, repayment into a credit deficit, and the within-family exception. The trigger derives `v_within` from `overpayment_root(source)` and its `source_payment_id`, rather than accepting a purpose supplied on the row. F1a exercises an external-family target and F2 the internal one.
- B/H/D/I: family-source bounce, cap checks at different dates, freeze and invariant tampering.

The own-bounce additions cover positive ledger descendants under the posting root and moves to nsf/reversed/voided. The base's negative give-back branch separately requires a payment not to have ended (`tu.sql` around 43300); the patch does not replace that branch. Refund departures take the source/family lock in the existing payment trigger. Reissue and overpayment creation remain internal-family movements; their exemption is not newly granted to external shortfall applications. A family credit's void is not a ledger give-back. I found no additional concrete bypass on these paths; this is not a claim of exhaustive execution.

Leaving `cash_drawn_at` unchanged is consistent with the intended source guard: a take-back requires net shortfall applications to be undone first, and `check_cash_order` reads the newly extended draw set to order it after those rows. The baseline includes undo-then-bounce and family cover cases. I do not claim that it establishes all historical share combinations.

[04-statement-shapes.sql](codex-r1-probes/04-statement-shapes.sql) predicts refusal of a two-row insert and a writable CTE whose total exceeds the target's dated deficit, using tally_app after owner setup. [05-copy.sql](codex-r1-probes/05-copy.sql) predicts the corresponding owner COPY refusal and prints COPY's own verbose error, including SQLSTATE/message; it does not trust `LAST_ERROR_SQLSTATE`. All probes end in ROLLBACK. The baseline also contains owner history loads and chosen-time rejection cases. No probe results are available yet.

**N4 — executed: concurrency and test review boundaries.**

The new application trigger takes the target lock before entering the source checker; the latter takes the source payment before a family credit. The cap itself relies on its caller's lock. The new ledger guard explicitly locks the source payment; the status guard relies on `enforce_payment_immutable` taking payment and refund-source locks. I found no new cap call site lacking its stated payment lock. Opposite-family applications can invert target/source order, as the design explicitly acknowledges; I found no source proof of a deadlock that survives a whole-transaction retry.

The READ COMMITTED check is in the source checker, after the target is locked/read, and errors abort the statement. The base ledger and status writers also contain isolation guards. SR7 specifically tests REPEATABLE READ; the frozen suite has no separate SERIALIZABLE test. SR1–SR4 assert observed blocking, and SR5/SR6/SR8 exercise recorded order and retries. I did not reproduce any of these, or the strict apply/twice results, earlier batteries, races, or 35/35 mutation result. The user's source-only restriction controls the brief's request to reproduce them.

The mutation runner matches the first failure against a named check, and apply mutations match the first ERROR phrase. I found no specific mutation demonstrably credited for the wrong failure from source alone. Its 35 mutations do not cover B1 or S1. The battery's end-of-year position helpers cannot detect B1's intermediate-date excess; its H and S sections need a combined sequence. The supplied statement-shape probes fill another gap, but are not a substitute for author-run isolation and concurrency tests. CI's diff adds the pending patch, battery and races; the patch tail and battery invoke the new invariant.

**N5 — executed: residuals R1–R4 are not independent blockers.**

R1's core ordering/refund policy and R2's per-jurisdiction escheat setoff policy follow the recorded decisions; this review does not demand a new customer-wide database guard. R3 expressly limits targets to ended payments, consistent with the design, leaving partial reversals on still-posted payments outside this patch. R4's split between a stored netting act and the core's customer-wide display is also authorized. The residuals do not excuse B1, which is inside the implemented target-cap contract. AC-44 still says -27 is “claimed, not drafted”; update that documentation when the patch is accepted.

Only this review and `codex-r1-probes/` were written. Author execution of B1 and the privilege probes is the next evidence needed; no database finding here is presented as reproduced.
