# v5.4.2-17 draft r3 — review (Opus)

**Artefacts checked:** patch md5 `74c730ed9ceb11b7449f3b373a851000` (3054 lines) and battery md5 `9d91b4852638755db3d1734887d66fab`. Both match the brief.

**Probe setup:** clones `opus17r3` (ZZ fixture and probe rows committed) and `opus17r3b` (clean), each strict-applied from `tally` with TEMP revoked. On `opus17r3b` the full suite passes:
- battery: 216 PASS;
- isolation: 0 failures;
- races: RC1–RC7 (RC6 and RC7 are new);
- law files: W1–W5 (W4: 899 documents, 0 disagreements).

I did not run the mutation suite.

**Verdict: ready.** Nothing is blocking. All three of my round-2 should-fixes hold under re-run. One new should-fix (the core-role invariant does not look at role membership) and two notes.

---

## 0. Round-2 findings, re-run against r3

| r2 | Re-run result | Holds? |
|---|---|---|
| **S1** facet type pairing | The same three-facet tariff (`text[]` over `text`, `boolean` over `text`, `number` over `integer`) is now refused at registration, naming all three mismatches: "facet b is boolean but zz_t2.b is text; facet codes is text[] but zz_t2.codes is text; facet n is number but zz_t2.n is integer". New check `rule_facet_column_errors` (1414–1429, run at 1578–1584). Checked one level further: a table registered correctly for v1 of its kind, then a v2 declaring the same facet as `text` over the `numeric` column. Its first row is refused: "facet n is text but zz_t4.n is numeric" (1744–1749) | **Yes** |
| **S2** re-seed comparison | Re-seeding with a different value in an area column (`memo`) is refused ("with a different memo"); so is a facet (`fee_cap: 999`). A document with its keys reordered is still the same row. The comparison now covers every column the seed names (2271–2283). See N1 for what it still does not cover | **Yes** |
| **S3** strategy version range | `version` must be an integer with 1 ≤ minimum ≤ maximum, resolved through `$ref` (466–481). R4n and R4o are the negatives. A strategy's v2 can now join the range within the same terms version | **Yes** |

**Other r2 fixes checked for new holes:**
- **Depth under unions.** Selecting a branch keeps the depth (674–677), and since a branch is an object schema, the recursion still descends. V24 covers it; the cross-check agrees.
- **Adoption.** The new `p_adoption_check` runs only when an empty document is filled, after `rule_row_prepare` (2033–2036), with the row as written, so a contradictory `terms` is refused. Registration refuses an adopting table whose documents are already filled. The insert check still runs during adoption, inside `rule_row_prepare`. That is right, as long as an area's insert check never reads its legacy columns; R14 could say so.
- **The freeze.** It now compares text (928), so 0 → 0.0 is an edit.
- **`assert_core_role_invariants()`.** See S1 below.

---

## Should-fix

### S1. `assert_core_role_invariants()` does not look at role membership
The function checks `tally_core`'s own attributes, its mutual membership with `tally_app`, materialized views, default ACLs, TEMP and CREATE (2880–2942). TEMP and CREATE are checked with `has_*_privilege`, which follows membership. The attribute checks do not: SUPERUSER, BYPASSRLS, CREATEROLE and the like are not inherited, but a member can `SET ROLE` to the role that holds them.

**Reproduction (opus17r3, rolled back):**

```sql
CREATE ROLE opus17r3_admin NOLOGIN BYPASSRLS;
GRANT opus17r3_admin TO tally_core;
SELECT public.assert_core_role_invariants();   -- passes
```

From there `tally_core` can `SET ROLE opus17r3_admin` and read every tenant. The same holds for membership in any superuser role, `tally` included.

Nothing in the patch grants such a membership. But the function's purpose is to catch exactly this kind of later misconfiguration ("guards must act"), and its comment claims it "holds no dangerous attribute".

**Fix:** require that `tally_core` is a member of no role at all, `NOT EXISTS (SELECT 1 FROM pg_auth_members WHERE member = 'tally_core'::regrole)`. Alternatively, check every role it can reach with `pg_has_role(…, 'MEMBER')` for those attributes. Add a K test. (Membership in a TEMP-holding role is already caught, since `has_database_privilege` follows membership; I probed that too.)

---

## Notes
- **N1. A re-seed is not compared on columns it omits, or on its `id`.** On re-seed (rolled back), these all returned the existing id without error:
  - a seed omitting `source_note`, or omitting an area column the stored row has;
  - a seed naming a different `id`.

  Only an omitted `effective_to` is checked (2281–2283). lawc always emits the full envelope and never an `id`, so tool-made seeds are unaffected. Either compare an omitted template column against NULL as `effective_to` is, or refuse a seed that omits one, and refuse a named `id` that differs from the row found.
- **N2.** This was reported as `opus17r3_admin` with BYPASSRLS; I created the role and granted the membership in a rolled-back transaction, and confirmed no `opus17r3*` role was left behind.

---

## 1. The spec (Step-2 items)
Unchanged from my round-2 table, and every item still holds:
- V1–V10, F1–F4, F7, T1–T6, U1–U4, P1 (class is residual R10), P3, C1–C4, L2 and L4 are held.
- T7 (R2), U5 (area), L1 (amended) and L3 (scenarios, R11) are a residual, area work or a note, as before.
- V5 now matches convention v2 §11.

**Template choices for -13 and -15:**
- **-13's adoption:** the r3 split of the adoption check from the insert check is what -13 needs. A permanent insert check that compares legacy columns would have refused every new row once those columns were dropped. R14 gives the sequence.
- **Spans, the NOT NULL `=` area key, "law always cited, tariff optional", shared-key tariff checks, and the seed's "same row":** all remain right.

## 2. Integrity probes that held in r3
- Facet types are paired, at registration and on a later version's first row.
- Re-seed differences are refused, for both area and facet columns.
- Strategy version ranges work.
- A TEMP grant reached through role membership is caught by the core invariant.
- The full test suite passes on a clean clone.

Databases `opus17r3`, `opus17r3b`, `opus17r3_iso`, `opus17r3_race` and `opus17r3_law` are dropped. The probe roles were created only inside rolled-back transactions.
