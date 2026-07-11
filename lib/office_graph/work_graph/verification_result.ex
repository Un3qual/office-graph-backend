defmodule OfficeGraph.WorkGraph.VerificationResult do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "verification_results"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :verification_check_id, :uuid, allow_nil?: false, public?: true
    attribute :evidence_item_id, :uuid, allow_nil?: true, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :work_run_id, :uuid, allow_nil?: true, public?: true
    attribute :work_packet_version_id, :uuid, allow_nil?: true, public?: true
    attribute :target_graph_item_id, :uuid, allow_nil?: true, public?: true
    attribute :actor_principal_id, :uuid, allow_nil?: true, public?: true
    attribute :policy_basis, :string, allow_nil?: true, public?: true
    attribute :reason, :string, allow_nil?: true, public?: true
    attribute :recorded_at, :utc_datetime_usec, allow_nil?: true, public?: true
    attribute :result, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :verification_check, OfficeGraph.WorkGraph.VerificationCheck do
      source_attribute :verification_check_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :evidence_item, OfficeGraph.WorkGraph.EvidenceItem do
      source_attribute :evidence_item_id
      define_attribute? false
      allow_nil? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :target_graph_item, OfficeGraph.WorkGraph.GraphItem do
      source_attribute :target_graph_item_id
      define_attribute? false
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
        :evidence_item_id,
        :operation_id,
        :work_run_id,
        :work_packet_version_id,
        :target_graph_item_id,
        :actor_principal_id,
        :policy_basis,
        :reason,
        :recorded_at,
        :result
      ]

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                verification_check_id: OfficeGraph.WorkGraph.VerificationCheck,
                evidence_item_id: OfficeGraph.WorkGraph.EvidenceItem,
                operation_id: OfficeGraph.Operations.OperationCorrelation
              ]}

      change OfficeGraph.WorkGraph.VerificationResult.ValidateResultEvidence
    end
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
  end

  graphql do
    type :work_graph_verification_result
  end

  json_api do
    type "verification_result"
  end
end
