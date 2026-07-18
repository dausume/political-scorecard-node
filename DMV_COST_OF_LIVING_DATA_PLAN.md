# DMV Cost-of-Living Data Plan — official sources, profiles, and the scoring machinery

**Written 2026-07-16 (Dustin's directive: what data is CRITICAL for
analyzing housing + cost of living per group/profile, using ONLY
public official government sources, cited; DC + Virginia + Maryland,
DMV region focus; account for housing longevity, builder impact on
longevity, rental-company impact over time, the cost to escape a bad
rental, and how many people report poor living conditions.)**

Status: PLAN + SOURCE CATALOG. Nothing seeded yet — the source
catalog below is the input to a data-refresh/seeding pass that
replaces `housing_affordability_seed.py`'s flagged "representative
estimates" with cited DMV values and adds the persona profiles.

---

## 1. How this lands in the existing machinery (read first)

The engine already has every needed shape — this plan adds DATA and
a few vocabulary rows, not architecture:

- **`ScoreTerm` + `ContextualizedValue`** (scoring_basis): each
  official statistic becomes term rows with `provenance_id` citing
  agency + table + vintage, values contextualized under
  `[geography, timeframe]` `ScoreContext` rows. The housing seed's
  own provenance strings already flag "representative 2022 estimate…
  flag for a live data-refresh pass" — §3 is that refresh, DMV-first.
- **Profiles are `ScoreContext` rows + PUMS-backed baselines.** A
  "fresh high-school graduate" or "part-timer with 2 roommates" is a
  PERSONA CONTEXT (context kind: persona/scenario), so any term can
  be contextualized by it. Census ACS **PUMS microdata** is the one
  official source that can be CUT to arbitrary personas (age ×
  education × employment × household composition × rent share), so
  each persona baseline is a derived record whose provenance names
  the PUMS vintage + filter — derived-from-official, never invented.
- **`CostCategory` / `SurvivalCostProfile`** (scr-12a): the survival
  walkthrough already models per-household effective cost of living
  (kinds: survival / work-required / pseudo-tax / discretionary,
  location+month contexts, pseudo-tax as a votable knob). This plan
  adds (a) OFFICIAL-BASELINE profiles — synthetic
  `SurvivalCostProfile` rows per persona × DMV jurisdiction whose
  entries come from the §3 sources (provenance on every entry),
  sitting NEXT TO citizen-entered profiles for comparison ("what the
  government data says surviving here costs" vs "what residents
  actually report"); and (b) new categories in §5 (escape-costs,
  displacement-risk).
