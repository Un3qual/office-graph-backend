defmodule OfficeGraph.Repo.Migrations.CreateGitHubOutboundActions do
  use Ecto.Migration

  def up do
    create table(:github_outbound_actions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :installation_id,
          references(:github_installations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict),
          null: false

      add :principal_id, references(:principals, type: :binary_id, on_delete: :restrict),
        null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :action_kind, :text, null: false
      add :target_type, :text, null: false
      add :target_id, :binary_id, null: false
      add :expected_provider_version, :text, null: false
      add :input, :map, null: false, default: %{}
      add :state, :text, null: false, default: "pending"
      add :provider_response_id, :text
      add :provider_response_version, :text
      add :failure_class, :text
      add :failure_code, :text
      add :attempted_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:github_outbound_actions, [:operation_id],
             name: :github_outbound_actions_operation_id_index
           )

    create index(:github_outbound_actions, [:installation_id, :inserted_at],
             name: :github_outbound_actions_installation_time_index
           )

    create constraint(:github_outbound_actions, :github_outbound_actions_kind_valid,
             check: "action_kind IN ('review_reply', 'check_update')"
           )

    create constraint(:github_outbound_actions, :github_outbound_actions_state_valid,
             check: "state IN ('pending', 'succeeded', 'retryable', 'terminal')"
           )

    for {key, description} <- [
          {"github.review.reply", "Reply to a GitHub review comment"},
          {"github.check.update", "Update a GitHub check result"}
        ] do
      execute("""
      INSERT INTO capabilities (id, key, description, inserted_at, updated_at)
      VALUES (md5('office_graph:capability:#{key}')::uuid, '#{key}', '#{description}', NOW(), NOW())
      ON CONFLICT (key) DO NOTHING
      """)

      execute("""
      INSERT INTO role_capabilities (id, role_id, capability_id, inserted_at, updated_at)
      SELECT
        md5('office_graph:role_capability:' || roles.id::text || ':#{key}')::uuid,
        roles.id,
        capabilities.id,
        NOW(),
        NOW()
      FROM roles
      JOIN capabilities ON capabilities.key = '#{key}'
      WHERE roles.key = 'owner'
      ON CONFLICT (role_id, capability_id) DO NOTHING
      """)
    end
  end

  def down do
    drop table(:github_outbound_actions)
  end
end
