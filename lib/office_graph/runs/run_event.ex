defmodule OfficeGraph.Runs.RunEvent do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Runs.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "run_events"
    repo OfficeGraph.Repo
    migrate? false

    foreign_key_names run_id: "run_events_run_id_fkey"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :run_id, :uuid, allow_nil?: false, public?: true
    attribute :event_type, :string, allow_nil?: false, public?: true
    attribute :payload, :map, allow_nil?: false, default: %{}, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      accept [:id, :run_id, :event_type, :payload]
    end
  end
end
