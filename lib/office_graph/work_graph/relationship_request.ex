defmodule OfficeGraph.WorkGraph.RelationshipRequest do
  @moduledoc false

  @enforce_keys [:definition_key, :source_item_id, :target_item_id]
  defstruct [
    :definition_key,
    :source_item_id,
    :target_item_id,
    :workspace_id,
    :valid_from,
    :run_id,
    :integration_event_id
  ]

  @type t :: %__MODULE__{
          definition_key: String.t(),
          source_item_id: Ecto.UUID.t(),
          target_item_id: Ecto.UUID.t(),
          workspace_id: Ecto.UUID.t() | nil,
          valid_from: DateTime.t() | nil,
          run_id: Ecto.UUID.t() | nil,
          integration_event_id: Ecto.UUID.t() | nil
        }

  @fields [
    :definition_key,
    :source_item_id,
    :target_item_id,
    :workspace_id,
    :valid_from,
    :run_id,
    :integration_event_id
  ]

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, {:invalid_relationship_request, atom()}}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.new(fn {key, value} -> {normalize_key(key), value} end)
      |> Map.take(@fields)

    request = struct(__MODULE__, attrs)

    case validate(request) do
      :ok -> {:ok, request}
      {:error, error} -> {:error, error}
    end
  end

  def new(_attrs), do: {:error, {:invalid_relationship_request, :request}}

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, request} -> request
      {:error, error} -> raise ArgumentError, inspect(error)
    end
  end

  @spec validate(t()) :: :ok | {:error, {:invalid_relationship_request, atom()}}
  def validate(%__MODULE__{} = request) do
    Enum.find_value(
      [
        definition_key: request.definition_key,
        source_item_id: request.source_item_id,
        target_item_id: request.target_item_id
      ],
      :ok,
      fn
        {_field, value} when is_binary(value) and value != "" -> false
        {field, _value} -> {:error, {:invalid_relationship_request, field}}
      end
    )
  end

  defp normalize_key(key) when key in @fields, do: key

  defp normalize_key(key) when is_binary(key) do
    Enum.find(@fields, key, &(Atom.to_string(&1) == key))
  end

  defp normalize_key(key), do: key
end
