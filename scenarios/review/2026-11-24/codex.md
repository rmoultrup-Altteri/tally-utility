# Review of dc7209c — tax scenarios

Reviewed SCN-0104–0114, the cast additions, and the SCN-0055(c) correction against the scenario conventions, the specified Texas inventory and tax design/inventory, Kyle's three specified decision records, v5.4.2-30, AC-47, and related scenarios. Arithmetic and weekdays were not independently re-audited, as requested.

**Verification limit:** live-database verification was attempted using the supplied read-only Docker/psql route, but access to `/Users/ryanscomputer/.docker/run/docker.sock` was denied. No database writes were attempted. Schema findings below are grounded in the migration and its test fixtures, not a successful live query. This report is the only file written.

## 1. Should-fix — SCN-0113(d) mistakes a place for a tenant-owned record

**Wrong:** Entering “a row for Pecan Flat's city, signed in as Bluebonnet” does not establish the promised tenant-isolation refusal. Places are shared platform data. Bluebonnet can own a levy naming that city; another city's geography is not another utility's data. A utility can serve delivery points in another municipality.

**Evidence:** `tax_levy_insert_check` in `sql/v5.4.2-30-tax-levies-and-taxability.sql:317` compares the new row's tenant with the user's tenant. Its place checks concern kind, state, code and date coverage, not ownership by a city's utility. `tax-design.md` §2.8 makes the same distinction.

**Fix:** Make (d) explicitly attempt to create or change **Pecan Flat utility's levy** while authenticated as Bluebonnet. Add the contrasting accepted case: Bluebonnet creates its own levy for a loaded, valid Pecan Flat municipality. Otherwise an implementation that incorrectly restricts utilities to their owning city would pass this test.

## 2. Should-fix — SCN-0111 infers no commercial city tax from no residential city tax

**Wrong:** The Rule cites the cast as establishing no local sales tax. The cast only says Pecan Flat has not adopted tax **on residential gas**. Adding a county with no sales tax does not establish that the café and weekly rental owe state tax only. The new county row and PF-03 description repeat this unsupported inference.

**Evidence:** `application/places-sources/texas.md` §5 distinguishes ordinary commercial taxation from the special residential treatment under §§151.317 and 321.105. A city's residential exemption does not exempt commercial sales. The Comptroller likewise treats residential gas as a distinct local-tax question: [residential utility tax guidance](https://comptroller.texas.gov/taxes/sales/utility/).

**Fix:** Explicitly invent that Pecan Flat has no municipal sales tax on these taxable gas deliveries, and that neither premise belongs to a taxing transit authority or district. Alternatively, give the city its commercial rate and update (b), (c), the county-row conclusion and PF-03's description. Preserve the separate residential fact.

## 3. Should-fix — SCN-0105 and SCN-0108 conflict with March's pipeline-safety bill

**Wrong:** Two March 2027 expectations no longer fit the shared cast:

- SCN-0108(b) gives BB-11's complete March bill as **$65.18**, omitting Bluebonnet's annual **$1.00** pipeline-safety fee. BB-11 is a homeowner, not an exempt state agency.
- The district added globally by SCN-0105 and the cast applies to BB-01 in March 2027, but SCN-0054(a) still asserts **$66.83** from city tax plus the safety fee only.

**Evidence:** `cast.md` §2 requires the fee on March bills. SCN-0054(a) explicitly works that March 2027 bill. Kyle 11-05 answer 20 provides no exemption for these homeowners. The tax family's common assumptions freeze commodity/GCA figures for comparison; they do not waive the safety fee or override the cast's new district.

**Fix:** Show BB-11's March fee separately, outside tax bases, and total **$66.18**. Update SCN-0054(a) to include BB-01's district tax of **$0.16**, giving **$66.99**. If an isolated tax-only illustration is intended, label it as a subtotal and explicitly exclude the fee from the comparison rather than calling it the complete bill.

## 4. Should-fix — SCN-0114 reopens the configured within-bill payment order

**Wrong:** The first Open asks Kyle to choose taxes first, last or proportional as though the system has no existing mechanism. SCN-0081 already requires the utility's configured within-bill order, with no default; the cash family's common fixture places fixed charges, usage and riders before taxes. Using that fixture, BB-10's **$100.00** cannot reach any tax because its tariff-priced charges total **$187.40**. The three tax shares are therefore **$0.00**, not indeterminate.

**Evidence:** `scenarios/cash.md`, common assumptions and SCN-0081, expressly distinguish the utility's within-bill order from Kyle's two-tier ordering of bills and charges. Kyle 11-05 answer 16 does not replace that mechanism.

**Fix:** State the configured payment order in the Given and assert zero tax collected from this payment. To test a partial collection of tax, use a payment that reaches the tax lines and specify their tie-break/order, or identify the narrower unresolved question of how multiple lines of the same tax charge type share payment. Do not substitute a new universal first/last/proportional choice for the existing tariff mechanism.

