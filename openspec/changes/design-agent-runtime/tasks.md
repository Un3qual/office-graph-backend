## 1. Review And Acceptance

- [x] 1.1 Review the foundation, work-graph, governance, change-proposal,
  persistence, revision/audit, and code-organization constraints that feed the
  agent runtime.
- [x] 1.2 Create the proposal for `design-agent-runtime`.
- [x] 1.3 Create the `agent-runtime` capability spec with runtime entry,
  context package, context expansion, model/tool separation, mutation boundary,
  provenance, and handoff requirements.
- [x] 1.4 Create the design document for the runtime architecture and first
  scope.

## 2. Capability Spec Review

- [x] 2.1 Review agent runtime entry-point requirements for embedded,
  automatic, delegated, and tool-action starts.
- [x] 2.2 Review authorized context package requirements for projection
  rationale, restricted context, and context-boundary explanations.
- [x] 2.3 Review context expansion requirements for additional scope requests
  and durable expansion decisions.
- [x] 2.4 Review model/tool separation requirements for untrusted structured
  output, tool authorization, and classified tool results.
- [x] 2.5 Review durable mutation boundary requirements for proposed graph
  changes and accepted domain actions.
- [x] 2.6 Review provenance and operation-context requirements for agent
  outputs, tool actions, external actions, errors, and verification-sensitive
  contributions.
- [x] 2.7 Review runtime handoff requirements for work packets, runs,
  verification, API/realtime projections, and review surfaces.

## 3. Open Decisions Before Runtime Code

- [x] 3.1 Decide which first tool actions are low-risk enough for direct domain
  actions rather than change proposals.
- [x] 3.2 Decide which model/tool payload fields are retained, summarized,
  hashed, or dropped under the first AI data-control policy.
- [x] 3.3 Decide which runtime events belong in the future `runs` model versus
  conversation, audit, operation-correlation, or provider-specific event
  tables.
- [x] 3.4 Decide the first automatic review agent: spec review, plan review, PR
  review comment triage, verification evidence review, or another graph-native
  review.
- [x] 3.5 Decide how much context package rationale is visible to ordinary
  users versus administrators, auditors, and debugging operators.

## 4. Follow-On Planning Work

- [x] 4.1 Feed invocation envelope, context package, authority, and autonomy
  envelope requirements into `design-work-packets-and-readiness`.
- [x] 4.2 Feed runtime state, run references, failure events, tool actions, and
  provenance requirements into `design-runs-and-verification`.
- [x] 4.3 Confirm runtime status, authority, context-boundary, approval,
  failure, and provenance projection requirements are represented in
  `openspec/changes/archive/2026-06-23-design-api-realtime-and-ui-projections`
  and the durable `ash-api-surface`, `realtime-delivery`, and
  `ui-projection-contracts` specs.
- [x] 4.4 Feed change-proposal and accepted-domain-action runtime mutation rules
  into `design-proposed-graph-changes`.
- [x] 4.5 Confirm tool manifest, credential scope, external action, and AI
  data-control runtime requirements are represented in
  `openspec/changes/archive/2026-06-23-design-enterprise-governance`, the
  durable governance specs, and `design-identity-and-authentication`.
- [x] 4.6 Feed runtime entrypoint, operation-context, Boundary, and future
  extractability requirements into `design-code-organization-and-boundaries`.
- [x] 4.7 Confirm graph projection, node conversation, context expansion, and
  embedded-agent mutation requirements are represented in
  `openspec/changes/archive/2026-06-23-design-work-graph-core` and the durable
  graph/core conversation specs.

## 5. Validation

- [x] 5.1 Run `openspec status --change design-agent-runtime`.
- [x] 5.2 Run `openspec validate design-agent-runtime --strict`.
- [x] 5.3 Run `openspec validate --changes --strict`.
