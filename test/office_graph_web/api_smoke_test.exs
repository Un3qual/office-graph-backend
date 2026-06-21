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
      conn
      |> post(~p"/api/manual-intake", %{
        source_identity: "manual:json",
        replay_identity: replay_identity,
        body: "Investigate flaky deploy and prove it from JSON."
      })
      |> json_response(200)

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

  defp graphql(conn, query, variables) do
    response =
      conn
      |> post(~p"/graphql", %{query: query, variables: variables})
      |> json_response(200)

    assert response["errors"] in [nil, []]
    response["data"] |> Map.values() |> hd()
  end
end
