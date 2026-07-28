defmodule OfficeGraph.Repo.Migrations.NormalizeAshResourceStorage do
  use Ecto.Migration

  def up do
    alter table(:execution_observations) do
      add :classification, :text
      remove :metadata
    end

    alter table(:raw_archives) do
      add :provider_event, :text
      add :external_installation_id, :bigint
      remove :metadata
    end

    alter table(:proposed_graph_changes) do
      add :title, :text
      add :body, :text
      remove :payload
    end

    alter table(:github_outbound_actions) do
      add :target_node_id, :text
      add :reply_body, :text
      add :check_status, :text
      add :check_conclusion, :text
      add :details_url, :text
      remove :input
    end

    alter table(:operation_correlations) do
      add :command_input_digest, :text
      remove :metadata
    end

    alter table(:run_events) do
      remove :payload
    end

    alter table(:document_marks) do
      remove :attrs
    end

    alter table(:evidence_items) do
      remove :visibility_constraints
    end

    alter table(:graph_relationships) do
      add :deletion_operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict)

      add :deleted_by_principal_id,
          references(:principals, type: :binary_id, on_delete: :restrict)

      add :deleted_at, :utc_datetime_usec
      add :deletion_reason, :text
      remove :tombstone_id
    end

    drop table(:tombstones)
  end

  def down do
    create table(:tombstones, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict)

      add :resource_type, :text, null: false
      add :resource_id, :binary_id, null: false
      add :deleted_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tombstones, [:resource_type, :resource_id])

    alter table(:graph_relationships) do
      add :tombstone_id, references(:tombstones, type: :binary_id, on_delete: :restrict)
      remove :deletion_reason
      remove :deleted_at
      remove :deleted_by_principal_id
      remove :deletion_operation_id
    end

    alter table(:evidence_items) do
      add :visibility_constraints, :map, null: false, default: %{}
    end

    alter table(:document_marks) do
      add :attrs, :map, null: false, default: %{}
    end

    alter table(:run_events) do
      add :payload, :map, null: false, default: %{}
    end

    alter table(:operation_correlations) do
      add :metadata, :map, null: false, default: %{}
      remove :command_input_digest
    end

    alter table(:github_outbound_actions) do
      add :input, :map, null: false, default: %{}
      remove :details_url
      remove :check_conclusion
      remove :check_status
      remove :reply_body
      remove :target_node_id
    end

    alter table(:proposed_graph_changes) do
      add :payload, :map, null: false, default: %{}
      remove :body
      remove :title
    end

    alter table(:raw_archives) do
      add :metadata, :map, null: false, default: %{}
      remove :external_installation_id
      remove :provider_event
    end

    alter table(:execution_observations) do
      add :metadata, :map, null: false, default: %{}
      remove :classification
    end
  end
end
