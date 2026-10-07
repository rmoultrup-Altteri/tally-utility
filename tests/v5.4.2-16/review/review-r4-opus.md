# v5.4.2-16 review round 4 — Opus

**Artefacts checked:** patch `patch-16-frozen-r4.sql` md5 `a0b43c01bda36c127707100c9726643f`, battery `battery-16-frozen-r4.sql` md5 `15eea127cf8d34da55d917325d947659`. Both match the brief.

**Environment:** clone `opus16r4` (TEMPLATE tally, TEMP revoked, strict apply clean on PG 16.14, en_US.utf8, libc). I added a committed probe fixture: two tenants, 40 TX premises, Harris and Travis counties (Travis zoned Central), Houston, El Paso city, a city `CTZ` zoned Central, a two-row state ZZ (`[1900,2000)`, `[2000,)`), and a uniform one-zone state YY. Application writes ran as `tally_app` with `app.user_id` set. I also used a separate clone `opus16r4r` for the race script and a scratch database `opus16r4m` for my own mutations. All three are dropped.

**Reproduced on the frozen pair:** battery **80/80 PASS**. Races **R1–R18 all PASS** on `opus16r4r`. R15 is the 25000 check inside the other legs.

**Verdict: ready.** Nothing I found lets the records reach a state the header refuses, or makes a lookup answer when it should refuse. The should-fix items below are modelling meanings that are cheap to settle now and costly later, plus four test gaps that my mutations prove.

---

## 0. Round 3's fixes: did they hold?

| Item | Holds? | What I tried |
|---|---|---|
| **B — finite distance** | **Yes** | Through the patch's own check: `'NaN'` → 23514 (`NaN <> NaN` is false in PG, so the leg refuses). `'NaN'::float8` and `' nan '` text → 23514. `'Infinity'` and `'-Infinity'` → 22003: the `numeric(8,3)` typmod cannot hold an infinity (PG 16), so the column refuses them before the CHECK runs. `0`, `-0.0`, `-1` → 23514. `0.0004` rounds to `0.000` → refused. `0.0005` → `0.001`, accepted (correct: positive). `100000` → 22003 overflow. A distance on `within` (`0` or `NaN`) → 23514. Patch 667-671. |
| **S-d′ — state close floor + the profile's state lock** | **Yes** | An open TX profile blocks closing TX (`23001 … a utility profile governed by it`). A ZZ profile on `zz2` blocks closing `zz2`. On a clean state XX: a profile ending on the close day plus a voided open profile → the close is **accepted**. A profile ending one day past → refused. A profile spanning both ZZ rows `[1990,2010)` → refused (R19, as stated). Against a state already closed at 2030: a profile from the close day, or open-ended, is refused; one ending on the close day is accepted. Both orders under load: R13 and R14 pass, each with the second session observed waiting. Patch 451-454 and 920-931. |
| **S-tz — answering level** | **Yes** | Twelve premises; results in the table below. Partial load refuses (P0002). A city with no zone falls through to its county. A boundary-dated pair (El Paso ending, Harris starting, both on 2024-06-01) on that day sees only Harris → refused. An `outside` county is ignored. Agreeing peers (El Paso + Hudspeth) → Denver. Two cities on two axes, one zoned and one not → refused. A NULL date → 22023; a date before Texas → P0002. |
| **S-key — citation-form key** | **Yes for blanks**; see should-fix 3 for spelling variants | Refused: tab, newline, NBSP, U+3000, doubled space, leading or trailing blank, ZWSP, ZWJ, BOM, a combining mark, `a b ` (trailing). Real citations that pass: `305 ILCS 20/13(k)`, `16 TAC §7.45`, `Tex. Util. Code § 104.103`, `§§ 7.45-7.46`, `Tex. Loc. Gov't Code §43.130`. |
| **S-err** | **Yes** | Membership, profile, jurisdiction pointer, state change (RR and SERIALIZABLE) and close (SERIALIZABLE) all raise **25000**, matching tu.sql 19966/19993/20459/22113. |
| **S-uninc** | **Yes** | A second TX area → 23P01 `places_one_unincorporated`. In XX: `[1990,2020)` beside `[2020,)` is accepted; `[1990,2020-01-02)` overlaps and is refused. |
| **T** | **Mostly**; four survivors in section 3 | |

