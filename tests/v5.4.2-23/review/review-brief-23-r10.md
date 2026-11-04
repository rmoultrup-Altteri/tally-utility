# Review brief: v5.4.2-23 r10 (Codex only) — round 9 plus Opus's and Fable's round-9 should-fixes

**Date:** 2026-11-04. **Kind:** patch review, round 10, Codex only.
Codex was rate-limited during round 9. Opus and Fable reviewed frozen r9 and both said **ready**. Their two should-fixes were folded in, and the result is frozen here as r10, so that Codex reviews exactly what would be mirrored. Do not read `opus-r9.md` or `fable-r9.md`. Every earlier review (`*-r1.md` to `*-r8.md`, `codex-r*-probes/`) is open to you.

## Frozen files (r10; these replace r9's table below)

| File | md5 |
|---|---|
| `tests/v5.4.2-23/review/patch-23-frozen-r10.sql` | `9529d1f0a416f12ab7f49199b1ec3742` |
| `tests/v5.4.2-23/review/battery-23-frozen-r10.sql` | `9127ab84d20c118e893aa9d15673e56a` (identical to r9) |
| `tests/v5.4.2-23/review/cash-23-frozen-r10.sh` | `b77dba8b96637d66100e684af6405237` |
| `tests/v5.4.2-23/review/mutations-23-frozen-r10.py` | `912628a1f71984536ac611f47ade5d9d` |
| `tests/v5.4.2-23/review/older-tests-23-frozen-r5.diff` | `be99c2f963ab9f2177c9f059a4de7e5c` |
| `tests/v5.4.2-23/review/patch-23-r8-to-r9.diff` | `89767fea98e8c239debc75b2f37321cd` |
| `tests/v5.4.2-23/review/patch-23-r9-to-r10.diff` | `a0c77469fcb2775071887b17ce82d6a1` |
| `tests/v5.4.2-23/review/tests-23-r9-to-r10.diff` | `6f869eeadec6cee184781f31f579e974` |

## What changed from r9 to r10

1. **`assert_cash_guard_invariants`** (Fable r9 S1) now refuses if `check_cash_order(text, uuid, timestamptz, uuid, text)` or `check_cash_leaving_order(uuid, timestamptz, text)` is missing, executable by PUBLIC or `tally_core`, or not executable by `tally_app`. Mutation N234 grants the leaving-order check to `tally_core` and is caught at apply.
2. **Race CR28c** (Opus r9 S1): it shows the harm the void check prevents. Without the check, a reissue's void stamped before a take-back moves the take-back's share and leaves an escheated credit holding 10 of the customer's money. It runs before CR28 in the script. N230 is now anchored at CR28c.

The races are now CR1–CR28c with 51 results, and the mutations are 233 (N234 new). Results on r10: strict apply clean twice; battery 409/409; races 51/51; mutations: the changed legs and every apply-stage mutation were rerun and caught (N229, N230, N234 and 32/32 at apply).

Where the r9 brief below says r9, read r10 for the files you review. Your output is `tests/v5.4.2-23/review/codex-r10.md`, and your probes go in `tests/v5.4.2-23/review/codex-r10-probes/` (each runs on a fresh clone with frozen **r10** applied). Everything else below applies as written. Answer the round-8 findings as r9's brief asks, including your own round-8 B1, S1 and S2.

---

## The round-9 brief, for reference

# Review brief: v5.4.2-23 r9 — cash: round 8's findings (the family cap skips the moves within a family, money leaving a family ordered after a take-back, agree() pins each line's figure, the reissue's size in one statement)

**Date:** 2026-11-04. **Kind:** patch review, round 9.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's round-9 files. You may read every earlier review in this folder (`*-r1.md` to `*-r8.md`, `codex-r*-probes/`): r9 answers round 8.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-23/review/patch-23-frozen-r9.sql` | `6651abf9526204f7839cd0986f931275` |
| `tests/v5.4.2-23/review/battery-23-frozen-r9.sql` | `9127ab84d20c118e893aa9d15673e56a` |
| `tests/v5.4.2-23/review/cash-23-frozen-r9.sh` | `c356839ee4f182cbacab4f0c210f7565` |
| `tests/v5.4.2-23/review/mutations-23-frozen-r9.py` | `66caafab1d9dc2730fa041fcc123e82c` |
| `tests/v5.4.2-23/review/older-tests-23-frozen-r5.diff` | `be99c2f963ab9f2177c9f059a4de7e5c` |
| `tests/v5.4.2-23/review/patch-23-r8-to-r9.diff` | `89767fea98e8c239debc75b2f37321cd` |

