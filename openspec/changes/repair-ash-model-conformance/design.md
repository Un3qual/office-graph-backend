# Design

## Canonical Resource Modules

The existing model module path is the canonical Ash resource path. For example,
`OfficeGraph.WorkGraph.Signal` is the Ash resource for `signals`; the parallel
`OfficeGraph.WorkGraph.Resources.Signal` module is removed. This keeps public
context code, test structs, and future GraphQL/interface code from choosing
between two definitions of the same table.

## Existing Migrations Stay Authoritative

The repair uses AshPostgres resources with `migrate? false` because the current
two migrations already create the walking-skeleton tables. Follow-on changes can
move selected tables to Ash-owned migrations intentionally, but this repair is
about model ownership and conformance rather than schema churn.

## Direct Ecto Boundary

Direct Ecto may remain for explicit transactions, performance-sensitive reads,
maintenance, replay scans, or raw SQL that Ash does not express cleanly. Direct
Ecto must not define table-backed schemas or bypass normal domain mutations.
Every remaining direct path is documented in the architecture exception ledger.

## Authorization

This repair preserves the existing walking-skeleton authorization behavior and
makes scope-aware Ash policies mandatory for resources that carry organization
or workspace scope. Bootstrap and trace append paths may use internal
`authorize?: false` calls only through owning context functions until their
administration flows are implemented.
