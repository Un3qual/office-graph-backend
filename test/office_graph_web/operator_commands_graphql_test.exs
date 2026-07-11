defmodule OfficeGraphWeb.OperatorCommandsGraphQLTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.Integrations.RawArchive

  require Ash.Query

  test "manual intake is a server-owned idempotent GraphQL command", %{conn: conn} do
    input = %{
      idempotencyKey: "graphql-manual-intake",
      sourceIdentity: "manual:graphql-command",
      replayIdentity: "paste:graphql-command",
      body: "Investigate the GraphQL operator command loop."
    }

    mutation = """
    mutation Submit($input: SubmitManualIntakeInput!) {
      submitManualIntake(input: $input) {
        command
        operationId
        normalizedEventId
        proposedChangeIds
        affectedIds { type id }
      }
    }
    """

    first = graphql(conn, mutation, %{input: input})
    replay = graphql(conn, mutation, %{input: input})

    assert first["command"] == "submit_manual_intake"
    assert is_binary(first["operationId"])
    assert is_binary(first["normalizedEventId"])
    assert length(first["proposedChangeIds"]) == 4
    assert replay == first

    conflict =
      raw_graphql(conn, mutation, %{
        input: %{input | body: "Changed command input."}
      })

    assert [%{"extensions" => %{"code" => "idempotency_conflict"}}] = conflict["errors"]
  end

  test "manual intake preserves leading and trailing body whitespace", %{conn: conn} do
    body = "\n  pasted log line  \n"

    result =
      graphql(
        conn,
        """
        mutation Submit($input: SubmitManualIntakeInput!) {
          submitManualIntake(input: $input) { operationId }
        }
        """,
        %{
          input: %{
            idempotencyKey: "graphql-manual-whitespace",
            sourceIdentity: "manual:graphql-whitespace",
            replayIdentity: "paste:graphql-whitespace",
            body: body
          }
        }
      )

    archive =
      RawArchive
      |> Ash.Query.filter(operation_id == ^result["operationId"])
      |> Ash.read_one!(authorize?: false)

    assert archive.body == body
  end

  defp graphql(conn, query, variables) do
    response = raw_graphql(conn, query, variables)
    assert response["errors"] in [nil, []]
    response["data"] |> Map.values() |> hd()
  end

  defp raw_graphql(conn, query, variables) do
    conn
    |> post(~p"/graphql", %{query: query, variables: variables})
    |> json_response(200)
  end
end
