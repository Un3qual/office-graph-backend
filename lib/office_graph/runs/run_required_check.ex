defmodule OfficeGraph.Runs.RunRequiredCheck do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Runs.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "run_required_checks"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :run_id, :uuid, allow_nil?: false, public?: true
    attribute :verification_check_id, :uuid, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :state, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      public? false

      accept [
        :id,
        :run_id,
        :verification_check_id,
        :organization_id,
        :workspace_id,
        :state
      ]

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                run_id: OfficeGraph.Runs.Run,
                verification_check_id: OfficeGraph.WorkGraph.VerificationCheck
              ]}

      change OfficeGraph.Runs.Changes.ValidateRunRequiredCheckContract
      change set_attribute(:state, "pending")
    end

    update :mark_satisfied do
      public? false
      accept []
      change set_attribute(:state, "satisfied")
    end
  end

  identities do
    identity :unique_run_check, [:run_id, :verification_check_id]
  end

  policies do
    policy action_type(:read) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :skeleton_read}
    end

    policy action_type(:read) do
      authorize_if expr(
                     organization_id == ^actor(:organization_id) and
                       workspace_id == ^actor(:workspace_id)
                   )
    end

    policy action(:create) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :work_run_start}
    end
  end

  graphql do
    type :run_required_check
  end

  json_api do
    type "run_required_check"
  end
end
