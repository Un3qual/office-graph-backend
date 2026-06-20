# Office Graph Requirements Discovery Plan

Status: discovery
Date: 2026-06-16

This file is a planning map, not an approved product spec. Its job is to keep
the early product, architecture, and OpenSpec questions organized until they are
decided and promoted into formal OpenSpec changes or specs.

## Source Material

- `chatgpt-reference-thread.md`: prior raw brainstorming.
- `chatgpt-generated-prd.md`: generated backend PRD reference.
- User notes from this thread about micro-approval, structured outputs,
  generative UI, clickable plan sections, validation artifacts, nested agents,
  execution packages, review agents, and integration packages.

The generated PRD is useful but not final. Treat its concrete choices as
candidate design material until explicitly accepted.

## Current Synthesis

Office Graph is best framed as a company-wide, agent-native work graph, not as
an AI todo tracker and not as a software-engineering-only tool. It should help
whole organizations convert messy signals into structured, permissioned,
verifiable work across departments such as engineering, design, marketing,
social media, finance, operations, and leadership.

Software engineering remains the best early proving workflow because it has
high-signal examples: PR review comments, code review bots, commits, CI,
Sentry, specs, tests, and concrete verification evidence. That workflow should
be used to sharpen the first user stories and architecture, but the core graph,
agent runtime, APIs, and permissions must stay department-agnostic.

The current core loop:

```text
messy signal from any department
  -> structured work graph
  -> blocking questions
  -> recorded decisions
  -> work packet or execution package
  -> human, internal-agent, external-agent, or integration run
  -> evidence / review / monitoring
  -> verified completion
  -> reusable organizational context
```

The first product should be narrow enough to build and demo with real workflows,
but the target demographic is entire companies. The early wedge should be a
department-neutral foundation with one or two high-fidelity workflows, likely
starting with software because that is where the project can be dogfooded most
accurately.

The locked MVP direction merges the strongest parts of the candidate shapes:
Option A provides the product wedge, Option C provides the core engine, and
Option B provides the expansion grammar. In product terms, Office Graph is an
agent-governed company work graph. The internal agent runtime is first-class
infrastructure for that graph, while department packs and templates remain an
expansion pattern rather than the first product surface.

## Locked Decisions

- Target demographic: entire companies, not only software engineering
  departments.
- Software workflows are early examples and dogfooding paths, not the whole
  product identity.
- Frontend will be React from day one, but frontend implementation is not
  starting yet.
- Phoenix LiveView is forbidden for the product UI.
- Both GraphQL and JSON API are required.
- Office Graph will have an internal agent runtime for automatic agents and
  node-scoped agent conversations.
- The MVP direction is an agent-governed company work graph with a software
  review/fix/verification proving workflow. The internal agent runtime,
  permissions, runs, proposed changes, and review governance are core
  infrastructure from the beginning, while reusable department packs are a
  later expansion pattern.
- Authorization will use a hybrid enterprise model: RBAC for coarse roles,
  ABAC for contextual rules, relationship-based checks for graph/work
  relationships, capability permissions for tools and agents, and explicit
  grants for exceptions.
- Default visibility is workspace scoped, with initiative/project as the
  normal work-container scope. Graph links do not automatically grant access to
  connected records; cross-boundary projections must be redacted, summarized,
  hidden, or explicitly granted by policy.
- Agent effective permissions are the intersection of delegator/user
  permissions, agent capabilities, work packet autonomy policy, tool or
  integration scope, and organization policy.
- Authorization should be its own bounded context and future extraction
  candidate. Permission data should be relational and typed rather than stored
  in JSON claims or generic metadata blobs.
- Linear does not need to be considered for the first planning slice.
- OpenSpec is the workflow for building Office Graph, not a concept that
  Office Graph product features depend on.
- Retire GraphPatch as product language. Keep the safety pattern as structured
  proposed graph changes applied through validated domain actions.
- Backend extensibility is a first-order requirement. The architecture should
  support long-term goals without large rewrites or tacked-on feature seams.
- Base database schemas should be provider-neutral and relational wherever a
  concept is shared across systems. For example, `pull_requests` should cover
  multiple PR providers, with `github_pull_requests` or `gitlab_pull_requests`
  added only when source-specific data or behavior truly requires them.
- Avoid JSON/JSONB columns for core domain data wherever possible. Prefer typed
  columns, join tables, lookup tables, and extension tables.
- Edit/revision history and soft deletion are required from the beginning, but
  should not be implemented as one giant JSON-backed versions table.
- Code organization must assume a very large backend: modular monolith,
  Boundary library, DDD-style bounded contexts, explicit public interfaces, and
  dependency rules from day one.
- Some domains should be designed for possible extraction into reusable
  libraries for future projects, including authentication/identity,
  authorization, the agent runtime, integration primitives, and revision/audit
  primitives. Avoid premature package splitting, but keep boundaries clean
  enough that extraction stays practical.

## Current Working Assumptions

Stable enough to guide discussion:

- First buyer hypothesis: company leadership, operations leadership,
  AI/platform leadership, or department leaders who need governed
  human-agent work across teams.
- First daily users may include tech leads, design leads, marketing leads,
  social/media managers, finance operators, and AI operations owners.
- First workflow should be one concrete departmental loop, likely software
  review/fix/verification because it is easiest to model precisely now.
- MVP should integrate with existing systems before trying to replace them.
- The graph should exist from the beginning, but the UI should start with
  practical projections such as inboxes, queues, packets, and verification
  views rather than a full arbitrary graph editor.
- Agents must not directly mutate durable graph state without passing through
  validated domain actions or structured proposed graph changes.
- Verification should be evidence-based: a task is not done merely because an
  agent says it is done.

Not yet locked:

- Whether CLI task bundles are part of MVP or immediate follow-up.
- Whether AI-generated low-risk patches can auto-apply.
- Exact Ash resource shape for generic nodes versus typed resources.
- How much code-editing capability the internal agent runtime owns in the first
  software workflow versus delegating to external tools.
