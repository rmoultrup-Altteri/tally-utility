# Independent review: the rule-terms convention proposal

You are one of three independent reviewers (the others are separate models; you will not see their work). Review the proposal at
`/Users/ryanscomputer/code/tally-utility/application/rule-terms-convention-proposal-2026-10-06.md`
(frozen; md5 `4b30e3704881764670d4ee34c199bec3` — check it and say if it differs).

Context you may read (repo `/Users/ryanscomputer/code/tally-utility`, read-only for you):
- `sql/tu.sql` — the current schema (~26,000 lines; PostgreSQL). Grep, don't read whole.
- `sql/v5.4.2-15-deposits-law-to-core.sql` — the draft deposits patch the proposal would rewrite (look at the rule tables, `enforce_deposit()`, `enforce_deposit_return_due_record()`, `enforce_deposit_return_due_evidence()`, `enforce_deposit_event()`).
- `application/deposits-source-survey-2026-10-06.md` — the 10-state survey (29 unholdable shapes).
- `application/texas-only-architecture-audit-2026-09-28.md` — the audit and its §4 order of work.
- `application/deposits-rules-for-the-core.md` — what the core must evaluate.

The decision-maker (Ryan) owns the product; the database is PostgreSQL with RLS; a C# calculation core is planned but not written; nothing is live. Ryan's standing principles are in proposal §1.

## What to do
1. Answer the seven questions in proposal §6, each with a verdict and the reasoning. Ground claims in the files: cite file:line or quote. Where you assert something about PostgreSQL behaviour, say whether you verified it or are reasoning from knowledge.
2. Find what the proposal gets wrong or leaves out — failure modes, integrity lost, operational cost, migration hazards, anything that would make Ryan regret it in two years. Be adversarial but concrete.
3. Give an overall verdict: adopt as written / adopt with changes (list them) / don't adopt (say what instead).
4. Separate findings by severity: blocking, should-change, note.

Do not modify any file in the repo. Do not run anything that writes to the database.

## Output
Write your full review to `OUTPUT_PATH`. Then make your final reply SHORT (under 2,500 characters): the verdict, the blocking findings, and the top should-change items. The file holds the detail.