- **Concept-tree interconnection** (Dustin's "interconnections of
  concept trees for different topics"): the existing mechanisms are
  `equivalent_terms_json` (purpose-equivalence across scorecards),
  `abstract_tags_json` + the scr-5 abstraction matcher (generic
  intents → suggested bindings), mechanism-B worldview elections
  (whose weighting IS the interconnection between price-only,
  quality-weighted, and supply-first views of the same tree), and
  mechanism-C `DecisionProcedureEdge` graphs. §6 uses all four:
  housing-longevity terms tag into BOTH the housing tree and the
  household-wealth/economy tree, so "cheap construction quietly makes
  the whole economy poorer" is expressible as shared terms with
  different weights per concept — exactly the housing seed's
  three-worldview disagreement, now with data under it.
- **Ingestion**: `POST /api/scoring/ingest` (data_ingestion.py)
  already refuses unknown terms/contexts and never invents metric
  semantics — the vocabulary rows in §5 land first, then values.

## 2. The personas (initial vocabulary — knobs, extendable by rows)

Each is one persona `ScoreContext` + one official-baseline
`SurvivalCostProfile` per jurisdiction (DC; NoVA: Arlington,
Alexandria, Fairfax, Loudoun, Prince William; MD: Montgomery,
Prince George's, Frederick):

| persona (kebab key) | definition (PUMS-cuttable) |
|---|---|
| fresh-hs-graduate | age 18-21, high-school diploma ≤2yr old, no degree, first-time full-time worker at 10th-25th pctile wage |
| part-timer-2-roommates | part-time worker (<35h), 3-person nonfamily household, splits a 3BR at 1/3 gross rent |
| part-timer-n-roommates | as above with N a knob (2..5), rent share = FMR(N BR)/N+1? — modeled per-N |
| single-fulltime-median | 1-person household, full-time at area median wage for entry occupations |
| minimum-wage-fulltime | 1-person, jurisdiction minimum wage × 2080h (DC/MD/VA minimums DIFFER — official rates cited per state) |
| young-family-starter | 2 adults 1 child, one full + one part-time earner, 2BR |
| fixed-income-senior | SSA average benefit, 1-person, 1BR |

Persona × geography × timeframe = the context triple every value
lands under. Per-persona budget lines follow the CostCategory
vocabulary: housing (FMR/SAFMR + ACS gross rent), utilities (EIA +
ACS), food (USDA plans by age/sex), transport-work (WMATA fares /
commuting), healthcare, childcare (young-family only), debt-minimums,
pseudo-tax subscriptions — plus §5's escape-cost reserve.

## 3. Federal source catalog (official only, cited)

FILLED FROM RESEARCH — see §3 tables appended below.

## 4. DC / Virginia / Maryland state + local catalog

FILLED FROM RESEARCH — see §4 tables appended below.

## 5. The obscure factors as vocabulary (Dustin's four)

1. **Housing longevity** — terms: `housing-stock-median-age`
   (ACS year-built), `housing-inadequacy-rate` (AHS severe/moderate),
   `structural-problem-rate` (AHS variables), `demolition-turnover`
   (permits). Longevity is BOTH a housing-tree term and an
   economy-tree term (depreciation of the region's housing capital) —
   the interconnection case from the housing seed, now data-backed.
2. **Builder impact on longevity** — official signals only:
   contractor licensing + DISCIPLINARY actions (VA DPOR, MD MHIC,
   DC DOB), building permits naming contractors (local open data),
   OSHA enforcement by construction employer, new-home warranty
   statutes. Modeled as subject-kind `construction-company`
   ScoreSubjects with per-company terms (violations, discipline,
   permit volume); the LINK company→longevity stays an assertion-
   with-evidence (mechanism scr-6 ScoreAssertion + validity votes),
   never presented as an official causal statistic — no official
   source publishes that causality; the honest model is official
   per-company signals + votable professional-judgment weighting
   (exactly the housing seed's construction-quality term, now with
   named subjects).
3. **Rental-company impact on cost of living over time** — subject
   kind `rental-company`: HUD REAC/NSPIRE inspection scores
   (multifamily, public), rent-increase petitions (DC RAD), eviction
   filings by plaintiff where officially published, rental license +
   code-violation counts keyed to owner (local open data), AG
   enforcement actions. Time-series contexts make "impact over time"
   first-class: the same company's terms across years.
4. **Cost to escape a bad rental** — a NEW CostCategory
   `escape-cost-reserve` (kind: survival — the plan's stance: the
   ability to LEAVE is part of the cost of living somewhere) whose
   jurisdiction values derive from OFFICIAL LAW as data: early-
   termination/lease-break liability, security-deposit rules +
   return deadlines, and tenant remedies, cited to the official code
   hosts per jurisdiction (§4). Escape cost ≈ statutory lease-break
   exposure + new unit's (deposit + first/last month at FMR) + move.
   Where a number is a formula over statutes, the provenance names
   the code sections; the formula itself is a votable criterion
   (mechanism C fork: what counts as the escape cost?).
5. **How many people report poor living conditions** — terms:
   AHS inadequacy shares, ACS plumbing/kitchen deficiencies +
   overcrowding (occupants/room), Census Household Pulse housing
   insecurity/conditions, local 311 housing-code complaint rates.
   These are the REPORTED-conditions counterweight to price-only
   affordability — a cheap unit failing inspection is not affordable
   housing, which is precisely the quality-weighted worldview's
   argument in the seeded election.

## 6. Effective cost of living + concept interconnection (review of
how we were analyzing it, extended)

- **Effective CoL today** = survival_report over SurvivalCostProfiles
  (per-category stats + pseudo-tax share, small-sample flagged).
  Extension: persona baselines (§2) make the report answerable
  BEFORE citizen volume exists, with derived-official provenance;
  citizen entries then become the agreement check (derived vs
  reported — same validator idiom as the materials work).
- **Interconnections**: shared ScoreTerms across concepts with
  per-concept weights (mechanism B elections decide the weights);
  `equivalent_terms_json` bridges vocabularies across topic trees
  (housing ↔ labor ↔ health); `abstract_tags_json` + scr-5 suggests
  bindings for new assertions; mechanism C graphs express
  decision-procedure interconnection; SystemChoiceInForce records
  which criterion is deployed where. New in this plan: LONGEVITY and
  ESCAPE-COST terms deliberately tagged into multiple trees
  (housing, household-economics, labor-mobility — a worker who
  cannot afford to escape a bad rental cannot take a better job
  elsewhere; that is a labor-market term reading a housing-tree
  value).

## 7. Execution phases (suggested)

- **col-1**: vocabulary rows — persona contexts, DMV geography
  contexts, new terms (§5), escape-cost + displacement CostCategory
  rows. Selftest + idempotent seed.
- **col-2**: federal ingestion — ACS/AHS/HUD/BLS values for the DMV
  under the §3 citations (via /api/scoring/ingest payloads generated
  from the catalog; each value's provenance = agency+table+vintage).
- **col-3**: state/local ingestion — DC/VA/MD rows (§4), incl. the
  law-as-data escape-cost derivations with code-section provenance.
- **col-4**: persona baselines — official-baseline
  SurvivalCostProfiles per persona × jurisdiction; survival_report
  gains a baseline-vs-reported comparison.
- **col-5**: subjects — construction-company + rental-company
  ScoreSubjects for the DMV with per-company official signals;
  assertions + validity votes for the causal links.
- **col-6**: PSC surface — a DMV cost-of-living page reading the
  persona reports (the survival endpoints have NO frontend today —
  first consumer).

## 8. PSC work-state review (2026-07-16, full detail in the plan doc)

All revamp phases + mechanisms A/B/C + implications + scoring UI +
assertion/policy-vote write paths: DONE + VERIFIED per the plan's own
stamps. Queued next (priority order): reconcile the ncg-2 court-case
surface with the plan (built 2026-07-16, not yet in the plan);
resolve the step-level diff/merge scope question; wire fork
resolutions into live solution execution (ncg-1/2 just built exactly
this seam — `graph_compilers` + `advance_case`; the plan's standing
follow-up is now largely DONE on the Polari side and needs only the
plan/PSC reconciliation); role-gate polari-vote topic admin acts;
CREATE UIs for logic-fork votes/edges/assertions; generalize
system-choice implications; staff-authorization admin UIs; Dustin's
manual browser pass on all new pages.

---

## APPENDIX A — The four obscure factors: verified official sources
(researched + URL-verified 2026-07-16; agent sweep against official
domains only)

### A1. Housing longevity
| Source | Product / variables | Geography | Cadence | URL |
|---|---|---|---|---|
| Census ACS | B25034 (Year Structure Built), B25035 (Median Year Built), B25036/B25037 (by tenure); note official errata for 2008-2015 | state/county/tract (5-yr) — DMV fully covered | annual | https://data.census.gov/table/ACSDT5Y2023.B25035 |
| Census/HUD AHS | structural-condition variables: ROOFSAG, ROOFSHIN, ROOFHOLE, LEAKO/LEAKI, FNDCRUMB (+YRBUILT) — **Washington metro is an AHS oversample area** | national + DC metro | biennial | https://www.census.gov/content/dam/Census/programs-surveys/ahs/tech-documentation/AHS%20Codebook%201997%20and%20later.pdf |
| HUD PD&R | Residential Rehabilitation Inspection Guide (official component-condition reference; dated 2000) | national | static | https://www.huduser.gov/publications/pdf/rehabinspect_1.pdf |
| NIST | Handbook 135 + BLCC (official life-cycle-cost METHODOLOGY + rates — not component lifetimes) | national | annual rates | https://nvlpubs.nist.gov/nistpubs/hb/2020/NIST.HB.135-2020.pdf |
| Census Building Permits Survey | new residential authorizations to permit-issuing place (turnover inflow) | all DMV jurisdictions | monthly | https://www.census.gov/permits |
| HUD CINCH | units permanently LOST (demolition/disaster) vs added — the only official housing-loss measure | national (+ historic metro) | biennial | https://www.huduser.gov/portal/datasets/cinch.html |

HONEST GAPS: federal demolition-permit survey (C-45) discontinued in
the 1990s → CINCH + LOCAL raze/demolition permits (Open Data DC,
dataMontgomery) are the best available. NO official U.S.
component-service-life table exists — ASHRAE/NAHB tables are
non-government proxies; say so in provenance if ever used.

### A2. Builder/contractor impact on longevity
| Source | Product | URL |
|---|---|---|
| VA DPOR | License Lookup + Disciplinary Actions Search (since 2002) | https://dporweb.dpor.virginia.gov/LicenseLookup/DisciplinaryActionsSearch |
| MD Labor MHIC | license queries + published disciplinary actions per FY | https://labor.maryland.gov/license/mhic/mhicdisc.shtml |
| DC DOB/DLCP | SCOUT consolidated search (permits/inspections/licenses/enforcement by contractor name) + Notices of Infraction | https://scout.dcra.dc.gov/licenses-8935 |
| Local permits | Open Data DC building permits; dataMontgomery new-construction issued (udfi-gf76, daily); Fairfax Building Records PLUS | https://data.montgomerycountymd.gov/Licenses-Permits/dataMontgomery-Residential-new-Construction-Issued/udfi-gf76 |
| Warranty law | VA Code §55.1-357 (implied warranty, 1yr/5yr structural); MD Real Prop §§10-601..610 + MoCo Code §31C-8; DC Code §42-1903.16 (CONDOS ONLY — DC has no general new-home statutory warranty) | https://law.lis.virginia.gov/vacode/title55.1/chapter3/section55.1-357/ |
| OSHA/DOL | Establishment Search + bulk enforcement CSVs (NAICS 23) — MD/VA state plans still flow into the DOL DB | https://enforcedata.dol.gov/views/data_catalogs.php |

HONEST GAP: no official dataset links a builder to long-run
durability — discipline + OSHA + permit identity are correlational
signals joined by us; the causal claim stays an assertion with
votable validity (§5.2). Contractor-name columns in permit datasets
are inconsistent across permit types — verify per dataset.

### A3. Rental companies' impact over time
| Source | Product | URL |
|---|---|---|
| HUD REAC/NSPIRE | Physical Inspection Scores (property-level, 0-100, multifamily + public housing) | https://www.huduser.gov/portal/datasets/pis.html |
| HUD Multifamily | Assistance & Section 8 Contracts DB (contract rents + owner, ~monthly) | https://www.hud.gov/hud-partners/multifamily-assist-section8-database |
| DC RAD | capital-improvement petitions (DC Code §42-3502.10; +15%/+20% caps), hardship petitions (12% return), NEW Rent Registry (rent rolls) | https://rentregistry.dc.gov/welcome-housing-providers/ |
| Courts | MD Case Search (FTPR plaintiffs public; cases w/o judgment shielded 60 days — undercount bias); VA General District OCIS (plaintiff names public) | https://www.mdcourts.gov/legalhelp/housing |
| AG enforcement | DC OAG housing-justice cases (e.g. $41M Marbury Plaza; RealPage + 14 landlords), MD OAG landlord actions ($11.6M Heather Hill), VA OAG press only | https://oag.dc.gov/tenant-resources |
| Owner-keyed local data | DC Landlord Violations Tool + code-violation datasets; dataMontgomery Housing Code Violations (k9nj-z35d) + Troubled Properties Analysis (bw2r-araf); PG DPIE rental licenses | https://data.montgomerycountymd.gov/Consumer-Housing/Troubled-Properties-Analysis/bw2r-araf |

HONEST GAPS: no official landlord-level rent-trajectory dataset (DC
Rent Registry + RAD petitions closest, not bulk); DC eviction bulk
data does not exist officially (LSC civil-court data is a
congressionally-chartered NONPROFIT proxy — label as such);
Fairfax has NO rental licensing (VA preemption) — code-enforcement
complaints are the only owner-keyed signal there.

### A4. Prevalence of reported poor living conditions
| Source | Product | URL |
|---|---|---|
| AHS | ADEQUACY (pre-2015 ZADEQ): severely/moderately inadequate (exact definitions in Census adequacy paper) | https://www.census.gov/content/dam/Census/programs-surveys/ahs/publications/HousingAdequacy.pdf |
| Census Pulse | housing module (caught-up on rent, eviction likelihood); NOTE: HPS ended 2024-09; successor HTOPS is NATIONAL-only, bimonthly | https://www.census.gov/programs-surveys/household-pulse-survey/data/tables.html |
| Census ACS | B25014 (occupants/room — crowding), B25047-49 (plumbing), B25051-53 (kitchen) — tract-level DMV | https://data.census.gov/ |
| CDC | childhood blood-lead surveillance (DC/MD/VA state tables; screening-rate confound documented by CDC), asthma call-back survey | https://www.cdc.gov/lead-prevention/php/data/state-surveillance-data.html |
| Local 311 | DC 311 service requests (daily), MC311 (xtyh-brr2, since 2012); PG + Fairfax have NO bulk complaint datasets (flag: request-based) | https://data.montgomerycountymd.gov/Government/MC311-Service-Requests/xtyh-brr2 |

HONEST GAPS: AHS adequacy is metro-level only — ACS
plumbing/kitchen/crowding is the small-area proxy; HTOPS lost
state/metro granularity vs pandemic-era HPS.

ENTITY-RESOLUTION NOTE: only DPOR/MHIC/SCOUT discipline, OSHA
enforcement, HUD contracts+REAC, the DC Landlord Violations Tool,
and AG cases key to a NAMED company — everything else joins on
address/parcel; plan an entity-resolution pass (col-5).

---

## APPENDIX B — Federal source catalog (verified 2026-07-16)
(bls.gov + transit.dot.gov block non-browser fetchers — verified via
indexed current releases; all others returned HTTP 200 directly.)
Profile key: HS=fresh HS grads · RM=roommates · MW=min/median-wage
single · YF=young families.

### B1. Census ACS (metro CBSA 47900 + every DMV county + tract via 5-yr; annual)
| Table | Variables | Profiles |
|---|---|---|
| B25064/B25063 | median gross rent / distribution | all |
| B25031 | median gross rent BY BEDROOMS — the roommate-math table | RM, YF |
| B25070/B25071 | rent as % of income (50%+ = severe burden) | all |
| B25003/B25042/B25011 | tenure, by bedrooms, by household type | RM, YF |
| B25047-49 / B25051-53 | plumbing / kitchen facilities | MW, RM |
| B25014/B25016 | occupants per room (crowding) | RM |
| B25034/B25035/B25036 | year built / median year / by tenure | all |
| B09019/B09021/B11001 | "housemate or roommate" counts, living arrangements 18+ | RM |
| B20004/B15001/B23001/B14005 | earnings by education (HS-only), employment by age, youth school/work | HS, MW |
Access: https://data.census.gov + api.census.gov. Pattern:
https://data.census.gov/table/ACSDT1Y2024.B25064?g=310XX00US47900

**ACS PUMS microdata** — THE persona source: RELSHIPP=34
(housemate/roommate), AGEP, SCHL, ESR/WKHP (part-time), WAGP/PINCP,
GRNTP, GRPIP; PUMA geography (~40 in the DMV, sub-county in the
core). https://www.census.gov/programs-surveys/acs/microdata.html

### B2. AHS — Washington metro is a Top-15 OVERSAMPLE (2015..2023 biennial)
Housing adequacy (severe/moderate), heating breakdowns, leaks,
rodents, monthly housing costs incl. utilities. Metro-level only.
https://www.census.gov/programs-surveys/ahs.html (Table Creator:
/data/interactive/ahstablecreator.html)

### B3. HUD
| Product | What | Geography | URL |
|---|---|---|---|
| Fair Market Rents FY2026 | 40th-pctile gross rent 0-4BR, "Washington-Arlington-Alexandria DC-VA-MD HUD Metro FMR Area" | FMR area | https://www.huduser.gov/portal/datasets/fmr.html |
| Small Area FMRs | same by ZIP (DC metro is MANDATORY SAFMR) | ZIP | https://www.huduser.gov/portal/datasets/fmr/smallarea/index.html |
| Income Limits | 30/50/80% AMI by household size | FMR area/county | https://www.huduser.gov/portal/datasets/il.html |
| CHAS | income × cost burden × housing problems × household type | to TRACT | https://www.huduser.gov/portal/datasets/cp.html |
| Picture of Subsidized Households | assisted units, rents, incomes | to project/tract | https://www.huduser.gov/portal/datasets/assthsg.html |
| REAC/NSPIRE scores | property-level inspection scores (NSPIRE≠UPCS pre-2023 — not comparable across the 2023 protocol change) | property | https://www.huduser.gov/portal/datasets/pis.html |

### B4. BLS (bimonthly CPI release verified 2026-06-10)
| Product | What | URL |
|---|---|---|
| CPI Washington-Arlington-Alexandria | series CUURS35ASA0 (all items), CUURS35ASEHA (rent of primary residence) — index/trend, not $ levels | https://www.bls.gov/regions/mid-atlantic/news-release/consumerpriceindex_washingtondc.htm |
| Consumer Expenditure Survey, Washington metro | full budget shares in DOLLARS (2-yr averages) + PUMD microdata for profile cuts | https://www.bls.gov/regions/mid-atlantic/news-release/consumerexpenditures_washington.htm |
| OEWS area 47900 | wages at 10th/25th/50th/75th/90th pctile per occupation — 10th/25th = the entry-level line | https://www.bls.gov/oes/current/oes_47900.htm |
| CPS/LAUS | youth (16-19/20-24) labor force, part-time for economic reasons | https://www.bls.gov/cps/ |

### B5. USDA / HHS / EIA / DOT
| Product | What | URL |
|---|---|---|
| USDA Food Plans | Thrifty/Low/Moderate/Liberal monthly food cost by age-sex (NATIONAL-dollar only) | https://www.fns.usda.gov/research/cnpp/usda-food-plans/cost-food-monthly-reports |
| HHS Poverty Guidelines | 2026: $15,960 (1p) + $5,680/person | https://aspe.hhs.gov/topics/poverty-economic-mobility/poverty-guidelines |
| EIA Electric Power Monthly 5.6.A | residential ¢/kWh: DC 25.41, MD 22.07, VA 17.38 (Apr 2026) | https://www.eia.gov/electricity/monthly/epm_table_grapher.php?t=epmt_5_6_a |
| EIA gas + RECS | residential gas $/Mcf by state; household energy expenditure | https://www.eia.gov/consumption/residential/ |
| FTA National Transit Database | WMATA fare revenues + trips → avg fare/trip | https://www.transit.dot.gov/ntd |
| DOL state minimum wages | the official listing of DC/MD/VA minimums (they differ) | https://www.dol.gov/agencies/whd/minimum-wage/state |

### B6. Housing instability (federal)
Census Household Pulse: caught-up-on-rent + eviction likelihood, Washington MSA
(historical; successor HTOPS is national-only) —
https://www.census.gov/programs-surveys/household-pulse-survey.html
HUD AHAR/PIT homelessness counts by Continuum of Care —
https://www.huduser.gov/portal/datasets/ahar.html

### B7. Honest federal gaps
1. NO federal eviction-filings database (courts are state/local;
   Eviction Lab is academic — excluded by scope).
2. NO per-room/roommate asking-rent series — derive from B25031÷N or
   PUMS RELSHIPP=34.
3. NO current asking-rent series (ACS lags + sitting tenants; FMR is
   administrative 40th percentile).
4. USDA food plans are national dollars; DC CPI food is an index.
5. OEWS has no education dimension — HS-grad wage ≈ 10th/25th pctile
   or ACS B20004/PUMS cut.
6. WMATA fare SCHEDULES are compact-agency data, not federal — NTD
   yields only derived average fares.
Strongest per-profile combos: HS = OEWS p10 + B20004/PUMS vs FMR;
roommates = PUMS RELSHIPP + B25031 + SAFMR-by-ZIP; single MW = OEWS
median + B25064/B25070 + Income Limits; young family = CHAS tract
burden + AHS adequacy + USDA plans + Income Limits.

---

## APPENDIX C — DC / Virginia / Maryland state + local catalog
(verified 2026-07-16; official domains only)

### C1. District of Columbia
| Source | What | URL |
|---|---|---|
| OTA monthly eviction data | scheduled + executed evictions, citywide monthly PDFs (NO bulk case data in DC — this is the official published number) | https://ota.dc.gov/page/monthly-eviction-data |
| OTA policy parameters | 2026 rent-increase caps (4.1% general / 2.1% elderly), $54 application-fee cap | https://ota.dc.gov/ |
| DHCD RAD Rent Registry | EVERY rental unit registered rent-stabilized/exempt with housing-provider identity — DC's rent-control universe as data | https://rentregistry.dc.gov/ |
| Open Data DC Basic Business Licenses | all rental-housing licenses with licensee identity | https://opendata.dc.gov/datasets/85bf98d3915f412c8a4de706f2d13513_0/about |
| DOB landlord violations | outstanding housing-code violations since 2017, searchable BY LANDLORD NAME | https://dob.dc.gov/page/agency-performance-dob |
| ORA tax-burden studies | DC vs 50 states + vs surrounding NoVA/MD — the official DC CoL-adjacent comparison | https://ora-cfo.dc.gov/page/tax-burden-studies |

### C2. Virginia (state + NoVA)
| Source | What | URL |
|---|---|---|
| OES GDC statistics | unlawful-detainer filings/dispositions by locality — Power BI refreshed DAILY, data 2008-present (no bulk case-level dataset; case lookups via OCIS) | https://www.vacourts.gov/courtadmin/aoc/djs/programs/cpss/csi/gd/home |
| GDC Online Case Info | per-case unlawful detainer with plaintiff names | https://eapps.courts.state.va.us/gdcourts/ |
| Fairfax dwelling data | parcel-level YEAR BUILT + structure attributes (open data) | https://data-fairfaxcountygis.opendata.arcgis.com/maps/Fairfaxcountygis::tax-administrations-real-estate-dwelling-data |
| Arlington / Loudoun / PWC portals | parcels, ownership (PWC nightly), permits | https://data.arlingtonva.us/ · https://logis.loudoun.gov/ · https://gisdata-pwcgov.opendata.arcgis.com/ |
| Alexandria rental inspections | the ONE NoVA rental-inspection regime (Va. Code §36-105.1:1 districts, 4-yr certificates) | https://www.alexandriava.gov/code-administration/residential-rental-inspections-program |

### C3. Maryland (state + suburbs)
| Source | What | URL |
|---|---|---|
| **District Court Eviction Case Data** | THE standout: statewide CASE-LEVEL eviction data (2022 law; Jan 2023→): event date/type, county, case type, tenant ZIP, evicted date | https://opendata.maryland.gov/Housing/District-Court-of-Maryland-Eviction-Case-Data/mvqb-b4hf |
| Judiciary L/T case activity | monthly per-jurisdiction counts incl. sheriff-executed evictions + dashboards | https://www.mdcourts.gov/dashboards |
| SDAT real property | statewide parcel bulk data: OWNER NAME + YEAR BUILT (the field MoCo uses for rent-stabilization coverage) | https://opendata.maryland.gov/ (Real Property Assessments) |
| **MoCo DHCA Annual Rental Housing Survey** | OFFICIAL per-facility RENT SURVEY (County Code §29-51): rents, utilities, vacancies, turnover — the region's richest official rent data | https://www.montgomerycountymd.gov/dhca/finance/licensing/rental-survey.html |
| MoCo rent stabilization | allowance = min(CPI+3%, 6%) on licensed units ≥23yr old; program reports | https://www.montgomerycountymd.gov/department-housing-community-affairs/rent-stabilization |
| MoCo licensing + violations | Housing Licensing & Registration (et5s-xste) + Housing Code Violations (k9nj-z35d, weekly) | https://data.montgomerycountymd.gov/ |
| PG rent stabilization + DPIE | permanent 2024 act (annual limits each May 1) + rental licenses + Housing Inspection Violations (9hyf-46qb) + LookSee | https://data.princegeorgescountymd.gov/ |
| Howard / Anne Arundel / Frederick City | rental licenses (lookup portals, no bulk data) | https://dilp.howardcountymd.gov/CitizenAccess/ · https://www.cityoffrederickmd.gov/1830/Rental-Licensing-Property-Search |

### C4. Law-as-data: the escape-cost statutes (official code hosts)
| Jurisdiction | Security deposit | Early termination | Repair remedies |
|---|---|---|---|
| DC | §42-3502.17 (max 1 month, 45-day return + interest) https://code.dccouncil.gov/us/dc/council/code/sections/42-3502.17 | §42-3505.07 (DV victims penalty-free); exit mechanics §§42-3505.53/.54 | no statutory repair-and-deduct — 14 DCMR + Housing Conditions calendar |
| VA | §55.1-1226 (max TWO months, 45-day return) https://law.lis.virginia.gov/vacode/title55.1/chapter12/section55.1-1226/ | §55.1-1235 (military), §55.1-1236 (abuse victims); **NO general cap on early-termination fees — the region's worst escape-cost exposure** | §55.1-1244 rent escrow + §55.1-1244.1 limited repair-and-deduct |
| MD | RP §8-203 (max ONE month post-2024, 45-day, treble damages) https://mgaleg.maryland.gov/mgawebsite/Laws/StatuteText?article=grp&section=8-203&enactments=false | §8-212.1 (military: rent due + 30 days), Title 8 Sub 5A (DV) | §8-211 rent escrow/withholding; §8-208 late-fee cap 5% |

Escape-cost formula per §5.4 uses these + FMR (new-unit deposit +
first month) — VA's uncapped lease-break liability is a real,
citable jurisdictional difference.

### C5. Landlord-identity linkage summary
Bulk owner identity: MD SDAT (statewide) + MoCo licensing + DC BBL/
Rent Registry + DOB landlord search. Case-level only: VA OCIS + MD
Case Search (MD's case-level eviction dataset deliberately omits
landlord names — join case numbers to Case Search for unshielded
cases). DC evictions: aggregate-only, NOT linkable to landlords —
violations/licenses are DC's linkable signals.

---

## §7 REVISED — execution via the API PROFILER (Dustin 2026-07-16:
"we have api profiler which can auto-ingest api data and
auto-convert it to local objects — utilize that")

The pipeline ALREADY EXISTS end to end:
`polariApiProfiler/` (APIDomain → APIEndpoint → APIProfiler queries
+ profiles responses via polyTyping → APIProfile → convert to a REAL
Polari class via createClassAPI → rows land as local objects) THEN
`scoring/data_ingestion.ingest_from_class` (any objectTables class →
ContextualizedValues via {subjectField, valueField, contextFields}
mapping) — the profiler-to-scoring bridge is a documented payload
away (`POST /api/scoring/ingest` with source_class). So each source
becomes: one APIDomain/APIEndpoint row + one profile→class + one
ingest mapping — ALL data-driven, no per-source Python.

**Profiler-ready sources (machine-readable APIs):**
- Census API (api.census.gov — ACS tables B25xxx + PUMS): JSON.
- HUD USER API (FMR/SAFMR/Income Limits have an official token API).
- EIA API v2 (official, keyed) — electricity/gas prices.
- BLS Public Data API v2 (CPI series CUURS35ASA0 etc.).
- Socrata SODA JSON: opendata.maryland.gov (eviction case data
  mvqb-b4hf), dataMontgomery (k9nj-z35d, et5s-xste, xtyh-brr2,
  udfi-gf76, bw2r-araf), data.princegeorgescountymd.gov (9hyf-46qb),
  data.transportation.gov (NTD ridership 8bui-9xvu).
- ArcGIS REST JSON: Open Data DC (BBL, permits, violations, 311),
  Fairfax dwelling data, PWC parcels.
- DOL enforcement (enforcedata.dol.gov bulk CSVs — OSHA).
**NOT profiler-ready (record/manual/PDF):** OTA eviction PDFs, AHS
PUFs (download files), CEX/PUMS microdata files, statutes (law-as-
data records with code-section provenance), MoCo rental survey
(portal/story pages — check for a Socrata mirror per year), AG case
listings, VA OES Power BI (request bulk from OES).

**Phases (revised):**
- **col-1** vocabulary rows (unchanged): persona + DMV geography
  contexts, §5 terms, escape-cost/displacement CostCategories.
- **col-2 profiler registration**: APIDomain rows per agency
  (census, huduser, eia, bls, socrata hosts, arcgis hosts) +
  APIEndpoint rows per product; profile → auto-create classes
  (profiler's createClassAPI path); keys (EIA/BLS/HUD tokens) ride
  env knobs, never committed (repos are public).
- **col-3 scheduled pulls + ingest mappings**: per endpoint an
  ingest_from_class payload (term, subjectField=geography,
  valueField, contextFields=[vintage…]) — provenance stamped
  endpoint-URL+vintage; refreshes re-run idempotently (overwrite
  knob). Non-API sources land as hand-entered records with citation
  provenance (same honest shape as today's seeds).
- **col-4** persona baselines (unchanged) — now COMPUTED from
  profiled rows (PUMS cuts prepared offline into a file the
  profiler ingests, or a small derive act).
- **col-5** entity resolution + company subjects (unchanged, uses
  C5 identity sources).
- **col-6** PSC surface (unchanged) + an API-health matrix category
  (each registered endpoint = a live check row: reachable, schema
  drift honest — the accountability matrix already has the idiom).

---

## §7c — Profiler resilience (Dustin 2026-07-16, second directive)

Government APIs DO rename fields between vintages and DO move
endpoints — the ingestion must survive both without hand-editing.
Two capabilities added to `polariApiProfiler/` (built + selftested
against an EMULATED external API):

1. **Schema-drift adaptation** (`schema_drift.py`): an endpoint's
   profile is considered SOLID after N consistent samples (knob);
   when the same URL later serves a changed format, the drift is
   detected as "this API changed its formatting" (never "unknown
   API"), and a field-migration mapping is PROPOSED by analyzing
   both the WORD formatting of field names (snake/camel token
   analysis, abbreviation containment, sequence similarity) and the
   DATA formatting (types + value-shape overlap — the same values
   under renamed fields is the strongest evidence). Ambiguous
   near-ties are surfaced, never silently picked. After applying a
   migration, a continuity check proves old ids and locally stored
   values still match up.
2. **Relocation discovery** (`api_discovery.py`): when an endpoint
   disappears, ask "what are your APIs?" at the standard
   advertising locations (RFC 9727 /.well-known/api-catalog,
   OpenAPI /openapi.json + /swagger.json, /api-docs, /api listing)
   and search the advertised APIs for the profile we want —
   drift-aware, so a relocated AND renamed API still matches.

Matrix row: `selftest:polariApiProfiler.profiler_drift` (format
category, blocking). col-3's scheduled pulls should route every
refresh through the stability tracker so agency format changes land
as suggestions with evidence, not silent ingestion corruption.

---

## §7d — GovSource registry (Dustin 2026-07-16, third directive)

Sources are OBJECTS (`dmvdata/gov_sources.py`):
- **`GovSource`** rows: the acronym glossary — every source's acronym
  expanded (ACS = American Community Survey, U.S. Census Bureau…),
  official website + data portal, jurisdiction, parent bureau
  linkage, `requires_api_key` + the env knob that holds the key
  (never the key itself — repos are public), and which registered
  APIEndpoints pull from it.
- **`SourceRetrieval`** rows: when a Polari group (or individual)
  retrieves and DUPLICATES a source's data, the origin record —
  datetime, retrieved_by (Contributor), retrieved_by_group
  (ScoreGroup or '' for an individual), what was pulled, row count,
  redacted provenance URL. The census_pull ingest path records one
  automatically when attribution is supplied.
- **Term-origin tracking**: `terms_from_source(source)` scans
  ScoreTerm/ContextualizedValue provenance for the source's acronym
  (word-boundary), full name, or URL domain — "what terms originate
  from this source" is answerable per source, with match evidence.
- `source_glossary()` = the easy acronym lookup;
  `source_report(source)` = one source's full card (expansion,
  website, key requirement, endpoints, retrievals with origins,
  originating terms).
Matrix row: `selftest:dmvdata.gov_sources` (format, blocking).

## §7e — Cross-validation + provider reliability (Dustin 2026-07-16,
fourth directive)

- **Cross-validation**: more users assert duplicated data as real by
  pulling the SAME source on their own Polari instance and comparing
  — `RetrievalConfirmation` rows tie a validator's independent
  SourceRetrieval to the original with a computed comparison
  (rows/matches/mismatches/verdict: confirmed|partial|contradicted)
  and group/individual attribution. Comparison reuses the
  continuity-check idiom (per-key, per-field equality).
- **Sourcing credibility**: a transparent reading over a
  retrieval/source — confirmations by DISTINCT groups raise it
  (independence is what counts), contradictions lower it,
  small-sample flagged (SMALL_SAMPLE idiom). A credibility READING
  with evidence, never an auto-declared truth; the formula itself is
  a votable criterion later (mechanism C).
- **Provider reliability**: groups PROVIDING data become scoreable
  subjects — ScoreTerms (data-confirmation-rate,
  data-contradiction-rate, retrieval-volume, span) + a
  'data-provider-reliability' ScoreConcept over subject_kind
  'group', so the standard engine scores providers and mechanism-B
  elections can weight the factors ("other factors" = more terms,
  votable).

## §7f — Varying legal source types (Dustin 2026-07-16, fifth
directive)

GovSource gains four siblings — the LEGAL TYPE of a source is
first-class: **NonProfitSource** (EIN, 501(c) subsection, IRS
Tax-Exempt-Organization-Search pointer, funding transparency),
**CompanySource** (state of incorporation, SEC CIK / state registry
pointer, ticker), **PoliticalGroupSource** (party/PAC/campaign/
advocacy kind, FEC committee id + fec.gov lookup),
**IndividualSource** (person, affiliation, credentials, Contributor
link when they're a platform user). One machinery spans all five
kinds: the glossary labels kind, retrievals/confirmations/credibility
are type-agnostic, and reports on non-government kinds carry an
honest 'not an official statistic origin' framing — the DMV data
plan's official-only scope is unchanged; these types exist so
NON-official sources (LSC's civil-court data, Eviction Lab, JCHS —
already referenced as proxies) are TYPED and disclosed rather than
laundered into officialdom. Matrix row:
`selftest:dmvdata.legal_sources` (format, blocking).
