defmodule OfficeGraph.Tombstones.Tombstone do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Tombstones.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "tombstones"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :resource_type, :string, allow_nil?: false, public?: true
    attribute :resource_id, :uuid, allow_nil?: false, public?: true
    attribute :deleted_at, :utc_datetime_usec, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      accept [:id, :operation_id, :resource_type, :resource_id, :deleted_at]
    end
  end

  identities do
    identity :unique_resource, [:resource_type, :resource_id]
  end
end
