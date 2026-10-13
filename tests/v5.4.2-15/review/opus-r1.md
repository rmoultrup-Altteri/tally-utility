# Review round 1 — v5.4.2-15 (rewrite): Opus

**Verdict: not yet.** Three blocking items, all on the tariff side: a tariff looser than the law can be written, and a deposit can be recorded above the statutory cap, while the patch's own text and two battery labels say the database prevents this. Every fix is small. The law table, the citing records, the return-due record and the races are sound in what I tested.

## Frozen artefacts and how I checked them

- patch `patch-15r-frozen-r1.sql`: md5 `988d73eff960db25d503cc2a39d10f3a` (matches; identical to `sql/v5.4.2-15-deposits-law-to-core.sql`)
- battery `battery-15r-frozen-r1.sql`: md5 `595ee401f0cfbc0d9c26f4013a155163` (matches; identical to `tests/v5.4.2-15/battery-15r.sql`)
- Strict application (`search_path=''`, `check_function_bodies=on`) on clone `opus15` of `tally`, with TEMP revoked: it applies cleanly. The battery passes 259/259.
- The embedded schemas parse equal to `law/deposit/deposit.v1.schema.json` and `deposit_tariff.v1.schema.json`. The four facets are registered as described.
- Probes ran in a copy of the battery with my own cases added and a ROLLBACK at the end (scratch `probes-tail.sql`). The labels O1–O10 and D1–D6 below refer to those cases.
- I wrote a mutation harness for 15 guards that `mutations-15r.py` does not mutate (O-M1..O-M15), and ran the battery against each mutant on its own clone.
- All `opus*` databases have been dropped.

---

## BLOCKING

### B1. The statutory cap is never recorded when the deposit says its cap came from the tariff. The claim that "each deposit's own recorded cap check holds a flat amount" is false.

`enforce_deposit` requires a recorded cap only when the law document has one (patch:4006). It then accepts `cap_source = 'tariff'` with any `cap_amount` (patch:4028-4033). `deposits_cap_source_check` (patch:3869-3872) allows a tariff cap under a law row that caps the deposit. Nothing ties a tariff cap to the law's cap.

The comparator does not compare a flat amount at all (patch:3381-3382, R7 at patch:5024-5030). It says the deposit's own check makes up for that. That check holds the principal to whichever cap the writer chose to record, so neither side holds the law's cap.

**Reproduction (O1).** As `tally_app`, the investor-owned utility T2 posts a residential credit-evaluation deposit under the 16 TAC 7.45 row (cap: one-sixth of annual billing). It cites its `residential_senior` tariff (fixed 5000, accepted by N4) with principal 5000, `cap_amount` 5000 and `cap_source` 'tariff'. **ACCEPTED.** The statute's cap is never stated anywhere on the record.

Battery N4's label ("each deposit records the cap that applied and its own check holds it to it") asserts exactly this false thing. The patch happens to pass it because N4 writes only the tariff.

**Fix.** When the cited law document has a `parts` cap, require the statutory cap on the deposit (`cap_source = 'statute'` with its `cap_component`). Where the utility's figure is lower, record it as a second, optional figure, for example `tariff_cap_amount` together with `tariff_id`. Then `principal ≤ cap_amount` holds the law's figure, as recorded by the core. The cheaper alternative is to drop the claim from R7, from the comparator comment and from N4, and record that the database does not hold a flat tariff to the statute. That makes a looser flat tariff a known hole, which I do not recommend.

### B2. The comparator ignores the tariff amount's `of` and `minimum_amount`, so a looser months-of-billing tariff passes as "not looser".

`deposit_tariff_compare` (patch:3416-3438) reads only `amount.months`. The tariff schema's `amount_months` carries `"of": "average" | "highest"` and a `minimum_amount`. The law's 7.45 part is one-sixth of *estimated annual* billing, which is an average. Two months of the *highest* bill is more than that, and so is any months figure with a large minimum. R7 does not list either case as uncompared.

**Reproduction.**
- (O2) T2 writes a `res_hi` tariff (class residential) of `{"months": 2, "of": "highest", "minimum_amount": none}`. **ACCEPTED.**
- (O2b) `{"months": 1, "of": "average", "minimum_amount": {"kind": "amount", "amount": 99999}}`. **ACCEPTED.**

