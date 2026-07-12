defmodule OfficeGraph.Repo.Migrations.CreateDomainEvents do
  use Ecto.Migration

  def change do
    create table(:domain_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict),
          null: false

      add :causation_event_id, references(:domain_events, type: :binary_id, on_delete: :restrict)
      add :event_key, :text, null: false
      add :event_kind, :text, null: false
      add :subject_kind, :text, null: false
      add :subject_id, :binary_id, null: false
      add :subject_version, :integer, null: false
      add :delivery_state, :text, null: false, default: "pending"
      add :failure_code, :text
      add :occurred_at, :utc_datetime_usec, null: false
      add :dispatched_at, :utc_datetime_usec
      add :failed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:domain_events, [:event_key], name: :domain_events_event_key_index)

    create index(:domain_events, [:organization_id, :workspace_id, :delivery_state, :occurred_at],
             name: :domain_events_scope_state_occurred_at_index
           )

    create index(:domain_events, [:operation_id], name: :domain_events_operation_id_index)

    create index(:domain_events, [:organization_id, :workspace_id, :subject_kind, :subject_id],
             name: :domain_events_subject_index
           )

    create constraint(:domain_events, :domain_events_subject_version_positive,
             check: "subject_version > 0"
           )

    create constraint(:domain_events, :domain_events_delivery_state_valid,
             check: "delivery_state IN ('pending', 'dispatched', 'failed')"
           )
  end
end
