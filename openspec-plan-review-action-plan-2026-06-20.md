# OpenSpec Plan Review Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert Claude's plan review and the follow-up Codex review into an
approved sequence of OpenSpec changes and edits that removes code-generation
blockers before Phoenix, Ash, Ecto, Boundary, API, Oban, integration, or agent
runtime code begins.

**Architecture:** Treat this as design remediation inside OpenSpec, not as
application implementation. The work first closes missing identity,
authorization, authentication, and schema ownership gaps, then reconciles
canonical spec ownership, then narrows the first backend slice to a runnable
walking skeleton with explicit ingestion and proposed-change semantics.

**Tech Stack:** OpenSpec 1.4.1 through the project Nix flake, Markdown
OpenSpec artifacts, Git commits at reviewable boundaries.

---

## Operating Rules

- Do not generate application code until the implementation-readiness gate in
  Task 9 is satisfied.
- Run project tools through:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command <tool>
```

- Validate after every OpenSpec artifact batch:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --changes --strict
```

- Commit after each coherent artifact batch. Keep Claude's review, this action
  plan, and later remediation edits in separate commits from future app code.
- Preserve the current good decisions unless a task below explicitly changes
  them: typed resources plus graph identity, provider-neutral base tables,
  explicit external references, no local polymorphic foreign keys, limited JSON,
  graph edges do not grant access, and operation correlation is a narrow write
  trace rather than an event store.

## Finding Disposition

| Finding | Disposition | Owning Task |
| --- | --- | --- |
| F1 authz/identity/credential table gap | Fix before code. Add a concrete schema inventory and scope hierarchy storage decision. | Task 2 |
| F2 missing identity/authentication change | Fix before code. Add a separate authentication mechanics change. | Task 3 |
| F3 first migration cannot run the core loop | Fix before code by defining a walking skeleton and minimal execution records. | Task 5 |
| F4 duplicate canonical requirements | Fix before promotion by assigning one canonical owner per shared concept. | Task 4 |
| F5 capability taxonomy collision | Fix before promotion by declaring foundation as framing, not wholesale durable spec content. | Task 4 |
| F6 stale project-plan sequencing | Fix soon by replacing the historical order with the real dependency order. | Task 1 |
| F7 rich text and placement scope | Change before first migration by narrowing v1 body and ordering semantics. | Task 5 |
| F8 product wedge underdefined | Fix before code by naming the first executable walking skeleton and validation metric. | Task 5 |
| F9 overloaded `check` vocabulary | Fix before schema/API design. | Task 7 |
| F10 classification mixes visibility and sensitivity | Fix before policy/schema design. | Task 7 |
| F11 aggregate vs rich-text revision boundary | Fix with a worked example. | Task 7 |
| F12 ingestion deferred but needed for MVP | Fix before code by writing ingestion/integration semantics. | Task 6 |
| F13 custom-role UI has no design home | Change: keep schema/actions/tests in authz, place UI/API in API/UI change. | Task 7 |
| F14 edge tombstones and restore cascade | Fix in revision/audit/soft-delete and work-graph artifacts. | Task 7 |
| F15 foundation metadata and stale tasks | Cleanup, not a blocker. | Task 7 |
| F16 `initiative_id` vs `project_id` | Fix by locking `initiative_id` in durable schema language. | Task 7 |
| F17 audit JSON exception cross-reference | Fix by cross-linking audit detail JSON to JSON storage policy. | Task 7 |
| N1 implementation-readiness gate missing | Add a cross-change gate before any code generation. | Task 9 |
| N2 first-org and first-admin bootstrap missing | Add to identity/authentication mechanics. | Task 3 |
| N3 graph identity plus typed resource transaction invariant missing | Add to persistence/code-organization remediation. | Task 5 |
| N4 manual pasted intake option not decided | Use manual intake as the first walking-skeleton adapter. | Task 6 |
| N5 transactional side-effect pattern missing | Add operation/job/event enqueue rules before Oban code. | Task 8 |

## File Structure

Review artifacts:

- Keep: `openspec-plan-review-2026-06-20.md`
- Create: `openspec-plan-review-action-plan-2026-06-20.md`

Existing OpenSpec files to modify during remediation:

- `openspec/project-plan.md`: dependency order, implementation-readiness gate,
  canonical capability map, walking-skeleton sequence.
- `openspec/project.md`: only stable final decisions that should become durable
  project doctrine.
- `openspec/changes/define-office-graph-foundation/.openspec.yaml`: metadata
  cleanup.
- `openspec/changes/define-office-graph-foundation/tasks.md`: refresh stale
  open questions and mark decisions answered downstream.
- `openspec/changes/define-office-graph-foundation/specs/*/spec.md`: remove or
  soften duplicated canonical requirements only after the canonical map is
  approved.
- `openspec/changes/design-enterprise-governance/design.md`: clarify
  classification, custom-role UI scope, policy fact ownership, and
  authentication/schema handoff.