- Whether the first non-engineering workflow should be design review, marketing
  campaign review, social content approvals, finance anomaly handling, or
  internal operations.
- Exact revision/history storage pattern per aggregate and per domain.
- Which provider-neutral base tables are needed in the first schema cut versus
  delayed until an integration requires them.
- Which domains are library-extraction candidates versus Office Graph-specific
  product domains.

## Reference Workflow: Software Review/Fix Loop

This is not the whole product, but it is a concrete workflow that can pressure
test the graph, runtime, integrations, and verification model.

Initial version:

1. A feature, bug fix, or task is represented in Office Graph.
2. A PR is created in GitHub.
3. External GitHub-integrated review bots such as CodeRabbit or Greptile add PR
   comments.
4. Office Graph imports those comments as review signals/findings and links
   them to the task, PR, commits, files, lines, checks, and related decisions.
5. Office Graph runs internal agents to propose or apply fixes under explicit
   permissions.
6. A human reviews and modifies the changes through an Office Graph agent.
7. Office Graph pushes or helps push changes, comments back on the PR, and
   stores the comments, fixes, decisions, runs, and evidence.

Long-term version:

- Office Graph runs native review bots that operate entirely on the graph
  instead of using PR comments as the primary data store.
- Review bots can run at different graph levels. A child spec section may pass
  review on its own, while a parent-level review bot can still catch that two
  accepted child sections do not integrate correctly.
- Review/fix history becomes reusable context. Future Sentry events, CI
  failures, regressions, support escalations, or new feature plans can refer to
  prior commits, review findings, fixes, affected lines, decisions, and project
  notes.

## Positioning Against Existing Tools

Office Graph overlaps with agent frameworks and workflow tools, but the current
direction is not "build LangChain again."

LangChain-like products primarily help developers compose model calls, tools,
retrieval, prompts, chains, and agent execution. Office Graph should instead be
an enterprise system of record and coordination layer for human-agent work:
typed work graph, decisions, questions, evidence, revision history, agent
runtime governance, integrations, audit, and reusable organizational context.

The closer adjacent categories are:

- Agent orchestration platforms: overlap on internal agent execution, tool
  permissions, and runs.
- Workflow/ticketing/project-management tools: overlap on tasks, approvals,
  queues, and status.
- Knowledge graphs and enterprise search: overlap on connected context and
  retrieval.
- Code review/coding-agent products: overlap on the software proving workflow.
- Automation platforms: overlap on triggers, integrations, and actions.

The intended differentiation is that Office Graph treats work itself as a
typed, revisable, auditable graph that agents and humans both operate on. The
agent runtime is part of the product, but it is not the whole product.

The integration strategy should also be defensive. Office Graph should connect
to the software companies already use, but integrations are adoption ramps and
signal sources, not the intended long-term moat. For high-value workflows,
Office Graph should eventually provide native graph-first experiences that are
substantially better than the integrated tools can provide alone because they
combine cross-tool context, department-neutral work history, internal agents,
permissions, revision history, and verification evidence. This reduces the
risk that an integration partner can simply copy one visible feature and make
Office Graph irrelevant inside its own product.

## OpenSpec Strategy

OpenSpec's built-in schema is feature/change oriented: proposal, design, specs,
and tasks. That is useful once a concrete capability is ready to build, but it
does not fully cover early project doctrine. Use the layers this way:

- `openspec/project.md`: durable project context, vocabulary, stack choices,
  constraints, and principles.
- `openspec/project-plan.md`: discovery agenda, open questions, candidate
  directions, and sequencing.
- `openspec/changes/<change-id>/proposal.md`: why a concrete increment should
  exist and what it changes.
- `openspec/changes/<change-id>/design.md`: architecture and tradeoffs for that
  increment.
- `openspec/changes/<change-id>/specs/<capability>/spec.md`: delta
  requirements for that increment.
- `openspec/changes/<change-id>/tasks.md`: implementation checklist after the
  proposal and design are agreed.
- `openspec/specs/<capability>/spec.md`: accepted durable requirements after a
  change is archived or otherwise promoted.

Recommended first formal change after discovery:

- `define-office-graph-foundation`: establish the company-wide product frame,
  first proving workflows, core loop, vocabulary, graph ontology, work packet
  concept, agent runtime posture, proposed graph change safety model,
  evidence-based verification model, enterprise constraints, and backend
  architecture boundaries before application code is generated.

## Candidate MVP Direction And Alternatives

### Locked Recommendation: Agent-Governed Company Work Graph

Build a department-neutral company work graph with a first-class internal
agent runtime and prove it through the software review/fix/verification loop.
This combines the product clarity of Option A with the runtime/governance
substance of Option C. Borrow only the useful part of Option B: design the
ontology so later department packs can add workflows for design, marketing,
social media, finance, operations, and other teams without changing the core
model.

Role of each option:

- Option A is the wedge: concrete value, dogfooding, and a crisp demo.
- Option C is the engine: graph-aware agents, tool permissions, runs,
  proposed changes, automatic reviews, and auditability.
- Option B is the expansion grammar: department-specific workflow packs and
  projections later, not a broad template platform in the first build.

The product identity should remain Office Graph as the system of record and
coordination layer for human-agent work. The agent runtime is what makes the
graph active; it is not the whole product.

### Option A: Company-Wide Work Graph With A Software Proving Workflow

Build the department-agnostic graph, agent runtime, question/decision loop,
work packet model, evidence model, and API foundation, then prove it with a
software workflow that imports GitHub/Sentry/CI/manual signals, runs internal
agents, records review/fix evidence, and verifies outcomes.

Strengths:

- Preserves the enterprise-wide product ambition.
- Lets the project dogfood with workflows the team understands deeply.
- Produces concrete demos: PR review comments -> Office Graph findings -> fix
  run -> human review -> push/comment -> stored evidence and future context.
