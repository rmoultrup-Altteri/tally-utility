# v5.4.2-16 review, round 2 (Opus)

**Hashes match the brief.** Patch `24998853c2a18e4c49ab0325a4a8ad4e`, battery `ef1c7da0baa64ee8cf727fb931e40b07`. The working files the mutation script reads (`sql/v5.4.2-16-places-and-applicability.sql`, `tests/v5.4.2-16/battery-16.sql`) are byte-identical to the frozen ones.

**Baseline on clone `opus16r2`** (TEMP revoked):
- Strict apply: clean.
- battery-16: **50/50 PASS**.
- `races/place-close-16.sh opus16r2`: **R1–R9 PASS**.
- 16 extra mutations of my own (below).
- `opus16r2` and the mutation clone `opus16m` have been dropped.

## Verdict: **not yet**

One blocking item: a wrong answer from the time-zone lookup, reproduced. The fix is small. Every round-1 blocking fix held under my probes.

---

## 0. Did round 1's fixes hold?

| # | Status | Probe / evidence |
|---|---|---|
| B1 RC pins | **Holds.** | R4–R6 pass. Both insert paths assert RC before the shared lock (patch 641, 794), and the jurisdiction trigger does too (890). Each reads the place in a fresh statement after the lock (659, 810, 892), which is a fresh snapshot under RC. The FK check takes FOR KEY SHARE on the place, and the close takes FOR NO KEY UPDATE, so there is no lock cycle. |
| B2 premise state | **Holds.** | The share-lock (650–652) plus the RC-pinned state trigger (708–737) closes both orders: R7 passes, and the reverse order reads the new state through FOR SHARE. The same-transaction order (membership, then state change) is refused. A change to NULL is refused (`IS DISTINCT FROM`). The lookup's state filter (947) is unreachable defence (see Tests). |
| B3 time zone | **Holds for what it fixed** (no county → refuse; tax-axis county read). **New hole, NB1:** two counties on different axes. | |
| B4 RLS-narrowed close | **Holds.** | `rolsuper OR rolbypassrls` on `current_user` (389) matches how RLS is decided, including SECURITY DEFINER (current_user = owner) and SET ROLE. A BYPASSRLS role with no SELECT errors out, which is a refusal. |
| B5 / P7 / P10 | Held. | `sales_tax_rate` fact (201); `relation`/`distance_miles` (602–604); residuals R11 (A5) and R12 (A6). |
| S1 outside vs unknown | **Partly held.** | "Outside city X" is recordable. "In no city" (unincorporated) is not, see S3. |
| S2 exclusivity | **Holds per axis.** | Across axes it does not, which feeds NB1. |
| S3 owner/place kind | Holds. | P2 covers it. |
| S4 keyed facts | Holds. | F6 covers it. |
| S5 lookup arguments | Holds. | L1, L7. `premise_time_zone_as_of` inherits the NULL-date refusal. |
| S6 jurisdiction pointer | **Holds against the close.** | But a pointer can be set *after* a scheduled close, see S1. |
| S7 created_by stamp | Holds. | |
| S8 parent kinds | Holds. | |
| S9 evidence date | Holds. | Unconstrained in value (N5). |
| S10 TRUNCATE | Holds. | |
| S11–S13 | Stated as residuals R13–R15. | S12 (backdated close) interacts with S2 below. |
| S14 tz names | Holds for `Factory`/`posixrules`. | `Etc/GMT+6` still passes (N1). |

---

## Blocking

### NB1. The time-zone lookup answers from one of two contradictory counties instead of refusing
The time-zone function reads both axes "because geography is the same on both" (patch 966–976). The exclusivity constraint, however, is per axis (614–617: `exclusivity_group WITH =, axis WITH =`). So a premise can be recorded within El Paso County (Mountain) on one axis and Dallas County (Central) on the other over the same dates. Both rows have specificity 10, and `ORDER BY pl.specificity DESC LIMIT 1` (975–976) picks one arbitrarily.

Reproduction (committed, as tally_app, tenant P1):
```
OL1: regulatory within 48141 (El Paso), tax within 48113 (Dallas), both from 2020-01-01
OL2: regulatory within 48113, tax within 48141
premise_time_zone_as_of(OL1, 2026-06-01) = America/Denver
premise_time_zone_as_of(OL2, 2026-06-01) = America/Denver
```
Both inserts are accepted. Swapping the axes does not change the answer, so the winner is set by scan order, not by any rule.

This is B3's class: a lookup that answers instead of refusing on contradictory input. The patch's own comment asserts an invariant that the schema does not hold. The same tie can occur between two municipalities on different axes in an annexation window (city A for tax until the quarter, city B for rates from the ordinance), if their zone facts differ.

**Fix.** The lookup-side fix is cheap and covers both cases; it is core-free and additive. Take the top-specificity rows that carry a zone, and refuse (`no_data_found`) if they disagree.

