## 1. Run Index Projection

- [x] 1.1 Add a focused `OfficeGraph.Projections` work-run index read that resolves the existing session scope and skeleton-read capability before returning only safe summary fields.
- [x] 1.2 Implement newest-first `(inserted_at DESC, id DESC)` keyset pagination, opaque cursor encoding/decoding, existing safe validation errors, and bounded packet/packet-version joins.
- [x] 1.3 Add projection coverage for organization/workspace isolation, authorization denial, invalid input, stable forward pagination across inserts, summary field safety, and constant query count as list size grows.

## 2. GraphQL Run Connection

- [x] 2.1 Add `OperatorRunSummary` and the read-only `operatorRuns(first:, after:)` Relay connection using the existing operator connection conventions.
- [x] 2.2 Add GraphQL and Relay-generation coverage for connection shape, cursor paging, invalid input, authorized scope filtering, unchanged `operatorRunState` detail behavior, and unchanged shared `RequestSession` resolution without route-specific session fallback.

## 3. All Runs Route

- [x] 3.1 Create the route-owned `assets/app/routes/runs/` package, read-only Relay documents, canonical `/runs` registration with no alias/compatibility route or query, and global stylesheet integration without Tailwind or a route-specific UI framework.
- [x] 3.2 Implement the run list, default selection only when `runId` is absent, authoritative detail for every present `?runId=<id>` selection (including off-page and unavailable ids), detail summary, first bounded activity page, and explicit list/activity load-more behavior.
- [x] 3.3 Implement empty, loading, list-error, detail-error, paging-error, retry, and stale-detail-clearing states without a second client-side run source of truth.
- [x] 3.4 Add route coverage for visible and off-page URL selections, present invalid/missing/forbidden/stale values that never default, selection URL updates, activity/list pagination, safe product fields, canonical route/session behavior, and route/import/style architecture boundaries that prohibit Tailwind and a route-specific UI framework.

## 4. Navigation And Packet Context

- [x] 4.1 Enable the `All Runs` product-navigation destination while retaining disabled `Entities` and `Reports`, and cover the app-shell and navigation states.
- [x] 4.2 Add packet-route `?packetId=<id>` selection that defaults only when the parameter is absent, authoritatively resolves every present value, safely preserves unavailable selections without fallback, and covers URL updates, shared-session behavior, deep links, existing list/detail/paging, and command ownership.
- [x] 4.3 Add `/runs` packet and operator links to `/packets?packetId=<id>` and `/operator?runId=<id>`, and verify the all-runs route introduces no mutation or duplicated command owner.

## 5. Verification

- [x] 5.1 Run strict OpenSpec validation through the project Nix flake.
- [x] 5.2 Run focused backend, GraphQL, Relay-generation, route, architecture, and query-bound tests through the project Nix flake for the new projection and product surfaces.
- [x] 5.3 Run every final verification command through the project Nix flake: typecheck, frontend test suite, production frontend build, `git diff --check`, and `mix verify`; resolve regressions before archiving the completed change.
