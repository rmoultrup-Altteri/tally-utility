-- Codex r3: PREDICTED, not executed by reviewer.
-- Run as owner on a FRESH scratch clone of tally with frozen r3 applied.
-- Never run on tally. No role is created, dropped or altered.
-- The author creates/drops the scratch clone outside this transaction.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path = '';
CREATE FUNCTION pg_temp.patch_sql() RETURNS text LANGUAGE sql AS $wrapper$
SELECT $frozen$
-- ============================================================================
-- PATCH v5.4.2-29 — every Texas county and its time zone, loaded once as
--                    shared place data (r3, 2026-11-05)
-- ============================================================================
-- Authority:   Ryan, 2026-11-04 (DECISION-LOG, the -28 r2 entry: "counties
--              and time zones rarely change; load them once for every
--              utility"). Board claim -29 (rates stream). -16 residual R2:
--              "counties ... with their facts (time zones ...) are loaded by
--              reviewed migrations from their publishers (Census FIPS)".
--              -28 known limit L1: until the counties are loaded, a non-zero
--              state-agency fee outside El Paso and Hudspeth is refused.
--
-- Sources (both copied into the repo):
--   counties   US Census Bureau, 2020 FIPS county codes for Texas,
--              https://www2.census.gov/geo/docs/reference/codes2020/cou/st48_tx_cou2020.txt
--              = application/places-sources/census-st48_tx_cou2020.txt
--              (md5 e1ea7280eb41b680feb924b3bef2c411; 254 counties, every one
--              class H1, status A). tests/v5.4.2-29/source-check-29.sh checks
--              that the list below is exactly that file.
--   time zones 49 CFR 71.7(e) (eCFR, current 2026-10-01): the
--              Central/Mountain line runs "westerly along the Texas-New
--              Mexico boundary to the east line of Hudspeth County, Tex.;
--              thence southerly along the east line of Hudspeth County ... to
--              the boundary between the United States and Mexico". West of
--              it: El Paso (48141) and Hudspeth (48229), Mountain
--              (America/Denver, as -16 seeded them). East of it: the other
--              252, Central (America/Chicago).
--
-- What it does: for each of the 254 counties, a places row (kind county,
--   state TX, the five-digit FIPS code, the Census name, parent Texas, in
--   force from 1900-01-01 as -16 R2 requires) and one time_zone fact over the
--   same range. El Paso and Hudspeth exist already (-16's seed) and are
--   checked, not reloaded. Data only: no table, function or grant changes.
--
-- Rules (r2: everything is judged as of 1900-01-01, the date the load
-- writes, not as of today — review r1, Opus S1, Fable S1):
--   * A county already present on 1900-01-01 must match: the same name, and
--     a time_zone fact in force that day with the same zone. A mismatch
--     refuses the whole load (the load never overwrites a place; a
--     correction is a close and a successor, its own reviewed migration).
--     A code with rows but none in force on 1900-01-01 refuses too.
--   * After the load, the Texas counties in force on 1900-01-01 are exactly
--     the 254, each under Texas with a zone fact in force that day of the
--     list's zone, Mountain exactly for 48141 and 48229. Anything else
--     refuses.
--   * Re-applying is a no-op, also after a later migration corrects a
--     county (closes it or its zone fact and adds a successor), closes one
--     without a successor, adds a county from a later date, or replaces
--     Texas itself (closes the state and adds a successor; r3): what was in
--     force on 1900-01-01 does not change. Texas, like each county, is the
--     row in force that day (r3; review r2, Codex B1: r2 still asked for an
--     open state). A county the load must insert goes under that row; if it
--     has since closed, the existing parent rule refuses the insert.
--   * Runs as the owner (tally_app cannot write places), under READ
--     COMMITTED.
--   * The in-loop comparison names the county that differs (the diagnostic
--     layer); the postcondition is the guard, and catches what the loop
--     would have (tests/v5.4.2-29/mutations-29.sh shows each layer alone).
--
-- KNOWN LIMITS
--   L1. A premise still needs its county recorded. The lookup reads the
--       premise's memberships (premise_place_memberships, the utility's
--       data); a premise with no county membership is refused as before.
--       What this patch removes is that most counties could not be recorded
--       at all. Deriving the county from the address is the application's
--       (the membership's evidence), not this patch's.
--   L2. Culberson County (48109) is Central by law; local practice in Van
--       Horn is Mountain. The schema stores the legal zone. If a utility
--       there bills on local time, that is its own setting, not a place
--       fact.
--   L3. 49 CFR 71.7(g) puts a municipality on the line in Mountain time.
--       The line runs along Texas's whole western border with New Mexico,
--       not only past Hudspeth County, so towns on that border (Farwell,
--       Texline: predicted, not checked against their limits) may be
--       Mountain by law while keeping Central in practice. Cities are not
--       loaded here; a city row's own zone (it outranks its county's) is how
--       such a city would be recorded, settled when cities are loaded.
--   L4. Counties only. Cities, special districts, transit authorities and
--       tax jurisdictions (the Comptroller's files) are later loads.
--   L5. Dated from 1900-01-01 (-16 R2): no bill reads a place before that.
--       No Texas county has been created or renamed since 1931.
--   L6. El Paso and Hudspeth keep -16's source notes ("Texas county (FIPS
--       n).") and -16's citation; the other 252 cite the Census file and
--       49 CFR 71.6(a). Changing a stored note would take a close and a
--       successor; the provenance is in this header.
--
-- Older tests that planted real county codes as fixtures (battery -16:
-- Travis 48453, Harris 48201, Bastrop 48021; race place-close-16: Anderson
-- 48001, Andrews 48003; battery -28: Travis 48453) now use even codes
-- (48990-48998). Texas county codes are odd, so these can never be real.
-- (A new fixture must use a code not on the Census list; battery -25's
-- 48925 is odd but beyond 48507, also never real.)
-- ============================================================================

DO $patch29$
DECLARE
    c_from CONSTANT date := DATE '1900-01-01';
    v_tx uuid;
    v_place public.places%ROWTYPE;
    v_zone text;
    v_nrows integer;
    v_bad text;
    v_new integer := 0;
    r record;
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'v5.4.2-29: run under READ COMMITTED (got %)', current_setting('transaction_isolation');
    END IF;
    SELECT p.id INTO v_tx FROM public.places p
     WHERE p.kind_code = 'state' AND p.state_code = 'TX' AND p.place_code = 'TX'
       AND daterange(p.effective_from, p.effective_to, '[)') @> c_from;
    IF v_tx IS NULL THEN
        RAISE EXCEPTION 'v5.4.2-29 precondition: no Texas state place in force on %', c_from;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.place_kinds WHERE kind_code = 'county' AND code_pattern = '^[0-9]{5}$')
       OR NOT EXISTS (SELECT 1 FROM public.place_fact_kinds WHERE fact_code = 'time_zone' AND 'county' = ANY (place_kinds)) THEN
        RAISE EXCEPTION 'v5.4.2-29 precondition: the county kind or the time_zone fact kind is not as -16 built it';
    END IF;

    CREATE TEMP TABLE IF NOT EXISTS p29_counties (fips text PRIMARY KEY, name text NOT NULL, zone text NOT NULL) ON COMMIT DROP;
    TRUNCATE p29_counties;
    INSERT INTO p29_counties (fips, name, zone) VALUES
    ('48001', 'Anderson County', 'America/Chicago'),
    ('48003', 'Andrews County', 'America/Chicago'),
    ('48005', 'Angelina County', 'America/Chicago'),
    ('48007', 'Aransas County', 'America/Chicago'),
    ('48009', 'Archer County', 'America/Chicago'),
    ('48011', 'Armstrong County', 'America/Chicago'),
    ('48013', 'Atascosa County', 'America/Chicago'),
    ('48015', 'Austin County', 'America/Chicago'),
    ('48017', 'Bailey County', 'America/Chicago'),
    ('48019', 'Bandera County', 'America/Chicago'),
    ('48021', 'Bastrop County', 'America/Chicago'),
    ('48023', 'Baylor County', 'America/Chicago'),
    ('48025', 'Bee County', 'America/Chicago'),
    ('48027', 'Bell County', 'America/Chicago'),
    ('48029', 'Bexar County', 'America/Chicago'),
    ('48031', 'Blanco County', 'America/Chicago'),
    ('48033', 'Borden County', 'America/Chicago'),
    ('48035', 'Bosque County', 'America/Chicago'),
    ('48037', 'Bowie County', 'America/Chicago'),
    ('48039', 'Brazoria County', 'America/Chicago'),
    ('48041', 'Brazos County', 'America/Chicago'),
    ('48043', 'Brewster County', 'America/Chicago'),
    ('48045', 'Briscoe County', 'America/Chicago'),
    ('48047', 'Brooks County', 'America/Chicago'),
    ('48049', 'Brown County', 'America/Chicago'),
    ('48051', 'Burleson County', 'America/Chicago'),
    ('48053', 'Burnet County', 'America/Chicago'),
    ('48055', 'Caldwell County', 'America/Chicago'),
    ('48057', 'Calhoun County', 'America/Chicago'),
    ('48059', 'Callahan County', 'America/Chicago'),
    ('48061', 'Cameron County', 'America/Chicago'),
    ('48063', 'Camp County', 'America/Chicago'),
    ('48065', 'Carson County', 'America/Chicago'),
    ('48067', 'Cass County', 'America/Chicago'),
    ('48069', 'Castro County', 'America/Chicago'),
    ('48071', 'Chambers County', 'America/Chicago'),
    ('48073', 'Cherokee County', 'America/Chicago'),
    ('48075', 'Childress County', 'America/Chicago'),
    ('48077', 'Clay County', 'America/Chicago'),
    ('48079', 'Cochran County', 'America/Chicago'),
    ('48081', 'Coke County', 'America/Chicago'),
    ('48083', 'Coleman County', 'America/Chicago'),
    ('48085', 'Collin County', 'America/Chicago'),
    ('48087', 'Collingsworth County', 'America/Chicago'),
    ('48089', 'Colorado County', 'America/Chicago'),
    ('48091', 'Comal County', 'America/Chicago'),
    ('48093', 'Comanche County', 'America/Chicago'),
    ('48095', 'Concho County', 'America/Chicago'),
    ('48097', 'Cooke County', 'America/Chicago'),
    ('48099', 'Coryell County', 'America/Chicago'),
    ('48101', 'Cottle County', 'America/Chicago'),
    ('48103', 'Crane County', 'America/Chicago'),
    ('48105', 'Crockett County', 'America/Chicago'),
    ('48107', 'Crosby County', 'America/Chicago'),
    ('48109', 'Culberson County', 'America/Chicago'),
    ('48111', 'Dallam County', 'America/Chicago'),
    ('48113', 'Dallas County', 'America/Chicago'),
    ('48115', 'Dawson County', 'America/Chicago'),
    ('48117', 'Deaf Smith County', 'America/Chicago'),
    ('48119', 'Delta County', 'America/Chicago'),
    ('48121', 'Denton County', 'America/Chicago'),
    ('48123', 'DeWitt County', 'America/Chicago'),
    ('48125', 'Dickens County', 'America/Chicago'),
    ('48127', 'Dimmit County', 'America/Chicago'),
    ('48129', 'Donley County', 'America/Chicago'),
    ('48131', 'Duval County', 'America/Chicago'),
    ('48133', 'Eastland County', 'America/Chicago'),
    ('48135', 'Ector County', 'America/Chicago'),
    ('48137', 'Edwards County', 'America/Chicago'),
    ('48139', 'Ellis County', 'America/Chicago'),
    ('48141', 'El Paso County', 'America/Denver'),
    ('48143', 'Erath County', 'America/Chicago'),
    ('48145', 'Falls County', 'America/Chicago'),
    ('48147', 'Fannin County', 'America/Chicago'),
    ('48149', 'Fayette County', 'America/Chicago'),
    ('48151', 'Fisher County', 'America/Chicago'),
    ('48153', 'Floyd County', 'America/Chicago'),
    ('48155', 'Foard County', 'America/Chicago'),
    ('48157', 'Fort Bend County', 'America/Chicago'),
    ('48159', 'Franklin County', 'America/Chicago'),
    ('48161', 'Freestone County', 'America/Chicago'),
    ('48163', 'Frio County', 'America/Chicago'),
    ('48165', 'Gaines County', 'America/Chicago'),
    ('48167', 'Galveston County', 'America/Chicago'),
    ('48169', 'Garza County', 'America/Chicago'),
    ('48171', 'Gillespie County', 'America/Chicago'),
    ('48173', 'Glasscock County', 'America/Chicago'),
    ('48175', 'Goliad County', 'America/Chicago'),
    ('48177', 'Gonzales County', 'America/Chicago'),
    ('48179', 'Gray County', 'America/Chicago'),
    ('48181', 'Grayson County', 'America/Chicago'),
    ('48183', 'Gregg County', 'America/Chicago'),
    ('48185', 'Grimes County', 'America/Chicago'),
    ('48187', 'Guadalupe County', 'America/Chicago'),
    ('48189', 'Hale County', 'America/Chicago'),
    ('48191', 'Hall County', 'America/Chicago'),
    ('48193', 'Hamilton County', 'America/Chicago'),
    ('48195', 'Hansford County', 'America/Chicago'),
    ('48197', 'Hardeman County', 'America/Chicago'),
    ('48199', 'Hardin County', 'America/Chicago'),
    ('48201', 'Harris County', 'America/Chicago'),
    ('48203', 'Harrison County', 'America/Chicago'),
    ('48205', 'Hartley County', 'America/Chicago'),
    ('48207', 'Haskell County', 'America/Chicago'),
    ('48209', 'Hays County', 'America/Chicago'),
    ('48211', 'Hemphill County', 'America/Chicago'),
    ('48213', 'Henderson County', 'America/Chicago'),
    ('48215', 'Hidalgo County', 'America/Chicago'),
    ('48217', 'Hill County', 'America/Chicago'),
    ('48219', 'Hockley County', 'America/Chicago'),
    ('48221', 'Hood County', 'America/Chicago'),
    ('48223', 'Hopkins County', 'America/Chicago'),
    ('48225', 'Houston County', 'America/Chicago'),
    ('48227', 'Howard County', 'America/Chicago'),
    ('48229', 'Hudspeth County', 'America/Denver'),
    ('48231', 'Hunt County', 'America/Chicago'),
    ('48233', 'Hutchinson County', 'America/Chicago'),
    ('48235', 'Irion County', 'America/Chicago'),
    ('48237', 'Jack County', 'America/Chicago'),
    ('48239', 'Jackson County', 'America/Chicago'),
    ('48241', 'Jasper County', 'America/Chicago'),
    ('48243', 'Jeff Davis County', 'America/Chicago'),
    ('48245', 'Jefferson County', 'America/Chicago'),
    ('48247', 'Jim Hogg County', 'America/Chicago'),
    ('48249', 'Jim Wells County', 'America/Chicago'),
    ('48251', 'Johnson County', 'America/Chicago'),
    ('48253', 'Jones County', 'America/Chicago'),
    ('48255', 'Karnes County', 'America/Chicago'),
    ('48257', 'Kaufman County', 'America/Chicago'),
    ('48259', 'Kendall County', 'America/Chicago'),
    ('48261', 'Kenedy County', 'America/Chicago'),
    ('48263', 'Kent County', 'America/Chicago'),
    ('48265', 'Kerr County', 'America/Chicago'),
    ('48267', 'Kimble County', 'America/Chicago'),
    ('48269', 'King County', 'America/Chicago'),
    ('48271', 'Kinney County', 'America/Chicago'),
    ('48273', 'Kleberg County', 'America/Chicago'),
    ('48275', 'Knox County', 'America/Chicago'),
    ('48277', 'Lamar County', 'America/Chicago'),
    ('48279', 'Lamb County', 'America/Chicago'),
    ('48281', 'Lampasas County', 'America/Chicago'),
    ('48283', 'La Salle County', 'America/Chicago'),
    ('48285', 'Lavaca County', 'America/Chicago'),
    ('48287', 'Lee County', 'America/Chicago'),
    ('48289', 'Leon County', 'America/Chicago'),
    ('48291', 'Liberty County', 'America/Chicago'),
    ('48293', 'Limestone County', 'America/Chicago'),
    ('48295', 'Lipscomb County', 'America/Chicago'),
    ('48297', 'Live Oak County', 'America/Chicago'),
    ('48299', 'Llano County', 'America/Chicago'),
    ('48301', 'Loving County', 'America/Chicago'),
    ('48303', 'Lubbock County', 'America/Chicago'),
    ('48305', 'Lynn County', 'America/Chicago'),
    ('48307', 'McCulloch County', 'America/Chicago'),
    ('48309', 'McLennan County', 'America/Chicago'),
    ('48311', 'McMullen County', 'America/Chicago'),
    ('48313', 'Madison County', 'America/Chicago'),
    ('48315', 'Marion County', 'America/Chicago'),
    ('48317', 'Martin County', 'America/Chicago'),
    ('48319', 'Mason County', 'America/Chicago'),
    ('48321', 'Matagorda County', 'America/Chicago'),
    ('48323', 'Maverick County', 'America/Chicago'),
    ('48325', 'Medina County', 'America/Chicago'),
    ('48327', 'Menard County', 'America/Chicago'),
    ('48329', 'Midland County', 'America/Chicago'),
    ('48331', 'Milam County', 'America/Chicago'),
    ('48333', 'Mills County', 'America/Chicago'),
    ('48335', 'Mitchell County', 'America/Chicago'),
    ('48337', 'Montague County', 'America/Chicago'),
    ('48339', 'Montgomery County', 'America/Chicago'),
    ('48341', 'Moore County', 'America/Chicago'),
    ('48343', 'Morris County', 'America/Chicago'),
    ('48345', 'Motley County', 'America/Chicago'),
    ('48347', 'Nacogdoches County', 'America/Chicago'),
    ('48349', 'Navarro County', 'America/Chicago'),
    ('48351', 'Newton County', 'America/Chicago'),
    ('48353', 'Nolan County', 'America/Chicago'),
    ('48355', 'Nueces County', 'America/Chicago'),
    ('48357', 'Ochiltree County', 'America/Chicago'),
    ('48359', 'Oldham County', 'America/Chicago'),
    ('48361', 'Orange County', 'America/Chicago'),
    ('48363', 'Palo Pinto County', 'America/Chicago'),
    ('48365', 'Panola County', 'America/Chicago'),
    ('48367', 'Parker County', 'America/Chicago'),
    ('48369', 'Parmer County', 'America/Chicago'),
    ('48371', 'Pecos County', 'America/Chicago'),
    ('48373', 'Polk County', 'America/Chicago'),
    ('48375', 'Potter County', 'America/Chicago'),
    ('48377', 'Presidio County', 'America/Chicago'),
    ('48379', 'Rains County', 'America/Chicago'),
    ('48381', 'Randall County', 'America/Chicago'),
    ('48383', 'Reagan County', 'America/Chicago'),
    ('48385', 'Real County', 'America/Chicago'),
    ('48387', 'Red River County', 'America/Chicago'),
    ('48389', 'Reeves County', 'America/Chicago'),
    ('48391', 'Refugio County', 'America/Chicago'),
    ('48393', 'Roberts County', 'America/Chicago'),
    ('48395', 'Robertson County', 'America/Chicago'),
    ('48397', 'Rockwall County', 'America/Chicago'),
    ('48399', 'Runnels County', 'America/Chicago'),
    ('48401', 'Rusk County', 'America/Chicago'),
    ('48403', 'Sabine County', 'America/Chicago'),
    ('48405', 'San Augustine County', 'America/Chicago'),
    ('48407', 'San Jacinto County', 'America/Chicago'),
    ('48409', 'San Patricio County', 'America/Chicago'),
    ('48411', 'San Saba County', 'America/Chicago'),
    ('48413', 'Schleicher County', 'America/Chicago'),
    ('48415', 'Scurry County', 'America/Chicago'),
    ('48417', 'Shackelford County', 'America/Chicago'),
    ('48419', 'Shelby County', 'America/Chicago'),
    ('48421', 'Sherman County', 'America/Chicago'),
    ('48423', 'Smith County', 'America/Chicago'),
    ('48425', 'Somervell County', 'America/Chicago'),
    ('48427', 'Starr County', 'America/Chicago'),
    ('48429', 'Stephens County', 'America/Chicago'),
    ('48431', 'Sterling County', 'America/Chicago'),
    ('48433', 'Stonewall County', 'America/Chicago'),
    ('48435', 'Sutton County', 'America/Chicago'),
    ('48437', 'Swisher County', 'America/Chicago'),
    ('48439', 'Tarrant County', 'America/Chicago'),
    ('48441', 'Taylor County', 'America/Chicago'),
    ('48443', 'Terrell County', 'America/Chicago'),
    ('48445', 'Terry County', 'America/Chicago'),
    ('48447', 'Throckmorton County', 'America/Chicago'),
    ('48449', 'Titus County', 'America/Chicago'),
    ('48451', 'Tom Green County', 'America/Chicago'),
    ('48453', 'Travis County', 'America/Chicago'),
    ('48455', 'Trinity County', 'America/Chicago'),
    ('48457', 'Tyler County', 'America/Chicago'),
    ('48459', 'Upshur County', 'America/Chicago'),
    ('48461', 'Upton County', 'America/Chicago'),
    ('48463', 'Uvalde County', 'America/Chicago'),
    ('48465', 'Val Verde County', 'America/Chicago'),
    ('48467', 'Van Zandt County', 'America/Chicago'),
    ('48469', 'Victoria County', 'America/Chicago'),
    ('48471', 'Walker County', 'America/Chicago'),
    ('48473', 'Waller County', 'America/Chicago'),
    ('48475', 'Ward County', 'America/Chicago'),
    ('48477', 'Washington County', 'America/Chicago'),
    ('48479', 'Webb County', 'America/Chicago'),
    ('48481', 'Wharton County', 'America/Chicago'),
    ('48483', 'Wheeler County', 'America/Chicago'),
    ('48485', 'Wichita County', 'America/Chicago'),
    ('48487', 'Wilbarger County', 'America/Chicago'),
    ('48489', 'Willacy County', 'America/Chicago'),
    ('48491', 'Williamson County', 'America/Chicago'),
    ('48493', 'Wilson County', 'America/Chicago'),
    ('48495', 'Winkler County', 'America/Chicago'),
    ('48497', 'Wise County', 'America/Chicago'),
    ('48499', 'Wood County', 'America/Chicago'),
    ('48501', 'Yoakum County', 'America/Chicago'),
    ('48503', 'Young County', 'America/Chicago'),
    ('48505', 'Zapata County', 'America/Chicago'),
    ('48507', 'Zavala County', 'America/Chicago')
