defmodule OfficeGraph.AgentRuntime.Domain do
  @moduledoc false

  use Ash.Domain, otp_app: :office_graph

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
