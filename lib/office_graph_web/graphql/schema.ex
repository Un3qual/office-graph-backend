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
      OfficeGraph.Runs.Domain
    ]

  alias OfficeGraph.Projections
  alias OfficeGraphWeb.GraphQL.Common.Errors
  alias OfficeGraphWeb.RequestSession

  import_types(OfficeGraphWeb.GraphQL.Common.Queries)
  import_types(OfficeGraphWeb.GraphQL.OperatorWorkflow.Types)
  import_types(OfficeGraphWeb.GraphQL.OperatorWorkflow.Queries)
  import_types(OfficeGraphWeb.GraphQL.PacketRunVerification.Types)
  import_types(OfficeGraphWeb.GraphQL.PacketRunVerification.Mutations)

  node interface do
    resolve_type(fn
      %{type: "operator_workflow_item"}, _ ->
        :operator_workflow_item

      %{normalized_event_id: _}, _ ->
        :operator_workflow_item

      value, _ ->
        Projections.graphql_node_type(value)
    end)
  end

  query do
    import_fields(:common_queries)
    import_fields(:operator_workflow_queries)

    node field do
      resolve(fn
        %{type: :operator_workflow_item, id: id}, resolution ->
          with {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
               {:ok, item} <- Projections.operator_workflow_item(session_context, id) do
            {:ok, item}
          else
            error -> Errors.to_absinthe(error)
          end

        %{type: type, id: id}, resolution ->
          with {:ok, session_context} <- RequestSession.resolve_resolution(resolution) do
            Projections.generated_graphql_node(session_context, type, id)
          end
      end)
    end
  end

  mutation do
    import_fields(:packet_run_verification_mutations)
  end
end
