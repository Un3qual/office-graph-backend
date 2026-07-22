defmodule OfficeGraph.Repo.Migrations.AddAgentRuntimeGovernedOutputs do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO capabilities (id, key, description, inserted_at, updated_at)
    SELECT
      md5('office_graph:capability:' || desired.key)::uuid,
      desired.key,
      desired.key,
      NOW(),
      NOW()
    FROM (VALUES
      ('agent.approval.resolve'),
      ('agent.context_expansion.resolve')
    ) AS desired(key)
    ON CONFLICT (key) DO NOTHING
    """)

    execute("""
    INSERT INTO role_capabilities (id, role_id, capability_id, inserted_at, updated_at)
    SELECT
      md5('office_graph:role_capability:' || roles.id::text || ':' || capabilities.key)::uuid,
      roles.id,
      capabilities.id,
      NOW(),
      NOW()
    FROM roles
    JOIN capabilities ON capabilities.key IN (
      'agent.approval.resolve',
      'agent.context_expansion.resolve'
    )
    WHERE roles.key = 'owner'
    ON CONFLICT (role_id, capability_id) DO NOTHING
    """)

    alter table(:agent_approval_requests) do
      add :execution_state_version, :bigint
    end

    alter table(:agent_context_expansion_requests) do
      add :execution_state_version, :bigint
    end

    execute("""
    UPDATE agent_approval_requests AS request
    SET execution_state_version = execution.state_version
    FROM agent_executions AS execution
    WHERE execution.id = request.execution_id
      AND request.execution_state_version IS NULL
    """)

    execute("""
    UPDATE agent_context_expansion_requests AS request
    SET execution_state_version = execution.state_version
    FROM agent_executions AS execution
    WHERE execution.id = request.execution_id
      AND request.execution_state_version IS NULL
    """)

    alter table(:agent_approval_requests) do
      modify :execution_state_version, :bigint, null: false
    end

    alter table(:agent_context_expansion_requests) do
      modify :execution_state_version, :bigint, null: false
    end

    create unique_index(:agent_context_packages, [:expansion_request_id],
             where: "expansion_request_id IS NOT NULL",
             name: :agent_context_packages_expansion_request_index
           )

    alter table(:proposed_graph_changes) do
      add :execution_id, references(:agent_executions, type: :binary_id)
      add :context_package_id, references(:agent_context_packages, type: :binary_id)
      add :step_key, :text
    end

    create unique_index(:proposed_graph_changes, [:execution_id, :step_key, :change_type],
             where: "execution_id IS NOT NULL",
             name: :proposed_graph_changes_agent_step_index
           )

    alter table(:execution_observations) do
      add :execution_id, references(:agent_executions, type: :binary_id)
      add :context_package_id, references(:agent_context_packages, type: :binary_id)
      add :step_key, :text
    end

    create unique_index(:execution_observations, [:execution_id, :step_key],
             where: "execution_id IS NOT NULL",
             name: :execution_observations_agent_step_index
           )

    alter table(:evidence_candidates) do
      add :execution_id, references(:agent_executions, type: :binary_id)
      add :context_package_id, references(:agent_context_packages, type: :binary_id)
      add :step_key, :text
    end

    create unique_index(:evidence_candidates, [:execution_id, :step_key],
             where: "execution_id IS NOT NULL",
             name: :evidence_candidates_agent_step_index
           )

    alter table(:conversation_messages) do
      add :step_key, :text
    end

    create unique_index(:conversation_messages, [:execution_id, :step_key],
             where: "execution_id IS NOT NULL",
             name: :conversation_messages_agent_step_index
           )
  end

  def down do
    drop_if_exists index(:conversation_messages, [:execution_id, :step_key],
                     name: :conversation_messages_agent_step_index
                   )

    alter table(:conversation_messages) do
      remove_if_exists :step_key
    end

    drop_if_exists index(:evidence_candidates, [:execution_id, :step_key],
                     name: :evidence_candidates_agent_step_index
                   )

    alter table(:evidence_candidates) do
      remove_if_exists :step_key
      remove_if_exists :context_package_id
      remove_if_exists :execution_id
    end

    drop_if_exists index(:execution_observations, [:execution_id, :step_key],
                     name: :execution_observations_agent_step_index
                   )

    alter table(:execution_observations) do
      remove_if_exists :step_key
      remove_if_exists :context_package_id
      remove_if_exists :execution_id
    end

    drop_if_exists index(:proposed_graph_changes, [:execution_id, :step_key, :change_type],
                     name: :proposed_graph_changes_agent_step_index
                   )

    alter table(:proposed_graph_changes) do
      remove_if_exists :step_key
      remove_if_exists :context_package_id
      remove_if_exists :execution_id
    end

    drop_if_exists index(:agent_context_packages, [:expansion_request_id],
                     name: :agent_context_packages_expansion_request_index
                   )

    alter table(:agent_context_expansion_requests) do
      remove :execution_state_version
    end

    alter table(:agent_approval_requests) do
      remove :execution_state_version
    end
  end
end
