## ADDED Requirements

### Requirement: Managed enterprise identity uses WorkOS adapters without AuthKit

Office Graph SHALL use WorkOS standalone SSO and Directory Sync as its managed
enterprise identity adapters while retaining Office Graph ownership of
principals, sessions, authorization, lifecycle policy, and audit evidence.

#### Scenario: Enterprise customer configures managed SSO

- **WHEN** an Office Graph organization is bound to a WorkOS organization
- **THEN** WorkOS MUST provide the external SSO connection and normalized
  profile exchange while Office Graph MUST own account linking, scope
  selection, session issuance, authorization, and logout revocation

#### Scenario: Enterprise customer configures managed provisioning

- **WHEN** a WorkOS directory is bound to the enterprise connection
- **THEN** WorkOS Directory Sync MUST provide normalized signed lifecycle
  events while Office Graph MUST own typed directory state, identity
  reconciliation, group-to-role mapping, deprovisioning effects, and audit
  provenance

#### Scenario: AuthKit is considered

- **WHEN** implementation chooses the WorkOS integration surface
- **THEN** it MUST NOT use AuthKit, WorkOS-hosted user sessions, or WorkOS
  authorization as the Office Graph authentication or permission authority

### Requirement: Managed adapters preserve the local identity lab

Office Graph SHALL keep local Authentik OIDC and deterministic fake directory
coverage independent of the managed WorkOS integration.

#### Scenario: Developer works without hosted credentials

- **WHEN** a developer or CI environment has no WorkOS account or credentials
- **THEN** it MUST still be able to test OIDC login, directory lifecycle,
  deprovisioning, group mapping, SSO reconciliation, replay, and conflict
  behavior through local and fake adapters

#### Scenario: WorkOS compatibility needs confirmation

- **WHEN** a release team runs a credentialed WorkOS sandbox smoke test
- **THEN** that optional check MUST exercise the same adapter contracts without
  becoming a prerequisite for normal development or canonical verification
