defmodule OfficeGraph.SessionCaseHelpers do
  @moduledoc false

  alias OfficeGraph.Authorization.{Capability, Role, RoleAssignment, RoleCapability}
  alias OfficeGraph.Identity.{Principal, Session, SessionContext}

  def create_session_with_capabilities!(bootstrap, capability_keys, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "capability-test")
    suffix = System.unique_integer([:positive])
    identity = "#{prefix}-#{suffix}"

    principal =
      Ash.create!(
        Principal,
        %{
          id: Ecto.UUID.generate(),
          email: "#{identity}@office-graph.local",
          kind: "human",
          status: "active"
        },
        action: :create,
        authorize?: false
      )

    session =
      Ash.create!(
        Session,
        %{
          id: Ecto.UUID.generate(),
          principal_id: principal.id,
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          purpose: identity
        },
        action: :create,
        authorize?: false
      )

    role =
      Ash.create!(
        Role,
        %{
          id: Ecto.UUID.generate(),
          organization_id: bootstrap.organization.id,
          key: identity,
          name: identity
        },
        action: :create,
        authorize?: false
      )

    Enum.each(capability_keys, fn capability_key ->
      capability = Ash.get!(Capability, %{key: capability_key}, authorize?: false)

      Ash.create!(
        RoleCapability,
        %{id: Ecto.UUID.generate(), role_id: role.id, capability_id: capability.id},
        action: :create,
        authorize?: false
      )
    end)

    Ash.create!(
      RoleAssignment,
      %{
        id: Ecto.UUID.generate(),
        principal_id: principal.id,
        role_id: role.id,
        organization_id: bootstrap.organization.id,
        workspace_id: bootstrap.workspace.id
      },
      action: :create,
      authorize?: false
    )

    %SessionContext{
      principal_id: principal.id,
      session_id: session.id,
      organization_id: bootstrap.organization.id,
      workspace_id: bootstrap.workspace.id,
      capabilities: MapSet.new(capability_keys),
      trusted?: Keyword.get(opts, :trusted?, false)
    }
  end
end
