defmodule OfficeGraph.Content.DocumentMark do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Content.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "document_marks"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :block_id, :uuid, allow_nil?: false, public?: true
    attribute :mark_type, :string, allow_nil?: false, public?: true
    attribute :attrs, :map, allow_nil?: false, default: %{}, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      accept [:id, :block_id, :mark_type, :attrs]
    end
  end
end
