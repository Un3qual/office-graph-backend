# Repair Ash Model Conformance

## Why

The first backend walking skeleton added Ash resources only for a subset of
WorkGraph records and left all table-backed model modules as manual Ecto
schemas. That creates duplicate validation surfaces and lets future
implementation drift away from the architecture decision that Ash owns stable
resources, actions, lifecycle rules, and authorization-aware policy surfaces.

## What Changes

- Promote every implemented durable table to a canonical Ash resource in its
  owning bounded-context domain.
- Remove duplicate WorkGraph `Resources.*` Ash modules and make the existing
  model modules the resource modules.
- Remove table-backed `use Ecto.Schema` modules from `lib/office_graph`.
- Convert context writes and reads from schema changesets/direct `Repo`
  mutations to Ash actions.
- Expand architecture conformance so all migration-created tables, Ash
  domains, resources, and direct Ecto exceptions are machine-checked.

## Impact

- Affects all backend model modules under `lib/office_graph`.
- Does not change existing database migrations except where a test exposes a
  real table mismatch.
- Keeps direct Ecto only for approved transaction/read/maintenance escape
  hatches with no manual model schemas.
