You are Codex, reviewer of patch v5.4.2-23, review round 3.

Read and follow `/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-23/review/review-brief-23-r3.md` exactly. Check the six frozen md5s first and stop if one differs.

You review SOURCE ONLY. Do not run docker, psql, ci.sh, the races or the mutation runner. Every database claim must be a probe file in `/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-23/review/codex-r3-probes/` (owner, fresh clone with frozen r3 applied, ends in ROLLBACK, RAISE NOTICE with SQLSTATE and message for caught errors; a COPY probe must print its own error, since psql leaves LAST_ERROR_SQLSTATE at 00000 after a failed COPY). The author will run them.

Do not read `opus-r3.md` or `fable-r3.md`; you may read every round-1 and round-2 review. The design, inventory and DECISION-LOG are in tally-utility `application/`; the rulings are in `/Users/ryanscomputer/code/gas-billing-memory/application/`.

Write the full review to `/Users/ryanscomputer/code/tally-utility/tests/v5.4.2-23/review/codex-r3.md`: verdict "ready" or "not yet", B/S/N items, each marked executed or predicted. Modify no other file except your probes.