- Differentiates from coding agents by owning cross-workflow context,
  governance, review, and verification rather than only code generation.
- Leaves room for design, marketing, social media, finance, and operations
  workflows without redesigning the core graph.

Risks:

- Requires discipline so engineering-specific concepts do not leak into the
  core ontology.
- Internal runtime scope can explode if the first software workflow tries to be
  a full coding IDE, CI system, and review platform at once.
- Needs careful proof that Office Graph improves completion outcomes compared
  with baseline agent use.

Recommendation: use this as the first proving workflow and demo path.

### Option B: Department Template Platform

Build around reusable department templates from the beginning: campaign review,
design review, social content approval, finance anomaly handling, operations
handoff, and software review/fix loops all sharing the same graph primitives.

Strengths:

- Directly reinforces the whole-company target.
- Avoids product language that sounds engineering-only.
- Forces a cleaner, more general ontology early.

Risks:

- Too broad for the first build unless each template is very shallow.
- Harder to create a crisp demo with real integrations and evidence.
- More domain research is needed outside software engineering.

Use this as the expansion pattern, not the first deep build.

### Option C: Agent Runtime And Review Governance Platform

Center v1 on the internal agent runtime: automatic agents, tool permissions,
parallel runs, coordinator agents, review gates, findings, proposed changes,
and run provenance across graph items.

Strengths:

- Strong enterprise AI governance story.
- Directly supports nested agents and execution packages.
- Matches the requirement that Office Graph runs its own agents for reviews,
  fixes, conversations, and graph-wide analysis.

Risks:

- Execution without a concrete signal/workflow can become another agent runner.
- More safety and infrastructure burden before value is visible.
- Without a sharp workflow, it may be hard to prove why the graph matters.

Recommendation: build this as core infrastructure from the beginning, but
ground the first implementation in one concrete workflow.

## Discovery Tracks

### 1. Buyer, User, And Wedge

Questions to answer:

- Is the first buyer company leadership, AI/platform leadership, operations,
  engineering leadership, design leadership, marketing leadership, finance
  leadership, or a founder/COO/CTO at AI-forward teams?
- Is the first daily user a department lead, AI agent operator, operations
  owner, tech lead, design lead, marketing lead, social media manager, finance
  operator, or platform engineer?
- Which first departmental workflow proves the general system best: software
  review/fix loops, Sentry/incident triage, design review, campaign planning,
  social approvals, finance anomaly handling, or manual cross-functional
  intake?
- Should the first promise be "time to agent-ready", "agent success uplift",
  "review/fix throughput", "triage time saved", "verified completion",
  "governed delegation", or "reusable organizational context"?
- Which existing product is augmented first: GitHub, Sentry, Jira, Slack,
  Google Drive, Figma, Notion, spreadsheets, social tools, finance systems,
  Cursor/Codex/Claude Code, or email?
- What would make a design partner use this weekly before all integrations are
  polished?

Discussion output:

- One primary buyer.
- One primary daily user.
- One first departmental workflow narrow enough for MVP.
- One flagship success metric.
- Clear non-goals for the first release.

### 2. Signal Intake And Normalization

Questions to answer:

- Does MVP start with manual pasted intake before real webhooks?
- Which real integration comes first: GitHub, Sentry, Slack, Figma, Google
  Drive, spreadsheets, email, or a finance/marketing system?
- What is the canonical shape of an external event?
- Should raw external events be append-only and replayable from day one?
- How should duplicate or out-of-order webhooks be handled?
- What parts of external payloads become artifacts versus signal properties?
- How much source code, stack trace, diff, CI log, document, design, finance,
  campaign, and social content can be stored?
- How are external agent artifacts represented, such as CodeRabbit/Greptile PR
  comments, GitHub review threads, CI annotations, and security scan findings?

Discussion output:

- MVP intake order.
- Canonical external event shape.
- Idempotency and replay rules.
- Artifact extraction rules.

### 3. Work Graph Ontology

Questions to answer:

- Are MVP node types limited to signal, task, question, decision, check,
  artifact, evidence, run, and work packet?
- Are requirement, goal, plan, milestone, risk, feature, and conversation
  deferred or represented as tags/properties initially?
- Which types must be domain-neutral versus domain-specific extensions?
- Are artifacts graph nodes, separate records linked to nodes, or both?
- Are evidence items nodes, artifacts, or typed node-artifact links?
- What edge types are required on day one?
- Which edge types must be acyclic?
- Can edges carry status, confidence, provenance, permissions, or evidence?
- When does a typed concept deserve a dedicated Ash resource rather than a
  generic node type?
- How should domain-specific objects such as PR review comments, design
  annotations, campaign assets, finance exceptions, and social posts attach to
  the shared graph?

Discussion output:

- Minimal node and edge taxonomy.
- MVP versus future type boundary.
- Ash resource split rule.
- Versioning and provenance model.

### 4. Questions, Decisions, And Micro-Approval

Questions to answer:

- What counts as a blocking question versus a note or recommendation?
- Should every answer create a decision node?
- Should questions support multiple-choice options, free-form answers, or both?
- What metadata is mandatory: why it matters, recommended answer, impact of
  each option, source evidence, risk of proceeding, blocked nodes, confidence?
- What exactly is the "Tinder-like" approval flow approving: questions,
  proposed tasks, proposed graph changes, prompt/context choices, work packets,
  review findings, fix proposals, or agent autonomy policies?
- Which micro-approvals can be single gesture and which need full review?
- How does feedback from approvals tune future suggestions?

Discussion output:

- Question schema.
- Decision schema.
- Approval queue semantics.
- Feedback loop rules.

### 5. Proposed Graph Changes And AI Mutation Safety

Questions to answer:

- What operations can a proposed graph change contain in MVP?
- Are agent-generated changes proposed, auto-applied below a risk threshold, or
  always reviewed by a human?