Time-zone probes (`premise_time_zone_as_of(…, 2024-06-01)`, `o4tz` in my fixture):

| # | Memberships | Result |
|---|---|---|
| 1 | Harris (tax) | refused P0002 (state-only; TX not uniform) |
| 2 | El Paso reg + Harris tax | refused P0002 (`Harris … carries none`) |
| 3 | El Paso reg + Houston reg (unzoned city) | America/Denver (falls through) |
| 4 | El Paso reg + CTZ tax (city zoned Central) | **America/Chicago** (city outranks county; by design, see note N1) |
| 5 | El Paso reg + Hudspeth tax | America/Denver (agreeing) |
| 6 | El Paso outside, 4 mi | refused |
| 7 | El Paso to 2024-06-01, Harris from 2024-06-01 | refused (only Harris on the day) |
| 8 | Travis + Houston tax + CTZ reg | refused (Houston unzoned at the city level) |
| 9 | El Paso reg + Travis tax + CTZ reg | **America/Chicago**: the county conflict is masked by the city (N1) |
| 10 | Travis reg + Harris tax + CTZ reg | America/Chicago: the partial county load is masked by the city (N1) |
| 11 | El Paso on both axes | America/Denver |
| 12 | none | refused |

Round 3 introduced no new hole that I could find. The profile's state-lock loop reads the state rows, then locks them (ordered by id), then re-reads containment as a fresh READ COMMITTED statement (920-931). A close locks only its own id (443), so the protocol is the same shape as the owning-place lock. Every state row is locked, closed ones included. That costs little and leaves no window. Lock order (state place, then owning place) can deadlock only against a platform session that closes an owning place and then its state in one transaction. PostgreSQL aborts one of them, the same as R18.

---

## 1. Spec

| Req | Status |
|---|---|
| P1 state | Held: the `state` kind; the premise's own column, read as `upper(btrim())`. The validated code is residual R10. |
| P2 county | Held: the kind, time zone, `weather_station`, sales-tax rate. Notice and cap laws are law rows (R1). |
| P3 city | Held: the kind, `census_population`, `gas_rate_jurisdiction_retained`, `residential_gas_taxable`, `sales_tax_rate`. Franchise is R4. |
| P4 limited-purpose area | The kind is held; its law is R6. See should-fix 2 for its tax-axis meaning. |
| P5 ETJ | The kind is held. See should-fix 2. |
| P6 utility rate areas | Residual R3. |
| P7 sales-tax jurisdictions | Held: tax-axis kinds, the transit group, stacking districts with a type fact, dated rates. |
| P8 time zone | Held. |
| P9 weather | Held: the station fact; the WNA zone stays on `jurisdictions`. |
| P10 inside/outside + distance | Held (relation + distance). Cross-state is R16. |
| A1 owner type | Held, but see **should-fix 1**: the vocabulary mixes owner with system kind. |
| A2 commission jurisdiction | Held: dated, separate from owner. Premise-dependent jurisdiction is R15. |
| A3 size | R7. |
| A4 local adoption | Held (keyed fact). See should-fix 3. |
| A5 enforcing body | R11. |
| A6 customer attributes | R12. |
| A7 market role | Out (R8). |
| D1 per-axis dates | Held. |
| D2 evidence | Held (kind, reference, date ≤ today). |
| D3 many-to-many with cardinality | Held (exclusivity groups). The rate area is R3. |

Rule-terms v2 §9 also names "the fictional-state fixture" as part of the places foundation. The patch does not seed one; the battery builds its own `ZZ`. If the fixture is meant to be a seeded platform row for every later battery, it is missing. If it is meant to be per-battery, say so in R2.

### Should-fix 1: `utility_owner_types` conflates who owns the system with what it distributes (meaning-changing; settle before law rows key on it)

`propane_piped` and `master_meter` (patch 278-279) are not owners. They are a product and a resale arrangement, and a city, a district or an investor can be either.

