defmodule OfficeGraph.AgentRuntime.ToolAdapterConformanceTest do
  use ExUnit.Case, async: false

  alias OfficeGraph.AgentRuntime.{ToolInput, ToolManifest, ToolOutput}
  alias OfficeGraph.AgentRuntime.AdapterContract
  alias OfficeGraph.AgentRuntime.Adapters.DeterministicTool

  setup do
    :ok = DeterministicTool.reset()

    on_exit(fn -> DeterministicTool.reset() end)

    %{input: tool_input("evidence_candidate")}
  end

  test "has a complete read-only manifest" do
    manifest = DeterministicTool.manifest()

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
    assert manifest.budget_units > 0
    assert [_ | _] = manifest.capability_keys
    assert manifest.credential_kinds == []
    assert manifest.external_write == false
    assert manifest.raw_retention == false
    assert manifest.idempotency_supported == true
  end

  test "keeps deterministic fixture selection inside the adapter-specific payload" do
    fields = ToolInput.__struct__() |> Map.keys()

    assert :adapter_payload in fields
    assert :step_key in fields
    refute :fixture_id in fields
  end

  test "tool manifest input schemas cover every typed request field", %{input: input} do
    manifest = DeterministicTool.manifest()

    incomplete_manifest =
      put_in(
        manifest.input_schema.fields,
        Map.delete(manifest.input_schema.fields, :external_write)
      )

    refute AdapterContract.valid_tool_manifest?(incomplete_manifest)

    assert {:error, {:terminal, :invalid_tool_input}} =
             AdapterContract.validate_tool_input(incomplete_manifest, input)
  end

  test "tool manifest input schemas require compatible provider-neutral field types", %{
    input: input
  } do
    manifest = DeterministicTool.manifest()

    incompatible_manifest =
      put_in(manifest.input_schema.fields.capability_keys, {:list, :atom})

    refute AdapterContract.valid_tool_manifest?(incompatible_manifest)

    assert {:error, {:terminal, :invalid_tool_input}} =
             AdapterContract.validate_tool_input(incompatible_manifest, input)
  end

  test "tool manifests reject input schemas too small for a typed request", %{input: input} do
    undersized_manifest =
      put_in(DeterministicTool.manifest().input_schema.max_serialized_bytes, 1)

    refute AdapterContract.valid_tool_manifest?(undersized_manifest)

    assert {:error, {:terminal, :invalid_tool_input}} =
             AdapterContract.validate_tool_input(undersized_manifest, input)
  end

  test "tool manifests require idempotent replay support", %{input: input} do
    manifest = %{DeterministicTool.manifest() | idempotency_supported: false}

    refute AdapterContract.valid_tool_manifest?(manifest)

    assert {:error, {:terminal, :invalid_tool_input}} =
             AdapterContract.validate_tool_input(manifest, input)
  end

  test "tool manifests without classified content schemas fail closed", %{input: input} do
    manifest = DeterministicTool.manifest()

    malformed_manifest = %{
      manifest
      | output_schema: Map.delete(manifest.output_schema, :content_schemas)
    }

    refute AdapterContract.valid_tool_manifest?(malformed_manifest)

    assert {:error, {:terminal, :invalid_tool_input}} =
             AdapterContract.validate_tool_input(malformed_manifest, input)

    assert {:error, {:terminal, :malformed_tool_output}} =
             AdapterContract.validate_tool_output(
               malformed_manifest,
               %ToolOutput{
                 classification: :evidence_candidate,
                 safe_summary: "Safe output",
                 structured_content: %{"evidence_candidate" => %{"check" => "static"}}
               }
             )
  end

  test "returns classified evidence candidates without retaining fixture content", %{input: input} do
    assert {:ok,
            output = %{
              classification: :evidence_candidate,
              safe_summary: "Static check completed"
            }} =
             DeterministicTool.invoke(input)

    retained = DeterministicTool.retained_request!(input.request_id)
    assert retained.classification == :evidence_candidate

    assert retained.output_hash ==
             output.structured_content
             |> :erlang.term_to_binary([:deterministic])
             |> then(&:crypto.hash(:sha256, &1))
             |> Base.encode16(case: :lower)

    assert byte_size(retained.output_hash) == 64

    refute Map.has_key?(retained, :structured_content)
    refute inspect(retained) =~ "fixture"
  end

  test "rejects external writes before a fixture executes", %{input: input} do
    assert {:error, {:terminal, :external_write_forbidden}} =
             DeterministicTool.invoke(%{input | external_write: true})
  end

  test "classifies retryable, terminal, malformed, and budget failures", %{input: input} do
    assert {:error, {:retryable, :tool_busy}} =
             DeterministicTool.invoke(%{
               input
               | adapter_payload: %{fixture_id: "retryable"},
                 request_id: uuid(),
                 idempotency_key: "retry-step"
             })

    assert {:error, {:terminal, :forbidden}} =
             DeterministicTool.invoke(%{
               input
               | adapter_payload: %{fixture_id: "terminal"},
                 request_id: uuid(),
                 idempotency_key: "terminal-step"
             })

    malformed = %{
      input
      | adapter_payload: %{fixture_id: "malformed"},
        request_id: uuid(),
        idempotency_key: "malformed-step"
    }

    assert {:error, {:terminal, :malformed_tool_output}} = DeterministicTool.invoke(malformed)

    refute DeterministicTool.retained_request!(malformed.request_id).safe_summary =~ "fixture"

    assert {:ok, _output} =
             DeterministicTool.invoke(%{
               input
               | timeout_ms: 500,
                 idempotency_key: "short-timeout"
             })

    assert {:error, {:terminal, :timeout_exceeded}} =
             DeterministicTool.invoke(%{
               input
               | timeout_ms: 1_001,
                 idempotency_key: "timeout-step"
             })

    assert {:error, {:terminal, :budget_exceeded}} =
             DeterministicTool.invoke(%{
               input
               | budget_units: 1_001,
                 idempotency_key: "budget-step"
             })
  end

  test "replays idempotent results and supports cancellation", %{input: input} do
    assert {:ok, output} = DeterministicTool.invoke(input)
    assert {:ok, ^output} = DeterministicTool.invoke(input)

    cancelled = %{input | request_id: uuid()}
    :ok = DeterministicTool.register_request(cancelled.request_id)
    assert :ok = DeterministicTool.cancel(cancelled.request_id)
    assert {:error, {:cancelled, :cancelled}} = DeterministicTool.invoke(cancelled)
    assert {:error, :not_found} = DeterministicTool.cancel(uuid())
  end

  test "replays the same semantic request under a new request id", %{input: input} do
    assert {:ok, output} = DeterministicTool.invoke(input)
    replay = %{input | request_id: uuid()}

    assert {:ok, ^output} = DeterministicTool.invoke(replay)
  end

  test "rejects malformed typed input before reading a fixture", %{input: input} do
    assert {:error, {:terminal, :invalid_tool_input}} =
             DeterministicTool.invoke(%{
               input
               | capability_keys: nil,
                 idempotency_key: "invalid-input"
             })

    assert {:error, {:terminal, :invalid_tool_input}} =
             DeterministicTool.invoke(%{input | request_id: nil, idempotency_key: "nil-request"})
  end

  test "shared contracts reject missing credential and approval authority before adapter execution",
       %{input: input} do
    manifest = %ToolManifest{
      DeterministicTool.manifest()
      | credential_kinds: [:api_token],
        sensitivity: :confidential,
        approval_required: true
    }

    assert {:error, {:terminal, :missing_credential}} =
             AdapterContract.validate_tool_input(manifest, %{input | sensitivity: :confidential})

    assert {:error, {:terminal, :approval_required}} =
             AdapterContract.validate_tool_input(manifest, %{
               input
               | credential_kinds: [:api_token],
                 sensitivity: :confidential
             })
  end

  test "tool output schema rejects a classification shape that does not match its manifest" do
    assert {:error, {:terminal, :malformed_tool_output}} =
             AdapterContract.validate_tool_output(
               DeterministicTool.manifest(),
               %ToolOutput{
                 classification: :evidence_candidate,
                 safe_summary: "Wrong nested type",
                 structured_content: %{"evidence_candidate" => %{"check" => 1}}
               }
             )
  end

  test "tool invocation fails closed for sensitivity and approval before fixture execution", %{
    input: input
  } do
    assert {:error, {:terminal, :sensitivity_not_allowed}} =
             DeterministicTool.invoke(%{input | sensitivity: :confidential})

    configured = Application.get_env(:office_graph, :deterministic_tool_approval_required, false)
    Application.put_env(:office_graph, :deterministic_tool_approval_required, true)

    on_exit(fn ->
      Application.put_env(:office_graph, :deterministic_tool_approval_required, configured)
    end)

    assert {:error, {:terminal, :approval_required}} = DeterministicTool.invoke(input)
    assert {:ok, %ToolOutput{}} = DeterministicTool.invoke(%{input | approval_granted?: true})
  end

  test "tool completed replays remain completed after cancellation", %{input: input} do
    assert {:ok, output} = DeterministicTool.invoke(input)
    assert :ok = DeterministicTool.cancel(input.request_id)
    assert {:ok, ^output} = DeterministicTool.invoke(input)
  end

  test "tool cancellation and conflict results retain safe classified metadata", %{input: input} do
    assert {:ok, _output} = DeterministicTool.invoke(input)

    conflicting = %{input | request_id: uuid(), budget_units: 11}

    assert {:error, {:terminal, :idempotency_conflict}} =
             DeterministicTool.invoke(conflicting)

    assert %{classification: :terminal, failure_code: :idempotency_conflict} =
             DeterministicTool.retained_request!(conflicting.request_id)

    cancelled = %{input | request_id: uuid(), idempotency_key: "cancelled-state"}
    :ok = DeterministicTool.register_request(cancelled.request_id)
    :ok = DeterministicTool.cancel(cancelled.request_id)

    assert {:error, {:cancelled, :cancelled}} = DeterministicTool.invoke(cancelled)

    assert %{classification: :cancelled, failure_code: :cancelled} =
             DeterministicTool.retained_request!(cancelled.request_id)
  end

  defp tool_input(fixture_id) do
    %ToolInput{
      request_id: uuid(),
      execution_id: uuid(),
      step_key: "tool-step",
      context_package_id: uuid(),
      authority_snapshot_id: uuid(),
      operation_id: uuid(),
      tool_key: "deterministic-tool",
      adapter_version: "1",
      idempotency_key: "tool-step-1",
      capability_keys: ["agent.tool.read"],
      credential_kinds: [],
      timeout_ms: 1_000,
      budget_units: 10,
      sensitivity: :internal,
      external_write: false,
      approval_granted?: false,
      adapter_payload: %{fixture_id: fixture_id}
    }
  end

  defp uuid, do: Ecto.UUID.generate()
end
