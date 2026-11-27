# v5.4.2-25 r8 — Fable's review (round-7 wording, diff only)

**Date:** 2026-11-27. **Reviewer:** Fable (claude-fable-5-2). **Verdict: ready.** Nothing blocking and nothing to fix. The round changes two function comments, one header paragraph and one test, and nothing else: the schema a database ends up with under r8 differs from r7's in exactly those two comments. Each changed sentence says what the code does. The strengthened test fails on every wrong pair I could make it produce. Six notes, none asking for a change to the patch.

**Frozen files:** the eleven md5s and the brief's own md5 match. `r7-to-r8.diff` and `battery-r7-to-r8.diff` are the true diffs of the frozen r7 and r8 copies (regenerated and compared), and the live patch and battery are byte-identical to the frozen r8 copies. The other seven files are byte-identical to their r7 copies. Read: the brief, the r8 plan in full, the "Round 7 reviewed" section of the r7 plan, both diffs in full, my own `fable-r7.md`. Did not read any `opus-*` or `codex-*` file.

**Reproduced** (clone `rv25fable` of `tally`, none left over; TEMP revoked from PUBLIC, `tally_app`, `tally_core`; frozen r8 applied strictly, `search_path=''`, `check_function_bodies=on`):
- strict apply succeeded; the second run said "already applied (disputes exists); nothing to do";
- `battery-25-frozen-r8.sql`: 351 PASS, 0 FAIL, rolled back ("battery-25: all checks passed"), D9t4 among them under its new label.

Not run, per the brief: `mutations-25.py`, `tests/ci.sh`; also not run: the races, `terms-25.py`, `migration-25.py` (all byte-identical to r7, and no function body changed, N1). No role created, dropped or altered. The clone and my files in the container are dropped; `tally`, `sql/tu.sql` and the repo are untouched (this file is my only write). No container started.

How the probes ran: appended to a copy of the frozen r8 battery after D9u (line 1752), inside its one rolled-back transaction, on its own fixtures (`combo`, `verdicts`, `tdoc`, `avg`, `wcap`, `undisp`, `st3b`, `lawgb`, `tariff_sql`), as the owner. The hand mutations replaced `dispute_terms_combined` inside a sub-transaction (from `pg_get_functiondef`, one text replacement, anchor checked present and unique) and were undone each time.

---

## B — blocking

None.

## S — should fix

None.

---

## N — notes

### N1. Nothing outside two comments, one header paragraph and D9t4 changed — executed

Applied frozen r7 to one fresh clone and frozen r8 to another, and compared `pg_dump --schema-only` of the two (59,351 lines each). The only differing lines, apart from pg_dump's own random session token, are:

```
COMMENT ON FUNCTION public.dispute_tariff_compare(p_tariff jsonb, p_law jsonb) IS ...
COMMENT ON FUNCTION public.enforce_dispute_reading_released() IS ...
```

So every function body, trigger, table, grant, policy and the manifest's hash lists are the same in the database, not only in the text. The third hunk of the patch diff is the header's R10 paragraph, a SQL comment that never reaches the database. The battery diff is one check (D9t4), two lines. The header's "Tests" line (351 checks, 199 mutations) is unchanged and still right.

### N2. R10 says what the code does, in both directions, and I find no third — executed

Stage lists below are id/decider/final.

Direction (a), a policy's final stage where the law's is not final:

```
policy [employee F, regulator T] under law [employee F, regulator F]
   -> s1/designated_employee/false, s2/regulator/false                      (at the law's last stage; D9u's shape)
policy [employee F, regulator T] under law [employee F, regulator F, governing_body T]
   -> s1/…/false, s2/regulator/false, s3/governing_body/true                (earlier than the law's last: the shorter policy)
```

Direction (b), a final law stage with the policy's own stage after it:

```
policy [employee F, regulator F, governing_body T] under 7.45 [employee F, regulator T]
   -> s1/…/false, s2/regulator/true, s3/governing_body/true
policy [employee F, regulator T] under law [employee F, governing_body F, regulator T]
   -> s1/…/false, law:s2/governing_body/false, s3/regulator/true, s2/regulator/true   (the policy's displaced stage)
policy [employee F, regulator F, governing_body T] under a one-stage law [employee T]
   -> s1/…/true, s2/regulator/false, s3/governing_body/true
```

Why there is no third direction. The flag is written in one place only, where a policy's stage is kept at a law's place, and it is always the law's value. A policy's stage that is not at a law's place keeps its own flag and moves after the law's last. So the flag can change in two ways and no more: true to false, which is (a), and false to true, which can only cost a customer something if a stage follows it, which is (b). A policy's displaced final stage landing after a final law stage (the fourth line above) is the same thing as (b): a final stage, then another. The contract sentence covers each of these.

The paragraph's last sentence also holds: "No seeded law row has a stage that is not final where a policy's could be." The one seeded law with stages is 7.45's protected row (employee not final, regulator final); the other three law rows and both platform defaults have none. A policy's final stage can only be its last (the document check, [L2d]), so the only way to put a final policy stage against 7.45's non-final first stage is a one-stage policy, and that cannot be filed:

