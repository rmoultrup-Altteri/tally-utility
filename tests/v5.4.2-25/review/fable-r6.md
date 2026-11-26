# v5.4.2-25 r6 — Fable's review (disputes, round-5 findings fixed)

**Date:** 2026-11-26. **Reviewer:** Fable (claude-fable-5-2). **Verdict: not yet** — nothing blocking, and every round-5 finding of mine is closed. One should-fix (S1, executed) needs a small change to the comparator: r6 says "undisputed charges" is a withholding cap of 1, and keeps saying undisputed charges ask no more than an average-usage cap, but a withholding cap of 1 or more against an average-usage cap is still "cannot be ranked". The three statements cannot all hold. The visible results: a policy of "withhold up to 1" is refused under 7.45 where "undisputed charges" (the same money) is admitted, and a record may name the utility's average cap under a later law of "withhold up to 1.1" where it is refused under a later law of "undisputed charges". Settled by the standing rule, no question for Ryan. S2 (executed) is tests only.

If the author would rather mirror and treat S1 as a residual, it is not a path around a guard at filing (the filing side fails toward refusal); the looser side is only in a combined record, where the core is already contracted to apply the more protective term. I would still fix it before the mirror: it is the same shape of inconsistency r6 was opened to remove, and the function is append-only once mirrored.

**Frozen files:** the ten md5s and the brief's own md5 match. Reviewed only those copies; read my own `fable-r5.md`, the r6 plan in full and `r5-to-r6.diff` in full. Did not read any `opus-*` or `codex-*` file for this round. Read the PATCH-LESSONS index and the sections on lock order as a rule, checks narrower than their claim, every branch and stated default tested, a race catch names its damage, and the rule-table fixture notes.

**Reproduced** (clones of `tally`, TEMP revoked from PUBLIC, `tally_app`, `tally_core`; no clone was left from round 5; frozen patch applied strictly, `search_path=''`, `check_function_bodies=on`):
- strict apply succeeded on both clones; the second run said "already applied (disputes exists); nothing to do";
- `battery-25-frozen-r6.sql` on `rv25fable`: 342 PASS, 0 FAIL, rolled back ("battery-25: all checks passed"), so `assert_dispute_guard_invariants()` passes with the three changed hashes;
- `disputes-25-frozen-r6.sh` on fresh clones of its own (`rv25fable_race`), two runs: 30 of 30 both times. DR2 did not miss its poll.

Not run, per the brief: `mutations-25.py`, `migration-25.py`, `ci.sh`, `terms-25.py` (unchanged since r4, md5 equal). No role created, dropped or altered. Both clones and my files in the container are dropped. `tally`, `sql/tu.sql` and the repo are untouched (this file is my only write). No container started; two `crystaldba/postgres-mcp` containers were running before I began.

How the probes ran: appended to a copy of the frozen battery after D9s (line 1715), inside its one rolled-back transaction, on its own fixtures (`tight2_sql`, `file2_sql`, `det2_sql`, `combo`, `verdicts`), as the owner. The hand mutations replaced one function inside that same transaction (from `pg_get_functiondef`, one text replacement, anchor checked) and ran the battery up to the H section, which pins the hashes: 310 checks.

---

## B — blocking

None.

---

## S — should fix

### S1. A withholding cap of 1 or more against an average-usage cap is still "cannot be ranked", though r6's own two statements rank it — executed

The comparator now holds three positions on the amount that must still be paid:
1. undisputed charges are a withholding cap of 1 (r6, item 2);
2. undisputed charges ask no more than an average-usage cap, and an average-usage cap against a law of undisputed charges is "looser" (kept from r5; the comment and the plan both restate it);
3. any withholding cap against an average-usage cap, either way round, cannot be ranked (unchanged since r1; battery N5c pins it for 1.1).

From 1 and 2, a cap of 1 asks exactly what undisputed charges ask, and a cap above 1 asks less; so a policy with a cap of 1 or more asks no more than a law's average cap, and a policy with an average cap asks more than a law's cap of 1 or more, for every customer. Position 3 contradicts that for fractions of 1 and above. (Below 1 it is right: which is better depends on the customer.)

The verdicts, by direct call (policy against law; the full 7 by 7 table is consistent everywhere else):

