# Review r2 — v5.4.2-15 rewrite (deposits at the rule-terms convention) — Fable

Date: 2026-10-12. Artefacts: `patch-15r-frozen-r2.sql` md5 `edb410da0fffe721ac499e5607cc8a61` (matches; `sql/v5.4.2-15-deposits-law-to-core.sql` identical), `battery-15r-frozen-r2.sql` md5 `4512683f6e9c9847353481883a09d1b3` (matches; identical to `tests/v5.4.2-15/battery-15r.sql`). Repo at `1153320`.

How I probed: clone `fable15r2` (TEMPLATE `tally`, TEMP revoked); patch applied strictly — clean; the frozen battery passes: 292 PASS lines, exit 0. Then the battery with my probes appended (same transaction, rolled back; `pg_temp.try` reports ACCEPTED / REFUSED). A re-application on `fable15r2`; an application as a plain role on clone `fable15r2b`; six of the new mutations through `mutations-15r.py` (M113, M118, M123, M125, M130, M138: 6/6 caught — it makes and drops its own `m15mut*` clones). All clones dropped. Line numbers are the r2 patch's.

## Verdict: NOT YET — one blocking item, narrow and cheap; otherwise the round-1 fixes are real and complete

Every round-1 finding of mine is fixed and proved on both sides of its boundary (section 1). The blocking item is what the cap fix left behind on the one path that matters most to the first customers: under a **delegation** (a city-owned system, the Texas munis) nothing holds a deposit's cap to the city's own tariff, while the patch now says in two places that it does.

---

## 1. Round-1 fixes verified (each reproduced, both sides)

