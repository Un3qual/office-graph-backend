## Context

Office Graph is an enterprise, company-wide work graph. Governance is not a
thin admin layer around the product; it shapes how graph items are scoped,
which context an agent can see, which tools an agent can use, how external
writes are approved, and which records must be auditable later.

The accepted foundation locks several constraints:

- Authorization uses a hybrid model: RBAC, ABAC, relationship checks,
  capabilities, and explicit grants.
- Humans, agents, integrations, service accounts, webhook sources, and system
  jobs are all principals.
- Graph edges never grant access by themselves.
- Agent effective permissions are the intersection of delegator permission,
  agent capability, work packet autonomy policy, tool or integration scope,
  and organization policy.
- Permission data should be relational and typed.
- Ash/domain policies own product authorization semantics. Postgres row-level
  security can be added later as defense-in-depth, but is not the v1 policy
  engine.

## Goals / Non-Goals

**Goals:**

- Establish the first tenant and scope model that later graph and persistence
  designs can use consistently.
- Define the first role, capability, grant, classification, and policy-context
  vocabulary.
- Define the product meaning of project/initiative so team, component, repo,
  and task scopes do not get overloaded.
- Include custom roles, external group mapping, and SCIM-compatible
  provisioning in the MVP data model even if the first admin UI is minimal.
- Decide which authorization decisions and sensitive actions require durable
  audit records.
- Define how agent permissions are computed, explained, and recorded.
- Define how automatic and delegated agent runs can request cross-scope
  context and tool authority without bypassing team ownership.
- Define human approval gates, manager/team-lead verification, and
  separation-of-duties requirements.
- Define baseline credential security, webhook-source trust, AI data controls,
  and enterprise integration posture.
- Define local SSO/SCIM testing requirements that do not require paying for
  Entra, Okta, or another hosted IdP during normal development.
- Keep reusable boundaries clean enough that authorization, identity,
  credential, audit, and AI data-control primitives can later be extracted.

**Non-Goals:**

- No Phoenix, Ash, Ecto, migration, GraphQL, JSON API, or React
  implementation.
- No final table list for every governance record.
- No full SIEM, billing, retention, or legal-hold implementation.
- No requirement for a polished custom-role UI in the first build.
- No provider-specific integration design beyond common security posture.
- No claim that governance decisions replace later security review.

## Decisions

### 0. Prefer conventional enterprise vocabulary in user-facing surfaces

Office Graph should feel familiar to IT, security, finance, HR, engineering,
and operations teams during setup and administration. User-facing vocabulary
should use conventional enterprise terms where they fit: organization,
workspace, department, org unit, team, group, role, custom role, permission,
policy, manager, owner, approver, service account, integration, audit log,
access review, retention, and legal hold.

Richer backend-only terms are acceptable when Office Graph has a genuinely new
concept or when no conventional term maps cleanly. For example, `principal`,
`capability`, `scope`, `policy bundle`, `graph projection`, `autonomy
envelope`, and `context expansion request` can exist in the domain model, API,
or engineering docs, but the admin UI should translate them into the closest
enterprise vocabulary where possible.

Alternatives considered:

- **Graph-native vocabulary everywhere:** Precise for the implementation, but
  too much cognitive load for enterprise admins and cross-functional users.
- **Enterprise vocabulary only:** Familiar, but insufficient for agent-native
  concepts that do not yet have standard enterprise terms.

### 1. Use organization as the root tenant

The root tenant is `organization`. Every durable product record that belongs to
customer data must carry an organization scope directly or through a strict
owned parent. Organization is the billing, policy, audit, identity, data
export, and retention root.

Alternatives considered:

- **Account root:** Useful for billing vendors, but too ambiguous for B2B
  product data. Keep account/billing as a later commercial concept.
- **Workspace root:** Good for collaboration, but too small for enterprise
  policies, SSO, audit, and cross-workspace governance.
- **Deployment root:** Useful for dedicated enterprise deployments, but not a
  general product data model.

### 2. Use workspace and initiative/project as default work scopes

