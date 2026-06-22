defmodule OfficeGraph.Revisions.Revision do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Revisions.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "revisions"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :resource_type, :string, allow_nil?: false, public?: true
    attribute :resource_id, :uuid, allow_nil?: false, public?: true
    attribute :revision_type, :string, allow_nil?: false, public?: true
    attribute :summary, :string, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      accept [:id, :operation_id, :resource_type, :resource_id, :revision_type, :summary]
    end
  end
end
