defmodule OfficeGraph.Identity do
  @moduledoc """
  Public boundary for principals, profiles, credentials, and local bootstrap identity.
  """

  use Boundary, deps: [OfficeGraph.Repo], exports: [SessionContext]

  alias OfficeGraph.Identity.{Principal, PrincipalProfile, Session, SessionContext}
  alias OfficeGraph.Repo

  def ensure_owner(attrs) do
    Repo.transaction(fn ->
      principal =
        get_or_insert!(
          Principal,
          [email: attrs[:owner_email]],
          Principal.changeset(%Principal{}, %{
            email: attrs[:owner_email],
            kind: "human",
            status: "active"
          })
        )

      profile =
        get_or_insert!(
          PrincipalProfile,
          [principal_id: principal.id],
          PrincipalProfile.changeset(%PrincipalProfile{}, %{
            principal_id: principal.id,
            display_name: attrs[:owner_name]
          })
        )

      %{principal: principal, profile: profile}
    end)
  end

  def ensure_session_context(principal, tenant, capabilities) do
    Repo.transaction(fn ->
      session =
        get_or_insert!(
          Session,
          [
            principal_id: principal.id,
            organization_id: tenant.organization.id,
            workspace_id: tenant.workspace.id,
            purpose: "local_owner"
          ],
          Session.changeset(%Session{}, %{
            principal_id: principal.id,
            organization_id: tenant.organization.id,
            workspace_id: tenant.workspace.id,
            purpose: "local_owner"
          })
        )

      %SessionContext{
        principal_id: principal.id,
        session_id: session.id,
        organization_id: tenant.organization.id,
        workspace_id: tenant.workspace.id,
        capabilities: MapSet.new(capabilities)
      }
    end)
  end

  defp get_or_insert!(schema, lookup, changeset) do
    Repo.get_by(schema, lookup) || Repo.insert!(changeset)
  end
end
