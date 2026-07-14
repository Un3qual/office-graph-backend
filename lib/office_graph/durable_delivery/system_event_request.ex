defmodule OfficeGraph.DurableDelivery.SystemEventRequest do
  @moduledoc false

  @event_kind_pattern ~r/^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$/

  @enforce_keys [
    :event_key,
    :event_kind,
    :organization_id,
    :operation_id,
    :operation_kind,
    :event_scope,
    :occurred_at
  ]

  defstruct [
    :workspace_id,
    :subject_kind,
    :subject_id,
    :subject_version,
    :causation_event_id | @enforce_keys
  ]

  def new(operation, attrs) when is_map(operation) and is_map(attrs) do
    with :ok <- validate_operation(operation),
         {:ok, event_key} <- required_string(attrs, :event_key),
         {:ok, event_kind} <- required_string(attrs, :event_kind),
         :ok <- validate_event_kind(event_kind),
         {:ok, subject} <- optional_subject(attrs),
         {:ok, causation_event_id} <- optional_uuid(attrs, :causation_event_id),
         {:ok, occurred_at} <- occurred_at(attrs) do
      {:ok,
       struct!(__MODULE__,
         event_key: event_key,
         event_kind: event_kind,
         organization_id: operation.organization_id,
         workspace_id: operation.workspace_id,
         operation_id: operation.id,
         operation_kind: "system",
         event_scope: if(is_nil(operation.workspace_id), do: "organization", else: "workspace"),
         subject_kind: subject.kind,
         subject_id: subject.id,
         subject_version: subject.version,
         causation_event_id: causation_event_id,
         occurred_at: occurred_at
       )}
    end
  end

  def new(_operation, _attrs), do: {:error, :invalid_system_event_request}

  def to_attrs(%__MODULE__{} = request) do
    request
    |> Map.from_struct()
    |> Map.put(:id, Ecto.UUID.generate())
    |> Map.put(:delivery_state, "pending")
  end

  defp validate_operation(operation) do
    valid? =
      Map.get(operation, :operation_kind) == "system" and
        is_binary(Map.get(operation, :id)) and
        is_binary(Map.get(operation, :organization_id)) and
        is_binary(Map.get(operation, :principal_id)) and
        is_nil(Map.get(operation, :session_id)) and
        present?(Map.get(operation, :authority_basis)) and
        present?(Map.get(operation, :causation_key)) and
        present?(Map.get(operation, :idempotency_scope))

    if valid?, do: :ok, else: {:error, :forbidden}
  end

  defp optional_subject(attrs) do
    kind = Map.get(attrs, :subject_kind)
    id = Map.get(attrs, :subject_id)
    version = Map.get(attrs, :subject_version)

    case {kind, id, version} do
      {nil, nil, nil} ->
        {:ok, %{kind: nil, id: nil, version: nil}}

      {kind, id, version} when is_binary(kind) and kind != "" ->
        with {:ok, id} <- cast_uuid(id, :subject_id),
             {:ok, version} <- optional_positive_integer(version, :subject_version) do
          {:ok, %{kind: kind, id: id, version: version}}
        end

      _other ->
        {:error, {:invalid_field, :subject}}
    end
  end

  defp required_string(attrs, field) do
    case Map.fetch(attrs, field) do
      {:ok, value} when is_binary(value) and byte_size(value) <= 255 ->
        if present?(value), do: {:ok, value}, else: {:error, {:missing_field, field}}

      {:ok, _value} ->
        {:error, {:invalid_field, field}}

      :error ->
        {:error, {:missing_field, field}}
    end
  end

  defp validate_event_kind(value) do
    if Regex.match?(@event_kind_pattern, value),
      do: :ok,
      else: {:error, {:invalid_event_kind, value}}
  end

  defp optional_uuid(attrs, field) do
    case Map.get(attrs, field) do
      nil -> {:ok, nil}
      value -> cast_uuid(value, field)
    end
  end

  defp cast_uuid(value, field) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, {:invalid_field, field}}
    end
  end

  defp optional_positive_integer(nil, _field), do: {:ok, nil}

  defp optional_positive_integer(value, _field) when is_integer(value) and value > 0,
    do: {:ok, value}

  defp optional_positive_integer(_value, field), do: {:error, {:invalid_field, field}}

  defp occurred_at(attrs) do
    case Map.get(attrs, :occurred_at) do
      nil -> {:ok, DateTime.utc_now()}
      %DateTime{} = value -> {:ok, value}
      _value -> {:error, {:invalid_field, :occurred_at}}
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