- `openspec/changes/design-enterprise-governance/specs/*/spec.md`: update
  authorization, tenancy, credential, integration posture, and run approval
  requirements.
- `openspec/changes/design-enterprise-governance/tasks.md`: add and complete
  remediation checklist items as decisions are captured.
- `openspec/changes/design-persistence-model/design.md`: replace "no
  migration-blocking questions remain" with the new cross-change readiness gate,
  add the walking-skeleton migration boundary, narrow rich text and placement,
  and add graph identity plus typed resource transaction rules.
- `openspec/changes/design-persistence-model/specs/*/spec.md`: update MVP
  inventory, graph storage, rich text, ordered placement, and JSON policy.
- `openspec/changes/design-persistence-model/tasks.md`: add remediation and
  follow-on items for the walking skeleton and identity/authz schema.
- `openspec/changes/design-revision-audit-soft-delete/design.md`: clarify
  revision stitching, edge tombstones, restore cascade, JSON exception, and
  operation correlation owner.
- `openspec/changes/design-revision-audit-soft-delete/specs/*/spec.md`: update
  typed revision, audit boundary, operation correlation, and tombstone specs.
- `openspec/changes/design-revision-audit-soft-delete/tasks.md`: add
  remediation checklist items.
- `openspec/changes/design-work-graph-core/design.md`: add edge lifecycle and
  walking-skeleton graph scope clarifications.
- `openspec/changes/design-work-graph-core/specs/*/spec.md`: update graph
  relationships, graph items, graph projections, and domain attachments as
  needed.
- `openspec/changes/design-work-graph-core/tasks.md`: add follow-on and
  remediation checklist items.
- `openspec/changes/design-code-organization-and-boundaries/design.md`: record
  concrete code-generation decisions after the blockers are resolved.
- `openspec/changes/design-code-organization-and-boundaries/specs/*/spec.md`:
  adjust entrypoint, operation contract, and Boundary requirements to reflect
  the approved gate.
- `openspec/changes/design-code-organization-and-boundaries/tasks.md`: complete
  review tasks and close tasks 3.1 through 3.6 after decisions are written.

New OpenSpec changes to create before backend code:

- `openspec/changes/design-identity-and-authorization-schema/`
- `openspec/changes/design-identity-and-authentication/`
- `openspec/changes/design-ingestion-and-integrations/`
- `openspec/changes/design-proposed-graph-changes/`

Optional OpenSpec changes to create only if the prior four become too large:

- `openspec/changes/design-rich-text-implementation-slice/`
- `openspec/changes/design-api-realtime-and-ui-projections/`

## Target Dependency Order

Use this order in `openspec/project-plan.md` after the remediation pass:

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

This order intentionally moves governance and identity before storage/code
generation because every Ash policy, graph projection, audit decision, and
agent authority check depends on those facts.

## Task 1: Record The Remediation Lane And Real Dependency Order

**Files:**

- Modify: `openspec/project-plan.md`
- Modify: `openspec/changes/define-office-graph-foundation/tasks.md`
- Create or keep: `openspec-plan-review-action-plan-2026-06-20.md`

- [ ] **Step 1: Add a "Plan Review Remediation" section to `openspec/project-plan.md`.**

  Add a section near "Architecture Notes To Resolve Before Code" with these
  decisions:

  - Claude's review and the Codex follow-up are accepted as a remediation input,
    not as durable product requirements by themselves.
  - No backend code generation starts until identity/authz schema,
    authentication mechanics, canonical spec ownership, walking skeleton,
    ingestion semantics, proposed graph changes, and code organization
    decisions are resolved.
  - The `design-persistence-model` statement that no migration-blocking
    persistence questions remain is superseded by a cross-change readiness gate.
  - The first backend target is a walking skeleton, not a maximal first schema.

- [ ] **Step 2: Replace the historical "Proposed First Formal OpenSpec Changes" order.**

  Keep the old list only if it is clearly labeled as historical. Add the target
  dependency order from this plan so future work does not put governance last.

- [ ] **Step 3: Refresh foundation open questions.**

  In `openspec/changes/define-office-graph-foundation/tasks.md`, add a small
  "Plan Review Remediation" subsection that points to the new identity,
  canonicalization, walking-skeleton, and ingestion work. Mark downstream
  decisions as resolved only when the corresponding active change contains the
  decision.

- [ ] **Step 4: Validate and commit.**

  Run:

  ```bash
  nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --changes --strict
  git add openspec/project-plan.md openspec/changes/define-office-graph-foundation/tasks.md openspec-plan-review-action-plan-2026-06-20.md
  git commit -m "Document OpenSpec review remediation plan"
  ```

  Expected validation result: all active changes pass.

## Task 2: Create `design-identity-and-authorization-schema`

**Files:**

