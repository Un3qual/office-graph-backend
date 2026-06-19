## Why

Office Graph needs enterprise governance decisions before graph, persistence,
agent runtime, and integration schemas are designed. Tenancy, authorization,
auditability, credential security, and AI data controls affect nearly every
durable table, API response, agent context package, and external action.

## What Changes

- Define the initial enterprise tenancy model and scope hierarchy for
  organizations, workspaces, initiatives/projects, teams, components,
  repositories, graphs, integrations, and external sources.
- Define the first authorization vocabulary: principals, roles, capabilities,
  grants, resource classifications, relationship checks, policy context, and
  decision records.
- Define MVP support for customer-specific custom roles, external group
  mapping, SCIM-compatible provisioning, and SSO/identity-provider mapping.
- Define hierarchical scope inheritance so policies can express patterns such
  as a frontend lead inheriting permissions across frontend subteams without
  relying on wildcard permission strings.
- Define the initial audit and compliance posture, including which actions
  require durable audit records versus operational logs and how shared
  operation/correlation records prevent audit/revision duplication.
- Define credential and integration security requirements for scoped tokens,
  webhook sources, rotation, revocation, and external writes.
- Define AI data controls for source code, prompts, model inputs/outputs,
  provider policy, retention, redaction, and secret handling.
- Define enterprise-readiness priorities such as SSO, SCIM, SIEM export,
  admin controls, local SSO/SCIM development testing, and future
  row-level-security defense-in-depth.
- Define governance for cross-scope agent runs, context expansion, approval
  gates, manager/team-lead verification, and separation-of-duties rules.
- Keep the work design-heavy. This change does not introduce Phoenix, Ash,
  migration, API, or frontend implementation.

## Capabilities

### New Capabilities

- `tenancy`: Tenant hierarchy, row-based isolation posture, scope inheritance,
  initiatives/projects, teams, components, memberships, and cross-scope
  boundaries.
- `authorization-governance`: Principals, roles, capabilities, grants,
  custom roles, group mappings, hierarchical scopes, classifications, policy
  context, agent effective permissions, and authorization decision records.
- `audit-compliance`: Durable audit record boundaries, retention, export,
  deletion, legal hold, operation correlation, and compliance traceability.
- `credential-security`: Integration credentials, tool tokens, webhook sources,
  secret handling, rotation, revocation, and external write controls.
- `ai-data-controls`: AI provider governance, prompt and model-output storage,
  source-code and sensitive-data controls, redaction, and no-training policy.
- `enterprise-integration-posture`: Enterprise administration and later
  integration posture for SSO, SCIM, SIEM, identity providers, local identity
  lab testing, and governance integrations.
- `run-approval-governance`: Cross-scope agent run authority, context
  expansion, human approval gates, manager/team-lead verification, and
  separation-of-duties rules.

### Modified Capabilities

- None. No accepted main specs exist yet; this change builds on the foundation
  planning artifacts and will later be promoted into durable specs.

## Impact

This change affects OpenSpec planning artifacts only. It will constrain later
schema, Ash policy, GraphQL, JSON API, agent runtime, integration, audit, and
revision designs, but it does not implement application code.