Default visibility is workspace scoped, with initiative/project as the normal
work container for planning, execution, review, and verification. A workspace
groups related teams and broad work areas. An initiative is a bounded business
or product outcome that may span teams, components, repositories, tools, and
departments.

`Project` should be treated as the familiar customer-facing alias for
initiative, not as a synonym for team, codebase, component, repo, or task.

Examples:

- `frontend` and `backend` are teams, product areas, components, or code
  areas, not initiatives by default.
- `migrate mobile app from Swift to React Native` is an initiative/project.
- `fix this bug` is normally a signal, issue, task, or incident item, not an
  initiative unless it expands into a larger investigation.
- `add image uploads to private messages` is likely an initiative/project
  because it can include requirements, design discussion, backend work,
  frontend work, security review, rollout, and verification.

Inside an initiative, workstreams can represent team- or domain-specific
execution lanes such as backend implementation, frontend implementation,
design review, security review, rollout, or finance approval. Teams,
components, repositories, services, departments, and external systems are
related resources and scopes that attach to the graph; they are not forced into
the project concept.

Graph items should usually carry:

- `organization_id`: mandatory tenant root
- `workspace_id`: common visibility boundary
- `initiative_id` or `project_id`: optional but common work-container boundary
- more specific scope columns when needed, such as team, component,
  repository, service, integration, external source, graph, or artifact scope

Graphs are product views and data structures inside the tenant hierarchy, not
independent tenants. A graph may span initiatives, workstreams, teams,
components, and repositories only when policy allows every included node, edge,
artifact, revision, and summary to be filtered.

Alternatives considered:

- **Team/component as project:** Familiar to software teams, but it breaks
  down for cross-functional work and non-engineering departments.
- **Task as project:** Makes large initiatives hard to reason about and turns
  every bug into a heavyweight container.
- **Graph as tenant:** Flexible, but risks making graph edges accidental
  access boundaries.
- **Team as primary scope:** Important for relationship checks, but teams cut
  across workspaces and projects.

### 3. Start with row-based tenant isolation in a shared database

MVP isolation should be row-based in Postgres with explicit tenant/scope
columns, indexes, and policy checks in the application/domain layer. Dedicated
database, schema-per-tenant, and deploy-per-tenant variants can remain future
enterprise options for customers with strict isolation or residency needs.

Postgres row-level security may be added later for selected tables or tenant
isolation defense-in-depth. It should not be the first policy engine because
Office Graph authorization must account for agents, work packets, integration
scopes, tool permissions, graph redaction, and explainable decision records.

Alternatives considered:

- **Schema per tenant:** Stronger isolation, but complicates migrations,
  analytics, cross-tenant operations, and early product iteration.
- **Database per tenant:** Strongest isolation, but heavy operational cost for
  MVP.
- **RLS-first:** Useful later, but too low-level to express the whole product
  policy model by itself.

### 4. Model every actor as a principal

The authorization boundary sees humans, agents, service accounts,
integrations, webhook sources, system jobs, and external executors as
principals. A principal has a type, lifecycle state, owning organization,
optional delegated actor, and allowed scopes.

Agents and integrations do not inherit broad user authority automatically.
They act as their own principals with constrained delegation and capability
sets.

Alternatives considered:

- **Users plus API keys:** Too weak for agent-native workflows and audit.
- **Separate auth paths for agents/integrations:** Easier short term, but
  would create inconsistent policy and audit semantics.

### 5. Use scoped roles plus MVP custom roles

Initial system roles should be simple and assignable at the appropriate scope:

- `org_owner`: full organization administration and break-glass ownership.
- `org_admin`: organization administration except ownership transfer and
  destructive break-glass operations.
- `workspace_admin`: workspace membership, settings, and policy defaults.
- `project_admin`: project membership, packet/review configuration, and
  project agent settings.
- `member`: normal contributor within assigned scopes.
- `viewer`: read-only access within assigned scopes, subject to
  classification policy.
- `auditor`: audit/compliance visibility without normal write authority.
- `integration_admin`: manages integration installations and credentials
  within allowed scopes.
- `agent_operator`: configures and runs approved agents within allowed scopes.

