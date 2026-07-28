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
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :source_identity, :string, allow_nil?: false, public?: true
    attribute :replay_identity, :string, allow_nil?: false, public?: true
    attribute :outcome, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :duplicate_of, OfficeGraph.Integrations.NormalizedIntakeEvent do
      source_attribute :duplicate_of_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :raw_archive, OfficeGraph.Integrations.RawArchive do
      source_attribute :raw_archive_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    has_many :duplicate_events, OfficeGraph.Integrations.NormalizedIntakeEvent do
      source_attribute :id
      destination_attribute :duplicate_of_id
    end

    has_many :proposed_changes, OfficeGraph.ProposedChanges.ProposedGraphChange do
      source_attribute :id
      destination_attribute :normalized_event_id
    end
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