;

    FOR r IN SELECT * FROM p29_counties ORDER BY fips LOOP
        -- The row of this code in force on 1900-01-01 (at most one:
        -- places_no_overlap), closed later or not.
        SELECT * INTO v_place FROM public.places p
         WHERE p.kind_code = 'county' AND p.state_code = 'TX' AND p.place_code = r.fips
           AND daterange(p.effective_from, p.effective_to, '[)') @> c_from;
        IF FOUND THEN
            -- its zone fact in force on 1900-01-01 (at most one:
            -- place_facts_no_overlap); none reads as NULL. Its parent is
            -- Texas: -16's place trigger admits no other parent for a Texas
            -- county; the postcondition re-checks it.
            SELECT f.value #>> '{}' INTO v_zone FROM public.place_facts f
             WHERE f.place_id = v_place.id AND f.fact_code = 'time_zone'
               AND daterange(f.effective_from, f.effective_to, '[)') @> c_from;
            IF v_place.name IS DISTINCT FROM r.name OR v_zone IS DISTINCT FROM r.zone THEN
                RAISE EXCEPTION 'v5.4.2-29: county % is already present on % as % (zone %), not as the load has it (%, %); the load does not overwrite a place',
                    r.fips, c_from, v_place.name, coalesce(v_zone, 'none'), r.name, r.zone;
            END IF;
            CONTINUE;
        END IF;
        SELECT count(*) INTO v_nrows FROM public.places p
         WHERE p.kind_code = 'county' AND p.state_code = 'TX' AND p.place_code = r.fips;
        IF v_nrows > 0 THEN
            RAISE EXCEPTION 'v5.4.2-29: county % has % row(s), none in force on %; the load does not overwrite or backdate a place',
                r.fips, v_nrows, c_from;
        END IF;
        INSERT INTO public.places (kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
        VALUES ('county', 'TX', r.fips, r.name, v_tx, c_from,
                format('US Census Bureau 2020 FIPS county codes for Texas (st48_tx_cou2020.txt): %s, FIPS %s (v5.4.2-29).', r.name, r.fips))
        RETURNING * INTO v_place;
        INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
        VALUES (v_place.id, 'time_zone', to_jsonb(r.zone), c_from,
                CASE r.zone WHEN 'America/Denver'
                     THEN '49 CFR 71.7(e), 71.8: west of the east line of Hudspeth County, Texas is Mountain time (v5.4.2-29).'
                     ELSE '49 CFR 71.6(a), 71.7(e): Texas east of the east line of Hudspeth County is Central time (v5.4.2-29).' END);
        v_new := v_new + 1;
    END LOOP;

    -- Postcondition (the guard), as of 1900-01-01: the Texas counties in
    -- force that day are exactly the list, each under Texas with a zone fact
    -- in force that day of the list's zone.
    SELECT string_agg(x.what, '; ') INTO v_bad FROM (
        SELECT 'county ' || p.place_code || ' is not on the Census list' AS what
          FROM public.places p
         WHERE p.kind_code = 'county' AND p.state_code = 'TX'
           AND daterange(p.effective_from, p.effective_to, '[)') @> c_from
           AND NOT EXISTS (SELECT 1 FROM p29_counties c WHERE c.fips = p.place_code)
        UNION ALL
        SELECT 'county ' || c.fips || ' (' || c.name || ') is missing, misnamed or misparented on 1900-01-01'
          FROM p29_counties c
         WHERE NOT EXISTS (SELECT 1 FROM public.places p
                            WHERE p.kind_code = 'county' AND p.state_code = 'TX' AND p.place_code = c.fips
                              AND daterange(p.effective_from, p.effective_to, '[)') @> c_from
                              AND p.name = c.name AND p.parent_place_id = v_tx)
        UNION ALL
        SELECT 'county ' || c.fips || ' has no time_zone fact of ' || c.zone || ' in force on 1900-01-01'
          FROM p29_counties c
          JOIN public.places p ON p.kind_code = 'county' AND p.state_code = 'TX' AND p.place_code = c.fips
                              AND daterange(p.effective_from, p.effective_to, '[)') @> c_from
         WHERE NOT EXISTS (SELECT 1 FROM public.place_facts f
                            WHERE f.place_id = p.id AND f.fact_code = 'time_zone'
                              AND daterange(f.effective_from, f.effective_to, '[)') @> c_from
                              AND f.value = to_jsonb(c.zone))
    ) x;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'v5.4.2-29 postcondition: %', v_bad;
    END IF;
    IF (SELECT count(*) FROM p29_counties) <> 254
       OR (SELECT array_agg(fips ORDER BY fips) FROM p29_counties WHERE zone = 'America/Denver') IS DISTINCT FROM ARRAY['48141', '48229'] THEN
        RAISE EXCEPTION 'v5.4.2-29 postcondition: the list is not 254 counties with Mountain exactly at 48141 and 48229';
    END IF;
    RAISE NOTICE 'v5.4.2-29: % counties loaded, % already present', v_new, 254 - v_new;
END;
$patch29$;
$frozen$::text
$wrapper$;
CREATE FUNCTION pg_temp.check_it(label text, condition boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 IF condition IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL %', label; END IF;
 RAISE NOTICE 'PASS %', label;
END $$;
CREATE FUNCTION pg_temp.run_sql(label text, command text, expected_state text DEFAULT NULL, fragment text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN
  EXECUTE command;
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '% caught SQLSTATE=% message=%', label, SQLSTATE, SQLERRM;
  IF expected_state IS NULL OR SQLSTATE <> expected_state OR strpos(SQLERRM, fragment) = 0 THEN
   RAISE;
  END IF;
  RAISE NOTICE 'PASS % (expected refusal)', label;
  RETURN;
 END;
 IF expected_state IS NOT NULL THEN RAISE EXCEPTION 'FAIL %: accepted', label; END IF;
 RAISE NOTICE 'PASS % (accepted)', label;
END $$;
CREATE FUNCTION pg_temp.fingerprint() RETURNS text LANGUAGE sql AS $$
 SELECT md5(string_agg(row_text, E'\n' ORDER BY row_text)) FROM (
  SELECT 'places:' || to_jsonb(p)::text AS row_text FROM public.places p
  UNION ALL SELECT 'facts:' || to_jsonb(f)::text FROM public.place_facts f
 ) s
$$;

-- Reconstruct the two-county pre-29 seed from the required post-29 clone.
-- Trigger bypass is ONLY for fixture removal. All guards are restored before
-- any tested INSERT or patch call. This is not claimed as an application path.
ALTER TABLE public.place_facts DISABLE TRIGGER a_enforce_place_fact;
DELETE FROM public.place_facts f USING public.places p WHERE f.place_id=p.id
 AND p.kind_code='county' AND p.state_code='TX' AND p.place_code NOT IN ('48141','48229');
ALTER TABLE public.place_facts ENABLE ALWAYS TRIGGER a_enforce_place_fact;
ALTER TABLE public.places DISABLE TRIGGER a_enforce_place;
DELETE FROM public.places WHERE kind_code='county' AND state_code='TX' AND place_code NOT IN ('48141','48229');
ALTER TABLE public.places ENABLE ALWAYS TRIGGER a_enforce_place;
-- B1: replace the state and its children through ordinary close/successor writes.
-- Fresh tally is expected to have no tenant citations of these seeded places.
-- If any setup close refuses, this is SETUP FAILURE, not a reproduction of B1.
DO $setup$
DECLARE r record; new_parent uuid;
BEGIN
 CREATE TEMP TABLE old_tree AS
 WITH RECURSIVE tree AS (
  SELECT p.id,0 AS depth FROM public.places p WHERE kind_code='state' AND state_code='TX' AND place_code='TX' AND effective_to IS NULL
  UNION ALL SELECT p.id,t.depth+1 FROM public.places p JOIN tree t ON p.parent_place_id=t.id
 ) SELECT p.*,t.depth,public.uuid_generate_v4() AS successor FROM tree t JOIN public.places p ON p.id=t.id;
 IF (SELECT count(*) FROM pg_temp.old_tree WHERE depth=0) <> 1 THEN RAISE EXCEPTION 'expected one state'; END IF;
 CREATE TEMP TABLE old_facts AS SELECT f.* FROM public.place_facts f JOIN pg_temp.old_tree t ON t.id=f.place_id;
 UPDATE public.place_facts f SET effective_to=DATE '2027-01-01' FROM pg_temp.old_tree t WHERE f.place_id=t.id AND f.effective_to IS NULL;
 FOR r IN SELECT * FROM pg_temp.old_tree ORDER BY depth DESC,id LOOP
  IF r.effective_to IS NULL THEN UPDATE public.places SET effective_to=DATE '2027-01-01' WHERE id=r.id; END IF;
 END LOOP;
 FOR r IN SELECT * FROM pg_temp.old_tree WHERE effective_to IS NULL ORDER BY depth,id LOOP
  SELECT successor INTO new_parent FROM pg_temp.old_tree WHERE id=r.parent_place_id;
  INSERT INTO public.places(id,kind_code,state_code,place_code,name,parent_place_id,effective_from,source_note)
  VALUES(r.successor,r.kind_code,r.state_code,r.place_code,r.name,new_parent,DATE '2027-01-01','probe: state hierarchy successor');
 END LOOP;
 INSERT INTO public.place_facts(place_id,fact_code,fact_key,value,effective_from,source_note)
 SELECT t.successor,f.fact_code,f.fact_key,f.value,DATE '2027-01-01','probe: successor fact'
 FROM pg_temp.old_facts f JOIN pg_temp.old_tree t ON t.id=f.place_id
 WHERE f.effective_to IS NULL AND t.effective_to IS NULL;
 RAISE NOTICE 'SETUP PASS: state, children and facts closed and succeeded with all guards enabled';
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'SETUP FAILURE SQLSTATE=% message=%',SQLSTATE,SQLERRM;
 RAISE;
END $setup$;
CREATE TEMP TABLE snapshot AS SELECT pg_temp.fingerprint() AS digest;
SELECT pg_temp.run_sql('P10b new county under closed historical Texas',pg_temp.patch_sql(),
 '23514','is not a state of state TX in force over 1900-01-01..open');
SELECT pg_temp.check_it('P10b refusal preserves every row',(SELECT digest FROM pg_temp.snapshot)=pg_temp.fingerprint());
ROLLBACK;
