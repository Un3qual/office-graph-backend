defmodule OfficeGraph.AgentRuntime.Adapters.DeterministicModel do
  @moduledoc false

  @behaviour OfficeGraph.AgentRuntime.ModelAdapter

  alias OfficeGraph.AgentRuntime.{
    AdapterContract,
    AdapterResult,
    AdapterState,
    ModelInput,
    ModelManifest,
    ModelOutput
  }

  @state_namespace __MODULE__
  @required_capability "agent.model.generate"
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
    %ModelManifest{
      key: "deterministic",
      version: "1",
      input_schema: %{
        required: [:fixture_id],
        fields: %{fixture_id: :string},
        max_serialized_bytes: 16_384
      },
      output_schema: %{
        required: [:classification, :safe_summary, :structured_content],
        fields: %{
          classification: {:enum, ModelOutput.classifications()},
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
      token_budget: 1_000,
      output_classifications: ModelOutput.classifications(),
      idempotency_supported: true,
      raw_retention: false,
      approval_required: false
    }
  end

  def register_request(request_id) when is_binary(request_id) do
    put({:known, request_id}, true)
    :ok
  end

  def retained_request!(request_id) when is_binary(request_id) do
    case lookup({:retained, request_id}) do
      {:ok, retained} -> retained
      :error -> raise KeyError, key: request_id, term: :deterministic_model_retention
    end
  end

  def reset, do: AdapterState.reset(@state_namespace)

  @impl true
  def invoke(%ModelInput{} = input) do
    with :ok <- AdapterContract.validate_model_input(manifest(), input) do
      register_request(input.request_id)

      case check_cancelled(input.request_id) do
        {:error, _failure} = result -> result
        :ok -> replay_or_invoke(input)
      end
    end
  end

  def invoke(_input), do: {:error, {:terminal, :invalid_model_input}}

  @impl true
  def cancel(request_id) when is_binary(request_id) do
    case lookup({:known, request_id}) do
      {:ok, true} ->
        put({:cancelled, request_id}, true)
        :ok

      :error ->
        {:error, :not_found}
    end
  end

  def cancel(_request_id), do: {:error, :not_found}

  defp replay_or_invoke(input) do
    fingerprint = AdapterContract.fingerprint(input)

    case lookup(replay_key(input)) do
      {:ok, %{fingerprint: ^fingerprint, result: result}} -> result
      {:ok, _cached} -> {:error, {:terminal, :idempotency_conflict}}
      :error -> invoke_new(input, fingerprint)
    end
  end

  defp invoke_new(input, fingerprint) do
    result =
      with :ok <- check_cancelled(input.request_id),
           {:ok, fixture} <- deterministic_fixture(input.fixture_id),
           result <- normalize_fixture(fixture) do
        result
      end

    retain(input.request_id, result)
    put(replay_key(input), %{fingerprint: fingerprint, result: result})
    result
  end

  defp replay_key(input), do: {:result, input.execution_id, input.idempotency_key}

  defp check_cancelled(request_id) do
    if lookup({:cancelled, request_id}) == {:ok, true},
      do: {:error, {:cancelled, :cancelled}},
      else: :ok
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

  defp normalize_fixture(%{
         "classification" => classification,
         "safe_summary" => safe_summary,
         "structured_content" => content
       })
       when is_binary(classification) do
    with {:ok, classification} <- output_classification(classification) do
      output = %ModelOutput{
        classification: classification,
        safe_summary: safe_summary,
        structured_content: content
      }

      case AdapterContract.validate_model_output(manifest(), output) do
        :ok -> AdapterResult.normalize({:ok, output})
        error -> error
      end
    else
      :error -> {:error, {:terminal, :malformed_model_output}}
    end
  end

  defp normalize_fixture(result) do
    case AdapterResult.normalize(result) do
      {:error, {:terminal, :invalid_adapter_result}} ->
        {:error, {:terminal, :malformed_model_output}}

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

  defp retain(request_id, {:ok, %ModelOutput{} = output}) do
    put({:retained, request_id}, %{
      classification: output.classification,
      output_hash: :crypto.hash(:sha256, :erlang.term_to_binary(output.structured_content)),
      safe_summary: output.safe_summary
    })
  end

  defp retain(request_id, {:error, {classification, failure_code}}) do
    put({:retained, request_id}, %{
      classification: classification,
      failure_code: failure_code,
      safe_summary: safe_failure_summary(failure_code)
    })
  end

  defp safe_failure_summary(:malformed_model_output),
    do: "Adapter returned invalid structured output."

  defp safe_failure_summary(:cancelled), do: "Adapter request was cancelled."
  defp safe_failure_summary(_failure_code), do: "Adapter request did not complete."

  defp lookup(key), do: AdapterState.get(@state_namespace, key)
  defp put(key, value), do: AdapterState.put(@state_namespace, key, value)
end
