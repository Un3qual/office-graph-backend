defmodule OfficeGraphWeb.ApiSmokeTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.Foundation
  alias OfficeGraph.ProposedChanges.ProposedGraphChange

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

    test "JSON manual intake reports missing body without crashing", %{conn: conn} do
      response =
        conn
        |> post(~p"/api/manual-intake", %{
          source_identity: "manual:json-missing-body",
          replay_identity: "json-missing-body"
        })
        |> json_response(422)

      assert response["error"]["code"] == "validation_failed"
      assert response["error"]["field"] == "body"

      response =
        conn
        |> post(~p"/api/manual-intake", %{
          source_identity: "manual:json-null-body",
          replay_identity: "json-null-body",
          body: nil
        })
        |> json_response(422)

      assert response["error"]["code"] == "validation_failed"
      assert response["error"]["field"] == "body"
    end

    test "JSON apply reports invalid proposed-change sets without crashing", %{conn: conn} do
      response =
        conn
        |> post(~p"/api/proposed-changes/apply", %{ids: []})
        |> json_response(422)

      assert response["error"]["code"] == "invalid_proposed_change_set"
      assert response["error"]["reason"]["kind"] == "missing_change_type"
    end

    test "JSON apply rejects non-array ids before querying proposed changes", %{conn: conn} do
      response =
        conn
        |> post(~p"/api/proposed-changes/apply", %{ids: "not-a-list"})
        |> json_response(422)

      assert response["error"]["code"] == "validation_failed"
      assert response["error"]["field"] == "ids"
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

    test "JSON complete reports missing verification checks without creating an operation", %{
      conn: conn
    } do
      missing_id = Ecto.UUID.generate()

      response =
        conn
        |> post(~p"/api/verification/complete", %{
          verification_check_id: missing_id,
          title: "Missing check",
          body: "This check does not exist.",
          artifact_uri: "https://example.test/missing-check"
        })
        |> json_response(422)

      assert response["error"]["code"] == "missing_verification_check"
      assert response["error"]["verification_check_id"] == missing_id
    end

    test "JSON complete reports repeated verification completion without duplicate evidence", %{
      conn: conn
    } do
      submit =
        json_submit(conn, %{
          source_identity: "manual:json-repeat-complete",
          replay_identity: "json-repeat-complete-#{System.unique_integer([:positive])}",
          body: "Investigate repeated verification completion."
        })

      proposed_change_ids = Enum.map(submit["proposed_changes"], & &1["id"])

      applied =
        conn
        |> post(~p"/api/proposed-changes/apply", %{ids: proposed_change_ids})
        |> json_response(200)

      attrs = %{
        verification_check_id: applied["verification_check"]["id"],
        title: "Repeated evidence",
        body: "Evidence should only be accepted once.",
        artifact_uri: "https://example.test/repeated-evidence"
      }

      conn
      |> post(~p"/api/verification/complete", attrs)
      |> json_response(200)

      response =
        conn
        |> post(~p"/api/verification/complete", attrs)
        |> json_response(422)

      assert response["error"]["code"] == "invalid_verification_check_status"
      assert response["error"]["verification_check_id"] == applied["verification_check"]["id"]
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

    test "GraphQL apply reports invalid proposed-change sets without crashing", %{conn: conn} do
      response = graphql_apply(conn, [])

      assert [%{"extensions" => %{"code" => "invalid_proposed_change_set"}} = error] =
               response["errors"]

      assert error["extensions"]["reason"]["kind"] == "missing_change_type"
      assert response["data"] in [nil, %{"applyProposedChanges" => nil}]
    end

    test "GraphQL apply preserves invalid proposed-change details", %{conn: conn} do
      submit =
        graphql(conn, submit_query(), %{
          replayIdentity: "graphql-invalid-change-#{System.unique_integer([:positive])}"
        })

      {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
      proposed_change_ids = Enum.map(submit["proposedChanges"], & &1["id"])
      [invalid_id | _rest] = proposed_change_ids

      ProposedGraphChange
      |> Ash.get!(invalid_id, actor: bootstrap.session)
      |> Ash.Changeset.for_update(:set_payload, %{payload: %{"body" => "missing title"}})
      |> Ash.update!(actor: bootstrap.session)

      response = graphql_apply(conn, proposed_change_ids)

      assert [%{"extensions" => %{"code" => "invalid_proposed_change"}} = error] =
               response["errors"]

      assert error["extensions"]["proposed_change_id"] == invalid_id
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

    test "GraphQL complete reports missing verification checks without crashing", %{conn: conn} do
      missing_id = Ecto.UUID.generate()

      response =
        conn
        |> post(~p"/graphql", %{
          query: """
          mutation Complete($checkId: ID!) {
            completeVerification(input: {
              verificationCheckId: $checkId,
              title: "Missing GraphQL check",
              body: "This check does not exist.",
              artifactUri: "https://example.test/graphql-missing"
            }) {
              verificationCheck { id }
            }
          }
          """,
          variables: %{checkId: missing_id}
        })
        |> json_response(200)

      assert [%{"extensions" => %{"code" => "missing_verification_check"}} = error] =
               response["errors"]

      assert error["extensions"]["verification_check_id"] == missing_id
      assert response["data"] in [nil, %{"completeVerification" => nil}]
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
