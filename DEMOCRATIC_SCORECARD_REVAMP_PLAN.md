# Democratic Scorecard revamp — plan (2026-07-14, Dustin away ~9hrs, autonomous session)

## Ground truth (from two research sweeps tonight — don't re-derive, read this first)

**political-scorecard-node** (Java 17/Spring Boot 3.5 backend, Angular 19 frontend,
MariaDB/Redis/MinIO/Keycloak, live at `psc-frontend`/`psc-backend`/`psc-redis`, reachable
today at `https://psc.192.168.0.210.nip.io/`) has a rich, well-designed **authoring** layer
(Term/TermContext/ContextualizedTerm/WorldviewElection CRUD, legislation upload + PDF/DOCX
export + rich-text annotation, live debate chat over STOMP) that works end-to-end against
its real backend. But its **scoring/calculation layer is not real**:
- `worldview-ballot.component.ts` reads `MOCK_TERMS`/`MOCK_CONTEXTUALIZED_WORLDVIEW_BALLOTS`
  from `state/mock-data/`, not the live API.
- `services/scoring/worldview-scoring.service.ts` (568 lines) is a genuine, coherent
  weighted-sum → levelized-score formula ("spreadsheet methodology") — but it's 100%
  client-side TypeScript over mock data, with no server equivalent.
- Backend `Score.java` is an empty stub (three bare `ArrayList` fields, no logic).
  `TermDimension`/`DataSeriesOrigin`/`DataSeriesProxy` are empty stub classes whose own
  comments say they're meant to proxy Polari. `WorldviewBallot`/`WorldviewVote` have a DB
  table but **no DAO, no controller** — can't even be written via the API today.
- `ContextualizedTerm` carries `preProcessPolariUrl`/`postProcessPolariUrl` DB columns,
  fully plumbed through DAO/getters/setters, but **never read by any service** — 100% inert.
- `competitive-scoring-service.ts` calls `GET /scores`/`GET /categories` — routes that
  don't exist on the backend. Dead code.
- `environment.ts` already has a correctly-resolved `polariResearchFrameworkUrl` per env
  (including nip.io auto-detect: `https://prf.${nipIoBase}`) — used today for exactly one
  hyperlink, no actual API calls.
- The clearest existing integration spec is prose in `solution-scoring.component.html`: a
  5-phase pipeline (Requirements Development → Logical Equivalence Assertions →
  Implications & Viability → WorldView Score Assertions → Solution Composition) that maps
  directly onto Polari's REAL `polariNoCode/SolutionExecutionEngine.py` (Complete/Partial/
  Composition step roles). Not implemented anywhere yet — spec only.

**Polari's `scoring/` module** (`polari-rf-node/polari-framework/scoring/`, 25 files,
~8464 lines) is explicitly documented in its own code as political-scorecard's original
design, generalized — see `scoring_basis.py` docstring: *"the Political Scorecard's proven
object graph... generalized into Polari... Dustin 2026-07-07: 'use arbitrary data in the
political scorecard, and plug it into polari.'"* It has the REAL, working version of
everything PSC stubbed out:
- `ScoreTerm` → `ContextualizedValue` (term × subject × context, can bind to ANY live
  Polari object via `data_ref_json`) → `ScoreContext` (hierarchical, `parent_name` chains)
  → `ScoreSubject` → `ScoreConcept` (weighted term bundle, NESTS, levelize-to-100) →
  `ScoreGroup` (member concepts/subjects/contributors + vote-derived weights).
- `ScoreAssertion` (evidence-weighted, full status lifecycle), `PolicyVote` (has a generic
  `ingest_votes_from_class()` for Congress.gov/GovTrack/OpenStates), `WorldviewElection` +
  `WorldviewBallot` (**actually implemented** — approval/sole/ranked-condorcet, closes→
  tally→derives group weights — this is PSC's "designed-never-built WorldviewVote", now
  built), `Contributor`, `MediaEvidence`, `AgreementPolicy` (consensus/divisive banding).
- Engine (`scoring_engine.py::score_concept()`, `policy_scoring.py::score_policy()`,
  `politician_scoring.py::politician_score()`/`cohort_report()`) computes LIVE on every
  request, over `manager.objectTables` — real weighted-mean math, missing values NAMED not
  dropped (`termsMissing`). Vocabulary already matches PSC (politician/policy/vote/chamber/
  session — no translation layer needed).
- Fully config/no-code: `SEED_SCORE_*` lists or live CRUDE, **zero bespoke Python per new
  concept/politician/policy**.
- Currently DEMO DATA ONLY (US labor stats + a wax-thermal-conductivity cross-domain proof
  concept) — **no real political data exists in Polari yet.** Seeding real content is real
  work, not already done.
- `topology_constants.py`: `'psc'` is a first-class registered Polari deployment role.

**No code today calls between the two apps.** The `polariUrl`-family fields are the only
seam, and they're inert on both sides.

## Decision: which app does the calculating?

**Polari does. PSC becomes a client, not a duplicate implementation.** Don't port
`worldview-scoring.service.ts`'s formula to Java, and don't hand-roll a second scoring
engine — Polari's is more complete (evidence weighting, assertion lifecycle, group
cohorts, missing-value honesty) and is *already the generalized descendant* of PSC's own
design. PSC's real, valuable asset is its authoring/legislation/debate UI, not a second
scoring math implementation.

Where does the live call happen — PSC backend or PSC frontend?
**Frontend, directly, for now.** `environment.ts` already resolves `polariResearchFrameworkUrl`
correctly per env; Polari's `/api/scoring/*` endpoints are already public read endpoints (no
auth required for GET, matching how `polari-platform-angular`'s own scoring components call
them). A direct frontend→Polari call is the smallest change that makes scoring real today.
PSC backend keeps owning authoring CRUD, legislation, debate — it does NOT need to proxy
scoring calls unless a real reason to add a server hop shows up (e.g. combining Polari data
with PSC-only data server-side for PDF export). Revisit this decision if that need appears;
don't build the proxy hop speculatively.

## Architecture correction (Dustin, 2026-07-14, after Phases 1-5): where ballots actually live

**Supersedes the "adopt Polari's WorldviewElection/WorldviewBallot directly" call in the
vocabulary table below and the Phase 3a/3b approach built earlier tonight.** Dustin's own
words: *"the primary place where the ballots should live is on the more locked down psc
side... polari should be where the aggregation lives, psc should be where the public facing
user interface and their immediate data lives, while polari is the analysis and group-level
layer where people might define how contextualization 'should be' according to their group,
and then the diffs of those can be compared and voted on in psc, and a derivative based on
the voting... can go back to be resolved into coherent plans of execution."* Follow-up:
*"The political scorecard is for voting on the various issues, and polari is where different
proposals and analyses on those proposals in terms of solutions are drafted, before being
sent to and getting voted on in the Political Scorecard."*

**The corrected split:**
- **Polari** = drafting + analysis + aggregation layer. Groups propose contextualization
  definitions here (`ScoreConcept`/`ScoreGroup`/`GroupDisplayVote` candidates — this part IS
  what Phases 2/4 already built and remains correct). Read-only from PSC's side. Polari's
  own `WorldviewElection`/`WorldviewBallot` classes stay as Polari-internal machinery for
  Polari-side processes (e.g. group-internal drafting consensus) — PSC does NOT write ballots
  into them directly anymore.
- **PSC** = the public-facing vote. This is where citizens actually cast ballots, using PSC's
  own accounts (anonymized IDs on both sides — Polari's `Contributor.pseudonymous` default
  already matches this). Needs a REAL `WorldviewBallot`/vote DAO + controller on PSC's own
  backend (the original ground-truth gap: PSC has the DB table but never built the DAO/
  controller — this is where that gets built, not by reusing Polari's endpoint).
- **The loop back**: PSC tallies its own ballots server-side (locked down, not Polari's
  currently-anonymous-write CRUDE). The RESULT — not raw ballots — gets pushed back to
  Polari as a derivative decision, resolved into the concept/weighting Polari actually
  scores by. This is a PSC-backend → Polari server-to-server call, a fundamentally smaller
  trust surface than the anonymous-browser-write path flagged as a blocker in Phase 3b — the
  write comes from PSC's own backend, not from arbitrary internet clients.

**Open scope question, NOT resolved autonomously (flagged, not guessed)**: Dustin's language
("diffs... divergence in those steps... resolved into coherent plans of execution") reads
like it may mean something more granular than whole-candidate voting — voting at the level
of individual logic steps/terms across divergent group definitions, then MERGING winning
pieces into one resolved plan, rather than electing one whole `ScoreConcept` outright. That
would be a genuinely new mechanism (closer to a 3-way-merge for scoring logic) — bigger
scope than relocating ballot-casting. Tonight's build targets the smaller, concrete,
buildable interpretation (whole-candidate voting, relocated to PSC, result pushed back to
Polari) since it's a direct, verifiable extension of what Phases 2-4 already proved works;
the step-level diff/merge idea is recorded here as a documented next-level refinement for
Dustin's own review, not built speculatively.

**Concrete build for tonight**:
1. PSC backend: real `WorldviewBallot` entity/DAO/controller (finally filling the gap the
   original ground-truth research found — DB table existed, no DAO/controller ever built),
   keyed to PSC's own anonymized user/contributor identity, POST/GET wired to real auth.
2. PSC frontend: a real ballot-casting UI against PSC's own new endpoint (not Polari's),
   pulling candidate definitions from Polari read-only (already built: `getConcepts()`/
   `getElections()`/`getDisplayVotes()` etc. in `PolariScoringService`).
