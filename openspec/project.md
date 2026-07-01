# Office Graph Project Context

Office Graph is a new enterprise product for whole companies, not only software
engineering departments. The current intent is to build an agent-native work
graph for planning, requirements, execution, review, and verification across
teams such as engineering, design, marketing, social media, finance,
operations, and leadership. The product should make human and agent work
traceable, auditable, and reusable rather than leaving decisions buried in
chats, tickets, documents, commits, PR comments, spreadsheets, design tools,
social calendars, finance systems, CI logs, and observability tools.

Software engineering is an important early proving workflow because it has
concrete signals, artifacts, review loops, and verification evidence. It should
shape examples and dogfooding, but it must not narrow the product ontology or
architecture into a software-only system.

## Reference Inputs

- `chatgpt-reference-thread.md`: raw prior brainstorming conversation.
- `chatgpt-generated-prd.md`: generated backend PRD reference.

These files are research inputs, not final requirements. Promote only stable
decisions into this file or into formal OpenSpec specs.

## Fixed Choices

- Backend stack: Elixir, Phoenix, Ash, and Postgres.
- Development Postgres runs through Docker Compose. The project Nix shell
  remains the entrypoint for application/runtime CLI tools, but local database
  process management should be documented as `docker compose` commands.
- Frontend stack: React from day one, though frontend work has not started yet.
- Phoenix LiveView is forbidden for the product UI.
- API surface: both GraphQL and JSON API are required.
- GraphQL should use capability interfaces for shared API affordances such as
  closable, updatable, reactable, comment-like, approvable, subscribable, and
  projection-capable resources. These interfaces are API contracts over typed
  resources and authorization-aware resolvers; they do not justify
  polymorphic local storage or generic mutation paths.
- Workflow source of truth: OpenSpec.
- Runtime and CLI dependencies come from the project Nix flake.
- Enterprise requirements are first-class, not later add-ons.
- Authorization is a core product concern, not a controller-level afterthought.
  Use a hybrid model: RBAC for coarse roles, ABAC for contextual rules,
  relationship-based authorization for graph/work relationships, capability
  permissions for tools and agents, and explicit grants only for exceptions.
- User-facing governance vocabulary should align with conventional enterprise
  software wherever possible: organization, workspace, department, org unit,
  team, group, role, custom role, permission, policy, manager, owner,
  approver, service account, integration, audit log, access review, retention,
  and legal hold. Richer backend-only terms should be reserved for new
  concepts or concepts that do not map cleanly to conventional words.
- Integrations and external connections should be isolated behind packages,
  likely separate Hex packages when they become substantial.
- Office Graph will have an internal agent runtime for graph-aware automatic
  agents and embedded conversations.
- The MVP direction is an agent-governed company work graph: a
  department-neutral work graph, first-class internal agent runtime, and
  software review/fix/verification as the first deep proving workflow.
  Department-specific workflow packs are an expansion pattern, not the first
  product surface.
- First buyer, daily user, and metric: target AI-forward company leadership,
  operations leadership, AI/platform leadership, or department leaders who own
  governed human-agent execution across teams; the daily user is a
  cross-functional work owner or agent operator who turns messy signals into
  work packets, work runs, and evidence-backed decisions; the flagship metric
  is packet-backed verified completion rate across selected cross-functional
  workflows. Software review/fix/verification remains the first high-fidelity
  proving workflow, but it must not make the buyer, user, or metric
  engineering-only.
- Linear is not a concern for the initial planning slice.
- OpenSpec is only the workflow for building Office Graph. Office Graph product
  features are not inherently OpenSpec features.
- Retire GraphPatch and `proposed_graph_change` as product language. Keep the
  underlying safety pattern as structured change proposals that apply through
  validated domain actions.
- Backend extensibility is a first-order requirement. New capabilities should
  feel like natural additions to the domain model rather than late add-ons that
  require broad rewrites.
- Prefer provider-neutral relational base tables for shared concepts. For
  example, a `pull_requests` table should represent pull requests from multiple
  sources; source-specific extension tables such as `github_pull_requests` or
  `gitlab_pull_requests` should exist only when source-specific data or
  behavior justifies them.
- Avoid JSON/JSONB columns for core domain data wherever possible. Use typed
  columns, join tables, and extension tables first. JSON is acceptable for raw
  external payload archival or truly unmodeled edge data, and should not become
  the normal query surface.
