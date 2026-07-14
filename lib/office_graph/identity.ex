defmodule OfficeGraph.Identity do
  @moduledoc """
  Public boundary for principals, profiles, credentials, and local bootstrap identity.
  """

  use Boundary, deps: [OfficeGraph.Repo], exports: [SessionContext]

  alias OfficeGraph.Identity.{Principal, PrincipalProfile, Session, SessionContext}
  alias OfficeGraph.Repo

  require Ash.Query

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
        capabilities: MapSet.new(capabilities),
        trusted?: true
      }
    end)
  end

  def validate_session_context(%SessionContext{} = session_context) do
    Session
    |> Ash.Query.filter(id == ^session_context.session_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok,
       %Session{
         principal_id: principal_id,
         organization_id: organization_id,
         workspace_id: workspace_id,
         revoked_at: nil
       }} ->
        if principal_id == session_context.principal_id and
             organization_id == session_context.organization_id and
             workspace_id == session_context.workspace_id and
             active_principal?(principal_id) do
          :ok
        else
          {:error, :forbidden}
        end

      {:ok, _missing_or_revoked} ->
        {:error, :forbidden}

      {:error, _error} ->
        {:error, :forbidden}
    end
  end

  def validate_session_context(_session_context), do: {:error, :forbidden}

  def active_system_principal?(principal_id) when is_binary(principal_id) do
    match?(
      {:ok, %Principal{kind: kind, status: "active"}}
      when kind in ["integration", "service", "webhook"],
      Ash.get(Principal, principal_id,
        authorize?: false,
        not_found_error?: false
      )
    )
  end

  def active_system_principal?(_principal_id), do: false

  def ensure_system_principal(email, kind)
      when is_binary(email) and kind in ["service", "webhook"] do
    principal =
      get_or_create!(
        Principal,
        [email: email],
        %{email: email, kind: kind, status: "active"}
      )

    if principal.kind == kind and principal.status == "active" do
      {:ok, principal}
    else
      {:error, :forbidden}
    end
  end

  def ensure_system_principal(_email, _kind), do: {:error, :forbidden}

  defp active_principal?(principal_id) do
    match?(
      {:ok, %Principal{status: "active"}},
      Ash.get(Principal, principal_id, authorize?: false, not_found_error?: false)
    )
  end

  defp get_or_create!(resource, lookup, attrs) do
    Repo.get_or_insert!(
      resource,
      lookup,
      attrs,
      fn resource, _attrs -> insert_contract!(resource) end,
      &fetch_existing/2
    )
  end

  defp fetch_existing(Session, lookup) do
    lookup = Map.new(lookup)

    Session
    |> Ash.Query.filter(
      principal_id == ^lookup.principal_id and
        organization_id == ^lookup.organization_id and
        workspace_id == ^lookup.workspace_id and
        purpose == ^lookup.purpose and
        is_nil(revoked_at)
    )
    |> Ash.read_one(authorize?: false)
  end

  defp fetch_existing(resource, lookup) do
    Ash.get(resource, Map.new(lookup), authorize?: false, not_found_error?: false)
  end

  defp insert_contract!(Principal), do: {"principals", [:email], [:id]}

  defp insert_contract!(PrincipalProfile) do
    {"principal_profiles", [:principal_id], [:id, :principal_id]}
  end

  defp insert_contract!(Session) do
    {"sessions",
     {:unsafe_fragment,
      "(principal_id, organization_id, workspace_id, purpose) WHERE revoked_at IS NULL"},
     [:id, :principal_id, :organization_id, :workspace_id]}
  end
end
