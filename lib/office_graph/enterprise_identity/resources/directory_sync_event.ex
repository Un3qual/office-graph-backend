defmodule OfficeGraph.EnterpriseIdentity.DirectorySyncEvent do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.EnterpriseIdentity.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "enterprise_directory_sync_events"
    repo OfficeGraph.Repo

    identity_index_names provider_event: "enterprise_directory_sync_events_provider_event_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :provider_event_id, :string, allow_nil?: false, public?: true
    attribute :event_type, :string, allow_nil?: false, public?: true
    attribute :content_hash, :string, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true
    attribute :result, :string, public?: true
    attribute :provider_occurred_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :processed_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :connection, OfficeGraph.EnterpriseIdentity.EnterpriseConnection do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :directory, OfficeGraph.EnterpriseIdentity.Directory do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :raw_archive, OfficeGraph.Integrations.RawArchive do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      allow_nil? false
      attribute_public? true
    end
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      public? false

      accept [
        :id,
        :connection_id,
        :directory_id,
        :raw_archive_id,
        :operation_id,
        :provider_event_id,
        :event_type,
        :content_hash,
        :status,
        :result,
        :provider_occurred_at,
        :processed_at
      ]

      validate one_of(:status, ~w(pending applied stale review_required failed))
    end

    update :mark_processed do
      public? false
      accept [:status, :result, :processed_at]

      validate one_of(:status, ~w(applied stale review_required failed)),
        where: [changing(:status)]

      require_atomic? false
    end
  end

  identities do
    identity :provider_event, [:provider_event_id]
  end
end
