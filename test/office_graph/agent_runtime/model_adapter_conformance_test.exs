defmodule OfficeGraph.AgentRuntime.ModelAdapterConformanceTest do
  use ExUnit.Case, async: false

  alias OfficeGraph.AgentRuntime.{AdapterResult, ModelInput, ModelOutput}
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
    assert manifest.timeout_ms in 1_000..120_000
    assert manifest.token_budget > 0
    assert length(manifest.capability_keys) > 0
    assert manifest.credential_kinds == []
    assert manifest.external_write == false
    assert manifest.raw_retention == false
    assert manifest.idempotency_supported == true
  end

  test "returns a classified structured proposal without retaining fixture content", %{
    input: input
  } do
    assert {:ok,
            %ModelOutput{classification: :proposal, safe_summary: "Propose a bounded follow-up"}} =
             DeterministicModel.invoke(input)

    retained = DeterministicModel.retained_request!(input.request_id)
    assert retained.classification == :proposal
    assert retained.safe_summary == "Propose a bounded follow-up"
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
    assert {:error, {:terminal, :timeout_exceeded}} =
             DeterministicModel.invoke(%{input | timeout_ms: 1, idempotency_key: "timeout-step"})

    assert {:error, {:terminal, :token_budget_exceeded}} =
             DeterministicModel.invoke(%{
               input
               | token_budget: 10_001,
                 idempotency_key: "budget-step"
             })

    assert {:ok, output} = DeterministicModel.invoke(input)
    assert {:ok, ^output} = DeterministicModel.invoke(input)
  end

  test "rejects malformed typed input before reading a fixture", %{input: input} do
    assert {:error, {:terminal, :invalid_model_input}} =
             DeterministicModel.invoke(%{
               input
               | capability_keys: nil,
                 idempotency_key: "invalid-input"
             })
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

  defp model_input(fixture_id) do
    %ModelInput{
      request_id: uuid(),
      execution_id: uuid(),
      context_package_id: uuid(),
      authority_snapshot_id: uuid(),
      operation_id: uuid(),
      adapter_key: "deterministic-model",
      adapter_version: "1",
      idempotency_key: "model-step-1",
      capability_keys: ["agent.model.generate"],
      timeout_ms: 1_000,
      token_budget: 100,
      fixture_id: fixture_id
    }
  end

  defp uuid, do: Ecto.UUID.generate()
end
