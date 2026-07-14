defmodule OfficeGraph.Operations.SystemOperationRequest do
  @moduledoc false

  @enforce_keys [
    :organization_id,
    :principal_id,
    :action,
    :action_name,
    :authority_basis,
    :causation_key,
    :idempotency_scope,
    :idempotency_key
  ]

  defstruct [
    :workspace_id,
    :credential_id,
    :subject_kind,
    :subject_id,
    :subject_version | @enforce_keys
  ]

  def new(attrs, declared_actions) when is_map(attrs) and is_map(declared_actions) do
    with {:ok, organization_id} <- required_uuid(attrs, :organization_id),
         {:ok, principal_id} <- required_uuid(attrs, :principal_id),
         {:ok, workspace_id} <- optional_uuid(attrs, :workspace_id),
         {:ok, action, action_name} <- declared_action(attrs, declared_actions),
         {:ok, authority_basis} <- required_string(attrs, :authority_basis),
         {:ok, causation_key} <- required_string(attrs, :causation_key),
         {:ok, idempotency_scope} <- required_string(attrs, :idempotency_scope),
         {:ok, idempotency_key} <- required_string(attrs, :idempotency_key),
         {:ok, credential_id} <- optional_uuid(attrs, :credential_id),
         {:ok, subject} <- optional_subject(attrs) do
      {:ok,
       struct!(__MODULE__,
         organization_id: organization_id,
         principal_id: principal_id,
         workspace_id: workspace_id,
         action: action,
         action_name: action_name,
         authority_basis: authority_basis,
         causation_key: causation_key,
         idempotency_scope: idempotency_scope,
         idempotency_key: idempotency_key,
         credential_id: credential_id,
         subject_kind: subject.kind,
         subject_id: subject.id,
         subject_version: subject.version
       )}
    end
  end

  def new(_attrs, _declared_actions), do: {:error, :invalid_system_operation_request}

  defp declared_action(attrs, declared_actions) do
    with {:ok, action} <- Map.fetch(attrs, :action),
         action_name when is_binary(action_name) <- Map.get(declared_actions, action) do
      {:ok, action, action_name}
    else
      :error -> {:error, {:missing_field, :action}}
      _other -> {:error, {:unsupported_system_action, Map.get(attrs, :action)}}
    end
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
        if String.trim(value) == "", do: {:error, {:missing_field, field}}, else: {:ok, value}

      {:ok, _value} ->
        {:error, {:invalid_field, field}}

      :error ->
        {:error, {:missing_field, field}}
    end
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

  defp optional_positive_integer(nil, _field), do: {:ok, nil}

  defp optional_positive_integer(value, _field) when is_integer(value) and value > 0,
    do: {:ok, value}

  defp optional_positive_integer(_value, field), do: {:error, {:invalid_field, field}}
end
