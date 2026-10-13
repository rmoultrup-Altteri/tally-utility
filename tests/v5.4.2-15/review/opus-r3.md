# Review round 3: v5.4.2-15 (rewrite), Opus

**Verdict: not yet.** One blocking item remains. It is the round-2 trigger hole (B2), now much narrower: a tariff trigger under a code the law does not use can still escape the comparison if its condition is combined, or if it counts the law's event in another unit. The fix is a few lines in the comparator's match test.

Every other round-2 fix holds. My round-2 lesser-of probe (Q1) is now refused, and so are the relabelled ratio trigger (Q2) and the stray cap part (Q4).

## What I checked

**Frozen files.** Both hashes match:
- patch `patch-15r-frozen-r3.sql`: md5 `0a13969608d7360dff2ae468a90b86d4`
- battery `battery-15r-frozen-r3.sql`: md5 `0f6ae2ce52c38492ec3fc31ce09b0593`

**Application and battery.** On clone `opus15`, the patch applies under strict settings (`search_path=''`, `check_function_bodies=on`). The battery passes 315/315.

**Diff review.** I read the r2→r3 diff in full: the comparator, the rate floor, `deposit_cap_part_figure`, the cap checks in `enforce_deposit`, the instalment check, and the wording.

**Probes.** I ran probes (scratch `probes-r3-body.sql`) after the battery's fixtures, in one transaction that ends in ROLLBACK.

**Mutations.** The guards I named in round 2 are all in `mutations-15r.py` now:

| Guard | Mutation |
|---|---|
| The close floor's accrual branch | M151 |
| The successor's span equality | M150 |
| Fractional counts | M149 |
| The tariff instalment sum | M152 |
| The `instalment_received` bound | M153 |
| A statutory cap source under a document with no cap | M146 |
| Lesser-of | M140 |

All `opus*` databases have been dropped.

---

## BLOCKING

### B1. A looser usage trigger still escapes the comparison under another code, if its condition is combined.

The new match test (patch:3506-3509) is:

```
v_samemeasure := (ratio AND ratio AND same measure) OR (count AND count AND same event AND same unit)
CONTINUE WHEN NOT v_samecode AND NOT v_samemeasure;
```

It looks only at the top level of the tariff's condition. A combined condition (`any_of` / `all_of`) is never "the same measure". So under a code the law does not name, it is skipped as "the utility's own".

On the deposit side, a combined condition counts as met whatever the observed figure (`ELSE true`, patch:4225).

**Reproduction (Z1, Z1b).** T2 is an investor-owned Texas utility, bound by 16 TAC 7.45. I wrote a tariff whose trigger has code `nsf` and condition `any_of [usage_to_estimate ≥ 1.01, 99 nsf in 1 month]`, with no days to pay. **Accepted.** I then posted an additional deposit on that trigger, observed 1.01. **Accepted.**

The law's rule is twice the estimate, with 2 days to pay. The plain ratio form of the same thing (Q2) is now refused, so a one-line `any_of` wrapper is all it takes to get around the round-2 fix.

**Reproduction (Z2), the count form.** This is ZZ only, since Texas has no count trigger. The law's `zz_late_history` counts 2 late payments in 12 months. A tariff trigger with code `zz_nsf_history` counting **1 late payment in 1 bill** is **accepted**.

The same condition under the law's own code is refused as not comparable (control Z2d). The window unit is part of `v_samemeasure`, so changing the unit plus changing the code hides the trigger.

R7 now says "a trigger is matched by code and by what it measures … so another code does not hide it". For these two shapes that claim is false.

**Fix.**
- Match on the *leaves* of the condition. A tariff trigger is matched to a law trigger when any leaf of its condition is a ratio of the same measure, or a count of the same event. Leave the window unit out of the match and keep it in the comparison; differing units then fall to "cannot be compared" and are refused, as under the law's own code.
- Once matched, a combined condition that is not the law's own is already refused by the existing `ELSIF v_tc IS DISTINCT FROM v_lc` branch.
- Add N-cases for `any_of` under another code and for another unit under another code. Add a mutation that removes the leaf walk.

