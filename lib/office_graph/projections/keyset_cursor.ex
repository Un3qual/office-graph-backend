defmodule OfficeGraph.Projections.KeysetCursor do
  @moduledoc false

  def encode(parts) when is_list(parts) do
    parts
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  def decode(cursor, expected_size) when is_binary(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, parts} when is_list(parts) and length(parts) == expected_size <- Jason.decode(json) do
      {:ok, parts}
    else
      _invalid -> {:error, {:invalid_field, :pagination}}
    end
  end
end
