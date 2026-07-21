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
             :crypto.hash(:sha256, :erlang.term_to_binary(output.structured_content))

    refute Map.has_key?(retained, :structured_content)
    refute inspect(retained) =~ "fixture"
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
    request = %{input | timeout_ms: 25, idempotency_key: "claim-timeout"}

    configuration = %Configuration{
      fixture_loader: fn _fixture_id ->
        send(parent, {:fixture_waiting, self()})

        receive do
          :release_fixture ->
            {:ok,
             %{
               "classification" => "proposal",
               "safe_summary" => "Completed after waiter timeout",
               "structured_content" => %{"proposal" => %{"intent" => "follow_up"}}
             }}
        end
      end,
      malformed_output_code: :malformed_model_output,
      manifest: DeterministicModel.manifest(),
      output_module: ModelOutput,
      state_namespace: DeterministicModel,
      validate_output: &AdapterContract.validate_model_output/2
    }

    owner = Task.async(fn -> DeterministicRuntime.invoke(request, configuration) end)
    assert_receive {:fixture_waiting, fixture_process}

    timed_out = %{request | request_id: uuid()}

    assert {:error, {:terminal, :timeout_exceeded}} =
             DeterministicRuntime.invoke(timed_out, configuration)

    assert %{classification: :terminal, failure_code: :timeout_exceeded} =
             DeterministicModel.retained_request!(timed_out.request_id)

    assert %{waiters: 0} = AdapterState.state_counts(DeterministicModel)
    send(fixture_process, :release_fixture)
    assert {:ok, output} = Task.await(owner, 500)

    assert {:error, {:terminal, :timeout_exceeded}} =
             DeterministicRuntime.invoke(timed_out, configuration)

    assert {:ok, ^output} =
             DeterministicRuntime.invoke(%{request | request_id: uuid()}, configuration)
  end

  test "replays the same semantic request under a new request id", %{input: input} do
    assert {:ok, output} = DeterministicModel.invoke(input)
    replay = %{input | request_id: uuid()}

    assert {:ok, ^output} = DeterministicModel.invoke(replay)

    assert DeterministicModel.retained_request!(replay.request_id) ==
             DeterministicModel.retained_request!(input.request_id)
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

  test "same-id invocation cannot retain a conflict before success retention is written", %{
    input: input
  } do
    key = {:result, input.execution_id, input.idempotency_key}
    fingerprint = AdapterContract.fingerprint(input)
    success = {:ok, :completed_before_retention}
    success_metadata = %{classification: :proposal, output_hash: <<0>>, safe_summary: "Success"}

    assert :claimed = AdapterState.claim(DeterministicModel, key, input.request_id, fingerprint)

    assert {:completed, ^success} =
             AdapterState.complete(DeterministicModel, key, fingerprint, success)

    assert {:error, {:terminal, :idempotency_conflict}} =
             DeterministicModel.invoke(%{input | token_budget: 101})

    assert :error = AdapterState.retained(DeterministicModel, input.request_id)
    assert :ok = AdapterState.put_retained(DeterministicModel, input.request_id, success_metadata)
    assert {:ok, ^success_metadata} = AdapterState.retained(DeterministicModel, input.request_id)
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

  defp uuid, do: Ecto.UUID.generate()
end
