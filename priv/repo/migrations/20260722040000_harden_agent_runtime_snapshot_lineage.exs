defmodule OfficeGraph.Repo.Migrations.HardenAgentRuntimeSnapshotLineage do
  use Ecto.Migration

  defmodule Snapshot do
    use Ecto.Schema

    @primary_key {:id, Ecto.UUID, autogenerate: false}

    schema "agent_authority_snapshots" do
      field(:organization_id, Ecto.UUID)
      field(:workspace_id, Ecto.UUID)
      field(:agent_principal_id, Ecto.UUID)
      field(:delegator_principal_id, Ecto.UUID)
      field(:policy_bundle_id, Ecto.UUID)
      field(:policy_bundle_version, :integer)
      field(:operation_id, Ecto.UUID)
      field(:version, :integer)
      field(:capability_keys, {:array, :string})
      field(:tool_keys, {:array, :string})
      field(:credential_ids, {:array, Ecto.UUID})
      field(:model_adapter_key, :string)
      field(:model_adapter_version, :string)
      field(:autonomy_mode, :string)
      field(:captured_at, :utc_datetime_usec)
    end
  end

  @legacy_hash_fields [
    :organization_id,
    :workspace_id,
    :agent_principal_id,
    :delegator_principal_id,
    :policy_bundle_id,
    :policy_bundle_version,
    :operation_id,
    :version,
    :capability_keys,
    :tool_keys,
    :credential_ids,
    :autonomy_mode,
    :captured_at
  ]

  @current_hash_fields @legacy_hash_fields ++ [:model_adapter_key, :model_adapter_version]

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

    execute(&rehash_authority_snapshots/0)

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

    execute(&rehash_legacy_authority_snapshots/0)

    alter table(:agent_authority_snapshots) do
      remove :model_adapter_version
      remove :model_adapter_key
    end
  end

  def rehash_authority_snapshots(migration_repo \\ repo()) do
    update_authority_hashes(migration_repo, &authority_hash(&1, @current_hash_fields))
  end

  defp rehash_legacy_authority_snapshots do
    update_authority_hashes(repo(), &authority_hash(&1, @legacy_hash_fields))
  end

  defp update_authority_hashes(migration_repo, hasher) do
    Snapshot
    |> migration_repo.all()
    |> Enum.each(fn snapshot ->
      authority_hash = snapshot |> Map.from_struct() |> hasher.()

      migration_repo.query!(
        "UPDATE agent_authority_snapshots SET authority_hash = $1 WHERE id = $2",
        [authority_hash, Ecto.UUID.dump!(snapshot.id)]
      )
    end)

    :ok
  end

  defp authority_hash(authority, fields) do
    authority
    |> Map.take(fields)
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
