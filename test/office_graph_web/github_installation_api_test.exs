defmodule OfficeGraphWeb.GitHubInstallationApiTest do
  use OfficeGraphWeb.ConnCase, async: false

  test "GraphQL binds an installation idempotently without disclosing secret references", %{
    conn: conn
  } do
    input = graphql_input("graphql")

    mutation = """
    mutation BindGitHub($input: BindGithubInstallationInput!) {
      bindGithubInstallation(input: $input) {
        command
        operationId
        affectedIds { type id }
        installation {
          id
          organizationId
          workspaceId
          externalInstallationId
          lifecycleState
          servicePrincipalId
          webhookPrincipalId
        }
        permissionSnapshot { id version }
        permissions { name accessLevel }
        credentials { id purpose kind status }
      }
    }
    """

    first = graphql(conn, mutation, %{input: input})
    replay = graphql(conn, mutation, %{input: input})

    assert replay == first
    assert first["command"] == "bind_github_installation"
    assert is_binary(first["operationId"])
    assert first["installation"]["externalInstallationId"] == input.externalInstallationId
    assert first["installation"]["lifecycleState"] == "active"
    assert first["permissionSnapshot"]["version"] == 1
    assert Enum.map(first["permissions"], & &1["name"]) == ["checks", "pull_requests"]

    assert Enum.sort(Enum.map(first["credentials"], & &1["purpose"])) == [
             "app_private_key",
             "webhook_secret"
           ]

    encoded = Jason.encode!(first)
    refute encoded =~ input.webhookSecretReference
    refute encoded =~ input.appPrivateKeyReference
  end

  test "JSON exposes the same installation command and safe result", %{conn: conn} do
    input = json_input("json")

    first =
      conn
      |> post("/api/v1/commands/bind-github-installation", input)
      |> json_response(200)

    replay =
      build_conn()
      |> post("/api/v1/commands/bind-github-installation", input)
      |> json_response(200)

    assert replay == first
    assert first["command"] == "bind_github_installation"
    assert is_binary(first["operation_id"])

    assert first["result"]["installation"]["external_installation_id"] ==
             input.external_installation_id

    assert first["result"]["permission_snapshot"]["version"] == 1
    assert Enum.map(first["result"]["permissions"], & &1["name"]) == ["checks", "pull_requests"]

    encoded = Jason.encode!(first)
    refute encoded =~ input.webhook_secret_reference
    refute encoded =~ input.app_private_key_reference
  end

  defp graphql(conn, query, variables) do
    response =
      conn
      |> post(~p"/graphql", %{query: query, variables: variables})
      |> json_response(200)

    assert response["errors"] in [nil, []], inspect(response["errors"])
    response["data"] |> Map.values() |> hd()
  end

  defp graphql_input(label) do
    unique = System.unique_integer([:positive])

    %{
      idempotencyKey: "bind-github-#{label}-#{unique}",
      externalInstallationId: Integer.to_string(unique),
      appSlug: "office-graph",
      accountLogin: "Un3qual",
      accountType: "organization",
      servicePrincipalEmail: "github-service-#{label}-#{unique}@office-graph.local",
      webhookPrincipalEmail: "github-webhook-#{label}-#{unique}@office-graph.local",
      webhookSecretReference: "test-secret://github/#{label}/#{unique}/webhook",
      appPrivateKeyReference: "test-secret://github/#{label}/#{unique}/private-key",
      permissions: [
        %{name: "pull_requests", accessLevel: "read"},
        %{name: "checks", accessLevel: "write"}
      ]
    }
  end

  defp json_input(label) do
    unique = System.unique_integer([:positive])

    %{
      idempotency_key: "bind-github-#{label}-#{unique}",
      external_installation_id: Integer.to_string(unique),
      app_slug: "office-graph",
      account_login: "Un3qual",
      account_type: "organization",
      service_principal_email: "github-service-#{label}-#{unique}@office-graph.local",
      webhook_principal_email: "github-webhook-#{label}-#{unique}@office-graph.local",
      webhook_secret_reference: "test-secret://github/#{label}/#{unique}/webhook",
      app_private_key_reference: "test-secret://github/#{label}/#{unique}/private-key",
      permissions: [
        %{name: "pull_requests", access_level: "read"},
        %{name: "checks", access_level: "write"}
      ]
    }
  end
end
