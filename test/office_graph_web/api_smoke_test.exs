defmodule OfficeGraphWeb.ApiSmokeTest do
  use OfficeGraphWeb.ConnCase, async: false

  describe "GraphQL and JSON API walking skeleton" do
    test "both transports drive the same durable loop", %{conn: conn} do
      graph = run_graphql_flow(conn, "graphql-flow")
      json = run_json_flow(conn, "json-flow")

      assert graph["verificationCheck"]["lifecycleState"] == "satisfied"
      assert graph["reviewFinding"]["lifecycleState"] == "verified_complete"
      assert graph["task"]["lifecycleState"] == "verified_complete"

      assert json["verification_check"]["lifecycle_state"] == "satisfied"
      assert json["review_finding"]["lifecycle_state"] == "verified_complete"
      assert json["task"]["lifecycle_state"] == "verified_complete"
    end

    test "JSON apply reports missing proposed-change ids without crashing", %{conn: conn} do
      missing_id = Ecto.UUID.generate()

      response =
        conn
        |> post(~p"/api/proposed-changes/apply", %{ids: [missing_id]})
        |> json_response(422)

      assert response["error"]["code"] == "missing_proposed_change"
      assert response["error"]["proposed_change_id"] == missing_id
    end

    test "JSON apply reports already-applied proposed-change ids without crashing", %{conn: conn} do
      submit =
        json_submit(conn, %{
          source_identity: "manual:json-stale",
          replay_identity: "json-stale-#{System.unique_integer([:positive])}",
          body: "Investigate stale JSON apply and report it safely."
        })

      proposed_change_ids = Enum.map(submit["proposed_changes"], & &1["id"])

      conn
      |> post(~p"/api/proposed-changes/apply", %{ids: proposed_change_ids})
      |> json_response(200)

      response =
        conn
        |> post(~p"/api/proposed-changes/apply", %{ids: proposed_change_ids})
        |> json_response(422)

      assert response["error"]["code"] == "invalid_proposed_change_status"
      assert response["error"]["proposed_change_id"] in proposed_change_ids
    end

    test "GraphQL apply reports missing proposed-change ids without crashing", %{conn: conn} do
      missing_id = Ecto.UUID.generate()

      response =
        conn
        |> post(~p"/graphql", %{
          query: """
          mutation Apply($ids: [ID!]!) {
            applyProposedChanges(input: { ids: $ids }) {
              task { id }
            }
          }
          """,
          variables: %{ids: [missing_id]}
        })
        |> json_response(200)

      assert [%{"extensions" => %{"code" => "missing_proposed_change"}} = error] =
               response["errors"]

      assert error["extensions"]["proposed_change_id"] == missing_id
      assert response["data"] in [nil, %{"applyProposedChanges" => nil}]
    end

    test "GraphQL apply reports already-applied proposed-change ids without crashing", %{
      conn: conn
    } do
      submit =
        graphql(conn, submit_query(), %{
          replayIdentity: "graphql-stale-#{System.unique_integer([:positive])}"
        })

      proposed_change_ids = Enum.map(submit["proposedChanges"], & &1["id"])

      first_apply = graphql_apply(conn, proposed_change_ids)
      assert first_apply["errors"] in [nil, []]

      response = graphql_apply(conn, proposed_change_ids)

      assert [%{"extensions" => %{"code" => "invalid_proposed_change_status"}} = error] =
               response["errors"]

      assert error["extensions"]["proposed_change_id"] in proposed_change_ids
      assert response["data"] in [nil, %{"applyProposedChanges" => nil}]
    end
  end

  defp run_graphql_flow(conn, replay_identity) do
    submit = graphql(conn, submit_query(), %{replayIdentity: replay_identity})

    assert submit["normalizedEvent"]["outcome"] == "accepted"
    proposed_change_ids = Enum.map(submit["proposedChanges"], & &1["id"])

    duplicate = graphql(conn, submit_query(), %{replayIdentity: replay_identity})
    assert duplicate["normalizedEvent"]["outcome"] == "duplicate"
    assert duplicate["proposedChanges"] == []

    applied =
      graphql(
        conn,
        """
        mutation Apply($ids: [ID!]!) {
          applyProposedChanges(input: { ids: $ids }) {
            task { id lifecycleState }
            reviewFinding { id lifecycleState }
            verificationCheck { id lifecycleState }
          }
        }
        """,
        %{ids: proposed_change_ids}
      )

    graphql(
      conn,
      """
      mutation Complete($checkId: ID!) {
        completeVerification(input: {
          verificationCheckId: $checkId,
          title: "GraphQL evidence",
          body: "GraphQL evidence accepted.",
          artifactUri: "https://example.test/graphql"
        }) {
          task { id lifecycleState }
          reviewFinding { id lifecycleState }
          verificationCheck { id lifecycleState }
        }
      }
      """,
      %{checkId: applied["verificationCheck"]["id"]}
    )
  end

  defp submit_query do
    """
    mutation Submit($replayIdentity: String!) {
      submitManualIntake(input: {
        sourceIdentity: "manual:graphql",
        replayIdentity: $replayIdentity,
        body: "Investigate flaky deploy and prove it from GraphQL."
      }) {
        normalizedEvent { outcome }
        proposedChanges { id changeType status }
      }
    }
    """
  end

  defp run_json_flow(conn, replay_identity) do
    submit =
      json_submit(conn, %{
        source_identity: "manual:json",
        replay_identity: replay_identity,
        body: "Investigate flaky deploy and prove it from JSON."
      })

    assert submit["normalized_event"]["outcome"] == "accepted"
    proposed_change_ids = Enum.map(submit["proposed_changes"], & &1["id"])

    duplicate =
      conn
      |> post(~p"/api/manual-intake", %{
        source_identity: "manual:json",
        replay_identity: replay_identity,
        body: "Investigate flaky deploy and prove it from JSON."
      })
      |> json_response(200)

    assert duplicate["normalized_event"]["outcome"] == "duplicate"
    assert duplicate["proposed_changes"] == []

    applied =
      conn
      |> post(~p"/api/proposed-changes/apply", %{ids: proposed_change_ids})
      |> json_response(200)

    conn
    |> post(~p"/api/verification/complete", %{
      verification_check_id: applied["verification_check"]["id"],
      title: "JSON evidence",
      body: "JSON evidence accepted.",
      artifact_uri: "https://example.test/json"
    })
    |> json_response(200)
  end

  defp json_submit(conn, attrs) do
    conn
    |> post(~p"/api/manual-intake", attrs)
    |> json_response(200)
  end

  defp graphql_apply(conn, proposed_change_ids) do
    conn
    |> post(~p"/graphql", %{
      query: """
      mutation Apply($ids: [ID!]!) {
        applyProposedChanges(input: { ids: $ids }) {
          task { id }
        }
      }
      """,
      variables: %{ids: proposed_change_ids}
    })
    |> json_response(200)
  end

  defp graphql(conn, query, variables) do
    response =
      conn
      |> post(~p"/graphql", %{query: query, variables: variables})
      |> json_response(200)

    assert response["errors"] in [nil, []]
    response["data"] |> Map.values() |> hd()
  end
end
