# Opus review: v5.4.2-25 r8 (round-7 wording, diff only)

**Date:** 2026-11-27. **Reviewer:** Opus. **Round:** 8.
**Verdict: ready.** Nothing blocks. The comments and D9t4 do what the plan says. Nothing outside comments and D9t4 changed. I confirmed this on the built database, not only in the diff.

One sentence of the new R10 still says something that is not true of the seeded data. It is harmless in effect, but Ryan chose this round so that the mirrored text would be accurate, so I mark it should-fix (S1, wording only). If that one sentence is changed, nothing else needs to change.

## Hashes (executed)

All eleven frozen files match the brief's table:
- patch `8f430bce…`, battery `772c6a71…`, races `ba77a039…`, mutations `68ee1252…`, terms `83d14843…`, migration `55d80759…`, fill-manifest `33802a5b…`;
- law file `deb66829…`, seed `3832a44f…`;
- `r7-to-r8.diff` `4b4514ef…`, `battery-r7-to-r8.diff` `d014313e…`.

The brief's own md5 matches its `.md5` (`04247fcb…`). The live `sql/v5.4.2-25-disputes.sql` and `tests/v5.4.2-25/battery-25.sql` match the frozen r8 copies.

## What I ran (executed)

Clones: `rv25opus` (r8), `rv25opus_r7` (r7, for comparison) and `rv25opus_m` (one hand mutation). Each was made from `tally` (the last one from `rv25opus`), with TEMP revoked from PUBLIC, `tally_app` and `tally_core`. All three are dropped, and the files I copied into the container are removed. No clone was left over from round 7. I did not run `mutations-25.py` or `ci.sh`.

- **The two diffs are the real diffs.** `diff -u` of frozen r7 against frozen r8 is byte-identical to `r7-to-r8.diff` and to `battery-r7-to-r8.diff`, apart from the two timestamp lines. The races, mutations, terms, migration, filler, law file and seed are byte-identical (`cmp`) to their r7 copies.
- **Strict apply, twice** (`search_path=''`, `check_function_bodies=on`): clean. The second run prints "already applied (disputes exists); nothing to do".
- **Nothing outside comments changed in the built database (r7 against r8).** I compared the two clones directly:
  - All 680 `public` functions match on the md5 of every body, the config, security definer, volatility and ACL (`43f105e0…` on both).
  - Every trigger definition and its enabled state is the same. For the comparison I ignored the oid-derived names of RI triggers.
  - Every policy expression is the same (`842b2f6f…`).
  - Of all the function comments, exactly two differ: `dispute_tariff_compare(jsonb,jsonb)` and `enforce_dispute_reading_released()`.
- **battery-25 (frozen r8):** 351 PASS, 0 FAIL, rc 0. This reproduces the author's result.

## The items

### 1. R10 (read; executed in part)

**Direction (b) is right and complete (read, and D9a executed in the battery).** When the law's stage is final and the policy's own appeal follows it, the appeal stays in the combined record after the final stage. The contract sentence is exactly the reading this needs: `final` binds the utility and never ends an appeal the combined record keeps. It replaces r6's looser wording ("the core treats the law's final decision as binding").

**Direction (a) is now stated in full scope (read; executed).** Line 2820 of the patch takes the law's flag, `coalesce(v_ls -> 'final', 'false')`, at every place of the law's, so the replacement does happen earlier than the law's last stage. I ran it against seeded 7.45: a policy whose only stage is the employee's decision, marked final, comes back with that stage not final, followed by the law's own regulator stage, which is final.

**Is there a third direction? No (read).** There are four combinations of flags at a place of the law's:
- law not final, policy final: this is (a);
- law final, policy not final, with a policy appeal after it: this is (b);
- law final, policy not final, with nothing after it: the record becomes final where the law says so, which is the law's own term;
- both the same: nothing changes.

The policy's own stages after the law's last keep their own flags, and they are not law places. The rule that only the last stage may be final [L2d] means a policy's final stage is always its last. So nothing of the policy's own follows a replaced finality.

### 2. The comments (read; executed in part)

- **"no start is wider than it":** this now says what the code does. `any_time` admits every dispute.
- **"a law of either" is now named.** The new text says that a tariff of `average_usage_cap` under a law of `undisputed_charges`, or of a withholding of 1 or more, is looser. That matches the code:
  - the battery's D9t verdicts at 1 and 1.1 (executed);
  - my round-7 grid, where the average-cap rows are "looser" at w1, w1.0, undisputed charges, w1.1 and w10 (executed in r7; the body is unchanged since).

  Nothing the old sentence said was lost.