3. Result push-back: once a PSC-side vote closes and tallies, a small PSC-backend → Polari
   server-to-server call applies the derived result (reusing Polari's existing
   `apply_election`/`apply_display_vote` functions where the shape fits, or a new endpoint
   if PSC's tally shape doesn't map 1:1 — check before assuming reuse).

## Vocabulary mapping (PSC → Polari — direct 1:1 in most cases)

| PSC class | Polari class | Notes |
|---|---|---|
| `Term` | `ScoreTerm` | `category` → Polari has no direct equivalent field; likely folds into `abstract_tags_json` or a ScoreConcept's own name/grouping. Check on contact. |
| `TermContext` (+ subtypes Demographic/Economic/Location/Timeframe/Custom) | `ScoreContext` | Polari's `ScoreContext` is generic + hierarchical (`parent_name`); PSC's typed subclasses likely become `context_type` values or `custom_json` fields, not separate Polari classes. |
| `ContextualizedTerm` | `ContextualizedValue` | Direct match — term × subject × context + value. `preProcessPolariUrl`/`postProcessPolariUrl` were reaching for exactly what `data_ref_json` already does (live objectRef binding) — retire those fields once real. |
| `WorldviewElection`/`WorldviewBallot`/`WorldviewVote` | `WorldviewElection`/`WorldviewBallot` | **Superseded 2026-07-14 — see "Architecture correction" above.** Same names, but NOT the same instance: PSC builds its OWN real DAO/controller for ballot-casting (the public vote); Polari's version stays Polari-internal (drafting/group-consensus machinery), read-only from PSC. Don't just "adopt Polari's directly" as originally planned. |
| (no PSC equivalent) | `ScoreSubject`, `ScoreConcept`, `ScoreGroup`, `ScoreAssertion`, `Contributor`, `MediaEvidence`, `AgreementPolicy`, `PolicyVote` | New concepts PSC's UI will need to learn to author/display — this is most of the real UI work. |
| `Score.java` (empty stub) | `scoring_engine.py::score_concept()` etc. (live) | Delete the Java stub's role entirely — no server-side Score object needed, the frontend calls Polari and gets a report back. |

## Feature requirements (Dustin, this session, folded in)

1. **Map integration** — score/context data visualized on maps. Reuse Polari's existing
   `models/geojson/` + `components/maps/` (maplibre) rather than a new mapping stack in PSC.
2. **Custom Displays from Polari plugged into the scorecard for decision support** — reuse
   the real `DISPLAY_COMPONENT_REGISTRY`/Display system already built and exercised heavily
   tonight (aquaponics pot editor, sim-space configured-interface panel are the reference
   examples). A score's explanation should be an actual pluggable Display, not hardcoded UI.
3. **Displays are "sourced" from different groups** — a score's Display isn't singular;
   different `ScoreGroup`s (e.g. affected-residents vs. subject-matter-experts) can each
   author their own explanatory Display for the same score/concept.
4. **Voting mechanism A — within a group, vote on which Display is best** at helping people
   understand the score's terms and why some matter more than others (explanatory quality,
   not the score itself).
