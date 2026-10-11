# v5.4.2-18 review round 2 — Opus

Hashes match (patch 2715fe77…, 814 lines, = sql/v5.4.2-18-…; battery 294ea5f8…, = tests/v5.4.2-18/battery-18.sql). Strict apply on opus18r2 (clone of `tally`, TEMP revoked): OK. battery-18: 107 PASS, no FAIL. migration-18.py (per-process names now) against `tally` with PATCH18 = frozen r2: 47 PASS, all pass. mutations-18.py not run by me (92 mutations; time).

Round-1 items: B1 folded (system_kinds {distribution}, R1, R9, tests). S1 → R8, S2 → R1, S3 → insert check + builder + check, N1 → comment, N2 → per-process names, N3 → G4 sweep, N4 → R4, N5 → PRECONDITION. All fine.

## Verdict: READY on the code, conditional on Ryan's B2 ruling — with one should-fix on R10's wording and what the delegations drop

### S1. The delegations drop cause facts that are not defaults, and the check does not even look at them
R10 says the unprotected rows' delivery path, units flag and test outcomes "were mechanics of the cause, authored as defaults". The -13 data says otherwise (tally, unprotected rows):
- meter_error: anchor test_date, outcomes {fast,slow}, delivery adjustment;
- non_registering_meter: test_date, {non_registering};
- rate_misapplication: units_invariant TRUE, delivery reissue.
These equal the protected rows' values cause by cause. They are R-39 ("the outcome decides the cause"; "correct units, wrong price") and R-33: Kyle's classification of the cause, independent of class and of 7.45's reach, not authored defaults. The adoption check's "claimed nothing" condition (patch, adoption check, v_unreached branch) tests enforce_scope, duty, straddles, supervisor evidence and window terms, but NOT units_invariant, qualifying_test_outcomes, anchor_basis or delivery_path. So a delegation silently drops units_invariant = true, which contradicts R10's "over old columns that must have claimed nothing".
It fails closed today (no backbilling tariff table, so unprotected cases are refused), so this is not blocking. But when the tariff kind is designed, each utility would re-author Kyle's cause classification. Fix: (a) correct R10. These are cause facts, and they now live only in -13's seed and git. (b) Record where they go: the cause vocabulary (backbilling_causes: anchor basis, qualifying outcomes, units invariance, maybe delivery path) or the future tariff kind as non-overridable inputs. Frame it as a cheap, additive change now. (c) Either make the check name those four columns in its message or compare them with the same cause's protected row, so the drop is deliberate rather than unseen.

### S2. The three R-39 rows: law-shaped placeholders, not delegations
Their note reads "R-39: no 7.45 billing cap; enforceable classification referred to counsel — never pending, per fail-toward-protection." 7.45 does reach the protected class, so these rows are not delegations. The empty windows (no cap) are a reading of the law. But enforcement `never` is the platform's interim policy pending counsel, stored as what the law says. When counsel rules, the change is a correction of a row that was wrong from day one, not a change in the law. A close plus successor would date it falsely, which is -17 R2's correction lineage. Add a residual naming these three as pending counsel, with a Kyle/counsel question. Nothing to change in the code.

### N1. Do other "uncapped" law rows mean "the tariff governs"?
Protected tampering_bypass (uncapped, "outside the backbilling limits") and the R-39 rows' empty windows are law documents saying "no cap". A law document lets the core backbill without any tariff, while a delegation would not. The current reading is defensible (7.45 reaches the class and imposes no cap), but ask Kyle whether these really mean "no limit" or "the tariff's limit".

### N2. The delegation loses the limitations law
The unprotected note says "ordinary limitations law and the filed tariff govern". The delegated document carries that only as note text. When the tariff table arrives, the statute of limitations is still law that bounds the tariff. Worth one line in R10 or R2.

### N3. Classification by note text
The builder, the check, the identity hash and the Python expectations all key the delegation on `source_note LIKE '16 TAC 7.45 does not reach this class;%'`. That holds for this one-time migration on known data, restricted to Texas gas. The Python expectation uses the same rule, so K2 and P1b are not independent on which rows are delegations; the list of eight is fixed by K. Fine.

### Checked and fine
- The delegation's anchor-facet clearing: the fill sets anchor_basis NULL for delegations, which is needed because the template refuses a writer facet that differs from the derived one. The hash excludes it only for those rows, and nothing in the case or evaluation guards compares a rule's anchor_basis.
- The Texas-gas refusal runs after the already-registered early return, so a second run is unaffected; P4 covers it.
- `{distribution}` is the only gas kind serving natural gas (including propane-blended) to the public in the vocabulary. Piped propane is excluded by (B)(ii). Master-meter is out by default (R9). A future kind fails closed.
- Outcome order is enforced in the insert check, and the builder and check sort.
- "Remain after an abort" in PRECONDITION applies only without `-1`; CI applies with `-1`, so nothing remains.
- On B2's merits: correct. 7.45 is for residential and small commercial; for the class it does not reach, the law leaves the matter to the utility's filed tariff (plus limitations law), which is V8's document. Failing toward refusal is right under "unknown law is not permission".
