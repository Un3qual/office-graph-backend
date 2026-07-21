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
    build_input_schema(AdapterContract.input_schema_fields(:model, @adapter_payload_schema))
  end

  def input_schema(:tool) do
    build_input_schema(AdapterContract.input_schema_fields(:tool, @adapter_payload_schema))
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
    deadline = System.monotonic_time(:millisecond) + input.timeout_ms
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
        invoke_new(input, replay_key, fingerprint, deadline, configuration)

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

  defp invoke_new(input, replay_key, fingerprint, deadline, configuration) do
    result = invoke_owned_work(input, deadline, configuration)

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

  defp invoke_owned_work(input, deadline, configuration) do
    case remaining_timeout(deadline) do
      0 ->
        timeout_error()

      timeout ->
        owner = self()

        task =
          Task.Supervisor.async_nolink(
            OfficeGraph.AgentRuntime.AdapterTaskSupervisor,
            fn -> load_while_owner_alive(owner, input, configuration) end
          )

        case Task.yield(task, timeout) do
          {:ok, result} ->
            result

          {:exit, _reason} ->
            malformed_output(configuration)

          nil ->
            Task.shutdown(task, :brutal_kill)
            timeout_error()
        end
    end
  end

  defp load_while_owner_alive(owner, input, configuration) do
    owner_monitor = Process.monitor(owner)

    receive do
      {:DOWN, ^owner_monitor, :process, ^owner, _reason} ->
        malformed_output(configuration)
    after
      0 ->
        Process.flag(:trap_exit, true)
        guardian = self()
        result_ref = make_ref()

        loader =
          spawn_link(fn ->
            result = load_and_normalize(input, configuration)
            send(guardian, {result_ref, result})
          end)

        await_owned_loader(owner, owner_monitor, loader, result_ref, configuration)
    end
  end

  defp await_owned_loader(owner, owner_monitor, loader, result_ref, configuration) do
    receive do
      {^result_ref, result} ->
        await_loader_exit(owner, owner_monitor, loader, result, configuration)

      {:EXIT, ^loader, _reason} ->
        Process.demonitor(owner_monitor, [:flush])
        malformed_output(configuration)

      {:DOWN, ^owner_monitor, :process, ^owner, _reason} ->
        stop_loader(loader)
        malformed_output(configuration)

      {:EXIT, _linked_process, reason} ->
        stop_loader(loader)
        exit(reason)
    end
  end

  defp await_loader_exit(owner, owner_monitor, loader, result, configuration) do
    receive do
      {:EXIT, ^loader, :normal} ->
        Process.demonitor(owner_monitor, [:flush])
        result

      {:EXIT, ^loader, _reason} ->
        Process.demonitor(owner_monitor, [:flush])
        malformed_output(configuration)

      {:DOWN, ^owner_monitor, :process, ^owner, _reason} ->
        stop_loader(loader)
        malformed_output(configuration)

      {:EXIT, _linked_process, reason} ->
        stop_loader(loader)
        exit(reason)
    end
  end

  defp stop_loader(loader) do
    Process.exit(loader, :kill)

    receive do
      {:EXIT, ^loader, _reason} -> :ok
    end
  end

  defp load_and_normalize(input, configuration) do
    case configuration.fixture_loader.(input.adapter_payload.fixture_id) do
      {:ok, fixture} -> normalize_fixture(fixture, configuration)
      loader_result -> normalize_result(loader_result, configuration)
    end
  catch
    _kind, _reason -> malformed_output(configuration)
  end

  defp remaining_timeout(deadline) do
    max(deadline - System.monotonic_time(:millisecond), 0)
  end

  defp timeout_error, do: {:error, {:terminal, :timeout_exceeded}}

  defp malformed_output(configuration),
    do: {:error, {:terminal, configuration.malformed_output_code}}

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

      normalize_result({:ok, output}, configuration)
    else
      :error -> {:error, {:terminal, configuration.malformed_output_code}}
    end
  end

  defp normalize_fixture(result, configuration), do: normalize_result(result, configuration)

  defp normalize_result(result, configuration) do
    case AdapterResult.normalize(result) do
      {:ok, output} = normalized ->
        case configuration.validate_output.(configuration.manifest, output) do
          :ok -> normalized
          _invalid_output -> {:error, {:terminal, configuration.malformed_output_code}}
        end

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
        output_hash: output_hash(output.structured_content),
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

  defp replay_key(input),
    do: {:result, input.execution_id, input.step_key, input.idempotency_key}

  defp output_hash(structured_content) do
    structured_content
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp safe_failure_summary(failure_code, failure_code),
    do: "Adapter returned invalid structured output."

  defp safe_failure_summary(:cancelled, _malformed_output_code),
    do: "Adapter request was cancelled."

  defp safe_failure_summary(_failure_code, _malformed_output_code),
    do: "Adapter request did not complete."
end
