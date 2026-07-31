defmodule OfficeGraph.TestSupport.AgentRuntimeSupport do
  @moduledoc false

  alias OfficeGraph.{AgentRuntime, Foundation, Operations}

  alias OfficeGraph.AgentRuntime.{
    ContextEntry,
    ContextPackage,
    ExecutionWorker,
    GateExpiryWorker,
    InvocationRequest
  }

  alias OfficeGraph.Authorization.{Capability, RoleAssignment, RoleCapability}
  alias OfficeGraph.TestSupport.OperatorProjectionSupport

  require Ash.Query

  def invocation_fixture(opts \\ []) do
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

    verification_checks =
      for _index <- 1..Keyword.get(opts, :verification_check_count, 1) do
        {:ok, verification_check} =
          OperatorProjectionSupport.create_required_verification_check(bootstrap.session)

        verification_check
      end

    verification_check =
      Enum.at(
        verification_checks,
        Keyword.get(opts, :selected_verification_check_index, 0)
      )

    {:ok, run_result} =
      OperatorProjectionSupport.create_ready_run(bootstrap.session, verification_checks)

    {:ok, bound} =
      AgentRuntime.bind_run_review_agent(bootstrap.session, %{
        idempotency_key: "bind-run-review-#{suffix}"
      })

    %{
      bootstrap: bootstrap,
      session: bootstrap.session,
      verification_check: verification_check,
      verification_checks: verification_checks,
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

  def execution_jobs(execution_id) do
    Oban.Testing.all_enqueued(
      repo: OfficeGraph.Repo,
      worker: ExecutionWorker,
      args: %{execution_id: execution_id}
    )
  end

  def approval_resume_jobs(request_id) do
    Oban.Testing.all_enqueued(
      repo: OfficeGraph.Repo,
      worker: ExecutionWorker,
      args: %{approval_request_id: request_id}
    )
  end

  def gate_expiry_jobs(request_kind, request_id) do
    Oban.Testing.all_enqueued(
      repo: OfficeGraph.Repo,
      worker: GateExpiryWorker,
      args: %{request_kind: request_kind, request_id: request_id}
    )
  end

  def configure_definition!(definition, attrs) do
    definition
    |> Ash.Changeset.for_update(:configure_authority, attrs)
    |> Ash.update!(authorize?: false)
  end

  def require_context_expansion!(invocation, count \\ 1)
      when is_integer(count) and count > 0 do
    target_ordinals =
      invocation.context_entries
      |> Enum.sort_by(& &1.ordinal)
      |> Enum.take(count)
      |> MapSet.new(& &1.ordinal)

    entry_attrs =
      Enum.map(invocation.context_entries, fn entry ->
        expansion_required? = MapSet.member?(target_ordinals, entry.ordinal)

        %{
          organization_id: entry.organization_id,
          workspace_id: entry.workspace_id,
          entry_type: entry.entry_type,
          resource_type: entry.resource_type,
          resource_id: entry.resource_id,
          external_reference_id: entry.external_reference_id,
          posture: if(expansion_required?, do: "expansion_required", else: entry.posture),
          rationale_code:
            if(
              expansion_required?,
              do: "fixture_context_expansion_required",
              else: entry.rationale_code
            ),
          source_version: entry.source_version,
          ordinal: entry.ordinal,
          operation_id: entry.operation_id
        }
        |> then(&Map.put(&1, :content_hash, fixture_digest(&1)))
      end)

    package =
      Ash.create!(
        ContextPackage,
        %{
          execution_id: invocation.execution.id,
          authority_snapshot_id: invocation.authority_snapshot.id,
          organization_id: invocation.execution.organization_id,
          workspace_id: invocation.execution.workspace_id,
          selected_graph_item_id: invocation.execution.graph_item_id,
          run_id: invocation.execution.run_id,
          previous_package_id: invocation.context_package.id,
          operation_id: invocation.operation.id,
          version: invocation.context_package.version + 1,
          package_hash: fixture_digest(entry_attrs),
          assembled_at: DateTime.utc_now()
        },
        action: :create,
        authorize?: false
      )

    entries =
      Enum.map(entry_attrs, fn attrs ->
        Ash.create!(
          ContextEntry,
          Map.put(attrs, :context_package_id, package.id),
          action: :create,
          authorize?: false
        )
      end)

    %{
      context_package: package,
      context_entries: entries,
      targets: Enum.filter(entries, &(&1.posture == "expansion_required"))
    }
  end

  def grant_capabilities!(context, capability_keys, principal_ids \\ nil) do
    principal_ids = principal_ids || [context.agent_principal.id]

    assignments =
      RoleAssignment
      |> Ash.Query.filter(
        principal_id in ^principal_ids and
          organization_id == ^context.bootstrap.organization.id and
          workspace_id == ^context.bootstrap.workspace.id
      )
      |> Ash.read!(authorize?: false)

    capabilities =
      Capability
      |> Ash.Query.filter(key in ^capability_keys)
      |> Ash.read!(authorize?: false)

    if Enum.sort(Enum.map(capabilities, & &1.key)) != Enum.sort(capability_keys) do
      raise ArgumentError, "unknown AgentRuntime fixture capability"
    end

    Enum.each(assignments, fn assignment ->
      Enum.each(capabilities, fn capability ->
        Ash.create!(
          RoleCapability,
          %{role_id: assignment.role_id, capability_id: capability.id},
          action: :ensure,
          authorize?: false
        )
      end)
    end)
  end

  def revoke_capabilities!(context, capability_keys) do
    role_ids =
      RoleAssignment
      |> Ash.Query.filter(
        principal_id == ^context.agent_principal.id and
          organization_id == ^context.bootstrap.organization.id and
          workspace_id == ^context.bootstrap.workspace.id
      )
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.role_id)

    capability_ids =
      Capability
      |> Ash.Query.filter(key in ^capability_keys)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.id)

    RoleCapability
    |> Ash.Query.filter(role_id in ^role_ids and capability_id in ^capability_ids)
    |> Ash.read!(authorize?: false)
    |> Enum.each(&Ash.destroy!(&1, action: :revoke, authorize?: false))
  end

  defp base_request(context) do
    %{
      binding_id: context.binding.id,
      graph_item_id: context.graph_item_id,
      run_id: context.run.id,
      origin: "operator",
      invocation_mode: "human",
      idempotency_key: "agent-invocation-#{context.suffix}",
      requested_outcome:
        "Review the selected run, work packet, graph context, checks, and evidence, then propose bounded follow-up work.",
      requested_capabilities:
        context.definition.requested_capabilities
        |> Kernel.--(["agent.invoke"]),
      autonomy_mode: "human_supervised"
    }
  end

  defp fixture_digest(value) do
    value
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
