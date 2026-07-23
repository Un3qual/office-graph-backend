defmodule OfficeGraph.AgentRuntime.Adapters.DeterministicOutputRoute do
  @moduledoc false

  @behaviour OfficeGraph.AgentRuntime.ToolAdapter

  alias OfficeGraph.AgentRuntime.{
    AdapterContract,
    RoutedOutputBatch,
    ToolInput,
    ToolManifest
  }

  @payload_schema AdapterContract.schema(
                    [:model_request_id, :model_output_hash, :review_summary],
                    %{
                      model_request_id: :uuid,
                      model_output_hash: {:string, 64},
                      review_summary: {:string, 1_000}
                    },
                    2_048
                  )

  @impl true
  def manifest do
    %ToolManifest{
      key: "internal.output.route",
      version: "1",
      input_schema:
        AdapterContract.schema(
          [:adapter_payload],
          AdapterContract.input_schema_fields(:tool, @payload_schema),
          16_384
        ),
      output_schema:
        AdapterContract.output_schema(
          [:observation],
          %{observation: RoutedOutputBatch.content_schema()}
        ),
      capability_keys: ["agent.model.generate"],
      credential_kinds: [],
      sensitivity: :internal,
      external_write: false,
      timeout_ms: 1_000,
      budget_units: 1,
      output_classifications: [:observation],
      idempotency_supported: true,
      raw_retention: false,
      approval_required: false
    }
  end

  @impl true
  def invoke(%ToolInput{} = input) do
    with :ok <- AdapterContract.validate_tool_input(manifest(), input),
         output <- RoutedOutputBatch.build(input.adapter_payload.review_summary),
         :ok <- AdapterContract.validate_tool_output(manifest(), output) do
      {:ok, output}
    end
  end

  def invoke(_input), do: {:error, {:terminal, :invalid_tool_input}}

  @impl true
  def cancel(_request_id), do: {:error, :not_found}
end
