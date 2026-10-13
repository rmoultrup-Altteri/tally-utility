# Review round 2: v5.4.2-15 (rewrite), Opus

**Verdict: not yet.** Two blocking items remain. Both are round-1 holes that have reopened by another route: a deposit cap above the law's limit, and a usage trigger looser than the law's. Each fix is a few lines. Every other round-1 finding I re-tested is fixed and holds.

## What I checked

**Frozen files.** Both hashes match:
- patch `patch-15r-frozen-r2.sql`: md5 `edb410da0fffe721ac499e5607cc8a61`
- battery `battery-15r-frozen-r2.sql`: md5 `4512683f6e9c9847353481883a09d1b3`

**Application and battery.** On clone `opus15`, the patch applies under strict settings (`search_path=''`, `check_function_bodies=on`). The battery passes 292/292.

**Re-run.** Applying the patch a second time prints "nothing to do". The transaction ids (xmin) of `enforce_deposit` and `deposits_cap_check` do not change, so nothing is re-installed. Round-1 S1 is fixed.

**Role check.** On a fresh clone, applying the patch under `SET ROLE tally_core` is refused by the new role check, before anything else runs. Round-1 S2 is fixed.

**Probes.** I re-ran my round-1 probes in a copy of the battery that ends in ROLLBACK (scratch `probes-r2.sql`):

