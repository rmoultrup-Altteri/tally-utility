# Review round 4: v5.4.2-18 (Opus, Fable: a delta check; Codex: the whole patch, first review)

**Frozen r4** (`/Users/ryanscomputer/code/tally-utility`): patch `tests/v5.4.2-18/review/patch-18-frozen-r4.sql` md5 `08e037236a0692827b090b327cc8400b` (877 lines); battery `battery-18-frozen-r4.sql` md5 `294ea5f8814fc1aa3695d1f93be505fb` (unchanged from r3). Briefs: `review-brief-18-r1.md` (the full questions), `-r3.md`; dispositions `review-findings-18-r1.md`.

**r3 -> r4 (Opus r3 S1 = Fable r3 S1, plus a cosmetic):** the delegation's cause-fact comparison now REQUIRES a protected row of the same cause in force over the delegation's dates (it raises "nothing to be compared with" when none) and compares against every overlapping protected row, instead of raising only when a same-start row differs. The closing NOTICE counts the adopted rows. Tests P7am (no twin), P7an (a twin that began on another day is still the twin); mutations M99–M101; 100 mutations, all caught. `diff patch-18-frozen-r3.sql patch-18-frozen-r4.sql` is the whole change.

Opus and Fable: confirm the change and look only for what it broke (including the P3 fixtures). Codex: review everything (this is your first round); write probes as .sql files in `tests/v5.4.2-18/review/codex-r4-probes/`. R10 (delegations) is Ryan's to confirm, not yours. Same output rules.
