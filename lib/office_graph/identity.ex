defmodule OfficeGraph.Identity do
  @moduledoc """
  Public boundary for principals, profiles, credentials, and local bootstrap identity.
  """

  use Boundary,
    deps: [OfficeGraph.CommandSupport, OfficeGraph.Tenancy],
    exports: [SessionContext]

  alias OfficeGraph.CommandSupport

  alias OfficeGraph.Identity.{
    ExternalIdentityReconciliation,
    DirectoryIdentityResult,
    ExternalIdentityLink,
    HumanSessions,
    LocalDevelopmentIdentity,
    OidcLoginTransaction,
    Principal,
    PrincipalProfile,
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

  def ensure_local_development_identity(attrs) when is_map(attrs) do
    ExternalIdentityLink
    |> Ash.ActionInput.for_action(:ensure_local_development_identity, %{
      provider: attrs[:provider],
      provider_tenant: attrs[:provider_tenant],
      subject: attrs[:subject],
      email: attrs[:email],
      display_name: attrs[:display_name],
      principal_status: attrs[:principal_status],
      link_status: attrs[:link_status]
    })
    |> Ash.run_action(authorize?: false)
    |> normalize_identity_write()
  end

  def ensure_local_development_identity(_attrs),
    do: {:error, :local_development_fixture_missing}

  def local_development_identity(attrs) when is_map(attrs) do
    with {:ok, %ExternalIdentityLink{} = link} <-
           Ash.get(
             ExternalIdentityLink,
             %{
               provider: attrs[:provider],
               provider_tenant: attrs[:provider_tenant],
               subject: attrs[:subject]
             },
             authorize?: false,
             not_found_error?: false
           ),
         {:ok, %Principal{} = principal} <-
           Ash.get(Principal, link.principal_id,
             authorize?: false,
             not_found_error?: false
           ),
         {:ok, %PrincipalProfile{} = profile} <-
           Ash.get(PrincipalProfile, %{principal_id: principal.id},
             authorize?: false,
             not_found_error?: false
           ),
         true <- exact_local_development_identity?(attrs, principal, link) do
      LocalDevelopmentIdentity.from_records(principal, profile, link)
    else
      {:error, _storage_error} -> {:error, :identity_storage_unavailable}
      _missing_or_drifted -> {:error, :local_development_fixture_missing}
    end
  end

  def local_development_identity(_attrs),
    do: {:error, :local_development_fixture_missing}

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
        |> Ash.create(authorize?: false, return_notifications?: true)
        |> consume_notifications()
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
             resolved.external_identity_link_id == external_identity_link_id and
             resolved.authentication_method == session_context.authentication_method and
             resolved.enterprise_connection_id == session_context.enterprise_connection_id do
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
        |> Ash.create(authorize?: false, return_notifications?: true)
        |> consume_notifications()
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

  def reconcile_directory_identity(attrs) when is_map(attrs) do
    ExternalIdentityLink
    |> Ash.ActionInput.for_action(:reconcile_directory_identity, attrs)
    |> Ash.run_action(authorize?: false)
    |> case do
      {:ok, %DirectoryIdentityResult{} = result} ->
        DirectoryIdentityResult.to_reconciliation_result(result)

      {:error, _storage_error} ->
        {:error, :identity_storage_unavailable}
    end
  end

  def reconcile_directory_identity(_attrs), do: {:error, :invalid_identity_claims}

  def deprovision_directory_identity(attrs) when is_map(attrs) do
    ExternalIdentityLink
    |> Ash.ActionInput.for_action(:deprovision_directory_identity, attrs)
    |> Ash.run_action(authorize?: false)
    |> case do
      {:ok, %DirectoryIdentityResult{status: "deprovisioned"}} -> :ok
      {:error, _storage_error} -> {:error, :identity_storage_unavailable}
    end
  end

  def deprovision_directory_identity(_attrs), do: {:error, :invalid_identity_claims}

  def reconcile_workos_sso_identity(profile, provider_tenant)
      when is_map(profile) and is_binary(provider_tenant) do
    with subject when is_binary(subject) and subject != "" <- profile[:subject],
         provider_identity_id when is_binary(provider_identity_id) and provider_identity_id != "" <-
           profile[:idp_id],
         verified_email when is_binary(verified_email) and verified_email != "" <-
           profile[:verified_email] do
      ExternalIdentityLink
      |> Ash.ActionInput.for_action(:reconcile_workos_sso_identity, %{
        provider_tenant: provider_tenant,
        subject: subject,
        provider_identity_id: provider_identity_id,
        verified_email: verified_email
      })
      |> Ash.run_action(authorize?: false)
      |> case do
        {:ok, %DirectoryIdentityResult{} = result} ->
          DirectoryIdentityResult.to_reconciliation_result(result)

        {:error, _storage_error} ->
          {:error, :identity_storage_unavailable}
      end
    else
      _invalid_profile -> {:error, :invalid_identity_claims}
    end
  end

  def reconcile_workos_sso_identity(_profile, _provider_tenant),
    do: {:error, :invalid_identity_claims}

  def workos_sso_session_identity(external_identity_link_id, principal_id, provider_tenant)
      when is_binary(external_identity_link_id) and is_binary(principal_id) and
             is_binary(provider_tenant) do
    ExternalIdentityLink
    |> Ash.Query.filter(
      id == ^external_identity_link_id and principal_id == ^principal_id and
        provider == "workos_sso" and provider_tenant == ^provider_tenant and
        status == "active" and linking_state == "linked"
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %ExternalIdentityLink{} = link} ->
        {:ok,
         %{
           provider_identity_id: link.provider_identity_id,
           verified_email: link.verified_email
         }}

      {:ok, nil} ->
        {:error, :identity_unavailable}

      {:error, _storage_error} ->
        {:error, :identity_storage_unavailable}
    end
  end

  def workos_sso_session_identity(_external_identity_link_id, _principal_id, _provider_tenant),
    do: {:error, :identity_unavailable}

  defdelegate issue_human_session(principal, link, scope, opts),
    to: HumanSessions,
    as: :issue

  defdelegate resolve_human_session(session_id), to: HumanSessions, as: :resolve
  defdelegate resolve_human_session(session_id, opts), to: HumanSessions, as: :resolve

  defdelegate human_session_authentication_method(session_id),
    to: HumanSessions,
    as: :authentication_method

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

  defp exact_local_development_identity?(%{email: expected_email} = attrs, principal, link)
       when is_binary(expected_email) do
    normalized_email = String.downcase(expected_email)

    principal.email == normalized_email and
      principal.kind == "human" and
      link.principal_id == principal.id and
      link.provider == attrs[:provider] and
      link.provider_tenant == attrs[:provider_tenant] and
      link.subject == attrs[:subject] and
      link.verified_email == normalized_email
  end

  defp exact_local_development_identity?(_attrs, _principal, _link), do: false

  defp with_identity_retry(fun) do
    case fun.() do
      {:error, %Ash.Error.Invalid{} = error} ->
        if CommandSupport.unique_constraint?(error, @identity_constraints),
          do: fun.(),
          else: {:error, error}

      result ->
        result
    end
  end

  defp normalize_identity_write({:ok, result}), do: {:ok, result}

  defp normalize_identity_write({:error, _storage_error}),
    do: {:error, :identity_storage_unavailable}

  defp consume_notifications({:ok, record, _notifications}), do: {:ok, record}
  defp consume_notifications({:error, error}), do: {:error, error}
end
