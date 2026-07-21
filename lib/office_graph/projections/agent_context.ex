defmodule OfficeGraph.Projections.AgentContext do
  @moduledoc false

  alias OfficeGraph.{Authorization, Runs, WorkGraph}
  alias OfficeGraph.ExternalRefs.ExternalReference

  require Ash.Query

  def project(authority, graph_item_id, run_id)
      when is_map(authority) and is_binary(graph_item_id) and is_binary(run_id) do
    with {:ok, scope} <- scope(authority),
         :ok <-
           Authorization.authorize_system_principal(
             scope.principal_id,
             scope.organization_id,
             scope.workspace_id,
             :skeleton_read
           ),
         {:ok, graph_context} <- WorkGraph.agent_context_items(authority, graph_item_id),
         {:ok, run_context} <- Runs.agent_context(authority, run_id, graph_item_id),
         selected_item = graph_context.selected_item,
         related_entries = related_entries(graph_context.relationships, selected_item.id),
         {:ok, external_entries} <- external_entries(scope, selected_item) do
      {:ok,
       [
         included(
           "selected_graph_item",
           selected_item.resource_type,
           selected_item.id,
           "selected_for_agent_invocation",
           selected_item.updated_at
         ),
         included(
           "work_run",
           "work_run",
           run_context.run.id,
           "governing_work_run",
           run_context.run.updated_at
         ),
         included(
           "work_packet",
           "work_packet",
           run_context.packet.id,
           "governing_work_packet",
           run_context.packet.updated_at
         ),
         included(
           "work_packet_version",
           "work_packet_version",
           run_context.packet_version.id,
           "governing_work_packet_version",
           run_context.packet_version.updated_at
         )
       ] ++
         Enum.map(run_context.required_checks, fn required_check ->
           included(
             "verification_check",
             "verification_check",
             required_check.verification_check_id,
             "required_by_work_run",
             required_check.updated_at
           )
         end) ++
         Enum.map(run_context.observations, fn observation ->
           included(
             "execution_observation",
             "execution_observation",
             observation.id,
             "recorded_for_work_run",
             observation.updated_at
           )
         end) ++
         Enum.map(run_context.evidence_items, fn evidence ->
           included(
             "evidence_item",
             "evidence_item",
             evidence.id,
             "accepted_for_work_run",
             evidence.updated_at
           )
         end) ++
         Enum.map(run_context.verification_results, fn result ->
           included(
             "verification_result",
             "verification_result",
             result.id,
             "recorded_for_work_run",
             result.updated_at
           )
         end) ++ related_entries ++ external_entries}
    else
      {:error, :integration_storage_unavailable} = error -> error
      _missing_or_forbidden -> {:error, :forbidden}
    end
  end

  def project(_authority, _graph_item_id, _run_id), do: {:error, :forbidden}

  defp scope(authority) do
    with principal_id when is_binary(principal_id) <- Map.get(authority, :agent_principal_id),
         organization_id when is_binary(organization_id) <- Map.get(authority, :organization_id),
         workspace_id when is_binary(workspace_id) <- Map.get(authority, :workspace_id) do
      {:ok,
       %{
         principal_id: principal_id,
         organization_id: organization_id,
         workspace_id: workspace_id
       }}
    else
      _invalid -> {:error, :forbidden}
    end
  end

  defp related_entries(relationships, selected_item_id) do
    Enum.map(relationships, fn relationship ->
      case related_endpoint(relationship, selected_item_id) do
        %{visibility: :visible} = endpoint ->
          included(
            "related_graph_item",
            endpoint.resource_type,
            endpoint.id,
            "authorized_graph_relationship",
            relationship.valid_from
          )

        %{visibility: :redacted} ->
          restricted_relationship(relationship)
      end
    end)
  end

  defp external_entries(scope, selected_item) do
    ExternalReference
    |> Ash.Query.filter(
      organization_id == ^scope.organization_id and
        (is_nil(workspace_id) or workspace_id == ^scope.workspace_id) and
        resource_type == ^selected_item.resource_type and
        resource_id == ^selected_item.resource_id
    )
    |> Ash.Query.sort(inserted_at: :asc, id: :asc)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, references} ->
        {:ok,
         Enum.map(references, fn reference ->
           included(
             "external_reference",
             "external_reference",
             reference.id,
             "linked_to_selected_graph_item",
             reference.updated_at,
             reference.id
           )
         end)}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp related_endpoint(relationship, selected_item_id) do
    if Map.get(relationship.source, :id) == selected_item_id,
      do: relationship.target,
      else: relationship.source
  end

  defp included(
         entry_type,
         resource_type,
         resource_id,
         rationale_code,
         source_version,
         external_reference_id \\ nil
       ) do
    %{
      entry_type: entry_type,
      resource_type: resource_type,
      resource_id: resource_id,
      external_reference_id: external_reference_id,
      posture: "included",
      rationale_code: rationale_code,
      source_version: source_version
    }
  end

  defp restricted_relationship(relationship) do
    %{
      entry_type: "related_graph_item",
      resource_type: "graph_relationship",
      resource_id: relationship.id,
      external_reference_id: nil,
      posture: "restricted",
      rationale_code: "related_item_outside_workspace",
      source_version: relationship.valid_from
    }
  end
end
