defmodule OfficeGraph.WorkGraph.Changes.ValidateEvidenceCandidateReferences do
  @moduledoc false

  use Ash.Resource.Change

  alias OfficeGraph.Repo

  @evidence_candidate_create_action "evidence_candidate.create"

  @impl true
  def change(changeset, _opts, context) do
    actor = Map.get(context, :actor)
    organization_id = Ash.Changeset.get_attribute(changeset, :organization_id)
    workspace_id = Ash.Changeset.get_attribute(changeset, :workspace_id)
    operation_id = Ash.Changeset.get_attribute(changeset, :operation_id)
    verification_check_id = Ash.Changeset.get_attribute(changeset, :verification_check_id)
    work_run_id = Ash.Changeset.get_attribute(changeset, :work_run_id)
    observation_id = Ash.Changeset.get_attribute(changeset, :execution_observation_id)

    with :ok <-
           validate_operation_context(operation_id, organization_id, workspace_id, actor),
         :ok <-
           validate_run_requires_check(
             work_run_id,
             verification_check_id,
             organization_id,
             workspace_id
           ),
         :ok <-
           validate_observation_belongs(
             observation_id,
             work_run_id,
             verification_check_id,
             organization_id,
             workspace_id
           ) do
      changeset
    else
      {:error, field, message} ->
        Ash.Changeset.add_error(changeset, field: field, message: message)
    end
  end

  defp validate_operation_context(nil, _organization_id, _workspace_id, _actor), do: :ok

  defp validate_operation_context(_operation_id, nil, _workspace_id, _actor), do: :ok

  defp validate_operation_context(_operation_id, _organization_id, nil, _actor), do: :ok

  defp validate_operation_context(operation_id, organization_id, workspace_id, actor) do
    """
    SELECT action, principal_id, session_id
    FROM operation_correlations
    WHERE id = $1::uuid
      AND organization_id = $2::uuid
      AND workspace_id = $3::uuid
    LIMIT 1
    """
    |> Repo.query!([db_uuid(operation_id), db_uuid(organization_id), db_uuid(workspace_id)])
    |> case do
      %{rows: [[@evidence_candidate_create_action, principal_id, session_id]]} ->
        validate_actor_operation_context(actor, principal_id, session_id)

      %{rows: [_other]} ->
        {:error, :operation_id,
         "operation_id must reference an evidence candidate create operation"}

      %{rows: []} ->
        {:error, :operation_id, "operation_id must reference an operation in the target scope"}
    end
  end

  defp validate_actor_operation_context(nil, _principal_id, _session_id), do: :ok

  defp validate_actor_operation_context(actor, principal_id, session_id) do
    if Map.get(actor, :principal_id) == normalize_uuid(principal_id) and
         Map.get(actor, :session_id) == normalize_uuid(session_id) do
      :ok
    else
      {:error, :operation_id,
       "operation_id must reference an operation for the current actor session"}
    end
  end

  defp validate_run_requires_check(nil, _verification_check_id, _organization_id, _workspace_id) do
    :ok
  end

  defp validate_run_requires_check(_work_run_id, _verification_check_id, nil, _workspace_id) do
    :ok
  end

  defp validate_run_requires_check(_work_run_id, _verification_check_id, _organization_id, nil) do
    :ok
  end

  defp validate_run_requires_check(_work_run_id, nil, _organization_id, _workspace_id) do
    {:error, :verification_check_id,
     "verification_check_id must reference a required check for the run"}
  end

  defp validate_run_requires_check(
         work_run_id,
         verification_check_id,
         organization_id,
         workspace_id
       ) do
    if row_exists?(
         """
         SELECT 1
         FROM run_required_checks
         WHERE run_id = $1::uuid
           AND verification_check_id = $2::uuid
           AND organization_id = $3::uuid
           AND workspace_id = $4::uuid
         LIMIT 1
         """,
         [
           db_uuid(work_run_id),
           db_uuid(verification_check_id),
           db_uuid(organization_id),
           db_uuid(workspace_id)
         ]
       ) do
      :ok
    else
      {:error, :verification_check_id,
       "verification_check_id must reference a required check for the run"}
    end
  end

  defp validate_observation_belongs(nil, _work_run_id, _verification_check_id, _org_id, _ws_id) do
    :ok
  end

  defp validate_observation_belongs(_observation_id, _work_run_id, _check_id, nil, _ws_id) do
    :ok
  end

  defp validate_observation_belongs(_observation_id, _work_run_id, _check_id, _org_id, nil) do
    :ok
  end

  defp validate_observation_belongs(_observation_id, nil, _verification_check_id, _org_id, _ws_id) do
    {:error, :execution_observation_id,
     "execution_observation_id requires a work_run_id on the evidence candidate"}
  end

  defp validate_observation_belongs(
         observation_id,
         work_run_id,
         verification_check_id,
         org_id,
         ws_id
       ) do
    if row_exists?(
         """
         SELECT 1
         FROM execution_observations AS observation
         JOIN verification_checks AS verification_check
           ON verification_check.id = $3::uuid
          AND verification_check.organization_id = $4::uuid
          AND verification_check.workspace_id = $5::uuid
         WHERE observation.id = $1::uuid
           AND observation.work_run_id = $2::uuid
           AND observation.organization_id = $4::uuid
           AND observation.workspace_id = $5::uuid
           AND (
             observation.verification_check_id = verification_check.id
             OR (
               observation.verification_check_id IS NULL
               AND observation.graph_item_id = verification_check.graph_item_id
             )
           )
         LIMIT 1
         """,
         [
           db_uuid(observation_id),
           db_uuid(work_run_id),
           db_uuid(verification_check_id),
           db_uuid(org_id),
           db_uuid(ws_id)
         ]
       ) do
      :ok
    else
      {:error, :execution_observation_id,
       "execution_observation_id must belong to the candidate run and verification check"}
    end
  end

  defp row_exists?(sql, params) do
    %{num_rows: count} = Repo.query!(sql, params)
    count > 0
  end

  defp db_uuid(value) do
    case Ecto.UUID.dump(value) do
      {:ok, uuid} -> uuid
      :error -> value
    end
  end

  defp normalize_uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> value
    end
  end
end
