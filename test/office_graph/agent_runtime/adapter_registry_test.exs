defmodule OfficeGraph.AgentRuntime.InvalidManifestModel do
  @behaviour OfficeGraph.AgentRuntime.ModelAdapter

  @impl true
  def manifest, do: %{}

  @impl true
  def invoke(_input), do: {:error, {:terminal, :invalid_model_input}}

  @impl true
  def cancel(_request_id), do: {:error, :not_found}
end

defmodule OfficeGraph.AgentRuntime.CallbackOnlyModel do
  def manifest, do: OfficeGraph.AgentRuntime.Adapters.DeterministicModel.manifest()
  def invoke(_input), do: {:error, {:terminal, :invalid_model_input}}
  def cancel(_request_id), do: {:error, :not_found}
end

defmodule OfficeGraph.AgentRuntime.MalformedSchemaModel do
  @behaviour OfficeGraph.AgentRuntime.ModelAdapter

  @impl true
  def manifest do
    %OfficeGraph.AgentRuntime.ModelManifest{
      OfficeGraph.AgentRuntime.Adapters.DeterministicModel.manifest()
      | input_schema: %{required: [:fixture_id], fields: nil, max_serialized_bytes: 16_384}
    }
  end

  @impl true
  def invoke(_input), do: {:error, {:terminal, :invalid_model_input}}

  @impl true
  def cancel(_request_id), do: {:error, :not_found}
end

defmodule OfficeGraph.AgentRuntime.AdapterRegistryTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.AgentRuntime.{AdapterRegistry, AgentDefinition, ModelAdapter, ToolAdapter}
  alias OfficeGraph.AgentRuntime.Adapters.{DeterministicModel, DeterministicTool}

  test "resolves configured model and tool adapters by their manifest key" do
    assert {:ok, DeterministicModel} = AdapterRegistry.model("deterministic")
    assert {:ok, DeterministicTool} = AdapterRegistry.tool("deterministic-tool")
    assert {:error, :adapter_not_found} = AdapterRegistry.model("missing")
    assert {:error, :adapter_not_found} = AdapterRegistry.tool("missing")
  end

  test "validates registered modules against the declared behavior and manifest key" do
    assert :ok = AdapterRegistry.validate()

    assert {:error, {:model, :manifest_key_mismatch}} =
             AdapterRegistry.validate(%{models: %{"wrong-key" => DeterministicModel}, tools: %{}})

    assert {:error, {:registry, :invalid_configuration}} = AdapterRegistry.validate(%{})

    assert {:error, {:model, :invalid_manifest}} =
             AdapterRegistry.validate(%{
               models: %{"invalid" => OfficeGraph.AgentRuntime.InvalidManifestModel},
               tools: %{}
             })

    assert {:error, {:model, :invalid_adapter_module}} =
             AdapterRegistry.validate(%{
               models: %{"deterministic" => OfficeGraph.AgentRuntime.CallbackOnlyModel},
               tools: %{}
             })

    assert {:error, {:model, :invalid_manifest}} =
             AdapterRegistry.validate(%{
               models: %{"deterministic" => OfficeGraph.AgentRuntime.MalformedSchemaModel},
               tools: %{}
             })
  end

  test "resolves the migrated OpenSpec-review definition through its stored model adapter key" do
    definition = Ash.get!(AgentDefinition, %{key: "openspec-review"}, authorize?: false)

    assert {:ok, DeterministicModel} = AdapterRegistry.model(definition.model_adapter_key)
  end

  test "behaviors require their typed contract callbacks" do
    assert Enum.sort(ModelAdapter.behaviour_info(:callbacks)) == [
             {:cancel, 1},
             {:invoke, 1},
             {:manifest, 0}
           ]

    assert Enum.sort(ToolAdapter.behaviour_info(:callbacks)) == [
             {:cancel, 1},
             {:invoke, 1},
             {:manifest, 0}
           ]
  end
end
