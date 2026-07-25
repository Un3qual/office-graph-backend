## Why

The product-native runtime and All Runs branch accumulated compatibility code,
test-only static-analysis machinery, duplicated planning records, and frontend
state that exceed the current unreleased product requirements. Simplifying
those paths now reduces maintenance without weakening authorization,
concurrency, pagination, recovery, or current user behavior.

## What Changes

- **BREAKING** Remove the unsupported forward upgrade from the legacy
  `openspec-review` database definition; fresh databases retain only the
  canonical `run-review` definition and affected local databases must reset.
- Replace the route-specific static analyzer and its synthetic self-tests with
  direct checks of the repository's actual route, imports, generated artifacts,
  styles, and dependencies.
- Make packet and run URLs the durable selection authority, remove hidden
  origin state, and reduce the run transition guard to one pending id.
- Narrow the run list and detail GraphQL documents to fields rendered by the
  All Runs route, and remove unused packet-version and watermark work from the
  run index.
- Let Relay own cumulative activity pagination instead of modeling individual
  continuation requests in component state.
- Remove duplicate test fixtures and public test seams, and archive completed
  planning records according to the repository's planning convention.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `agent-definitions`: Remove the unsupported legacy-definition upgrade
  contract while retaining the canonical fresh-install definition.
- `packet-workspace`: Make present packet URL selection authoritative and keep
  default selection local until an operator explicitly selects a packet.
- `work-runs`: Narrow the run-index contract to the fields required by the
  product list and retain bounded authorized reads.
- `operator-console`: Preserve All Runs behavior with direct architecture
  checks and URL-authoritative selection.
- `frontend-architecture`: Require Relay-owned cumulative activity pagination
  and direct repository checks instead of a custom analyzer.

## Impact

The change removes one Ecto migration and its upgrade-only regression suite,
simplifies run projection and GraphQL types, refactors the `/runs` and
`/packets` React routes, regenerates Relay artifacts, trims frontend
architecture and behavior tests, and archives completed planning documents.
There are no new dependencies or product routes.
