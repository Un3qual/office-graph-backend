# OpenSpec Product-Boundary Correction Design

## Status

Approved in conversation on 2026-07-23 after closing PR #30, which had made
OpenSpec and the Office Graph source checkout production runtime dependencies.

## Problem

`openspec/project.md` fixes OpenSpec's role as the development workflow used to
build Office Graph. It is not an Office Graph product feature.

The internal-agent-runtime change contradicts that boundary by defining the
first product agent as `openspec-review`. Merged foundation code installs and
binds that definition, grants `openspec.read`, and exposes OpenSpec-specific
operator copy. Closed PR #30 extended the mistake into local repository and
OpenSpec tool adapters, release configuration, and startup readiness.

The generic internal agent runtime remains required. It already supports a
governed, run-linked model step over authorized Office Graph context, routes
validated output through owning domains, and exposes bounded operator controls.
The correction must preserve those product capabilities without retaining an
OpenSpec-shaped compatibility layer.

## Fixed Constraints

- OpenSpec remains available in the Nix development shell and under
  `openspec/` as the specification and delivery workflow.
- Production Office Graph code must not invoke OpenSpec, read `openspec/`
  artifacts, mount the Office Graph source checkout, or require the OpenSpec
  CLI.
- The first canonical product agent must consume Office Graph run, work packet,
  graph, conversation, check, and evidence context through existing authorized
  projections.
- Initial agent output remains proposal-first and cannot directly mutate
  business state, perform external writes, or complete verification.
- The product is unreleased. Current direction wins over compatibility with the
  invalid `openspec-review` definition; no alias or fallback should preserve
  that product language.
- Existing generic runtime, authority, approval, context-expansion,
  conversation, retry, audit, and provenance behavior remains in scope.

## Considered Approaches

### 1. Close PR #30 only

This prevents the local checkout and OpenSpec CLI from becoming production
dependencies, but leaves the merged `openspec-review` definition, binding API,
capability, operator copy, and migration assertions in the product. It does not
restore the fixed architecture boundary.

Rejected.

### 2. Rename the existing agent while retaining repository/OpenSpec concepts

This would hide the coupling behind generic names while keeping a source-tree
review workflow in the product. It would also turn a semantic correction into a
compatibility migration for an unreleased and invalid feature.

Rejected.

### 3. Replace the invalid definition with a product-native run-review agent

The canonical `run-review` agent uses the existing deterministic model adapter
and the authorized Office Graph context package already assembled for the
selected run and graph item. It has no tool allowlist and requests only the
capabilities needed to invoke the model and route proposal/evidence output.
Operator affordances describe reviewing the selected Office Graph run context.

Selected. This preserves the justified runtime while removing every product
dependency on OpenSpec or the local source checkout.

## Architecture

### Development-only OpenSpec

Keep:

- `openspec/project.md`, durable specs, active changes, and archived changes.
- The OpenSpec package in the development Nix shell.
- OpenSpec validation in the repository verification gate.
- Documentation that describes OpenSpec as the project workflow.

Remove or forbid:

- Production OpenSpec adapters, runtime configuration, executable lookup,
  readiness supervisors, telemetry wrappers, or source-checkout mounts.
- Agent capabilities, definitions, UI copy, fixtures, or product records named
  after OpenSpec.

### Canonical Product Agent

Replace the canonical definition key `openspec-review` with `run-review`.

The definition:

- uses the existing deterministic model adapter for normal verification;
- supports human and automatic run-linked invocation;
- receives authorized context through the existing immutable context package;
- has an empty tool allowlist;
- requests `agent.invoke`, `agent.model.generate`, `proposal.create`, and
  `evidence.suggest`;
- allows only the existing proposal-first output classifications;
- keeps the existing bounded autonomy posture.

The binding command becomes `bind_run_review_agent/2`. It provisions only the
runtime, skeleton-read, model-generation, proposal, and evidence capabilities
required by the definition.

The operator projection selects the active `run-review` binding and presents
product-native copy:

- unavailable: no approved run-review agent is bound;
- action: review the selected run context;
- default outcome: review the selected run, work packet, graph context, checks,
  and evidence, then propose bounded follow-up work.

### Persistence And Migration History

Because Office Graph is unreleased, revise the existing agent-runtime
migrations so a fresh database has never contained an OpenSpec product
definition:

- install `run-review` in the foundation migration;
- update later definition-specific backfills to target `run-review`;
- remove `openspec.read` from delegation-capability backfills;
- keep generic `repository.read` only where it is independently exercised as a
  provider-neutral capability, not as local source-checkout access.

Do not add an `openspec-review` alias, compatibility binding, fallback lookup,
or runtime data migration. Local development databases created from the invalid
migration history must be reset, consistent with the unreleased-project policy.

### OpenSpec Artifact Correction

Update `implement-internal-agent-runtime` so its proposal, design, delta specs,
and task list describe:

- a product-native run-review agent;
- authorized Office Graph context rather than repository/OpenSpec context;
- no release-time repository tooling or OpenSpec readiness contract;
- verification of the tool-free first automatic workflow.

Previously checked tasks that named OpenSpec must be rewritten to describe the
actual delivered generic or run-review behavior. Verification and archive tasks
remain pending until the corrected implementation passes the full gate.

## Data Flow

1. An operator or declared system trigger selects an active run, graph item, and
   bound `run-review` definition.
2. AgentRuntime validates binding, scope, trigger or delegator authority, and
   creates the immutable authority snapshot.
3. The context package assembler records authorized Office Graph references and
   redaction rationale.
4. The existing durable worker invokes the deterministic or configured model
   adapter for `model:review`.
5. Validated output routes through conversation, proposal, observation, or
   evidence-candidate owners.
6. The run timeline and focused operator surface expose only bounded product
   state and safe provenance.

No step reads the Office Graph repository, invokes Git, invokes OpenSpec, or
loads a local planning artifact.

## Failure And Authorization Behavior

- Missing or inactive run-review binding fails closed before invocation.
- Requested authority is intersected with the agent principal and, for human
  invocation, the delegator.
- Mutable grants, adapter registration, approvals, and context-expansion
  decisions continue to be revalidated before execution.
- Adapter and storage failures retain the existing bounded retry or terminal
  classification.
- An output outside the definition allowlist or authority snapshot is rejected
  before an owning-domain effect.

## Testing

Use behavior tests rather than source-string assertions:

1. Migration tests prove the canonical definition is `run-review`, has no tool
   allowlist, and contains no `openspec.read` capability.
2. Binding tests prove `bind_run_review_agent/2` is scoped, authorized,
   idempotent, and provisions only required capabilities.
3. Invocation and authority tests use product-native requested outcomes and
   capability sets.
4. Conversation/API projection tests prove product-native affordance copy and
   the absence of an OpenSpec-specific invocation target.
5. Repository-wide searches prove OpenSpec remains only in planning,
   development-tooling, architecture-validation, and test-support paths—not in
   production product modules, runtime configuration, or product migrations.
6. Focused agent-runtime, conversation, API, migration, and architecture tests
   pass before the full Nix-backed `mix verify` gate.
7. Strict OpenSpec validation and `git diff --check` pass before publication.

## Completion Criteria

- PR #30 remains closed.
- No production Office Graph module, runtime config, product migration, agent
  definition, capability, copy, or fixture treats OpenSpec as a product
  feature.
- The canonical `run-review` agent is run-linked, tool-free, product-native,
  proposal-first, and covered by behavior tests.
- The active OpenSpec change agrees with `openspec/project.md`.
- Focused verification, full `mix verify`, strict OpenSpec validation, and
  `git diff --check` all pass.
