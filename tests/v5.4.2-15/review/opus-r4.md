# Review round 4: v5.4.2-15 (rewrite), Opus

**Verdict: READY.** Nothing blocking is left. Every round-3 finding of mine is fixed and holds under probing. I have one should-fix, which can go in this patch or follow it, and two notes.

## What I checked

- **Hashes.** Both match.
  - patch `patch-15r-frozen-r4.sql`: md5 `9dfd0030636bf43ee4da4e9e74acaf84`
  - battery `battery-15r-frozen-r4.sql`: md5 `ec821be4ed17e5e5669f55404d6314f7`
- **Application and battery.** On clone `opus15`, the patch applies under strict settings (`search_path=''`, `check_function_bodies=on`). The battery passes 333/333.
- **The diff.** I read the whole r3→r4 diff (137 lines): the insert-check rule against mixed bases, `deposit_condition_leaves`, coverage per profile segment, the related-trigger rule, `deposits_cap_source_check`, and the tariff figure that holds the cap.
- **Probes.** These run after the battery's fixtures, in one transaction that ends in ROLLBACK. The scratch files are `probes-r4.sql` and `probes-r4b.sql`. Every round-2 and round-3 reproduction was re-run.
- All `opus*` databases have been dropped.

## Round-3 findings: verified fixed

| Round-3 item | Re-run | Result now |
|---|---|---|
| B1: a combined trigger under another code (Z1) | tariff `nsf` = `any_of[usage ≥ 1.01, 99 nsf/month]` | **Refused**: not comparable with the law's `usage_doubled`, and no days to pay |
| B1: the count form under another code and unit (Z2) | `zz_nsf_history` counting late payments per bill | **Refused**: not comparable with `zz_late_history` |
| S1: a city deposit with no cap (O7) | a 9999 deposit under a flat-175 tariff, cap NULL | **Refused**: "the cited tariff states an amount … the cap that applied is recorded" |
| S2: lesser-of mixing bases (Z3) | `lesser_of[1/6 annual, 1 month]` | **Refused** at the law row (patch:3023) |
| r2: lesser-of naming the larger part (Q1) | `lesser_of[100, 1/6 of 1200]`, cap 200 naming the fraction part | **Refused**: above 100 |
| r2: the relabelled ratio (Q2) | `nsf` = usage ≥ 1.01 | **Refused** |
| r2: a stray cap part under a delegation (Q4) | cap part `zz9` | **Refused** |

New behaviour I also confirmed:
- **Z5.** A condition identical to the law's under another code is related, and its days to pay are still compared. A trigger with no days to pay is refused.
- **Z7b.** A tariff tighter than the statute holds the cap. A deposit citing a flat-150 tariff with a statutory cap of 200 is refused, "above the cited tariff's own amount (150)". That is Fable S1.

## SHOULD-FIX (not blocking)

### S1. An investor-owned deposit can avoid its own tariff by not citing it.

The tariff's figure holds the cap only when `NEW.tariff_id IS NOT NULL` (patch:4225). Outside a delegation, `tariff_id` is optional.

**Reproduction.**
- **Z7.** T2 is investor-owned. Its category `res_f` has a tariff of a flat 150 in force. A deposit of 200 in that category, with the statutory cap of 200 and no `tariff_id`, is **accepted**.
- **Z7b.** The same deposit citing the tariff is refused.

Texas law is still held either way: the statutory cap is recorded and bounds the deposit. Only the utility's own, stricter policy is left out of the record. The patch already says which tariff row applies is the core's call. But this is the same pattern as round-3 S1, where leaving a field empty escaped a check, and the fix is one lookup.

**Fix.** When `NEW.tariff_category` is set and `rule_tariff_row_as_of(...)` finds a tariff row in force for it on the posting date, require `tariff_id` to be that row.

## NOTES

- **N1. The relate rule fails closed, sometimes too closed.** A related pair is compared only when both conditions are identical, or are simple forms of one measure.
  - **Reproduction (Z6).** A tariff trigger under `nsf` with `all_of[usage ≥ 3, 1 nsf in 12 months]` and 5 days to pay is **refused** as not comparable. It is stricter than 7.45, since it needs more than twice the usage.
  - A Texas utility that wants that rule must split it into two triggers or ask for a version 2. Worth one line in R7. A later version could treat an `all_of` that contains a leaf at least as strict as the law's as no looser.
- **N2. The law's other guards must be matched exactly.** This is unchanged from round 3 (N1 there), and so is the number-comparison idea: a stricter notice period is still refused. Fails closed; acceptable for version 1.
- **N3. The brief's decisions made without Ryan.**
  - Decision 1, a deposit's own closed law row stays citable: no objection.
  - Decision 2, a partial return needs no due row: fine.
  - Decision 3, no count-event vocabulary: with matching on leaves, the code carries nothing the comparison depends on, so not having the vocabulary is acceptable. Write AC-24/25 into the mirror commit, as R12 says.
- **N4. Nothing below changed in r4, and none of it is a blocker:**
  - basis figures are the writer's own (stated in R7);
  - the identity freeze leaves out the instrument issuer, reference and expiry;
  - the comment on the waiver-determinations column overstates what it checks;
  - the `:already` psql variable is set for the whole session.
