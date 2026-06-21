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
    uuid_primary_key :id, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :plain_text, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
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
