defmodule OfficeGraph.ReleaseSetupTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.AgentRuntime.AgentDefinition
  alias OfficeGraph.AgentRuntime.ReferenceCatalog, as: AgentReferenceCatalog
  alias OfficeGraph.Authorization.Capability

  alias OfficeGraph.WorkGraph.{RelationshipDefinition, RelationshipEndpointRule}

  test "release setup is idempotent and reconciles each owning catalog" do
    assert :ok = OfficeGraph.Release.setup()
    assert_catalog_ids_are_uuid_v7()
    first = catalog_snapshot()

    assert :ok = OfficeGraph.Release.setup()
    assert catalog_snapshot() == first

    assert first.capabilities == OfficeGraph.Authorization.recognized_capability_keys()
    assert first.relationship_definitions == expected_relationship_definitions()
    assert first.relationship_rules == Enum.sort(OfficeGraph.WorkGraph.ReferenceCatalog.rules())
    assert first.agent_definitions == AgentReferenceCatalog.definitions()
  end

  defp assert_catalog_ids_are_uuid_v7 do
    for resource <- [
          Capability,
          RelationshipDefinition,
          RelationshipEndpointRule,
          AgentDefinition
        ],
        record <- Ash.read!(resource, authorize?: false) do
      assert String.at(record.id, 14) == "7",
             "expected PostgreSQL UUIDv7 for #{inspect(resource)}, got #{inspect(record.id)}"
    end
  end

  defp catalog_snapshot do
    %{
      capabilities:
        Capability
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.key)
        |> Enum.sort(),
      relationship_definitions:
        RelationshipDefinition
        |> Ash.read!(authorize?: false)
        |> Enum.map(&definition_attrs/1)
        |> Enum.sort_by(& &1.key),
      relationship_rules:
        RelationshipEndpointRule
        |> Ash.Query.load(:definition)
        |> Ash.read!(authorize?: false)
        |> Enum.map(&{&1.definition.key, &1.source_kind, &1.target_kind})
        |> Enum.sort(),
      agent_definitions:
        AgentDefinition
        |> Ash.read!(authorize?: false)
        |> Enum.map(&agent_definition_attrs/1)
        |> Enum.sort_by(& &1.key)
    }
  end

  defp expected_relationship_definitions do
    OfficeGraph.WorkGraph.ReferenceCatalog.definitions()
    |> Enum.sort_by(& &1.key)
  end

  defp definition_attrs(definition) do
    Map.take(definition, [
      :key,
      :family,
      :direction,
      :meaning,
      :lifecycle,
      :provenance_policy,
      :authorization_policy,
      :cycle_policy,
      :specialization_posture
    ])
  end

  defp agent_definition_attrs(definition) do
    Map.take(definition, [
      :key,
      :name,
      :description,
      :lifecycle_state,
      :supported_modes,
      :requested_capabilities,
      :model_adapter_key,
      :tool_allowlist,
      :default_autonomy_mode,
      :allowed_output_kinds
    ])
  end
end