- **The release comment** now says "a close can deadlock with any transaction that writes the reading's row (its move into or out of disputed, a clerk's note) and then takes one of its disputes' locks". That is the header's r5 rule word for word in substance (patch lines 126–130: any column, then a dispute's lock, in the reverse of a close's order). My round-7 N1 is closed.

### 3. D9t4 (executed)

- **The value is right, and in this order.** The actual `must_pay.either` is `[policy's average cap (id m1, history 2, similar_customers), law's withholding cap (id m2, 0.9, citation battery)]`. That is exactly `jsonb_build_array(avg('m1'), wcap(0.9,'m2'))`. The combine code puts the tariff's term first and the law's second (line 2776). The law's id is not prefixed `law:` here, because the two ids differ (m1 and m2). The reverse pair (0.9 policy, average-cap law) also comes back `[policy's, law's]`.
- **It fails on every wrong shape.** I compared the expected value against each wrong one: swapped, the law's dropped, the policy's dropped, the policy's term twice, missing (NULL), and the law's id relabelled `law:m2`. All six give false.
- **A hand mutation it now catches.** In `dispute_terms_combined`, I replaced `jsonb_build_array(v_doc -> v_f.section, v_lt)` with `jsonb_build_array(v_doc -> v_f.section, v_doc -> v_f.section)`, so the tariff's term is kept twice and the law's is lost. This is exactly the gap my r7 N3 named.
  - Run alone on the mutated clone, r7's D9t4 condition (a count of 2) is **true** and r8's is **false**. On the clean clone, both are true.
  - In the full battery, D9f2 fails first (line 1558), and with D9f2 skipped, D9f4 does. So the mutation was already caught before r8. What r8 adds is that D9t4 now catches it too, and so matches its own label.
- No mutation in the unchanged runner is aimed at D9t4 (grep), so tightening it changes no mutation's expected check.

### 4. Anything else changed? (executed)

Nothing changed beyond the header's R10, the two comments and D9t4: see "What I ran". The plan's two "Not changed" items (my r7 N2, Codex's D9u point) are left as decided. I agree with both.

### 5. My round-7 items

| Round 7 | What it was | Round 8 |
|---|---|---|
| N1 | Two wording points (the release comment narrower than the header; "narrower than no start") | Closed (item 2) |
| N2 | An always-true condition in the average-cap leg | Not changed, by decision. Harmless; no mutation for it |
| N3 | D9t4 counted the kept terms but did not say which | Closed (item 3) |
| N4 | The must-pay order is complete | Nothing to do |

---

## S — should fix (wording only, before the mirror)

### S1. R10's last sentence is not true of the seeded 7.45 row (executed)

R10 ends: "No seeded law row has a stage that is not final where a policy's could be; one written so comes back to Ryan under his 2026-11-26 ruling."

**The seeded data.** The seeded 7.45 row for protected customers (16 TAC 7.45(6)(D), investor-owned and cooperative) has two stages:
- the employee's decision, not final;
- the regulator's, final.

The other three seeded rows have no stages, or delegate the rule to the utility.

**Why the sentence is false.** A policy's stage at the employee's place can be final: a policy whose only stage is the employee's decision. I ran exactly that through the combination. The policy's finality is replaced by the law's "not final", and the law's regulator stage follows. That is R10's direction (a), "earlier", on a seeded row.

**What happens to the customer.** No customer is harmed. Where the replaced stage is not the law's last, the law's own later stages always follow it. So the combined record keeps every appeal the law gives, and it is never less protective than the law. Only at the law's last stage does "which protects more depends on the customer" really apply. The fact that matters, and r7's old sentence, is that no seeded law row has a *last* stage that is not final.

**Why fix it now.** As mirrored, the sentence would tell a reader that the seeded data never meets direction (a), when it does (harmlessly). It would also leave unclear which future law row should "come back to Ryan". The text cannot be edited after the mirror.

**Suggested wording** (no code or test changes):

> (a) … the policy's finality is replaced. Earlier than the law's last stage the law's later stages follow, so the customer keeps every appeal the law gives (7.45's employee stage is such a place); at the law's last stage which protects more depends on the customer. … No seeded law row has a last stage that is not final; one written so comes back to Ryan under his 2026-11-26 ruling.

If Ryan prefers not to spend another round on it, the same correction can go in the mirror's contract list instead. Nothing in the behaviour depends on it.

## N — notes

None new.
