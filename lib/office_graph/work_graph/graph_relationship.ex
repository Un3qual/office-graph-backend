defmodule OfficeGraph.WorkGraph.GraphRelationship do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "graph_relationships"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names active_definition_edge:
                           "graph_relationships_active_definition_edge_index"
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :definition_id, :uuid, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, public?: true
    attribute :source_item_id, :uuid, allow_nil?: false, public?: true
    attribute :target_item_id, :uuid, allow_nil?: false, public?: true
    attribute :lifecycle, :string, allow_nil?: false, public?: true
    attribute :asserting_principal_id, :uuid, allow_nil?: false, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :valid_from, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :valid_until, :utc_datetime_usec, public?: true
    attribute :run_id, :uuid, public?: true
    attribute :integration_event_id, :uuid, public?: true
    attribute :supersedes_relationship_id, :uuid, public?: true
    attribute :tombstone_id, :uuid, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :definition, OfficeGraph.WorkGraph.RelationshipDefinition do
      source_attribute :definition_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :governing_workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      define_attribute? false
    end

    belongs_to :source_item, OfficeGraph.WorkGraph.GraphItem do
      source_attribute :source_item_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :target_item, OfficeGraph.WorkGraph.GraphItem do
      source_attribute :target_item_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :asserting_principal, OfficeGraph.Identity.Principal do
      source_attribute :asserting_principal_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :superseded_relationship, __MODULE__ do
      source_attribute :supersedes_relationship_id
      define_attribute? false
    end

    belongs_to :tombstone, OfficeGraph.Tombstones.Tombstone do
      source_attribute :tombstone_id
      define_attribute? false
    end
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      public? false

      accept [
        :id,
        :definition_id,
        :organization_id,
        :workspace_id,
        :source_item_id,
        :target_item_id,
        :lifecycle,
        :asserting_principal_id,
        :operation_id,
        :valid_from,
        :valid_until,
        :run_id,
        :integration_event_id,
        :supersedes_relationship_id,
        :tombstone_id
      ]

      change OfficeGraph.WorkGraph.Changes.ValidateRelationshipEndpoints
    end
  end

  identities do
    identity :active_definition_edge,
             [:organization_id, :definition_id, :source_item_id, :target_item_id],
             where: expr(lifecycle == "active")
  end

  graphql do
    type :graph_relationship
  end

  json_api do
    type "graph_relationship"
  end
end
