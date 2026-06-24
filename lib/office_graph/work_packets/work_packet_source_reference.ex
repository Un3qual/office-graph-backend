defmodule OfficeGraph.WorkPackets.WorkPacketSourceReference do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkPackets.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "work_packet_version_sources"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :work_packet_version_id, :uuid, allow_nil?: false, public?: true
    attribute :graph_item_id, :uuid, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :source_kind, :string, allow_nil?: false, public?: true
    attribute :rationale, :string, allow_nil?: false, public?: true
    attribute :visibility, :string, allow_nil?: false, public?: true
    attribute :sensitivity, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :id,
        :work_packet_version_id,
        :graph_item_id,
        :organization_id,
        :workspace_id,
        :source_kind,
        :rationale,
        :visibility,
        :sensitivity
      ]

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                graph_item_id: OfficeGraph.WorkGraph.GraphItem
              ]}
    end
  end

  identities do
    identity :unique_version_source, [:work_packet_version_id, :graph_item_id, :source_kind]
  end
end
