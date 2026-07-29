defmodule OfficeGraph.GitHubIntegration.BindingCredential do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :id, :uuid, allow_nil?: false
    field :credential_id, :uuid, allow_nil?: false
    field :purpose, :string, allow_nil?: false
    field :kind, :string, allow_nil?: false
    field :status, :string, allow_nil?: false
  end

  def build!(binding, credential) do
    new!(
      id: binding.id,
      credential_id: credential.id,
      purpose: binding.purpose,
      kind: credential.kind,
      status: credential.status
    )
  end
end

defmodule OfficeGraph.GitHubIntegration.BindingResult do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :operation, :struct,
      allow_nil?: false,
      constraints: [instance_of: Module.concat([OfficeGraph, Operations, OperationCorrelation])]

    field :installation, :struct,
      allow_nil?: false,
      constraints: [
        instance_of: Module.concat([OfficeGraph, GitHubIntegration, Installation])
      ]

    field :permission_snapshot, :struct,
      allow_nil?: false,
      constraints: [
        instance_of: Module.concat([OfficeGraph, GitHubIntegration, PermissionSnapshot])
      ]

    field :permissions, {:array, :struct},
      allow_nil?: false,
      constraints: [
        items: [
          instance_of: Module.concat([OfficeGraph, GitHubIntegration, PermissionEntry])
        ]
      ]

    field :credentials, {:array, OfficeGraph.GitHubIntegration.BindingCredential},
      allow_nil?: false
  end

  def build!(operation, installation, snapshot, permissions, credentials) do
    new!(
      operation: operation,
      installation: installation,
      permission_snapshot: snapshot,
      permissions: Enum.sort_by(permissions, & &1.name),
      credentials: Enum.sort_by(credentials, & &1.purpose)
    )
  end
end

