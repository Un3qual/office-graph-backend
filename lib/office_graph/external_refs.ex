defmodule OfficeGraph.ExternalRefs do
  @moduledoc """
  Public boundary for provider-neutral external references.
  """

  use Boundary,
    deps: [
      OfficeGraph.Audit,
      OfficeGraph.Integrations,
      OfficeGraph.Operations,
      OfficeGraph.Repo,
      OfficeGraph.Revisions
    ],
    exports: [ExternalReference]

  require Ash.Query

  alias OfficeGraph.{Audit, Operations, Revisions}
  alias OfficeGraph.ExternalRefs.ExternalReference

  def upsert_provider_reference(operation, source, attrs)
      when is_map(operation) and is_map(source) and is_map(attrs) do
    with :ok <- Operations.validate_system_operation(operation, :integration_reconcile),
         :ok <- validate_source(source),
         {:ok, external_id} <- required_string(attrs, :external_id),
         {:ok, resource_type} <- required_string(attrs, :resource_type),
         {:ok, resource_id} <- required_uuid(attrs, :resource_id),
         {:ok, object_type} <- required_string(attrs, :object_type),
         {:ok, provider} <- required_string(attrs, :provider),
         {:ok, url} <- optional_string(attrs, :url) do
      persist_reference(operation, source, %{
        external_id: external_id,
        resource_type: resource_type,
        resource_id: resource_id,
        object_type: object_type,
        provider: provider,
        url: url
      })
    end
  end

  def upsert_provider_reference(_operation, _source, _attrs), do: {:error, :forbidden}

  def read_provider_reference(operation, source, attrs)
      when is_map(operation) and is_map(source) and is_map(attrs) do
    with :ok <- Operations.validate_system_operation(operation, :integration_reconcile),
         :ok <- validate_source(source),
         {:ok, external_id} <- required_string(attrs, :external_id),
         {:ok, resource_type} <- required_string(attrs, :resource_type),
         {:ok, resource_id} <- required_uuid(attrs, :resource_id),
         {:ok, object_type} <- required_string(attrs, :object_type),
         {:ok, provider} <- required_string(attrs, :provider) do
      lookup = [
        organization_id: operation.organization_id,
        workspace_id: operation.workspace_id,
        source_id: source.id,
        external_id: external_id
      ]

      identity = %{
        external_id: external_id,
        resource_type: resource_type,
        resource_id: resource_id,
        object_type: object_type,
        provider: provider
      }

      case reference_by_lookup(ExternalReference, lookup) do
        {:ok, nil} ->
          {:ok, nil}

        {:ok, reference} ->
          if matching_reference?(reference, operation, identity),
            do: {:ok, reference},
            else: {:error, :forbidden}

        {:error, _storage_error} ->
          {:error, :integration_storage_unavailable}
      end
    end
  end

  def read_provider_reference(_operation, _source, _attrs), do: {:error, :forbidden}

  defp persist_reference(operation, source, identity) do
    upsert_identity =
      if is_nil(operation.workspace_id),
        do: :unique_organization_source_external_id,
        else: :unique_workspace_source_external_id

    result =
      ExternalReference
      |> Ash.Changeset.for_create(:create, %{
        organization_id: operation.organization_id,
        workspace_id: operation.workspace_id,
        source_id: source.id,
        provider: identity.provider,
        object_type: identity.object_type,
        external_id: identity.external_id,
        url: identity.url,
        sync_state: "synced",
        operation_id: operation.id,
        resource_type: identity.resource_type,
        resource_id: identity.resource_id
      })
      |> Ash.create(
        authorize?: false,
        return_notifications?: true,
        return_skipped_upsert?: true,
        upsert?: true,
        upsert_identity: upsert_identity,
        upsert_fields: []
      )

    case result do
      {:ok, reference, _notifications} ->
        persist_or_reconcile_reference(operation, reference, identity)

      {:ok, reference} ->
        persist_or_reconcile_reference(operation, reference, identity)

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp persist_or_reconcile_reference(operation, reference, identity) do
    if created_by_upsert?(reference) do
      trace!(operation, reference.id, "create")
      {:ok, reference}
    else
      reconcile_reference(operation, reference, identity)
    end
  end

  defp created_by_upsert?(reference) do
    case Ash.Resource.get_metadata(reference, :upsert_action) do
      :insert -> true
      :update -> false
      _other -> not Ash.Resource.get_metadata(reference, :upsert_skipped)
    end
  end

  defp reconcile_reference(operation, existing, identity) do
    if matching_reference?(existing, operation, identity) do
      reference =
        existing
        |> Ash.Changeset.for_update(:reconcile, %{
          url: identity.url || existing.url,
          sync_state: "synced",
          operation_id: operation.id
        })
        |> Ash.update!(authorize?: false)

      trace!(operation, reference.id, "update")
      {:ok, reference}
    else
      {:error, :forbidden}
    end
  end

  defp matching_reference?(reference, operation, identity) do
    reference.organization_id == operation.organization_id and
      reference.workspace_id == operation.workspace_id and
      reference.provider == identity.provider and
      reference.resource_type == identity.resource_type and
      reference.resource_id == identity.resource_id and
      reference.object_type == identity.object_type
  end

  defp reference_by_lookup(ExternalReference, lookup) do
    organization_id = Keyword.fetch!(lookup, :organization_id)
    workspace_id = Keyword.fetch!(lookup, :workspace_id)
    source_id = Keyword.fetch!(lookup, :source_id)
    external_id = Keyword.fetch!(lookup, :external_id)

    query =
      ExternalReference
      |> Ash.Query.filter(
        organization_id == ^organization_id and source_id == ^source_id and
          external_id == ^external_id
      )

    query =
      if is_nil(workspace_id),
        do: Ash.Query.filter(query, is_nil(workspace_id)),
        else: Ash.Query.filter(query, workspace_id == ^workspace_id)

    Ash.read_one(query, authorize?: false)
  end

  defp validate_source(%{id: id, kind: "provider"}) when is_binary(id), do: :ok
  defp validate_source(_source), do: {:error, :forbidden}

  defp required_string(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _invalid -> {:error, {:invalid_external_reference, key}}
    end
  end

  defp required_uuid(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) ->
        if match?({:ok, _}, Ecto.UUID.cast(value)),
          do: {:ok, value},
          else: {:error, {:invalid_external_reference, key}}

      _invalid ->
        {:error, {:invalid_external_reference, key}}
    end
  end

  defp optional_string(attrs, key) do
    case Map.get(attrs, key) do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        if String.trim(value) == "",
          do: {:ok, nil},
          else: {:ok, value}

      _invalid ->
        {:error, {:invalid_external_reference, key}}
    end
  end

  defp trace!(operation, id, change) do
    action = "external_reference.reconcile.#{change}"
    Audit.record!(operation, action, "external_reference", id)
    Revisions.record!(operation, "external_reference", id, action, action)
  end
end