## 5. Should-fix — SCN-0114 has no defined period basis for collected tax

**Wrong:** The Rule promises liability by **accounting period**, but October's collected column includes a share of a payment made on **November 3**. The scenario does not say whether it means cash collected during October or collections to date against October invoices, nor when the report is read. These produce different results once a payment reaches tax. Resolving the payment allocation Open would not resolve this ambiguity.

**Evidence:** Kyle 10-14 answer 4 requires billed and collected amounts by jurisdiction and period. `tax-inventory.md` gap 12 and open point 12 distinguish line-level collection from the missing period grouping. The scenario itself selects accounting period but does not define the collection coordinate.

**Fix:** Define the report's period and as-of cutoff. For collections posted in October, exclude November receipts and assert October collections of state **$26.19**, county **$2.10**, city **$0.00**. If the intended report follows the October invoice cohort, name it accordingly and specify its cutoff separately. Assign the record/grouping contract to the **money stream**, with Kyle/tax counsel deciding any business or filing-policy question. Include a later payment that actually reaches tax so the period boundary is observable.

## 6. Should-fix — SCN-0108 states the annexation tax date without the statutory delay exception

**Wrong:** The Rule defines the tax date unconditionally as the quarter immediately after Comptroller receipt. The Given does not establish that the Comptroller did not request additional time. The cited source expressly includes that exception, which can change April 1 to July 1 for these dates.

**Evidence:** `application/places-sources/texas.md` §3 includes §321.102(d). Under that subsection, timely Comptroller notice postpones implementation by another quarter. [Texas Tax Code §321.102(c)–(d)](https://tcss.legis.texas.gov/resources/TX/htm/TX.321.htm#321.102).

**Fix:** Qualify the Rule and state that no extension notice was issued in the existing example. Add a timely-notice variant with July 1 as the tax date, keeping February 15 as the rate-boundary date; May then has no city tax. This also verifies that the core uses the recorded tax-effective date rather than calculating a mandatory next-quarter date from receipt.

## 7. Should-fix — SCN-0109/0110 omit AC-47's prerequisite for historical reads

**Wrong:** These scenarios cite AC-47 but assert historical reads at the run's instant without establishing its required condition: no earlier-started transaction remains open when that instant is chosen. Their sequential examples do not test the known failure where a later commit changes a historical lookup, yields duplicate jurisdictions, or makes the fixed instant permanently ambiguous. Recording which rows were used preserves evidence; it does not make an unsafe historical query reproduce them.

**Evidence:** `APPLICATION-CONTRACTS.md:463`–470 and migration limit L7 explicitly distinguish bill snapshots from historical reads. SCN-0109's Rule and SCN-0110(a)'s historical-membership assertion need that distinction.

**Fix:** Add the safe-instant precondition to these Given sections, require both tax and place reads at the same instant, and make replay assertions explicitly snapshot-based. Add an earlier-open-writer variant: the run must choose a safe instant before computing; waiting after choosing the instant is insufficient. Assert the documented distinction between retryable 40001 and fixed-instant 21000. This is an existing application contract, not an Open for Kyle.

## 8. Should-fix — SCN-0104–0106 lack an independent overlapping-jurisdiction test

**Wrong:** Every worked Texas district is citywide and there is no worked transit-authority case. A core that adds district tax to every customer of the city, or ignores transit membership entirely, can pass all these examples. Merely saying districts stack does not assert that the delivery point independently belongs to each one.

**Evidence:** Kyle 10-14 answer 1 requires every jurisdiction the service location sits in. `application/places-sources/texas.md` §5 requires delivery-point membership and distinguishes residential treatment of transit authorities and most districts. SCN-0105 varies dates and customer class, but not district membership within a city.

**Fix:** Add matched premises within the same city but on opposite sides of a partial district boundary, with explicit tax-axis memberships. Add a taxable business in a transit authority and an ordinary district, plus a residential counterpart: those taxes reach the taxable business but not residential gas. Keep the local stack within the cap and state each expected jurisdiction line and base. This tests location selection independently from city membership and residential eligibility.

## 9. Minor — SCN-0108 assigns district-boundary law to Kyle as a policy choice

**Wrong:** The second Open asks Kyle whether a citywide crime-control district expands on the city's tax date or requires a separate boundary action. That is a legal/evidence question, not a utility preference. Section 321.1055(c)'s requirement to supply boundaries does not by itself settle how annexation changes the district.

**Evidence:** The local source inventory supports separate district boundary evidence; it does not establish the scenario's assumed automatic expansion. [Texas Tax Code §321.1055](https://tcss.legis.texas.gov/resources/TX/htm/TX.321.htm#321.1055).

**Fix:** Assign this Open to a **citation check/tax counsel**, with rates responsible for recording the resulting boundary and effective date. Keep the invented synchronized boundary explicitly conditional until that check is resolved; Kyle can decide operational handling once the legal dates are known.
