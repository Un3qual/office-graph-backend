defmodule OfficeGraph.WorkGraph.EvidenceCandidate do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "evidence_candidates"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_operation: "evidence_candidates_operation_id_unique_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :step_key, :string, public?: true
    attribute :claim, :string, allow_nil?: false, public?: true
    attribute :source_kind, :string, allow_nil?: false, public?: true
    attribute :source_identity, :string, allow_nil?: false, public?: true
    attribute :freshness_state, :string, allow_nil?: false, public?: true
    attribute :trust_basis, :string, allow_nil?: false, public?: true
    attribute :sensitivity, :string, allow_nil?: false, public?: true
    attribute :candidate_state, :string, allow_nil?: false, public?: true
    attribute :rejection_reason, :string, allow_nil?: true, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :verification_check, OfficeGraph.WorkGraph.VerificationCheck do
      source_attribute :verification_check_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :artifact, OfficeGraph.WorkGraph.Artifact do
      source_attribute :artifact_id
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :context_package, OfficeGraph.AgentRuntime.ContextPackage do
      source_attribute :context_package_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :execution, OfficeGraph.AgentRuntime.AgentExecution do
      source_attribute :execution_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :execution_observation, OfficeGraph.Runs.ExecutionObservation do
      source_attribute :execution_observation_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :work_run, OfficeGraph.Runs.Run do
      source_attribute :work_run_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    has_many :evidence_items, OfficeGraph.WorkGraph.EvidenceItem do
      source_attribute :id
      destination_attribute :candidate_id
    end
  end

  actions do
    defaults [:read]

    read :read_for_accept_command do
      public? false
    end

    create :create do
      public? false

      accept [
        :id,
        :organization_id,
        :workspace_id,
        :verification_check_id,
        :work_run_id,
        :execution_observation_id,
        :artifact_id,
        :operation_id,
        :execution_id,
        :context_package_id,
        :step_key,
        :claim,
        :source_kind,
        :source_identity,
        :freshness_state,
        :trust_basis,
        :sensitivity
      ]

      change set_attribute(:candidate_state, "candidate")
      change set_attribute(:rejection_reason, nil)

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                verification_check_id: OfficeGraph.WorkGraph.VerificationCheck,
                artifact_id: OfficeGraph.WorkGraph.Artifact,
                operation_id: OfficeGraph.Operations.OperationCorrelation
              ]}

      change OfficeGraph.WorkGraph.Changes.ValidateEvidenceCandidateReferences
    end

    update :mark_accepted do
      public? false
      accept []
      change set_attribute(:candidate_state, "accepted")
    end
  end

  identities do
    identity :unique_operation, [:operation_id]
  end

  policies do
    policy action(:read) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :skeleton_read}
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
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :evidence_candidate_create}
    end
  end

  graphql do
    type :evidence_candidate
  end

  json_api do
    type "evidence_candidate"
  end
end
