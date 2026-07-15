defmodule OfficeGraph.GitHubIntegration.Health do
  @moduledoc false

  alias OfficeGraph.Authorization

  alias OfficeGraph.GitHubIntegration.{
    Installation,
    InstallationCredential,
    OutboundAction,
    PermissionEntry,
    SyncOutcome
  }

  alias OfficeGraph.Integrations.IntegrationCredential

  @required_write_permissions ~w(checks pull_requests)

  require Ash.Query

  def read(session_context, installation_id, opts \\ [])

  def read(session_context, installation_id, opts) when is_binary(installation_id) do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()

    with :ok <-
           Authorization.authorize_projection(session_context, :skeleton_read,
             organization_id: session_context.organization_id
           ),
         {:ok, installation} <- authorized_installation(session_context, installation_id) do
      permissions = permissions(installation)
      credentials = credentials(installation)
      outcomes = recent_failure_outcomes(installation.id, limit)
      actions = recent_failure_actions(installation.id, limit)
      last_success = last_success(installation.id)

      {:ok,
       view(
         installation,
         permissions,
         credentials,
         outcomes,
         actions,
         last_success,
         limit
       )}
    end
  end

  def read(_session_context, _installation_id, _opts), do: {:error, :forbidden}

  defp authorized_installation(session_context, installation_id) do
    case Ash.get(Installation, installation_id, authorize?: false, not_found_error?: false) do
      {:ok,
       %Installation{organization_id: organization_id, workspace_id: workspace_id} = installation}
      when organization_id == session_context.organization_id and
             workspace_id in [nil, session_context.workspace_id] ->
        {:ok, installation}

      _missing_or_cross_scope ->
        {:error, :forbidden}
    end
  end

  defp permissions(%{current_permission_snapshot_id: nil}), do: []

  defp permissions(installation) do
    PermissionEntry
    |> Ash.Query.filter(permission_snapshot_id == ^installation.current_permission_snapshot_id)
    |> Ash.Query.sort(name: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp credentials(installation) do
    bindings =
      InstallationCredential
      |> Ash.Query.filter(installation_id == ^installation.id)
      |> Ash.read!(authorize?: false)

    credential_ids = Enum.map(bindings, & &1.credential_id)

    credentials =
      if credential_ids == [] do
        []
      else
        IntegrationCredential
        |> Ash.Query.filter(id in ^credential_ids)
        |> Ash.read!(authorize?: false)
      end

    by_id = Map.new(credentials, &{&1.id, &1})

    Enum.map(bindings, fn binding ->
      credential = Map.get(by_id, binding.credential_id)
      %{purpose: binding.purpose, status: credential && credential.status}
    end)
  end

  defp recent_failure_outcomes(installation_id, limit) do
    SyncOutcome
    |> Ash.Query.filter(
      installation_id == ^installation_id and
        state in ["retryable", "terminal", "authorization", "configuration"]
    )
    |> Ash.Query.sort(updated_at: :desc, id: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.read!(authorize?: false)
  end

  defp recent_failure_actions(installation_id, limit) do
    OutboundAction
    |> Ash.Query.filter(
      installation_id == ^installation_id and state in ["retryable", "terminal"]
    )
    |> Ash.Query.sort(updated_at: :desc, id: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.read!(authorize?: false)
  end

  defp last_success(installation_id) do
    SyncOutcome
    |> Ash.Query.filter(installation_id == ^installation_id and state == "reconciled")
    |> Ash.Query.sort(updated_at: :desc, id: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(authorize?: false)
  end

  defp view(installation, permissions, credentials, outcomes, actions, last_success, limit) do
    failures = failure_summaries(outcomes, actions, limit)

    %{
      installation_id: installation.id,
      lifecycle: installation.lifecycle_state,
      account_login: installation.account_login,
      permission_posture: permission_posture(permissions),
      permissions: Enum.map(permissions, &%{name: &1.name, access_level: &1.access_level}),
      credential_posture: credential_posture(credentials),
      credentials: credentials,
      last_success_at: last_success && last_success.updated_at,
      retryable_count: Enum.count(failures, &(&1.class == "retryable")),
      terminal_count: Enum.count(failures, &(&1.class == "terminal")),
      remediation_code: remediation_code(installation, permissions, credentials, failures),
      recent_failures: failures
    }
  end

  defp failure_summaries(outcomes, actions, limit) do
    outcome_failures =
      outcomes
      |> Enum.filter(&(&1.state in ~w(retryable terminal authorization configuration)))
      |> Enum.map(fn outcome ->
        %{
          kind: "reconciliation",
          class: outcome.failure_class || outcome.state,
          code: outcome.failure_code || "integration_failure",
          occurred_at: outcome.updated_at
        }
      end)

    action_failures =
      actions
      |> Enum.filter(&(&1.state in ~w(retryable terminal)))
      |> Enum.map(fn action ->
        %{
          kind: action.action_kind,
          class: action.failure_class || action.state,
          code: action.failure_code || "integration_failure",
          occurred_at: action.attempted_at || action.inserted_at
        }
      end)

    (outcome_failures ++ action_failures)
    |> Enum.sort_by(& &1.occurred_at, {:desc, DateTime})
    |> Enum.take(limit)
  end

  defp permission_posture([]), do: "missing"

  defp permission_posture(permissions) do
    access_by_name = Map.new(permissions, &{&1.name, &1.access_level})

    if Enum.all?(
         @required_write_permissions,
         &(Map.get(access_by_name, &1) in ~w(write admin))
       ),
      do: "configured",
      else: "insufficient"
  end

  defp credential_posture(credentials) do
    active_purposes =
      credentials
      |> Enum.filter(&(&1.status == "active"))
      |> Enum.map(& &1.purpose)

    if Enum.all?(~w(webhook_secret app_private_key), &(&1 in active_purposes)),
      do: "active",
      else: "invalid"
  end

  defp remediation_code(
         %{lifecycle_state: "revoked"},
         _permissions,
         _credentials,
         _failures
       ),
    do: "reauthorize_installation"

  defp remediation_code(_installation, _permissions, credentials, _failures)
       when credentials == [],
       do: "configure_credentials"

  defp remediation_code(_installation, permissions, credentials, failures) do
    cond do
      credential_posture(credentials) != "active" -> "rotate_credentials"
      permission_posture(permissions) != "configured" -> "reauthorize_installation"
      Enum.any?(failures, &(&1.code == "installation_revoked")) -> "reauthorize_installation"
      Enum.any?(failures, &(&1.code == "invalid_credential")) -> "rotate_credentials"
      Enum.any?(failures, &(&1.code == "adapter_unavailable")) -> "configure_adapter"
      true -> nil
    end
  end

  defp normalize_limit(limit) when is_integer(limit), do: limit |> max(1) |> min(50)
  defp normalize_limit(_limit), do: 20
end
