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

    Repo.transaction(fn ->
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
    end)
  end

  def apply_all(session_context, operation, proposed_changes) do
    with :ok <-
           Authorization.authorize(session_context, :proposed_change_apply,
             organization_id: session_context.organization_id
           ),
         :ok <- validate_operation_scope(session_context, operation),
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
      mark_applied!(session_context, proposed_changes)

      {:ok,
       %{
         signal: signal_bundle.signal,
         task: task_bundle.task,
         review_finding: finding_bundle.review_finding,
         verification_check: check_bundle.verification_check
       }}
    end
  end

  defp read_scoped_changes(session_context, ids) do
    records =
      ProposedGraphChange
      |> Ash.Query.filter(id in ^ids)
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

  defp reload_for_apply(session_context, proposed_changes) do
    proposed_changes
    |> Enum.map(& &1.id)
    |> then(&read_scoped_changes(session_context, &1))
  end

  defp validate_operation_scope(session_context, operation) do
    if operation.organization_id == session_context.organization_id and
         operation.workspace_id == session_context.workspace_id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp validate_change_set(session_context, proposed_changes) do
    with :ok <- validate_record_scopes(session_context, proposed_changes),
         :ok <- validate_pending(proposed_changes),
         :ok <- validate_required_types(proposed_changes) do
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

      length(types) != length(@required_change_types) ->
        {:error, {:invalid_proposed_change_set, :wrong_count}}

      true ->
        :ok
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

  defp blank?(value), do: is_nil(value) or String.trim(to_string(value)) == ""

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

  defp mark_applied!(session_context, changes) do
    now = DateTime.utc_now()

    Enum.each(changes, fn change ->
      ash_update!(change, :mark_applied, %{applied_at: now}, session_context)
    end)
  end

  defp ash_create!(resource, attrs, session_context) do
    resource
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!(actor: session_context, return_notifications?: true)
    |> record_without_notifications()
  end

  defp ash_update!(record, action, attrs, session_context) do
    record
    |> Ash.Changeset.for_update(action, attrs)
    |> Ash.update!(actor: session_context, return_notifications?: true)
    |> record_without_notifications()
  end

  defp record_without_notifications({record, _notifications}), do: record
  defp record_without_notifications(record), do: record

  defp first_sentence(body) do
    body
    |> String.split(~r/[.\n]/, parts: 2)
    |> hd()
    |> String.trim()
  end

  defp change_payload("create_signal", title, body), do: %{title: title, body: body}
  defp change_payload("create_task", title, body), do: %{title: title, body: body}

  defp change_payload("create_review_finding", title, body),
    do: %{title: "Review: " <> title, body: body}

  defp change_payload("create_verification_check", title, _body),
    do: %{title: "Verify: " <> title, body: "Evidence required for: " <> title}

  defp atomize_payload(payload) do
    Map.new(payload, fn {key, value} -> {String.to_existing_atom(to_string(key)), value} end)
  end
end
