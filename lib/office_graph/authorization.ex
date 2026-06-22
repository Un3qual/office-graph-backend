defmodule OfficeGraph.Authorization do
  @moduledoc """
  Public boundary for authorization decisions and capability checks.
  """

  use Boundary, deps: [OfficeGraph.Repo], exports: []

  alias OfficeGraph.Authorization.{Capability, PolicyBundle, Role, RoleAssignment, RoleCapability}
  alias OfficeGraph.Repo

  @owner_capabilities %{
    skeleton_read: "skeleton.read",
    manual_intake_submit: "manual_intake.submit",
    proposed_change_apply: "proposed_change.apply",
    evidence_link: "evidence.link",
    verification_complete: "verification.complete"
  }

  def ensure_owner_role(principal, tenant) do
    Repo.transaction(fn ->
      capabilities =
        @owner_capabilities
        |> Map.values()
        |> Enum.map(&ensure_capability!/1)

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

  def authorize(session_context, action, opts \\ []) do
    case Map.fetch(@owner_capabilities, action) do
      {:ok, required} ->
        cond do
          is_nil(session_context) ->
            {:error, :forbidden}

          session_context.organization_id != opts[:organization_id] ->
            {:error, :forbidden}

          MapSet.member?(session_context.capabilities, required) ->
            :ok

          true ->
            {:error, :forbidden}
        end

      :error ->
        {:error, :forbidden}
    end
  end

  defp ensure_capability!(key) do
    get_or_create!(
      Capability,
      [key: key],
      %{key: key, description: key}
    )
  end

  defp get_or_create!(resource, lookup, attrs) do
    case Ash.get(resource, Map.new(lookup), authorize?: false, not_found_error?: false) do
      {:ok, nil} ->
        attrs =
          attrs
          |> Map.new()
          |> Map.put_new(:id, Ecto.UUID.generate())

        insert_then_fetch!(resource, lookup, attrs)

      {:ok, record} ->
        record

      {:error, error} ->
        raise error
    end
  end

  defp insert_then_fetch!(resource, lookup, attrs) do
    {table, conflict_target, uuid_fields} = insert_contract!(resource, attrs)
    now = DateTime.utc_now()

    insert_attrs =
      attrs
      |> Map.put(:inserted_at, now)
      |> Map.put(:updated_at, now)
      |> dump_uuid_fields(uuid_fields)

    Repo.insert_all(table, [insert_attrs],
      on_conflict: :nothing,
      conflict_target: conflict_target
    )

    case Ash.get(resource, Map.new(lookup), authorize?: false, not_found_error?: false) do
      {:ok, nil} -> raise "#{inspect(resource)} not found after create"
      {:ok, record} -> record
      {:error, refetch_error} -> raise refetch_error
    end
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

  defp dump_uuid_fields(attrs, fields) do
    Enum.reduce(fields, attrs, fn field, acc ->
      Map.update!(acc, field, &Ecto.UUID.dump!/1)
    end)
  end
end
