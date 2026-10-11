# v5.4.2-18 review round 5 (delta) — Opus

Hashes match: patch r5 `ee7ccdfb…` (= `sql/v5.4.2-18-…` in the repo), battery r5 `84d50708…` (= repo battery). `diff r4 r5` is the whole change: the B2 pre-flight, DISTINCT in three outcome expressions, the priority `maximum` removed, and two comment/message rewordings.

## Runs
- Strict apply (`search_path=''`, `check_function_bodies=on`) of the frozen r5 patch on a fresh clone of `tally`: OK, NOTICE "16 rows".
- The frozen battery, run by hand: exit 0, 107 PASS. D40 (0 refused) passes; D40b (9 accepted) succeeds. The battery's ROLLBACK leaves 16 rows.
- `PATCH18=<frozen r5> migration-18.py`: 60 PASS, all pass, including P8a/b, P9a/b and P10a/b.
- Codex's three probes, re-pointed to an `opus18` clone, run once with the embedded r4 patch and once with r5 swapped in:

| probe | r4 | r5 |
|---|---|---|
| b1 priority 9 | aborts: "must be at most 8" | adopts (17 rows) |
| b2 delegation anchor | adopts, `REPRODUCED B2` (the anchor is lost) | aborts at the pre-flight, naming row …1802 (codex_notice_date vs discovery_date) |
| s1 `['fast','fast']` | aborts: "items must be unique" | adopts (17 rows) |

## Verdict: READY (R10 is still Ryan's)

All three fixes are confirmed. I found nothing that the fixes broke.

### What I checked for breakage
- **B1.** I checked whether the validator now accepts more than it should, using `rule_terms_errors` on the registered schema. `9`, `1e1` (stored as 10) and `2147483648` are accepted. `1.0` is refused by -17's canonical-number rule, and `1.5` is refused as not an integer. Because `1.0` is refused, removing the cap does not open a way past the duplicate-priority check (that check groups on `t->>'priority'` as text). The law file `law/backbilling/backbilling.v1.schema.json` is equal, as JSON, to the schema in the patch. No other text still says "at most 8".
- **B2.**
  - The pre-flight sits after the idempotency return and before the identity hash and every write.
  - It finds delegations with the same LIKE text the builder and the check use, and twins with the same overlap predicate as the check.
  - It is a plain SELECT, so it does not depend on who owns the database.
  - Every other column a delegation drops is still covered by the check: outcomes, units and delivery path against the twin; duty, straddles, enforcement, supervisor evidence and window terms as "claims nothing". The anchor was the only gap, and the pre-flight closes it.
- **S1.** NULL and empty behave as before (an empty array cannot reach the check because of -13's cardinality CHECK, and NULL elements fail its `<@`). Within the twin comparison, DISTINCT is applied to both sides. The builder output still passes the insert check's byte-order rule and the schema's `uniqueItems`.

## Should-fix (non-blocking)
1. **migration-18.py leaks three databases per run.** P8, P9 and P10 clone `m18_g`, `m18_h` and `m18_i` (migration-18.py:265, 275, 293), but the cleanup loop (line 408) drops only `m18_a`–`m18_f`. The server already holds about 180 leaked `m18_{g,h,i}_<pid>` databases, most likely from the mutation runner (each mutation is a run). Add g, h and i to the loop. I dropped the six from today's two finished runs (mine and one other); the rest are left for the author.

## Notes
2. **The priority now has no upper bound.** The schema accepts 10^23. Nothing in the database casts it, but the legacy column was int4, and a C# core reading it into `int` would overflow. `"maximum": 2147483647` would keep B1 fixed (it matches -13's column) and bound what the core reads. Optional.
3. **The pre-flight's HINT can't fix every case it catches.** Probe E1: a delegation dated 1800–1810 overlaps two successive protected twins (1800–1805 with discovery_date, 1805–1810 with a different anchor). The pre-flight correctly stops the patch, naming the second twin. But no single anchor equals both twins, so "set it on the delegation" cannot work; the delegation has to be split at the twins' boundary. The same is true of r4's facts check. The HINT could say "or split the delegation at its twins' boundaries".
4. **The adoption check's own comment doesn't point to the pre-flight.** The comment at lines 242–246 says the fill has already cleared the anchor. The check itself never compares a delegation's anchor; only the migration's pre-flight does (M104 tests that). One line pointing to the pre-flight would stop someone reading the check alone from thinking it is complete.

Clean-up: `opus18r5` and `opus18probe` dropped; I also removed a stray `/tmp/opus_s.json` (left from an earlier round, dated 9 October) from the container. No repo file was touched apart from this report.
