defmodule OfficeGraphWeb.GeneratedApiReadTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.Foundation
  alias OfficeGraph.Identity.{Principal, Session, SessionContext}
  alias OfficeGraph.Operations
  alias OfficeGraph.QueryCounter
  alias OfficeGraph.Runs
  alias OfficeGraph.WorkGraph
  alias OfficeGraph.WorkPackets

  describe "generated AshGraphql reads" do
    test "generated resource lists stay bounded across returned parents", %{conn: conn} do
      Enum.each(1..3, fn _index -> seed_scope([]) end)

      {response, queries} =
        QueryCounter.count(fn ->
          conn
          |> post(~p"/graphql", %{query: generated_reads_query()})
          |> json_response(200)
        end)

      assert response["errors"] in [nil, []]
      assert length(response["data"]["listWorkPackets"]["edges"]) >= 3
      assert length(response["data"]["listWorkRuns"]["edges"]) >= 3
      assert QueryCounter.source_count(queries, "signals") <= 1
      assert QueryCounter.source_count(queries, "work_packets") <= 1
      assert QueryCounter.source_count(queries, "runs") <= 1
    end

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

    test "generated get reads accept Relay IDs returned by connection lists", %{conn: conn} do
      seed_generated_read_fixtures()

      reads =
        conn
        |> post(~p"/graphql", %{query: generated_reads_query()})
        |> json_response(200)

      assert reads["errors"] in [nil, []]

      [signal] = connection_nodes(reads["data"]["listSignals"])
      [work_packet] = connection_nodes(reads["data"]["listWorkPackets"])
      [work_run] = connection_nodes(reads["data"]["listWorkRuns"])

      response =
        conn
        |> post(~p"/graphql", %{
          query: generated_gets_query(),
          variables: %{
            signalId: signal["id"],
            workPacketId: work_packet["id"],
            workRunId: work_run["id"]
          }
        })
        |> json_response(200)

      assert response["errors"] in [nil, []]
      assert response["data"]["getSignal"]["id"] == signal["id"]
      assert response["data"]["getSignal"]["title"] == signal["title"]
      assert response["data"]["getWorkPacket"]["id"] == work_packet["id"]
      assert response["data"]["getWorkPacket"]["title"] == work_packet["title"]
      assert response["data"]["getWorkRun"]["id"] == work_run["id"]
      assert response["data"]["getWorkRun"]["state"] == work_run["state"]
    end

    test "packet deep-link lookup isolates malformed and unavailable Relay IDs from the list",
         %{conn: conn} do
      fixtures = seed_generated_read_fixtures()

      valid_id =
        Absinthe.Relay.Node.to_global_id(
          "work_packet",
          fixtures.local.packet.id,
          OfficeGraphWeb.GraphQL.Schema
        )

      missing_id =
        Absinthe.Relay.Node.to_global_id(
          "work_packet",
          Ecto.UUID.generate(),
          OfficeGraphWeb.GraphQL.Schema
        )

      foreign_id =
        Absinthe.Relay.Node.to_global_id(
          "work_packet",
          fixtures.foreign.packet.id,
          OfficeGraphWeb.GraphQL.Schema
        )

      listed =
        conn
        |> post(~p"/graphql", %{query: generated_reads_query()})
        |> json_response(200)

      [listed_packet] = connection_nodes(listed["data"]["listWorkPackets"])
      assert listed_packet["id"] == valid_id

      valid =
        conn
        |> post(~p"/graphql", %{
          query: packet_deep_link_query(),
          variables: %{packetId: valid_id}
        })
        |> json_response(200)

      assert valid["errors"] in [nil, []]
      assert [_local_packet] = connection_nodes(valid["data"]["listWorkPackets"])
      assert valid["data"]["linkedPacket"]["id"] == valid_id
      refute valid["data"]["linkedPacket"]["id"] == fixtures.local.packet.id

      Enum.each(["not-a-relay-id", missing_id, foreign_id], fn packet_id ->
        unavailable =
          conn
          |> post(~p"/graphql", %{
            query: packet_deep_link_query(),
            variables: %{packetId: packet_id}
          })
          |> json_response(200)

        assert [_local_packet] = connection_nodes(unavailable["data"]["listWorkPackets"])
        assert unavailable["data"]["linkedPacket"] == nil
      end)
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

    test "node(id:) returns structured forbidden errors when no actor can be bootstrapped",
         %{conn: conn} do
      seed_generated_read_fixtures()
      signal_id = generated_signal_node_id(conn)

      original = Application.get_env(:office_graph, :allow_local_api_owner_bootstrap)
      Application.put_env(:office_graph, :allow_local_api_owner_bootstrap, false)

      try do
        response =
          conn
          |> post(~p"/graphql", %{query: generated_node_query(), variables: %{id: signal_id}})
          |> json_response(200)

        assert [%{"extensions" => %{"code" => "forbidden"}} | _rest] = response["errors"]
        assert response["data"] in [nil, %{"node" => nil}]
      after
        Application.put_env(:office_graph, :allow_local_api_owner_bootstrap, original)
      end
    end

    test "node(id:) preserves forbidden errors from trusted actors without read grants",
         %{conn: conn} do
      fixtures = seed_generated_read_fixtures()

      signal_id =
        Absinthe.Relay.Node.to_global_id(
          :signal,
          fixtures.local.signal.id,
          OfficeGraphWeb.GraphQL.Schema
        )

      forbidden_actor =
        create_ungranted_session_context!(
          fixtures.local.bootstrap,
          "generated-node-forbidden"
        )

      response =
        conn
        |> Ash.PlugHelpers.set_actor(forbidden_actor)
        |> post(~p"/graphql", %{query: generated_node_query(), variables: %{id: signal_id}})
        |> json_response(200)

      assert [%{"extensions" => %{"code" => "forbidden"}} | _rest] = response["errors"]
      assert response["data"] in [nil, %{"node" => nil}]
    end

    test "return structured forbidden errors for generated node refetches without an actor",
         %{conn: conn} do
      original = Application.get_env(:office_graph, :allow_local_api_owner_bootstrap)
      Application.put_env(:office_graph, :allow_local_api_owner_bootstrap, false)

      relay_id =
        Absinthe.Relay.Node.to_global_id(
          :signal,
          Ecto.UUID.generate(),
          OfficeGraphWeb.GraphQL.Schema
        )

      try do
        response =
          conn
          |> post(~p"/graphql", %{query: generated_node_query(), variables: %{id: relay_id}})
          |> json_response(200)

        assert [%{"extensions" => %{"code" => "forbidden"}} | _rest] = response["errors"]
        assert response["data"] in [nil, %{"node" => nil}]
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

  defp generated_gets_query do
    """
    query GeneratedGets($signalId: ID!, $workPacketId: ID!, $workRunId: ID!) {
      getSignal(id: $signalId) {
        id
        title
        state
      }
      getWorkPacket(id: $workPacketId) {
        id
        title
        state
      }
      getWorkRun(id: $workRunId) {
        id
        state
        workPacketId
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

  defp packet_deep_link_query do
    """
    query PacketDeepLink($packetId: ID!) {
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
          }
        }
      }
      linkedPacket: getWorkPacket(id: $packetId) {
        id
        title
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

  defp generated_signal_node_id(conn) do
    response =
      conn
      |> post(~p"/graphql", %{query: generated_reads_query()})
      |> json_response(200)

    assert response["errors"] in [nil, []]

    [signal] = connection_nodes(response["data"]["listSignals"])
    signal["id"]
  end

  defp create_ungranted_session_context!(bootstrap, purpose) do
    suffix = System.unique_integer([:positive])

    principal =
      Ash.create!(
        Principal,
        %{
          id: Ecto.UUID.generate(),
          email: "#{purpose}-#{suffix}@office-graph.local",
          kind: "human",
          status: "active"
        },
        action: :create,
        authorize?: false
      )

    session =
      Ash.create!(
        Session,
        %{
          id: Ecto.UUID.generate(),
          principal_id: principal.id,
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          purpose: purpose
        },
        action: :create,
        authorize?: false
      )

    %SessionContext{
      principal_id: principal.id,
      session_id: session.id,
      organization_id: bootstrap.organization.id,
      workspace_id: bootstrap.workspace.id,
      capabilities: MapSet.new()
    }
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
