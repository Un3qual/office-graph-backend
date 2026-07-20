defmodule OfficeGraph.AgentRuntime.PersistenceValidationTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.AgentRuntime.{
    AgentExecution,
    ApprovalRequest,
    ContextEntry,
    ContextExpansionRequest,
    ModelRequest,
    ToolRequest
  }

  alias OfficeGraph.NodeConversations.ConversationMessage

  test "model requests reject non-positive runtime limits before storage" do
    attrs = model_request_attrs()

    assert_invalid_create(ModelRequest, %{attrs | timeout_ms: 0}, :timeout_ms)
    assert_invalid_create(ModelRequest, %{attrs | token_budget: 0}, :token_budget)
  end

  test "tool requests reject non-positive runtime limits before storage" do
    attrs = tool_request_attrs()

    assert_invalid_create(ToolRequest, %{attrs | timeout_ms: 0}, :timeout_ms)
    assert_invalid_create(ToolRequest, %{attrs | budget_units: 0}, :budget_units)
  end

  test "execution counters and context ordinals reject values outside database bounds" do
    execution_attrs = agent_execution_attrs()

    assert_invalid_create(AgentExecution, %{execution_attrs | state_version: 0}, :state_version)
    assert_invalid_create(AgentExecution, %{execution_attrs | attempt_count: -1}, :attempt_count)
    assert_invalid_create(ContextEntry, %{context_entry_attrs() | ordinal: -1}, :ordinal)
  end

  test "approval and expansion request versions and durations reject non-positive values" do
    approval_attrs = approval_request_attrs()
    expansion_attrs = context_expansion_request_attrs()

    assert_invalid_create(ApprovalRequest, %{approval_attrs | version: 0}, :version)
    assert_invalid_create(ContextExpansionRequest, %{expansion_attrs | version: 0}, :version)

    assert_invalid_create(
      ContextExpansionRequest,
      %{expansion_attrs | expected_duration_seconds: 0},
      :expected_duration_seconds
    )

    assert_invalid_update(
      %ApprovalRequest{state: "pending", version: 1},
      :resolve,
      %{state: "approved", version: 0},
      :version
    )

    assert_invalid_update(
      %ContextExpansionRequest{state: "pending", version: 1},
      :resolve,
      %{state: "approved", version: 0},
      :version
    )
  end

  test "conversation messages reject provenance combinations disallowed by storage" do
    human_attrs = conversation_message_attrs()

    assert_invalid_create(
      ConversationMessage,
      Map.put(human_attrs, :author_principal_id, nil),
      :author_principal_id
    )

    assert_invalid_create(
      ConversationMessage,
      Map.put(human_attrs, :execution_id, uuid()),
      :execution_id
    )

    agent_attrs = %{
      human_attrs
      | source: "agent",
        execution_id: uuid(),
        context_package_id: nil
    }

    assert_invalid_create(ConversationMessage, agent_attrs, :context_package_id)

    system_attrs = %{
      human_attrs
      | source: "system",
        author_principal_id: nil,
        execution_id: uuid()
    }

    assert_invalid_create(ConversationMessage, system_attrs, :execution_id)
  end

  defp model_request_attrs do
    %{
      id: uuid(),
      execution_id: uuid(),
      context_package_id: uuid(),
      authority_snapshot_id: uuid(),
      operation_id: uuid(),
      step_key: "model",
      adapter_key: "deterministic",
      adapter_version: "1",
      model_family: "deterministic",
      idempotency_key: "model-request",
      state: "pending",
      timeout_ms: 1,
      token_budget: 1,
      input_hash: "model-input",
      requested_at: now()
    }
  end

  defp tool_request_attrs do
    %{
      id: uuid(),
      execution_id: uuid(),
      context_package_id: uuid(),
      authority_snapshot_id: uuid(),
      operation_id: uuid(),
      step_key: "tool",
      tool_key: "repository.read",
      adapter_version: "1",
      idempotency_key: "tool-request",
      state: "pending",
      sensitivity: "internal",
      external_write: false,
      timeout_ms: 1,
      budget_units: 1,
      input_hash: "tool-input",
      requested_at: now()
    }
  end

  defp agent_execution_attrs do
    %{
      id: uuid(),
      definition_id: uuid(),
      organization_binding_id: uuid(),
      organization_id: uuid(),
      workspace_id: uuid(),
      run_id: uuid(),
      graph_item_id: uuid(),
      agent_principal_id: uuid(),
      operation_id: uuid(),
      invocation_mode: "human",
      origin: "operator",
      requested_outcome: "Review the selected OpenSpec change",
      autonomy_mode: "human_supervised",
      state: "queued",
      state_version: 1,
      attempt_count: 0,
      idempotency_key: "execution"
    }
  end

  defp context_entry_attrs do
    %{
      id: uuid(),
      context_package_id: uuid(),
      organization_id: uuid(),
      workspace_id: uuid(),
      entry_type: "graph_item",
      resource_type: "task",
      resource_id: uuid(),
      posture: "included",
      rationale_code: "selected",
      ordinal: 0,
      operation_id: uuid()
    }
  end

  defp approval_request_attrs do
    %{
      id: uuid(),
      execution_id: uuid(),
      authority_snapshot_id: uuid(),
      organization_id: uuid(),
      workspace_id: uuid(),
      operation_id: uuid(),
      step_key: "approval",
      requested_action: "tool.execute",
      reason: "Requires approval",
      scope_type: "workspace",
      scope_id: uuid(),
      sensitivity: "internal",
      external_write: false,
      state: "pending",
      version: 1,
      expires_at: now()
    }
  end

  defp context_expansion_request_attrs do
    %{
      id: uuid(),
      execution_id: uuid(),
      current_context_package_id: uuid(),
      authority_snapshot_id: uuid(),
      organization_id: uuid(),
      workspace_id: uuid(),
      operation_id: uuid(),
      step_key: "context-expansion",
      target_resource_type: "task",
      target_resource_id: uuid(),
      target_scope_type: "workspace",
      target_scope_id: uuid(),
      access_mode: "read",
      reason: "Additional context required",
      sensitivity: "internal",
      expected_duration_seconds: 60,
      state: "pending",
      version: 1,
      expires_at: now()
    }
  end

  defp conversation_message_attrs do
    %{
      id: uuid(),
      conversation_id: uuid(),
      author_principal_id: uuid(),
      execution_id: nil,
      context_package_id: nil,
      operation_id: uuid(),
      source: "human",
      visibility: "run_participants",
      body: "Review this change",
      body_hash: "message-body"
    }
  end

  defp assert_invalid_create(resource, attrs, field) do
    resource
    |> Ash.Changeset.for_create(:create, attrs)
    |> assert_invalid(field)
  end

  defp assert_invalid_update(record, action, attrs, field) do
    record
    |> Ash.Changeset.for_update(action, attrs)
    |> assert_invalid(field)
  end

  defp assert_invalid(changeset, field) do
    refute changeset.valid?
    assert ash_error_message(changeset) =~ Atom.to_string(field)
  end

  defp ash_error_message(changeset) do
    changeset.errors
    |> Ash.Error.to_error_class()
    |> Exception.message()
  end

  defp uuid, do: Ecto.UUID.generate()
  defp now, do: DateTime.utc_now()
end
