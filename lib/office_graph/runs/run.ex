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
    uuid_primary_key :id, writable?: true
    attribute :organization_id, :uuid, allow_nil?: true, public?: true
    attribute :workspace_id, :uuid, allow_nil?: true, public?: true
    attribute :work_packet_id, :uuid, allow_nil?: false, public?: true
    attribute :work_packet_version_id, :uuid, allow_nil?: true, public?: true
    attribute :operation_id, :uuid, allow_nil?: true, public?: true
    attribute :initiator_principal_id, :uuid, allow_nil?: true, public?: true
    attribute :objective, :string, allow_nil?: true, public?: true
    attribute :authority_posture, :string, allow_nil?: true, public?: true
    attribute :source_surface, :string, allow_nil?: true, public?: true
    attribute :reason, :string, allow_nil?: true, public?: true
    attribute :aggregate_state, :string, allow_nil?: true, public?: true
    attribute :execution_state, :string, allow_nil?: true, public?: true
    attribute :verification_state, :string, allow_nil?: true, public?: true
    attribute :started_at, :utc_datetime_usec, allow_nil?: true, public?: true
    attribute :completed_at, :utc_datetime_usec, allow_nil?: true, public?: true
    attribute :state, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    read :read do
      primary? true
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
        :reason,
        :aggregate_state,
        :execution_state,
        :verification_state,
        :started_at,
        :completed_at,
        :state
      ]

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                work_packet_id: OfficeGraph.WorkPackets.WorkPacket,
                work_packet_version_id: OfficeGraph.WorkPackets.WorkPacketVersion,
                operation_id: OfficeGraph.Operations.OperationCorrelation
              ]}

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
    type :work_run
  end

  json_api do
    type "work_run"
  end
end
