defmodule OfficeGraph.BoundaryLayoutTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

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
    OfficeGraph.ProposedChanges,
    OfficeGraph.AgentRuntime,
    OfficeGraph.Projections,
    OfficeGraph.ApiSupport
  ]

  test "boundary compiler is part of the backend verification path" do
    project_config = Mix.Project.config()
    aliases = project_config[:aliases]

    assert :boundary in project_config[:compilers]
    assert aliases[:"boundary.check"] == ["compile --force --warnings-as-errors"]
    assert "boundary.check" in aliases[:verify]
    assert aliases[:"dependency.audit"] == ["hex.audit", "cmd --cd assets pnpm audit --prod"]
    assert "dependency.audit" in aliases[:verify]
    assert "spec.verify" in aliases[:verify]
    assert "frontend.verify.precompiled" in aliases[:verify]
    assert "dependency.audit" in aliases[:precommit]
    assert "spec.verify" in aliases[:precommit]
  end

  test "public context modules declare boundary contracts" do
    for context <- @public_contexts do
      assert Code.ensure_loaded?(context)
      assert Keyword.has_key?(context.__info__(:attributes), Boundary)
    end
  end

  test "architecture layers name only loadable concrete modules" do
    {reach_config, _bindings} = Code.eval_file(".reach.exs")

    missing_modules =
      reach_config
      |> Keyword.fetch!(:layers)
      |> Keyword.values()
      |> List.flatten()
      |> Enum.reject(fn module_name ->
        String.contains?(module_name, "*") or
          module_name
          |> then(&Module.concat([&1]))
          |> Code.ensure_loaded?()
      end)

    assert missing_modules == []
  end

  test "verification waiver execution has a focused internal owner" do
    waiver = Module.concat(OfficeGraph.Verification, Waiver)

    assert Code.ensure_loaded?(waiver)
    assert function_exported?(waiver, :execute, 5)
  end

  test "module graph has no compile-time dependency cycles" do
    cycles =
      capture_io(fn ->
        Mix.Task.reenable("xref")
        Mix.Task.run("xref", ["graph", "--format", "cycles"])
      end)

    refute cycles =~ " compile)", cycles
  end
end