- If Office Graph adds configurable form, survey, intake, or field-builder
  behavior, queryable native product data should use versioned typed
  definitions, options, submissions, answers, and value tables. JSON may still
  preserve raw imported form payloads, third-party snapshots, or temporary
  unmodeled configuration with an explicit promotion path.
- Permission data should be relational and typed. Model principals, roles,
  role assignments, capabilities, scopes, team memberships, grants, tool
  permissions, and autonomy policies explicitly rather than hiding policy state
  in JSON claims or metadata blobs.
- Default graph visibility should be workspace scoped, with
  initiative/project as the normal work-container scope. Graph edges provide
  context but do not automatically grant access to connected records.
  Cross-boundary links may reveal redacted summaries or restricted placeholders
  only when policy allows that disclosure.
- `Project` should be treated as a customer-facing alias for an initiative or
  bounded work container, not as a synonym for team, component, repository, or
  task. Teams, components, repositories, services, departments, and code areas
  are related resources/scopes that attach to the work graph.
- MVP authorization should support a custom-role data model, external group
  mapping, and SCIM-compatible provisioning from day one, even if the first
  custom-role UI is minimal.
- Tree-like permissions should use typed hierarchical scopes and explicit
  descendant inheritance, not wildcard permission strings such as
  `frontend.*`. Graph edges remain context relationships and do not create
  permission inheritance.
- Authorization policy is a versioned rule set that interprets facts for a
  specific actor, action, resource, scope, classification, tool, integration,
  or run context. Role assignments, grants, classifications, group
  memberships, ownership links, manager relationships, and agent capabilities
  are facts; policies decide what those facts mean. Sensitive decision records
  should reference immutable policy bundle versions and relevant fact versions.
- Agent effective permissions are the intersection of delegator/user
  permissions, agent capabilities, work packet autonomy policy, tool or
  integration scope, and organization policy. Agents must not simply inherit
  unrestricted user authority.
- Cross-scope agent runs should request context expansion explicitly and may
  receive policy-approved redacted context, approval-gated access, or
  temporary scoped grants. Automatic agent runs need an explicit authority
  basis even when no human directly starts them.
- Agent automation should use approved autonomy envelopes so humans approve
  boundaries rather than babysitting repeated low-risk steps. Higher-risk
  actions such as sensitive context access, credential use, external writes,
  exports, destructive changes, broad data sweeps, or cross-organization access
  require explicit policy support or approval gates.
- Approval gates and separation-of-duties rules should resolve eligible
  approvers from the customer's existing company structure when possible:
  SCIM/IdP groups, departments, org units, manager relationships, owners,
  custom roles, data owners, code owners, finance/legal/security roles, and
  explicit grants.
- Secret values should sit behind a `SecretStore` boundary. The managed SaaS
  default can store customer-supplied integration secrets in Office
  Graph-managed secret infrastructure with strong tenant scoping, audit,
  rotation, and revocation. The model should also preserve a path to
  customer-managed secret stores through narrow delegated access.
- Edit/revision history and soft deletion are required from the beginning.
  Avoid a single giant JSON-backed versions table. Prefer typed, aggregate-aware
  history/revision/event tables that preserve actor, source, agent run,
  timestamp, reason, supersession, and affected fields.
- Audit logs and revision history should share operation/correlation records
  when they refer to the same command, but should not duplicate each other's
  payloads. Revisions reconstruct meaningful state changes; audit records
  explain sensitive actor behavior and policy decisions.
- Code organization must assume a large backend. Use a modular monolith with
  explicit bounded contexts, the Boundary library, DDD-style domain boundaries,
  clear public APIs per context, and dependency rules that prevent lateral
  coupling.
- Some domains should be designed so they can later be extracted into reusable
  libraries for future projects. Authentication/identity, authorization,
  integration primitives, revision/audit primitives, and the agent runtime are
  candidate extraction targets. Do not split them into separate libraries
  prematurely, but keep their dependencies, configuration, storage assumptions,
  and public APIs clean enough that extraction remains practical.

## Current Working Direction

- Product frame: company-wide agent-native work graph with department-specific
  projections, integrations, and agent libraries.
- MVP frame: agent-governed company work graph. The graph is the system of
  record, the internal runtime makes the graph active, and department packs are
  later extensions over shared primitives.
- First buyer/user/metric frame: AI-forward cross-functional leaders buy
  governed human-agent execution; cross-functional work owners and agent
  operators use it daily; the flagship metric is packet-backed verified
  completion rate across selected workflows.
