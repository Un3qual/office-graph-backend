defmodule OfficeGraph.AgentRuntime.Adapters.DeterministicTool do
  @moduledoc false

  @behaviour OfficeGraph.AgentRuntime.ToolAdapter

  alias OfficeGraph.AgentRuntime.{
    AdapterContract,
    AdapterState,
    ToolInput,
    ToolManifest,
    ToolOutput
  }

  alias OfficeGraph.AgentRuntime.Adapters.DeterministicRuntime
  alias OfficeGraph.AgentRuntime.Adapters.DeterministicRuntime.Configuration

  @state_namespace __MODULE__
  @required_capability "agent.tool.read"

  @impl true
  def manifest do
    %ToolManifest{
      key: "deterministic-tool",
      version: "1",
      input_schema: DeterministicRuntime.input_schema(:tool),
      output_schema: DeterministicRuntime.output_schema(ToolOutput.classifications()),
      capability_keys: [@required_capability],
      credential_kinds: [],
      sensitivity: :internal,
      external_write: false,
      timeout_ms: 1_000,
      budget_units: 1_000,
      output_classifications: ToolOutput.classifications(),
      idempotency_supported: true,
      raw_retention: false,
      approval_required:
        Application.get_env(:office_graph, :deterministic_tool_approval_required, false)
    }
  end

  def register_request(request_id) when is_binary(request_id) do
    AdapterState.register(@state_namespace, request_id)
  end

  def retained_request!(request_id) when is_binary(request_id) do
    case AdapterState.retained(@state_namespace, request_id) do
      {:ok, retained} -> retained
      :error -> raise KeyError, key: request_id, term: :deterministic_tool_retention
    end
  end

  def reset, do: AdapterState.reset(@state_namespace)

  @impl true
  def invoke(%ToolInput{} = input) do
    manifest = manifest()

    with :ok <- AdapterContract.validate_tool_input(manifest, input) do
      DeterministicRuntime.invoke(input, runtime_configuration(manifest))
    end
  end

  def invoke(_input), do: {:error, {:terminal, :invalid_tool_input}}

  @impl true
  def cancel(request_id) when is_binary(request_id) do
    AdapterState.cancel(@state_namespace, request_id)
  end

  def cancel(_request_id), do: {:error, :not_found}

  defp runtime_configuration(manifest) do
    %Configuration{
      fixture_loader: &deterministic_fixture/1,
      malformed_output_code: :malformed_tool_output,
      manifest: manifest,
      output_module: ToolOutput,
      state_namespace: @state_namespace,
      validate_output: &AdapterContract.validate_tool_output/2
    }
  end

  defp deterministic_fixture("evidence_candidate") do
    {:ok,
     %{
       "classification" => "evidence_candidate",
       "safe_summary" => "Static check completed",
       "structured_content" => %{"evidence_candidate" => %{"check" => "static"}}
     }}
  end

  defp deterministic_fixture("retryable"), do: {:ok, {:error, {:retryable, :tool_busy}}}
  defp deterministic_fixture("terminal"), do: {:ok, {:error, {:terminal, :forbidden}}}
  defp deterministic_fixture("malformed"), do: {:ok, %{"unknown" => true}}
  defp deterministic_fixture(_fixture_id), do: {:error, {:terminal, :fixture_not_found}}
end
