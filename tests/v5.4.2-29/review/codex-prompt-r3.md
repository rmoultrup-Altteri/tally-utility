You are Codex, reviewer of patch v5.4.2-29, review round 3 (you reviewed round 2: `codex-r2.md`, with the author's probe results at its end).

Read and follow `/Users/ryanscomputer/code/tally-utility-rates/tests/v5.4.2-29/review/review-brief-29-r3.md` exactly. Check the frozen md5s first and stop if one differs.

You review SOURCE ONLY. Do not run docker, psql, ci.sh, reapply-29.sh or the mutation runner. You may run `tests/v5.4.2-29/source-check-29.sh tests/v5.4.2-29/review/patch-29-frozen-r3.sql` and read-only shell commands. Every database claim must be a probe file in `/Users/ryanscomputer/code/tally-utility-rates/tests/v5.4.2-29/review/codex-r3-probes/` (owner, fresh clone of tally with frozen r3 applied, ends in ROLLBACK, RAISE NOTICE with SQLSTATE and message for caught errors). The author will run them.

You may read the round-2 and round-3 plans (`application/rates-build-2026-11-04/v5.4.2-29-r2-plan.md`, `-r3-plan.md`) and your own `codex-r2.md`. Do not read `opus-r1.md` or `fable-r1.md`. The schema is `sql/tu.sql` (grep, never read whole); the DECISION-LOG is in `application/`.

Write the full review to `/Users/ryanscomputer/code/tally-utility-rates/tests/v5.4.2-29/review/codex-r3.md`: verdict "ready" or "not yet", B/S/N items, each marked executed or predicted. Modify no other file except your probes.
