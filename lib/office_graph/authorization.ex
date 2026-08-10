defmodule OfficeGraph.Authorization do
  @moduledoc """
  Public boundary for authorization decisions and capability checks.
  """

  use Boundary,
    deps: [OfficeGraph.CommandSupport, OfficeGraph.Identity],
    exports: [Domain, ExternalRoleFacts]

  alias OfficeGraph.Authorization.{
    Capability,
    DecisionStore,
    Domain,
    Persistence,
    PolicyBundle,
    ReferenceCatalog,
    Role,
    RoleAssignment,
    RoleCapability
  }

  alias OfficeGraph.{CommandSupport, Identity}

  require Ash.Query

  @identity_constraints ~w[
    capabilities_key_index
    roles_organization_id_key_index
    role_capabilities_role_id_capability_id_index
    role_assignments_org_wide_unique_index
    role_assignments_workspace_unique_index
    policy_bundles_organization_id_version_index
  ]

  @owner_capabilities ReferenceCatalog.owner_capabilities()
  @recognized_capabilities ReferenceCatalog.recognized_capabilities()
  @system_capabilities ReferenceCatalog.system_capabilities()

  def recognized_capability_keys do
    @recognized_capabilities
    |> Map.values()
    |> Enum.sort()
  end

  def ensure_owner_role(principal, tenant) do
    input = %{
      principal_id: principal.id,
      organization_id: tenant.organization.id,
      workspace_id: tenant.workspace.id,
      recognized_capability_keys: recognized_capability_keys(),
      owner_capability_keys: @owner_capabilities |> Map.values() |> Enum.sort()
    }

    case run_role_action_with_identity_retry(:ensure_owner_role, input) do
      {:ok, role_setup} -> {:ok, role_setup}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  def ensure_local_development_role(principal, tenant, fixture)
      when is_map(fixture) do
    with role_profile when role_profile in [:workspace_admin, :member] <-
           fixture[:role_profile],
         {:ok, capability_keys} <- ReferenceCatalog.capability_keys(fixture[:actions]) do
      input = %{
        principal_id: principal.id,
        organization_id: tenant.organization.id,
        workspace_id: tenant.workspace.id,
        role_key: Atom.to_string(role_profile),
        role_name: local_development_role_name(role_profile),
        capability_keys: capability_keys
      }

      case run_role_action_with_identity_retry(:ensure_local_development_role, input) do
        {:ok, role_setup} -> {:ok, role_setup}
        {:error, _storage_error} -> {:error, :integration_storage_unavailable}
      end
    else
      _unknown_profile -> {:error, :forbidden}
    end
  end

  def ensure_local_development_role(_principal, _tenant, _fixture),
    do: {:error, :forbidden}

  def reconcile_local_development_role_assignments(principal, expected_assignment)
      when is_binary(principal.id) and is_binary(expected_assignment.id) do
    RoleAssignment
    |> Ash.ActionInput.for_action(:reconcile_local_development_assignments, %{
      principal_id: principal.id,
      expected_assignment_id: expected_assignment.id
    })
    |> Ash.run_action(authorize?: false)
    |> case do
      {:ok, :ok} -> :ok
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  def reconcile_local_development_role_assignments(_principal, _expected_assignment),
    do: {:error, :forbidden}

  def resolve_local_development_login_scope(principal_id, fixture)
      when is_binary(principal_id) and is_map(fixture) do
    with {:ok, role_key, expected_capability_keys} <-
           local_development_role_facts(fixture),
         :ok <- Persistence.before_read(:login_scope),
         {:ok, assignments, roles, role_capabilities} <-
           local_development_assignment_facts(principal_id),
         {:ok, scope} <-
           exact_local_development_scope(
             assignments,
             roles,
             role_capabilities,
             role_key,
             expected_capability_keys
           ),
         :ok <- reject_external_local_development_roles(principal_id) do
      {:ok, scope}
    else
      {:error, :authorization_storage_unavailable} = error -> error
      _missing_or_drifted -> {:error, :local_development_fixture_missing}
    end
  end

  def resolve_local_development_login_scope(_principal_id, _fixture),
    do: {:error, :local_development_fixture_missing}

  def authorize(session_context, action, opts \\ [])

  def authorize(%{organization_id: organization_id} = session_context, action, opts) do
    {result, _decision_attrs} =
      evaluate_authorization(session_context, organization_id, action, opts)

    result
  end

  def authorize(_session_context, _action, _opts), do: {:error, :forbidden}

  def authorize_system_principal(principal_id, organization_id, workspace_id, action)
      when is_binary(principal_id) and is_binary(organization_id) do
    with :ok <- Persistence.before_read(:system_principal),
         {:ok, required} <- Map.fetch(@recognized_capabilities, action),
         {:ok, true} <- Identity.active_system_principal(principal_id),
         {:ok, true} <-
           granted_capability_for_principal(
             principal_id,
             organization_id,
             workspace_id,
             required
           ) do
      :ok
    else
      {:error, :integration_storage_unavailable} = error -> error
      _other -> {:error, :forbidden}
    end
  end

  def authorize_system_principal(_principal_id, _organization_id, _workspace_id, _action),
    do: {:error, :forbidden}

  def authorize_principal(principal_id, organization_id, workspace_id, action)
      when is_binary(principal_id) and is_binary(organization_id) do
    with {:ok, required} <- Map.fetch(@recognized_capabilities, action),
         {:ok, true} <- Identity.active_principal(principal_id),
         {:ok, true} <-
           granted_capability_for_principal(
             principal_id,
             organization_id,
             workspace_id,
             required
           ) do
      :ok
    else
      {:error, :integration_storage_unavailable} = error -> error
      _other -> {:error, :forbidden}
    end
  end

  def authorize_principal(_principal_id, _organization_id, _workspace_id, _action),
    do: {:error, :forbidden}

  def resolve_login_scope(principal_id, preferred_scope \\ nil)

  def resolve_login_scope(principal_id, preferred_scope) when is_binary(principal_id) do
    with :ok <- Persistence.before_read(:login_scope) do
      case RoleAssignment
           |> Ash.Query.filter(principal_id == ^principal_id and not is_nil(workspace_id))
           |> Ash.read(authorize?: false) do
        {:ok, assignments} ->
          with {:ok, external_scopes} <-
                 external_role_facts().login_scopes(principal_id) do
            assignments
            |> Enum.map(&%{organization_id: &1.organization_id, workspace_id: &1.workspace_id})
            |> Kernel.++(external_scopes)
            |> Enum.uniq()
            |> select_login_scope(preferred_scope)
          else
            {:error, _storage_error} ->
              {:error, :authorization_storage_unavailable}
          end

        {:error, _storage_error} ->
          {:error, :authorization_storage_unavailable}
      end
    else
      {:error, _storage_error} -> {:error, :authorization_storage_unavailable}
    end
  end

  def resolve_login_scope(_principal_id, _preferred_scope), do: {:error, :no_login_scope}

  def intersect_principal_capabilities(
        principal_id,
        organization_id,
        workspace_id,
        requested_capabilities
      )
      when is_binary(principal_id) and is_binary(organization_id) and
             (is_nil(workspace_id) or is_binary(workspace_id)) and
             is_list(requested_capabilities) do
    requested_capabilities
    |> Enum.reduce_while({:ok, []}, fn capability_key, {:ok, granted} ->
      case granted_capability_for_principal(
             principal_id,
             organization_id,
             workspace_id,
             capability_key
           ) do
        {:ok, true} -> {:cont, {:ok, [capability_key | granted]}}
        {:ok, false} -> {:cont, {:ok, granted}}
        {:error, :integration_storage_unavailable} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, granted} -> {:ok, granted |> Enum.uniq() |> Enum.sort()}
      {:error, _reason} = error -> error
    end
  end

  def intersect_principal_capabilities(
        _principal_id,
        _organization_id,
        _workspace_id,
        _requested_capabilities
      ),
      do: {:error, :forbidden}

  def active_policy_bundle(organization_id) when is_binary(organization_id) do
    PolicyBundle
    |> Ash.Query.filter(organization_id == ^organization_id and status == "active")
    |> Ash.Query.sort(version: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, [%PolicyBundle{} = bundle]} -> {:ok, bundle}
      {:ok, []} -> {:error, :forbidden}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  def active_policy_bundle(_organization_id), do: {:error, :forbidden}

  def ensure_system_role(
        %{id: principal_id},
        %{organization_id: organization_id, workspace_id: workspace_id},
        actions
      )
      when is_binary(principal_id) and is_binary(organization_id) and
             (is_nil(workspace_id) or is_binary(workspace_id)) and is_list(actions) do
    with {:ok, true} <- Identity.active_system_principal(principal_id),
         {:ok, capability_keys} <- system_capability_keys(actions) do
      persist_system_role(principal_id, organization_id, workspace_id, capability_keys)
    else
      {:error, :integration_storage_unavailable} = error -> error
      _error -> {:error, :forbidden}
    end
  end

  def ensure_system_role(_principal, _scope, _actions), do: {:error, :forbidden}

  defp persist_system_role(principal_id, organization_id, workspace_id, capability_keys) do
    input = %{
      principal_id: principal_id,
      organization_id: organization_id,
      workspace_id: workspace_id,
      role_key: system_role_key(principal_id, workspace_id),
      role_name: system_role_name(principal_id, workspace_id),
      capability_keys: Enum.sort(capability_keys)
    }

    case run_role_action_with_identity_retry(:ensure_system_role, input) do
      :ok -> :ok
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp local_development_role_name(:workspace_admin), do: "Workspace Administrator"
  defp local_development_role_name(:member), do: "Workspace Member"

  defp system_role_key(principal_id, nil),
    do: "system:#{principal_id}:organization"

  defp system_role_key(principal_id, workspace_id),
    do: "system:#{principal_id}:workspace:#{workspace_id}"

  defp system_role_name(principal_id, nil),
    do: "System principal #{principal_id} (organization)"

  defp system_role_name(principal_id, workspace_id),
    do: "System principal #{principal_id} (workspace #{workspace_id})"

  def authorize_projection(session_context, action, opts \\ [])

  def authorize_projection(
        %Identity.SessionContext{trusted?: true} = session_context,
        action,
        opts
      ) do
    {result, _decision_attrs} =
      evaluate_trusted_session_authorization(
        session_context,
        session_context.organization_id,
        action,
        opts
      )

    result
  end

  def authorize_projection(session_context, action, opts),
    do: authorize(session_context, action, opts)

  def authorize_operation(session_context, operation, action, opts \\ [])

  def authorize_operation(
        %{organization_id: organization_id} = session_context,
        operation,
        action,
        opts
      )
      when is_map(operation) do
    {authorization_result, {action_name, decision, reason}} =
      evaluate_authorization(session_context, organization_id, action, opts)

    operation_matches? = operation_matches_session?(operation, session_context)

    result =
      if operation_matches? do
        authorization_result
      else
        {:error, :forbidden}
      end

    case {operation_matches?, authorization_result} do
      {true, {:error, :integration_storage_unavailable}} ->
        authorization_result

      {true, _authorization_result} ->
        with :ok <- record_decision(session_context, operation, action_name, decision, reason) do
          result
        end

      {false, _authorization_result} ->
        # Mismatched operations are refused before audit persistence so a forged
        # request cannot attach decisions to an operation it does not own.
        result
    end
  end

  def authorize_operation(_session_context, _operation, _action, _opts), do: {:error, :forbidden}

  defp evaluate_authorization(session_context, organization_id, action, opts) do
    requested_workspace_id = Keyword.get(opts, :workspace_id, session_context.workspace_id)

    case Map.fetch(@recognized_capabilities, action) do
      {:ok, required} ->
        cond do
          Identity.validate_session_context(session_context) != :ok ->
            deny(required, "invalid_session")

          organization_id != opts[:organization_id] ->
            deny(required, "scope_mismatch")

          true ->
            evaluate_capability(
              session_context,
              requested_workspace_id,
              required
            )
        end

      :error ->
        deny(recorded_action_name(action), "unknown_action")
    end
  end

  defp evaluate_trusted_session_authorization(session_context, organization_id, action, opts) do
    case Map.fetch(@recognized_capabilities, action) do
      {:ok, required} ->
        cond do
          Identity.validate_session_context(session_context) != :ok ->
            deny(required, "invalid_session")

          organization_id != opts[:organization_id] ->
            deny(required, "scope_mismatch")

          not trusted_capability?(session_context, required) ->
            deny(required, "missing_capability")

          true ->
            {:ok, {required, "allow", nil}}
        end

      :error ->
        deny(recorded_action_name(action), "unknown_action")
    end
  end

  defp deny(action, reason), do: {{:error, :forbidden}, {action, "deny", reason}}

  defp unavailable(action),
    do:
      {{:error, :integration_storage_unavailable},
       {action, "deny", "integration_storage_unavailable"}}

  defp evaluate_capability(session_context, requested_workspace_id, required) do
    case granted_capability?(session_context, requested_workspace_id, required) do
      {:ok, true} -> {:ok, {required, "allow", nil}}
      {:ok, false} -> deny(required, "missing_capability")
      {:error, :integration_storage_unavailable} -> unavailable(required)
    end
  end

  defp record_decision(session_context, operation, action, decision, reason) do
    attrs = %{
      operation_id: Map.fetch!(operation, :id),
      principal_id: session_context.principal_id,
      organization_id: session_context.organization_id,
      action: action,
      decision: decision,
      reason: reason
    }

    DecisionStore.record(attrs)
  end

  defp operation_matches_session?(operation, session_context) do
    Map.get(operation, :principal_id) == session_context.principal_id and
      Map.get(operation, :session_id) == session_context.session_id and
      Map.get(operation, :organization_id) == session_context.organization_id and
      Map.get(operation, :workspace_id) == session_context.workspace_id
  end

  defp recorded_action_name(action) when is_atom(action), do: Atom.to_string(action)
  defp recorded_action_name(action) when is_binary(action), do: action
  defp recorded_action_name(action), do: inspect(action)

  defp granted_capability?(session_context, requested_workspace_id, required) do
    case granted_capability_for_principal(
           session_context.principal_id,
           session_context.organization_id,
           requested_workspace_id,
           required
         ) do
      {:ok, granted?} -> {:ok, granted?}
      {:error, :integration_storage_unavailable} = error -> error
    end
  end

  defp granted_capability_for_principal(
         principal_id,
         organization_id,
         workspace_id,
         required
       ) do
    with :ok <- Persistence.before_read(:principal_capability) do
      case Ash.get(Capability, %{key: required},
             authorize?: false,
             not_found_error?: false
           ) do
        {:ok, %Capability{id: capability_id}} ->
          with {:ok, role_ids} <- role_ids_for_capability(capability_id, organization_id),
               {:ok, granted?} <-
                 role_assignment_exists(principal_id, organization_id, workspace_id, role_ids),
               {:ok, externally_granted?} <-
                 external_role_granted?(
                   granted?,
                   principal_id,
                   organization_id,
                   workspace_id,
                   role_ids
                 ) do
            {:ok, granted? or externally_granted?}
          end

        {:ok, nil} ->
          {:ok, false}

        {:error, _storage_error} ->
          {:error, :integration_storage_unavailable}
      end
    end
  end

  defp trusted_capability?(%{capabilities: %MapSet{} = capabilities}, required) do
    MapSet.member?(capabilities, required)
  end

  defp trusted_capability?(%{capabilities: capabilities}, required) when is_list(capabilities) do
    required in capabilities
  end

  defp trusted_capability?(_session_context, _required), do: false

  defp role_ids_for_capability(capability_id, organization_id) do
    case RoleCapability
         |> Ash.Query.filter(capability_id == ^capability_id)
         |> Ash.read(authorize?: false) do
      {:ok, role_capabilities} ->
        role_capabilities
        |> Enum.map(& &1.role_id)
        |> role_ids_in_organization(organization_id)

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp role_ids_in_organization([], _organization_id), do: {:ok, []}

  defp role_ids_in_organization(role_ids, organization_id) do
    case Role
         |> Ash.Query.filter(id in ^role_ids and organization_id == ^organization_id)
         |> Ash.read(authorize?: false) do
      {:ok, roles} -> {:ok, Enum.map(roles, & &1.id)}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp role_assignment_exists(_principal_id, _organization_id, _workspace_id, []),
    do: {:ok, false}

  defp role_assignment_exists(principal_id, organization_id, nil, role_ids) do
    RoleAssignment
    |> Ash.Query.filter(
      principal_id == ^principal_id and
        organization_id == ^organization_id and
        role_id in ^role_ids and
        is_nil(workspace_id)
    )
    |> Ash.exists(authorize?: false)
    |> normalize_exists_result()
  end

  defp role_assignment_exists(
         principal_id,
         organization_id,
         requested_workspace_id,
         role_ids
       )
       when is_binary(requested_workspace_id) do
    RoleAssignment
    |> Ash.Query.filter(
      principal_id == ^principal_id and
        organization_id == ^organization_id and
        role_id in ^role_ids and
        (is_nil(workspace_id) or workspace_id == ^requested_workspace_id)
    )
    |> Ash.exists(authorize?: false)
    |> normalize_exists_result()
  end

  defp role_assignment_exists(_principal_id, _organization_id, _workspace_id, _role_ids),
    do: {:ok, false}

  defp external_role_granted?(true, _principal_id, _organization_id, _workspace_id, _role_ids),
    do: {:ok, false}

  defp external_role_granted?(false, principal_id, organization_id, workspace_id, role_ids) do
    case external_role_facts().role_ids(
           principal_id,
           organization_id,
           workspace_id,
           role_ids
         ) do
      {:ok, external_role_ids} -> {:ok, external_role_ids != []}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp external_role_facts do
    Application.get_env(
      :office_graph,
      :external_role_facts,
      OfficeGraph.Authorization.ExternalRoleFacts.Empty
    )
  end

  defp normalize_exists_result({:ok, exists?}), do: {:ok, exists?}

  defp normalize_exists_result({:error, _storage_error}),
    do: {:error, :integration_storage_unavailable}

  defp local_development_role_facts(fixture) do
    role_profile = fixture[:role_profile]
    role_key = fixture[:role_key]

    with true <- fixture[:scope] == :workspace,
         true <- role_profile in [:owner, :workspace_admin, :member],
         true <- is_binary(role_key) and role_key == Atom.to_string(role_profile),
         {:ok, capability_keys} <-
           local_development_capability_keys(role_profile, fixture[:actions]) do
      {:ok, role_key, capability_keys}
    else
      _invalid_fixture -> {:error, :local_development_fixture_missing}
    end
  end

  defp local_development_capability_keys(:owner, _actions) do
    {:ok, @owner_capabilities |> Map.values() |> Enum.sort()}
  end

  defp local_development_capability_keys(_role_profile, actions),
    do: ReferenceCatalog.capability_keys(actions)

  defp local_development_assignment_facts(principal_id) do
    with {:ok, assignments} <- Domain.local_development_login_assignments(principal_id),
         role_ids <- assignments |> Enum.map(& &1.role_id) |> Enum.uniq(),
         {:ok, roles} <- Domain.local_development_login_roles(role_ids),
         {:ok, role_capabilities} <-
           Domain.local_development_login_role_capabilities(role_ids, load: :capability) do
      {:ok, assignments, roles, role_capabilities}
    else
      {:error, _storage_error} -> {:error, :authorization_storage_unavailable}
    end
  end

  defp exact_local_development_scope(
         [
           %RoleAssignment{
             role_id: role_id,
             organization_id: organization_id,
             workspace_id: workspace_id
           }
         ],
         [%Role{id: role_id, organization_id: organization_id, key: role_key}],
         role_capabilities,
         role_key,
         expected_capability_keys
       )
       when is_binary(organization_id) and is_binary(workspace_id) do
    actual_capability_keys =
      Enum.map(role_capabilities, fn %RoleCapability{capability: capability} ->
        capability.key
      end)

    if MapSet.new(actual_capability_keys) == MapSet.new(expected_capability_keys) do
      {:ok, %{organization_id: organization_id, workspace_id: workspace_id}}
    else
      {:error, :local_development_fixture_missing}
    end
  end

  defp exact_local_development_scope(
         _missing_or_drifted_assignments,
         _missing_or_drifted_roles,
         _role_capabilities,
         _role_key,
         _expected_capability_keys
       ),
       do: {:error, :local_development_fixture_missing}

  defp reject_external_local_development_roles(principal_id) do
    case external_role_facts().login_scopes(principal_id) do
      {:ok, []} -> :ok
      {:ok, _external_scopes} -> {:error, :local_development_fixture_missing}
      {:error, _storage_error} -> {:error, :authorization_storage_unavailable}
    end
  end

  defp select_login_scope([], _preferred_scope), do: {:error, :no_login_scope}
  defp select_login_scope([scope], nil), do: {:ok, scope}

  defp select_login_scope(scopes, %{
         organization_id: organization_id,
         workspace_id: workspace_id
       })
       when is_binary(organization_id) and is_binary(workspace_id) do
    preferred = %{organization_id: organization_id, workspace_id: workspace_id}
    organization_scope = %{organization_id: organization_id, workspace_id: nil}

    if preferred in scopes or organization_scope in scopes do
      {:ok, preferred}
    else
      {:error, :scope_selection_required}
    end
  end

  defp select_login_scope(_scopes, _preferred_scope),
    do: {:error, :scope_selection_required}

  defp system_capability_keys(actions) do
    actions
    |> Enum.reduce_while({:ok, []}, fn action, {:ok, keys} ->
      case Map.fetch(@system_capabilities, action) do
        {:ok, key} -> {:cont, {:ok, [key | keys]}}
        :error -> {:halt, {:error, :forbidden}}
      end
    end)
  end

  defp run_role_action_with_identity_retry(action, input) do
    case run_role_action(action, input) do
      {:error, %Ash.Error.Invalid{} = error} ->
        if CommandSupport.unique_constraint?(error, @identity_constraints) do
          run_role_action(action, input)
        else
          {:error, error}
        end

      result ->
        result
    end
  end

  defp run_role_action(action, input) do
    Role
    |> Ash.ActionInput.for_action(action, input)
    |> Ash.run_action(authorize?: false)
  end
end