| r1 | What I re-ran on r2 | Result |
|---|---|---|
| B1 floor ordering | PC2: one wholesale category, category-less rate 1% in ZZ (retail floor 5%) | REFUSED "below the floor (0.05)"; PC2b 5% ACCEPTED. `deposit_rate_floor` 3673–3677 now lists every class of the state/service. F17–F19 and M123/M124 cover it. |
| B2a highest months | PA1: 2 months of HIGHEST under the 1/6-annual cap | REFUSED "cannot be shown to fit … stated on average billing"; PA3 (2 average months) ACCEPTED. |
| B2b minimum amount | PA2: 1 average month, minimum 9999 | REFUSED. |
| B2c count triggers | PD1 longer window, PD2 not consecutive / disputed counted | both REFUSED, each reason named; PD5 (shorter window, same protections) ACCEPTED; PD6 (unit `bills` vs `months`) REFUSED as incomparable; PD7 (law's count inside an `all_of` with an extra condition — stricter) REFUSED as incomparable (conservative, fine, stated at 3412–3414). |
| S1 cap record | PB1 tariff cap 5000, no part → REFUSED (R27); PB1b part c1, basis 1200, cap 5000 → REFUSED "above the statutory cap of part c1 (200)"; PB2 statutory 900 → REFUSED; PB3 exactly 200.00 → ACCEPTED; PB4 200.01 → REFUSED; PB5 100 → ACCEPTED | boundary right at the cent (`+ 0.005`, 4108). |
| S3 insert check | PE1 cap none + `excess_over_cap` → REFUSED (X16); PE2 two guards of a kind → REFUSED (X15); tariff side N26 | fixed. |
| S4 precondition | r2 section 1 counts `interest_accrued` (92–98); role check (85–88) | applied as a plain role on a fresh clone: refused at line 101 with the new message, database untouched. P5b/M138 cover the accrual count. |
| S6 mutations | 27 new (M111–M138; the list is 138 rows, the brief says 137) | the six I ran are caught by their named checks. |
| re-run (Opus S1) | second application on `fable15r2` | prints only "nothing to do" (line 67) and executes nothing else — `\gset`/`\if` wrap the whole patch (64–67, 5151). |

---

## Blocking

### B1. Under a delegation (and any no-cap law row) the deposit's cap is held to nothing, and `cap_component` / `cap_basis_amount` take garbage — while the patch now claims "a flat amount is held at each deposit by its recorded cap check" (3417, R7 at 5121–5124)

The new cap block (4073–4117) does everything inside `IF v_doc #>> '{cap,strategy}' = 'parts'`. Where the cited document is a delegation or a `cap: none` law row, the only check left is `cap_source = 'tariff' ⇒ tariff_id` (4077–4080), and the relaxed `deposits_cap_source_check` (3937–3940) no longer requires `cap_component IS NULL` for a tariff cap.

```
PO0 t1 homeowner tariff in force 2026-02-01: amount fixed 175
PO2 t1 city deposit under the delegation: cap_source tariff, cap 999999, principal 999999 => ACCEPTED
PO1 t1 city deposit under the delegation: cap_source tariff, cap_component "zzz", cap_basis_amount 7 => ACCEPTED
```

Why blocking: for a city-owned system the tariff *is* the deposit policy (design §5, R12 in the battery), and Texas munis are the first customers. The r1 fix made the claim true for law-capped deposits and false for exactly the path those customers use — rule 7 again. The core may compute the figure, but "the cap that applied is no more than the cited tariff's stated amount" is the same record-coherence check as 4108 is for the statute.

Fix (record checks only, no evaluation): when `cap_source = 'tariff'` and the tariff's `amount.strategy` is `fixed`, require `cap_amount ≤ amount`; when `months_of_billing`, require `cap_basis_amount` and `cap_amount ≤ cap_basis_amount × months` (and ≥ `minimum_amount` when stated — or leave the minimum to the core and say so); `none` / `case_by_case` hold nothing, stated. Where the cited document has no cap, require `cap_component IS NULL` and `cap_basis_amount` only when the tariff needs it (restores half of the old `deposits_cap_source_check`). Add R cases both sides for the city path (R12 today only proves 175 = 175).

---

## Should-fix

### S1. The comparator's "no law for the class" check is over *any* row, not over the tariff's whole range; a class whose law lapses mid-range passes on another class's coverage

`rule_tariff_check` (-17 2247) proves coverage over the range with rows of any class; `deposit_tariff_compare` (3446–3448) then only asks whether *a* row of the class exists among them.

```
PG0 ZZ class gap: one law row, 2020-01-01..2021-01-01
PG1 t3 gapcat tariff 2020-01-01..2022-01-01 (no gap law in 2021) => ACCEPTED
PG2 (control) tariff 2022-01-01..2023-01-01 (no gap law then)  => REFUSED "no law is known for the class gap"
```

`p_tariff` carries `effective_from`/`effective_to`; the comparator can build the class's `datemultirange` from the rows it was given and refuse unless it covers the tariff's range (the same arithmetic as -17 2241–2252). A deposit on the uncovered date is still refused by `rule_law_row_cite`, so this is "unknown law accepted as a tariff", not money — hence should-fix, not blocking. N18 tests only the no-row-at-all case; add the partial case.

### S2. A statutory cap on a `highest_bills` or `seasonal_average` part is recorded but unchecked, though its figure is computable from the recorded basis

`v_stat` (4103–4107) is NULL for those kinds, so 4108 is skipped; `cap_basis_amount` is required (4098) but idle.

```
PB6a ZZ hb law row: cap part highest_bills (count 2, window 12)
PB6 t3 deposit under it: cap_basis_amount 100, cap 99999, principal 99999 => ACCEPTED
```

If `cap_basis_amount` for `highest_bills` is the total of the N highest bills (as the schema's description says the part is), the cap is that figure; for `seasonal_average` it is `basis × multiple`. Both are one line each in the CASE at 4103. If the basis is defined otherwise, say what it is in the column comment (today it says only "the figure it was computed from") and state the gap in R7.

### S3 (decision for Ryan, not mine to settle). A deposit's own law row stays citable after its close, for dates after the close

Unchanged from r1 S2 by the coordinator's decision 1 ("grandfathered"); R4 (5098–5102) now states it, and PF1 (June accrual citing the row closed 2026-04-01, successor in force) is still ACCEPTED. I read Ryan's B1 the other way (the later law *reaches* deposits already held — so after a successor takes effect the old row is not the law for later periods). Either reading is defensible; it is a one-question decision and the database should encode whichever he gives, not the coordinator's reading. Plain question for him: "Once a deposit law row has been closed and replaced, may interest periods or return-due dates after the close still cite the old row, or must they cite the successor?"

### S4. Guards other than days-to-pay are dropped silently on a tariff trigger the law also names

Stated at 3415–3416 ("guards other than days to pay: not compared, and said so"), so not a defect in the claim; but `not_after_service_months`, `not_if_moved_within_days`, `notice_days`, `cured_by` are the customer's protections, and a tariff may drop all of them:

```
PD8 t3 shop: the law's condition, without the law's not_after_service_months guard => ACCEPTED
```

Same shape as the consecutive/disputed fix: a guard the law has and the tariff lacks (or with fewer months/days) fires where the law would not. Cheap to add for the four numeric kinds; `cured_by` compared by code. If left, name them in R7 as a core audit item (R7 names only "waivers and instalments").

### S5. Small things
- The mutation list has 138 entries (M138 added after the brief's "137"); `README`/brief count should follow.
- `\if`/`\gset` (64–67) make the patch psql-only; a non-psql runner (the future C# migration runner, or `tu.sql` assembly if it concatenates patches) would either choke on the backslash commands or run the body twice. Say so in the header, or guard the body with a DO-level check as well.
- A category-less rate is accepted while a class of the state has no law row (PC7: ZZ class `nolaw`, 5% accepted); a named-category rate for that class is refused (PC6, F19). Consistent with "a later law is a core audit finding", but the asymmetry should be a line in the `deposit_rate_floor` comment.

---

## Notes
- N1. `enforce_deposit_instalments_complete` (4289–4291): the law's schedule, else the cited tariff's (via `NEW.tariff_id`), else none. I1–I5 and M130–M134 cover it. A deposit with `received_at_posting` under TX law with no tariff is refused (schedule 0). Right.
- N2. The comparator's incomparable-condition branch (3516–3519) refuses a *stricter* combined condition (PD7). Conservative and stated; a utility wanting "the law's trigger plus one more" must write it as two tariff triggers (different codes) — worth one sentence in the tariff schema's trigger description.
- N3. `v_problem` is now de-duplicated and sorted (3531); messages are stable across runs. Good for the battery's phrase matches.
- N4. Non-superuser owner: the patch refuses before any DDL (85–88), after `BEGIN` — the transaction aborts cleanly; verified untouched.
- N5. Race scripts, evidence script, fail-first: unchanged from r1; not re-run.
- N6. The N4 battery label still reads "each deposit records the cap that applied and its own check holds it to it" — true now for a law-capped deposit (R27–R30); see B1 for where it is not.

## Answer to the brief's questions
Fixes real and complete: rate floor (yes), comparator (yes, with S1 and S4 as the stated limits), cap on a deposit (yes where the law caps; B1 where it does not), instalments (yes), insert checks (yes), precondition/re-run (yes), tests (yes; sample of the runner verified). Broke or newly allowed: nothing found; the relaxed `deposits_cap_source_check` is what lets B1's `cap_component "zzz"` through. Not on the list from my r1: S5 (`principal_returned` without a due row) is now R11 — accepted as a decision.