`billing_admin` is likely needed later but can remain outside the initial
product schema unless billing begins early.

Custom roles should be part of the MVP authorization data model, even if the
first UI is minimal. Enterprise customers will want to map their IdP groups,
SCIM groups, and internal role vocabulary onto Office Graph behavior. The
right compromise is:

- seed the simple system roles above
- model custom roles from day one as scoped capability bundles
- support external group to role/team/grant mapping from day one
- defer the polished custom-role builder UI until the capability vocabulary is
  proven

Custom roles must not become arbitrary JSON policy blobs. They should use the
same relational capability, scope, inheritance, classification, and approval
vocabulary as system roles.

Alternatives considered:

- **Roles only:** Not expressive enough for sensitive artifacts, tool actions,
  waivers, and agents.
- **Capabilities only:** Too hard for enterprise admins to reason about.
- **No custom role model in v1:** Easier to ship, but creates unnecessary
  rewrites when SCIM/SSO group mapping arrives.
- **Full custom-role UI in v1:** Valuable, but not necessary if the schema,
  API, seeds, and tests support custom roles.

### 6. Use named capabilities as the durable permission vocabulary

Roles grant default capability sets. Explicit grants can add narrowly scoped
capabilities. Policies can deny or require approval even when a capability is
present.

Seeded v1 capabilities should include at least:

- `view_graph_item`
- `create_graph_item`
- `modify_graph_item`
- `delete_graph_item`
- `restore_graph_item`
- `manage_members`
- `manage_roles`
- `manage_integrations`
- `manage_credentials`
- `run_agent`
- `approve_agent_run`
- `configure_agent`
- `modify_work_packet`
- `approve_proposed_graph_change`
- `waive_check`
- `view_sensitive_artifact`
- `export_data`
- `use_integration_read`
- `use_integration_write`
- `post_external_comment`
- `push_external_change`
- `manage_retention`
- `manage_legal_hold`
- `view_audit_log`

Capability names are product policy vocabulary, not UI copy. They should be
stable, relationally modeled, documented, and tested.

Capabilities should not rely on wildcard strings such as `frontend.*`.
Wildcard-like behavior should come from typed scope inheritance, not string
matching. For example, a principal may receive `approve_agent_run` on
`team/frontend` with `applies_to_descendants: true`, which applies to
`team/frontend/ios` and `team/frontend/web` according to scope-tree policy.
This keeps policy queryable and auditable while preserving the ergonomics of
tree-shaped permissions.

Alternatives considered:

- **Free-form permission strings only:** Flexible but hard to govern and
  migrate.
- **Enum only:** Simple but too rigid for future library extraction and
  integrations. Prefer seeded relational capabilities with stable identifiers.
- **Wildcard permissions:** Familiar, but too opaque for relational policy,
  audit, scope moves, and cross-scope agent explanations.

### 7. Use hierarchical scopes for inheritance, not graph edges

Office Graph needs hierarchy where organizations already have hierarchy:
departments, org units, teams, subteams, components, services, repositories,
workspaces, and initiatives. Hierarchical scope inheritance should support
cases like:

```text
team/frontend
  -> team/frontend/ios
  -> team/frontend/web
```

An assignment can apply to one scope only or to descendants according to an
explicit inheritance flag. Policy should also support non-tree relationships
through relationship checks, because real organizations are matrices:
initiatives cross teams, services support multiple products, and incidents can
touch several departments.

Graph edges remain context relationships, not permission inheritance. A graph
edge can make a cross-scope relationship visible to policy, but it cannot
grant access by itself.

Departments and teams should be modeled as familiar organization scopes rather
than forcing users to learn a novel graph term. SCIM-provisioned departments,
IdP groups, and local teams can map into Office Graph's typed scopes and
relationships. Workspace templates can still provide department-specific setup
for engineering, design, finance, HR, marketing, social, or operations, but a
template is not the source of authorization by itself.

Alternatives considered:

- **Pure tree authorization:** Too rigid for cross-functional work.
- **Pure graph authorization:** Too easy to create accidental access grants.
- **String-prefix permissions:** Hard to audit and refactor when teams or
  components move.

