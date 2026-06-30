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
    uuid_primary_key :id, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :verification_check_id, :uuid, allow_nil?: false, public?: true
    attribute :work_run_id, :uuid, allow_nil?: true, public?: true
    attribute :execution_observation_id, :uuid, allow_nil?: true, public?: true
    attribute :artifact_id, :uuid, allow_nil?: true, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
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
      define_attribute? false
      allow_nil? false
    end

    belongs_to :artifact, OfficeGraph.WorkGraph.Artifact do
      source_attribute :artifact_id
      define_attribute? false
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
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
        :organization_id,
        :workspace_id,
        :verification_check_id,
        :work_run_id,
        :execution_observation_id,
        :artifact_id,
        :operation_id,
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
