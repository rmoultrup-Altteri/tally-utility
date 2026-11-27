# v5.4.2-25 r7 — Fable's review (disputes, round-6 findings fixed)

**Date:** 2026-11-26. **Reviewer:** Fable (claude-fable-5-2). **Verdict: ready.** Nothing blocking and nothing to fix before the mirror. Both of my round-6 should-fix items are closed, with both sides tested. The must-pay ordering is now consistent over every pair I could build. Six notes; two of them (N3, N4) ask for one sentence each in the application contract when it is written at the mirror, because the comparator's ordering is only right if the core computes the average cap and reads the final flag the way the patch assumes.

**Frozen files:** the ten md5s and the brief's own md5 match. Reviewed only those copies; read my own `fable-r6.md`, the r7 plan in full and `r6-to-r7.diff` in full. Did not read any `opus-*` or `codex-*` file.

**Reproduced** (clones of `tally`, none left over from round 6; TEMP revoked from PUBLIC, `tally_app`, `tally_core`; frozen patch applied strictly, `search_path=''`, `check_function_bodies=on`):
- strict apply succeeded on both clones; the second run said "already applied (disputes exists); nothing to do";
- `battery-25-frozen-r7.sql` on `rv25fable`: 351 PASS, 0 FAIL, rolled back ("battery-25: all checks passed"), so `assert_dispute_guard_invariants()` passes with the two changed hashes;
- `disputes-25-frozen-r7.sh` on `rv25fable_race`, one run: 30 of 30.

Not run, per the brief: `mutations-25.py`, `migration-25.py`, `ci.sh`, `terms-25.py`. No role created, dropped or altered. Both clones and my files in the container are dropped; `tally`, `sql/tu.sql` and the repo are untouched (this file is my only write). No container started.

How the probes ran: appended to a copy of the frozen battery after D9u (line 1753, before the H section), inside its one rolled-back transaction, on its own fixtures (`verdicts`, `combo`, `tight2_sql`, `det2_sql`, `file2_sql`, `wcap`, `undisp`, `avg`), as the owner. The hand mutations replaced `enforce_dispute_determination()` inside that same transaction (from `pg_get_functiondef`, one text replacement, anchor checked) and ran the battery up to the H section.

---

## B — blocking

None.

## S — should fix

None.

---

## N — notes

### N1. My round-6 findings are closed — executed

- **S1 (a withholding of 1 or more against an average cap).** Fixed in both directions, and the boundary is at 1. Direct calls and the real path:

```
policy withhold 1 / 1.0 / 1.1 | law average cap   -> no finding
policy withhold 0.9 / 0.999   | law average cap   -> must_pay: not_comparable
policy average cap            | law withhold 1 / 1.0 / 1.1 -> must_pay: looser   (combined: the law's term, id m2)
policy average cap            | law withhold 0.9  -> must_pay: not_comparable     (combined: both kept)

file "withhold up to 1.1" on July 1 under a law of the average cap        -> ADMITTED
file "withhold up to 0.999" under 7.45                                     -> REFUSED 23514
file an average-cap policy under a later law "withhold up to 1.1"          -> REFUSED 23514
average-cap policy, later law "withhold up to 1" (m2): record names m1     -> REFUSED [D4g] "is not the cited document's (m2)"
                                                       record names m2     -> ADMITTED
average-cap policy, later law "withhold up to 0.9":    m1 -> ADMITTED; m2  -> ADMITTED
```

  The last-but-one pair is my round-6 case B2 at exactly 1, which the battery tests only at 1.1 (D9t2, D9t3); it behaves the same. `1.0` and `1` compare alike (the fraction is cast to numeric).
- **S2 (the unruled end had no fixture).** D4y2 and D4y3 reach the branch on the real path. Three hand mutations, all caught:

```
unruled branch turned off (falls to the fail-closed branch)   -> FAIL at D4y2 ("a kind this check does not know")
unruled fits only with a last day                             -> FAIL at D4y3
unruled fits only with no last day                            -> FAIL at D4y2
```

  So the two checks are independent: each side of "with a last day and with none" is held by its own check.
