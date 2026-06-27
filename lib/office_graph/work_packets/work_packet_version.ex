defmodule OfficeGraph.WorkPackets.WorkPacketVersion do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkPackets.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "work_packet_versions"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :work_packet_id, :uuid, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :version_number, :integer, allow_nil?: false, public?: true
    attribute :lifecycle_state, :string, allow_nil?: false, public?: true
    attribute :objective, :string, allow_nil?: false, public?: true
    attribute :context_summary, :string, allow_nil?: false, public?: true
    attribute :requirements, :string, allow_nil?: false, public?: true
    attribute :success_criteria, :string, allow_nil?: true, public?: true
    attribute :autonomy_posture, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :work_packet, OfficeGraph.WorkPackets.WorkPacket do
      source_attribute :work_packet_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      define_attribute? false
      allow_nil? false
    end

    has_many :source_references, OfficeGraph.WorkPackets.WorkPacketSourceReference do
      destination_attribute :work_packet_version_id
    end

    has_many :required_checks, OfficeGraph.WorkPackets.WorkPacketRequiredCheck do
      destination_attribute :work_packet_version_id
    end
  end

  actions do
    defaults [:read]

    create :create do
      public? false

      accept [
        :id,
        :work_packet_id,
        :organization_id,
        :workspace_id,
        :operation_id,
        :version_number,
        :lifecycle_state,
        :objective,
        :context_summary,
        :requirements,
        :success_criteria,
        :autonomy_posture
      ]

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                work_packet_id: OfficeGraph.WorkPackets.WorkPacket,
                operation_id: OfficeGraph.Operations.OperationCorrelation
              ]}
    end
  end

  identities do
    identity :unique_packet_version, [:work_packet_id, :version_number]
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
    type :work_packet_version
  end

  json_api do
    type "work_packet_version"
  end
end
