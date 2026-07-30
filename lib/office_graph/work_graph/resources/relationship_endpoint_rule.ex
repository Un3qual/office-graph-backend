defmodule OfficeGraph.WorkGraph.RelationshipEndpointRule do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "relationship_endpoint_rules"
    repo OfficeGraph.Repo
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :source_kind, :string, allow_nil?: false, public?: true
    attribute :target_kind, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :definition, OfficeGraph.WorkGraph.RelationshipDefinition do
      source_attribute :relationship_definition_id
      allow_nil? false
      attribute_public? true
    end
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :ensure do
      public? false
      accept [:relationship_definition_id, :source_kind, :target_kind]
      upsert? true
      upsert_identity :unique_definition_kinds
      upsert_fields []
      return_skipped_upsert? true
    end
  end

  identities do
    identity :unique_definition_kinds,
             [:relationship_definition_id, :source_kind, :target_kind]
  end
end
