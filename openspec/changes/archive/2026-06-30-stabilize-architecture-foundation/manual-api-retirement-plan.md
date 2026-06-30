# Manual API Retirement Plan

This plan records the deletion path for manual endpoints that now have
generated reads or domain command/projection replacements. Backwards
compatibility is not a release constraint during current stabilization; a
manual endpoint only stays live while it preserves useful development smoke or
an accepted customer integration contract.

## Replacement Groups

| Manual surface group | Replacement now available | Next retirement step | Delete when |
| --- | --- | --- | --- |
| WorkGraph, WorkPacket, and Run resource reads | Generated GraphQL reads and AshJsonApi reads under `/api/v1` for `Signal`, `WorkPacket`, and `Run` | Move tests and clients that only need plain resource reads to generated surfaces | No desired caller needs the old `/api` or manual projection envelope for plain reads |
| Packet-run-verification one-shot GraphQL and JSON commands | `OfficeGraph.PacketRunVerification.execute/2` domain command under the existing wrappers | Keep wrappers temporary; add replacement command/projection clients before UI depends on the one-shot envelope | Desired callers use durable command/projection surfaces, or a later spec explicitly promotes the one-shot as a customer integration command |
| Operator workflow JSON projection routes | GraphQL is the locked product frontend API direction | Replace the frontend JSON adapter with a GraphQL projection client | The operator frontend no longer calls temporary JSON projection routes |
| Legacy proposed-change compatibility commands | Product concept simplification defers generic graph proposal machinery | Remove or replace with typed domain-command proposal workflow if a real review workflow appears | Generic `ProposedGraphChange` leaves MVP API/UI scope |
| Manual intake and verification completion commands | Narrow custom command wrappers remain valid until domain command boundaries are split further | Move command ownership into durable domain modules and expose only documented command exceptions | Replacement commands preserve authorization, idempotency, validation, and structured errors |

## Guardrails

- Retiring a manual endpoint does not require preserving old field names or
  response envelopes unless a later customer contract explicitly requires it.
- The product frontend must prefer GraphQL replacements. REST/JSON API remains
  for customer integrations under `/api/v1` or explicitly documented custom
  command endpoints.
- Manual endpoint deletion must update `api-migration-ledger.md`,
  stabilization inventory, and focused API tests in the same change.
- Compatibility wrappers must stay thin: context loading, domain command or
  projection invocation, and transport-specific error mapping.
- Replacement API and UI labels must follow `product-vocabulary.md`; legacy
  field names such as `proposed_change_status`, `evidence_candidates`, or
  `verification_results` do not make those terms default product nouns.
