defmodule OfficeGraph.Identity.AuthenticationEvent do
  @moduledoc false

  @reason_codes ~w(
    authentication_failed
    authentication_unavailable
    authorization_storage_unavailable
    directory_provisioning_required
    enterprise_connection_unavailable
    enterprise_identity_storage_unavailable
    identity_disabled
    identity_review_required
    identity_storage_unavailable
    invalid_identity_claims
    invalid_login_transaction
    invalid_scope
    invalid_session
    login_completed
    no_login_scope
    principal_disabled
    provider_unavailable
    scope_selection_required
    session_expired
    session_replaced
    session_revoked
    unverified_identifier
    user_logout
  )
  @event_names ~w(login logout revocation session_validation)
  @result_names ~w(succeeded rejected)

  use Ash.Resource,
    domain: OfficeGraph.Identity.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "authentication_events"
    repo OfficeGraph.Repo

    references do
      reference :workspace do
        name "authentication_events_workspace_scope_fkey"
        match_with organization_id: :organization_id
      end
    end
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :event, :string, allow_nil?: false, public?: true
    attribute :result, :string, allow_nil?: false, public?: true
    attribute :reason, :string, allow_nil?: false, public?: true
    attribute :authentication_method, :string, allow_nil?: false, public?: true
    attribute :source_surface, :string, allow_nil?: false, public?: true
    attribute :trace_id, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :external_identity_link, OfficeGraph.Identity.ExternalIdentityLink do
      source_attribute :external_identity_link_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :principal, OfficeGraph.Identity.Principal do
      source_attribute :principal_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :session, OfficeGraph.Identity.Session do
      source_attribute :session_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      attribute_public? true
    end
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      accept [
        :id,
        :principal_id,
        :external_identity_link_id,
        :session_id,
        :organization_id,
        :workspace_id,
        :event,
        :result,
        :reason,
        :authentication_method,
        :source_surface,
        :trace_id
      ]

      validate one_of(:event, @event_names)
      validate one_of(:result, @result_names)
      validate one_of(:reason, @reason_codes)
    end
  end
end
