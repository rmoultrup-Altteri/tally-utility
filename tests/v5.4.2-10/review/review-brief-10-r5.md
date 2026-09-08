# Review Brief — v5.4.2-10, ROUND 5 (final confirmation): rebill typing and the tenant-composite lineage FK

**File:** `sql/v5.4.2-10-snapshot-coordinate-binding.sql` — **     980 lines, md5 `f143c1cb8a7e894208ed353df8abd20c` — FROZEN.** Round 4 was `2d0ece3c…` (935 lines; both verdicts "sound enough to mirror", one LOW each).

## The two changes since round 4
1. **Fable LOW-1 (a `regular` bill carrying `replaces_invoice_id` escaped the lineage count).** The ordinary shape now refuses `replaces_invoice_id` on every `invoice_type` except `credit_memo` and `duplicate` ("a rebill must be typed correction"); for those two, the replaced bill must be RLS-visible and same-tenant. The lineage count now covers every live snapshotted descendant that carries `replaces_invoice_id` and is not a credit memo or duplicate (so a rebill mistyped before this patch could not slip past; after it, none can exist). Battery F31a (regular rebill refused), F31b (credit memo reversing a same-tenant bill lands and does not count).
2. **Codex LOW (plain `invoices_replaces_invoice_id_fkey` let any tenant point at any tenant's bill — pre-existing).** The FK is now `(replaces_invoice_id, tenant_id) → invoices(id, tenant_id)` on A-3's UNIQUE. A self-verifying precondition refuses the patch if cross-tenant links already exist (corrupt lineage, named in the message). Battery F23 now proves the FK refusal at INSERT; the binding's RLS visibility check stands behind it.

Header records the operator order rule "root before child" for transactions touching two bills of one lineage (Fable round-4 item 4). Battery **58 green** on clean and pre-seeded applies; the nine live shapes re-run green (`races/*-r5.out`). Strict apply ×2 clean.

## Confirm
1. Your round-4 repros against this hash (Fable `r4-01-edges.sql` MIXED block must now refuse the regular rebill; Codex's cross-tenant `credit_memo` insert must fail at the FK).
2. Any legitimate flow that carries `replaces_invoice_id` on a `final` / `prebill` / `consolidated` bill? (Author's position: none — a bill that replaces another is a correction; consolidated parents link children through `parent_invoice_id`, not `replaces_invoice_id`.)
3. The composite FK: any existing writer that sets `replaces_invoice_id` without `tenant_id` agreement (void_invoice? consolidation? imports?) — grep tu.sql.

Same DBs and paths (`s10c` pristine with revision 5). Report under 2500 characters: hash; findings; verdict.