Battery N10 writes a `highest` tariff, but only under a non-residential law with no cap, so nothing tests this.

**Fix.** Compare only `of: average` with `minimum_amount: none`. For anything else, return a reason ("the law's cap is in average months; this tariff's amount cannot be shown to be within it"), or list it in R7 as uncompared and send it to the deposit-side check from B1. Of the two, I prefer refusing, which fails closed.

### B3. A trigger the law names can be loosened by any condition shape the comparator does not recognise, and the deposit side then accepts any observed value.

The comparator (patch:3448-3460) compares a ratio only against a ratio of the same measure, and a count only against a count with an identical window. For anything else it returns no reason, so the tariff is accepted. It never compares `consecutive` or `exclude_disputed`. On the deposit side, `enforce_deposit` treats every combined condition as met (`ELSE true`, patch:4063). R7 mentions "a combined condition" but none of the other shapes below.

**Reproduction.**
- (O3) T2 tariff, `usage_doubled` as `any_of [ratio ≥ 1.01, ratio ≥ 1.02]`, 2 days to pay. **ACCEPTED.**
- (O3b) A T2 additional deposit on that tariff trigger with `trigger_observed` 1.01, where 7.45 needs 2. **ACCEPTED.**
- (O3c) `usage_doubled` as a ratio of a different measure (`final_bill_to_class_average ≥ 0.1`). **ACCEPTED.** This is a plain way to bypass the Texas usage trigger.
- (O4) A ZZ law trigger of 2 late payments in 12 months. The tariff counts 2 in 120 months. **ACCEPTED.**
- (O4b) The tariff counts 1 in a 1-bill window. **ACCEPTED.**
- Control (O4c): 1 in 12 months is refused, as it should be.

This is the "sneaked in" route the brief asks about. It needs no successor row and no remap, only a condition shape the comparator does not read.

**Fix.** Where the law names a trigger code, the tariff's trigger for that code must be comparable, or it is refused. Comparable means the same kind, measure and window, and flags no looser (law `consecutive` true needs tariff true; law `exclude_disputed` true needs tariff true). Otherwise return "the tariff's trigger for X cannot be shown to be no looser than the law's". This is rule 2 applied to the comparator: unknown is not permission. On the deposit side, `ELSE true` is fine only once the tariff side guarantees this.

---

## SHOULD-FIX

### S1. A second application is not a no-op. It re-issues every function, trigger, constraint and comment, which reverts any later patch, while still printing "nothing to do".

The re-run guard (patch:78-81) `RETURN`s from its own `DO` block only. Every statement after it still runs.

**Reproduction.** On `opus15` I replaced `deposit_tariff_close_floor` (standing in for a later patch), then re-applied -15. The function was back to -15's text. The xmin of `enforce_deposit`, `deposits_cap_check` and `a_enforce_deposit_return_due_record` all changed. The patch still printed the -15 notice.

`migration-15r.py` P2 compares row data only (`snap`, migration-15r.py:205), so it cannot see this. That is a check narrower than its claim: "a second application changes nothing".

**Fix.** Do as -18 does, with the whole body inside one guarded block. Or at least stop the script on re-run with `\if`/`\quit`. Or say plainly that a re-run re-installs, must never follow a later patch, and that P2 checks data only.

### S2. The "nothing is live" precondition silently passes when the role applying the patch does not see every tenant.

`deposits` has FORCE row-level security. The precondition counts are plain SELECTs (patch:82-84). The header requires a superuser or BYPASSRLS role (patch:58-59), but nothing checks it.

**Reproduction (O9).** With 15 non-legacy deposits present, the superuser counts 15. A role without BYPASSRLS counts **0**, so the patch would proceed and carry real deposits as citation-less rows.

