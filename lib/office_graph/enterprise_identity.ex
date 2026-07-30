defmodule OfficeGraph.EnterpriseIdentity do
  @moduledoc """
  Provider-neutral enterprise connections, directories, and synchronized identity facts.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.CommandSupport,
      OfficeGraph.Identity,
      OfficeGraph.Integrations,
      OfficeGraph.Operations,
      OfficeGraph.Tenancy
    ],
    exports: [Domain]

  alias OfficeGraph.EnterpriseIdentity.{
    ActionSupport,
    Directory,
    DirectoryApplyResult,
    DirectoryProcessingResult,
    DirectorySyncEvent,
    DirectoryUser,
    EnterpriseConnection
  }

  alias OfficeGraph.EnterpriseIdentity.Adapters.WorkOS.DirectoryEvent
  alias OfficeGraph.EnterpriseIdentity.WebhookReceipt

  require Ash.Query

  @storage_exceptions [
    Ash.Error.Forbidden,
    Ash.Error.Framework,
    Ash.Error.Invalid,
    Ash.Error.Unknown,
    DBConnection.ConnectionError,
    Ecto.ConstraintError,
    Ecto.StaleEntryError,
    Postgrex.Error
  ]

  def apply_directory_event(directory_id, %DirectoryEvent{} = event, operation_id)
      when is_binary(directory_id) and is_binary(operation_id) do
    Directory
    |> Ash.ActionInput.for_action(:apply_event, %{
      directory_id: directory_id,
      event: event,
      operation_id: operation_id
    })
    |> Ash.run_action(authorize?: false)
    |> ActionSupport.normalize_action_result()
    |> case do
      {:ok, %DirectoryApplyResult{} = result} -> DirectoryApplyResult.to_public_result(result)
      {:error, reason} when is_atom(reason) -> {:error, reason}
      {:error, _storage_error} -> {:error, :enterprise_identity_storage_unavailable}
    end
  rescue
    _error in @storage_exceptions -> {:error, :enterprise_identity_storage_unavailable}
  end

  def apply_directory_event(_directory_id, _event, _operation_id),
    do: {:error, :invalid_directory_event}

  def accept_webhook(headers, raw_body), do: WebhookReceipt.accept(headers, raw_body)

  def process_sync_event(sync_event_id, provider_event_id)
      when is_binary(sync_event_id) and is_binary(provider_event_id) do
    DirectorySyncEvent
    |> Ash.ActionInput.for_action(:process_event, %{
      sync_event_id: sync_event_id,
      provider_event_id: provider_event_id
    })
    |> Ash.run_action(authorize?: false)
    |> ActionSupport.normalize_action_result()
    |> case do
      {:ok, %DirectoryProcessingResult{}} -> :ok
      {:error, reason} when is_atom(reason) -> {:error, reason}
      {:error, _storage_error} -> {:error, :enterprise_identity_storage_unavailable}
    end
  rescue
    _error in @storage_exceptions -> {:error, :enterprise_identity_storage_unavailable}
  end

  def process_sync_event(_sync_event_id, _provider_event_id),
    do: {:error, :unknown_sync_event}

  def fail_sync_event(sync_event_id, reason) when is_binary(sync_event_id) do
    with {:ok, %DirectorySyncEvent{} = sync_event} <-
           Ash.get(DirectorySyncEvent, sync_event_id,
             authorize?: false,
             not_found_error?: false
           ),
         {:ok, _failed} <-
           sync_event
           |> Ash.Changeset.for_update(:mark_processed, %{
             status: "failed",
             result: bounded_sync_result(reason),
             processed_at: DateTime.utc_now()
           })
           |> Ash.update(authorize?: false) do
      :ok
    else
      {:ok, nil} -> {:error, :unknown_sync_event}
      {:error, _storage_error} -> {:error, :enterprise_identity_storage_unavailable}
    end
  end

  def fail_sync_event(_sync_event_id, _reason), do: {:error, :unknown_sync_event}

  def prepare_workos_login(connection_id, redirect_uri, state)
      when is_binary(connection_id) and is_binary(redirect_uri) and is_binary(state) do
    with {:ok, connection} <- active_connection(connection_id),
         {:ok, config} <- workos_configuration(connection),
         {:ok, authorization_uri} <-
           workos_sso_client().authorization_uri(%{
             config: config,
             redirect_uri: redirect_uri,
             state: state
           }) do
      {:ok,
       %{
         authorization_uri: authorization_uri,
         connection_id: connection.id
       }}
    else
      {:error, :enterprise_connection_unavailable} = error -> error
      {:error, _provider_or_configuration_error} -> {:error, :provider_unavailable}
    end
  end

  def prepare_workos_login(_connection_id, _redirect_uri, _state),
    do: {:error, :enterprise_connection_unavailable}

  def exchange_workos_code(connection_id, code, redirect_uri)
      when is_binary(connection_id) and is_binary(code) and is_binary(redirect_uri) do
    with {:ok, connection} <- active_connection(connection_id),
         {:ok, config} <- workos_configuration(connection),
         {:ok, profile} <-
           workos_sso_client().exchange(%{
             config: config,
             code: code,
             redirect_uri: redirect_uri
           }),
         :ok <- validate_sso_profile(profile, connection) do
      {:ok,
       %{
         connection_id: connection.id,
         organization_id: connection.organization_id,
         workspace_id: connection.workspace_id,
         provider_organization_id: connection.provider_organization_id,
         directory_requirement: connection.directory_requirement,
         session_ttl_seconds: config.session_ttl_seconds,
         profile: profile
       }}
    else
      {:error, :enterprise_connection_unavailable} = error -> error
      {:error, _provider_or_configuration_error} -> {:error, :provider_unavailable}
    end
  end

  def exchange_workos_code(_connection_id, _code, _redirect_uri),
    do: {:error, :provider_unavailable}

  def validate_workos_provisioning(
        %{
          connection_id: connection_id,
          directory_requirement: "optional"
        },
        _principal_id
      )
      when is_binary(connection_id),
      do: :ok

  def validate_workos_provisioning(
        %{
          connection_id: connection_id,
          directory_requirement: "required",
          profile: %{idp_id: idp_id, verified_email: verified_email}
        },
        principal_id
      )
      when is_binary(connection_id) and is_binary(principal_id) and is_binary(idp_id) and
             is_binary(verified_email) do
    DirectoryUser
    |> Ash.Query.filter(
      principal_id == ^principal_id and status == "active" and
        idp_id == ^idp_id and email == ^verified_email and
        directory.status == "active" and directory.connection_id == ^connection_id
    )
    |> Ash.exists(authorize?: false)
    |> case do
      {:ok, true} -> :ok
      {:ok, false} -> {:error, :directory_provisioning_required}
      {:error, _storage_error} -> {:error, :enterprise_identity_storage_unavailable}
    end
  end

  def validate_workos_provisioning(_exchange, _principal_id),
    do: {:error, :directory_provisioning_required}

  defp active_connection(connection_id) do
    EnterpriseConnection
    |> Ash.Query.filter(id == ^connection_id and provider == "workos" and status == "active")
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %EnterpriseConnection{} = connection} -> {:ok, connection}
      {:ok, nil} -> {:error, :enterprise_connection_unavailable}
      {:error, _storage_error} -> {:error, :enterprise_connection_unavailable}
    end
  end

  defp workos_configuration(connection) do
    config = Application.get_env(:office_graph, :workos_enterprise, [])
    api_base_url = config[:api_base_url]
    api_key_reference = config[:api_key_reference]
    client_id = config[:client_id]
    session_ttl_seconds = session_ttl_seconds(config[:session_ttl_seconds])

    if present?(api_base_url) and present?(api_key_reference) and present?(client_id) and
         is_integer(session_ttl_seconds) do
      {:ok,
       %{
         api_base_url: api_base_url,
         api_key_reference: api_key_reference,
         client_id: client_id,
         provider_organization_id: connection.provider_organization_id,
         session_ttl_seconds: session_ttl_seconds
       }}
    else
      {:error, :workos_unavailable}
    end
  end

  defp validate_sso_profile(
         %{
           subject: subject,
           idp_id: idp_id,
           verified_email: verified_email,
           provider_organization_id: provider_organization_id
         },
         %{provider_organization_id: provider_organization_id}
       )
       when is_binary(subject) and subject != "" and is_binary(idp_id) and idp_id != "" and
              is_binary(verified_email) and verified_email != "",
       do: :ok

  defp validate_sso_profile(_profile, _connection), do: {:error, :invalid_profile}

  defp workos_sso_client do
    Application.fetch_env!(:office_graph, :workos_sso_client)
  end

  defp session_ttl_seconds(nil), do: 8 * 60 * 60
  defp session_ttl_seconds(value) when is_integer(value) and value > 0, do: value

  defp session_ttl_seconds(value) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, ""} when seconds > 0 -> seconds
      _invalid -> :invalid
    end
  end

  defp session_ttl_seconds(_value), do: :invalid

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp bounded_sync_result(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.slice(0, 255)

  defp bounded_sync_result(_reason), do: "directory_sync_failed"
end
