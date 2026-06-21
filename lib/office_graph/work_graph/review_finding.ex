defmodule OfficeGraph.WorkGraph.ReviewFinding do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "review_findings"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :graph_item_id, :uuid, allow_nil?: false, public?: true
    attribute :task_id, :uuid, allow_nil?: false, public?: true
    attribute :body_document_id, :uuid, allow_nil?: false, public?: true
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :lifecycle_state, :string, allow_nil?: false, public?: true

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
        :task_id,
        :body_document_id,
        :title,
        :lifecycle_state
      ]

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                graph_item_id:
                  {OfficeGraph.WorkGraph.GraphItem,
                   resource_type: "review_finding", resource_id: :id},
                task_id: OfficeGraph.WorkGraph.Task,
                body_document_id: OfficeGraph.Content.Document
              ]}
    end

    update :mark_verified_complete do
      change set_attribute(:lifecycle_state, "verified_complete")
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
                    capability: :proposed_change_apply}
    end

    policy action(:mark_verified_complete) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :verification_complete}
    end
  end

  graphql do
    type :review_finding
  end

  json_api do
    type "review_finding"
  end
end
