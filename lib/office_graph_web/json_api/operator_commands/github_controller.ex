defmodule OfficeGraphWeb.JsonApi.OperatorCommands.GitHubController do
  use OfficeGraphWeb, :controller

  alias OfficeGraph.{GitHubIntegration, Operations}
  alias OfficeGraphWeb.JsonApi.Common.Errors
  alias OfficeGraphWeb.JsonApi.OperatorCommands.Serializer
  alias OfficeGraphWeb.OperatorCommands.Input
  alias OfficeGraphWeb.RequestSession

  def bind_installation(conn, params) do
    command = "bind_github_installation"

    with {:ok, parsed} <- Input.parse(:bind_github_installation, params),
         {:ok, session_context} <- request_session(conn),
         {idempotency_key, attrs} <- Map.pop!(parsed, :idempotency_key),
         {:ok, operation} <-
           Operations.start_command(
             session_context,
             :github_installation_bind,
             idempotency_key,
             attrs
           ),
         {:ok, bound} <- GitHubIntegration.bind_installation(session_context, operation, attrs) do
      Serializer.render(
        conn,
        command,
        operation.id,
        [
          %{type: "github_installation", id: bound.installation.id},
          %{type: "github_permission_snapshot", id: bound.permission_snapshot.id}
        ],
        %{
          installation: %{
            id: bound.installation.id,
            organization_id: bound.installation.organization_id,
            workspace_id: bound.installation.workspace_id,
            external_installation_id:
              Integer.to_string(bound.installation.external_installation_id),
            lifecycle_state: bound.installation.lifecycle_state,
            service_principal_id: bound.installation.service_principal_id,
            webhook_principal_id: bound.installation.webhook_principal_id
          },
          permission_snapshot: %{
            id: bound.permission_snapshot.id,
            version: bound.permission_snapshot.version
          },
          permissions:
            Enum.map(bound.permissions, &%{name: &1.name, access_level: &1.access_level}),
          credentials: Enum.map(bound.credentials, &Map.take(&1, [:id, :purpose, :kind, :status]))
        }
      )
    else
      error -> Errors.render(conn, error, command: command)
    end
  end

  defp request_session(conn) do
    conn
    |> Ash.PlugHelpers.get_actor()
    |> RequestSession.resolve()
  end
end
