defmodule OfficeGraph.Integrations do
  @moduledoc """
  Public boundary for provider adapters and manual intake.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.DurableDelivery,
      OfficeGraph.Operations,
      OfficeGraph.ProposedChanges,
      OfficeGraph.Repo
    ],
    exports: [IntegrationCredential]

  require Ash.Query

  alias OfficeGraph.Authorization
  alias OfficeGraph.DurableDelivery
  alias OfficeGraph.Integrations.{ExternalSource, NormalizedIntakeEvent, RawArchive}
  alias OfficeGraph.Operations
  alias OfficeGraph.ProposedChanges
  alias OfficeGraph.Repo

  @manual_intake_action "manual_intake.submit"

  def ensure_provider_source(key, name)
      when is_binary(key) and byte_size(key) in 1..255 and is_binary(name) and
             byte_size(name) in 1..255 do
    case Repo.get_or_insert(
           ExternalSource,
           [kind: "provider", key: key],
           %{key: key, name: name, kind: "provider"},
           &provider_source_insert_contract/2
         ) do
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
      archive_id = Ecto.UUID.generate()
      body = Map.fetch!(attrs, :body)

      archive_attrs = %{
        id: archive_id,
        organization_id: operation.organization_id,
        workspace_id: operation.workspace_id,
        source_id: source.id,
        operation_id: operation.id,
        content_hash: content_hash(body),
        archive_kind: "provider_delivery",
        external_delivery_id: Map.fetch!(attrs, :external_delivery_id),
        body: body,
        metadata: Map.get(attrs, :metadata, %{})
      }

      case Repo.get_or_insert(
             RawArchive,
             [
               source_id: source.id,
               external_delivery_id: archive_attrs.external_delivery_id
             ],
             archive_attrs,
             &provider_archive_insert_contract/2,
             &fetch_provider_archive/2
           ) do
        {:ok, archive} ->
          if archive.content_hash == archive_attrs.content_hash and
               archive.operation_id == operation.id and
               archive.organization_id == operation.organization_id and
               archive.workspace_id == operation.workspace_id do
            {:ok, archive, if(archive.id == archive_id, do: :created, else: :replayed)}
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
    if command_operation?(operation) do
      submit_or_replay_manual_intake_command(session_context, operation, attrs)
    else
      record_manual_intake(session_context, operation, attrs)
    end
  end

  defp submit_or_replay_manual_intake_command(session_context, operation, attrs) do
    with :ok <- Operations.validate_command_replay(operation, attrs) do
      Repo.transaction(fn ->
        case Operations.lock_operation(operation.id) do
          {:ok, _locked_operation} ->
            case existing_intake_for_operation(session_context, operation) do
              {:ok, nil} ->
                case record_manual_intake(session_context, operation, attrs) do
                  {:ok, intake} -> intake
                  {:error, error} -> Repo.rollback(error)
                end

              {:ok, intake} ->
                intake

              {:error, error} ->
                Repo.rollback(error)
            end

          {:error, error} ->
            Repo.rollback(error)
        end
      end)
      |> case do
        {:ok, intake} -> {:ok, intake}
        {:error, error} -> {:error, error}
      end
    end
  end

  defp command_operation?(operation) do
    operation
    |> Map.get(:metadata, %{})
    |> command_digest?()
  end

  defp command_digest?(%{"command_input_digest" => digest}), do: is_binary(digest)
  defp command_digest?(%{command_input_digest: digest}), do: is_binary(digest)
  defp command_digest?(_metadata), do: false

  defp existing_intake_for_operation(session_context, operation) do
    NormalizedIntakeEvent
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and operation_id == ^operation.id
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, normalized_event} ->
        with {:ok, raw_archive} <-
               Ash.get(RawArchive, normalized_event.raw_archive_id, authorize?: false),
             proposed_changes <-
               ProposedChanges.for_normalized_event(session_context, normalized_event.id) do
          {:ok,
           %{
             raw_archive: raw_archive,
             normalized_event: normalized_event,
             duplicate?: normalized_event.outcome == "duplicate",
             proposed_changes: proposed_changes
           }}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp record_manual_intake(session_context, operation, attrs) do
    case insert_manual_intake(session_context, operation, attrs) do
      {:ok, intake} ->
        {:ok, intake}

      {:error, error} ->
        record_duplicate_after_replay_conflict(session_context, operation, attrs, error)
    end
  end

  defp insert_manual_intake(session_context, operation, attrs, opts \\ []) do
    Repo.transaction(fn ->
      with {:ok, source} <- get_or_create_source(attrs.source_identity),
           {:ok, duplicate_of} <- accepted_duplicate(session_context, attrs),
           duplicate_of <- required_duplicate(opts[:duplicate_retry?], duplicate_of),
           outcome = if(duplicate_of, do: "duplicate", else: "accepted"),
           {:ok, raw_archive} <-
             ash_create(RawArchive, %{
               organization_id: session_context.organization_id,
               workspace_id: session_context.workspace_id,
               source_id: source.id,
               operation_id: operation.id,
               content_hash: content_hash(attrs.body),
               body: attrs.body,
               metadata: %{}
             }),
           {:ok, normalized_event} <-
             ash_create(NormalizedIntakeEvent, %{
               organization_id: session_context.organization_id,
               workspace_id: session_context.workspace_id,
               raw_archive_id: raw_archive.id,
               operation_id: operation.id,
               source_identity: attrs.source_identity,
               replay_identity: attrs.replay_identity,
               outcome: outcome,
               duplicate_of_id: duplicate_of && duplicate_of.id
             }),
           {:ok, intake} <-
             record_manual_intake_proposed_changes(
               session_context,
               operation,
               attrs,
               raw_archive,
               normalized_event,
               outcome
             ) do
        intake
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
  end

  defp record_manual_intake_proposed_changes(
         _session_context,
         _operation,
         _attrs,
         raw_archive,
         normalized_event,
         "duplicate"
       ) do
    {:ok,
     %{
       raw_archive: raw_archive,
       normalized_event: normalized_event,
       duplicate?: true,
       proposed_changes: []
     }}
  end

  defp record_manual_intake_proposed_changes(
         session_context,
         operation,
         attrs,
         raw_archive,
         normalized_event,
         "accepted"
       ) do
    with {:ok, proposed_changes} <-
           ProposedChanges.create_for_manual_intake(
             session_context,
             operation,
             normalized_event,
             attrs
           ),
         {:ok, _event} <-
           DurableDelivery.record_and_enqueue(session_context, operation, %{
             event_key: "manual-intake:#{normalized_event.id}:accepted",
             event_kind: "manual_intake.accepted",
             subject_kind: "normalized_intake_event",
             subject_id: normalized_event.id
           }) do
      {:ok,
       %{
         raw_archive: raw_archive,
         normalized_event: normalized_event,
         duplicate?: false,
         proposed_changes: proposed_changes
       }}
    end
  end

  defp record_duplicate_after_replay_conflict(session_context, operation, attrs, original_error) do
    case accepted_duplicate(session_context, attrs) do
      {:ok, nil} ->
        {:error, original_error}

      {:ok, _duplicate_of} ->
        insert_manual_intake(session_context, operation, attrs, duplicate_retry?: true)

      {:error, {:manual_intake_replay_conflict, _accepted_id} = conflict} ->
        {:error, conflict}

      {:error, _error} ->
        {:error, original_error}
    end
  end

  defp required_duplicate(true, nil), do: Repo.rollback(:accepted_replay_not_found)
  defp required_duplicate(_duplicate_retry?, duplicate_of), do: duplicate_of

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

  defp provider_source_insert_contract(ExternalSource, _attrs) do
    {"external_sources", [:kind, :key], [:id]}
  end

  defp provider_archive_insert_contract(RawArchive, _attrs) do
    {"raw_archives",
     {:unsafe_fragment,
      "(source_id, external_delivery_id) WHERE external_delivery_id IS NOT NULL"},
     [:id, :organization_id, :workspace_id, :source_id, :operation_id]}
  end

  defp fetch_provider_archive(RawArchive, lookup) do
    lookup = Map.new(lookup)

    RawArchive
    |> Ash.Query.filter(
      source_id == ^lookup.source_id and external_delivery_id == ^lookup.external_delivery_id
    )
    |> Ash.read_one(authorize?: false)
  end

  defp get_or_create_source(source_identity) do
    case Ash.get(ExternalSource, %{kind: "manual", key: source_identity},
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok, nil} ->
        insert_source_then_refetch(source_identity)

      {:ok, source} ->
        {:ok, source}

      {:error, error} ->
        {:error, error}
    end
  end

  defp insert_source_then_refetch(source_identity) do
    now = DateTime.utc_now()

    Repo.insert_all(
      "external_sources",
      [
        %{
          id: Ecto.UUID.dump!(Ecto.UUID.generate()),
          key: source_identity,
          name: "Manual Intake",
          kind: "manual",
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:kind, :key]
    )

    case fetch_source(source_identity) do
      {:ok, nil} -> {:error, :source_not_found_after_create}
      result -> result
    end
  end

  defp fetch_source(source_identity) do
    Ash.get(ExternalSource, %{kind: "manual", key: source_identity},
      authorize?: false,
      not_found_error?: false
    )
  end

  defp accepted_duplicate(session_context, attrs) do
    NormalizedIntakeEvent
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and
        source_identity == ^attrs.source_identity and
        replay_identity == ^attrs.replay_identity and
        outcome == "accepted"
    )
    |> Ash.read_one(authorize?: false)
    |> then(&verify_duplicate_content(&1, attrs))
  end

  defp verify_duplicate_content({:ok, nil}, _attrs), do: {:ok, nil}

  defp verify_duplicate_content({:ok, duplicate}, attrs) do
    case Ash.get(RawArchive, duplicate.raw_archive_id, authorize?: false) do
      {:ok, %{content_hash: hash}} ->
        if hash == content_hash(attrs.body) do
          {:ok, duplicate}
        else
          {:error, {:manual_intake_replay_conflict, duplicate.id}}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp verify_duplicate_content({:error, error}, _attrs) do
    {:error, error}
  end

  defp ash_create(resource, attrs) do
    Ash.create(
      resource,
      attrs,
      action: :create,
      authorize?: false,
      return_notifications?: true
    )
    |> case do
      {:ok, record, _notifications} -> {:ok, record}
      {:ok, record} -> {:ok, record}
      {:error, error} -> {:error, error}
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
