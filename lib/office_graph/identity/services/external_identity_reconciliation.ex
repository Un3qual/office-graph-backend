defmodule OfficeGraph.Identity.ExternalIdentityReconciliation do
  @moduledoc false

  alias OfficeGraph.Identity.{ExternalIdentityLink, Principal}
  alias OfficeGraph.Repo

  require Ash.Query

  @storage_exceptions [
    DBConnection.ConnectionError,
    Ecto.ConstraintError,
    Ecto.StaleEntryError,
    Postgrex.Error
  ]

  def reconcile(claims, opts) do
    case reconcile_with_evidence(claims, opts) do
      {:error, reason, _evidence} -> {:error, reason}
      result -> result
    end
  end

  def reconcile_with_evidence(claims, opts) when is_map(claims) and is_list(opts) do
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

  def reconcile_with_evidence(_claims, _opts), do: {:error, :invalid_identity_claims}

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

    cond do
      not present?(provider) or not present?(provider_tenant) ->
        {:error, :invalid_identity_configuration}

      account_linking_policy != :verified_email_existing_principal ->
        {:error, :unsupported_account_linking_policy}

      true ->
        {:ok,
         %{
           provider: provider,
           provider_tenant: provider_tenant,
           account_linking_policy: account_linking_policy
         }}
    end
  end

  defp reconcile_locked(identity, config) do
    case external_identity_link(config, identity.subject) do
      nil -> reconcile_new_identity(identity, config)
      link -> reconcile_existing_identity(link, identity)
    end
  end

  defp reconcile_existing_identity(link, identity) do
    case link do
      %ExternalIdentityLink{status: "review_required"} ->
        rejected_with_evidence(:identity_review_required, link)

      %ExternalIdentityLink{status: "disabled"} ->
        rejected_with_evidence(:identity_disabled, link)

      %ExternalIdentityLink{
        status: "active",
        linking_state: "linked",
        principal_id: principal_id
      } ->
        case Ash.get(Principal, principal_id,
               authorize?: false,
               not_found_error?: false
             ) do
          {:ok, %Principal{kind: "human", status: "active"} = principal} ->
            if verified_identifier_compatible?(link, identity) do
              authenticated_link =
                link
                |> Ash.Changeset.for_update(:record_authentication, %{
                  last_authenticated_at: DateTime.utc_now()
                })
                |> Repo.ash_update!()

              {:ok, %{principal: principal, external_identity_link: authenticated_link}}
            else
              reviewed_link =
                link
                |> Ash.Changeset.for_update(:set_lifecycle, %{
                  status: "review_required",
                  linking_state: "review_required",
                  review_reason: "verified_identifier_conflict"
                })
                |> Repo.ash_update!()

              rejected_with_evidence(:identity_review_required, reviewed_link)
            end

          {:ok, _ineligible_or_inactive} ->
            rejected_with_evidence(:principal_disabled, link)

          {:error, error} ->
            raise error
        end
    end
  end

  defp verified_identifier_compatible?(
         %ExternalIdentityLink{verified_email: verified_email},
         %{verified_email: verified_email}
       ),
       do: true

  defp verified_identifier_compatible?(link, identity) do
    external_links_for_email(identity.verified_email) == [] and
      case principals_for_email(identity.verified_email) do
        [] -> true
        [%Principal{id: principal_id}] -> principal_id == link.principal_id
        _conflicting_principals -> false
      end
  end

  defp reconcile_new_identity(
         identity,
         %{
           account_linking_policy: :verified_email_existing_principal
         } = config
       ) do
    case external_links_for_email(identity.verified_email) do
      [] ->
        link_verified_principal(identity, config)

      _incompatible_links ->
        persist_review_link(identity, config, "verified_identifier_conflict")
    end
  end

  defp link_verified_principal(identity, config) do
    case principals_for_email(identity.verified_email) do
      [] ->
        persist_review_link(identity, config, "unlinked_verified_identifier")

      [%Principal{kind: "human", status: "active"} = principal] ->
        now = DateTime.utc_now()

        link =
          Repo.ash_create!(
            ExternalIdentityLink,
            %{
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

      [%Principal{}] ->
        persist_review_link(identity, config, "ineligible_principal")

      _ambiguous_principals ->
        persist_review_link(identity, config, "ambiguous_verified_identifier")
    end
  end

  defp persist_review_link(identity, config, reason) do
    link =
      Repo.ash_create!(
        ExternalIdentityLink,
        %{
          provider: config.provider,
          provider_tenant: config.provider_tenant,
          subject: identity.subject,
          verified_email: identity.verified_email,
          status: "review_required",
          linking_state: "review_required",
          review_reason: reason
        }
      )

    rejected_with_evidence(:identity_review_required, link)
  end

  defp external_identity_link(config, subject) do
    ExternalIdentityLink
    |> Ash.Query.filter(
      provider == ^config.provider and provider_tenant == ^config.provider_tenant and
        subject == ^subject
    )
    |> Ash.read_one!(authorize?: false)
  end

  defp external_links_for_email(verified_email) do
    ExternalIdentityLink
    |> Ash.Query.filter(verified_email == ^verified_email)
    |> Ash.read!(authorize?: false)
  end

  defp principals_for_email(verified_email) do
    Principal
    |> Ash.Query.filter(fragment("lower(btrim(?))", email) == ^verified_email)
    |> Ash.read!(authorize?: false)
  end

  defp lock_reconciliation!(identity, config) do
    [
      "external-identity-subject:#{config.provider}:#{config.provider_tenant}:#{identity.subject}",
      "external-identity-email:#{identity.verified_email}"
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
  end

  defp rejected_with_evidence(reason, link) do
    {:error, reason, %{external_identity_link: link}}
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
