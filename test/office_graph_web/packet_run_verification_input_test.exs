defmodule OfficeGraphWeb.PacketRunVerificationInputTest do
  use ExUnit.Case, async: true

  alias OfficeGraphWeb.GraphQL.PacketRunVerification.Input

  test "parses atom-keyed input fields" do
    verification_check_id = Ecto.UUID.generate()
    source_graph_item_id = Ecto.UUID.generate()

    assert {:ok, parsed} = Input.parse(params(verification_check_id, source_graph_item_id))

    assert parsed.flow_identity == "operator-flow"
    assert parsed.verification_check_id == verification_check_id
    assert parsed.source_graph_item_id == source_graph_item_id
    assert parsed.acceptance_policy_basis == "owner_acceptance"
  end

  test "parses string-keyed input fields and trims ids" do
    verification_check_id = Ecto.UUID.generate()
    source_graph_item_id = Ecto.UUID.generate()

    input =
      params(" #{verification_check_id} ", " #{source_graph_item_id} ")
      |> Map.new(fn {key, value} -> {to_string(key), value} end)

    assert {:ok, parsed} = Input.parse(input)

    assert parsed.verification_check_id == verification_check_id
    assert parsed.source_graph_item_id == source_graph_item_id
  end

  test "rejects blank required strings" do
    input = %{params() | packet_title: " "}

    assert Input.parse(input) == {:error, {:missing_field, :packet_title}}
  end

  test "rejects non-string required fields" do
    input = %{params() | packet_title: 42}

    assert Input.parse(input) == {:error, {:invalid_field, :packet_title}}
  end

  test "rejects invalid ids" do
    input = %{params() | verification_check_id: "not-a-uuid"}

    assert Input.parse(input) == {:error, {:invalid_field, :verification_check_id}}
  end

  defp params(
         verification_check_id \\ Ecto.UUID.generate(),
         source_graph_item_id \\ Ecto.UUID.generate()
       ) do
    %{
      flow_identity: "operator-flow",
      verification_check_id: verification_check_id,
      source_graph_item_id: source_graph_item_id,
      packet_title: "Packet title",
      objective: "Objective",
      context_summary: "Context summary",
      requirements: "Requirements",
      success_criteria: "Success criteria",
      autonomy_posture: "human_supervised",
      source_surface: "operator_console",
      reason: "Run verification",
      authority_posture: "human_supervised",
      observation_source_kind: "human",
      observation_source_identity: "operator",
      observation_idempotency_key: "observation-key",
      observed_status: "passed",
      normalized_status: "succeeded",
      freshness_state: "fresh",
      trust_basis: "owner_attested",
      observation_rationale: "Observed in console.",
      evidence_claim: "Evidence claim",
      evidence_title: "Evidence title",
      evidence_body: "Evidence body",
      evidence_result: "passed",
      acceptance_policy_basis: "owner_acceptance"
    }
  end
end
