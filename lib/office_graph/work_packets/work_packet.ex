defmodule OfficeGraph.WorkPackets.WorkPacket do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkPackets.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "work_packets"
    repo OfficeGraph.Repo
    migrate? false

    foreign_key_names organization_id: "work_packets_organization_id_fkey",
                      workspace_id: "work_packets_workspace_id_fkey"

    identity_index_names unique_operation: "work_packets_operation_id_unique_index"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :operation_id, :uuid, allow_nil?: true, public?: true
    attribute :current_version_id, :uuid, allow_nil?: true, public?: true
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :state, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      define_attribute? false
    end

    belongs_to :current_version, OfficeGraph.WorkPackets.WorkPacketVersion do
      source_attribute :current_version_id
      define_attribute? false
    end

    has_many :versions, OfficeGraph.WorkPackets.WorkPacketVersion do
      destination_attribute :work_packet_id
    end
  end

  actions do
    read :read do
      primary? true
    end

    create :create do
      public? false

      accept [
        :id,
        :organization_id,
        :workspace_id,
        :operation_id,
        :title,
        :state
      ]

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                operation_id: OfficeGraph.Operations.OperationCorrelation
              ]}
    end

    update :set_current_version do
      public? false
      require_atomic? false
      accept [:current_version_id, :state]

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                current_version_id: OfficeGraph.WorkPackets.WorkPacketVersion
              ]}

      change OfficeGraph.WorkPackets.Changes.ValidateCurrentVersion
    end
  end

  identities do
    identity :unique_operation, [:operation_id], where: expr(not is_nil(operation_id))
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
    type :work_packet
  end

  json_api do
    type "work_packet"
  end
end
