# Judicial adjudication no-code graph — plan (stashed, not built)

**Status: PLANNED, NOT STARTED. Dustin explicitly asked to stash this as a plan and move
on to frontend work (2026-07-14). Do not begin implementation without a fresh go-ahead —
this doc exists so the design isn't lost, not as a queued task.**

## The ask

Dustin: *"the logic diagram should be based largely on the same sort of engine we are using
for no-code already. Drag and drop logic blocks, with arrows connecting and context
flowing so that an object of the context of the crime can flow through the logic blocks
step by step in a court and be adjudicated by either a judge and/or a jury of peers."*

This means wiring the decision-procedure model already built (`scoring/logic_fork_vote.py`
— `LogicForkCriterion`/`LogicForkVote`/`DecisionProcedureEdge`, see
`DEMOCRATIC_SCORECARD_REVAMP_PLAN.md`'s "Mechanism C" section) into Polari's REAL no-code
execution engine (`polariNoCode/SolutionExecutionEngine.py` + the existing D3 drag-and-drop
graph editor in `polari-platform-angular`) — not the simpler custom `DecisionProcedureEdge`
summary model, which is a readable report, not an executable graph.

## Research findings (verified against exact code, not guessed — full detail in the forked
research transcript this plan is derived from)

**The one finding that reshapes the design**: Polari's no-code engine has **no pause/resume
capability**. `SolutionExecutionEngine.execute()` runs one `while current_state is not None`
loop synchronously to completion (or a 200k-step cap) inside a single call — there is no
`yield`, no persisted mid-run state, no "waiting for input" status anywhere in
`ExecutionTrace`. Once a graph starts, every value any `ConditionalChain` node reads must
already be in the flat execution `context` dict at that moment — supplied at the very start
of `execute()` (via `instance_fields`/`input_params`) or written by an earlier state in the
*same* run. A judge/jury factual determination supplied mid-flow, after the graph has
already started, cannot be read by a later node in that same execution.

**The established precedent for human-paced, multi-step workflows in this codebase**
(`simulations/multi_scale_stages.py::evaluate_stage_gate`,
`simulations/simulation_runner.py::validate_initial_conditions`) does NOT try to pause a
single graph — it runs **many small, complete graph executions**, orchestrated from
*outside* the engine, with a human supplying input *between* runs, not *during* one. This
is the pattern to follow, not fight.

**Other exact, load-bearing facts** (see the full research transcript for citations):
- `SolutionDefinition.definition` is a JSON blob: `{solutionName, stateInstances: [...]}`.
  Each `stateInstance`: `{stateName, stateClass, boundObjectClass, boundObjectFieldValues,
  slots: [...]}`. `boundClass` (top-level) is decorative/codegen-only, never read by
  execution — safe to omit.