- Create: `openspec/changes/design-identity-and-authorization-schema/.openspec.yaml`
- Create: `openspec/changes/design-identity-and-authorization-schema/proposal.md`
- Create: `openspec/changes/design-identity-and-authorization-schema/design.md`
- Create: `openspec/changes/design-identity-and-authorization-schema/tasks.md`
- Create: `openspec/changes/design-identity-and-authorization-schema/specs/identity-authorization-inventory/spec.md`
- Create: `openspec/changes/design-identity-and-authorization-schema/specs/scope-hierarchy-storage/spec.md`
- Create: `openspec/changes/design-identity-and-authorization-schema/specs/principal-role-capability-model/spec.md`
- Create: `openspec/changes/design-identity-and-authorization-schema/specs/policy-fact-versioning/spec.md`
- Create: `openspec/changes/design-identity-and-authorization-schema/specs/credential-metadata-model/spec.md`
- Modify: `openspec/changes/design-persistence-model/design.md`
- Modify: `openspec/changes/design-persistence-model/specs/mvp-persistence-inventory/spec.md`
- Modify: `openspec/changes/design-persistence-model/tasks.md`
- Modify: `openspec/changes/design-enterprise-governance/design.md`
- Modify: `openspec/changes/design-enterprise-governance/tasks.md`

- [ ] **Step 1: Define the change scope.**

  The proposal must state that this change owns concrete persistence inventory
  for identity, authorization, scope hierarchy, policy facts, classifications,
  credential metadata, and external identity references. It must remain
  design-only and must not implement migrations.

- [ ] **Step 2: Add the initial table-family inventory.**

  The design must cover these table families:

  - `principals`: human users, agents, service accounts, integrations, webhook
    sources, external executors, and system jobs.
  - `principal_profiles` or equivalent human profile table separate from the
    generic principal record.
  - `external_identity_links`: provider, provider tenant, external subject,
    verified identifier, account-linking state, lifecycle state, and conflict
    state.
  - `authorization_scopes`: organization, workspace, initiative, workstream,
    department, org unit, team, component, repository, service, integration,
    external source, artifact, and resource scopes.
  - `authorization_scope_paths`: closure-table rows for ancestor scope,
    descendant scope, depth, inheritance mode, lifecycle state, and provenance.
  - `capabilities`: stable capability identifiers and descriptions.
  - `roles`: system and custom roles with organization ownership and lifecycle
    state.
  - `role_capabilities`: capability membership in a role.
  - `role_assignments`: principal, role, assigned scope, descendant inheritance
    mode, actor, reason, lifecycle state, and operation correlation.
  - `explicit_grants`: principal, resource or scope, capability, reason,
    creator, expiration when applicable, lifecycle state, and operation
    correlation.
  - `teams`, `team_memberships`, `groups`, `group_mappings`, `departments`, and
    `org_units` where they are policy facts rather than only display objects.
  - `resource_sensitivity_labels`: sensitivity labels such as normal,
    confidential, secret, source_code, customer_sensitive, finance_sensitive,
    legal_sensitive, and security_sensitive.
  - `resource_sensitivity_assignments`: resource, sensitivity label,
    inheritance basis, actor, lifecycle state, and operation correlation.
  - `policy_bundles` and `policy_bundle_versions`: immutable policy version,
    digest, effective period, and component policy references.
  - `authorization_fact_versions`: optional fact-version anchor for sensitive
    decision records when exact policy inputs must be reconstructable.
  - `credential_metadata`: provider, owner principal, organization, allowed
    scopes, capability, lifecycle, fingerprint/reference, secret-store key,
    rotation, revocation, and audit linkage.

- [ ] **Step 3: Decide scope hierarchy storage.**

  Use an adjacency list plus closure table as the recommended first storage
  model. Reject `ltree` as the first design because it ties policy inheritance
  to string paths and makes scope moves harder to audit. Reject materialized
  path as the sole model because descendant permission explanations need stable
  ancestor and descendant rows.

- [ ] **Step 4: Define scope move behavior.**

  The design must specify that moving a scope recalculates closure rows through
  an operation-correlated domain action, records before/after inheritance
  impact, and invalidates or recomputes cached authorization explanations.

- [ ] **Step 5: Feed the inventory back into persistence.**

  Update `design-persistence-model` so its MVP inventory explicitly references
  the identity/authz inventory as a required companion before first migrations.
  Do not duplicate every table in the persistence change; link to the schema
  change as the owning artifact.

- [ ] **Step 6: Validate and commit.**

  Run:

  ```bash
  nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate design-identity-and-authorization-schema --strict
  nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --changes --strict
  git add openspec/changes/design-identity-and-authorization-schema openspec/changes/design-persistence-model openspec/changes/design-enterprise-governance
  git commit -m "Design identity and authorization schema inventory"
  ```

  Expected validation result: the new change and all active changes pass.

## Task 3: Create `design-identity-and-authentication`

**Files:**

