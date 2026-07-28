defmodule OfficeGraphWeb.StableProjectionNodeTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.TestSupport.AgentRuntimeSupport

  test "stable run, packet, and conversation projections refetch as Relay nodes", %{conn: conn} do
    context = AgentRuntimeSupport.invocation_fixture()
    conn = Ash.PlugHelpers.set_actor(conn, context.session)

    response =
      conn
      |> post(~p"/graphql", %{
        query: """
        query StableProjections($runId: ID!, $packetId: ID!, $graphItemId: ID!) {
          run: operatorRunState(id: $runId) { id status }
          packet: operatorPacketWorkspace(id: $packetId) { id status }
          conversation: operatorRunConversation(
            runId: $runId
            graphItemId: $graphItemId
          ) { id type }
        }
        """,
        variables: %{
          runId: relay_id(:work_run, context.run.id),
          packetId: relay_id(:work_packet, context.run.work_packet_id),
          graphItemId: relay_id(:graph_item, context.graph_item_id)
        }
      })
      |> json_response(200)

    assert response["errors"] in [nil, []]
    projections = response["data"]

    refetched =
      conn
      |> post(~p"/graphql", %{
        query: """
        query StableProjectionNodes($run: ID!, $packet: ID!, $conversation: ID!) {
          run: node(id: $run) {
            id
            __typename
            ... on OperatorRunState { status }
          }
          packet: node(id: $packet) {
            id
            __typename
            ... on OperatorPacketWorkspace { status }
          }
          conversation: node(id: $conversation) {
            id
            __typename
            ... on OperatorRunConversation { type }
          }
        }
        """,
        variables: %{
          run: projections["run"]["id"],
          packet: projections["packet"]["id"],
          conversation: projections["conversation"]["id"]
        }
      })
      |> json_response(200)

    assert refetched["errors"] in [nil, []]

    assert refetched["data"]["run"] == %{
             "id" => projections["run"]["id"],
             "__typename" => "OperatorRunState",
             "status" => projections["run"]["status"]
           }

    assert refetched["data"]["packet"] == %{
             "id" => projections["packet"]["id"],
             "__typename" => "OperatorPacketWorkspace",
             "status" => projections["packet"]["status"]
           }

    assert refetched["data"]["conversation"] == %{
             "id" => projections["conversation"]["id"],
             "__typename" => "OperatorRunConversation",
             "type" => "operator_run_conversation"
           }
  end

  defp relay_id(type, id) do
    Absinthe.Relay.Node.to_global_id(Atom.to_string(type), id, OfficeGraphWeb.GraphQL.Schema)
  end
end
