# Review round 5: v5.4.2-18 (Opus, Fable, Codex: a delta check of what Codex's r4 review found)

**Frozen r5** (`/Users/ryanscomputer/code/tally-utility`): patch `tests/v5.4.2-18/review/patch-18-frozen-r5.sql` md5 `ee7ccdfb56da2f0fa8ac717bce421d81` (890 lines); battery `battery-18-frozen-r5.sql` md5 `84d50708415062f8667f2952b24afeb6`. Briefs: `review-brief-18-r1.md` (the full questions), `-r4.md`; Codex's r4 review: `codex-r4.md` and `codex-r4-probes/`. `diff patch-18-frozen-r4.sql patch-18-frozen-r5.sql` is the whole patch change.

**r4 -> r5 (Codex r4 B1, B2, S1, reproduced on a pre-18 clone by the author, then fixed):**
- B1: a legacy window-term priority above 8 (valid under -13) aborted adoption. The schema's priority maximum is removed (any positive integer, as -13 allowed). Battery D40 now refuses 0, D40b accepts 9. Test P8, mutation M66 (re-pointed).
- B2: a delegated row's own anchor was cleared by the fill without being compared. The migration now stops (before touching anything) if a delegation's anchor differs from its protected twin's (same cause, overlapping dates). Test P10, mutation M104.
- S1: a repeated legacy outcome (`['fast','fast']`) aborted adoption. The builder, the adoption check and the twin comparison now treat outcomes as a set. Test P9 (including delegation/twin pairs with repeats on either side), mutations M102, M103, M105, M106.
- Cosmetic (Opus r4 note): "in force over its dates" reworded to "overlapping its dates".
`tests/ci.sh` passes; 105 mutations, all caught.

Everyone: confirm the three fixes and look for what they broke. R10 (delegations) is Ryan's to confirm, not yours. Same output rules as r4. Write reports to `opus-r5.md`, `fable-r5.md`, `codex-r5.md`; Opus and Fable use their own database prefixes and clean up; Codex writes probes to `codex-r5-probes/` and the author runs them.
