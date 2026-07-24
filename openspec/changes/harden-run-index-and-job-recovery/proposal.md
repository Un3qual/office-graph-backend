## Why

The All Runs index assumes non-null lifecycle state and a storage order that the
current `runs` schema does not enforce, so legacy rows can break the GraphQL
connection and large workspaces can require an avoidable sort. The global Oban
Lifeline window is also shorter than any enforced worker runtime, which can
rescue a job that is still legitimately executing.

## What Changes

- Backfill legacy run lifecycle state to an explicit safe value and make the
  three lifecycle columns non-null.
- Add a scope-and-keyset composite index matching the All Runs filter and sort.
- Give every production Oban worker a finite execution deadline and keep the
  Lifeline orphan threshold strictly above that deadline.
- Add storage-catalog and runtime-configuration regression coverage.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `work-runs`: Require storage invariants and an index that support the
  non-null, bounded All Runs connection contract.
- `agent-executions`: Require live workers to time out before Lifeline orphan
  recovery can make their jobs eligible again.

## Impact

This affects the `runs` table and Ash resource, the run-index projection
contract, every configured Oban worker, Oban Lifeline configuration, and their
focused backend tests. It does not add a product command, API field, or runtime
OpenSpec dependency.
