defmodule OfficeGraph.Content.DocumentReference do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Content.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "document_references"
    repo OfficeGraph.Repo
    migrate? false

    foreign_key_names document_id: "document_references_document_id_fkey"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :document_id, :uuid, allow_nil?: false, public?: true
    attribute :target_type, :string, allow_nil?: false, public?: true
    attribute :target_id, :uuid, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      accept [:id, :document_id, :target_type, :target_id]
    end
  end
end
