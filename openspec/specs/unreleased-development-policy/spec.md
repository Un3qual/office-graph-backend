# unreleased-development-policy Specification

## Purpose

Define how Office Graph treats old paths, compatibility code, and wording while
the product is unreleased.

## Requirements

### Requirement: Current Product Direction Wins Before Release
Office Graph SHALL treat current product direction as authoritative while the
product is unreleased.

#### Scenario: Old path has no current user
- **WHEN** an adapter, route, module layout, test, fixture, or document exists
  only for an old demo, migration, or old path
- **THEN** the implementation MUST delete or replace it instead of preserving it
  for compatibility

#### Scenario: Compatibility is proposed
- **WHEN** a change keeps an old path for compatibility
- **THEN** the design MUST name the current caller, current verification need,
  external contract, data-safety reason, or local development workflow that
  still requires that path

### Requirement: Current Behavior Still Needs Proof
Office Graph SHALL prove current intended behavior after deleting or replacing
old unreleased paths.

#### Scenario: Old path is removed
- **WHEN** a change deletes or replaces an old unreleased path
- **THEN** verification MUST cover the current workflow, authorization,
  validation, idempotency where applicable, data changes, and user-visible
  behavior that replace it

#### Scenario: Old test only protects removed behavior
- **WHEN** a test only proves an old adapter, response shape, or demo layout
  that no current workflow uses
- **THEN** the test MUST be deleted or rewritten around the current workflow

### Requirement: Specs Use Plain Project Words
Office Graph SHALL use plain project wording in docs and specs unless a precise
domain term is needed.

#### Scenario: Architecture shorthand hides a simple rule
- **WHEN** a spec or design uses broad architecture shorthand such as surface,
  posture, projection, durable, or seam without naming the concrete thing
- **THEN** the wording MUST be replaced with the concrete UI, API, data, file,
  workflow, or test it describes

#### Scenario: Domain term maps to current code or product behavior
- **WHEN** a term such as work packet, run, verification, evidence, GraphQL,
  JSON API, Ash, or Boundary maps to current code, database records, or accepted
  specs
- **THEN** the term MAY remain, but nearby wording MUST explain what the user or
  developer can do with it
