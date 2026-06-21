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

  actions do
    defaults [:read]

    create :create do
      accept [:id, :source_item_id, :target_item_id, :relationship_type]
    end
  end

  identities do
    identity :unique_relationship, [:source_item_id, :target_item_id, :relationship_type]
  end

  policies do
    policy action_type(:read) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :skeleton_read}
    end

    policy action(:create) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :proposed_change_apply}
    end
  end

  graphql do
    type :graph_relationship
  end

  json_api do
    type "graph_relationship"
  end
end