```
one-stage final policy, investor-owned tenant, from 2026-02-01   -> REFUSED 23514 "looser than the law: stages …"
the same from 2003-01-01 (before 7.45 took effect), open-ended   -> REFUSED P0002 "no law is known … over [2003-01-01,2004-07-12)"
the same from 2003-01-01 to 2004-01-01                            -> REFUSED P0002
two stages, the first final                                       -> REFUSED 23514 [L2d]
```

So "a shorter older policy under a longer later law" cannot arise against any seeded row; it needs a law row written later, which is what the sentence says comes back to Ryan.

### N3. One reading of "Both are safe only as the core reads final" — predicted, no change asked

The sentence states a condition that is needed, not one that is enough, and that is accurate. For whoever writes the contract at the mirror, the two directions do not lean on it equally. Direction (b) is fully settled by the contract: if `final` never ends an appeal the combined record keeps, the policy's appeal survives and no customer loses anything. Direction (a) stays what the paragraph already calls it, dependent on the customer (one who won at that stage loses the utility being bound there; one who lost gains the law's further stage, where there is one). The contract keeps (a) from being worse; it does not make (a) neutral. The paragraph does not claim otherwise, so this is a note for the contract's wording, not a correction.

### N4. The two comparator sentences are right — executed

"any_time admits every dispute …, so no start is wider than it, and every other start is narrower than a law's any_time":

```
policy any_time under a law of before_termination / before_delinquency / within_days (receipt) /
       within_days (issue) / on_regulator_complaint / any_time            -> no finding, all six
each of the first five as the policy under a law of any_time              -> shelter_earned: looser, all five
```

"so a tariff of average_usage_cap under a law of undisputed_charges or of a withholding of 1 or more is looser":

```
policy average cap under law undisputed charges  -> must_pay: looser
                   under law withhold 1          -> must_pay: looser
                   under law withhold 1.1        -> must_pay: looser
                   under law withhold 0.999      -> must_pay: not_comparable   (below 1: the next clause of the comment)
                   under law full bill           -> no finding                 ("never exceeded")
```

The ambiguous "either" I raised in round 7 (my N6) is gone; the sentence now names the two strategies.

### N5. The release function's deadlock clause now matches the header's lock rule — by reading

Header (lines 126–130): "a transaction that writes a reading's row (any column: its move into or out of 'disputed', a clerk's note) and then takes the lock of one of its disputes takes the two in the reverse of a close's order, and can deadlock with a close". Comment, r8: "a close can deadlock with any transaction that writes the reading's row (its move into or out of disputed, a clerk's note) and then takes one of its disputes' locks". Same subject (any write to the row), same condition (then a dispute's lock), same examples. The rest of the sentence (two disputes in opposite orders, two readings in opposite orders, every writer retries 40P01) is unchanged from r7 and matches the header's r6 sentence. The lock behaviour itself is unchanged (N1), and I tested it in rounds 4 to 7.

### N6. D9t4 is right and now fails on every wrong pair — executed

The combined record's `either` for an average-cap policy under a law withholding up to 0.9:

```
[{"id": "m1", "version": 1, "strategy": "average_usage_cap", "no_history": "similar_customers", "history_years": 2},
 {"id": "m2", "version": 1, "citation": "battery", "fraction": 0.9, "strategy": "withhold_cap"}]
```

That is `jsonb_build_array(avg('m1'), wcap(0.9,'m2'))`: the policy's term first, the law's second, the law's id unmarked because the two ids differ. Seven hand mutations of the line that builds the pair, each evaluated under the r7 check (count is 2) and the r8 check:

```
mutation                                      r7 check   r8 check
order swapped (law's first)                   passes     FAILS
the law's term twice                          passes     FAILS
the policy's term twice                       passes     FAILS
the law's term dropped                        fails      FAILS
the policy's term dropped                     fails      FAILS
the law's id always marked 'law:'             passes     FAILS
the law's citation stripped                   passes     FAILS
unmutated, before and after                   passes     passes
```

Five mutations that r7's check let through are now caught. The comparison is whole-value and NULL-safe (`IS NOT DISTINCT FROM`, and `ok()` fails on anything but true), so a missing section fails too. One thing I could not run, per the brief: whether any of the 199 mutations that used to be caught at a later check is now caught first at D9t4; the author reports 199 of 199 each at its named check after the change, and the runner is byte-identical to r7's.

### N7. My round-7 items

- **N4 (the other direction of the law's final flag):** closed in the patch by R10 (b) and the contract clause (N2 above).
- **N6 (the ambiguous "either"):** closed (N4 above).
- **N3 (what the average-usage cap means) and the contract half of N4:** not in the patch, by design; the r8 plan lists both sentences under "Contracts at the mirror". Still open until the application contract is written at the mirror: (1) under an average-usage cap the customer pays the undisputed part plus the disputed part up to the average-usage amount; (2) `final` binds the utility and never ends an appeal the combined record keeps. The must-pay ordering mirrored in this patch is only right for every customer under (1).
- **N1, N2, N5, N7:** nothing was asked. The always-true average-cap condition stays, as the plan says; I agree it is not worth a body change.

### N8. Housekeeping, not about the patch

Two `crystaldba/postgres-mcp` containers were running when I started (`pgmcp-41600-…`, `pgmcp-44623-…`). I did not start or stop them; they did not get in the way.
