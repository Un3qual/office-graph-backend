defmodule OfficeGraph.WorkGraph.Changes.ValidateEvidenceCandidateReferences do
  @moduledoc false

  use Ash.Resource.Change

  alias OfficeGraph.Operations.OperationCorrelation
  alias OfficeGraph.Runs.{ExecutionObservation, RunRequiredCheck}
  alias OfficeGraph.WorkGraph.VerificationCheck

  require Ash.Query

  @evidence_candidate_create_action "evidence_candidate.create"
  @agent_runtime_action "agent.runtime.execute"

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
    OperationCorrelation
    |> Ash.Query.filter(
      id == ^operation_id and organization_id == ^organization_id and
        workspace_id == ^workspace_id
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok,
       %{
         action: @evidence_candidate_create_action,
         principal_id: principal_id,
         session_id: session_id
       }} ->
        validate_actor_operation_context(actor, principal_id, session_id)

      {:ok, %{action: @agent_runtime_action, session_id: nil}} when is_nil(actor) ->
        :ok

      {:ok, nil} ->
        {:error, :operation_id, "operation_id must reference an operation in the target scope"}

      {:ok, _other} ->
        {:error, :operation_id,
         "operation_id must reference an evidence candidate create operation"}

      {:error, _error} ->
        {:error, :operation_id, "operation_id could not be validated"}
    end
  end

  defp validate_actor_operation_context(nil, _principal_id, _session_id), do: :ok

  defp validate_actor_operation_context(actor, principal_id, session_id) do
    if Map.get(actor, :principal_id) == principal_id and
         Map.get(actor, :session_id) == session_id do
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
    RunRequiredCheck
    |> Ash.Query.filter(
      run_id == ^work_run_id and verification_check_id == ^verification_check_id and
        organization_id == ^organization_id and workspace_id == ^workspace_id
    )
    |> Ash.exists(authorize?: false)
    |> case do
      {:ok, true} ->
        :ok

      {:ok, false} ->
        {:error, :verification_check_id,
         "verification_check_id must reference a required check for the run"}

      {:error, _error} ->
        {:error, :verification_check_id, "verification_check_id could not be validated"}
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
         organization_id,
         workspace_id
       ) do
    with {:ok, %VerificationCheck{} = verification_check} <-
           scoped_verification_check(
             verification_check_id,
             organization_id,
             workspace_id
           ),
         {:ok, true} <-
           matching_observation?(
             observation_id,
             work_run_id,
             verification_check,
             organization_id,
             workspace_id
           ) do
      :ok
    else
      {:ok, _missing_or_mismatched} ->
        {:error, :execution_observation_id,
         "execution_observation_id must belong to the candidate run and verification check"}

      {:error, _error} ->
        {:error, :execution_observation_id, "execution_observation_id could not be validated"}
    end
  end

  defp scoped_verification_check(verification_check_id, organization_id, workspace_id) do
    VerificationCheck
    |> Ash.Query.filter(
      id == ^verification_check_id and organization_id == ^organization_id and
        workspace_id == ^workspace_id
    )
    |> Ash.read_one(authorize?: false)
  end

  defp matching_observation?(
         observation_id,
         work_run_id,
         verification_check,
         organization_id,
         workspace_id
       ) do
    verification_check_id = verification_check.id
    graph_item_id = verification_check.graph_item_id

    ExecutionObservation
    |> Ash.Query.filter(
      id == ^observation_id and work_run_id == ^work_run_id and
        organization_id == ^organization_id and workspace_id == ^workspace_id and
        (verification_check_id == ^verification_check_id or
           (is_nil(verification_check_id) and graph_item_id == ^graph_item_id))
    )
    |> Ash.exists(authorize?: false)
  end
end
