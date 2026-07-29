defmodule OfficeGraph.Projections.RunState.Activity do
  @moduledoc false

  alias OfficeGraph.Runs.{ExecutionObservation, RunRequiredCheck}

  alias OfficeGraph.WorkGraph.{
    EvidenceCandidate,
    EvidenceItem,
    VerificationResult
  }

  require Ash.Query

  def page(session_context, run, after_key, limit) do
    with {:ok, activities} <- read_activities(session_context, run, after_key, limit),
         {:ok, activities} <- mark_failed_missing_evidence(session_context, run, activities) do
      activities =
        activities
        |> Enum.reduce([], fn activity, selected ->
          selected
          |> insert_activity(activity)
          |> Enum.take(limit + 1)
        end)

      {:ok, activities}
    end
  end

  defp read_activities(session_context, run, after_key, limit) do
    run_resource = run.__struct__
    execution_resource = related_resource!(run_resource, :agent_executions)
    conversation_resource = related_resource!(run_resource, :conversations)

    specs = [
      required_check_spec(session_context, run),
      observation_spec(session_context, run),
      evidence_candidate_spec(session_context, run),
      evidence_item_spec(session_context, run),
      verification_result_spec(session_context, run),
      execution_spec(execution_resource, session_context, run),
      context_spec(execution_resource, session_context, run),
      approval_spec(execution_resource, session_context, run),
      expansion_spec(execution_resource, session_context, run),
      tool_request_spec(execution_resource, session_context, run),
      proposal_spec(execution_resource, session_context, run),
      message_spec(conversation_resource, session_context, run),
      missing_evidence_spec(session_context, run)
    ]

    Enum.reduce_while(specs, {:ok, []}, fn spec, {:ok, activities} ->
      {kind, query, projection, cursor_attribute} = normalize_spec(spec)

      query =
        query
        |> apply_cursor(kind, cursor_attribute, after_key)
        |> Ash.Query.sort([{:inserted_at, :asc}, {cursor_attribute, :asc}])
        |> Ash.Query.limit(limit + 1)

      case Ash.read(query, actor: session_context) do
        {:ok, records} ->
          projected = Enum.map(records, &projection.(&1))
          {:cont, {:ok, Enum.reverse(projected, activities)}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp required_check_spec(session_context, run) do
    query =
      RunRequiredCheck
      |> scoped_run_query(session_context, :run_id, run.id)
      |> Ash.Query.load(:verification_check)

    {"required_check", query,
     fn required_check ->
       activity(
         required_check,
         "required_check",
         title(required_check.verification_check, "Required check"),
         required_check.state
       )
     end}
  end

  defp observation_spec(session_context, run) do
    query =
      scoped_run_query(ExecutionObservation, session_context, :work_run_id, run.id)

    {"observation", query, &activity(&1, "observation", &1.source_identity, &1.normalized_status)}
  end

  defp evidence_candidate_spec(session_context, run) do
    query =
      scoped_run_query(EvidenceCandidate, session_context, :work_run_id, run.id)

    {"evidence_candidate", query,
     &activity(&1, "evidence_candidate", &1.claim, &1.candidate_state)}
  end

  defp evidence_item_spec(session_context, run) do
    query = scoped_run_query(EvidenceItem, session_context, :work_run_id, run.id)

    {"evidence_item", query, &activity(&1, "evidence_item", &1.title, &1.state)}
  end

  defp verification_result_spec(session_context, run) do
    query =
      scoped_run_query(VerificationResult, session_context, :work_run_id, run.id)

    {"verification_result", query,
     &activity(&1, "verification_result", &1.policy_basis || "Verification result", &1.result)}
  end

  defp execution_spec(resource, session_context, run) do
    query = scoped_run_query(resource, session_context, :run_id, run.id)

    {"agent_execution", query, &activity(&1, "agent_execution", "Agent execution", &1.state)}
  end

  defp context_spec(execution_resource, session_context, run) do
    resource = related_resource!(execution_resource, :context_packages)
    query = scoped_run_query(resource, session_context, :run_id, run.id)

    {"agent_context", query,
     &activity(&1, "agent_context", "Agent context version #{&1.version}", "assembled")}
  end

  defp approval_spec(execution_resource, session_context, run) do
    resource = related_resource!(execution_resource, :approval_requests)
    query = scoped_execution_query(resource, session_context, run.id)

    {"agent_approval", query, &activity(&1, "agent_approval", &1.requested_action, &1.state)}
  end

  defp expansion_spec(execution_resource, session_context, run) do
    resource = related_resource!(execution_resource, :context_expansion_requests)
    query = scoped_execution_query(resource, session_context, run.id)

    {"agent_context_expansion", query,
     &activity(&1, "agent_context_expansion", &1.target_resource_type, &1.state)}
  end

  defp tool_request_spec(execution_resource, session_context, run) do
    resource = related_resource!(execution_resource, :tool_requests)

    query =
      Ash.Query.filter(
        resource,
        execution.run_id == ^run.id and
          execution.organization_id == ^session_context.organization_id and
          execution.workspace_id == ^session_context.workspace_id
      )

    {"agent_tool_request", query, &activity(&1, "agent_tool_request", &1.tool_key, &1.state)}
  end

  defp proposal_spec(execution_resource, session_context, run) do
    resource = related_resource!(execution_resource, :proposed_changes)

    query =
      Ash.Query.filter(
        resource,
        execution.run_id == ^run.id and
          execution.organization_id == ^session_context.organization_id and
          execution.workspace_id == ^session_context.workspace_id
      )

    {"agent_proposal", query, &activity(&1, "agent_proposal", &1.change_type, &1.status)}
  end

  defp message_spec(conversation_resource, session_context, run) do
    resource = related_resource!(conversation_resource, :messages)

    query =
      Ash.Query.filter(
        resource,
        conversation.run_id == ^run.id and
          conversation.organization_id == ^session_context.organization_id and
          conversation.workspace_id == ^session_context.workspace_id
      )

    {"conversation_message", query,
     &activity(&1, "conversation_message", message_title(&1.source), "recorded")}
  end

  defp missing_evidence_spec(session_context, run) do
    query =
      RunRequiredCheck
      |> scoped_run_query(session_context, :run_id, run.id)
      |> Ash.Query.filter(state == "pending")
      |> Ash.Query.load(:verification_check)

    {"missing_evidence", query,
     fn required_check ->
       required_check
       |> activity(
         "missing_evidence",
         title(required_check.verification_check, "Missing evidence"),
         "missing_accepted_evidence"
       )
       |> Map.put(:verification_check_id, required_check.verification_check_id)
       |> Map.put(:stable_id, required_check.verification_check_id)
     end, :verification_check_id}
  end

  defp scoped_run_query(resource, session_context, :run_id, run_id) do
    resource
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and run_id == ^run_id
    )
  end

  defp scoped_run_query(resource, session_context, :work_run_id, run_id) do
    resource
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and work_run_id == ^run_id
    )
  end

  defp scoped_execution_query(resource, session_context, run_id) do
    Ash.Query.filter(
      resource,
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and execution.run_id == ^run_id
    )
  end

  defp normalize_spec({kind, query, projection}),
    do: {kind, query, projection, :id}

  defp normalize_spec({kind, query, projection, cursor_attribute}),
    do: {kind, query, projection, cursor_attribute}

  defp apply_cursor(query, _kind, _cursor_attribute, nil), do: query

  defp apply_cursor(query, kind, :id, {inserted_at, cursor_kind, id}) do
    inserted_at = DateTime.from_naive!(inserted_at, "Etc/UTC")

    cond do
      kind < cursor_kind ->
        Ash.Query.filter(query, inserted_at > ^inserted_at)

      kind == cursor_kind ->
        Ash.Query.filter(
          query,
          inserted_at > ^inserted_at or (inserted_at == ^inserted_at and id > ^id)
        )

      true ->
        Ash.Query.filter(query, inserted_at >= ^inserted_at)
    end
  end

  defp apply_cursor(
         query,
         kind,
         :verification_check_id,
         {inserted_at, cursor_kind, id}
       ) do
    inserted_at = DateTime.from_naive!(inserted_at, "Etc/UTC")

    cond do
      kind < cursor_kind ->
        Ash.Query.filter(query, inserted_at > ^inserted_at)

      kind == cursor_kind ->
        Ash.Query.filter(
          query,
          inserted_at > ^inserted_at or
            (inserted_at == ^inserted_at and verification_check_id > ^id)
        )

      true ->
        Ash.Query.filter(query, inserted_at >= ^inserted_at)
    end
  end

  defp mark_failed_missing_evidence(session_context, run, activities) do
    verification_check_ids =
      activities
      |> Enum.filter(&(&1.kind == "missing_evidence"))
      |> Enum.map(& &1.verification_check_id)
      |> Enum.uniq()

    if verification_check_ids == [] do
      {:ok, activities}
    else
      VerificationResult
      |> Ash.Query.filter(
        work_run_id == ^run.id and
          organization_id == ^session_context.organization_id and
          workspace_id == ^session_context.workspace_id and result == "failed" and
          verification_check_id in ^verification_check_ids
      )
      |> Ash.Query.select([:verification_check_id])
      |> Ash.read(actor: session_context)
      |> case do
        {:ok, failed_results} ->
          failed_ids = MapSet.new(failed_results, & &1.verification_check_id)

          {:ok,
           Enum.map(activities, fn
             %{kind: "missing_evidence", verification_check_id: check_id} = activity ->
               activity
               |> Map.put(
                 :status,
                 if(MapSet.member?(failed_ids, check_id),
                   do: "failed_check",
                   else: "missing_accepted_evidence"
                 )
               )
               |> Map.delete(:verification_check_id)

             activity ->
               activity
           end)}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp activity(record, kind, title, status) do
    %{
      inserted_at: record.inserted_at,
      kind: kind,
      stable_id: record.id,
      title: title,
      status: status
    }
  end

  defp title(%{title: title}, _fallback) when not is_nil(title), do: title
  defp title(_record, fallback), do: fallback

  defp message_title("agent"), do: "Agent message"
  defp message_title("human"), do: "Human message"
  defp message_title(_source), do: "System message"

  defp insert_activity([], activity), do: [activity]

  defp insert_activity([next | rest] = activities, activity) do
    if before?(activity, next) do
      [activity | activities]
    else
      [next | insert_activity(rest, activity)]
    end
  end

  defp before?(left, right) do
    case compare_timestamps(left.inserted_at, right.inserted_at) do
      :lt -> true
      :gt -> false
      :eq -> {left.kind, left.stable_id} <= {right.kind, right.stable_id}
    end
  end

  defp compare_timestamps(%DateTime{} = left, %DateTime{} = right),
    do: DateTime.compare(left, right)

  defp compare_timestamps(%NaiveDateTime{} = left, %NaiveDateTime{} = right),
    do: NaiveDateTime.compare(left, right)

  defp related_resource!(resource, relationship) do
    Ash.Resource.Info.related(resource, relationship) ||
      raise ArgumentError,
            "missing Ash relationship #{inspect(resource)}.#{relationship}"
  end
end
