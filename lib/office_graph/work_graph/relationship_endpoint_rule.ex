defmodule OfficeGraph.WorkGraph.RelationshipEndpointRule do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "relationship_endpoint_rules"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    uuid_primary_key :id

    attribute :relationship_definition_id, :uuid,
      allow_nil?: false,
      public?: true

    attribute :source_kind, :string, allow_nil?: false, public?: true
    attribute :target_kind, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :definition, OfficeGraph.WorkGraph.RelationshipDefinition do
      source_attribute :relationship_definition_id
      define_attribute? false
      allow_nil? false
    end
  end

  actions do
    read :read do
      primary? true
      public? false
    end
  end

  identities do
    identity :unique_definition_kinds,
             [:relationship_definition_id, :source_kind, :target_kind]
  end
end
