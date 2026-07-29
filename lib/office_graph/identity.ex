defmodule OfficeGraph.Identity do
  @moduledoc """
  Public boundary for principals, profiles, credentials, and local bootstrap identity.
  """

  use Boundary, deps: [OfficeGraph.Tenancy], exports: [SessionContext]

  alias OfficeGraph.Identity.{
    ExternalIdentityReconciliation,
    HumanSessions,
    OidcLoginTransaction,
    Principal,
    Session,
    SessionContext
  }

  require Ash.Query

  @identity_constraints ~w[
    principals_email_index
    principal_profiles_principal_id_index
    sessions_principal_id_organization_id_workspace_id_purpose_inde
  ]

  def ensure_owner(attrs) do
    with_identity_retry(fn ->
      Principal
      |> Ash.ActionInput.for_action(:ensure_owner, %{
        email: attrs[:owner_email],
        display_name: attrs[:owner_name]
      })
      |> Ash.run_action(authorize?: false)
    end)
    |> normalize_identity_write()
  end

  def ensure_session_context(principal, tenant, capabilities) do
    result =
      with_identity_retry(fn ->
        Session
        |> Ash.Changeset.for_create(:ensure_local_owner, %{
          principal_id: principal.id,
          organization_id: tenant.organization.id,
          workspace_id: tenant.workspace.id,
          purpose: "local_owner"
        })
        |> Ash.create(authorize?: false)
      end)

    case result do
      {:ok, session} ->
        {:ok,
         %SessionContext{
           principal_id: principal.id,
           session_id: session.id,
           organization_id: tenant.organization.id,
           workspace_id: tenant.workspace.id,
           capabilities: MapSet.new(capabilities),
           trusted?: true
         }}

      {:error, _storage_error} ->
        {:error, :identity_storage_unavailable}
    end
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
    result =
      with_identity_retry(fn ->
        Principal
        |> Ash.Changeset.for_create(:ensure, %{
          email: email,
          kind: kind,
          status: "active"
        })
        |> Ash.create(authorize?: false)
      end)

    case result do
      {:ok, %Principal{kind: ^kind, status: "active"} = principal} -> {:ok, principal}
      {:ok, _mismatched_principal} -> {:error, :forbidden}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
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

  def store_oidc_login_transaction(expires_at_unix) when is_integer(expires_at_unix) do
    with {:ok, expires_at} <- DateTime.from_unix(expires_at_unix) do
      OidcLoginTransaction
      |> Ash.ActionInput.for_action(:store_login_transaction, %{expires_at: expires_at})
      |> Ash.run_action(authorize?: false)
      |> case do
        {:ok, transaction} -> {:ok, transaction.id}
        {:error, _storage_error} -> {:error, :identity_storage_unavailable}
      end
    end
  end

  def store_oidc_login_transaction(_expires_at_unix), do: {:error, :invalid_login_transaction}

  def store_oidc_login_transaction(transaction_id, expires_at_unix)
      when is_binary(transaction_id) and is_integer(expires_at_unix) do
    with {:ok, transaction_id} <- Ash.Type.UUID.cast_input(transaction_id, []),
         {:ok, expires_at} <- DateTime.from_unix(expires_at_unix),
         {:ok, _transaction} <-
           OidcLoginTransaction
           |> Ash.Changeset.for_create(:create, %{
             id: transaction_id,
             expires_at: expires_at
           })
           |> Ash.create(authorize?: false) do
      :ok
    else
      :error -> {:error, :invalid_login_transaction}
      {:error, _storage_error} -> {:error, :identity_storage_unavailable}
    end
  end

  def store_oidc_login_transaction(_transaction_id, _expires_at_unix),
    do: {:error, :invalid_login_transaction}

  def consume_oidc_login_transaction(transaction_id) when is_binary(transaction_id) do
    with {:ok, transaction_id} <- Ash.Type.UUID.cast_input(transaction_id, []) do
      OidcLoginTransaction
      |> Ash.ActionInput.for_action(:consume_login_transaction, %{id: transaction_id})
      |> Ash.run_action(authorize?: false)
      |> case do
        {:ok, true} -> :ok
        {:ok, false} -> {:error, :invalid_login_transaction}
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

  defp with_identity_retry(fun) do
    case fun.() do
      {:error, %Ash.Error.Invalid{} = error} ->
        if identity_conflict?(error), do: fun.(), else: {:error, error}

      result ->
        result
    end
  end

  defp identity_conflict?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, fn
      %Ash.Error.Changes.InvalidAttribute{private_vars: private_vars} ->
        Keyword.get(private_vars, :constraint_type) == :unique and
          Keyword.get(private_vars, :constraint) in @identity_constraints

      _other ->
        false
    end)
  end

  defp normalize_identity_write({:ok, result}), do: {:ok, result}

  defp normalize_identity_write({:error, _storage_error}),
    do: {:error, :identity_storage_unavailable}
end
