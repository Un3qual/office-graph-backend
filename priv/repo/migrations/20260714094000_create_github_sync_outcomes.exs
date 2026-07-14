defmodule OfficeGraph.Repo.Migrations.CreateGitHubSyncOutcomes do
  use Ecto.Migration

  def up do
    create table(:github_sync_outcomes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :installation_id,
          references(:github_installations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict),
          null: false

      add :object_type, :text, null: false
      add :object_id, :text, null: false
      add :delivery_id, :text, null: false
      add :state, :text, null: false
      add :provider_version, :text
      add :provider_sequence, :bigint
      add :resource_type, :text
      add :resource_id, :binary_id
      add :signal_ids, {:array, :binary_id}, null: false, default: []
      add :failure_class, :text
      add :failure_code, :text
      add :retry_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:github_sync_outcomes, [:operation_id],
             name: :github_sync_outcomes_operation_id_index
           )

    create index(:github_sync_outcomes, [:installation_id, :inserted_at],
             name: :github_sync_outcomes_installation_time_index
           )

    create constraint(:github_sync_outcomes, :github_sync_outcomes_state_valid,
             check:
               "state IN ('reconciled', 'skipped_stale', 'retryable', 'terminal', 'authorization', 'configuration')"
           )

    create constraint(:github_sync_outcomes, :github_sync_outcomes_provider_sequence_positive,
             check: "provider_sequence IS NULL OR provider_sequence >= 0"
           )
  end

  def down do
    drop table(:github_sync_outcomes)
  end
end