- Early proving workflow: software teams delegating work to humans and agents,
  including PR review comments, fixes, commits, Sentry events, CI results, and
  code-review evidence. This is the first deep proof point, not a restriction
  on the company-wide product frame.
- Core loop: signal -> question -> decision -> work packet
  -> human or agent run -> evidence -> verification -> reusable context.
- Signal sources should eventually include anything an organization uses:
  chat, documents, tickets, GitHub, Sentry, CI, design tools, marketing tools,
  social platforms, finance systems, spreadsheets, email, and manual intake.
- Integration strategy: accept signals from external systems first, store and
  analyze the resulting work, then gradually move high-value workflows into
  native Office Graph agents and graph-native review/approval loops.
- Defensibility strategy: integrate broadly so Office Graph fits into existing
  company workflows, but use those integrations as adoption ramps toward
  native Office Graph workflows that are materially better because they combine
  cross-tool context, graph-native agents, permissions, revision history, and
  evidence. Office Graph should not remain a thin layer that an integrated
  vendor can absorb as a feature.
- Initial value: reduce ambiguity before delegation, preserve decisions, set
  autonomy boundaries, run graph-aware agents, link completion to evidence, and
  make prior work reusable in future context.
- Near-term product surface: inbox, work item triage, work packet view, run
  view, evidence and verification view, focused trace/debug detail, and
  integration settings. Question queues, graph conversations, and agent
  execution internals require workflow justification before becoming default
  operator-facing vocabulary.
- Enterprise identity testing should not require paid hosted IdPs during
  normal development. Use a local identity lab with authentik for OIDC, SAML,
  and SCIM, optional Keycloak for OIDC/SAML compatibility, and a repo-owned
  fake SCIM client for deterministic contract tests. Hosted vendor smoke tests
  can be optional later.
- MVP custom-role management should have a basic frontend UI and backend
  endpoints for custom roles, external group mappings, and scoped assignments,
  while a polished role-builder experience can wait.

## Technical Direction

Locked or strongly preferred technical direction:

- Phoenix API for a React frontend.
- Absinthe GraphQL plus a JSON API.
- No LiveView.
- Phoenix PubSub, Channels, and OTP processes for realtime and ephemeral run
  state.
- Oban for durable async jobs.
- Postgres as the durable source of truth for graph state, events, audit,
  artifacts, runs, work packets, and integration data.
- GraphQL global IDs, durable internal primary keys, and URL-facing scoped
  numbers or handles should stay separate. Scoped auto-incrementing URL
  numbers are feasible but not yet locked; if adopted, they must be durable
  URL tokens that are scoped, allocated transactionally, and never reassigned
  to another resource after deletion.
- Internal agent runtime as a core product capability. It should be graph-aware,
  permissioned, auditable, and connected to node-scoped conversations,
  automatic review agents, and run records.
- Library-ready internal boundaries for reusable domains such as
  authentication/identity, authorization, agent runtime, integration adapters,
  and revision/audit primitives.
- Authorization should be a bounded context and future extraction candidate. It
  should expose policy checks and decision records to Ash resources, Phoenix
  contexts, GraphQL resolvers, JSON API controllers, Oban jobs, integrations,
  and the agent runtime without letting those callers duplicate policy logic.
- Ash and domain policies should own business authorization semantics.
  Postgres row-level security may be added later as defense-in-depth for tenant
  isolation or especially sensitive tables, but it should not become the main
  product policy engine in the first design.
- Provider-neutral relational schemas for common external concepts such as
  repositories, branches, commits, pull requests, issues, review comments,
  checks, design assets, campaign assets, documents, and finance records.
- Typed revision/history storage and soft deletion for graph items, domain
  records, conversations, runs, decisions, and integration-derived artifacts.
- No Redis, Neo4j, Kafka, RabbitMQ, or microservice split for the MVP unless a
  real requirement forces it.
- Use Ash for resource actions, policies, validation, state transitions, and
  API-facing domain boundaries.
- Use explicit SQL/Ecto where graph traversal, replay, analytics, or bulk
  operations exceed what should be forced through Ash.
- Treat query shape as part of the design review for new or changed reads.
  Keep watching for avoidable query fanout and N+1 patterns in API,
  projection, GraphQL, JSON, and background-job paths; prefer batched reads,
  shared projection assembly, and focused query-count regression coverage when
  a workflow can grow by rows, graph links, runs, evidence, or integration
  records.

