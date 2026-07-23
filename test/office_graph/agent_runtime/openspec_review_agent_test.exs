defmodule OfficeGraph.AgentRuntime.OpenSpecReviewAgentTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{AgentRuntime, Operations}

  alias OfficeGraph.AgentRuntime.{
    AdapterContract,
    AgentExecution,
    AuthoritySnapshot,
    ContextPackage,
    ExecutionWorker,
    ModelRequest,
    RoutedOutputBatch,
    ToolReferenceResolver,
    ToolRequest
  }

  alias OfficeGraph.AgentRuntime.Adapters.DeterministicOutputRoute
  alias OfficeGraph.AgentRuntime.Agents.OpenSpecReviewWorkflow
  alias OfficeGraph.AgentRuntime.Tools.CommandRunner

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

  defmodule VariantCommandRunner do
    def run("openspec", _argv, _opts) do
      {:ok, Application.fetch_env!(:office_graph, :openspec_review_test_content)}
    end

    def run(executable, argv, opts), do: CommandRunner.run(executable, argv, opts)
  end

  defmodule FailingContinuationEnqueuer do
    def insert(_changeset), do: {:error, :forced_continuation_enqueue_failure}
  end

  defmodule BlockingRepositoryCommandRunner do
    def run("git", ["-C", _root, "cat-file", "-s", _object] = argv, opts) do
      test_pid = Application.fetch_env!(:office_graph, :openspec_review_test_pid)
      send(test_pid, {:blocking_repository_read, self()})

      receive do
        :release_repository_read -> CommandRunner.run("git", argv, opts)
      end
    end

    def run(executable, argv, opts), do: CommandRunner.run(executable, argv, opts)
  end

  defmodule SpyingCommandRunner do
    def run(executable, argv, opts) do
      test_pid = Application.fetch_env!(:office_graph, :openspec_review_test_pid)
      send(test_pid, {:unexpected_reference_read, executable, argv})
      CommandRunner.run(executable, argv, opts)
    end
  end

  defmodule RevokedRevalidator do
    def revalidate_step(_execution_id, _opts), do: {:error, :agent_principal_inactive}
  end

  defmodule RetryTwiceModel do
    @behaviour OfficeGraph.AgentRuntime.ModelAdapter

    alias OfficeGraph.AgentRuntime.Adapters.DeterministicModel

    @impl true
    def manifest, do: DeterministicModel.manifest()

    @impl true
    def invoke(input) do
      if next_attempt(:model) <= 2,
        do: {:error, {:retryable, :model_temporarily_unavailable}},
        else: DeterministicModel.invoke(input)
    end

    @impl true
    def cancel(request_id), do: DeterministicModel.cancel(request_id)

    defp next_attempt(step) do
      coordinator = Application.fetch_env!(:office_graph, :openspec_review_retry_coordinator)

      Agent.get_and_update(coordinator, fn attempts ->
        next = Map.get(attempts, step, 0) + 1
        {next, Map.put(attempts, step, next)}
      end)
    end
  end

  defmodule RetryTwiceOutputRoute do
    @behaviour OfficeGraph.AgentRuntime.ToolAdapter

    alias OfficeGraph.AgentRuntime.Adapters.DeterministicOutputRoute

    @impl true
    def manifest, do: DeterministicOutputRoute.manifest()

    @impl true
    def invoke(input) do
      if next_attempt(:route) <= 2,
        do: {:error, {:retryable, :route_temporarily_unavailable}},
        else: DeterministicOutputRoute.invoke(input)
    end

    @impl true
    def cancel(request_id), do: DeterministicOutputRoute.cancel(request_id)

    defp next_attempt(step) do
      coordinator = Application.fetch_env!(:office_graph, :openspec_review_retry_coordinator)

      Agent.get_and_update(coordinator, fn attempts ->
        next = Map.get(attempts, step, 0) + 1
        {next, Map.put(attempts, step, next)}
      end)
    end
  end

  defmodule MalformedOutputRoute do
    @behaviour OfficeGraph.AgentRuntime.ToolAdapter

    alias OfficeGraph.AgentRuntime.{
      AdapterContract,
      ToolInput,
      ToolOutput
    }

    alias OfficeGraph.AgentRuntime.Adapters.DeterministicOutputRoute

    @impl true
    def manifest, do: DeterministicOutputRoute.manifest()

    @impl true
    def invoke(%ToolInput{} = input) do
      with :ok <- AdapterContract.validate_tool_input(manifest(), input) do
        {:ok,
         %ToolOutput{
           classification: :observation,
           safe_summary: input.adapter_payload.review_summary,
           structured_content: %{
             "observation" => %{"subject" => "unvalidated_placeholder"}
           }
         }}
      end
    end

    @impl true
    def cancel(request_id), do: DeterministicOutputRoute.cancel(request_id)
  end

  defmodule MaximumSummaryModel do
    @behaviour OfficeGraph.AgentRuntime.ModelAdapter

    alias OfficeGraph.AgentRuntime.Adapters.DeterministicModel

    @impl true
    def manifest, do: DeterministicModel.manifest()

    @impl true
    def invoke(input) do
      with {:ok, output} <- DeterministicModel.invoke(input) do
        {:ok, %{output | safe_summary: String.duplicate("x", 1_000)}}
      end
    end

    @impl true
    def cancel(request_id), do: DeterministicModel.cancel(request_id)
  end

  setup do
    retry_coordinator = start_supervised!({Agent, fn -> %{} end})
    Application.put_env(:office_graph, :openspec_review_retry_coordinator, retry_coordinator)

    on_exit(fn ->
      Application.delete_env(:office_graph, :openspec_review_retry_coordinator)
    end)

    fixture =
      "test/support/fixtures/agent_runtime/openspec_review_case.json"
      |> File.read!()
      |> Jason.decode!()

    {:ok, Map.put(AgentRuntimeSupport.invocation_fixture(), :review_fixture, fixture)}
  end

  test "model review receives a full retry budget after both context phases", context do
    configure_adapter_registry(fn registry ->
      put_in(registry, [:models, "deterministic"], RetryTwiceModel)
    end)

    invoked = invoke_automatic!(context, "model-retry-budget")

    assert :ok = perform_step(invoked.execution.id, "context:repository", 1)
    assert :ok = perform_step(invoked.execution.id, "context:openspec", 1)
    assert {:snooze, 1} = perform_step(invoked.execution.id, "model:review", 1)
    assert {:snooze, 1} = perform_step(invoked.execution.id, "model:review", 2)
    assert :ok = perform_step(invoked.execution.id, "model:review", 3)
    assert :ok = perform_step(invoked.execution.id, "output:route", 1)

    completed = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    model_request = request_for!(ModelRequest, invoked.execution.id, "model:review")

    assert completed.state == "completed"
    assert completed.attempt_count == 6
    assert model_request.state == "succeeded"

    assert Agent.get(
             Application.fetch_env!(:office_graph, :openspec_review_retry_coordinator),
             & &1.model
           ) == 3
  end

  test "output route receives a full retry budget after the preceding three phases", context do
    configure_adapter_registry(fn registry ->
      put_in(registry, [:tools, "internal.output.route"], RetryTwiceOutputRoute)
    end)

    invoked = invoke_automatic!(context, "route-retry-budget")

    assert :ok = perform_step(invoked.execution.id, "context:repository", 1)
    assert :ok = perform_step(invoked.execution.id, "context:openspec", 1)
    assert :ok = perform_step(invoked.execution.id, "model:review", 1)
    assert {:snooze, 1} = perform_step(invoked.execution.id, "output:route", 1)
    assert {:snooze, 1} = perform_step(invoked.execution.id, "output:route", 2)
    assert :ok = perform_step(invoked.execution.id, "output:route", 3)

    completed = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    route_request = request_for!(ToolRequest, invoked.execution.id, "output:route")

    assert completed.state == "completed"
    assert completed.attempt_count == 6
    assert route_request.state == "succeeded"

    assert Agent.get(
             Application.fetch_env!(:office_graph, :openspec_review_retry_coordinator),
             & &1.route
           ) == 3
  end

  test "malformed routed batch is rejected before any governed output is written", context do
    configure_adapter_registry(fn registry ->
      put_in(registry, [:tools, "internal.output.route"], MalformedOutputRoute)
    end)

    invoked = invoke_automatic!(context, "malformed-routed-batch")

    assert :ok = perform_step(invoked.execution.id, "context:repository", 1)
    assert :ok = perform_step(invoked.execution.id, "context:openspec", 1)
    assert :ok = perform_step(invoked.execution.id, "model:review", 1)

    assert {:cancel, "malformed_tool_output"} =
             perform_step(invoked.execution.id, "output:route", 1)

    failed = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    assert failed.state == "failed"
    assert failed.failure_code == "malformed_tool_output"
    assert governed_output_counts(invoked.execution.id) == empty_governed_output_counts()
  end

  test "maximum-sized model summary cannot create an oversized routed batch", context do
    configure_adapter_registry(fn registry ->
      put_in(registry, [:models, "deterministic"], MaximumSummaryModel)
    end)

    invoked = invoke_automatic!(context, "bounded-routed-batch")

    assert :ok = perform_all_agent_jobs(invoked.execution.id)

    [message] = records_for(ConversationMessage, invoked.execution.id)
    proposals = records_for(ProposedGraphChange, invoked.execution.id)
    [observation] = records_for(ExecutionObservation, invoked.execution.id)
    [candidate] = records_for(EvidenceCandidate, invoked.execution.id)

    routed_summaries =
      [message.body, observation.rationale, candidate.claim] ++
        Enum.flat_map(proposals, &[&1.payload["title"], &1.payload["body"]])

    assert Enum.all?(routed_summaries, &(byte_size(&1) <= 1_000))
  end

  test "oversized routed batch is rejected by its declared nested schema" do
    oversized_output =
      "bounded review"
      |> RoutedOutputBatch.build()
      |> put_in(
        [Access.key!(:structured_content), "observation", "message", "safe_summary"],
        String.duplicate("x", 1_001)
      )

    assert {:error, {:terminal, :malformed_tool_output}} =
             AdapterContract.validate_tool_output(
               DeterministicOutputRoute.manifest(),
               oversized_output
             )
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

    assert Enum.map(OpenSpecReviewWorkflow.steps(), & &1.key) ==
             context.review_fixture["workflow_steps"]

    assert execution.current_step_key == context.review_fixture["route_step"]

    tool_requests = requests_for(ToolRequest, execution.id)
    model_requests = requests_for(ModelRequest, execution.id)

    read_requests =
      Enum.filter(tool_requests, &(&1.step_key in context.review_fixture["read_steps"]))

    route_requests =
      Enum.filter(tool_requests, &(&1.step_key == context.review_fixture["route_step"]))

    assert Enum.map(read_requests, & &1.step_key) == context.review_fixture["read_steps"]
    assert Enum.map(model_requests, & &1.step_key) == [context.review_fixture["model_step"]]
    assert Enum.map(route_requests, & &1.step_key) == [context.review_fixture["route_step"]]
    assert Enum.all?(tool_requests ++ model_requests, &(&1.state == "succeeded"))
    assert Enum.all?(tool_requests ++ model_requests, &is_binary(&1.input_hash))
    assert Enum.all?(tool_requests ++ model_requests, &is_binary(&1.output_hash))

    assert Enum.map(model_requests, & &1.output_classification) == ["observation"]
    assert Enum.all?(model_requests, &is_binary(&1.output_safe_summary))

    assert Enum.map(read_requests, & &1.tool_key) == ["repository.read", "openspec.read"]
    assert Enum.map(route_requests, & &1.tool_key) == ["internal.output.route"]
    assert Enum.all?(tool_requests, &(not &1.external_write))

    assert Enum.all?(read_requests, fn request_record ->
             is_binary(request_record.output_reference) and
               is_binary(request_record.output_content_hash) and
               request_record.output_byte_count > 0
           end)

    snapshot = snapshot_for!(execution.id)
    context_package = context_package_for!(execution.id)

    assert Enum.all?(read_requests, fn request_record ->
             match?(
               {:ok, %{content: content, reference_id: reference_id}}
               when is_binary(content) and reference_id == request_record.id,
               ToolReferenceResolver.dereference(
                 execution,
                 snapshot,
                 context_package,
                 request_record
               )
             )
           end)

    requests_by_step = Map.new(tool_requests ++ model_requests, &{&1.step_key, &1})

    assert Enum.all?(context.review_fixture["workflow_steps"], fn step_key ->
             request_record = Map.fetch!(requests_by_step, step_key)
             {:ok, operation} = Operations.read_operation(request_record.operation_id)

             operation.idempotency_key == "step:#{step_key}" and
               operation.causation_key == "agent-execution:#{execution.id}" and
               operation.idempotency_scope == "agent-runtime:#{execution.id}"
           end)

    assert (tool_requests ++ model_requests)
           |> Enum.map(& &1.operation_id)
           |> Enum.uniq()
           |> length() == 4

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

  test "changing an authorized tool reference changes the deterministic review result" do
    original_runner = Application.get_env(:office_graph, :agent_runtime_command_runner)
    original_content = Application.get_env(:office_graph, :openspec_review_test_content)

    Application.put_env(:office_graph, :agent_runtime_command_runner, VariantCommandRunner)

    on_exit(fn ->
      restore_env(:agent_runtime_command_runner, original_runner)
      restore_env(:openspec_review_test_content, original_content)
    end)

    first = run_variant_review!("authorized-openspec-context-v1")
    second = run_variant_review!("authorized-openspec-context-v2")

    refute first.openspec_reference_hash == second.openspec_reference_hash
    refute first.model_output_hash == second.model_output_hash
    refute first.model_output_summary == second.model_output_summary
    refute first.message_body_hash == second.message_body_hash
  end

  test "continuation enqueue failure rolls back the completed read and its next operation",
       context do
    request =
      AgentRuntimeSupport.request(context, %{
        origin: "system_trigger",
        invocation_mode: "automatic",
        idempotency_key: "automatic-continuation-rollback-#{context.suffix}",
        requested_capabilities: context.definition.requested_capabilities
      })

    assert {:ok, operation} = AgentRuntimeSupport.system_operation(context, request)
    assert {:ok, invoked} = AgentRuntime.invoke_system(operation, request)
    [job] = AgentRuntimeSupport.execution_jobs(invoked.execution.id)

    original = Application.get_env(:office_graph, :agent_runtime_step_enqueuer)

    Application.put_env(
      :office_graph,
      :agent_runtime_step_enqueuer,
      FailingContinuationEnqueuer
    )

    on_exit(fn -> restore_env(:agent_runtime_step_enqueuer, original) end)

    assert {:cancel, "agent_step_continuation_failed"} =
             ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})

    failed = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    [read_request] = requests_for(ToolRequest, invoked.execution.id)

    assert failed.state == "failed"
    assert failed.current_step_key == "context:repository"
    assert read_request.state == "failed"
    assert is_nil(read_request.output_reference)
    assert is_nil(read_request.output_content_hash)
    assert is_nil(read_request.output_byte_count)

    assert [] ==
             Operations.OperationCorrelation
             |> Ash.Query.filter(
               causation_key == ^"agent-execution:#{failed.id}" and
                 idempotency_key == "step:context:openspec"
             )
             |> Ash.read!(authorize?: false)
  end

  test "cancelling a leased automatic tool step durably cancels its typed request", context do
    request =
      AgentRuntimeSupport.request(context, %{
        origin: "system_trigger",
        invocation_mode: "automatic",
        idempotency_key: "automatic-tool-cancellation-#{context.suffix}",
        requested_capabilities: context.definition.requested_capabilities
      })

    assert {:ok, operation} = AgentRuntimeSupport.system_operation(context, request)
    assert {:ok, invoked} = AgentRuntime.invoke_system(operation, request)
    [job] = AgentRuntimeSupport.execution_jobs(invoked.execution.id)

    original_runner = Application.get_env(:office_graph, :agent_runtime_command_runner)

    Application.put_env(
      :office_graph,
      :agent_runtime_command_runner,
      BlockingRepositoryCommandRunner
    )

    Application.put_env(:office_graph, :openspec_review_test_pid, self())

    on_exit(fn ->
      restore_env(:agent_runtime_command_runner, original_runner)
      Application.delete_env(:office_graph, :openspec_review_test_pid)
    end)

    worker =
      Elixir.Task.async(fn ->
        ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})
      end)

    assert_receive {:blocking_repository_read, command_pid}, 1_000

    running = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    [tool_request] = requests_for(ToolRequest, invoked.execution.id)
    assert running.state == "running"
    assert tool_request.state == "running"

    assert {:snooze, duplicate_delay} =
             ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})

    assert duplicate_delay in 1..30
    assert [_same_request] = requests_for(ToolRequest, invoked.execution.id)

    attrs = %{execution_id: running.id, expected_state_version: running.state_version}

    assert {:ok, cancel_operation} =
             Operations.start_command(
               context.session,
               :agent_cancel,
               "cancel-automatic-tool-#{context.suffix}",
               attrs
             )

    assert {:ok, cancelled} =
             AgentRuntime.cancel_execution(context.session, cancel_operation, attrs)

    assert cancelled.execution.state == "cancelled"
    assert Ash.get!(ToolRequest, tool_request.id, authorize?: false).state == "cancelled"

    assert {:ok, replayed} =
             AgentRuntime.cancel_execution(context.session, cancel_operation, attrs)

    assert replayed.replayed?
    assert replayed.tool_request.id == tool_request.id
    assert replayed.tool_request.state == "cancelled"

    send(command_pid, :release_repository_read)
    assert :ok = Elixir.Task.await(worker, 1_000)
    assert Ash.get!(ToolRequest, tool_request.id, authorize?: false).state == "cancelled"
  end

  test "authority is revalidated before classified tool references are dereferenced", context do
    request =
      AgentRuntimeSupport.request(context, %{
        origin: "system_trigger",
        invocation_mode: "automatic",
        idempotency_key: "automatic-reference-revalidation-#{context.suffix}",
        requested_capabilities: context.definition.requested_capabilities
      })

    assert {:ok, operation} = AgentRuntimeSupport.system_operation(context, request)
    assert {:ok, invoked} = AgentRuntime.invoke_system(operation, request)

    [repository_job] = AgentRuntimeSupport.execution_jobs(invoked.execution.id)
    assert :ok = ExecutionWorker.perform(%{repository_job | attempt: 1, max_attempts: 3})

    openspec_job =
      invoked.execution.id
      |> AgentRuntimeSupport.execution_jobs()
      |> Enum.find(&(&1.args["step_key"] == "context:openspec"))

    assert :ok = ExecutionWorker.perform(%{openspec_job | attempt: 1, max_attempts: 3})

    model_job =
      invoked.execution.id
      |> AgentRuntimeSupport.execution_jobs()
      |> Enum.find(&(&1.args["step_key"] == "model:review"))

    original_runner = Application.get_env(:office_graph, :agent_runtime_command_runner)
    original_revalidator = Application.get_env(:office_graph, :agent_runtime_revalidator)
    Application.put_env(:office_graph, :agent_runtime_command_runner, SpyingCommandRunner)
    Application.put_env(:office_graph, :agent_runtime_revalidator, RevokedRevalidator)
    Application.put_env(:office_graph, :openspec_review_test_pid, self())

    on_exit(fn ->
      restore_env(:agent_runtime_command_runner, original_runner)
      restore_env(:agent_runtime_revalidator, original_revalidator)
      Application.delete_env(:office_graph, :openspec_review_test_pid)
    end)

    assert {:cancel, "agent_principal_inactive"} =
             ExecutionWorker.perform(%{model_job | attempt: 1, max_attempts: 3})

    refute_receive {:unexpected_reference_read, _executable, _argv}
    failed = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    assert failed.state == "failed"
    assert failed.current_step_key == "model:review"
    assert requests_for(ModelRequest, invoked.execution.id) == []
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

  defp request_for!(resource, execution_id, step_key) do
    resource
    |> Ash.Query.filter(execution_id == ^execution_id and step_key == ^step_key)
    |> Ash.read_one!(authorize?: false)
  end

  defp invoke_automatic!(context, suffix) do
    request =
      AgentRuntimeSupport.request(context, %{
        origin: "system_trigger",
        invocation_mode: "automatic",
        idempotency_key: "automatic-#{suffix}-#{context.suffix}",
        requested_capabilities: context.definition.requested_capabilities
      })

    {:ok, operation} = AgentRuntimeSupport.system_operation(context, request)
    {:ok, invoked} = AgentRuntime.invoke_system(operation, request)
    invoked
  end

  defp perform_step(execution_id, step_key, attempt) do
    job =
      execution_id
      |> AgentRuntimeSupport.execution_jobs()
      |> Enum.find(&(&1.args["step_key"] == step_key))

    ExecutionWorker.perform(%{job | attempt: attempt, max_attempts: 3})
  end

  defp configure_adapter_registry(update) when is_function(update, 1) do
    original = Application.fetch_env!(:office_graph, :agent_runtime_adapters)
    registry = original |> Map.new() |> update.()
    Application.put_env(:office_graph, :agent_runtime_adapters, registry)
    on_exit(fn -> Application.put_env(:office_graph, :agent_runtime_adapters, original) end)
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

  defp empty_governed_output_counts do
    %{messages: 0, proposals: 0, observations: 0, candidates: 0}
  end

  defp snapshot_for!(execution_id) do
    AuthoritySnapshot
    |> Ash.Query.filter(execution_id == ^execution_id and version == 1)
    |> Ash.read_one!(authorize?: false)
  end

  defp context_package_for!(execution_id) do
    ContextPackage
    |> Ash.Query.filter(execution_id == ^execution_id)
    |> Ash.Query.sort(version: :desc)
    |> Ash.read_one!(authorize?: false)
  end

  defp run_variant_review!(content) do
    Application.put_env(:office_graph, :openspec_review_test_content, content)
    context = AgentRuntimeSupport.invocation_fixture()

    request =
      AgentRuntimeSupport.request(context, %{
        origin: "system_trigger",
        invocation_mode: "automatic",
        idempotency_key: "automatic-variant-#{context.suffix}",
        requested_capabilities: context.definition.requested_capabilities
      })

    {:ok, operation} = AgentRuntimeSupport.system_operation(context, request)
    {:ok, invoked} = AgentRuntime.invoke_system(operation, request)
    :ok = perform_all_agent_jobs(invoked.execution.id)

    openspec_request =
      ToolRequest
      |> Ash.Query.filter(
        execution_id == ^invoked.execution.id and step_key == "context:openspec"
      )
      |> Ash.read_one!(authorize?: false)

    model_request =
      ModelRequest
      |> Ash.Query.filter(execution_id == ^invoked.execution.id and step_key == "model:review")
      |> Ash.read_one!(authorize?: false)

    [message] = records_for(ConversationMessage, invoked.execution.id)

    %{
      openspec_reference_hash: openspec_request.output_content_hash,
      model_output_hash: model_request.output_hash,
      model_output_summary: model_request.output_safe_summary,
      message_body_hash: message.body_hash
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:office_graph, key)
  defp restore_env(key, value), do: Application.put_env(:office_graph, key, value)
end