- New Mexico 62-3-3(G)(2) (`places-sources/utility-type-10-states.md:257`) reaches LPG "through any pipeline system operating under municipal authority or franchise". The law keys on the product and the authority together.
- Texas Utilities Code §121.211 binds "each operator of a gas distribution system and each gas master meter operator" (`texas.md:72`), whoever owns them.

A city-owned piped-propane system therefore has to be recorded as either `municipal` or `propane_piped`, never both, and one law row or the other reads it wrongly. `service_type` cannot carry the product: tu.sql's lists stop at `gas` (e.g. tu.sql 3720).

Law rows will key on `owner_type` (R1, rule-terms v2 §9), so splitting it later is meaning-changing on every keyed row.

**Recommendation:**
- Narrow owner types to owners (municipal, political subdivision, special district, investor, cooperative).
- Add a dated `system_kind` (natural gas / piped LPG / master-meter resale), or a profile-level vocabulary column. This is additive now.

### Should-fix 2: on the tax axis, "in no city" has no place whose meaning fits

`unincorporated_area` takes both axes, but its description (patch 187-188) is "outside any city's extraterritorial jurisdiction". `extraterritorial_area` and `limited_purpose_area` are regulatory only (185, 183).

Take a premise in Austin's ETJ, or in a limited-purpose area, where city sales tax is barred (LGC 43.130). On the tax axis the only positive record of "no city sales tax here" is a membership in Unincorporated Texas, and that place's description says the premise is outside every ETJ. Without that record, the tax axis says *unknown*, not *outside* (P10).

So the same row means "outside every ETJ" on one axis and "in no city" on the other. A law row that reads `unincorporated_area` membership on the tax axis inherits the ambiguity.

**Recommendation:** state the per-axis meaning: on tax, unincorporated = in no city, ETJ and LPA included. Or give the tax axis its own "no city" kind. This costs a comment or one vocabulary row now, and a reinterpretation of recorded memberships later.

### Note: `service_locations.jurisdiction_id → jurisdictions.place_id` is a second, undated "which city" path

It is not reconciled with the memberships: a premise can point at Dallas's rate area while its memberships say Houston. R3 covers dating it, not consistency. Worth one line in R3 saying the membership answers for law and the pointer only for rate area.

---

## 2. Integrity

Nothing reached a refused state. What I attacked and saw refuse or hold:

- **NULL legs.** NULL date → 22023. Invisible or other-tenant premise → P0002. NULL owner place on a municipal profile → 23514. An empty void reason → the void path's alnum check. Voided-at without a reason → the close path's whole-row compare.
- **Close floors.** State leg checks: voided, boundary, a past-dated profile, several state rows, a profile starting after the close. Owning-place leg: R2/R18. Facts and children: they block the YY close (the fact leg fired first). Jurisdictions are counted regardless of RLS, since the closer must bypass it (436-441).
- **Races.** R1–R18 re-run and passing, each with the named second session observed waiting. The wait check filters `datname = current_database()` (race script line 88), so concurrent reviewers' runs cannot satisfy each other's legs.
- **RLS.** Policies on the two new tenant tables are identical to `service_locations`'. The state guard reads memberships under the invoker's RLS, but a membership is tied to its premise's tenant by the composite FK (652-653), so whoever can update the premise sees all its memberships. Exclusion constraints key on a tenant-bound premise or include `tenant_id`, so they leak nothing across tenants.
- **Side channel (note).** `tally_app` can probe `pg_try_advisory_lock(place_lock_key(x))` to learn that some tenant has a citation of place *x* in flight, and can hold a session-level shared lock on the TX state key to stall every platform close of Texas. This is R13 (cooperative locks); it is only a pointer that the TX state key is now the hottest key in the system.
- **Isolation.** Every writer refuses RR and SERIALIZABLE with 25000.

### Note N1: a city's zone masks county-level conflicts and partial loads (cases 4, 9, 10)

Round 2 N1 ("two counties on two axes with different zones are refused") and round 3 S-tz ("a partial load must refuse") hold only when the answering level is the county. Once any city the premise is within carries a zone, a Denver/Chicago county conflict on the two axes (case 9), or an unzoned peer county (case 10), is never examined.

