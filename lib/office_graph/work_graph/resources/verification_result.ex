defmodule OfficeGraph.WorkGraph.Resources.VerificationResult do
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
    attribute :evidence_item_id, :uuid, allow_nil?: false, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :result, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :id,
        :organization_id,
        :workspace_id,
        :verification_check_id,
        :evidence_item_id,
        :operation_id,
        :result
      ]

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                verification_check_id: OfficeGraph.WorkGraph.VerificationCheck,
                evidence_item_id: OfficeGraph.WorkGraph.EvidenceItem,
                operation_id: OfficeGraph.Operations.OperationCorrelation
              ]}
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

    policy action(:create) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :verification_complete}
    end
  end

  graphql do
    type :verification_result
  end

  json_api do
    type "verification_result"
  end
end
