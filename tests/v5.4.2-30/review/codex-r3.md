# Codex — v5.4.2-30, round 3

Verdict: **not yet**.

**Executed** means source inspection, file/hash verification, or a local parser demonstration only. **Predicted** means database behavior awaiting the author’s execution of the supplied probes. No database, docker, psql, CI, precondition script, race script, or mutation runner was executed. I did not read `opus-r3.md` or `fable-r3.md`. The earlier author execution records are evidence from the author, not executions by this reviewer.

## Blocking items

### B1 — predicted: historical membership ambiguity is still silently returned for repeated places

**Source:** `patch-30-frozen-r3.sql:821–848`; `sql/v5.4.2-16-places-and-applicability.sql:728–741` (the two membership exclusion constraints).

The new check reconstructs `premise_place_memberships_exclusive`, but not `premise_place_memberships_no_repeat`. These are different invariants. The latter allows only one membership of a particular place per premise and axis, regardless of relation or exclusivity group. The new historical check excludes NULL groups and all `outside` rows; the result uses `UNION ALL` and retains them.

Concrete paths with the same overlapping-transaction stamps as M12:

1. A premise has a `within` membership of a special-purpose district. Transaction A begins. B voids that membership and commits. A inserts its replacement for the same district and dates, with corrected evidence, and commits. At a recorded instant between A’s start and B’s void, both memberships qualify. Their group is NULL, so the new check ignores both and the reader returns that district twice.
2. Replace a city’s `within` membership with `outside` in the same transaction ordering. The historical result contains both relations for the same city. Only one is `within`, so the exclusive-group check does not refuse this contradiction either.

The live exclusion constraints allow these replacements after the predecessor is voided. Neither path changes the premise’s state, so the new state recorder’s retry does not help. This is the same class of historical ambiguity that r3 deliberately makes loud for two counties. A repeated district can multiply a downstream join to its levy; contradictory relations require the caller to invent a resolution. I am not claiming that a particular billing consumer has already double-charged.

**Probe:** `codex-r3-probes/01-membership-no-repeat-as-known.sql`. It uses the battery’s planted-stamp method, not an executed concurrency test. Inserts and voids run as `tally_app` with all guards enabled. Only fixture timestamps are backdated as owner, then guards restored before reads. Predicted notices:

- Live duplicate control: `23P01`, naming `premise_place_memberships_no_repeat`.
- Two *different* districts: count 2, legitimate stacking.
- Historical same district: count 2, with no error.
- Historical same city: `outside,within`, with no error.
- Current read: one row per place, city outside.

**Fix:** apply the historical filters once, and refuse repeated `place_id` values for the selected premise/axis in addition to the existing exclusive-group test. Preserve multiple distinct districts and legitimate outside relations. Do not merely use DISTINCT: it cannot resolve opposite relations or different outside distances. Add tests for both paths and positive controls, and mutate the additional refusal separately. L7’s “refuses, never mis-answers” remains unfulfilled until this is handled.

## Should-fix items

### S1 — executed: RACE mutation catches do not distinguish a broken guard from a broken experiment

**Source:** `mutations-30-frozen-r3.sh`, `RACE:*` arm; `levy-30-frozen-r3.sh`, `seen()` and R1–R5 result handling.

The runner extracts only the first `FAIL R<number>`. `seen()` emits that identical label when session A itself fails or when B was never observed waiting. Consequently these unrelated outputs are accepted as the named mutation catch:

- `FAIL R3: session A itself failed: connection lost` becomes `RACE:R3`, satisfying N54.
- `FAIL R5: the second session was never seen waiting (sequential, not a race)` becomes `RACE:R5`, satisfying N53.

I demonstrated the parser mapping locally over those literal strings; I did not run a race or claim the reported 57/57 actually encountered either problem. The issue is that the harness cannot substantiate “caught for the right reason” from its recorded label alone. The fixed sleeps and single waiting sample make an inconclusive schedule a realistic category to distinguish.

Report setup/session failures and inconclusive scheduling separately from a semantic assertion failure; require the expected reason for a mutation catch. N52 needs an explicit exception to that design: removing the shared lock is itself expected to remove the wait, so a verified successful conflicting write/no-wait result can be its intended catch. Do not let arbitrary A failures count for N52 either. R1/R2 should also pin SQLSTATE as R3/R5 do, and recording B’s exit status would make diagnostics stronger.

## Notes and answers to the brief

### N1 — executed: frozen inputs match

Checked first, before other review work:

