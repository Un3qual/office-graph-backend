defmodule OfficeGraph.Content.DocumentRevision do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Content.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "document_revisions"
    repo OfficeGraph.Repo

    identity_index_names unique_document_revision:
                           "document_revisions_document_id_revision_number_index"

    foreign_key_names document_id: "document_revisions_document_id_fkey",
                      operation_id: "document_revisions_operation_id_fkey"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :revision_number, :integer, allow_nil?: false, public?: true
    attribute :semantic_summary, :string, allow_nil?: false, public?: true

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

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end
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
