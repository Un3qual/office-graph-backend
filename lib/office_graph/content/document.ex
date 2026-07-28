defmodule OfficeGraph.Content.Document do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Content.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "documents"
    repo OfficeGraph.Repo
    migrate? false

    foreign_key_names organization_id: "documents_organization_id_fkey",
                      workspace_id: "documents_workspace_id_fkey"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :plain_text, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
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

    has_many :blocks, OfficeGraph.Content.DocumentBlock do
      source_attribute :id
      destination_attribute :document_id
    end

    has_many :references, OfficeGraph.Content.DocumentReference do
      source_attribute :id
      destination_attribute :document_id
    end

    has_many :revisions, OfficeGraph.Content.DocumentRevision do
      source_attribute :id
      destination_attribute :document_id
    end
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      accept [:id, :organization_id, :workspace_id, :plain_text]
    end
  end
end
