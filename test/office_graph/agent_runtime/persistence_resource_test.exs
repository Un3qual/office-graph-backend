defmodule OfficeGraph.AgentRuntime.PersistenceResourceTest do
  use OfficeGraph.DataCase, async: false

  @resources [
    {OfficeGraph.AgentRuntime.Domain, OfficeGraph.AgentRuntime.AgentDefinition,
     "agent_definitions"},
    {OfficeGraph.AgentRuntime.Domain, OfficeGraph.AgentRuntime.OrganizationBinding,
     "agent_organization_bindings"},
    {OfficeGraph.AgentRuntime.Domain, OfficeGraph.AgentRuntime.AgentExecution,
     "agent_executions"},
    {OfficeGraph.AgentRuntime.Domain, OfficeGraph.AgentRuntime.AuthoritySnapshot,
     "agent_authority_snapshots"},
    {OfficeGraph.AgentRuntime.Domain, OfficeGraph.AgentRuntime.ContextPackage,
     "agent_context_packages"},
    {OfficeGraph.AgentRuntime.Domain, OfficeGraph.AgentRuntime.ContextEntry,
     "agent_context_entries"},
    {OfficeGraph.AgentRuntime.Domain, OfficeGraph.AgentRuntime.ModelRequest,
     "agent_model_requests"},
    {OfficeGraph.AgentRuntime.Domain, OfficeGraph.AgentRuntime.ToolRequest,
     "agent_tool_requests"},
    {OfficeGraph.AgentRuntime.Domain, OfficeGraph.AgentRuntime.ApprovalRequest,
     "agent_approval_requests"},
    {OfficeGraph.AgentRuntime.Domain, OfficeGraph.AgentRuntime.ContextExpansionRequest,
     "agent_context_expansion_requests"},
    {OfficeGraph.NodeConversations.Domain, OfficeGraph.NodeConversations.Conversation,
     "conversations"},
    {OfficeGraph.NodeConversations.Domain, OfficeGraph.NodeConversations.ConversationMessage,
     "conversation_messages"}
  ]

  test "each runtime table has one canonical AshPostgres resource in its owning domain" do
    for {domain, resource, table} <- @resources do
      assert Code.ensure_loaded?(domain), "expected #{inspect(domain)} to load"
      assert Code.ensure_loaded?(resource), "expected #{inspect(resource)} to load"
      assert Ash.Resource.Info.data_layer(resource) == AshPostgres.DataLayer
      assert AshPostgres.DataLayer.Info.table(resource) == table
      assert AshPostgres.DataLayer.Info.repo(resource) == OfficeGraph.Repo
      refute AshPostgres.DataLayer.Info.migrate?(resource)
      assert resource in Ash.Domain.Info.resources(domain)
    end
  end

  test "runtime resources expose typed lifecycle, scope, and provenance attributes" do
    assert_attributes(OfficeGraph.AgentRuntime.AgentDefinition, [
      :key,
      :lifecycle_state,
      :supported_modes,
      :requested_capabilities,
      :model_adapter_key,
      :model_credential_id,
      :tool_allowlist,
      :default_autonomy_mode,
      :allowed_output_kinds
    ])

    for resource <- [
          OfficeGraph.AgentRuntime.OrganizationBinding,
          OfficeGraph.AgentRuntime.AgentExecution,
          OfficeGraph.AgentRuntime.AuthoritySnapshot,
          OfficeGraph.AgentRuntime.ContextPackage,
          OfficeGraph.AgentRuntime.ContextEntry,
          OfficeGraph.AgentRuntime.ApprovalRequest,
          OfficeGraph.AgentRuntime.ContextExpansionRequest,
          OfficeGraph.NodeConversations.Conversation
        ] do
      assert_attributes(resource, [:organization_id, :workspace_id, :operation_id])
    end

    assert_attributes(OfficeGraph.AgentRuntime.AgentExecution, [
      :definition_id,
      :organization_binding_id,
      :run_id,
      :graph_item_id,
      :agent_principal_id,
      :delegator_principal_id,
      :invocation_mode,
      :origin,
      :autonomy_mode,
      :state,
      :state_version,
      :idempotency_key
    ])

    assert_attributes(OfficeGraph.NodeConversations.ConversationMessage, [
      :conversation_id,
      :execution_id,
      :author_principal_id,
      :context_package_id,
      :operation_id,
      :source,
      :visibility,
      :body,
      :body_hash
    ])
  end

  test "immutable runtime records have create/read actions but no update or destroy actions" do
    for resource <- [
          OfficeGraph.AgentRuntime.AuthoritySnapshot,
          OfficeGraph.AgentRuntime.ContextPackage,
          OfficeGraph.AgentRuntime.ContextEntry,
          OfficeGraph.NodeConversations.ConversationMessage
        ] do
      assert Code.ensure_loaded?(resource), "expected #{inspect(resource)} to load"
      action_types = resource |> Ash.Resource.Info.actions() |> Enum.map(& &1.type)

      assert :create in action_types
      assert :read in action_types
      refute :update in action_types
      refute :destroy in action_types
    end
  end

  test "request resources retain hashes and classifications without raw traffic or secret values" do
    for resource <- [
          OfficeGraph.AgentRuntime.AgentDefinition,
          OfficeGraph.AgentRuntime.ModelRequest,
          OfficeGraph.AgentRuntime.ToolRequest
        ] do
      assert Code.ensure_loaded?(resource), "expected #{inspect(resource)} to load"
      attribute_names = resource |> Ash.Resource.Info.attributes() |> MapSet.new(& &1.name)

      for forbidden <- [
            :secret,
            :secret_value,
            :api_key,
            :token,
            :raw_prompt,
            :raw_response,
            :raw_input,
            :raw_output
          ] do
        refute MapSet.member?(attribute_names, forbidden)
      end
    end

    assert_attributes(OfficeGraph.AgentRuntime.ModelRequest, [
      :input_hash,
      :output_hash,
      :output_classification,
      :failure_code
    ])

    assert_attributes(OfficeGraph.AgentRuntime.ToolRequest, [
      :input_hash,
      :output_hash,
      :output_classification,
      :failure_code,
      :external_write
    ])
  end

  defp assert_attributes(resource, names) do
    assert Code.ensure_loaded?(resource), "expected #{inspect(resource)} to load"

    actual = resource |> Ash.Resource.Info.attributes() |> MapSet.new(& &1.name)

    for name <- names do
      assert MapSet.member?(actual, name), "expected #{inspect(resource)}.#{name}"
    end
  end
end
