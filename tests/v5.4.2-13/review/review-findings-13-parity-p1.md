# Review round P1 — findings and dispositions (2026-09-30)

**Reviewed:** the frozen parity build, patch md5 `07ced77c92311ae73ffd3f19623ca4f9` (brief: `review-brief-13-parity-p1.md`).
**Reviewers:** Fable and Opus, each on its own database. Both said **"not yet"**.
**Probes:** `p1-reviewer-probes/fable/` (its report is `REPORT.md`) and `p1-reviewer-probes/opus/`. The Opus report arrived as three messages, summarised below.
**Every finding was reproduced on the frozen build before anything changed.**

## Ryan's calls (2026-09-30)

- **A.** Store "the known onset, otherwise half the time since the last test". Done as a known onset on any case plus a fallback chain on window terms.
- **B.** Turn the fixed lists into lookup tables and give window terms a unit. Interest on refunds and payment-plan duties go to -14 as residual R10.
- **C.** Record the core version on the evaluation only, not on holds, approvals, freezes or withdrawals (residual R11).

## Findings

Findings that both reviewers raised independently are merged into one row.

| Finding | Who | Disposition | Battery | Mutation |
|---|---|---|---|---|
| A freeze compared only the cause and anchor. The direction, claimed start and discovering test could differ from the evaluation's, and the evaluation didn't record the test. | Opus F1, Fable F-4 | The evaluation now records `discovering_test_id`. A freeze compares cause, anchor, basis, direction, claimed start and discovering test. | H9, H10, H11 | M26, M27, M28 |
| "The known onset, otherwise half the time since the last test" didn't fit as rows. | Opus F2 | Call A: `claimed_from` (with `claimed_from_evidence`) is allowed on any case; new term kind `claimed_start`; term `priority` builds a fallback chain. | Z1, E18, E19 | — |
| Evaluations, approvals and holds landed on a frozen or withdrawn case, and a late approval cleared `approval_pending`. | Opus F3, Fable F-5 | Each insert reads the case under a share lock and refuses unless it is open. Closing an existing hold stays allowed. | H12, H13, H14, H16, I10 | M29, M30, M31 |
| Window terms could be added to a cited rule afterwards. | Opus F4a, Fable F-1 | Rule rows stamp `recorded_txid`. Terms are accepted only in that transaction. | C15 | M32 |
| A cited rule could be closed retroactively, and a close wasn't stamped. | Opus F4b, Fable F-2 | Refused on or before the latest date any evaluation (its anchor or its own date) or evidence row (its period start) cites the row for. Stamped `closed_at` / `closed_by`. Refused to a role that row-level security narrows. | F13, Z2, C19 | M33, M45, M42 |
| Classes and causes could be rewritten or deleted. | Opus F4c, Fable F-7 | The same immutability guard covers the classes, the causes and the three new vocabularies. | C16 | M34 |
| Holds, approvals and freezes don't name the core version. | Opus F5 | Declined (call C): these are acts by a person, and they are stamped. Residual R11. | — | — |
| Fixed lists: notice-date anchor, windows in days or billing periods, other enforcement conditions; no interest or payment-plan fields. | Opus F6, Fable F-Q1-1…4 | Call B: `backbilling_anchor_bases` (with `rests_on_test`), `backbilling_window_term_kinds` (with `takes_quantity`) and `backbilling_enforce_conditions`; terms carry `quantity` and `unit`. Interest and payment plans are residual R10. | Z1, C12, C14 | M04, M43, M44 |
| A case or evaluation could name another meter's test or deployment. | Fable F-3 | Same-meter checks on the case (discovering test, evidence deployment) and on the evaluation (discovering and governing test, deployment). | E16, E17, F11 | M35, M36, M37 |
| A withdrawal could rewrite the case. | Fable F-6 | A withdrawal changes only status, reason and notes. | H15 | M40 |
| Evidence could cite another state's or service's rule. | Opus F7 | Must match the evaluation rule's state and service. The evaluation's rule must match the meter's service. A cross-state meter is residual R13. | F12, F14 | M38, M39 |
| Caller-set `updated_at` on insert. | Opus F8, Fable P12 | Stamped. | E1 | M41 |

**Not a finding.** Fable's P22 (`months = 0` accepted) is superseded, because `quantity > 0` is now a CHECK.

## Verified on the revision

| Artefact | md5 |
|---|---|
| Patch, 2,567 lines | `6a773f19d1a69b7b58821a41c5f3f713` |
| Battery, 1,070 lines | `a158e562bf9d16476c8d65707c8afdcf` |
| `mutations-13.py` | `82bd2e2c6785d2011cdedefeb8980883` |
| `evidence-txn-13.sh` | unchanged |

**Results:**
- Strict apply twice: clean.
- **Battery: 99/99 PASS.**
- **X1 PASS.**
- **Mutations: 45/45 caught.** M16 was first rewritten against the wrong comparison and missed. It was re-pointed at the class check and caught; the battery did not change.
- Regressions: **28 / 58 / 41 / 116**, unchanged.

**Reviewer probes re-run on the revision:**
- Every probe that still reaches its target is refused: Opus p1, p2 (after its evaluation records the test), p3 and p4; Fable P1–P4 and P8.
- Fable's P3c, P6 and P10 now stop at an earlier refused step, so they never reach their target. The battery covers each on real rows: E17, H12/H14 and H15.

**Stopping rule:** no further open-ended round. The revision is ready to mirror.