| Probe | Result now |
|---|---|
| O1 (no statutory part recorded) | refused |
| O2 (months of the highest bill) | refused |
| O2b (a minimum amount) | refused |
| O3 (combined condition) | refused |
| O3c (another measure) | refused |
| O5 rate floor, via battery F17 | fixed |
| O6 (unruled cap), via N25 | fixed |
| O10 (instalments by the tariff's schedule), via I1 | fixed |

**Mutations.** I mutated 22 guards, my own set (scratch `mut2.py`), and ran the battery against each.

All `opus*` databases have been dropped.

---

## BLOCKING

### B1. A lesser-of cap can be exceeded by naming its larger part as the one that governed.

The new bound (patch:4103-4113) checks the recorded cap only against the part named in `cap_component`. Under `lesser_of`, the cap is the least of the parts. If the writer names the larger part, no check notices that a smaller part exists.

The patch's own comment says the cap "is no more than the statute's" (patch:4073-4077). That holds for `single` and `greater_of`, but not for `lesser_of`.

**Reproduction (Q1).** I added a ZZ law row for a class `opuslo`. Its cap is `lesser_of` two parts: c1, a fixed 100, and c2, one-sixth of annual billing. As T3, I posted a deposit with principal 200 and cap 200, naming c2 with annual billing 1200. **Accepted.** The law's cap is 100.

**Control (Q1b).** The same deposit naming c1 is refused ("above the statutory cap of part c1 (100)").

The Texas seed uses only `single` caps, so it is not affected today. But this is exactly the claim that round-1 B1 was about.

**Fix.** Under `lesser_of`, require `cap_amount ≤` every part that can be computed. A `fixed_amount` part can always be computed, and parts on the recorded basis figure can be computed too. Under `greater_of`, the named part is enough.

A related note: there is only one `cap_basis_amount` column. A fraction part reads it as annual billing, and a months part multiplies it as monthly billing. So a `lesser_of` with one fraction part and one months part cannot record both figures. Either record a basis figure per part, or refuse that combination in the insert check.

### B2. A usage trigger looser than the law's still passes under another trigger code.

The comparator matches the tariff's triggers to the law's triggers by `trigger_code` only (patch:3490, `CONTINUE WHEN v_lt IS NULL`). Any code the law does not name is treated as "the utility's own". On the deposit side, the check only tests the observed figure against the cited trigger's own condition.

**Reproduction (Q2, Q2b).** T2 is an investor-owned Texas utility, bound by 16 TAC 7.45. I wrote a tariff whose trigger has code `nsf` but whose condition is "usage at least 1.01 times the estimate", with no days to pay. **Accepted.** I then posted an additional deposit on it, `trigger_basis` `nsf`, source tariff, observed 1.01. **Accepted.**

The law's own usage rule is twice the estimate with 2 days to pay. So round-1 B3 is open again by relabelling the trigger. The record also says "nsf" for what is in fact a deposit demanded on usage.

**Fix.** Tie each trigger code to the condition it may carry. For example, give `deposit_triggers` a column for the measure or count event the code stands for (`usage_doubled` → `usage_to_estimate`; `nsf` → count of `nsf` events). Then the insert checks refuse a condition whose measure or event is not the code's own. This also covers round-1 S8, the missing vocabulary for count events.

The cheaper fix: in the comparator, compare a tariff trigger with every law trigger that uses the same measure or event, whatever its code.

---

## SHOULD-FIX

### S1. Under a delegation, the tariff's own figure is still not held on the deposit, and stray cap fields are accepted.

This is round-1 S5. Only its instalment half was fixed.

**Reproduction.**
- **(O7)** A city deposit of 9999 under a flat 175 tariff, with no cap recorded. **Accepted.**
- **(Q4)** A city deposit with `cap_source` tariff, cap 9999, `cap_component` 'zz9' and `cap_basis_amount` 1. Neither document has a part called zz9. **Accepted.**

The relaxed `deposits_cap_source_check` (patch:3940) and the branch for a document with no cap (patch:4114) never clear `cap_component` or `cap_basis_amount`.

**Fix.** Where the cited document does not cap the deposit, require `cap_component` and `cap_basis_amount` to be NULL. Where the law delegates and the tariff states an amount, require a cap from the tariff. Whether that cap must be ≤ the tariff's `fixed` amount can stay the core's call.

### S2. Guards the battery still does not catch (round-1 S6, mostly not acted on).

With the r2 battery, these mutants pass all 292 checks. `mutations-15r.py` does not mutate any of them.

| Mutant | Where | Battery |
|---|---|---|
| O-M1: the close floor ignores `deposit_events` | patch:2956 | not caught; H13's expected date is still set by a deposit posting |
| O-M3: the check that a cap records its basis figure is off | — | not caught |
| O-M6: `deposit_rule_citable` ignores span equality | — | not caught |
| O-M7: a count may be fractional | — | not caught |
| O-M9: the tariff's instalment fractions need not add up to 1 | — | not caught |
| O-M12: the `instalment_received` bound is off | — | not caught |
| O-M23 (new): `cap_source='statute'` under a document with no cap is no longer refused | patch:4114 | not caught |

O-M5, O-M10, O-M11, O-M13 and O-M14 are not caught by the battery either. They are covered by `evidence-txn`, the races script and `migration-15r.py` P1f, but the runner does not mutate them to prove that. Each needs a case that only its guard refuses.

The new guards are all caught: M111–M138, and my own versions of them, O-M2, O-M4, O-M16 to O-M22.

### S3. A rate for every category serves a category whose class has no law row.

**Reproduction (Q5).** In ZZ, utility T9 has a category `nl` mapped to `opusnolaw`, a class with no law row.
- **Q5a.** A rate for `nl` itself is refused, which is correct.
- **Q5b.** A 6% rate for every category is **accepted**.
- **Q5c.** `deposit_interest_rate_row_as_of(..., 'nl', ...)` returns that 6% rate.

So the "unknown law" refusal on a category's rate is avoided by writing the rate for every category instead.

**Fix.** For a NULL category, refuse when any class of the utility's own categories has no law row binding it on the date. Alternatively, leave it to the core and say so in R7/F19.

---

## NOTES

- **N1.** The basis figure (`cap_basis_amount`) is the writer's own number. Claiming annual billing of 30000 permits a cap of 5000 under the one-sixth part (O1r was accepted). That is acceptable, since the figure is the core's and it is recorded. It should be stated in R1 or R7, because the new bound is only as good as that figure.
- **N2.** The re-run guard (patch:64) leaves a psql variable `:already` set for the rest of the session. Once this patch is mirrored into `tu.sql`, any later block that tests `:already` would inherit it. Use a patch-specific name, such as `v5_4_2_15_already`. The guard also makes the patch psql-only, which deserves one line in the header.
- **N3.** Under a law cap the law has not ruled on (`unruled`), the comparator refuses only `fixed` and `months_of_billing` amounts. A `case_by_case` amount passes. That is consistent with "the core decides each case", but R7 should name it.
- **N4.** The decisions the brief made without Ryan:
  - **1. A deposit's own closed law row stays citable after its close ("grandfathered").** I agree. It matches B1 of 2026-10-02, and R4 now says so.
  - **2. A partial return (`principal_returned`) needs no due row.** Acceptable: a voluntary refund needs none either, and when a due row is cited the exact amount is enforced.
  - **3. Leaving the count-event vocabulary undone.** I would undo this. The B2 fix gives most of it for free.
- **N5.** I re-checked round-1 N2, N3, N5 and N6: the identity freeze, the comment on the waiver-determinations column, the tariff waiver's reach, and the description of the tariff minimum amount. They are unchanged. All are minor.