| File | MD5 |
|---|---|
| patch-30-frozen-r3.sql | `a90c82cb685eecc2578d87b29ef322b0` |
| battery-30-frozen-r3.sql | `5b77be6f0cc757ee9dde1fb85e3a99b5` |
| mutations-30-frozen-r3.sh | `a5db1e2fdb7e91b2b5b26fedf6275964` |
| preconditions-30-frozen-r3.sh | `b4a7ca5a79a59a03491256d97cad0646` |
| levy-30-frozen-r3.sh | `9202e6a96f8d34889de8b20d9eb8f38f` |
| older-tests-30-frozen-r1.diff | `bfaa7b62019e5ef4d68883b627e1fad1` |
| r2-to-r3.diff | `1bd33e4e28f80792eb72280885ec4834` |

### N2 — executed source disposition; database outcomes predicted: my round-1 findings, individually

- **B1, closing a place strands a levy: closed for the reported path.** Section 2b adds the deferred ALWAYS coverage check; C1/C3 exercise a close without succession, C2 succession, C4 closing the levy first. C5 now checks the role-switch hole. Probe 00 reproduces these checks with error notices. This is a source disposition, not independent certification of every concurrent schedule.
- **B2, correcting a premise’s state rewrites its past: closed for the reported path.** The reader uses recorded state rather than today’s column. M6/M7 test the old and new answers after the correction; M8/M8b/M10 cover recording and spelling; M13 covers a later-stamped history row. Probe 00. B1 of this review is a separate membership ambiguity, not a recurrence of mutable-current-state lookup.
- **S1, reapply after percent facts: closed in source.** The refusal is conditional on `value_max IS DISTINCT FROM 100`. Probe 02 inserts a five-decimal published percent fact and embeds the complete frozen patch for a second apply, replacing only its outer BEGIN/COMMIT with the probe’s BEGIN/ROLLBACK. This is stronger than merely rerunning the precondition; execution remains pending.
- **S2, database-age-dependent M3: closed in source.** The battery plants the history stamps and derives M3 from the premise’s history. M2’s relevant fixture timestamps are planted. Probe 00 contains these exact checks.
- **S3, code continuity: closed as an explicit platform convention, not as a newly represented identity.** The header now declares successive rows of a kind/state/code to be the same place. C1–C4/L22/L23 test coverage and gaps (probe 00). The database still does not establish that two adjacent rows refer to the same legal entity; this closure relies on the documented convention, as my original finding allowed.
- **S4, reference precision/endpoint: closed by the narrowed contract.** Design §2.4 and the vocabulary description now distinguish published reference precision and `[0,100)` from the utility levy’s four decimals and inclusive 100. Probe 02 checks the five-decimal reference and rejected 100 endpoint. There is no remaining requirement here to round a published rate to four decimals.

The round-1 notes are also accounted for: counts-versus-row-identifiers wording was corrected; ordinary guard coverage is carried into probe 00; the older-test adaptations remain scoped to required answers, gas exemptions and percent units. The known limits are discussed below.

### N3 — executed: review of the new source paths and prior write guards

The recorder is an AFTER INSERT / UPDATE OF state trigger, enabled ALWAYS. Its no-op spelling branch precedes its retry branch. The normalized-state comparison is consistent with the reader and -16. The retry query tests history after the transaction start, not merely “did I wait”; that is the right shape for a writer whose newer predecessor already committed before the UPDATE began. Equal stamps retain the sequence tie-break. M8c actually exercises an insert followed by one correction in a transaction, which tests that tie-break; its broader description should not be mistaken for a distinct test of two UPDATE statements.

The existing BEFORE state-change guard requires READ COMMITTED for a normalized change. The recorder does not replace it. Membership insertion still takes FOR SHARE on the premise, and the new history reader uses the same tenant policy. The history’s direct-insert depth fence, append-only guard and FK are explicit, rather than trusting callers to supply history. Backfill inserts only missing histories; its use of the current normalized state at the original creation stamp is the acknowledged migration approximation. These observations do not extend trust to owner-disabled triggers or arbitrary superuser history inserts.

The coverage trigger adds to `enforce_place`; it does not replace its existing membership/profile/fact/child/jurisdiction checks. Its role check is inside the deferred function, so the source no longer assumes the role at UPDATE is the role at checking. SET CONSTRAINTS can run it earlier, not omit it. Probe 00 carries C0–C5 for author verification.

The levy insert locks row IDs in sorted order, compares the re-read sorted array, and raises 40001 rather than looping. Empty arrays are normalized consistently. The code comparison has no source-level ordering mismatch that would manufacture a retry in a stable single-session fixture; L1/L2/L19/L22 in probe 00 are ordinary-insert controls. R5 specifically exercises a successor committed while waiting. This source review does not certify untested interleavings.

