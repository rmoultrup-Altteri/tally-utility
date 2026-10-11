# Review round 3 — v5.4.2-18 (Fable)

Frozen r3 checked: patch md5 `cc820b6de0d3671d1337b7157639903b` (866 lines), battery md5 `294ea5f8814fc1aa3695d1f93be505fb` (unchanged from r2); the repo's `sql/v5.4.2-18-backbilling-rule-terms.sql` and `tests/v5.4.2-18/battery-18.sql` equal the frozen copies. The r2→r3 diff is confined to the adoption check (note/class agreement; the protected-twin comparison) and residuals R10/R11.

## Verdict: READY — no blocking item; one should-fix (a check narrower than its claim), subject to Ryan's R10 decision which is not for reviewers.

What ran (own clones `fable18r3*`; `tally` untouched):
- strict apply on a clone of `tally`; battery-18 r3 107/107.
- on the migrated clone: batteries 09, 10, 11, 12, 13, 14, 16, 17; lawfiles-17 W1–W5 (W2 no drift, W3 re-seeds the 16 unchanged, W4 2015 documents 0 disagreements); isolation-17; rule-close-17 races. All pass.
- migration-18.py with PATCH18 = frozen r3: 52/52 (P7ah–P7al included).
- mutations-18.py (97): result appended at the end. (For the record, the r2 suite finished 92/92 caught before r3 arrived.)

## The two folds

**Note/class agreement (patch:213-220).** `v_unreached IS DISTINCT FROM (customer_class = 'unprotected')` raises before either branch. This closes r2 S2 both ways (P7ak, P7al; M95). The builder is unchanged, which is fine: a disagreeing row now fails the fill rather than being built wrong. The migration's Texas-gas refusal still runs first, so the `'unprotected'` literal is only ever applied to TX gas.

**The protected-twin comparison (patch:242-256).** For a delegation, the old row's outcomes (as a set), units flag and delivery path must equal those of the protected row with the same state, service, cause and `effective_from`. For the sixteen every unprotected row has such a twin and the facts agree (verified by P1/K2 and by reading `tally`). P7ah–P7aj and M94/M96–M98 prove each leg bites when the twin differs.

## Should-fix

**S1. The twin comparison passes when there is no twin.** patch:248 is `IF EXISTS (SELECT 1 FROM backbilling_rules q WHERE … q.customer_class = 'protected' AND q.effective_from = … AND (facts differ))`: with no protected row of that cause and start, EXISTS is false and the delegation drops its cause facts unseen — exactly the "different classification dropped unseen" the comment says it prevents. Probe (clone of `tally` plus one historical unprotected rate_misapplication row 1991-01-01..1992-01-01 with `units_invariant=false, delivery_path=adjustment` — the opposite of the real cause facts — and no protected row starting 1991-01-01): the patch applies, the row is adopted as `delegated_to_utility`, nothing is said. Also the twin is matched on `effective_from` equality, so a protected row of the same cause in force over the same dates but starting on another day is not the twin either. Fix: select the protected row of the same cause whose range overlaps the delegation's (`daterange(q.effective_from, q.effective_to, '[)') && daterange(p.effective_from, p.effective_to, '[)')`), require exactly one (raise "no protected row of this cause to compare with" when none), then compare. Add a P7 case with no twin and a mutation that drops the existence requirement. Not blocking: the sixteen all have twins with equal facts, and the migration refuses any non-Texas-gas row, so no production row can reach the gap; but the check as written certifies more than it checks.

## Notes

**N1. R10's rewrite is right and complete:** what is lost (outcomes, units, delivery path, the anchor with the outcomes), where it must live (the future tariff kind or the core's cause semantics), and limitations law bounding a delegated window at the future comparator. The decision whether the eight are delegations at all remains Ryan's; the mechanism holds either way (a law answer is a different builder branch and the same checks).

**N2. R11 is a fair statement** of the three R-39 rows as law-shaped placeholders whose correction, when counsel rules, is a row wrong from its first day (-17 R2) rather than a close-and-successor. Agreed that the "no limit vs the tariff's limit" reading of an empty window is a Kyle question; nothing in the database depends on the answer yet.

**N3. Leftovers on the container (not the patch's):** two databases `m18_a_97868`, `m18_b_97868` exist in `tally-pg` from an interrupted migration-18 run (not mine: my r2 mutation run finished and cleaned its own); whoever owns pid 97868 should drop them.

**N4. Carried, fine to leave:** DEPLOY-VERIFICATION.md:123 and the parity `catalog-identity.sql` scripts name the dropped tables; `maxItems` 8 vs seven kinds; run-battery-18.sh's fixed `/tmp/battery-18.sql` (identical content).