defmodule OfficeGraph.GitHubIntegration.InstallationCommands do
  @moduledoc false

  @behaviour Ash.Resource.Actions.Implementation

  alias OfficeGraph.{Authorization, CommandSupport, Identity, Operations}

  alias OfficeGraph.GitHubIntegration.{
    ActionSupport,
    BindingCredential,
    BindingResult,
    Installation,
    InstallationBindingStore,
    InstallationCredential,
    PermissionEntry,
    PermissionSnapshot,
    RecordLoader,
    StorageResult
  }

  alias OfficeGraph.Integrations.IntegrationCredential

  require Ash.Query

  @identity_constraints ~w[
    github_installations_external_installation_id_index
    integration_credentials_workspace_reference_index
    integration_credentials_organization_reference_index
  ]

  @impl true
  def run(input, [mode: :bind], %{actor: session_context}) when is_map(session_context) do
    case persist_binding_records(session_context, input.arguments) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> ActionSupport.rollback(Installation, error)
    end
  end

  def run(_input, _opts, _context), do: {:error, :forbidden}

  def bind(session_context, operation, attrs) do
    StorageResult.run(fn ->
      action = fn ->
        Installation
        |> Ash.ActionInput.for_action(
          :persist_binding_contract,
          attrs
          |> Map.new()
          |> Map.put(:operation_id, operation.id)
        )
        |> InstallationBindingStore.persist(actor: session_context, authorize?: false)
      end

      action
      |> run_with_identity_retry()
      |> ActionSupport.normalize_action_result()
    end)
  end

  defp persist_binding_records(session_context, attrs) do
    with {:ok, operation} <- Operations.lock_operation(attrs.operation_id),
         {:ok, existing} <- installation_by_operation(operation.id) do
      case existing do
        nil -> create_binding(session_context, operation, attrs)
        installation -> replay_binding(session_context, operation, installation, attrs)
      end
    end
  end

  defp create_binding(session_context, operation, attrs) do
    with {:ok, service_principal} <-
           Identity.ensure_system_principal(attrs.service_principal_email, "service"),
         {:ok, webhook_principal} <-
           Identity.ensure_system_principal(attrs.webhook_principal_email, "webhook"),
         :ok <-
           Authorization.ensure_system_role(
             webhook_principal,
             %{organization_id: session_context.organization_id, workspace_id: nil},
             [:provider_webhook_receive]
           ),
         :ok <-
           Authorization.ensure_system_role(
             service_principal,
             %{
               organization_id: session_context.organization_id,
               workspace_id: attrs.workspace_id
             },
             [:integration_reconcile]
           ),
         {:ok, installation} <-
           create_installation(
             session_context,
             operation,
             attrs,
             service_principal.id,
             webhook_principal.id
           ),
         :ok <-
           validate_installation(
             installation,
             session_context,
             operation,
             attrs,
             service_principal.id,
             webhook_principal.id
           ),
         {:ok, snapshot} <- create_permission_snapshot(installation, operation),
         {:ok, permissions} <- create_permission_entries(snapshot, attrs.permissions),
         {:ok, installation} <- set_permission_snapshot(installation, snapshot),
         {:ok, credentials} <-
           create_credential_bindings(
             session_context,
             operation,
             installation,
             attrs
           ) do
      {:ok,
       BindingResult.build!(
         operation,
         installation,
         snapshot,
         permissions,
         credentials
       )}
    end
  end

  defp replay_binding(session_context, operation, installation, attrs) do
    with :ok <-
           validate_installation_scope(
             installation,
             session_context,
             operation,
             attrs
           ),
         {:ok, snapshot} <-
           Ash.get(
             PermissionSnapshot,
             installation.current_permission_snapshot_id,
             authorize?: false,
             not_found_error?: false
           ),
         true <- is_struct(snapshot, PermissionSnapshot),
         {:ok, permissions} <-
           PermissionEntry
           |> Ash.Query.filter(permission_snapshot_id == ^snapshot.id)
           |> Ash.Query.sort(name: :asc)
           |> Ash.read(authorize?: false),
         {:ok, credentials} <- read_credentials(installation.id) do
      {:ok,
       BindingResult.build!(
         operation,
         installation,
         snapshot,
         permissions,
         credentials
       )}
    else
      false -> {:error, :integration_storage_unavailable}
      {:error, error} -> {:error, error}
    end
  end

  defp create_installation(
         session_context,
         operation,
         attrs,
         service_principal_id,
         webhook_principal_id
       ) do
    Installation
    |> Ash.Changeset.for_create(:create, %{
      organization_id: session_context.organization_id,
      workspace_id: attrs.workspace_id,
      external_installation_id: attrs.external_installation_id,
      app_slug: attrs.app_slug,
      account_login: attrs.account_login,
      account_type: attrs.account_type,
      service_principal_id: service_principal_id,
      webhook_principal_id: webhook_principal_id,
      lifecycle_state: "active",
      operation_id: operation.id
    })
    |> Ash.create(
      authorize?: false,
      return_notifications?: true,
      return_skipped_upsert?: true,
      upsert?: true,
      upsert_identity: :unique_external_installation,
      upsert_fields: []
    )
    |> CommandSupport.normalize_ash_write()
  end

  defp validate_installation(
         installation,
         session_context,
         operation,
         attrs,
         service_principal_id,
         webhook_principal_id
       ) do
    with :ok <- validate_installation_scope(installation, session_context, operation, attrs),
         true <- installation.service_principal_id == service_principal_id,
         true <- installation.webhook_principal_id == webhook_principal_id,
         true <- installation.app_slug == attrs.app_slug,
         true <- installation.account_login == attrs.account_login,
         true <- installation.account_type == attrs.account_type do
      :ok
    else
      _mismatch -> {:error, :forbidden}
    end
  end

  defp validate_installation_scope(installation, session_context, operation, attrs) do
    if installation.organization_id == session_context.organization_id and
         installation.workspace_id == attrs.workspace_id and
         installation.external_installation_id == attrs.external_installation_id and
         installation.operation_id == operation.id and
         installation.lifecycle_state == "active" do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp create_permission_snapshot(installation, operation) do
    PermissionSnapshot
    |> Ash.Changeset.for_create(:create, %{
      installation_id: installation.id,
      version: 1,
      captured_at: DateTime.utc_now(),
      operation_id: operation.id
    })
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> CommandSupport.normalize_ash_write()
  end

  defp create_permission_entries(snapshot, permissions) do
    Enum.reduce_while(permissions, {:ok, []}, fn permission, {:ok, entries} ->
      PermissionEntry
      |> Ash.Changeset.for_create(:create, %{
        permission_snapshot_id: snapshot.id,
        name: permission.name,
        access_level: permission.access_level
      })
      |> Ash.create(authorize?: false, return_notifications?: true)
      |> CommandSupport.normalize_ash_write()
      |> case do
        {:ok, entry} -> {:cont, {:ok, [entry | entries]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, error} -> {:error, error}
    end
  end

  defp set_permission_snapshot(installation, snapshot) do
    installation
    |> Ash.Changeset.for_update(:set_permission_snapshot, %{
      current_permission_snapshot_id: snapshot.id
    })
    |> Ash.update(authorize?: false, return_notifications?: true)
    |> CommandSupport.normalize_ash_write()
  end

  defp create_credential_bindings(session_context, operation, installation, attrs) do
    [
      {"webhook_secret", attrs.webhook_secret_reference},
      {"app_private_key", attrs.app_private_key_reference}
    ]
    |> Enum.reduce_while({:ok, []}, fn {purpose, reference}, {:ok, credentials} ->
      case create_credential_binding(
             session_context,
             operation,
             installation,
             purpose,
             reference
           ) do
        {:ok, credential} -> {:cont, {:ok, [credential | credentials]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, credentials} -> {:ok, Enum.reverse(credentials)}
      {:error, error} -> {:error, error}
    end
  end

  defp create_credential_binding(
         session_context,
         operation,
         installation,
         purpose,
         reference
       ) do
    credential_attrs = %{
      organization_id: session_context.organization_id,
      workspace_id: installation.workspace_id,
      kind: "secret_reference",
      secret_reference: reference,
      status: "active",
      operation_id: operation.id
    }

    identity =
      if is_nil(installation.workspace_id),
        do: :unique_organization_reference,
        else: :unique_workspace_reference

    with {:ok, credential} <-
           IntegrationCredential
           |> Ash.Changeset.for_create(:create, credential_attrs)
           |> Ash.create(
             authorize?: false,
             return_notifications?: true,
             return_skipped_upsert?: true,
             upsert?: true,
             upsert_identity: identity,
             upsert_fields: []
           )
           |> CommandSupport.normalize_ash_write(),
         :ok <- validate_credential(credential, session_context, installation, reference),
         {:ok, binding} <-
           InstallationCredential
           |> Ash.Changeset.for_create(:create, %{
             installation_id: installation.id,
             credential_id: credential.id,
             purpose: purpose,
             operation_id: operation.id
           })
           |> Ash.create(authorize?: false, return_notifications?: true)
           |> CommandSupport.normalize_ash_write() do
      {:ok, BindingCredential.build!(binding, credential)}
    end
  end

  defp validate_credential(credential, session_context, installation, reference) do
    if credential.status == "active" and
         credential.organization_id == session_context.organization_id and
         credential.workspace_id == installation.workspace_id and
         credential.kind == "secret_reference" and
         credential.secret_reference == reference do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp installation_by_operation(operation_id) do
    query =
      Installation
      |> Ash.Query.filter(operation_id == ^operation_id)
      |> Ash.Query.lock(:for_update)

    RecordLoader.read_one(Installation, query, authorize?: false)
  end

  defp read_credentials(installation_id) do
    InstallationCredential
    |> Ash.Query.filter(installation_id == ^installation_id)
    |> Ash.Query.sort(purpose: :asc)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, bindings} ->
        Enum.reduce_while(bindings, {:ok, []}, fn binding, {:ok, credentials} ->
          case Ash.get(
                 IntegrationCredential,
                 binding.credential_id,
                 authorize?: false,
                 not_found_error?: false
               ) do
            {:ok, %IntegrationCredential{} = credential} ->
              {:cont, {:ok, [BindingCredential.build!(binding, credential) | credentials]}}

            {:ok, nil} ->
              {:halt, {:error, :integration_storage_unavailable}}

            {:error, error} ->
              {:halt, {:error, error}}
          end
        end)
        |> case do
          {:ok, credentials} -> {:ok, Enum.reverse(credentials)}
          {:error, error} -> {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp run_with_identity_retry(action) do
    case action.() do
      {:error, %Ash.Error.Invalid{} = error} ->
        if identity_conflict?(error), do: action.(), else: {:error, error}

      result ->
        result
    end
  end

  defp identity_conflict?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, fn
      %Ash.Error.Changes.InvalidAttribute{private_vars: private_vars} ->
        private_vars = private_vars || []

        Keyword.get(private_vars, :constraint_type) == :unique and
          Keyword.get(private_vars, :constraint) in @identity_constraints

      _other ->
        false
    end)
  end
end
