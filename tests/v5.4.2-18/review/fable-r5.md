# Review round 5 (delta) — v5.4.2-18 (Fable)

Frozen r5: patch md5 `ee7ccdfb56da2f0fa8ac717bce421d81` (890 lines), battery md5 `84d50708415062f8667f2952b24afeb6`; both equal the repo copies (`sql/v5.4.2-18-backbilling-rule-terms.sql`, `tests/v5.4.2-18/battery-18.sql`), so the battery runner's copy-from-repo is the frozen battery. `diff patch-18-frozen-r4.sql patch-18-frozen-r5.sql` is exactly the brief's delta: `SELECT DISTINCT o` in the builder (patch:364), the adoption check's law path (:297) and both sides of the twin comparison (:261, :263); the delegation-anchor pre-flight (:413-424); `"priority": {"type": "integer", "minimum": 1}` (:573); two rewordings (:245, :253). Battery delta: D40 re-pointed to priority 0, D40b accepts 9. The registered schema in the migrated clone equals `law/backbilling/backbilling.v1.schema.json` (compared as parsed JSON).

## Verdict: READY. The three fixes do what the brief says and I found nothing they broke.

### Runs (databases `fable18pre`, `fable18probe`, clones of `tally`; dropped at the end)
- Strict apply (search_path '', check_function_bodies on) of the frozen r5 patch on a clone of `tally`: NOTICE "16 rows on the convention". Frozen battery run by hand on it: 107 PASS, 0 FAIL/ERROR.
- `migration-18.py` with `PATCH18` = frozen r5, base `tally`: 60/60 PASS (P1–P10, P7a–P7an).
- Mutations M66, M99–M106 with the repo patch (= frozen r5): 9/9 caught, each at its named check (M66 at P8a; M99, M100 at P7am; M101 at P7an; M102, M103, M105, M106 at P9a; M104 at P10a). M104 is the one that matters most: with the pre-flight disabled, nothing else sees the delegation's anchor, and P10a is the only check that would.

### Codex's r4 probes, reproduced against r4 and r5
Each probe spliced around the frozen r4 and the frozen r5 patch (fixture and tail unchanged; the database-name guard retargeted to `fable18%`), run on one pre-18 clone; every run rolled back (16 rows and the child table remain).
- **B1** `b1-priority-nine`: r4 aborts in the fill — "/windows/adverse/0/priority: must be at most 8" from `rule_row_prepare`; r5 adopts 17 rows. Confirmed.
- **B2** `b2-delegation-anchor`: r4 adopts 18 rows and the probe's own check prints "REPRODUCED B2: distinct notice-date anchor lost without comparison" (1802 ends with anchor NULL, governs delegated); r5 stops at the pre-flight (DO block line 34, before any write): "a delegation drops its anchor, and these anchors differ from their protected twin's … 00000000-…-1802 (unprotected rate_misapplication, anchor codex_notice_date, its protected twin discovery_date)". Confirmed.
- **S1** `s1-duplicate-outcomes`: r4 aborts — "/anchor/qualifying_outcomes: items must be unique"; r5 adopts 17 rows. Confirmed.

### My own probes on r5 (what the fixes might have broken)
- A delegation 1800-01-01..1801-01-01 spanning two protected rows of its cause, one with the same anchor (test_date, second half) and one with another (discovery_date, first half): the pre-flight refuses, naming the delegation once with the differing twin only. The pre-flight's twin predicate (state, service, cause, protected, date overlap) is the adoption check's (patch:247-251, :256-260), so a delegation the pre-flight passes has at least the same twin the adoption check compares outcomes/units/path against; with the same anchor, -13's record guard already made both sides' outcomes-null-ness agree.
- The same fixture without the differing twin: adopted (19 rows); the delegation's anchor is NULL, its twin keeps test_date.
- A law row whose only window term has priority 2147483647 (integer max; -13's CHECK is `priority > 0`, so valid): adopted, the document says 2147483647. With seven term kinds, no kind repeated and `window.maxItems 8`, a priority is only a rank, so an upper bound had nothing to protect.
- Two edge cases I expected S1/B2 to open are closed by -13 itself: `qualifying_test_outcomes = '{}'` (would strip to no outcomes on a test basis) is refused by -13's `cardinality(...) > 0` (v5.4.2-13:713); a delegation with a NULL anchor cannot exist (`anchor_basis NOT NULL`, :680).

### Notes (nothing to fix)
- The pre-flight (:416-420) compares anchors only for rows whose note says 7.45 does not reach the class; an `unprotected` row whose note does not say it is not a delegation and goes to the adoption check's note/class agreement (:215). Consistent.
- The HINT "set it on the delegation (or the twin) first" implies an owner edit under -13's history guard (DISABLE TRIGGER, as the brief's probe recipe does). That is the migration operator's act, not the app's; fine as a hint.
- R10 (whether the delegations' dropped facts are what Ryan wants) remains Ryan's; this round changes nothing there except that an anchor that differs is now refused rather than lost.
