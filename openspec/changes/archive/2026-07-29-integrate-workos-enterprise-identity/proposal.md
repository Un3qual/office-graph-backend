## Why

Office Graph already owns durable principals, external identity links, browser
sessions, and authorization, but its only implemented human login provider is
the local Authentik-oriented OIDC path and it has no directory provisioning or
group lifecycle ingestion. Enterprise customers need managed SSO and directory
connectivity without handing session, authorization, or user ownership to a
hosted authentication product.

## What Changes

- Add a WorkOS SSO adapter for organization-selected enterprise login while
  retaining Office Graph-owned login transactions, external identity
  reconciliation, sessions, and authorization; do not adopt AuthKit.
- Keep generic OIDC and local Authentik login available for development,
  deterministic tests, and non-WorkOS deployments.
- Add provider-neutral external directory, user, group, membership, and mapping
  resources with typed lifecycle and synchronization state.
- Add a verified, replay-safe WorkOS Directory Sync webhook adapter that
  normalizes user, group, and membership events before applying them through
  owning Ash actions.
- Reconcile SSO and directory subjects into the same durable principal, fail
  closed on conflicts or deprovisioning, and preserve historical provenance.
- Map external groups only through explicit Office Graph role-mapping policy;
  WorkOS profile or directory attributes never become capabilities directly.
- Add a repo-owned fake WorkOS/Directory Sync adapter and contract coverage so
  normal development and CI do not require WorkOS credentials or network
  access.

## Capabilities

### New Capabilities

- `workos-enterprise-sso`: WorkOS SSO authorization-code integration without
  AuthKit, including organization selection, callback validation, and
  Office Graph-owned session issuance.
- `enterprise-directory-sync`: Provider-neutral directory users, groups,
  memberships, mappings, verified WorkOS event ingestion, lifecycle
  reconciliation, and deterministic contract testing.

### Modified Capabilities

- `human-authentication`: Distinguish local generic OIDC from configured WorkOS
  enterprise SSO while preserving one durable login and session contract.
- `external-identity-reconciliation`: Reconcile login-time WorkOS profiles and
  provisioning-time directory users into one principal and apply
  deprovisioning promptly.
- `enterprise-integration-posture`: Select WorkOS SSO and Directory Sync as the
  managed enterprise adapters while retaining the local identity lab and fake
  contract path.

## Impact

- Affects the Authentication, Identity, Authorization, Integrations, and web
  entrypoint boundaries plus their Ash resources, policies, and migrations.
- Adds WorkOS HTTP and webhook adapters behind project-owned behaviours and
  runtime configuration for API credentials, client ID, redirect URI, webhook
  secret, and Office Graph organization mappings.
- Adds WorkOS login routes and a Directory Sync webhook route; no provider
  token, authorization code, raw webhook payload, or AuthKit session becomes
  product authorization state.
- Adds generated AshPostgres migration and resource snapshots, focused
  concurrency/replay tests, and optional credentialed smoke-test seams while
  keeping canonical verification fully local.
