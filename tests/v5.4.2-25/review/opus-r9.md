# Opus review: v5.4.2-25 r9 (one sentence of R10, diff only)

**Date:** 2026-11-27. **Reviewer:** Opus. **Round:** 9.
**Verdict: ready.** Nothing blocks and nothing should be fixed. R10 is now true of the code and of the seeded law rows, clause by clause. Nothing outside the header comment changed. My round-8 S1 is closed. One optional wording note (N1).

## Hashes (executed)

All ten frozen files match the brief's table (patch `9dae050b…`, battery `772c6a71…`, races `ba77a039…`, mutations `68ee1252…`, terms `83d14843…`, migration `55d80759…`, fill-manifest `33802a5b…`, law file `deb66829…`, seed `3832a44f…`, `r8-to-r9.diff` `612c0f9e…`). The brief's own md5 matches its `.md5` (`3f25c3cb…`). The live `sql/v5.4.2-25-disputes.sql` and `tests/v5.4.2-25/battery-25.sql` are byte-identical to the frozen r9 copies.

## What I ran (executed)

Clone `rv25opus` from `tally` (none left over), TEMP revoked from PUBLIC, `tally_app` and `tally_core`. Dropped when done; the files copied into the container are removed. I did not run `mutations-25.py` or `ci.sh`.

- **The diff is the real diff.** `diff -u` of frozen r8 against frozen r9 is byte-identical to `r8-to-r9.diff` apart from the two timestamp lines.
- **Only comment lines changed.** Of the changed lines between r8 and r9, none is anything but a `--` comment (0 non-comment lines). The changed lines are the header's R10 only, so no function body, `COMMENT ON` text or test differs.
- **Every other frozen file is byte-identical (`cmp`) to its r8 copy:** battery, races, mutations, terms, migration, filler, law file, seed.
- **Strict apply, twice** (`search_path=''`, `check_function_bodies=on`): clean, rc 0; the second run prints "already applied (disputes exists); nothing to do".
- **battery-25 (frozen r9):** 351 PASS, 0 FAIL, rc 0.

## The items

### 1. Is R10 true of the code, clause by clause? Yes (read, and executed on seeded 7.45)

The merge (`dispute_terms_combined`, patch lines 2806–2835) walks the law's stages by position. At each law place it keeps the policy's stage if it has the law's decider (with the law's `final`, line 2822), otherwise the law's own stage; then it appends the policy's other stages, with their own flags, after the law's last. So every law place appears in the combined record, in the law's order, with the law's final flag.

- "at each of the law's places the combined stage takes the law's final flag, either way": line 2822, or the law's stage itself. True.
- (a) "Wherever the policy's stage at a law place is final and the law's is not, the policy's finality is replaced": line 2822. True.
- "Earlier than the law's last stage the law's later stages follow, so the customer keeps every appeal the law gives": every later law place is still in the output, after it. True.
- "7.45's employee stage is such a place": the seeded 7.45 row is `designated_employee: not final > regulator: final`. Case A below shows it. True.
- "at the law's last stage which protects more depends on the customer": nothing of the law follows there. True as a statement of what is left open.
- (b) and "both rest on the core reading final …": unchanged in substance from r8, which I found right.
- "No seeded law row has a last stage that is not final" (executed): the seeded rows in `dispute_rules` are 7.45 protected (`employee:false > regulator:true`), 7.45 unprotected (no stages), and the two municipal rows (no stages section). The two platform defaults have `stages: []`. The only seeded last stage is final. True.

### 2. Does the customer keep every law appeal, including where the policy's list displaces a stage? Yes (executed)

I ran the merge against the seeded 7.45 row with four policies:

| Policy's stages | Combined |
|---|---|
| A. employee, final | employee (p1): not final > regulator (s2): final |
| B. manager, final (displaced: not the law's decider) | employee (s1): not final > regulator (s2): final > manager (p1): final |
| C. employee not final, then manager final | employee (p1): not final > regulator (s2): final > manager (p2): final |
| D. manager not final, then employee final (both displaced) | employee (s1): not final > regulator (s2): final > manager (p1): not final > employee (p2): final |

In every case both of the law's appeals are present, in the law's order, with the law's flags. A displaced policy stage is not at a law place, so (a) does not touch it: it keeps its own flag after the law's last, which is direction (b) ("a final stage, then another"). This is what the code reads as, and R10 covers it.

Case D puts a policy's employee decision after the regulator's. That is positional matching, already stated in R9 ("the law's stages must be its first") and in the function's comment; it is not something R10 must say.

### 3. Did anything outside the comment change? No (executed)

See "What I ran".

### 4. My round-8 items

| Round 8 | What it was | Round 9 |
|---|---|---|
| S1 | R10's last sentence was false of seeded 7.45 | Closed: my suggested wording is in, item 1 |

## B — blocking

None.

## S — should fix

None.

## N — notes

### N1. A parenthetical reads awkwardly (read; optional, wording only)

"(7.45's employee stage is such a place, as for a shorter older policy under a longer later law)" joins two different examples with "as for", which can be read as saying 7.45's case *is* the shorter-older-policy case. Both are correct examples of "earlier than the law's last stage". If anyone touches the line again, "(7.45's employee stage is such a place; so is the last stage of a shorter older policy under a longer later law)" is clearer. Not worth a round by itself.