- Create: `openspec/changes/design-identity-and-authentication/.openspec.yaml`
- Create: `openspec/changes/design-identity-and-authentication/proposal.md`
- Create: `openspec/changes/design-identity-and-authentication/design.md`
- Create: `openspec/changes/design-identity-and-authentication/tasks.md`
- Create: `openspec/changes/design-identity-and-authentication/specs/human-authentication/spec.md`
- Create: `openspec/changes/design-identity-and-authentication/specs/session-and-token-model/spec.md`
- Create: `openspec/changes/design-identity-and-authentication/specs/service-account-and-agent-credentials/spec.md`
- Create: `openspec/changes/design-identity-and-authentication/specs/external-identity-reconciliation/spec.md`
- Create: `openspec/changes/design-identity-and-authentication/specs/bootstrap-and-local-identity-lab/spec.md`
- Modify: `openspec/changes/design-enterprise-governance/specs/enterprise-integration-posture/spec.md`
- Modify: `openspec/changes/design-code-organization-and-boundaries/design.md`
- Modify: `openspec/project-plan.md`

- [ ] **Step 1: Define authentication mechanics separately from authorization facts.**

  This change owns how a principal becomes authenticated or receives runtime
  credentials. The authorization schema change owns what facts policy evaluates.

- [ ] **Step 2: Cover human authentication.**

  The design must decide the first supported human login path:

  - local development login through the identity lab
  - OIDC login through authentik as the primary local fixture
  - optional SAML and Keycloak compatibility paths as test fixtures, not launch
    blockers
  - account linking through `external_identity_links`
  - deprovisioning behavior when an external identity is disabled

- [ ] **Step 3: Cover sessions and tokens.**

  The design must cover browser sessions, API tokens if any, refresh behavior,
  token revocation, tenant scoping, audit events for sensitive session actions,
  and how sessions map to a `principal_id`.

- [ ] **Step 4: Cover service accounts, webhook principals, and agents.**

  The design must describe credential issuance, rotation, revocation, scope
  constraints, capability constraints, and audit linkage for:

  - service accounts
  - webhook source principals
  - integration installation principals
  - internal agent principals
  - external executor principals

- [ ] **Step 5: Define first-org and first-admin bootstrap.**

  Add a bootstrap path that creates the first organization, first org owner
  principal, first workspace, and initial policy bundle without relying on
  hosted enterprise IdP setup. The bootstrap path must be audited, idempotent in
  development/test, and disabled or tightly controlled after the first owner is
  established.

- [ ] **Step 6: Preserve future library extraction.**

  The design must keep authentication/identity as an internal Boundary context
  with clean configuration, storage, and public contracts so it can later be
  extracted without depending on Office Graph-specific graph semantics.

- [ ] **Step 7: Validate and commit.**

  Run:

  ```bash
  nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate design-identity-and-authentication --strict
  nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --changes --strict
  git add openspec/changes/design-identity-and-authentication openspec/changes/design-enterprise-governance openspec/changes/design-code-organization-and-boundaries openspec/project-plan.md
  git commit -m "Design identity and authentication mechanics"
  ```

## Task 4: Decide Canonical Capability Map And Promotion Policy

**Files:**

- Modify: `openspec/project-plan.md`
- Modify: `openspec/changes/define-office-graph-foundation/design.md`
- Modify: `openspec/changes/define-office-graph-foundation/specs/authorization/spec.md`
- Modify: `openspec/changes/define-office-graph-foundation/specs/persistence/spec.md`
- Modify: `openspec/changes/define-office-graph-foundation/specs/work-graph/spec.md`
- Modify: `openspec/changes/define-office-graph-foundation/specs/backend-architecture/spec.md`
- Modify: `openspec/changes/define-office-graph-foundation/tasks.md`
- Modify: `openspec/changes/design-enterprise-governance/specs/authorization-governance/spec.md`
- Modify: `openspec/changes/design-revision-audit-soft-delete/specs/audit-record-boundaries/spec.md`
- Modify: `openspec/changes/design-revision-audit-soft-delete/specs/operation-correlation/spec.md`
- Modify: `openspec/changes/design-work-graph-core/specs/graph-relationships/spec.md`
- Modify: `openspec/changes/design-code-organization-and-boundaries/specs/shared-operation-contracts/spec.md`

- [ ] **Step 1: Declare foundation as framing.**

  Record that `define-office-graph-foundation` is the durable "why/what"
  framing change and should not be promoted wholesale into duplicate canonical
  `openspec/specs/authorization`, `openspec/specs/persistence`,
  `openspec/specs/work-graph`, or `openspec/specs/backend-architecture`
  capabilities when the granular changes are archived.

- [ ] **Step 2: Add the canonical concept owner table.**

  Add this table to `openspec/project-plan.md`:

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

- [ ] **Step 3: Pin operation correlation fields in one place.**

  Make `design-revision-audit-soft-delete/specs/operation-correlation/spec.md`
  the field-list owner. The first operation record must include organization,
  optional workspace/initiative/workstream scope, actor principal, delegated
  principal, agent run when present, service account or external source when
  present, command key, idempotency key when applicable, request/trace
  identifiers, authority basis, reason, source surface, primary graph item or
  external reference when present, and timestamps.

