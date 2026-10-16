# v5.4.2-22 review round 8: findings and dispositions (2026-10-16)

**Verdicts: Opus ready, Fable ready**, neither with a should-fix item. Codex waived by Ryan for the rounds after r5.

- **Opus** re-ran everything on its own clone (strict apply twice, battery 167, CR1–CR20, 30 PASS). It probed each grant, unique-index column and lock mode the paragraph names.
- **Fable** probed the bare-SELECT lock paths, Opus's one-statement shape, and its control.

Both found nothing false in the lock-order paragraph. Ryan asked that the notes be fixed before the mirror rather than carried into -23's header.

| # | Note | Who | Disposition in r9 (comments only) |
|---|---|---|---|
| 1 | "FOR UPDATE by ... a bare SELECT ... FOR NO KEY UPDATE" names the wrong mode (it is its own mode, with the same conflicts here) | Opus N1 | The head's list says tally_app may lock it by a bare SELECT in any FOR mode, its UPDATE grant on one column being enough. That also covers FOR SHARE and FOR KEY SHARE (Opus N2). |
| 2 | tally_void holds the grant but cannot log in and runs only inside the void: a privilege, not a path | Opus N2, Fable N1 | Said so. |
| 3 | A DELETE of a users or tenant row is the owner's only, and refused | Opus N3 | The DELETE leaves the list of ways to take the row FOR UPDATE: "Only the owner may DELETE them, and the delete is refused". The author checked that only `tally` holds DELETE, and that `no_hard_delete` (ENABLE ALWAYS) refuses every delete unconditionally. |

## r9 results (author)

- Strict apply: applies. The r8→r9 diff is comment lines only, and the tests are unchanged from r7.
- `mutations-22.py`: 79/79 caught, one full run.
- `tests/ci.sh`: all pass, 35 steps.
