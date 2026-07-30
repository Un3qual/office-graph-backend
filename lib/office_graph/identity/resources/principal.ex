defmodule OfficeGraph.Identity.OwnerIdentity do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :principal, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.Identity.Principal]

    field :profile, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.Identity.PrincipalProfile]
  end

  def from_records(principal, profile) do
    new(principal: principal, profile: profile)
  end
end

defmodule OfficeGraph.Identity.Actions.EnsureOwner do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.Identity.{OwnerIdentity, Principal, PrincipalProfile}

  @impl true
  def run(input, _opts, _context) do
    attrs = input.arguments

    with {:ok, principal} <-
           ensure(Principal, %{
             email: attrs.email,
             kind: "human",
             status: "active"
           }),
         {:ok, profile} <-
           ensure(PrincipalProfile, %{
             principal_id: principal.id,
             display_name: attrs.display_name
           }) do
      OwnerIdentity.from_records(principal, profile)
    end
  end

  defp ensure(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:ensure, attrs)
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> case do
      {:ok, record, _notifications} -> {:ok, record}
      {:error, error} -> {:error, error}
    end
  end
end

defmodule OfficeGraph.Identity.Principal do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Identity.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "principals"
    repo OfficeGraph.Repo

    identity_index_names email: "principals_email_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :email, :string, allow_nil?: false, public?: true
    attribute :kind, :string, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    has_one :profile, OfficeGraph.Identity.PrincipalProfile do
      source_attribute :id
      destination_attribute :principal_id
    end

    has_many :credentials, OfficeGraph.Identity.Credential do
      source_attribute :id
      destination_attribute :principal_id
    end

    has_many :sessions, OfficeGraph.Identity.Session do
      source_attribute :id
      destination_attribute :principal_id
    end

    has_many :external_identity_links, OfficeGraph.Identity.ExternalIdentityLink do
      source_attribute :id
      destination_attribute :principal_id
    end

    has_many :authentication_events, OfficeGraph.Identity.AuthenticationEvent do
      source_attribute :id
      destination_attribute :principal_id
    end

    has_many :role_assignments, OfficeGraph.Authorization.RoleAssignment do
      source_attribute :id
      destination_attribute :principal_id
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:id, :email, :kind, :status]
      change OfficeGraph.Identity.Changes.NormalizePrincipalEmail
      validate one_of(:status, ~w(active inactive disabled))
    end

    create :ensure do
      public? false
      accept [:email, :kind, :status]
      upsert? true
      upsert_identity :email
      upsert_fields []
      return_skipped_upsert? true
      change OfficeGraph.Identity.Changes.NormalizePrincipalEmail
      validate one_of(:status, ~w(active inactive disabled))
    end

    update :set_status do
      accept [:status]
      validate one_of(:status, ~w(active inactive disabled))
    end

    action :ensure_owner, OfficeGraph.Identity.OwnerIdentity do
      public? false
      transaction? true
      touches_resources [OfficeGraph.Identity.PrincipalProfile]

      argument :email, :string, allow_nil?: false
      argument :display_name, :string, allow_nil?: false

      run OfficeGraph.Identity.Actions.EnsureOwner
    end

    action :ensure_local_development_identity,
           OfficeGraph.Identity.LocalDevelopmentIdentity do
      public? false
      transaction? true

      touches_resources [
        OfficeGraph.Identity.PrincipalProfile,
        OfficeGraph.Identity.ExternalIdentityLink
      ]

      argument :provider, :string, allow_nil?: false
      argument :provider_tenant, :string, allow_nil?: false
      argument :subject, :string, allow_nil?: false
      argument :email, :string, allow_nil?: false
      argument :display_name, :string, allow_nil?: false
      argument :principal_status, :string, allow_nil?: false
      argument :link_status, :string, allow_nil?: false

      run OfficeGraph.Identity.Actions.EnsureLocalDevelopmentIdentity
    end
  end

  identities do
    identity :email, [:email]
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(id == ^actor(:principal_id))
    end
  end
end
