defmodule OfficeGraph.SoftwareProving do
  @moduledoc """
  Public boundary for software proving artifacts and checks.
  """

  use Boundary,
    deps: [
      OfficeGraph.Audit,
      OfficeGraph.ExternalRefs,
      OfficeGraph.Integrations,
      OfficeGraph.Operations,
      OfficeGraph.Repo,
      OfficeGraph.Revisions,
      OfficeGraph.Tenancy
    ],
    exports: [
      CheckRun,
      Commit,
      Domain,
      PullRequest,
      Repository,
      RepositoryRef,
      ReviewComment,
      ReviewThread
    ]

  alias OfficeGraph.{Audit, Operations, Repo, Revisions}

  def upsert_provider_resource(operation, source, resource, existing, attrs)
      when is_map(operation) and is_map(source) and is_atom(resource) and is_map(attrs) do
    with :ok <- Operations.validate_system_operation(operation, :integration_reconcile),
         :ok <- validate_source(source),
         :ok <- validate_scope(operation, attrs),
         :ok <- validate_existing_scope(operation, source, existing),
         :ok <- validate_sequence(attrs) do
      do_upsert_provider_resource(operation, source, resource, existing, attrs)
    end
  end

  def upsert_provider_resource(_operation, _source, _resource, _existing, _attrs),
    do: {:error, :forbidden}

  defp do_upsert_provider_resource(operation, source, resource, nil, attrs) do
    record =
      attrs
      |> Map.merge(%{
        id: Map.get(attrs, :id, Ecto.UUID.generate()),
        organization_id: operation.organization_id,
        workspace_id: operation.workspace_id,
        source_id: source.id,
        sync_state: "synced",
        lifecycle_state: "active",
        operation_id: operation.id
      })
      |> then(&Repo.ash_create!(resource, &1))

    trace!(operation, resource, record.id, "create")
    {:ok, %{record: record, status: :created}}
  end

  defp do_upsert_provider_resource(operation, _source, resource, existing, attrs) do
    if attrs.provider_sequence > (existing.provider_sequence || -1) do
      record =
        existing
        |> Ash.Changeset.for_update(
          :reconcile,
          attrs
          |> Map.drop([:id, :organization_id, :workspace_id, :source_id])
          |> Map.merge(%{
            sync_state: "synced",
            lifecycle_state: "active",
            operation_id: operation.id
          })
        )
        |> Repo.ash_update!()

      trace!(operation, resource, record.id, "update")
      {:ok, %{record: record, status: :updated}}
    else
      {:ok, %{record: existing, status: :stale}}
    end
  end

  defp validate_source(%{id: id, kind: "provider"}) when is_binary(id), do: :ok
  defp validate_source(_source), do: {:error, :forbidden}

  defp validate_scope(operation, attrs) do
    if Map.get(attrs, :organization_id, operation.organization_id) == operation.organization_id and
         Map.get(attrs, :workspace_id, operation.workspace_id) == operation.workspace_id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp validate_existing_scope(_operation, _source, nil), do: :ok

  defp validate_existing_scope(operation, source, existing) do
    if Map.get(existing, :organization_id) == operation.organization_id and
         Map.get(existing, :workspace_id) == operation.workspace_id and
         Map.get(existing, :source_id) == source.id,
       do: :ok,
       else: {:error, :forbidden}
  end

  defp validate_sequence(%{provider_sequence: sequence})
       when is_integer(sequence) and sequence >= 0,
       do: :ok

  defp validate_sequence(_attrs), do: {:error, :invalid_provider_sequence}

  defp trace!(operation, resource, id, change) do
    resource_type = resource |> Module.split() |> List.last() |> Macro.underscore()
    action = "#{resource_type}.reconcile.#{change}"
    Audit.record!(operation, action, resource_type, id)
    Revisions.record!(operation, resource_type, id, action, action)
  end
end