This follows from "a city's zone outranks its county's" (kept in round 3), so it is not a new hole. But the comment at 1103-1106 reads as if those refusals were unconditional. Say there that they apply at the answering level only.

If Texas loads no city zones (49 CFR 71 assigns zones by county), this never arises in Texas.

---

## 3. Tests

The battery and races catch every round-3 change I mutated except the four marked **survives** below. I ran these against the frozen pair (my own runner, database `opus16r4m`; `mutations-16.py` itself targets `sql/` and a shared database name `m16`, so I did not run it).

| Mutation | Result |
|---|---|
| X1: drop the time-zone kind filter (1115), so a limited-purpose area or district at the city level counts as a candidate | **survives (80/80)**. Its only effect is a false refusal for a zoned city alongside a limited-purpose area (both specificity 20). Low value; note. |
| X9: the state leg counts only open-ended profiles (`g.effective_to IS NULL`) | **survives**. No case closes a state under a *dated* profile that runs past the close. **Should-fix (test)**: T2 needs a profile `[2005, 2040)` and a close at 2030. |
| X15: `premise_places_as_of` reads the state place on any date (`ORDER BY effective_from LIMIT 1` for the `@> p_on` filter) | **survives**. No case asks for a date when the premise's state has no row in force (before 1900, or a ZZ date after a close). **Should-fix (test)**: one line, `premise_places_as_of(L1, '1850-01-01', 'regulatory')` must raise P0002. |
| X28: `array_agg(c.tz)` without DISTINCT, so agreeing peers count twice | **survives**. The brief names "agreeing duplicates"; no case has two different places at the answering level with the same zone. **Should-fix (test)**: El Paso reg + Hudspeth tax → Denver. |
| X30: apostrophe dropped from the key class | survives. Add `Gov't` to T4's passing list. Note. |
| X32: one unincorporated area per state *ever* (range dropped) | survives. No case records a successor after a close. Note. |
| X2 (state leg for every state), X3 (state leg for every kind), X4 (lookahead `(?=.)`), X5 (unanchored `$`), X18 (a missing uniform fact answers), X19 (no leading §), X22 (unzoned at every level), X23 (pointer at a dated place) | caught |

The race legs I could not have strengthened: R13 and R14 both observe the named session waiting.

### Should-fix 3: keys that differ only in spelling are still distinct (A4)

The citation form blocks blanks, but `16 TAC §7.45` and `16 TAC § 7.45`, `ILCS` and `ilcs`, and the fullwidth `Ａ1` all pass `place_facts_key_check` (506). They are distinct keys, so two `local_adoption` facts for one law can stand at once, which `place_facts_no_overlap` exists to stop.

Real citations the form refuses:
- `Tex. Bus. & Com. Code` and `Tex. Agric. & Com. Code` (`&`);
- `Gov’t` with a typographic apostrophe;
- `Ord. #2024-5`;
- an en-dash range;
- `¶`.

The bare key `§` passes.

This is platform-written, so it is not blocking. But the S-key rule was "one law, one key", and only a canonical form or a code vocabulary gives that. Either:
- key `local_adoption` on the law row's citation code (an FK when law rows exist; a registered code list until then); or
- state the canonical spelling (upper case; `§` followed by one space; `&` allowed) and check it.

---

## 4. Verdict

**Ready.** No blocking items.

**Should-fix:**
1. Owner type conflates owner with system kind (`propane_piped`, `master_meter`). Split it before law rows key on it; that is meaning-changing later and additive now.
2. The tax-axis meaning of `unincorporated_area` for ETJ and limited-purpose premises.
3. Fact keys are not canonical (case, `§` spacing, Unicode alnum lookalikes). Real citations with `&`, `’` or `#` are refused.
4. Test gaps proven by surviving mutations: a dated governed profile past a state close (X9); a lookup dated before the state exists (X15); agreeing peers at the answering level (X28).

**Notes:**
- N1, the city mask on county conflicts: fix the comment at 1103-1106.
- `jurisdiction_id` versus memberships: one line in R3.
- The fictional-state fixture of rule-terms §9.
- Advisory-lock probing: R13.
- X1, X30, X32.
