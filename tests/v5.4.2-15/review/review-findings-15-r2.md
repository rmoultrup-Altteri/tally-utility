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

## Citations checked (2026-10-04, after the round)

The reviewers cited D2 and D3 from memory. Both citations were wrong, but each shape exists in real law under another section.

| Item | Cited | What the text says | Effect on the decision |
|---|---|---|---|
| D2 | 16 TAC §25.24 (Texas electric), "lesser of" | §25.24(f) is a single cap: "The total of all deposits shall not exceed an amount equivalent to one-sixth of the estimated annual billing." "Lesser", "greater" and "two months" appear nowhere in it. The two-part cap is in **16 TAC §25.478(e)(1)(A)** (retail electric providers), and it is the opposite operator: "the **greater** of: (i) one-fifth of the customer's estimated annual billing; or (ii) the sum of the estimated billings for the next two months." | Real shape, but not Texas gas: **§7.45(5)(C)(ii) is a single cap** ("shall not exceed ... one-sixth of the estimated annual billings"). If built, the combinator must hold both lesser-of and greater-of. |
| D3 | Pennsylvania Chapter 14 | **52 Pa. Code §56.42** (implements 66 Pa.C.S. Ch. 14; covers natural gas distribution companies; amended eff. 2019-06-01). (b) delinquent account: the customer "may elect" three instalments, 50% on determination, 25% at 30 days, 25% at 60 days; the utility must offer the option. (c) reconnection: 50% before reconnection, 25% at 30 and 60 days. (d) broken payment arrangement: the same. A missed instalment is grounds for termination (§56.81); the customer may pay in full early. | **Verified gas law.** One deposit, a required amount paid on a statutory schedule: the deposit's required amount and its paid amount become separate figures. This is the invasive migration, so decide it now rather than later. |

### New: the Texas gas statute's own additional-deposit trigger is missing

§7.45(5)(C)(ii): "If actual use is at least twice the amount of the estimated billings, a new deposit requirement may be calculated and an additional deposit may be required within two days." Same shape in §25.24(d)(1)(A) for electric.

- The trigger vocabulary (`nsf`, `disconnect_history`, `broken_dpa`) comes from Kyle's #55 rules 5–7. It has no usage trigger. Neither the -15 patch nor `deposits-rules-for-the-core.md` mentions one.
- This is a **parity gap with the statute**, not a hypothetical shape. Proposed: a `usage_doubled` trigger row, plus a Kyle question (K9: why #55 omits it).
- It changes **D1**: the threshold is a ratio of actual use to estimated billing, not "N events in M months". A threshold part built only for event counts would not hold it.

### Schema vs core: which shapes need a migration (discussed with Ryan, 2026-10-04)

Vocabulary values (bases, triggers, classes, waiver classes, disqualifiers, reasons, rates) are rows; a new value is data plus core code. A rule's **shape** is closed (one column per setting on `deposit_rules`, CHECKs listing the kinds), so every D item is a schema change. They differ in cost:

- **Additive, cheap to make later:** D1 (threshold columns or a part table), D4 (nullable amount on `deposit_return_due`), D5 (a window on `deposit_rule_refund_disqualifiers`; new waiver effects).
- **Changes the meaning of existing columns:** D2 (cap moves into parts) is moderate. D3 (required vs paid amount) is expensive: status, interest basis, refund amount and `cap_other_held` all read the one amount.

Sources: [16 TAC §25.24](https://www.law.cornell.edu/regulations/texas/16-Tex-Admin-Code-SS-25-24) · [16 TAC §25.478](https://www.law.cornell.edu/regulations/texas/16-Tex-Admin-Code-SS-25-478) · [16 TAC §7.45](https://www.law.cornell.edu/regulations/texas/16-Tex-Admin-Code-SS-7-45) · [52 Pa. Code §56.42](https://pacodeandbulletin.gov/secure/pacode/data/052/chapter56/s56.42.html)

## Dispositions (2026-10-06)

Ryan adopted the stopping rule on 2026-10-06: model a shape when a real source (a statute, Kyle's tables, our own design) calls for it; record a hypothetical shape as a residual. With it and the standing principles, no D item needed a separate decision. Each line names the rule that settled it.

| # | Built as | Settled by |
|---|---|---|
| I1–I8 | As proposed above, with one change to I3: an accrual may not **span** a partial return (it may follow one) and may not reach a full return; "not past exhaustion" is implied by "basis ≤ the least held over the period", so it has no guard of its own | Integrity fixes |
| D1 | `deposit_rule_trigger_thresholds` (statute) and `deposit_tariff_trigger_thresholds` (utility), each a count in a window or a usage ratio; the deposit cites one plus the observed measure; required where the rule sets one. The tariff row closes like a waiver ground (I5 pattern) | Source: #55 rules 5–7, §7.45(5)(C)(ii). Utility owns its values (R-D1) for #55's configurable thresholds |
| new | `usage_doubled` trigger; TX additional-deposit rules carry ratio 2, payable in 2 days; K9 to Kyle | Source: §7.45(5)(C)(ii). Parity with the statute |
| D2 | `deposit_rules.cap_combinator` (none / single / lesser_of / greater_of) plus `deposit_rule_cap_parts`; the deposit names the governing part's kind. Nested caps (floor and ceiling) are R13 | Source: §25.478(e)(1)(A). Launch scope is not architecture scope |
| D3 | `deposit_rule_instalments` (the schedule); `deposits.received_at_posting` + `deposit_instalments`; `instalment_received` events; held = received. Tariff-only instalment plans are R14 | Source: 52 Pa. Code §56.42. Costly to migrate later, so settled now |
| D4 | `deposit_return_due.amount`; reason `excess_over_cap`; `deposit_rules.refund_excess_over_cap`; settled by `principal_returned` of exactly the amount; a settled partial row stops being live | Source: rules-for-the-core §2.2 (refund Alt 4) |
| D5 | Residual R16 | No source |

Verified on patch `2f528181` (clones with TEMP revoked): strict apply ×2 clean and idempotent; battery **127/127** (group N covers round 2); X1–X2; races R1–R10; mutations **140/140**, each caught at its named check (M93–M144 for round 2); regressions 28/58/41/116/3/99/6; -13 X1.

While building, four guards turned out to be implied by others, so each was folded in rather than kept as an uncatchable check. The new least-held check covers interest before posting and after exhaustion. The commit-time count covers instalments under a rule with no schedule. The receipt bound covers a receipt on a deposit received whole. A rule with no cap has no parts, so the parts check covers a statutory cap under such a rule. Their mutations (M30, M114, M122 and the old M84) were retired or retargeted.

## The source survey (2026-10-06): 29 more shapes

Ten more states' gas deposit rules were surveyed: OK, LA, NM, AR, KS, OH, IL, NY, CA and GA. See `application/deposits-source-survey-2026-10-06.md`. **29 shapes found there cannot be held by the round-2 schema.** Examples: late-payment triggers; Treasury-indexed interest bands; caps on the highest bill or the heating season; runs of consecutive bills; refund thresholds in dollars; periodic recalculation with a tolerance band; Kansas's separate municipal deposit account with January 1 crediting. Kansas K.S.A. 12-822 binds municipally owned utilities directly. This puts the typed-column representation of a rule's shape in question; see HANDOFF.
