defmodule OfficeGraphWeb.OperatorRunsApiTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.Foundation
  alias OfficeGraph.Repo
  alias OfficeGraph.SessionCaseHelpers

  import OfficeGraph.TestSupport.OperatorProjectionSupport,
    only: [create_ready_run: 2, create_required_verification_check: 1]

  @operator_runs_query """
  query OperatorRuns($first: Int!, $after: String) {
    operatorRuns(first: $first, after: $after) {
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
          sourceWatermark
          packet { id title state }
          packetVersion { id versionNumber lifecycleState objective }
        }
      }
    }
  }
  """

  test "returns forward Relay pages with only safe run summary fields", %{conn: conn} do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, older} = create_ready_run(bootstrap.session, verification_check)
    {:ok, newer} = create_ready_run(bootstrap.session, verification_check)

    set_run_inserted_at!(older.run.id, ~U[2026-07-20 10:00:00Z])
    set_run_inserted_at!(newer.run.id, ~U[2026-07-20 11:00:00Z])

    first_page = graphql(conn, @operator_runs_query, %{first: 1}, "operatorRuns")
    assert first_page["pageInfo"]["hasNextPage"] == true
    assert first_page["pageInfo"]["hasPreviousPage"] == false
    assert [%{"cursor" => cursor, "node" => first_node}] = first_page["edges"]
    assert is_binary(cursor)
    assert first_node["id"] == newer.run.id
    assert first_node["objective"] == newer.run.objective
    assert first_node["packetVersion"]["id"] == newer.packet_version.id
    assert is_binary(first_node["sourceWatermark"])

    second_page =
      graphql(
        conn,
        @operator_runs_query,
        %{first: 1, after: first_page["pageInfo"]["endCursor"]},
        "operatorRuns"
      )

    assert second_page["pageInfo"]["hasNextPage"] == false
    assert second_page["pageInfo"]["hasPreviousPage"] == true
    assert [%{"node" => second_node}] = second_page["edges"]
    assert second_node["id"] == older.run.id
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
               "message" => "A field has an invalid value.",
               "extensions" => %{"code" => "validation_failed", "field" => "pagination"}
             }
           ] =
             invalid_cursor["errors"]

    assert invalid_cursor["data"] in [nil, %{"operatorRuns" => nil}]

    negative_first =
      conn
      |> post(~p"/graphql", %{query: @operator_runs_query, variables: %{first: -1}})
      |> json_response(200)

    assert [
             %{
               "message" => "A field has an invalid value.",
               "extensions" => %{"code" => "validation_failed", "field" => "first"}
             }
           ] =
             negative_first["errors"]

    assert negative_first["data"] in [nil, %{"operatorRuns" => nil}]
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

    page = graphql(conn, @operator_runs_query, %{first: 10}, "operatorRuns")
    ids = page["edges"] |> Enum.map(&get_in(&1, ["node", "id"]))
    assert local_run.run.id in ids
    refute foreign_run.run.id in ids
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

    assert [%{"extensions" => %{"code" => "forbidden"}}] = response["errors"]
    assert response["data"] in [nil, %{"operatorRuns" => nil}]
  end

  test "does not include raw run payload fields in the summary schema", %{conn: conn} do
    response =
      conn
      |> post(~p"/graphql", %{
        query: "{ __type(name: \"OperatorRunSummary\") { fields { name } } }"
      })
      |> json_response(200)

    assert response["errors"] in [nil, []]
    fields = get_in(response, ["data", "__type", "fields"]) |> Enum.map(& &1["name"])

    assert Enum.sort(fields) ==
             Enum.sort([
               "aggregateState",
               "executionState",
               "id",
               "insertedAt",
               "objective",
               "packet",
               "packetVersion",
               "sourceWatermark",
               "verificationState"
             ])
  end

  defp graphql(conn, query, variables, field) do
    response =
      conn
      |> post(~p"/graphql", %{query: query, variables: variables})
      |> json_response(200)

    assert response["errors"] in [nil, []]
    Map.fetch!(response["data"], field)
  end

  defp set_run_inserted_at!(run_id, inserted_at) do
    Repo.query!("UPDATE runs SET inserted_at = $1, updated_at = $1 WHERE id = $2", [
      inserted_at,
      Ecto.UUID.dump!(run_id)
    ])
  end
end