Optionally, also make county membership exclusive across axes. A premise is in one county on any axis, so this could be an axis-independent exclusion, for example a second partial exclusion for `exclusivity_group = 'county'` without `axis`. This is a schema shape, so settle it now if wanted.

Add a battery case: two counties on two axes with different zones, expecting a refusal.

---

## Should-fix

### S1. A jurisdiction can point at a place whose close is already scheduled, then outlive it
The close refuses while any jurisdiction points at the place (410–411, J2). The pointer trigger, though, checks only "in force **today**" (893–894), and jurisdictions are undated (R3).

Reproduction:
```
UPDATE places SET effective_to = '2027-01-01' WHERE place_code = 'OCA';   -- nothing cites it: accepted
-- as tally_app:
INSERT INTO jurisdictions (..., place_id = OCA);                         -- accepted (in force today)
=> jurisdiction OJ1 → OCA, effective_to 2027-01-01
```
From 2027-01-01, the jurisdiction points at a closed place. That is the state the table comment (878: "the place cannot close while pointed at") says cannot arise. Memberships and profiles cannot do this, because they need containment over their whole range.

**Fix.** Because the pointer is undated, require an open place: `v_place.effective_to IS NULL`. Add a battery case for it.

### S2. A membership or profile wrong from its first day can never be corrected for that day
There is no void or correction path. A close needs `valid_to > valid_from` (606), so a wrong row always keeps at least its first day. The exclusivity constraint then refuses the correct row for that day.

Reproduction (OL3, an El Paso premise recorded in Dallas County by mistake):
```
insert regulatory within 48113 from 2020-01-01             -- wrong
UPDATE … SET valid_to = '2020-01-02'                       -- the shortest close allowed
insert regulatory within 48141 from 2020-01-01             -- ERROR: premise_place_memberships_exclusive
premise_time_zone_as_of(OL3, 2020-01-01) = America/Chicago -- permanently
```
The same holds for profiles: `utility_service_profiles_no_overlap` covers closed rows. A wrong owner type answers for its first day forever, and that is the key every law row will read.

Places have a "reviewed platform repair" hint (539). Memberships and profiles are tenant-written and have nothing. Combined with R14 (backdated closes allowed), the only correction available for history is partial.

**Fix.** A stamped void (for example `voided_at` / `voided_by`, set only on an otherwise-unchanged row). The exclusions get `WHERE voided_at IS NULL`, and the lookups and the close floor skip voided rows. This changes what readers must filter, so per "frame shapes by migration cost" settle it now, before law rows read profiles.

### S3. "Unincorporated" cannot be recorded, so §7.45's own-force scope cannot be decided without guessing
- P10 makes absence mean unknown (patch 50). The only negative record is "outside city X" (602–604).
- 16 TAC §7.45 applies of its own force "in unincorporated areas" (`places-sources/texas.md:84–86`; inventory line 18). That is the key the Texas investor-owned law rows (R1) will need.
- An "outside X" row per nearby city does not say "in no city". The ETJ kind is optional (P5), so an unincorporated premise outside every ETJ has no positive record at all.
- The core must therefore either refuse §7.45 forever for those premises, or read absence as unincorporated, which is the guess P10 forbids.

**Fix.** A positive "unincorporated" member of the `municipal_status` group, for example a kind `unincorporated_area` (one per county, parent county, regulatory axis). The group then reads exactly one of city / limited-purpose / ETJ / unincorporated. This is additive and cheap now. It also makes the "one of" in D3 a closed set.

### S4. Tests: 11 of 16 extra mutations survive the battery
I applied each mutation to a fresh clone and ran the battery. `mut.py` is in the scratchpad.

| Mutation | Result |
|---|---|
| Xb: membership insert no longer nulls `closed_at`/`closed_by` (a pre-stamped close; my r1 X4) | **MISSED** |
| Xq: the same for profiles | **MISSED** |
| Xc: `place_fact_kinds` and `place_membership_evidence_kinds` dropped from the immutability list (my r1 X3) | **MISSED** |
| Xd: tally_app granted INSERT/UPDATE on `place_membership_evidence_kinds` | **MISSED** (A1 covers only places, facts and owner types) |
| Xf: the time zone reads `outside` rows (`WHERE pl.relation = 'within'` removed) | **MISSED** |
| Xg: the time-zone fact's date filter removed (a county whose zone changed) | **MISSED** |
| Xu: the `time_zone_uniform` fact's date filter removed | **MISSED** |
| Xw: `place_facts.created_at` not stamped | **MISSED** |
| Xx: the state-change guard counts only open memberships (`m.valid_to IS NULL`) | **MISSED** (S1 uses an open membership) |
| Xs / Xt: the lookup's "defence in depth" legs (state filter, place in force on the date) removed | **MISSED**. Unreachable through the guards: either test them with a fixture written with the trigger disabled, or drop them and say so. As written they are untested claims (memory: checks narrower than their claim). |
| Xr: the jurisdiction trigger on INSERT only | caught (J1b) |
| Xv: place insert keeps `closed_at` | caught (A7) |
| Xy: profile lookup range `[]` | caught (P6) |
| Xz: uniform check disabled | caught (L3a) |
| Xe: jurisdiction "in force today" weakened to "started" | caught (J1b) |

