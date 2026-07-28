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
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

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
      allow_nil? false
      attribute_public? true
    end

    belongs_to :evidence_item, OfficeGraph.WorkGraph.EvidenceItem do
      source_attribute :evidence_item_id
      allow_nil? true
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :target_graph_item, OfficeGraph.WorkGraph.GraphItem do
      source_attribute :target_graph_item_id
      attribute_public? true
    end

    belongs_to :actor_principal, OfficeGraph.Identity.Principal do
      source_attribute :actor_principal_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :work_packet_version, OfficeGraph.WorkPackets.WorkPacketVersion do
      source_attribute :work_packet_version_id
      destination_attribute :id
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
