defmodule OfficeGraph.AgentRuntime.Authority do
  @moduledoc false

  alias OfficeGraph.{Authorization, Identity, Runs}

  alias OfficeGraph.AgentRuntime.{
    AdapterRegistry,
    AgentDefinition,
    AgentExecution,
    ApprovalRequest,
    AuthoritySnapshot,
    ContextPackage,
    ContextExpansionRequest,
    OrganizationBinding
  }

  alias OfficeGraph.Integrations.IntegrationCredential

  require Ash.Query

  def compute(%OrganizationBinding{} = binding, %AgentDefinition{} = definition, request, attrs) do
    with :ok <- validate_definition_authority(definition, request),
         :ok <- authorize_agent(binding),
         {:ok, capability_keys} <-
           effective_capability_keys(binding, request, attrs[:delegator_principal_id]),
         {:ok, credentials} <- active_credentials(definition, binding),
         {:ok, model_manifest} <- AdapterRegistry.model_manifest(definition.model_adapter_key),
         {:ok, policy_bundle} <- Authorization.active_policy_bundle(binding.organization_id) do
      tool_keys = Enum.sort(definition.tool_allowlist)
      credential_ids = Enum.sort(Enum.map(credentials, & &1.id))

      authority = %{
        organization_id: binding.organization_id,
        workspace_id: binding.workspace_id,
        agent_principal_id: binding.agent_principal_id,
        delegator_principal_id: attrs[:delegator_principal_id],
        policy_bundle_id: policy_bundle.id,
        policy_bundle_version: policy_bundle.version,
        operation_id: attrs[:operation_id],
        version: 1,
        capability_keys: capability_keys,
        tool_keys: tool_keys,
        credential_ids: credential_ids,
        model_adapter_key: model_manifest.key,
        model_adapter_version: model_manifest.version,
        autonomy_mode: request.autonomy_mode,
        captured_at: DateTime.utc_now()
      }

      {:ok, Map.put(authority, :authority_hash, authority_hash(authority))}
    end
  end

  def revalidate(execution_id, opts \\ [])

  def revalidate(execution_id, opts) when is_binary(execution_id) and is_list(opts) do
    with {:ok, execution} <- load_execution(execution_id),
         {:ok, snapshot} <- load_snapshot(execution.id),
         {:ok, binding} <- load_binding(execution.organization_binding_id),
         {:ok, definition} <- load_definition(execution.definition_id),
         :ok <- validate_execution_binding(execution, binding, definition),
         :ok <- validate_agent_principal(execution.agent_principal_id),
         :ok <- validate_agent_grants(execution, snapshot),
         :ok <- validate_delegator_grant(execution, snapshot),
         :ok <- validate_snapshot_contract(snapshot, execution, definition),
         :ok <- validate_policy_bundle(snapshot, execution),
         :ok <- Runs.revalidate_agent_authority(execution, snapshot.autonomy_mode),
         :ok <- validate_snapshot_credentials(snapshot, execution),
         :ok <- validate_tool(opts[:tool_key], snapshot, definition),
         :ok <- validate_approval(opts[:approval_request_id], execution, snapshot),
         :ok <-
           validate_context_expansion_lineage(
             opts[:context_expansion_request_id],
             execution,
             snapshot
           ) do
      :ok
    end
  end

  def revalidate(_execution_id, _opts), do: {:error, :forbidden}

  defp validate_definition_authority(definition, request) do
    unsupported = request.requested_capabilities -- definition.requested_capabilities

    cond do
      definition.lifecycle_state != "active" ->
        {:error, :forbidden}

      request.invocation_mode not in definition.supported_modes ->
        {:error, :forbidden}

      request.autonomy_mode != definition.default_autonomy_mode ->
        {:error, :forbidden}

      unsupported != [] ->
        {:error, {:unsupported_agent_capabilities, Enum.sort(unsupported)}}

      true ->
        :ok
    end
  end

  defp authorize_agent(binding) do
    with :ok <-
           Authorization.authorize_system_principal(
             binding.agent_principal_id,
             binding.organization_id,
             binding.workspace_id,
             :agent_runtime_execute
           ),
         :ok <-
           Authorization.authorize_system_principal(
             binding.agent_principal_id,
             binding.organization_id,
             binding.workspace_id,
             :skeleton_read
           ) do
      :ok
    end
  end

  defp effective_capability_keys(binding, request, delegator_principal_id) do
    with {:ok, agent_granted} <-
           Authorization.intersect_principal_capabilities(
             binding.agent_principal_id,
             binding.organization_id,
             binding.workspace_id,
             request.requested_capabilities
           ),
         :ok <- require_requested_capabilities(request, agent_granted),
         {:ok, _delegated} <-
           delegated_capability_keys(binding, request, delegator_principal_id) do
      {:ok, Enum.sort(request.requested_capabilities)}
    end
  end

  defp delegated_capability_keys(_binding, request, nil),
    do: {:ok, Enum.sort(request.requested_capabilities)}

  defp delegated_capability_keys(binding, request, delegator_principal_id) do
    with {:ok, granted} <-
           Authorization.intersect_principal_capabilities(
             delegator_principal_id,
             binding.organization_id,
             binding.workspace_id,
             request.requested_capabilities
           ),
         :ok <- require_requested_capabilities(request, granted) do
      {:ok, granted}
    end
  end

  defp require_requested_capabilities(request, granted) do
    case request.requested_capabilities -- granted do
      [] -> :ok
      missing -> {:error, {:unauthorized_agent_capabilities, Enum.sort(missing)}}
    end
  end

  defp active_credentials(definition, binding) do
    [definition.model_credential_id]
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce_while({:ok, []}, fn credential_id, {:ok, credentials} ->
      case credential(credential_id, binding.organization_id, binding.workspace_id) do
        {:ok, credential} -> {:cont, {:ok, [credential | credentials]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, credentials} -> {:ok, Enum.reverse(credentials)}
      error -> error
    end
  end

  defp credential(id, organization_id, workspace_id) do
    IntegrationCredential
    |> Ash.Query.filter(
      id == ^id and organization_id == ^organization_id and
        (is_nil(workspace_id) or workspace_id == ^workspace_id)
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %{status: "active"} = credential} ->
        if is_nil(credential.expires_at) or
             DateTime.compare(credential.expires_at, DateTime.utc_now()) == :gt,
           do: {:ok, credential},
           else: {:error, :credential_inactive}

      {:ok, _missing_or_inactive} ->
        {:error, :credential_inactive}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp load_execution(id), do: get(AgentExecution, id, :execution_not_found)
  defp load_binding(id), do: get(OrganizationBinding, id, :binding_inactive)
  defp load_definition(id), do: get(AgentDefinition, id, :definition_inactive)

  defp load_snapshot(execution_id) do
    AuthoritySnapshot
    |> Ash.Query.filter(execution_id == ^execution_id and version == 1)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %AuthoritySnapshot{} = snapshot} -> {:ok, snapshot}
      {:ok, nil} -> {:error, :authority_snapshot_missing}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp get(resource, id, missing_reason) do
    case Ash.get(resource, id, authorize?: false, not_found_error?: false) do
      {:ok, nil} -> {:error, missing_reason}
      {:ok, record} -> {:ok, record}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp validate_execution_binding(execution, binding, definition) do
    if binding.lifecycle_state == "active" and definition.lifecycle_state == "active" and
         binding.definition_id == definition.id and
         binding.organization_id == execution.organization_id and
         binding.workspace_id == execution.workspace_id and
         binding.agent_principal_id == execution.agent_principal_id do
      :ok
    else
      {:error, :binding_inactive}
    end
  end

  defp validate_agent_principal(principal_id) do
    case Identity.active_system_principal(principal_id) do
      {:ok, true} -> :ok
      {:ok, false} -> {:error, :agent_principal_inactive}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_agent_grants(execution, snapshot) do
    with :ok <-
           Authorization.authorize_system_principal(
             execution.agent_principal_id,
             execution.organization_id,
             execution.workspace_id,
             :agent_runtime_execute
           ),
         :ok <-
           Authorization.authorize_system_principal(
             execution.agent_principal_id,
             execution.organization_id,
             execution.workspace_id,
             :skeleton_read
           ),
         {:ok, granted_capabilities} <-
           Authorization.intersect_principal_capabilities(
             execution.agent_principal_id,
             execution.organization_id,
             execution.workspace_id,
             snapshot.capability_keys
           ),
         true <- Enum.empty?(snapshot.capability_keys -- granted_capabilities) do
      :ok
    else
      {:error, :integration_storage_unavailable} = error -> error
      _error -> {:error, :agent_authority_revoked}
    end
  end

  defp validate_delegator_grant(%{delegator_principal_id: nil}, _snapshot), do: :ok

  defp validate_delegator_grant(execution, snapshot) do
    with :ok <-
           Authorization.authorize_principal(
             execution.delegator_principal_id,
             execution.organization_id,
             execution.workspace_id,
             :agent_invoke
           ),
         {:ok, granted_capabilities} <-
           Authorization.intersect_principal_capabilities(
             execution.delegator_principal_id,
             execution.organization_id,
             execution.workspace_id,
             snapshot.capability_keys
           ),
         true <- Enum.empty?(snapshot.capability_keys -- granted_capabilities) do
      :ok
    else
      {:error, :integration_storage_unavailable} = error -> error
      _revoked_or_inactive -> {:error, :delegator_authority_revoked}
    end
  end

  defp validate_snapshot_contract(snapshot, execution, definition) do
    valid? =
      snapshot.execution_id == execution.id and
        snapshot.organization_id == execution.organization_id and
        snapshot.workspace_id == execution.workspace_id and
        snapshot.agent_principal_id == execution.agent_principal_id and
        snapshot.operation_id == execution.operation_id and
        snapshot.autonomy_mode == execution.autonomy_mode and
        Enum.empty?(snapshot.capability_keys -- definition.requested_capabilities) and
        Enum.empty?(snapshot.tool_keys -- definition.tool_allowlist) and
        snapshot.authority_hash == authority_hash(Map.from_struct(snapshot))

    if valid?, do: :ok, else: {:error, :authority_snapshot_invalid}
  end

  defp validate_snapshot_credentials(snapshot, execution) do
    Enum.reduce_while(snapshot.credential_ids, :ok, fn credential_id, :ok ->
      case credential(credential_id, execution.organization_id, execution.workspace_id) do
        {:ok, _credential} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_policy_bundle(snapshot, execution) do
    case Authorization.active_policy_bundle(execution.organization_id) do
      {:ok, %{id: id, version: version}}
      when id == snapshot.policy_bundle_id and version == snapshot.policy_bundle_version ->
        :ok

      {:error, :integration_storage_unavailable} = error ->
        error

      _changed_or_missing ->
        {:error, :authority_policy_changed}
    end
  end

  defp validate_tool(nil, _snapshot, _definition), do: :ok

  defp validate_tool(tool_key, snapshot, definition) when is_binary(tool_key) do
    if tool_key in snapshot.tool_keys and tool_key in definition.tool_allowlist,
      do: :ok,
      else: {:error, :tool_not_authorized}
  end

  defp validate_tool(_tool_key, _snapshot, _definition), do: {:error, :tool_not_authorized}

  defp validate_approval(nil, _execution, _snapshot), do: :ok

  defp validate_approval(approval_id, execution, snapshot) when is_binary(approval_id) do
    case Ash.get(ApprovalRequest, approval_id,
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok,
       %ApprovalRequest{
         execution_id: execution_id,
         authority_snapshot_id: snapshot_id,
         organization_id: organization_id,
         workspace_id: workspace_id,
         scope_type: "workspace",
         scope_id: scope_id,
         step_key: step_key,
         execution_state_version: execution_state_version,
         capability_key: capability_key,
         resolution_operation_id: resolution_operation_id,
         state: "approved"
       } = approval}
      when execution_id == execution.id and snapshot_id == snapshot.id and
             organization_id == execution.organization_id and
             workspace_id == execution.workspace_id and scope_id == execution.workspace_id and
             step_key == execution.current_step_key ->
        if active_gate_execution?(execution, execution_state_version) and
             is_binary(resolution_operation_id) and
             capability_key in snapshot.capability_keys and
             DateTime.compare(approval.expires_at, DateTime.utc_now()) == :gt,
           do: :ok,
           else: {:error, :approval_not_active}

      {:ok, _missing_or_inactive} ->
        {:error, :approval_not_active}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp validate_approval(_approval_id, _execution, _snapshot),
    do: {:error, :approval_not_active}

  defp validate_context_expansion_lineage(expansion_id, execution, snapshot) do
    with {:ok, lineage_ids} <- context_expansion_lineage(execution.id),
         :ok <- validate_requested_expansion(expansion_id, lineage_ids) do
      Enum.reduce_while(lineage_ids, :ok, fn lineage_id, :ok ->
        case validate_context_expansion(lineage_id, execution, snapshot) do
          :ok -> {:cont, :ok}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end
  end

  defp validate_requested_expansion(nil, _lineage_ids), do: :ok

  defp validate_requested_expansion(expansion_id, lineage_ids) when is_binary(expansion_id) do
    if expansion_id in lineage_ids,
      do: :ok,
      else: {:error, :context_expansion_not_active}
  end

  defp validate_requested_expansion(_expansion_id, _lineage_ids),
    do: {:error, :context_expansion_not_active}

  defp validate_context_expansion(id, execution, snapshot) when is_binary(id) do
    case Ash.get(ContextExpansionRequest, id,
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok,
       %ContextExpansionRequest{
         execution_id: execution_id,
         authority_snapshot_id: snapshot_id,
         organization_id: organization_id,
         workspace_id: workspace_id,
         target_scope_type: "workspace",
         target_scope_id: scope_id,
         step_key: step_key,
         execution_state_version: execution_state_version,
         capability_key: capability_key,
         resolution_operation_id: resolution_operation_id,
         state: "approved"
       } = expansion}
      when execution_id == execution.id and snapshot_id == snapshot.id and
             organization_id == execution.organization_id and
             workspace_id == execution.workspace_id and scope_id == execution.workspace_id and
             step_key == execution.current_step_key ->
        if active_gate_execution?(execution, execution_state_version) and
             is_binary(resolution_operation_id) and capability_key in snapshot.capability_keys and
             DateTime.compare(expansion.expires_at, DateTime.utc_now()) == :gt,
           do: :ok,
           else: {:error, :context_expansion_not_active}

      {:ok, _missing_or_inactive} ->
        {:error, :context_expansion_not_active}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp validate_context_expansion(_expansion_id, _execution, _snapshot),
    do: {:error, :context_expansion_not_active}

  defp active_gate_execution?(execution, waiting_version) do
    execution.state in ["queued", "running", "retry_scheduled"] and
      execution.state_version > waiting_version
  end

  defp context_expansion_lineage(execution_id) do
    ContextPackage
    |> Ash.Query.filter(execution_id == ^execution_id)
    |> Ash.Query.sort(version: :desc)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, []} ->
        {:error, :context_expansion_not_active}

      {:ok, packages} ->
        validate_package_lineage(packages)

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp validate_package_lineage(packages) do
    valid? =
      packages
      |> Enum.chunk_every(2, 1, [nil])
      |> Enum.all?(fn
        [package, nil] ->
          is_nil(package.previous_package_id) and package.version == 1

        [package, previous] ->
          package.previous_package_id == previous.id and package.version == previous.version + 1
      end)

    if valid? do
      {:ok, packages |> Enum.map(& &1.expansion_request_id) |> Enum.reject(&is_nil/1)}
    else
      {:error, :context_expansion_not_active}
    end
  end

  def authority_hash(authority) when is_map(authority) do
    authority
    |> Map.take([
      :organization_id,
      :workspace_id,
      :agent_principal_id,
      :delegator_principal_id,
      :policy_bundle_id,
      :policy_bundle_version,
      :operation_id,
      :version,
      :capability_keys,
      :tool_keys,
      :credential_ids,
      :model_adapter_key,
      :model_adapter_version,
      :autonomy_mode,
      :captured_at
    ])
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
