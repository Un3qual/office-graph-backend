defmodule OfficeGraphWeb.GitHubActionsApiTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.{Foundation, GitHubIntegration, Repo}
  alias OfficeGraphWeb.OperatorCommands.Input

  setup do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    unique = System.unique_integer([:positive])

    {:ok, bound} =
      GitHubIntegration.bind_installation(bootstrap.session, %{
        idempotency_key: "bind-actions-api-#{unique}",
        external_installation_id: unique,
        workspace_id: bootstrap.workspace.id,
        app_slug: "office-graph",
        account_login: "Un3qual",
        account_type: "organization",
        service_principal_email: "github-service-actions-api-#{unique}@office-graph.local",
        webhook_principal_email: "github-webhook-actions-api-#{unique}@office-graph.local",
        webhook_secret_reference: "test-secret://github/actions-api/#{unique}/webhook",
        app_private_key_reference: "test-secret://github/actions-api/#{unique}/private-key",
        permissions: [
          %{name: "checks", access_level: "write"},
          %{name: "pull_requests", access_level: "write"}
        ]
      })

    {:ok, installation: bound.installation}
  end

  test "GraphQL and JSON expose the same bounded safe health posture", %{
    conn: conn,
    installation: installation
  } do
    query = """
    query GitHubHealth($installationId: ID!) {
      githubIntegrationHealth(installationId: $installationId, limit: 50) {
        installationId
        lifecycle
        accountLogin
        permissionPosture
        permissions { name accessLevel }
        credentialPosture
        credentials { purpose status }
        lastSuccessAt
        retryableCount
        terminalCount
        remediationCode
        recentFailures { kind class code occurredAt }
      }
    }
    """

    graphql = graphql(conn, query, %{installationId: installation.id})

    json =
      build_conn()
      |> get("/api/v1/github/installations/#{installation.id}/health?limit=50")
      |> json_response(200)
      |> Map.fetch!("data")

    assert graphql["installationId"] == installation.id
    assert graphql["lifecycle"] == "active"
    assert graphql["permissionPosture"] == "configured"
    assert graphql["credentialPosture"] == "active"
    assert graphql["retryableCount"] == 0
    assert graphql["terminalCount"] == 0

    assert json["installation_id"] == graphql["installationId"]
    assert json["lifecycle"] == graphql["lifecycle"]
    assert json["permission_posture"] == graphql["permissionPosture"]
    assert json["credential_posture"] == graphql["credentialPosture"]

    encoded = Jason.encode!(%{graphql: graphql, json: json})
    refute encoded =~ "test-secret://"
    refute encoded =~ "private-key"
    refute encoded =~ "raw_archive"
  end

  test "only the two approved GitHub outbound mutations and routes are exposed", %{
    conn: conn,
    installation: installation
  } do
    introspection = "{ __schema { mutationType { fields { name } } } }"

    response =
      conn
      |> post(~p"/graphql", %{query: introspection})
      |> json_response(200)

    names = Enum.map(response["data"]["__schema"]["mutationType"]["fields"], & &1["name"])
    assert "replyToGithubReview" in names
    assert "updateGithubCheck" in names
    refute "mergeGithubPullRequest" in names
    refute "createGithubBranch" in names
    refute "commitToGithubRepository" in names

    payload = %{
      idempotency_key: "reply-api-missing-target",
      installation_id: installation.id,
      review_comment_id: Ecto.UUID.generate(),
      body: "Safe reply",
      expected_provider_version: "v1"
    }

    error =
      build_conn()
      |> post("/api/v1/commands/reply-to-github-review", payload)
      |> json_response(403)

    assert error["command"] == "reply_to_github_review"
    assert error["error"]["code"] == "forbidden"
  end

  test "public check-update input accepts an omitted conclusion for progress states" do
    assert {:ok, parsed} =
             Input.parse(:update_github_check, %{
               idempotency_key: "check-progress-input",
               installation_id: Ecto.UUID.generate(),
               check_run_id: Ecto.UUID.generate(),
               status: "in_progress",
               details_url: "https://example.test/checks/progress",
               expected_provider_version: "v1"
             })

    refute Map.has_key?(parsed, :conclusion)
  end

  test "JSON command start storage outages return only the safe availability response" do
    Repo.query!("""
    ALTER TABLE operation_correlations
    ADD CONSTRAINT test_github_command_start_storage
    CHECK (action <> 'github.review.reply')
    """)

    response =
      try do
        build_conn()
        |> post("/api/v1/commands/reply-to-github-review", %{
          idempotency_key: "reply-api-operation-storage",
          installation_id: Ecto.UUID.generate(),
          review_comment_id: Ecto.UUID.generate(),
          body: "Retry after operation storage recovers.",
          expected_provider_version: "v1"
        })
        |> json_response(503)
      after
        Repo.query!("""
        ALTER TABLE operation_correlations
        DROP CONSTRAINT test_github_command_start_storage
        """)
      end

    assert response["command"] == "reply_to_github_review"
    assert response["error"]["code"] == "integration_storage_unavailable"
    refute inspect(response) =~ "Ash.Error"
    refute inspect(response) =~ "Postgrex"
  end

  defp graphql(conn, query, variables) do
    response =
      conn
      |> post(~p"/graphql", %{query: query, variables: variables})
      |> json_response(200)

    assert response["errors"] in [nil, []], inspect(response["errors"])
    response["data"] |> Map.values() |> hd()
  end
end
