# Opus review: v5.4.2-25 r7 (disputes, round-6 findings fixed)

**Date:** 2026-11-26. **Reviewer:** Opus. **Round:** 7.
**Verdict: ready.** Nothing blocks the patch and nothing needs fixing before the mirror. There are four notes: two are wording, one is a redundant condition, and one is a test that checks a count where it could check the contents.

All of my round-6 notes are closed. N1, the end check's `unruled` branch with no test, now has two checks. I confirmed with a hand mutation of my own that those checks catch it. N2 is pinned by D9u and recorded as residual R10. N3 is the rewritten comments. N4 needed nothing.

I ran the must-pay comparison on every pair of ten must-pay terms, both directions, and checked it for consistency. Every verdict is right, and the ordering has no contradiction. The premise, that a withholding of at least the disputed amount asks no more than 7.45(6)(D)'s average-usage cap, holds for every customer (worked below).

## Hashes

All ten frozen files match the brief:

| File | md5 |
|---|---|
| patch | `a2646d04…` |
| battery | `3255b770…` |
| races | `ba77a039…` |
| mutations | `68ee1252…` |
| terms | `83d14843…` |
| migration | `55d80759…` |
| fill-manifest | `33802a5b…` |
| law file | `deb66829…` |
| seed | `3832a44f…` |
| diff | `8a597274…` |

The brief's own md5 matches its `.md5` file (`d2e98858…`).

## What I ran (executed)

I used three scratch clones of `tally`, each with TEMP revoked from PUBLIC, `tally_app` and `tally_core`:
- `rv25opus`: the battery and the probes;
- `rv25opus_race`: the races;
- `rv25opus_m`: one hand mutation.

All three were dropped at the end, and the files I copied into the container were removed. No clone was left over from round 6. Two `postgres-mcp` containers were already running before I started; they are not mine, and I started none.

