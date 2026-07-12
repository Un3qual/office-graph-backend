# boundary-enforcement Specification

## Purpose
Define compile-time boundary declarations and dependency enforcement across bounded contexts.
## Requirements
### Requirement: Boundary Definitions
The codebase SHALL use the Boundary library to define bounded contexts,
exports, dependencies, and private implementation modules once application code
exists.

#### Scenario: A context is implemented
- **WHEN** a bounded context receives its first production modules
- **THEN** it has a Boundary definition or is covered by a parent Boundary
  definition with explicit exports

#### Scenario: A public interface is added
- **WHEN** a module is intended for cross-context use
- **THEN** it is exported by the owning Boundary definition

### Requirement: Private Module Protection
Private implementation modules MUST NOT be imported by peer contexts unless
explicitly exported, including modules for resource internals, Ecto query
details, provider adapter details, policy internals, revision internals, audit
storage, or raw archive storage.

#### Scenario: A peer context calls a private module
- **WHEN** Boundary checks find a call from one context to a non-exported module
  in another context
- **THEN** the implementation must move the behavior behind an exported public
  API, shared behaviour, or event contract

#### Scenario: A provider adapter exposes internals
- **WHEN** a provider-specific adapter needs to make synchronized data
  available
- **THEN** it exports provider-neutral sync results or context APIs rather than
  provider-private table or client modules

### Requirement: Boundary Verification
Boundary checks SHALL be part of the normal verification path before a backend
change is considered complete.

#### Scenario: Backend CI is defined
- **WHEN** CI or release checks are introduced for backend code
- **THEN** Boundary validation is included with compilation, formatting, tests,
  and OpenSpec validation

#### Scenario: First app shell exists
- **WHEN** the first Phoenix app shell exists
- **THEN** coarse Boundary contexts MUST be defined and Boundary validation
  MUST run in local verification and CI before backend work is considered
  complete

#### Scenario: Boundary validation fails
- **WHEN** a Boundary rule fails in local verification or CI
- **THEN** the change is not considered complete until the dependency rule is
  fixed or the boundary export is intentionally updated

### Requirement: Test Boundary Discipline
Tests SHALL exercise public context contracts by default and SHALL use private
test helpers only inside the owning context.

#### Scenario: A cross-context integration test is added
- **WHEN** a test spans multiple bounded contexts
- **THEN** it calls public APIs or approved fixtures rather than private
  resource internals

#### Scenario: A context-specific unit test is added
- **WHEN** a test targets private implementation details within one context
- **THEN** the test lives with that context's test area and does not become a
  shared test dependency