```
policy undisputed charges | law average cap         -> no finding
policy withhold 1         | law average cap         -> must_pay: not_comparable
policy withhold 1.1       | law average cap         -> must_pay: not_comparable
policy average cap        | law undisputed charges  -> must_pay: looser          (combined: the law's)
policy average cap        | law withhold 1          -> must_pay: not_comparable  (combined: both kept)
policy average cap        | law withhold 1.1        -> must_pay: not_comparable  (combined: both kept)
```

On the real path:

```
A1 file a policy "withhold up to 1" under 7.45's average cap        -> REFUSED 23514 (must_pay, "asks more or is not comparable")
A2 file a policy "withhold up to 1.1" under 7.45                    -> REFUSED 23514 (this is battery N5c)
A3 file a policy "undisputed charges" under 7.45                    -> ADMITTED
B1 average-cap policy, later law of undisputed charges; record names the policy's average (m1) -> REFUSED [D4g] ("is not the cited document's (m2)")
B2 average-cap policy, later law "withhold up to 1";   record names the policy's average (m1) -> ADMITTED
B3 average-cap policy, later law "withhold up to 1.1"; record names the policy's average (m1) -> ADMITTED
B4 … the law's component (m2)                                                                 -> ADMITTED
```

A1 against A3 is the pair Codex's round-5 blocker named, one law over: the same money, admitted under one name and refused under the other. That side only over-refuses. B1 against B2 is the side that matters: the same later law in money terms, and the database refuses the utility's average under one spelling and admits it under the other. B3 is the realistic case, since both documents are shapes the fixtures already model: a utility whose policy is 7.45's average cap, and a later law row in the Government Code 2251 shape (withhold up to 1.1). The guard then admits a record that holds the customer to the average cap although the law lets them withhold more than the whole disputed amount. The core is contracted to apply the more protective term, so this is the backstop failing, not the rule; but "kept both" is Ryan's ruling for pairs that cannot be ranked, and by positions 1 and 2 this pair can.

**Fix (by rule: never looser than the law; rank what can be ranked):** against an average-usage cap, treat a withholding cap whose fraction is at least 1 as undisputed charges are treated — no finding when it is the policy's, "looser" when it is the law's and the policy has the average cap. A cap below 1 stays "cannot be ranked". N5c flips to admitted for 1.1 (keep a refusal at 0.9). Tests on both sides, at 0.9, 1 and 1.1, at filing and in a combination (B1–B4 above are the shape), and a mutation per leg.

One caution, repeated from my round-5 N3: position 2 itself rests on reading the average cap as "the undisputed part, plus the disputed part up to the average". If the author's answer to S1 is instead that an average cap really cannot be ranked against a cap of 1, then position 2 has to go, and with it the admission of an undisputed-charges policy under 7.45 (the battery's default tariff). One of the two gives; today's code holds both.

### S2. The end check's new `unruled` branch has no fixture, and a seeded law row reaches it — executed (tests only)

r6 split the end check's last branch in two: an end of kind `unruled` fits any record, anything else fits nothing. No battery check records a shelter under a document whose end is unruled. I turned the `unruled` branch off (so it falls into the fail-closed one):

```
hand mutation: ELSIF v_alt ->> 'kind' = 'unruled'  ->  ELSIF false      -> SURVIVED (310 of 310)
```

The branch is reachable. A law row alone (no policy in force) whose end is unruled, a sheltered determination under it:

```
frozen r6:        last day recorded -> ADMITTED;  no last day -> ADMITTED
with the mutation: both -> REFUSED 23514 "ends the shelter by a kind this check does not know (unruled) [D4t]"
```

The seeded unprotected row for 7.45(1) has exactly this end (`{"kind": "unruled"}`), so a regression here would refuse every sheltered record for that class and the battery would stay green. This is the lesson `every-branch-and-stated-default-tested`. **Fix:** one D4 or D9 check that admits a sheltered record under a law row with an unruled end, with and without a last day, and a mutation that removes the branch.

---

## N — notes

