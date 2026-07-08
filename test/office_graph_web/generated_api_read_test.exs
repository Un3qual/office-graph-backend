defmodule OfficeGraphWeb.GeneratedApiReadTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.Foundation
  alias OfficeGraph.Operations
  alias OfficeGraph.Runs
  alias OfficeGraph.WorkGraph
  alias OfficeGraph.WorkPackets

  describe "generated AshGraphql reads" do
    test "return local actor scope records for selected generated reads", %{conn: conn} do
      fixtures = seed_generated_read_fixtures()

      response =
        conn
        |> post(~p"/graphql", %{query: generated_reads_query()})
        |> json_response(200)

      assert response["errors"] in [nil, []]

      assert [signal] = connection_nodes(response["data"]["listSignals"])
      assert signal["id"] != fixtures.local.signal.id
      assert signal["title"] == fixtures.local.signal.title
      assert signal["organizationId"] == fixtures.local.bootstrap.organization.id
      assert signal["workspaceId"] == fixtures.local.bootstrap.workspace.id

      assert [work_packet] = connection_nodes(response["data"]["listWorkPackets"])
      assert work_packet["id"] != fixtures.local.packet.id
      assert work_packet["title"] == fixtures.local.packet.title
      assert work_packet["organizationId"] == fixtures.local.bootstrap.organization.id
      assert work_packet["workspaceId"] == fixtures.local.bootstrap.workspace.id

      assert [work_run] = connection_nodes(response["data"]["listWorkRuns"])
      assert work_run["id"] != fixtures.local.run.id
      assert work_run["workPacketId"] == fixtures.local.packet.id
      assert work_run["organizationId"] == fixtures.local.bootstrap.organization.id
      assert work_run["workspaceId"] == fixtures.local.bootstrap.workspace.id

      refute signal["id"] == fixtures.foreign.signal.id
      refute work_packet["id"] == fixtures.foreign.packet.id
      refute work_run["id"] == fixtures.foreign.run.id

      node =
        conn
        |> post(~p"/graphql", %{query: generated_node_query(), variables: %{id: signal["id"]}})
        |> json_response(200)

      assert node["errors"] in [nil, []]
      assert node["data"]["node"]["id"] == signal["id"]
      assert node["data"]["node"]["title"] == signal["title"]

      packet_node =
        conn
        |> post(~p"/graphql", %{
          query: generated_node_query(),
          variables: %{id: work_packet["id"]}
        })
        |> json_response(200)

      assert packet_node["errors"] in [nil, []]
      assert packet_node["data"]["node"]["id"] == work_packet["id"]
      assert packet_node["data"]["node"]["title"] == work_packet["title"]

      run_node =
        conn
        |> post(~p"/graphql", %{query: generated_node_query(), variables: %{id: work_run["id"]}})
        |> json_response(200)

      assert run_node["errors"] in [nil, []]
      assert run_node["data"]["node"]["id"] == work_run["id"]
      assert run_node["data"]["node"]["state"] == work_run["state"]
    end

    test "return structured forbidden errors when no actor can be bootstrapped", %{conn: conn} do
      original = Application.get_env(:office_graph, :allow_local_api_owner_bootstrap)
      Application.put_env(:office_graph, :allow_local_api_owner_bootstrap, false)

      try do
        response =
          conn
          |> post(~p"/graphql", %{query: generated_reads_query()})
          |> json_response(200)

        assert [%{"code" => "forbidden"} | _rest] = response["errors"]

        assert response["data"] in [
                 nil,
                 %{"listSignals" => nil, "listWorkPackets" => nil, "listWorkRuns" => nil}
               ]
      after
        Application.put_env(:office_graph, :allow_local_api_owner_bootstrap, original)
      end
    end
  end

  describe "generated AshJsonApi reads" do
    test "mount under /api/v1 for selected generated reads", %{conn: conn} do
      fixtures = seed_generated_read_fixtures()

      assert [signal] =
               conn
               |> json_api_get(~p"/api/v1/signals")
               |> json_response(200)
               |> Map.fetch!("data")

      assert signal["type"] == "signal"
      assert signal["id"] == fixtures.local.signal.id
      assert signal["attributes"]["title"] == fixtures.local.signal.title

      assert [work_packet] =
               conn
               |> json_api_get(~p"/api/v1/work-packets")
               |> json_response(200)
               |> Map.fetch!("data")

      assert work_packet["type"] == "work_packet"
      assert work_packet["id"] == fixtures.local.packet.id
      assert work_packet["attributes"]["title"] == fixtures.local.packet.title

      assert [work_run] =
               conn
               |> json_api_get(~p"/api/v1/work-runs")
               |> json_response(200)
               |> Map.fetch!("data")

      assert work_run["type"] == "work_run"
      assert work_run["id"] == fixtures.local.run.id
      assert work_run["attributes"]["work_packet_id"] == fixtures.local.packet.id

      refute signal["id"] == fixtures.foreign.signal.id
      refute work_packet["id"] == fixtures.foreign.packet.id
      refute work_run["id"] == fixtures.foreign.run.id
    end

    test "do not expose generated lifecycle writes", %{conn: conn} do
      assert Code.ensure_loaded?(OfficeGraphWeb.JsonApi.Router)

      write_routes =
        OfficeGraphWeb.JsonApi.Router
        |> AshJsonApi.Router.formatted_routes()
        |> Enum.filter(&(&1.verb in ["POST", "PATCH", "DELETE"]))

      assert write_routes == []

      conn =
        conn
        |> put_req_header("accept", "application/vnd.api+json")
        |> put_req_header("content-type", "application/vnd.api+json")
        |> post(~p"/api/v1/work-runs", %{
          data: %{
            type: "work_run",
            attributes: %{state: "running"}
          }
        })

      assert conn.status in [404, 405]
    end

    test "return structured forbidden errors when no actor can be bootstrapped", %{conn: conn} do
      original = Application.get_env(:office_graph, :allow_local_api_owner_bootstrap)
      Application.put_env(:office_graph, :allow_local_api_owner_bootstrap, false)

      try do
        response =
          conn
          |> json_api_get(~p"/api/v1/signals")
          |> json_response(403)

        assert [%{"code" => "forbidden"} | _rest] = response["errors"]
      after
        Application.put_env(:office_graph, :allow_local_api_owner_bootstrap, original)
      end
    end
  end

  defp generated_reads_query do
    """
    query GeneratedResourceReads {
      listSignals(first: 10) {
        pageInfo {
          hasNextPage
          hasPreviousPage
          startCursor
          endCursor
        }
        edges {
          cursor
          node {
            id
            title
            state
            organizationId
            workspaceId
          }
        }
      }
      listWorkPackets(first: 10) {
        pageInfo {
          hasNextPage
          hasPreviousPage
          startCursor
          endCursor
        }
        edges {
          cursor
          node {
            id
            title
            state
            organizationId
            workspaceId
          }
        }
      }
      listWorkRuns(first: 10) {
        pageInfo {
          hasNextPage
          hasPreviousPage
          startCursor
          endCursor
        }
        edges {
          cursor
          node {
            id
            state
            workPacketId
            organizationId
            workspaceId
          }
        }
      }
    }
    """
  end

  defp generated_node_query do
    """
    query GeneratedNode($id: ID!) {
      node(id: $id) {
        id
        ... on Signal {
          title
          state
        }
        ... on WorkPacket {
          title
          state
        }
        ... on WorkRun {
          state
          workPacketId
        }
      }
    }
    """
  end

  defp connection_nodes(connection) do
    assert %{
             "edges" => edges,
             "pageInfo" => %{
               "hasNextPage" => false,
               "hasPreviousPage" => false,
               "startCursor" => start_cursor,
               "endCursor" => end_cursor
             }
           } = connection

    assert is_binary(start_cursor)
    assert is_binary(end_cursor)

    Enum.map(edges, fn edge ->
      assert is_binary(edge["cursor"])
      edge["node"]
    end)
  end

  defp json_api_get(conn, path) do
    conn
    |> put_req_header("accept", "application/vnd.api+json")
    |> get(path)
  end

  defp seed_generated_read_fixtures do
    %{
      local: seed_scope([]),
      foreign:
        seed_scope(
          organization_name: "Foreign Generated Reads",
          organization_slug: "foreign-generated-reads",
          workspace_name: "Foreign Generated Reads",
          workspace_slug: "foreign-generated-reads",
          initiative_name: "Foreign Generated Reads",
          initiative_slug: "foreign-generated-reads",
          owner_email: "foreign-generated-reads@office-graph.local"
        )
    }
  end

  defp seed_scope(attrs) do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner(attrs)

    suffix = System.unique_integer([:positive])

    {:ok, graph_operation} =
      Operations.start_operation(bootstrap.session, :proposed_change_apply,
        idempotency_key: "generated-read-graph-#{suffix}"
      )

    {:ok, %{signal: signal}} =
      WorkGraph.create_signal(bootstrap.session, graph_operation, %{
        title: "Generated read signal #{suffix}",
        body: "Generated read signal body #{suffix}."
      })

    {:ok, %{task: task}} =
      WorkGraph.create_task(bootstrap.session, graph_operation, signal, %{
        title: "Generated read task #{suffix}",
        body: "Generated read task body #{suffix}."
      })

    {:ok, %{review_finding: review_finding}} =
      WorkGraph.create_review_finding(bootstrap.session, graph_operation, task, %{
        title: "Generated read finding #{suffix}",
        body: "Generated read finding body #{suffix}."
      })

    {:ok, %{verification_check: verification_check}} =
      WorkGraph.create_verification_check(bootstrap.session, graph_operation, review_finding, %{
        title: "Generated read check #{suffix}",
        body: "Generated read check body #{suffix}."
      })

    {:ok, packet_operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create,
        idempotency_key: "generated-read-packet-#{suffix}"
      )

    {:ok, packet_result} =
      WorkPackets.create_packet(bootstrap.session, packet_operation, %{
        title: "Generated read packet #{suffix}",
        objective: "Expose generated read packet #{suffix}.",
        context_summary: "Generated read context #{suffix}.",
        requirements: "Read generated API state #{suffix}.",
        success_criteria: "Selected generated reads are visible.",
        autonomy_posture: "human_supervised",
        source_graph_item_ids: [verification_check.graph_item_id],
        verification_check_ids: [verification_check.id]
      })

    {:ok, run_operation} =
      Operations.start_operation(bootstrap.session, :work_run_start,
        idempotency_key: "generated-read-run-#{suffix}"
      )

    {:ok, run_result} =
      Runs.start_run(bootstrap.session, run_operation, packet_result.version, %{
        source_surface: "generated_api_read_test",
        reason: "Verify generated read API exposure.",
        authority_posture: "human_supervised"
      })

    %{
      bootstrap: bootstrap,
      signal: signal,
      packet: packet_result.packet,
      run: run_result.run
    }
  end
end
