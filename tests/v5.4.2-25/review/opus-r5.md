# Opus review: v5.4.2-25 r5 (disputes, round-4 findings fixed)

**Date:** 2026-11-26. **Reviewer:** Opus. **Round:** 5.
**Verdict: not yet.** Nothing is blocking. Two should-fix items:

- **S1.** The comparator treats "the undisputed charges" as asking no more than any other must-pay. That is false against a withholding cap above 1. Under the Government Code shape (the payer may withhold 1.1 times the disputed amount), a policy of "undisputed charges" asks more than the law, and it is admitted. A withholding of exactly 1, which asks the same, is refused (N7d). The reverse pair is labelled "looser" although the policy protects more for every customer. So a combined record would hand the customer the law's smaller protection, and the insert check refuses a more generous policy. Executed. No seeded law row has this shape today (residual R1).
- **S2.** Three hand mutations of the new merge survive every behavioural check in the battery; only the body-hash invariant catches them. The worst one drops the law's decision deadline from a stage where the policy's own stage has none, which makes the combined record looser than the law. The code is right today (executed); the tests do not hold it there.

All my round-4 findings are closed. The merge is right in every case I tried. So are the verdicts outside S1, and the checks against either of two terms.

## Hashes

All ten frozen files match the brief: patch `138f6770…`, battery `20b101e9…`, races `a5ad8111…`, mutations `5e471357…`, terms `83d14843…`, migration `55d80759…`, fill-manifest `33802a5b…`, law file `deb66829…`, seed `3832a44f…`, diff `f2710398…`. The brief's own md5 matches its `.md5` (`3bef277f…`).

## What I ran

I used two scratch clones of `tally`: `rv25opus` for the battery and probes, and `rv25opus_race` for the races. A third clone, `rv25opus_m`, held my hand mutations, one at a time. TEMP was revoked from PUBLIC, `tally_app` and `tally_core` on each clone. All clones were dropped at the end.

- **Strict apply, twice, on each clone:** clean. The second run prints "already applied; nothing to do". Reproduced.
- **battery-25 (frozen r5):** 318 PASS, 0 FAIL, rc 0. Reproduced.
- **Races (frozen r5), on the race clone, two runs on fresh clones:** 30 PASS, rc 0, both runs. DR16 and DR17 lost session A in both runs. No flake.
- **Invariants on the patched clone:** `assert_seal_role_invariants()`, `assert_dispute_guard_invariants()` and `assert_rule_table_invariants()` all pass.
- **Probes:**
  - the comparator and the merge called directly on hand-built documents (rolled back);
  - two battery prefixes (through N9j, and through N7f) plus my statements on the real path, rolled back;
  - three hand mutations of the frozen patch. Each was applied strictly to a fresh clone, with the patch's own invariant call removed as `mutations-25.py` does, and the battery was then run.
- **Not run:** `mutations-25.py` and `ci.sh`, which the brief forbids.

## My round-4 findings: closed?

| Round 4 | What it was | Round 5 | How I know |
|---|---|---|---|
| S1 | The combination replaced a list section whole, so a tightened law removed the policy's later appeal stage and its subjects | **Closed** | D9a is my round-4 probe: the governing-body appeal is kept, its stage event is admitted on the real path, and the employee's 10 days stand. D9c to D9c3 cover the subjects union for each pair of kinds. M160 to M163 and M166 cover whole-section replacement. |
| N1 | A third deadlock shape (a note edit, then an amount, against a close) | **Closed** | The header states it as a rule, and DR17 runs it. N2 below suggests one wording change. |
| N2 | Admitting a stage after the law's final one | Unchanged, as agreed; carried into the application contracts | the plan |
| N3 | The combination relied on message prefixes | **Closed** | `dispute_tariff_compare_sections` returns the section and the verdict as columns. |
| N5 | The combined record changes if the subject list grows | **Closed** | The combination's comment says so. |
| N6 | No test where the law's single-valued term wins | **Closed** | D9d and D9d2 (the must-pay), and D9e and D9e2 (the end). M147 is now caught at D9d. |

---

## S — should fix

### S1. "Undisputed charges" is not the least a customer can be asked to pay when the law lets the payer withhold more than the disputed amount (executed)

**What happens.** The comparator's must-pay branch starts from "undisputed_charges asks no more than any strategy" (`dispute_tariff_compare_sections`):
- the first branch skips the comparison whenever the policy's strategy is `undisputed_charges`;
- r5's new verdict calls any pair "looser" when the law's strategy is `undisputed_charges`.

