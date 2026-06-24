## 1. Review And Acceptance

- [x] 1.1 Confirm this change is design-only and does not start Phoenix, Ash,
  Ecto, migration, API, frontend, Oban, integration, or agent-runtime code.
- [x] 1.2 Confirm this change owns concrete identity and authorization schema
  inventory while `design-enterprise-governance` owns policy semantics.
- [x] 1.3 Confirm authentication mechanics are deferred to
  `design-identity-and-authentication`.
- [x] 1.4 Confirm `design-persistence-model` references this inventory rather
  than duplicating every identity and authorization table family.

## 2. Capability Spec Review

- [x] 2.1 Review `identity-authorization-inventory` requirements for table
  families and schema ownership.
- [x] 2.2 Review `scope-hierarchy-storage` requirements for adjacency list,
  closure table, scope moves, and explanation invalidation.
- [x] 2.3 Review `principal-role-capability-model` requirements for principals,
  profiles, roles, capabilities, assignments, groups, teams, and grants.
- [x] 2.4 Review `policy-fact-versioning` requirements for policy bundle
  versions and fact-version anchors.
- [x] 2.5 Review `credential-metadata-model` requirements for secret-free
  credential metadata and lifecycle.

## 3. Follow-On Planning Work

- [x] 3.1 Feed accepted principal, profile, external identity, scope, role,
  capability, grant, group, team, and credential inventory into first migration
  planning after the implementation-readiness gate is satisfied.
- [x] 3.2 Feed scope hierarchy and scope move semantics into authorization,
  audit, revision, and graph projection implementation plans.
- [x] 3.3 Feed sensitivity label separation into the enterprise governance and
  persistence cleanup tasks.
- [x] 3.4 Coordinate with `design-identity-and-authentication` on how login,
  sessions, external identity reconciliation, service accounts, and agents
  create or use `principal_id` and `credential_metadata` records.

## 4. Validation

- [x] 4.1 Run `openspec validate design-identity-and-authorization-schema
  --strict`.
- [x] 4.2 Run `openspec validate --changes --strict`.
- [x] 4.3 Fix any schema, delta, task-formatting, or validation issues
  reported by OpenSpec.
