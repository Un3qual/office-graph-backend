defmodule OfficeGraph.Authorization do
  @moduledoc """
  Public boundary for authorization decisions and capability checks.
  """

  use Boundary, deps: [OfficeGraph.Identity, OfficeGraph.Repo], exports: []

  alias OfficeGraph.Authorization.{
    AuthorizationDecision,
    Capability,
    PolicyBundle,
    Role,
    RoleAssignment,
    RoleCapability
  }

  alias OfficeGraph.Identity
  alias OfficeGraph.Repo

  require Ash.Query

  @owner_capabilities %{
    skeleton_read: "skeleton.read",
    durable_delivery_read: "durable_delivery.read",
    manual_intake_submit: "manual_intake.submit",
    proposed_change_apply: "proposed_change.apply",
    evidence_link: "evidence.link",
    verification_complete: "verification.complete",
    work_packet_create: "work_packet.create",
    work_packet_version_create: "work_packet.version.create",
    work_run_start: "work_run.start",
    execution_observation_record: "execution_observation.record",
    evidence_candidate_create: "evidence_candidate.create",
    evidence_accept: "evidence.accept",
    graph_relationship_create: "graph_relationship.create",
    graph_relationship_supersede: "graph_relationship.supersede",
    graph_relationship_archive: "graph_relationship.archive",
    graph_relationship_restore: "graph_relationship.restore",
    github_installation_bind: "github.installation.bind",
    verification_waive: "verification.waive"
  }

  @restricted_capabilities %{
    graph_relationship_cross_workspace: "graph_relationship.cross_workspace",
    integration_reconcile: "integration.reconcile",
    provider_webhook_receive: "provider.webhook.receive",
    system_conformance: "system.conformance"
  }

  @recognized_capabilities Map.merge(@owner_capabilities, @restricted_capabilities)

  def ensure_owner_role(principal, tenant) do
    Repo.transaction(fn ->
      capabilities_by_key =
        @recognized_capabilities
        |> Map.values()
        |> Map.new(fn key -> {key, ensure_capability!(key)} end)

      capabilities =
        @owner_capabilities
        |> Enum.map(fn {_action, key} -> Map.fetch!(capabilities_by_key, key) end)

      role =
        get_or_create!(
          Role,
          [organization_id: tenant.organization.id, key: "owner"],
          %{
            organization_id: tenant.organization.id,
            key: "owner",
            name: "Owner"
          }
        )

      Enum.each(capabilities, fn capability ->
        get_or_create!(
          RoleCapability,
          [role_id: role.id, capability_id: capability.id],
          %{
            role_id: role.id,
            capability_id: capability.id
          }
        )
      end)

      role_assignment =
        get_or_create!(
          RoleAssignment,
          [
            principal_id: principal.id,
            role_id: role.id,
            organization_id: tenant.organization.id,
            workspace_id: tenant.workspace.id
          ],
          %{
            principal_id: principal.id,
            role_id: role.id,
            organization_id: tenant.organization.id,
            workspace_id: tenant.workspace.id
          }
        )

      policy_bundle =
        get_or_create!(
          PolicyBundle,
          [organization_id: tenant.organization.id, version: 1],
          %{
            organization_id: tenant.organization.id,
            version: 1,
            status: "active"
          }
        )

      %{
        role_assignment: role_assignment,
        policy_bundle: policy_bundle,
        capabilities: Enum.map(capabilities, & &1.key)
      }
    end)
  end

  def authorize(session_context, action, opts \\ [])

  def authorize(%{organization_id: organization_id} = session_context, action, opts) do
    {result, _decision_attrs} =
      evaluate_authorization(session_context, organization_id, action, opts)

    result
  end

  def authorize(_session_context, _action, _opts), do: {:error, :forbidden}

  def authorize_system_principal(principal_id, organization_id, workspace_id, action)
      when is_binary(principal_id) and is_binary(organization_id) do
    with {:ok, required} <- Map.fetch(@recognized_capabilities, action),
         true <- Identity.active_system_principal?(principal_id),
         true <-
           granted_capability_for_principal?(
             principal_id,
             organization_id,
             workspace_id,
             required
           ) do
      :ok
    else
      _other -> {:error, :forbidden}
    end
  end

  def authorize_system_principal(_principal_id, _organization_id, _workspace_id, _action),
    do: {:error, :forbidden}

  def ensure_system_role(
        %{id: principal_id},
        %{organization_id: organization_id, workspace_id: workspace_id},
        actions
      )
      when is_binary(principal_id) and is_binary(organization_id) and is_list(actions) do
    with true <- Identity.active_system_principal?(principal_id),
         {:ok, capability_keys} <- system_capability_keys(actions) do
      role =
        get_or_create!(
          Role,
          [organization_id: organization_id, key: "system:#{principal_id}"],
          %{
            organization_id: organization_id,
            key: "system:#{principal_id}",
            name: "System principal #{principal_id}"
          }
        )

      Enum.each(capability_keys, fn capability_key ->
        capability = ensure_capability!(capability_key)

        get_or_create!(
          RoleCapability,
          [role_id: role.id, capability_id: capability.id],
          %{role_id: role.id, capability_id: capability.id}
        )
      end)

      get_or_create!(
        RoleAssignment,
        [
          principal_id: principal_id,
          role_id: role.id,
          organization_id: organization_id,
          workspace_id: workspace_id
        ],
        %{
          principal_id: principal_id,
          role_id: role.id,
          organization_id: organization_id,
          workspace_id: workspace_id
        }
      )

      :ok
    else
      _error -> {:error, :forbidden}
    end
  end

  def ensure_system_role(_principal, _scope, _actions), do: {:error, :forbidden}

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

    case operation_matches? do
      true ->
        with :ok <- record_decision(session_context, operation, action_name, decision, reason) do
          result
        end

      false ->
        # Mismatched operations are refused before audit persistence so a forged
        # request cannot attach decisions to an operation it does not own.
        result
    end
  end

  def authorize_operation(_session_context, _operation, _action, _opts), do: {:error, :forbidden}

  defp evaluate_authorization(session_context, organization_id, action, opts) do
    case Map.fetch(@recognized_capabilities, action) do
      {:ok, required} ->
        cond do
          Identity.validate_session_context(session_context) != :ok ->
            deny(required, "invalid_session")

          organization_id != opts[:organization_id] ->
            deny(required, "scope_mismatch")

          not granted_capability?(session_context, required) ->
            deny(required, "missing_capability")

          true ->
            {:ok, {required, "allow", nil}}
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

  defp record_decision(session_context, operation, action, decision, reason) do
    attrs = %{
      id: Ecto.UUID.generate(),
      operation_id: Map.fetch!(operation, :id),
      principal_id: session_context.principal_id,
      organization_id: session_context.organization_id,
      action: action,
      decision: decision,
      reason: reason
    }

    AuthorizationDecision
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> case do
      {:ok, _decision, _notifications} -> :ok
      {:ok, _decision} -> :ok
      {:error, error} -> {:error, {:authorization_decision_failed, error}}
    end
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

  defp granted_capability?(session_context, required) do
    granted_capability_for_principal?(
      session_context.principal_id,
      session_context.organization_id,
      session_context.workspace_id,
      required
    )
  end

  defp granted_capability_for_principal?(
         principal_id,
         organization_id,
         workspace_id,
         required
       ) do
    with {:ok, %Capability{id: capability_id}} <-
           Ash.get(Capability, %{key: required}, authorize?: false),
         role_ids when role_ids != [] <-
           role_ids_for_capability(capability_id, organization_id) do
      role_assignment_exists?(principal_id, organization_id, workspace_id, role_ids)
    else
      _ -> false
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
    role_ids =
      RoleCapability
      |> Ash.Query.filter(capability_id == ^capability_id)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.role_id)

    case role_ids do
      [] ->
        []

      role_ids ->
        Role
        |> Ash.Query.filter(id in ^role_ids and organization_id == ^organization_id)
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.id)
    end
  end

  defp role_assignment_exists?(principal_id, organization_id, nil, role_ids) do
    RoleAssignment
    |> Ash.Query.filter(
      principal_id == ^principal_id and
        organization_id == ^organization_id and
        role_id in ^role_ids and
        is_nil(workspace_id)
    )
    |> Ash.exists?(authorize?: false)
  end

  defp role_assignment_exists?(
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
    |> Ash.exists?(authorize?: false)
  end

  defp role_assignment_exists?(_principal_id, _organization_id, _workspace_id, _role_ids),
    do: false

  defp ensure_capability!(key) do
    get_or_create!(
      Capability,
      [key: key],
      %{key: key, description: key}
    )
  end

  defp system_capability_keys(actions) do
    actions
    |> Enum.reduce_while({:ok, []}, fn action, {:ok, keys} ->
      case Map.fetch(@restricted_capabilities, action) do
        {:ok, key} -> {:cont, {:ok, [key | keys]}}
        :error -> {:halt, {:error, :forbidden}}
      end
    end)
  end

  defp get_or_create!(resource, lookup, attrs) do
    Repo.get_or_insert!(resource, lookup, attrs, &insert_contract!/2)
  end

  defp insert_contract!(Capability, _attrs), do: {"capabilities", [:key], [:id]}

  defp insert_contract!(Role, _attrs) do
    {"roles", [:organization_id, :key], [:id, :organization_id]}
  end

  defp insert_contract!(RoleCapability, _attrs) do
    {"role_capabilities", [:role_id, :capability_id], [:id, :role_id, :capability_id]}
  end

  defp insert_contract!(RoleAssignment, %{workspace_id: nil}) do
    {"role_assignments",
     {:unsafe_fragment, "(principal_id, role_id, organization_id) WHERE workspace_id IS NULL"},
     [:id, :principal_id, :role_id, :organization_id]}
  end

  defp insert_contract!(RoleAssignment, _attrs) do
    {"role_assignments",
     {:unsafe_fragment,
      "(principal_id, role_id, organization_id, workspace_id) WHERE workspace_id IS NOT NULL"},
     [:id, :principal_id, :role_id, :organization_id, :workspace_id]}
  end

  defp insert_contract!(PolicyBundle, _attrs) do
    {"policy_bundles", [:organization_id, :version], [:id, :organization_id]}
  end
end