- **N3 (the law's final flag, the unpinned direction):** D9u pins it; see N4. **N4 (the `any_time` premise), N5 (the fail-closed branch's comment), N6 (D9s's label), N8 (the stale sentence):** all done as the plan says.

### N2. The must-pay ordering, whole — executed (11 terms by 11)

Terms: unruled, full bill, withhold 0.5, 0.9, 0.999, undisputed charges, withhold 1, 1.0, 1.1, the average cap (2 years), a different average cap (3 years). Rows are the policy, columns the law, in that order; "ok" is no finding.

```
unruled   | ok ok LOOSER LOOSER LOOSER LOOSER LOOSER LOOSER LOOSER LOOSER LOOSER
full_bill | ok ok LOOSER LOOSER LOOSER LOOSER LOOSER LOOSER LOOSER LOOSER LOOSER
W0.5      | ok ok ok     LOOSER LOOSER LOOSER LOOSER LOOSER LOOSER nc     nc
W0.9      | ok ok ok     ok     LOOSER LOOSER LOOSER LOOSER LOOSER nc     nc
W0.999    | ok ok ok     ok     ok     LOOSER LOOSER LOOSER LOOSER nc     nc
UC        | ok ok ok     ok     ok     ok     ok     ok     LOOSER ok     ok
W1        | ok ok ok     ok     ok     ok     ok     ok     LOOSER ok     ok
W1.0      | ok ok ok     ok     ok     ok     ok     ok     LOOSER ok     ok
W1.1      | ok ok ok     ok     ok     ok     ok     ok     ok     ok     ok
A         | ok ok nc     nc     nc     LOOSER LOOSER LOOSER LOOSER ok     nc
A3        | ok ok nc     nc     nc     LOOSER LOOSER LOOSER LOOSER nc     ok
```

Three mechanical checks over all 121 pairs and 1,331 triples, each returning no row:
- no triple where A asks no more than B, B no more than C, and A against C is a finding (the round-6 inconsistency is gone and nothing replaced it);
- no "looser" whose reverse is also a finding (every "looser" is a strict ranking);
- no "not comparable" whose reverse is clean (every "not comparable" is refused both ways round).

Every "not comparable" left is a pair that does depend on the customer: a withholding below 1 against an average cap (a small average favours the cap, a large one the withholding), and two average caps with different history or no-history terms. Every "looser" is a pair the law wins for every customer, given the premise in N3. The schema bounds the fraction above 0 and at most 10, so there is no "withhold 0" that would have to equal the full bill.

One equivalent condition, for whoever reads the code later: in the new no-finding branch, `AND v_lp ->> 'strategy' = 'average_usage_cap'` cannot be false when reached (unruled, full bill, undisputed charges and a withholding law are all taken by earlier branches). It is harmless and reads well; no mutation can kill it.

### N3. The premise holds for every customer on the rule's literal reading, and that reading is not written where the core will find it — predicted

7.45(6)(D), as the seeded row's note has it: "the disputed portion above average usage need not be paid". Read literally, the cap bounds the disputed part only, and the undisputed part is always owed:

- average cap: pay the undisputed part, plus the disputed part up to the average-usage amount;
- undisputed charges, or a withholding of 1: pay the undisputed part;
- a withholding above 1: pay less than the undisputed part.

On that reading a withholding of at least the disputed amount never asks more than the average cap, whatever the customer's bill, disputed amount or average. No customer is worse off. Example: bill 200, disputed 150, average-usage amount 30. Average cap: 50 + 30 = 80. Withholding of 1: 50. Withholding of 1.1: 35.

The ordering is wrong only if the core computed the average cap as "the whole bill capped at an average bill" (pay 30 in the example, less than the 50 a policy of undisputed charges asks). Nothing in the patch or the schema says which formula is meant: the average cap's schema entry carries no description, and the comparator's comment defines undisputed charges ("withholds exactly the disputed amount") but not the average cap. This premise is not new in r7 (it has carried the undisputed-charges ranking since r5, and I raised it in rounds 5 and 6); r7 leans on it once more. **Suggest, at the mirror:** one sentence in the application contract for the core — under an average-usage cap the customer pays the undisputed part plus the disputed part up to the average-usage amount. Not blocking: it is a statement to the core, not a change to the patch.

### N4. R10 is stated rightly; it is not quite the only direction, though the other one costs nothing in the database — executed

R10's direction (the law's last stage not final, the policy's stage there final): D9u pins it, and the header says it depends on the customer and is the core's to apply. Right.

The other direction is D9j's own shape: a law whose regulator stage is final, and a policy that adds its own appeal after it. The combined stages come back as

```
ids    ["s1", "s2", "s3"]
final  [false, true, true]
```

so a stage marked final is followed by another stage. In the database no customer loses anything: the policy's appeal stays in the list, and the event guard reads a stage's id and decider, never the flag (my round-6 N2 admitted a stage event at `s3` after the regulator; `dispute_terms_combined` is unchanged since, its hash is not in the diff). But a core that read `final: true` as "nothing follows" would stop at the regulator and take away the appeal the utility's policy promises. **Suggest, at the mirror:** the same contract sentence covers both — at a law's place the flag says where the law's own process ends; a later stage in the list is still open to the customer. Not blocking.

### N5. The new tests are as strong as their labels — executed and by reading

- `pg_temp.ok()` fails on NULL, so D9t, D9t4 and D9u cannot pass on a missing field. No `IF NOT (...)` assertion is left in the battery; D8j and D9a now test `IS DISTINCT FROM true`; D9j compares the whole stage list.
- D9t2 is refused for its own reason: the message is "[D4g] … is not the cited document's (m2)", and frozen r6 admitted the same record (my round-6 B3).
- D9t4 checks only that two terms are kept, not which two. The either-branch has built the pair from the policy's and the law's terms since r5 and its content is pinned by D9k and D9o, so nothing is missing.
- D9u would also pass if the policy's stage were dropped and the law's stage stood in its place (also not final). That is still "the law's flag at the law's place", so the label holds.
- M17 now names N5c: N5c is the first policy admitted for the tenant whose owner type the unprotected row binds, and the mutated comparator refuses any start against that row's unruled start. The catch is the mutation's own damage, only at a check whose label is about something else. Fine as disclosed (I did not run the mutation runner).

### N6. One ambiguous clause in the rewritten comment

`dispute_tariff_compare`'s comment: "a withholding of 1 or more, like undisputed_charges, asks no more than average_usage_cap or full_bill, and a law of either against a tariff of average_usage_cap asks less". "Either" is meant as "a withholding of 1 or more, or undisputed charges", but the nearest pair in the sentence is "average_usage_cap or full_bill". The sections comment says the same thing unambiguously. A wording nit; leave it unless the comment is touched again.

### N7. Paths around, -17's template, -23's seal, concurrency, residuals

r7 adds no table, trigger, grant or lock. Two function bodies change: `dispute_tariff_compare_sections` (two conditions) and `enforce_dispute_determination` (a comment only); the manifest hunks are those two hashes, and the battery's invariant check passes with them. The comparator still reads only its arguments, invoker rights, STABLE; a missing fraction makes both new conditions NULL, which falls to "not comparable" (fails toward refusal). The guard stays `ENABLE ALWAYS`, so a superuser history load meets the same checks (D4y2, D4y3 and the D9t refusals run through it). The diff has no hunk in the seal invariant or the rule-table registration. The lock rule is unchanged and the release function's comment now states it as the header does. Races 30 of 30.

Residuals R1–R10: none blocking. R1 (no governmental class seeded) still keeps the "withhold up to 1.1" law shape out of real data; when it arrives, r7's ordering is the one it will meet.
