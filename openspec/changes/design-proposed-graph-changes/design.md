## Context

Office Graph retired GraphPatch as product language but kept the safety
pattern: agents and generated UI propose structured changes; validation,
authorization, approval, and domain actions decide what becomes true. This
design gives that pattern a concrete OpenSpec home.

## Goals / Non-Goals

**Goals:**

- Define the proposed change envelope.
- Define validation before approval or application.
- Define authorization and approval requirements.
- Define application through domain actions.
- Preserve normal revision, audit, operation correlation, and evidence records.

**Non-Goals:**

- No application code, migrations, API, UI, runtime, or jobs.
- No final mutation DSL syntax.
- No permission to bypass domain actions or truth-table validation.
- No replacement for work packet, run, verification, or agent-runtime designs.

## Decisions

### 1. Proposed changes are structured mutation proposals

A proposed graph change records proposer, source surface, operation kind,
target resource, intended domain action, payload, preconditions, idempotency
basis, validation state, approval state, and operation correlation. It may be
created by a human, agent, generated UI, integration, manual intake, or
provider adapter.

### 2. Validation is separate from authorization

Validation checks structural and domain readiness: operation kind is known,
target exists or creation target is allowed, payload schema is valid,
preconditions match, lifecycle transition is legal, referenced resources exist,
idempotency basis is unique or duplicate-safe, and domain constraints can be
evaluated. Authorization decides who may propose, approve, or apply.

### 3. Authorization includes actor, agent, sensitivity, and approval policy

Proposed changes evaluate proposer principal, agent principal when present,
delegator or trigger authority, work packet autonomy policy, tool or
integration scope, target resource scope, sensitivity labels, organization
policy, temporary grants, and required approval gates. High-risk changes may
remain proposed until approved even when structurally valid.

### 4. Application uses domain actions

Applying a proposed change calls the owning domain action. The domain action
writes truth tables, operation correlation, revisions, audit records,
authorization decision records, verification/evidence links, and run events as
normal. The proposed change records applied operation reference and final
result; it does not mutate truth tables by itself.

## Handoff To Other Changes

- `design-ingestion-and-integrations` may create proposed changes from manual
  or provider input.
- `design-agent-runtime` will create proposed changes from agents.
- `design-code-organization-and-boundaries` owns context/module placement.
- `design-revision-audit-soft-delete` owns revision/audit/operation outputs.