## Working Vocabulary

- Work graph: the typed graph of signals, tasks, questions, decisions, checks,
  evidence, artifacts, runs, work packets, documents, plans, users, teams, and
  external artifacts.
- Initiative/project: a bounded work container for a business, product, or
  operational outcome that can span teams, components, repositories,
  departments, requirements, tasks, approvals, and verification. `Project` is a
  familiar alias; initiative is the more precise concept.
- Workstream: a team-, domain-, or phase-specific execution lane inside an
  initiative, such as backend implementation, frontend implementation, design
  review, security review, rollout, or finance approval.
- Team/component/repository/service: related scopes or resources that can own,
  participate in, or be affected by work, but are not automatically projects.
- Signal: an inbound external or manual trigger, such as a Sentry issue,
  GitHub issue, failing CI run, PR event, design comment, campaign request,
  social post, finance anomaly, spreadsheet row, pasted bug report, or messy
  request.
- Node or block: an addressable graph item. Examples may include a signal,
  task, question, decision, check, evidence item, plan section, requirement,
  validation rule, generated UI component, or work-packet source. This is
  graph/debug vocabulary by default, not the primary operator-facing product
  spine.
- Edge: a typed relationship between nodes, such as generated-from, raises,
  answers, blocked-by, depends-on, requires, validates, produced,
  evidence-for, duplicates, discusses, reviewed-by, or failed-in.
- Question: a decision request that blocks planning, delegation, verification,
  or safe execution.
- Decision: a recorded answer to a question, with provenance and affected
  graph links.
- Requirement: durable desired behavior or constraint.
- Task: intended work needed to change the system or graph.
- Check: something that must be true before a task, packet, or requirement is
  considered satisfied.
- Evidence: proof or counterproof attached to a check, task, run, or
  requirement. Examples include a merged PR, passing CI run, Sentry quiet
  period, human approval, test result, or review decision.
- Change proposal: deferred MVP vocabulary for proposed mutation review. If it
  returns, it proposes typed domain command input and applies through owning
  domain actions rather than mutating the graph projection as source of truth.
- External reference: a typed link between an Office Graph record and a record
  in an external system, including provider, source identifier, URL, sync
  state, and provenance.
- Revision: a durable record of a meaningful change to a graph item or domain
  record. Revisions should be typed enough to query and reconstruct important
  history without relying on opaque JSON snapshots.
- Work packet: a bounded, versioned package of objective, context,
  constraints, decisions, artifacts, autonomy policy, success criteria,
  verification steps, and escalation rules for a human or agent.
- Agent readiness: a Work Packet readiness state that explains whether work is
  ready for agent execution, human execution, investigation only, senior
  review, or human-only handling. It is packet state by default, not a separate
  first-spine product noun.
- Agent runtime: Office Graph's managed environment for graph-aware agents that
  can converse about selected graph items, run automatic reviews, produce
  findings, create change proposals, and perform approved tool actions.
- Automatic agent: an agent attached to a graph item, workflow, trigger, or
  completion event. Examples include code review, security review, spec review,
  plan review, finance review, campaign review, or brand review agents.
- Embedded agent: a conversation agent scoped to a selected graph item, such as
  a task, requirement, design asset, review finding, PR comment, check, or
  evidence item.
- Run: a handoff or execution attempt, whether performed by a human, local CLI,
  external agent, internal agent, or integration.
- Autonomy policy: allowed actions, forbidden actions, approval requirements,
  confidence thresholds, and escalation rules for a run or work packet.
- Autonomy envelope: the approved boundary for an agent, workflow, or work
  packet, including allowed scopes, tools, classifications, action types,
  runtime or budget limits, data volume limits, approval gates, and whether
  execution is read-only, proposal-only, write-capable, or
  external-write-capable.
- Conversation: a contextual interaction with a human or agent that can attach
  to any graph node, not just to a top-level project.
- Principal: an actor that can be authorized, such as a human user, agent,
  service account, integration installation, webhook source, or system process.
- Capability: a named permission to perform an action or use a tool, such as
  `run_agent`, `approve_agent_run`, `modify_work_packet`,
  `use_github_write_token`, `post_external_comment`, `waive_check`, or
  `view_sensitive_artifact`.
