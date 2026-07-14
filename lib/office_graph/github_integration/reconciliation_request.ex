defmodule OfficeGraph.GitHubIntegration.ReconciliationRequest do
  @moduledoc "Validated identity of one authoritative provider reconciliation read."

  @enforce_keys [:installation_id, :object_type, :object_id, :delivery_id]
  defstruct [:installation_id, :object_type, :object_id, :delivery_id]

  @object_types ~w(pull_request review_comment check_run)
  @fields [:installation_id, :object_type, :object_id, :delivery_id]

  def new(attrs) when is_map(attrs) do
    normalized =
      attrs
      |> Map.new(fn {key, value} -> {normalize_key(key), value} end)
      |> Map.take(@fields)

    request = struct(__MODULE__, normalized)

    with :ok <- required_uuid(request.installation_id, :installation_id),
         :ok <- one_of(request.object_type, :object_type, @object_types),
         :ok <- required_string(request.object_id, :object_id),
         :ok <- required_string(request.delivery_id, :delivery_id) do
      {:ok, request}
    end
  end

  def new(_attrs), do: {:error, {:invalid_reconciliation_request, :request}}

  def new!(attrs) do
    case new(attrs) do
      {:ok, request} -> request
      {:error, error} -> raise ArgumentError, inspect(error)
    end
  end

  defp required_uuid(value, field) do
    if is_binary(value) and match?({:ok, _}, Ecto.UUID.cast(value)),
      do: :ok,
      else: {:error, {:invalid_reconciliation_request, field}}
  end

  defp required_string(value, _field) when is_binary(value) and value != "", do: :ok
  defp required_string(_value, field), do: {:error, {:invalid_reconciliation_request, field}}

  defp one_of(value, field, values) do
    if value in values,
      do: :ok,
      else: {:error, {:invalid_reconciliation_request, field}}
  end

  defp normalize_key(key) when key in @fields, do: key

  defp normalize_key(key) when is_binary(key),
    do: Enum.find(@fields, key, &(to_string(&1) == key))

  defp normalize_key(key), do: key
end