- **Strict apply, twice, on each clone:** clean. The second run prints "already applied (disputes exists); nothing to do".
- **battery-25 (frozen r7):** 351 PASS, 0 FAIL, rc 0. This reproduces the author's result.
- **Races (frozen r7), on their own clone:** 30 PASS, rc 0.
- **Invariants on the patched clone:** `assert_seal_role_invariants()`, `assert_dispute_guard_invariants()`, `assert_rule_table_invariants()` and `assert_tenant_isolation_invariants()` all pass.
- **Probes, all rolled back:**
  - the must-pay grid, called on `dispute_tariff_compare_sections` with hand-built documents (7.45's protected document with `must_pay` replaced on each side);
  - the combination, `dispute_terms_combined`, on the twelve cross pairs of the average cap and the withholding caps.
- **Hand mutation MA:** the end check's `ELSIF v_alt ->> 'kind' = 'unruled'` became `ELSIF false`, so an unruled end falls into the fail-closed branch. This is a different mutation from the author's M192, which sets `v_fits := false`. I applied it strictly to a fresh clone with the patch's own invariant call removed, the way `mutations-25.py` does, then ran the battery.
  - It failed first at **D4y2**, after 171 passes, with "ends the shelter by a kind this check does not know (unruled) [D4t]".
  - In round 6 the same mutation got through every behavioural check and was caught only by the body hash at H16. The gap is closed.
- **Not run:** `mutations-25.py` and `ci.sh`, which the brief forbids.

## 1. My round-6 findings: closed?

| Round 6 | What it was | Round 7 | How I know |
|---|---|---|---|
| N1 | The end check's `unruled` branch fits a seeded row (7.45(1), the unprotected class), but no test reached it | **Closed** | D4y2 (with a last day) and D4y3 (with none) are both admitted on the real path. My mutation MA is caught at D4y2 (executed). M192 is the author's mutation. |
| N2 | The law's `final: false` would override a policy's `final: true` | **Closed as a residual** | D9u pins the direction: the result comes back not final. R10 states the shape and sends a real row of this shape back to Ryan. M193 is the mutation. See question 7 for whether R10 is the only direction. |
| N3 | Two descriptions still stated round-5 rules | **Closed** | `dispute_tariff_compare`'s comment is rewritten whole and states each order once. The sections comment names the average-cap case. Design L6, lines 66–68, states the start order (with `any_time` and the anchor rule) and the must-pay order as built. Two small wording points remain: N1 below. |
| N4 | Mutations M173–M187 aim at checks that assert the changed value | Nothing to do | — |

## The must-pay ordering, whole (executed)

I ran ten terms against each other on both sides:
- unruled;
- full bill;
- the average cap with 2 and with 3 years of history;
- withholding caps of 0.9, 1, 1.0, 1.1 and 10;
- undisputed charges.

Rows are the policy, columns are the law. "—" means no finding; "looser" means the law's term protects more.

| policy \ law | unruled | full | avg2 | avg3 | w0.9 | w1 / w1.0 | undisp. | w1.1 | w10 |
|---|---|---|---|---|---|---|---|---|---|
| unruled | — | — | looser | looser | looser | looser | looser | looser | looser |
| full | — | — | looser | looser | looser | looser | looser | looser | looser |
| avg2 | — | — | — | not comp. | not comp. | looser | looser | looser | looser |
| avg3 | — | — | not comp. | — | not comp. | looser | looser | looser | looser |
| w0.9 | — | — | not comp. | not comp. | — | looser | looser | looser | looser |
| w1, w1.0 | — | — | — | — | — | — | — | looser | looser |
| undisp. | — | — | — | — | — | — | — | looser | looser |
| w1.1 | — | — | — | — | — | — | — | — | looser |
| w10 | — | — | — | — | — | — | — | — | — |

No section other than `must_pay` raised a finding in any cell.

I ran three consistency checks over the hundred cells:
- **Transitive:** whenever A has no finding under B, and B has none under C, A has none under C. No exceptions.
- **One-sided "looser":** wherever A under B is looser, B under A has no finding.
- **Symmetric "not comparable":** wherever A under B is not comparable, B under A is not comparable too.

**The combination (executed).**
- Where the verdict is looser, the combined must-pay is the law's term. For example, an average-cap policy under a law of 1 or 1.1 comes back as the law's cap.
- Where there is no finding, it is the policy's term. For example, a 1.1 policy under the average cap comes back as 1.1.
- Where the two are not comparable, both are kept under `either`: a 0.9 policy against the average cap, either way round.

**The premise, for every customer.** Take a bill B with disputed amount D, undisputed charges U = B − D, and the customer's average A (at least 0).
- **The average cap.** 7.45(6)(D)(ii) excuses the disputed portion above the average. The customer pays max(U, min(B, A)), which is never less than U.
- **A withholding of fraction f ≥ 1.** The customer may withhold min(B, f·D), which is at least D, so they pay at most U.

So a withholding of 1 or more asks no more than the average cap, for every customer.

Below 1 it depends on the customer. A withholding of 0.9 makes the customer pay U + 0.1·D:
- when A ≤ U, the average cap asks only U, which is less;
- when A ≥ B, the average cap asks the whole bill B, which is more.

"Not comparable" is therefore right for fractions below 1. No customer is worse off under any admitted pair.

## 2. Paths around a rule (read; races and invariants executed)

r7 changes three function bodies:
- `dispute_tariff_compare_sections`: the two must-pay legs;
- `enforce_dispute_determination`: a comment inside the body only;
- nothing else in any body.

It also changes three comments (on the comparator, the sections function and the release function), the header, and two body hashes in the guard invariant. It changes no grant, policy, lock, trigger attachment or role.

The comparator is invoker-rights. It is called from the insert checks that r6 already reviewed, so no role, isolation level or statement shape reaches it differently than before. The determination trigger is still ENABLE ALWAYS, so a superuser history load meets the same end check, and D4y2 now covers its `unruled` arm.

## 3. -17's template and -23's seals

Both still hold (executed): the four invariants pass, and the carried bodies are untouched apart from the two hash updates the diff shows.

## 4. Concurrency

The lock order is unchanged (read); the races pass 30 of 30 (executed). The release function's new comment points to the header's rule, but it states the rule a little more narrowly than the header does: see N1.

## 5. Invariants

The guard invariant's two new hashes match the built bodies: the strict apply runs the invariant and passes. My mutation, with the invariant call removed, would otherwise have been caught by it.

## 6. The tests

- **N5c, N5d and N5e** file a policy under 7.45 that differs from the battery's admitted base policy only in its must-pay. A cap of 1.1 and a cap of 1 are admitted; 0.9 is refused at `must_pay`.
- **D9t** asserts all six verdicts.
- **D9t2 and D9t3** cover a later law of 1.1 on the real path: the policy's average cap is refused at [D4g], and the law's cap is admitted.
- **The NULL fixes.**
  - D8j and D9a now wrap the whole condition in `IS DISTINCT FROM true`.
  - D9j compares the whole stage list, so an empty or missing result raises an error.
  - I searched the battery for any other DO-block `IF` that a NULL would slip through. None remains: the other three use `IS DISTINCT FROM`.
- **The new mutations.**
  - M188–M191 each remove or tighten one leg. The checks they are aimed at assert the value each mutation changes.
  - Other variants I considered are also caught: the tariff side's `>= 1` loosened to `>= 0.9` would be caught by N5e; the law side's would be caught by D9t's 0.9 cells and by D9t4.
- **One weak check:** D9t4 counts the kept terms but does not say which two they are: N3 below.

## 7. Residuals

R1–R9 are unchanged and none blocks (as in round 6).

**R10 (read; executed in part).** R10 is stated rightly, and it is the only direction in which the law's final flag can cost a customer something in the record. The other direction does occur with seeded data: 7.45's regulator is final, and a policy marks it not final and then adds its own governing-body appeal, as in D9j and D9a.
- There the combined record marks the regulator final but keeps the policy's later appeal after it.
- A stage event for that appeal is still admitted (D9a, executed in the battery).
- So the customer keeps the appeal. The law's flag only binds the utility to the regulator's decision, which is the law's own term.
- What a final stage followed by another stage means is already in r6's contract line for the mirror ("a combined record can hold two final stages … the core treats the law's final decision as binding").

---

## N — notes

### N1. Two wording points in the rewritten comments (read)

- **The release function's comment** says "a close can deadlock with the reading's own move". The header's rule (r5) is wider: any transaction that writes the reading's row, a clerk's note included, and then takes one of its disputes' locks. "A close can deadlock with any write to the reading's row followed by one of its disputes' locks" would match the header.
- **`dispute_tariff_compare`'s comment** (and r6's before it) says `any_time` "is narrower than no start". That is meant as "no start is wider than it", but on a quick read it says the opposite. Suggested: "no start is wider than any_time".

