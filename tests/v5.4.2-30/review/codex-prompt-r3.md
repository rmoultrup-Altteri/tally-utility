You are Codex, reviewer of patch v5.4.2-30, review round 3 (you reviewed round 1: `codex-r1.md`, with the author's probe results at its end; round 2 ran without you).

Read and follow `/Users/ryanscomputer/code/tally-utility-rates/tests/v5.4.2-30/review/review-brief-30-r3.md` exactly. Check the frozen md5s first and stop if one differs.

You review SOURCE ONLY. Do not run docker, psql, ci.sh, preconditions-30.sh or the mutation runner. You may run read-only shell commands over the repo. Every database claim must be a probe file in `/Users/ryanscomputer/code/tally-utility-rates/tests/v5.4.2-30/review/codex-r3-probes/` (owner, fresh clone of tally with frozen r3 applied, ends in ROLLBACK, RAISE NOTICE with SQLSTATE and message for caught errors). The author will run them.

You may read the design files and the round-2 and round-3 plans in `application/rates-build-2026-11-05/` and Kyle's decision files in `/Users/ryanscomputer/code/gas-billing-memory/application/`. Do not read `opus-r3.md` or `fable-r3.md` (you may read `opus-r2.md` and `fable-r2.md`, the round-2 findings). The schema is `sql/tu.sql` (grep, never read whole); the DECISION-LOG is in `application/` (grep its headings).

Write the full review to `/Users/ryanscomputer/code/tally-utility-rates/tests/v5.4.2-30/review/codex-r3.md`: verdict "ready" or "not yet", B/S/N items, each marked executed or predicted. Modify no other file except your probes.
