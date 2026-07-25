defmodule OfficeGraph.Identity.ExternalIdentityReconciliation do
  @moduledoc false

  alias OfficeGraph.Identity.{ExternalIdentityLink, Principal}
  alias OfficeGraph.Repo

  require Ash.Query

  @storage_exceptions [
    Ash.Error.Forbidden,
    Ash.Error.Framework,
    Ash.Error.Invalid,
    Ash.Error.Unknown,
    DBConnection.ConnectionError,
    Ecto.ConstraintError,
    Ecto.StaleEntryError,
    Postgrex.Error,
    RuntimeError
  ]

  def reconcile(claims, opts) when is_map(claims) and is_list(opts) do
    with {:ok, identity} <- normalized_oidc_identity(claims),
         {:ok, config} <- reconciliation_config(opts) do
      with_storage_boundary(fn ->
        Repo.transaction(fn ->
          lock_reconciliation!(identity, config)
          reconcile_locked(identity, config)
        end)
      end)
    end
  end

  def reconcile(_claims, _opts), do: {:error, :invalid_identity_claims}

  defp normalized_oidc_identity(%{
         "sub" => subject,
         "email" => email,
         "email_verified" => true
       })
       when is_binary(subject) and is_binary(email) do
    subject = String.trim(subject)
    email = email |> String.trim() |> String.downcase()

    if subject != "" and email != "" do
      {:ok, %{subject: subject, verified_email: email}}
    else
      {:error, :invalid_identity_claims}
    end
  end

  defp normalized_oidc_identity(%{"email_verified" => false}),
    do: {:error, :unverified_identifier}

  defp normalized_oidc_identity(_claims), do: {:error, :invalid_identity_claims}

  defp reconciliation_config(opts) do
    provider = Keyword.get(opts, :provider)
    provider_tenant = Keyword.get(opts, :provider_tenant)
    account_linking_policy = Keyword.get(opts, :account_linking_policy)

    if present?(provider) and present?(provider_tenant) do
      {:ok,
       %{
         provider: provider,
         provider_tenant: provider_tenant,
         account_linking_policy: account_linking_policy
       }}
    else
      {:error, :invalid_identity_configuration}
    end
  end

  defp reconcile_locked(identity, config) do
    case external_identity_link(config, identity.subject) do
      nil -> reconcile_new_identity(identity, config)
      link -> reconcile_existing_identity(link)
    end
  end

  defp reconcile_existing_identity(%ExternalIdentityLink{
         status: "review_required"
       }),
       do: {:error, :identity_review_required}

  defp reconcile_existing_identity(%ExternalIdentityLink{status: "disabled"}),
    do: {:error, :identity_disabled}

  defp reconcile_existing_identity(
         %ExternalIdentityLink{
           status: "active",
           linking_state: "linked",
           principal_id: principal_id
         } = link
       ) do
    case Ash.get(Principal, principal_id,
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok, %Principal{kind: "human", status: "active"} = principal} ->
        authenticated_link =
          link
          |> Ash.Changeset.for_update(:record_authentication, %{
            last_authenticated_at: DateTime.utc_now()
          })
          |> Repo.ash_update!()

        {:ok, %{principal: principal, external_identity_link: authenticated_link}}

      {:ok, _ineligible_or_inactive} ->
        {:error, :principal_disabled}

      {:error, error} ->
        raise error
    end
  end

  defp reconcile_new_identity(
         identity,
         %{
           account_linking_policy: :verified_email_existing_principal
         } = config
       ) do
    case external_links_for_email(config, identity.verified_email) do
      [] ->
        link_verified_principal(identity, config)

      _incompatible_links ->
        persist_review_link(identity, config, "verified_identifier_conflict")
    end
  end

  defp reconcile_new_identity(identity, config) do
    persist_review_link(identity, config, "account_linking_not_allowed")
  end

  defp link_verified_principal(identity, config) do
    case principal_for_email(identity.verified_email) do
      nil ->
        persist_review_link(identity, config, "unlinked_verified_identifier")

      %Principal{kind: "human", status: "active"} = principal ->
        now = DateTime.utc_now()

        link =
          Repo.ash_create!(
            ExternalIdentityLink,
            %{
              id: Ecto.UUID.generate(),
              principal_id: principal.id,
              provider: config.provider,
              provider_tenant: config.provider_tenant,
              subject: identity.subject,
              verified_email: identity.verified_email,
              status: "active",
              linking_state: "linked",
              first_linked_at: now,
              last_authenticated_at: now
            }
          )

        {:ok, %{principal: principal, external_identity_link: link}}

      %Principal{kind: "human"} ->
        {:error, :principal_disabled}

      %Principal{} ->
        persist_review_link(identity, config, "ineligible_principal")
    end
  end

  defp persist_review_link(identity, config, reason) do
    Repo.ash_create!(
      ExternalIdentityLink,
      %{
        id: Ecto.UUID.generate(),
        provider: config.provider,
        provider_tenant: config.provider_tenant,
        subject: identity.subject,
        verified_email: identity.verified_email,
        status: "review_required",
        linking_state: "review_required",
        review_reason: reason
      }
    )

    {:error, :identity_review_required}
  end

  defp external_identity_link(config, subject) do
    ExternalIdentityLink
    |> Ash.Query.filter(
      provider == ^config.provider and provider_tenant == ^config.provider_tenant and
        subject == ^subject
    )
    |> Ash.read_one!(authorize?: false)
  end

  defp external_links_for_email(config, verified_email) do
    ExternalIdentityLink
    |> Ash.Query.filter(
      provider == ^config.provider and provider_tenant == ^config.provider_tenant and
        verified_email == ^verified_email
    )
    |> Ash.read!(authorize?: false)
  end

  defp principal_for_email(verified_email) do
    Principal
    |> Ash.Query.filter(email == ^verified_email)
    |> Ash.read_one!(authorize?: false)
  end

  defp lock_reconciliation!(identity, config) do
    [
      "external-identity-subject:#{config.provider}:#{config.provider_tenant}:#{identity.subject}",
      "external-identity-email:#{config.provider}:#{config.provider_tenant}:#{identity.verified_email}"
    ]
    |> Enum.sort()
    |> Enum.each(fn key ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key])
    end)
  end

  defp with_storage_boundary(fun) do
    case fun.() do
      {:ok, result} -> result
      {:error, _storage_error} -> {:error, :identity_storage_unavailable}
      result -> result
    end
  rescue
    _error in @storage_exceptions -> {:error, :identity_storage_unavailable}
  catch
    _kind, _reason -> {:error, :identity_storage_unavailable}
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
