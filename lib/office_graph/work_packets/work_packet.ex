defmodule OfficeGraph.WorkPackets.WorkPacket do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkPackets.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "work_packets"
    repo OfficeGraph.Repo
    migrate? false

    foreign_key_names organization_id: "work_packets_organization_id_fkey",
                      workspace_id: "work_packets_workspace_id_fkey"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :title, :string, allow_nil?: false, public?: true
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
      accept [:id, :organization_id, :workspace_id, :title, :state]
    end
  end
end
