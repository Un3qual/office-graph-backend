defmodule OfficeGraph.AgentRuntime.ContextAssembler do
  @moduledoc false

  alias OfficeGraph.{Projections, Repo}
  alias OfficeGraph.AgentRuntime.{ContextEntry, ContextPackage}

  require Ash.Query

  def project(authority, graph_item_id, run_id) do
    Projections.agent_context(authority, graph_item_id, run_id)
  end

  def persist_initial!(execution, snapshot, operation, projected_entries) do
    entries =
      projected_entries
      |> Enum.uniq_by(fn entry ->
        {entry.entry_type, entry.resource_type, entry.resource_id, entry.posture}
      end)
      |> Enum.with_index()
      |> Enum.map(fn {entry, ordinal} ->
        entry
        |> Map.take([
          :entry_type,
          :resource_type,
          :resource_id,
          :external_reference_id,
          :posture,
          :rationale_code
        ])
        |> Map.merge(%{
          id: Ecto.UUID.generate(),
          organization_id: execution.organization_id,
          workspace_id: execution.workspace_id,
          ordinal: ordinal,
          operation_id: operation.id,
          content_hash: entry_hash(entry)
        })
      end)

    package =
      Repo.ash_create!(ContextPackage, %{
        id: Ecto.UUID.generate(),
        execution_id: execution.id,
        authority_snapshot_id: snapshot.id,
        organization_id: execution.organization_id,
        workspace_id: execution.workspace_id,
        selected_graph_item_id: execution.graph_item_id,
        run_id: execution.run_id,
        operation_id: operation.id,
        version: 1,
        package_hash: package_hash(entries),
        assembled_at: DateTime.utc_now()
      })

    persisted_entries =
      Enum.map(entries, fn entry ->
        Repo.ash_create!(ContextEntry, Map.put(entry, :context_package_id, package.id))
      end)

    {package, persisted_entries}
  end

  def persist_expansion!(execution, snapshot, operation, request, current_package) do
    current_entries = load_entries!(current_package.id)

    expanded_entries =
      Enum.map(current_entries, fn entry ->
        posture = if expansion_target?(entry, request), do: "included", else: entry.posture

        entry_attrs = %{
          id: Ecto.UUID.generate(),
          organization_id: entry.organization_id,
          workspace_id: entry.workspace_id,
          entry_type: entry.entry_type,
          resource_type: entry.resource_type,
          resource_id: entry.resource_id,
          external_reference_id: entry.external_reference_id,
          posture: posture,
          rationale_code:
            if(posture != entry.posture,
              do: "approved_context_expansion",
              else: entry.rationale_code
            ),
          ordinal: entry.ordinal,
          operation_id: operation.id
        }

        Map.put(entry_attrs, :content_hash, entry_hash(entry_attrs))
      end)

    if Enum.count(expanded_entries, &(&1.rationale_code == "approved_context_expansion")) != 1 do
      Repo.rollback(:context_expansion_target_mismatch)
    end

    package =
      Repo.ash_create!(ContextPackage, %{
        id: Ecto.UUID.generate(),
        execution_id: execution.id,
        authority_snapshot_id: snapshot.id,
        organization_id: execution.organization_id,
        workspace_id: execution.workspace_id,
        selected_graph_item_id: current_package.selected_graph_item_id,
        run_id: current_package.run_id,
        previous_package_id: current_package.id,
        expansion_request_id: request.id,
        operation_id: operation.id,
        version: current_package.version + 1,
        package_hash: package_hash(expanded_entries),
        assembled_at: DateTime.utc_now()
      })

    entries =
      Enum.map(expanded_entries, fn entry ->
        Repo.ash_create!(ContextEntry, Map.put(entry, :context_package_id, package.id))
      end)

    {package, entries}
  end

  def load_initial(execution_id) do
    with {:ok, %ContextPackage{} = package} <- load_package(execution_id),
         {:ok, entries} <- load_entries(package.id) do
      {:ok, {package, entries}}
    end
  end

  defp load_package(execution_id) do
    ContextPackage
    |> Ash.Query.filter(execution_id == ^execution_id and version == 1)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :context_package_missing}
      result -> result
    end
  end

  defp load_entries(package_id) do
    ContextEntry
    |> Ash.Query.filter(context_package_id == ^package_id)
    |> Ash.Query.sort(ordinal: :asc)
    |> Ash.read(authorize?: false)
  end

  defp load_entries!(package_id) do
    case load_entries(package_id) do
      {:ok, entries} -> entries
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp expansion_target?(entry, request) do
    entry.resource_type == request.target_resource_type and
      entry.resource_id == request.target_resource_id and entry.posture == "expansion_required" and
      entry.organization_id == request.organization_id and
      entry.workspace_id == request.target_scope_id
  end

  defp entry_hash(entry) do
    entry
    |> Map.take([
      :entry_type,
      :resource_type,
      :resource_id,
      :external_reference_id,
      :posture,
      :rationale_code,
      :source_version
    ])
    |> digest()
  end

  defp package_hash(entries) do
    entries
    |> Enum.map(&Map.take(&1, [:ordinal, :content_hash, :posture, :rationale_code]))
    |> digest()
  end

  defp digest(value) do
    value
    |> normalize()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp normalize(value) when is_map(value) and not is_struct(value) do
    value
    |> Enum.map(fn {key, nested} -> {to_string(key), normalize(nested)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)
  defp normalize(value), do: value
end
