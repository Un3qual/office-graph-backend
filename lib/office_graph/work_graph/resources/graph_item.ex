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

    custom_indexes do
      index [:organization_id, :workspace_id, :id], name: "graph_items_scope_id_index"
    end
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

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

    has_one :signal, OfficeGraph.WorkGraph.Signal do
      source_attribute :id
      destination_attribute :graph_item_id
      public? true
    end

    has_one :task, OfficeGraph.WorkGraph.Task do
      source_attribute :id
      destination_attribute :graph_item_id
      public? true
    end

    has_one :review_finding, OfficeGraph.WorkGraph.ReviewFinding do
      source_attribute :id
      destination_attribute :graph_item_id
      public? true
    end

    has_one :verification_check, OfficeGraph.WorkGraph.VerificationCheck do
      source_attribute :id
      destination_attribute :graph_item_id
      public? true
    end

    has_one :artifact, OfficeGraph.WorkGraph.Artifact do
      source_attribute :id
      destination_attribute :graph_item_id
      public? true
    end

    has_one :evidence_item, OfficeGraph.WorkGraph.EvidenceItem do
      source_attribute :id
      destination_attribute :graph_item_id
    end
  end

  actions do
    read :read do
      primary? true
      pagination keyset?: true, countable: false, required?: false
    end

    create :create do
      accept [:id, :organization_id, :workspace_id, :resource_type, :resource_id, :title]
    end

    update :set_title do
      accept [:title]
      require_atomic? false
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
