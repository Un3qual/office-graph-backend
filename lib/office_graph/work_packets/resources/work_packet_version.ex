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
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :version_number, :integer, allow_nil?: false, public?: true
    attribute :lifecycle_state, :string, allow_nil?: false, public?: true
    attribute :title, :string, allow_nil?: false, public?: true
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
      allow_nil? false
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      allow_nil? false
      attribute_public? true
    end

    has_many :source_references, OfficeGraph.WorkPackets.WorkPacketSourceReference do
      destination_attribute :work_packet_version_id
      public? true
    end

    has_many :required_checks, OfficeGraph.WorkPackets.WorkPacketRequiredCheck do
      destination_attribute :work_packet_version_id
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

    has_many :verification_results, OfficeGraph.WorkGraph.VerificationResult do
      source_attribute :id
      destination_attribute :work_packet_version_id
    end

    has_many :runs, OfficeGraph.Runs.Run do
      source_attribute :id
      destination_attribute :work_packet_version_id
    end
  end

  actions do
    read :read do
      primary? true
      pagination keyset?: true, countable: false, required?: false
    end

    read :read_for_run_start_command do
      public? false
    end

    create :create do
      public? false

      argument :source_graph_item_ids, {:array, :uuid}, allow_nil?: false, default: []
      argument :verification_check_ids, {:array, :uuid}, allow_nil?: false, default: []

      accept [
        :id,
        :work_packet_id,
        :organization_id,
        :workspace_id,
        :operation_id,
        :version_number,
        :title,
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

      change OfficeGraph.WorkPackets.Changes.DeriveVersionLifecycleState
    end
  end

  identities do
    identity :unique_packet_version, [:work_packet_id, :version_number]
  end

  policies do
    policy action(:read) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :skeleton_read}
    end

    policy action(:read_for_run_start_command) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :work_run_start}
    end

    policy action_type(:read) do
      authorize_if expr(
                     organization_id == ^actor(:organization_id) and
                       workspace_id == ^actor(:workspace_id)
                   )
    end

    policy action(:create) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :work_packet_version_create}
    end
  end

  graphql do
    type :work_packet_version
  end

  json_api do
    type "work_packet_version"
  end
end
