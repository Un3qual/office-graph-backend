defmodule OfficeGraphWeb.OperatorRunsApiTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.Foundation
  alias OfficeGraph.Repo
  alias OfficeGraph.SessionCaseHelpers

  import OfficeGraph.TestSupport.OperatorProjectionSupport,
    only: [create_ready_run: 2, create_required_verification_check: 1]

  @operator_runs_query """
  query OperatorRuns($first: Int!, $after: String) {
    listWorkRuns(
      first: $first
      after: $after
      sort: [{ field: INSERTED_AT, order: DESC }]
    ) {
      pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
      edges {
        cursor
        node {
          id
          objective
          aggregateState
          executionState
          verificationState
          insertedAt
          workPacket { id title state }
        }
      }
    }
  }
  """

  @operator_run_detail_query """
  query OperatorRunDetail($id: ID!) {
    getWorkRun(id: $id) {
      id
      workPacket { id title state }
      workPacketVersion { id versionNumber lifecycleState objective }
      aggregateState
      executionState
      verificationState
    }
  }
  """

  test "returns ordered generated WorkRun Relay pages with packet relationships", %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, older} = create_ready_run(bootstrap.session, verification_check)
    {:ok, newer} = create_ready_run(bootstrap.session, verification_check)

    set_run_inserted_at!(older.run.id, ~U[2026-07-20 10:00:00Z])
    set_run_inserted_at!(newer.run.id, ~U[2026-07-20 11:00:00Z])

    first_page = graphql(conn, @operator_runs_query, %{first: 1}, "listWorkRuns")
    assert first_page["pageInfo"]["hasNextPage"] == true
    assert first_page["pageInfo"]["hasPreviousPage"] == false
    assert [%{"cursor" => cursor, "node" => first_node}] = first_page["edges"]
    assert is_binary(cursor)
    assert first_node["id"] == relay_id("work_run", newer.run.id)
    assert first_node["objective"] == newer.run.objective

    assert first_node["workPacket"] == %{
             "id" => relay_id("work_packet", newer.run.work_packet_id),
             "state" => "ready",
             "title" => "Ready operator packet"
           }

    second_page =
      graphql(
        conn,
        @operator_runs_query,
        %{first: 1, after: first_page["pageInfo"]["endCursor"]},
        "listWorkRuns"
      )

    assert second_page["pageInfo"]["hasNextPage"] == false
    assert second_page["pageInfo"]["hasPreviousPage"] == true
    assert [%{"node" => second_node}] = second_page["edges"]
    assert second_node["id"] == relay_id("work_run", older.run.id)
  end

  test "returns graph-targeted runs without requiring a packet-version summary", %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, result} = create_ready_run(bootstrap.session, verification_check)

    Repo.query!("UPDATE runs SET work_packet_version_id = NULL WHERE id = $1", [
      Ecto.UUID.dump!(result.run.id)
    ])

    page = graphql(conn, @operator_runs_query, %{first: 10}, "listWorkRuns")

    assert %{"workPacket" => %{"id" => packet_id}} =
             page["edges"]
             |> Enum.find(&(get_in(&1, ["node", "id"]) == relay_id("work_run", result.run.id)))
             |> Map.fetch!("node")

    assert packet_id == relay_id("work_packet", result.run.work_packet_id)
  end

  test "returns selected detail for graph-targeted runs without packet versions", %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, result} = create_ready_run(bootstrap.session, verification_check)

    Repo.query!("UPDATE runs SET work_packet_version_id = NULL WHERE id = $1", [
      Ecto.UUID.dump!(result.run.id)
    ])

    detail =
      graphql(
        conn,
        @operator_run_detail_query,
        %{id: relay_id("work_run", result.run.id)},
        "getWorkRun"
      )

    assert detail["workPacketVersion"] == nil
    assert detail["workPacket"]["id"] == relay_id("work_packet", result.run.work_packet_id)
    assert detail["id"] == relay_id("work_run", result.run.id)
  end

  test "rejects invalid Relay input without returning a partial page", %{conn: conn} do
    invalid_cursor =
      conn
      |> post(~p"/graphql", %{
        query: @operator_runs_query,
        variables: %{first: 1, after: "invalid"}
      })
      |> json_response(200)

    assert [
             %{
               "code" => "invalid_keyset",
               "fields" => ["after"],
               "path" => ["listWorkRuns"]
             }
           ] = Enum.map(invalid_cursor["errors"], &Map.take(&1, ["code", "fields", "path"]))

    assert invalid_cursor["data"] in [nil, %{"listWorkRuns" => nil}]

    negative_first =
      conn
      |> post(~p"/graphql", %{query: @operator_runs_query, variables: %{first: -1}})
      |> json_response(200)

    assert [%{"message" => message, "path" => ["listWorkRuns"]}] = negative_first["errors"]
    assert String.starts_with?(message, "Something went wrong.")

    assert negative_first["data"] in [nil, %{"listWorkRuns" => nil}]
  end

  test "uses the shared request session and does not expose other tenant summaries", %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, local_check} = create_required_verification_check(bootstrap.session)
    {:ok, local_run} = create_ready_run(bootstrap.session, local_check)
    suffix = System.unique_integer([:positive])

    {:ok, foreign_scope} =
      Foundation.bootstrap_local_owner(
        organization_name: "GraphQL foreign organization #{suffix}",
        organization_slug: "graphql-foreign-organization-#{suffix}",
        workspace_name: "GraphQL foreign workspace #{suffix}",
        workspace_slug: "graphql-foreign-workspace-#{suffix}",
        initiative_name: "GraphQL foreign initiative #{suffix}",
        initiative_slug: "graphql-foreign-initiative-#{suffix}",
        owner_email: "graphql-foreign-#{suffix}@office-graph.local"
      )

    {:ok, foreign_check} = create_required_verification_check(foreign_scope.session)
    {:ok, foreign_run} = create_ready_run(foreign_scope.session, foreign_check)

    page = graphql(conn, @operator_runs_query, %{first: 10}, "listWorkRuns")
    ids = page["edges"] |> Enum.map(&get_in(&1, ["node", "id"]))
    assert relay_id("work_run", local_run.run.id) in ids
    refute relay_id("work_run", foreign_run.run.id) in ids
  end

  test "returns the existing safe forbidden shape for a session without skeleton read", %{
    conn: conn
  } do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    denied_session =
      SessionCaseHelpers.create_session_with_capabilities!(bootstrap, [],
        prefix: "operator-runs-api-denied"
      )

    response =
      conn
      |> Ash.PlugHelpers.set_actor(denied_session)
      |> post(~p"/graphql", %{query: @operator_runs_query, variables: %{first: 1}})
      |> json_response(200)

    assert [
             %{
               "code" => "forbidden",
               "message" => "forbidden",
               "path" => ["listWorkRuns"]
             }
           ] = Enum.map(response["errors"], &Map.take(&1, ["code", "message", "path"]))

    assert response["data"] in [nil, %{"listWorkRuns" => nil}]
  end

  test "uses the generated Relay WorkRun type instead of a manual summary object", %{conn: conn} do
    response =
      conn
      |> post(~p"/graphql", %{
        query:
          "{ generated: __type(name: \"WorkRun\") { interfaces { name } fields { name } } manual: __type(name: \"OperatorRunSummary\") { name } }"
      })
      |> json_response(200)

    assert response["errors"] in [nil, []]
    assert get_in(response, ["data", "manual"]) == nil
    assert get_in(response, ["data", "generated", "interfaces"]) == [%{"name" => "Node"}]

    fields = get_in(response, ["data", "generated", "fields"]) |> Enum.map(& &1["name"])
    assert "workPacket" in fields
  end

  defp graphql(conn, query, variables, field) do
    response =
      conn
      |> post(~p"/graphql", %{query: query, variables: variables})
      |> json_response(200)

    assert response["errors"] in [nil, []]
    Map.fetch!(response["data"], field)
  end

  defp relay_id(type, id) do
    Absinthe.Relay.Node.to_global_id(type, id, OfficeGraphWeb.GraphQL.Schema)
  end

  defp set_run_inserted_at!(run_id, inserted_at) do
    Repo.query!("UPDATE runs SET inserted_at = $1, updated_at = $1 WHERE id = $2", [
      inserted_at,
      Ecto.UUID.dump!(run_id)
    ])
  end
end
