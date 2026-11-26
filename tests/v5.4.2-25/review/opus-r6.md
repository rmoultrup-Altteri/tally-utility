# Opus review: v5.4.2-25 r6 (disputes, round-5 findings fixed)

**Date:** 2026-11-26. **Reviewer:** Opus. **Round:** 6.
**Verdict: ready.** Nothing is blocking and nothing needs fixing before the mirror. There are four notes. The one worth acting on is N1: the new `unruled` branch of the end check fits a real seeded row, but no test reaches it.

Both of my round-5 should-fix items are closed, with tests on both sides. So are my notes N1, N2 and N4. N3 is in the plan's list of contract lines for the mirror. I ran the always-run stages merge, the withholding ranking and the start ranking across every pair of kinds. Each verdict is right in both directions.

## Hashes

All ten frozen files match the brief: patch `2e98f5d5…`, battery `a5204e30…`, races `ba77a039…`, mutations `77d92d30…`, terms `83d14843…`, migration `55d80759…`, fill-manifest `33802a5b…`, law file `deb66829…`, seed `3832a44f…`, diff `7d40f73f…`. The brief's own md5 matches its `.md5` (`e2d650ec…`).

## What I ran

I used three scratch clones of `tally`:
- `rv25opus` for the battery and the probes;
- `rv25opus_race` for the races;
- `rv25opus_m` for two hand mutations, one at a time.

TEMP was revoked from PUBLIC, `tally_app` and `tally_core` on each clone, and all of them were dropped at the end. I did not start any container. Two `postgres-mcp` containers were already running; they are not mine.

- **Strict apply, twice, on each clone:** clean. The second run prints "already applied (disputes exists); nothing to do". Reproduced.
- **battery-25 (frozen r6):** 342 PASS, 0 FAIL, rc 0. Reproduced.
- **Races (frozen r6):** two runs, each on a fresh clone. 30 PASS and rc 0 both times, DR2 included. Reproduced.
- **Invariants on the patched clone:** `assert_seal_role_invariants()`, `assert_dispute_guard_invariants()` and `assert_rule_table_invariants()` all pass.
- **Probes (all rolled back):**
  - the comparator and the combination called directly on hand-built documents, against the seeded 7.45 protected row;
  - a battery prefix (through D4y) plus my own statement, on the real path;
  - two hand mutations of the frozen patch. Each was applied strictly to a fresh clone, with the patch's own invariant call removed the way `mutations-25.py` removes it, and then the battery was run.
- **Not run:** `mutations-25.py` and `ci.sh`, which the brief forbids.

## My round-5 findings: closed?

| Round 5 | What it was | Round 6 | How I know |
|---|---|---|---|
| S1 | "Undisputed charges" was ranked above every withholding cap. So a policy asking more than a 1.1 law was admitted, and a more generous 1.5 policy was called looser. | **Closed** | The must-pay grid below (executed). Filing is tested both ways: D9k2 refuses, D9k3 admits, D9k4 refuses. A later law is tested both ways: D9k5/D9k6 and D9k7. M174, M175 and M176 are the mutations. |
| S2 | Three parts of the merge and the comparator could break with only the body hash noticing | **Closed** | My three mutations are now M182 (the decision deadline), M183 (two anchors called looser) and M184 (the narrower window kept). Each is aimed at D9p, D9p2 and D9p3, and I read that each check asserts the value the mutation changes. |
| N1 | "Any time" was not ranked against a window of days | **Closed** | The start grid below (executed), D9q and D9q2, M185 and M186. |
| N2 | The lock-order rule named one instance of the general shape | **Closed** | The header now says that a transaction writing to two disputes takes their locks in its own order, that two such transactions can deadlock, and that the loser retries. |
| N3 | Contract lines for a combined record with two final stages, or two stages of one decider | **Carried to the mirror** | It is in the plan's "Application contracts at the mirror". |
| N4 | The end loop admitted an end of any kind it did not name | **Closed**, with a test gap | Unknown kinds now fail closed [D4t]. But the `unruled` branch it split out has no test: see N1 below. |

