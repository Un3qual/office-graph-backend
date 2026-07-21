defmodule OfficeGraph.AgentRuntime.Adapters.DeterministicRuntime do
  @moduledoc false

  alias OfficeGraph.AgentRuntime.{AdapterContract, AdapterResult, AdapterState}

  defmodule Configuration do
    @moduledoc false

    @enforce_keys [
      :fixture_loader,
      :malformed_output_code,
      :manifest,
      :output_module,
      :state_namespace,
      :validate_output
    ]
    defstruct @enforce_keys
  end

  @adapter_payload_schema %{
    required: [:fixture_id],
    fields: %{fixture_id: :string},
    max_serialized_bytes: 1_024
  }
  @common_input_fields %{
    request_id: :uuid,
    execution_id: :uuid,
    context_package_id: :uuid,
    authority_snapshot_id: :uuid,
    operation_id: :uuid,
    adapter_version: :string,
    idempotency_key: :string,
    capability_keys: {:list, :string},
    credential_kinds: {:list, :atom},
    sensitivity: {:enum, [:public, :internal, :confidential, :restricted]},
    approval_granted?: :boolean,
    timeout_ms: :positive_integer,
    adapter_payload: {:map, @adapter_payload_schema}
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

  def input_schema(:model) do
    build_input_schema(
      Map.merge(@common_input_fields, %{adapter_key: :string, token_budget: :positive_integer})
    )
  end

  def input_schema(:tool) do
    build_input_schema(
      Map.merge(@common_input_fields, %{
        tool_key: :string,
        budget_units: :positive_integer,
        external_write: :boolean
      })
    )
  end

  def output_schema(classifications) when is_list(classifications) do
    %{
      required: [:classification, :safe_summary, :structured_content],
      fields: %{
        classification: {:enum, classifications},
        safe_summary: {:string, 1_000},
        structured_content: :classified_content
      },
      content_schemas: @content_schemas,
      max_serialized_bytes: 16_384
    }
  end

  def invoke(input, %Configuration{} = configuration) do
    fingerprint = AdapterContract.fingerprint(input)
    replay_key = replay_key(input)

    case AdapterState.claim(
           configuration.state_namespace,
           replay_key,
           input.request_id,
           fingerprint,
           input.timeout_ms
         ) do
      :claimed ->
        invoke_new(input, replay_key, fingerprint, configuration)

      {:replay, result} ->
        retain_result(input, result, configuration)

      :cancelled ->
        retain_result(input, {:error, {:cancelled, :cancelled}}, configuration)

      :identity_conflict ->
        {:error, {:terminal, :idempotency_conflict}}

      :conflict ->
        retain_result(input, {:error, {:terminal, :idempotency_conflict}}, configuration)

      {:error, {:terminal, :timeout_exceeded}} = error ->
        retain_result(input, error, configuration)
    end
  end

  defp build_input_schema(fields) do
    %{required: [:adapter_payload], fields: fields, max_serialized_bytes: 16_384}
  end

  defp invoke_new(input, replay_key, fingerprint, configuration) do
    result =
      with {:ok, fixture} <- configuration.fixture_loader.(input.adapter_payload.fixture_id) do
        normalize_fixture(fixture, configuration)
      end

    case AdapterState.complete(
           configuration.state_namespace,
           replay_key,
           fingerprint,
           result
         ) do
      {:completed, completed_result} ->
        retain_result(input, completed_result, configuration)

      {:replay, completed_result} ->
        retain_result(input, completed_result, configuration)

      :cancelled ->
        retain_result(input, {:error, {:cancelled, :cancelled}}, configuration)

      :conflict ->
        {:error, {:terminal, :idempotency_conflict}}
    end
  end

  defp normalize_fixture(
         %{
           "classification" => classification,
           "safe_summary" => safe_summary,
           "structured_content" => content
         },
         configuration
       )
       when is_binary(classification) do
    with {:ok, classification} <- output_classification(classification, configuration.manifest) do
      output =
        struct!(configuration.output_module,
          classification: classification,
          safe_summary: safe_summary,
          structured_content: content
        )

      case configuration.validate_output.(configuration.manifest, output) do
        :ok -> AdapterResult.normalize({:ok, output})
        error -> error
      end
    else
      :error -> {:error, {:terminal, configuration.malformed_output_code}}
    end
  end

  defp normalize_fixture(result, configuration) do
    case AdapterResult.normalize(result) do
      {:error, {:terminal, :invalid_adapter_result}} ->
        {:error, {:terminal, configuration.malformed_output_code}}

      normalized ->
        normalized
    end
  end

  defp output_classification(classification, manifest) do
    classification
    |> String.to_existing_atom()
    |> then(fn value ->
      if value in manifest.output_classifications, do: {:ok, value}, else: :error
    end)
  rescue
    ArgumentError -> :error
  end

  defp retain(request_id, {:ok, output}, configuration) do
    if is_struct(output, configuration.output_module) do
      AdapterState.put_retained(configuration.state_namespace, request_id, %{
        classification: output.classification,
        output_hash: :crypto.hash(:sha256, :erlang.term_to_binary(output.structured_content)),
        safe_summary: output.safe_summary
      })
    end
  end

  defp retain(request_id, {:error, {classification, failure_code}}, configuration) do
    AdapterState.put_retained(configuration.state_namespace, request_id, %{
      classification: classification,
      failure_code: failure_code,
      safe_summary: safe_failure_summary(failure_code, configuration.malformed_output_code)
    })
  end

  defp retain_result(input, result, configuration) do
    retain(input.request_id, result, configuration)
    result
  end

  defp replay_key(input), do: {:result, input.execution_id, input.idempotency_key}

  defp safe_failure_summary(failure_code, failure_code),
    do: "Adapter returned invalid structured output."

  defp safe_failure_summary(:cancelled, _malformed_output_code),
    do: "Adapter request was cancelled."

  defp safe_failure_summary(_failure_code, _malformed_output_code),
    do: "Adapter request did not complete."
end
