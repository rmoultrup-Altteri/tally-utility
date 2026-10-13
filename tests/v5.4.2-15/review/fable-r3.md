# Review r3 — v5.4.2-15 rewrite (deposits at the rule-terms convention) — Fable

Date: 2026-10-12. Artefacts: `patch-15r-frozen-r3.sql` md5 `0a13969608d7360dff2ae468a90b86d4` (matches; identical to `sql/v5.4.2-15-deposits-law-to-core.sql`), `battery-15r-frozen-r3.sql` md5 `0f6ae2ce52c38492ec3fc31ce09b0593` (matches; identical to `tests/v5.4.2-15/battery-15r.sql`). Repo at `a471982`.

How I probed: clone `fable15r3` (TEMPLATE `tally`, TEMP revoked); patch applied strictly — clean; the frozen battery: 315 PASS, exit 0. Then the battery with my probes appended (same transaction, rolled back). Six of the newest mutations through `mutations-15r.py` (M139 M140 M143 M147 M150 M154): 6/6 caught by their named checks. Clone and temp files dropped. Line numbers are the r3 patch's.

## Verdict: READY — no blocking item; two should-fixes (one narrow guard, one decision for Ryan) and notes

---

## 1. Round-2 fixes verified (each reproduced on both sides)

| r2 | Probe on r3 | Result |
|---|---|---|
| Fable B1 — city's cap held to nothing | PO1 `cap_component "zzz"` under the delegation → REFUSED "sets no cap, so there is no cap part 'zzz'" (4170–4172); PO2 cap 999999 under a flat-175 tariff → REFUSED "above the tariff's own amount (175)" (4190–4194); PO3 175.01 → REFUSED; PO3b 175.00 → ACCEPTED; PO4 city tariff 2 months, basis 100: cap 200.00 ACCEPTED, 200.01 REFUSED, no basis REFUSED (4184–4188) | fixed, boundary at the cent. R35–R39, M142–M145. |
| Fable S1 — class coverage over the range | PG1 tariff 2020–2022 with the class's only law row 2020–2021 → REFUSED "no law is known for the class gap … over {[2021-01-01,2022-01-01)}" (3454–3460); PG3 2020–2021 → ACCEPTED | fixed; N30/N31, M155. |
| Fable S2 — highest_bills / seasonal parts | PB6 highest_bills basis 100, cap 99999 → REFUSED "(100, from 100.00)"; cap 100 → ACCEPTED; seasonal ×2 basis 100: 200.01 REFUSED, 200.00 ACCEPTED (`deposit_cap_part_figure` 4007–4018) | fixed; R42/R43, M141. |
| Fable S4 — the law's other guards | PD8 law's condition without the law's `not_after_service_months` → REFUSED "does not carry the law's guard {…}" (3546–3551); PD8b carried exactly → ACCEPTED | fixed; N28, M148. |
| Opus B1 — lesser-of lifted by the larger part | PL1 lesser_of(fixed 50, 3 months), naming the months part, basis 100, cap 300 → REFUSED "(50, from 100.00)" (4155–4160); cap 50 → ACCEPTED | fixed; R40/R41, M140. |
| Opus B2 — looser trigger under another code | PD9 the law's count under code `zz_nsf_history`, 2 in 12 → REFUSED "fires at 2 … where the law waits for 3" (3505–3509 match by measure) | fixed; N27, M147. |
| Codex B2 / Opus S3 — category-less rate, class with no law | PC7 ZZ category-less 9% while a class has no row → REFUSED naming the classes (3710–3724); PC8 a TX city's category-less 0% → ACCEPTED (delegations are rows) | fixed; F19/F20, M154. |
| Codex B3 — instalments after a flush | `deposit_instalments_check` (4354–4378) now runs from both deferred triggers (4396–4405) | I6/I7, M139/M153; not re-probed. |
| re-run / plain role | header 57–60 states the psql-only skip; the role check is unchanged from r2 | fine. |

Nothing found that the fixes broke or newly allow. The guard-carried-identically rule and the by-measure matching are both conservative (they can only add refusals); the cap block's new branches only add refusals; coverage per class only adds refusals.

---

## Should-fix

### S1. A cited tariff that is *tighter* than the statute is not held when the deposit records the statute's cap

The tariff's own amount is held only on the `cap_source = 'tariff'` branch (4177–4195), and a months tariff only where the document sets no cap (4181: `CASE WHEN … 'parts' THEN NULL`). So under a law cap, a utility whose own filed tariff is tighter can record the statute's figure:

```
t2 category res_m: tariff 1 month of average billing (under TX residential, cap 1/6 annual)
PS1b deposit citing that tariff, cap_source STATUTE, part c1, basis 1200 (so the tariff's own figure is 100), cap 200, principal 200 => ACCEPTED
PS2  same, cap_source TARIFF, part c1, basis 1200, cap 200 => ACCEPTED   (4181 makes v_tamt NULL)
```

Both figures are on the record: for the law's `fraction_of_annual_billing` part the basis is annual billing, so the tariff's months are `basis / 12 × months`; for a `months_of_billing` part the basis is monthly billing already. For a `fixed` tariff amount the figure is in the tariff. Hold `cap_amount ≤` the cited tariff's figure whenever a tariff row is cited and its amount is `fixed` or `months_of_billing` (with the conversion by the named part's kind), regardless of `cap_source` — the same shape as 4190. Not blocking: the statute is still held, R7 claims only what the delegation path does, and charging above one's own filed tariff is a tariff breach the core can audit from the record. Add R cases both sides.

### S2 (decision for Ryan; unchanged). A deposit's own closed law row stays citable for dates after its close

Decision 1 of the brief; R4 (5194–5202) states it. The coordinator asks whether I think the first draft's tests misread him. I have no evidence either way — only that B1's words ("a later law reaches deposits already held") read to me as "the successor governs later periods", and the database today lets either row be cited for a period after the close. That is a one-question decision for Ryan; the tests can prove whichever answer he gives. Not blocking.

---

## Notes
- N1. The guard rule is "carried identically" (3546–3551): a tariff guard that is *stricter* for the customer is refused — PD8c (`not_after_service_months` 6 where the law says 12) → REFUSED. Conservative and stated in R7 ("must be carried identically"); a numeric compare per kind would let it through, if ever wanted.
- N2. `mutations-15r.py` has 155 rows (M155 added after the brief's 154).
- N3. The r3 battery defines a ZZ class `hb`; my probe collided with it once (my error, renamed).
- N4. My PF1 probe (own closed row cited after its close) now errors on my own subquery (the r3 battery closes a second household row for A22), so it proves nothing this round; the behaviour is the stated R4 one and S2 covers it.
- N5. `deposit_rate_floor` (3710–3724) now refuses a category-less rate when *any* class of the state has no law row for the utility's owner type — including a class the utility will never serve. Right under "unknown law is not permission", and the message names the classes; worth a line in the column comment so an operator knows why a class they never heard of blocks their rate.
- N6. R7 (5216–5232) now says what the comparator holds and what it does not; it matches the code as probed (highest months, minimum amount, unruled cap, count window/flags, other guards, matching by measure, coverage per class, lesser-of least computable figure, delegation cap to tariff amount).
- N7. Decision 2 (a partial return needs no due row) is stated in R11; accepted.
