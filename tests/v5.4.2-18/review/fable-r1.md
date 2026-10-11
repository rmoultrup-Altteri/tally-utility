# Review round 1 — v5.4.2-18 (Fable)

Frozen artefacts checked: patch md5 `db6179fda7501533dd8e0892a5690bb7` (703 lines), battery md5 `5a4f0271b84d06abf0ab2637ec7d3e4d` — both as the brief states. The embedded schema equals `law/backbilling/backbilling.v1.schema.json` (JSON-equal).

## Verdict: READY — no blocking item. Four should-fixes, the rest notes.

What ran (all on my own clones, prefixed `fable18`; `tally` untouched):
- strict apply (search_path '', function bodies checked) on a clone of `tally`: applies; battery-18 (frozen) 99/99 PASS.
- migration-18.py P1–P7 (a renamed copy, so its clones were `fable18m_*` not `m18_*`): all pass against the frozen patch.
- on the migrated clone: batteries 09, 10, 11, 12, 13 (the rewritten C/Z: 94 passes), 14, 16, 17; lawfiles-17 W1–W5 (W4 cross-checks `backbilling.v1` over 2015 documents, 0 disagreements; W3 re-seeds the 16 rows unchanged); isolation-17; races rule-close-17; evidence-txn-13. All pass.
- mutations-18.py (renamed copy, `fable18mut`): result appended at the end of this file.
- pg_depend on the live `tally`: nothing outside the table's own constraints/triggers depends on the ten columns or the three dropped tables; no view; the only functions whose bodies name them are the two the patch drops.

## Decisions, challenged

1. **Owner types {investor_owned, cooperative}** — agree on the ownership half (memory and §101.003(7)(A) settle the municipal exclusion; nothing in the list reaches a distribution cooperative). The **jurisdiction half is undocumented** (should-fix S3 below).
2. **One facet** — right: nothing in the database reads the other content (verified: no trigger or function reads the dropped columns), and the exclusion needs none of it.
3. **Window terms as a list** — right; the two UNIQUE constraints are the insert check (X1, X3, X9, X10), the quantity/unit pairing is the `before_anchor` branch, the kind FK is the `term` union. The canonical order is new and sound (equal law, equal text) — but the examples don't follow it (S2).
4. **A new basis/condition is a schema version** — right; the core needs code for either anyway, and a vocabulary row alone could never produce a valid document (D15 proves it).
5. **Citation derived from the lead clause** — acceptable; R4 admits the five non-statute leads. K2's hand-typed citations are the independent check of the regex (the builder, the adoption check and migration-18.py all share the same regex).
6. **Dropped guards** — equivalence holds by reading and by battery-13/-18: same floor function, same "sees every tenant" rule, same stamps. Two visible differences, both intended: the exclusion now keys on the three spans (R2's delegated row can sit beside the sixteen — verified), and a close below the floor is now `check_violation` (23514) where -13 raised `restrict_violation` (23001) — battery-13 F13 was updated; nothing else in the repo matches on that SQLSTATE.
7. **Refusing a municipal owner** rather than writing delegated rows now — agree: "the law leaves it to the city" is itself a legal claim (Utilities Code ch. 103) nobody has ruled on; refusing is "unknown law is not permission". The product consequence (a city cannot run a backbilling case until R2 lands) is real and should be in HANDOFF, not a patch defect.

## Should-fix

**S1. A non-Texas legacy row is silently bound to §7.45's owner types.** `patch:546-549` gives every legacy row `owner_types = {investor_owned, cooperative}` by column default, and `patch:562` only checks the default took. The sixteen are the only rows in production, but migration-18.py P3 deliberately adopts ZZ rows "like the Texas rows (the migration's one applicability)" — i.e. the migration invents who a row binds for a row nobody ruled on. Applicability is law content (the law file says "never omitted"). Suggest the DO block refuse any legacy row that is not (`TX`, `gas`) — or assert `v_count = 16` — naming the row, and P3 become an abort case (or keep P3 and state the residual). Not blocking because no such row can exist in `tally` (only -13's seed wrote the table and tally_app cannot).

**S2. Two of the four law examples are refused by the database.** `law/backbilling/examples/backbilling.meter_error.yaml` lists `before_anchor, last_test_any_outcome, deployment_start`; `backbilling.chain.yaml` lists `claimed_start, half_since_last_test, before_anchor` (and favourable `service_start, last_test_accurate, before_anchor`). Written as ZZ rows on the migrated clone both are refused: "the adverse window lists its terms out of order — by kind, in byte order" (`backbilling_rule_insert_check`, patch:140-145). W4 cannot see it (schema-only cross-check), so the examples claim a shape the area refuses. Reorder them; consider having `lawc crosscheck` note that an area's insert check is outside its reach.

**S3. Decision 1's jurisdiction half is unstated.** `commission_jurisdiction NULL` (patch:548, 551) makes the sixteen bind an investor-owned utility inside a city that holds original jurisdiction over its rates and services (Utilities Code §103.001) as well as in the commission's environs. R1 (patch:656-668) cites §101.003(7) for ownership only; neither the patch nor the law file says why §7.45 reaches both statuses. If §7.45(1)'s application clause binds every gas utility regardless of who has original jurisdiction, write that sentence into R1 and the yaml header; if it does not, the rows should bind `commission_jurisdiction = true` and a delegated row the other status. -13 had no such dimension, so this is a claim the migration makes for the first time; it deserves a cited line.

