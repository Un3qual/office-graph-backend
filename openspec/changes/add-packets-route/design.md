## Context

Office Graph now has a Phoenix-served React Router Framework Mode application,
a shared Relay environment, and generated Relay-compatible `listWorkPackets`
and `getWorkPacket` fields. The only configured product route is `/operator`,
whose navigation still renders unavailable buttons instead of real route
destinations. The packet route is the smallest next screen because packets are
central to the product's verified-completion loop and their list contract is
already available without backend expansion.

Constraints:

- React Router Framework Mode remains the route owner and Phoenix serves the
  SPA build.
- Relay owns product GraphQL server state; no TanStack Query or JSON adapter is
  introduced.
- Tailwind, Tailwind-dependent libraries, and LiveView product UI remain
  forbidden.
- Shared UI stays shallow, generic, and product-vocabulary-free.
- The first packet route is read-only and reuses current generated GraphQL
  fields.

## Goals / Non-Goals

**Goals:**

- Prove the frontend platform with a second route at `/packets`.
- Make product navigation use accessible client-side route links for available
  destinations and disabled controls for unavailable destinations.
- Load packet rows through the generated Relay connection with explicit
  loading, empty, error, loaded, next-page, and previous-page states.
- Keep packet selection local to the route and show a dense, readable summary
  of the selected packet.
- Preserve the existing `/operator` behavior and visual language.

**Non-Goals:**

- Do not add packet mutations, packet creation forms, run controls, version
  editing, search, filters, realtime updates, or URL-persisted selection.
- Do not add a custom packet projection, a new backend field, or a JSON API
  frontend adapter.
- Do not redesign the product shell, introduce a component library, or add a
  motion dependency.

## Decisions

### 1. Reuse the generated packet Relay connection

The route will own a `PacketsRouteQuery` over `listWorkPackets(first, after)`
and a packet fragment for the fields already exposed by `WorkPacket`: Relay
`id`, title, state, current version identity, operation identity, and update
time. A route-local hook will use the existing Relay environment and the same
observable cleanup pattern as the operator route.

This is preferred over a custom packet-workspace projection because the first
screen needs only stable packet summary fields. A custom projection would add
backend ownership and tests before the UI proves a missing contract.

### 2. Keep navigation generic and route-aware

`NavRail` will accept generic destination descriptors and render available
destinations with React Router `NavLink`, deriving active state from the
router. Unavailable destinations remain disabled buttons. Product labels and
paths stay in route-owned layout code, so the shared primitive contains no
packet or operator vocabulary.

A shallow generic workspace shell may own the repeated brand, navigation,
header, and main-content frame. `OperatorLayout` and the packet route will
provide product-specific titles and content through props. This avoids copying
the entire app shell while preserving route ownership of product behavior.

### 3. Use route-local packet selection and cursor history

The first packet on a loaded page becomes selected when there is no current
selection. Selecting another row updates local React state. When pagination
moves the route to a page that does not contain the selected packet, selection
moves to that page's first packet. A route-local cursor stack enables previous
navigation without inventing global client state or URL semantics.

### 4. Preserve the existing operational visual system

Visual thesis: a calm, dense operational workspace using the existing neutral
surfaces, typography, and single blue active-state accent.

Content plan: persistent product navigation, a packet queue with pagination,
and one selected-packet detail region. The screen starts with working data and
status rather than marketing copy or dashboard cards.

Interaction thesis: route-link active state, immediate selected-row feedback,
and restrained pagination state changes. No ornamental entrance or scroll
motion is added because it would not improve operation or scanning.

### 5. Verify the route at every existing boundary

Tests will cover generic navigation semantics, route-owned import boundaries,
Relay document compilation, loading/empty/error/selection/pagination states,
route registration, and Phoenix app-shell serving for `/packets`. The existing
frontend `verify` command and project `mix verify` remain the reproducible
gates.

## Risks / Trade-offs

- **The generated packet type exposes only summary fields** -> Keep the first
  route intentionally read-only and summary-focused; propose a backend
  projection only when a concrete screen need is demonstrated.
- **Router-aware shared navigation adds a React Router dependency to shared
  UI** -> Depend only on the public generic `NavLink` API and protect the
  boundary from route modules, Relay, and product vocabulary with tests.
- **Cursor history is session-local** -> Accept reset-on-reload behavior for
  this first route; URL pagination is outside the approved scope.
- **A generic shell can become over-abstracted** -> Limit it to existing
  repeated shell structure and generic slots; keep packet layout and mapping in
  the route folder.

## Migration Plan

1. Make the existing navigation and shell route-aware while keeping
   `/operator` behavior unchanged.
2. Add and compile the route-owned packet Relay documents and hook.
3. Register `/packets`, add the packet workspace UI, and expand app-shell
   verification.

Rollback removes the `/packets` route and its navigation destination while
leaving `/operator` and the existing Phoenix SPA shell intact.

## Open Questions

None. Packet mutations, richer version data, URL selection, and realtime
invalidation require later accepted changes if product evidence justifies them.
