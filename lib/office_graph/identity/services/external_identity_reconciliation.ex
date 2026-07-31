defmodule OfficeGraph.Identity.ExternalIdentityReconciliation do
  @moduledoc false

  alias OfficeGraph.Identity.{ExternalIdentityLink, ReconciliationResult}

  @storage_exceptions [
    DBConnection.ConnectionError,
    Ecto.ConstraintError,
    Ecto.StaleEntryError,
    Postgrex.Error
  ]

  @provider_subject_constraint "external_identity_links_provider_provider_tenant_subject_index"

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
        identity
        |> run_reconciliation(config)
        |> normalize_result()
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

  defp run_reconciliation(identity, config) do
    input = %{
      provider: config.provider,
      provider_tenant: config.provider_tenant,
      subject: identity.subject,
      verified_email: identity.verified_email
    }

    case run_reconciliation_action(input) do
      {:error, %Ash.Error.Invalid{} = error} ->
        if provider_subject_conflict?(error) do
          run_reconciliation_action(input)
        else
          {:error, error}
        end

      result ->
        result
    end
  end

  defp run_reconciliation_action(input) do
    ExternalIdentityLink
    |> Ash.ActionInput.for_action(:reconcile_oidc_identity, input)
    |> Ash.run_action(authorize?: false)
  end

  defp provider_subject_conflict?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, fn
      %Ash.Error.Changes.InvalidAttribute{private_vars: private_vars} ->
        Keyword.get(private_vars, :constraint_type) == :unique and
          Keyword.get(private_vars, :constraint) == @provider_subject_constraint

      _other ->
        false
    end)
  end

  defp normalize_result({:ok, %ReconciliationResult{} = result}) do
    ReconciliationResult.to_public_result(result)
  end

  defp normalize_result({:error, _error}), do: {:error, :identity_storage_unavailable}

  defp with_storage_boundary(fun) do
    fun.()
  rescue
    _error in @storage_exceptions -> {:error, :identity_storage_unavailable}
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
