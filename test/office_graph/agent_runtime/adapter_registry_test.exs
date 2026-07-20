defmodule OfficeGraph.AgentRuntime.AdapterRegistryTest do
  use ExUnit.Case, async: false

  alias OfficeGraph.AgentRuntime.{AdapterRegistry, ModelAdapter, ToolAdapter}
  alias OfficeGraph.AgentRuntime.Adapters.{DeterministicModel, DeterministicTool}

  test "resolves configured model and tool adapters by their manifest key" do
    assert {:ok, DeterministicModel} = AdapterRegistry.model("deterministic-model")
    assert {:ok, DeterministicTool} = AdapterRegistry.tool("deterministic-tool")
    assert {:error, :adapter_not_found} = AdapterRegistry.model("missing")
    assert {:error, :adapter_not_found} = AdapterRegistry.tool("missing")
  end

  test "validates registered modules against the declared behavior and manifest key" do
    assert :ok = AdapterRegistry.validate()

    assert {:error, {:model, :manifest_key_mismatch}} =
             AdapterRegistry.validate(%{models: %{"wrong-key" => DeterministicModel}, tools: %{}})
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