- [ ] **Step 4: Pin the agent effective permission formula in one place.**

  Make `design-enterprise-governance/specs/authorization-governance/spec.md`
  canonical. The formula is the intersection of delegator/user permission,
  agent principal capability, work packet autonomy policy, tool or integration
  scope, organization policy, resource sensitivity policy, and any approved
  context expansion or temporary grant.

- [ ] **Step 5: Convert duplicates into references.**

  Foundation and other changes may summarize shared concepts, but must point to
  the canonical owner instead of restating subtly different requirements.

- [ ] **Step 6: Validate and commit.**

  Run:

  ```bash
  nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --changes --strict
  git add openspec/project-plan.md openspec/changes/define-office-graph-foundation openspec/changes/design-enterprise-governance openspec/changes/design-revision-audit-soft-delete openspec/changes/design-work-graph-core openspec/changes/design-code-organization-and-boundaries
  git commit -m "Reconcile OpenSpec capability ownership"
  ```

## Task 5: Define The Walking Skeleton And Rescope First Persistence

**Files:**

- Modify: `openspec/project-plan.md`
- Modify: `openspec/changes/design-persistence-model/design.md`
- Modify: `openspec/changes/design-persistence-model/specs/mvp-persistence-inventory/spec.md`
- Modify: `openspec/changes/design-persistence-model/specs/portable-rich-text-persistence/spec.md`
- Modify: `openspec/changes/design-persistence-model/specs/ordered-placement-model/spec.md`
- Modify: `openspec/changes/design-persistence-model/specs/graph-storage-contract/spec.md`
- Modify: `openspec/changes/design-persistence-model/tasks.md`
- Modify: `openspec/changes/design-work-graph-core/design.md`
- Modify: `openspec/changes/design-work-graph-core/specs/graph-items/spec.md`
- Modify: `openspec/changes/design-revision-audit-soft-delete/specs/typed-revision-history/spec.md`

- [ ] **Step 1: Name the first executable slice.**

  Use this walking skeleton:

  ```text
  manual intake signal
    -> task
    -> review finding
    -> required verification check
    -> evidence item
    -> verified completion
  ```

  The slice must include one organization, one workspace, one initiative, one
  authenticated principal, one role assignment, one graph identity per
  graph-addressable resource, one audit record for a sensitive action, one
  operation correlation record, and one typed revision path.

- [ ] **Step 2: Pull minimal execution records forward.**

  Add design language that the first backend cut needs minimal versions of:

  - `work_packets`: objective, source task, readiness state, autonomy policy
    reference, and required checks.
  - `runs`: actor principal, optional agent principal, work packet, lifecycle
    state, operation correlation, and result.
  - `run_events`: append-only execution timeline with operation correlation.
  - `proposed_graph_changes`: proposed operation, target resource, validation
    state, actor/agent source, approval state, and applied operation reference.
  - `verification_results`: check, evidence, result, verifier, timestamp, and
    operation correlation.

  These are skeletal records, not full runtime implementations.

- [ ] **Step 3: Narrow the rich text v1.**

  Replace the first-cut expectation of full copy-on-write rich text with:

  - normalized `rich_text_documents`
  - current `rich_text_blocks`
  - basic marks for bold, italic, inline code, links, principal mentions, graph
    item references, external references, URLs, and artifact references
  - whole-document semantic revision records for v1
  - derived plain text only where needed for search or agent context

  Defer per-inline copy-on-write reconstruction, quote snapshots, live quote
  resolution, selection-intent preservation, HTML render caches, Lexical
  adapter persistence, and collaboration/session state to a rich text
  implementation change.

- [ ] **Step 4: Narrow ordered placement v1.**

  Keep the durable no-polymorphic-FK rule. For the first cut, use explicit
  domain-owned ordering for task lists and rich text blocks. Defer the reusable
  generic ordered-placement API, rebalancing job design, dense ordinal
  projections, grid placement, swimlanes, and topological ordering until real
  usage requires them.

- [ ] **Step 5: Add graph identity plus typed resource transaction invariants.**

  State that graph-addressable typed resources are created through one domain
  action that writes the graph identity and typed resource in the same database
  transaction. If either insert fails, neither record becomes visible. The
  graph identity context provides the public allocation contract; typed
  resource contexts own business validation and lifecycle.

- [ ] **Step 6: Replace isolated readiness claims.**

  In `design-persistence-model/design.md`, replace the "No
  migration-blocking persistence questions remain" language with: "No
  persistence-only questions remain, but first migration readiness is blocked
  until the cross-change implementation-readiness gate is complete."

- [ ] **Step 7: Validate and commit.**

  Run:

  ```bash
  nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate design-persistence-model --strict
  nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --changes --strict
  git add openspec/project-plan.md openspec/changes/design-persistence-model openspec/changes/design-work-graph-core openspec/changes/design-revision-audit-soft-delete
  git commit -m "Define walking skeleton persistence scope"
  ```

## Task 6: Create Ingestion And Proposed Graph Change Designs

**Files:**

