defmodule OfficeGraph.Runs.Run do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Runs.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "runs"
    repo OfficeGraph.Repo
    migrate? false

    foreign_key_names work_packet_id: "runs_work_packet_id_fkey"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :work_packet_id, :uuid, allow_nil?: false, public?: true
    attribute :state, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      accept [:id, :work_packet_id, :state]
    end
  end
end
