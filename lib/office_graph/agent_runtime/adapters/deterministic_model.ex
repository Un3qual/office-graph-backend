defmodule OfficeGraph.AgentRuntime.Adapters.DeterministicModel do
  @moduledoc false

  @behaviour OfficeGraph.AgentRuntime.ModelAdapter

  alias OfficeGraph.AgentRuntime.{
    AdapterContract,
    AdapterState,
    ModelInput,
    ModelManifest,
    ModelOutput
  }

  alias OfficeGraph.AgentRuntime.Adapters.DeterministicRuntime
  alias OfficeGraph.AgentRuntime.Adapters.DeterministicRuntime.Configuration

  @state_namespace __MODULE__
  @required_capability "agent.model.generate"

  @impl true
  def manifest do
    %ModelManifest{
      key: "deterministic",
      version: "1",
      input_schema: DeterministicRuntime.input_schema(:model),
      output_schema: DeterministicRuntime.output_schema(ModelOutput.classifications()),
      capability_keys: [@required_capability],
      credential_kinds: [],
      sensitivity: :internal,
      external_write: false,
      timeout_ms: 1_000,
      token_budget: 1_000,
      output_classifications: ModelOutput.classifications(),
      idempotency_supported: true,
      raw_retention: false,
      approval_required:
        Application.get_env(:office_graph, :deterministic_model_approval_required, false)
    }
  end

  def register_request(request_id) when is_binary(request_id) do
    AdapterState.register(@state_namespace, request_id)
  end

  def retained_request!(request_id) when is_binary(request_id) do
    case AdapterState.retained(@state_namespace, request_id) do
      {:ok, retained} -> retained
      :error -> raise KeyError, key: request_id, term: :deterministic_model_retention
    end
  end

  def reset, do: AdapterState.reset(@state_namespace)

  @impl true
  def invoke(%ModelInput{} = input) do
    manifest = manifest()

    with :ok <- AdapterContract.validate_model_input(manifest, input) do
      DeterministicRuntime.invoke(input, runtime_configuration(manifest))
    end
  end

  def invoke(_input), do: {:error, {:terminal, :invalid_model_input}}

  @impl true
  def cancel(request_id) when is_binary(request_id) do
    AdapterState.cancel(@state_namespace, request_id)
  end

  def cancel(_request_id), do: {:error, :not_found}

  defp runtime_configuration(manifest) do
    %Configuration{
      fixture_loader: &deterministic_fixture/1,
      malformed_output_code: :malformed_model_output,
      manifest: manifest,
      output_module: ModelOutput,
      state_namespace: @state_namespace,
      validate_output: &AdapterContract.validate_model_output/2
    }
  end

  defp deterministic_fixture("proposal") do
    {:ok,
     %{
       "classification" => "proposal",
       "safe_summary" => "Propose a bounded follow-up",
       "structured_content" => %{"proposal" => %{"intent" => "follow_up"}}
     }}
  end

  defp deterministic_fixture("retryable"),
    do: {:ok, {:error, {:retryable, :provider_unavailable}}}

  defp deterministic_fixture("terminal"), do: {:ok, {:error, {:terminal, :invalid_request}}}
  defp deterministic_fixture("malformed"), do: {:ok, %{"unexpected" => true}}
  defp deterministic_fixture(_fixture_id), do: {:error, {:terminal, :fixture_not_found}}
end
