defmodule OfficeGraph.GitHubIntegration do
  @moduledoc """
  Authorized boundary for GitHub installation authority and credential metadata.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.Audit,
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

  require Ash.Query

  alias OfficeGraph.{Authorization, Identity, Operations, Repo}

  alias OfficeGraph.GitHubIntegration.{
    Installation,
    InstallationCredential,
    Health,
    OutboundCommands,
    PermissionEntry,
    PermissionSnapshot,
    Reconciler,
    ReconciliationRequest,
    WebhookReceipt
  }

  alias OfficeGraph.Integrations.IntegrationCredential

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
    with :ok <-
           Authorization.authorize_operation(
             session_context,
             operation,
             :github_installation_bind,
             organization_id: session_context.organization_id,
             workspace_id: normalized.workspace_id
           ) do
      persist_binding(session_context, operation, normalized)
    end
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

  defp installation_available?(session_context, operation, normalized) do
    case installation_by_external_id(normalized.external_installation_id) do
      {:ok, nil} ->
        :ok

      {:ok, %Installation{organization_id: organization_id, operation_id: operation_id}}
      when organization_id == session_context.organization_id and operation_id == operation.id ->
        :ok

      _other ->
        {:error, :forbidden}
    end
  end

  defp persist_binding(session_context, operation, normalized) do
    Repo.transaction(fn ->
      with {:ok, _locked_operation} <- Operations.lock_operation(operation.id) do
        lock_installation!(normalized.external_installation_id)

        with :ok <- installation_available?(session_context, operation, normalized),
             {:ok, existing} <- installation_by_operation(operation.id) do
          case existing do
            nil -> create_binding!(session_context, operation, normalized)
            installation -> binding_result(operation, installation)
          end
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp create_binding!(session_context, operation, attrs) do
    service_principal =
      ensure_system_principal!(attrs.service_principal_email, "service")

    webhook_principal =
      ensure_system_principal!(attrs.webhook_principal_email, "webhook")

    ensure_system_role!(
      webhook_principal,
      %{organization_id: session_context.organization_id, workspace_id: nil},
      [:provider_webhook_receive]
    )

    ensure_system_role!(
      service_principal,
      %{
        organization_id: session_context.organization_id,
        workspace_id: attrs.workspace_id
      },
      [:integration_reconcile]
    )

    installation =
      Repo.ash_create!(Installation, %{
        id: Ecto.UUID.generate(),
        organization_id: session_context.organization_id,
        workspace_id: attrs.workspace_id,
        external_installation_id: attrs.external_installation_id,
        app_slug: attrs.app_slug,
        account_login: attrs.account_login,
        account_type: attrs.account_type,
        service_principal_id: service_principal.id,
        webhook_principal_id: webhook_principal.id,
        lifecycle_state: "active",
        operation_id: operation.id
      })

    snapshot =
      Repo.ash_create!(PermissionSnapshot, %{
        id: Ecto.UUID.generate(),
        installation_id: installation.id,
        version: 1,
        captured_at: DateTime.utc_now(),
        operation_id: operation.id
      })

    permissions =
      Enum.map(attrs.permissions, fn permission ->
        Repo.ash_create!(
          PermissionEntry,
          Map.merge(permission, %{
            id: Ecto.UUID.generate(),
            permission_snapshot_id: snapshot.id
          })
        )
      end)

    installation =
      installation
      |> Ash.Changeset.for_update(:set_permission_snapshot, %{
        current_permission_snapshot_id: snapshot.id
      })
      |> Repo.ash_update!()

    credentials = [
      create_credential_binding!(
        session_context,
        operation,
        installation,
        "webhook_secret",
        attrs.webhook_secret_reference
      ),
      create_credential_binding!(
        session_context,
        operation,
        installation,
        "app_private_key",
        attrs.app_private_key_reference
      )
    ]

    result(operation, installation, snapshot, permissions, credentials)
  end

  defp ensure_system_role!(principal, scope, actions) do
    case Authorization.ensure_system_role(principal, scope, actions) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp create_credential_binding!(session_context, operation, installation, purpose, reference) do
    lookup = [
      organization_id: session_context.organization_id,
      workspace_id: installation.workspace_id,
      kind: "secret_reference",
      secret_reference: reference
    ]

    credential =
      Repo.get_or_insert!(
        IntegrationCredential,
        lookup,
        %{
          organization_id: session_context.organization_id,
          workspace_id: installation.workspace_id,
          kind: "secret_reference",
          secret_reference: reference,
          status: "active",
          operation_id: operation.id
        },
        &credential_insert_contract/2,
        &credential_by_reference/2
      )

    if credential.status != "active" or
         credential.organization_id != session_context.organization_id or
         credential.workspace_id != installation.workspace_id do
      Repo.rollback(:forbidden)
    end

    binding =
      Repo.ash_create!(InstallationCredential, %{
        id: Ecto.UUID.generate(),
        installation_id: installation.id,
        credential_id: credential.id,
        purpose: purpose,
        operation_id: operation.id
      })

    safe_credential(binding, credential)
  end

  defp binding_result(operation, installation) do
    snapshot =
      Ash.get!(PermissionSnapshot, installation.current_permission_snapshot_id, authorize?: false)

    permissions =
      PermissionEntry
      |> Ash.Query.filter(permission_snapshot_id == ^snapshot.id)
      |> Ash.Query.sort(name: :asc)
      |> Ash.read!(authorize?: false)

    credentials =
      InstallationCredential
      |> Ash.Query.filter(installation_id == ^installation.id)
      |> Ash.Query.sort(purpose: :asc)
      |> Ash.read!(authorize?: false)
      |> Enum.map(fn binding ->
        credential = Ash.get!(IntegrationCredential, binding.credential_id, authorize?: false)
        safe_credential(binding, credential)
      end)

    result(operation, installation, snapshot, permissions, credentials)
  end

  defp result(operation, installation, snapshot, permissions, credentials) do
    %{
      operation: operation,
      installation: installation,
      permission_snapshot: snapshot,
      permissions: Enum.sort_by(permissions, & &1.name),
      credentials: Enum.sort_by(credentials, & &1.purpose)
    }
  end

  defp safe_credential(binding, credential) do
    %{
      id: binding.id,
      credential_id: credential.id,
      purpose: binding.purpose,
      kind: credential.kind,
      status: credential.status
    }
  end

  defp ensure_system_principal!(email, kind) do
    case Identity.ensure_system_principal(email, kind) do
      {:ok, principal} -> principal
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp installation_by_external_id(external_installation_id) do
    Installation
    |> Ash.Query.filter(external_installation_id == ^external_installation_id)
    |> Ash.read_one(authorize?: false)
  end

  defp installation_by_operation(operation_id) do
    Installation
    |> Ash.Query.filter(operation_id == ^operation_id)
    |> Ash.read_one(authorize?: false)
  end

  defp credential_by_reference(IntegrationCredential, lookup) do
    organization_id = Keyword.fetch!(lookup, :organization_id)
    workspace_id = Keyword.fetch!(lookup, :workspace_id)
    kind = Keyword.fetch!(lookup, :kind)
    secret_reference = Keyword.fetch!(lookup, :secret_reference)

    query =
      IntegrationCredential
      |> Ash.Query.filter(
        organization_id == ^organization_id and kind == ^kind and
          secret_reference == ^secret_reference
      )

    query =
      if is_nil(workspace_id),
        do: Ash.Query.filter(query, is_nil(workspace_id)),
        else: Ash.Query.filter(query, workspace_id == ^workspace_id)

    Ash.read_one(query, authorize?: false)
  end

  defp credential_insert_contract(IntegrationCredential, %{workspace_id: nil}) do
    {
      "integration_credentials",
      {:unsafe_fragment, "(organization_id, kind, secret_reference) WHERE workspace_id IS NULL"},
      [:id, :organization_id, :operation_id]
    }
  end

  defp credential_insert_contract(IntegrationCredential, _attrs) do
    {
      "integration_credentials",
      {:unsafe_fragment,
       "(organization_id, workspace_id, kind, secret_reference) WHERE workspace_id IS NOT NULL"},
      [:id, :organization_id, :workspace_id, :operation_id]
    }
  end

  defp lock_installation!(external_installation_id) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      "github:installation:#{external_installation_id}"
    ])
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
