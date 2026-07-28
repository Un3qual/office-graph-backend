defmodule OfficeGraph.Content.DocumentBlock do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Content.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "document_blocks"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_document_position: "document_blocks_document_id_position_index"
    foreign_key_names document_id: "document_blocks_document_id_fkey"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :position, :integer, allow_nil?: false, public?: true
    attribute :block_type, :string, allow_nil?: false, public?: true
    attribute :text, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :document, OfficeGraph.Content.Document do
      source_attribute :document_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    has_many :marks, OfficeGraph.Content.DocumentMark do
      source_attribute :id
      destination_attribute :block_id
    end
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      accept [:id, :document_id, :position, :block_type, :text]
    end
  end

  identities do
    identity :unique_document_position, [:document_id, :position]
  end
end