### 8. Keep explicit grants narrow, reasoned, and expiring when possible

Explicit grants are exceptions, not the primary collaboration model. A grant
should have a principal, resource or scope, capability, reason, creator,
created time, optional expiration, optional approval requirement, and audit
trail.

Grants are useful for cross-project review, temporary incident access,
external auditor visibility, sensitive artifact access, or one-off agent/tool
authority. Grants must not be stored as generic JSON policy blobs.

Alternatives considered:

- **Ad hoc sharing links:** Too weak for enterprise audit.
- **Adding users to every scope:** Creates stale access and hides exceptional
  collaboration.

### 9. Represent resource classification explicitly

Every graph item and external artifact should have an explicit classification
or inherit one from its scope. Classification affects visibility, redaction,
agent context assembly, export, AI provider eligibility, audit requirements,
and external write approvals.

Initial classifications should include:

- `org_internal`
- `workspace_scoped`
- `project_scoped`
- `team_restricted`
- `restricted`
- `secret`
- `source_code`
- `customer_sensitive`
- `finance_sensitive`
- `legal_sensitive`
- `security_sensitive`

These can be modeled as typed labels or classification records. The important
rule is that policy can query them without parsing JSON metadata.

Alternatives considered:

- **Visibility enum only:** Too coarse for AI data controls and compliance.
- **Arbitrary tags:** Useful for search, but not enough for policy.

### 10. Make policy decisions explainable

Authorization checks should return a decision that can explain the allow,
deny, redaction, placeholder, approval requirement, or escalation. For agent
actions, the decision should identify which factors were limiting:

```text
delegator permission
  intersect agent capability
  intersect work packet autonomy policy
  intersect tool or integration scope
  intersect organization policy
  intersect resource classification policy
```

This explanation is product-critical. Users need to understand why an agent
can comment on a PR but cannot push commits, why a linked artifact is
redacted, or why a waiver needs approval.

A policy is the versioned rule set that interprets authorization facts for a
request. It is not a single grant, role assignment, or permission row. Role
assignments, custom role definitions, grants, classifications, group
memberships, ownership links, manager relationships, and agent capabilities
are facts. Policies say what those facts mean for a given actor, action,
resource, scope, classification, tool, and run context.

For a single authorization request, the effective policy is the collection of
applicable rule versions selected from organization policy, workspace or
project policy, classification policy, agent autonomy policy, integration
policy, approval policy, and any relevant inherited scope policy. Sensitive
decision records should store the policy bundle version, digest, component
policy versions, relevant fact references, result, and explanation. They
should not copy a giant policy blob into every decision record.

Alternatives considered:

- **Boolean policy checks only:** Simpler, but inadequate for agent governance
  and enterprise support.
- **Explain only denials:** Allows are also sensitive when agents and external
  writes are involved.

### 11. Store durable authorization decision records for sensitive actions

Not every read needs a durable decision record. Durable records are required
when a policy-sensitive action is allowed, denied, redacted, escalated, or
approval-gated.

Durable decision records are required for:

- agent tool use
- external writes
- credential access or use
- check waivers
- approval gate decisions
- sensitive artifact access
- cross-boundary graph traversal results that expose a placeholder or summary
- data export
- retention or legal-hold changes
- role, grant, membership, and policy changes
- destructive or restore actions

Normal low-risk reads can be operational logs unless policy marks the resource
or customer as requiring durable read audit.

Alternatives considered:

- **Audit every authorization check:** Too expensive and noisy for graph reads
  and context assembly.
- **Audit only successful writes:** Misses denied attempts, redaction, and
  sensitive agent/tool behavior.

### 12. Separate audit, revision, domain events, and run events

Governance uses audit logs for security/compliance evidence. It should not
reuse revision history, domain events, or run events as a substitute.

Audit records should capture principal, delegator when applicable, action,
resource, tenant/scope, decision result, reason, source, request/trace id,
related run, related approval, and policy version when available. They should
be append-only from product code and designed for export.

