defmodule OfficeGraphWeb.JsonApi.Router do
  @moduledoc false

  use AshJsonApi.Router,
    domains: [
      OfficeGraph.WorkGraph.Domain,
      OfficeGraph.WorkPackets.Domain,
      OfficeGraph.Runs.Domain,
      OfficeGraph.Integrations.Domain,
      OfficeGraph.ProposedChanges.Domain,
      OfficeGraph.AgentRuntime.Domain,
      OfficeGraph.NodeConversations.Domain,
      OfficeGraph.GitHubIntegration.Domain
    ],
    prefix: "/api/v1"
end
