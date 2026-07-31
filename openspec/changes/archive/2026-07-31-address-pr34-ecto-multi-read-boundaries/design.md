## Context

The database-boundary scanner classifies calls from parsed Elixir AST after
resolving explicit aliases and imports. It already treats database-changing
`Ecto.Multi` operations as direct Ecto access, but its operation inventory was
created before the pinned Ecto version exposed `all/4`, `one/4`, and
`exists?/4`. Those APIs execute repository queries when the multi runs and are
therefore the same Ash-boundary violation as direct repository reads.

No runtime application behavior or database schema changes are needed. The fix
must remain receiver-aware and must not classify lookalike calls solely from an
operation name.

## Goals / Non-Goals

**Goals:**

- Cover every public database-reading operation exposed by the pinned
  `Ecto.Multi` implementation.
- Reuse existing fully qualified and explicit-alias receiver resolution.
- Prove the positive and unrelated-receiver cases with focused scanner tests.

**Non-Goals:**

- Classify `Ecto.Multi.new`, `to_list`, or `inspect`, which do not themselves
  compose database access.
- Replace the scanner with runtime introspection or a generated API inventory.
- Broaden this review fix into changes to the separate historical conformance
  support scanner.

## Decisions

### Extend the existing `Ecto.Multi` operation inventory

Add `all`, `one`, and `exists?` to `@direct_multi_operations`. The scanner's
existing receiver resolution will classify fully qualified calls and calls
through explicit aliases while preserving unrelated modules.

Maintaining a complete semantic operation inventory is preferable to matching
all `Ecto.Multi` calls: `new`, `to_list`, and `inspect` manipulate an in-memory
multi and do not cross the persistence boundary. Runtime reflection was
rejected because the canonical Credo check must be deterministic without
loading project dependencies or executing tracked source.

### Test observable scanner output

The regression will scan controlled Elixir source and assert the exact
classified constructs and lines for all three read APIs while including
same-named calls on an unrelated receiver. This exercises the real parser and
alias resolver instead of asserting on the private operation list.

## Risks / Trade-offs

- **A future Ecto release adds another database operation** -> Keep the pinned
  dependency's public API as the review baseline and require behavioral scanner
  coverage whenever the operation inventory changes.
- **Operation names collide with unrelated modules** -> Continue resolving the
  receiver first and include an unrelated-receiver regression.
