## 1. Unreleased Migration History

- [x] 1.1 Remove the forward legacy-definition reconciliation migration and its upgrade-only tests while retaining fresh-install coverage
- [x] 1.2 Update durable agent-definition requirements to match the unreleased reset policy

## 2. Direct Architecture Verification

- [x] 2.1 Replace the All Runs custom analyzer fixtures with direct checks of the actual route, imports, styles, generated artifacts, and dependencies
- [x] 2.2 Remove custom shell and glob parsing from the frontend verification tests

## 3. URL-Owned Selection

- [x] 3.1 Make packet defaults local and present `packetId` values authoritative
- [x] 3.2 Replace the pending run boolean and ref with one transition-only id while preserving stale-detail loading behavior

## 4. Focused Relay Data

- [x] 4.1 Narrow the run index and GraphQL documents to fields rendered by the list and detail
- [x] 4.2 Replace manual activity request state with Relay pagination and preserve safe continuation retry behavior
- [x] 4.3 Regenerate Relay artifacts and derive route-test payloads from generated operation types

## 5. Test And Documentation Cleanup

- [x] 5.1 Remove duplicate route scenarios, the BrowserRouter Request patch, and the execution-worker public test seam
- [x] 5.2 Archive the completed planning documents and keep OpenSpec as the sole active change record

## 6. Verification

- [x] 6.1 Run focused red-green tests for each behavior change
- [x] 6.2 Run strict OpenSpec validation and the canonical Nix repository gate
- [x] 6.3 Review the final diff for unnecessary APIs, abstractions, tests, and documentation before archiving the change
