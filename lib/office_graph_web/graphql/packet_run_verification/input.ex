defmodule OfficeGraphWeb.GraphQL.PacketRunVerification.Input do
  @moduledoc false

  def parse(params) do
    with {:ok, flow_identity} <- required_string(params, :flow_identity),
         {:ok, verification_check_id} <- required_id(params, :verification_check_id),
         {:ok, source_graph_item_id} <- required_id(params, :source_graph_item_id),
         {:ok, packet_title} <- required_string(params, :packet_title),
         {:ok, objective} <- required_string(params, :objective),
         {:ok, context_summary} <- required_string(params, :context_summary),
         {:ok, requirements} <- required_string(params, :requirements),
         {:ok, success_criteria} <- required_string(params, :success_criteria),
         {:ok, autonomy_posture} <- required_string(params, :autonomy_posture),
         {:ok, source_surface} <- required_string(params, :source_surface),
         {:ok, reason} <- required_string(params, :reason),
         {:ok, authority_posture} <- required_string(params, :authority_posture),
         {:ok, observation_source_kind} <- required_string(params, :observation_source_kind),
         {:ok, observation_source_identity} <-
           required_string(params, :observation_source_identity),
         {:ok, observation_idempotency_key} <-
           required_string(params, :observation_idempotency_key),
         {:ok, observed_status} <- required_string(params, :observed_status),
         {:ok, normalized_status} <- required_string(params, :normalized_status),
         {:ok, freshness_state} <- required_string(params, :freshness_state),
         {:ok, trust_basis} <- required_string(params, :trust_basis),
         {:ok, observation_rationale} <- required_string(params, :observation_rationale),
         {:ok, evidence_claim} <- required_string(params, :evidence_claim),
         {:ok, evidence_title} <- required_string(params, :evidence_title),
         {:ok, evidence_body} <- required_string(params, :evidence_body),
         {:ok, evidence_result} <- required_string(params, :evidence_result),
         {:ok, acceptance_policy_basis} <- required_string(params, :acceptance_policy_basis) do
      {:ok,
       %{
         flow_identity: flow_identity,
         verification_check_id: verification_check_id,
         source_graph_item_id: source_graph_item_id,
         packet_title: packet_title,
         objective: objective,
         context_summary: context_summary,
         requirements: requirements,
         success_criteria: success_criteria,
         autonomy_posture: autonomy_posture,
         source_surface: source_surface,
         reason: reason,
         authority_posture: authority_posture,
         observation_source_kind: observation_source_kind,
         observation_source_identity: observation_source_identity,
         observation_idempotency_key: observation_idempotency_key,
         observed_status: observed_status,
         normalized_status: normalized_status,
         freshness_state: freshness_state,
         trust_basis: trust_basis,
         observation_rationale: observation_rationale,
         evidence_claim: evidence_claim,
         evidence_title: evidence_title,
         evidence_body: evidence_body,
         evidence_result: evidence_result,
         acceptance_policy_basis: acceptance_policy_basis
       }}
    end
  end

  defp required_id(params, key) do
    case value(params, key) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          {:error, {:missing_field, key}}
        else
          cast_id(String.trim(value), key)
        end

      nil ->
        {:error, {:missing_field, key}}

      _other ->
        {:error, {:invalid_field, key}}
    end
  end

  defp required_string(params, key) do
    case value(params, key) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          {:error, {:missing_field, key}}
        else
          {:ok, value}
        end

      nil ->
        {:error, {:missing_field, key}}

      _other ->
        {:error, {:invalid_field, key}}
    end
  end

  defp cast_id(value, key) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, {:invalid_field, key}}
    end
  end

  defp value(params, key) do
    cond do
      Map.has_key?(params, key) -> params[key]
      Map.has_key?(params, to_string(key)) -> params[to_string(key)]
      true -> nil
    end
  end
end
