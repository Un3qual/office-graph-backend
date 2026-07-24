defmodule OfficeGraph.AgentRuntime.InvalidManifestModel do
  @behaviour OfficeGraph.AgentRuntime.ModelAdapter

  @impl true
  def manifest, do: %{}

  @impl true
  def invoke(_input), do: {:error, {:terminal, :invalid_model_input}}

  @impl true
  def cancel(_request_id), do: {:error, :not_found}
end

defmodule OfficeGraph.AgentRuntime.CallbackOnlyModel do
  def manifest, do: OfficeGraph.AgentRuntime.Adapters.DeterministicModel.manifest()
  def invoke(_input), do: {:error, {:terminal, :invalid_model_input}}
  def cancel(_request_id), do: {:error, :not_found}
end

defmodule OfficeGraph.AgentRuntime.AuxiliaryAdapterBehaviour do
  @callback auxiliary_callback() :: :ok
end

defmodule OfficeGraph.AgentRuntime.MultiBehaviourModel do
  @behaviour OfficeGraph.AgentRuntime.AuxiliaryAdapterBehaviour
  @behaviour OfficeGraph.AgentRuntime.ModelAdapter

  @impl true
  def auxiliary_callback, do: :ok

  @impl true
  def manifest, do: OfficeGraph.AgentRuntime.Adapters.DeterministicModel.manifest()

  @impl true
  def invoke(_input), do: {:error, {:terminal, :invalid_model_input}}

  @impl true
  def cancel(_request_id), do: {:error, :not_found}
end

defmodule OfficeGraph.AgentRuntime.MalformedSchemaModel do
  @behaviour OfficeGraph.AgentRuntime.ModelAdapter

  @impl true
  def manifest do
    %OfficeGraph.AgentRuntime.ModelManifest{
      OfficeGraph.AgentRuntime.Adapters.DeterministicModel.manifest()
      | input_schema: %{required: [:adapter_payload], fields: nil, max_serialized_bytes: 16_384}
    }
  end

  @impl true
  def invoke(_input), do: {:error, {:terminal, :invalid_model_input}}

  @impl true
  def cancel(_request_id), do: {:error, :not_found}
end

defmodule OfficeGraph.AgentRuntime.RaisingManifestModel do
  @behaviour OfficeGraph.AgentRuntime.ModelAdapter

  @impl true
  def manifest, do: raise("provider detail")

  @impl true
  def invoke(_input), do: {:error, {:terminal, :invalid_model_input}}

  @impl true
  def cancel(_request_id), do: {:error, :not_found}
end

defmodule OfficeGraph.AgentRuntime.ExitingManifestModel do
  @behaviour OfficeGraph.AgentRuntime.ModelAdapter

  @impl true
  def manifest, do: exit(:provider_unavailable)

  @impl true
  def invoke(_input), do: {:error, {:terminal, :invalid_model_input}}

  @impl true
  def cancel(_request_id), do: {:error, :not_found}
end

defmodule OfficeGraph.AgentRuntime.ThrowingManifestModel do
  @behaviour OfficeGraph.AgentRuntime.ModelAdapter

  @impl true
  def manifest, do: throw(:provider_unavailable)

  @impl true
  def invoke(_input), do: {:error, {:terminal, :invalid_model_input}}

  @impl true
  def cancel(_request_id), do: {:error, :not_found}
end

