## Context

Office Graph has backend contracts for the first operator workflow: manual
intake appears in an operator inbox, item detail exposes triage and graph
state, packet readiness explains whether work can start, run state tracks
packet-backed execution, and verification outcome closes the loop. The project
has no frontend app yet. The fixed product direction requires React from day
one and forbids Phoenix LiveView for the product UI.

The existing Phoenix app already serves JSON APIs and static assets. This
change should add the first operator-facing frontend without changing the
backend workflow model unless the UI exposes a concrete API gap.

## Goals / Non-Goals

**Goals:**
- Mount a React operator console from the Phoenix app.
- Let an operator inspect inbox rows, select an item, review actionability
  status, see packet readiness, inspect run state, and check verification
  outcome from the existing JSON API.
- Add a minimal frontend build and test path that runs inside the project Nix
  shell and can be wired into project verification.
- Keep the first console implementation accessible, responsive, and usable as
  a product surface rather than a marketing or documentation page.

**Non-Goals:**
- No Phoenix LiveView product UI.
- No full graph canvas, arbitrary graph editor, workflow builder, mobile app,
  collaborative rich text, provider webhook ingestion, or generic ordered
  placement behavior.
- No GraphQL client in the first console unless the JSON API proves
  insufficient for an accepted requirement.
- No durable frontend-only source of truth; backend workflow projections remain
  authoritative.

## Decisions

### Use a Phoenix-served React SPA

The operator console will be a React single-page app whose compiled assets are
served by Phoenix. Phoenix remains responsible for routing the app shell and
serving static asset digests; React owns product UI state after mount.

Alternatives considered:
- LiveView: rejected because project direction forbids LiveView for product UI.
- Separate frontend service: rejected for this slice because it would add
  deployment and local-run complexity before the product surface exists.
- Static hand-written JavaScript: rejected because React is the locked
  frontend stack and the console needs reusable components and stateful views.

### Use the JSON operator workflow API first

The frontend will consume `/api/operator-workflow/*` endpoints directly through
a small typed API client. The UI should reflect the shared projection contract
without duplicating domain rules client-side.

Alternatives considered:
- GraphQL client first: deferred because the archived operator workflow already
  provides JSON endpoints for the exact first screens, and a GraphQL client
  would add dependency and schema workflow before it is necessary.
- Client-side mock-only screens: rejected because the first console must prove
  the backend workflow is operable through real contracts.

### Build an operational workbench, not a landing page

The first screen will be a compact workbench with an inbox/list region, a
selected item detail region, and focused panes for packet readiness, run state,
and verification outcome. The visual system should be quiet, dense enough for
repeated use, and tailored to triage and verification rather than promotional
positioning.

Alternatives considered:
- Multi-page navigation: deferred until there are more product surfaces.
- Card-heavy overview dashboard: rejected because the operator's primary job
  is scanning actionable rows and closing a specific workflow loop.

### Add lightweight frontend verification

The implementation should include frontend unit/component tests for loading,
empty, error, inbox selection, readiness, run, and verification states. Phoenix
tests should cover serving the app shell. Build output should be reproducible
from the project Nix shell.

Alternatives considered:
- Browser-only manual QA: rejected because this creates the first frontend
  foundation and needs regression coverage.
- End-to-end browser tests first: useful later, but unit/component coverage
  plus Phoenix app-shell tests are enough for this initial slice.

## Risks / Trade-offs

- Frontend dependency footprint grows from zero to a real toolchain →
  Mitigation: keep dependencies minimal and aligned with Node from the project
  flake.
- Backend API shapes may be convenient for tests but awkward for operators →
  Mitigation: consume existing projections first and only add backend fields
  when a concrete UI requirement exposes a contract gap.
- The first UI could drift into broad platform navigation → Mitigation: keep
  the route and navigation scoped to the operator workflow loop and explicitly
  defer other surfaces.
- Visual design approval is needed before high-fidelity implementation →
  Mitigation: generate or capture a full primary-screen concept before coding
  the React surface, then implement from that design system rather than
  improvising a generic dashboard.

## Migration Plan

1. Add the frontend source tree and build configuration without changing
   existing API routes.
2. Add Phoenix app-shell routing/static serving for the compiled React assets.
3. Build the console against existing operator workflow endpoints.
4. Wire frontend build/test checks into the project verification path.
5. Rollback by removing the app-shell route and frontend assets; backend
   workflow APIs remain unchanged.

## Open Questions

- Whether the console should mount at `/` or `/operator` for the first
  implementation. The implementation should choose the route that best fits
  Phoenix routing and leaves room for future product surfaces.
- Whether frontend verification should be added to `mix verify` immediately or
  exposed as a separate script first. The implementation should prefer one
  command for local confidence if dependency installation remains reasonable.
