# v5.4.2-15 review round 2 — findings and dispositions

Frozen hash: patch `026e25d22ca8e25c396168876c795db9`, battery `c5d2ff85f2cfe83432790adbf7ae608e` (brief: `review-brief-15-r2.md`).
Reviewers: Opus and Fable (subagents, ran probes on clones with TEMP revoked), Codex (`gpt-6-astra`, static; the main session ran its three scripts).
**All three verdicts: "not yet".** Every finding below was reproduced by the main session on a fresh clone (`mr2`) before being accepted. The probes are under `/private/tmp/claude-501/review15r2-{opus,fable}/` and in the session scratchpad (`codex-r2-1..3.sql`).

Reviewer IDs: Opus F1–F9, Fable F1–F11 (written here as Fb-n), Codex R2-1..R2-3.

**Q0 — round 1's fixes.** All three confirm these held: A1–A6, A8–A13 and A15, B1, B2, B3, tenant isolation, and the literal sweep. None found a NULL leg left in any CHECK or trigger `IF`. A7, A14, and the combination of A8 with B1 held only partly (I1, I2, I3 below).

## I. Fix in round 3 (record integrity; one obvious shape)

| # | Finding | Reviewers | Reproduced | Disposition |
|---|---|---|---|---|
| I1 | The rule close floor ignores return events (their `period_end` is NULL), so a successor rule a refund cites can be closed under it | Codex R2-2, Opus F3, Fable F2 | yes | The floor reads `coalesce(period_end, effective_on)` |
| I2 | `hold_term_elapsed` passes under a rule that counts BILLS (a Texas due row on time held alone); and a return on time held with no delinquency limit can't be stored | Opus F5, Fable F1, Fb-F9 | yes | Each reason names the measure it rests on (`requires_measure`), checked against the rule's `refund_measure`; the delinquency limit becomes optional under a count |
| I3 | Chronology holds in one order only: an accrual written after a refund or partial return is accepted over its date; an accrual runs past exhaustion; interest is credited before it was earned; an accrual for a future period is accepted today | Opus F2, F8; Fable Fb-F4, Fb-F7 | yes | An accrual may not end on or after any return's date, nor after exhaustion; its principal basis ≤ the principal held at the period's end; a credit ≤ interest accrued for periods ending before it; an accrual's period ends before today |
| I4 | Evidence dated after the due date (a bill, a closure); a refund dated before the due row it settles | Opus F4, Fable Fb-F5 | yes | Evidence on or before `due_on`; an event citing a due row is on or after its `due_on` |
| I5 | Closing a tariff waiver ground races a determination that cites it | Opus F1 | yes (`race-ground-close.sh`) | The determination locks its ground; the close runs only under READ COMMITTED (the rate pattern). Add a race leg |
| I6 | In the rate report, a class-specific utility rate hides another class's missing rate | Codex R2-3 | yes | Coverage per customer class actually held |
| I7 | One waiver class can hold an any-trigger row and a trigger-specific row on the same rule, with no precedence | Opus F9 | yes | Refuse mixing them for one class on one rule |
| I8 | The closure-date check uses the session time zone | Fable Fb-F6 | yes (UTC accepts, Chicago refuses) | Compare in UTC, which no session can change; the premise's own time zone waits for the places table (audit row; a residual beside R8) |

## D. Shapes the schema can't hold — decisions for Ryan

| # | Shape | Reviewers | Source cited | The question |
|---|---|---|---|---|
| D1 | Thresholds for an additional deposit ("2 NSF in 12 months") | Fable Fb-F3 | Kyle's decision table #55 rules 5–7 | A rule part (law) or a utility table (tariff), or both? |
| D2 | A cap built from two parts: "the lesser of 1/6 annual or two months", or "1/6, not over $X / not under $Y" | Opus F6, Fable Fb-F8 | Opus: Texas electric, 16 TAC §25.24 (not verified) | Model cap parts plus a combinator? |
| D3 | A deposit paid in instalments | Opus F7, Fable Fb-F11 | Opus: Pennsylvania Chapter 14 (not verified) | Model it, or accept two deposit rows / leave it residual? |
| D4 | A mandatory PARTIAL return (refund the excess over a cap) tied to a due row | Codex R2-1 | rules-for-the-core §2.2 (refund Alt 4) | A due row with an amount, settled by a partial return? |
| D5 | Waivers that reduce TO an amount or substitute an instrument; disqualifiers with their own window | Fable Fb-F10 | none (hypothetical) | Residual? |
