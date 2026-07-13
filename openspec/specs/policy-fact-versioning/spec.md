# policy-fact-versioning Specification

## Purpose
Define versioned policy facts so authorization decisions can be reconstructed.
## Requirements
### Requirement: Policy Bundle Versions
Office Graph SHALL store authorization policy rule sets as immutable bundle
versions separate from mutable authorization facts.

#### Scenario: Policy bundle version is published
- **WHEN** organization policy rules change
- **THEN** Office Graph MUST create an immutable policy bundle version with
  organization, version identity, digest, effective period, lifecycle state,
  and component policy references sufficient for later decision explanation

#### Scenario: Component policy changes
- **WHEN** organization, workspace, sensitivity, approval, integration, agent,
  autonomy, or retention policy components change
- **THEN** Office Graph MUST preserve immutable component policy versions or
  digests that can be referenced by the effective policy bundle version and by
  sensitive authorization decision records

#### Scenario: Authorization fact changes
- **WHEN** a role assignment, custom role definition, group membership,
  ownership link, manager relationship, sensitivity assignment, explicit
  grant, scope path, or agent capability changes
- **THEN** the change MUST be represented as a fact change interpreted by the
  effective policy bundle rather than as an opaque policy blob

### Requirement: Authorization Fact Version Anchors
Office Graph SHALL preserve optional fact-version anchors for sensitive
authorization decisions that need reconstructable inputs.

#### Scenario: Sensitive decision is recorded
- **WHEN** an authorization decision affects sensitive data, credentials,
  external writes, exports, grants, waivers, cross-boundary access, or approval
  gates
- **THEN** the decision MUST be able to reference the effective policy bundle
  version, relevant component policy versions or digests, and either the
  relevant fact rows directly or an authorization-fact-version anchor

#### Scenario: Historical decision is reviewed
- **WHEN** an auditor reviews an old sensitive decision
- **THEN** Office Graph MUST preserve enough policy version and fact reference
  information to explain the decision without copying a large policy or fact
  JSON blob into the decision record
