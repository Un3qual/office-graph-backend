defmodule OfficeGraphWeb.GraphQL.PacketRunVerification.Input do
  @moduledoc false

  @required_fields [
    flow_identity: :string,
    verification_check_id: :id,
    source_graph_item_id: :id,
    packet_title: :string,
    objective: :string,
    context_summary: :string,
    requirements: :string,
    success_criteria: :string,
    autonomy_posture: :string,
    source_surface: :string,
    reason: :string,
    authority_posture: :string,
    observation_source_kind: :string,
    observation_source_identity: :string,
    observation_idempotency_key: :string,
    observed_status: :string,
    normalized_status: :string,
    freshness_state: :string,
    trust_basis: :string,
    observation_rationale: :string,
    evidence_claim: :string,
    evidence_title: :string,
    evidence_body: :string,
    evidence_result: :string,
    acceptance_policy_basis: :string
  ]

  def parse(params) do
    Enum.reduce_while(@required_fields, {:ok, %{}}, fn {key, type}, {:ok, parsed} ->
      case required_field(params, key, type) do
        {:ok, value} -> {:cont, {:ok, Map.put(parsed, key, value)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp required_field(params, key, :id), do: required_id(params, key)
  defp required_field(params, key, :string), do: required_string(params, key)

  defp required_id(params, key) do
    require_value(params, key, fn _value, trimmed -> cast_id(trimmed, key) end)
  end

  defp required_string(params, key) do
    require_value(params, key, fn value, _trimmed -> {:ok, value} end)
  end

  defp require_value(params, key, cast) do
    case value(params, key) do
      value when is_binary(value) ->
        trimmed = String.trim(value)

        if trimmed == "" do
          {:error, {:missing_field, key}}
        else
          cast.(value, trimmed)
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
