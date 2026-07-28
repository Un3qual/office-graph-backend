defmodule OfficeGraph.Runs.Run do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Runs.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "runs"
    repo OfficeGraph.Repo
    migrate? false

    foreign_key_names work_packet_id: "runs_work_packet_id_fkey"

    identity_index_names unique_operation: "runs_operation_id_unique_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :objective, :string, allow_nil?: true, public?: true
    attribute :authority_posture, :string, allow_nil?: true, public?: true
    attribute :source_surface, :string, allow_nil?: true, public?: true
    attribute :reason, :string, allow_nil?: true, public?: true
    attribute :aggregate_state, :string, allow_nil?: false, public?: true
    attribute :execution_state, :string, allow_nil?: false, public?: true
    attribute :verification_state, :string, allow_nil?: false, public?: true
    attribute :started_at, :utc_datetime_usec, allow_nil?: true, public?: true
    attribute :completed_at, :utc_datetime_usec, allow_nil?: true, public?: true
    attribute :state, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :work_packet, OfficeGraph.WorkPackets.WorkPacket do
      source_attribute :work_packet_id
      allow_nil? false
      attribute_public? true
      public? true
    end

    belongs_to :work_packet_version, OfficeGraph.WorkPackets.WorkPacketVersion do
      source_attribute :work_packet_version_id
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      attribute_public? true
    end

    belongs_to :initiator_principal, OfficeGraph.Identity.Principal do
      source_attribute :initiator_principal_id
      attribute_public? true
    end

    has_many :required_checks, OfficeGraph.Runs.RunRequiredCheck do
      destination_attribute :run_id
    end

    has_many :execution_observations, OfficeGraph.Runs.ExecutionObservation do
      destination_attribute :work_run_id
    end

    has_many :events, OfficeGraph.Runs.RunEvent do
      destination_attribute :run_id
    end

    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      attribute_public? true
    end

    has_many :evidence_candidates, OfficeGraph.WorkGraph.EvidenceCandidate do
      source_attribute :id
      destination_attribute :work_run_id
    end

    has_many :evidence_items, OfficeGraph.WorkGraph.EvidenceItem do
      source_attribute :id
      destination_attribute :work_run_id
    end

    has_many :verification_results, OfficeGraph.WorkGraph.VerificationResult do
      source_attribute :id
      destination_attribute :work_run_id
    end

    has_many :agent_executions, OfficeGraph.AgentRuntime.AgentExecution do
      source_attribute :id
      destination_attribute :run_id
    end

    has_many :conversations, OfficeGraph.NodeConversations.Conversation do
      source_attribute :id
      destination_attribute :run_id
    end
  end

  actions do
    read :read do
      primary? true
      public? true
      pagination keyset?: true, countable: false, required?: false
    end

    read :read_for_observation_command do
      public? false
    end

    read :read_for_waive_command do
      public? false
    end

    create :create do
      public? false

      accept [
        :id,
        :organization_id,
        :workspace_id,
        :work_packet_id,
        :work_packet_version_id,
        :operation_id,
        :initiator_principal_id,
        :objective,
        :authority_posture,
        :source_surface,
        :reason
      ]

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                work_packet_id: OfficeGraph.WorkPackets.WorkPacket,
                work_packet_version_id: OfficeGraph.WorkPackets.WorkPacketVersion,
                operation_id: OfficeGraph.Operations.OperationCorrelation
              ]}

      change OfficeGraph.Runs.Changes.ValidateRunStartContract
      change OfficeGraph.Runs.Changes.DeriveRunInitialLifecycle
    end

    update :set_lifecycle_state do
      public? false

      accept [
        :state,
        :aggregate_state,
        :execution_state,
        :verification_state,
        :completed_at
      ]
    end
  end

  identities do
    identity :unique_operation, [:operation_id], where: expr(not is_nil(operation_id))
  end

  policies do
    policy action(:read) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :skeleton_read}
    end

    policy action(:read_for_observation_command) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :execution_observation_record}
    end

    policy action(:read_for_waive_command) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :verification_waive}
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
    type :work_run
  end

  json_api do
    type "work_run"
  end
end
