## Why

The current database-boundary scanner has become a general Elixir and Erlang
execution analyzer. Its callback, dataflow, process, reflection, and compiler
rules do not form a bounded proof of database access, and each new executor
shape expands a gate that this project intended to simplify.

## What Changes

- Define the enforced threat model explicitly: Office Graph governs trusted
  project source and pinned dependencies; it does not claim that static
  analysis can sandbox arbitrary code running in the BEAM.
- Replace callback, dataflow, OTP, runtime-compilation, and reflection analysis
  with four independent gates over finite evidence:
  1. tracked-source detection of explicit low-level database primitives and
     repository-authored SQL;
  2. compiled project-module dependency/import auditing for direct references
     to database implementation modules;
  3. AshPostgres migration generation in non-mutating check mode; and
  4. terminal PostgreSQL object comparison against resource ownership.
- Preserve repository-wide tracked-source coverage, exact exception
  fingerprints and provenance, the two approved UUIDv7 fragments, and focused
  behavior tests for every approved low-level path.
- Restrict hand-authored migrations to a finite declarative syntax surface.
  Dynamic migration values, helpers, control flow, external SQL files, and raw
  SQL remain prohibited unless the exact occurrence is approved.
- Remove generic execution APIs from the database-boundary policy. A future
  requirement to execute untrusted code would require a separate process with
  isolated database credentials and network access.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `ecto-sql-boundaries`: Limit strict database enforcement to observable
  source, compiled dependency, generated migration, exact approval, and
  terminal database evidence under the trusted-code threat model.
- `project-quality-gates`: Replace the open-ended executable-syntax analyzer
  contract with bounded direct-primitive and compiled-dependency contracts.

## Impact

- Replaces `DatabaseBoundaryScanner` and its synthetic semantic test corpus
  with focused source occurrence and compiled dependency checks.
- Retains the existing Credo repository gate and approved-exception inventory
  format while reducing what the source scanner is responsible for proving.
- Retains the built-in AshPostgres drift command and the terminal migration
  baseline gate, with terminal inventory support ported from the superseded
  implementation where it is independently useful.
- Removes no product API, schema, or dependency and adds no raw SQL.