Neither changes behaviour. Both can be fixed at the mirror or in a later patch.

### N2. One condition in the new must-pay leg can never be false (read)

`ELSIF v_tp ->> 'strategy' = 'withhold_cap' AND (v_tp ->> 'fraction')::numeric >= 1 AND v_lp ->> 'strategy' = 'average_usage_cap'`:
- by the time this line is reached, the earlier branches have handled every law of unruled, full bill, undisputed charges and withholding cap;
- so `average_usage_cap` is the only law strategy left, and the last condition is always true;
- a mutation that removes it would change nothing and could not be caught.

It is harmless and makes the line easier to read. It needs no change. I note it only so that nobody writes a mutation for it.

### N3. D9t4 counts the kept terms but does not check which they are (executed)

D9t4 asserts `jsonb_array_length(v #> '{must_pay,either}') = 2`. A combination that kept two copies of one term would pass. My run of the combination shows the right two, the policy's average cap and the law's 0.9 cap, in both directions. Comparing the strategy of each kept term would make the check match its label.

### N4. The ordering is now complete for the must-pay kinds the schemas have (executed)

Every pair in the grid above follows one partial order:
- unruled and full bill ask the most;
- below them, side by side and not ranked against each other, are each average cap and each withholding below 1 (two different average caps are not ranked either);
- below both sits a withholding of 1, which is the same as undisputed charges;
- a larger withholding asks less still. Nothing in it calls for a decision by Ryan; it is the standing rule applied consistently.
