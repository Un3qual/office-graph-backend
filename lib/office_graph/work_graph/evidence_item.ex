defmodule OfficeGraph.WorkGraph.EvidenceItem do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "evidence_items"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_acceptance_operation:
                           "evidence_items_acceptance_operation_id_unique_index"
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :graph_item_id, :uuid, allow_nil?: false, public?: true
    attribute :verification_check_id, :uuid, allow_nil?: false, public?: true
    attribute :artifact_id, :uuid, allow_nil?: true, public?: true
    attribute :body_document_id, :uuid, allow_nil?: false, public?: true
    attribute :candidate_id, :uuid, allow_nil?: true, public?: true
    attribute :work_run_id, :uuid, allow_nil?: true, public?: true
    attribute :accepted_by_principal_id, :uuid, allow_nil?: true, public?: true
    attribute :acceptance_operation_id, :uuid, allow_nil?: true, public?: true
    attribute :acceptance_policy_basis, :string, allow_nil?: true, public?: true
    attribute :accepted_at, :utc_datetime_usec, allow_nil?: true, public?: true
    attribute :visibility_constraints, :map, allow_nil?: false, public?: true, default: %{}
    attribute :sensitivity, :string, allow_nil?: true, public?: true
    attribute :freshness_state, :string, allow_nil?: true, public?: true
    attribute :trust_basis, :string, allow_nil?: true, public?: true
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :state, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :graph_item, OfficeGraph.WorkGraph.GraphItem do
      source_attribute :graph_item_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :verification_check, OfficeGraph.WorkGraph.VerificationCheck do
      source_attribute :verification_check_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :artifact, OfficeGraph.WorkGraph.Artifact do
      source_attribute :artifact_id
      define_attribute? false
    end

    belongs_to :body_document, OfficeGraph.Content.Document do
      source_attribute :body_document_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :candidate, OfficeGraph.WorkGraph.EvidenceCandidate do
      source_attribute :candidate_id
      define_attribute? false
    end

    belongs_to :acceptance_operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :acceptance_operation_id
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
        :graph_item_id,
        :verification_check_id,
        :artifact_id,
        :body_document_id,
        :candidate_id,
        :work_run_id,
        :accepted_by_principal_id,
        :acceptance_operation_id,
        :acceptance_policy_basis,
        :accepted_at,
        :visibility_constraints,
        :sensitivity,
        :freshness_state,
        :trust_basis,
        :title
      ]

      change set_attribute(:state, "accepted")

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                graph_item_id:
                  {OfficeGraph.WorkGraph.GraphItem,
                   resource_type: "evidence_item", resource_id: :id},
                verification_check_id: OfficeGraph.WorkGraph.VerificationCheck,
                artifact_id: OfficeGraph.WorkGraph.Artifact,
                body_document_id: OfficeGraph.Content.Document
              ]}
    end
  end

  identities do
    identity :unique_acceptance_operation, [:acceptance_operation_id],
      where: expr(not is_nil(acceptance_operation_id))
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
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :evidence_link}
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :evidence_accept}
    end
  end

  graphql do
    type :evidence_item
  end

  json_api do
    type "evidence_item"
  end
end