To avoid duplicating data across revision history and audit logs, write a
shared operation or command correlation record for meaningful product actions.
That record represents the user's, agent's, integration's, or system job's
attempt to do something. It can then be referenced by:

- revision records when product state changed
- audit records when behavior is security/compliance-sensitive
- run events when execution timelines need detail
- domain events when other domains need business notifications
- external sync events when provider replay/debugging needs traceability

Audit records should not copy full before/after state when a revision already
contains the reconstructable state change. Revisions reconstruct product
history. Audit records answer who attempted what, whether policy allowed it,
which authority basis applied, and how to investigate it.

Alternatives considered:

- **One event table for everything:** Easy early, but conflicts with the
  project's typed history and JSON-avoidance direction.
- **Use revisions as audit:** Revisions reconstruct product state; they do not
  answer all security/compliance questions.
- **Duplicate full state in both audit and revision records:** Easier for
  isolated queries, but expensive, inconsistent, and contrary to the typed
  history direction.

### 13. Treat credentials as scoped governance resources

Integration credentials, tool tokens, webhook secrets, signing keys, and model
provider keys are governed resources. They need owners, scopes, classification,
allowed capabilities, rotation state, revocation state, last-used metadata,
audit records, and approval policy for sensitive use.

Secret values should be protected behind a `SecretStore` boundary. Product
tables should store references, fingerprints, version identifiers, ownership,
scope, provider, lifecycle, rotation, revocation, and policy metadata, not
plaintext secrets.

The default SaaS production posture should be Office Graph-managed secret
storage: a customer supplies an integration credential to Office Graph, and
Office Graph stores it in its own controlled secret backend, such as a cloud
secret manager or KMS-backed store, with per-tenant scoping, audit, rotation,
and revocation controls. This is the simplest managed-product path and is
compatible with later compliance work if controls are strong.

The domain model should also preserve a path to customer-managed secrets for
larger enterprises. In that model, the customer keeps selected secret values in
their own AWS, GCP, Azure, Vault, or similar keystore and grants Office Graph a
narrow, auditable way to retrieve or use only the approved secrets. Prefer
workload identity, federated access, external IDs, short-lived credentials, or
provider-native delegated access over a broad long-lived token to a customer's
entire keystore.

Alternatives considered:

- **Store credentials inside integration config:** Too easy to leak or misuse.
- **One global integration token per provider:** Too broad for agent/tool
  governance.
- **Customer-managed secrets only:** Strong customer control, but too much
  setup burden for MVP and early pilots.

### 14. Treat webhook sources as principals

Webhook sources should be explicitly registered and authorized. A webhook
source has provider, installation/source scope, verification method, allowed
event types, replay/idempotency policy, and trust level.

Inbound webhooks create signals or sync events only through integration
adapters and domain actions. They do not bypass tenant, scope, or
classification policy.

Alternatives considered:

- **Provider secret only:** Validates origin but does not model authority.
- **Webhook handlers write directly:** Faster to build, but bypasses policy
  and provenance.

### 15. Include SSO and SCIM compatibility in MVP architecture

SSO and SCIM solve different problems and should not be collapsed:

```text
SSO: authenticates a user logging in now
SCIM: provisions users, groups, and memberships over time
Office Graph: maps external identity data into internal principals, teams,
roles, grants, scopes, and capabilities
```

The MVP should include enough identity architecture for SCIM-compatible
provisioning and SSO mapping from day one. This does not require every vendor
integration to be production-polished immediately, but it does require the data
model, import pipeline, conflict handling, and tests to exist early.

Office Graph should store external identity links with provider, tenant,
external user/group id, external username/email when available, lifecycle
state, last sync, and mapping status. External groups and SSO claims should be
mapped into Office Graph teams, custom roles, explicit grants, and scoped role
assignments. Office Graph should not blindly trust customer role names as
product permissions.

Alternatives considered:

- **SSO only in MVP:** Handles login but misses deprovisioning, group sync, and
  enterprise lifecycle management.
- **SCIM later with no schema preparation:** Creates avoidable rewrites in
  principals, memberships, roles, and audit.
- **Trust external roles directly:** Easier to integrate, but weakens policy
  explainability and makes customer IdP mistakes product-critical.