- What validation rules are mandatory before a proposed change can apply?
- Should change application happen through Ash actions, a graph service, raw
  Ecto transactions, or a hybrid?
- How are temp IDs resolved, duplicates detected, and invalid cycles rejected?
- How is confidence represented?
- How are provenance, prompt version, model, source artifacts, agent run, and
  human review captured?

Discussion output:

- Internal proposed-change operation schema.
- Proposed-change lifecycle.
- Validation and authorization rules.
- Transaction and audit model.

### 6. Agent Readiness And Work Packets

Questions to answer:

- What fields are required in every work packet?
- What makes a task ready for agent execution versus investigation-only,
  human-only, or senior-review-needed?
- Should readiness be a numeric score, categorical status, or both?
- Which readiness factors are deterministic and which are AI-derived?
- What execution modes are available: investigate, draft plan, draft PR, work
  locally, create issue, run internal agent, run automatic review, handoff to
  human, or handoff to an external agent/tool?
- How are work packets versioned and invalidated when questions, decisions,
  artifacts, checks, or autonomy policies change?
- What should the Markdown and JSON packet formats guarantee?
- Can an agent-ready block have subtasks, or only steps, constraints, checks,
  and requirements?
- How does a generic work packet adapt to different departments without
  becoming a weak lowest-common-denominator schema?

Discussion output:

- Work packet schema.
- Readiness scoring model.
- Agent-ready block rules.
- Execution mode decision tree.

### 7. Handoff, Runs, And Local Workflow

Questions to answer:

- Is MVP handoff only copy/export, or should it create GitHub issues, PR
  comments, Slack messages, design tasks, document comments, or other external
  artifacts?
- Should a local CLI task bundle be part of MVP or post-MVP?
- What is the minimum useful internal agent run?
- Should runs track human handoffs, external-agent handoffs, local bundles,
  GitHub issue handoffs, PR comment/fix runs, design handoffs, campaign
  handoffs, and finance handoffs uniformly?
- What run events must be durable?
- What run state can remain ephemeral in OTP processes?
- How do humans or external agents submit output: branch, commits, PR URL,
  test results, notes, and new questions?
- For software workflows, does the internal runtime check out repos, make code
  edits, run tests, push branches, and comment on PRs in MVP, or does it first
  produce patches and instructions for human-mediated application?
- What tool permissions and approvals are required before an internal agent can
  modify files, push commits, call external APIs, or post comments?

Discussion output:

- MVP handoff targets.
- Run lifecycle.
- Local bundle decision.
- Output submission contract.

### 8. Internal Agent Runtime

Questions to answer:

- What agent types exist first: conversational node agents, automatic review
  agents, fix agents, coordinator agents, or scheduled monitoring agents?
- What can agents attach to: every graph node, only executable blocks, only
  work packets, only review-ready nodes, or configurable trigger points?
- How do automatic agents run on completion of tasks, work packets, commits,
  reviews, or external events?
- What is the boundary between an internal Office Graph agent and an external
  coding/design/automation tool?
- How are smaller models restricted to structured output while parent agents or
  trusted runtime components hold tool access?
- How are agent prompts, model choices, tool calls, outputs, findings,
  proposed graph changes, and human approvals stored?
- Can agents run at parent graph levels to detect cross-child conflicts, such
  as two spec sections passing review independently but failing integration
  review together?
- How are agent libraries and a future marketplace modeled without making
  untrusted agents unsafe?

Discussion output:

- Runtime scope for MVP.
- Agent attachment and trigger model.
- Tool permission model.
- Conversation-agent model.
- Automatic review/fix agent lifecycle.

### 9. Verification And Evidence

Questions to answer:

- What is the difference between a check and evidence?
- Which checks are required for a task to become verified?
- When does a task enter monitoring instead of verified?
- What counts as Sentry quiet: no events for a time window, issue resolved, or
  event volume below baseline?
- Can humans waive checks, and what permission/reason is required?
- How should failed future runs link back to the original signal, work packet,
  decision, PR, and verification evidence?
- Should verification be per task, per work packet version, per run, or all of
  these?

Discussion output:

- Check/evidence schema.
- Verification state machine.
- Monitoring rules.
- Waiver policy.
- Traceability rules.

### 10. Conversations And Embedded Agents

Questions to answer:

- Can every node host its own conversation, or are conversations global with
  scoped references?
- What context should an embedded agent receive when a user chats from a
  selected signal, question, task, work packet, run, or failed check?
- Can embedded agents directly propose graph changes, or must they route
  through task-specific domain actions?
- What actions should be available through conversational commands rather than
  forms?
- How are agent suggestions represented before acceptance?
- How does the UI reveal agent-made changes without hiding graph operations?

Discussion output:

- Conversation scoping model.
- Embedded-agent context assembly.
- Mutation and approval policy.
- Minimal command/action protocol.

### 11. Review And Prediction Loops

Questions to answer:

- At what graph level do code review, security review, spec review, plan
  review, design review, brand review, campaign review, finance review, and
  operations review agents run?
- Who or what marks a block as review-ready?
- How does "future prediction" work: review the plan, predict implementation
  risks, review the implementation, then update the plan?
- Are review agents advisory, blocking, or configurable per organization?
- How are reviewer comments, resolved threads, outdated comments, and follow-up
  tasks represented in the graph?
- Are review outputs checks, evidence, questions, findings, proposed graph
  changes, or all of these depending on type?
- What is the maturity path from importing external review comments
  (CodeRabbit/Greptile/GitHub comments) to running native Office Graph review
  bots that never need PR comments as the data store?

Discussion output:

- Review trigger model.
- Review artifact schema.
- Feedback loop from implementation back to plans and requirements.
- Native review-bot evolution path.

### 12. Product UI And Projections

Questions to answer:

- What React application architecture is appropriate once frontend work starts?
- Which data belongs on GraphQL versus JSON API?
- Which screens are mandatory for MVP: inbox, question queue, work packet,
  mini graph, node-scoped chat, agent run, verification,
  settings/integrations?