The premise holds against the full bill and against the average-usage cap. It fails against `withhold_cap` with a fraction above 1, which the schema allows (up to 10) and which the design gives for Government Code §2251 (1.1).

Take a $500 bill with $100 in dispute:
- under "undisputed charges", the customer pays $400;
- under "withhold up to 1.1 of the disputed amount", the customer withholds $110 and pays $390.

So "undisputed charges" asks more than a withholding of 1.1, and exactly as much as a withholding of 1.

**Evidence (executed).**
1. **On the real path.** I took the battery prefix through N7f, where T4 is the special district under the battery's §2251 law row (withhold 1.1). I then wrote T4 a policy that is the same except `must_pay: undisputed_charges`. **It is admitted.** N7d refuses `withhold_cap` 1.0 under the same law, and 1.0 asks the same $400. So the database admits a policy that asks the payer for more than the law allows, against "never looser than the law".
2. **The verdicts, called directly.**
   - Law `undisputed_charges`, policy `withhold_cap` 1.5: one finding, `must_pay | looser`. But the policy protects more for every customer with anything in dispute.
     - At a policy's insert, a more generous policy is refused.
     - In a combined record, the law's term replaces the policy's. The customer then pays $400 where the utility's own policy promises $350.
   - Law `withhold_cap` 1.1, policy `undisputed_charges`: no finding.

**Why it is not blocking.** No seeded law row has a withholding cap. The §2251 document is a test fixture until there is a governmental class (residual R1). It becomes live the day that class is added.

**Fix (by the standing rule: never looser than the law).** In the must-pay branch, compare `undisputed_charges` with `withhold_cap` as a withholding of exactly 1:
- a law of withhold *f* against a policy of undisputed charges: the policy is **looser** when *f* > 1, and there is no finding otherwise;
- a law of undisputed charges against a policy of withhold *f*: **looser** when *f* < 1, and there is no finding otherwise.

Both directions rank for every customer, so neither is "not comparable". Tests:
- N7g: undisputed charges under the law of 1.1 is refused;
- N7h: a policy of withhold 1.5 under a law of undisputed charges is admitted;
- one D9 case where the combination keeps the policy's withhold 1.5;
- a mutation for each direction.

The comparator's comment and `dispute_tariff_compare`'s comment ("undisputed_charges asks no more than any strategy") change with it.

### S2. Three branches of the new merge and comparator can be broken without any behavioural check failing (executed)

I made three one-line mutations of the frozen patch. Each was applied strictly to a fresh clone of `tally`, with the patch's own invariant call removed the way `mutations-25.py` removes it, and the battery was run. In each run the **only** failure was H16, the body-hash invariant. No check about behaviour failed.

| Mutation | What breaks | Behaviour today (direct call, executed) |
|---|---|---|
| **MA.** In the merged stage, `WHEN v_tw ->> 'kind' = 'none' THEN v_lw` becomes `THEN v_tw` | When the policy's stage has no decision deadline and the law's has one, the combined stage keeps "no deadline". **The combined record is then looser than the law.** | The law's 5 days are kept. |
| **MB.** The shelter-start verdict for two day-windows from different anchors becomes always `looser` | "30 days from the bill's issue" against the law's "21 days from receipt" is called looser. So the policy's window is dropped, though for a customer who receives the bill late it is the wider one. | Both are kept as `either`. |
| **ME.** The filing window of one anchor keeps the narrower (`>=` becomes `<=`) | The policy's wider window (30 days from issue against the law's 20) is lost. | The policy's 30 days are kept. |

D9b tests only the "no window" leg and D9b2 only two anchors. No D9 case has the policy's stage without a decision deadline, and no verdict test has two day-windows from different anchors (N7b refuses at insert either way).

**Fix.** Add the three D9 cases and the three mutations: MA against D9b's shape with the policy's regulator undated; ME with one anchor and two day counts; MB through `dispute_tariff_compare_sections`. PATCH-LESSONS `checks-narrower-than-their-claim` asks for exactly this: prove that the check catches drift. MA matters most, because its drift is the one direction the merge must never take.

---

## N — notes

### N1. "Any time" is not ranked against a window of days (executed)

`c_rank` holds `any_time`, `before_termination` and `before_delinquency`. `within_days` compares only with its own kind. So:
- a policy of `any_time` under a law of `within_days` gives the verdict `not_comparable`. At insert it is refused, though "a dispute at any time" admits everything a window does.
- a law of `any_time` against a policy's `within_days` is also `not_comparable` instead of `looser`. The combination keeps both. The core then picks "any time", which gives the same result as "looser" would, so nothing is lost.

