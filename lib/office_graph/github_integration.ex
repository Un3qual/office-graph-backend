defmodule OfficeGraph.GitHubIntegration do
  @moduledoc """
  Authorized boundary for GitHub installation authority and credential metadata.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.Audit,
      OfficeGraph.CommandSupport,
      OfficeGraph.DurableDelivery,
      OfficeGraph.ExternalRefs,
      OfficeGraph.Identity,
      OfficeGraph.Integrations,
      OfficeGraph.Operations,
      OfficeGraph.Repo,
      OfficeGraph.Revisions,
      OfficeGraph.SoftwareProving,
      OfficeGraph.WorkGraph
    ],
    exports: [SecretStore]

  alias OfficeGraph.{Authorization, Operations}

  alias OfficeGraph.GitHubIntegration.{
    Health,
    InstallationCommands,
    OutboundCommands,
    Reconciler,
    ReconciliationRequest,
    StorageResult,
    WebhookReceipt
  }

  @permission_levels ~w(none read write admin)
  @secret_reference ~r/\A(?:[a-z][a-z0-9+.-]*:\/\/\S+|env:[A-Z][A-Z0-9_]*)\z/

  def accept_webhook(headers, raw_body), do: WebhookReceipt.accept(headers, raw_body)

  def reconcile(operation, %ReconciliationRequest{} = request),
    do: Reconciler.reconcile(operation, request)

  def reply_to_review(session_context, operation, attrs),
    do: OutboundCommands.reply_to_review(session_context, operation, attrs)

  def update_check(session_context, operation, attrs),
    do: OutboundCommands.update_check(session_context, operation, attrs)

  def integration_health(session_context, installation_id, opts \\ []),
    do: Health.read(session_context, installation_id, opts)

  def bind_installation(session_context, attrs) when is_map(attrs) do
    with {:ok, idempotency_key} <- required_string(attrs, :idempotency_key),
         {:ok, normalized} <- normalize_binding(session_context, attrs),
         {:ok, operation} <-
           Operations.start_command(
             session_context,
             :github_installation_bind,
             idempotency_key,
             normalized
           ) do
      bind_normalized_installation(session_context, operation, normalized)
    end
  end

  def bind_installation(_session_context, _attrs), do: {:error, :forbidden}

  def bind_installation(session_context, operation, attrs)
      when is_map(operation) and is_map(attrs) do
    with :ok <- Operations.validate_operation_context(session_context, operation),
         :ok <- Operations.validate_operation_action(operation, "github.installation.bind"),
         :ok <- Operations.validate_command_replay(operation, attrs),
         {:ok, normalized} <- normalize_binding(session_context, attrs) do
      bind_normalized_installation(session_context, operation, normalized)
    end
  end

  def bind_installation(_session_context, _operation, _attrs), do: {:error, :forbidden}

  defp bind_normalized_installation(session_context, operation, normalized) do
    with :ok <- authorize_binding(session_context, operation, normalized.workspace_id) do
      persist_binding(session_context, operation, normalized)
    end
  end

  defp authorize_binding(session_context, operation, workspace_id) do
    StorageResult.run(fn ->
      Authorization.authorize_operation(
        session_context,
        operation,
        :github_installation_bind,
        organization_id: session_context.organization_id,
        workspace_id: workspace_id
      )
    end)
  end

  defp normalize_binding(session_context, attrs) do
    with {:ok, external_installation_id} <- positive_integer(attrs, :external_installation_id),
         {:ok, app_slug} <- required_string(attrs, :app_slug),
         {:ok, account_login} <- required_string(attrs, :account_login),
         {:ok, account_type} <- one_of_string(attrs, :account_type, ~w(organization user)),
         {:ok, service_principal_email} <- required_string(attrs, :service_principal_email),
         {:ok, webhook_principal_email} <- required_string(attrs, :webhook_principal_email),
         {:ok, webhook_secret_reference} <- secret_reference(attrs, :webhook_secret_reference),
         {:ok, app_private_key_reference} <-
           secret_reference(attrs, :app_private_key_reference),
         {:ok, permissions} <- normalize_permissions(fetch(attrs, :permissions)),
         {:ok, workspace_id} <- normalize_workspace(session_context, attrs) do
      {:ok,
       %{
         external_installation_id: external_installation_id,
         workspace_id: workspace_id,
         app_slug: app_slug,
         account_login: account_login,
         account_type: account_type,
         service_principal_email: service_principal_email,
         webhook_principal_email: webhook_principal_email,
         webhook_secret_reference: webhook_secret_reference,
         app_private_key_reference: app_private_key_reference,
         permissions: permissions
       }}
    end
  end

  defp normalize_workspace(session_context, attrs) do
    workspace_id =
      if has_key?(attrs, :workspace_id),
        do: fetch(attrs, :workspace_id),
        else: session_context.workspace_id

    if workspace_id in [nil, session_context.workspace_id],
      do: {:ok, workspace_id},
      else: {:error, :forbidden}
  end

  defp normalize_permissions(permissions) when is_list(permissions) and permissions != [] do
    permissions
    |> Enum.reduce_while({:ok, []}, fn permission, {:ok, normalized} ->
      with true <- is_map(permission),
           {:ok, name} <- required_string(permission, :name),
           true <- Regex.match?(~r/^[a-z][a-z0-9_]*$/, name),
           {:ok, access_level} <- one_of_string(permission, :access_level, @permission_levels) do
        {:cont, {:ok, [%{name: name, access_level: access_level} | normalized]}}
      else
        _error -> {:halt, {:error, {:invalid_field, :permissions}}}
      end
    end)
    |> case do
      {:ok, normalized} ->
        sorted = Enum.sort_by(normalized, & &1.name)

        if Enum.uniq_by(sorted, & &1.name) == sorted,
          do: {:ok, sorted},
          else: {:error, {:invalid_field, :permissions}}

      error ->
        error
    end
  end

  defp normalize_permissions(_permissions), do: {:error, {:invalid_field, :permissions}}

  defp persist_binding(session_context, operation, normalized) do
    InstallationCommands.bind(session_context, operation, normalized)
  end

  defp positive_integer(attrs, key) do
    case fetch(attrs, key) do
      value when is_integer(value) and value > 0 ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} when integer > 0 -> {:ok, integer}
          _other -> {:error, {:invalid_field, key}}
        end

      _other ->
        {:error, {:invalid_field, key}}
    end
  end

  defp secret_reference(attrs, key) do
    with {:ok, reference} <- required_string(attrs, key),
         true <- Regex.match?(@secret_reference, reference) do
      {:ok, reference}
    else
      _error -> {:error, {:invalid_field, key}}
    end
  end

  defp one_of_string(attrs, key, allowed) do
    with {:ok, value} <- required_string(attrs, key),
         true <- value in allowed do
      {:ok, value}
    else
      _error -> {:error, {:invalid_field, key}}
    end
  end

  defp required_string(attrs, key) do
    case fetch(attrs, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, {:missing_field, key}}
          normalized -> {:ok, normalized}
        end

      nil ->
        {:error, {:missing_field, key}}

      _other ->
        {:error, {:invalid_field, key}}
    end
  end

  defp fetch(attrs, key), do: Map.get(attrs, key, Map.get(attrs, to_string(key)))

  defp has_key?(attrs, key),
    do: Map.has_key?(attrs, key) or Map.has_key?(attrs, to_string(key))
end
