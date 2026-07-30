defmodule OfficeGraph.DurableDelivery.DomainEvent do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.DurableDelivery.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "domain_events"
    repo OfficeGraph.Repo

    identity_index_names event_key: "domain_events_event_key_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :operation_kind, :string, allow_nil?: false, default: "human", public?: true
    attribute :event_scope, :string, allow_nil?: false, default: "workspace", public?: true
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

  relationships do
    belongs_to :causation_event, OfficeGraph.DurableDelivery.DomainEvent do
      source_attribute :causation_event_id
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

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      attribute_public? true
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

    action :record_and_enqueue, :term do
      public? false
      transaction? true

      argument :operation_kind, :string, allow_nil?: false
      argument :event_scope, :string, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false
      argument :workspace_id, :uuid
      argument :operation_id, :uuid, allow_nil?: false
      argument :causation_event_id, :uuid
      argument :event_key, :string, allow_nil?: false
      argument :event_kind, :string, allow_nil?: false
      argument :subject_kind, :string
      argument :subject_id, :uuid
      argument :subject_version, :integer
      argument :occurred_at, :utc_datetime_usec, allow_nil?: false

      run fn input, _context ->
        OfficeGraph.DurableDelivery.record_and_enqueue_action(input.arguments)
      end
    end

    action :dispatch, :term do
      public? false
      transaction? true

      argument :event_id, :uuid, allow_nil?: false
      argument :enforce_scope?, :boolean, allow_nil?: false
      argument :organization_id, :uuid
      argument :workspace_id, :uuid
      argument :broadcaster, :atom, allow_nil?: false

      run fn input, _context ->
        {:ok, OfficeGraph.DurableDelivery.dispatch_action(input.arguments)}
      end
    end

    action :mark_failure, :term do
      public? false
      transaction? true

      argument :event_id, :uuid, allow_nil?: false
      argument :enforce_scope?, :boolean, allow_nil?: false
      argument :organization_id, :uuid
      argument :workspace_id, :uuid
      argument :failure_code, :string, allow_nil?: false
      argument :allowed_states, {:array, :string}, allow_nil?: false

      run fn input, _context ->
        {:ok, OfficeGraph.DurableDelivery.mark_failure_action(input.arguments)}
      end
    end
  end

  identities do
    identity :event_key, [:event_key]
  end
end