**Fix.** Raise at the top of the precondition unless `rolsuper OR rolbypassrls` holds for `current_user` (the template's own test, -17:2283).

### S3. A rate "for every category" is held only to the classes of the categories that exist when the rate is written.

`deposit_rate_floor` (patch:3615-3621) uses the classes the tenant's categories map to. It falls back to every class of the state and service only when the tenant has no categories. Adding a category later re-checks nothing.

**Reproduction (O5).** In ZZ, a retail floor is 5% and a household floor is 3%.
- T9 with no categories: a 3% every-category rate is refused (O5a, correct).
- T9 with only a household category: 3% is accepted (O5b).
- T9 then adds a `shop` category mapped to retail (O5c), and `deposit_interest_rate_row_as_of(T9,'ZZ','gas','shop',…)` returns the 3% row (O5d).

Battery F11 ("a rate for every category must clear every class's floor") overclaims.

**Fix.** For a NULL category, always use every class of the state and service. Alternatively, refuse a new category whose class's floor an every-category rate in force does not clear, taking the rate lock.

### S4. A law cap of `unruled` is treated as no cap.

The design (§8) and the schema (`cap_unruled`: "unknown law is not permission") say it is not the same as no cap.
- The comparator compares nothing under `unruled` (patch:3417). **Reproduction (O6):** 48 months of the highest bill under an unruled ZZ cap is **ACCEPTED.**
- `enforce_deposit` requires a recorded cap only for `parts` (patch:4006), so a deposit under an unruled cap needs none.

**Fix.** The comparator returns "the law's cap is not known" for any amount other than `none`. A deposit under an `unruled` cap is refused, or at minimum must record a cap.

### S5. Under a delegation, the tariff's own terms are not held on the record, and its instalments cannot be used at all.

- (O7) A city deposit of 9999 under a 175 flat tariff, with no cap recorded, is **ACCEPTED**. `enforce_deposit` requires a cap only from the law document, and a delegated document has none.
- (O10) `enforce_deposit_instalments_complete` reads the schedule only from the law row (patch:4205). A city deposit taken in instalments under its tariff's schedule (the tariff with instalments is accepted, O8) is refused: "its law row's schedule has 0". The tariff schema's `instalments` are dead for exactly the utilities they exist for.

**Fix.** When `tariff_id` is set and the law delegates, read the cap requirement and the instalment count from the tariff document.

### S6. Tests: the guards the mutation runner does not mutate are mostly not caught.

I mutated 15 guards absent from `mutations-15r.py` and ran the battery on each (scratch `mut.py`). Each line below gives the mutant, what the battery result was, and what else might catch it.

| Mutant | Battery result | Other coverage |
|---|---|---|
| O-M1: close floor ignores `deposit_events` (patch:2956) | **259/259 pass** | none |
| O-M2: combined-cap `cap_other_held` check off (patch:4018) | pass | none |
| O-M3: `cap_basis_amount` check off (patch:4023) | pass | none |
| O-M4: instalments-complete check off (patch:4206) | pass | none; `evidence-txn-15.sh` only writes a correct schedule |
| O-M5: instalment-only-in-the-deposit's-transaction off | pass | `evidence-txn` X2 |
| O-M6: `deposit_rule_citable` ignores span equality (patch:3775) | pass | none |
| O-M7: a count may be fractional (patch:4062) | pass | none |
| O-M9: tariff instalment sum off (patch:3365-3371) | pass | none |
| O-M10: rate READ COMMITTED check off | pass | races R6 |
| O-M11: accrual on a legacy deposit allowed | pass | migration P1f |
| O-M12: `instalment_received` bound off (patch:4800) | pass | none |
| O-M13 / O-M14: withdrawal mutex, due-row version write | pass | races R3 / R4 |
| O-M8, O-M15 | caught (U5/H24, R26) | — |

What this means:
- H13's label names four sources for the floor, but its expected date (2026-11-01) is set by one deposit's posting, so the accrual and return branches are never decisive.
- The instalment flow (`received_at_posting`, the schedule count and sum, `instalment_received`) has **no** battery case at all.
- The combined cap, the cap's basis figure, span equality on successor citations, whole counts, and the tariff instalment sum each need a case that only that guard refuses, with the boundary tested on both sides.
- Two battery labels overclaim: N4 (B1) and F11 (S3).

### S7. Contract documents describe the -06 law that this patch drops.

`application/APPLICATION-CONTRACTS.md` AC-24 and AC-25 (lines 241, 243-246) still name `deposit_interest_rate_as_of`, `deposit_accrual_amount`, `deposits_refund_due`, `deposit_refund_trigger_state` and `cap_basis_annual_billing`, the waiver refusal, the day-31 cliff and contiguous periods. `sql/DEPLOY-VERIFICATION.md:264` describes -06 as it stood. Nothing in the database depends on the dropped objects: the only dependent object was the view, and the patch drops it. Update the contract before mirroring.

### S8. A count condition's `event` has no vocabulary.

(D4) A ZZ law row whose trigger counts `"late_paymnet"` is **ACCEPTED**. The schema gives `event` only the `code` pattern. Design §3 calls it a vocabulary. The core will meet event names that nobody defined.

**Fix.** Add a `deposit_count_events` vocabulary and a facet on `$..condition.event`, or an `enum`.

---

## NOTES

- **N1.** A statutory `cap_amount` is not tied to its `cap_basis_amount` (O1c: cap 5000 from annual billing 1200 under divisor 6 is accepted). Computing the figure is the core's job. A record-coherence check (cap = basis ÷ divisor, to the cent) would be cheap if wanted.
- **N2.** The identity freeze (patch:4076-4091) leaves out `instrument_issuer`, `instrument_reference`, `instrument_expires_on` and `notes`. That is probably deliberate, carried from -06, but worth one sentence.
- **N3.** The comment on `deposit_waiver_determinations.waiver_class` (patch:4975) says it is "a waiver class of a state and service (deposit_waiver_classes)". It is actually -06's CHECK of four Texas values, with no foreign key and no state. R6 covers the gap; the comment should not claim otherwise.
- **N4.** The comparator compares the amount only against the caps of the `credit_evaluation` and `tariff` bases. It does not compare against the `additional_trigger` cap, which is the same in Texas, and ignores a `combined` scope. It compares only the `payment_due_days` guard; `not_after_service_months`, `notice_days` and `assess_within_days` are not compared. None matter for the Texas seed, but all belong in R7.
- **N5.** The tariff insert check does not check that a tariff waiver `applies_to: trigger` names a trigger the tariff has. The law side checks the same thing (X9).
- **N6.** The tariff schema's `min_amount` description ("No refund below this amount") is reused for a deposit's minimum amount, where it reads wrong.
- **N7.** The tariff insert check's tenant test, which runs before row-level security, is safe. It only adds refusals, and the RLS WITH CHECK still applies after it. Mutating it is caught by U5/H24.
- **N8.** The races script covers the mutex, the rate lock and the close handshake as claimed. Lock order: deposit row, then law-row share lock, then rate share lock, against rate-insert exclusive and close exclusive. I found no cycle. Citations of the deposit's own row take only the advisory share lock, not `rule_row_cite`, so they are allowed under REPEATABLE READ. That is consistent with R4.
- **N9.** The close floor counts citations of a deposit's own row, which may still be cited after a close (R4). Those citations can therefore only block a close, never protect one. That follows from Ryan's B1 ruling (2026-10-02), but is worth stating in R4.
- **N10.** The template enforces unique component ids (D1–D3 refused) and the waiver reach (D6 refused).

## Answers to the brief, briefly

1. **Migration.** Strict application, one transaction and registration are good. The re-run is not a no-op (S1). The precondition fails open under a role without BYPASSRLS (S2). The drops have no remaining database dependants, but the docs are stale (S7).
2. **Law hooks.** The close floor is right and reads every tenant under the template's sees-all close, but its events branch is untested (S6). The insert check is sound on what it covers; event names are unchecked (S8).
3. **Tariff side.** B1, B2, B3 and S4. A category cannot be remapped (C7), and successor and overlapping tariff rows go through the template's check. Another utility's data is invisible through row-level security.
4. **Rate floor.** Fixed rates, by-hold lists and reference rates behave as stated. The every-category rate is the gap (S3). The settled-accrual check, the lock and READ COMMITTED are as claimed (races R5/R6).
5. **Citing records.** Sound. Under a delegation, the tariff's cap and instalments are not on the record (S5).
6. **Tests.** See S6. The battery labels N4, F11 and H13 claim more than they prove.
