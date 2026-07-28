defmodule OfficeGraph.AgentRuntime.Domain do
  @moduledoc false

  use Ash.Domain,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain],
    otp_app: :office_graph

  graphql do
    queries do
      get OfficeGraph.AgentRuntime.AgentExecution, :get_agent_execution, :read
      list OfficeGraph.AgentRuntime.AgentExecution, :list_agent_executions, :read, relay?: true

      get OfficeGraph.AgentRuntime.ApprovalRequest, :get_agent_approval_request, :read

      list OfficeGraph.AgentRuntime.ApprovalRequest,
           :list_agent_approval_requests,
           :read,
           relay?: true

      get OfficeGraph.AgentRuntime.ContextExpansionRequest,
          :get_agent_context_expansion_request,
          :read

      list OfficeGraph.AgentRuntime.ContextExpansionRequest,
           :list_agent_context_expansion_requests,
           :read,
           relay?: true
    end
  end

  json_api do
    routes do
      base_route "/agent-executions", OfficeGraph.AgentRuntime.AgentExecution do
        get(:read, primary?: true)
        index :read
        related(:organization_binding, :read)
        related(:run, :read)
        related(:graph_item, :read)
        related(:approval_requests, :read)
        related(:context_expansion_requests, :read)
      end

      base_route "/agent-approval-requests", OfficeGraph.AgentRuntime.ApprovalRequest do
        get(:read, primary?: true)
        index :read
        related(:execution, :read)
      end

      base_route "/agent-context-expansion-requests",
                 OfficeGraph.AgentRuntime.ContextExpansionRequest do
        get(:read, primary?: true)
        index :read
        related(:execution, :read)
      end
    end
  end

  resources do
    resource OfficeGraph.AgentRuntime.AgentDefinition
    resource OfficeGraph.AgentRuntime.OrganizationBinding
    resource OfficeGraph.AgentRuntime.AgentExecution
    resource OfficeGraph.AgentRuntime.AuthoritySnapshot
    resource OfficeGraph.AgentRuntime.ContextPackage
    resource OfficeGraph.AgentRuntime.ContextEntry
    resource OfficeGraph.AgentRuntime.ModelRequest
    resource OfficeGraph.AgentRuntime.ToolRequest
    resource OfficeGraph.AgentRuntime.ApprovalRequest
    resource OfficeGraph.AgentRuntime.ContextExpansionRequest
  end
end
