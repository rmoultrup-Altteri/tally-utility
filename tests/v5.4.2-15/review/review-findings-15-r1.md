# v5.4.2-15 review round 1 — findings and dispositions

Frozen hash: patch `4f9468eb257d4423b88a545c157d6ed4`, battery `e2497c40e5a3ffb13464be9137ce0e58` (brief: `review-brief-15-r1.md`).
Reviewers: Opus (subagent, ran probes), Fable (subagent, ran probes), Codex (`gpt-6-astra`, static; its sandbox cannot reach Docker, so the main session ran its five scripts).
**All three verdicts: "not yet".** Every finding below was reproduced by the main session on a fresh clone (`rev15_main`) before being accepted. The probes are under `/private/tmp/claude-501/review15-{opus,fable}/` and in the session scratchpad (`codex-R1..R5.sql`).

Reviewer IDs: Opus F1–F12, Fable F-1..F-11, Codex R-1..R-5.

## A. Fix in round 2 (record integrity, or a gap with one obvious shape)

| # | Finding | Reviewers | Reproduced | Disposition |
|---|---|---|---|---|
| A1 | The one-live-due-row mutex is a bare `FOR UPDATE`. Under REPEATABLE READ two live due rows commit, and a refund can cite a row a concurrent transaction withdrew | Opus F1, Fable F-1 | yes: 2 live rows; refund joined to the withdrawal | Row-version mutex: the due-row and withdrawal triggers UPDATE the deposit row (as -10/-13), so an RR racer fails on serialisation. Add RR legs to `due-mutex-15.sh` |
| A2 | The rate backdating guard races the accrual job: neither side locks | Fable F-2 | yes: rate 2026-02-01 and a Jan–Mar accrual at the old rate both commit | The accrual locks its cited rate row FOR KEY SHARE; the rate insert locks same-key rate rows FOR UPDATE under a READ COMMITTED pin. State the lock order (rate rows → deposit row). Add a race leg |
| A3 | `deposits_trigger_basis_required_check` names `additional_trigger`; `deposits_legacy_interest_check` and `post_deposit_event()` name `legacy_unknown` | Opus F4, Codex R-1 | yes: a new triggered basis refused | `deposit_bases.requires_trigger`, checked in `enforce_deposit`; the legacy branches read `insertable = false`. Battery L5 widened to every deposit CHECK and function |
| A4 | `account_closed` evidence accepts any state event of the customer, of any kind or date | Opus F5, Codex R-4, Fable F-9 | yes: an initial `active` event, and one from before posting | The reason row carries the statuses that qualify (vocabulary, not a literal); the event must be one of them and dated on or after posting |
| A5 | `deposits.created_at` is whatever the caller sends (inherited from -06) | Opus F11, Codex R-5 | yes: 2001-01-01 stored | Stamped on INSERT |
| A6 | A due row is accepted on a `refund_pending` deposit, where it never shows on the owed list | Fable F-8a | yes | Refused: a started return is not "due" (rules-for-the-core §5.1) |
| A7 | Event chronology: a return dated inside an accrued period; an accrual after the principal was used up; a principal basis above the principal | Fable F-6, F-7 (P4c) | yes (P3a–c, P4c) | Arithmetic, not law: a return's effective_on > accrued_through; an accrual period may not start after exhaustion; principal_basis ≤ principal |
| A8 | The refund-time "no interest is owed" decision records no core version | Fable F-11 | yes (schema) | Optional `calculated_by` and `rule_id` on refund_initiated / refunded / released |
| A9 | Interest rates can't differ by customer class | Opus F6 | yes: duplicate key | Nullable `customer_class` (NULL = every class) on both rate tables, checked against the deposit's class |
| A10 | A binding combined cap can't be recorded | Opus F8 | yes | Record the amount already held (`cap_other_held`); under combined scope, binding means principal = cap − other held |
| A11 | A partial return of principal (the excess over a cap) can't be recorded | Opus F9, Codex R-3 | yes: 40 of 100 refused | A `principal_returned` event of any amount ≤ remainder; `deposit_balance()` subtracts it |
| A12 | The refund-history test has no lookback window and one disqualifier | Opus F7 | yes (schema) | `refund_lookback` quantity and unit (NULL = the whole hold), and disqualifiers as vocabulary rows keyed to the rule. K7's answer becomes a seed row |
| A13 | A return whose evidence is neither a bill nor a state change needs DDL (a time-held trigger) | Fable F-5 | yes (schema) | An evidence kind `deposit` (the deposit's own posting); disconnection stays residual R3 |
| A14 | A due row's reasons aren't tied to the rule's triggers | Opus F10 | yes | Each return reason names the rule attribute that enables it; a reason the rule doesn't enable is refused (a stored attribute, like refund_mandatory) |
| A15 | The test environment: a `TEMPLATE` clone has an empty database ACL, so `tally_app` has TEMP and the trigger-depth fences are open in every clone the batteries ran on | Opus (environment note) | yes: `has_database_privilege(... 'TEMP') = t` on a clone | The run scripts REVOKE TEMP right after cloning; re-run all batteries that way |

## B. Decisions for Ryan

| # | Finding | Reviewers | The question |
|---|---|---|---|
| B1 | An accrual or due row must cite the deposit's posting rule forever: after a law change for deposits already held, the successor rule is refused and the closed rule is accepted outside its range | Opus F2, Codex R-2, Fable P10 | Which rule may a later accrual or due row cite: only the posting rule, only the rule in force on the date, or either? |
| B2 | A utility's own tariff cap (tighter, or where the law sets none) can't be recorded; the cap that bound is hidden | Fable F-3 | Does the deposit record the cap's source (statute or tariff)? Is there a per-utility deposit-policy table? |
| B3 | Waiver reach is one boolean per rule; decision table #53's ranking (family violence reaches §366, the others don't) can't be stored | Opus F3, Fable F-4 | Replace `waivable` with per-class reach rows |

## C. Residuals (stated, not changed)

| # | Finding | Reviewers | Why it stays |
|---|---|---|---|
| C1 | The deposit records the state but not the premise it came from | Opus F12, Fable F-10 | The places table (as -13 R2/R13) |
| C2 | Waiver and customer classes are undated; the rule enumerations (cap kind, method, day count, cadence, measure, instruments, evidence kind) are CHECK lists | Opus F12 | -13 kept the same enumerations as CHECKs; a new value is a reviewed migration plus a core change either way |
| C3 | The recorded cap isn't checked against basis ÷ divisor | Fable F-7 (P4a) | It is the formula, and the rounding convention is the core's. Recording both makes a mismatch visible |
| C4 | A due row that a refund cites can still be withdrawn afterwards | Fable F-8b | By design (§3.5): a withdrawal says the answer was wrong and moves no money; the correction is the deposit's events |

## Also pending from before the round

- The **DIVERGENCE** in the patch header (accrued interest must be credited by the last event). Ryan has not yet confirmed it; no reviewer objected.
