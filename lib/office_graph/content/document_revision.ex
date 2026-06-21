defmodule OfficeGraph.Content.DocumentRevision do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Content.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "document_revisions"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :document_id, :uuid, allow_nil?: false, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :revision_number, :integer, allow_nil?: false, public?: true
    attribute :semantic_summary, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      accept [:id, :document_id, :operation_id, :revision_number, :semantic_summary]
    end
  end

  identities do
    identity :unique_document_revision, [:document_id, :revision_number]
  end
end
