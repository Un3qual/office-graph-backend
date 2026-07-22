defmodule OfficeGraph.TestSupport.AgentRuntimeSupport do
  @moduledoc false

  alias OfficeGraph.{AgentRuntime, Foundation, Operations}
  alias OfficeGraph.AgentRuntime.InvocationRequest
  alias OfficeGraph.TestSupport.OperatorProjectionSupport

  def invocation_fixture do
    suffix = System.unique_integer([:positive])

    {:ok, bootstrap} =
      Foundation.bootstrap_local_owner(
        organization_name: "Agent Invocation #{suffix}",
        organization_slug: "agent-invocation-#{suffix}",
        workspace_name: "Agent Invocation Workspace #{suffix}",
        workspace_slug: "agent-invocation-workspace-#{suffix}",
        initiative_name: "Agent Invocation Initiative #{suffix}",
        initiative_slug: "agent-invocation-initiative-#{suffix}",
        owner_email: "agent-invocation-#{suffix}@office-graph.local"
      )

    {:ok, verification_check} =
      OperatorProjectionSupport.create_required_verification_check(bootstrap.session)

    {:ok, run_result} =
      OperatorProjectionSupport.create_ready_run(bootstrap.session, verification_check)

    {:ok, bound} =
      AgentRuntime.bind_openspec_review_agent(bootstrap.session, %{
        idempotency_key: "bind-openspec-review-#{suffix}"
      })

    %{
      bootstrap: bootstrap,
      session: bootstrap.session,
      verification_check: verification_check,
      graph_item_id: verification_check.graph_item_id,
      run: run_result.run,
      packet_version: run_result.packet_version,
      definition: bound.definition,
      binding: bound.binding,
      agent_principal: bound.principal,
      suffix: suffix
    }
  end

  def request(context, overrides \\ %{}) do
    context
    |> base_request()
    |> Map.merge(overrides)
    |> InvocationRequest.new!()
  end

  def human_operation(session, request) do
    Operations.start_command(
      session,
      :agent_invoke,
      request.idempotency_key,
      InvocationRequest.command_input(request)
    )
  end

  def invoke_human(context, overrides \\ %{}) do
    request = request(context, overrides)
    {:ok, operation} = human_operation(context.session, request)
    {:ok, result} = AgentRuntime.invoke(context.session, operation, request)
    Map.merge(result, %{request: request, operation: operation})
  end

  def system_operation(context, request, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          organization_id: context.bootstrap.organization.id,
          workspace_id: context.bootstrap.workspace.id,
          principal_id: context.agent_principal.id,
          action: :agent_runtime_execute,
          authority_basis: "agent-binding:#{context.binding.id}",
          causation_key: "work-run:#{context.run.id}",
          idempotency_scope: "agent-runtime:#{context.binding.id}:#{context.run.id}",
          idempotency_key: request.idempotency_key,
          subject_kind: "work_run",
          subject_id: context.run.id
        },
        overrides
      )

    with {:ok, system_request} <- Operations.new_system_operation_request(attrs) do
      Operations.start_system_operation(system_request)
    end
  end

  defp base_request(context) do
    %{
      binding_id: context.binding.id,
      graph_item_id: context.graph_item_id,
      run_id: context.run.id,
      origin: "operator",
      invocation_mode: "human",
      idempotency_key: "agent-invocation-#{context.suffix}",
      requested_outcome: "Review the selected work and propose bounded follow-up.",
      requested_capabilities: [
        "agent.model.generate",
        "agent.tool.read",
        "proposal.create",
        "repository.read"
      ],
      autonomy_mode: "human_supervised"
    }
  end
end
