# Review r1 — v5.4.2-15 rewrite (deposits at the rule-terms convention) — Fable

Date: 2026-10-12. Reviewer: Fable (one of three, independent).
Artefacts checked: `patch-15r-frozen-r1.sql` md5 `988d73eff960db25d503cc2a39d10f3a` (matches; the working copy `sql/v5.4.2-15-deposits-law-to-core.sql` has the same hash), `battery-15r-frozen-r1.sql` md5 `595ee401f0cfbc0d9c26f4013a155163` (matches; same as `tests/v5.4.2-15/battery-15r.sql`). Repo at `0e72b41`.

How I probed: clone `fable15` (TEMPLATE `tally`, TEMP revoked), the patch applied strictly (`search_path=''`, `check_function_bodies=on`) — clean, 16 law rows, invariants hold. The frozen battery passed to H29 (exit 0). Then the battery with my probes appended in the same transaction (rolled back): a `pg_temp.try` helper that reports ACCEPTED / REFUSED without aborting. A second clone `fable15b` for the migration precondition. Both clones dropped. Line numbers below are the frozen patch's unless marked.

## Verdict: NOT YET

Two blocking items (B1, B2), one borderline (B3) that I put in should-fix because fixing it may be a wording change rather than a guard, and a list of should-fixes. Nothing here is a tenancy or grant hole; the convention plumbing (registration, seeds, facets, locks, RLS, append-only) is sound and the battery proves most of what it claims. The problems are in the two places where this patch makes its own promises beyond the template: the interest floor (decision 4) and the comparator (decision 5's "never looser than the law").

---

## Blocking

### B1. The floor on a category-less rate reaches only the classes the utility's categories map to *at the time of writing* — adding a category later puts a below-floor rate in force for it (decision 4 bypassed by ordering)

`deposit_rate_floor` (patch 3612–3622): with `p_category` NULL, `v_classes` is the DISTINCT `law_class` of the utility's existing categories, and only when it has **none** does it fall back to every class of the state and service. `deposit_interest_rate_row_as_of` (3731–3735) then serves the category-less row to any category with no row of its own.

Reproduction (ZZ fixtures from the battery: retail's law names a fixed 5% floor; wholesale's rate is `reference`, no floor):

```
PC1 t5 (no categories)            category-less rate 1% in ZZ  => REFUSED 23514 … below the floor (0.05)
PC2 t4 (one category -> wholesale) category-less rate 1% in ZZ  => ACCEPTED
   t4 then adds category shop -> retail
PC3 rate row in force for t4 shop on 2026-01-15: 0.010000
PC4 t4 deposit in category shop (retail) under the retail law row => ACCEPTED
PC5 t4 accrual on that retail deposit at the 1% row (law floor 5%)   => ACCEPTED
```

So the same 1% row is refused for a utility with no categories and accepted for one with a single wholesale category, and the moment a retail category exists the 1% row is the rate in force for retail deposits, and accruals at 1% cite it. Nothing re-checks: `enforce_deposit_utility_category` (3272) does not look at rates, and `enforce_deposit_event` (4826–4846) checks only that the rate row is the tenant's, in effect by the period start, at its own rate.

The battery's F11 ("a rate for every category must clear every class's floor") passes only because t3 happens to have a category for every ZZ class; the check is narrower than its label (rule 7).

Fix (schema side, no evaluation): a category-less rate clears every class of the state and service whose law row binds the utility (drop the first branch of the `ELSE` at 3616–3621 and always use the `deposit_customer_classes` list). That is what the text at 3591–3594 half-says and what F11's label claims. The alternative (re-check category-less rates on category insert) is a count-guard on a moving set; avoid it.

### B2. `deposit_tariff_compare` certifies "never looser than the law" but silently skips three shapes the schema admits, and the residual (R7) does not say so

(a) `months_of_billing` with `of: highest` (schema `amount_months.of ∈ {average, highest}`, tariff schema line ~2169; `deposit_tariff.city_commercial` example is "twice the highest monthly bill") is converted exactly as `average` (3416–3438). Two months of the *highest* bill is more than one-sixth of annual billing (two *average* months), yet:

```
PA1 t2 residential tariff: 2 months of HIGHEST billing  => ACCEPTED
```

(b) `minimum_amount` on a months tariff is ignored: `PA2 1 month of average billing, minimum 9999 => ACCEPTED`. R7 names "a flat amount"; a minimum is a flat amount hiding inside a compared shape.

(c) Count triggers are compared only when `v_tc -> 'window' = v_lc -> 'window'` (3454–3455), and `consecutive` / `exclude_disputed` are never read. A longer window with the same count fires sooner; dropping `consecutive` or counting disputed bills fires sooner. Reproduced against a ZZ retail `additional_trigger` row (3 late payments in 12 months, consecutive, disputed excluded):

```
PD1 same trigger, 3 in 24 MONTHS                              => ACCEPTED
PD2 same trigger and window, NOT consecutive, disputed counted => ACCEPTED
PD3 (control) same window, 2 in 12                            => REFUSED … fires at 2 … where the law waits for 3
```

Why blocking: the comparator is the one guard decision 5 rests on ("a looser one is refused when written", design §5). Rule 7: a check narrower than its claim buys false confidence; the battery's N group (N1, N2, N5–N7, N14, N15) only ever exercises `average` months, equal windows and ratio triggers, so it passes.

Fix: (a) treat `of: highest` as unconvertible (`v_allowed := NULL`) and add it to R7, or — better — refuse to compare and say so in the returned reason list is not available, so the honest option is "uncompared, stated". (b) same for a non-`none` `minimum_amount`. (c) for counts of the same event and unit: tariff is looser when `at_least` is lower, **or** the window is larger, **or** law `consecutive` is true and the tariff's is false, **or** law `exclude_disputed` is true and the tariff's is false; a different unit is uncompared and stated. Add N cases for each side of each boundary.

---

## Should-fix

### S1 (borderline blocking). A tariff cap, or a statutory cap, is held to nothing but the number the application writes — and the comparator's comment, R7 and N4 claim otherwise

`deposits_cap_check` (3877) holds `principal ≤ cap_amount − cap_other_held`. For `cap_source = 'tariff'` the only check is that a tariff row is cited (4028–4033); for `cap_source = 'statute'`, that the part id exists and `cap_basis_amount` is present (4011–4027). Nothing ties `cap_amount` to the part's figure, nor a tariff cap to the law's cap.

```
PB1 t2 deposit, category residential_senior (law cap 1/6 annual), cap_source tariff, cap 5000, principal 5000  => ACCEPTED
PB2 t2 deposit, statutory cap c1 (divisor 6), cap_basis_amount 1200, cap_amount 900, principal 900             => ACCEPTED
```

PB1 is a 5000 deposit under a law whose cap is one-sixth of annual billing, with the tariff's flat amount never compared (N4) — the comparator comment (3381–3382), R7 (5028–5029) and N4's label all say "each deposit's own recorded cap check holds it". It holds the principal to a figure the app chose. PB2 shows the statutory branch is no tighter: 1200/6 is 200, the record says 900.

Under rule 6 the cap's size is the core's; but the *record's coherence* is the database's, and `cap_amount = cap_basis_amount / divisor` (or `× months`) is arithmetic on recorded figures, not evaluation — exactly what `rate_applied = annual_rate` already does for accruals (4842). Minimum fix: correct the three false claims (comment, R7, N4) so nobody trusts them. Better: for a statutory cap on a `fraction_of_annual_billing` / `months_of_billing` part, require `cap_amount` to equal the figure (rounded as the core states, or ≤ it); for a tariff cap under a law row whose cap is `parts`, require the statutory figure recorded too and `cap_amount ≤` it. Add R cases on both sides.

### S2. A deposit's own law row is citable for periods *after* its close; the close floor then rises above the row's own end (R4 states this; it contradicts B1)

`deposit_rule_citable` (3773): `r.id = own.id` is true without any date test; `deposit_cite_rule` (3800–3801) then only takes the lock. The battery's A17 (March, before the April close) is fine; but:

```
PF1 t3 c4 accrual June 2026 citing the CLOSED own row (successor in force since April) => ACCEPTED
PF3 close floor of the closed household row now: 2026-06-20 (its effective_to is 2026-04-01)
```

Ryan's B1 (2026-10-02, cited at 3759–3760) says a later law reaches deposits already held — so after the successor takes effect, the old row is *not* the law for June, and an accrual citing it is the wrong law recorded as right. The row's close floor also now exceeds its own `effective_to`, which inverts what the floor means. R4 (5009–5013) states the behaviour as intended; I think it is the wrong reading of B1 and should be put to Ryan as one decision: "may a record for a date after a law row's close still cite that row?" If no: `deposit_rule_citable` requires in-force over `[p_from, p_to]` for the own row too (keeping the lock-only path for the posting-date citation that `rule_law_row_cite` already covers). A19/A17 stay green either way.

### S3. `deposit_rule_insert_check` accepts two documents it should refuse

```
PE1 ZZ retail law row: cap {strategy: none} + return rule {reason: excess_over_cap}  => ACCEPTED
PE2 a trigger with two guards of the same kind (payment_due_days 10 and 2)           => ACCEPTED
```

PE1 matters: `enforce_deposit_return_due_record` (4405–4412) lets a partial due row through on any document with a partial-reason rule; under a no-cap document "excess over the cap" has no meaning. Add to the insert check: a `partial` reason (`deposit_return_reasons.partial`) needs `cap.strategy = 'parts'` (excess_over_cap) — `excess_over_current_bill` is fine without a cap. PE2: one guard per kind, as the cap and trigger lists already demand.

### S4. The precondition does not name a legacy deposit that carries -06 accrual events; the patch dies on a CHECK instead

Section 1 counts non-legacy deposits, waiver rows and rate rows (82–90). A `legacy_unknown` deposit with an `interest_accrued` event from -06 (no `rate_id` / `rule_id`) passes the precondition, then:

```
psql:<stdin>:4667: ERROR: check constraint "deposit_events_accrual_fields_check" of relation "deposit_events" is violated by some row
```

Fail-closed and the transaction aborts (database untouched: verified), but with no name and no hint. P1 plants legacy deposits without events, so the migration test never sees this. Add the count to section 1's message (and a P1 variant with an accrual event).

### S5. `principal_returned` needs no due row, so the "partial return only under a document with a partial rule" guard is on the label, not the act

Q1 proves a *due row* with an amount is refused under Texas; but `PJ2: principal_returned of 10 on the t2 Texas deposit, no return_due_id => ACCEPTED`. If a voluntary partial return is intended (the utility may hand money back at will, as it may refund at will), say so in the table comment and R-list; if not, require `return_due_id` on `principal_returned` (the refund events may stay optional).

### S6. Mutation runner: guards with no mutation (each should get one, or a stated reason)

Read against the 110 in `mutations-15r.py`; none of these has a mutation, and several have no battery case either:
- `enforce_deposit_instalment` (4149): earlier transaction, received whole, due before posting; `enforce_deposit_instalments_complete` (4192): count vs schedule, sum vs principal. (evidence-txn X2 covers the txn one only.)
- `enforce_deposit`: `cap_other_held` ⇔ combined scope (4018); `cap_basis_amount` ⇔ not fixed_amount (4023); trigger from the tariff needs `tariff_id` (4045); born held (3945); `legacy_interest_earned` (3942).
- `deposit_tariff_insert_check`: the tenant line (3343; RLS would still refuse, so U5 cannot tell) and the instalment sum (3365).
- `deposit_tariff_compare`: the `governs = 'law'` filter (3414), the basis filter `('credit_evaluation','tariff')` (3416), the `greater_of` branch (3430), `single` with an unconvertible part (3432).
- `deposit_rate_floor`: the fixed-rate branch (3635; F7 tests it, no mutation), the owner/system/jurisdiction span filters (3629–3631; M41 mutates the class filter only), the profile-date filter.
- `deposit_published_rate`: the `scoped_by` matching (3577–3578).
- `enforce_deposit_event`: rate-row tenant/state/service lines (4827–4828; M57 is the category only); refund amount = remainder (4899, 4909); cash refunded / non-cash released (4903–4907); nothing accrued uncredited at the last event (4913).
- `enforce_deposit_return_due_withdrawal`: the whole function.
- The isolation checks (3675) — due-mutex R6/R8/R10 cover them outside the runner; say so in the M-list as M96 does.
Equivalences: none found; M22/M23 both name N2 but mutate different things (a boundary flip vs a wrong conversion), fine.

### S7. Docs that still name the dropped -06 objects

`application/APPLICATION-CONTRACTS.md` AC-25 (line 243–246) tells the application to watch `deposits_refund_due` and call `deposit_interest_rate_as_of()` / `deposit_refund_trigger_state()`, all dropped by section 13. No database object references them any more (checked `pg_proc` / `pg_views` on `fable15`); CHANGELOG and the audit docs are history and fine. AC-25 needs rewriting to the owed view and the core.

---

## Notes (no action needed, or a line of wording)

- N1. `deposit_tariff_insert_check` pre-empting row security (3343–3348) is safe: the policy on `deposit_tariffs` has no WITH CHECK, so USING governs inserts and runs after the BEFORE trigger; the check only improves the message (`is_platform_admin()` is the same predicate the policy uses). It is therefore also untestable by a mutation — see S6.
- N2. `lesser_of` with an unconvertible part is compared against the least convertible part (3429: `min()` ignores the NULL) — stricter than the comment "only when every part can be converted" (3381). `PI2 4 months vs lesser_of(fixed 50, 3 months) => REFUSED; PI3 2 months => ACCEPTED`. Right behaviour; R7 should say it.
- N3. Re-run: after the "nothing to do" NOTICE (79) the other ~150 statements still execute — idempotent (`IF NOT EXISTS`, `OR REPLACE`, `DROP … IF EXISTS` then re-add). P2 proves no data moved; the re-added CHECKs are re-validated over live rows, which is a table scan, not a change. Worth a line in the header.
- N4. `rule_tariff_check` is satisfied by *any* class's law row over the dates (-17 2247–2252); a category mapped to a class with no law row would get a tariff accepted with nothing compared (the deposit would then be refused by `rule_law_row_cite`). Not reproduced (every ZZ class in the battery has a row); a one-line statement in R7 or a comparator reason ("no law row for class X") would close it.
- N5. Grants: `tally_app` holds UPDATE on `deposits` (the row-version mutex needs it; identity frozen by trigger, status at depth ≥ 2 only — `PJ1` refused) and on `deposit_tariffs` (close only, template trigger); UPDATE/DELETE on categories are refused by trigger (C7, C8). `deposit_rules` SELECT only (H8). Consistent with R5.
- N6. `deposit_rate_floor`'s jurisdiction `CASE` (3631) mirrors the template's; `utility_service_profiles.commission_jurisdiction` is NOT NULL, so no fail-open there.
- N7. Non-superuser owner: not tested. The patch needs table ownership throughout; seeds go through the law insert trigger (no role check on insert), and closes of law rows need superuser/BYPASSRLS (template 2289). Nothing in the patch itself checks `rolsuper`.
- N8. `deposit_rule_close_floor` (2953–2959) counts deposits' posting, events' `coalesce(period_end, effective_on)` and due rows' `due_on` across tenants (invoked by the closing role, which sees all; H13/H14 prove the floor and R25 the deposit). Withdrawals and evidence carry no `rule_id` — right, they rest on their due row.
- N9. The withdrawal-after-settlement probe matched no row, so "can a settled due row be withdrawn?" is unproven either way; the guard (4562–4584) does not look at `deposit_return_due_is_live`. Harmless if "it moves no money" is the whole story; a line in the comment would do.
- N10. Dropped objects: no view or function in the database still references `deposits_refund_due`, `deposit_interest_rate_as_of`, `deposit_accrual_amount`, `deposit_refund_trigger_state`, `refund_eligibility_on`, `cap_basis_annual_billing` (checked on `fable15`). `tu.sql` consumers: none found.
- N11. `deposit_return_due_withdrawals` / `_evidence` / `_due` have no `created_by` FK scoping to the tenant (`assert_same_tenant_user` is not called there; `created_by` comes from the session setting). Minor; the template's other record tables do the same.

## What I did not do
- Run `mutations-15r.py` or `migration-15r.py` (they create their own `m15*` clones; I read them instead — the runner's CAUGHT rule (the named check's own FAIL line) is sound; the migration script's P-cases are as the brief says).
- Run the race scripts; read their claims (R1–R10) and the lock order (rate: exclusive on insert / shared on accrual; law row: shared on cite / exclusive on close; deposit row FOR UPDATE + version write) — consistent with the template.
- Test the patch under a non-superuser owner.
