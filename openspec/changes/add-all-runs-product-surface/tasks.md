## 1. Run Index Projection

- [ ] 1.1 Add a focused `OfficeGraph.Projections` work-run index read that resolves the existing session scope and skeleton-read capability before returning only safe summary fields.
- [ ] 1.2 Implement newest-first `(inserted_at DESC, id DESC)` keyset pagination, opaque cursor encoding/decoding, existing safe validation errors, and bounded packet/packet-version joins.
- [ ] 1.3 Add projection coverage for organization/workspace isolation, authorization denial, invalid input, stable forward pagination across inserts, summary field safety, and constant query count as list size grows.

## 2. GraphQL Run Connection

- [ ] 2.1 Add `OperatorRunSummary` and the read-only `operatorRuns(first:, after:)` Relay connection using the existing operator connection conventions.
- [ ] 2.2 Add GraphQL and Relay-generation coverage for connection shape, cursor paging, invalid input, authorized scope filtering, and unchanged `operatorRunState` detail behavior.

## 3. All Runs Route

- [ ] 3.1 Create the route-owned `assets/app/routes/runs/` package, read-only Relay documents, route registration, and global stylesheet integration for `/runs`.
- [ ] 3.2 Implement the run list, default and `?runId=<id>` selection, detail summary, first bounded activity page, and explicit list/activity load-more behavior.
- [ ] 3.3 Implement empty, loading, list-error, detail-error, paging-error, retry, and stale-detail-clearing states without a second client-side run source of truth.
- [ ] 3.4 Add route coverage for visible and off-page URL selections, safe missing/forbidden selection behavior, selection URL updates, activity/list pagination, safe product fields, and route/import/style boundaries.

## 4. Navigation And Packet Context

- [ ] 4.1 Enable the `All Runs` product-navigation destination while retaining disabled `Entities` and `Reports`, and cover the app-shell and navigation states.
- [ ] 4.2 Add packet-route `?packetId=<id>` selection, safe unavailable handling, URL updates, and deep-link coverage while preserving existing packet list, detail, paging, and command ownership.
- [ ] 4.3 Add `/runs` packet and operator links to `/packets?packetId=<id>` and `/operator?runId=<id>`, and verify the all-runs route introduces no mutation or duplicated command owner.

## 5. Verification

- [ ] 5.1 Run strict OpenSpec validation from the project Nix shell.
- [ ] 5.2 Run focused backend, GraphQL, Relay-generation, route, architecture, and query-bound tests for the new projection and product surfaces.
- [ ] 5.3 Run the project Nix-shell typecheck, frontend test suite, production frontend build, `git diff --check`, and `mix verify`; resolve regressions before archiving the completed change.
