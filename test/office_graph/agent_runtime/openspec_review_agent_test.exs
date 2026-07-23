defmodule OfficeGraph.AgentRuntime.OpenSpecReviewAgentTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.AgentRuntime

  alias OfficeGraph.AgentRuntime.{
    AgentExecution,
    ExecutionWorker,
    ModelRequest,
    ToolRequest
  }

  alias OfficeGraph.NodeConversations.ConversationMessage
  alias OfficeGraph.ProposedChanges.ProposedGraphChange
  alias OfficeGraph.Runs.ExecutionObservation
  alias OfficeGraph.TestSupport.AgentRuntimeSupport

  alias OfficeGraph.WorkGraph.{
    EvidenceCandidate,
    EvidenceItem,
    GraphItem,
    ReviewFinding,
    Task,
    VerificationResult
  }

  require Ash.Query

  setup do
    fixture =
      "test/support/fixtures/agent_runtime/openspec_review_case.json"
      |> File.read!()
      |> Jason.decode!()

    {:ok, Map.put(AgentRuntimeSupport.invocation_fixture(), :review_fixture, fixture)}
  end

  test "automatic OpenSpec review reads authorized context and produces governed records",
       context do
    before_direct_effects = direct_effect_counts()

    request =
      AgentRuntimeSupport.request(context, %{
        origin: "system_trigger",
        invocation_mode: "automatic",
        idempotency_key: "automatic-openspec-review-#{context.suffix}",
        requested_capabilities: context.definition.requested_capabilities
      })

    assert {:ok, operation} = AgentRuntimeSupport.system_operation(context, request)
    assert {:ok, invoked} = AgentRuntime.invoke_system(operation, request)

    assert :ok = perform_all_agent_jobs(invoked.execution.id)

    execution = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    assert execution.state == "completed"
    assert execution.current_step_key == List.last(context.review_fixture["model_steps"])

    tool_requests = requests_for(ToolRequest, execution.id)
    model_requests = requests_for(ModelRequest, execution.id)

    assert Enum.map(tool_requests, & &1.step_key) == context.review_fixture["tool_steps"]
    assert Enum.map(model_requests, & &1.step_key) == context.review_fixture["model_steps"]
    assert Enum.all?(tool_requests ++ model_requests, &(&1.state == "succeeded"))
    assert Enum.all?(tool_requests ++ model_requests, &is_binary(&1.input_hash))
    assert Enum.all?(tool_requests ++ model_requests, &is_binary(&1.output_hash))

    assert Enum.map(model_requests, & &1.output_classification) ==
             context.review_fixture["output_classifications"]

    assert Enum.map(tool_requests, & &1.tool_key) == ["repository.read", "openspec.read"]
    assert Enum.all?(tool_requests, &(not &1.external_write))

    assert [message] = records_for(ConversationMessage, execution.id)
    assert message.source == "agent"

    assert [finding, proposal] =
             ProposedGraphChange
             |> Ash.Query.filter(execution_id == ^execution.id)
             |> Ash.Query.sort(step_key: :asc)
             |> Ash.read!(authorize?: false)

    assert {finding.change_type, finding.status} == {"create_review_finding", "pending"}
    assert {proposal.change_type, proposal.status} == {"create_task", "pending"}

    assert [check] = records_for(ExecutionObservation, execution.id)
    assert check.observed_status == "reported"
    assert check.trust_basis == "agent_reported"

    assert [candidate] = records_for(EvidenceCandidate, execution.id)
    assert candidate.candidate_state == "candidate"
    assert candidate.trust_basis == "agent_reported"

    assert direct_effect_counts() == before_direct_effects
    assert Repo.aggregate(VerificationResult, :count) == 0

    counts = governed_output_counts(execution.id)

    assert :ok = replay_all_agent_jobs(execution.id)
    assert governed_output_counts(execution.id) == counts

    Enum.each(tool_requests ++ model_requests, fn request_record ->
      fields = Map.from_struct(request_record)
      refute Map.has_key?(fields, :raw_input)
      refute Map.has_key?(fields, :raw_output)
      refute Map.has_key?(fields, :raw_payload)
    end)
  end

  defp perform_all_agent_jobs(execution_id),
    do: perform_all_agent_jobs(execution_id, MapSet.new(), 0)

  defp perform_all_agent_jobs(_execution_id, _performed, count) when count > 12,
    do: {:error, :workflow_did_not_complete}

  defp perform_all_agent_jobs(execution_id, performed, count) do
    execution = Ash.get!(AgentExecution, execution_id, authorize?: false)

    if execution.state == "completed" do
      :ok
    else
      job =
        execution_id
        |> AgentRuntimeSupport.execution_jobs()
        |> Enum.sort_by(&{&1.inserted_at, &1.id})
        |> Enum.find(&(not MapSet.member?(performed, &1.id)))

      if job do
        with :ok <- ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3}) do
          perform_all_agent_jobs(execution_id, MapSet.put(performed, job.id), count + 1)
        end
      else
        {:error, :workflow_job_missing}
      end
    end
  end

  defp replay_all_agent_jobs(execution_id) do
    execution_id
    |> AgentRuntimeSupport.execution_jobs()
    |> Enum.reduce_while(:ok, fn job, :ok ->
      case ExecutionWorker.perform(%{job | attempt: 2, max_attempts: 3}) do
        :ok -> {:cont, :ok}
        other -> {:halt, other}
      end
    end)
  end

  defp requests_for(resource, execution_id) do
    resource
    |> Ash.Query.filter(execution_id == ^execution_id)
    |> Ash.Query.sort(requested_at: :asc, id: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp records_for(resource, execution_id) do
    resource
    |> Ash.Query.filter(execution_id == ^execution_id)
    |> Ash.read!(authorize?: false)
  end

  defp direct_effect_counts do
    %{
      graph_items: Repo.aggregate(GraphItem, :count),
      tasks: Repo.aggregate(Task, :count),
      review_findings: Repo.aggregate(ReviewFinding, :count),
      evidence_items: Repo.aggregate(EvidenceItem, :count)
    }
  end

  defp governed_output_counts(execution_id) do
    %{
      messages: length(records_for(ConversationMessage, execution_id)),
      proposals: length(records_for(ProposedGraphChange, execution_id)),
      observations: length(records_for(ExecutionObservation, execution_id)),
      candidates: length(records_for(EvidenceCandidate, execution_id))
    }
  end
end
