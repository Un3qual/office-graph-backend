## Context

The completed quality-boundary work moved generated GraphQL reads, enterprise
identity, and authentication evidence onto Ash-owned contracts. A local review
found six narrow mismatches between those accepted contracts and their current
implementation. The fixes span three boundaries but require no new dependency,
table, route, or architectural layer.

## Goals / Non-Goals

**Goals:**

- Restore root Relay refetch for every generated resource exposed by the
  schema.
- Make organization-wide external group mappings behave like organization-wide
  direct role assignments.
- Reject malformed present directory fields at the normalization boundary.
- Preserve external identity ownership and deterministic conflict evidence.
- Bound authentication lifecycle evidence to its supported vocabulary.
- Prove each fix with behavior-level regression tests.

**Non-Goals:**

- Implement CodeRabbit suggestions that were false positives or optional
  refactors.
- Change WorkOS provider error taxonomy, Oban recovery policy, HTTP streaming,
  or authentication-event visibility.
- Add migrations, raw SQL, dependencies, or a generic reconciliation helper.

## Decisions

### Extend the existing generated node domain registry

`NodeResolver` will include the same generated-resource domains already
registered by the GraphQL schema. This keeps AshGraphql responsible for
resource loading and avoids adding manual node resolvers.

Alternative considered: add custom node clauses for the two missing resources.
That would duplicate AshGraphql behavior and violate the generated API
boundary.

### Match external mapping inheritance to direct role inheritance

An active mapping with `workspace_id: nil` will contribute an organization-only
login scope and will satisfy authorization in any workspace inside that
organization. A workspace-specific mapping remains limited to that workspace.

Alternative considered: require a mapping per workspace. That contradicts the
existing meaning of an organization-scoped role assignment and the optional
workspace relationship on the mapping resource.

### Make malformed present values different from absent values

WorkOS directory normalization will return tagged optional-field results so
`nil` remains accepted, valid strings remain normalized, and malformed,
blank, or over-limit present values reject the delivery.

Alternative considered: continue dropping invalid optional values. That hides
provider contract violations and makes malformed input indistinguishable from
absence.

### Keep identity ownership out of lifecycle transitions

The lifecycle action will no longer accept `principal_id`. Principal selection
remains the responsibility of reconciliation actions and the existing lock
order. The incompatible-link/no-principal case will return the specific
verified-identifier conflict reason.

Alternative considered: validate that a submitted `principal_id` is unchanged.
Not accepting the field is smaller and removes an unnecessary mutation path.

### Validate authentication evidence at the resource boundary

The authentication event create action will validate the supported event and
result values alongside its existing bounded reason validation.

Alternative considered: rely on current callers. Resource-level validation
keeps future internal callers from persisting unrecognized evidence.

## Risks / Trade-offs

- [Organization-wide mappings may expose previously omitted legitimate
  authority] → Match the already-established direct-role inheritance rule and
  cover both organization-only and workspace authorization explicitly.
- [Stricter directory normalization rejects payloads previously accepted after
  data loss] → Reject only present invalid optional fields; absent fields remain
  valid.
- [New validation reveals unsupported internal event producers] → Inventory
  current producer values in tests and run the full canonical gate.