- Which graph projections are useful first: signal flow, blockers, questions,
  board state, evidence chain, dependencies?
- How rich must plan documents be so any section/node/item can start a scoped
  chat?
- Is a full graph canvas intentionally deferred?
- What is the minimum generative UI capability, if any, for MVP?
- How does the UI stay department-neutral while supporting specialized
  projections for engineering, design, marketing, social media, finance, and
  operations?

Discussion output:

- MVP screen list.
- Graph projection list.
- GraphQL/JSON API responsibility split.
- Generative UI scope decision.

### 13. Persistence Model And Schema Extensibility

Questions to answer:

- What provider-neutral base tables are needed first: repositories, branches,
  commits, pull requests, issues, review comments, checks, documents, design
  assets, campaign assets, finance records, or generic external artifacts?
- What rule determines when a concept belongs in a shared base table versus a
  provider-specific extension table?
- How should `pull_requests` model multiple providers without becoming too
  vague: provider, source account, external id, repository, branch refs, state,
  author, reviewer links, timestamps, merge metadata, and sync status?
- What source-specific fields are acceptable as separate nullable columns,
  lookup tables, extension tables, or external references?
- Where, if anywhere, is JSON/JSONB acceptable: raw external payload archives,
  unqueried webhook bodies, model input/output blobs, or not at all for MVP?
- How do we model arbitrary graph extensibility without a large JSON `props`
  column on every node?
- Which tables require tenant, organization, workspace, project, or graph scope
  columns from day one?
- Which indexes are part of the baseline: foreign-key indexes, tenant/status
  composites, partial indexes for `deleted_at is null`, external-id uniqueness,
  and time-range indexes for events/runs?
- Which high-volume tables may need partitioning later: raw events, run events,
  audit logs, revisions, integration sync events, and model/tool-call logs?

Discussion output:

- Provider-neutral schema rules.
- Extension-table decision rule.
- JSON avoidance policy.
- Baseline index strategy.
- Large-table and partitioning candidates.
- MVP inventory of provider-neutral resources, external-reference-only
  records, provider-specific extension tables, and initial Ash resources.

Note: `design-work-graph-core` defines the decision rule for when attached or
imported data deserves a first-class typed resource. The concrete MVP inventory
belongs in `design-persistence-model`.

### 14. Revision History, Audit, And Soft Deletion

Questions to answer:

- What is the difference between audit logs, revision history, domain events,
  run events, and external sync events?
- Which records require reconstructable revision history versus only audit
  entries?
- Should each aggregate own typed revision tables, should each domain own
  revision tables, or should there be a small set of typed cross-domain
  revision tables?
- How do revisions represent changed fields without falling back to opaque JSON
  snapshots?
- How are actor, agent run, integration source, reason, request id, trace id,
  and approval linked to each revision?
- How does soft deletion work: `deleted_at`/`deleted_by`, tombstone records,
  deletion events, restore windows, legal hold, and retention policies?
- Which uniqueness rules must ignore soft-deleted rows through partial indexes,
  and which must stay globally unique forever?
- How do revisions and soft deletion interact with graph edges, evidence,
  external references, and immutable audit records?

Discussion output:

- Revision/history architecture.
- Soft deletion policy.
- Audit versus revision distinction.
- Retention and restore rules.
- Indexing rules for active versus deleted records.

### 15. Code Organization And Domain Boundaries

Questions to answer:

- What are the initial bounded contexts: Accounts, Organizations, Graph,
  WorkItems, Questions, Decisions, AgentRuntime, Runs, Verification,
  Integrations, ExternalArtifacts, Audit, Revisions, API, and Realtime?
- Which contexts are Ash domains, which are plain Elixir services, and which
  are infrastructure adapters?
- What dependency rules should Boundary enforce between domains?
- What public interfaces should each domain expose: Ash actions, commands,
  queries, events, policies, and DTOs?
- How should Phoenix, Absinthe GraphQL, JSON API controllers, background jobs,
  and integration webhooks call into domains without owning business logic?
- What naming and folder conventions keep a large backend navigable?
- How do we keep integration packages from reaching into core internals?
- Which domains should be designed as future standalone libraries, and what
  dependencies would block extraction?
- How should candidate libraries receive product-specific behavior:
  callbacks/behaviours, configuration, explicit adapters, events, or extension
  modules?
- Which pieces must stay Office Graph-specific: work graph semantics, product
  policies, graph projections, and organization-specific workflows?
- What testing strategy matches the boundaries: domain tests, contract tests,
  policy tests, integration adapter tests, database migration tests, and
  end-to-end workflow tests?

Discussion output:

- Bounded context map.
- Boundary dependency rules.
- Domain public API conventions.
- Library extraction candidate list.
- Test layering strategy.
- Integration package dependency contract.

### 16. Backend Architecture

Questions to answer:

- Should the initial Phoenix project be a single app with Ash domains, an
  umbrella, or a modular monolith that can later split?
- How should GraphQL and JSON API be layered over shared Ash actions and domain
  services?
- What are the first Ash domains: Accounts, Organizations, Graph,
  ProposedChanges, Ingestion, AgentRuntime, WorkPackets, Questions, Runs,
  Verification, Integrations, Audit, and Realtime?
- Should the graph start as generic `nodes` and `edges` with typed relational
  support tables, typed Ash resources over generic nodes, or extension tables
  per type?
- Which operations must use Ash actions, and which may use direct Ecto/SQL?
- Is append-only audit enough, or is full event sourcing needed?
- Should Oban be accepted as the durable job engine?
- Which realtime layer is canonical: Absinthe subscriptions, Phoenix Channels,
  or both?
- What search/retrieval is required: deterministic context extraction,
  Postgres full text, pgvector, external search, or delayed?