### 16. Use a local identity lab for SSO and SCIM development

Normal development and CI should not require paid Entra, Okta, or another
hosted enterprise IdP. The project should support a local identity lab:

- self-hosted authentik as the primary local IdP for OIDC, SAML, and SCIM
  end-to-end testing
- Keycloak as an optional SSO-focused fixture for OIDC/SAML compatibility
- a repo-owned fake SCIM client for deterministic contract tests
- optional Okta/Entra compatibility smoke tests for later pilot readiness, not
  as normal dev or CI requirements

The fake SCIM client should exercise user create/update/deactivate, group
create/rename/delete, group membership add/remove, duplicate external IDs,
invalid payloads, pagination/filter expectations where supported, and PATCH
add/remove/replace behavior. Local E2E tests should validate that SSO login
and SCIM provisioning reconcile to the same principal through external identity
links.

Alternatives considered:

- **Depend on hosted vendor trials:** Produces flaky, costly, and account-bound
  development.
- **Only mock SCIM payloads:** Good for unit tests, but insufficient for
  integration behavior.
- **Only use a real local IdP:** Good for E2E, but deterministic edge-case
  testing still needs a controlled fake client.

### 17. Govern cross-scope agent runs through context expansion

Automatic and delegated agent runs often need to cross the scope where the
initial signal appeared. A frontend Sentry crash may require backend, devops,
repository, deployment, feature-flag, support, and prior decision context.
That is normal product behavior, not an exception, but it must be governed.

An agent run should start with an initial authority basis:

- triggering signal or selected graph item
- triggering principal, webhook source, integration, or system policy
- configured agent principal and capability set
- work packet autonomy policy when present
- organization policy and resource classifications

When the agent needs more context, it should issue a context expansion request.
The request identifies the target scopes, reason, requested capabilities,
resources, classifications, and whether the expansion is read-only,
proposal-only, or write-capable. Policy can allow it, deny it, return redacted
context, require approval, or create a temporary explicit grant.

Cross-organization expansion should be rare and separately governed.
Cross-team, cross-component, and cross-repository expansion inside one
organization is a core workflow.

Agents should run inside approved autonomy envelopes so humans approve the
boundary, not every small action. An autonomy envelope defines allowed scopes,
tools, classifications, action types, budgets, runtime limits, data volume
limits, whether the run is read-only, proposal-only, write-capable, or
external-write-capable, and which gates require approval.

Default expansion tiers:

- **Auto:** same scope or directly owned descendant scope, low or normal
  classification, read-only, no secrets, no export, no external write.
- **Auto with durable decision record:** same organization, related workspace
  or initiative, read-only or summary-only, limited data volume, no credential
  access, and a temporary scoped grant when needed.
- **Proposal-only:** the agent may inspect policy-approved context and propose
  changes, but cannot mutate Office Graph or external systems.
- **Approval required:** sensitive classifications, broad cross-workspace
  access, credential use, write-capable expansion, external comments, external
  provider mutations, production-affecting actions, exports, destructive
  actions, or high-risk proposed graph changes.
- **Blocked unless explicitly configured:** cross-organization access, broad
  data sweeps, unknown classification, suspicious repetition, policy
  ambiguity, or requested authority outside the agent's configured purpose.

To avoid approval fatigue, repeated manual approvals should become policy
review signals. For example, if the same backend-log read expansion is
approved many times for the same agent under the same limits, Office Graph
should suggest a narrow auto-approval rule rather than training users to click
approve without reading.

Alternatives considered:

- **Agent inherits broad org access:** Too risky and impossible to explain.
- **Agent stays in the initial scope:** Too weak for real diagnosis and
  cross-functional work.
- **Manual grants before every expansion:** Safe but slow; use policy to
  auto-allow low-risk expansions and approval-gate higher-risk ones.

### 18. Model human approval gates as governed checks

Human approvals should be first-class graph/check records, not side-channel
comments. A developer may approve an agent's proposed PR fix within a PR scope,
while merge to `main` may require a separate team lead, code owner, security
reviewer, incident commander, manager, or release owner approval.

