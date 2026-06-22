defmodule OfficeGraph.ProposedChanges do
  @moduledoc """
  Public boundary for proposed graph change validation and application.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.Repo,
      OfficeGraph.WorkGraph
    ],
    exports: []

  alias OfficeGraph.Authorization
  alias OfficeGraph.ProposedChanges.ProposedGraphChange
  alias OfficeGraph.Repo
  alias OfficeGraph.WorkGraph

  require Ash.Query

  @required_change_types [
    "create_signal",
    "create_task",
    "create_review_finding",
    "create_verification_check"
  ]

  @apply_operation_action "proposed_change.apply"
  @manual_intake_action "manual_intake.submit"
  @normalized_intake_event Module.concat([OfficeGraph, Integrations, NormalizedIntakeEvent])

  defguardp is_apply_validation_error(error)
            when error == :forbidden or
                   (is_tuple(error) and
                      elem(error, 0) in [
                        :invalid_apply_operation,
                        :invalid_proposed_change,
                        :invalid_proposed_change_scope,
                        :invalid_proposed_change_set,
                        :invalid_proposed_change_status,
                        :missing_proposed_change
                      ])

  def get_many(session_context, ids), do: read_scoped_changes(session_context, ids)

  def get_many!(_session_context, []), do: []

  def get_many!(session_context, ids) do
    case get_many(session_context, ids) do
      {:ok, records} -> records
      {:error, {:missing_proposed_change, id}} -> raise KeyError, key: id, term: ids
      {:error, error} -> raise RuntimeError, message: inspect(error)
    end
  end

  def create_for_manual_intake(session_context, operation, normalized_event, attrs) do
    title = first_sentence(attrs.body)

    with :ok <-
           validate_manual_intake_creation_context(session_context, operation, normalized_event) do
      Repo.transaction(fn ->
        normalized_event = lock_normalized_event!(session_context, operation, normalized_event)

        case read_existing_for_normalized_event(normalized_event.id, lock?: true) do
          [] ->
            Enum.map(@required_change_types, fn change_type ->
              ash_create!(
                ProposedGraphChange,
                %{
                  organization_id: session_context.organization_id,
                  workspace_id: session_context.workspace_id,
                  operation_id: operation.id,
                  normalized_event_id: normalized_event.id,
                  change_type: change_type,
                  payload: change_payload(change_type, title, attrs.body)
                },
                session_context
              )
            end)

          existing ->
            case existing_required_set(existing) do
              {:ok, proposed_changes} ->
                proposed_changes

              {:error, error} ->
                Repo.rollback(error)
            end
        end
      end)
    end
  end

  def apply_all(session_context, operation, proposed_changes) do
    Repo.transaction(fn ->
      case apply_all_locked(session_context, operation, proposed_changes) do
        {:ok, applied} -> {:ok, applied}
        {:error, error} when is_apply_validation_error(error) -> {:error, error}
        {:error, error} -> Repo.rollback(error)
      end
    end)
    |> case do
      {:ok, {:ok, applied}} -> {:ok, applied}
      {:ok, {:error, error}} -> {:error, error}
      {:error, error} -> {:error, error}
    end
  end

  defp read_scoped_changes(session_context, ids, opts \\ []) do
    records =
      ProposedGraphChange
      |> Ash.Query.filter(id in ^ids)
      |> maybe_lock(opts[:lock?])
      |> Ash.read!(actor: session_context)

    by_id = Map.new(records, &{&1.id, &1})

    ids
    |> Enum.map(&Map.fetch(by_id, &1))
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, record}, {:ok, acc} ->
        {:cont, {:ok, [record | acc]}}

      :error, {:ok, _acc} ->
        {:halt, {:error, {:missing_proposed_change, find_missing_id(ids, by_id)}}}
    end)
    |> case do
      {:ok, records} -> {:ok, Enum.reverse(records)}
      error -> error
    end
  end

  defp find_missing_id(ids, by_id), do: Enum.find(ids, &(not Map.has_key?(by_id, &1)))

  defp maybe_lock(query, true), do: Ash.Query.lock(query, :for_update)
  defp maybe_lock(query, _lock?), do: query

  defp read_existing_for_normalized_event(normalized_event_id, opts) do
    ProposedGraphChange
    |> Ash.Query.filter(normalized_event_id == ^normalized_event_id)
    |> maybe_lock(opts[:lock?])
    |> Ash.read!(authorize?: false)
  end

  defp existing_required_set(proposed_changes) do
    types = Enum.map(proposed_changes, & &1.change_type)
    by_type = Map.new(proposed_changes, &{&1.change_type, &1})

    if length(proposed_changes) == length(@required_change_types) and
         Enum.sort(types) == Enum.sort(@required_change_types) and
         map_size(by_type) == length(@required_change_types) do
      {:ok, Enum.map(@required_change_types, &Map.fetch!(by_type, &1))}
    else
      {:error, {:invalid_proposed_change_set, :existing_normalized_event_changes}}
    end
  end

  defp reload_for_apply(session_context, proposed_changes) do
    proposed_changes
    |> Enum.map(& &1.id)
    |> then(&read_scoped_changes(session_context, &1, lock?: true))
  end

  defp validate_apply_operation(session_context, operation) do
    cond do
      not is_map(session_context) or not is_map(operation) ->
        {:error, :forbidden}

      operation.principal_id != session_context.principal_id or
        operation.session_id != session_context.session_id or
        operation.organization_id != session_context.organization_id or
          operation.workspace_id != session_context.workspace_id ->
        {:error, :forbidden}

      operation.action != @apply_operation_action ->
        {:error, {:invalid_apply_operation, operation.id}}

      true ->
        :ok
    end
  end

  defp validate_manual_intake_creation_context(session_context, operation, normalized_event) do
    cond do
      not is_map(session_context) or not is_map(operation) or not is_map(normalized_event) ->
        {:error, :forbidden}

      operation.principal_id != session_context.principal_id or
        operation.session_id != session_context.session_id or
        operation.organization_id != session_context.organization_id or
          operation.workspace_id != session_context.workspace_id ->
        {:error, :forbidden}

      operation.action != @manual_intake_action ->
        {:error, {:invalid_manual_intake_operation, operation.id}}

      normalized_event.organization_id != session_context.organization_id or
          normalized_event.workspace_id != session_context.workspace_id ->
        {:error, {:invalid_proposed_change_scope, normalized_event.id}}

      normalized_event.outcome != "accepted" ->
        {:error,
         {:invalid_proposed_change_set, {:normalized_event_not_accepted, normalized_event.id}}}

      normalized_event.operation_id != operation.id ->
        {:error,
         {:invalid_proposed_change_set,
          {:normalized_event_operation_mismatch, normalized_event.id}}}

      true ->
        :ok
    end
  end

  defp lock_normalized_event!(session_context, operation, normalized_event) do
    @normalized_intake_event
    |> Ash.Query.filter(id == ^normalized_event.id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %{__struct__: @normalized_intake_event} = locked_event} ->
        case validate_manual_intake_creation_context(session_context, operation, locked_event) do
          :ok -> locked_event
          {:error, error} -> Repo.rollback(error)
        end

      {:ok, nil} ->
        Repo.rollback({:missing_normalized_event, normalized_event.id})

      {:error, error} ->
        Repo.rollback({:normalized_event_lock_failed, error})
    end
  end

  defp apply_all_locked(session_context, operation, proposed_changes) do
    with :ok <-
           Authorization.authorize_operation(session_context, operation, :proposed_change_apply,
             organization_id: session_context.organization_id
           ),
         :ok <- validate_apply_operation(session_context, operation),
         {:ok, proposed_changes} <- reload_for_apply(session_context, proposed_changes),
         :ok <- validate_change_set(session_context, proposed_changes),
         :ok <- validate_all(session_context, proposed_changes),
         {:ok, signal_bundle} <-
           find_change(proposed_changes, "create_signal")
           |> apply_signal(session_context, operation),
         {:ok, task_bundle} <-
           find_change(proposed_changes, "create_task")
           |> apply_task(session_context, operation, signal_bundle.signal),
         {:ok, finding_bundle} <-
           find_change(proposed_changes, "create_review_finding")
           |> apply_review_finding(session_context, operation, task_bundle.task),
         {:ok, check_bundle} <-
           find_change(proposed_changes, "create_verification_check")
           |> apply_verification_check(session_context, operation, finding_bundle.review_finding) do
      mark_applied!(proposed_changes)

      {:ok,
       %{
         signal: signal_bundle.signal,
         task: task_bundle.task,
         review_finding: finding_bundle.review_finding,
         verification_check: check_bundle.verification_check
       }}
    end
  end

  defp validate_change_set(session_context, proposed_changes) do
    with :ok <- validate_record_scopes(session_context, proposed_changes),
         :ok <- validate_pending(proposed_changes),
         :ok <- validate_required_types(proposed_changes),
         :ok <- validate_single_normalized_event(proposed_changes),
         :ok <- validate_accepted_normalized_event(session_context, proposed_changes) do
      :ok
    end
  end

  defp validate_record_scopes(session_context, proposed_changes) do
    case Enum.find(proposed_changes, &(not same_scope?(session_context, &1))) do
      nil -> :ok
      change -> {:error, {:invalid_proposed_change_scope, change.id}}
    end
  end

  defp same_scope?(session_context, change) do
    change.organization_id == session_context.organization_id and
      change.workspace_id == session_context.workspace_id
  end

  defp validate_pending(proposed_changes) do
    case Enum.find(proposed_changes, &(&1.status != "pending")) do
      nil -> :ok
      change -> {:error, {:invalid_proposed_change_status, change.id}}
    end
  end

  defp validate_required_types(proposed_changes) do
    types = Enum.map(proposed_changes, & &1.change_type)
    unique_types = Enum.uniq(types)
    duplicate_type = Enum.find(unique_types, &(Enum.count(types, fn type -> type == &1 end) > 1))
    unexpected_type = Enum.find(types, &(&1 not in @required_change_types))
    missing_type = Enum.find(@required_change_types, &(&1 not in types))

    cond do
      duplicate_type ->
        {:error, {:invalid_proposed_change_set, {:duplicate_change_type, duplicate_type}}}

      unexpected_type ->
        {:error, {:invalid_proposed_change_set, {:unexpected_change_type, unexpected_type}}}

      missing_type ->
        {:error, {:invalid_proposed_change_set, {:missing_change_type, missing_type}}}

      true ->
        :ok
    end
  end

  defp validate_single_normalized_event(proposed_changes) do
    normalized_event_ids =
      proposed_changes
      |> Enum.map(& &1.normalized_event_id)
      |> Enum.uniq()
      |> Enum.sort()

    cond do
      nil in normalized_event_ids ->
        {:error, {:invalid_proposed_change_set, :missing_normalized_event_id}}

      match?([_id], normalized_event_ids) ->
        :ok

      true ->
        ids = normalized_event_ids
        {:error, {:invalid_proposed_change_set, {:mixed_normalized_event_ids, ids}}}
    end
  end

  defp validate_accepted_normalized_event(session_context, proposed_changes) do
    normalized_event_id = proposed_changes |> hd() |> Map.fetch!(:normalized_event_id)
    organization_id = session_context.organization_id
    workspace_id = session_context.workspace_id

    @normalized_intake_event
    |> Ash.Query.filter(id == ^normalized_event_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok,
       %{
         organization_id: ^organization_id,
         workspace_id: ^workspace_id,
         outcome: "accepted"
       }} ->
        :ok

      {:ok, %{organization_id: ^organization_id, workspace_id: ^workspace_id}} ->
        {:error,
         {:invalid_proposed_change_set, {:normalized_event_not_accepted, normalized_event_id}}}

      {:ok, _missing_or_cross_scope} ->
        {:error, {:invalid_proposed_change_scope, normalized_event_id}}

      {:error, error} ->
        {:error, {:invalid_proposed_change_set, {:normalized_event_lookup_failed, error}}}
    end
  end

  defp validate_all(session_context, proposed_changes) do
    case Enum.find(proposed_changes, &invalid?/1) do
      nil ->
        :ok

      change ->
        reject!(session_context, change, "title and body are required")
        {:error, {:invalid_proposed_change, change.id}}
    end
  end

  defp invalid?(change) do
    blank?(payload_value(change.payload, "title")) or
      blank?(payload_value(change.payload, "body"))
  end

  defp payload_value(payload, key) do
    Map.get(payload, key) || Map.get(payload, String.to_existing_atom(key))
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: true

  defp reject!(session_context, change, reason) do
    ash_update!(change, :reject, %{validation_errors: [reason]}, session_context)
  end

  defp find_change(changes, change_type) do
    Enum.find(changes, &(&1.change_type == change_type))
  end

  defp apply_signal(change, session_context, operation) do
    WorkGraph.create_signal(session_context, operation, atomize_payload(change.payload))
  end

  defp apply_task(change, session_context, operation, signal) do
    WorkGraph.create_task(session_context, operation, signal, atomize_payload(change.payload))
  end

  defp apply_review_finding(change, session_context, operation, task) do
    WorkGraph.create_review_finding(
      session_context,
      operation,
      task,
      atomize_payload(change.payload)
    )
  end

  defp apply_verification_check(change, session_context, operation, review_finding) do
    WorkGraph.create_verification_check(
      session_context,
      operation,
      review_finding,
      atomize_payload(change.payload)
    )
  end

  defp mark_applied!(changes) do
    now = DateTime.utc_now()

    Enum.each(changes, fn change ->
      ash_update_internal!(change, :mark_applied, %{applied_at: now})
    end)
  end

  defp ash_create!(resource, attrs, session_context) do
    resource
    |> Ash.Changeset.for_create(:create, attrs, actor: session_context)
    |> Ash.create!(return_notifications?: true)
    |> record_without_notifications()
  end

  defp ash_update!(record, action, attrs, session_context) do
    record
    |> Ash.Changeset.for_update(action, attrs)
    |> Ash.update!(actor: session_context, return_notifications?: true)
    |> record_without_notifications()
  end

  defp ash_update_internal!(record, action, attrs) do
    record
    |> Ash.Changeset.for_update(action, attrs)
    |> Ash.update!(authorize?: false, return_notifications?: true)
    |> record_without_notifications()
  end

  defp record_without_notifications({record, _notifications}), do: record
  defp record_without_notifications(record), do: record

  defp first_sentence(body) do
    body
    |> String.split(~r/[.\n]/)
    |> Enum.map(&String.trim/1)
    |> Enum.find(&(not blank?(&1)))
    |> case do
      nil -> ""
      title -> title
    end
  end

  defp change_payload("create_signal", title, body), do: %{title: title, body: body}
  defp change_payload("create_task", title, body), do: %{title: title, body: body}

  defp change_payload("create_review_finding", title, body),
    do: %{title: "Review: " <> title, body: body}

  defp change_payload("create_verification_check", title, _body),
    do: %{title: "Verify: " <> title, body: "Evidence required for: " <> title}

  defp atomize_payload(payload) do
    payload
    |> Map.take(["title", "body", :title, :body])
    |> Map.new(fn {key, value} -> {String.to_existing_atom(to_string(key)), value} end)
  end
end