- Create: `openspec/changes/design-ingestion-and-integrations/.openspec.yaml`
- Create: `openspec/changes/design-ingestion-and-integrations/proposal.md`
- Create: `openspec/changes/design-ingestion-and-integrations/design.md`
- Create: `openspec/changes/design-ingestion-and-integrations/tasks.md`
- Create: `openspec/changes/design-ingestion-and-integrations/specs/manual-intake-adapter/spec.md`
- Create: `openspec/changes/design-ingestion-and-integrations/specs/external-event-normalization/spec.md`
- Create: `openspec/changes/design-ingestion-and-integrations/specs/idempotency-and-replay/spec.md`
- Create: `openspec/changes/design-ingestion-and-integrations/specs/provider-adapter-contract/spec.md`
- Create: `openspec/changes/design-ingestion-and-integrations/specs/sync-state-machine/spec.md`
- Create: `openspec/changes/design-proposed-graph-changes/.openspec.yaml`
- Create: `openspec/changes/design-proposed-graph-changes/proposal.md`
- Create: `openspec/changes/design-proposed-graph-changes/design.md`
- Create: `openspec/changes/design-proposed-graph-changes/tasks.md`
- Create: `openspec/changes/design-proposed-graph-changes/specs/proposed-change-shape/spec.md`
- Create: `openspec/changes/design-proposed-graph-changes/specs/proposed-change-validation/spec.md`
- Create: `openspec/changes/design-proposed-graph-changes/specs/proposed-change-authorization/spec.md`
- Create: `openspec/changes/design-proposed-graph-changes/specs/proposed-change-application/spec.md`
- Modify: `openspec/changes/design-persistence-model/design.md`
- Modify: `openspec/changes/design-code-organization-and-boundaries/design.md`
- Modify: `openspec/project-plan.md`

- [ ] **Step 1: Make manual intake the first adapter.**

  The first executable slice starts with manual pasted intake. This avoids
  blocking the first demo on GitHub/Sentry webhook maturity while still using
  the same adapter contract, raw archive boundary, idempotency, and signal
  normalization path that webhooks will use.

- [ ] **Step 2: Define external event normalization.**

  The ingestion design must distinguish raw payload archive, normalized
  external event, signal, provider-neutral resource, review finding, evidence,
  and sync event.

- [ ] **Step 3: Define idempotency and replay.**

  The design must specify replay identity, source identity, duplicate handling,
  out-of-order event handling, retry behavior, operation correlation linkage,
  and how domain actions reject or merge duplicates.

- [ ] **Step 4: Define adapter contract.**

  Adapter outputs must be typed and provider-neutral:

  - source identity
  - normalized event kind
  - raw archive reference
  - idempotency basis
  - intended domain action
  - affected external references
  - required credential or webhook principal
  - operation context input

- [ ] **Step 5: Define proposed graph changes.**

  The proposed-change design must preserve the product rule that agents and
  generated UI do not mutate truth tables directly. A proposed graph change is
  validated, authorized, optionally approved, and applied through domain
  actions that produce normal revisions, audit records, operation correlation,
  and evidence.

- [ ] **Step 6: Validate and commit.**

  Run:

  ```bash
  nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate design-ingestion-and-integrations --strict
  nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate design-proposed-graph-changes --strict
  nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --changes --strict
  git add openspec/changes/design-ingestion-and-integrations openspec/changes/design-proposed-graph-changes openspec/changes/design-persistence-model openspec/changes/design-code-organization-and-boundaries openspec/project-plan.md
  git commit -m "Design ingestion and proposed graph changes"
  ```

## Task 7: Resolve Modeling Ambiguities And Cleanup Items

**Files:**

- Modify: `openspec/changes/design-enterprise-governance/design.md`
- Modify: `openspec/changes/design-enterprise-governance/specs/authorization-governance/spec.md`
- Modify: `openspec/changes/design-enterprise-governance/specs/run-approval-governance/spec.md`
- Modify: `openspec/changes/design-persistence-model/design.md`
- Modify: `openspec/changes/design-persistence-model/specs/mvp-persistence-inventory/spec.md`
- Modify: `openspec/changes/design-persistence-model/specs/json-storage-policy/spec.md`
- Modify: `openspec/changes/design-revision-audit-soft-delete/design.md`
- Modify: `openspec/changes/design-revision-audit-soft-delete/specs/typed-revision-history/spec.md`
- Modify: `openspec/changes/design-revision-audit-soft-delete/specs/audit-record-boundaries/spec.md`
- Modify: `openspec/changes/design-revision-audit-soft-delete/specs/soft-delete-tombstones/spec.md`
- Modify: `openspec/changes/design-work-graph-core/specs/graph-relationships/spec.md`
- Modify: `openspec/changes/define-office-graph-foundation/.openspec.yaml`
- Modify: `openspec/changes/define-office-graph-foundation/tasks.md`

- [ ] **Step 1: Disambiguate check vocabulary.**

  Use these terms:

  - `verification_check`: desired condition that must be satisfied.
  - `approval_gate`: governed human or policy approval requirement that may
    satisfy or unblock a verification check.
  - `check_run`: provider-neutral CI or external system check run.
  - `check_waiver`: authorized exception against a verification check.

  Update existing specs so "approval gates are checks" becomes "approval gates
  are governed requirements that can produce evidence or satisfy a verification
  check."

