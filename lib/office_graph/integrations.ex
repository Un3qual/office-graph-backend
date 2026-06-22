defmodule OfficeGraph.Integrations do
  @moduledoc """
  Public boundary for provider adapters and manual intake.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.ProposedChanges,
      OfficeGraph.Repo
    ],
    exports: []

  require Ash.Query

  alias OfficeGraph.Authorization
  alias OfficeGraph.Integrations.{ExternalSource, NormalizedIntakeEvent, RawArchive}
  alias OfficeGraph.ProposedChanges
  alias OfficeGraph.Repo

  @manual_intake_action "manual_intake.submit"

  def submit_manual_intake(session_context, operation, attrs) do
    with :ok <- validate_manual_intake_attrs(attrs),
         :ok <- validate_manual_intake_operation(session_context, operation),
         :ok <-
           Authorization.authorize_operation(session_context, operation, :manual_intake_submit,
             organization_id: session_context.organization_id
           ),
         {:ok, intake} <- record_manual_intake(session_context, operation, attrs) do
      {:ok, intake}
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
    case ProposedChanges.create_for_manual_intake(
           session_context,
           operation,
           normalized_event,
           attrs
         ) do
      {:ok, proposed_changes} ->
        {:ok,
         %{
           raw_archive: raw_archive,
           normalized_event: normalized_event,
           duplicate?: false,
           proposed_changes: proposed_changes
         }}

      {:error, error} ->
        {:error, error}
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

  defp get_or_create_source(source_identity) do
    case Ash.get(ExternalSource, %{key: source_identity},
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
      conflict_target: [:key]
    )

    case fetch_source(source_identity) do
      {:ok, nil} -> {:error, :source_not_found_after_create}
      result -> result
    end
  end

  defp fetch_source(source_identity) do
    Ash.get(ExternalSource, %{key: source_identity},
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
