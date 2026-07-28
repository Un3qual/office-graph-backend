defmodule OfficeGraph.WorkGraph.Task do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "tasks"
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

    attribute :title, :string, allow_nil?: false, public?: true
    attribute :lifecycle_state, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :graph_item, OfficeGraph.WorkGraph.GraphItem do
      source_attribute :graph_item_id
      allow_nil? false
      attribute_public? true
      public? true
    end

    belongs_to :source_signal, OfficeGraph.WorkGraph.Signal do
      source_attribute :source_signal_id
      attribute_public? true
      public? true
    end

    belongs_to :body_document, OfficeGraph.Content.Document do
      source_attribute :body_document_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    has_many :review_findings, OfficeGraph.WorkGraph.ReviewFinding do
      source_attribute :id
      destination_attribute :task_id
      public? true
    end
  end

  actions do
    read :read do
      primary? true
      pagination keyset?: true, countable: false, required?: false
    end

    read :read_for_proposed_change_replay do
      public? false
    end

    create :create do
      accept [
        :id,
        :organization_id,
        :workspace_id,
        :graph_item_id,
        :source_signal_id,
        :body_document_id,
        :title
      ]

      change set_attribute(:lifecycle_state, "open")

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                graph_item_id:
                  {OfficeGraph.WorkGraph.GraphItem, resource_type: "task", resource_id: :id},
                source_signal_id: OfficeGraph.WorkGraph.Signal,
                body_document_id: OfficeGraph.Content.Document
              ]}
    end

    update :mark_verified_complete do
      public? false
      accept []
      change set_attribute(:lifecycle_state, "verified_complete")
    end
  end

  policies do
    policy action(:read) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :skeleton_read}
    end

    policy action(:read_for_proposed_change_replay) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :proposed_change_apply}
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
  end

  graphql do
    type :task

    paginate_relationship_with(review_findings: :relay)
  end

  json_api do
    type "task"
  end
end
