defmodule OfficeGraph.Repo.Migrations.HardenAgentRuntimeSnapshotLineage do
  use Ecto.Migration

  def up do
    alter table(:agent_authority_snapshots) do
      add :model_adapter_key, :text, null: false, default: "unresolved"
      add :model_adapter_version, :text, null: false, default: "unresolved"
    end

    execute("""
    UPDATE agent_authority_snapshots AS snapshots
    SET model_adapter_key = definitions.model_adapter_key,
        model_adapter_version = CASE
          WHEN definitions.model_adapter_key = 'deterministic' THEN '1'
          ELSE 'unresolved'
        END
    FROM agent_executions AS executions
    JOIN agent_definitions AS definitions ON definitions.id = executions.definition_id
    WHERE executions.id = snapshots.execution_id
    """)

    execute("ALTER TABLE agent_authority_snapshots ALTER COLUMN model_adapter_key DROP DEFAULT")

    execute(
      "ALTER TABLE agent_authority_snapshots ALTER COLUMN model_adapter_version DROP DEFAULT"
    )

    alter table(:agent_context_entries) do
      add :source_version, :utc_datetime_usec
    end

    execute(
      "UPDATE agent_context_entries SET source_version = inserted_at WHERE source_version IS NULL"
    )

    execute("ALTER TABLE agent_context_entries ALTER COLUMN source_version SET NOT NULL")

    alter table(:agent_approval_requests) do
      add :context_expansion_request_id,
          references(:agent_context_expansion_requests, type: :binary_id)
    end

    create index(:agent_approval_requests, [:context_expansion_request_id],
             name: :agent_approval_requests_context_expansion_index
           )
  end

  def down do
    drop_if_exists index(:agent_approval_requests, [:context_expansion_request_id],
                     name: :agent_approval_requests_context_expansion_index
                   )

    alter table(:agent_approval_requests) do
      remove :context_expansion_request_id
    end

    alter table(:agent_context_entries) do
      remove :source_version
    end

    alter table(:agent_authority_snapshots) do
      remove :model_adapter_version
      remove :model_adapter_key
    end
  end
end
