# Review brief — v5.4.2-11 (round 1, frozen)

| Artefact | Lines | md5 |
|---|---|---|
| `sql/v5.4.2-11-definer-hygiene-and-view-rls.sql` | 703 | `133546f8733e06e7006f1a4769086bc3` |
| `tests/v5.4.2-11/battery-11.sql` | 397 | `db6c16c2aa5d8b6e4b14290225b56384` |
| `tests/v5.4.2-11/probe-pre-11.sql` | 189 | `98fca01a13532a7539b3b246327e1862` |

The patch file is **frozen** for this round. Do not review a different hash; if
you believe the file changed under you, stop and say so.

## What this patch is

`tally` is a superuser with `rolbypassrls`. Anything that executes with
`tally`'s rights — a view without `security_invoker`, a `SECURITY DEFINER`
function — reads every tenant's rows. This patch closes the four places that
were doing that, removes a blanket `PUBLIC` EXECUTE grant, and constrains one
free-text polymorphic discriminator.

Seven things land; the header enumerates them as items 1–7. In brief:

1. `adhoc_void_pending_review` and `void_released_read_alerts` get
   `security_invoker = true` (the other three views already had it).
2. `get_user_tenant_id()` / `is_platform_admin()` **stay** definer — the
   `users` policy calls them, so invoker rights would recurse — but get
   `public.users` qualified and `SET search_path = ''`.
3. Recorded consequence: a trigger function may now pin `''`. The ~190
   existing ones are deliberately **not** re-pinned (residual R2).
4. `validate_custom_fields()` → invoker, qualified, pinned, **plus an explicit
   tenant refusal**.
5. `get_correction_rate_date()` → invoker, qualified, pin kept.
6. `REVOKE ALL … FROM PUBLIC` on all five definer-family functions; explicit
   `GRANT EXECUTE … TO tally_app`.
7. `anomalies.entity_type` gets a fifteen-value singular CHECK.

## Measured, not asserted

`probe-pre-11.sql` runs the discriminating checks against a build **without**
the patch. On the v5.4.2-10 build all eight are holes:

```
PRE-PATCH HOLE  A1 adhoc_void_pending_review rows visible to tenant 1  -> got 2 (patched: 1)
PRE-PATCH HOLE  A2 void_released_read_alerts rows visible to tenant 1  -> got 2 (patched: 1)
PRE-PATCH HOLE  A3 views WITHOUT security_invoker                      -> got 2 (patched: 0)
PRE-PATCH HOLE  C1 of the five, executable by PUBLIC                   -> got 5 (patched: 0)
PRE-PATCH HOLE  E1 tenant 2 election leaked to tenant 1                -> got 2026-02-14 (patched: refused)
PRE-PATCH HOLE  D3 foreign tenant validate_custom_fields
                   -> [{"error":"Required field is missing","field":"t2_badge","label":"T2 Badge"}]
PRE-PATCH HOLE  B1 search_path='' read of an RLS table
                   -> relation "users" does not exist  (patched: succeeds)
PRE-PATCH HOLE  F2 anomalies.entity_type accepted 'billing_runs'       (patched: refused)
```

Re-run against the patched build and every line reads `as expected`.

Note D3: the pre-patch behaviour is worse than "a false VALID" — it returns
another tenant's field keys and labels.

## Verification already done (please re-run, do not take my word)

- Strict apply ×2 (`search_path=''`, `check_function_bodies=on`) on a fresh
  `TEMPLATE tally` clone — clean and idempotent; the patch's own §7 block
  asserts the catalog afterwards.
- `battery-11.sql`: 24 checks, all PASS on the patched build.
- Regression: `battery-09.sql` 28 PASS, `battery-10.sql` 58 PASS on the
  patched build. This matters most for `get_correction_rate_date` — battery
  checks E3/E4/E5 exercise the v5.4.2-10 coordinate binding end to end with
  the resolver on invoker rights.

```sh
docker exec tally-pg psql -U tally -d postgres -c "CREATE DATABASE r11 TEMPLATE tally"
docker exec -i tally-pg psql -U tally -d r11 -v ON_ERROR_STOP=1 <<'SQL'
SET search_path = ''; SET check_function_bodies = on;
\i /tmp/p11.sql
SQL
docker exec tally-pg psql -U tally -d r11 -v ON_ERROR_STOP=1 -f /tmp/b11.sql 2>&1 | grep -E 'PASS|FAIL|ERROR'
```

## Where I most want an adversarial read

1. **Does anything still execute with `tally`'s rights and read tenant data?**
   I enumerated views and `prosecdef` functions. Did I miss a surface —
   materialised views, functions owned by `tally` that are invoker but called
   from a definer context, default privileges on future objects, a `SET ROLE`
   inside a function body?
2. **Item 2 is the load-bearing risk.** If `get_user_tenant_id()` /
   `is_platform_admin()` break, every RLS read in the system breaks. Is
   `SET search_path = ''` genuinely safe for those two bodies (the `::uuid`
   cast, the `=` operators, `current_setting`)? Is there a call path where the
   empty pin bites — a policy evaluated during `COPY`, a partition, an
   index-expression, logical replication, `pg_dump`?
3. **The `PUBLIC` revoke (item 6) is new scope.** Only `tally` and `tally_app`
   exist today. Is there a path where PUBLIC EXECUTE was doing necessary work
   — e.g. a policy or view evaluated as a role I have not considered?
4. **Item 4's refusal.** `NOT is_platform_admin() AND NOT superuser AND
   p_tenant_id IS DISTINCT FROM get_user_tenant_id()`. Is there an ordering or
   NULL case that still lets a foreign id through? Note the function is
   `STABLE`, not `SECURITY DEFINER`, and now raises where it used to return —
   is raising the right shape for an app-facing validator, or should it return
   a structured error?
5. **Item 5's blast radius.** `get_correction_rate_date` is documented for the
   (not yet written) billing engine. Under invoker rights it returns NULL for
   an invisible target. The -10 caller checks visibility first, so it cannot
   observe the change — but is there a path where a correction run legitimately
   needs to resolve a target the *writer* cannot see (a platform-admin batch,
   a background worker with no `app.user_id`)?
6. **Item 7's domain.** Fifteen singular values derived from the 37
   `anomaly_type` values. Is any current or clearly-planned detector left
   without a home? `adhoc_charge` and `service_order` are deliberately out
   (Ryan's call) — flag it if you think a specific `anomaly_type` needs them.
7. **Residual R1**: `void_invoice` keeps `public, pg_temp` rather than `''`.
   Its body is qualified and `tally_app` holds no TEMP. Is that reasoning
   sound, or is there a reachable `pg_temp` shadowing path I dismissed?

## Rules of engagement

- Severity: CRITICAL / HIGH / MEDIUM / LOW, each with a reproduction I can run.
- If a finding is "this is fine but undocumented", say LOW and name the line.
- Do not propose re-pinning the ~190 trigger functions; that is R2, and it is
  deliberately out of scope.
