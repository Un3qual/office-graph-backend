defmodule OfficeGraph.Identity.AuthenticationEvent do
  @moduledoc false

  @reason_codes ~w(
    authentication_failed
    authentication_unavailable
    authorization_storage_unavailable
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

  use Ash.Resource,
    domain: OfficeGraph.Identity.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "authentication_events"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :principal_id, :uuid, public?: true
    attribute :external_identity_link_id, :uuid, public?: true
    attribute :session_id, :uuid, public?: true
    attribute :organization_id, :uuid, public?: true
    attribute :workspace_id, :uuid, public?: true
    attribute :event, :string, allow_nil?: false, public?: true
    attribute :result, :string, allow_nil?: false, public?: true
    attribute :reason, :string, allow_nil?: false, public?: true
    attribute :authentication_method, :string, allow_nil?: false, public?: true
    attribute :source_surface, :string, allow_nil?: false, public?: true
    attribute :trace_id, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
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

      validate one_of(:reason, @reason_codes)
    end
  end
end
