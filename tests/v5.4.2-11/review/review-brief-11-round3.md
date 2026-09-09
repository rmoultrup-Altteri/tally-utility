# Review brief — v5.4.2-11 (round 3, frozen) — confirmation round

| Artefact | Lines | md5 (round 3) | round 2 |
|---|---|---|---|
| `sql/v5.4.2-11-definer-hygiene-and-view-rls.sql` | 955 | `90ba114da26846561f88c4f89189bb9b` | `5b27cc38…` |
| `tests/v5.4.2-11/battery-11.sql` | 545 | `9fac4a37e72ffba36bae4843e8e34986` | `30101ae6…` |
| `tests/v5.4.2-11/probe-pre-11.sql` | 237 | `5a38f3f3a15966f4f1be20c5897c2bf4` | unchanged |

Both of you returned SOUND ENOUGH TO MIRROR on round 2. This round exists to
confirm that folding your remaining findings did not introduce anything, not
to re-litigate the patch. **Scope: section 7 and residual R5 only.** If you
find something outside that, say so, but the other sections are unchanged.

## What changed, and why

**Section 7 is now a re-runnable function**, not a one-shot DO block:
`public.assert_tenant_isolation_invariants()`. You both reached the same
weakness from different directions — Fable via the `ON TABLES` default making
the next view/matview born leaky, Codex via a per-schema default reopening
section 5b — and both are instances of "a one-shot check certifies only the
instant it ran." Ryan's call (2026-09-09) was the assert function; the event
trigger is recorded as the option declined, on the grounds that it adds a new
privileged execution surface to a patch whose purpose is removing them.

Every future patch calls it in its tail; the container build runs it last.
Invoker rights, owner-only by explicit REVOKE — the per-schema default at
tu.sql:11390 would otherwise hand it to `tally_app` at creation.

**Your three remaining findings are folded into it:**

- `has_any_column_privilege` replaces `has_table_privilege` in the matview
  check, in the function and in battery A5 (Fable MEDIUM — your column-grant
  repro is now battery G5).
- The default-privilege test covers **both** the global row and a `public`
  per-schema row, and is scoped to `defaclrole = current_user::regrole`
  (Codex MEDIUM + Fable LOW). Codex: your conclusion was right, the mechanism
  is union rather than precedence — global and per-schema defaults are
  additive; a PUBLIC item in either is sufficient. The header says so.
- R5 records that `refresh_statistics_views()` has never worked
  (`ON CONFLICT (view_name)` ambiguous with the `RETURNS TABLE` OUT variable),
  that nothing reads the four matviews, and that the one-line fix is
  deliberately NOT applied here — unrelated pre-existing defect, hygiene patch
  (Ryan). The dashboard work fixes read path and refresh path together.

**The assertion is proven to CATCH drift, not merely to pass.** Battery group
G, all four failing-if-not-caught:

```
PASS G1: owner-only, and passes on this build
PASS G2: a newly created matview makes it RAISE
PASS G3: a newly created (owner-rights) view makes it RAISE
PASS G4: a per-schema PUBLIC EXECUTE default makes it RAISE
PASS G5: a column-level grant on a matview makes it RAISE
```

## State

- Strict apply ×2 (`search_path=''`, `check_function_bodies=on`): clean, idempotent.
- `battery-11.sql`: **34 checks**, all PASS, zero errors (was 29).
- `probe-pre-11.sql`: 11 holes on -10, 11 `as expected` on patched.
- Regression: `battery-09` 28 PASS, `battery-10` 58 PASS, zero errors.

## The only questions for this round

1. Does `assert_tenant_isolation_invariants()` have a **false negative** — a
   drift shape it should catch and does not? G2–G5 cover the four we know of.
2. Does it have a **false positive** — a legitimate future object it would
   refuse? A view deliberately owner-rights for a good reason, a matview
   granted to a role that is not `tally_app`, a second default-ACL row.
3. Is invoker + owner-only right? It reads catalogs and privilege functions
   only. Is there a reason it should be definer (a catalog it cannot see as a
   non-superuser caller — noting only `tally` can call it today anyway)?
4. Anything in the R5 text that overstates or understates what you measured.

Same rules of engagement. If you have nothing, say so plainly — a short
"confirmed, no findings" is the useful answer if that is the truth.