**Missing negative cases:**
- NB1 (two counties on two axes);
- S1 (pointer after a scheduled close);
- an `outside` membership in a county with a zone, which must not answer the time zone;
- a closed county zone fact with a successor of a different zone;
- the state guard against a *closed* membership.

---

## Notes

- **N1.** `Etc/GMT+6` (and every `Etc/*` fixed offset) passes the zone check (492). It is accepted for a place (probe), has no DST, and its sign is inverted. If the intent is civil zones, exclude `^Etc/` other than `Etc/UTC`, or require `^(America|Pacific|…)/`.
- **N2.** Numbers have no range. `sales_tax_rate = -3` is accepted (probe), and so is a negative `census_population`. A per-fact-kind min/max in `place_fact_kinds` would be cheap.
- **N3.** A county's FIPS state prefix is not tied to its state. A TX county `06037` (Los Angeles) is accepted (probe). The check could be a state place fact (`fips_state_code`) compared at insert.
- **N4.** One code per place. Cities and districts are coded "as the tax authority publishes" (303), but counties use Census FIPS, and cities also have Census place FIPS and Comptroller codes. Loading from two publishers (R2) will need an alternate-code mechanism. Better to decide this before the first bulk load.
- **N5.** `evidence_date` is unconstrained. It can be in the future, or later than the evidence it dates.
- **N6.** The premise share-lock (650–652) blocks every update of the premise row until the membership transaction commits. If an application transaction inserts a membership and then updates the same premise, two such concurrent transactions deadlock (share-to-exclusive upgrade). PostgreSQL detects it and kills one. Worth a line in the header, or record memberships in their own transaction.
- **N7.** The state trigger pins READ COMMITTED for **every** normalised state change (718), including premises with no memberships. Probe: under REPEATABLE READ, the OL4 change is refused. This is consistent with the house pattern (tu.sql 19963, 20456, 22110), but it is a behaviour change for existing writers; state it in the header's "What the database refuses".
- **N8.** `CURRENT_DATE` in the jurisdiction trigger (894) follows the session `TimeZone`. That is harmless, but once S1 requires an open place, `CURRENT_DATE` is no longer needed.
- **N9.** `utility_service_profiles.state_code` is not tied to a known state place (a `ZZ` profile is accepted when no ZZ place exists). The lookup takes the premise's state, so a mistyped profile state means "not found", which is a refusal. Note only.
- **N10.** `assert_same_tenant_user` (647, 800) can only refuse for a role that bypasses RLS: for tally_app, the stamped user is already the RLS tenant. That is fine as defence. M9 tests it as the owner.

---

## 1. Spec coverage

| Req | Status |
|---|---|
| P1 state | Held. Premise state unvalidated (R10), but cannot change under memberships. |
| P2 county | Held (kind, FIPS form, zone, weather, sales-tax rate). Cross-axis county consistency missing (NB1); FIPS prefix unchecked (N3). |
| P3 city | Held (population, rate jurisdiction retained, taxability, rate). Franchise remains R4. |
| P4 limited-purpose | Kind held, regulatory axis only; R6. |
| P5 ETJ | Held. |
| P6 rate area | Residual R3. |
| P7 sales-tax jurisdictions + rate history | Held (transit, SPD, type fact, dated `sales_tax_rate`). Quarter-start dates are not enforced, rightly (Texas rule, not schema). |
| P8 time zone | Held, except NB1. |
| P9 weather | Held. |
| P10 inside/outside + distance | Held for "outside city X". "Unincorporated" is missing (S3). |
| A1 owner type | Held (7 types, owning-place kinds). |
| A2 commission status | Held (dated boolean); premise-dependent cases are R15. |
| A3 size | R7. |
| A4 local adoption | Held (keyed). |
| A5 enforcing body | R11. |
| A6 customer attributes | R12. |
| A7 market role | R8. |
| D1 dates per axis | Held (L6). |
| D2 evidence | Held (kind, reference, date). |
| D3 cardinality | Held per axis. The group is not a closed set without S3. |

## Modelling for where this goes next

- **Law rows on owner type and status:** sound. Profiles need S2 (correction) before law rows read them.
- **Tax jurisdictions:** shape is fine. N4 (codes from two publishers) should be settled before R2's bulk load.
- **Annexation:** the per-axis close/open is right. NB1 shows the axes can disagree on facts that are not axis-specific.
- **A utility in two states:** fine (profile per state; cross-state owning place allowed).
- **A city system serving outside its limits:** fine for "outside the owning city" (TX §103.053, KS, NM). The IOU-side "unincorporated" law needs S3.
