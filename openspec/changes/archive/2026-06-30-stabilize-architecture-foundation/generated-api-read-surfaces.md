# Generated API Read Surfaces

This note records the first AshGraphql and AshJsonApi resource reads introduced
for API surface stabilization tasks 2.6-2.9.

## Selection Rules

The first generated surfaces must:

- use existing AshGraphql/AshJsonApi resource extensions;
- expose read actions only;
- keep lifecycle-driving creates, updates, and deletes private or unmounted;
- enforce `:skeleton_read` and actor organization/workspace scope;
- follow `product-vocabulary.md` so generated resource reads do not make graph
  projection internals the default product vocabulary.

## Selected Surfaces

| Domain | Resource | Generated GraphQL field | JSON API route | Why this is safe first |
| --- | --- | --- | --- | --- |
| WorkGraph | `OfficeGraph.WorkGraph.Signal` | `listSignals` | `GET /api/v1/signals` and `GET /api/v1/signals/:id` | Signal is part of the product spine and already has public actor-scoped reads. Generated writes are not declared. |
| WorkPackets | `OfficeGraph.WorkPackets.WorkPacket` | `listWorkPackets` | `GET /api/v1/work-packets` and `GET /api/v1/work-packets/:id` | Work Packet is the user-facing execution contract. Its `:create` and `:set_current_version` actions remain private and unmounted. |
| Runs | `OfficeGraph.Runs.Run` | `listWorkRuns` | `GET /api/v1/work-runs` and `GET /api/v1/work-runs/:id` | Run is the product-spine attempt record. This change intentionally makes only `Run.read` public so generated reads can use existing actor-scope policies; `:create` and lifecycle update actions remain private and unmounted. |

`GraphItem`, `GraphRelationship`, `ExecutionObservation`, `RunEvent`, raw
evidence-candidate style records, and verification-result rows remain deferred
from default generated product reads. They are infrastructure records or
audit/debug details unless a later projection or workflow requires them.

## Actor And Error Behavior

Generated GraphQL and JSON API requests use `OfficeGraphWeb.LocalApiOwnerPlug`
to set the Ash actor from the same local owner bootstrap used by current manual
API compatibility surfaces. When local API owner bootstrap is disabled, no
actor is set and the generated APIs return structured forbidden errors through
Ash authorization.

## Verification

`test/office_graph_web/generated_api_read_test.exs` proves:

- generated GraphQL reads return only the local actor scope;
- generated JSON API reads are mounted under `/api/v1`;
- no generated JSON API write routes are mounted;
- missing generated API actors return structured forbidden errors.
