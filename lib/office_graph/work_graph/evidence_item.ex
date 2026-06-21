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
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :graph_item_id, :uuid, allow_nil?: false, public?: true
    attribute :verification_check_id, :uuid, allow_nil?: false, public?: true
    attribute :artifact_id, :uuid, allow_nil?: true, public?: true
    attribute :body_document_id, :uuid, allow_nil?: false, public?: true
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :state, :string, allow_nil?: false, public?: true

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
        :graph_item_id,
        :verification_check_id,
        :artifact_id,
        :body_document_id,
        :title,
        :state
      ]

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
    end
  end

  graphql do
    type :evidence_item
  end

  json_api do
    type "evidence_item"
  end
end
