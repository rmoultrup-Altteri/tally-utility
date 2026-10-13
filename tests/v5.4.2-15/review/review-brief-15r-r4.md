# Review round 4: v5.4.2-15 (rewrite)

Same job and rules as before (`review-brief-15r-r1.md` … `r3.md`). Round 3: Fable said **READY** (two should-fix), Opus **not yet** (one blocking, two should-fix), Codex **not yet** (three blocking). Reports: `opus-r3.md`, `fable-r3.md`, `codex-r3.md`, Codex's probes in `codex-r3-probes/`. Output files: `opus-r4.md` / `fable-r4.md` / `codex-r4.md`.

**Frozen artefacts (round 4)** — check the hashes:
- patch `tests/v5.4.2-15/review/patch-15r-frozen-r4.sql` — md5 `9dfd0030636bf43ee4da4e9e74acaf84`
- battery `tests/v5.4.2-15/review/battery-15r-frozen-r4.sql` — md5 `ec821be4ed17e5e5669f55404d6314f7` (333 checks)
- tests: `migration-15r.py`, `mutations-15r.py` (165 mutations, all caught), `races/due-mutex-15.sh`, `evidence-txn-15.sh`, `fail-first.py` (every block passes alone).

## What changed, by round-3 finding (verify; do not trust this list)
- **A combined or renamed trigger escaping the comparison** (Opus B1, Codex B2): triggers are related by code OR by sharing a *leaf* (`deposit_condition_leaves`: a usage ratio of the same measure, a count of the same event) through any all_of / any_of, whatever the unit. A related pair is compared only when the conditions are identical, or both simple ratios of one measure, or both simple counts of one event over one unit; anything else is refused as incomparable. N32, N33.
- **Class coverage spanning an owner change** (Codex B1): the comparator now builds the class's coverage per segment of the utility's profile, counting only law rows that bind that segment's owner type, system kind and jurisdiction. N34–N36 (a utility that is investor-owned then cooperative).
- **A city deposit that omits its cap or its source** (Codex B3, Opus S1): `deposits_cap_source_check` now refuses a cap with no source (the old form let NULL through); where the law sets no cap and the cited tariff states a fixed or months amount, the cap that applied must be recorded. R49, R50.
- **A tariff tighter than the statute** (Fable S1): the cited tariff's own figure (a fixed amount; months converted through the named part's kind) holds `cap_amount` whatever the source. R51, R52.
- **A lesser-of or greater-of cap mixing bases** (Opus S2): refused in the law row's insert check when two parts need different billing figures (annual, monthly, highest bills …); one such part and any fixed amounts are allowed. X17. The comparator's min/max over parts therefore has one convertible part to take; that is why it carries no min/max mutation.
- **Tests** (Codex S1): seasonal arithmetic (R47, R48), the strict/inclusive ratio at exactly the law's value (N37–N39), lesser-of and greater-of tariffs against a cap in months (N40–N43), each with a mutation.

## Decisions made without Ryan (unchanged — challenge them)
1. A deposit's own closed law row stays citable after its close (the first draft's tests under Ryan's B1 ruling accept both that and the successor).
2. A partial return needs no due row.
3. Not done: a count-event vocabulary; the AC-24/25 rewrite (at mirror); a non-superuser owner (refused).

## What to do
Verify each fix; look for what the fixes broke or newly allow; re-check any round-3 finding not on the list; then give a verdict: **ready** or **not yet** with blocking items. Same output rules.