## The questions the brief asks

**The always-run merge (executed).** I gave a policy 7.45's two stages plus its own governing-body appeal, with the employee deciding within 5 days.
- Under 7.45 the comparator finds nothing. The combined stages equal the policy's stages exactly.
- With the policy's regulator not final, the only difference is that flag, which comes back true.
- Across the whole document, only `blocks` and `duties` differ. They are re-sorted as the union, which is r4's behaviour.
- With no stages on either side, the combined document gains `"stages": []`. Nothing reads that as anything but empty.

So with no stage finding, the merge changes nothing except the final flag at the law's places.

**The law's `final: false` over a policy's `final: true`.** The schema allows a final stage only as the last one [L2d]. That limits where this can happen:
- If the policy's final stage sits at a law place that is not the law's last, the policy lacks the law's later stages. The merge appends them. The customer gains the law's further appeal, which is more protective.
- The remaining case is a law whose own last stage is not final. See N2: no seeded row has this shape.

**The withholding comparison (executed).** I called the comparator on every pair of seven must-pay kinds: undisputed charges, withholding caps of 0.9, 1 and 1.1, the average cap, the full bill, and unruled. "—" means no finding. Rows are the policy, columns the law.

| policy \ law | undisp. | w0.9 | w1 | w1.1 | avg | full | unruled |
|---|---|---|---|---|---|---|---|
| undisputed | — | — | — | looser | — | — | — |
| w0.9 | looser | — | looser | looser | not comp. | — | — |
| w1 | — | — | — | looser | not comp. | — | — |
| w1.1 | — | — | — | — | not comp. | — | — |
| avg | looser | not comp. | not comp. | not comp. | — | — | — |
| full | looser | looser | looser | looser | looser | — | — |
| unruled | looser | looser | looser | looser | looser | — | — |

Every cell is right:
- Undisputed charges counts exactly as a withholding of 1, both ways.
- The average cap asks at least the undisputed charges, so it is looser than a law of undisputed charges.
- An average cap and a withholding cap depend on the customer's usage, so they cannot be ranked.
- Nothing exceeds a law of full bill or unruled.

The combination takes the law's term on "looser" and keeps both on "not comparable". D9k5 to D9k7 check this on the real path.

**The start ranking (executed).** I ran the same grid for seven start kinds: any time, before termination, before delinquency, 21 days from receipt, 30 days from issue, on a regulator complaint, and unruled.
- A policy of `any_time` gives no finding under any law.
- Every other policy kind is looser under a law of `any_time`.
- `on_regulator_complaint` cannot be ranked against the termination, delinquency and day-window kinds, in either direction.

`any_time` is no narrower than a regulator complaint either. A regulator referral is itself a dispute (channel `regulator_referral`), and `any_time` shelters every dispute.

**The fail-closed end check (read, and executed for `unruled`).** Both schemas list four end kinds: resolution, through the regulator's close, the earlier of resolution and days, and unruled (the tariff schema has no unruled). The loop names all four.
- A delegated law document has no `shelter_ends`. It is cited alone only with no tariff and no platform default, and then the answer is "no terms" [D4d], which never reaches the end check. Even if one reached it, [D4g] would already refuse it, because there is no must-pay id.
- So no valid document reaches the new refusal.
- `unruled` is reached, on the seeded row (N1).

**`lacks` (read).** The only reader of the verdicts is `dispute_terms_combined`, and it tests only `= 'not_comparable'`, and only for the three single terms. The list sections merge whatever the verdict. `dispute_tariff_compare` returns only the messages. Nothing in `terms-25.py`, `migration-25.py`, -26 or anywhere else in the repo reads a verdict. The battery reads `lacks` in D9s.