- What isolation is required for internal agent runtime execution, tool calls,
  secrets, repo checkouts, filesystem access, and external API calls?

Discussion output:

- Backend module/domain map.
- Persistence strategy.
- Ash/Ecto boundary.
- Async execution and realtime strategy.
- Retrieval strategy.

### 17. Integration Architecture

Questions to answer:

- How should integration packages register capabilities, resources, actions,
  webhook handlers, and handoff targets?
- Which integrations are core-app modules for MVP and which become Hex
  packages later?
- What is the common adapter contract for GitHub, Sentry, Jira, Slack, CI
  providers, design tools, document stores, marketing tools, social platforms,
  finance systems, email, spreadsheets, and local CLI?
- How are integration credentials encrypted, scoped, rotated, and audited?
- How are rate limits, retries, replay, and partial outages represented?
- Which integration data is stored raw, normalized, summarized, or referenced
  externally?
- What is the integration maturity ladder from imported external signals, to
  assisted actions, to bidirectional sync, to native Office Graph workflows?

Discussion output:

- Integration adapter contract.
- MVP integration order.
- Credential and webhook security model.
- Package boundary rules.
- Integration maturity ladder.

### 18. Enterprise Governance

Locked authorization direction:

- Use a hybrid authorization model rather than plain roles-only RBAC.
- Represent users, agents, service accounts, integrations, webhook sources, and
  system jobs as principals that go through the same authorization boundary.
- Use coarse roles for administration and default access, contextual policy for
  risk/classification/source/status rules, relationship checks for graph and
  team ownership, capabilities for tool and agent permissions, and explicit
  grants for exceptional collaboration.
- Keep default visibility scoped to workspaces and initiatives/projects. Graph
  edges provide context and traceability, but do not expand access on their
  own.
- Treat `project` as a customer-facing alias for an initiative or bounded work
  container. Teams, components, repositories, services, departments, and code
  areas are related scopes/resources, not projects by default.
- Prefer conventional enterprise vocabulary in user-facing setup and
  administration surfaces. Richer backend-only terms should be used only for
  new concepts or concepts that do not map cleanly to conventional words.
- Treat departments, org units, teams, and groups as familiar organization
  scopes and relationships that can be imported from SCIM/IdP data or
  configured locally. Workspace templates can provide department-specific setup,
  but templates are not authorization sources by themselves.
- Let restricted graph links appear only as policy-approved redacted summaries,
  hidden nodes, or placeholders.
- Keep `graph` as a projection over scoped graph items for the first schema
  cut, not as a durable tenant or access-granting scope.
- Calculate agent effective permissions as:

```text
delegator/user permission
  intersect agent capability
  intersect work packet autonomy policy
  intersect tool or integration scope
  intersect organization policy
```

- Keep authorization as a bounded context that can later be extracted into a
  reusable library. Ash/domain policies should own product authorization
  semantics; Postgres row-level security is a possible defense-in-depth layer,
  not the initial policy engine.
- MVP architecture should include a custom-role data model, external group
  mapping, SCIM-compatible provisioning, and SSO identity mapping. MVP should
  include basic custom-role frontend UI plus backend endpoints for custom
  roles, external group mappings, and scoped assignments; a polished
  role-builder can come later.
- Tree-shaped permissions should use typed hierarchical scopes with explicit
  descendant inheritance rather than wildcard permission strings.
- Authorization policies are versioned rule sets that interpret authorization
  facts for a given actor, action, resource, scope, classification, tool,
  integration, or run context. Sensitive decision records should reference
  immutable policy bundle versions and relevant fact versions.
- Durable read audit should apply by default to audit logs, secrets and
  credential metadata, sensitive artifacts, agent prompts/context, exports,
  legal-hold records, and cross-scope summaries.
- Audit logs and revision history should share operation/correlation records
  when they refer to the same command, but should not duplicate each other's
  payloads.
- Secret values should sit behind a `SecretStore` boundary. The SaaS default
  can use Office Graph-managed secret infrastructure, while the domain keeps a
  path to customer-managed secret stores through narrow delegated access.
- Cross-scope agent runs should request context expansion explicitly and run
  inside approved autonomy envelopes. Low-risk repeated actions can auto-run
  where policy allows; sensitive context, credentials, external writes, exports,
  destructive actions, broad data sweeps, or cross-organization access require
  explicit policy support or approval.
- Human approvals should be modeled as approval gates/checks with evidence,
  authorization, audit, and separation-of-duties rules. Eligible approvers
  should resolve from the customer's existing company structure where possible:
  SCIM/IdP groups, departments, org units, manager relationships, owners,
  custom roles, data owners, code owners, finance/legal/security roles, and
  explicit grants.
- Local SSO/SCIM development should not require paid hosted IdPs. Use
  authentik as the primary local OIDC/SAML/SCIM fixture, optional Keycloak for
  OIDC/SAML compatibility, and a repo-owned fake SCIM client for deterministic
  contract tests.

Questions to answer:

- Which resource classifications are needed first: public-to-org, workspace,
  initiative/project, team-only, restricted, secret, source-code,
  finance-sensitive, legal-sensitive, customer-sensitive, or
  security-sensitive?
- What data retention, export, deletion, and legal hold requirements matter?
- What AI data controls are required: source-code redaction, prompt storage
  settings, provider allowlists, no-training guarantees, and secret detection?
- Which enterprise integrations are table stakes later: SSO, SCIM, GitHub,
  GitLab, Slack, Teams, Jira, Linear, Confluence, Google Drive, Notion, or
  SIEM?

Discussion output:

- Tenant and authorization model.
- Audit and compliance requirements.
- AI data-control requirements.
- Enterprise integration priority list.

### 19. OpenSpec Bootstrap

Questions to answer:

- Which concepts from this file are stable enough to move into formal specs?
- Should the first change be design-only or include Phoenix/Ash scaffolding?
- Should initial specs be capability-oriented around graph, ingestion,
  proposed graph changes, agent runtime, work packets, verification, and
  governance?