- [ ] **Step 2: Split visibility from sensitivity.**

  Replace one mixed classification enum with:

  - visibility scope from tenant/scope columns and projection policy:
    organization, workspace, initiative, workstream, team, component,
    repository, service, integration, external source, artifact, or resource.
  - sensitivity label from typed labels: normal, confidential, secret,
    source_code, customer_sensitive, finance_sensitive, legal_sensitive,
    security_sensitive.

- [ ] **Step 3: Add aggregate versus rich-text revision example.**

  Add a worked example: when a user edits a task title and one word of its
  description in one save, the task aggregate revision captures the title
  change and references the rich text document revision for the description
  change. Both records reference the same operation correlation id.

- [ ] **Step 4: Add edge tombstones and restore cascade.**

  Graph relationships must have lifecycle and deletion semantics. Deleting a
  graph item tombstones or disables its incident edges according to relationship
  type. Restoring a graph item does not automatically restore all incident
  edges unless the relationship type declares restore eligibility and policy
  approves it. Restoring a parent work container must declare whether child
  graph items restore in place, remain deleted, or require explicit selection.

- [ ] **Step 5: Lock `initiative_id`.**

  Replace schema-facing "`initiative_id` or `project_id`" wording with
  `initiative_id`. Keep `project` as a customer-facing alias only.

- [ ] **Step 6: Cross-link audit JSON exception.**

  Update audit specs to state that `audit_event_details` is an approved,
  schema-versioned JSON exception under `json-storage-policy`; queryable audit
  fields and targets remain relational.

- [ ] **Step 7: Refresh foundation metadata and stale tasks.**

  Add `.openspec.yaml` to `define-office-graph-foundation` with metadata
  consistent with the other active changes. Refresh stale foundation checklist
  items by pointing to the downstream owner or marking only those that are
  genuinely resolved.

- [ ] **Step 8: Validate and commit.**

  Run:

  ```bash
  nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --changes --strict
  git add openspec/changes/design-enterprise-governance openspec/changes/design-persistence-model openspec/changes/design-revision-audit-soft-delete openspec/changes/design-work-graph-core openspec/changes/define-office-graph-foundation
  git commit -m "Resolve OpenSpec modeling ambiguities"
  ```

## Task 8: Close Code Organization Decisions

**Files:**

- Modify: `openspec/changes/design-code-organization-and-boundaries/design.md`
- Modify: `openspec/changes/design-code-organization-and-boundaries/tasks.md`
- Modify: `openspec/changes/design-code-organization-and-boundaries/specs/bounded-context-architecture/spec.md`
- Modify: `openspec/changes/design-code-organization-and-boundaries/specs/shared-operation-contracts/spec.md`
- Modify: `openspec/changes/design-code-organization-and-boundaries/specs/entrypoint-boundary-contracts/spec.md`
- Modify: `openspec/changes/design-code-organization-and-boundaries/specs/boundary-enforcement/spec.md`

- [ ] **Step 1: Mark review acceptance tasks after actual review.**

  Complete tasks 1.1 through 2.7 only after this remediation plan and the
  updated artifacts have been reviewed against project context.

- [ ] **Step 2: Decide first module and folder layout.**

  Recommended first namespace:

  ```text
  OfficeGraph
  OfficeGraph.Foundation
  OfficeGraph.Identity
  OfficeGraph.Tenancy
  OfficeGraph.Authorization
  OfficeGraph.Operations
  OfficeGraph.Audit
  OfficeGraph.Revisions
  OfficeGraph.WorkContainers
  OfficeGraph.WorkGraph
  OfficeGraph.Content
  OfficeGraph.ExternalRefs
  OfficeGraph.Integrations
  OfficeGraph.SoftwareProving
  OfficeGraph.WorkPackets
  OfficeGraph.Runs
  OfficeGraph.Verification
  OfficeGraph.ProposedChanges
  OfficeGraph.AgentRuntime
  OfficeGraph.Projections
  OfficeGraphWeb
  ```

  Public context modules live at `lib/office_graph/<context>.ex`. Internal
  implementation lives under `lib/office_graph/<context>/`. Web/API entrypoints
  live under `lib/office_graph_web/`.

- [ ] **Step 3: Decide operation correlation context.**

  Start operation correlation as `OfficeGraph.Operations`, a dedicated context
  that owns operation context structs, idempotency basis, and durable operation
  records. It must not be under audit or revision because it spans audit,
  revisions, auth decisions, runs, sync events, proposed changes, and jobs.

- [ ] **Step 4: Decide software proving context.**

  Start software proving as `OfficeGraph.SoftwareProving`, separate from
  provider adapters. GitHub/Sentry/GitLab adapter code belongs under
  integrations; provider-neutral review findings, review comments, check runs,
  commits, pull requests, observability issues, and evidence-oriented resources
  belong under software proving when they become product facts.

