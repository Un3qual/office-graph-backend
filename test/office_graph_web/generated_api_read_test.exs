defmodule OfficeGraphWeb.GeneratedApiReadTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.Foundation
  alias OfficeGraph.Identity.{Principal, Session, SessionContext}
  alias OfficeGraph.Operations
  alias OfficeGraph.QueryCounter
  alias OfficeGraph.Runs
  alias OfficeGraph.WorkGraph
  alias OfficeGraph.WorkGraph.{Artifact, GraphItem}
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

    test "signal graph relationships use generated resource nodes and Relay connections", %{
      conn: conn
    } do
      fixtures = seed_generated_read_fixtures()

      response =
        conn
        |> post(~p"/graphql", %{
          query: generated_signal_relationships_query(),
          variables: %{signalId: relay_id(:signal, fixtures.local.signal.id)}
        })
        |> json_response(200)

      assert response["errors"] in [nil, []]
      signal = response["data"]["getSignal"]

      assert signal["graphItem"]["id"] ==
               relay_id(:graph_item, fixtures.local.signal.graph_item_id)

      assert [task_edge] = signal["tasks"]["edges"]
      task = task_edge["node"]
      assert task["id"] == relay_id(:task, fixtures.local.task.id)
      assert task["sourceSignal"]["id"] == signal["id"]
      assert task["graphItem"]["id"] == relay_id(:graph_item, fixtures.local.task.graph_item_id)

      assert [finding_edge] = task["reviewFindings"]["edges"]
      finding = finding_edge["node"]
      assert finding["id"] == relay_id(:review_finding, fixtures.local.review_finding.id)
      assert finding["task"]["id"] == task["id"]

      assert [check_edge] = finding["verificationChecks"]["edges"]
      check = check_edge["node"]
      assert check["id"] == relay_id(:verification_check, fixtures.local.verification_check.id)
      assert check["reviewFinding"]["id"] == finding["id"]

      assert check["graphItem"]["id"] ==
               relay_id(:graph_item, fixtures.local.verification_check.graph_item_id)

      Enum.each(
        [
          signal["graphItem"]["id"],
          task["id"],
          task["graphItem"]["id"],
          finding["id"],
          check["id"],
          check["graphItem"]["id"]
        ],
        fn node_id ->
          node =
            conn
            |> post(~p"/graphql", %{
              query: generated_node_query(),
              variables: %{id: node_id}
            })
            |> json_response(200)

          assert node["errors"] in [nil, []]
          assert node["data"]["node"]["id"] == node_id
        end
      )
    end

    test "packet versions and contract links use generated relationships and node refetch",
         %{conn: conn} do
      fixtures = seed_generated_read_fixtures()
      packet_id = relay_id(:work_packet, fixtures.local.packet.id)

      response =
        conn
        |> post(~p"/graphql", %{
          query: generated_packet_relationships_query(),
          variables: %{packetId: packet_id}
        })
        |> json_response(200)

      assert response["errors"] in [nil, []]
      packet = response["data"]["getWorkPacket"]
      assert packet["id"] == packet_id

      version = packet["currentVersion"]
      assert version["id"] == relay_id(:work_packet_version, fixtures.local.version.id)
      assert [source_reference] = version["sourceReferences"]
      assert [required_check] = version["requiredChecks"]
      assert [version_edge] = packet["versions"]["edges"]
      assert version_edge["node"]["id"] == version["id"]

      Enum.each(
        [version["id"], source_reference["id"], required_check["id"]],
        fn node_id ->
          node =
            conn
            |> post(~p"/graphql", %{
              query: generated_node_query(),
              variables: %{id: node_id}
            })
            |> json_response(200)

          assert node["errors"] in [nil, []]
          assert node["data"]["node"]["id"] == node_id
        end
      )
    end

    test "run packet versions and required checks use generated relationships and node refetch",
         %{conn: conn} do
      fixtures = seed_generated_read_fixtures()
      run_id = relay_id(:work_run, fixtures.local.run.id)

      response =
        conn
        |> post(~p"/graphql", %{
          query: generated_run_relationships_query(),
          variables: %{runId: run_id}
        })
        |> json_response(200)

      assert response["errors"] in [nil, []]
      run = response["data"]["getWorkRun"]
      assert run["id"] == run_id

      assert run["workPacketVersion"]["id"] ==
               relay_id(:work_packet_version, fixtures.local.version.id)

      assert [required_check_edge] = run["requiredChecks"]["edges"]

      Enum.each(
        [run["workPacketVersion"]["id"], required_check_edge["node"]["id"]],
        fn node_id ->
          node =
            conn
            |> post(~p"/graphql", %{
              query: generated_node_query(),
              variables: %{id: node_id}
            })
            |> json_response(200)

          assert node["errors"] in [nil, []]
          assert node["data"]["node"]["id"] == node_id
        end
      )
    end

    test "artifact reads are generated Relay connections with authorized node refetch", %{
      conn: conn
    } do
      fixtures = seed_generated_read_fixtures()
      artifact_id = relay_id(:artifact, fixtures.local.artifact.id)

      response =
        conn
        |> post(~p"/graphql", %{
          query: """
          query ArtifactRead($id: ID!) {
            listArtifacts(first: 10) {
              pageInfo {
                hasNextPage
                hasPreviousPage
                startCursor
                endCursor
              }
              edges {
                cursor
                node { id title graphItem { id } }
              }
            }
            node(id: $id) {
              id
              ... on Artifact { title }
            }
          }
          """,
          variables: %{id: artifact_id}
        })
        |> json_response(200)

      assert response["errors"] in [nil, []]
      assert [listed] = connection_nodes(response["data"]["listArtifacts"])
      assert listed["id"] == artifact_id
      assert listed["title"] == fixtures.local.artifact.title

      assert listed["graphItem"]["id"] ==
               relay_id(:graph_item, fixtures.local.artifact.graph_item_id)

      assert response["data"]["node"]["id"] == artifact_id
      assert response["data"]["node"]["title"] == fixtures.local.artifact.title
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

      Enum.each(
        [
          {"not-a-relay-id", ["invalid_primary_key"]},
          {missing_id, []},
          {foreign_id, []}
        ],
        fn {packet_id, expected_error_codes} ->
          unavailable =
            conn
            |> post(~p"/graphql", %{
              query: packet_deep_link_query(),
              variables: %{packetId: packet_id}
            })
            |> json_response(200)

          assert Enum.map(unavailable["errors"] || [], & &1["code"]) == expected_error_codes
          assert [_local_packet] = connection_nodes(unavailable["data"]["listWorkPackets"])
          assert unavailable["data"]["linkedPacket"] == nil
        end
      )
    end

    test "return structured forbidden errors without a human actor", %{conn: conn} do
      response =
        conn
        |> without_human_session()
        |> post(~p"/graphql", %{query: generated_reads_query()})
        |> json_response(200)

      assert [%{"code" => "forbidden"} | _rest] = response["errors"]

      assert response["data"] in [
               nil,
               %{"listSignals" => nil, "listWorkPackets" => nil, "listWorkRuns" => nil}
             ]
    end

    test "node(id:) returns structured forbidden errors without a human actor",
         %{conn: conn} do
      seed_generated_read_fixtures()
      signal_id = generated_signal_node_id(conn)

      response =
        conn
        |> without_human_session()
        |> post(~p"/graphql", %{query: generated_node_query(), variables: %{id: signal_id}})
        |> json_response(200)

      assert [%{"code" => "forbidden"} | _rest] = response["errors"]
      assert response["data"] in [nil, %{"node" => nil}]
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

      assert [%{"code" => "forbidden"} | _rest] = response["errors"]
      assert response["data"] in [nil, %{"node" => nil}]
    end

    test "return structured forbidden errors for generated node refetches without an actor",
         %{conn: conn} do
      relay_id =
        Absinthe.Relay.Node.to_global_id(
          :signal,
          Ecto.UUID.generate(),
          OfficeGraphWeb.GraphQL.Schema
        )

      response =
        conn
        |> without_human_session()
        |> post(~p"/graphql", %{query: generated_node_query(), variables: %{id: relay_id}})
        |> json_response(200)

      assert [%{"code" => "forbidden"} | _rest] = response["errors"]
      assert response["data"] in [nil, %{"node" => nil}]
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

      graph_items =
        conn
        |> json_api_get(~p"/api/v1/graph-items")
        |> json_response(200)
        |> Map.fetch!("data")

      assert Enum.any?(graph_items, &(&1["id"] == fixtures.local.signal.graph_item_id))

      assert [task] =
               conn
               |> json_api_get(~p"/api/v1/tasks")
               |> json_response(200)
               |> Map.fetch!("data")

      assert task["id"] == fixtures.local.task.id

      assert [review_finding] =
               conn
               |> json_api_get(~p"/api/v1/review-findings")
               |> json_response(200)
               |> Map.fetch!("data")

      assert review_finding["id"] == fixtures.local.review_finding.id

      assert [verification_check] =
               conn
               |> json_api_get(~p"/api/v1/verification-checks")
               |> json_response(200)
               |> Map.fetch!("data")

      assert verification_check["id"] == fixtures.local.verification_check.id

      assert [work_packet] =
               conn
               |> json_api_get(~p"/api/v1/work-packets")
               |> json_response(200)
               |> Map.fetch!("data")

      assert work_packet["type"] == "work_packet"
      assert work_packet["id"] == fixtures.local.packet.id
      assert work_packet["attributes"]["title"] == fixtures.local.packet.title

      assert [work_packet_version] =
               conn
               |> json_api_get(~p"/api/v1/work-packet-versions")
               |> json_response(200)
               |> Map.fetch!("data")

      assert work_packet_version["type"] == "work_packet_version"
      assert work_packet_version["id"] == fixtures.local.version.id
      assert work_packet_version["attributes"]["work_packet_id"] == fixtures.local.packet.id

      assert [source_reference] =
               conn
               |> json_api_get(~p"/api/v1/work-packet-source-references")
               |> json_response(200)
               |> Map.fetch!("data")

      assert source_reference["type"] == "work_packet_source_reference"
      assert source_reference["attributes"]["work_packet_version_id"] == fixtures.local.version.id

      assert [required_check] =
               conn
               |> json_api_get(~p"/api/v1/work-packet-required-checks")
               |> json_response(200)
               |> Map.fetch!("data")

      assert required_check["type"] == "work_packet_required_check"
      assert required_check["attributes"]["work_packet_version_id"] == fixtures.local.version.id

      assert [work_run] =
               conn
               |> json_api_get(~p"/api/v1/work-runs")
               |> json_response(200)
               |> Map.fetch!("data")

      assert work_run["type"] == "work_run"
      assert work_run["id"] == fixtures.local.run.id
      assert work_run["attributes"]["work_packet_id"] == fixtures.local.packet.id

      assert [run_required_check] =
               conn
               |> json_api_get(~p"/api/v1/run-required-checks")
               |> json_response(200)
               |> Map.fetch!("data")

      assert run_required_check["type"] == "run_required_check"
      assert run_required_check["id"] == fixtures.local.required_check.id
      assert run_required_check["attributes"]["run_id"] == fixtures.local.run.id

      Enum.each(
        [
          ~p"/api/v1/execution-observations",
          ~p"/api/v1/evidence-candidates",
          ~p"/api/v1/evidence-items",
          ~p"/api/v1/verification-results"
        ],
        fn path ->
          assert conn
                 |> json_api_get(path)
                 |> json_response(200)
                 |> Map.fetch!("data") == []
        end
      )

      refute signal["id"] == fixtures.foreign.signal.id
      refute work_packet["id"] == fixtures.foreign.packet.id
      refute work_run["id"] == fixtures.foreign.run.id
    end

    test "mount generated related routes for the signal graph spine", %{conn: conn} do
      fixtures = seed_generated_read_fixtures()

      graph_item =
        conn
        |> json_api_get(~p"/api/v1/signals/#{fixtures.local.signal.id}/graph_item")
        |> json_response(200)
        |> Map.fetch!("data")

      assert graph_item["id"] == fixtures.local.signal.graph_item_id
      assert graph_item["type"] == "graph_item"

      assert [task] =
               conn
               |> json_api_get(~p"/api/v1/signals/#{fixtures.local.signal.id}/tasks")
               |> json_response(200)
               |> Map.fetch!("data")

      assert task["id"] == fixtures.local.task.id

      assert [finding] =
               conn
               |> json_api_get(~p"/api/v1/tasks/#{fixtures.local.task.id}/review_findings")
               |> json_response(200)
               |> Map.fetch!("data")

      assert finding["id"] == fixtures.local.review_finding.id

      assert [check] =
               conn
               |> json_api_get(
                 ~p"/api/v1/review-findings/#{fixtures.local.review_finding.id}/verification_checks"
               )
               |> json_response(200)
               |> Map.fetch!("data")

      assert check["id"] == fixtures.local.verification_check.id
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

    test "return structured forbidden errors without a human actor", %{conn: conn} do
      response =
        conn
        |> without_human_session()
        |> json_api_get(~p"/api/v1/signals")
        |> json_response(403)

      assert [%{"code" => "forbidden"} | _rest] = response["errors"]
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

  defp generated_packet_relationships_query do
    """
    query GeneratedPacketRelationships($packetId: ID!) {
      getWorkPacket(id: $packetId) {
        id
        currentVersion {
          id
          sourceReferences {
            id
            graphItemId
          }
          requiredChecks {
            id
            verificationCheckId
          }
        }
        versions(first: 10, sort: [{ field: VERSION_NUMBER, order: ASC }]) {
          edges {
            node {
              id
              versionNumber
            }
          }
        }
      }
    }
    """
  end

  defp generated_signal_relationships_query do
    """
    query GeneratedSignalRelationships($signalId: ID!) {
      getSignal(id: $signalId) {
        id
        graphItem { id resourceType resourceId }
        tasks(first: 10, sort: [{ field: INSERTED_AT, order: ASC }]) {
          edges {
            node {
              id
              sourceSignal { id }
              graphItem { id resourceType resourceId }
              reviewFindings(first: 10, sort: [{ field: INSERTED_AT, order: ASC }]) {
                edges {
                  node {
                    id
                    task { id }
                    graphItem { id }
                    verificationChecks(
                      first: 10
                      sort: [{ field: INSERTED_AT, order: ASC }]
                    ) {
                      edges {
                        node {
                          id
                          reviewFinding { id }
                          graphItem { id resourceType resourceId }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    """
  end

  defp generated_run_relationships_query do
    """
    query GeneratedRunRelationships($runId: ID!) {
      getWorkRun(id: $runId) {
        id
        workPacketVersion {
          id
          versionNumber
        }
        requiredChecks(first: 10, sort: [{ field: POSITION, order: ASC }]) {
          edges {
            node {
              id
              verificationCheckId
              state
            }
          }
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

  defp relay_id(type, id) do
    Absinthe.Relay.Node.to_global_id(Atom.to_string(type), id, OfficeGraphWeb.GraphQL.Schema)
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

    artifact_id = Ecto.UUID.generate()

    graph_item =
      Ash.create!(
        GraphItem,
        %{
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          resource_type: "artifact",
          resource_id: artifact_id,
          title: "Generated read artifact #{suffix}"
        },
        action: :create,
        authorize?: false
      )

    artifact =
      Ash.create!(
        Artifact,
        %{
          id: artifact_id,
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          graph_item_id: graph_item.id,
          title: "Generated read artifact #{suffix}",
          uri: "https://example.test/generated-read-artifact/#{suffix}"
        },
        action: :create,
        authorize?: false
      )

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
      task: task,
      review_finding: review_finding,
      verification_check: verification_check,
      artifact: artifact,
      packet: packet_result.packet,
      version: packet_result.version,
      run: run_result.run,
      required_check: hd(run_result.required_checks)
    }
  end
end
