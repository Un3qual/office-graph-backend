defmodule OfficeGraph.Identity do
  @moduledoc """
  Public boundary for principals, profiles, credentials, and local bootstrap identity.
  """

  use Boundary, deps: [OfficeGraph.Repo, OfficeGraph.Tenancy], exports: [SessionContext]

  alias OfficeGraph.Identity.{
    ExternalIdentityReconciliation,
    HumanSessions,
    OidcLoginTransaction,
    Principal,
    PrincipalProfile,
    Session,
    SessionContext
  }

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

  def validate_session_context(
        %SessionContext{external_identity_link_id: external_identity_link_id} = session_context
      )
      when is_binary(external_identity_link_id) do
    case HumanSessions.resolve(session_context.session_id) do
      {:ok, resolved} ->
        if resolved.principal_id == session_context.principal_id and
             resolved.organization_id == session_context.organization_id and
             resolved.workspace_id == session_context.workspace_id and
             resolved.external_identity_link_id == external_identity_link_id do
          :ok
        else
          {:error, :forbidden}
        end

      {:error, :invalid_session} ->
        {:error, :forbidden}

      {:error, :identity_storage_unavailable} = error ->
        error
    end
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

  def active_system_principal(principal_id) when is_binary(principal_id) do
    case Ash.get(Principal, principal_id,
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok, %Principal{kind: kind, status: "active"}}
      when kind in ["agent", "integration", "service", "webhook"] ->
        {:ok, true}

      {:ok, _missing_or_inactive} ->
        {:ok, false}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  def active_system_principal(_principal_id), do: {:ok, false}

  def active_principal(principal_id) when is_binary(principal_id) do
    case Ash.get(Principal, principal_id,
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok, %Principal{status: "active"}} -> {:ok, true}
      {:ok, _missing_or_inactive} -> {:ok, false}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  def active_principal(_principal_id), do: {:ok, false}

  def ensure_system_principal(email, kind)
      when is_binary(email) and kind in ["agent", "service", "webhook"] do
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

  defdelegate reconcile_oidc_identity(claims, opts),
    to: ExternalIdentityReconciliation,
    as: :reconcile

  defdelegate reconcile_oidc_identity_with_evidence(claims, opts),
    to: ExternalIdentityReconciliation,
    as: :reconcile_with_evidence

  defdelegate issue_human_session(principal, link, scope, opts),
    to: HumanSessions,
    as: :issue

  defdelegate resolve_human_session(session_id), to: HumanSessions, as: :resolve
  defdelegate resolve_human_session(session_id, opts), to: HumanSessions, as: :resolve
  defdelegate revoke_human_session(session_id, opts), to: HumanSessions, as: :revoke
  defdelegate record_authentication_event(attrs), to: HumanSessions, as: :record_event
  defdelegate reject_human_session(session_context, reason, opts), to: HumanSessions, as: :reject

  def store_oidc_login_transaction(transaction_id, expires_at_unix)
      when is_binary(transaction_id) and is_integer(expires_at_unix) do
    with {:ok, transaction_id} <- Ecto.UUID.cast(transaction_id),
         {:ok, expires_at} <- DateTime.from_unix(expires_at_unix),
         {:ok, _transaction} <-
           OidcLoginTransaction
           |> Ash.Changeset.for_create(:create, %{
             id: transaction_id,
             expires_at: expires_at
           })
           |> Ash.create() do
      :ok
    else
      :error -> {:error, :invalid_login_transaction}
      {:error, _storage_error} -> {:error, :identity_storage_unavailable}
    end
  end

  def store_oidc_login_transaction(_transaction_id, _expires_at_unix),
    do: {:error, :invalid_login_transaction}

  def consume_oidc_login_transaction(transaction_id) when is_binary(transaction_id) do
    with {:ok, transaction_id} <- Ecto.UUID.cast(transaction_id) do
      case Repo.query(
             """
             DELETE FROM oidc_login_transactions
             WHERE id = $1
             RETURNING expires_at >= (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
             """,
             [Ecto.UUID.dump!(transaction_id)]
           ) do
        {:ok, %{rows: [[true]]}} -> :ok
        {:ok, %{rows: []}} -> {:error, :invalid_login_transaction}
        {:ok, %{rows: [[false]]}} -> {:error, :invalid_login_transaction}
        {:error, _storage_error} -> {:error, :identity_storage_unavailable}
      end
    else
      :error -> {:error, :invalid_login_transaction}
    end
  end

  def consume_oidc_login_transaction(_transaction_id),
    do: {:error, :invalid_login_transaction}

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
