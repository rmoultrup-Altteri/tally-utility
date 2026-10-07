# v5.4.2-17 review round 3: findings and dispositions

**Frozen:** patch `74c730ed9ceb11b7449f3b373a851000` (3,054 lines), battery `9d91b4852638755db3d1734887d66fab`.

**Verdicts:**
- **Opus:** ready. One should-fix, one note.
- **Fable:** ready. Three notes.
- **Codex:** did not run. The CLI hit its usage limit ("try again at 7:41 PM"). Codex's round-2 blockers (facet-type pairing, union depth, filled documents at adopting registration) were each re-verified in r3 by Opus and Fable, who re-ran the reproductions.

**Reviews:** `review-r3-opus.md`, `review-r3-fable.md`.

| # | Finding | Who | Disposition |
|---|---|---|---|
| 1 | `assert_core_role_invariants()` ignores which roles `tally_core` belongs to. Opus reproduced a membership in a BYPASSRLS role: the assertion passed, and the core could `SET ROLE` past every policy | Opus S1 | **Fixed.** tally_core is a member of no role. K10; M137 |
| 2 | A re-seed is not compared on a column it leaves out, and an `id` it names is ignored | Opus N1 | **Fixed.** A seed names the whole envelope (state, service, the three applicability sets, both dates, citation, kind, version, document) and no id. T4l, T4m; M138, M139. lawc's seeds already did |
| 3 | A strategy version range accepts a non-integer bound (1..1.5) | Fable note | **Fixed.** Bounds are integers. R4p; M140 |
| 4 | A re-seed treats `50.0` as the stored `50` (jsonb), unlike the text-compared close and freeze | Fable note | **Comment.** Deliberate: a seed restates the law, and a number's scale is not the law; a close or a freeze must change nothing at all |
| 5 | One extra catalog read per rule-row write (the facet-type check) | Fable note | Accepted: law rows are few, and tariff rows are written rarely |
