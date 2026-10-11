# Review round 2 — v5.4.2-18 (Fable)

Frozen r2 checked: patch md5 `2715fe7723fad45d6a71190eb805ec57` (814 lines), battery md5 `294ea5f8814fc1aa3695d1f93be505fb`; the repo's `sql/v5.4.2-18-backbilling-rule-terms.sql` and `tests/v5.4.2-18/battery-18.sql` equal the frozen copies.

## Verdict: READY — no blocking item, subject to Ryan's confirmation of R10 (a meaning change, not a defect). Two should-fixes, the rest notes.

What ran (own clones `fable18r2*`; `tally` untouched):
- strict apply on a clone of `tally`; battery-18 r2 107/107.
- on the migrated clone: batteries 09, 10, 11, 12, 13 (rewritten C/Z), 14, 16, 17; lawfiles-17 W1–W5 (W2 no drift, W3 the regenerated 16-row file re-seeds unchanged, W4 2015 documents 0 disagreements); isolation-17; rule-close-17 races. All pass.
- migration-18.py (per-process names now) with PATCH18 = frozen r2: 47/47 pass (P1–P7, including P3's closed historical rows and P7's call in the trigger's row shape).
- mutations-18.py (92): result appended at the end.

## The changes, reviewed

**(1) `system_kinds = {distribution}`.** Right for the vocabulary as it stands: of the three gas kinds (`distribution` "natural gas, including gas blended with propane", `master_meter`, `piped_propane_distribution`), only `distribution` serves the public with natural gas under GURA; LPG distribution is outside §101.003(7)(B), and master meters are a Kyle question that fails closed (R9). §7.45's preamble, as R8 quotes it, orders "each gas distribution utility" — the same word. L6/L7/O11 cover it. Nothing broke: the spans are recomputed at registration for every legacy row, the exclusion still refuses a `{cooperative}`-only row (O9), and a master-meter row sits beside the sixteen (O11).

**(2) The eight unprotected rows as delegations.** The mechanism is sound: the builder returns the standard delegated document for a note that starts "16 TAC 7.45 does not reach this class;", the adoption check demands exactly that document (citation `16 TAC 7.45`, note = source_note whole) and demands the old columns claimed nothing (uncapped, permitted, whole periods, no supervisor evidence, no window terms — P7ab–ag, M85–M89), the fill clears the facet and the template's facet compare refuses a kept one (M91), and the identity hash masks the facet only for those rows (M92). What the eight drop (read from `tally`): meter_error `delivery_path=adjustment`, outcomes `{fast,slow}`, basis test_date; non_registering_meter outcomes `{non_registering}`, basis test_date; rate_misapplication `delivery_path=reissue`, `units_invariant=true`. R10 calls these mechanics of the cause authored as defaults (the -13 seed wrote them by CASE on the cause, sql/v5.4.2-13:1020-1023 — true). Two things for Ryan's confirmation, below (S1, N1).

**(3) The Texas-gas refusal.** patch:368-375, before any snapshot or DDL; names every offending row; P4a/M81. Correct and fail-closed.

**(4) Outcomes in byte order.** Insert check (law branch only, patch:141-147), builder sorts, adoption check compares as a set (patch:260-263), X12/X13, P3's unsorted historical row, P7af, M90. The law file's `[fast, slow]` and `[non_registering]` are in order; W3 re-seeds unchanged.

**(5) Adoption check no longer compares the strategy; comment states the two limits.** Agreed; P7 now calls it in the trigger's shape (`shaped()`), and P7i is honestly caught by the outcomes comparison.

**"Delegations in disguise?"** The three R-39 rows ("no 7.45 billing cap; enforceable classification referred to counsel — never pending, per fail-toward-protection") are not delegations: §7.45 sets no window for those causes (uncapped is the law's silence) and `enforcement: never` is the platform's own protective ruling pending counsel — the utility is given no choice, so `delegated_to_utility` would be wrong. They are law rows whose enforcement value is provisional; R4 already says the lead clause is a ruling id. estimation_catchup cites (6)(C) and (4)(E)(vii): law. tampering_bypass cites (4)(D)(v): law. No other disguise.

## Should-fix

**S1. The unprotected delegation overstates what it says.** The note the document carries whole says "ordinary limitations law and the filed tariff govern": limitations law (the statute of limitations on the debt) is law, not the utility's choice. `governs: delegated_to_utility` tells the core and the future tariff check that the law leaves the window entirely to the tariff — so a backbilling tariff claiming ten years for unprotected customers would meet no law row with anything to compare, and "stricter, never looser" would pass it. The faithful document is either a law row with the limitations window (needs Kyle's ruling on which limitations period and its anchor) or the delegation as written plus a stated residual that the tariff comparator must bound a delegated window by limitations law when that table exists. Ask Ryan to decide which; the patch's R10 should say it either way. (Not blocking: nothing reads the document yet, and either choice is a close-and-new-row later.)

**S2. The delegation branch is keyed on the note's words, not on the class.** patch:197, 202, 313-316, 378-379: `source_note LIKE '16 TAC 7.45 does not reach this class;%'` decides delegation; `customer_class` is never consulted. Probe (clone of `tally`, one unprotected note reworded to "7.45 does not reach this class; …", patch applied): `unprotected/crossed_meters` adopted as `governs=law, enforcement=uncapped, anchor_basis=discovery_date` — an uncapped permission written as law for a class the vocabulary itself defines as "16 TAC 7.45's backbilling limits do not reach them". The converse (a protected row with that note and empty-looking columns) would be adopted as a delegation. For the real sixteen the two agree, so this is a robustness point, but it is cheap and in the spirit of "guard the act, not the label": for a Texas gas row, require `v_unreached = (customer_class = 'unprotected')` in the adoption check (and the builder), raising when the note and the class disagree. Then neither a reworded note nor a mislabeled class can flip a row's nature.

## Notes

**N1. What the eight drop is not all "defaults".** `units_invariant = true` on unprotected rate_misapplication and the `qualifying_test_outcomes` on the two test-anchored unprotected rows are statewide facts about the cause (R-39 "correct units, wrong price"; "the outcome decides the cause"), seeded by cause, not by class. After -18 the core has no place to read them for an unprotected case until a tariff table or a core-side cause table carries them. R10 says the core refuses an unprotected case until a tariff exists, which keeps it safe; the HANDOFF should say that the tariff (or the core's cause semantics) must restate units invariance and the qualifying outcomes, or the unprotected rate-misapplication case will have lost a constraint -13 held.

**N2. R8's reading of the preamble supports `{distribution}` and NULL jurisdiction** ("each gas distribution utility … incorporated areas … except where a municipal standard conflicts"). The per-premise carve-out is correctly left to the core/tariff. Nothing to change; I could not verify the preamble text independently.

**N3. Harness.** Per-process names work (migration-18.py `nm()`, `/tmp/m18_<pid>.sql`; mutations `m18mut<pid>`); I ran the repo scripts directly this round. run-battery-18.sh still copies to a fixed `/tmp/battery-18.sql`, but the content is identical across runs, so harmless.

**N4. Carried from r1, still open and fine to leave:** `sql/DEPLOY-VERIFICATION.md:123` and the parity `catalog-identity.sql` scripts name the dropped tables (mirror-time docs); maxItems 8 vs seven kinds.

## Decisions (brief §3), r2
Owner types — agreed (r1). System kinds `{distribution}` — agreed. Jurisdiction NULL — now cited (R8); agreed. Delegation for the unprotected class — mechanism correct; meaning for Ryan (S1, N1). Refusing municipal/propane/master-meter — agreed, fails closed.
