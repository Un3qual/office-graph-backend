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
        get_or_insert!(
          Role,
          [organization_id: tenant.organization.id, key: "owner"],
          Role.changeset(%Role{}, %{
            organization_id: tenant.organization.id,
            key: "owner",
            name: "Owner"
          })
        )

      Enum.each(capabilities, fn capability ->
        get_or_insert!(
          RoleCapability,
          [role_id: role.id, capability_id: capability.id],
          RoleCapability.changeset(%RoleCapability{}, %{
            role_id: role.id,
            capability_id: capability.id
          })
        )
      end)

      role_assignment =
        get_or_insert!(
          RoleAssignment,
          [principal_id: principal.id, role_id: role.id, organization_id: tenant.organization.id],
          RoleAssignment.changeset(%RoleAssignment{}, %{
            principal_id: principal.id,
            role_id: role.id,
            organization_id: tenant.organization.id,
            workspace_id: tenant.workspace.id
          })
        )

      policy_bundle =
        get_or_insert!(
          PolicyBundle,
          [organization_id: tenant.organization.id, version: 1],
          PolicyBundle.changeset(%PolicyBundle{}, %{
            organization_id: tenant.organization.id,
            version: 1,
            status: "active"
          })
        )

      %{
        role_assignment: role_assignment,
        policy_bundle: policy_bundle,
        capabilities: Enum.map(capabilities, & &1.key)
      }
    end)
  end

  def authorize(session_context, action, opts \\ []) do
    required = Map.fetch!(@owner_capabilities, action)

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
  end

  defp ensure_capability!(key) do
    get_or_insert!(
      Capability,
      [key: key],
      Capability.changeset(%Capability{}, %{key: key, description: key})
    )
  end

  defp get_or_insert!(schema, lookup, changeset) do
    Repo.get_by(schema, lookup) || Repo.insert!(changeset)
  end
end
