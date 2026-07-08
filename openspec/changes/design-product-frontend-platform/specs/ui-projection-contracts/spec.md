## ADDED Requirements

### Requirement: UI Projection Contracts Support Relay
Office Graph SHALL shape product UI projection contracts so they can be consumed
through Relay without a parallel JSON adapter or route-specific transport
workaround.

#### Scenario: Product route consumes projection through Relay
- **WHEN** a product route consumes a projection through Relay
- **THEN** the projection contract MUST define stable GraphQL object identity,
  pagination shape, fragment-safe field ownership, redaction behavior, and
  invalidation or update semantics that allow Relay components to declare data
  dependencies without reading hidden transport fields

#### Scenario: Projection object has stable identity
- **WHEN** a product projection object has a stable product identity
- **THEN** the GraphQL object MUST expose an opaque Relay Node `id`, and raw
  database identifiers MUST remain in explicit compatibility, trace, or command
  input fields only when the UI has a current need for them

#### Scenario: Projection list can grow
- **WHEN** a product projection field returns a list that can grow with rows,
  graph links, runs, checks, evidence, observations, or integration records
- **THEN** the GraphQL field MUST expose Relay-style connection pagination with
  `edges`, edge cursors, and `pageInfo` rather than a route-specific rows/cursor
  object shape

#### Scenario: GraphQL client model changes
- **WHEN** an accepted change replaces Relay as the product GraphQL client model
- **THEN** the projection contract MUST be updated in OpenSpec before route
  implementation changes so components do not drift across incompatible
  GraphQL data ownership patterns

## MODIFIED Requirements

### Requirement: UI Data Exposes Product Meaning

Office Graph SHALL expose product meaning in frontend-facing data rather than
raw infrastructure mechanics.

#### Scenario: Projection includes mixed workflow records

- **WHEN** a projection includes Signals, Work Items, Work Packets, Runs,
  Checks, Evidence, Verification state, observations, graph items, or audit
  traces
- **THEN** the frontend data MUST present named product fields for the default
  UI and place infrastructure details behind explicit trace, debug, or audit
  fields

#### Scenario: UI needs to render command affordances

- **WHEN** the frontend renders available commands, disabled commands,
  navigation affordances, readiness, blockers, or verification state
- **THEN** the projection MUST provide normalized command and affordance fields
  and MUST NOT require the UI to infer domain meaning from raw `type` strings,
  relationship names, role names, status strings, or private resource state

### Requirement: Allowed Commands Come From Backend Reads

Office Graph SHALL provide allowed commands and UI affordances through backend
reads when the UI needs to start, continue, or explain workflow commands.

#### Scenario: UI renders packet readiness or run-start command

- **WHEN** an operator-facing UI needs to prepare a packet, start a run, accept
  evidence, or complete verification
- **THEN** the backend read MUST provide the required command, stable input
  shape, affordance state, blocker reasons, and safe explanation rather than
  requiring the frontend to assemble domain command input from graph links

#### Scenario: Command input cannot be projected

- **WHEN** a command input requires operator-authored fields or local form state
- **THEN** the backend read MUST still provide allowed commands, required
  fields, defaults, validation hints, target identities, safe disabled or
  hidden state, and safe explanations so the frontend does not reconstruct
  domain relationships from raw projection internals

#### Scenario: Revealing an affordance would leak policy-sensitive information

- **WHEN** showing a command, navigation target, disabled state, or explanation
  would reveal restricted resource existence, sensitive capability structure,
  or policy internals
- **THEN** the backend projection MUST mark the affordance hidden or redacted
  with a safe reason code rather than making the frontend infer secrecy rules