- [ ] **Step 5: Decide first direct SQL paths.**

  Use Ash-backed composition for single-context CRUD and simple lists. Allow
  direct Ecto/SQL only for authorization-filtered graph neighborhood
  projections, mixed-type graph projection queries, replay/idempotency scans,
  operation-correlated history joins, and high-volume event/sync maintenance.

- [ ] **Step 6: Decide Boundary strictness.**

  Use coarse Boundary contexts from the first app cut. Export public context
  modules and approved Ash domain modules. Keep private modules private even in
  tests except for context-local test support. Add Boundary validation to CI as
  soon as the app shell exists.

- [ ] **Step 7: Decide first behaviours/callback seams.**

  Add behaviours early only for provider adapters, SecretStore, external
  identity/SCIM test adapter, agent tool adapters, and notifier/export sinks.
  Keep rich text, ordered placement, revisions, audit, and authorization policy
  concrete until their public contracts stabilize.

- [ ] **Step 8: Define transactional side-effect pattern.**

  State that durable domain actions use one transaction for product state,
  operation correlation, revisions, and audit records. Jobs, domain events, and
  external side effects are enqueued or emitted only through approved
  transaction-safe mechanisms so retries cannot create duplicate truth-table
  mutations.

- [ ] **Step 9: Validate and commit.**

  Run:

  ```bash
  nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate design-code-organization-and-boundaries --strict
  nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --changes --strict
  git add openspec/changes/design-code-organization-and-boundaries
  git commit -m "Close code organization decisions"
  ```

## Task 9: Add The Implementation-Readiness Gate

**Files:**

- Modify: `openspec/project-plan.md`
- Modify: `openspec/changes/design-code-organization-and-boundaries/tasks.md`
- Create: future `openspec/changes/first-backend-walking-skeleton/` only after
  this gate is satisfied and approved.

- [ ] **Step 1: Add gate checklist to `openspec/project-plan.md`.**

  The first backend app-generation change may start only when all items below
  are true:

  - `design-identity-and-authorization-schema` exists and validates.
  - `design-identity-and-authentication` exists and validates.
  - `design-ingestion-and-integrations` exists and validates.
  - `design-proposed-graph-changes` exists and validates.
  - Canonical concept owner table is recorded.
  - Foundation is marked as framing or explicitly scoped as an umbrella spec.
  - The walking skeleton is defined and accepted.
  - Rich text v1 is narrowed.
  - Ordered placement v1 is narrowed.
  - Check vocabulary is disambiguated.
  - Visibility scope and sensitivity labels are separated.
  - Edge tombstone and restore rules are recorded.
  - `initiative_id` is the durable column name.
  - Code organization tasks 3.1 through 3.6 are complete.
  - All active changes pass `openspec validate --changes --strict`.

- [ ] **Step 2: Define the next OpenSpec change after the gate.**

  The first implementation change should be named
  `first-backend-walking-skeleton`. It should generate the Phoenix API app,
  configure Boundary, create only the minimal Ash/Ecto resources needed for the
  walking skeleton, and include verification commands for compile, format,
  tests, Boundary, and OpenSpec.

- [ ] **Step 3: Validate and commit.**

  Run:

  ```bash
  nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --changes --strict
  git add openspec/project-plan.md openspec/changes/design-code-organization-and-boundaries/tasks.md
  git commit -m "Add backend implementation readiness gate"
  ```

## Execution Order

1. Task 1: record remediation lane and real dependency order.
2. Task 2: create identity and authorization schema change.
3. Task 3: create identity and authentication change.
4. Task 4: reconcile canonical capability ownership.
5. Task 5: define walking skeleton and rescope first persistence.
6. Task 6: create ingestion and proposed graph change designs.
7. Task 7: resolve modeling ambiguities and cleanup items.
8. Task 8: close code organization decisions.
9. Task 9: add final implementation-readiness gate.

## Verification Strategy

Run these after every task:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --changes --strict
git status --short --branch
```

Run these when a new change is created:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec status --change <change-name> --json
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate <change-name> --strict
```

Expected final result before backend code generation:

- All active OpenSpec changes validate.
- No critical or high Claude finding remains unaddressed.
- Every medium finding is either resolved in an artifact or explicitly assigned
  to a named future change.
- The new Codex findings N1 through N5 are captured in OpenSpec artifacts.
- `openspec/project-plan.md` no longer points contributors through stale
  sequencing.
- The first backend implementation has a narrow, testable walking skeleton
  instead of a maximal schema target.

## Approval Checkpoint

Before Task 1 begins, review this action plan and approve:

- the creation of two new identity changes rather than one combined identity
  mega-change
- the choice of adjacency list plus closure table for scope hierarchy storage
- the choice to treat foundation as framing rather than promoting its coarse
  specs wholesale
- the choice to use manual pasted intake as the first walking-skeleton adapter
- the choice to narrow rich text and ordered placement for v1
- the choice to block backend code generation until the readiness gate is met
