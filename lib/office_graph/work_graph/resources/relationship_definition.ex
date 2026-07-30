defmodule OfficeGraph.WorkGraph.RelationshipDefinition do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "relationship_definitions"
    repo OfficeGraph.Repo
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :key, :string, allow_nil?: false, public?: true
    attribute :family, :string, allow_nil?: false, public?: true
    attribute :direction, :string, allow_nil?: false, public?: true
    attribute :meaning, :string, allow_nil?: false, public?: true
    attribute :lifecycle, :string, allow_nil?: false, public?: true

    attribute :provenance_policy, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\Aoperation_required\z/]

    attribute :authorization_policy, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\Aauthorize_scope_and_endpoints\z/]

    attribute :cycle_policy, :string, allow_nil?: false, public?: true
    attribute :specialization_posture, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    has_many :endpoint_rules, OfficeGraph.WorkGraph.RelationshipEndpointRule do
      source_attribute :id
      destination_attribute :relationship_definition_id
    end
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :ensure do
      public? false

      accept [
        :key,
        :family,
        :direction,
        :meaning,
        :lifecycle,
        :provenance_policy,
        :authorization_policy,
        :cycle_policy,
        :specialization_posture
      ]

      upsert? true
      upsert_identity :unique_key

      upsert_fields [
        :family,
        :direction,
        :meaning,
        :lifecycle,
        :provenance_policy,
        :authorization_policy,
        :cycle_policy,
        :specialization_posture
      ]

      return_skipped_upsert? true
    end

    action :setup_catalog, :integer do
      public? false
      transaction? true
      touches_resources [OfficeGraph.WorkGraph.RelationshipEndpointRule]
      run OfficeGraph.WorkGraph.Actions.SetupReferenceCatalog
    end
  end

  identities do
    identity :unique_key, [:key]
  end
end