5. **Voting mechanism B — across groups, vote on which groups are most impacted/relevant/
   expert for a given score.** Worked example: for a chemical-spill score, "people who lived
   there when it happened" (lived-experience authority) and "experts on health impacts from
   those chemicals" (technical authority) are both relevant groups, ranked/voted separately
   from each other and separately from #4's per-group Display-quality vote.

   **VERIFIED (read the actual source, not just the audit summary) — mechanism B is
   ALREADY FULLY BUILT.** `scoring/score_group.py` + `scoring/worldview_elections.py`:
   `ScoreGroup.member_concept_names_json` docstring literally says *"each member's
   definition of a scored idea IS a ScoreConcept: their term weights + stances"* —
   i.e. a group (political/professional/civic/custom — `GROUP_TYPES`, and the module
   docstring cites Dustin 2026-07-08 verbatim: *"(a) All groups - Consensus, (b) Political
   Groups, (c) Professional Groups"*) doesn't just get weighted from outside — each member
   PROPOSES their own ScoreConcept (their own term-weighting worldview) as their entry.
   `WorldviewElection` (candidates = ScoreConcept names, approval/sole/ranked-condorcet) →
   `tally_election()` → `apply_election()` writes vote-derived weights onto
   `ScoreGroup.member_weights_json` + `weights_provenance` (refuses to apply an OPEN
   election — never silently finalizes a still-changing result). There's working seed data
   (`demo-labor-definition-election`, 4 worldviews, 3 ballots, ranked-condorcet) proving
   the whole path end to end. **Nothing new needed for mechanism B — use this as-is.**

   **Mechanism A (vote on which Display best explains a concept within a group) needs ONE
   new small class — do NOT generalize the shipped WorldviewElection schema for it.**
   `candidate_concept_names_json` is concept-typed by name and by every docstring/comment
   around it; forcing Display names through that field would be a type lie. BUT the tally
   logic (`_tally_approval`/`_tally_sole`/`_tally_ranked` in `worldview_elections.py`) are
   plain functions over `(ballots, candidates)` — they don't care what a candidate NAME
   actually references, only that ballots name members of the candidate list. Plan: a new
   `scoring/group_display_vote.py` with `GroupDisplayVote` (group_name, concept_name or
   context_name being explained, candidate_display_names_json, mode, status) +
   `GroupDisplayBallot` (same voter/approvals/sole_choice/ranking shape as
   `WorldviewBallot`), reusing the SAME three tally functions by import (don't duplicate the
   Condorcet/approval math) — the only genuinely new logic is what "apply" writes onto
   (there's no `ScoreGroup.member_weights_json`-equivalent slot to write into for "the
   group's currently-endorsed Display"; likely a new field or a `GroupDisplayEndorsement`
   row `{group_name, concept_name, display_id, votes_provenance}`. Build this in Phase 4,
   not Phase 1 — it's new backend surface, needs its own selftest before anything depends
   on it.

6. **"Context Trees" — the priority, per Dustin explicitly ("leave Odoo/economic-simulation
   aside for now, but contextualization tree and context-based organizing of scores and
   terms are critical for scoring").** Curate a real `ScoreContext`/`ScoreConcept`
   hierarchy (they already nest/parent-chain — no new data structure needed, this is
   content-authoring + a UI to do it well). Three worked examples given, each sharpening a
   different facet:
   - **Housing Affordability** — shouldn't reduce to a single price number; weight
     professional-judgment terms too (building longevity, material quality, construction
     practice), because cheap/deceptive construction quietly makes the whole economy
     poorer long-term even though it looks cheaper short-term.
   - **Household Food Health** — knowledge on nutrition, food-prep skill, availability and
     cost PER INCOME BRACKET (i.e. this concept needs an income-bracket `ScoreContext`
     dimension, not just location/time — matches the existing generic ScoreContext
     hierarchy, just a context type not yet seeded).
   - **Intersectional / nested concepts, with the authoring PROCESS spelled out**:
     "Law Enforcement Effectiveness" → sub-concept "Sexual Assault Handling" (ScoreConcept
     nesting — a child concept's score feeds a parent term). "Legal Coherence" →
     "Upholding Public Expectations of Rulings" → "Upholding Sentences Against Repeat
     Offenders" (3 levels deep — ScoreConcept already supports this, cycle-refused,
     depth-capped at 8 per the engine). "Legal vs Public Expectation of Statute of
     Limitations" is a DIFFERENT shape of concept: instead of measuring an existing metric,
     the concept IS a live democratic value-setting process (people vote on what a statute
     limit SHOULD be; law enforcement attaches REASONING for why current limits exist,
     e.g. evidence degrading after N years) — this maps onto `ScoreAssertion` (the
     reasoning, evidence-graded, attributed to a `Contributor` like "law enforcement
     association") + a `WorldviewElection` whose candidates are literal VALUE OPTIONS
     framed as tiny ScoreConcepts (e.g. one concept per candidate limit: "5-year limit",
     "10-year limit", "no limit") rather than measurement worldviews — same mechanism,
     different use. No new backend class needed, just a specific authoring pattern.

   **The stated PROCESS for building Context Trees (Dustin, verbatim intent) is itself a
   design requirement, not just content**: find the professional and lobby groups that
   typically weigh in on an issue → let them propose solutions democratically → let them
   EACH define what metrics best measure the issue (different interest/professional groups
   see things the public doesn't) → do this PER-COMMUNITY too, since situations vary by
   locality (maps onto `ScoreContext`'s existing location hierarchy). This is exactly
   mechanism B's flow (groups propose ScoreConcepts, get voted/weighted) applied
   specifically to context-tree authoring — confirms mechanism B and Context Tree
   authoring are the SAME underlying workflow, not two separate features to build.

7. **Data sourcing preference**: official sources for economic quantitative data generally;
   tax-burden/cost-of-living per person specifically likely need participatory
   (crowdsourced) data since official sources don't reach individual-level detail there —
   official first, participatory only where official genuinely doesn't reach.
8. **Explicitly parked, NOT this session** (Dustin: "leave apart integrating odoo for now
   and simulating the economy, those are separate topics"): Odoo (open-source ERP)
   integration with Polari's simulation layer, and a vision of open-source businesses
   becoming producers of currently-privatized economic data. Documented here for
   continuity; not investigated or built tonight. `Contributor` is already the right seam
   for this once it's real.

## Phased plan

**Phase 1 — ✅ DONE + VERIFIED (2026-07-14)**: `political-categories` page converted from
`MOCK_POLITICAL_CATEGORIES` to live `GET /api/scoring/concepts`. Built: `environment.ts`
`polariApiUrl` (5 config sites), `models/polari-scoring/polari-scoring-types.ts` (verified
against live API, not guessed), `services/polari/polari-scoring.service.ts`,
`political-categories.component.{ts,html,scss}` (loading/error states, real `ScoreConceptSummary`
→ `PoliticalCategory` mapping). Full `ng build` clean (only a pre-existing unrelated CSS budget
warning). Deployed via suite-root `docker-compose.staging-nip.yml --no-deps psc-frontend` +
`pol-proxy` restart — confirmed this is the correct compose file (same network-correctness
lesson as prf-frontend). **Cross-app CORS proven live**: Polari's API reflects
`https://psc.192.168.0.210.nip.io` as an allowed origin dynamically and returns real concept
JSON — first-ever browser-verified call between the two apps, works. Also fixed an unrelated
pre-existing typo blocking `tsc --noEmit` (`StateLabor Data` → `StateLaborData` in
`state/mock-data/labor-quality-score-sample.ts`, stray space in the identifier, self-contained
to that file). Two other pre-existing, unrelated `tsc` errors left untouched (out of scope):
a stale `.spec.ts` referencing a renamed component, and a duplicate export ambiguity in
`state/mock-data/index.ts`.

**Phase 1 (original scope note, superseded by the DONE block above)** — Wire ONE real PSC scoring surface to live Polari data,
proving the whole approach end-to-end before touching more UI:
- Add a thin `PolariScoringService` (Angular) using the existing `polariResearchFrameworkUrl`
  + `HttpClient`, mirroring the call shapes already proven in
  `polari-platform-angular/src/app/services/scoring/scoring.service.ts` +
  `accountability.service.ts` (which I refactored earlier tonight — I know their exact
  request/response shapes already, now in `models/scoring/scoring-types.ts`).
- Pick the smallest real surface to convert first — likely `terms-page` (list real
  `ScoreConcept`/`ScoreTerm` data instead of whatever it shows today) or a read-only score
  report view, NOT the full worldview-ballot voting flow (that needs WorldviewBallot write
  support Polari already has but PSC's UI doesn't call yet — bigger lift, do second).
- Test against the live Polari API at `https://api.prf.192.168.0.210.nip.io/api/scoring/*`
  (confirmed reachable) — no backend changes needed for this phase.
- Rebuild/redeploy `psc-frontend` the same way `prf-frontend` was rebuilt all night
  (`docker compose -f docker-compose.staging-nip.yml --env-file .generated/.env.staging
  up -d --build --no-deps psc-frontend`, restart `pol-proxy`, verify via curl) — confirm
  this exact command works for psc-frontend before relying on it repeatedly.

**Phase 2 — ✅ DONE + VERIFIED (2026-07-14)**: Housing Affordability seeded as the first
real Context Tree in `scoring/housing_affordability_seed.py` — 4 terms (2 official-data-
aligned, 1 explicitly professional-judgment per Dustin's framing, 1 supply proxy), 3
worldview ScoreConcepts (price-only / quality-weighted / supply-first — quality-weighted
genuinely flips the best-state ranking vs. price-only, concretely proving Dustin's "cheap
construction quietly costs more" point), 5 Contributors, 1 ScoreGroup, 1 closed
WorldviewElection + 5 ranked-condorcet ballots. `selftest_housing_context_tree.py` 8/8
passing. Full mechanism-B pipeline (propose → tally → apply) verified against the LIVE
running API, not just the selftest: real Condorcet winner reproduced exactly, `apply`
wrote provenance-stamped weights onto the group, `groups/.../aggregate` confirms them.
Full detail (exact numbers, API responses) in the `political-scorecard-revamp` memory note.

**Phase 2 (original scope note, superseded by the DONE block above)** — Seed ONE real Context Tree end-to-end using the group-proposes-
concepts → WorldviewElection → apply-weights workflow that's already fully built (see
mechanism B above): pick Housing Affordability or Household Food Health, author 2-3
professional/interest-group ScoreConcepts each proposing their own term-weighting for it
(e.g. for Housing Affordability: a "price-only" worldview vs. a "construction-quality-
weighted" worldview), a ScoreGroup containing them, a WorldviewElection, and seed ballots —
this simultaneously (a) proves mechanism B for real content instead of the demo labor-stat
data, (b) produces the first real Context Tree, (c) gives Phase 1's live-data UI something
substantive to display. Source quantitative terms from official data per Dustin's stated
preference; professional-judgment terms (e.g. construction quality) are inherently
qualitative-but-scored, sourced from the proposing group's own definition, not "official."

**Phase 3a — ✅ DONE + VERIFIED (2026-07-14)**: `browse-worldview-ballots` now lists real
Polari `WorldviewElection` rows (both the labor demo and the new housing election) via a new
`GET /api/scoring/elections` backend endpoint (list + live tally digest in one round trip,
mirrors the existing `/concepts` route's pattern). Clicking through goes to a new read-only
`polari-elections/:name` results page (candidates, share bars, winner, pairwise matchups for
ranked-condorcet, refused ballots) — NOT the old mocked `worldview-ballot.component.ts`
editor, which is untouched and still reachable via its own entry points. Full `ng build`
clean, deployed, both new routes verified 200 live, CORS verified on the real response (not
just OPTIONS preflight — see the caveat below).

**Phase 3b — REDESIGNED per Dustin's architecture correction (2026-07-14), BACKEND
✅ DONE + VERIFIED END-TO-END, frontend UI not yet built.**

The original Phase 3b plan (citizens vote directly against Polari's generic CRUDE) is
superseded — see the "Architecture correction" section above. Dustin: ballots belong on
PSC's own locked-down backend, keyed to PSC's own anonymized user ids; Polari stays the
drafting/analysis/aggregation layer. This resolves the anonymous-write concern for the
RIGHT reason — PSC's browser clients never touch Polari's write endpoint at all; only
PSC's own backend does, server-to-server, after a citizen has already cast a real,
authenticated vote against PSC's own database.

**Built**: `PolariVoteTopic` (new) + `WorldviewVote` (redefined — was a completely
unimplemented, zero-reference stub, confirmed safe before touching) with full DAO/DTO/
Controller/TableInitializer matching `WorldviewElectionDAO`/`WorldviewElectionController`'s
exact existing house style. New `/api/polari-votes/*` endpoints: create/list/get topics,
auth-gated `POST /{id}/ballots` (voter id resolved server-side from the Keycloak JWT `sub`
claim via the existing `UserInfoService` — never client-supplied), `GET /{id}/results`
(PSC-side raw-count preview, explicitly labeled not-the-real-tally), `POST /{id}/close`,
`POST /{id}/sync`. One vote per (topic, voter) enforced at the DB layer.

**`PolariSyncService`** is the "derivative goes back to Polari" mechanism, and needed
almost zero new tally math: on sync, PSC creates a uniquely-named Polari-side
`WorldviewElection`/`GroupDisplayVote` (`psc-vote-{topicId}` — never reuses/pollutes an
existing Polari election), replays PSC's real votes as Polari `WorldviewBallot`/
`GroupDisplayBallot` rows via the generic CRUDE write path, then calls Polari's EXISTING,
already-tested `apply_election`/`apply_display_vote` unchanged. Polari does 100% of the
real tally computation, exactly matching "polari is where the aggregation lives."

**Real bug found + fixed**: Spring's `FormHttpMessageConverter`/`MultipartBodyBuilder` both
produced a multipart body Polari's Falcon parser rejected as "unreadable multipart body"
despite an explicit Content-Type header — confirmed (via `curl --trace-ascii` byte
comparison, not guessed) as a genuine RestTemplate↔Falcon incompatibility. Fixed by
building the multipart body as a raw byte array by hand, mirroring curl's exact bytes. Any
future Java→Polari-CRUDE integration should start with this raw-multipart approach.

**Verified fully end-to-end against the live running system**: 3 real Keycloak test users
created; unauthenticated cast correctly 401s; authenticated cast resolves voter id from the
JWT (never client-supplied); duplicate vote from the same voter honestly refused; 3 real
votes cast (2-1 split); PSC-side preview matched by hand; closed; synced — Polari's live
API afterward shows `housing-affordability-assembly`'s `memberWeights` genuinely derived
from this PSC vote, and the election's `voters` list shows real anonymized Keycloak `sub`
UUIDs (not real names) — proving the "anonymized ids on both sides" requirement holds, not
just asserted. Full numbers in the `political-scorecard-revamp` memory note.

**Frontend — ✅ DONE + VERIFIED (2026-07-14)**: `PolariVoteApiService` (matches the
existing `worldview-ballots-api.service.ts` convention exactly, including relying on
`auth.interceptor.ts` to attach the Keycloak bearer token automatically — no manual token
code) + `polari-vote-list`/`polari-vote-detail` components. Voting form supports all three
modes (approval/sole/ranked-condorcet), gated on real login state with a working "Log In"
button, candidate labels resolved from Polari for `concept`-kind topics via the existing
`PolariScoringService`. Linked from `browse-worldview-ballots`. Full `ng build` clean,
deployed, both routes verified live, and — critically — the ACTUAL compiled component
code confirmed present in the deployed JS bundle (not just a 200 status, which Angular's
SPA shell returns for any path regardless of whether a route is really wired). Exercised
both `polariItemKind` values live with real authenticated votes, including a second OPEN
demo topic (`2db3a850-...`) left live on the site for `'display'`-kind voting.

**Still not built**: an admin/moderator role gate on topic creation/close/sync (matches an
existing accepted gap on `WorldviewElectionController`, not newly introduced here) — the
UI itself labels these actions "not role-gated yet" rather than hiding the gap. Also
not built: the step-level diff/merge mechanism Dustin's architecture language may have
implied beyond whole-candidate voting — flagged for his own scoping, not guessed at.

**Phase 4a — ✅ BACKEND DONE + VERIFIED (2026-07-14)**: mechanism A's `GroupDisplayVote`/
`GroupDisplayBallot` (`scoring/group_display_vote.py`, new file) — reuses
`worldview_elections.py`'s tally functions by import exactly as designed. Investigated
`DisplayDefinition` first rather than guessing (forked research, verified against source):
it has NO existing group/concept binding field (`source_class` is a bare class name, not an
instance/group reference; `DISPLAY_COMPONENT_REGISTRY` is frontend-only, no backend
counterpart) — so the group↔Display relationship lives on the new vote row itself
(`candidate_display_names_json`), and applying writes the winner onto the vote row directly
(`elected_display_name`/`elected_provenance`) rather than onto `ScoreGroup` (a group can run
several display votes; `ScoreGroup`'s schema is shared/stable and stays untouched). New API
routes `GET /api/scoring/display-votes`, `GET .../{name}/tally`, `POST .../{name}/apply`.

Seeded a real demo reusing Phase 2's exact 3 professional groups + 5 voters: each proposes
its own explanatory Display for the Housing Affordability score (3 genuinely different
`DisplayDefinition` rows, minimal-but-valid `text`-type items — verified the DisplayItem
shape against `DisplayItem.ts` rather than guessing). `selftest_group_display_vote.py` 9/9
passing (approval tally math, apply gate, tie-refusal, unknown-vote/no-ballots honesty).
**Verified live against the real API**: tally reproduces the exact hand-computed 3/5-vs-2/5-
vs-2/5 approval split, `apply` records `housing-afford-explainer-tenant` as the elected
Display with correct provenance. **Correction to an earlier note in this doc**: the first
deploy attempt returned `{"ok": true, "displayVotes": []}` — empty, not erroring — and a
`GET /GroupDisplayVote` (generic CRUDE) returned a flat `404 Not Found`. The actual root
cause (confirmed by reading `polariServer.py` directly, not guessed): `GroupDisplayVote`/
`GroupDisplayBallot` were imported and used throughout `seed_pairs`, but were NEVER added to
`self.defClassList` (the ~150-class literal list around line 1002 that gates which classes
get auto-CRUDE registered at all — being in `seed_pairs` only seeds DATA for a class that's
*already* registered, it doesn't register the class itself). Fix: added both classes to
`defClassList` next to `WorldviewElection`/`WorldviewBallot`. One restart after that fix
was sufficient — "restart twice" was never the real fix, it just happened to coincide with
someone eventually noticing the actual gap. **Lesson for any future new scoring class**:
adding it to `seed_pairs` is necessary but not sufficient — it must also go in
`defClassList`, or every route for it 404s silently with no error pointing at the cause.

**Phase 4b — ✅ DONE + VERIFIED (2026-07-14)**: both halves built.

*Display-vote frontend*: `polari-display-vote-results` (built earlier alongside Phase 4a
work) reads `/api/scoring/display-votes/*` live — candidate Displays' actual explanatory
text rendered next to vote shares, not just numbers.

*Map visualization*: reused PSC's OWN existing (previously-overlooked!) `stateGeoLocations`
store — `StateGeoLocationController`/`StateGeoInitializer` already fetch and cache REAL
per-US-state boundary GeoJSON at backend startup (confirmed live: `GET /stateGeoLocations/
all` returns 50 real state polygons). Combined with Polari's already-built
`getConceptScore()`, this needed ZERO new backend work — purely a frontend integration.
Deliberately did NOT reuse Polari's own `components/maps/`/`map-renderer.ts` after
researching it first: it's Point-geometry-only (no choropleth/value-scale support), no US
state boundaries exist anywhere in Polari's own data, and it can't be imported cross-app
anyway (hard-coupled to `polari-platform-angular`'s own `@models`/`@services` path
aliases, not a published library). Also deliberately skipped adding `maplibre-gl` as a new
dependency — built a small dependency-free SVG choropleth instead
(`utils/geojson-to-svg-path.ts`, plain equirectangular projection with a `cos(meanLat)`
correction, good enough for a continental-US choropleth).

New `PolariScoreMapComponent` at `/score-map`: toggle between the 3 Housing Affordability
worldviews, watch the SAME 4 states' colors genuinely change per worldview (Alabama wins
price-only, Washington DC wins quality-weighted — the concrete point Phase 2 was built to
prove, now visually obvious). **Honest handling of a real data gap**: Washington DC is one
of the 5 scored subjects but is NOT a US state and has no boundary row in PSC's store
(confirmed against the live API) — surfaced as a visible "no map data for: Washington DC"
note rather than silently dropped from the map (DC scores 100/100 under quality-weighted —
omitting it invisibly would have been actively misleading, not just incomplete). Full
`ng build` clean, deployed, route verified live with the actual compiled component code
confirmed present in the deployed bundle, real concept-score + state-boundary data flow
verified via curl against the live APIs (not assumed from the code alone).

**Phase 5 — ✅ DONE + VERIFIED (2026-07-14)**: independently re-verified each candidate
(destructive action — checked real reference counts, JPA annotations, and migration files
before deleting anything, not just trusted the earlier flag) then deleted the 3 confirmed-
dead items: `Score.java`, `TermDimension`/`DataSeriesOrigin`/`DataSeriesProxy` (backend
stubs, zero references, unannotated, no migrations touch them), `competitive-scoring-
service.ts` (frontend, zero consumers, calls 4 routes with no matching backend controller).
**Left `ContextualizedTerm.preProcessPolariUrl`/`postProcessPolariUrl` in place** — turned
out NOT to be confirmed cruft: it's a persisted, DAO/DTO-plumbed field whose own comment
reads `// Optional: Link to a ... Polari URL (for future use)`, an intentional placeholder
for the exact kind of integration this revamp is building. Deleting it also needs a DB
migration, not just a code edit. Flagged for Dustin's own call rather than an autonomous
delete. Verified via the real build path: backend compiles clean through `Dockerfile.prod`'s
actual `mvn package` stage (`docker build -f Dockerfile.prod --target builder .` —
`Dockerfile.suite` doesn't actually compile at build time, only at container startup, so it
can't verify this); frontend `tsc --noEmit` clean (same 2 unrelated pre-existing errors).

## Mechanism C — logic-fork criterion votes (Dustin, 2026-07-14, after Phase 4b)

A third, genuinely different voting mechanism from A (whole Displays) and B (whole
worldview concepts): voting at the granularity of ONE decision point (fork) inside an
otherwise-shared decision procedure — not picking a whole competing proposal, amending one
specific if/else branch's criterion. **Dustin's own worked example (verbatim intent)**: a
repeat-offense sentencing framework's fork might default to "is this a repeat offender?" —
a proposed ALTERNATE criterion for that SAME fork could instead be "likelihood that reform
actually lasts a lifetime under their context." People vote on which of the two variations
at that fork is most valid.

**Researched before designing** (not guessed): Polari's no-code engine
(`polariNoCode/SolutionExecutionEngine.py`) already has the right graph/branching
substrate — `ConditionalChain` nodes with parameterized conditions
(`leftSource`/`conditionType`/`rightSource`, all `ValueSourceConfig`s) are genuinely
if/else forks whose criterion is DATA, not hardcoded logic. But nothing makes a fork's
criterion an independently addressable, swappable, votable entity — it's embedded inline
inside one node's `boundObjectFieldValues`, with no external reference contract. That's
the one real gap. PSC's own original design (`solution-scoring.component.html`, phases
4-5, never built) already sketched almost exactly this — "assertions at logic decision
branches," "Solution of Solutions" composition — this mechanism finishes what PSC's own
earlier design pointed at, not a new invention.

**Built** (`scoring/logic_fork_vote.py`, new file): `LogicForkCriterion` (one proposed
criterion for one named fork in one named decision procedure — `decision_procedure_name` +
`fork_name` + `is_current_default`), `LogicForkVote`/`LogicForkBallot` (reuses
`worldview_elections.py`'s tally functions by import, third time this pattern's been
reused — same as mechanism A). New API: `GET /api/scoring/logic-fork-votes`, `.../{name}
/tally`, `POST .../{name}/apply`, and `GET /api/scoring/decision-procedures/{name}
/resolved` — a human-readable "what does this procedure look like right now" summary
(vote-resolved criterion if applied, else the incumbent default, else honestly
unresolved).

**Honest scope limit, stated up front, not discovered late**: this mechanism votes on and
RECORDS the winning criterion (name, description, provenance) for one fork. It does NOT
auto-rewrite a live `SolutionDefinition`'s no-code graph JSON to splice the winning
criterion's actual condition config into the running `ConditionalChain` node — that would
mean parsing and mutating `SolutionExecutionEngine.py`'s internal schema, a separate, real
piece of engineering not attempted here. `resolved_procedure_summary()` is a readable
report, not a graph rewrite. Flagged as a genuine follow-up if Dustin wants forks to
actually execute with their vote-resolved criteria, not silently assumed done.

Seeded with Dustin's own worked example as real content (not a throwaway placeholder): the
`repeat-offense-sentencing-framework`'s `recidivism-risk-fork`, 2 candidate criteria
(`is-repeat-offender` = incumbent default; `reform-durability-likelihood` = proposed
alternate), a real 5-ballot sole-choice vote (hand-computed: reform-durability-likelihood
wins 3/5 — voters: reform-assessment-coalition, judge-1, reentry-specialist vs.
status-quo, victim-advocate). `selftest_logic_fork_vote.py` 11/11 passing, including the
before/after-apply `resolved_procedure_summary()` behavior (shows the incumbent default
before the vote is applied, the vote's winner after). **Verified live against the real
running API**, not just the selftest: tally reproduces the exact 3/5 split, `apply` records
`reform-durability-likelihood` with correct provenance, `resolved` correctly flips from
`resolvedSource: 'incumbent-default'` to `resolvedSource: 'vote'` after apply.

### Mechanism C expansion — a complete connected graph (Dustin, same session, two follow-ups)

Dustin asked for two things in sequence: (1) "come up with a more realistic criteria
evaluation... in a court trying a criminal for rape and different variations in context
that would affect conviction and sentencing," then (2) "flush out a more complete logic
graph and we will use that as a basis for going forward in refining this system." Both
built into `scoring/logic_fork_vote.py`'s seed data — this is now the reference example
for the whole mechanism, not a throwaway demo.

**5 new forks, each grounded in real, documented legal standards, not invented** (spanning
conviction AND sentencing, matching real criminal-procedure order):
- `prior-sexual-history-admissibility-fork` (pretrial evidentiary): broadly-admissible
  (pre-reform) / categorically-excluded-with-exceptions (the real modern rape-shield
  standard, FRE 412 and state equivalents — **default**) / judicial-discretion-balancing.
- `consent-determination-fork` (guilt phase): force-based (traditional statutory baseline
  — **default**) / affirmative-consent ("yes means yes" reform direction) /
  incapacitation-focused.
- `testimony-sufficiency-fork` (guilt phase): corroboration-requirement (abolished-in-
  most-US-jurisdictions historical rule) / victim-testimony-sufficient (**default** — the
  actual modern majority-US standard).
- `aggravating-mitigating-factor-weighting-fork` (sentencing): structured-point-based-
  guideline (**default** — real federal/state guideline structure) / mandatory-minimum /
  restorative-justice-informed.
- `victim-impact-weighting-fork` (sentencing): informational-only (**default**) /
  clinically-scored-trauma (validated-instrument-based) / structured-victim-voice.
- Plus a 3rd `recidivism-risk-fork` candidate added without disturbing the already-
  resolved original vote: `actuarial-risk-instrument-standard`, modeled on real published
  sex-offense recidivism tools (e.g. STATIC-99R) — a documented proposal, not yet put to a
  vote (a real, valid state this mechanism supports).

**5 new real votes, deliberately a mix of outcomes** (some reaffirm the current default,
one adopts the proposed alternate — not ideologically one-directional): consent-
determination (ranked-condorcet, `affirmative-consent-standard` wins, beating both others
pairwise) / testimony-sufficiency (sole, keeps the modern default 4-1 against a proposed
reversion) / prior-history-admissibility (ranked-condorcet, reaffirms the rape-shield
default) / aggravating-mitigating-weighting (ranked-condorcet, reaffirms the guideline
default) / victim-impact-weighting (sole, `clinically-scored-trauma-standard` wins 3/5 — a
genuine reform adoption). All hand-computed before seeding, all verified live against the
real API afterward — not staged.

**New `DecisionProcedureEdge` class** — makes the procedure an actual connected GRAPH, not
isolated forks: 10 real edges mirroring true criminal-procedure order (pretrial
evidentiary ruling → guilt-phase consent/sufficiency determinations, each with an
ACQUITTAL branch → conviction → sentencing-phase recidivism/weighting/victim-impact forks
→ final sentence). `resolved_procedure_summary()` extended to return `edges` alongside
`forks`. Same honest scope limit as the rest of the module: this is a readable graph
model, NOT wired to Polari's real no-code `SolutionExecutionEngine` — recorded explicitly,
not silently assumed. One real cross-procedure-reference wrinkle worth remembering:
`recidivism-risk-fork`'s `LogicForkCriterion` rows are tagged under the ORIGINAL
`repeat-offense-sentencing-framework` procedure (not duplicated under this new one) —
`edge-conviction-to-recidivism` references it by name across procedures, so
`resolved_procedure_summary('sexual-assault-adjudication-framework')` correctly returns 5
locally-defined forks (not 6) while the edges list still shows all 10 connections
including the cross-reference. `selftest_logic_fork_vote.py` now 19/19, covering all 6
votes' hand-computed winners and the graph's edge topology (1 true start edge, 4 terminal
edges: 2 ACQUITTAL, 1 CONVICTION, 1 SENTENCE_IMPOSED).

**Verified live against the real running API, all 5 new votes AND the full graph**: every
vote's tally reproduces its hand-computed winner exactly; all 5 were applied; `GET
/api/scoring/decision-procedures/sexual-assault-adjudication-framework/resolved` afterward
shows every fork's `resolvedSource: 'vote'` with the correct elected criterion, and the
`edges` array traces the complete flow from `[START]` through to `[SENTENCE_IMPOSED]`.

**Not yet built**: any PSC-frontend UI for proposing/voting on fork criteria or viewing the
graph (backend fully proven via direct API calls, mirroring how Phase 3b's backend was
proven before its frontend). Also not built: actually wiring `DecisionProcedureEdge`/
resolved criteria into Polari's real no-code `SolutionExecutionEngine` so a fork's
resolution changes what a live solution actually executes — the documented, still-open
follow-up mentioned throughout this section.

## System-choice implications (Dustin, 2026-07-14, after the graph expansion)

Dustin: "have an 'implications' portion, where people can assert that particular system
choices in judicial rulings have real world effects on scores. One would be rape
occurrence in the area compared to other areas... assert for judicial solutions to crimes,
that those solutions should have associated scores that they can impact which we can
review through history to see which systems work best."

**Two real gaps, both filled by REUSING existing Polari machinery, not building new
primitives from scratch** — the same "reuse over reinvention" discipline as mechanisms
A/B/C:
1. **Which criterion is actually deployed where, over time.** A `LogicForkVote`'s
   `elected_criterion_name` is one global resolution; real criminal law varies by
   jurisdiction and changes on its own schedule. New: `SystemChoiceInForce`
   (`scoring/system_choice_implications.py`, new file — `logic_fork_vote.py` was already
   past 1000 lines, kept this genuinely separate rather than appending further) — "in
   jurisdiction J, fork F is/was configured to criterion C, from date X (to date Y, or
   still in force)."
2. **The actual claim.** Reuses `ScoreAssertion` (`assertions.py`) COMPLETELY UNCHANGED —
   it already models exactly this shape (a claim binding a target to a score concept/term,
   direction/strength/evidence/an accountable asserter, a full multi-round-voted
   asserted→under-review→confirmed/rejected lifecycle). The target is a
   `LogicForkCriterion` via `target_ref_json`'s standard objectRef binding — the same seam
   used everywhere else in this codebase. Object-coherence: also added 2 new
   `ScoreSubject` rows (`system-choice-affirmative-consent`/`system-choice-force-based-
   consent`) so a system choice IS a real scored subject with an objectRef, not a bare
   label — same pattern as `beeswax-material` → `MaterialsScienceMaterial`.

**New read** (the "review through history to see which systems work best" capability):
`GET /api/scoring/system-choices/{fork}/outcomes?term=<name>` — groups jurisdictions by
which criterion they currently deploy at a fork, reports each's outcome-term value + a
per-group average.

**Genuine epistemic care taken with this specific domain, not glossed over**: reported-
rate crime metrics conflate TRUE INCIDENCE with REPORTING PROPENSITY — more survivor-
friendly evidentiary/consent standards can raise REPORTED rates even as true incidence
falls, because people trust the system more to report. This is a well-documented, real
criminological confound, not an invented caveat. Consequently:
- The comparison function's own response explicitly states it is a RAW grouped comparison,
  NOT a controlled-for-confounds causal estimate, and points at the assertions endpoint
  for the actual evidence-weighted claims.
- Seeded TWO COMPETING assertions rather than one confident claim:
  `assert-affirmative-consent-safety-improvement` (direction='supports', asserted by the
  victim advocacy coalition) and `assert-reporting-propensity-rival-explanation`
  (direction='harms' — correctly, since raising the raw reported-rate number IS what the
  confound predicts regardless of the underlying reality — asserted by the forensic
  psychology panel). Both seeded `status='under-review'`, NOT `'confirmed'` — settling a
  genuinely contested empirical question by seed-data fiat would be dishonest.
- Seeded a REAL, non-unanimous `AssertionValidityVote` split (1 valid / 1 invalid / 1
  abstain on the safety-improvement claim — a real "divisive" band, not manufactured
  consensus in either direction) — **verified live**: `tally_validity()` correctly reports
  `band: 'divisive'`, `leaning: 'tied'`, and suggests opening another round rather than
  transitioning to confirmed/rejected. The reporting-propensity confound itself is
  uncontested (2/2 valid, including from the coalition that disagrees with its policy
  implication) — a real, defensible distinction: agreeing a confound EXISTS is different
  from agreeing what it IMPLIES for policy.

**Demo data used**: the 5 states already seeded by earlier phases (CA/DC deploy
`affirmative-consent-standard`, TX/AL/ID deploy `force-based-consent-standard` — a
representative, not exactly-sourced, reflection of real policy direction differences), a
new `rape-occurrence-rate` ScoreTerm (representative 2022 estimates aligned with FBI
UCR/NIBRS + BJS NCVS aggregate reporting styles, same "flagged for a live data-refresh
pass" honesty convention as the housing/labor demo data) — verified live: affirmative-
consent group averages 36.35/100k (CA 27.4, DC 45.3), force-based group averages
37.87/100k (TX 41.8, AL 38.2, ID 33.6).

`selftest_system_choice_implications.py` 9/9 passing (now 13/13 after the correction
below). **Verified live against the real running API**, not just the selftest: the
outcomes comparison reproduces the exact hand-computed group averages; both assertions are
queryable via the existing `/api/scoring/assertions?subject=` filter (proving zero new API
surface was needed for the claims themselves — only the comparison read is genuinely new);
the validity tally's `divisive`/`tied` classification and re-vote suggestion confirmed
live, not simulated.

### Correction: comparative weighting, not binary validity (Dustin, same session)

Dustin's pushback on the framing above: *"The part you flagged is resolved by
WorldViewBallot, people can just as easily say both are valid but should be weighted, as
they could say one of the terms is valid and the other invalid. It's not strictly one or
the other, you can consider both to be important metrics and weight them comparatively to
get a standard score democratically."* Correct, and it identifies a real design error: the
original seed only offered `AssertionValidityVote`'s binary valid/invalid lens for the two
competing explanations — an implicit XOR forcing a choice between them, when the actual
epistemic situation (and Dustin's intent) is that BOTH can be real simultaneously, at
different relative weights.

**Fix: reuse mechanism B (`worldview_elections.py`), completely unchanged, exactly as
already proven for labor-quality and housing-affordability — no new voting primitive
needed.** The two explanations became WorldviewElection CANDIDATES
(`interpretation-safety-improvement-effect` / `interpretation-reporting-propensity-
effect`, minimal `ScoreConcept` stand-ins whose real role is as named election positions,
same as `member-labor-alice` et al.), under a new `ScoreGroup`
(`rape-occurrence-interpretation-assembly`) and a `WorldviewElection` run in **APPROVAL
mode specifically** — the mechanism that literally lets a voter approve BOTH candidates on
one ballot, which is the direct technical expression of "both are valid." 2 of 5 demo
voters (the judicial conference and the prosecutors' association) approved both;
`apply_election()`'s derived weights (3/7 safety ≈ 0.429, 4/7 reporting ≈ 0.571) ARE the
comparative democratic blend Dustin described — not a forced single winner, a real weighted
split reflecting genuine mixed support.

The `AssertionValidityVote` machinery from the original seed was NOT deleted — it still
answers a genuinely different, legitimate question ("is this methodological consideration
credible reasoning at all," which stayed honestly divisive) — the two mechanisms now each
answer the question they're actually suited to, rather than one forcing an XOR onto a
question that isn't one.

**Verified live against the real running API**: `tally_election()` on the new approval
election reproduces the exact hand-computed 3/7-vs-4/7 split, correctly shows the judicial
conference and prosecutors' association in BOTH candidates' voter lists; `apply_election()`
writes the comparative weights onto `rape-occurrence-interpretation-assembly` with correct
provenance; `groups/.../aggregate` confirms `memberWeights: {safety: 0.4286, reporting:
0.5714}`. `selftest_system_choice_implications.py` now 13/13 (was 9/9).

**Not yet built** (as of the correction above): any PSC-frontend UI for browsing
implications, the outcomes comparison, or the comparative-weighting election. Also not
built: extending this beyond the one worked fork/term pair (the mechanism generalizes to
any fork + any outcome term, just not demonstrated with more than one pairing yet). Both
gaps closed in the frontend rework below.

## Testing discipline for this stack (established tonight)

`psc-frontend`'s build/deploy cycle works the same way `prf-frontend`'s does — same
docker-compose command, same rebuild timing, same Angular major version (19.2). Confirmed
via the frontend rework below, not assumed.

## PSC frontend rework: mechanism C + graph + implications UI (Dustin, same session)

Per Dustin: *"Just stash [the no-code judicial-adjudication-graph work] as a plan for now,
and move on to reworking the political scorecard app frontend to match the backend work."*
The judicial no-code graph integration is stashed in
`JUDICIAL_ADJUDICATION_GRAPH_PLAN.md` (design only, not built, needs a fresh go-ahead).
This section covers what got built instead: UI for everything the backend already does
that had no frontend yet.

**Models + service layer** (`models/polari-scoring/polari-scoring-types.ts`,
`services/polari/polari-scoring.service.ts`): 7 new interface groups + 6 new
`PolariScoringService` methods (`getLogicForkVotes`, `getLogicForkVoteTally`,
`getResolvedProcedure`, `getSystemChoiceOutcomes`, `getAssertions`,
`getAssertionValidity`), field names verified against a live curl of the real API before
finalizing (not guessed from the Python source).

**Three new components**, each mirroring the existing `polari-display-vote-results`
read-only-live-view pattern:
- `polari-logic-fork-vote-results` (route `/polari-logic-fork-votes/:name`) — mechanism C
  tally view: which alternate criterion won a fork vote, with the resolved weights/shares.
- `polari-decision-procedure-graph` (route `/decision-procedures/:name`) — new UI
  territory, no prior analog: walks `forks[]` + `edges[]` from `resolved_procedure_summary`
  into a client-side tree (starting from the true-start edge, branching on `fromOutcome`,
  cycle-guarded since the edge graph is human-editable data) and renders it as a
  flowchart — fork cards show every candidate criterion with the vote-derived or
  incumbent-default winner highlighted, connected by outcome-labeled arrows down to
  terminal cards (ACQUITTAL/CONVICTION/SENTENCE_IMPOSED). Explicitly a read-only summary,
  not Polari's executable no-code graph (see the stashed plan doc for why those differ).
- `polari-system-choice-outcomes` (route `/system-choices/:fork`) — the "implications"
  view: outcome-term values grouped by in-force criterion per jurisdiction, with the
  backend's raw-not-causal `note` always rendered, never summarized away; below it, the
  evidence-weighted `ScoreAssertion`s with their multi-round validity tally loaded on
  demand (not eagerly, since most visitors won't drill into every assertion).

**Reused surface**: the comparative-weighting election
(`rape-occurrence-interpretation-assembly`) needed no new UI — it's a normal
`WorldviewElection` and already renders via the existing `polari-election-results` page
and `browse-worldview-ballots` list, exactly as intended when it was built.

**`browse-worldview-ballots`**: extended `BrowsableBallot.kind` from `'election' |
'display-vote'` to add `'logic-fork-vote'`, so all three real Polari voting mechanisms
(A/B/C) are discoverable from one browse page, each still routing to its own results view.

**Verification** (live, not just `tsc`): `npx tsc --noEmit` clean except the two
pre-existing unrelated errors (a stale `.spec.ts` and the `labor-quality-score-sample`
export collision, both documented earlier, neither touched tonight). `ng build
--configuration production` succeeded after fixing one real template bug (`@else if
(...; as x)` isn't legal in Angular's control-flow syntax — the `as` binding only works on
the primary `@if`; restructured to `@if (validityFor(...); as validity) {...} @else
{...}`) and one real service typing bug (`getAssertions()`'s conditional params object
needed an explicit `Record<string, string>` annotation to satisfy `HttpClient.get`'s
overloads). Deployed via `docker compose -f docker-compose.staging-nip.yml --env-file
.generated/.env.staging up -d --build --no-deps psc-frontend` + `docker restart
pol-proxy`. Confirmed all 4 new/changed routes serve 200 through the real nip.io proxy,
and — per the established "200 alone doesn't prove it's wired" standard — confirmed via
`docker exec psc-frontend grep` that the compiled bundle's chunks actually contain each
new component's selector/class name, not just that the SPA shell loads. Cross-checked the
exact API calls each component makes against the live backend directly: logic-fork-vote
tally, resolved-procedure forks/edges, system-choice outcome groups, and the assertions
list all returned real `ok: true` data matching the TypeScript interfaces exactly.

**Not yet built**: no UI to CREATE logic-fork votes, decision-procedure edges, or
assertions (this rework is entirely read-only views onto existing seed data, matching the
scope of "match the backend work" — creation UIs were never asked for). No visual/manual
browser check of the new pages by Dustin yet (only automated build/deploy/bundle/API
verification) — same caveat already standing for `polari-election-results` and
`polari-display-vote-results`.

## General scoring UI — the actual scoring layer, DONE + VERIFIED (2026-07-14)

Dustin's follow-up after the above ("what about scoring in general") surfaced a real
blind spot, not a deferred item: mechanisms A/B/C (voting) now had full UI, but the thing
they're supposed to feed INTO — Polari's actual score computation — had almost none.
`political-categories` listed concept names only (no score value, no detail page);
`polari-score-map` was the only consumer of `getConceptScore()` and only used it to color
a map, never rendering the term-by-term breakdown. Worse: `policies/{name}/score`,
`politicians/{name}/score`, and `cohorts/{name}/report` — the literal original framing of
this whole revamp ("compute issue scores... politician/policy accountability") — had
working backend endpoints and ZERO frontend consumers.

**4 new components + 1 hub page**, all reading response shapes verified against a live
curl before finalizing:
- `polari-concept-score-detail` (`/polari-concepts/:name/score`) — a concept's full
  live-computed report: every subject sorted by score, expandable to its term-by-term
  breakdown (raw value, normalization method, weighted contribution), missing terms
  always named per the engine's own "an absent measurement lowers the score, never
  silently shrinks the basis" design. Linked from `political-categories`' cards (a new
  "View Score" button per category) — the concept LIST now has a real detail page.
- `polari-policy-score` (`/policy-scores/:name?concept=`) — a policy's assertion-composed
  score: every counted assertion itemized (quote, direction, strength, evidence grade,
  weight), every excluded assertion named with its reason.
- `polari-politician-score` (`/politician-scores/:name?concept=`) — a politician's
  vote-weighted score: per-vote contribution, abstentions surfaced as a participation gap
  (never folded into the stance), unscoreable policies named rather than skipped.
- `polari-cohort-report` (`/cohort-reports/:name?concept=`) — a committee/party cohort's
  per-member scores plus per-policy vote cohesion, banded through the same editable
  AgreementPolicy as worldview agreement.
- `polari-accountability-hub` (`/accountability`) — landing page for the three
  concept-relative views above. Real gap found while scoping this: there is NO dedicated
  `/api/scoring/policies` or `/api/scoring/politicians` LIST route (only
  `.../{name}/score`), so a picker UI had nothing to enumerate against. Fixed without any
  new backend code: reused Polari's GENERIC CRUDE `GET /{ClassName}` (the same mechanism
  `polari-platform-angular`'s `CRUDEclassService` already relies on for
  `GET /ScoreSubject` / `GET /ScoreGroup`), parsed client-side
  (`envelope[0][className][0].data`), filtered to `kind: 'policy'` / `kind: 'politician'`
  / groups with real `memberSubjectNames`. CORS confirmed correct on this generic route
  too, not just the bespoke `/api/scoring/*` ones.

**Types added** (`polari-scoring-types.ts`): replaced two previously-`unknown[]`
placeholders (`ScoredSubject.breakdown`, `ConceptScoreReport.nestedConcepts`) with real
typed shapes now that a real consumer reads into them (`ScoreBreakdownEntry`,
`nestedConcepts: string[]`), plus `PolicyScoreReport`/`PoliticianScoreReport`/
`CohortReport` and the generic-CRUDE-backed `PolariScoreSubjectSummary`/
`PolariScoreGroupSummary`.

**Real seed data used for verification** (not invented): `policy-fair-wage-act` +
`policy-labor-standards-2020` (policies), `pol-rivera`/`pol-stone` (politicians, already
seeded for scr-6), `demo-assembly-labor-committee` (cohort), scored against `labor-quality`
— confirmed live: `policy-fair-wage-act` scores 0.93 (stance 0.86, one harms-direction
assertion partially offsetting several supports-direction ones + a carried-over
dependency), `pol-rivera` scores 0.96 (2/2 decisive votes, full participation),
`pol-stone` scores 0.07 (nay + an abstention — a real participation gap, band divisive on
the Fair Wage Act cohesion read), cohort mean 0.52.

**Real bugs found and fixed during `ng build`**: an Angular optional-chain warning-turned-
error (`a.evidence?.items?.length` on a field the type already guarantees non-null —
Angular's template type-checker treats a needless `?.` as an error, not just a lint
warning; fixed by dropping the redundant `?.`), and (from the mechanism-C rework earlier
the same session) the `@else if (...; as x)` restriction — no new instance this time,
applied the lesson from the start.

**Verified live, same discipline as every other phase tonight**: full
`ng build --configuration production` clean (2 pre-existing unrelated errors only),
deployed via the standard `docker compose ... up -d --build --no-deps psc-frontend` +
`pol-proxy` restart, all 5 new routes 200 live, `docker exec psc-frontend grep` confirmed
each new component's selector present in its compiled chunk, CORS verified correct on
BOTH the bespoke `/api/scoring/*` routes and the generic `/{ClassName}` routes the hub
page newly depends on, and the exact concept/policy/politician/cohort score numbers
rendered by each page cross-checked directly against the live backend, matching exactly.

**Timeframe picker — DONE + VERIFIED (same-session follow-up)**: added `getTimeframeContexts()`
(generic CRUDE `GET /ScoreContext` filtered to `context_type: 'timeframe'`, same pattern as
`getScoreSubjects`/`getScoreGroups`) and a real `mat-select` control on both
`polari-politician-score` and `polari-cohort-report`, deep-linkable via `?timeframe=`.
Verified live against the real seeded quarters (`q1-2022`..`q4-2022`, `year-2022`) —
including confirming the HONEST empty-result path: `pol-rivera`'s two votes are dated
2020/2024, both outside `year-2022`, so selecting that timeframe correctly returns
`"cast no decisive vote"` rather than a stale/wrong number.

## ScoreAssertion citizen submission — write path, DONE + VERIFIED (2026-07-14)

Dustin's next ask ("keep going on those") hit the flagged write-path security question
head-on: Polari's generic CRUDE write endpoint is still fully open/unauthenticated, so a
CREATE UI writing straight to it from PSC's browser would ship the exact hole Phase 3b's
ballot-hosting redesign avoided. `AskUserQuestion` was unavailable in this session
(don't-ask mode), so the three options were laid out in plain text instead; Dustin replied
"go ahead with 1" — **route through PSC's own authenticated backend**, mirroring Phase 3b's
proven architecture (Keycloak-gated PSC endpoint → server-to-server push into Polari).

**Deliberate scope cut, stated plainly rather than silently done**: built ScoreAssertion
submission, did NOT build PolicyVote submission. Reason: `ScoreAssertion` has a real
review lifecycle (`asserted → under-review → confirmed/rejected`) and
`policy_scoring.py::score_policy()` only counts `'confirmed'` assertions by default — an
unreviewed citizen submission has ZERO live scoring effect until a human moves it through
that lifecycle. `PolicyVote` has NO such status field at all — a citizen-created row would
count toward a real politician's score the instant it exists, letting anyone fabricate a
piece of a real public figure's voting record with no review gate. That's a materially
different, real integrity risk, not just the same auth question restated — flagged instead
of built.

**Backend (`political-scorecard-backend`, Java)**: `PolariSyncService.submitScoreAssertion()`
(new public method, reuses the existing raw-multipart `postCrude()` byte-for-byte — the
hard-won fix from Phase 3b for Polari's Falcon-side parser). `ScoreAssertionSubmissionService`
(new) — forces `status='asserted'` and `asserted_by=<resolved Keycloak sub>` server-side
regardless of what the client sends (a client-supplied `assertedBy` is not even a DTO
field, so it's silently ignored by Jackson, not just overwritten). `ScoreAssertionController`
(new) — `POST /api/score-assertions/submit`, `@PreAuthorize("isAuthenticated()")`, same
`UserInfoService.extractUserInfo()` pattern as `PolariVoteController.castVote`. No new PSC
DB table — unlike `PolariVoteTopic`/`WorldviewVote` (which needed local persistence for
PSC-side tallying before an aggregate sync), one ScoreAssertion submission has no tally
step, so it pushes straight through.

**Frontend**: `ScoreAssertionApiService` (client for PSC's own new endpoint, matches
`polari-vote-api.service.ts`'s pattern exactly, no manual token code —
`auth.interceptor.ts` already attaches the bearer token to any `/api/` URL) and
`polari-assertion-submission` component (`/policy-scores/:name/submit-assertion?concept=`)
— same auth-gated login-prompt pattern as `polari-vote-detail` (`isAuthenticated$` via
`AuthSelectors.selectIsAuthenticated`, `OidcService.login()` on demand). Linked from a new
"Submit an assertion" button on `polari-policy-score`. The form states plainly, up front,
that a submitted claim has zero scoring effect until reviewed — doesn't imply it counts
immediately.

**Verified live, full end-to-end, not just build-clean**: `mvn package` (Docker builder
stage) `BUILD SUCCESS`, `ng build --configuration production` clean, both `psc-backend`
and `psc-frontend` redeployed, `pol-proxy` restarted. Created a real, temporary Keycloak
test user (`assertion-test-user`, deleted after the test) in the `Political-Scorecard`
realm, obtained a real password-grant JWT, and: (1) confirmed an unauthenticated
`POST /api/score-assertions/submit` is refused with a real `401`; (2) confirmed CORS on
the new endpoint reflects the PSC origin correctly; (3) submitted a real authenticated
assertion (including a deliberately spoofed `"assertedBy":"someone-else-fake-id"` in the
request body, to prove client-supplied identity is fully ignored) and confirmed via a live
curl of Polari's `/api/scoring/assertions` that the created row shows
`assertedBy: "<the real resolved Keycloak sub>"`, NOT the spoofed value, at
`status: "asserted"`; (4) confirmed via a live `policy-fair-wage-act` score re-query that
the submission changed NOTHING (`score` still exactly `0.929947`, identical to before) and
that the new assertion appears correctly in the response's `excluded` list with the honest
reason `"status 'asserted' not in ['confirmed']"` — the safety property this whole design
rests on, proven live rather than assumed from reading the code. The route serves 200 and
the compiled bundle contains the new component's selector, confirmed the same way as
every other page tonight.

**Not yet built**: at the time this was written, PolicyVote citizen submission — see the
next section, it's now built.

## PolicyVote dual-path submission — DONE + VERIFIED (2026-07-14)

Dustin's follow-up resolved the deliberately-punted PolicyVote question directly
(verbatim): *"PolicyVote should either cite an official government source for the vote
record, and be defined by a policy voting admin, or it should be defined by the Politician
themselves or one of their cabinet people or assistants they personally authorized to
handle it."* Two real authorization paths, both enforced entirely server-side.

**Research first** (forked, read real code not guessed): confirmed `political-scorecard-backend`
ALREADY has everything needed — `SecurityConfiguration` maps Keycloak `realm_access.roles`
to Spring `ROLE_*` authorities (`hasRole()` already used, e.g.
`OidcTestController.adminEndpoint()`), and a full `KeycloakAdminService` (client-credentials
service-account token, `assignRealmRole`, `addUserToGroup`, `getUserGroups`,
`getGroupIdByName`) already exists and is used by `GroupMembershipService`. Frontend already
exposes REALM roles via `oidc.service.ts::extractRoles()` → `AuthUser.roles` →
`AuthSelectors.selectAuthUserRoles`. Nothing new needed at the infrastructure level — just
new endpoints wiring existing pieces together, confirmed before writing any code.

**Design**: `POST /api/policy-votes/submit` (`@PreAuthorize("isAuthenticated()")`) resolves
the caller to ONE of two paths server-side, never a client-supplied flag:
- **Admin path**: caller holds `ROLE_policy-voting-admin` (checked via real granted
  authorities, not trusted from the client) AND supplies a non-blank `officialSourceUrl` —
  refused with a real 403 if missing. No group membership needed; an admin can record any
  politician's vote as long as it's cited.
- **Staff path**: caller is a member of the Keycloak group
  `policy-vote-staff-<politician-name>` (checked live via `KeycloakAdminService.getUserGroups()`
  at request time — NOT a JWT claim, since Keycloak groups aren't in the token by default and
  adding a client-scope mapper felt like more infrastructure surface than reusing the
  existing admin-API call). No source URL required — the submitter's own authorized
  identity IS the record's provenance (`source` defaults to a self-attestation string
  naming the politician).

New admin-only `POST /api/policy-votes/authorize-staff` (`@PreAuthorize("hasRole('policy-voting-admin')")`)
lets an admin add a Keycloak user to a politician's staff group (created on first use via
the new `KeycloakAdminService.ensureGroupExists()`/`findUserIdByUsername()` — the only two
genuinely new methods added to that service, everything else reused unchanged).

**Real, previously-undiscovered bug found and fixed**: `SecurityConfiguration`'s
`JwtGrantedAuthoritiesConverter.setAuthoritiesClaimName("realm_access.roles")` is a NO-OP —
that converter only reads a flat top-level claim, it does NOT traverse dot-notation into a
nested object, and Keycloak's roles live under a genuinely nested `realm_access: {roles:
[...]}` claim. This means **`hasRole()` has never actually granted anything in this
codebase**, including the pre-existing `OidcTestController` demo endpoints (whose target
realm roles — `admin`/`moderator`/`user` — don't even exist in the live realm, confirming
they were never exercised live before either). Fixed by replacing the converter with a
small inline one that does the same nested-claim extraction `UserInfoService.extractRoles()`
already does correctly elsewhere in the codebase, just wired into Spring Security's
authority pipeline this time. **This fix benefits every future/past `hasRole()` check in
the app, not just this feature.**

**Second real, previously-undiscovered bug found and fixed**: `KeycloakAdminService`'s
service-account client (`admin-permissions`) has been calling Keycloak with a WRONG secret
since at least whenever `pol-keycloak` was last freshly deployed — `pol-keycloak/keycloak-admin.env`
declares `KEYCLOAK_ADMIN_CLIENT_SECRET`, and its own comment claims `configure_clients.sh`
applies it to the live client at startup, but that script only ever manages redirect URIs,
never secrets. The declared value had drifted from the client's real secret, so every
`KeycloakAdminService` call (including pre-existing `GroupMembershipService` calls) was
silently broken — confirmed live via a real `401 unauthorized_client` when this feature
first tried to use it. Fixed by regenerating the client's real secret via `kcadm.sh create
clients/{id}/client-secret` and syncing `keycloak-admin.env` to match, with the file's
comment corrected to stop claiming an automatic sync that doesn't exist. **Also benefits
`GroupMembershipService`, not just this feature.**

**Frontend**: `PolicyVoteSubmissionApiService`, `polari-policy-vote-submission` component
(`/politician-scores/:name/submit-vote`, auth-gated like the assertion form, shows an
"admin role detected" chip when `selectAuthUserRoles` includes `policy-voting-admin` —
purely cosmetic labeling, the backend re-verifies regardless), `polari-authorize-staff`
component (`/policy-votes/authorize-staff`, admin-only page reachable from the
Accountability Hub). Linked from a new "Submit a vote record" button on
`polari-politician-score`.

**Verified live, full end-to-end, 6 real cases, not just build-clean**: created 2
temporary Keycloak test users (`vote-admin-test` with the real `policy-voting-admin`
role assigned, `vote-random-citizen` with nothing — both deleted after testing) plus reused
the real seeded `pol-rivera`/`policy-fair-wage-act`/`policy-labor-standards-2020`. (1) admin
path missing source → real 403; (2) admin path with source → real 201, lands with
`provenance_id: psc-citizen-submission-admin`; (3) random citizen with no role/group → real
403; (4) admin authorizes the random citizen as `pol-rivera`'s staff → real 200; (5) a
non-admin attempting to authorize staff → real 403 (blocked at the `@PreAuthorize` layer
before even reaching application code); (6) the now-authorized former-random-citizen
submits a vote via the staff path with NO source URL → real 201, lands with
`provenance_id: psc-citizen-submission-staff`, `source: "self-attested by an authorized
submitter for pol-rivera"`. **Then confirmed the actual integrity-critical behavior**:
re-queried `pol-rivera`'s live score — genuinely changed (3 decisive votes now, not 2;
stance dropped from 0.929947 to 0.333333, correctly reflecting the new admin-submitted nay
partially offsetting the earlier yea; the staff-submitted abstain correctly shows in
`abstains`, not counted as a stance) — proving the dual-path gate is the ONLY thing
standing between an arbitrary citizen and a real politician's live score, and that it holds.
CORS verified correct on `/api/policy-votes/*`. Both new frontend routes 200 live with
their compiled component code confirmed present in the bundle.

**Realm role registered for future fresh deploys too**: added `policy-voting-admin` to
`pol-keycloak/realm-imports/political-scorecard-realm.json` (matches the live-created role
exactly, including its Keycloak-assigned id) — NOTE for future sessions: this JSON only
gets applied via `POST /admin/realms` on container boot, which is a CREATE and silently
409s against an already-existing realm (confirmed by reading `load_realms.sh`), so editing
this file does NOT retroactively update the current live staging realm — that always needs
a direct `kcadm.sh`/Admin-API call against the running instance, same as this session did.

**Not yet built**: no UI to browse/revoke existing staff authorizations (only grant); no
admin UI to list who currently holds `policy-voting-admin` (only Keycloak's own admin
console can show that today). Both are real, scoped-out follow-ups.

**Independently re-verified afterward, and one real cleanup gap found and fixed**: rather
than trust the above summary at face value, re-ran the core claims from scratch — fresh
`mvn package --no-cache` (`BUILD SUCCESS`, 193 source files), confirmed both new endpoints
live-reject unauthenticated requests (401), confirmed the `hasRole()` fix genuinely works
by creating a fresh test user, hitting `/authorize-staff` BEFORE granting the role (real
403) and AFTER granting it with a fresh token (passes the gate — request reaches
application code and fails for an unrelated, expected reason instead), and ran a full
staff-authorization + vote-submission round trip myself. **Found**: the two test
`PolicyVote` rows from the write-up above's step (6) were still live in Polari — unlike a
`ScoreAssertion` test row (harmless until confirmed), a `PolicyVote` has NO review gate and
counts immediately, so leaving test rows in place had silently corrupted `pol-rivera`'s
live score away from this document's own hand-verified `0.964974`/2-decisive-votes
baseline (referenced elsewhere in this doc and in memory) to a stale `0.666667`/3-votes
value. Deleted the 3 leftover test `PolicyVote` rows (2 from the original verification + 1
from my own re-test) via generic CRUDE `DELETE /PolicyVote`, confirmed `pol-rivera` is back
to exactly `0.964974` / 2 decisive votes. **Standing lesson for future sessions**: any test
that submits through `/api/policy-votes/submit` MUST delete the resulting `PolicyVote` row
afterward (`DELETE /PolicyVote` with `targetInstance: {"id": "<row id>"}`) — never leave
one live the way a ScoreAssertion test row can safely be left, since there's no
'asserted'-vs-'confirmed' buffer protecting the reference dataset.
