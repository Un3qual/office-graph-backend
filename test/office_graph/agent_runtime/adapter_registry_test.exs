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

defmodule OfficeGraph.AgentRuntime.MalformedSchemaModel do
  @behaviour OfficeGraph.AgentRuntime.ModelAdapter

  @impl true
  def manifest do
    %OfficeGraph.AgentRuntime.ModelManifest{
      OfficeGraph.AgentRuntime.Adapters.DeterministicModel.manifest()
      | input_schema: %{required: [:fixture_id], fields: nil, max_serialized_bytes: 16_384}
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

  test "resolves the migrated OpenSpec-review definition through its stored model adapter key" do
    definition = Ash.get!(AgentDefinition, %{key: "openspec-review"}, authorize?: false)

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
    assert total <= AdapterState.retention_limit()

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
    assert total == records + 1
    assert :error = AdapterState.retained(namespace, "conflict-1")
    assert :ok = AdapterState.cancel(namespace, "owner")
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
