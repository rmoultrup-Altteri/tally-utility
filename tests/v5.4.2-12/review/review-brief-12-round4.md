# Review brief — v5.4.2-12, the meter test history (round 4, frozen)

| Artefact | Lines | md5 |
|---|---|---|
| `sql/v5.4.2-12-meter-test-history.sql` (= `review/patch-12-frozen-r4.sql`) | 1756 | `437ffb6b3563642abc1bdf431061707e` |
| `tests/v5.4.2-12/battery-12.sql` (= `review/battery-12-frozen-r4.sql`) | 1074 | `05133a611d1d1d11bb2d1a66170f8dc9` |
| `tests/v5.4.2-12/isolation-check-12.sql` | 34 | `63134a0adc9037582a75b8c6c4081697` |

Frozen. **Do not edit any file in the repo.** The round 1–3 briefs still
govern environment, rules and scope.

## Round 3 — found and folded

Both round-3 reviewers confirmed all six round-2 fixes.

| # | Finding (who) | Change | Pinned by |
|---|---|---|---|
| 1 | A same-date row that supersedes nothing still displaced a failure — within one basis by insertion order, or as a stronger basis without readings (both) | Insert guard: a non-superseding row WITHOUT readings is refused when a live same-date row has readings or found the meter defective. A same-day retest WITH readings is accepted. Both readers' ranking rewritten to mirror the correction rule: **readings first, then an asserted failure, then record_basis, then recorded_seq** | K5, K5b, K5c, K6b; ranking independent of the guard: K8, K8b, K8c (planted with the insert guard disabled, as owner, in a savepoint) |
| 2 | Swapping users.id with the tenant's platform_admin row made the session an administrator without touching role (Opus) | §1b trigger now `UPDATE OF role, id`; tally_app may not change users.id | K7 — the working one-statement re-key (my row aside, the admin row takes my id); shown to succeed with the guard removed |
| 3 | The isolation refusal blocked a tenant INSERT carrying its cutover (both, LOW) | Refusal applies to UPDATE only | ISO2 flipped to "accepted" |
| — | Documented: demoting an in-tenant platform_admin (R16), the app.user_id trust premise (R16), `ON CONFLICT DO NOTHING` over-strictness (1b comment), default_transaction_isolation on tally_app (§3) | | |

**Note on the ranking order.** Round 3's proposed ranking put record_basis
before the readings and failure keys. That order would still let a
"recorded" inconclusive row without readings outrank a date-only "fast" —
round 3's own case. The folded order puts readings and asserted failures
first; record_basis only decides between rows that have neither.

Verification: strict apply ×2 clean; battery **115 PASS**; isolation 3 PASS;
regressions 28 / 58 / 41; **nineteen** planted mutations (M1–M19), each
caught by its named check — including one per ranking key.

## What I want from round 4

1. Confirm or refute the three round-3 fixes against your round-3 repros.
2. The new insert guard: false refusals of legitimate data (migration loading
   two legacy sources for one day; a recorded reason-only test on a day that
   already has a migrated full record; as-found/as-left), and any displacement
   it still misses.
3. The ranking order above — is there any pair of same-date rows where it
   picks the wrong one?
4. If nothing above LOW remains: "sound enough to mirror".
