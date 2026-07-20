defmodule OfficeGraph.AgentRuntime.Adapters.DeterministicTool do
  @moduledoc false

  @behaviour OfficeGraph.AgentRuntime.ToolAdapter

  alias OfficeGraph.AgentRuntime.{
    AdapterContract,
    AdapterResult,
    AdapterState,
    ToolInput,
    ToolManifest,
    ToolOutput
  }

  @state_namespace __MODULE__
  @required_capability "agent.tool.read"
  @input_schema %{
    required: [:fixture_id],
    fields: %{
      request_id: :uuid,
      execution_id: :uuid,
      context_package_id: :uuid,
      authority_snapshot_id: :uuid,
      operation_id: :uuid,
      tool_key: :string,
      adapter_version: :string,
      idempotency_key: :string,
      capability_keys: {:list, :string},
      credential_kinds: {:list, :atom},
      sensitivity: {:enum, [:public, :internal, :confidential, :restricted]},
      approval_granted?: :boolean,
      timeout_ms: :positive_integer,
      budget_units: :positive_integer,
      external_write: :boolean,
      fixture_id: :string
    },
    max_serialized_bytes: 16_384
  }
  @content_schemas %{
    proposal: %{
      required: ["intent"],
      fields: %{"intent" => {:string, 1_000}},
      max_serialized_bytes: 16_384
    },
    finding: %{
      required: ["summary"],
      fields: %{"summary" => {:string, 1_000}},
      max_serialized_bytes: 16_384
    },
    evidence_candidate: %{
      required: ["check"],
      fields: %{"check" => {:string, 1_000}},
      max_serialized_bytes: 16_384
    },
    message: %{
      required: ["body"],
      fields: %{"body" => {:string, 1_000}},
      max_serialized_bytes: 16_384
    },
    observation: %{
      required: ["subject"],
      fields: %{"subject" => {:string, 1_000}},
      max_serialized_bytes: 16_384
    }
  }

  @impl true
  def manifest do
    %ToolManifest{
      key: "deterministic-tool",
      version: "1",
      input_schema: @input_schema,
      output_schema: %{
        required: [:classification, :safe_summary, :structured_content],
        fields: %{
          classification: {:enum, ToolOutput.classifications()},
          safe_summary: {:string, 1_000},
          structured_content: :classified_content
        },
        content_schemas: @content_schemas,
        max_serialized_bytes: 16_384
      },
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
    with :ok <- AdapterContract.validate_tool_input(manifest(), input) do
      replay_or_invoke(input)
    end
  end

  def invoke(_input), do: {:error, {:terminal, :invalid_tool_input}}

  @impl true
  def cancel(request_id) when is_binary(request_id) do
    AdapterState.cancel(@state_namespace, request_id)
  end

  def cancel(_request_id), do: {:error, :not_found}

  defp replay_or_invoke(input) do
    fingerprint = AdapterContract.fingerprint(input)

    case AdapterState.claim(@state_namespace, replay_key(input), input.request_id, fingerprint) do
      :claimed -> invoke_new(input, fingerprint)
      {:replay, result} -> result
      :cancelled -> retain_state_failure(input, {:error, {:cancelled, :cancelled}})
      :identity_conflict -> {:error, {:terminal, :idempotency_conflict}}
      :conflict -> retain_state_failure(input, {:error, {:terminal, :idempotency_conflict}})
    end
  end

  defp invoke_new(input, fingerprint) do
    result =
      with {:ok, fixture} <- deterministic_fixture(input.fixture_id),
           result <- normalize_fixture(fixture) do
        result
      end

    case AdapterState.complete(@state_namespace, replay_key(input), fingerprint, result) do
      {:completed, completed_result} ->
        retain(input.request_id, completed_result)
        completed_result

      {:replay, completed_result} ->
        completed_result

      :cancelled ->
        retain_state_failure(input, {:error, {:cancelled, :cancelled}})

      :conflict ->
        {:error, {:terminal, :idempotency_conflict}}
    end
  end

  defp replay_key(input), do: {:result, input.execution_id, input.idempotency_key}

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

  defp normalize_fixture(%{
         "classification" => classification,
         "safe_summary" => safe_summary,
         "structured_content" => content
       })
       when is_binary(classification) do
    with {:ok, classification} <- output_classification(classification) do
      output = %ToolOutput{
        classification: classification,
        safe_summary: safe_summary,
        structured_content: content
      }

      case AdapterContract.validate_tool_output(manifest(), output) do
        :ok -> AdapterResult.normalize({:ok, output})
        error -> error
      end
    else
      :error -> {:error, {:terminal, :malformed_tool_output}}
    end
  end

  defp normalize_fixture(result) do
    case AdapterResult.normalize(result) do
      {:error, {:terminal, :invalid_adapter_result}} ->
        {:error, {:terminal, :malformed_tool_output}}

      normalized ->
        normalized
    end
  end

  defp output_classification(classification) do
    classification
    |> String.to_existing_atom()
    |> then(fn value ->
      if value in manifest().output_classifications, do: {:ok, value}, else: :error
    end)
  rescue
    ArgumentError -> :error
  end

  defp retain(request_id, {:ok, %ToolOutput{} = output}) do
    AdapterState.put_retained(@state_namespace, request_id, %{
      classification: output.classification,
      output_hash: :crypto.hash(:sha256, :erlang.term_to_binary(output.structured_content)),
      safe_summary: output.safe_summary
    })
  end

  defp retain(request_id, {:error, {classification, failure_code}}) do
    AdapterState.put_retained(@state_namespace, request_id, %{
      classification: classification,
      failure_code: failure_code,
      safe_summary: safe_failure_summary(failure_code)
    })
  end

  defp retain_state_failure(input, result) do
    retain(input.request_id, result)
    result
  end

  defp safe_failure_summary(:malformed_tool_output),
    do: "Adapter returned invalid structured output."

  defp safe_failure_summary(:cancelled), do: "Adapter request was cancelled."
  defp safe_failure_summary(_failure_code), do: "Adapter request did not complete."
end
