defmodule OfficeGraph.Integrations do
  @moduledoc """
  Public boundary for provider adapters and manual intake.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.CommandSupport,
      OfficeGraph.DurableDelivery,
      OfficeGraph.Operations,
      OfficeGraph.ProposedChanges
    ],
    exports: [IntegrationCredential]

  require Ash.Query

  alias OfficeGraph.{Authorization, CommandSupport}

  alias OfficeGraph.Integrations.{
    ExternalSource,
    ManualIntakeActionResult,
    NormalizedIntakeEvent,
    ProviderArchiveResult,
    RawArchive
  }

  alias OfficeGraph.Operations

  @manual_intake_action "manual_intake.submit"
  @external_source_constraint "external_sources_kind_key_index"
  @provider_archive_constraint "raw_archives_provider_delivery_index"
  @accepted_replay_constraint "normalized_intake_events_accepted_replay_identity_index"

  def ensure_provider_source(key, name)
      when is_binary(key) and byte_size(key) in 1..255 and is_binary(name) and
             byte_size(name) in 1..255 do
    case ensure_source("provider", key, name) do
      {:ok, source} ->
        if source.kind == "provider",
          do: {:ok, source},
          else: {:error, :source_identity_conflict}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  def ensure_provider_source(_key, _name), do: {:error, :invalid_provider_source}

  def archive_system_delivery(operation, source, attrs)
      when is_map(operation) and is_map(source) and is_map(attrs) do
    with :ok <- validate_system_archive_scope(operation, source),
         :ok <- validate_required_string(attrs, :external_delivery_id),
         :ok <- validate_required_string(attrs, :body) do
      body = Map.fetch!(attrs, :body)

      archive_attrs = %{
        organization_id: operation.organization_id,
        workspace_id: operation.workspace_id,
        source_id: source.id,
        operation_id: operation.id,
        content_hash: content_hash(body),
        archive_kind: "provider_delivery",
        external_delivery_id: Map.fetch!(attrs, :external_delivery_id),
        provider_event: Map.get(attrs, :provider_event),
        external_installation_id: Map.get(attrs, :external_installation_id),
        body: body
      }

      case archive_provider_delivery(archive_attrs) do
        {:ok, %ProviderArchiveResult{archive: archive, status: status}} ->
          if archive.content_hash == archive_attrs.content_hash and
               archive.operation_id == operation.id and
               archive.organization_id == operation.organization_id and
               archive.workspace_id == operation.workspace_id do
            {:ok, archive, String.to_existing_atom(status)}
          else
            {:error, :delivery_identity_conflict}
          end

        {:error, _storage_error} ->
          {:error, :integration_storage_unavailable}
      end
    end
  end

  def archive_system_delivery(_operation, _source, _attrs),
    do: {:error, :invalid_provider_delivery}

  def provider_delivery_archive(
        organization_id,
        workspace_id,
        archive_id,
        delivery_id,
        opts \\ []
      )

  def provider_delivery_archive(
        organization_id,
        workspace_id,
        archive_id,
        delivery_id,
        opts
      )
      when is_binary(organization_id) and (is_binary(workspace_id) or is_nil(workspace_id)) and
             is_binary(archive_id) and is_binary(delivery_id) and is_list(opts) do
    RawArchive
    |> Ash.Query.filter(
      id == ^archive_id and organization_id == ^organization_id and
        archive_kind == "provider_delivery" and external_delivery_id == ^delivery_id
    )
    |> scope_archive_query(workspace_id)
    |> read_provider_delivery_archive(opts)
    |> case do
      {:ok, nil} -> {:error, :invalid_delivery_archive}
      {:ok, archive} -> {:ok, archive}
      {:error, _error} -> {:error, :integration_storage_unavailable}
    end
  end

  def provider_delivery_archive(
        _organization_id,
        _workspace_id,
        _archive_id,
        _delivery_id,
        _opts
      ),
      do: {:error, :invalid_delivery_archive}

  defp scope_archive_query(query, nil), do: Ash.Query.filter(query, is_nil(workspace_id))

  defp scope_archive_query(query, workspace_id),
    do: Ash.Query.filter(query, workspace_id == ^workspace_id)

  defp read_provider_delivery_archive(query, opts) do
    case Keyword.get(opts, :record_loader) do
      nil -> Ash.read_one(query, authorize?: false)
      loader -> loader.read_one(RawArchive, query, authorize?: false)
    end
  end

  def submit_manual_intake(session_context, operation, attrs) do
    with :ok <- validate_manual_intake_attrs(attrs),
         :ok <- validate_manual_intake_operation(session_context, operation),
         :ok <-
           Authorization.authorize_operation(session_context, operation, :manual_intake_submit,
             organization_id: session_context.organization_id
           ),
         {:ok, intake} <- submit_or_replay_manual_intake(session_context, operation, attrs) do
      {:ok, intake}
    end
  end

  defp submit_or_replay_manual_intake(session_context, operation, attrs) do
    with :ok <- validate_command_replay(operation, attrs) do
      run = fn ->
        NormalizedIntakeEvent
        |> Ash.ActionInput.for_action(:persist_manual_intake, %{
          operation_id: operation.id,
          source_identity: attrs.source_identity,
          replay_identity: attrs.replay_identity,
          body: attrs.body
        })
        |> Ash.run_action(actor: session_context, authorize?: false)
      end

      run
      |> with_identity_retry([
        @external_source_constraint,
        @accepted_replay_constraint
      ])
      |> case do
        {:ok, %ManualIntakeActionResult{} = result} ->
          ManualIntakeActionResult.to_public_result(result)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp validate_command_replay(operation, attrs) do
    if is_binary(Map.get(operation, :command_input_digest)) do
      Operations.validate_command_replay(operation, attrs)
    else
      :ok
    end
  end

  defp content_hash(body) do
    :crypto.hash(:sha256, body)
    |> Base.encode16(case: :lower)
  end

  defp validate_system_archive_scope(operation, source) do
    valid? =
      operation.operation_kind == "system" and is_binary(operation.organization_id) and
        (is_binary(operation.workspace_id) or is_nil(operation.workspace_id)) and
        source.kind == "provider"

    if valid?, do: :ok, else: {:error, :forbidden}
  end

  defp archive_provider_delivery(attrs) do
    run = fn ->
      RawArchive
      |> Ash.ActionInput.for_action(:archive_provider_delivery, attrs)
      |> Ash.run_action(authorize?: false)
    end

    with_identity_retry(run, @provider_archive_constraint)
  end

  defp ensure_source(kind, key, name) do
    run = fn ->
      ExternalSource
      |> Ash.Changeset.for_create(:ensure, %{kind: kind, key: key, name: name})
      |> Ash.create(authorize?: false, return_notifications?: true)
      |> case do
        {:ok, source, _notifications} -> {:ok, source}
        {:error, error} -> {:error, error}
      end
    end

    with_identity_retry(run, @external_source_constraint)
  end

  defp with_identity_retry(run, constraint) do
    case run.() do
      {:error, %Ash.Error.Invalid{} = error} ->
        if CommandSupport.unique_constraint?(error, constraint),
          do: run.(),
          else: {:error, error}

      result ->
        result
    end
  end

  defp validate_manual_intake_attrs(attrs) do
    with :ok <- validate_required_string(attrs, :source_identity),
         :ok <- validate_required_string(attrs, :replay_identity),
         :ok <- validate_required_string(attrs, :body) do
      :ok
    end
  end

  defp validate_required_string(attrs, field) do
    case Map.fetch(attrs, field) do
      {:ok, value} when is_binary(value) ->
        if String.trim(value) == "" do
          {:error, {:missing_field, field}}
        else
          :ok
        end

      {:ok, _other} ->
        {:error, {:invalid_field, field}}

      :error ->
        {:error, {:missing_field, field}}
    end
  end

  defp validate_manual_intake_operation(
         session_context,
         %{
           principal_id: principal_id,
           session_id: session_id,
           organization_id: organization_id,
           workspace_id: workspace_id,
           action: @manual_intake_action
         }
       )
       when is_map(session_context) do
    if principal_id == session_context.principal_id and
         session_id == session_context.session_id and
         organization_id == session_context.organization_id and
         workspace_id == session_context.workspace_id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp validate_manual_intake_operation(_session_context, _operation) do
    {:error, :forbidden}
  end
end
