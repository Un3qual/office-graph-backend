# Task 3 Report: Shared Command Input And Error Semantics

## Status

`DONE_WITH_CONCERNS`

Task 3 implementation is complete. OpenSpec tasks 4.1-4.3 are checked; no other task was changed.

## Root Cause

- GraphQL and JSON each owned a complete command field registry and casting implementation.
- GraphQL and JSON each owned a private command-error registry. JSON had already drifted: `invalid_proposed_change_replay` and `invalid_evidence_result` fell through to generic validation, while neither transport classified `evidence_candidate_already_accepted` or `verification_result_slot_conflict`.
- JSON's one-level reason formatter could attempt to encode arbitrary structs, and both prior formatters could retain unsafe nested adapter/SQL/exception strings.
- The Relay mutation hook already refreshed after any value mapped as `conflict`, but its code registry did not include either evidence concurrency outcome.

## RED Evidence

### Shared parser, transport parity, and nested sanitization

Command:

```sh
nix --extra-experimental-features 'nix-command flakes' develop -c zsh -lc \
  'mix test test/office_graph_web/operator_command_semantics_test.exs'
```

Observed:

- `Result: 0/4 passed`, four failures.
- Shared `OfficeGraphWeb.OperatorCommands.Input.parse/2` and `Errors.classify/1` were undefined.
- JSON returned `validation_failed` where `invalid_proposed_change_replay` was required.
- A nested `%RuntimeError{message: "SELECT ..."}` reached JSON encoding and raised `Protocol.UndefinedError` for `Jason.Encoder`.

Additional recursive-key RED:

```sh
nix --extra-experimental-features 'nix-command flakes' develop -c zsh -lc \
  'mix test test/office_graph_web/operator_command_semantics_test.exs:137'
```

Observed `Result: 0/1 passed`: tuple map key `{:sql, :key}` raised `Protocol.UndefinedError` for `String.Chars`, proving recursive sanitization also needed total key handling.

Independent review found a second compact-token escape. The same focused test was expanded with `Postgrex.Error`, `Ecto.ConstraintError`, and `SELECT`; RED showed all three unchanged in both public envelopes. Applying the internal-term denylist to compact binary values produced `Result: 1 passed, 3 excluded` for the focused sanitization test.

### Frontend conflict mapping and authoritative refresh

Command:

```sh
nix --extra-experimental-features 'nix-command flakes' develop -c zsh -lc \
  'cd assets && pnpm test -- app/relay/commandMutation.test.tsx app/routes/operator/commandWorkflow.test.tsx'
```

Observed:

- `3 failed | 125 passed (128)`.
- `evidence_candidate_already_accepted` mapped to `error`, not `conflict`.
- `verification_result_slot_conflict` mapped to `error`, not `conflict`.
- The hook-level result-slot test stayed in `error`, so the authoritative refresh callback was not invoked.

## GREEN Implementation

### Shared input

- Added `OfficeGraphWeb.OperatorCommands.Input` as the sole command registry/caster.
- Updated every GraphQL resolver and JSON controller to call it directly.
- Removed both transport-owned duplicate parsers.
- Characterization coverage proves atom/string keys, trimming, raw-body preservation, UUID/list casting, and stable missing/invalid field outcomes.

### Shared safe error classification

- Added `OfficeGraphWeb.OperatorCommands.Errors.classify/1` returning stable `category`, `code`, `detail`, `fields`, and sanitized `metadata`.
- GraphQL retains Absinthe message/extensions ownership.
- JSON retains command envelope and HTTP-status ownership, including existing contextual not-found status options.
- Added explicit stable outcomes for invalid proposal replay, invalid evidence result, already-accepted evidence, and `verification_result_slot_conflict`.
- Metadata sanitization recursively handles tuples, lists, maps, arbitrary keys, structs, atoms, and strings. Unsafe module/adapter/SQL/exception values become `internal` or `invalid`; no exception, SQL, or adapter text crosses either adapter.
- Table-driven parity covers 22 public command outcomes across the classifier and both adapters.

### Frontend concurrency

- Added `evidence_candidate_already_accepted` and `verification_result_slot_conflict` to the Relay conflict registry.
- Added direct mapping coverage for both codes.
- Added a hook-level `GraphQLResponseError` test proving a result-slot conflict invokes the authoritative refresh callback.

## GREEN Verification

Backend focused transport suite in an isolated database partition:

```sh
nix --extra-experimental-features 'nix-command flakes' develop -c zsh -lc '
  export MIX_ENV=test MIX_TEST_PARTITION=_task3
  mix ecto.create --quiet
  mix ecto.migrate --quiet
  mix test test/office_graph_web/operator_command_semantics_test.exs \
    test/office_graph_web/operator_commands_graphql_test.exs \
    test/office_graph_web/operator_commands_json_test.exs
'
```

Output: `Result: 24 passed`.

Frontend focused suite and typecheck:

```sh
nix --extra-experimental-features 'nix-command flakes' develop -c zsh -lc '
  cd assets
  pnpm exec vitest run app/relay/commandMutation.test.tsx \
    app/routes/operator/commandWorkflow.test.tsx
  pnpm typecheck
'
```

Output: `2 passed (2)` files, `23 passed (23)` tests; `tsc --noEmit` exited 0.

Static/OpenSpec checks:

```sh
nix --extra-experimental-features 'nix-command flakes' develop -c zsh -lc '
  mix format --check-formatted
  mix compile --warnings-as-errors
  openspec validate harden-project-quality --strict
  git diff --check
'
```

Output: format and compile exited 0; OpenSpec reported `Change 'harden-project-quality' is valid`; diff check exited 0.

## Files

- `lib/office_graph_web/operator_commands/input.ex`
- `lib/office_graph_web/operator_commands/errors.ex`
- `lib/office_graph_web/graphql/common/errors.ex`
- `lib/office_graph_web/json_api/common/errors.ex`
- GraphQL operator command resolvers under `lib/office_graph_web/graphql/operator_commands/resolvers/`
- JSON operator command controllers under `lib/office_graph_web/json_api/operator_commands/`
- Removed transport-local `graphql/operator_commands/input.ex` and `json_api/operator_commands/input.ex`
- `test/office_graph_web/operator_command_semantics_test.exs`
- `assets/app/relay/commandMutation.ts`
- `assets/app/relay/commandMutation.test.tsx`
- `assets/app/routes/operator/commandWorkflow.test.tsx`
- `openspec/changes/harden-project-quality/tasks.md`

## Commits

- `df080c3` — `unify operator command semantics`
- `739b626` — `refresh after evidence command conflicts`
- `3ce75d9` — `close compact error metadata leaks`

The OpenSpec/report checkpoint is committed separately after this report.

## Concerns

- `mix credo --strict` is not green because of two pre-existing warnings in Task-2-owned files outside this task's allowed edit scope:
  - `lib/office_graph/work_graph/changes/validate_same_scope_references.ex:149`
  - `lib/office_graph/runs/changes/validate_run_required_check_contract.ex:200`
  Both warnings report Logger metadata keys `field`/`error` are absent from Logger configuration.
- One non-partitioned focused backend run observed unrelated `runless-completion-race` rows from a concurrently running suite and failed a global snapshot assertion. The same 24 tests passed in the dedicated `_task3` partition; this is shared-database interference, not a Task 3 product failure.
- No push was performed.
