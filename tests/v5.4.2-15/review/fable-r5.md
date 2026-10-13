# Review r5 — v5.4.2-15 rewrite — Fable (delta on round 4)

Date: 2026-10-12. Artefacts: `patch-15r-frozen-r5.sql` md5 `fb44ecc041cb2f6004171dd3723962bb` (matches; identical to `sql/v5.4.2-15-deposits-law-to-core.sql`), `battery-15r-frozen-r5.sql` md5 `1c93db1658445380739edd198b0e3543` (matches; identical to `tests/v5.4.2-15/battery-15r.sql`). Repo at `7d66a09`. `mutations-15r.py`: 166 rows.

How I probed: `diff patch-15r-frozen-r4.sql patch-15r-frozen-r5.sql` read whole (three hunks); clone `fable15r5` (TEMPLATE `tally`, TEMP revoked), patch applied strictly — clean; battery 334 PASS, exit 0; M167 through the runner: caught at R53; five probes appended to the battery (same transaction, rolled back). Clone and temp files dropped.

## Verdict: READY — the delta does not change my round-4 verdict

## The delta, verified
1. **Opus r4 S1 — a category with a tariff in force must cite it** (patch 4150–4158: with `tariff_id` NULL and a category, `rule_tariff_row_as_of` is asked; a row in force refuses). Probes on t2 (TX investor-owned, residential law cap 1/6 annual):
   - P1 category `fwith` (flat-150 tariff in force), `tariff_id` NULL → REFUSED "the tariff row … is in force for category fwith on 2026-01-15; the deposit cites it".
   - P2 same category, tariff cited, cap 150 from the tariff → ACCEPTED.
   - P3 category `fwithout` (no tariff), `tariff_id` NULL → ACCEPTED.
   - P4 no category, `tariff_id` NULL → ACCEPTED.
   - P5 category `fwith` posted 2019-06-01, before its tariff's start → ACCEPTED (no row in force then; right).
   R53 and M167 cover it; R10/R13 now use categories without a tariff so each is refused by its own guard alone (read in the battery).
2. **Wording** (my r4 note 1): 4231–4232 and R7 (5300–5306) now say that under a highest-bills or seasonal-average law cap a months tariff is neither compared nor held, and that a stricter combined condition or a longer notice is refused (fail toward refusal). Matches the behaviour I probed in r4 (PH1/PH2, PT4).

Nothing broken or newly allowed: the new guard only adds a refusal, and only where a tariff row is in force for the deposit's category on its posting date — a deposit with no category, or a category with no tariff, is as before.

## Notes
- The guard leaves the choice of `cap_source` to the core: with a tariff cited, the tariff's figure already holds `cap_amount` whatever the source (r4 S1 fix), so citing the row is enough.
- Decisions 1–3 unchanged; decision 1 (own closed law row citable after its close) remains Ryan's to confirm, as in my r3 and r4 reports.
