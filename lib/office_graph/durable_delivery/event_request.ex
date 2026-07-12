defmodule OfficeGraph.DurableDelivery.EventRequest do
  @moduledoc false

  alias OfficeGraph.Identity

  @event_kind_pattern ~r/^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$/
  @subject_kind_pattern ~r/^[a-z][a-z0-9_]*$/

  @enforce_keys [
    :event_key,
    :event_kind,
    :subject_kind,
    :subject_id,
    :subject_version,
    :organization_id,
    :workspace_id,
    :operation_id,
    :occurred_at
  ]
  defstruct [:causation_event_id | @enforce_keys]

  def new(session_context, operation, attrs) when is_map(attrs) do
    with :ok <- validate_context(session_context, operation),
         {:ok, event_key} <- required_string(attrs, :event_key),
         {:ok, event_kind} <- required_string(attrs, :event_kind),
         :ok <- validate_pattern(event_kind, @event_kind_pattern, :invalid_event_kind),
         {:ok, subject_kind} <- required_string(attrs, :subject_kind),
         :ok <- validate_pattern(subject_kind, @subject_kind_pattern, :invalid_subject_kind),
         {:ok, subject_id} <- required_uuid(attrs, :subject_id),
         {:ok, subject_version} <- subject_version(attrs),
         {:ok, causation_event_id} <- optional_uuid(attrs, :causation_event_id),
         {:ok, occurred_at} <- occurred_at(attrs) do
      {:ok,
       %__MODULE__{
         event_key: event_key,
         event_kind: event_kind,
         subject_kind: subject_kind,
         subject_id: subject_id,
         subject_version: subject_version,
         organization_id: session_context.organization_id,
         workspace_id: session_context.workspace_id,
         operation_id: operation.id,
         causation_event_id: causation_event_id,
         occurred_at: occurred_at
       }}
    end
  end

  def new(_session_context, _operation, _attrs), do: {:error, :invalid_event_request}

  def to_attrs(%__MODULE__{} = request) do
    request
    |> Map.from_struct()
    |> Map.put(:id, Ecto.UUID.generate())
    |> Map.put(:delivery_state, "pending")
  end

  defp validate_context(session_context, operation) do
    with :ok <- Identity.validate_session_context(session_context),
         true <- operation_matches?(session_context, operation) do
      :ok
    else
      _other -> {:error, :forbidden}
    end
  end

  defp operation_matches?(session_context, operation) when is_map(operation) do
    operation.principal_id == session_context.principal_id and
      operation.session_id == session_context.session_id and
      operation.organization_id == session_context.organization_id and
      operation.workspace_id == session_context.workspace_id
  end

  defp operation_matches?(_session_context, _operation), do: false

  defp required_string(attrs, field) do
    case Map.fetch(attrs, field) do
      {:ok, value} when is_binary(value) and byte_size(value) <= 255 ->
        if String.trim(value) == "", do: {:error, {:missing_field, field}}, else: {:ok, value}

      {:ok, _value} ->
        {:error, {:invalid_field, field}}

      :error ->
        {:error, {:missing_field, field}}
    end
  end

  defp validate_pattern(value, pattern, error_tag) do
    if Regex.match?(pattern, value), do: :ok, else: {:error, {error_tag, value}}
  end

  defp required_uuid(attrs, field) do
    case Map.fetch(attrs, field) do
      {:ok, value} -> cast_uuid(value, field)
      :error -> {:error, {:missing_field, field}}
    end
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

  defp subject_version(attrs) do
    case Map.get(attrs, :subject_version, 1) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _value -> {:error, {:invalid_field, :subject_version}}
    end
  end

  defp occurred_at(attrs) do
    case Map.get(attrs, :occurred_at) do
      nil -> {:ok, DateTime.utc_now()}
      %DateTime{} = value -> {:ok, value}
      _value -> {:error, {:invalid_field, :occurred_at}}
    end
  end
end
