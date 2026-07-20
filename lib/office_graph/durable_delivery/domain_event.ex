defmodule OfficeGraph.DurableDelivery.DomainEvent do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.DurableDelivery.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "domain_events"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names event_key: "domain_events_event_key_index"
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :operation_kind, :string, allow_nil?: false, default: "human", public?: true
    attribute :event_scope, :string, allow_nil?: false, default: "workspace", public?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :causation_event_id, :uuid, public?: true
    attribute :event_key, :string, allow_nil?: false, public?: true
    attribute :event_kind, :string, allow_nil?: false, public?: true
    attribute :subject_kind, :string, public?: true
    attribute :subject_id, :uuid, public?: true
    attribute :subject_version, :integer, public?: true
    attribute :delivery_state, :string, allow_nil?: false, default: "pending", public?: true
    attribute :failure_code, :string, public?: true
    attribute :occurred_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :dispatched_at, :utc_datetime_usec, public?: true
    attribute :failed_at, :utc_datetime_usec, public?: true

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
        :operation_kind,
        :event_scope,
        :organization_id,
        :workspace_id,
        :operation_id,
        :causation_event_id,
        :event_key,
        :event_kind,
        :subject_kind,
        :subject_id,
        :subject_version,
        :delivery_state,
        :occurred_at
      ]
    end

    update :mark_dispatched do
      accept [:delivery_state, :dispatched_at, :failure_code, :failed_at]
      require_atomic? false
    end

    update :mark_failed do
      accept [:delivery_state, :failure_code, :failed_at]
      require_atomic? false
    end
  end

  identities do
    identity :event_key, [:event_key]
  end
end
