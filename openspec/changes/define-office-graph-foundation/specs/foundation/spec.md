## ADDED Requirements

### Requirement: Company-Wide Product Frame

Office Graph SHALL be defined as an enterprise product for whole companies,
not as a software-engineering-only tool or a personal task tracker.

#### Scenario: New capability is proposed

- **WHEN** a new Office Graph capability is planned
- **THEN** the capability definition must explain how it preserves the
  department-neutral foundation or explicitly mark itself as a department pack,
  workflow projection, or integration-specific extension

#### Scenario: Engineering examples are used

- **WHEN** software engineering examples are used to drive product decisions
- **THEN** the underlying concepts must remain applicable to other departments
  such as design, marketing, social media, finance, operations, and leadership

### Requirement: Agent-Governed Work Graph Direction

Office Graph SHALL use the agent-governed company work graph as its locked MVP
direction.

#### Scenario: MVP scope is discussed

- **WHEN** MVP functionality is prioritized
- **THEN** the graph, internal agent runtime, authorization, runs, change
  proposals, and evidence-based verification must be treated as core
  infrastructure rather than optional add-ons

#### Scenario: Department packs are discussed

- **WHEN** department-specific workflows are planned
- **THEN** they must be treated as later expansion packs over shared graph
  primitives unless explicitly accepted into the first proving workflow

### Requirement: Software Proving Workflow

Office Graph SHALL use software review/fix/verification as the first deep
proving workflow while keeping the product identity company-wide.

#### Scenario: First deep workflow is selected

- **WHEN** the first detailed workflow is modeled
- **THEN** it should cover signals such as PR comments, review findings,
  commits, CI results, Sentry events, fixes, human review, and verification
  evidence

#### Scenario: Long-term native review agents are considered

- **WHEN** external PR review comments are imported
- **THEN** the design must preserve a path toward native Office Graph review
  agents that store findings, fixes, decisions, and evidence in the graph
  instead of using PR comments as the long-term data store

### Requirement: Integrate First And Native Workflow Defensibility

Office Graph SHALL integrate with existing company software while preserving a
path toward native graph-first workflows that are materially better than a thin
integration layer.

#### Scenario: Integration is added

- **WHEN** Office Graph integrates with an external tool
- **THEN** the integration must be treated as an adoption ramp, signal source,
  or action target rather than as the permanent center of the workflow

#### Scenario: High-value workflow matures

- **WHEN** a workflow proves high value through integrations
- **THEN** the product strategy should consider a native Office Graph version
  that uses cross-tool context, graph-native agents, permissions, revision
  history, and verification evidence in ways a single integrated vendor cannot
  easily reproduce

### Requirement: OpenSpec Scope Boundary

OpenSpec SHALL be the workflow for building Office Graph and SHALL NOT become
an assumed Office Graph product concept.

#### Scenario: Product requirements reference planning artifacts

- **WHEN** Office Graph product requirements are written
- **THEN** they must describe Office Graph behavior without requiring users,
  agents, or integrations to know about OpenSpec unless a future import/export
  feature explicitly adds that support

### Requirement: Locked Platform Constraints

The foundation SHALL preserve the current locked platform constraints.

#### Scenario: Backend architecture is planned

- **WHEN** backend implementation work is proposed
- **THEN** it must use Elixir, Phoenix, Ash, and Postgres as the primary
  backend stack

#### Scenario: Product UI is planned

- **WHEN** frontend implementation work is proposed
- **THEN** it must target a React frontend and must not use Phoenix LiveView
  for the product UI

#### Scenario: API surface is planned

- **WHEN** external or frontend API work is proposed
- **THEN** both GraphQL and JSON API responsibilities must be planned over the
  same domain actions and authorization boundary

### Requirement: Research References Are Non-Authoritative

The ChatGPT reference thread and generated PRD SHALL be treated as research
inputs, not as approved requirements.

#### Scenario: Reference material conflicts with locked decisions

- **WHEN** reference material conflicts with current locked decisions
- **THEN** the locked project context and accepted OpenSpec changes take
  precedence
