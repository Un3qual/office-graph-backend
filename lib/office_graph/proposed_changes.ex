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

  import Ecto.Query

  def get_many!(ids) do
    records = Repo.all(from change in ProposedGraphChange, where: change.id in ^ids)
    by_id = Map.new(records, &{&1.id, &1})
    Enum.map(ids, &Map.fetch!(by_id, &1))
  end

  def create_for_manual_intake(session_context, operation, normalized_event, attrs) do
    title = first_sentence(attrs.body)

    change_attrs = [
      {"create_signal", %{title: title, body: attrs.body}},
      {"create_task", %{title: title, body: attrs.body}},
      {"create_review_finding", %{title: "Review: " <> title, body: attrs.body}},
      {"create_verification_check",
       %{title: "Verify: " <> title, body: "Evidence required for: " <> title}}
    ]

    Repo.transaction(fn ->
      Enum.map(change_attrs, fn {change_type, payload} ->
        %ProposedGraphChange{}
        |> ProposedGraphChange.changeset(%{
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          operation_id: operation.id,
          normalized_event_id: normalized_event.id,
          status: "pending",
          change_type: change_type,
          payload: payload,
          validation_errors: []
        })
        |> Repo.insert!()
      end)
    end)
  end

  def apply_all(session_context, operation, proposed_changes) do
    with :ok <-
           Authorization.authorize(session_context, :proposed_change_apply,
             organization_id: session_context.organization_id
           ),
         :ok <- validate_all(proposed_changes),
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

  defp validate_all(proposed_changes) do
    case Enum.find(proposed_changes, &invalid?/1) do
      nil ->
        :ok

      change ->
        reject!(change, "title and body are required")
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

  defp reject!(change, reason) do
    change
    |> ProposedGraphChange.changeset(%{status: "rejected", validation_errors: [reason]})
    |> Repo.update!()
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
      change
      |> ProposedGraphChange.changeset(%{status: "applied", applied_at: now})
      |> Repo.update!()
    end)
  end

  defp first_sentence(body) do
    body
    |> String.split(~r/[.\n]/, parts: 2)
    |> hd()
    |> String.trim()
  end

  defp atomize_payload(payload) do
    Map.new(payload, fn {key, value} -> {String.to_existing_atom(to_string(key)), value} end)
  end
end
