defmodule OfficeGraph.BoundaryLayoutTest do
  use ExUnit.Case, async: true

  @public_contexts [
    OfficeGraph.Foundation,
    OfficeGraph.Identity,
    OfficeGraph.Authentication,
    OfficeGraph.Tenancy,
    OfficeGraph.Authorization,
    OfficeGraph.Operations,
    OfficeGraph.Audit,
    OfficeGraph.Revisions,
    OfficeGraph.WorkContainers,
    OfficeGraph.WorkGraph,
    OfficeGraph.Content,
    OfficeGraph.OrderedPlacement,
    OfficeGraph.ExternalRefs,
    OfficeGraph.RawArchives,
    OfficeGraph.Integrations,
    OfficeGraph.SoftwareProving,
    OfficeGraph.WorkPackets,
    OfficeGraph.Runs,
    OfficeGraph.Verification,
    OfficeGraph.ProposedChanges,
    OfficeGraph.AgentRuntime,
    OfficeGraph.NodeConversations,
    OfficeGraph.Projections,
    OfficeGraph.ApiSupport
  ]

  @behavior_value_objects [
    {OfficeGraph.AgentRuntime.InvocationRequest,
     "lib/office_graph/agent_runtime/values/invocation_request.ex",
     [new: 1, new!: 1, command_input: 1]},
    {OfficeGraph.GitHubIntegration.ReconciliationRequest,
     "lib/office_graph/github_integration/requests/reconciliation_request.ex", [new: 1, new!: 1]},
    {OfficeGraph.WorkGraph.RelationshipRequest,
     "lib/office_graph/work_graph/requests/relationship_request.ex",
     [new: 1, new!: 1, validate: 1]}
  ]

  @grouped_contexts ~w(
    agent_runtime
    durable_delivery
    github_integration
    identity
    work_graph
    work_packets
  )

  @passive_boundary_dtos [
    {OfficeGraph.AgentRuntime.ModelInput, "lib/office_graph/agent_runtime/values/model_input.ex"},
    {OfficeGraph.AgentRuntime.ModelManifest,
     "lib/office_graph/agent_runtime/values/model_manifest.ex"},
    {OfficeGraph.AgentRuntime.ToolInput, "lib/office_graph/agent_runtime/values/tool_input.ex"},
    {OfficeGraph.AgentRuntime.ToolManifest,
     "lib/office_graph/agent_runtime/values/tool_manifest.ex"},
    {OfficeGraph.WorkGraph.RelationshipView,
     "lib/office_graph/work_graph/values/relationship_view.ex"},
    {OfficeGraph.WorkPackets.PacketResult,
     "lib/office_graph/work_packets/values/packet_result.ex"}
  ]

  test "boundary compiler is part of the backend verification path" do
    project_config = Mix.Project.config()
    aliases = project_config[:aliases]

    assert :boundary in project_config[:compilers]
    assert aliases[:"boundary.check"] == ["compile --force --warnings-as-errors"]
    assert "boundary.check" in aliases[:verify]

    assert aliases[:"architecture.check"] == [
             "xref graph --format cycles --label compile-connected --fail-above 0"
           ]

    assert "architecture.check" in aliases[:verify]

    assert aliases[:"dependency.audit"] == [
             "cmd mix hex.audit",
             "cmd --cd assets pnpm audit --prod"
           ]

    assert "dependency.audit" in aliases[:verify]
    assert "spec.verify" in aliases[:verify]
    assert "frontend.verify.precompiled" in aliases[:verify]

    assert aliases[:"frontend.verify.precompiled"] == [
             "assets.setup",
             "cmd --cd assets env MIX_ENV=test OFFICE_GRAPH_SCHEMA_PRECOMPILED=1 pnpm run verify"
           ]

    assert aliases[:"static.analysis"] == [
             "credo --strict",
             "reach.check --arch --smells --strict",
             "reach.check --smells --strict credo_checks"
           ]

    assert "test" in aliases[:verify]
    refute "architecture.conformance" in aliases[:verify]
    assert aliases[:precommit] == ["verify"]
  end

  test "public context modules declare boundary contracts" do
    for context <- @public_contexts do
      assert Code.ensure_loaded?(context)
      assert Keyword.has_key?(context.__info__(:attributes), Boundary)
    end
  end

  test "architecture layers name only loadable concrete modules" do
    reach_config = ".reach.exs" |> File.read!() |> Code.string_to_quoted!()
    layers = Keyword.fetch!(reach_config, :layers)

    assert "OfficeGraph.Verification.*" in Keyword.fetch!(layers, :domain)

    missing_modules =
      layers
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

  test "crowded contexts group internal files by responsibility" do
    for context <- @grouped_contexts do
      direct_files =
        "lib/office_graph/#{context}/*.ex"
        |> Path.wildcard()
        |> Enum.map(&Path.basename/1)
        |> Enum.sort()

      assert direct_files == ["domain.ex"],
             "#{context} must keep only its domain module at the context root, got #{inspect(direct_files)}"
    end
  end

  test "value objects live with their responsibility and own reusable behavior" do
    for {module, path, functions} <- @behavior_value_objects do
      assert File.regular?(path), "#{inspect(module)} must live at #{path}"
      assert Code.ensure_loaded?(module)

      for {function, arity} <- functions do
        assert function_exported?(module, function, arity),
               "#{inspect(module)} must own #{function}/#{arity}"
      end
    end
  end

  test "passive boundary DTOs are placed and documented as passive values" do
    for {module, path} <- @passive_boundary_dtos do
      assert File.regular?(path), "#{inspect(module)} must live at #{path}"
      assert Code.ensure_loaded?(module)

      assert {:docs_v1, _annotation, _language, _format, module_doc, _metadata, _docs} =
               Code.fetch_docs(module)

      assert is_map(module_doc) and map_size(module_doc) > 0,
             "#{inspect(module)} must document why it remains a passive DTO"
    end
  end
end
