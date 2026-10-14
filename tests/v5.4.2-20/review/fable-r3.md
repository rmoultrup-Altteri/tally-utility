# v5.4.2-20 r3 review — Fable (diff-scoped)

**Brief:** `review-brief-20-r3.md`, md5 `90548f46815a1ac7b2603a12f7e67cbb` (checked). Frozen: diff `d95f7302…`, patch `0ae59349…`, battery `f5c9f965…`, seal-20.sh `5a2bf6df…`, all match. Reviewed the 237-line diff only.
**Clone:** `rv20fable` rebuilt (TEMPLATE tally, TEMP revoked, frozen r3 patch strict-applied with `search_path=''` + `check_function_bodies=on`; second apply skipped by the marker). Dropped at the end.
**Reproduced (executed):** strict apply twice; battery-20 r3: 80 PASS, `complete`; `seal-20-frozen-r3.sh`: every leg PASS (RC1–RC6, RC3b, T1–T7c). Did not run mutations-20.py.

## Verdict: ready

No blocking items.

## The one question, clause by clause (all executed in a rolled-back transaction)

- **PUBLIC clause.** `tally` today has zero table/column grants to PUBLIC in `public` (count 0; the apply tail passes). `GRANT SELECT ON tenants TO PUBLIC` → raises, naming `tenants`. `GRANT EXECUTE … TO PUBLIC` on a function → passes (functions are outside the clause by design; `is_invoice_issued` and others already carry PUBLIC EXECUTE). A later patch that grants PUBLIC a table privilege would be refused — that is the intended contract, and the message says why.
- **Constraint-definition string.** Rendered `CHECK (((status = 'billed'::text) = (billed_on_invoice_id IS NOT NULL)))` — only a column, a literal and `pg_catalog.text`, nothing `search_path` can requalify. Invariants pass with the session at `search_path = ''` and at `pg_temp, public` with a shadowing `pg_temp.enforce_bitemporal_assertion()` (the three new trigger strings also hold there, because the invariant pins its own path). Re-adding the CHECK `NOT VALID` → raises "missing, changed or not validated".
- **Grant-option strings.** `GRANT SELECT ON invoices TO tally_void WITH GRANT OPTION` → raises with `extra … SELECT WITH GRANT OPTION; missing … SELECT`, so the rendering distinguishes the two states as claimed.
- **Narrowed temp exclusion.** The battery's invoker helpers (`pg_temp.refuses_at`, `ok`, `admits`, my `pg_temp.try`) granted to tally_void → passes (G1/G8 in the 80 confirm it). A SECURITY DEFINER temp function granted to tally_void → raises, naming `pg_temp_N.defr() EXECUTE`. Correct both ways.

## Should-fix

None.

## Notes

- N1 (predicted). The PUBLIC clause scans `pg_class` in `public` for every relkind, so views and sequences are covered too; functions and schemas are not, consistent with the comment ("table or column privilege").
- N2 (read). The mutation-harness change (ordered stream, first failure of any kind must be the named check, setup errors stop the mutation) is the stricter reading of "caught at its named check"; nothing in it loosens a pass.