- **N1. My round-5 findings — executed.** S1 (four untested "looser" branches): closed. D9l and D9l2 put the 60-day end under a law of resolution on the real path, both sides; D9m, D9n, D9o and D9o2 reach the full bill, the smaller fraction, the unruled section and the fewer days; M177–M181 turn each into "cannot be ranked". Direct calls for D9m and D9n are right: neither policy can be filed. N3 (two start pairs that one side always wins): closed, see N3 below. N4 (two disputes' locks): the header now says it. N5 (the displaced stage): D9r pins the order and admits a stage event at `law:s2` on the real path; the contract line covers two stages of one decider. N6 (the law's final flag): closed by item 1, see N2. N9 (boundary days): D9g4 and D9g5 pin August 8 and August 9.
- **N2. The always-run merge changes nothing but the final flag — executed.** A policy no looser in its stages comes back with its own stages, in order, each with its own id, windows and deadlines; the only differences from the policy's document are the law's `final` at the law's places and the blocks and duties sorted with the law's among them (as in r5). Checked for the battery's default policy and for D9j's three-stage policy under 7.45, under a law with an empty stage list, and under a law with no stages key. A policy document with no stages key comes back with `"stages": []` (the schema requires the key, so no stored policy is affected). D9j's policy on the real path, as it stands under 7.45: the stage event at the policy's own appeal `s3` is admitted after the regulator became final.
- **N3. The law's `final: false` over a policy's `final: true` — executed, and not pinned.** Where the policy's only stage is final and the law's stage at that place is not, the combined stage reads `final: false`. I do not see a customer made worse off: either the law has later stages, which the merge appends (more appeal, not less), or it has none and the flag ends nothing in the database (no guard reads it; the event guard reads a stage's id and decider only). But no test holds this direction: replacing the assignment with "set final only where the law's is true" survives 310 of 310. If the intent is "the law's flag, whichever way", add the case to D9j; if a policy's final decision should stand where the law is silent on finality, that is a different rule and worth a sentence either way.
- **N4. The start ranking — executed (7 kinds by 7).** A policy of `any_time` has no finding against any law start, including `on_regulator_complaint` and both day windows; every other start is "looser" against a law of `any_time`; the combination keeps the policy's `any_time` and takes the law's `any_time`. Nothing else moved. One premise to state in the comment: `any_time` covers a law that shelters on a regulator complaint only if a complaint to the regulator is recorded as a dispute with the utility (it is, as a stage before the regulator; the core must open the dispute when the complaint arrives).
- **N5. The fail-closed end branch — executed, cannot be reached by a stored document.** Both schemas require `shelter_ends` and admit four kinds, all named by the check; the platform default refuses `unruled` [L8b]; a combined end is one document's term or the pair of two valid terms, never a nested pair. Making the branch admit again survives 310 of 310, as expected for a branch only M158's damage reaches. Fine as defence; it should be said in the comment that no fixture can take it, so nobody goes looking for one.
- **N6. `lacks` — executed.** Only `dispute_terms_combined` reads the verdicts, and only for "any `not_comparable` in this section"; the four list sections are dispatched by name. `dispute_tariff_compare` returns messages only. The pending -26 patch reads neither function. All three values appear only in these two functions. D9s's label says "the single terms keep looser and not comparable" but checks the four lists only; D9k, D9o, D9o2 and D9p2 cover the rest, so nothing is missing, the label is just wider than its check. M187 mutates blocks alone; D9s's exact array would catch the other three.
- **N7. The end verdicts — executed (5 kinds by 5).** Unchanged from r5 and right.
- **N8. A stale sentence.** `dispute_tariff_compare`'s comment still opens its must-pay clause with "undisputed_charges asks no more than any strategy" and corrects it 400 characters later under "r6". Rewrite the clause rather than amend it; S1 changes it again anyway.
- **N9. Paths around, -17's template, -23's seal, concurrency.** r6 adds no table, trigger, grant or lock. The three changed functions read only their arguments and the cited rows, as in r5; all stay invoker-rights and STABLE; the guard stays `ENABLE ALWAYS`, so a superuser history load meets the same checks (the battery's D9 refusals run as the owner). The diff has no hunk in the seal invariant; the manifest hunks are the three hashes. The lock rule is now complete as a rule (two disputes' locks in a transaction's own order can deadlock; the loser retries); I found no read without the lock that orders it. Races 30 of 30 twice.
- **N10. Residuals R1–R9.** None blocking. R1 (no governmental class) is what keeps S1's B3 case from arising today.