- `ConditionalChain` node's `boundObjectFieldValues`: `{displayName, description,
  defaultLogicalOperator, links: [ConditionalChainLink, ...]}`. Each link:
  `{id, displayName, leftSource, conditionType, rightSource, logicalOperator,
  isStateSpaceObject}` — `leftSource`/`rightSource` are `ValueSourceConfig`s.
- `ValueSourceConfig` for reading the flowing case-context: `{sourceType:
  'from_source_object', sourceObjectPath: 'self.<fieldName>'}` — resolves against the flat
  `context` dict (strips the `self.` prefix). For a literal: `{sourceType:
  'direct_assignment', directValue: <v>, directValueType: 'int'|'float'|'bool'|'str'}`.
  **Never use `sourceType: 'from_dataset'`** — unimplemented server-side, silently
  returns `None`.
- Branch routing: `combined == True → branch_taken = 0`, else `1` — this indexes into
  **output-slot LIST ORDER**, not each slot's own `index` field. Order the `slots` array
  so the "True"/proceed branch is the first non-input slot if you want branch 0 to mean
  what it looks like it means.
- `nestedConditions` on a link is a UI-only field — the Python engine never interprets it.
  Only flat `links` lists (combined via each link's own `logicalOperator`) actually drive
  execution.
- `between`/`in`/`like`/`regexMatch` condition types exist in the TS type union but are
  **absent from Python's `COMPARISON_OPS`** and silently fall back to `operator.eq` —
  avoid them.
- The case's fact bag (`instance_fields`/`input_params`) can be an entirely ad hoc flat
  dict — **no pre-existing Polari `treeObject` class is required** for it. Confirmed: zero
  reflection/schema validation happens on these dicts anywhere in the engine.
- Real entry point (class method, not a free function):
  ```python
  from polariNoCode.SolutionExecutionEngine import SolutionExecutionEngine, StepConfig
  engine = SolutionExecutionEngine(manager=manager)
  trace = engine.execute(solution_data=parsed_definition_dict,
                          input_params={...}, config=StepConfig(mode='step', record_context=True),
                          target_runtime='python_backend', instance_fields={...})
  # trace.status: 'running'|'completed'|'errored'|'cancelled'
  # trace.final_return_value, trace.error_summary, trace.steps (per-step snapshots)
  ```
  Working, non-simulation precedent to pattern-match: `polariNoCode/selftest_composition.py`
  (a pure logic/recursion test suite, zero domain coupling) — its `node()`/`solution()`/
  `entry()`/`var_src()`/`lit_src()` helper functions are a ready-made minimal DSL for
  hand-building graphs from Python, already proven to work end-to-end.

## Proposed architecture (design only — not built)

1. **New Polari class `CourtCase`** — persists a case's accumulated fact context across
   multiple fork-graph invocations (something has to hold state between runs, since the
   engine itself doesn't): `name, decision_procedure_name, current_fork, status
   ('in-progress'|'acquitted'|'convicted'|'sentenced'), context_json (the flat case-facts
   dict, accumulated), execution_log_json (JSON list of {fork, criterion_used,
   judge_jury_input, outcome, at}), adjudicator_type ('judge'|'jury'), adjudicator_name
   (Contributor), jurisdiction_subject_name, provenance_id, notes`.

2. **A compiler**: `LogicForkCriterion` + the fork's currently-resolved criterion (from
   `resolved_procedure_summary()`) → a real, small `SolutionDefinition` PER FORK. Each
   compiled graph: an `InitialState` entry reading the case context + the judge/jury's
   supplied determination for that one fork, ONE `ConditionalChain` node evaluating that
   determination against the fork's resolved criterion, and `ReturnValue`/`ReturnStatement`
   terminal states for each branch outcome. Small, focused, individually
   inspectable/editable in the existing D3 UI — not one giant procedure-wide graph.

3. **Orchestration function** `advance_case(manager, case_name, judge_jury_input)`:
   - Look up the `CourtCase`'s `current_fork`.
   - Compile (or fetch a cached compiled) `SolutionDefinition` for that fork + its
     currently-resolved criterion.
   - Call `SolutionExecutionEngine.execute()` with the case's accumulated context +
     `judge_jury_input` for this fork.
   - Read `trace.final_return_value` / which terminal state was hit → the fork's outcome
     label (e.g. `'consent-established'` / `'consent-not-established'`).
   - Use the ALREADY-BUILT `DecisionProcedureEdge` rows (exact same data mechanism C's
     `resolved_procedure_summary()` already reads) to look up the next fork or terminal
     outcome for `(from_fork=this fork, from_outcome=this outcome)`.
   - Update `CourtCase.current_fork` (or set `status` if a terminal was reached), append to
     `execution_log_json`, persist.
   - This is `evaluate_stage_gate`'s exact pattern, applied to judicial forks instead of
     simulation stages — reuse over reinvention, again.

4. **API surface** (sketch, not built): `POST /api/scoring/court-cases/create` (start a
   case, decision_procedure_name + initial context), `POST /api/scoring/court-cases/{name}
   /advance` (submit the judge/jury's determination for the current fork, triggers
   `advance_case`), `GET /api/scoring/court-cases/{name}` (current state + full execution
   log — the "context flowing through step by step" audit trail Dustin described).

## Isolation plan (per Dustin, 2026-07-14: "we need to isolate it into its own branch so
it cannot break everything")

Real git isolation needs a commit boundary, not just a branch — branching alone doesn't
separate uncommitted changes. When this work resumes:
1. Confirm with Dustin before committing anything (standing rule — never commit without
   being asked).
2. Once confirmed: commit the current, fully-tested, already-deployed scoring work
   (Phases 1-4b, mechanisms A/B/C, system-choice implications + the comparative-weighting
   correction — everything already verified live against the running system) as a
   checkpoint on `dev` in `polari-rf-node`.
3. Branch off that checkpoint specifically for this feature (e.g.
   `dev-judicial-adjudication-graph`) — so if the no-code compiler/execution work goes
   sideways, it's contained there and `dev` stays at a known-good, already-verified state.
4. Build iteratively on that branch: `CourtCase` class → compiler → `advance_case()` →
   selftest (mirroring `selftest_composition.py`'s in-memory-manager pattern, no real
   server needed for a first pass) → THEN docker cp + live verification once the selftest
   is solid.

## Explicitly NOT started

No code has been written for this feature. `CourtCase` does not exist. No compiler exists.
No API routes exist. This document is the complete state of the plan as of 2026-07-14 —
read this first if resuming, don't re-derive the no-code engine research (it's expensive;
re-read the plan doc instead).
