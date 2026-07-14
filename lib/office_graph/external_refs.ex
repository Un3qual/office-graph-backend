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

  alias OfficeGraph.{Audit, Operations, Repo, Revisions}
  alias OfficeGraph.ExternalRefs.ExternalReference

  def upsert_provider_reference(operation, source, attrs)
      when is_map(operation) and is_map(source) and is_map(attrs) do
    with :ok <- Operations.validate_system_operation(operation, :integration_reconcile),
         :ok <- validate_source(source),
         {:ok, external_id} <- required_string(attrs, :external_id),
         {:ok, resource_type} <- required_string(attrs, :resource_type),
         {:ok, resource_id} <- required_uuid(attrs, :resource_id),
         {:ok, object_type} <- required_string(attrs, :object_type) do
      persist_reference(operation, source, attrs, %{
        external_id: external_id,
        resource_type: resource_type,
        resource_id: resource_id,
        object_type: object_type
      })
    end
  end

  def upsert_provider_reference(_operation, _source, _attrs), do: {:error, :forbidden}

  defp persist_reference(operation, source, attrs, identity) do
    case reference_by_external_id(
           operation.organization_id,
           operation.workspace_id,
           source.id,
           identity.external_id
         ) do
      {:ok, nil} ->
        reference =
          Repo.ash_create!(ExternalReference, %{
            id: Ecto.UUID.generate(),
            organization_id: operation.organization_id,
            workspace_id: operation.workspace_id,
            source_id: source.id,
            provider: Map.get(attrs, :provider),
            object_type: identity.object_type,
            external_id: identity.external_id,
            url: Map.get(attrs, :url),
            sync_state: "synced",
            operation_id: operation.id,
            resource_type: identity.resource_type,
            resource_id: identity.resource_id
          })

        trace!(operation, reference.id, "create")
        {:ok, reference}

      {:ok, existing} ->
        reconcile_reference(operation, existing, attrs, identity)

      {:error, error} ->
        {:error, error}
    end
  end

  defp reconcile_reference(operation, existing, attrs, identity) do
    if existing.organization_id == operation.organization_id and
         existing.workspace_id == operation.workspace_id and
         existing.resource_type == identity.resource_type and
         existing.resource_id == identity.resource_id and
         existing.object_type == identity.object_type do
      reference =
        existing
        |> Ash.Changeset.for_update(:reconcile, %{
          provider: Map.get(attrs, :provider, existing.provider),
          object_type: identity.object_type,
          url: Map.get(attrs, :url, existing.url),
          sync_state: "synced",
          operation_id: operation.id,
          resource_type: identity.resource_type,
          resource_id: identity.resource_id
        })
        |> Repo.ash_update!()

      trace!(operation, reference.id, "update")
      {:ok, reference}
    else
      {:error, :forbidden}
    end
  end

  defp reference_by_external_id(organization_id, workspace_id, source_id, external_id) do
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

  defp trace!(operation, id, change) do
    action = "external_reference.reconcile.#{change}"
    Audit.record!(operation, action, "external_reference", id)
    Revisions.record!(operation, "external_reference", id, action, action)
  end
end
