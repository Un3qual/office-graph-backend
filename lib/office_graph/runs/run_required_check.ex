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
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :position, :integer, allow_nil?: false, default: 0, public?: true
    attribute :state, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :run, OfficeGraph.Runs.Run do
      source_attribute :run_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :verification_check, OfficeGraph.WorkGraph.VerificationCheck do
      source_attribute :verification_check_id
      allow_nil? false
      attribute_public? true
      public? true
    end

    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end
  end

  actions do
    read :read do
      primary? true
      pagination keyset?: true, countable: false, required?: false
    end

    read :read_for_waive_command do
      public? false
    end

    read :read_for_accept_command do
      public? false
    end

    create :create do
      public? false

      accept [
        :id,
        :run_id,
        :verification_check_id,
        :organization_id,
        :workspace_id,
        :position
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

    update :mark_waived do
      public? false
      accept []
      change set_attribute(:state, "waived")
    end
  end

  identities do
    identity :unique_run_check, [:run_id, :verification_check_id]
  end

  policies do
    policy action(:read) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :skeleton_read}
    end

    policy action(:read_for_waive_command) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :verification_waive}
    end

    policy action(:read_for_accept_command) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :evidence_accept}
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
