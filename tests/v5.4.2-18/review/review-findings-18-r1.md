# v5.4.2-18 round 1: findings and dispositions

Frozen r1: patch `db6179fd…` (703 lines), battery `5a4f0271…`. Reviewers: Opus (not yet, 2 blocking), Fable (ready, 4 should-fix), Codex (could not run: usage limit until 4:15 PM; carried to the r2 round). Full texts: `opus-r1.md`, `fable-r1.md`.

| # | Finding | Disposition in r2 |
|---|---|---|
| Opus B1 | `system_kinds` NULL binds piped-propane/master-meter systems that §101.003(7)(B) excludes (repro: a propane profile resolved the 7.45 row) | Folded: the sixteen bind `{distribution}`; battery L6/L7 (propane, master meter refuse), O11 (a master-meter row sits beside the sixteen), M7; law file and R1/R9. Master meters: out by default, a Kyle question |
| Opus B2 | The eight "unprotected" rows say 7.45 does not reach the class: a delegation, adopted as law (uncapped) | Folded as the default Opus recommended, per standing rules (delegated is not absent; the utility owns regulated values): the eight are `delegated_to_utility` documents citing 16 TAC 7.45 with the note whole; the adoption check demands it and demands the old columns claimed nothing; the fill clears their anchor facet. R10. **Meaning changes: Ryan to confirm** |
| Opus S1 / Fable S3 | Why §7.45 reaches utilities under a city's original jurisdiction | R8 cites the preamble's order to every gas distribution utility and its carve-out for conflicting municipal standards, which the database cannot express per premise (Kyle question). Value unchanged (NULL) |
| Opus S2 | River authorities are gas utilities under 101.003(7); R1 said political_subdivision/special_district "find no row" as right | R1 now says the statute would bind them and the lookup fails closed |
| Opus S3 | `qualifying_outcomes` has no canonical order | Folded: insert check (byte order), X12/X13, builder sorts, adoption check compares as a set, mutation M90 |
| Opus N1 / Fable N1 | The adoption check's anchor-strategy comparison is vacuous in the trigger path | Removed the comparison; the check's comment says the template guards the facet; P7 now calls the check in the trigger's row shape |
| Opus N2 / Fable N4 | Fixed database and /tmp names | Per-process suffixes in migration-18.py, mutations-18.py, run-battery-18.sh |
| Opus N3 | G4 narrower than its claim | G4 sweeps every comment and every function body but the adoption check's |
| Opus N4 | Some citations are not law | R4 says so; the law file carries real clauses when rewritten |
| Opus N5 / Fable N2 | Preconditions; table-level atomicity only | Header states superuser/BYPASSRLS, READ COMMITTED, the surviving hook functions after an abort, fail-closed on a basis v1 does not name |
| Fable S1 | A non-Texas legacy row would be silently bound to 7.45's owner types | Folded: the migration refuses any legacy row that is not Texas gas, naming it; P4 is that abort; P3 uses historical Texas rows |
| Fable S2 | Two examples out of canonical order | Reordered |
| Fable S4 | Test gaps (a)–(d) | L5 (cooperative), O9/O10/O11 (subset overlap; a city-type delegation and a master-meter row beside the sixteen), P3 closed legacy row with stamps, P7 call shape |
| Fable N3 | The basis vocabulary's comment | Rewritten; G7; mutation M93 |
| Fable N5 | maxItems 8 vs seven kinds; the adoption machinery is untestable after the mirror | Noted (R6) |