- What naming convention should be used for capabilities and changes?
- What validation commands should every change run before it is accepted?
- How should the generated PRD be referenced without becoming authoritative?
- How do we keep OpenSpec as the project workflow without accidentally making
  OpenSpec a required Office Graph product concept?

Discussion output:

- First capability map.
- First OpenSpec change proposal.
- Validation checklist.
- Research reference policy.

## Historical Proposed First Formal OpenSpec Changes

This was the first formal change order proposed during discovery. It remains
useful history, but the plan-review remediation lane below supersedes it for
current execution order because governance, identity, authorization,
authentication, ingestion, proposed changes, and code organization decisions
now block safe backend code generation.

1. `define-office-graph-foundation`
   - Establish the agent-governed company work graph direction, company-wide
     product frame, software proving workflow, internal runtime posture,
     department-pack expansion grammar, success metrics, vocabulary, core loop,
     non-goals, and accepted planning assumptions.
2. `design-work-graph-core`
   - Define nodes, edges, artifacts, provenance, versioning, statuses, graph
     projections, department-neutral types, domain extensions, and Ash resource
     boundaries.
3. `design-persistence-model`
   - Define provider-neutral relational base tables, extension-table rules,
     JSON avoidance policy, external references, indexing, large-table
     candidates, and schema evolution rules.
4. `design-revision-audit-soft-delete`
   - Define typed revision history, audit logs, domain/run/sync event
     boundaries, soft deletion, restore, retention, and legal hold posture.
5. `design-code-organization-and-boundaries`
   - Define bounded contexts, Boundary rules, DDD conventions, public domain
     interfaces, candidate library extraction boundaries, testing layers, and
     integration package boundaries.
6. `design-ingestion-and-integrations`
   - Define external events, normalization, replay, idempotency, first
     integration scope, adapter contracts, and the maturity ladder from
     imported signals to native Office Graph workflows.
7. `design-agent-runtime`
   - Define internal agent types, node-scoped conversations, automatic review
     agents, tool permissions, run isolation, structured model outputs,
     marketplace posture, and agent provenance.
8. `design-proposed-graph-changes`
   - Define AI/agent output proposals, internal change operations, validation,
     authorization, review, audit, and application semantics.
9. `design-work-packets-and-readiness`
   - Define question/decision flow, readiness scoring, work packet schema,
     autonomy policy, and handoff modes.
10. `design-runs-and-verification`
   - Define runs, run events, checks, evidence, monitoring, verification,
     waivers, and traceability.
11. `design-api-realtime-and-ui-projections`
   - Decide GraphQL/JSON API, React app, Channels/Subscriptions boundaries, and
     the first product screens/projections.
12. `design-enterprise-governance`
   - Define tenancy, authorization, audit, credential security, AI data
     controls, and enterprise integration posture.

These should stay design-heavy until the first MVP cut is chosen. Avoid
generating Phoenix/Ash code before these boundaries are stable enough to avoid
rewrites.

## Plan Review Remediation

Claude's 2026-06-20 plan review and the follow-up Codex review are accepted as
remediation input for the OpenSpec plan. They are not durable product
requirements by themselves; product requirements become durable only when they
are captured in `openspec/project.md`, a formal OpenSpec change, or an archived
spec.

Backend code generation must not start until these cross-change blockers are
resolved:

- identity and authorization schema inventory
- authentication mechanics
- canonical spec ownership and promotion policy
- first executable walking skeleton
- ingestion semantics
- proposed graph change semantics
- code organization and Boundary decisions

Ownership note: `design-identity-and-authorization-schema` owns durable
principal, external identity, authorization, scope, policy fact, sensitivity,
and credential metadata facts. `design-identity-and-authentication` owns how
principals authenticate, receive sessions or runtime credentials, reconcile
external identities, and bootstrap the first organization/owner.

The `design-persistence-model` statement that no migration-blocking persistence
questions remain is superseded by this cross-change readiness gate. Persistence
may have no remaining persistence-only blockers while first migration readiness
is still blocked by identity, authorization, ingestion, proposed-change,
walking-skeleton, or code-organization decisions.

The first backend target is a narrow walking skeleton, not a maximal first
schema. The first executable slice should prove the core loop:

```text
manual intake signal
  -> task
  -> review finding
  -> required verification check
  -> evidence item
  -> verified completion
```

Current remediation dependency order:

```text
define-office-graph-foundation
  -> design-enterprise-governance
  -> design-identity-and-authorization-schema
  -> design-identity-and-authentication
  -> design-work-graph-core
  -> design-persistence-model
  -> design-revision-audit-soft-delete
  -> design-code-organization-and-boundaries
  -> design-ingestion-and-integrations
  -> design-proposed-graph-changes
  -> design-work-packets-and-readiness
  -> design-runs-and-verification
  -> design-agent-runtime
  -> design-api-realtime-and-ui-projections
  -> first-backend-walking-skeleton
```

This order intentionally moves governance and identity before storage and code
generation because Ash policies, graph projections, audit decisions, runtime
authority checks, integration credentials, and agent behavior all depend on
those facts.

### Canonical Concept Ownership

These active changes may reference each other, but each shared concept should
have one canonical owner before promotion into durable specs:

| Concept | Canonical owner | Referencing changes |
| --- | --- | --- |
| Principal model | `design-identity-and-authorization-schema` plus `design-enterprise-governance/specs/authorization-governance` | foundation, code organization, authentication |
| Authentication mechanics | `design-identity-and-authentication` | governance, code organization |
| Scope hierarchy | `design-identity-and-authorization-schema/specs/scope-hierarchy-storage` | governance, persistence |
| Audit record shape | `design-revision-audit-soft-delete/specs/audit-record-boundaries` | governance, code organization |
| Operation correlation | `design-revision-audit-soft-delete/specs/operation-correlation` | persistence, governance, code organization |
| Agent effective permission formula | `design-enterprise-governance/specs/authorization-governance` | foundation, agent runtime, work packets |
| Edges do not grant access | `design-work-graph-core/specs/graph-relationships` plus `design-enterprise-governance/specs/tenancy` | persistence, projections |
| JSON storage policy | `design-persistence-model/specs/json-storage-policy` | revision/audit, integrations |
| Check/evidence/verification vocabulary | `design-runs-and-verification` when created | foundation, governance, persistence |