**Paths around the rules, template, seals, concurrency (read; the invariants and races executed).** r6 changes only the bodies of three invoker-rights functions and the BEFORE INSERT trigger function. It changes no grant, policy, lock or trigger attachment.
- The trigger is still ENABLE ALWAYS, so the end check runs for `tally_app`, for the owner, and in a superuser history load.
- -17's template and -23's seals still hold: the invariants pass, and the carried bodies are untouched.
- The lock order is unchanged. Only its comment widened.

**Residuals R1–R9 (read).** None is blocking. R1 (there is still no governmental class) is now only about coverage. The general withholding ranking that R1 exposed is fixed.

---

## N — notes

### N1. The end check's `unruled` branch fits a seeded row and no test reaches it (executed)

r6 splits the old catch-all ELSE in two:
- `ELSIF kind = 'unruled' THEN v_fits := true`;
- an ELSE that fails closed.

The `unruled` branch is live. The seeded Texas IOU/co-op row for the unprotected class governs, with `shelter_ends: unruled`. An IOU with no policy of its own cites that row alone.

**Executed:**
- **On the real path.** I ran the battery prefix through D4y, then wrote a "sheltered" record superseding D4y's, under that row, with a last day. Frozen r6 admits it.
- **Hand mutation MA.** `ELSIF v_alt ->> 'kind' = 'unruled'` became `ELSIF false`, so `unruled` falls into the fail-closed branch. The battery passed 330 checks and then failed first at H16, the body-hash invariant. **No behavioural check failed.** The transaction aborted there, so the 11 checks after H16 did not run; they are H16a to H16g, the invariant's own drift checks, and none of them writes a determination. My statement above is then refused: "ends the shelter by a kind this check does not know (unruled) [D4t]".

This drift fails toward refusal, not toward a looser record, so it is a note rather than a should-fix. But it is the same kind of gap plan item 3 set out to close: a change to this branch would silently refuse every sheltered record for those customers. **Suggested:** one battery check, the statement above (admitted), plus a mutation aimed at it.

(Hand mutation MB, removing the new `ELSIF v_tp ->> 'strategy' = 'undisputed_charges' THEN NULL`, is caught at once at N1b. It is covered.)

### N2. A law whose last stage is not final would override a policy's final flag (predicted)

The merge always writes the law's `final` at the law's places. Suppose a law's last stage is `final: false`, and a policy has the same stage, of the same decider, at that place as `final: true` (the utility promising to treat that decision as binding). The combined record then has no final stage.

Whether that is looser depends on the customer:
- a customer who won at that stage loses the policy's promise;
- a customer who lost keeps any further appeal.

By Ryan's ruling, a pair that cannot be ranked would keep both. No seeded row has this shape, because 7.45's last stage is final and every other row has no stages. **Suggested:** one contract line at the mirror: "where a policy marks final a stage the law does not, the core holds the utility to the policy's promise." Or leave it as a residual.

### N3. Two descriptions still state the round-5 rules (read)

- `dispute_tariff_compare`'s COMMENT still opens with "undisputed_charges asks no more than any strategy" and "within_days against its own kind only … any other pair not comparable". The r6 sentence appended at its end contradicts both. Rewriting the two clauses in place would leave one rule stated once.
- The design (`application/wave3-build-2026-10-18/v5.4.2-25-design.md`, line 68) still says "`undisputed_charges` asks no more than any other strategy". The r6 plan says "the design's ordering paragraph changes with it". The design is not frozen, so this can be fixed at the mirror.

### N4. The mutations I checked aim at checks that assert the changed value (read)

- M173 to M187 each change the line they name.
- M180 and M183 replace the same original line with opposite constants (always "not comparable", always "looser"). Each is caught by its own check: D9o2 and D9p2.
- M187 changes only the blocks verdict. D9s asserts all four list verdicts, and only the combination reads them (above), so one mutation is enough.
- M158's retarget to D9g is explained correctly: the branch now refuses rather than admits.
