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
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :source_item_id, :uuid, allow_nil?: false, public?: true
    attribute :target_item_id, :uuid, allow_nil?: false, public?: true
    attribute :relationship_type, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
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
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      public? false
      accept [:id, :source_item_id, :target_item_id, :relationship_type]

      change OfficeGraph.WorkGraph.Changes.ValidateRelationshipEndpoints
    end
  end

  identities do
    identity :unique_relationship, [:source_item_id, :target_item_id, :relationship_type]
  end

  graphql do
    type :graph_relationship
  end

  json_api do
    type "graph_relationship"
  end
end
