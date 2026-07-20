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

  alias OfficeGraph.AgentRuntime.Adapters.DeterministicModel

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
    assert manifest.input_schema.required == [:fixture_id]
    assert manifest.input_schema.fields.fixture_id == :string

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
               | fixture_id: "retryable",
                 request_id: uuid(),
                 idempotency_key: "retry-step"
             })

    assert {:error, {:terminal, :invalid_request}} =
             DeterministicModel.invoke(%{
               input
               | fixture_id: "terminal",
                 request_id: uuid(),
                 idempotency_key: "terminal-step"
             })
  end

  test "malformed output is terminal and retained only as safe metadata", %{input: input} do
    malformed = %{input | fixture_id: "malformed"}

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

  test "a stopped caller before atomic claim cannot evict a full replay window", %{input: input} do
    anchor = %{input | idempotency_key: "anchor"}
    assert {:ok, output} = DeterministicModel.invoke(anchor)

    for sequence <- 1..(AdapterState.retention_limit() - 1) do
      assert {:ok, %ModelOutput{}} =
               DeterministicModel.invoke(%{
                 input
                 | request_id: uuid(),
                   idempotency_key: "full-window-#{sequence}"
               })
    end

    parent = self()

    caller =
      spawn(fn ->
        send(parent, :ready_to_claim)

        receive do
          :claim -> DeterministicModel.invoke(%{input | request_id: uuid()})
        end
      end)

    assert_receive :ready_to_claim
    Process.exit(caller, :kill)
    assert {:ok, ^output} = DeterministicModel.invoke(anchor)
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
      fixture_id: fixture_id
    }
  end

  defp uuid, do: Ecto.UUID.generate()
end
