defmodule OfficeGraph.Runs.CommandResults.StartWorkRun do
  @moduledoc false

  alias OfficeGraph.CommandSupport.TypedId

  use Ash.TypedStruct

  typed_struct do
    field :command, :string, allow_nil?: false
    field :operation_id, :uuid, allow_nil?: false
    field :affected_ids, {:array, TypedId}, allow_nil?: false

    field :run, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.Runs.Run]

    field :required_checks, {:array, :struct},
      allow_nil?: false,
      constraints: [items: [instance_of: OfficeGraph.Runs.RunRequiredCheck]]
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :start_work_run_payload

  def from_result(operation, result) do
    new(
      command: "start_work_run",
      operation_id: operation.id,
      affected_ids:
        [TypedId.new!(type: "work_run", id: result.run.id)] ++
          Enum.map(
            result.required_checks,
            &TypedId.new!(type: "run_required_check", id: &1.id)
          ),
      run: result.run,
      required_checks: result.required_checks
    )
  end
end

defimpl Jason.Encoder, for: OfficeGraph.Runs.CommandResults.StartWorkRun do
  def encode(result, options) do
    Jason.Encode.map(
      %{
        command: result.command,
        operation_id: result.operation_id,
        affected_ids: result.affected_ids,
        run: run_result(result.run),
        required_checks: Enum.map(result.required_checks, &required_check_result/1)
      },
      options
    )
  end

  defp run_result(run) do
    %{
      id: run.id,
      work_packet_version_id: run.work_packet_version_id,
      execution_state: run.execution_state,
      verification_state: run.verification_state,
      aggregate_state: run.aggregate_state
    }
  end

  defp required_check_result(required_check) do
    %{
      id: required_check.id,
      verification_check_id: required_check.verification_check_id,
      state: required_check.state
    }
  end
end

defmodule OfficeGraph.Runs.CommandResults.RecordExecutionObservation do
  @moduledoc false

  alias OfficeGraph.CommandSupport.TypedId

  use Ash.TypedStruct

  typed_struct do
    field :command, :string, allow_nil?: false
    field :operation_id, :uuid, allow_nil?: false
    field :affected_ids, {:array, TypedId}, allow_nil?: false

    field :observation, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.Runs.ExecutionObservation]

    field :run, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.Runs.Run]
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :record_execution_observation_payload

  def from_result(operation, result) do
    new(
      command: "record_execution_observation",
      operation_id: operation.id,
      affected_ids: [
        TypedId.new!(type: "execution_observation", id: result.observation.id),
        TypedId.new!(type: "work_run", id: result.run.id)
      ],
      observation: result.observation,
      run: result.run
    )
  end
end

defimpl Jason.Encoder, for: OfficeGraph.Runs.CommandResults.RecordExecutionObservation do
  def encode(result, options) do
    Jason.Encode.map(
      %{
        command: result.command,
        operation_id: result.operation_id,
        affected_ids: result.affected_ids,
        observation: %{
          id: result.observation.id,
          normalized_status: result.observation.normalized_status
        },
        run: %{
          id: result.run.id,
          work_packet_version_id: result.run.work_packet_version_id,
          execution_state: result.run.execution_state,
          verification_state: result.run.verification_state,
          aggregate_state: result.run.aggregate_state
        }
      },
      options
    )
  end
end

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
      public? true
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
      public? true
    end

    has_many :execution_observations, OfficeGraph.Runs.ExecutionObservation do
      destination_attribute :work_run_id
      public? true
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
      public? true
    end

    has_many :evidence_items, OfficeGraph.WorkGraph.EvidenceItem do
      source_attribute :id
      destination_attribute :work_run_id
      public? true
    end

    has_many :verification_results, OfficeGraph.WorkGraph.VerificationResult do
      source_attribute :id
      destination_attribute :work_run_id
      public? true
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

    action :start_work_run,
           OfficeGraph.Runs.CommandResults.StartWorkRun do
      argument :idempotency_key, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      argument :packet_version_id, :uuid, allow_nil?: false
      argument :source_surface, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :reason, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :authority_posture, :string, allow_nil?: false, constraints: [match: ~r/\S/]

      run fn input, context ->
        OfficeGraph.Runs.Actions.StartWorkRun.run(input, [], context)
      end
    end

    action :record_execution_observation,
           OfficeGraph.Runs.CommandResults.RecordExecutionObservation do
      argument :idempotency_key, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      argument :run_id, :uuid, allow_nil?: false
      argument :verification_check_id, :uuid, allow_nil?: false
      argument :source_graph_item_id, :uuid, allow_nil?: false

      argument :observation_source_kind, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      argument :observation_source_identity, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      argument :observation_idempotency_key, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      argument :observed_status, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :normalized_status, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :freshness_state, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :trust_basis, :string, allow_nil?: false, constraints: [match: ~r/\S/]

      argument :observation_rationale, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      run fn input, context ->
        OfficeGraph.Runs.Actions.RecordExecutionObservation.run(input, [], context)
      end
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

    policy action(:start_work_run) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :work_run_start}
    end

    policy action(:record_execution_observation) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :execution_observation_record}
    end
  end

  graphql do
    type :work_run

    paginate_relationship_with(
      required_checks: :relay,
      execution_observations: :relay,
      evidence_candidates: :relay,
      evidence_items: :relay,
      verification_results: :relay
    )
  end

  json_api do
    type "work_run"
  end
end
