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
         {:ok, object_type} <- required_string(attrs, :object_type),
         {:ok, provider} <- required_string(attrs, :provider) do
      persist_reference(operation, source, attrs, %{
        external_id: external_id,
        resource_type: resource_type,
        resource_id: resource_id,
        object_type: object_type,
        provider: provider
      })
    end
  end

  def upsert_provider_reference(_operation, _source, _attrs), do: {:error, :forbidden}

  defp persist_reference(operation, source, attrs, identity) do
    reference_id = Ecto.UUID.generate()

    lookup = [
      organization_id: operation.organization_id,
      workspace_id: operation.workspace_id,
      source_id: source.id,
      external_id: identity.external_id
    ]

    reference =
      Repo.get_or_insert!(
        ExternalReference,
        lookup,
        %{
          id: reference_id,
          organization_id: operation.organization_id,
          workspace_id: operation.workspace_id,
          source_id: source.id,
          provider: identity.provider,
          object_type: identity.object_type,
          external_id: identity.external_id,
          url: Map.get(attrs, :url),
          sync_state: "synced",
          operation_id: operation.id,
          resource_type: identity.resource_type,
          resource_id: identity.resource_id
        },
        &reference_insert_contract/2,
        &reference_by_lookup/2
      )

    if reference.id == reference_id do
      trace!(operation, reference.id, "create")
      {:ok, reference}
    else
      reconcile_reference(operation, reference, attrs, identity)
    end
  end

  defp reconcile_reference(operation, existing, attrs, identity) do
    if existing.organization_id == operation.organization_id and
         existing.workspace_id == operation.workspace_id and
         existing.provider == identity.provider and
         existing.resource_type == identity.resource_type and
         existing.resource_id == identity.resource_id and
         existing.object_type == identity.object_type do
      reference =
        existing
        |> Ash.Changeset.for_update(:reconcile, %{
          url: Map.get(attrs, :url) || existing.url,
          sync_state: "synced",
          operation_id: operation.id
        })
        |> Repo.ash_update!()

      trace!(operation, reference.id, "update")
      {:ok, reference}
    else
      {:error, :forbidden}
    end
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

  defp reference_insert_contract(ExternalReference, %{workspace_id: nil}) do
    {
      "external_references",
      {:unsafe_fragment,
       "(organization_id, source_id, external_id) WHERE organization_id IS NOT NULL AND workspace_id IS NULL"},
      [:id, :organization_id, :source_id, :operation_id, :resource_id]
    }
  end

  defp reference_insert_contract(ExternalReference, _attrs) do
    {
      "external_references",
      {:unsafe_fragment,
       "(organization_id, workspace_id, source_id, external_id) WHERE workspace_id IS NOT NULL"},
      [:id, :organization_id, :workspace_id, :source_id, :operation_id, :resource_id]
    }
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