- Grant: an explicit permission exception scoped to a principal, resource,
  capability, time window, reason, or review requirement.
- Policy: a versioned rule set that interprets authorization facts for a
  request. A policy is not a single grant or role assignment; it is the logic
  that decides whether those facts allow, deny, redact, escalate, or require
  approval.
- Policy bundle: an immutable, digestable collection of applicable policy
  versions used to evaluate a sensitive authorization decision.
- Custom role: an organization-defined scoped capability bundle, often mapped
  from external IdP groups or SCIM groups, that uses the same capability,
  scope, classification, approval, and audit model as system roles.
- External identity link: a typed relationship between an Office Graph
  principal and an identity provider user, group, claim, or SCIM resource,
  including provider, external identifier, lifecycle state, mapping status, and
  sync provenance.
- Operation or command correlation: a shared traceable record for a meaningful
  attempted action. Revisions, audit records, run events, approvals, domain
  events, and external sync events may reference it without duplicating one
  another's payloads.
- Context expansion request: a request by an agent or workflow to access
  additional scopes beyond the current authorized context, with target scopes,
  reason, requested capabilities, classifications, and decision outcome.
- Approval gate: a governed check requiring eligible human approval, such as a
  team lead, manager, code owner, security reviewer, finance approver, incident
  commander, or release owner. Approval gates can include separation-of-duties
  rules.
- SecretStore: a domain boundary for storing, retrieving, rotating, revoking,
  and auditing secret values without binding product domains to a specific
  cloud or vault provider.
- Policy context: the facts used to evaluate authorization, including actor,
  action, resource, tenant, workspace, project, graph, team membership,
  resource classification, agent run, work packet, autonomy policy, tool scope,
  integration source, request source, and risk level.
- Authorization decision: a durable decision or denial about whether a
  principal may perform an action on a resource under a specific policy
  context. Policy-sensitive decisions should be auditable.

## Product Principles

- The graph is the source of truth.
- AI proposes changes; humans and validated domain logic decide what becomes
  true.
- Treat planning, execution, and validation as connected graph data.
- Preserve provenance for agent and human changes.
- Prefer explicit requirements, decisions, and evidence over implicit chat
  history.
- Make graph items addressable so a user can discuss a selected section, node,
  task, requirement, run, review, or failure with an embedded agent.
- Keep agent execution bounded by clear context packages, autonomy policies,
  permissions, and review gates.
- Make the internal agent runtime graph-aware from the beginning: agents should
  use Office Graph context, write durable evidence and findings, and operate
  under explicit permissions rather than using external PR comments or chat
  threads as the long-term data store.
- Treat integrations as bridges, not the moat. The long-term product advantage
  should come from native graph workflows that are better than the integrated
  tools can build alone because they operate across departments, systems,
  history, agents, permissions, and verification evidence.
- Authorize humans, agents, integrations, and service accounts through the same
  policy boundary. An agent may receive less authority than its delegating user,
  and tool use must be separately authorized from graph read/write access.
- Do not let graph links become accidental access grants. Every graph
  projection, traversal, embedded conversation, agent context package, and API
  response must be filtered through authorization.
- Let smaller models produce structured outputs for supervising agents rather
  than granting every model direct tool access.
- Track proof, not just status.
- Keep the ontology department-agnostic. Engineering examples are useful, but
  concepts such as signals, decisions, requirements, reviews, checks, evidence,
  runs, and agents must work across departments.
- Design enterprise controls, auditability, tenancy, and permission boundaries
  into the core model.
- Preserve clean architecture boundaries. Domains should communicate through
  declared actions, policies, events, and query interfaces rather than reaching
  across schemas or modules ad hoc.
- Design extraction candidates with minimal Office Graph coupling. A reusable
  library should not depend on product-specific graph concepts unless that
  dependency is the point of the library.

## OpenSpec Organization

- Keep this file for durable project context and vocabulary.
- Use `openspec/project-plan.md` for pre-feature discovery, open questions,
  architectural discussion tracks, and sequencing.
- Use `openspec/changes/<change-id>/` for concrete proposed product or
  behavior changes.
- Use `openspec/specs/<capability>/spec.md` for accepted, durable capability
  requirements after decisions have been made.
- Do not turn every brainstorm into a spec. Promote only stable decisions and
  requirements into OpenSpec specs.
- Keep OpenSpec-specific concepts out of the Office Graph product model unless
  a future integration or dogfooding feature explicitly requires them.
