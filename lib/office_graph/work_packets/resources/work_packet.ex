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
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :title, :string, allow_nil?: false, public?: true
    attribute :state, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      attribute_public? true
    end

    belongs_to :current_version, OfficeGraph.WorkPackets.WorkPacketVersion do
      source_attribute :current_version_id
      attribute_public? true
      public? true
    end

    has_many :versions, OfficeGraph.WorkPackets.WorkPacketVersion do
      destination_attribute :work_packet_id
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

    read :read_for_version_command do
      public? false
    end

    create :create do
      public? false

      accept [
        :id,
        :organization_id,
        :workspace_id,
        :operation_id,
        :title
      ]

      change set_attribute(:state, "draft")

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                operation_id: OfficeGraph.Operations.OperationCorrelation
              ]}
    end

    update :set_current_version do
      public? false
      require_atomic? false
      accept [:current_version_id]

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                current_version_id: OfficeGraph.WorkPackets.WorkPacketVersion
              ]}

      change OfficeGraph.WorkPackets.Changes.ValidateCurrentVersion
    end

    action :create_work_packet,
           OfficeGraph.WorkPackets.CommandResults.PacketMutation do
      argument :idempotency_key, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      argument :title, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :objective, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :context_summary, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :requirements, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :success_criteria, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :autonomy_posture, :string, allow_nil?: false, constraints: [match: ~r/\S/]

      argument :source_graph_item_ids, {:array, :uuid}, allow_nil?: false

      argument :verification_check_ids, {:array, :uuid}, allow_nil?: false

      run OfficeGraph.WorkPackets.Actions.CreateWorkPacket
    end

    action :create_work_packet_version,
           OfficeGraph.WorkPackets.CommandResults.PacketMutation do
      argument :idempotency_key, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      argument :packet_id, :uuid, allow_nil?: false
      argument :expected_current_version_id, :uuid, allow_nil?: false
      argument :title, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :objective, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :context_summary, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :requirements, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :success_criteria, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :autonomy_posture, :string, allow_nil?: false, constraints: [match: ~r/\S/]

      argument :source_graph_item_ids, {:array, :uuid}, allow_nil?: false

      argument :verification_check_ids, {:array, :uuid}, allow_nil?: false

      run OfficeGraph.WorkPackets.Actions.CreateWorkPacketVersion
    end
  end

  identities do
    identity :unique_operation, [:operation_id], where: expr(not is_nil(operation_id))
  end

  policies do
    policy action(:read) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :skeleton_read}
    end

    policy action(:read_for_version_command) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :work_packet_version_create}
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

    policy action(:create_work_packet) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :work_packet_create}
    end

    policy action(:create_work_packet_version) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :work_packet_version_create}
    end
  end

  graphql do
    type :work_packet
    paginate_relationship_with(versions: :relay)
  end

  json_api do
    type "work_packet"
  end
end
