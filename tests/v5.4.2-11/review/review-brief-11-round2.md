# Review brief — v5.4.2-11 (round 2, frozen)

| Artefact | Lines | md5 (round 2) | was (round 1) |
|---|---|---|---|
| `sql/v5.4.2-11-definer-hygiene-and-view-rls.sql` | 883 | `5b27cc38f756dd3433308fffe034a286` | `133546f8…` |
| `tests/v5.4.2-11/battery-11.sql` | 485 | `30101ae6b5497cff7fa8ee017e7a2810` | `db6c16c2…` |
| `tests/v5.4.2-11/probe-pre-11.sql` | 237 | `5a38f3f3a15966f4f1be20c5897c2bf4` | `98fca01a…` |

Frozen for this round. Round 1's brief is `review-brief-11.md`; the seven
original attack surfaces still apply and are not repeated here.

## Every round-1 finding, and what happened to it

**CRITICAL/HIGH — four materialized views leak cross-tenant.** Confirmed
independently before folding. **Resolution: REVOKE, not wrap** (Ryan,
2026-09-09). Section 5c revokes ALL on all four from `tally_app` and `PUBLIC`.

Both of you proposed a `security_invoker` wrapper view. That shape is
impossible and the brief now says so: an invoker wrapper requires the *caller*
to hold SELECT on the matview underneath, which is the grant being removed.
The only workable wrapper is owner-rights with a hand-written tenant
predicate — a second copy of the `tenant_isolation` policy, running with the
same owner rights as the hole being closed. It was declined; residual R5
records the absent read path and the options set aside.

**The blind spot** (`relkind = 'v'`) is fixed in both places: §7.1b asserts no
matview is readable by `tally_app` or `PUBLIC`, and battery A5/A6 do the same
plus an actual refused read.

**MEDIUM — default privileges reopen PUBLIC EXECUTE for the next definer.**
Real, reproduced. **But the proposed fix does not work.** Measured while
folding:

```
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC
    -> pg_default_acl unchanged; new function acl '=X/tally …'; PUBLIC-exec = true   (NO-OP)
ALTER DEFAULT PRIVILEGES FOR ROLE tally REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC
    -> global entry 'tally=X/tally'; new function acl has no '=X/'; PUBLIC-exec = false  (WORKS)
```

PUBLIC's EXECUTE comes from the **global** (schema-less) default ACL, not the
per-schema one. Section 5b uses the unqualified form and carries the
measurement so nobody "fixes" it back. §7.4c re-asserts by shape; §7.4d checks
the global default itself (`defaclnamespace = 0`); battery C4 creates a definer
and proves it is not PUBLIC-executable.

**LOW — "evaluated once per query" is false.** Accepted; it was reasoning, not
measurement. The header now carries your numbers (260 ms → 377 ms, ~+45%,
~1.2 µs/row over 100k rows, seq-scan filter) and states that index paths are
unaffected.

**LOW — TEMP is revoked on the built database, not on clones.** Accepted, and
it changed R1's *reasoning*: the pin is safe because `void_invoice`'s body has
zero unqualified relation references (verified), not because TEMP is absent.
The battery now prints the TEMP state it is actually running under rather than
assuming it.

**LOW — `app.user_id = ''` raises instead of returning NULL.** Accepted; the
`get_user_tenant_id` COMMENT now says so, including the pooler consequence.

**Battery gaps.** All closed: matview checks (A5/A6); `void_invoice` now
actually *called* by `tally_app` after the revoke (C3 — it was catalog-only);
the future-definer default (C4); the TEMP context line. Note the new grants on
the `pg_temp` helpers — section 5b means a battery no longer gets EXECUTE on
its own helpers for free, which is itself a small proof the revoke works.

## State now

- Strict apply ×2 (`search_path=''`, `check_function_bodies=on`): clean, idempotent.
- `battery-11.sql`: **29 checks**, all PASS (was 24).
- `probe-pre-11.sql`: **11 pre-patch holes** on the -10 build (was 8); all 11
  read `as expected` on the patched build.
- Regression: `battery-09` 28 PASS, `battery-10` 58 PASS, zero errors.

## What I want from round 2

1. **Re-check the two folded fixes on their own terms.** The matview revoke:
   does anything legitimately break — a view, a function body, a planner path
   that reads one of the four? The default-privileges revoke: is the
   unqualified `FOR ROLE tally` form too wide, or does it miss a case (objects
   created by a role other than `tally`; `pg_temp`; a future schema)?
2. **§7.4d is a catalog-shape assertion.** I would rather it be behavioural
   like battery C4, but a migration that creates and drops a probe function
   felt wrong. Is the `defaclnamespace = 0` + `item LIKE '=%'` test correct in
   all cases — e.g. a grant to a role literally named such that the ACL item
   renders ambiguously, or a second default-ACL row from another grantor?
3. **Did revoking the matviews move the problem?** Anything that used to read
   them and now silently returns nothing, or an index/constraint that depended
   on the grant.
4. **Anything round 1 missed that round 1's own findings now make visible.**
   The `relkind` blind spot suggests a general question: what else in this
   schema is enumerated by a filter narrower than the property it certifies?

Same rules of engagement: severity, one-line claim, runnable repro, file:line.
