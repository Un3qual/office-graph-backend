defmodule OfficeGraph.WorkGraph.GraphItem do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "graph_items"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :resource_type, :string, allow_nil?: false, public?: true
    attribute :resource_id, :uuid, allow_nil?: false, public?: true
    attribute :title, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    has_many :outgoing_relationships, OfficeGraph.WorkGraph.GraphRelationship do
      source_attribute :id
      destination_attribute :source_item_id
    end

    has_many :incoming_relationships, OfficeGraph.WorkGraph.GraphRelationship do
      source_attribute :id
      destination_attribute :target_item_id
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:id, :organization_id, :workspace_id, :resource_type, :resource_id, :title]
    end
  end

  identities do
    identity :unique_resource, [:resource_type, :resource_id]
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
    type :graph_item
  end

  json_api do
    type "graph_item"
  end
end
