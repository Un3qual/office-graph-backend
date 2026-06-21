defmodule OfficeGraph.Integrations.NormalizedIntakeEvent do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Integrations.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "normalized_intake_events"
    repo OfficeGraph.Repo
    migrate? false

    foreign_key_names organization_id: "normalized_intake_events_organization_id_fkey",
                      workspace_id: "normalized_intake_events_workspace_id_fkey",
                      raw_archive_id: "normalized_intake_events_raw_archive_id_fkey",
                      operation_id: "normalized_intake_events_operation_id_fkey",
                      duplicate_of_id: "normalized_intake_events_duplicate_of_id_fkey"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :raw_archive_id, :uuid, allow_nil?: false, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :source_identity, :string, allow_nil?: false, public?: true
    attribute :replay_identity, :string, allow_nil?: false, public?: true
    attribute :outcome, :string, allow_nil?: false, public?: true
    attribute :duplicate_of_id, :uuid, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      accept [
        :id,
        :organization_id,
        :workspace_id,
        :raw_archive_id,
        :operation_id,
        :source_identity,
        :replay_identity,
        :outcome,
        :duplicate_of_id
      ]
    end
  end

  identities do
    identity :accepted_replay_key,
             [:organization_id, :workspace_id, :source_identity, :replay_identity],
             where: expr(outcome == "accepted")
  end
end
