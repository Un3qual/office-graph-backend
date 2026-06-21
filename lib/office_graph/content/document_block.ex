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
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :document_id, :uuid, allow_nil?: false, public?: true
    attribute :position, :integer, allow_nil?: false, public?: true
    attribute :block_type, :string, allow_nil?: false, public?: true
    attribute :text, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
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
