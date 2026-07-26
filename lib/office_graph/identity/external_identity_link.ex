defmodule OfficeGraph.Identity.ExternalIdentityLink do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Identity.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "external_identity_links"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :principal_id, :uuid, public?: true
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