Today the live copies are identical to the frozen ones. Review the frozen copies. `older-tests-23-frozen-r5.diff` is still every change -23 makes to earlier tests (r9 adds none; `tests/ci.sh` now vacuums the cash tables before each battery). `patch-23-r8-to-r9.diff` is for orientation; review the whole patch.

## What changed since round 8

Fable said "ready"; Opus and Codex "not yet". The merged list is `application/wave2-build-2026-10-15/v5.4.2-23-r9-plan.md`, with "As built" at its end. The call and its reasons are in `application/DECISION-LOG.md` (2026-11-04 -23 r9).

1. **Codex B1: a required reissue refused while the family is over its payment.** Ryan, 2026-11-04, option 1: `check_cash_source`'s cap on a payment and its credits together is not applied when `p_purpose` is `reissue` or `overpayment_credit`, the two moves within the family (the family sum already leaves both out). Every other check on them stays. Codex's 60 case is U1–U1f: the reissue is admitted; a cent out of the reissue or the payment afterwards is refused.
2. **Opus B1: a refund's return stamped before a take-back moving the take-back's share onto an escheated reissue.** New `check_cash_leaving_order(payment, at, what)`: money leaving a family (a refund of the payment or of a family credit moving to voided, nsf or reversed; a family credit's void) is refused for retry (40001; 23514 for a chosen time) when a row under the payment's posting entry was recorded after the move's stamp. Called under the payment's lock the move already takes, from `enforce_payment_immutable` and `enforce_customer_credit_immutable`. Only for a payment with a live overpayment credit. R17 rewritten. Races CR27 (Opus J) and CR28 (a reissue's void). On r8, CR28's void was already refused by r7's share rule; r9 retries it first.
3. **Opus B2 = Fable S1: agree() pins each line's figure.** agree_side now admits a refund of exactly `least(own cap, pool)` and refuses it plus a cent (a cent when it is 0 or less), and refuses a position above it, for every active line, at every agree() site. The payment's own cap is computed in the battery from its draws and the family's shares as recorded. Opus's mA and mB are N232, N233; N207 is now caught first by agree() too (relabelled Y7j).
4. **Opus S1: a reissue's size in one statement.** The size reads the reissue's own side as its amount less its share as recorded, not less its draws. U2/U2a (one data-modifying statement: a reissue of 15 plus a refund of 5 refused; of 20 plus 5 admitted).
5. **Fable S2:** P-G as U3–U3f. **Codex S1:** Z6's preamble says it is a planted-chain endpoint test; Z7 is a 20-deep line made through every guard, checks flushed after each generation, then a refund of the 20th. **Codex S2, Opus S3:** the header's withdrawn exact-cap sentence marked; `enforce_ledger_reversal`'s and `enforce_customer_credit_immutable`'s COMMENTs corrected.
6. **Opus S2, the statistics.** `tests/ci.sh` vacuums `account_ledger, payments, customer_credits` right before each battery, as the mutation runner does. Pinning `customer_credit_draws_as_of` was tried and measured: under Opus's planted "60 pages, 0 rows" statistics, Z6 took 28 minutes with it pinned (beside a mutation run), its self-time 614 s against Opus's 323 s, so the pin was not kept. R21 now says the pins do not make depth independent of the statistics.

## Known limits (accepted; listed so you can judge them, not as findings to rediscover)

- **R22, R23, R24 and option A** as in round 8 (R23's netting across payments and R24's never-closing credit both end with -27).
- **The family cap's skip.** A reissue or an overpayment credit is admitted while the family reads over its payment; what it carries can then be paid out by nothing (U1d, U1e). That is the intent: the move records money the family already holds.
- **Depth under bad statistics (R21).** Real lines are 1–3 deep; the bound is a safety bound.

## Drafting calls to check in particular

- **The skip.** Can a reissue or an overpayment credit, admitted past the family cap, ever let money leave the family beyond what it holds? Is `overpayment_credit` in the skip right, or is only `reissue` needed? (The author included both because the family sum excludes both; the overpayment credit is still capped by the payment's own side.)
- **The leaving order.** Is every move that changes `overpayment_shares` after the fact covered: a refund's return or cancel, a family credit's void, anything else (an escheat move, a donation's undo, an application's undo)? Is the check under the lock every take-back takes? Can it make a legitimate act unrecordable (a retry that can never succeed)?
- **agree()'s payment cap.** Is the battery's formula for the payment's own cap the cap's own, in every shape (a voided overpayment credit, a payment not posted)?
- **The reissue size.** Can its share at insert ever be non-zero?

## Results so far (reproduce them)

- **Strict apply, twice:** clean (the second skips: "already applied").
- **`battery-23.sql`:** 409 checks, all pass, 38–74 s (67 s on the frozen copy) after `VACUUM payments, customer_credits, account_ledger`. U1–U4a and Z7 are new; every agree() site now pins each line's figure.
- **`races/cash-23.sh`:** CR1–CR28, 47 results. CR27 and CR28 are new.
- **Against r8** (`tests/v5.4.2-23/red-r9-against-r8.txt`): U1b refused by the family cap (110 > 100); with U1 removed, U2 admitted; CR27 reproduces Opus J (0 / 10 / 10, R escheated holding 10 of its own); CR28 refused with 23001 instead of retried.
- **`mutations-23.py`:** 232 of 232 caught, each at its named check. The full run (2026-11-04, 52 min, files unchanged throughout by md5) caught 223; the shared container was replaced by another stream's `ci.sh --build` during its last eight, which were rerun with N161 (a race seen not waiting under load; caught when run alone) and N207 (now caught first at Y7j by the exact agree(), relabelled): 9 of 9. N227–N233 are new; N181, N205, N222 re-anchored. After the full run, the `customer_credit_draws_as_of` pin was removed (and its mutation N234 with it); the strict apply, battery and races were rerun on the frozen copy.
- **`tests/ci.sh`:** not yet run on r9. On r8 every step passed except battery -15 (its V23 fixture date expired on 2026-11-02; a test-only fix in the money stream, not this patch).

## What to answer

1. **Does r9 close each round-8 finding it claims to close?** Go item by item, for all three reviews.
2. **Does r9 apply the rulings faithfully** (K-10; Kyle's 10-30 answer; Ryan's 10-21 escheat rule, option A and the 11-04 family-cap call)?
3. **Did r9 open anything new?** For example: a guard that refuses a legitimate act, a retry that can never succeed, a lock-order cycle, a moved check, or a role or superuser path.
4. **Is there still a path around any rule?** Consider every role, isolation level and statement shape.
5. **Concurrency.** Is every cap behind its lock? Does every move that frees money, or moves a share, order itself against the take-backs it could re-read?
6. **The invariants and the tests.** Is any claim narrower than its check, or any mutation passing for the wrong reason? Is anything missing?
7. **Residuals R1–R24 and AC-44 as now worded.** Is any of them blocking?

## How to probe

**Opus and Fable** may query the running `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv23opus`, Fable `rv23fable`):
1. `CREATE DATABASE <name> TEMPLATE tally`.
2. Revoke TEMP on the clone from PUBLIC, `tally_app` and `tally_core` right after creating it.
3. `docker cp` the frozen patch into the container and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

4. Run the battery with the default search_path (only the strict apply uses an empty one), after `VACUUM public.account_ledger, public.payments, public.customer_credits` on your clone.

-25 and -26 are not needed for this review.

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim must be a probe file in `tests/v5.4.2-23/review/codex-r9-probes/`. Each probe runs as the owner on a fresh clone with frozen r9 applied, ends in ROLLBACK, and prints SQLSTATE and message for each caught error with RAISE NOTICE. A COPY probe must print its own error. Keep any long-chain probe to what runs in minutes: the author cancels a probe past 30 minutes.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role.
- Do not run `mutations-23.py`; it uses the fixed name `m23`.
- Run `cash-23.sh` only against your own clone; it commits rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.
- Other sessions share this container: do not run `tests/ci.sh`, and keep to your own clone.

## Output

Write your full review to `tests/v5.4.2-23/review/<reviewer>-r9.md` (`opus`, `fable` or `codex`). It should contain:
- a verdict: "ready" or "not yet";
- the round-8 findings, each marked closed, partly closed or not closed;
- blocking items (B1…), each with the concrete path or repro;
- should-fix items (S1…);
- notes (N1…).

Mark each claim as **executed** or **predicted**. Your final message gives the verdict, the blocking items in one line each, and the file path, in several messages, each under 3 KB.
