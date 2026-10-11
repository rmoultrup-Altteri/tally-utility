# Review round 4 (delta) — v5.4.2-18 (Fable)

Frozen r4: patch md5 `08e037236a0692827b090b327cc8400b` (877 lines) equals the repo's `sql/v5.4.2-18-backbilling-rule-terms.sql`; battery unchanged (`294ea5f8…`). The r3→r4 diff is exactly the brief's: the delegation's cause-fact comparison (patch:247-255 requires a protected row of the same cause in force over the delegation's dates; 258-260 compares against every overlapping one) and the closing NOTICE's row count.

## Verdict: READY. The r3 S1 fix is as suggested and I found nothing it broke.

Confirmed:
- strict apply on a clone of `tally` (NOTICE: "16 rows on the convention"); battery-18 107/107; batteries 09–17; lawfiles-17 W1–W5; all pass on the migrated clone.
- migration-18.py with PATCH18 = frozen r4: 54/54 — P3's fixtures still adopt (the historical unprotected meter_error 1990–2000 finds the historical protected chain row 1990–1995 as its overlapping twin, equal facts), P7am (no twin) and P7an (a twin that began on another day) pass.
- My r3 probe re-run on r4: the historical unprotected rate_misapplication row 1991–1992 with no protected row in force is now refused — "no protected row of the same cause is in force over its dates … nothing to be compared with" — and the table is untouched.
- A new probe: a delegation 2003-01-01..2004-07-12 whose only overlapping protected row (2003–2004) carries different cause facts is refused with "the facts about its cause … differ" (the EXISTS now bites with an overlap match, not a same-start match).
- The r3 mutation suite finished 97/97; the r4 suite (100) result is appended below.

## Notes (nothing to fix)
- "Compares against every overlapping protected row": a delegation spanning a change in the protected row's cause facts is refused rather than split. That is the fail-closed answer; the migration's fixtures never need it. If it ever does, the row is closed and re-written by a reviewed migration, as R10's HANDOFF line implies.
- The twin query reads the other rows' OLD columns inside the same UPDATE statement; all rows are filled by one statement, so every twin is seen pre-fill regardless of row order. Fine.
- The `'protected'` literal in the twin query is Texas-gas vocabulary; the migration refuses any other state/service first, so it cannot misfire.
