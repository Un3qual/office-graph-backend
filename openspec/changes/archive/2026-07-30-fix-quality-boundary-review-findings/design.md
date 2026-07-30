## Context

Organization-wide external group-role mappings are represented with
`workspace_id: nil`. Login-scope discovery already returns that organization
scope and authorization already lets it contribute inside a workspace, but
the authorized management boundary replaces explicit nil scope with the
current session workspace. Login scope selection also requires an exact
workspace match even though Office Graph sessions themselves must be
workspace-bound.

The database-boundary scanner classifies repository calls from their source
receiver spelling. It therefore recognizes `Repo` and `OfficeGraph.Repo`, but
not an explicit alias such as `Database`.

## Goals / Non-Goals

**Goals:**

- Preserve the distinction between omitted workspace scope and an explicitly
  organization-wide target in enterprise identity management.
- Require organization-scoped `enterprise_identity.manage` authority before
  creating or changing an organization-wide enterprise identity record.
- Let an organization-wide external mapping satisfy a trusted preferred
  workspace during login and subsequent session validation.
- Resolve explicit Elixir aliases before classifying repository calls.
- Prove each review finding with a focused red-green regression test.

**Non-Goals:**

- Add organization-only human sessions or remove the workspace requirement
  from existing sessions.
- Add customer-facing WorkOS configuration UI or provider provisioning.
- Add raw SQL, direct Ecto, migrations, or new database inventory exceptions.
- Build a general Elixir compiler or semantic-analysis framework inside the
  Credo check.

## Decisions

### Distinguish omitted and explicit nil management scope

Management writes will default an omitted `workspace_id` to the current
session workspace but preserve an explicitly supplied nil. Authorization and
record lookup will use that resolved target scope. Organization-wide lifecycle
updates will likewise require the caller to name `workspace_id: nil`, avoiding
an ambiguous lookup and ensuring the organization-scoped capability check runs
before persistence.

Alternative considered: allow every workspace administrator to manage nil
scope. Rejected because an organization-wide mapping affects authorization in
every workspace and therefore requires organization-scoped authority.

### Expand organization scope only into a trusted preferred workspace

Login scope selection will continue returning the exact preferred workspace
when an exact mapping exists. If not, an organization-wide scope for the same
organization may satisfy that preferred workspace. The preferred workspace is
server-owned configuration or the transaction-bound enterprise connection,
and session persistence retains the composite organization/workspace foreign
key.

Alternative considered: issue a nil-workspace human session. Rejected because
the session model and downstream product surfaces are intentionally
workspace-bound.

### Resolve explicit aliases before call classification

The scanner will collect explicit aliases for the database receiver modules
that it enforces and classify calls using the resolved receiver name. The
scanner remains syntax-only, deterministic, non-mutating, and independent of
compiling the inspected source.

Alternative considered: treat every `query` or `query!` receiver as raw SQL.
Rejected because unrelated modules may expose those function names and would
create false-positive policy failures.

## Risks / Trade-offs

- [An organization-wide mapping is managed from a workspace-bound session] →
  Require a separate organization-scoped capability assignment and an
  explicit nil target.
- [An inherited login scope names a mismatched workspace] → Retain the
  database-enforced organization/workspace relationship when the session is
  persisted.
- [Alias collection does not implement every possible macro-generated alias] →
  Cover ordinary `alias ... as:` syntax now and keep the scanner conservative;
  macro-generated database access remains prohibited by architecture
  conformance and review.
