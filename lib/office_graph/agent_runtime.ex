defmodule OfficeGraph.AgentRuntime do
  @moduledoc """
  Public boundary for governed, run-linked agent runtime orchestration.
  """

  use Boundary,
    deps: [
      OfficeGraph.Audit,
      OfficeGraph.Authorization,
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

  alias OfficeGraph.{Authorization, Identity, Operations, Repo}

  alias OfficeGraph.AgentRuntime.{
    AgentDefinition,
    ApprovalCommands,
    Authority,
    CancellationCommands,
    ContextExpansionCommands,
    InvocationCommands,
    InvocationRequest,
    OrganizationBinding,
    StorageResult
  }

  alias OfficeGraph.Identity.Principal

  @canonical_definition_key "openspec-review"
  @agent_capabilities [:agent_runtime_execute, :skeleton_read]

  def invoke(session_context, operation, %InvocationRequest{} = request) do
    InvocationCommands.invoke(session_context, operation, request)
  end

  def invoke(_session_context, _operation, _request), do: {:error, :forbidden}

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
  Binds the migration-owned OpenSpec review definition in the caller's workspace.

  The command is authorized and idempotent, and it provisions only the scoped
  backend agent authority required by the canonical definition.
  """
  def bind_openspec_review_agent(session_context, attrs)
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

  def bind_openspec_review_agent(_session_context, _attrs), do: {:error, :forbidden}

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
      Repo.transaction(fn ->
        with {:ok, _locked_operation} <- Operations.lock_operation(operation.id) do
          lock_binding_scope!(session_context.organization_id, session_context.workspace_id)

          definition = canonical_definition!()

          case binding_for_scope(
                 definition.id,
                 session_context.organization_id,
                 session_context.workspace_id
               ) do
            nil -> create_binding!(session_context, operation, definition)
            binding -> replay_binding!(session_context, operation, definition, binding)
          end
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp canonical_definition! do
    definition =
      AgentDefinition
      |> Ash.Query.filter(key == ^@canonical_definition_key)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one!(authorize?: false)

    if definition && definition.lifecycle_state == "active" do
      definition
    else
      Repo.rollback(:forbidden)
    end
  end

  defp create_binding!(session_context, operation, definition) do
    principal = ensure_agent_principal!(session_context.organization_id)
    ensure_agent_role!(principal, session_context)

    binding =
      Repo.ash_create!(OrganizationBinding, %{
        id: Ecto.UUID.generate(),
        definition_id: definition.id,
        organization_id: session_context.organization_id,
        workspace_id: session_context.workspace_id,
        agent_principal_id: principal.id,
        bound_by_principal_id: session_context.principal_id,
        lifecycle_state: "active",
        operation_id: operation.id
      })

    binding_result(operation, definition, binding, principal)
  end

  defp replay_binding!(session_context, operation, definition, binding) do
    if binding.operation_id == operation.id and
         binding.organization_id == session_context.organization_id and
         binding.workspace_id == session_context.workspace_id and
         binding.lifecycle_state == "active" do
      principal = Ash.get!(Principal, binding.agent_principal_id, authorize?: false)

      if principal.kind == "agent" and principal.status == "active" do
        ensure_agent_role!(principal, session_context)
        binding_result(operation, definition, binding, principal)
      else
        Repo.rollback(:forbidden)
      end
    else
      Repo.rollback(:forbidden)
    end
  end

  defp binding_for_scope(definition_id, organization_id, workspace_id) do
    OrganizationBinding
    |> Ash.Query.filter(
      definition_id == ^definition_id and organization_id == ^organization_id and
        workspace_id == ^workspace_id
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp ensure_agent_principal!(organization_id) do
    email = "openspec-review+#{organization_id}@agents.office-graph.local"

    case Identity.ensure_system_principal(email, "agent") do
      {:ok, principal} -> principal
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp ensure_agent_role!(principal, session_context) do
    scope = %{
      organization_id: session_context.organization_id,
      workspace_id: session_context.workspace_id
    }

    case Authorization.ensure_system_role(principal, scope, @agent_capabilities) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp binding_result(operation, definition, binding, principal) do
    %{
      operation: operation,
      definition: definition,
      binding: binding,
      principal: principal
    }
  end

  defp lock_binding_scope!(organization_id, workspace_id) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      "agent-runtime:openspec-review:#{organization_id}:#{workspace_id}"
    ])
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