The first refuses a more protective policy. That is a nuisance, not a harm: the utility can copy the law's window. Ranking `any_time` above `within_days` fixes both. `within_days` against `before_*` rightly stays not comparable. No seeded row is affected.

### N2. The lock-order rule names one instance of a general shape (predicted from the code)

The rule's second clause, "two transactions closing disputes of two readings in opposite order", is one case of a general shape: any two transactions that take two disputes' locks in opposite order. `dispute_lock` is `pg_advisory_xact_lock`. So a clerk who records an amount on dispute X and then on Y, against another who does Y then X, deadlocks on the advisory locks alone. No close or reading is involved. Item 1 fixes the order only for the reading's move (id order).

"Writers retry 40P01" covers it, so nothing is unsafe. But PATCH-LESSONS `lock-order-as-a-rule` asks for the rule, not instances. Suggested wording: "a transaction that takes more than one dispute's lock takes them in the order it writes (the reading's move: in id order); two transactions taking two disputes' locks in opposite order can deadlock, as can one that writes a reading's row before a lock of one of its disputes against a close. The loser retries."

### N3. The combined stages can hold two final stages, and two stages of one decider (executed)

These are by design (the plan's "each stage keeps its own final flag"). They belong in the application contract, stated so that the core does not read the combined list like a schema-valid one:
- A policy of [employee; governing body, final] under 7.45 combines to [s1; `law:s2` regulator, final; `s2` governing body, final]. There are two final stages.
- A policy of [employee; manager, filed within 3 days; regulator in 10 days] under 7.45 combines to [s1; `law:s2` regulator in 15 days; `s2` manager; `s3` regulator in 10 days]. The policy's quicker regulator decision survives as its own later stage, not at the law's place. The event guard admits a regulator stage event under either id.

Proposed contract lines:
- the law's final stage binds whatever stage follows (already listed);
- where the combined stages hold two stages of one decider, the core applies the earlier deadline of the two to that decider's one decision.

### N4. The checks against either term do what the ruling says (executed and read)

- **[D4g]** admits a component that is one of the alternatives' ids and nothing else (D9f3, D9f4, D9f5). A law id that the policy also uses is written `law:` and the id, so the two stay distinct.
  - A stage id cannot collide with `law:…`: component ids match `^[a-z][a-z0-9_]*$`, and -17 refuses a repeated id within a document (executed: two stages `s1` are refused, 23514).
- **[D4t]** admits a last day, or none, that fits one alternative.
  - "Fits neither" raises [D4t]. With one alternative, the old [D4p] or [D4s] is raised.
  - An `either` never holds `unruled`: a policy left unruled is "looser", and a law left unruled gives no finding. So the two alternatives are always real ends.
- **One small fail-open:** the end loop's `ELSE v_fits := true` admits any last day for an end of a kind it does not name. It exists for `unruled`. Naming `unruled` and failing closed on anything else costs nothing. (Read only; no path reaches it today.)
- **Nothing else reads an `either`.** The event guard reads only a stage's id and decider. The shelter readers read the determination's own columns. The facets are computed from the stored rows, never from the combination.
- **A policy's insert** is compared with every law row over the policy's dates (-17's `rule_tariff_insert_check`). So a backdated policy is compared with a law that is already written and later in force. `either` can arise only from a law row written after the policy, which is the ruling's case.

### N5. Paths around the new rules, the template and the seals (read; the battery and invariants executed)

- [D4g] and [D4t] sit in `b_enforce_dispute_determination`, which is ENABLE ALWAYS. They therefore run for `tally_app`, the owner and a superuser history load alike.
- The combination runs with invoker rights. A policy hidden by row security makes the document NULL, and [D4g] then refuses (fail closed).
- At REPEATABLE READ, `dispute_lock` still refuses (25000).
- `dispute_tariff_compare_sections` is invoker-rights and read-only. Its grant to `tally_core` is pinned by the guard invariant.
- **-17's template:** both documents the combination reads are cited (and locked shared) before it is computed. The close floor is unchanged.
- **-23's seals:** the invariant passes, and r5 does not touch the carried bodies.

### N6. Residuals R1–R9 (read)

None is blocking.
- **R1** (no governmental class) is what keeps S1 from being live today.
- **R9** (two classes giving different stage lists) fails toward the law, and no seeded row is affected.
