defmodule OfficeGraph.AgentRuntime.ModelAdapterConformanceTest do
  use ExUnit.Case, async: false

  alias OfficeGraph.AgentRuntime.{
    AdapterContract,
    AdapterResult,
    AdapterState,
    ModelInput,
    ModelManifest,
    ModelOutput
  }

  alias OfficeGraph.AgentRuntime.Adapters.{DeterministicModel, DeterministicRuntime}
  alias OfficeGraph.AgentRuntime.Adapters.DeterministicRuntime.Configuration

  setup do
    :ok = DeterministicModel.reset()

    on_exit(fn -> DeterministicModel.reset() end)

    %{input: model_input("proposal")}
  end

  test "has a complete fail-closed manifest" do
    manifest = DeterministicModel.manifest()

    assert manifest.key != ""
    assert manifest.version != ""
    assert is_map(manifest.input_schema)
    assert is_map(manifest.output_schema)
    assert manifest.input_schema.required == [:adapter_payload]
    assert {:map, adapter_payload_schema} = manifest.input_schema.fields.adapter_payload
    assert adapter_payload_schema.fields.fixture_id == :string

    assert manifest.output_schema.required == [
             :classification,
             :safe_summary,
             :structured_content
           ]

    assert manifest.output_schema.fields.structured_content == :classified_content
    assert manifest.timeout_ms in 1_000..120_000
    assert manifest.token_budget > 0
    assert [_ | _] = manifest.capability_keys
    assert manifest.credential_kinds == []
    assert manifest.external_write == false
    assert manifest.raw_retention == false
    assert manifest.idempotency_supported == true
  end

  test "model manifests require at least one declared capability", %{input: input} do
    manifest = %{DeterministicModel.manifest() | capability_keys: []}

    refute AdapterContract.valid_model_manifest?(manifest)

    assert {:error, {:terminal, :invalid_model_input}} =
             AdapterContract.validate_model_input(manifest, %{input | capability_keys: []})
  end

  test "keeps deterministic fixture selection inside the adapter-specific payload" do
    fields = ModelInput.__struct__() |> Map.keys()

    assert :adapter_payload in fields
    refute :fixture_id in fields
  end

  test "returns a classified structured proposal without retaining fixture content", %{
    input: input
  } do
    assert {:ok,
            output = %ModelOutput{
              classification: :proposal,
              safe_summary: "Propose a bounded follow-up"
            }} =
             DeterministicModel.invoke(input)

    retained = DeterministicModel.retained_request!(input.request_id)
    assert retained.classification == :proposal
    assert retained.safe_summary == "Propose a bounded follow-up"

    assert retained.output_hash ==
             output.structured_content
             |> :erlang.term_to_binary([:deterministic])
             |> then(&:crypto.hash(:sha256, &1))
             |> Base.encode16(case: :lower)

    assert byte_size(retained.output_hash) == 64

    refute Map.has_key?(retained, :structured_content)
    refute inspect(retained) =~ "fixture"
  end

  test "retained output hashes use canonical structured-content encoding", %{input: input} do
    namespace = {:canonical_output_hash, make_ref()}
    fields = Map.new(1..40, &{"field-#{&1}", :string})
    content = Map.new(1..40, &{"field-#{&1}", "value-#{&1}"})
    structured_content = %{"proposal" => content}

    manifest =
      put_in(
        DeterministicModel.manifest().output_schema.content_schemas.proposal,
        %{
          required: Map.keys(fields),
          fields: fields,
          max_serialized_bytes: 16_384
        }
      )

    request = %{input | request_id: uuid(), idempotency_key: "canonical-output-hash"}

    output = %ModelOutput{
      classification: :proposal,
      safe_summary: "Canonical content",
      structured_content: structured_content
    }

    configuration = %Configuration{
      fixture_loader: fn _fixture_id -> {:ok, {:ok, output}} end,
      malformed_output_code: :malformed_model_output,
      manifest: manifest,
      output_module: ModelOutput,
      state_namespace: namespace,
      validate_output: &AdapterContract.validate_model_output/2
    }

    assert {:ok, %ModelOutput{}} = DeterministicRuntime.invoke(request, configuration)
    assert {:ok, retained} = AdapterState.retained(namespace, request.request_id)

    expected_hash =
      structured_content
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    assert retained.output_hash == expected_hash
  end

  test "classifies declared retryable and terminal fixtures", %{input: input} do
    assert {:error, {:retryable, :provider_unavailable}} =
             DeterministicModel.invoke(%{
               input
               | adapter_payload: %{fixture_id: "retryable"},
                 request_id: uuid(),
                 idempotency_key: "retry-step"
             })

    assert {:error, {:terminal, :invalid_request}} =
             DeterministicModel.invoke(%{
               input
               | adapter_payload: %{fixture_id: "terminal"},
                 request_id: uuid(),
                 idempotency_key: "terminal-step"
             })
  end

  test "retains safe metadata for retryable attempts", %{input: input} do
    retryable = %{
      input
      | adapter_payload: %{fixture_id: "retryable"},
        request_id: uuid(),
        idempotency_key: "retained-retry-step"
    }

    assert {:error, {:retryable, :provider_unavailable}} =
             DeterministicModel.invoke(retryable)

    assert %{
             classification: :retryable,
             failure_code: :provider_unavailable,
             safe_summary: "Adapter request did not complete."
           } = DeterministicModel.retained_request!(retryable.request_id)
  end

  test "retryable metadata is replaced by final same-request metadata" do
    retryable_result = {:error, {:retryable, :provider_unavailable}}
    retryable_metadata = %{classification: :retryable, failure_code: :provider_unavailable}

    final_outcomes = [
      {:success, {:ok, :recovered}, %{classification: :proposal, output_hash: "00"}},
      {:terminal, {:error, {:terminal, :invalid_request}},
       %{classification: :terminal, failure_code: :invalid_request}}
    ]

    Enum.each(final_outcomes, fn {label, final_result, final_metadata} ->
      namespace = {:retryable_metadata_refresh, label, make_ref()}
      key = :shared_result
      request_id = "same-request"
      fingerprint = "same-input"

      assert :claimed = AdapterState.claim(namespace, key, request_id, fingerprint)

      assert {:completed, ^retryable_result} =
               AdapterState.complete(namespace, key, fingerprint, retryable_result)

      assert :ok = AdapterState.put_retained(namespace, request_id, retryable_metadata)
      assert {:ok, ^retryable_metadata} = AdapterState.retained(namespace, request_id)

      assert :claimed = AdapterState.claim(namespace, key, request_id, fingerprint)

      assert {:completed, ^final_result} =
               AdapterState.complete(namespace, key, fingerprint, final_result)

      assert :ok = AdapterState.put_retained(namespace, request_id, final_metadata)
      assert {:ok, ^final_metadata} = AdapterState.retained(namespace, request_id)
    end)
  end

  test "malformed output is terminal and retained only as safe metadata", %{input: input} do
    malformed = %{input | adapter_payload: %{fixture_id: "malformed"}}

    assert {:error, {:terminal, :malformed_model_output}} = DeterministicModel.invoke(malformed)

    retained = DeterministicModel.retained_request!(malformed.request_id)
    assert retained.failure_code == :malformed_model_output
    refute retained.safe_summary =~ "fixture"
  end

  test "enforces manifest limits and idempotency without reinvoking the fixture", %{input: input} do
    shorter_timeout = %{
      input
      | request_id: uuid(),
        timeout_ms: 500,
        idempotency_key: "short-timeout"
    }

    assert {:ok, _output} = DeterministicModel.invoke(shorter_timeout)

    assert {:error, {:terminal, :timeout_exceeded}} =
             DeterministicModel.invoke(%{
               input
               | timeout_ms: 1_001,
                 idempotency_key: "timeout-step"
             })

    assert {:error, {:terminal, :token_budget_exceeded}} =
             DeterministicModel.invoke(%{
               input
               | token_budget: 10_001,
                 idempotency_key: "budget-step"
             })

    assert {:ok, output} = DeterministicModel.invoke(input)
    assert {:ok, ^output} = DeterministicModel.invoke(input)
  end

  test "replay wait timeouts are classified, retained, and removed from pending state", %{
    input: input
  } do
    parent = self()
    namespace = {:replay_wait_timeout, make_ref()}
    request = %{input | timeout_ms: 25, idempotency_key: "claim-timeout"}

    replay_key =
      {:result, request.execution_id, request.step_key, request.idempotency_key}

    fingerprint = AdapterContract.fingerprint(request)

    output = %ModelOutput{
      classification: :proposal,
      safe_summary: "Completed after waiter timeout",
      structured_content: %{"proposal" => %{"intent" => "follow_up"}}
    }

    configuration = %Configuration{
      fixture_loader: fn _fixture_id ->
        send(parent, :unexpected_fixture_invocation)
        {:error, {:terminal, :fixture_should_not_run}}
      end,
      malformed_output_code: :malformed_model_output,
      manifest: DeterministicModel.manifest(),
      output_module: ModelOutput,
      state_namespace: namespace,
      validate_output: &AdapterContract.validate_model_output/2
    }

    owner =
      Task.async(fn ->
        assert :claimed =
                 AdapterState.claim(namespace, replay_key, "manual-owner", fingerprint)

        send(parent, :manual_owner_claimed)

        receive do
          :complete -> AdapterState.complete(namespace, replay_key, fingerprint, {:ok, output})
        end
      end)

    assert_receive :manual_owner_claimed

    assert {:error, {:terminal, :timeout_exceeded}} =
             DeterministicRuntime.invoke(request, configuration)

    assert {:ok, %{classification: :terminal, failure_code: :timeout_exceeded}} =
             AdapterState.retained(namespace, request.request_id)

    assert %{waiters: 0} = AdapterState.state_counts(namespace)
    send(owner.pid, :complete)
    assert {:completed, {:ok, ^output}} = Task.await(owner, 500)

    assert {:error, {:terminal, :timeout_exceeded}} =
             DeterministicRuntime.invoke(request, configuration)

    assert {:ok, ^output} =
             DeterministicRuntime.invoke(%{request | request_id: uuid()}, configuration)

    refute_received :unexpected_fixture_invocation
  end

  test "owned adapter work is terminated at the request deadline", %{input: input} do
    parent = self()
    namespace = {:owned_work_timeout, make_ref()}
    request = %{input | timeout_ms: 25, idempotency_key: "owned-work-timeout"}

    configuration = %Configuration{
      fixture_loader: fn _fixture_id ->
        send(parent, {:owned_fixture_started, self()})
        Process.sleep(200)

        {:ok,
         %{
           "classification" => "proposal",
           "safe_summary" => "Completed too late",
           "structured_content" => %{"proposal" => %{"intent" => "follow_up"}}
         }}
      end,
      malformed_output_code: :malformed_model_output,
      manifest: DeterministicModel.manifest(),
      output_module: ModelOutput,
      state_namespace: namespace,
      validate_output: &AdapterContract.validate_model_output/2
    }

    assert {:error, {:terminal, :timeout_exceeded}} =
             DeterministicRuntime.invoke(request, configuration)

    assert_receive {:owned_fixture_started, fixture_pid}
    refute fixture_pid == self()

    monitor = Process.monitor(fixture_pid)
    assert_receive {:DOWN, ^monitor, :process, ^fixture_pid, _reason}, 100

    assert {:ok, %{classification: :terminal, failure_code: :timeout_exceeded}} =
             AdapterState.retained(namespace, request.request_id)
  end

  test "cancel-target attachment cannot deliver completed work after the request deadline", %{
    input: input
  } do
    parent = self()
    namespace = {:cancel_target_attachment_deadline, make_ref()}

    request = %{
      input
      | request_id: uuid(),
        idempotency_key: "cancel-target-attachment-deadline",
        timeout_ms: 40
    }

    configuration = %Configuration{
      fixture_loader: fn _fixture_id ->
        send(parent, :attachment_deadline_fixture_completed)

        {:ok,
         %{
           "classification" => "proposal",
           "safe_summary" => "Completed while state was backlogged",
           "structured_content" => %{"proposal" => %{"intent" => "follow_up"}}
         }}
      end,
      malformed_output_code: :malformed_model_output,
      manifest: DeterministicModel.manifest(),
      output_module: ModelOutput,
      state_namespace: namespace,
      validate_output: &AdapterContract.validate_model_output/2
    }

    invocation =
      Task.async(fn ->
        Process.flag(:priority, :low)

        receive do
          :invoke -> DeterministicRuntime.invoke(request, configuration)
        end
      end)

    :erlang.trace_pattern(
      {AdapterState, :claim, 5},
      [{:_, [], [{:return_trace}]}],
      [:local]
    )

    :erlang.trace(invocation.pid, true, [:call, {:tracer, self()}])
    send(invocation.pid, :invoke)

    assert_receive {:trace, pid, :return_from, {AdapterState, :claim, 5}, :claimed}
                   when pid == invocation.pid,
                   500

    :ok = :sys.suspend(AdapterState)

    try do
      assert_receive :attachment_deadline_fixture_completed, 500
      Process.sleep(request.timeout_ms + 10)
      assert nil == Task.yield(invocation, 0)
    after
      :erlang.trace(invocation.pid, false, [:call])
      :erlang.trace_pattern({AdapterState, :claim, 5}, false, [:local])
      :ok = :sys.resume(AdapterState)
    end

    assert {:error, {:terminal, :timeout_exceeded}} = Task.await(invocation, 500)

    assert {:ok, %{classification: :terminal, failure_code: :timeout_exceeded}} =
             AdapterState.retained(namespace, request.request_id)
  end

  test "owned adapter process failures are isolated and classified", %{input: input} do
    parent = self()
    namespace = {:owned_work_failure, make_ref()}
    request = %{input | request_id: uuid(), idempotency_key: "owned-work-failure"}

    configuration = %Configuration{
      fixture_loader: fn _fixture_id -> Process.exit(self(), :kill) end,
      malformed_output_code: :malformed_model_output,
      manifest: DeterministicModel.manifest(),
      output_module: ModelOutput,
      state_namespace: namespace,
      validate_output: &AdapterContract.validate_model_output/2
    }

    {caller, monitor} =
      spawn_monitor(fn ->
        send(
          parent,
          {:isolated_result, self(), DeterministicRuntime.invoke(request, configuration)}
        )
      end)

    assert_receive {:isolated_result, ^caller, {:error, {:terminal, :malformed_model_output}}},
                   500

    assert_receive {:DOWN, ^monitor, :process, ^caller, :normal}, 500

    assert {:ok, %{classification: :terminal, failure_code: :malformed_model_output}} =
             AdapterState.retained(namespace, request.request_id)
  end

  test "owned adapter work stops when the owning caller exits", %{input: input} do
    parent = self()
    namespace = {:owned_work_caller_exit, make_ref()}
    request = %{input | request_id: uuid(), idempotency_key: "owned-work-caller-exit"}

    configuration = %Configuration{
      fixture_loader: fn _fixture_id ->
        send(parent, {:caller_owned_fixture_started, self()})

        receive do
          :release -> {:error, {:terminal, :released_after_owner_exit}}
        end
      end,
      malformed_output_code: :malformed_model_output,
      manifest: DeterministicModel.manifest(),
      output_module: ModelOutput,
      state_namespace: namespace,
      validate_output: &AdapterContract.validate_model_output/2
    }

    caller = spawn(fn -> DeterministicRuntime.invoke(request, configuration) end)

    assert_receive {:caller_owned_fixture_started, fixture_pid}, 500

    on_exit(fn ->
      if Process.alive?(fixture_pid), do: Process.exit(fixture_pid, :kill)
    end)

    fixture_monitor = Process.monitor(fixture_pid)
    Process.exit(caller, :kill)

    assert_receive {:DOWN, ^fixture_monitor, :process, ^fixture_pid, _reason}, 500
    assert_pending_count(namespace, 0)
  end

  test "active cancellation stops owned adapter work without waiting for its deadline", %{
    input: input
  } do
    parent = self()
    namespace = {:owned_work_cancellation, make_ref()}

    request = %{
      input
      | request_id: uuid(),
        idempotency_key: "owned-work-cancellation",
        timeout_ms: 1_000
    }

    configuration = %Configuration{
      fixture_loader: fn _fixture_id ->
        send(parent, {:cancelled_fixture_started, self()})

        receive do
          :release -> {:error, {:terminal, :released_after_cancellation}}
        end
      end,
      malformed_output_code: :malformed_model_output,
      manifest: DeterministicModel.manifest(),
      output_module: ModelOutput,
      state_namespace: namespace,
      validate_output: &AdapterContract.validate_model_output/2
    }

    invocation = Task.async(fn -> DeterministicRuntime.invoke(request, configuration) end)

    on_exit(fn ->
      if Process.alive?(invocation.pid), do: Task.shutdown(invocation, :brutal_kill)
    end)

    assert_receive {:cancelled_fixture_started, fixture_pid}, 500
    fixture_monitor = Process.monitor(fixture_pid)

    assert :ok = AdapterState.cancel(namespace, request.request_id)

    assert {:ok, {:error, {:cancelled, :cancelled}}} = Task.yield(invocation, 200)
    assert_receive {:DOWN, ^fixture_monitor, :process, ^fixture_pid, _reason}, 200
  end

  test "unclassified fixture loader failures fail closed and replay safely", %{input: input} do
    parent = self()

    Enum.each([error_atom: :error, error_tuple: {:error, :enoent}], fn {label, loader_result} ->
      namespace = {:unclassified_loader_failure, label, make_ref()}

      request = %{
        input
        | request_id: uuid(),
          idempotency_key: "unclassified-loader-#{label}"
      }

      configuration = %Configuration{
        fixture_loader: fn _fixture_id ->
          send(parent, {:fixture_loader_called, label})
          loader_result
        end,
        malformed_output_code: :malformed_model_output,
        manifest: DeterministicModel.manifest(),
        output_module: ModelOutput,
        state_namespace: namespace,
        validate_output: &AdapterContract.validate_model_output/2
      }

      assert {:error, {:terminal, :malformed_model_output}} =
               DeterministicRuntime.invoke(request, configuration)

      replay = %{request | request_id: uuid()}

      assert {:error, {:terminal, :malformed_model_output}} =
               DeterministicRuntime.invoke(replay, configuration)

      assert_received {:fixture_loader_called, ^label}
      refute_received {:fixture_loader_called, ^label}

      assert {:ok, %{classification: :terminal, failure_code: :malformed_model_output}} =
               AdapterState.retained(namespace, request.request_id)

      assert {:ok, %{classification: :terminal, failure_code: :malformed_model_output}} =
               AdapterState.retained(namespace, replay.request_id)
    end)
  end

  test "a waiter remains timed out when completion is queued before timeout cleanup" do
    namespace = {:timeout_completion_race, make_ref()}
    key = :shared_result
    fingerprint = "same-input"
    parent = self()

    owner =
      Task.async(fn ->
        assert :claimed = AdapterState.claim(namespace, key, "owner", fingerprint)
        send(parent, :owner_claimed)

        receive do
          :complete ->
            AdapterState.complete(namespace, key, fingerprint, {:ok, :finished})
        end
      end)

    assert_receive :owner_claimed
    :ok = :sys.suspend(AdapterState)

    waiter =
      try do
        waiter =
          Task.async(fn ->
            AdapterState.claim(namespace, key, "waiter", fingerprint, 20)
          end)

        assert_server_queue_length(1)
        send(owner.pid, :complete)
        assert_server_queue_length(2)
        assert_server_queue_length(3)
        waiter
      after
        :ok = :sys.resume(AdapterState)
      end

    assert {:error, {:terminal, :timeout_exceeded}} = Task.await(waiter, 500)
    assert {:completed, {:ok, :finished}} = Task.await(owner, 500)

    assert {:error, {:terminal, :timeout_exceeded}} =
             AdapterState.claim(namespace, key, "waiter", fingerprint)

    assert {:replay, {:ok, :finished}} =
             AdapterState.claim(namespace, key, "later-request", fingerprint)
  end

  test "a waiter remains timed out when retryable completion is queued before cleanup" do
    namespace = {:timeout_retryable_race, make_ref()}
    key = :shared_result
    fingerprint = "same-input"
    retryable_result = {:error, {:retryable, :provider_unavailable}}
    parent = self()

    owner =
      Task.async(fn ->
        assert :claimed = AdapterState.claim(namespace, key, "owner", fingerprint)
        send(parent, :retryable_owner_claimed)

        receive do
          :complete_retryable ->
            AdapterState.complete(namespace, key, fingerprint, retryable_result)
        end
      end)

    assert_receive :retryable_owner_claimed
    :ok = :sys.suspend(AdapterState)

    waiter =
      try do
        waiter =
          Task.async(fn ->
            AdapterState.claim(namespace, key, "waiter", fingerprint, 20)
          end)

        assert_server_queue_length(1)
        send(owner.pid, :complete_retryable)
        assert_server_queue_length(2)
        assert_server_queue_length(3)
        waiter
      after
        :ok = :sys.resume(AdapterState)
      end

    assert {:error, {:terminal, :timeout_exceeded}} = Task.await(waiter, 500)
    assert {:completed, ^retryable_result} = Task.await(owner, 500)

    assert {:error, {:terminal, :timeout_exceeded}} =
             AdapterState.claim(namespace, key, "waiter", fingerprint)

    assert :claimed = AdapterState.claim(namespace, key, "later-request", fingerprint)
    assert :ok = AdapterState.cancel(namespace, "later-request")
  end

  test "a waiter remains timed out when owner cancellation is queued before cleanup" do
    namespace = {:timeout_cancellation_race, make_ref()}
    key = :shared_result
    fingerprint = "same-input"
    parent = self()

    owner =
      Task.async(fn ->
        assert :claimed = AdapterState.claim(namespace, key, "owner", fingerprint)
        send(parent, :cancellation_owner_claimed)

        receive do
          :stop -> :stopped
        end
      end)

    assert_receive :cancellation_owner_claimed
    :ok = :sys.suspend(AdapterState)

    {waiter, cancellation} =
      try do
        waiter =
          Task.async(fn ->
            AdapterState.claim(namespace, key, "waiter", fingerprint, 20)
          end)

        assert_server_queue_length(1)
        cancellation = Task.async(fn -> AdapterState.cancel(namespace, "owner") end)
        assert_server_queue_length(2)
        assert_server_queue_length(3)
        {waiter, cancellation}
      after
        :ok = :sys.resume(AdapterState)
      end

    assert {:error, {:terminal, :timeout_exceeded}} = Task.await(waiter, 500)
    assert :ok = Task.await(cancellation, 500)

    assert {:error, {:terminal, :timeout_exceeded}} =
             AdapterState.claim(namespace, key, "waiter", fingerprint)

    send(owner.pid, :stop)
    assert :stopped = Task.await(owner, 500)
  end

  test "a waiter remains timed out when its cancellation is queued before cleanup" do
    namespace = {:timeout_waiter_cancellation_race, make_ref()}
    key = :shared_result
    fingerprint = "same-input"
    parent = self()

    owner =
      Task.async(fn ->
        assert :claimed = AdapterState.claim(namespace, key, "owner", fingerprint)
        send(parent, :waiter_cancellation_owner_claimed)

        receive do
          :stop -> :stopped
        end
      end)

    assert_receive :waiter_cancellation_owner_claimed
    :ok = :sys.suspend(AdapterState)

    {waiter, cancellation} =
      try do
        waiter =
          Task.async(fn ->
            AdapterState.claim(namespace, key, "waiter", fingerprint, 20)
          end)

        assert_server_queue_length(1)
        cancellation = Task.async(fn -> AdapterState.cancel(namespace, "waiter") end)
        assert_server_queue_length(2)
        assert_server_queue_length(3)
        {waiter, cancellation}
      after
        :ok = :sys.resume(AdapterState)
      end

    assert {:error, {:terminal, :timeout_exceeded}} = Task.await(waiter, 500)
    assert :ok = Task.await(cancellation, 500)

    assert {:error, {:terminal, :timeout_exceeded}} =
             AdapterState.claim(namespace, key, "waiter", fingerprint)

    send(owner.pid, :stop)
    assert :stopped = Task.await(owner, 500)
  end

  test "an owner remains timed out when cancellation is queued before timeout cleanup" do
    namespace = {:timeout_owner_cancellation_race, make_ref()}
    key = :shared_result
    fingerprint = "same-input"
    :ok = :sys.suspend(AdapterState)

    {owner, cancellation} =
      try do
        owner =
          Task.async(fn ->
            AdapterState.claim(namespace, key, "owner", fingerprint, 20)
          end)

        assert_server_queue_length(1)
        cancellation = Task.async(fn -> AdapterState.cancel(namespace, "owner") end)
        assert_server_queue_length(2)
        assert_server_queue_length(3)
        {owner, cancellation}
      after
        :ok = :sys.resume(AdapterState)
      end

    assert {:error, {:terminal, :timeout_exceeded}} = Task.await(owner, 500)
    assert :ok = Task.await(cancellation, 500)

    assert {:error, {:terminal, :timeout_exceeded}} =
             AdapterState.claim(namespace, key, "owner", fingerprint)
  end

  test "a cancelled replay remains timed out when delivery is queued before cleanup" do
    namespace = {:timeout_cancelled_replay_race, make_ref()}
    key = :shared_result
    fingerprint = "same-input"

    assert :claimed = AdapterState.claim(namespace, key, "owner", fingerprint)
    assert :ok = AdapterState.cancel(namespace, "owner")
    :ok = :sys.suspend(AdapterState)

    timed_out_claim =
      try do
        claim =
          Task.async(fn ->
            AdapterState.claim(namespace, key, "timed-out", fingerprint, 20)
          end)

        assert_server_queue_length(1)
        Process.sleep(25)
        assert_server_queue_length(2)
        claim
      after
        :ok = :sys.resume(AdapterState)
      end

    assert {:error, {:terminal, :timeout_exceeded}} = Task.await(timed_out_claim, 500)

    assert {:error, {:terminal, :timeout_exceeded}} =
             AdapterState.claim(namespace, key, "timed-out", fingerprint)
  end

  test "an already-cancelled request remains timed out when delivery is queued before cleanup" do
    namespace = {:timeout_cancelled_request_race, make_ref()}
    key = :shared_result
    fingerprint = "same-input"
    request_id = "already-cancelled"

    assert :ok = AdapterState.register(namespace, request_id)
    assert :ok = AdapterState.cancel(namespace, request_id)
    :ok = :sys.suspend(AdapterState)

    timed_out_claim =
      try do
        claim =
          Task.async(fn ->
            AdapterState.claim(namespace, key, request_id, fingerprint, 20)
          end)

        assert_server_queue_length(1)
        Process.sleep(25)
        assert_server_queue_length(2)
        claim
      after
        :ok = :sys.resume(AdapterState)
      end

    assert {:error, {:terminal, :timeout_exceeded}} = Task.await(timed_out_claim, 500)

    assert {:error, {:terminal, :timeout_exceeded}} =
             AdapterState.claim(namespace, key, request_id, fingerprint)
  end

  test "a conflicting claim remains timed out when delivery is queued before cleanup" do
    namespace = {:timeout_conflict_race, make_ref()}
    key = :shared_result

    assert :claimed = AdapterState.claim(namespace, key, "owner", "original-input")
    :ok = :sys.suspend(AdapterState)

    timed_out_claim =
      try do
        claim =
          Task.async(fn ->
            AdapterState.claim(namespace, key, "timed-out", "different-input", 20)
          end)

        assert_server_queue_length(1)
        Process.sleep(25)
        assert_server_queue_length(2)
        claim
      after
        :ok = :sys.resume(AdapterState)
      end

    assert {:error, {:terminal, :timeout_exceeded}} = Task.await(timed_out_claim, 500)

    assert {:error, {:terminal, :timeout_exceeded}} =
             AdapterState.claim(namespace, key, "timed-out", "different-input")

    assert :ok = AdapterState.cancel(namespace, "owner")
  end

  test "replays the same semantic request under a new request id", %{input: input} do
    assert {:ok, output} = DeterministicModel.invoke(input)
    replay = %{input | request_id: uuid()}

    assert {:ok, ^output} = DeterministicModel.invoke(replay)

    assert DeterministicModel.retained_request!(replay.request_id) ==
             DeterministicModel.retained_request!(input.request_id)
  end

  test "scopes replay identity to the durable execution step", %{input: input} do
    first_step = struct!(input, step_key: "draft-proposal")

    second_step =
      struct!(input,
        request_id: uuid(),
        step_key: "validate-proposal",
        adapter_payload: %{fixture_id: "terminal"}
      )

    assert {:ok, %ModelOutput{classification: :proposal}} =
             DeterministicModel.invoke(first_step)

    assert {:error, {:terminal, :invalid_request}} =
             DeterministicModel.invoke(second_step)
  end

  test "validates authority before replay and rejects a mismatched replay", %{input: input} do
    assert {:ok, _output} = DeterministicModel.invoke(input)

    assert {:error, {:terminal, :missing_capability}} =
             DeterministicModel.invoke(%{input | capability_keys: []})

    assert {:error, {:terminal, :idempotency_conflict}} =
             DeterministicModel.invoke(%{input | token_budget: 101})
  end

  test "shared contracts reject missing credential and approval authority before adapter execution",
       %{input: input} do
    manifest = %ModelManifest{
      DeterministicModel.manifest()
      | credential_kinds: [:api_token],
        sensitivity: :confidential,
        approval_required: true
    }

    assert {:error, {:terminal, :missing_credential}} =
             AdapterContract.validate_model_input(manifest, %{input | sensitivity: :confidential})

    assert {:error, {:terminal, :approval_required}} =
             AdapterContract.validate_model_input(manifest, %{
               input
               | credential_kinds: [:api_token],
                 sensitivity: :confidential
             })
  end

  test "credential contracts reject nil credential kinds", %{input: input} do
    nil_manifest = %{DeterministicModel.manifest() | credential_kinds: [nil]}

    refute AdapterContract.valid_model_manifest?(nil_manifest)

    assert {:error, {:terminal, :invalid_model_input}} =
             AdapterContract.validate_model_input(nil_manifest, %{input | credential_kinds: [nil]})

    credential_manifest = %ModelManifest{
      DeterministicModel.manifest()
      | credential_kinds: [:api_token]
    }

    assert {:error, {:terminal, :invalid_model_input}} =
             AdapterContract.validate_model_input(credential_manifest, %{
               input
               | credential_kinds: [nil]
             })
  end

  test "credential contracts reject boolean credential kinds", %{input: input} do
    credential_manifest = %ModelManifest{
      DeterministicModel.manifest()
      | credential_kinds: [:api_token]
    }

    for boolean <- [false, true] do
      boolean_manifest = %{DeterministicModel.manifest() | credential_kinds: [boolean]}

      refute AdapterContract.valid_model_manifest?(boolean_manifest)

      assert {:error, {:terminal, :invalid_model_input}} =
               AdapterContract.validate_model_input(boolean_manifest, %{
                 input
                 | credential_kinds: [boolean]
               })

      assert {:error, {:terminal, :invalid_model_input}} =
               AdapterContract.validate_model_input(credential_manifest, %{
                 input
                 | credential_kinds: [boolean]
               })
    end
  end

  test "rejects malformed typed input before reading a fixture", %{input: input} do
    assert {:error, {:terminal, :invalid_model_input}} =
             DeterministicModel.invoke(%{
               input
               | capability_keys: nil,
                 idempotency_key: "invalid-input"
             })

    assert {:error, {:terminal, :invalid_model_input}} =
             DeterministicModel.invoke(%{input | request_id: nil, idempotency_key: "nil-request"})
  end

  test "cancelled requests do not invoke fixtures", %{input: input} do
    :ok = DeterministicModel.register_request(input.request_id)
    assert :ok = DeterministicModel.cancel(input.request_id)
    assert {:error, {:cancelled, :cancelled}} = DeterministicModel.invoke(input)
    assert {:error, :not_found} = DeterministicModel.cancel(uuid())
  end

  test "adapter result rejects outputs outside the typed contract" do
    assert {:error, {:terminal, :invalid_adapter_result}} = AdapterResult.normalize(%{})
  end

  test "adapter result rejects sentinel classified failure codes" do
    for classification <- [:retryable, :terminal, :cancelled],
        failure_code <- [nil, false, true] do
      assert {:error, {:terminal, :invalid_adapter_result}} =
               AdapterResult.normalize({:error, {classification, failure_code}})
    end
  end

  test "direct typed model outputs still pass through manifest validation", %{input: input} do
    namespace = {:direct_typed_output, make_ref()}

    configuration = %Configuration{
      fixture_loader: fn _fixture_id ->
        {:ok,
         {:ok,
          %ModelOutput{
            classification: :proposal,
            safe_summary: "Wrong nested type",
            structured_content: %{"proposal" => %{"intent" => true}}
          }}}
      end,
      malformed_output_code: :malformed_model_output,
      manifest: DeterministicModel.manifest(),
      output_module: ModelOutput,
      state_namespace: namespace,
      validate_output: &AdapterContract.validate_model_output/2
    }

    assert {:error, {:terminal, :malformed_model_output}} =
             DeterministicRuntime.invoke(
               %{input | idempotency_key: "direct-typed-output"},
               configuration
             )
  end

  test "model output schema rejects missing content, wrong nested types, and oversized content" do
    manifest = DeterministicModel.manifest()

    assert {:error, {:terminal, :malformed_model_output}} =
             AdapterContract.validate_model_output(
               manifest,
               struct(ModelOutput,
                 classification: :proposal,
                 safe_summary: "Missing content",
                 structured_content: nil
               )
             )

    assert {:error, {:terminal, :malformed_model_output}} =
             AdapterContract.validate_model_output(
               manifest,
               %ModelOutput{
                 classification: :proposal,
                 safe_summary: "Wrong nested type",
                 structured_content: %{"proposal" => %{"intent" => true}}
               }
             )

    assert {:error, {:terminal, :malformed_model_output}} =
             AdapterContract.validate_model_output(
               manifest,
               %ModelOutput{
                 classification: :proposal,
                 safe_summary: "Oversized content",
                 structured_content: %{
                   "proposal" => %{"intent" => String.duplicate("x", 16_385)}
                 }
               }
             )
  end

  test "model output schemas reject undeclared provider fields while allowing declared optional fields" do
    manifest = DeterministicModel.manifest()

    assert {:error, {:terminal, :malformed_model_output}} =
             AdapterContract.validate_model_output(
               manifest,
               %ModelOutput{
                 classification: :proposal,
                 safe_summary: "Raw fields are forbidden",
                 structured_content: %{
                   "proposal" => %{
                     "intent" => "follow_up",
                     "raw_provider_payload" => "secret"
                   }
                 }
               }
             )

    optional_manifest =
      put_in(manifest.output_schema.content_schemas.proposal.fields["note"], :string)

    assert :ok =
             AdapterContract.validate_model_output(
               optional_manifest,
               %ModelOutput{
                 classification: :proposal,
                 safe_summary: "Optional fields may be omitted",
                 structured_content: %{"proposal" => %{"intent" => "follow_up"}}
               }
             )
  end

  test "model manifests without classified content schemas fail closed", %{input: input} do
    manifest = DeterministicModel.manifest()

    malformed_manifest = %{
      manifest
      | output_schema: Map.delete(manifest.output_schema, :content_schemas)
    }

    refute AdapterContract.valid_model_manifest?(malformed_manifest)

    assert {:error, {:terminal, :invalid_model_input}} =
             AdapterContract.validate_model_input(malformed_manifest, input)

    assert {:error, {:terminal, :malformed_model_output}} =
             AdapterContract.validate_model_output(
               malformed_manifest,
               %ModelOutput{
                 classification: :proposal,
                 safe_summary: "Safe output",
                 structured_content: %{"proposal" => %{"intent" => "follow_up"}}
               }
             )
  end

  test "model manifest input schemas cover every typed request field", %{input: input} do
    manifest = DeterministicModel.manifest()

    incomplete_manifest =
      put_in(
        manifest.input_schema.fields,
        Map.delete(manifest.input_schema.fields, :execution_id)
      )

    refute AdapterContract.valid_model_manifest?(incomplete_manifest)

    assert {:error, {:terminal, :invalid_model_input}} =
             AdapterContract.validate_model_input(incomplete_manifest, input)
  end

  test "model manifest input schemas require compatible provider-neutral field types", %{
    input: input
  } do
    manifest = DeterministicModel.manifest()
    incompatible_manifest = put_in(manifest.input_schema.fields.adapter_payload, :atom)

    refute AdapterContract.valid_model_manifest?(incompatible_manifest)

    assert {:error, {:terminal, :invalid_model_input}} =
             AdapterContract.validate_model_input(incompatible_manifest, input)
  end

  test "model manifests reject input schemas too small for a typed request", %{input: input} do
    undersized_manifest =
      put_in(DeterministicModel.manifest().input_schema.max_serialized_bytes, 1)

    refute AdapterContract.valid_model_manifest?(undersized_manifest)

    assert {:error, {:terminal, :invalid_model_input}} =
             AdapterContract.validate_model_input(undersized_manifest, input)
  end

  test "model manifests reject output schemas too small for a typed result", %{input: input} do
    undersized_manifest =
      put_in(DeterministicModel.manifest().output_schema.max_serialized_bytes, 1)

    refute AdapterContract.valid_model_manifest?(undersized_manifest)

    assert {:error, {:terminal, :invalid_model_input}} =
             AdapterContract.validate_model_input(undersized_manifest, input)
  end

  test "model manifests require idempotent replay support", %{input: input} do
    manifest = %{DeterministicModel.manifest() | idempotency_supported: false}

    refute AdapterContract.valid_model_manifest?(manifest)

    assert {:error, {:terminal, :invalid_model_input}} =
             AdapterContract.validate_model_input(manifest, input)
  end

  test "model invocation fails closed for sensitivity and approval before fixture execution", %{
    input: input
  } do
    assert {:error, {:terminal, :sensitivity_not_allowed}} =
             DeterministicModel.invoke(%{input | sensitivity: :confidential})

    configured = Application.get_env(:office_graph, :deterministic_model_approval_required, false)
    Application.put_env(:office_graph, :deterministic_model_approval_required, true)

    on_exit(fn ->
      Application.put_env(:office_graph, :deterministic_model_approval_required, configured)
    end)

    assert {:error, {:terminal, :approval_required}} = DeterministicModel.invoke(input)
    assert {:ok, %ModelOutput{}} = DeterministicModel.invoke(%{input | approval_granted?: true})
  end

  test "model completed replays remain completed after cancellation", %{input: input} do
    assert {:ok, output} = DeterministicModel.invoke(input)
    assert :ok = DeterministicModel.cancel(input.request_id)
    assert {:ok, ^output} = DeterministicModel.invoke(input)
  end

  test "model replayed successes remain completed after cancellation", %{input: input} do
    assert {:ok, output} = DeterministicModel.invoke(input)
    replay = %{input | request_id: uuid()}

    assert {:ok, ^output} = DeterministicModel.invoke(replay)
    assert :ok = DeterministicModel.cancel(replay.request_id)
    assert {:ok, ^output} = DeterministicModel.invoke(replay)
  end

  test "distinct cancellation and conflict results retain only safe failure metadata", %{
    input: input
  } do
    assert {:ok, _output} = DeterministicModel.invoke(input)
    successful = DeterministicModel.retained_request!(input.request_id)

    conflicting = %{input | request_id: uuid(), token_budget: 101}

    assert {:error, {:terminal, :idempotency_conflict}} =
             DeterministicModel.invoke(conflicting)

    assert %{classification: :terminal, failure_code: :idempotency_conflict} =
             DeterministicModel.retained_request!(conflicting.request_id)

    cancelled = %{input | request_id: uuid(), idempotency_key: "cancelled-state"}
    :ok = DeterministicModel.register_request(cancelled.request_id)
    :ok = DeterministicModel.cancel(cancelled.request_id)

    assert {:error, {:cancelled, :cancelled}} = DeterministicModel.invoke(cancelled)

    assert %{classification: :cancelled, failure_code: :cancelled} =
             DeterministicModel.retained_request!(cancelled.request_id)

    assert successful == DeterministicModel.retained_request!(input.request_id)
  end

  test "model concurrent same and conflicting replays are coherent", %{input: input} do
    same = for _ <- 1..6, do: Task.async(fn -> DeterministicModel.invoke(input) end)
    assert Enum.all?(same, &match?({:ok, %ModelOutput{}}, Task.await(&1)))

    conflicting = %{input | token_budget: 101}
    assert {:error, {:terminal, :idempotency_conflict}} = DeterministicModel.invoke(conflicting)
  end

  test "replay fingerprints canonicalize authority sets", %{input: input} do
    first = %{
      input
      | capability_keys: ["agent.model.generate", "agent.context.read"],
        credential_kinds: [:oauth_token, :api_token]
    }

    reordered = %{
      first
      | capability_keys: ["agent.context.read", "agent.model.generate", "agent.context.read"],
        credential_kinds: [:api_token, :oauth_token, :api_token]
    }

    assert AdapterContract.fingerprint(first) == AdapterContract.fingerprint(reordered)

    refute AdapterContract.fingerprint(first) ==
             AdapterContract.fingerprint(%{reordered | credential_kinds: [:api_token]})
  end

  test "retryable outcomes preserve the replay-key fingerprint across request ids" do
    namespace = {:retryable_binding, make_ref()}
    key = :retryable_result

    assert :claimed = AdapterState.claim(namespace, key, "first", "same-input")

    assert {:completed, {:error, {:retryable, :provider_unavailable}}} =
             AdapterState.complete(
               namespace,
               key,
               "same-input",
               {:error, {:retryable, :provider_unavailable}}
             )

    assert :conflict = AdapterState.claim(namespace, key, "different", "different-input")
    assert :claimed = AdapterState.claim(namespace, key, "retry", "same-input")

    assert {:completed, {:ok, :recovered}} =
             AdapterState.complete(namespace, key, "same-input", {:ok, :recovered})
  end

  test "completed retries remain replayable when a stale restartable attempt is cancelled" do
    for restartable_status <- [:retryable, :abandoned] do
      namespace = {:stale_restartable_cancellation, restartable_status, make_ref()}
      key = :shared_result
      fingerprint = "same-input"
      stale_request_id = "stale-#{restartable_status}"

      case restartable_status do
        :retryable ->
          assert :claimed = AdapterState.claim(namespace, key, stale_request_id, fingerprint)

          assert {:completed, {:error, {:retryable, :provider_unavailable}}} =
                   AdapterState.complete(
                     namespace,
                     key,
                     fingerprint,
                     {:error, {:retryable, :provider_unavailable}}
                   )

        :abandoned ->
          parent = self()

          owner =
            spawn(fn ->
              result = AdapterState.claim(namespace, key, stale_request_id, fingerprint)
              send(parent, {:stale_owner_claimed, result})
              Process.sleep(:infinity)
            end)

          assert_receive {:stale_owner_claimed, :claimed}
          Process.exit(owner, :kill)
          assert_pending_count(namespace, 0)
      end

      assert :claimed = AdapterState.claim(namespace, key, "recovered", fingerprint)

      assert {:completed, {:ok, :recovered}} =
               AdapterState.complete(namespace, key, fingerprint, {:ok, :recovered})

      assert :ok = AdapterState.cancel(namespace, stale_request_id)

      assert {:replay, {:ok, :recovered}} =
               AdapterState.claim(namespace, key, stale_request_id, fingerprint)
    end
  end

  test "timed-out retries remain terminal when a stale restartable attempt is cancelled" do
    for restartable_status <- [:retryable, :abandoned] do
      namespace = {:timed_out_retry_cancellation, restartable_status, make_ref()}
      key = :shared_result
      fingerprint = "same-input"
      stale_request_id = "stale-#{restartable_status}"

      case restartable_status do
        :retryable ->
          assert :claimed = AdapterState.claim(namespace, key, stale_request_id, fingerprint)

          assert {:completed, {:error, {:retryable, :provider_unavailable}}} =
                   AdapterState.complete(
                     namespace,
                     key,
                     fingerprint,
                     {:error, {:retryable, :provider_unavailable}}
                   )

        :abandoned ->
          parent = self()

          owner =
            spawn(fn ->
              result = AdapterState.claim(namespace, key, stale_request_id, fingerprint)
              send(parent, {:stale_owner_claimed, result})
              Process.sleep(:infinity)
            end)

          assert_receive {:stale_owner_claimed, :claimed}
          Process.exit(owner, :kill)
          assert_pending_count(namespace, 0)
      end

      :ok = :sys.suspend(AdapterState)

      timed_out_claim =
        try do
          claim =
            Task.async(fn ->
              AdapterState.claim(namespace, key, "retry", fingerprint, 20)
            end)

          assert_server_queue_length(1)
          Process.sleep(25)
          assert_server_queue_length(2)
          claim
        after
          :ok = :sys.resume(AdapterState)
        end

      assert {:error, {:terminal, :timeout_exceeded}} = Task.await(timed_out_claim, 500)
      assert :ok = AdapterState.cancel(namespace, stale_request_id)

      assert {:error, {:terminal, :timeout_exceeded}} =
               AdapterState.claim(namespace, key, stale_request_id, fingerprint)
    end
  end

  test "cancellation preserves an existing idempotency conflict" do
    namespace = {:conflict_cancellation, make_ref()}
    key = :shared_result

    assert :claimed = AdapterState.claim(namespace, key, "owner", "original-input")

    assert {:completed, {:ok, :finished}} =
             AdapterState.complete(namespace, key, "original-input", {:ok, :finished})

    assert :conflict = AdapterState.claim(namespace, key, "conflict", "different-input")
    assert :ok = AdapterState.cancel(namespace, "conflict")
    assert :conflict = AdapterState.claim(namespace, key, "conflict", "different-input")
  end

  test "an abandoned owner keeps the replay key bound to its fingerprint" do
    namespace = {:abandoned_binding, make_ref()}
    key = :shared_result
    parent = self()

    owner =
      spawn(fn ->
        send(parent, {:owner_claimed, AdapterState.claim(namespace, key, "owner", "same-input")})
        Process.sleep(:infinity)
      end)

    assert_receive {:owner_claimed, :claimed}
    Process.exit(owner, :kill)
    assert_pending_count(namespace, 0)

    assert :conflict = AdapterState.claim(namespace, key, "different", "different-input")
    assert :claimed = AdapterState.claim(namespace, key, "retry", "same-input")
    assert :ok = AdapterState.cancel(namespace, "retry")
  end

  test "a timed-out owner keeps the replay key bound to its fingerprint" do
    namespace = {:timed_out_owner_binding, make_ref()}
    key = :shared_result
    :ok = :sys.suspend(AdapterState)

    timed_out_claim =
      try do
        claim =
          Task.async(fn ->
            AdapterState.claim(namespace, key, "timed-out", "same-input", 20)
          end)

        assert_server_queue_length(1)
        Process.sleep(25)
        assert_server_queue_length(2)
        claim
      after
        :ok = :sys.resume(AdapterState)
      end

    assert {:error, {:terminal, :timeout_exceeded}} = Task.await(timed_out_claim, 500)
    assert %{pending: 0} = AdapterState.state_counts(namespace)

    assert :conflict = AdapterState.claim(namespace, key, "different", "different-input")

    assert {:error, {:terminal, :timeout_exceeded}} =
             AdapterState.claim(namespace, key, "same-input-retry", "same-input")
  end

  test "retryable fingerprint retention remains bounded after an active retry is abandoned" do
    namespace = {:retryable_abandonment_retention, make_ref()}
    configured = Application.get_env(:office_graph, :agent_runtime_retention_limit)

    on_exit(fn ->
      if configured do
        Application.put_env(:office_graph, :agent_runtime_retention_limit, configured)
      else
        Application.delete_env(:office_graph, :agent_runtime_retention_limit)
      end
    end)

    Application.put_env(:office_graph, :agent_runtime_retention_limit, 2)
    key = :retryable_result
    fingerprint = "same-input"

    assert :claimed = AdapterState.claim(namespace, key, "first", fingerprint)

    assert {:completed, {:error, {:retryable, :provider_unavailable}}} =
             AdapterState.complete(
               namespace,
               key,
               fingerprint,
               {:error, {:retryable, :provider_unavailable}}
             )

    parent = self()

    owner =
      spawn(fn ->
        send(parent, {:retry_claimed, AdapterState.claim(namespace, key, "retry", fingerprint)})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:retry_claimed, :claimed}

    record_cancelled_requests(namespace, 1..2)
    assert AdapterState.entry_count(namespace) == 1

    Process.exit(owner, :kill)
    assert_pending_count(namespace, 0)

    record_cancelled_requests(namespace, 3..4)
    assert AdapterState.entry_count(namespace) == 0
  end

  test "a timed-out same-request duplicate cannot replace the active owner" do
    namespace = {:same_request_timeout, make_ref()}
    key = :shared_result
    request_id = "same-request"
    fingerprint = "same-input"

    assert :claimed = AdapterState.claim(namespace, key, request_id, fingerprint)

    duplicate =
      Task.async(fn ->
        AdapterState.claim(namespace, key, request_id, fingerprint, 20)
      end)

    assert_waiter_count(namespace, 1)
    assert {:error, {:terminal, :timeout_exceeded}} = Task.await(duplicate, 500)
    assert %{pending: 1, waiters: 0} = AdapterState.state_counts(namespace)

    assert {:completed, {:ok, :owner_result}} =
             AdapterState.complete(namespace, key, fingerprint, {:ok, :owner_result})

    assert {:replay, {:ok, :owner_result}} =
             AdapterState.claim(namespace, key, request_id, fingerprint)
  end

  test "adapter atomic claims keep all retention stores bounded", %{input: input} do
    for sequence <- 1..(AdapterState.retention_limit() + 1) do
      assert {:ok, %ModelOutput{}} =
               DeterministicModel.invoke(%{
                 input
                 | request_id: uuid(),
                   idempotency_key: "capacity-#{sequence}"
               })
    end

    assert %{pending: 0, terminal: terminal, records: records, retained: retained, total: total} =
             AdapterState.state_counts(DeterministicModel)

    assert terminal == AdapterState.retention_limit()
    assert records == AdapterState.retention_limit()
    assert retained == AdapterState.retention_limit()
    assert total == terminal + records + retained
  end

  test "a stopped in-flight waiter cannot evict a full replay window" do
    namespace = {:stopped_waiter_retention, make_ref()}
    :ok = AdapterState.reset(namespace)

    for sequence <- 1..AdapterState.retention_limit() do
      key = {:full_window, sequence}
      fingerprint = "fingerprint-#{sequence}"
      assert :claimed = AdapterState.claim(namespace, key, "request-#{sequence}", fingerprint)

      assert {:completed, {:ok, ^sequence}} =
               AdapterState.complete(namespace, key, fingerprint, {:ok, sequence})
    end

    assert :claimed =
             AdapterState.claim(namespace, :anchor, "anchor-request", "anchor-fingerprint")

    assert {:completed, {:ok, :anchor}} =
             AdapterState.complete(
               namespace,
               :anchor,
               "anchor-fingerprint",
               {:ok, :anchor}
             )

    assert AdapterState.entry_count(namespace) == AdapterState.retention_limit()
    assert :claimed = AdapterState.claim(namespace, :pending, "owner", "pending-fingerprint")

    waiter =
      Task.async(fn ->
        AdapterState.claim(namespace, :pending, "waiter", "pending-fingerprint")
      end)

    assert_waiter_count(namespace, 1)
    assert nil == Task.shutdown(waiter, :brutal_kill)
    assert_waiter_count(namespace, 0)

    assert {:replay, {:ok, :anchor}} =
             AdapterState.claim(namespace, :anchor, "anchor-replay", "anchor-fingerprint")

    assert :ok = AdapterState.cancel(namespace, "owner")
  end

  test "completion and replay retain safe metadata in their request-record transitions", %{
    input: input
  } do
    key = {:result, input.execution_id, input.step_key, input.idempotency_key}
    fingerprint = AdapterContract.fingerprint(input)
    success = {:ok, :completed_before_retention}
    success_metadata = %{classification: :proposal, output_hash: <<0>>, safe_summary: "Success"}

    assert :claimed = AdapterState.claim(DeterministicModel, key, input.request_id, fingerprint)

    assert {:completed, ^success} =
             AdapterState.complete(
               DeterministicModel,
               key,
               fingerprint,
               success,
               success_metadata
             )

    assert {:ok, ^success_metadata} =
             AdapterState.retained(DeterministicModel, input.request_id)

    assert {:error, {:terminal, :idempotency_conflict}} =
             DeterministicModel.invoke(%{input | token_budget: 101})

    assert {:ok, ^success_metadata} = AdapterState.retained(DeterministicModel, input.request_id)

    replay_request_id = uuid()

    assert {:replay, ^success} =
             AdapterState.claim(DeterministicModel, key, replay_request_id, fingerprint)

    assert {:ok, ^success_metadata} =
             AdapterState.retained(DeterministicModel, replay_request_id)
  end

  test "adapter state survives the caller process that created the replay entry", %{input: input} do
    parent = self()
    request = %{input | idempotency_key: "cross-process"}

    spawn(fn -> send(parent, {:invoked, DeterministicModel.invoke(request)}) end)

    assert_receive {:invoked, {:ok, output}}
    assert {:ok, ^output} = DeterministicModel.invoke(request)
  end

  defp model_input(fixture_id) do
    %ModelInput{
      request_id: uuid(),
      execution_id: uuid(),
      step_key: "model-step",
      context_package_id: uuid(),
      authority_snapshot_id: uuid(),
      operation_id: uuid(),
      adapter_key: "deterministic",
      adapter_version: "1",
      idempotency_key: "model-step-1",
      capability_keys: ["agent.model.generate"],
      credential_kinds: [],
      sensitivity: :internal,
      approval_granted?: false,
      timeout_ms: 1_000,
      token_budget: 100,
      adapter_payload: %{fixture_id: fixture_id}
    }
  end

  defp assert_waiter_count(namespace, expected, attempts \\ 40)

  defp assert_waiter_count(namespace, expected, attempts) when attempts > 0 do
    case AdapterState.state_counts(namespace) do
      %{waiters: ^expected} ->
        :ok

      _counts ->
        Process.sleep(5)
        assert_waiter_count(namespace, expected, attempts - 1)
    end
  end

  defp assert_waiter_count(_namespace, expected, 0) do
    flunk("expected adapter waiter count to become #{expected}")
  end

  defp assert_pending_count(namespace, expected, attempts \\ 100)

  defp assert_pending_count(namespace, expected, attempts) when attempts > 0 do
    case AdapterState.state_counts(namespace) do
      %{pending: ^expected} ->
        :ok

      _counts ->
        Process.sleep(1)
        assert_pending_count(namespace, expected, attempts - 1)
    end
  end

  defp assert_pending_count(_namespace, expected, 0) do
    flunk("expected adapter pending count to become #{expected}")
  end

  defp record_cancelled_requests(namespace, sequences) do
    Enum.each(sequences, fn sequence ->
      request_id = "cancelled-#{sequence}"
      assert :ok = AdapterState.register(namespace, request_id)
      assert :ok = AdapterState.cancel(namespace, request_id)
    end)
  end

  defp assert_server_queue_length(expected, attempts \\ 100)

  defp assert_server_queue_length(expected, attempts) when attempts > 0 do
    case Process.info(Process.whereis(AdapterState), :message_queue_len) do
      {:message_queue_len, length} when length >= expected ->
        :ok

      _queue_length ->
        Process.sleep(1)
        assert_server_queue_length(expected, attempts - 1)
    end
  end

  defp assert_server_queue_length(expected, 0) do
    flunk("expected adapter state queue length to reach #{expected}")
  end

  defp uuid, do: Ecto.UUID.generate()
end
