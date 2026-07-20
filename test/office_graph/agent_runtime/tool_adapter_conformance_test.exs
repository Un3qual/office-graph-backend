defmodule OfficeGraph.AgentRuntime.ToolAdapterConformanceTest do
  use ExUnit.Case, async: false

  alias OfficeGraph.AgentRuntime.ToolInput
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
    assert manifest.timeout_ms in 1_000..120_000
    assert manifest.budget_units > 0
    assert length(manifest.capability_keys) > 0
    assert manifest.credential_kinds == []
    assert manifest.external_write == false
    assert manifest.raw_retention == false
    assert manifest.idempotency_supported == true
  end

  test "returns classified evidence candidates without retaining fixture content", %{input: input} do
    assert {:ok, %{classification: :evidence_candidate, safe_summary: "Static check completed"}} =
             DeterministicTool.invoke(input)

    retained = DeterministicTool.retained_request!(input.request_id)
    assert retained.classification == :evidence_candidate
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
               | fixture_id: "retryable",
                 request_id: uuid(),
                 idempotency_key: "retry-step"
             })

    assert {:error, {:terminal, :forbidden}} =
             DeterministicTool.invoke(%{
               input
               | fixture_id: "terminal",
                 request_id: uuid(),
                 idempotency_key: "terminal-step"
             })

    malformed = %{
      input
      | fixture_id: "malformed",
        request_id: uuid(),
        idempotency_key: "malformed-step"
    }

    assert {:error, {:terminal, :malformed_tool_output}} = DeterministicTool.invoke(malformed)

    refute DeterministicTool.retained_request!(malformed.request_id).safe_summary =~ "fixture"

    assert {:error, {:terminal, :timeout_exceeded}} =
             DeterministicTool.invoke(%{input | timeout_ms: 1, idempotency_key: "timeout-step"})

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

  test "rejects malformed typed input before reading a fixture", %{input: input} do
    assert {:error, {:terminal, :invalid_tool_input}} =
             DeterministicTool.invoke(%{
               input
               | capability_keys: nil,
                 idempotency_key: "invalid-input"
             })
  end

  defp tool_input(fixture_id) do
    %ToolInput{
      request_id: uuid(),
      execution_id: uuid(),
      context_package_id: uuid(),
      authority_snapshot_id: uuid(),
      operation_id: uuid(),
      tool_key: "deterministic-tool",
      adapter_version: "1",
      idempotency_key: "tool-step-1",
      capability_keys: ["agent.tool.read"],
      timeout_ms: 1_000,
      budget_units: 10,
      sensitivity: :internal,
      external_write: false,
      fixture_id: fixture_id
    }
  end

  defp uuid, do: Ecto.UUID.generate()
end