defmodule OfficeGraph.AgentRuntime.AdapterRegistryTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.AgentRuntime.{
    AdapterRegistry,
    AdapterState,
    AgentDefinition,
    ModelAdapter,
    ToolAdapter
  }

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

    assert {:error, {:model, :invalid_adapter_module}} =
             AdapterRegistry.validate(%{
               models: %{"deterministic" => OfficeGraph.AgentRuntime.CallbackOnlyModel},
               tools: %{}
             })

    assert :ok =
             AdapterRegistry.validate(%{
               models: %{"deterministic" => OfficeGraph.AgentRuntime.MultiBehaviourModel},
               tools: %{}
             })

    assert {:error, {:model, :invalid_manifest}} =
             AdapterRegistry.validate(%{
               models: %{"deterministic" => OfficeGraph.AgentRuntime.MalformedSchemaModel},
               tools: %{}
             })

    assert {:error, {:registry, :invalid_configuration}} = AdapterRegistry.validate([:invalid])

    assert {:error, {:model, :invalid_manifest}} =
             AdapterRegistry.validate(%{
               models: %{"deterministic" => OfficeGraph.AgentRuntime.RaisingManifestModel},
               tools: %{}
             })

    assert {:error, {:model, :invalid_manifest}} =
             AdapterRegistry.validate(%{
               models: %{"deterministic" => OfficeGraph.AgentRuntime.ExitingManifestModel},
               tools: %{}
             })

    assert {:error, {:model, :invalid_manifest}} =
             AdapterRegistry.validate(%{
               models: %{"deterministic" => OfficeGraph.AgentRuntime.ThrowingManifestModel},
               tools: %{}
             })
  end

  test "resolves the migrated run-review definition through its stored model adapter key" do
    definition = Ash.get!(AgentDefinition, %{key: "run-review"}, authorize?: false)

    assert {:ok, DeterministicModel} = AdapterRegistry.model(definition.model_adapter_key)
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

  test "adapter state atomically bounds completed replay retention" do
    namespace = __MODULE__
    :ok = AdapterState.reset(namespace)

    for sequence <- 1..(AdapterState.retention_limit() + 1) do
      key = {:step, sequence}

      assert :claimed =
               AdapterState.claim(
                 namespace,
                 key,
                 "request-#{sequence}",
                 "fingerprint-#{sequence}"
               )

      assert {:completed, {:ok, ^sequence}} =
               AdapterState.complete(namespace, key, "fingerprint-#{sequence}", {:ok, sequence})
    end

    assert AdapterState.entry_count(namespace) <= AdapterState.retention_limit()

    assert :claimed =
             AdapterState.claim(namespace, {:step, 1}, "replacement", "replacement-fingerprint")
  end

  test "adapter state releases retryable outcomes for a later attempt" do
    namespace = {:retryable_release, make_ref()}
    :ok = AdapterState.reset(namespace)
    retryable = {:error, {:retryable, :provider_unavailable}}

    assert :claimed = AdapterState.claim(namespace, :step, "first-request", "fingerprint")

    assert {:completed, ^retryable} =
             AdapterState.complete(namespace, :step, "fingerprint", retryable)

    assert :claimed = AdapterState.claim(namespace, :step, "retry-request", "fingerprint")
  end

  test "cancelling a retryable outcome prevents a later attempt for the replay key" do
    namespace = {:retryable_cancellation, make_ref()}
    :ok = AdapterState.reset(namespace)
    retryable = {:error, {:retryable, :provider_unavailable}}

    assert :claimed = AdapterState.claim(namespace, :step, "first-request", "fingerprint")

    assert {:completed, ^retryable} =
             AdapterState.complete(namespace, :step, "fingerprint", retryable)

    assert :ok = AdapterState.cancel(namespace, "first-request")

    assert :cancelled =
             AdapterState.claim(namespace, :step, "later-request", "fingerprint")

    assert :conflict =
             AdapterState.claim(namespace, :step, "conflicting-request", "different-fingerprint")
  end

  test "adapter state accepts an explicit replay-wait timeout" do
    namespace = {:claim_timeout, make_ref()}
    :ok = AdapterState.reset(namespace)

    assert :claimed = AdapterState.claim(namespace, :step, "owner-request", "fingerprint")

    waiter =
      Task.async(fn ->
        AdapterState.claim(namespace, :step, "waiter-request", "fingerprint", 1_000)
      end)

    assert nil == Task.yield(waiter, 25)

    assert {:completed, {:ok, :done}} =
             AdapterState.complete(namespace, :step, "fingerprint", {:ok, :done})

    assert {:replay, {:ok, :done}} = Task.await(waiter)
  end

  test "adapter state returns a terminal timeout and releases the expired waiter" do
    namespace = {:claim_timeout_cleanup, make_ref()}
    :ok = AdapterState.reset(namespace)

    assert :claimed = AdapterState.claim(namespace, :step, "owner-request", "fingerprint")

    waiter =
      Task.async(fn ->
        AdapterState.claim(namespace, :step, "waiter-request", "fingerprint", 25)
      end)

    assert {:error, {:terminal, :timeout_exceeded}} = Task.await(waiter, 500)
    assert %{waiters: 0} = AdapterState.state_counts(namespace)

    assert {:completed, {:ok, :done}} =
             AdapterState.complete(namespace, :step, "fingerprint", {:ok, :done})

    assert {:error, {:terminal, :timeout_exceeded}} =
             AdapterState.claim(namespace, :step, "waiter-request", "fingerprint")
  end

  test "adapter state retention limit is configurable with a safe default" do
    namespace = {:configured_retention, make_ref()}
    configured = Application.get_env(:office_graph, :agent_runtime_retention_limit)

    on_exit(fn ->
      if configured do
        Application.put_env(:office_graph, :agent_runtime_retention_limit, configured)
      else
        Application.delete_env(:office_graph, :agent_runtime_retention_limit)
      end
    end)

    :ok = AdapterState.reset(namespace)

    for sequence <- 1..4 do
      key = {:step, sequence}
      fingerprint = "fingerprint-#{sequence}"
      assert :claimed = AdapterState.claim(namespace, key, "request-#{sequence}", fingerprint)

      assert {:completed, {:ok, ^sequence}} =
               AdapterState.complete(namespace, key, fingerprint, {:ok, sequence})
    end

    Application.put_env(:office_graph, :agent_runtime_retention_limit, 2)

    assert :claimed = AdapterState.claim(namespace, {:step, 5}, "request-5", "fingerprint-5")

    assert {:completed, {:ok, 5}} =
             AdapterState.complete(namespace, {:step, 5}, "fingerprint-5", {:ok, 5})

    assert AdapterState.retention_limit() == 2
    assert AdapterState.entry_count(namespace) == 2
  end

  test "pruning the original request preserves replay while retained replays reference it" do
    namespace = {:replay_reference_retention, make_ref()}
    configured = Application.get_env(:office_graph, :agent_runtime_retention_limit)

    on_exit(fn ->
      if configured do
        Application.put_env(:office_graph, :agent_runtime_retention_limit, configured)
      else
        Application.delete_env(:office_graph, :agent_runtime_retention_limit)
      end
    end)

    Application.put_env(:office_graph, :agent_runtime_retention_limit, 2)
    :ok = AdapterState.reset(namespace)

    assert :claimed = AdapterState.claim(namespace, :shared, "owner", "fingerprint")

    assert {:completed, {:ok, :done}} =
             AdapterState.complete(namespace, :shared, "fingerprint", {:ok, :done})

    assert {:replay, {:ok, :done}} =
             AdapterState.claim(namespace, :shared, "replay-1", "fingerprint")

    assert {:replay, {:ok, :done}} =
             AdapterState.claim(namespace, :shared, "replay-2", "fingerprint")

    assert {:replay, {:ok, :done}} =
             AdapterState.claim(namespace, :shared, "replay-3", "fingerprint")
  end

  test "adapter state cancels pending work without changing completed replay semantics" do
    namespace = __MODULE__
    :ok = AdapterState.reset(namespace)

    assert :claimed =
             AdapterState.claim(namespace, :pending, "pending-request", "pending-fingerprint")

    assert :conflict =
             AdapterState.claim(namespace, :pending, "other-request", "other-fingerprint")

    assert :ok = AdapterState.cancel(namespace, "pending-request")

    assert :cancelled =
             AdapterState.complete(namespace, :pending, "pending-fingerprint", {:ok, :late})

    assert :claimed =
             AdapterState.claim(
               namespace,
               :completed,
               "completed-request",
               "completed-fingerprint"
             )

    assert {:completed, {:ok, :done}} =
             AdapterState.complete(namespace, :completed, "completed-fingerprint", {:ok, :done})

    assert :ok = AdapterState.cancel(namespace, "completed-request")

    assert {:replay, {:ok, :done}} =
             AdapterState.claim(
               namespace,
               :completed,
               "completed-request",
               "completed-fingerprint"
             )
  end

  test "pending claims do not consume terminal retention before completion" do
    namespace = {:pending_retention, make_ref()}
    :ok = AdapterState.reset(namespace)

    owners =
      for sequence <- 1..(AdapterState.retention_limit() + 1) do
        start_claim_owner(
          namespace,
          {:pending, sequence},
          "request-#{sequence}",
          "fp-#{sequence}"
        )
      end

    Enum.each(owners, fn {_owner, sequence} ->
      assert_receive {:claim_owner, ^sequence, :claimed}
    end)

    assert %{pending: pending, terminal: 0, records: 0, total: total} =
             AdapterState.state_counts(namespace)

    assert pending == AdapterState.retention_limit() + 1
    assert total == pending

    {owner, _sequence} = hd(owners)
    send(owner, {:complete, {:ok, :done}})
    assert_receive {:claim_owner_complete, {:completed, {:ok, :done}}}

    assert {:replay, {:ok, :done}} =
             AdapterState.claim(namespace, {:pending, 1}, "request-1", "fp-1")

    Enum.each(tl(owners), fn {pending_owner, _sequence} -> Process.exit(pending_owner, :kill) end)
  end

  test "all non-active request state is bounded with retained metadata" do
    namespace = {:bounded_records, make_ref()}
    :ok = AdapterState.reset(namespace)

    for sequence <- 1..(AdapterState.retention_limit() + 5) do
      request_id = "registered-#{sequence}"
      assert :ok = AdapterState.register(namespace, request_id)
      assert :ok = AdapterState.cancel(namespace, request_id)
      assert :ok = AdapterState.put_retained(namespace, request_id, %{failure_code: :cancelled})
    end

    assert %{pending: 0, terminal: 0, records: records, retained: retained, total: total} =
             AdapterState.state_counts(namespace)

    assert records <= AdapterState.retention_limit()
    assert retained <= AdapterState.retention_limit()
    assert total == records + retained

    assert :error = AdapterState.retained(namespace, "registered-1")

    assert {:ok, %{failure_code: :cancelled}} =
             AdapterState.retained(namespace, "registered-#{AdapterState.retention_limit() + 5}")
  end

  test "fresh conflicting request ids remain bounded with their safe retained metadata" do
    namespace = {:bounded_conflicts, make_ref()}
    :ok = AdapterState.reset(namespace)

    assert :claimed = AdapterState.claim(namespace, :shared, "owner", "owner-fingerprint")

    for sequence <- 1..(AdapterState.retention_limit() + 5) do
      request_id = "conflict-#{sequence}"

      assert :conflict =
               AdapterState.claim(namespace, :shared, request_id, "conflict-#{sequence}")

      assert :ok =
               AdapterState.put_retained(namespace, request_id, %{
                 failure_code: :idempotency_conflict
               })
    end

    assert %{pending: 1, terminal: terminal, records: records, retained: retained, total: total} =
             AdapterState.state_counts(namespace)

    assert terminal <= AdapterState.retention_limit()
    assert records <= AdapterState.retention_limit()
    assert retained <= AdapterState.retention_limit()
    assert total == records + retained + 1
    assert :error = AdapterState.retained(namespace, "conflict-1")
    assert :ok = AdapterState.cancel(namespace, "owner")
  end

  test "a request id is bound to one active and terminal replay identity" do
    namespace = {:request_binding, make_ref()}
    :ok = AdapterState.reset(namespace)

    assert :claimed = AdapterState.claim(namespace, :first, "request", "first-fingerprint")

    assert :identity_conflict =
             AdapterState.claim(namespace, :second, "request", "second-fingerprint")

    assert {:completed, {:ok, :first}} =
             AdapterState.complete(namespace, :first, "first-fingerprint", {:ok, :first})

    assert {:replay, {:ok, :first}} =
             AdapterState.claim(namespace, :first, "request", "first-fingerprint")

    assert :identity_conflict =
             AdapterState.claim(namespace, :second, "request", "second-fingerprint")

    assert {:replay, {:ok, :first}} =
             AdapterState.claim(namespace, :first, "request", "first-fingerprint")

    assert %{pending: 0, terminal: 1, records: 1, retained: 0, total: 2} =
             AdapterState.state_counts(namespace)
  end

  test "pruning a distinct conflict preserves the original terminal replay" do
    namespace = {:conflict_pruning, make_ref()}
    :ok = AdapterState.reset(namespace)

    assert :claimed = AdapterState.claim(namespace, :shared, "original", "original-fingerprint")

    assert {:completed, {:ok, :original}} =
             AdapterState.complete(namespace, :shared, "original-fingerprint", {:ok, :original})

    assert :conflict =
             AdapterState.claim(namespace, :shared, "conflict", "conflict-fingerprint")

    assert {:replay, {:ok, :original}} =
             AdapterState.claim(namespace, :shared, "original", "original-fingerprint")

    for sequence <- 1..(AdapterState.retention_limit() - 1) do
      request_id = "cancelled-#{sequence}"
      assert :ok = AdapterState.register(namespace, request_id)
      assert :ok = AdapterState.cancel(namespace, request_id)
    end

    assert {:replay, {:ok, :original}} =
             AdapterState.claim(namespace, :shared, "original", "original-fingerprint")
  end

  test "a retained conflict keeps its replay entry terminal" do
    namespace = {:retained_conflict, make_ref()}
    configured = Application.get_env(:office_graph, :agent_runtime_retention_limit)

    on_exit(fn ->
      if configured do
        Application.put_env(:office_graph, :agent_runtime_retention_limit, configured)
      else
        Application.delete_env(:office_graph, :agent_runtime_retention_limit)
      end
    end)

    Application.put_env(:office_graph, :agent_runtime_retention_limit, 2)
    :ok = AdapterState.reset(namespace)

    assert :claimed = AdapterState.claim(namespace, :shared, "original", "original-fingerprint")

    assert {:completed, {:ok, :original}} =
             AdapterState.complete(namespace, :shared, "original-fingerprint", {:ok, :original})

    assert :conflict =
             AdapterState.claim(namespace, :shared, "conflict", "conflict-fingerprint")

    assert :ok = AdapterState.register(namespace, "newer-request")

    assert :conflict =
             AdapterState.claim(namespace, :shared, "conflict", "conflict-fingerprint")

    assert {:replay, {:ok, :original}} =
             AdapterState.claim(namespace, :shared, "later-replay", "original-fingerprint")
  end

  test "reset cancels blocked waiters and drops active state" do
    namespace = {:reset, make_ref()}
    :ok = AdapterState.reset(namespace)

    {owner, _sequence} =
      start_claim_owner(namespace, :shared, "owner-request", "shared-fingerprint")

    assert_receive {:claim_owner, 1, :claimed}

    waiter =
      Task.async(fn ->
        AdapterState.claim(namespace, :shared, "waiter-request", "shared-fingerprint")
      end)

    assert nil == Task.yield(waiter, 50)
    assert :ok = AdapterState.reset(namespace)
    assert :cancelled = Task.await(waiter, 500)

    send(owner, {:complete, {:ok, :after_reset}})
    assert_receive {:claim_owner_complete, :conflict}

    assert %{pending: 0, terminal: 0, records: 0, retained: 0, total: 0} =
             AdapterState.state_counts(namespace)
  end

  test "cancelled replay waiters cannot rejoin the pending claim" do
    namespace = {:cancelled_waiter, make_ref()}
    :ok = AdapterState.reset(namespace)

    {owner, _sequence} =
      start_claim_owner(namespace, :shared, "owner-request", "shared-fingerprint")

    assert_receive {:claim_owner, 1, :claimed}

    waiter =
      Task.async(fn ->
        AdapterState.claim(namespace, :shared, "waiter-request", "shared-fingerprint")
      end)

    assert nil == Task.yield(waiter, 50)
    assert :ok = AdapterState.cancel(namespace, "waiter-request")
    assert :cancelled = Task.await(waiter, 500)

    reclaim =
      Task.async(fn ->
        AdapterState.claim(
          namespace,
          :shared,
          "waiter-request",
          "shared-fingerprint",
          1_000
        )
      end)

    assert {:ok, :cancelled} = Task.yield(reclaim, 100)

    send(owner, {:complete, {:ok, :done}})
    assert_receive {:claim_owner_complete, {:completed, {:ok, :done}}}
  end

  test "active-owner cancellation permits only safe retained metadata" do
    namespace = {:owner_cancellation, make_ref()}
    :ok = AdapterState.reset(namespace)

    {owner, _sequence} =
      start_claim_owner(namespace, :shared, "owner-request", "shared-fingerprint")

    assert_receive {:claim_owner, 1, :claimed}
    assert :ok = AdapterState.cancel(namespace, "owner-request")

    assert :ok =
             AdapterState.put_retained(namespace, "owner-request", %{failure_code: :cancelled})

    send(owner, {:complete, {:ok, :late}})
    assert_receive {:claim_owner_complete, :cancelled}

    assert {:ok, %{failure_code: :cancelled}} =
             AdapterState.retained(namespace, "owner-request")
  end

  test "owner death promotes one waiting claimant and rejects non-owner completion" do
    namespace = {:owner_death, make_ref()}
    :ok = AdapterState.reset(namespace)

    {owner, _sequence} =
      start_claim_owner(namespace, :shared, "owner-request", "shared-fingerprint")

    assert_receive {:claim_owner, 1, :claimed}

    {waiter, _sequence} =
      start_claim_owner(namespace, :shared, "waiter-request", "shared-fingerprint")

    refute_receive {:claim_owner, 1, :claimed}, 50

    assert :conflict =
             AdapterState.complete(namespace, :shared, "shared-fingerprint", {:ok, :wrong_owner})

    Process.exit(owner, :kill)

    assert_receive {:claim_owner, 1, :claimed}
    send(waiter, {:complete, {:ok, :recovered}})
    assert_receive {:claim_owner_complete, {:completed, {:ok, :recovered}}}

    assert {:replay, {:ok, :recovered}} =
             AdapterState.claim(namespace, :shared, "takeover-request", "shared-fingerprint")
  end

  test "cancelling an abandoned owner terminalizes its promoted replay claim" do
    namespace = {:abandoned_owner_cancellation, make_ref()}
    :ok = AdapterState.reset(namespace)

    {owner, _sequence} =
      start_claim_owner(namespace, :shared, "owner-request", "shared-fingerprint")

    assert_receive {:claim_owner, 1, :claimed}

    {promoted, _sequence} =
      start_claim_owner(namespace, :shared, "retry-request", "shared-fingerprint")

    refute_receive {:claim_owner, 1, :claimed}, 50
    Process.exit(owner, :kill)
    assert_receive {:claim_owner, 1, :claimed}

    assert :ok = AdapterState.cancel(namespace, "owner-request")
    send(promoted, {:complete, {:ok, :late}})
    assert_receive {:claim_owner_complete, :cancelled}

    assert :cancelled =
             AdapterState.claim(namespace, :shared, "later-request", "shared-fingerprint")
  end

  test "one claim executes while same-fingerprint callers wait and replay" do
    namespace = {:single_claim, make_ref()}
    :ok = AdapterState.reset(namespace)

    {owner, _sequence} =
      start_claim_owner(namespace, :single, "owner-request", "single-fingerprint")

    assert_receive {:claim_owner, 1, :claimed}

    waiters =
      for sequence <- 1..5 do
        Task.async(fn ->
          AdapterState.claim(namespace, :single, "waiter-#{sequence}", "single-fingerprint")
        end)
      end

    assert Enum.all?(waiters, &(Task.yield(&1, 50) == nil))
    send(owner, {:complete, {:ok, :once}})
    assert_receive {:claim_owner_complete, {:completed, {:ok, :once}}}
    assert Enum.all?(waiters, &(Task.await(&1) == {:replay, {:ok, :once}}))
  end

  defp start_claim_owner(namespace, key, request_id, fingerprint) do
    parent = self()
    sequence = if is_tuple(key), do: elem(key, 1), else: 1

    owner =
      spawn(fn ->
        result = AdapterState.claim(namespace, key, request_id, fingerprint)
        send(parent, {:claim_owner, sequence, result})

        receive do
          {:complete, result} ->
            send(
              parent,
              {:claim_owner_complete, AdapterState.complete(namespace, key, fingerprint, result)}
            )
        end
      end)

    {owner, sequence}
  end
end
