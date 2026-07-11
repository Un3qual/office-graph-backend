defmodule OfficeGraphWeb.GraphQL.OperatorCommands.Input do
  @moduledoc false

  @fields %{
    submit_manual_intake: [
      idempotency_key: :string,
      source_identity: :string,
      replay_identity: :string,
      body: :raw_string
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

  defp required(params, key, :string) do
    required_string(params, key, &String.trim/1)
  end

  defp required(params, key, :raw_string) do
    required_string(params, key, &Function.identity/1)
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
end
