# Review r4 — v5.4.2-15 rewrite (deposits at the rule-terms convention) — Fable

Date: 2026-10-12. Artefacts: `patch-15r-frozen-r4.sql` md5 `9dfd0030636bf43ee4da4e9e74acaf84` (matches; identical to `sql/v5.4.2-15-deposits-law-to-core.sql`), `battery-15r-frozen-r4.sql` md5 `ec821be4ed17e5e5669f55404d6314f7` (matches; identical to `tests/v5.4.2-15/battery-15r.sql`). Repo at `d8c3c47`.

How I probed: clone `fable15r4` (TEMPLATE `tally`, TEMP revoked); patch applied strictly — clean; the frozen battery: 333 PASS, exit 0. Then the battery with my probes appended (same transaction, rolled back). Six of the newest mutations through `mutations-15r.py` (M156 M158 M160 M162 M164 M165): 6/6 caught by their named checks. Clone and temp files dropped. Line numbers are the r4 patch's.

## Verdict: READY — no blocking item, no should-fix; two notes

---

## 1. Round-3 fixes verified (each reproduced on both sides)

| r3 finding | Probe on r4 | Result |
|---|---|---|
| Fable S1 — a cited tariff tighter than the statute | t2 category with a 1-average-month tariff under TX residential (cap 1/6 of 1200 = 200; the tariff's figure 100): PS1b `cap_source` statute, cap 200 → REFUSED "above the cited tariff's own amount (100)"; PS2 `cap_source` tariff, cap 200 → REFUSED; PS3 cap 100.00 → ACCEPTED; PS4 100.01 → REFUSED (4225–4253: the tariff's figure is converted through the named part's kind, 4241–4246, and held whatever the source, 4248) | fixed; R51/R52, M162/M163. |
| Codex B3 / Opus S1 — a city deposit omitting cap or source | PR1 under a flat-175 tariff with no cap → REFUSED "the cited tariff states an amount and the law sets no cap, so the cap that applied is recorded" (4227–4231); PR2 cap 175 with no source → REFUSED by `deposits_cap_source_check` (4015–4017: `cap_amount IS NOT NULL ⇒ cap_source IS NOT NULL`) | fixed; R49/R50, M159/M160. |
| Opus B1 / Codex B2 — relabelled or combined trigger | law: usage ratio ≥ 2 under `usage_doubled`. PT1 tariff under code `nsf` with `any_of(usage ratio ≥ 1.01, nsf count)` → REFUSED "cannot be compared with the law's usage_doubled trigger (any_of against ratio)" (3549–3553 relate by shared leaf through `deposit_condition_leaves` 3427–3443; 3579–3581 refuse); PT2 a plain nsf count under `nsf` (no shared leaf) → ACCEPTED as the utility's own; PT3 same code, ratio ≥ 2 → ACCEPTED; PT4 `all_of(law's ratio, nsf count)` — stricter — → REFUSED as incomparable (conservative, as the brief says) | fixed; N32/N33, M157/M158. |
| Codex B1 — coverage spanning an owner change | per-profile-segment coverage (3485–3503), counting only rows whose spans bind the segment | N34–N36, M156 (caught in my sample); not re-probed beyond reading. |
| Opus S2 — lesser-of / greater-of mixing bases | PX1 `lesser_of(1/6 annual, 2 months)` → REFUSED by the insert check (3023–3027); PX2 `greater_of(fixed 500, 2 months)` → ACCEPTED | fixed; X17, M161. |
| Tests (Codex S1) | R47/R48 seasonal, N37–N39 strict/inclusive ratio at the law's value, N40–N43 lesser/greater against a months cap; M164/M165 caught in my sample | present. |

Nothing found that the fixes broke or newly allow: the leaf relation can only add refusals (a tariff trigger sharing no leaf and no code is still the utility's own — PT2); per-segment coverage can only add refusals; the constraint tightening and the tariff-figure hold can only add refusals; X17 narrows the law documents accepted (version-1 scope, stated in the message).

---

## Notes
- N1. Where the law's cap part is `highest_bills` or `seasonal_average` and the cited tariff is in months of billing, the tariff's own figure is not held at the deposit (4241–4246 convert only through `fraction_of_annual_billing` and `months_of_billing`; `v_tamt` is NULL otherwise) and the comparator does not compare it either (the part does not convert to months, 3517–3521). PH1 a 1-month tariff under a highest-bills cap → ACCEPTED; PH2 a deposit citing it, cap = the statute's 100 → ACCEPTED. Right — the recorded basis is the total of the highest bills, not a billing average, so there is nothing to convert — but the comment at 4221–4222 ("months of billing, from the figure recorded (the named part's, where the document caps)") should say that only the two billing-average kinds convert, and R7 should list it with the other "not compared" items.
- N2. `mutations-15r.py` has 166 rows (M166 added after the brief's 165).
- N3. Decisions 1 and 2 are unchanged (R4, R11) and were answered in my r3 report: decision 1 is Ryan's to confirm; I have no evidence the first draft's tests misread him.
