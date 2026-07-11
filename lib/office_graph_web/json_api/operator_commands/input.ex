defmodule OfficeGraphWeb.JsonApi.OperatorCommands.Input do
  @moduledoc false

  @fields %{
    submit_manual_intake: [
      idempotency_key: :string,
      source_identity: :string,
      replay_identity: :string,
      body: :raw_string
    ],
    apply_proposed_changes: [
      idempotency_key: :string,
      normalized_event_id: :uuid,
      proposed_change_ids: {:list, :uuid}
    ],
    create_work_packet: [
      idempotency_key: :string,
      title: :string,
      objective: :string,
      context_summary: :string,
      requirements: :string,
      success_criteria: :string,
      autonomy_posture: :string,
      source_graph_item_ids: {:list, :uuid},
      verification_check_ids: {:list, :uuid}
    ],
    create_work_packet_version: [
      idempotency_key: :string,
      packet_id: :uuid,
      expected_current_version_id: :uuid,
      title: :string,
      objective: :string,
      context_summary: :string,
      requirements: :string,
      success_criteria: :string,
      autonomy_posture: :string,
      source_graph_item_ids: {:list, :uuid},
      verification_check_ids: {:list, :uuid}
    ],
    start_work_run: [
      idempotency_key: :string,
      packet_version_id: :uuid,
      source_surface: :string,
      reason: :string,
      authority_posture: :string
    ]
  }

  def parse(command, params) do
    @fields
    |> Map.fetch!(command)
    |> Enum.reduce_while({:ok, %{}}, fn {key, type}, {:ok, parsed} ->
      case required(params, key, type) do
        {:ok, value} -> {:cont, {:ok, Map.put(parsed, key, value)}}
        error -> {:halt, error}
      end
    end)
  end

  defp required(params, key, :string), do: required_string(params, key, &String.trim/1)
  defp required(params, key, :raw_string), do: required_string(params, key, &Function.identity/1)

  defp required(params, key, :uuid) do
    with {:ok, value} <- required(params, key, :string),
         {:ok, uuid} <- Ecto.UUID.cast(value) do
      {:ok, uuid}
    else
      :error -> {:error, {:invalid_field, key}}
      error -> error
    end
  end

  defp required(params, key, {:list, type}) do
    case Map.get(params, key) || Map.get(params, to_string(key)) do
      values when is_list(values) -> parse_list(values, key, type)
      nil -> {:error, {:missing_field, key}}
      _other -> {:error, {:invalid_field, key}}
    end
  end

  defp required_string(params, key, return_value) do
    case Map.get(params, key) || Map.get(params, to_string(key)) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, {:missing_field, key}}
          _nonblank -> {:ok, return_value.(value)}
        end

      nil ->
        {:error, {:missing_field, key}}

      _other ->
        {:error, {:invalid_field, key}}
    end
  end

  defp parse_list(values, key, type) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, parsed} ->
      case required(%{key => value}, key, type) do
        {:ok, cast} -> {:cont, {:ok, [cast | parsed]}}
        _error -> {:halt, {:error, {:invalid_field, key}}}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      error -> error
    end
  end
end
