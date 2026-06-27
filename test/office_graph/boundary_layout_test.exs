defmodule OfficeGraph.BoundaryLayoutTest do
  use ExUnit.Case, async: true

  @public_contexts [
    OfficeGraph.Foundation,
    OfficeGraph.Identity,
    OfficeGraph.Tenancy,
    OfficeGraph.Authorization,
    OfficeGraph.Operations,
    OfficeGraph.Audit,
    OfficeGraph.Revisions,
    OfficeGraph.WorkContainers,
    OfficeGraph.WorkGraph,
    OfficeGraph.Content,
    OfficeGraph.OrderedPlacement,
    OfficeGraph.Tombstones,
    OfficeGraph.ExternalRefs,
    OfficeGraph.RawArchives,
    OfficeGraph.Integrations,
    OfficeGraph.SoftwareProving,
    OfficeGraph.WorkPackets,
    OfficeGraph.Runs,
    OfficeGraph.Verification,
    OfficeGraph.PacketRunVerification,
    OfficeGraph.ProposedChanges,
    OfficeGraph.AgentRuntime,
    OfficeGraph.Projections,
    OfficeGraph.ApiSupport
  ]

  test "boundary compiler is part of the backend verification path" do
    project_config = Mix.Project.config()

    assert :boundary in project_config[:compilers]
    assert project_config[:aliases][:"boundary.check"] == ["compile --force --warnings-as-errors"]
    assert "boundary.check" in project_config[:aliases][:verify]
  end

  test "public context modules declare boundary contracts" do
    for context <- @public_contexts do
      assert Code.ensure_loaded?(context)
      assert Keyword.has_key?(context.__info__(:attributes), Boundary)
    end
  end
end