Approval gates should define:

- required capability or role
- required scope relationship
- required approver count
- separation-of-duties rule, such as "author cannot final-approve"
- applicable resource classification
- escalation path
- expiration or reapproval rules when linked work changes
- evidence produced by approval or rejection

Approvals are checks with evidence, and waivers are governed exceptions.
Agent and human approvals should both preserve principal, authority basis,
related run, related proposed graph change, related revisions, reason when
available, and audit trail.

Approval requirements and eligible approvers should derive from the customer's
existing company structure where possible rather than hardcoded Office Graph
special cases. Office Graph should resolve approver candidates from SCIM and
IdP groups, departments, org units, manager relationships, team owners,
workspace/project admins, data owners, integration owners, code owners,
security/compliance/finance/legal roles, custom roles, and explicit grants.

An approval rule should describe the capability, relationship, scope,
classification, approver count, and separation-of-duties requirements. For
example, exporting a finance-sensitive artifact can require one eligible
finance data owner or finance manager who is not the requester, not the agent
delegator, and not the implementer. Office Graph should evaluate that rule
against imported and locally configured company structure.

Alternatives considered:

- **Status flag approval:** Too weak for traceability and enterprise policy.
- **Only provider-native approvals:** Useful integration signal, but Office
  Graph needs graph-native approvals across tools and departments.
- **Manager approval as a role special case:** Too narrow; model approval
  gates so team leads, code owners, security reviewers, finance approvers, and
  managers all use the same primitive.

### 19. Define AI data controls as organization policy

Organizations need policies for model providers, model classes, prompt storage,
model output storage, source-code handling, secret detection, redaction,
retention, and no-training requirements.

Initial posture:

- Store prompt/model provenance and enough input/output metadata for audit and
  replay decisions.
- Allow organization policy to restrict which providers and models may receive
  source code, finance-sensitive, legal-sensitive, customer-sensitive, or
  security-sensitive data.
- Run secret/sensitive-data detection before external model calls where the
  context package may contain credentials, source code, or customer data.
- Support redaction/summarization when full context is not allowed.
- Treat no-training commitments and data-retention terms as provider policy
  metadata.

Alternatives considered:

- **Provider policy in code config only:** Not enough for enterprise
  administration or audit.
- **Never store prompts:** Reduces risk, but weakens provenance and debugging.
  Make storage policy configurable by organization and classification.

### 20. Prioritize enterprise integrations without implementing them here

Governance should reserve space for SSO, SCIM, and SIEM export. MVP
architecture should support SCIM-compatible provisioning and SSO mapping, but
this change does not implement vendor-specific production integrations.

Recommended priority:

1. SSO/OIDC/SAML posture and identity-provider mapping.
2. SCIM provisioning model for users, groups, and deprovisioning.
3. Local identity lab with authentik, optional Keycloak, and fake SCIM client.
4. SIEM/audit export contract.
5. GitHub/GitLab organization installation governance.
6. Slack/Teams notification and approval surfaces.
7. Later knowledge/work systems such as Jira, Confluence, Google Drive,
   Notion, Figma, finance systems, and marketing/social platforms.

Linear remains out of the initial planning slice unless explicitly reintroduced.

Alternatives considered:

- **Implement hosted-vendor SSO first:** Valuable, but premature before the
  domain model has stable tenancy and principal semantics.
- **Ignore SSO/SCIM/SIEM until late:** Risky because early identity and audit
  models could block enterprise adoption later.

## Risks / Trade-offs

- **Broad governance scope can slow product iteration** -> Keep this change
  design-only and use it to constrain schemas, not to implement every control
  immediately.
- **Too many roles and capabilities can confuse admins** -> Seed a small
  default role set, support custom roles in the schema/API, hide raw
  capabilities from most UI, and delay the polished custom-role builder until
  the vocabulary is proven.
- **Backend policy terms can leak into the product UI** -> Prefer conventional
  enterprise vocabulary in setup, admin, and end-user surfaces; keep richer
  terms for new concepts and implementation docs.
