defmodule OfficeGraph.Repo.Migrations.CreateAgentRuntimeFoundation do
  use Ecto.Migration

  def up do
    create table(:agent_definitions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :text, null: false
      add :name, :text, null: false
      add :description, :text
      add :lifecycle_state, :text, null: false
      add :supported_modes, {:array, :text}, null: false, default: []
      add :requested_capabilities, {:array, :text}, null: false, default: []
      add :model_adapter_key, :text, null: false

      add :model_credential_id,
          references(:integration_credentials, type: :binary_id, on_delete: :nilify_all)

      add :tool_allowlist, {:array, :text}, null: false, default: []
      add :default_autonomy_mode, :text, null: false
      add :allowed_output_kinds, {:array, :text}, null: false, default: []
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:agent_definitions, [:key], name: :agent_definitions_key_index)

    create constraint(:agent_definitions, :agent_definitions_key_valid,
             check: "key ~ '^[a-z][a-z0-9-]*$'"
           )

    create constraint(:agent_definitions, :agent_definitions_lifecycle_state_valid,
             check: "lifecycle_state IN ('active', 'disabled', 'retired')"
           )

    create constraint(:agent_definitions, :agent_definitions_default_autonomy_mode_valid,
             check: "default_autonomy_mode IN ('human_supervised', 'bounded_automatic')"
           )

    create table(:agent_organization_bindings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :definition_id, references(:agent_definitions, type: :binary_id), null: false
      add :organization_id, references(:organizations, type: :binary_id), null: false
      add :workspace_id, references(:workspaces, type: :binary_id)
      add :agent_principal_id, references(:principals, type: :binary_id), null: false
      add :bound_by_principal_id, references(:principals, type: :binary_id), null: false
      add :lifecycle_state, :text, null: false
      add :operation_id, references(:operation_correlations, type: :binary_id), null: false
      add :disabled_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:agent_organization_bindings, [:definition_id, :organization_id],
             name: :agent_organization_bindings_definition_organization_index
           )

    create unique_index(:agent_organization_bindings, [:organization_id, :agent_principal_id],
             name: :agent_organization_bindings_organization_principal_index
           )

    create unique_index(:agent_organization_bindings, [:operation_id],
             name: :agent_organization_bindings_operation_index
           )

    create index(:agent_organization_bindings, [
             :organization_id,
             :workspace_id,
             :lifecycle_state
           ])

    create constraint(
             :agent_organization_bindings,
             :agent_organization_bindings_lifecycle_state_valid,
             check: "lifecycle_state IN ('active', 'disabled', 'revoked')"
           )

    create constraint(
             :agent_organization_bindings,
             :agent_organization_bindings_disabled_at_valid,
             check:
               "(lifecycle_state = 'active' AND disabled_at IS NULL) OR (lifecycle_state <> 'active' AND disabled_at IS NOT NULL)"
           )

    create table(:agent_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :definition_id, references(:agent_definitions, type: :binary_id), null: false

      add :organization_binding_id,
          references(:agent_organization_bindings, type: :binary_id),
          null: false

      add :organization_id, references(:organizations, type: :binary_id), null: false
      add :workspace_id, references(:workspaces, type: :binary_id), null: false
      add :run_id, references(:runs, type: :binary_id), null: false
      add :graph_item_id, references(:graph_items, type: :binary_id), null: false
      add :agent_principal_id, references(:principals, type: :binary_id), null: false
      add :delegator_principal_id, references(:principals, type: :binary_id)
      add :operation_id, references(:operation_correlations, type: :binary_id), null: false
      add :invocation_mode, :text, null: false
      add :origin, :text, null: false
      add :requested_outcome, :text, null: false
      add :autonomy_mode, :text, null: false
      add :state, :text, null: false
      add :state_version, :bigint, null: false, default: 1
      add :current_step_key, :text
      add :attempt_count, :integer, null: false, default: 0
      add :idempotency_key, :text, null: false
      add :failure_code, :text
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :cancelled_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:agent_executions, [:operation_id],
             name: :agent_executions_operation_index
           )

    create unique_index(
             :agent_executions,
             [:organization_binding_id, :run_id, :idempotency_key],
             name: :agent_executions_binding_run_idempotency_index
           )

    create index(:agent_executions, [:organization_id, :workspace_id, :state],
             name: :agent_executions_scope_state_index
           )

    create index(:agent_executions, [:run_id, :inserted_at],
             name: :agent_executions_run_inserted_at_index
           )

    create constraint(:agent_executions, :agent_executions_state_valid,
             check:
               "state IN ('queued', 'running', 'waiting_approval', 'waiting_context', 'retry_scheduled', 'completed', 'failed', 'cancelled')"
           )

    create constraint(:agent_executions, :agent_executions_invocation_mode_valid,
             check: "invocation_mode IN ('human', 'automatic')"
           )

    create constraint(:agent_executions, :agent_executions_origin_valid,
             check: "origin IN ('operator', 'system_trigger')"
           )

    create constraint(:agent_executions, :agent_executions_versions_valid,
             check: "state_version > 0 AND attempt_count >= 0"
           )

    create table(:agent_authority_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :execution_id, references(:agent_executions, type: :binary_id), null: false
      add :organization_id, references(:organizations, type: :binary_id), null: false
      add :workspace_id, references(:workspaces, type: :binary_id), null: false
      add :agent_principal_id, references(:principals, type: :binary_id), null: false
      add :delegator_principal_id, references(:principals, type: :binary_id)
      add :policy_bundle_id, references(:policy_bundles, type: :binary_id)
      add :policy_bundle_version, :bigint
      add :operation_id, references(:operation_correlations, type: :binary_id), null: false
      add :version, :bigint, null: false
      add :capability_keys, {:array, :text}, null: false, default: []
      add :tool_keys, {:array, :text}, null: false, default: []
      add :credential_ids, {:array, :binary_id}, null: false, default: []
      add :autonomy_mode, :text, null: false
      add :authority_hash, :text, null: false
      add :captured_at, :utc_datetime_usec, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:agent_authority_snapshots, [:execution_id, :version],
             name: :agent_authority_snapshots_execution_version_index
           )

    create index(:agent_authority_snapshots, [:organization_id, :workspace_id, :captured_at])

    create constraint(:agent_authority_snapshots, :agent_authority_snapshots_version_valid,
             check: "version > 0"
           )

    create table(:agent_context_packages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :execution_id, references(:agent_executions, type: :binary_id), null: false

      add :authority_snapshot_id,
          references(:agent_authority_snapshots, type: :binary_id),
          null: false

      add :organization_id, references(:organizations, type: :binary_id), null: false
      add :workspace_id, references(:workspaces, type: :binary_id), null: false
      add :selected_graph_item_id, references(:graph_items, type: :binary_id), null: false
      add :run_id, references(:runs, type: :binary_id), null: false
      add :previous_package_id, references(:agent_context_packages, type: :binary_id)
      add :expansion_request_id, :binary_id
      add :operation_id, references(:operation_correlations, type: :binary_id), null: false
      add :version, :bigint, null: false
      add :package_hash, :text, null: false
      add :assembled_at, :utc_datetime_usec, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:agent_context_packages, [:execution_id, :version],
             name: :agent_context_packages_execution_version_index
           )

    create index(:agent_context_packages, [:organization_id, :workspace_id, :run_id])

    create constraint(:agent_context_packages, :agent_context_packages_version_valid,
             check: "version > 0"
           )

    create table(:agent_context_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :context_package_id, references(:agent_context_packages, type: :binary_id), null: false
      add :organization_id, references(:organizations, type: :binary_id), null: false
      add :workspace_id, references(:workspaces, type: :binary_id), null: false
      add :entry_type, :text, null: false
      add :resource_type, :text, null: false
      add :resource_id, :binary_id, null: false
      add :external_reference_id, references(:external_references, type: :binary_id)
      add :posture, :text, null: false
      add :rationale_code, :text, null: false
      add :content_hash, :text
      add :ordinal, :integer, null: false
      add :operation_id, references(:operation_correlations, type: :binary_id), null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:agent_context_entries, [:context_package_id, :ordinal],
             name: :agent_context_entries_package_ordinal_index
           )

    create index(
             :agent_context_entries,
             [:organization_id, :workspace_id, :resource_type, :resource_id],
             name: :agent_context_entries_scope_resource_index
           )

    create constraint(:agent_context_entries, :agent_context_entries_posture_valid,
             check:
               "posture IN ('included', 'redacted', 'omitted', 'restricted', 'expansion_required')"
           )

    create constraint(:agent_context_entries, :agent_context_entries_ordinal_valid,
             check: "ordinal >= 0"
           )

    create table(:agent_model_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :execution_id, references(:agent_executions, type: :binary_id), null: false
      add :context_package_id, references(:agent_context_packages, type: :binary_id), null: false

      add :authority_snapshot_id,
          references(:agent_authority_snapshots, type: :binary_id),
          null: false

      add :credential_id, references(:integration_credentials, type: :binary_id)
      add :operation_id, references(:operation_correlations, type: :binary_id), null: false
      add :step_key, :text, null: false
      add :adapter_key, :text, null: false
      add :adapter_version, :text, null: false
      add :model_family, :text, null: false
      add :idempotency_key, :text, null: false
      add :state, :text, null: false
      add :timeout_ms, :integer, null: false
      add :token_budget, :integer, null: false
      add :input_hash, :text, null: false
      add :output_hash, :text
      add :output_classification, :text
      add :failure_code, :text
      add :requested_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:agent_model_requests, [:execution_id, :step_key, :idempotency_key],
             name: :agent_model_requests_execution_step_idempotency_index
           )

    create constraint(:agent_model_requests, :agent_model_requests_state_valid,
             check:
               "state IN ('pending', 'running', 'succeeded', 'retry_scheduled', 'failed', 'cancelled')"
           )

    create constraint(:agent_model_requests, :agent_model_requests_limits_valid,
             check: "timeout_ms > 0 AND token_budget > 0"
           )

    create table(:agent_tool_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :execution_id, references(:agent_executions, type: :binary_id), null: false
      add :context_package_id, references(:agent_context_packages, type: :binary_id), null: false

      add :authority_snapshot_id,
          references(:agent_authority_snapshots, type: :binary_id),
          null: false

      add :credential_id, references(:integration_credentials, type: :binary_id)
      add :operation_id, references(:operation_correlations, type: :binary_id), null: false
      add :step_key, :text, null: false
      add :tool_key, :text, null: false
      add :adapter_version, :text, null: false
      add :idempotency_key, :text, null: false
      add :state, :text, null: false
      add :sensitivity, :text, null: false
      add :external_write, :boolean, null: false, default: false
      add :timeout_ms, :integer, null: false
      add :budget_units, :integer, null: false
      add :input_hash, :text, null: false
      add :output_hash, :text
      add :output_classification, :text
      add :failure_code, :text
      add :requested_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:agent_tool_requests, [:execution_id, :step_key, :idempotency_key],
             name: :agent_tool_requests_execution_step_idempotency_index
           )

    create constraint(:agent_tool_requests, :agent_tool_requests_state_valid,
             check:
               "state IN ('pending', 'running', 'succeeded', 'retry_scheduled', 'failed', 'cancelled')"
           )

    create constraint(:agent_tool_requests, :agent_tool_requests_initial_runtime_read_only,
             check: "external_write = false"
           )

    create constraint(:agent_tool_requests, :agent_tool_requests_limits_valid,
             check: "timeout_ms > 0 AND budget_units > 0"
           )

    create table(:agent_approval_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :execution_id, references(:agent_executions, type: :binary_id), null: false

      add :authority_snapshot_id,
          references(:agent_authority_snapshots, type: :binary_id),
          null: false

      add :organization_id, references(:organizations, type: :binary_id), null: false
      add :workspace_id, references(:workspaces, type: :binary_id), null: false
      add :operation_id, references(:operation_correlations, type: :binary_id), null: false
      add :resolution_operation_id, references(:operation_correlations, type: :binary_id)
      add :resolved_by_principal_id, references(:principals, type: :binary_id)
      add :credential_id, references(:integration_credentials, type: :binary_id)
      add :step_key, :text, null: false
      add :requested_action, :text, null: false
      add :reason, :text, null: false
      add :scope_type, :text, null: false
      add :scope_id, :binary_id, null: false
      add :capability_key, :text
      add :sensitivity, :text, null: false
      add :external_write, :boolean, null: false, default: false
      add :state, :text, null: false
      add :version, :bigint, null: false, default: 1
      add :expires_at, :utc_datetime_usec, null: false
      add :resolution_reason, :text
      add :resolved_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:agent_approval_requests, [:execution_id, :step_key],
             name: :agent_approval_requests_execution_step_index
           )

    create unique_index(:agent_approval_requests, [:execution_id, :step_key],
             name: :agent_approval_requests_pending_step_index,
             where: "state = 'pending'"
           )

    create constraint(:agent_approval_requests, :agent_approval_requests_state_valid,
             check:
               "state IN ('pending', 'approved', 'denied', 'cancelled', 'expired', 'superseded')"
           )

    create constraint(:agent_approval_requests, :agent_approval_requests_version_valid,
             check: "version > 0"
           )

    create table(:agent_context_expansion_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :execution_id, references(:agent_executions, type: :binary_id), null: false

      add :current_context_package_id,
          references(:agent_context_packages, type: :binary_id),
          null: false

      add :authority_snapshot_id,
          references(:agent_authority_snapshots, type: :binary_id),
          null: false

      add :organization_id, references(:organizations, type: :binary_id), null: false
      add :workspace_id, references(:workspaces, type: :binary_id), null: false
      add :operation_id, references(:operation_correlations, type: :binary_id), null: false
      add :resolution_operation_id, references(:operation_correlations, type: :binary_id)
      add :resolved_by_principal_id, references(:principals, type: :binary_id)
      add :step_key, :text, null: false
      add :target_resource_type, :text, null: false
      add :target_resource_id, :binary_id, null: false
      add :target_scope_type, :text, null: false
      add :target_scope_id, :binary_id, null: false
      add :access_mode, :text, null: false
      add :capability_key, :text
      add :reason, :text, null: false
      add :sensitivity, :text, null: false
      add :expected_duration_seconds, :integer, null: false
      add :state, :text, null: false
      add :version, :bigint, null: false, default: 1
      add :expires_at, :utc_datetime_usec, null: false
      add :resolution_reason, :text
      add :resolved_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:agent_context_expansion_requests, [:execution_id, :step_key],
             name: :agent_context_expansion_requests_execution_step_index
           )

    create unique_index(:agent_context_expansion_requests, [:execution_id, :step_key],
             name: :agent_context_expansion_requests_pending_step_index,
             where: "state = 'pending'"
           )

    create constraint(
             :agent_context_expansion_requests,
             :agent_context_expansion_requests_state_valid,
             check:
               "state IN ('pending', 'approved', 'denied', 'cancelled', 'expired', 'superseded')"
           )

    create constraint(
             :agent_context_expansion_requests,
             :agent_context_expansion_requests_version_valid,
             check: "version > 0 AND expected_duration_seconds > 0"
           )

    alter table(:agent_context_packages) do
      modify :expansion_request_id,
             references(:agent_context_expansion_requests, type: :binary_id),
             from: :binary_id
    end

    create table(:conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, type: :binary_id), null: false
      add :workspace_id, references(:workspaces, type: :binary_id), null: false
      add :graph_item_id, references(:graph_items, type: :binary_id), null: false
      add :run_id, references(:runs, type: :binary_id), null: false
      add :created_by_principal_id, references(:principals, type: :binary_id), null: false
      add :operation_id, references(:operation_correlations, type: :binary_id), null: false
      add :purpose, :text, null: false
      add :visibility, :text, null: false
      add :state, :text, null: false
      add :state_version, :bigint, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(
             :conversations,
             [:organization_id, :workspace_id, :run_id, :graph_item_id, :purpose],
             name: :conversations_run_graph_item_index
           )

    create constraint(:conversations, :conversations_state_valid,
             check: "state IN ('active', 'closed', 'archived')"
           )

    create constraint(:conversations, :conversations_visibility_valid,
             check: "visibility IN ('run_participants', 'workspace')"
           )

    create table(:conversation_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :conversation_id, references(:conversations, type: :binary_id), null: false
      add :execution_id, references(:agent_executions, type: :binary_id)
      add :author_principal_id, references(:principals, type: :binary_id)
      add :context_package_id, references(:agent_context_packages, type: :binary_id)
      add :operation_id, references(:operation_correlations, type: :binary_id), null: false

      add :proposed_graph_change_id,
          references(:proposed_graph_changes, type: :binary_id)

      add :domain_action_operation_id,
          references(:operation_correlations, type: :binary_id)

      add :source, :text, null: false
      add :visibility, :text, null: false
      add :body, :text, null: false
      add :body_hash, :text, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:conversation_messages, [:conversation_id, :inserted_at, :id],
             name: :conversation_messages_conversation_inserted_at_index
           )

    create unique_index(:conversation_messages, [:operation_id],
             name: :conversation_messages_operation_index
           )

    create constraint(:conversation_messages, :conversation_messages_source_valid,
             check: "source IN ('human', 'agent', 'system')"
           )

    create constraint(:conversation_messages, :conversation_messages_visibility_valid,
             check: "visibility IN ('run_participants', 'workspace')"
           )

    create constraint(:conversation_messages, :conversation_messages_provenance_valid,
             check:
               "(source = 'human' AND author_principal_id IS NOT NULL AND execution_id IS NULL) OR (source = 'agent' AND author_principal_id IS NOT NULL AND execution_id IS NOT NULL AND context_package_id IS NOT NULL) OR (source = 'system' AND execution_id IS NULL)"
           )

    execute("""
    INSERT INTO agent_definitions (
      id,
      key,
      name,
      description,
      lifecycle_state,
      supported_modes,
      requested_capabilities,
      model_adapter_key,
      tool_allowlist,
      default_autonomy_mode,
      allowed_output_kinds,
      inserted_at,
      updated_at
    )
    VALUES (
      gen_random_uuid(),
      'openspec-review',
      'OpenSpec Review',
      'Reviews authorized repository and OpenSpec context through read-only tools.',
      'active',
      ARRAY['human', 'automatic']::text[],
      ARRAY['agent.invoke', 'repository.read', 'openspec.read', 'proposal.create', 'evidence.suggest']::text[],
      'deterministic',
      ARRAY['repository.read', 'openspec.read']::text[],
      'human_supervised',
      ARRAY['message', 'finding', 'proposal', 'check', 'evidence_candidate']::text[],
      now(),
      now()
    )
    ON CONFLICT (key) DO NOTHING
    """)
  end

  def down do
    drop table(:conversation_messages)
    drop table(:conversations)

    alter table(:agent_context_packages) do
      remove :expansion_request_id
    end

    drop table(:agent_context_expansion_requests)
    drop table(:agent_approval_requests)
    drop table(:agent_tool_requests)
    drop table(:agent_model_requests)
    drop table(:agent_context_entries)
    drop table(:agent_context_packages)
    drop table(:agent_authority_snapshots)
    drop table(:agent_executions)
    drop table(:agent_organization_bindings)
    drop table(:agent_definitions)
  end
end