`define-office-graph-foundation` is durable product framing. It should not be
promoted wholesale into duplicate canonical authorization, persistence,
work-graph, or backend-architecture specs when more granular changes own the
actual durable requirements.

## Architecture Notes To Resolve Before Code

- Prefer a modular monolith with clear Ash domains first unless there is a
  concrete reason for an umbrella.
- Design selected domains as library-ready components inside the modular
  monolith. Extraction should be an architectural option, not an initial
  packaging burden.
- Postgres should be the durable source of truth for graph state, raw external
  events, audit, artifacts, runs, work packets, and integration state.
- Keep graph storage boring until a query requirement proves otherwise:
  indexed node/edge tables, typed resources/actions, relational support tables,
  and recursive CTEs when needed.
- Avoid generic JSON property bags for core graph extensibility. Prefer typed
  node classes, typed edge classes, external reference tables, join tables,
  extension tables, and explicit migrations.
- Ash is likely valuable as the domain/action/policy layer, but it should not
  replace explicit thinking about the graph model.
- Raw SQL/Ecto can be appropriate for graph traversal, replay, analytics, and
  performance-sensitive ingestion.
- Treat audit/provenance as product data, not only observability.
- Treat revision history as product data, distinct from audit logs and distinct
  from raw external event archives.
- Treat verification as evidence, not a status toggle.
- Do not let AI pipeline code write directly to truth tables.
- Do not let generated UI bypass declared graph actions.
- Do not let low-trust agents receive broad tool access just because they are
  part of a larger run.
- Build the internal agent runtime as a core capability, but scope the first
  runtime carefully around graph-aware conversations, automatic reviews,
  proposed changes, and approved tool actions.
- Keep authentication/identity, authorization, integration primitives,
  revision/audit primitives, and the agent runtime decoupled from
  Office Graph-specific product semantics where practical.
- Do not try to replace every external coding/design/automation environment in
  the first version. Integrate with them, store their artifacts, and graduate
  workflows into native Office Graph agents where the graph context creates
  clear leverage.

## Candidate MVP Product Surface

Likely MVP screens:

- Inbox: incoming manual/GitHub/Sentry/CI signals with suggested
  classification and readiness. Later inboxes should cover design, marketing,
  social, finance, operations, and document signals with the same primitives.
- Question Queue: blocking questions with recommended answers, options,
  rationale, and affected work.
- Work Packet View: objective, context, artifacts, decisions, constraints,
  autonomy policy, success criteria, verification steps, and handoff options.
- Mini Graph View: focused projection around a selected node rather than a full
  canvas.
- Node Chat: embedded agent conversations attached to selected graph items.
- Agent Run View: internal-agent, human, external-agent, and integration run
  state with tool calls, outputs, proposed changes, and approvals.
- Verification View: checks, evidence, monitoring state, PR/CI/Sentry status,
  review state, and waivers.
- Settings/Integrations: organization, repo/project connections, credentials,
  data controls, and webhook health.

Explicitly defer:

- Full Jira/Linear replacement.
- Full visual graph editor.
- Full IDE replacement or unrestricted coding-agent platform.
- Custom CI runner.
- General-purpose personal todo app.
- Agent marketplace.
- Mobile app.
- Broad enterprise workflow builder.

## Candidate MVP Metrics

Metrics to validate the wedge:

- Agent-ready conversion rate.
- Median time from signal to agent-ready work packet.
- Blocking question resolution rate.
- Work packets generated per department/team per week.
- Human triage time saved.
- Agent/human handoff completion rate.
- PR acceptance, CI pass, and merge rate for packet-backed work.
- Verification completion rate with linked evidence.
- Reuse rate for prior decisions, findings, fixes, evidence, and project notes
  in future agent runs.
- Repeat weekly usage by department leads, operators, tech leads, or senior
  contributors.

The most important metric to prove is whether work compiled through Office
Graph produces better completion outcomes than baseline agent use without it,
within at least one concrete department workflow.

## Suggested Discussion Order

1. Confirm the first proving workflow while preserving the company-wide target.
2. Pick the first user, buyer, and success metric.
3. Decide the first intake path: manual, GitHub, Sentry, CI, Slack, Figma,
   documents, spreadsheets, email, or another department system.
4. Define the minimal graph ontology and which future node types are deferred.
5. Define provider-neutral persistence rules, extension-table rules, and JSON
   avoidance policy.
6. Define revision history, audit, and soft deletion architecture.
7. Define code organization, bounded contexts, and Boundary dependency rules.
8. Identify future library extraction candidates and their dependency rules.
9. Define question, decision, proposed graph change, and micro-approval
   semantics.
10. Define internal agent runtime scope, agent attachment rules, and tool
   permissions.
11. Define work packet, readiness, and autonomy policy semantics.
12. Define handoff/run scope and whether CLI bundles are MVP.
13. Define verification/check/evidence semantics.
14. Decide GraphQL/JSON API/realtime posture.
15. Decide Ash/Ecto/Postgres boundaries.
16. Decide integration package boundaries and security posture.
17. Convert accepted decisions into the first formal OpenSpec change.

## First Question To Answer

Which concrete proving workflow should define the first formal OpenSpec change,
while keeping the product framed for whole-company use?

Current recommendation: start with the software review/fix/verification loop
because it is precise enough to dogfood, but write the foundation spec so the
same graph, agent runtime, and evidence model apply to design, marketing,
social media, finance, operations, and other departments.
