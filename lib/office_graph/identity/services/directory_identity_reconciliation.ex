defmodule OfficeGraph.Identity.DirectoryIdentityResult do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :status, :string, allow_nil?: false
    field :reason, :string
    field :principal_origin, :string
    field :principal, :struct, constraints: [instance_of: OfficeGraph.Identity.Principal]

    field :external_identity_link, :struct,
      constraints: [instance_of: OfficeGraph.Identity.ExternalIdentityLink]
  end

  def linked(principal, external_identity_link, principal_origin) do
    new(
      status: "linked",
      principal: principal,
      external_identity_link: external_identity_link,
      principal_origin: principal_origin
    )
  end

  def review_required(reason), do: new(status: "review_required", reason: reason)
  def deprovisioned, do: new(status: "deprovisioned")

  def to_reconciliation_result(%__MODULE__{
        status: "linked",
        principal: principal,
        external_identity_link: link,
        principal_origin: principal_origin
      }) do
    {:ok,
     %{
       principal: principal,
       external_identity_link: link,
       principal_origin: principal_origin
     }}
  end

  def to_reconciliation_result(%__MODULE__{status: "review_required", reason: reason}),
    do: {:review, reason}
end

defmodule OfficeGraph.Identity.Actions.ReconcileDirectoryIdentity do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.Identity.{
    DirectoryIdentityResult,
    ExternalIdentityLink,
    Principal
  }

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    attrs = input.arguments

    with {:ok, principals} <- locked_principals_for_email(attrs.verified_email),
         {:ok, subject_link} <-
           locked_subject_link(attrs.provider_tenant, attrs.subject),
         {:ok, email_links} <- locked_links_for_email(attrs.verified_email) do
      select_identity_basis(subject_link, principals, email_links, attrs)
    end
  end

  defp select_identity_basis(
         %ExternalIdentityLink{
           status: "active",
           linking_state: "linked",
           principal_id: principal_id,
           verified_email: verified_email
         } = link,
         principals,
         email_links,
         attrs
       )
       when is_binary(principal_id) do
    with true <- verified_email == attrs.verified_email,
         %Principal{kind: "human", status: "active"} = principal <-
           Enum.find(principals, &(&1.id == principal_id)),
         false <- incompatible_link?(email_links, principal.id) do
      DirectoryIdentityResult.linked(
        principal,
        link,
        principal_origin(attrs, principal.id, "reused")
      )
    else
      _conflict -> DirectoryIdentityResult.review_required("verified_identifier_conflict")
    end
  end

  defp select_identity_basis(%ExternalIdentityLink{}, _principals, _email_links, _attrs),
    do: DirectoryIdentityResult.review_required("provider_subject_conflict")

  defp select_identity_basis(nil, [], [], attrs) do
    with {:ok, principal} <- ensure_principal(attrs.verified_email),
         {:ok, link} <- create_directory_link(principal, attrs) do
      DirectoryIdentityResult.linked(
        principal,
        link,
        principal_origin(attrs, principal.id, "created")
      )
    end
  end

  defp select_identity_basis(nil, [], [_existing_link | _rest], _attrs),
    do: DirectoryIdentityResult.review_required("verified_identifier_conflict")

  defp select_identity_basis(
         nil,
         [%Principal{kind: "human", status: "active"} = principal],
         email_links,
         attrs
       ) do
    if incompatible_link?(email_links, principal.id) do
      DirectoryIdentityResult.review_required("verified_identifier_conflict")
    else
      with {:ok, link} <- create_directory_link(principal, attrs) do
        DirectoryIdentityResult.linked(
          principal,
          link,
          principal_origin(attrs, principal.id, "reused")
        )
      end
    end
  end

  defp select_identity_basis(nil, [_ineligible], _email_links, _attrs),
    do: DirectoryIdentityResult.review_required("ineligible_principal")

  defp select_identity_basis(nil, _ambiguous, _email_links, _attrs),
    do: DirectoryIdentityResult.review_required("ambiguous_verified_identifier")

  defp principal_origin(
         %{current_principal_id: principal_id, current_principal_origin: origin},
         principal_id,
         _fallback
       )
       when origin in ["created", "reused"],
       do: origin

  defp principal_origin(_attrs, _principal_id, fallback), do: fallback

  defp incompatible_link?(links, principal_id) do
    Enum.any?(links, fn link ->
      is_nil(link.principal_id) or link.principal_id != principal_id or
        link.status != "active" or link.linking_state != "linked"
    end)
  end

  defp ensure_principal(email) do
    Principal
    |> Ash.Changeset.for_create(:ensure, %{
      email: email,
      kind: "human",
      status: "active"
    })
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> consume_notifications()
  end

  defp create_directory_link(principal, attrs) do
    ExternalIdentityLink
    |> Ash.Changeset.for_create(:create, %{
      principal_id: principal.id,
      provider: "workos_directory",
      provider_tenant: attrs.provider_tenant,
      subject: attrs.subject,
      verified_email: attrs.verified_email,
      status: "active",
      linking_state: "linked",
      first_linked_at: DateTime.utc_now()
    })
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> consume_notifications()
  end

  defp locked_subject_link(provider_tenant, subject) do
    ExternalIdentityLink
    |> Ash.Query.filter(
      provider == "workos_directory" and provider_tenant == ^provider_tenant and
        subject == ^subject
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp locked_links_for_email(email) do
    ExternalIdentityLink
    |> Ash.Query.filter(verified_email == ^email)
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.lock(:for_update)
    |> Ash.read(authorize?: false)
  end

  defp locked_principals_for_email(email) do
    Principal
    |> Ash.Query.filter(email == ^email)
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.lock(:for_update)
    |> Ash.read(authorize?: false)
  end

  defp consume_notifications({:ok, record, _notifications}), do: {:ok, record}
  defp consume_notifications({:error, error}), do: {:error, error}
end

defmodule OfficeGraph.Identity.Actions.DeprovisionDirectoryIdentity do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.Identity.{
    DirectoryIdentityResult,
    ExternalIdentityLink,
    Principal
  }

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    attrs = input.arguments

    with {:ok, principal} <- locked_principal(attrs.principal_id),
         :ok <- disable_link(attrs.external_identity_link_id, attrs.disabled_at),
         :ok <-
           maybe_disable_sso_links(
             attrs.principal_id,
             attrs.provider_tenant,
             attrs.disabled_at
           ),
         :ok <- maybe_disable_created_principal(attrs, principal) do
      DirectoryIdentityResult.deprovisioned()
    end
  end

  defp disable_link(nil, _disabled_at), do: :ok

  defp disable_link(link_id, disabled_at) do
    case locked_link(link_id) do
      {:ok, nil} ->
        :ok

      {:ok, %ExternalIdentityLink{status: "disabled"}} ->
        :ok

      {:ok, link} ->
        link
        |> Ash.Changeset.for_update(:set_lifecycle, %{
          status: "disabled",
          disabled_at: disabled_at
        })
        |> Ash.update(authorize?: false)
        |> normalize_ok()

      {:error, _reason} = error ->
        error
    end
  end

  defp disable_sso_links(principal_id, provider_tenant, disabled_at) do
    ExternalIdentityLink
    |> Ash.Query.filter(
      principal_id == ^principal_id and provider == "workos_sso" and
        provider_tenant == ^provider_tenant and status != "disabled"
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, links} ->
        Enum.reduce_while(links, :ok, fn link, :ok ->
          case disable_link(link.id, disabled_at) do
            :ok -> {:cont, :ok}
            {:error, _reason} = error -> {:halt, error}
          end
        end)

      {:error, _reason} = error ->
        error
    end
  end

  defp maybe_disable_sso_links(nil, _provider_tenant, _disabled_at), do: :ok

  defp maybe_disable_sso_links(principal_id, provider_tenant, disabled_at) do
    with {:ok, active_basis?} <-
           active_directory_basis?(principal_id, provider_tenant) do
      if active_basis?,
        do: :ok,
        else: disable_sso_links(principal_id, provider_tenant, disabled_at)
    end
  end

  defp active_directory_basis?(principal_id, provider_tenant) do
    ExternalIdentityLink
    |> Ash.Query.filter(
      principal_id == ^principal_id and provider == "workos_directory" and
        provider_tenant == ^provider_tenant and status == "active" and
        linking_state == "linked"
    )
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.lock(:for_update)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, links} -> {:ok, links != []}
      {:error, _reason} = error -> error
    end
  end

  defp maybe_disable_created_principal(
         %{principal_id: principal_id, principal_origin: "created"},
         %Principal{} = principal
       )
       when is_binary(principal_id) do
    with {:ok, false} <- other_active_identity_basis?(principal_id) do
      principal
      |> Ash.Changeset.for_update(:set_status, %{status: "disabled"})
      |> Ash.update(authorize?: false)
      |> normalize_ok()
    else
      {:ok, true} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp maybe_disable_created_principal(_attrs, _principal), do: :ok

  defp other_active_identity_basis?(principal_id) do
    ExternalIdentityLink
    |> Ash.Query.filter(
      principal_id == ^principal_id and status == "active" and linking_state == "linked"
    )
    |> Ash.exists(authorize?: false)
  end

  defp locked_link(link_id) do
    ExternalIdentityLink
    |> Ash.Query.filter(id == ^link_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp locked_principal(nil), do: {:ok, nil}

  defp locked_principal(principal_id) when is_binary(principal_id) do
    Principal
    |> Ash.Query.filter(id == ^principal_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp normalize_ok({:ok, _record}), do: :ok
  defp normalize_ok({:error, _reason} = error), do: error
end

defmodule OfficeGraph.Identity.Actions.ReconcileWorkOSSsoIdentity do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.Identity.{
    DirectoryIdentityResult,
    ExternalIdentityLink,
    Principal
  }

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    attrs = input.arguments

    with {:ok, principals} <- locked_principals_for_email(attrs.verified_email),
         {:ok, subject_link} <-
           locked_subject_link(attrs.provider_tenant, attrs.subject),
         {:ok, email_links} <- locked_links_for_email(attrs.verified_email) do
      reconcile(subject_link, principals, email_links, attrs)
    end
  end

  defp reconcile(
         %ExternalIdentityLink{
           status: "active",
           linking_state: "linked",
           principal_id: principal_id,
           verified_email: verified_email
         } = link,
         principals,
         email_links,
         attrs
       )
       when is_binary(principal_id) do
    with true <- verified_email == attrs.verified_email,
         %Principal{kind: "human", status: "active"} = principal <-
           Enum.find(principals, &(&1.id == principal_id)),
         true <- compatible_links?(email_links, principal.id) do
      with {:ok, authenticated_link} <-
             link
             |> Ash.Changeset.for_update(:record_authentication, %{
               last_authenticated_at: DateTime.utc_now()
             })
             |> Ash.update(authorize?: false) do
        DirectoryIdentityResult.linked(principal, authenticated_link, "reused")
      end
    else
      _conflict -> DirectoryIdentityResult.review_required("verified_identifier_conflict")
    end
  end

  defp reconcile(%ExternalIdentityLink{}, _principals, _email_links, _attrs),
    do: DirectoryIdentityResult.review_required("provider_subject_conflict")

  defp reconcile(
         nil,
         [%Principal{kind: "human", status: "active"} = principal],
         email_links,
         attrs
       ) do
    if compatible_new_subject_links?(email_links, principal.id) do
      with {:ok, link} <- create_sso_link(principal, attrs) do
        DirectoryIdentityResult.linked(principal, link, "reused")
      end
    else
      DirectoryIdentityResult.review_required("verified_identifier_conflict")
    end
  end

  defp reconcile(nil, [_ineligible], _email_links, _attrs),
    do: DirectoryIdentityResult.review_required("ineligible_principal")

  defp reconcile(nil, _ambiguous_or_missing, _email_links, _attrs),
    do: DirectoryIdentityResult.review_required("ambiguous_verified_identifier")

  defp compatible_links?(links, principal_id) do
    Enum.all?(links, fn link ->
      link.principal_id == principal_id and link.status in ["active", "disabled"] and
        link.linking_state == "linked"
    end)
  end

  defp compatible_new_subject_links?(links, principal_id) do
    Enum.all?(links, fn link ->
      link.principal_id == principal_id and link.status == "active" and
        link.linking_state == "linked"
    end)
  end

  defp create_sso_link(principal, attrs) do
    now = DateTime.utc_now()

    ExternalIdentityLink
    |> Ash.Changeset.for_create(:create, %{
      principal_id: principal.id,
      provider: "workos_sso",
      provider_tenant: attrs.provider_tenant,
      subject: attrs.subject,
      verified_email: attrs.verified_email,
      status: "active",
      linking_state: "linked",
      first_linked_at: now,
      last_authenticated_at: now
    })
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> consume_notifications()
  end

  defp locked_subject_link(provider_tenant, subject) do
    ExternalIdentityLink
    |> Ash.Query.filter(
      provider == "workos_sso" and provider_tenant == ^provider_tenant and
        subject == ^subject
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp locked_links_for_email(email) do
    ExternalIdentityLink
    |> Ash.Query.filter(verified_email == ^email)
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.lock(:for_update)
    |> Ash.read(authorize?: false)
  end

  defp locked_principals_for_email(email) do
    Principal
    |> Ash.Query.filter(email == ^email)
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.lock(:for_update)
    |> Ash.read(authorize?: false)
  end

  defp consume_notifications({:ok, record, _notifications}), do: {:ok, record}
  defp consume_notifications({:error, error}), do: {:error, error}
end