---

## SHOULD-FIX

### S1. Under a delegation, a deposit may still record no cap at all.

**Reproduction (O7).** A city deposit of 9999 under a flat-175 tariff, with `cap_source` NULL and no cap. **Accepted.**

The new tariff bound (patch:4177-4194) acts only when `cap_source = 'tariff'`. A writer escapes it by leaving the cap empty. This is the first half of my round-2 S1. Round-1 B1 was the same "record nothing, nothing is held" pattern on the statutory side, and the fix there was to require the cap.

**Fix.** Where the cited law row delegates and the cited tariff states a `fixed` or `months_of_billing` amount, require `cap_source = 'tariff'` (with its cap). `none` and `case_by_case` stay optional.

### S2. A lesser-of cap with a fraction part and a months part is still not held by its smaller part.

`deposit_cap_part_figure` is computed from the one recorded basis figure, and only for parts of the named part's kind (patch:4155-4160).

**Reproduction (Z3).** The cap is `lesser_of [1/6 of annual billing, 1 month of billing]`. A deposit naming the fraction part, with annual billing 1200 and cap 200, is **accepted**. The one-month part, typically about 100, is never checked.

The patch comments say this is by design ("from the one basis recorded"). But it is the round-2 note again: one basis column cannot carry both an annual and a monthly figure.

**Fix.** Either refuse a `lesser_of` that mixes parts on different bases in `deposit_rule_insert_check`, or record a basis figure per part. Otherwise say in R7 that such a cap is held only by the part named.

Texas is unaffected.

---

## NOTES

- **N1.** The law's other guards must be carried *identically* (patch:3554-3558). That also refuses a stricter tariff.

  **Reproduction (Z4).** The law requires 10 days' notice; a tariff giving 30 days is refused, "does not carry the law's guard".

  This fails closed, which is acceptable. But the day-count guards (`notice_days`, `assess_within_days`, `not_if_moved_within_days`, `not_after_service_months`) each have a direction and could be compared as numbers, the way days to pay is. A utility that gives more notice than the law requires should not be told it is looser.
- **N2.** The coverage check (N18/N30/N31) is real: the comparator now builds the class's own date coverage. It counts rows of any basis. A class covered only by an `additional_trigger` row passes coverage, while the amount is compared only against the `credit_evaluation`/`tariff` caps. That is harmless for Texas, where every class has all four bases.
- **N3.** On the brief's three decisions made without Ryan:
  - **Decision 1, the closed row stays citable.** I have no evidence that the old tests misread Ryan's ruling. The `deposit_rule_citable` comment and R4 now state it plainly; I'd keep it and ask him in one line when convenient.
  - **Decision 2, a partial return needs no due row.** Fine.
  - **Decision 3, the count-event vocabulary.** With B1 fixed by matching on leaves, the code really does carry no meaning the comparison depends on. I withdraw my round-1 S8 as a blocker for this patch.
- **N4.** Basis figures remain self-reported, the writer's own number (round-2 N1, which R7 now states).

## Verified fixed (round 2 → round 3)

| Round-2 finding | How I verified it | Result |
|---|---|---|
| B1, lesser-of cap lifted by naming the larger part | Q1 retest | refused, with the c1 figure of 100 |
| B2, the plain relabelled ratio trigger | Q2 retest | refused: a lower ratio, and no days to pay |
| S1, stray cap part under a delegation | Q4 retest | refused |
| S1, tariff cap above the tariff's amount | read patch:4177-4194; mutations M142–M144 | held |
| S2, test gaps | mutations M146 and M149–M153 | now present |
| S3, a rate for every category reaching a class with no law | F20; mutation M154 | refused |
| Instalment completeness after an early flush | read the deferred trigger now on `deposit_instalments` | sound |
