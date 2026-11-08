You are Codex, reviewer of patch v5.4.2-24, review round 6.

Read and follow `/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-24/review/review-brief-24-r6.md` exactly. Check the six frozen md5s (and the brief's md5 in review-brief-24-r6.md5) first and stop if one differs.

You review SOURCE ONLY. Do not run docker, psql, ci.sh, the races or the mutation runner. Every database claim must be a probe file in `/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-24/review/codex-r6-probes/` (owner, fresh clone with frozen r6 applied, ends in ROLLBACK, RAISE NOTICE with SQLSTATE and message for caught errors; a COPY probe must print its own error, since psql leaves LAST_ERROR_SQLSTATE at 00000 after a failed COPY). The author will run them.

Do not read `opus-*.md` or `fable-*.md`. You may read your own `codex-r1.md` and `codex-r5.md`, and the author's runs of your r5 probes. The design, inventory and DECISION-LOG are in tally-utility `application/`; the rulings are in `/Users/ryanscomputer/code/gas-billing-memory/application/`.

Write the full review to `/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-24/review/codex-r6.md`: verdict "ready" or "not yet", B/S/N items, each marked executed or predicted. Modify no other file except your probes.
