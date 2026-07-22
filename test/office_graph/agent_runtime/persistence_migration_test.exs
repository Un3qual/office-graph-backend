defmodule OfficeGraph.AgentRuntime.PersistenceMigrationTest do
  use OfficeGraph.DataCase, async: false

  import OfficeGraph.TestSupport.PostgresCatalog

  @runtime_tables ~w(
    agent_definitions
    agent_organization_bindings
    agent_executions
    agent_authority_snapshots
    agent_context_packages
    agent_context_entries
    agent_model_requests
    agent_tool_requests
    agent_approval_requests
    agent_context_expansion_requests
  )

  @conversation_tables ~w(conversations conversation_messages)

  test "agent runtime and conversation persistence is relational, scoped, and constrained" do
    for table <- @runtime_tables ++ @conversation_tables do
      assert table_exists?(table), "expected #{table} to exist"
      assert column_exists?(table, "id")
    end

    for table <- @runtime_tables -- ["agent_definitions"] do
      assert column_exists?(table, "operation_id"),
             "expected #{table} to retain operation provenance"
    end

    for table <- [
          "agent_organization_bindings",
          "agent_executions",
          "agent_authority_snapshots",
          "agent_context_packages",
          "agent_context_entries",
          "agent_approval_requests",
          "agent_context_expansion_requests",
          "conversations"
        ] do
      assert column_exists?(table, "organization_id")
      assert column_exists?(table, "workspace_id")
    end

    assert constraint_exists?("agent_definitions_lifecycle_state_valid")
    assert constraint_exists?("agent_organization_bindings_lifecycle_state_valid")
    assert constraint_exists?("agent_executions_state_valid")
    assert constraint_exists?("agent_context_entries_posture_valid")
    assert constraint_exists?("agent_model_requests_state_valid")
    assert constraint_exists?("agent_tool_requests_state_valid")
    assert constraint_exists?("agent_tool_requests_initial_runtime_read_only")
    assert constraint_exists?("agent_approval_requests_state_valid")
    assert constraint_exists?("agent_context_expansion_requests_state_valid")
    assert constraint_exists?("conversations_state_valid")
    assert constraint_exists?("conversation_messages_source_valid")

    assert index_exists?("agent_definitions_key_index")
    refute column_nullable?("agent_organization_bindings", "workspace_id")

    assert index_exists?("agent_org_bindings_definition_org_workspace_index")

    assert index_columns("agent_org_bindings_definition_org_workspace_index") ==
             ["definition_id", "organization_id", "workspace_id"]

    assert index_exists?("agent_executions_scope_state_index")
    assert index_exists?("agent_executions_operation_index")
    assert index_exists?("agent_executions_state_lease_index")
    assert column_exists?("agent_executions", "lease_token")
    assert column_exists?("agent_executions", "lease_expires_at")
    assert index_exists?("agent_authority_snapshots_execution_version_index")
    assert index_exists?("agent_context_packages_execution_version_index")
    assert index_exists?("agent_context_entries_package_ordinal_index")
    assert index_exists?("agent_model_requests_execution_step_idempotency_index")
    assert index_exists?("agent_tool_requests_execution_step_idempotency_index")
    assert index_exists?("agent_approval_requests_execution_step_index")
    assert index_exists?("agent_context_expansion_requests_execution_step_index")
    assert index_exists?("conversations_run_graph_item_index")
    assert index_exists?("conversation_messages_conversation_inserted_at_index")
  end

  test "the migration installs the canonical OpenSpec review definition without secrets" do
    assert table_exists?("agent_definitions")

    assert %{
             rows: [
               [
                 key,
                 lifecycle_state,
                 requested_capabilities,
                 model_adapter_key,
                 tool_allowlist
               ]
             ]
           } =
             OfficeGraph.Repo.query!("""
             SELECT
               key,
               lifecycle_state,
               requested_capabilities,
               model_adapter_key,
               tool_allowlist
             FROM agent_definitions
             WHERE key = 'openspec-review'
             """)

    assert key == "openspec-review"
    assert lifecycle_state == "active"
    assert model_adapter_key == "deterministic"
    assert "agent.model.generate" in requested_capabilities
    assert "agent.tool.read" in requested_capabilities
    assert Enum.sort(tool_allowlist) == ["openspec.read", "repository.read"]

    for forbidden <- ~w(secret api_key token raw_prompt raw_response raw_input raw_output) do
      refute column_exists?("agent_definitions", forbidden)
      refute column_exists?("agent_model_requests", forbidden)
      refute column_exists?("agent_tool_requests", forbidden)
    end
  end
end