**S4. Test gaps (battery-18, migration-18).**
- No lookup for a `cooperative` profile: L1/L2 cover investor_owned and municipal; M7 only reads the stored column. My probe: a cooperative profile outside the commission's jurisdiction resolves the adopted row. Add an L case (it is the second half of decision 1).
- No overlap case for a subset of the owner set: O3 tests NULL (every owner) only. Probe: a `{cooperative}`-only row for the same key from 2021 is refused by `backbilling_rules_rule_no_overlap` (owner_span `{[0,1)}` vs `{[0,2)}`). Add an O case; and an O case that a delegated `{municipal, political_subdivision, special_district}` row from 2004-07-12 IS accepted beside the sixteen (R2's shape) — probe: accepted, `anchor_basis` NULL.
- P3 has no CLOSED legacy row. Probe: a row closed before the migration (effective_to 2030-01-01, closed_by/closed_at stamped) is adopted with its stamps unchanged (the fill branch does not require the row to be open). Add one to P3, since the identity hash is the only thing proving it.
- P7 calls the adoption check with `to_jsonb(b) || {terms}` — `anchor_basis` is the OLD column. The trigger never produces that shape (note N1), so P7i and mutation M17 pass on a path the migration does not take.

## Notes

**N1. The adoption check's anchor-strategy comparison cannot fire in the trigger path.** `enforce_rule_row_history` (-17:2328-2330) passes `v_new || v_set`, and `v_set` carries the derived facets, so `p_row ->> 'anchor_basis'` is already `terms.anchor.strategy`; patch:204 compares the document with itself. Spy probe (a wrapper registered as the adoption check on a pre-18 clone, steps 3.1–3.4 run, then the fill): the row handed over has `anchor_basis = discovery_date = terms.anchor.strategy`, plus `owner_span` and the old `qualifying_test_outcomes` key. A fill with a swapped strategy is refused anyway — earlier, by `rule_row_prepare`'s facet compare ("anchor_basis is a facet, derived from the document ("test_date"); the writer set "discovery_date"", -17:2062-2066), and under v1 any swap also flips the outcomes comparison (patch:210). So no protection is missing; the claim "key by key, independent of the builder" is false for the basis, and the real guard is the template's. Either say so in the adoption check's comment, or (a -17 change) have the trigger pass the old facet values — e.g. `v_new || jsonb_build_object('terms', v_set -> 'terms')` — so an adoption check can see the old column; then P7's call shape would match.

**N2. "Fully migrated or untouched" holds for the table, not the database, unless applied with `-1`.** Sections 1–2 autocommit before the DO block. Probe (clone with a QQ row, applied as CI and migration-18.py do, without `-1`): the apply aborts at registration and leaves `backbilling_rule_close_floor`, `_insert_check`, `_adoption_check` and the builder `backbilling_rule_legacy_document` behind; nothing else moved. Harmless (CREATE OR REPLACE; the builder is dropped by the next full run), but migration-18.py's `untouched()` does not look, and the header says one DO block. Either wrap the file in BEGIN/COMMIT or state "apply in one transaction". Also PRECONDITION: the fill needs a role with `rolsuper` or `rolbypassrls` (-17:2321-2325 "adopting … is a reviewed migration's act"); a non-superuser owner without BYPASSRLS fails closed at the first row, whole block rolled back — worth one line.

**N3. Words left behind.** `backbilling_anchor_bases`' table comment still ends "a new basis is a row plus a core change" (now a schema version plus a vocabulary row plus a core change, decision 4); patch 3.8 updates three other comments but not this one. `sql/DEPLOY-VERIFICATION.md:123` and `tests/v5.4.2-13/parity/catalog-identity.sql` / `-14/parity/catalog-identity.sql` still name the dropped tables (mirror-time docs/tools, not CI).

**N4. Harness: fixed names.** migration-18.py uses `m18_a…f` and `/tmp/m18.sql`; mutations-18.py `m18mut`; run-battery-18.sh `/tmp/battery-18.sql`. Two concurrent runs (two reviewers today; a shared CI container tomorrow) race on `/tmp/m18.sql` with different mutated patches. I ran renamed copies. Suffix with `$$`/pid.

**N5. Small.** `window.maxItems` is 8 but seven kinds exist and a kind appears once, so the effective bound is 7 (harmless). After mirroring, P1–P7 and the mutation suite can never run again (they need a pre-18 base) — correct in ci.sh, and the adoption machinery becomes untestable dead code; R6 says as much.

## Fidelity checklist (brief §1) — all held
ordering (list in byte order, insert check) · uniqueness (kind, priority per direction: insert check) · NULL semantics (outcomes/months/condition absent ⇔ NULL: adoption check 210, 218-219) · units_invariant, delivery_path 'unruled', straddles (enums) · quantity/unit pairing (before_anchor branch only) · priorities (1..8) · vocabulary FKs (enum branches; anchor_basis FK + facet vocabulary) · created_at/recorded_txid/closed_* (identity hash 311-313, 589-591; template stamps) · close floor unchanged; closer must see every tenant (template) · adoption check compares every old column except the basis (N1) and windows as a set.

## Mutation suite

mutations-18.py (renamed copy, DB fable18mut, frozen patch): 80/80 caught, each at its named check; no MISSED, ANCHOR-ERROR or APPLY-ERROR. Note that M17 is caught by P7i only in the direct-call shape (N1, S4d).
