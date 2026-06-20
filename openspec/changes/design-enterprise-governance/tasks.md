## 1. Review And Acceptance

- [x] 1.1 Review `proposal.md` against `openspec/project.md` and the accepted
  foundation change.
- [x] 1.2 Confirm that organization is the root tenant and that workspace plus
  initiative/project are the default visibility and work-container scopes.
- [x] 1.3 Confirm that row-based tenant isolation is the MVP posture and that
  database/schema/deployment isolation and Postgres RLS remain future options.
- [x] 1.4 Confirm that graph membership and graph edges do not grant access.
- [x] 1.5 Confirm that this change remains design-only and does not start
  Phoenix, Ash, database, API, or frontend implementation.
- [x] 1.6 Confirm that MVP architecture includes custom-role data modeling,
  external group mapping, SCIM-compatible provisioning, and local SSO/SCIM
  testing fixtures.

## 2. Capability Spec Review

- [x] 2.1 Review `tenancy` requirements for organization, workspace,
  initiative/project semantics, workstreams, hierarchical scopes, graph
  projection, and explicit scope columns.
- [x] 2.2 Review `authorization-governance` requirements for principals, roles,
  custom roles, external group mappings, capabilities, hierarchical scope
  inheritance, grants, classifications, explanations, and decision records.
- [x] 2.3 Review `audit-compliance` requirements for audit boundaries, record
  shape, operation correlation, retention, export, legal hold, visibility, and
  growth planning.
- [x] 2.4 Review `credential-security` requirements for scoped credentials,
  secret separation, webhook sources, external writes, rotation, and
  revocation.
- [x] 2.5 Review `ai-data-controls` requirements for provider policy,
  sensitive context filtering, prompt provenance, detection, redaction, and
  provider terms metadata.
- [x] 2.6 Review `enterprise-integration-posture` requirements for SSO, SCIM,
  external identity links, local identity lab, fake SCIM contract tests, SIEM,
  admin surfaces, and integration priorities.
- [x] 2.7 Review `run-approval-governance` requirements for cross-scope agent
  runs, context expansion, temporary run grants, approval gates, separation of
  duties, and provider-native approval evidence.

## 3. Open Governance Questions

- [x] 3.1 Decide whether departments are first-class scopes, team labels,
  workspace templates, or a combination.
- [x] 3.2 Decide whether `graph` is a durable scope table in the first schema
  cut or a projection over scoped graph items.
- [x] 3.3 Decide which resources require durable read-audit records by default.
- [x] 3.4 Decide how policy versions should be represented for future audit and
  decision-record interpretation.
- [x] 3.5 Decide the first secret-storage and key-management approach.
- [x] 3.6 Decide which SCIM operations and SSO flows are required in CI versus
  local E2E identity-lab tests.
- [x] 3.7 Decide how much custom-role management UI is needed in the first
  customer-facing release.
- [x] 3.8 Decide which cross-scope agent expansions can be auto-approved by
  policy and which require human approval.
- [x] 3.9 Decide which approval gates require separation of duties from the
  author, agent delegator, or original requester.

## 4. Follow-On Planning Work

- [ ] 4.1 Feed accepted initiative/project, workstream, tenancy, and scope
  rules into `design-work-graph-core`.
- [ ] 4.2 Feed tenant, scope, classification, and audit rules into
  `design-persistence-model`.
- [ ] 4.3 Feed operation correlation, audit, decision-record, retention,
  legal-hold, and soft-delete rules into `design-revision-audit-soft-delete`.
- [ ] 4.4 Feed bounded-context and extractability requirements into
  `design-code-organization-and-boundaries`.
- [ ] 4.5 Feed SSO, SCIM, local identity lab, credential, webhook-source, and
  external-write rules into `design-ingestion-and-integrations`.
- [ ] 4.6 Feed cross-scope run authority, context expansion, temporary grants,
  agent effective permission, and AI data-control rules into
  `design-agent-runtime`.
- [ ] 4.7 Feed capability, grant, approval gate, separation-of-duties, and
  manager/team-lead verification requirements into
  `design-proposed-graph-changes` and `design-work-packets-and-readiness`.
- [x] 4.8 Create `design-identity-and-authorization-schema` as the concrete
  schema inventory owner for identity, authorization scopes, policy facts,
  sensitivity labels, and credential metadata.
- [x] 4.9 Split visibility scope from sensitivity labels and clarify that
  approval gates are governed requirements that can produce evidence or
  satisfy verification checks.

## 5. Validation

- [x] 5.1 Run `openspec status --change design-enterprise-governance`.
- [x] 5.2 Run `openspec validate --changes --strict`.
- [x] 5.3 Fix any schema or formatting issues reported by OpenSpec.
