defmodule OfficeGraph.AgentRuntime.Adapters.DeterministicModel do
  @moduledoc false

  @behaviour OfficeGraph.AgentRuntime.ModelAdapter

  alias OfficeGraph.AgentRuntime.{AdapterResult, ModelInput, ModelManifest, ModelOutput}

  @table __MODULE__
  @required_capability "agent.model.generate"

  @impl true
  def manifest do
    %ModelManifest{
      key: "deterministic-model",
      version: "1",
      input_schema: %{fixture_id: :string, capability_keys: {:list, :string}},
      output_schema: %{classification: ModelOutput.classifications(), safe_summary: :string},
      capability_keys: [@required_capability],
      credential_kinds: [],
      sensitivity: :internal,
      external_write: false,
      timeout_ms: 1_000,
      token_budget: 1_000,
      output_classifications: ModelOutput.classifications(),
      idempotency_supported: true,
      raw_retention: false
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

  def reset do
    ensure_table!()
    :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def invoke(%ModelInput{} = input) do
    register_request(input.request_id)

    case check_cancelled(input.request_id) do
      {:error, _failure} = result ->
        result

      :ok ->
        case lookup({:result, input.idempotency_key}) do
          {:ok, result} -> result
          :error -> invoke_new(input)
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

  defp invoke_new(input) do
    result =
      with :ok <- validate_input(input),
           :ok <- check_cancelled(input.request_id),
           {:ok, fixture} <- fetch_fixture(input.fixture_id),
           result <- normalize_fixture(fixture) do
        result
      end

    retain(input.request_id, result)
    put({:result, input.idempotency_key}, result)
    result
  end

  defp validate_input(input) do
    manifest = manifest()

    cond do
      not valid_input_fields?(input) ->
        {:error, {:terminal, :invalid_model_input}}

      input.adapter_key != manifest.key ->
        {:error, {:terminal, :invalid_model_input}}

      input.adapter_version != manifest.version ->
        {:error, {:terminal, :invalid_model_input}}

      not is_binary(input.fixture_id) ->
        {:error, {:terminal, :invalid_model_input}}

      not Enum.all?(manifest.capability_keys, &(&1 in input.capability_keys)) ->
        {:error, {:terminal, :missing_capability}}

      input.timeout_ms < manifest.timeout_ms ->
        {:error, {:terminal, :timeout_exceeded}}

      input.token_budget > manifest.token_budget ->
        {:error, {:terminal, :token_budget_exceeded}}

      true ->
        :ok
    end
  end

  defp valid_input_fields?(input) do
    Enum.all?(
      [
        input.request_id,
        input.execution_id,
        input.context_package_id,
        input.authority_snapshot_id,
        input.operation_id
      ],
      &match?({:ok, _uuid}, Ecto.UUID.cast(&1))
    ) and
      Enum.all?(
        [input.adapter_key, input.adapter_version, input.idempotency_key, input.fixture_id],
        &nonempty_string?/1
      ) and
      is_list(input.capability_keys) and Enum.all?(input.capability_keys, &nonempty_string?/1) and
      is_integer(input.timeout_ms) and input.timeout_ms > 0 and
      is_integer(input.token_budget) and input.token_budget > 0
  end

  defp nonempty_string?(value), do: is_binary(value) and value != ""

  defp check_cancelled(request_id) do
    if lookup({:cancelled, request_id}) == {:ok, true},
      do: {:error, {:cancelled, :cancelled}},
      else: :ok
  end

  defp fetch_fixture(fixture_id) do
    deterministic_fixture(fixture_id)
  end

  defp deterministic_fixture("proposal") do
    {:ok, %{"classification" => "proposal", "safe_summary" => "Propose a bounded follow-up"}}
  end

  defp deterministic_fixture("retryable"),
    do: {:ok, {:error, {:retryable, :provider_unavailable}}}

  defp deterministic_fixture("terminal"), do: {:ok, {:error, {:terminal, :invalid_request}}}
  defp deterministic_fixture("malformed"), do: {:ok, %{"unexpected" => true}}
  defp deterministic_fixture(_fixture_id), do: {:error, {:terminal, :fixture_not_found}}

  defp normalize_fixture(%{"classification" => classification, "safe_summary" => safe_summary})
       when is_binary(classification) do
    with {:ok, classification} <- output_classification(classification) do
      AdapterResult.normalize(
        {:ok, %ModelOutput{classification: classification, safe_summary: safe_summary}}
      )
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

  defp lookup(key) do
    ensure_table!()

    case :ets.lookup(@table, key) do
      [{^key, value}] -> {:ok, value}
      [] -> :error
    end
  end

  defp put(key, value) do
    ensure_table!()
    :ets.insert(@table, {key, value})
  end

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
        rescue
          ArgumentError -> @table
        end

      table ->
        table
    end
  end
end
