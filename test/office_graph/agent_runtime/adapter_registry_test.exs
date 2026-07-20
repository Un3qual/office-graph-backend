defmodule OfficeGraph.AgentRuntime.InvalidManifestModel do
  @behaviour OfficeGraph.AgentRuntime.ModelAdapter

  @impl true
  def manifest, do: %{}

  @impl true
  def invoke(_input), do: {:error, {:terminal, :invalid_model_input}}

  @impl true
  def cancel(_request_id), do: {:error, :not_found}
end

defmodule OfficeGraph.AgentRuntime.AdapterRegistryTest do
  use ExUnit.Case, async: false

  alias OfficeGraph.AgentRuntime.{AdapterRegistry, ModelAdapter, ToolAdapter}
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
