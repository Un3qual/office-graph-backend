defmodule OfficeGraph.WorkPackets.WorkPacketRequiredCheck do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkPackets.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "work_packet_version_required_checks"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :work_packet_version_id, :uuid, allow_nil?: false, public?: true
    attribute :verification_check_id, :uuid, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :requirement_kind, :string, allow_nil?: false, public?: true
    attribute :state, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :work_packet_version, OfficeGraph.WorkPackets.WorkPacketVersion do
      source_attribute :work_packet_version_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :verification_check, OfficeGraph.WorkGraph.VerificationCheck do
      source_attribute :verification_check_id
      define_attribute? false
      allow_nil? false
    end
  end

  actions do
    defaults [:read]

    create :create do
      public? false

      accept [
        :id,
        :work_packet_version_id,
        :verification_check_id,
        :organization_id,
        :workspace_id
      ]

      change set_attribute(:requirement_kind, "required")
      change set_attribute(:state, "pending")

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                work_packet_version_id: OfficeGraph.WorkPackets.WorkPacketVersion,
                verification_check_id: OfficeGraph.WorkGraph.VerificationCheck
              ]}
    end
  end

  identities do
    identity :unique_version_check, [:work_packet_version_id, :verification_check_id]
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
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :work_packet_create}
    end
  end

  graphql do
    type :work_packet_required_check
  end

  json_api do
    type "work_packet_required_check"
  end
end
