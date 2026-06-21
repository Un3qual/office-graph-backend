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
        get_or_create!(
          Principal,
          [email: attrs[:owner_email]],
          %{
            email: attrs[:owner_email],
            kind: "human",
            status: "active"
          }
        )

      profile =
        get_or_create!(
          PrincipalProfile,
          [principal_id: principal.id],
          %{
            principal_id: principal.id,
            display_name: attrs[:owner_name]
          }
        )

      %{principal: principal, profile: profile}
    end)
  end

  def ensure_session_context(principal, tenant, capabilities) do
    Repo.transaction(fn ->
      session =
        get_or_create!(
          Session,
          [
            principal_id: principal.id,
            organization_id: tenant.organization.id,
            workspace_id: tenant.workspace.id,
            purpose: "local_owner"
          ],
          %{
            principal_id: principal.id,
            organization_id: tenant.organization.id,
            workspace_id: tenant.workspace.id,
            purpose: "local_owner"
          }
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

  defp get_or_create!(resource, lookup, attrs) do
    case Ash.get(resource, Map.new(lookup), authorize?: false, not_found_error?: false) do
      {:ok, nil} ->
        attrs =
          attrs
          |> Map.new()
          |> Map.put_new(:id, Ecto.UUID.generate())

        {record, _notifications} =
          Ash.create!(resource, attrs,
            action: :create,
            authorize?: false,
            return_notifications?: true
          )

        record

      {:ok, record} ->
        record
    end
  end
end