The exclusivity query’s tenant-visible membership, axis, state, creation, void, effective-range and close-as-known filters match the main membership query. Its extra within/non-NULL-group conditions correctly describe the *exclusive-group* rule. The missing piece is the independent no-repeat rule (B1), not a need to reject every NULL group or outside row.

I found no additional concrete source bypass of the levy document checks, required rate-version answers, service-list checks, state-agency basis/logging, or ALWAYS restoration. Probe 00 covers their ordinary paths. No claim is made that the reported earlier CI batteries were rerun. The history also deliberately adds a new permanent FK dependency to every premise, including premises with no memberships; absence of an earlier FK on such a row should not be confused with proof that all formerly possible deletion/identity-reassignment operations remain possible.

### N4 — executed: test and mutation scope

The single-session refusal helper checks SQLSTATE and a guard fragment/constraint name; the narrowed L messages and P4 fixture improve specificity. The r3 mutations target the new retry, group refusal, coverage-role check and sequence order. N15–N17 anchor the main read explicitly now that the filters are repeated. None tests the independent no-repeat historical invariant in B1.

R1/R2/R3/R5 sample the named second session for a Lock wait and reject an observed failure of session A. R3 checks both 40001 and the intended message, plus history/live-state agreement; R4 is sequential control, not a waiting leg. R5 checks 40001 and its intended message. These are useful source assertions, but a single wait sample is not a deterministic barrier and S1 weakens the mutation runner’s interpretation of failures. I found no evidence that any reported run actually caught the wrong reason; I cannot certify the count from source.

The RACE clone branch also omits the TEMP revocations present in the ordinary mutation clone branch and prescribed by the review brief. Keep clone setup consistent. The ordinary race paths do not themselves try to exploit TEMP, so this is not evidence of a production bypass.

### N5 — executed: L1–L7 assessment

L1–L5 remain the agreed scope boundaries: application approval/staging, cross-table penalty concurrency, later reference data, retirement of unread legacy columns, and the money stream’s bill-line work. They do not independently block this review. The report’s current-state/current-membership and service-insensitive scope is now documented; this is not a certification of per-service missing-levy completeness.

L6 explicitly refuses knowledge predating the available state history and directs pre-go-live rebills to legacy evidence. Its backfill approximation must not be represented as reconstructed historical state changes.

L7 permits loud ambiguity during overlapping writes, not contradictory or repeated output. The remaining B1 paths violate that distinction. The template-wide timestamp redesign may remain deferred; the reader still needs to refuse ambiguity for both membership invariants.

## Probe handoff

Run each SQL file independently as owner on a fresh clone of `tally` with frozen r3 applied, with the brief’s TEMP revocations. Every file ends in ROLLBACK, and every explicit caught-error handler emits a RAISE NOTICE containing SQLSTATE and message. No file creates or alters roles. No two-session probe is supplied or claimed executed.

| Probe | Purpose |
|---|---|
| `codex-r3-probes/00-battery-with-error-notices.sql` | Frozen r3 battery, adding caught-error notices only |
| `codex-r3-probes/01-membership-no-repeat-as-known.sql` | B1, live no-repeat control, legitimate district stacking and current-read control |
| `codex-r3-probes/02-percent-fact-full-reapply.sql` | Full second apply with a published percent fact; precision and endpoint contract |

**Author execution record: pending.** Please append output, distinguish fixture/setup failures from the predicted observations, and do not convert predicted findings into executed findings without that record.

---

## Author execution record (2026-11-22)

Fresh clone of `tally` (TEMP revoked), frozen r3 strict-applied (clean). Each probe run independently as owner with ON_ERROR_STOP; each ended in ROLLBACK, exit 0. Every prediction held.

- **00** (frozen battery with notices): `battery-30: all checks passed`.
- **01** (B1), all notices:
```
NOTICE:  CONTROL live duplicate SQLSTATE=23P01 message=conflicting key value violates exclusion constraint "premise_place_memberships_no_repeat"
NOTICE:  CONTROL distinct districts legitimately stack: count=2 (expect 2)
NOTICE:  B1 district returned 2 times (predicted 2, should refuse ambiguity)
NOTICE:  B1 city relations=outside,within (predicted outside,within; should refuse ambiguity)
NOTICE:  CONTROL now: one row per place, city outside; result=TX:within,TX-C33-CITY:outside,TX-C33-D1:within,TX-C33-D2:within
```
- **02** (full re-apply over a percent fact):
```
NOTICE:  v5.4.2-30: tenant isolation and rule-table invariants hold
NOTICE:  reapply completed with reference value=6.25001
NOTICE:  endpoint 100 caught SQLSTATE=23514 message=place fact rejected: sales_tax_rate takes a number; 100 is not one (v5.4.2-16)
```

B1 is confirmed (executed, planted stamps). Folded in r4.
