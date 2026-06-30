# Implementation Notes

## Completed Stabilization Tracks

- API surface stabilization split GraphQL and JSON API code by transport and
  capability, added generated read surfaces for Signal, Work Packet, and Run,
  and kept manual compatibility routes ledgered.
- Domain cleanup added first-pass relationships and moved packet, run,
  verification, and WorkGraph invariants toward owning Ash/domain commands.
- Frontend foundation moved tooling under `assets`, uses pnpm, adds shared
  tokens/primitives, wires StyleX through Vite, verifies React Aria and
  TanStack Query compatibility, and decomposes the operator console into
  focused layout, hook, projection-client, and panel modules.
- Product vocabulary simplification documents the canonical Signal, Work Item,
  Work Packet, Run, Check, Evidence, and Verification spine and translates
  legacy operator UI terms such as proposed changes, evidence candidates, and
  verification results into product-facing labels.

## Remaining Exception-Ledger And Compatibility Work

- Operator workflow JSON routes remain temporary until the React frontend uses
  the GraphQL projection client by default.
- Legacy proposed-change compatibility commands remain only while generic graph
  proposal storage still exists; current MVP vocabulary defers this surface.
- Packet-run-verification one-shot wrappers remain transitional over durable
  domain commands until desired callers use smaller command/projection
  surfaces.
- Direct database, raw SQL, broad authorization bypass, and manual transaction
  entries remain burn-down items in the backend architecture exception ledger.

## Follow-Up Sequencing

1. Move the operator console from the JSON bridge to the GraphQL projection
   client once GraphQL coverage is sufficient for the full current view model.
2. Retire JSON operator workflow routes after the frontend no longer calls
   them.
3. Continue burning down domain exception entries inside WorkGraph,
   WorkPackets, Runs, Verification, and ProposedChanges with focused tests per
   retired exception.
4. Archive this change after final verification is complete and durable specs
   are synced or confirmed current.

## Verification Evidence

- `nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate stabilize-architecture-foundation --strict`
- `nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --specs --strict`
- `nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets run verify`
- `nix --extra-experimental-features 'nix-command flakes' develop --command mix architecture.conformance`
- `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph_web/operator_workflow_api_test.exs test/office_graph_web/generated_api_read_test.exs test/office_graph_web/operator_console_controller_test.exs`
- `git diff --check`