- **Initiative/project terminology can confuse software teams** -> Define
  initiative as the actual work container, keep project as a familiar alias,
  and model teams, components, repos, services, and workstreams separately.
- **Row-based isolation may not satisfy every enterprise customer** -> Design
  tenant/scope columns and export boundaries so dedicated deployments or
  stronger isolation remain possible later.
- **Hierarchical scope inheritance can overgrant access** -> Make descendant
  inheritance explicit, keep graph edges out of permission inheritance, and
  audit inherited authority in policy explanations.
- **SCIM/SSO support can pull the MVP into vendor-specific work** -> Use a
  SCIM-compatible internal model, local identity lab, and fake SCIM client
  first; keep hosted vendor tests optional.
- **Cross-scope agent runs can become hidden broad access** -> Require context
  expansion requests, temporary grants when needed, explanations, and durable
  decision records for sensitive expansions.
- **Durable decision records can become high volume** -> Audit sensitive
  decisions durably, use operational logs for low-risk reads, and identify
  partitioning paths before implementation.
- **Approval gates can slow automation or create approval fatigue** -> Use
  autonomy envelopes for agents, auto-satisfy low-risk checks where policy
  allows, suggest narrow policy rules after repeated equivalent approvals, and
  preserve human gates for sensitive merges, waivers, external writes,
  destructive actions, and high-risk cross-scope authority.
- **Prompt storage improves provenance but increases sensitivity** -> Make
  prompt/input/output retention configurable by organization and resource
  classification.
- **Credential metadata can leak operational details** -> Classify credential
  records as sensitive governance resources and restrict audit-log visibility.
- **Explainable policy decisions add complexity** -> Build explanation into
  the authorization boundary early, before agents and integrations multiply.

## Migration Plan

There is no application data to migrate yet. Follow-on implementation changes
should use this design to shape:

1. account, organization, workspace, initiative/project, workstream, team,
   component, membership, external identity, and principal schemas
2. system-role, custom-role, capability, group mapping, grant,
   classification, scope-inheritance, and policy-context schemas
3. operation/correlation, audit-log, authorization-decision, approval, and
   credential metadata schemas
4. Ash policy integration and domain authorization APIs
5. agent-runtime permission checks, context assembly, context expansion, and
   temporary grant flows
6. integration credential, webhook-source, SSO mapping, SCIM provisioning, and
   local identity-lab contracts

Rollback for this change is simply revising or replacing the OpenSpec change
before implementation begins.

## Resolved Governance Questions

- User-facing vocabulary should align with normal enterprise software where
  possible. Backend-only terms should be reserved for new concepts or cases
  that do not map cleanly to conventional terms.
- Departments, org units, teams, and groups should be familiar organization
  scopes and relationships. Workspace templates can provide department-specific
  setup, but templates are not authorization sources by themselves.
- `Graph` should stay a projection over scoped graph items for the first schema
  cut rather than becoming an independent tenant or access-granting scope.
- Durable read audit should apply by default to audit logs, secrets and
  credential metadata, sensitive artifacts, agent prompts/context, exports,
  legal-hold records, and cross-scope summaries.
- Policy versions should be represented as immutable policy bundle versions
  with digests and component policy versions, referenced from sensitive
  authorization decision records.
- Secret storage should use a `SecretStore` boundary, with Office
  Graph-managed secret storage as the SaaS production default and a path to
  customer-managed secret stores for larger enterprises.
- CI should use deterministic fake SCIM contract tests. Local E2E should use
  authentik as the primary OIDC/SAML/SCIM fixture, optional Keycloak for
  OIDC/SAML compatibility, and hosted Okta/Entra only as optional future smoke
  tests.
- MVP should include basic custom-role UI on the frontend and backend endpoints
  for custom role, external group mapping, and scoped assignment management.
- Cross-scope agent runs should use approved autonomy envelopes, context
  expansion requests, temporary grants, and approval gates only when policy
  risk requires them.
- Approval gates and separation-of-duties rules should resolve approvers from
  the customer's existing company structure where possible, including SCIM/IdP
  groups, departments, manager relationships, owners, custom roles, and grants.
