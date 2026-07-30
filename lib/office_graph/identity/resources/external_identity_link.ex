defmodule OfficeGraph.Identity.ReconciliationResult do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :status, :string, allow_nil?: false
    field :reason, :string

    field :principal, :struct, constraints: [instance_of: OfficeGraph.Identity.Principal]

    field :external_identity_link, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.Identity.ExternalIdentityLink]
  end

  def authenticated(principal, external_identity_link) do
    new(
      status: "authenticated",
      principal: principal,
      external_identity_link: external_identity_link
    )
  end

  def rejected(reason, external_identity_link) do
    new(
      status: "rejected",
      reason: Atom.to_string(reason),
      external_identity_link: external_identity_link
    )
  end

  def to_public_result(%__MODULE__{
        status: "authenticated",
        principal: principal,
        external_identity_link: external_identity_link
      }) do
    {:ok, %{principal: principal, external_identity_link: external_identity_link}}
  end

  def to_public_result(%__MODULE__{
        status: "rejected",
        reason: reason,
        external_identity_link: external_identity_link
      }) do
    {:error, String.to_existing_atom(reason), %{external_identity_link: external_identity_link}}
  end
end

defmodule OfficeGraph.Identity.Actions.ReconcileExternalIdentity do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.Identity.{ExternalIdentityLink, Principal, ReconciliationResult}

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    identity = %{
      subject: input.arguments.subject,
      verified_email: input.arguments.verified_email
    }

    config = %{
      provider: input.arguments.provider,
      provider_tenant: input.arguments.provider_tenant
    }

    with {:ok, principals} <- principals_for_email(identity.verified_email),
         {:ok, email_links} <- external_links_for_email(identity.verified_email),
         {:ok, subject_link} <- external_identity_link(config, identity.subject) do
      reconcile(subject_link, identity, config, principals, email_links)
    end
  end

  defp reconcile(nil, identity, config, principals, email_links) do
    reconcile_new_identity(identity, config, principals, email_links)
  end

  defp reconcile(link, identity, _config, principals, email_links) do
    reconcile_existing_identity(link, identity, principals, email_links)
  end

  defp reconcile_existing_identity(
         %ExternalIdentityLink{status: "review_required"} = link,
         _identity,
         _principals,
         _email_links
       ) do
    ReconciliationResult.rejected(:identity_review_required, link)
  end

  defp reconcile_existing_identity(
         %ExternalIdentityLink{status: "disabled"} = link,
         _identity,
         _principals,
         _email_links
       ) do
    ReconciliationResult.rejected(:identity_disabled, link)
  end

  defp reconcile_existing_identity(
         %ExternalIdentityLink{
           status: "active",
           linking_state: "linked",
           principal_id: principal_id
         } = link,
         identity,
         principals,
         email_links
       ) do
    case locked_principal(principal_id) do
      {:ok, %Principal{kind: "human", status: "active"} = principal} ->
        if verified_identifier_compatible?(link, identity, principals, email_links) do
          with {:ok, authenticated_link} <-
                 update(link, :record_authentication, %{
                   last_authenticated_at: DateTime.utc_now()
                 }) do
            ReconciliationResult.authenticated(principal, authenticated_link)
          end
        else
          with {:ok, reviewed_link} <-
                 update(link, :set_lifecycle, %{
                   status: "review_required",
                   linking_state: "review_required",
                   review_reason: "verified_identifier_conflict"
                 }) do
            ReconciliationResult.rejected(:identity_review_required, reviewed_link)
          end
        end

      {:ok, _ineligible_or_inactive} ->
        ReconciliationResult.rejected(:principal_disabled, link)

      {:error, error} ->
        {:error, error}
    end
  end

  defp verified_identifier_compatible?(
         %ExternalIdentityLink{verified_email: verified_email},
         %{verified_email: verified_email},
         _principals,
         _email_links
       ),
       do: true

  defp verified_identifier_compatible?(link, _identity, principals, email_links) do
    email_links == [] and
      case principals do
        [] -> true
        [%Principal{id: principal_id}] -> principal_id == link.principal_id
        _conflicting_principals -> false
      end
  end

  defp reconcile_new_identity(identity, config, principals, []) do
    link_verified_principal(identity, config, principals)
  end

  defp reconcile_new_identity(identity, config, _principals, _incompatible_links) do
    persist_review_link(identity, config, "verified_identifier_conflict")
  end

  defp link_verified_principal(identity, config, []) do
    persist_review_link(identity, config, "unlinked_verified_identifier")
  end

  defp link_verified_principal(
         identity,
         config,
         [%Principal{kind: "human", status: "active"} = principal]
       ) do
    now = DateTime.utc_now()

    with {:ok, link} <-
           create_link(%{
             principal_id: principal.id,
             provider: config.provider,
             provider_tenant: config.provider_tenant,
             subject: identity.subject,
             verified_email: identity.verified_email,
             status: "active",
             linking_state: "linked",
             first_linked_at: now,
             last_authenticated_at: now
           }) do
      ReconciliationResult.authenticated(principal, link)
    end
  end

  defp link_verified_principal(identity, config, [%Principal{}]) do
    persist_review_link(identity, config, "ineligible_principal")
  end

  defp link_verified_principal(identity, config, _ambiguous_principals) do
    persist_review_link(identity, config, "ambiguous_verified_identifier")
  end

  defp persist_review_link(identity, config, reason) do
    with {:ok, link} <-
           create_link(%{
             provider: config.provider,
             provider_tenant: config.provider_tenant,
             subject: identity.subject,
             verified_email: identity.verified_email,
             status: "review_required",
             linking_state: "review_required",
             review_reason: reason
           }) do
      ReconciliationResult.rejected(:identity_review_required, link)
    end
  end

  defp external_identity_link(config, subject) do
    ExternalIdentityLink
    |> Ash.Query.filter(
      provider == ^config.provider and provider_tenant == ^config.provider_tenant and
        subject == ^subject
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp external_links_for_email(verified_email) do
    ExternalIdentityLink
    |> Ash.Query.filter(verified_email == ^verified_email)
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.lock(:for_update)
    |> Ash.read(authorize?: false)
  end

  defp principals_for_email(verified_email) do
    Principal
    |> Ash.Query.filter(string_downcase(string_trim(email)) == ^verified_email)
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.lock(:for_update)
    |> Ash.read(authorize?: false)
  end

  defp locked_principal(principal_id) do
    Principal
    |> Ash.Query.filter(id == ^principal_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp create_link(attrs) do
    ExternalIdentityLink
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> consume_notifications()
  end

  defp update(record, action, attrs) do
    record
    |> Ash.Changeset.for_update(action, attrs)
    |> Ash.update(authorize?: false, return_notifications?: true)
    |> consume_notifications()
  end

  defp consume_notifications({:ok, record, _notifications}), do: {:ok, record}
  defp consume_notifications({:error, error}), do: {:error, error}
end

defmodule OfficeGraph.Identity.ExternalIdentityLink do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Identity.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "external_identity_links"
    repo OfficeGraph.Repo

    identity_index_names provider_subject:
                           "external_identity_links_provider_provider_tenant_subject_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :provider, :string, allow_nil?: false, public?: true
    attribute :provider_tenant, :string, allow_nil?: false, public?: true
    attribute :subject, :string, allow_nil?: false, public?: true
    attribute :verified_email, :string, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true
    attribute :linking_state, :string, allow_nil?: false, public?: true
    attribute :review_reason, :string, public?: true
    attribute :first_linked_at, :utc_datetime_usec, public?: true
    attribute :last_authenticated_at, :utc_datetime_usec, public?: true
    attribute :disabled_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :principal, OfficeGraph.Identity.Principal do
      source_attribute :principal_id
      destination_attribute :id
      attribute_public? true
    end

    has_many :sessions, OfficeGraph.Identity.Session do
      source_attribute :id
      destination_attribute :external_identity_link_id
    end

    has_many :authentication_events, OfficeGraph.Identity.AuthenticationEvent do
      source_attribute :id
      destination_attribute :external_identity_link_id
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :id,
        :principal_id,
        :provider,
        :provider_tenant,
        :subject,
        :verified_email,
        :status,
        :linking_state,
        :review_reason,
        :first_linked_at,
        :last_authenticated_at,
        :disabled_at
      ]

      validate one_of(:status, ~w(active review_required disabled))
      validate one_of(:linking_state, ~w(linked review_required))
    end

    update :record_authentication do
      accept [:last_authenticated_at]
    end

    update :set_lifecycle do
      accept [:status, :linking_state, :review_reason, :disabled_at, :principal_id]

      validate one_of(:status, ~w(active review_required disabled)),
        where: [changing(:status)]

      validate one_of(:linking_state, ~w(linked review_required)),
        where: [changing(:linking_state)]

      require_atomic? false
    end

    action :reconcile_oidc_identity, OfficeGraph.Identity.ReconciliationResult do
      public? false
      transaction? true
      touches_resources [OfficeGraph.Identity.Principal]

      argument :provider, :string, allow_nil?: false
      argument :provider_tenant, :string, allow_nil?: false
      argument :subject, :string, allow_nil?: false
      argument :verified_email, :string, allow_nil?: false

      run OfficeGraph.Identity.Actions.ReconcileExternalIdentity
    end

    action :reconcile_directory_identity,
           Module.concat([OfficeGraph, Identity, DirectoryIdentityResult]) do
      public? false
      transaction? true
      touches_resources [OfficeGraph.Identity.Principal]

      argument :provider_tenant, :string, allow_nil?: false
      argument :subject, :string, allow_nil?: false
      argument :verified_email, :string, allow_nil?: false
      argument :current_principal_id, :uuid
      argument :current_principal_origin, :string

      run Module.concat([OfficeGraph, Identity, Actions, ReconcileDirectoryIdentity])
    end

    action :deprovision_directory_identity,
           Module.concat([OfficeGraph, Identity, DirectoryIdentityResult]) do
      public? false
      transaction? true
      touches_resources [OfficeGraph.Identity.Principal]

      argument :provider_tenant, :string, allow_nil?: false
      argument :principal_id, :uuid
      argument :external_identity_link_id, :uuid
      argument :principal_origin, :string
      argument :disabled_at, :utc_datetime_usec, allow_nil?: false

      run Module.concat([OfficeGraph, Identity, Actions, DeprovisionDirectoryIdentity])
    end

    action :reconcile_workos_sso_identity,
           Module.concat([OfficeGraph, Identity, DirectoryIdentityResult]) do
      public? false
      transaction? true
      touches_resources [OfficeGraph.Identity.Principal]

      argument :provider_tenant, :string, allow_nil?: false
      argument :subject, :string, allow_nil?: false
      argument :verified_email, :string, allow_nil?: false

      run Module.concat([OfficeGraph, Identity, Actions, ReconcileWorkOSSsoIdentity])
    end
  end

  identities do
    identity :provider_subject, [:provider, :provider_tenant, :subject]
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(principal_id == ^actor(:principal_id))
    end
  end
end
