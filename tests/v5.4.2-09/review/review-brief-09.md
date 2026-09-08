# Review Brief — v5.4.2-09 (A-9: tax exemption certificate evidence + renewal surfacing)

**File under review:** `sql/v5.4.2-09-tax-exemption-renewal-and-certificate-evidence.sql`
**368 lines, md5 `b8318398100bd6a0838df211b7c107da` — FROZEN for this round. Verify the hash before testing; if it differs, stop and say so.**

## What it is

Wave 3's A-9, deliberately small. `customer_tax_exemptions` was rebuilt by A-1 (v5.4.2-03, tu.sql §5.3 around line 15738): bi-temporal in place, born `pending_verification`, R-12's verification lock (active requires verified_by/verified_at), in-place status flips on asserted rows refused, expiry/revocation = successor rows, open-rows EXCLUDE per (customer, exemption_type) on the valid bracket, reads via `customer_tax_exemption_as_of` / `should_charge_tax` (coordinate pair required). This patch adds ONLY what CI-046 still lacked:

1. `tax_exemption_certificate_required(tenant, exemption_type)` — per-category certificate-required-vs-flag-only from `tenants.settings.tax_exemptions.certificate_required.<type>`, DEFAULT TRUE (R-13: certificate-backed exemptions only; Comptroller Rule 3.287). Unknown category or malformed value raises.
2. The evidence gate, folded into `enforce_tax_exemption_lifecycle` (redefined; same trigger): ENTRY to any asserted state (active / expired / revoked) requires non-blank `certificate_number` OR `certificate_url`, unless flag-only. Fires only on entry (INSERT born asserted, or the verify UPDATE where OLD.recorded_at IS NULL) — drafts stay editable, asserted rows are never re-judged.
3. Self-verifying precondition (the R-13/R-4 pattern): the patch refuses to apply while any CURRENT active assertion lacks required evidence. Ended assertions and malformed config get NOTICE counts.
4. `tax_exemption_renewal_notice_days(tenant)` — settings `{tax_exemptions,renewal_notice_days_before}`, default 60, >= 1, loud on bad config (max_consecutive_estimates pattern verbatim).
5. `customer_tax_exemptions_renewal_due` view (security_invoker): current active assertions with effective_end inside the tenant window or past ('lapsed'), suppressed when a later-bracketed open active assertion (a renewal) exists for the same (customer, exemption_type).

Deliberately NOT landed (attack these decisions if you think they're wrong): no stored `renewal_due_at` / `renewal_notice_sent_at` (later facts on a frozen assertion — the A-7 `remitted_on` lesson); no guard on legacy `customers.is_tax_exempt` (display-only path the tax engine never reads — recorded residual); no per-category validity-period seed (no citable figure).

## Verified before this brief

Strict apply ×2 (search_path='', check_function_bodies=on) on a fresh-load scratch; battery 21 checks green as `tally_app` end-to-end (draft-without-evidence OK; active-without refused; url-alone OK; whitespace refused; per-category flip honored; malformed config raises; RLS through accessor and view; renewal view due/lapsed/suppressed; succession close-then-insert under deferred constraints; should_charge_tax at coordinates); pre-seeded pre-patch DB with a violating active row refuses the patch, remediation (flag-only flip) unblocks, battery green over the pre-seeded apply.

## What to attack

- **Cap-escape analogues:** any route to an asserted exemption without evidence when required — succession/correction rows, backfill change_type, the close-then-reassert dance, config flipped mid-flight, direct `recorded_at` writes, platform_admin paths.
- **The gate's placement:** is "entry to assertion" the right firing set? Can an UPDATE re-enter assertion in a way that skips it? Does the redefined function preserve every v5.4.2-03 behavior exactly?
- **The view:** suppression correctness (is a pending-verification renewal rightly NOT suppressing?), the NOT EXISTS shape, per-row accessor calls raising for one bad tenant and blocking the whole queue (acceptable? A-20 precedent says loud), CURRENT_DATE vs the battery's constant now().
- **Config parsing:** `#>>` on JSON booleans/strings/numbers, 't'/'f' acceptance, the precondition's treatment of malformed values as "required" (conservative refusal — asymmetric with the accessor's raise; is that a hole or fine?).
- **Precondition completeness:** should ended (expired/revoked) assertions without evidence block too? Should the precondition also run the malformed-config check per category actually in use?
- **RLS/privileges:** accessor readable cross-tenant? View grants? tally_app write paths. TEMP still revoked assumptions.
- **The residuals:** is leaving `customers.is_tax_exempt` unguarded defensible, or is there a cheap tooth this patch should carry?

## How to test

Container `tally-pg` (no host port — `docker exec tally-pg psql -U tally -d ...`). DB `scratch` has the patch applied over a fresh load; `scratch2` is the pre-seeded apply; `tally` is virgin tu.sql — clone your own DB (`CREATE DATABASE mine TEMPLATE tally`) if you want a clean run; patch at `/tmp/p09.sql` in the container, battery at `/tmp/battery-09.sql`. Fixture minimums: tenants(name,slug), users(id,tenant_id,display_name,email,role in platform_admin|tenant_admin|operator|viewer), customers(tenant_id,customer_number). Tenant context: `SET app.user_id = '<users.id>'` then `SET ROLE tally_app`.

Report findings with severity (CRITICAL/HIGH/MEDIUM/LOW), a repro for each, and your verdict: sound enough to mirror, or not.
