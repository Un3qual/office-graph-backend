## 1. Review And Acceptance

- [x] 1.1 Confirm this change is design-only and does not start Phoenix, Ash,
  Ecto, migration, API, frontend, Oban, identity-lab, or runtime code.
- [x] 1.2 Confirm this change owns authentication mechanics while
  `design-identity-and-authorization-schema` owns durable identity and
  authorization facts.
- [x] 1.3 Confirm sessions/tokens do not store product permissions and must
  re-evaluate authorization against durable policy facts.
- [x] 1.4 Confirm first-org/first-owner bootstrap is required before backend
  implementation can start.

## 2. Capability Spec Review

- [x] 2.1 Review `human-authentication` requirements for local login, OIDC,
  optional SAML/Keycloak fixtures, account linking, and deprovisioning.
- [x] 2.2 Review `session-and-token-model` requirements for thin sessions,
  token posture, revocation, tenant scoping, and audit events.
- [x] 2.3 Review `service-account-and-agent-credentials` requirements for
  service account, webhook, integration, agent, and external executor
  credential mechanics.
- [x] 2.4 Review `external-identity-reconciliation` requirements for SSO/SCIM
  convergence and conflict states.
- [x] 2.5 Review `bootstrap-and-local-identity-lab` requirements for first
  organization bootstrap and local identity-lab fixture coverage.

## 3. Follow-On Planning Work

- [x] 3.1 Feed authenticated principal/session context contracts into the first
  backend walking-skeleton implementation plan.
- [ ] 3.2 Feed service account, webhook, integration, and agent credential
  mechanics into `design-ingestion-and-integrations` and
  `design-agent-runtime`.
- [x] 3.3 Feed SecretStore behaviour placement and identity context public
  contracts into `design-code-organization-and-boundaries`.
- [ ] 3.4 Feed bootstrap audit and operation-correlation requirements into
  `design-revision-audit-soft-delete`.

## 4. Validation

- [x] 4.1 Run `openspec validate design-identity-and-authentication --strict`.
- [x] 4.2 Run `openspec validate --changes --strict`.
- [x] 4.3 Fix any schema, delta, task-formatting, or validation issues
  reported by OpenSpec.
