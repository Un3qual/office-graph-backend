defmodule OfficeGraphWeb.GraphQL.OperatorCommands.Resolvers.GitHub do
  @moduledoc false

  alias OfficeGraph.{GitHubIntegration, Operations}
  alias OfficeGraphWeb.GraphQL.Common.Errors
  alias OfficeGraphWeb.OperatorCommands.Input
  alias OfficeGraphWeb.RequestSession

  def bind_installation(%{input: input}, resolution) do
    with {:ok, parsed} <- Input.parse(:bind_github_installation, input),
         {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
         {idempotency_key, attrs} <- Map.pop!(parsed, :idempotency_key),
         {:ok, operation} <-
           Operations.start_command(
             session_context,
             :github_installation_bind,
             idempotency_key,
             attrs
           ),
         {:ok, bound} <- GitHubIntegration.bind_installation(session_context, operation, attrs) do
      {:ok,
       %{
         command: "bind_github_installation",
         operation_id: operation.id,
         affected_ids: [
           %{type: "github_installation", id: bound.installation.id},
           %{type: "github_permission_snapshot", id: bound.permission_snapshot.id}
         ],
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
         permission_snapshot: bound.permission_snapshot,
         permissions: bound.permissions,
         credentials: bound.credentials
       }}
    else
      error -> Errors.to_absinthe(error)
    end
  end
end
