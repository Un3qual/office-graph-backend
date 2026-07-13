defmodule OfficeGraphWeb.GraphQL.Common.Errors do
  @moduledoc false

  alias OfficeGraphWeb.OperatorCommands.Errors

  def to_absinthe(error) do
    classification = Errors.classify(error)

    extensions =
      classification.metadata
      |> maybe_put_fields(classification.fields)
      |> Map.put(:code, classification.code)

    {:error, message: classification.detail, extensions: extensions}
  end

  defp maybe_put_fields(metadata, []), do: metadata
  defp maybe_put_fields(%{field: _field} = metadata, _fields), do: metadata
  defp maybe_put_fields(metadata, fields), do: Map.put(metadata, :fields, fields)
end
