defmodule OfficeGraphWeb.GraphQL.Schema do
  use Absinthe.Schema

  use Absinthe.Relay.Schema,
    flavor: :modern,
    global_id_translator: OfficeGraphWeb.GraphQL.RelayIdTranslator

  use AshGraphql,
    define_relay_types?: false,
    relay_ids?: true,
    domains: [
      OfficeGraph.WorkGraph.Domain,
      OfficeGraph.WorkPackets.Domain,
      OfficeGraph.Runs.Domain,
      OfficeGraph.Integrations.Domain,
      OfficeGraph.ProposedChanges.Domain,
      OfficeGraph.AgentRuntime.Domain,
      OfficeGraph.NodeConversations.Domain,
      OfficeGraph.GitHubIntegration.Domain
    ]

  alias OfficeGraphWeb.GraphQL.Common.NodeResolver

  import_types(OfficeGraphWeb.GraphQL.Common.Queries)
  import_types(OfficeGraphWeb.GraphQL.OperatorWorkflow.Types)
  import_types(OfficeGraphWeb.GraphQL.OperatorWorkflow.Queries)

  node interface do
    resolve_type(fn value, _ -> NodeResolver.resolve_type(value) end)
  end

  query do
    import_fields(:common_queries)
    import_fields(:operator_workflow_queries)

    field :node, :node do
      arg(:id, non_null(:id))
      middleware(NodeResolver)
    end
  end

  mutation do
  end
end
