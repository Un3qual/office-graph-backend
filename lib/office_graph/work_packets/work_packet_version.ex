defmodule OfficeGraph.WorkPackets.WorkPacketVersion do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkPackets.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "work_packet_versions"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :work_packet_id, :uuid, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :version_number, :integer, allow_nil?: false, public?: true
    attribute :lifecycle_state, :string, allow_nil?: false, public?: true
    attribute :objective, :string, allow_nil?: false, public?: true
    attribute :context_summary, :string, allow_nil?: false, public?: true
    attribute :requirements, :string, allow_nil?: false, public?: true
    attribute :success_criteria, :string, allow_nil?: true, public?: true
    attribute :autonomy_posture, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :id,
        :work_packet_id,
        :organization_id,
        :workspace_id,
        :operation_id,
        :version_number,
        :lifecycle_state,
        :objective,
        :context_summary,
        :requirements,
        :success_criteria,
        :autonomy_posture
      ]
    end
  end

  identities do
    identity :unique_packet_version, [:work_packet_id, :version_number]
  end
end
