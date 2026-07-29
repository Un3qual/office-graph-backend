defmodule OfficeGraph.AgentRuntime do
  @moduledoc """
  Public boundary for governed, run-linked agent runtime orchestration.
  """

  use Boundary,
    deps: [
      OfficeGraph.Audit,
      OfficeGraph.Authorization,
      OfficeGraph.CommandSupport,
      OfficeGraph.DurableDelivery,
      OfficeGraph.ExternalRefs,
      OfficeGraph.Identity,
      OfficeGraph.Integrations,
      OfficeGraph.NodeConversations,
      OfficeGraph.Operations,
      OfficeGraph.Projections,
      OfficeGraph.ProposedChanges,
      OfficeGraph.Repo,
      OfficeGraph.Revisions,
      OfficeGraph.Runs,
      OfficeGraph.Tenancy,
      OfficeGraph.Verification,
      OfficeGraph.WorkGraph
    ],
    exports: [InvocationRequest]

  require Ash.Query

  alias OfficeGraph.{Authorization, CommandSupport, Identity, Operations}

  alias OfficeGraph.AgentRuntime.{
    ActionSupport,
    AgentDefinition,
    ApprovalCommands,
    Authority,
    BindingResult,
    CancellationCommands,
    ContextExpansionCommands,
    InvocationCommands,
    InvocationRequest,
    OrganizationBinding,
    StorageResult
  }

  alias OfficeGraph.Identity.Principal

  @behaviour Ash.Resource.Actions.Implementation

  @canonical_definition_key "run-review"
  @agent_capabilities [
    :agent_runtime_execute,
    :skeleton_read,
    :agent_model_generate,
    :agent_proposal_create,
    :agent_evidence_suggest
  ]

  @impl true
  def run(input, [mode: :bind_run_review], %{actor: session_context})
      when is_map(session_context) do
    case persist_binding_records(session_context, input.arguments.operation_id) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> ActionSupport.rollback(OrganizationBinding, error)
    end
  end

  def run(_input, _opts, _context), do: {:error, :forbidden}

  def invoke(session_context, operation, %InvocationRequest{} = request) do
    InvocationCommands.invoke(session_context, operation, request)
  end

  def invoke(_session_context, _operation, _request), do: {:error, :forbidden}

  def invoke_human(session_context, attrs)
      when is_map(session_context) and is_map(attrs) and not is_struct(attrs) do
    with {:ok, request} <-
           attrs
           |> Map.put(:origin, "operator")
           |> Map.put(:invocation_mode, "human")
           |> InvocationRequest.new(),
         {:ok, operation} <-
           Operations.start_command(
             session_context,
             :agent_invoke,
             request.idempotency_key,
             InvocationRequest.command_input(request)
           ) do
      InvocationCommands.invoke(session_context, operation, request)
    end
  end

  def invoke_human(_session_context, _attrs), do: {:error, :forbidden}

  def invoke_system(operation, %InvocationRequest{} = request) do
    InvocationCommands.invoke_system(operation, request)
  end

  def invoke_system(_operation, _request), do: {:error, :forbidden}

  def revalidate_step(execution_id, opts \\ []) do
    Authority.revalidate(execution_id, opts)
  end

  def cancel_execution(session_context, operation, attrs) do
    CancellationCommands.cancel(session_context, operation, attrs)
  end

  def approve(session_context, operation, request_id, expected_version, reason) do
    ApprovalCommands.resolve(
      session_context,
      operation,
      request_id,
      expected_version,
      "approved",
      reason
    )
  end

  def deny_approval(session_context, operation, request_id, expected_version, reason) do
    ApprovalCommands.resolve(
      session_context,
      operation,
      request_id,
      expected_version,
      "denied",
      reason
    )
  end

  def cancel_approval(session_context, operation, request_id, expected_version, reason) do
    ApprovalCommands.resolve(
      session_context,
      operation,
      request_id,
      expected_version,
      "cancelled",
      reason
    )
  end

  def approve_context_expansion(
        session_context,
        operation,
        request_id,
        expected_version,
        reason
      ) do
    ContextExpansionCommands.resolve(
      session_context,
      operation,
      request_id,
      expected_version,
      "approved",
      reason
    )
  end

  def deny_context_expansion(
        session_context,
        operation,
        request_id,
        expected_version,
        reason
      ) do
    ContextExpansionCommands.resolve(
      session_context,
      operation,
      request_id,
      expected_version,
      "denied",
      reason
    )
  end

  def cancel_context_expansion(
        session_context,
        operation,
        request_id,
        expected_version,
        reason
      ) do
    ContextExpansionCommands.resolve(
      session_context,
      operation,
      request_id,
      expected_version,
      "cancelled",
      reason
    )
  end

  @doc """
  Binds the migration-owned run review definition in the caller's workspace.

  The command is authorized and idempotent, and it provisions only the scoped
  backend agent authority required by the canonical definition.
  """
  def bind_run_review_agent(session_context, attrs)
      when is_map(session_context) and is_map(attrs) do
    with {:ok, idempotency_key, command_input} <- normalize_binding_input(session_context, attrs),
         {:ok, operation} <-
           Operations.start_command(
             session_context,
             :agent_definition_bind,
             idempotency_key,
             command_input
           ),
         :ok <- authorize_binding(session_context, operation) do
      persist_binding(session_context, operation)
    end
  end

  def bind_run_review_agent(_session_context, _attrs), do: {:error, :forbidden}

  defp normalize_binding_input(session_context, attrs) do
    with :ok <- reject_unknown_binding_fields(attrs),
         {:ok, idempotency_key} <- required_string(attrs, :idempotency_key),
         true <- is_binary(Map.get(session_context, :organization_id)),
         true <- is_binary(Map.get(session_context, :workspace_id)) do
      {:ok, idempotency_key,
       %{
         definition_key: @canonical_definition_key,
         organization_id: session_context.organization_id,
         workspace_id: session_context.workspace_id
       }}
    else
      false -> {:error, :forbidden}
      {:error, _reason} = error -> error
    end
  end

  defp reject_unknown_binding_fields(attrs) do
    case Enum.find(Map.keys(attrs), &(&1 not in [:idempotency_key, "idempotency_key"])) do
      nil -> :ok
      field -> {:error, {:invalid_field, field}}
    end
  end

  defp authorize_binding(session_context, operation) do
    Authorization.authorize_operation(
      session_context,
      operation,
      :agent_definition_bind,
      organization_id: session_context.organization_id,
      workspace_id: session_context.workspace_id
    )
  end

  defp persist_binding(session_context, operation) do
    StorageResult.run(fn ->
      OrganizationBinding
      |> Ash.ActionInput.for_action(:persist_run_review_binding_contract, %{
        operation_id: operation.id
      })
      |> Ash.run_action(actor: session_context, authorize?: false)
      |> ActionSupport.normalize_action_result()
    end)
  end

  defp persist_binding_records(session_context, operation_id) do
    with {:ok, operation} <- Operations.lock_operation(operation_id),
         {:ok, definition} <- canonical_definition(),
         {:ok, binding} <-
           binding_for_scope(
             definition.id,
             session_context.organization_id,
             session_context.workspace_id
           ) do
      case binding do
        nil -> create_binding(session_context, operation, definition)
        binding -> replay_binding(session_context, operation, definition, binding)
      end
    end
  end

  defp canonical_definition do
    AgentDefinition
    |> Ash.Query.filter(key == ^@canonical_definition_key)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %AgentDefinition{lifecycle_state: "active"} = definition} ->
        {:ok, definition}

      {:ok, _missing_or_inactive} ->
        {:error, :forbidden}

      {:error, error} ->
        {:error, error}
    end
  end

  defp create_binding(session_context, operation, definition) do
    with {:ok, principal} <- ensure_agent_principal(session_context.organization_id),
         :ok <- ensure_agent_role(principal, session_context),
         {:ok, binding} <-
           OrganizationBinding
           |> Ash.Changeset.for_create(:create, %{
             definition_id: definition.id,
             organization_id: session_context.organization_id,
             workspace_id: session_context.workspace_id,
             agent_principal_id: principal.id,
             bound_by_principal_id: session_context.principal_id,
             lifecycle_state: "active",
             operation_id: operation.id
           })
           |> Ash.create(
             authorize?: false,
             return_notifications?: true,
             upsert?: true,
             upsert_identity: :unique_definition_organization_workspace,
             upsert_fields: []
           )
           |> CommandSupport.normalize_ash_write(),
         :ok <- validate_binding_replay(session_context, binding, principal) do
      {:ok, binding_result(operation, definition, binding, principal)}
    end
  end

  defp replay_binding(session_context, operation, definition, binding) do
    with {:ok, principal} when is_struct(principal) <-
           Ash.get(Principal, binding.agent_principal_id, authorize?: false),
         :ok <- validate_binding_replay(session_context, binding, principal),
         :ok <- ensure_agent_role(principal, session_context) do
      {:ok, binding_result(operation, definition, binding, principal)}
    else
      {:ok, _missing_principal} -> {:error, :forbidden}
      {:error, error} -> {:error, error}
    end
  end

  defp validate_binding_replay(session_context, binding, principal) do
    if binding.organization_id == session_context.organization_id and
         binding.workspace_id == session_context.workspace_id and
         binding.lifecycle_state == "active" and principal.kind == "agent" and
         principal.status == "active" and binding.agent_principal_id == principal.id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp binding_for_scope(definition_id, organization_id, workspace_id) do
    OrganizationBinding
    |> Ash.Query.filter(
      definition_id == ^definition_id and organization_id == ^organization_id and
        workspace_id == ^workspace_id
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp ensure_agent_principal(organization_id) do
    email = "run-review+#{organization_id}@agents.office-graph.local"
    Identity.ensure_system_principal(email, "agent")
  end

  defp ensure_agent_role(principal, session_context) do
    scope = %{
      organization_id: session_context.organization_id,
      workspace_id: session_context.workspace_id
    }

    Authorization.ensure_system_role(principal, scope, @agent_capabilities)
  end

  defp binding_result(operation, definition, binding, principal) do
    BindingResult.build!(operation, definition, binding, principal)
  end

  defp required_string(attrs, key) do
    case Map.get(attrs, key, Map.get(attrs, to_string(key))) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, {:missing_field, key}}
          normalized -> {:ok, normalized}
        end

      nil ->
        {:error, {:missing_field, key}}

      _other ->
        {:error, {:invalid_field, key}}
    end
  end
end
